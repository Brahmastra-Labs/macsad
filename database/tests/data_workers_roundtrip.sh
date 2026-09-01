#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
readonly WORKER_DIR="${REPOSITORY_ROOT}/database/workers"
readonly SOURCE_DATABASE="${PGDATABASE:-macsad}"
readonly SOURCE_USER="${PGUSER:-postgres}"
readonly ADMIN_USER="${MACSAD_TEST_ADMIN_USER:-${SOURCE_USER}}"
readonly TARGET_DATABASE="macsad_restore_contract_${BASHPID}_${RANDOM}"
readonly SECOND_SEED_DATABASE="macsad_seed_contract_${BASHPID}_${RANDOM}"
readonly TEMP_BASE="$(realpath -- "${TMPDIR:-/tmp}")"
readonly TEMP_ROOT="$(mktemp -d "${TEMP_BASE}/macsad-worker-roundtrip.XXXXXXXX")"
TARGET_CREATED=0
SECOND_SEED_CREATED=0
SOURCE_SENTINEL_CREATED=0
CAS_WATCHER_PID=''

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${CAS_WATCHER_PID:-}" ]] && kill -0 "${CAS_WATCHER_PID}" 2>/dev/null; then
    kill "${CAS_WATCHER_PID}" 2>/dev/null || true
    wait "${CAS_WATCHER_PID}" 2>/dev/null || true
  fi
  if (( SOURCE_SENTINEL_CREATED == 1 )); then
    PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" psql \
      --no-psqlrc --set=ON_ERROR_STOP=1 \
      --command='SET ROLE macsad_owner; DROP SCHEMA macsad_unreviewed_sentinel CASCADE' \
      >/dev/null || true
  fi
  if (( TARGET_CREATED == 1 )); then
    PGUSER="${ADMIN_USER}" PGDATABASE=postgres dropdb --if-exists -- "${TARGET_DATABASE}" || true
  fi
  if (( SECOND_SEED_CREATED == 1 )); then
    PGUSER="${ADMIN_USER}" PGDATABASE=postgres dropdb --if-exists -- \
      "${SECOND_SEED_DATABASE}" || true
  fi
  if [[ "${TEMP_ROOT}" == "${TEMP_BASE}/macsad-worker-roundtrip."* && -d "${TEMP_ROOT}" ]]; then
    rm -rf -- "${TEMP_ROOT}"
  else
    printf 'error: refusing to remove unexpected temporary path: %s\n' "${TEMP_ROOT}" >&2
  fi
}
trap cleanup EXIT

replace_cas_after_staging() {
  local stage_parent="$1"
  local stage_directory_prefix="$2"
  local staged_name="$3"
  local caller_manifest="$4"
  local deadline=$((SECONDS + 15))
  local candidate
  local -a candidates=()
  shopt -s nullglob
  while (( SECONDS < deadline )); do
    candidates=("${stage_parent}/${stage_directory_prefix}"*/"${staged_name}")
    for candidate in "${candidates[@]}"; do
      if [[ -f "${candidate}" ]] &&
          cmp --silent "${TEMP_ROOT}/cas.tsv" "${candidate}"; then
        printf 'format\tmacsad-cas-manifest/1\n' >"${caller_manifest}"
        return 0
      fi
    done
  done
  return 1
}

assert_no_macsad_schemas() {
  local failure_label="$1"
  local schema_count
  schema_count="$(
    PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" psql \
      --no-psqlrc --set=ON_ERROR_STOP=1 --tuples-only --no-align \
      --command="SELECT count(*) FROM pg_namespace WHERE nspname IN ('macsad', 'macsad_meta')"
  )"
  [[ "${schema_count}" == '0' ]] ||
    die "${failure_label} changed the scratch database"
}

create_scratch_database() {
  local database_name="$1"
  PGUSER="${ADMIN_USER}" PGDATABASE=postgres createdb \
    --template=template0 --owner=macsad_owner "${database_name}"
  PGUSER="${ADMIN_USER}" PGDATABASE=postgres psql \
    --no-psqlrc --set=ON_ERROR_STOP=1 \
    --command="REVOKE ALL ON DATABASE ${database_name} FROM PUBLIC" \
    --command="GRANT CONNECT ON DATABASE ${database_name} TO alejandro, macsad_owner, macsad_migrator, macsad_app, macsad_reader" \
    >/dev/null
  PGUSER="${ADMIN_USER}" PGDATABASE="${database_name}" psql \
    --no-psqlrc --set=ON_ERROR_STOP=1 \
    --command='REVOKE ALL ON SCHEMA public FROM PUBLIC' >/dev/null
}

[[ "$#" -eq 0 ]] || die 'usage: data_workers_roundtrip.sh'
[[ "${SOURCE_DATABASE}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] ||
  die 'PGDATABASE must be a database name, not a connection URI'
[[ "${TARGET_DATABASE}" =~ ^macsad_restore_contract_[0-9]+_[0-9]+$ ]] ||
  die 'generated restore database name is unsafe'
[[ "${SECOND_SEED_DATABASE}" =~ ^macsad_seed_contract_[0-9]+_[0-9]+$ ]] ||
  die 'generated independent-seed database name is unsafe'
for command_name in awk bash cmp cp createdb dropdb mktemp psql python3 realpath sed sha256sum; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    die "required command not found: ${command_name}"
done

cd -- "${REPOSITORY_ROOT}"
if [[ "${MACSAD_ROUNDTRIP_SKIP_SEED:-0}" != '1' ]]; then
  PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
    "${WORKER_DIR}/seed_representative_v1.sh"
fi
PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
  "${SCRIPT_DIR}/representative_v1_field_coverage.sh"

PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
  "${WORKER_DIR}/export_workspace_views.sh" \
  10000000-0000-4000-8000-000000000001 "${TEMP_ROOT}/export-one.ndjson"
PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
  "${WORKER_DIR}/export_workspace_views.sh" \
  10000000-0000-4000-8000-000000000001 "${TEMP_ROOT}/export-two.ndjson"
cmp --silent "${TEMP_ROOT}/export-one.ndjson" "${TEMP_ROOT}/export-two.ndjson" ||
  die 'two unchanged workspace exports differ'

python3 - "${TEMP_ROOT}/export-one.ndjson" <<'PY'
import json
import pathlib
import re
import sys

rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(
    encoding="utf-8"
).splitlines()]
assert rows and rows[0]["format"] == "macsad-workspace-views/1"
assert rows[0]["wire_contract"]["numeric"] == "decimal-string-12-fractional-digits"
assert all(isinstance(row, dict) for row in rows)

budget = next(row["row"] for row in rows if row.get("record_type") == "budget_balance")
assert re.fullmatch(r"-?[0-9]+\.[0-9]{12}", budget["spending_limit"])
assert isinstance(budget["version"], str)
assert isinstance(budget["can_reserve"], bool)
assert "updated_at" not in budget

case_board = next(row["row"] for row in rows if row.get("record_type") == "case_board")
assert "updated_at" not in case_board

model_cost = next(
    row["row"] for row in rows if row.get("record_type") == "model_cost_variance"
)
assert "reservation_entry_id" not in model_cost
assert "settlement_entry_id" not in model_cost

audit = next(row["row"] for row in rows if row.get("record_type") == "audit_timeline")
assert isinstance(audit["workspace_sequence_no"], str)
assert re.fullmatch(r"[0-9a-f]{64}", audit["event_hash"])

publication = next(
    row["row"] for row in rows if row.get("record_type") == "publication_catalog"
)
assert re.fullmatch(r"[0-9a-f]{64}", publication["item_digest"])
assert re.fullmatch(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]{15}Z", publication["published_at"]
)
PY

# A second workspace with no view rows must receive only its own package header.
# It is deliberately outside representative-v1 so the canonical fixture remains
# a single-workspace, independently reproducible scenario.
PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet <<'SQL'
SET ROLE macsad_owner;
INSERT INTO macsad.workspace (
  id, github_repository_id, owner_name, repository_name, default_branch,
  installation_id, state, version, created_at, updated_at
) VALUES (
  '10000000-0000-4000-8000-000000000099', 910000099,
  'Brahmastra-Labs', 'macsad-isolation-sentinel', 'main', 920000099,
  'active', 0, '2026-01-15T13:00:00Z', '2026-01-15T13:00:00Z'
);
SQL
PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
  "${WORKER_DIR}/export_workspace_views.sh" \
  10000000-0000-4000-8000-000000000099 "${TEMP_ROOT}/sentinel-export.ndjson"
python3 - "${TEMP_ROOT}/sentinel-export.ndjson" <<'PY'
import json
import pathlib
import sys

rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(
    encoding="utf-8"
).splitlines()]
assert len(rows) == 1
assert rows[0]["workspace_id"] == "10000000-0000-4000-8000-000000000099"
assert "10000000-0000-4000-8000-000000000001" not in pathlib.Path(
    sys.argv[1]
).read_text(encoding="utf-8")
PY

# The package must be byte-identical across two independently migrated and
# seeded databases, despite routine-generated ledger UUIDs and trigger times.
create_scratch_database "${SECOND_SEED_DATABASE}"
SECOND_SEED_CREATED=1
PGUSER="${SOURCE_USER}" PGDATABASE="${SECOND_SEED_DATABASE}" \
  "${REPOSITORY_ROOT}/database/apply_migrations.sh"
PGUSER="${SOURCE_USER}" PGDATABASE="${SECOND_SEED_DATABASE}" \
  "${WORKER_DIR}/seed_representative_v1.sh"
PGUSER="${SOURCE_USER}" PGDATABASE="${SECOND_SEED_DATABASE}" \
  "${SCRIPT_DIR}/representative_v1_field_coverage.sh"
PGUSER="${SOURCE_USER}" PGDATABASE="${SECOND_SEED_DATABASE}" \
  "${WORKER_DIR}/export_workspace_views.sh" \
  10000000-0000-4000-8000-000000000001 \
  "${TEMP_ROOT}/independent-seed-export.ndjson"
cmp --silent "${TEMP_ROOT}/export-one.ndjson" \
  "${TEMP_ROOT}/independent-seed-export.ndjson" ||
  die 'independently seeded workspace exports differ'
PGUSER="${ADMIN_USER}" PGDATABASE=postgres dropdb -- "${SECOND_SEED_DATABASE}"
SECOND_SEED_CREATED=0

printf 'format\tmacsad-cas-manifest/1\n' >"${TEMP_ROOT}/cas.tsv"
PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" psql \
  --no-psqlrc --quiet --set=ON_ERROR_STOP=1 --tuples-only --no-align \
  --field-separator=$'\t' \
  --file="${WORKER_DIR}/sql/referenced_blobs.sql" |
  awk '{ print "blob\t" $0 }' >>"${TEMP_ROOT}/cas.tsv"
WRITE_FENCE_SHA256_LINE="$(
  printf '%s' 'macsad-roundtrip externally enforced write fence v1' | sha256sum
)"
readonly WRITE_FENCE_SHA256_LINE
readonly WRITE_FENCE_SHA256="${WRITE_FENCE_SHA256_LINE%% *}"
[[ "${WRITE_FENCE_SHA256}" =~ ^[0-9a-f]{64}$ ]] ||
  die 'could not calculate the round-trip write-fence evidence digest'

# A whole-database recovery archive must reject code or data in an unreviewed
# source schema, even though normal MaCSad verification ignores that namespace.
PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet <<'SQL'
SET ROLE macsad_owner;
CREATE SCHEMA macsad_unreviewed_sentinel AUTHORIZATION macsad_owner;
CREATE TABLE macsad_unreviewed_sentinel.payload (value text NOT NULL);
CREATE FUNCTION macsad_unreviewed_sentinel.effect()
RETURNS integer LANGUAGE sql AS 'SELECT 1';
SQL
SOURCE_SENTINEL_CREATED=1
if PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
    "${WORKER_DIR}/backup_database.sh" \
    "${TEMP_ROOT}/unreviewed-schema-backup" "${TEMP_ROOT}/cas.tsv" \
    "${WRITE_FENCE_SHA256}" \
    >"${TEMP_ROOT}/unreviewed-schema-backup.log" 2>&1; then
  die 'backup accepted an unreviewed source schema'
fi
[[ ! -e "${TEMP_ROOT}/unreviewed-schema-backup" ]] ||
  die 'unreviewed source schema failure published a backup directory'
PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet \
  --command='SET ROLE macsad_owner; DROP SCHEMA macsad_unreviewed_sentinel CASCADE'
SOURCE_SENTINEL_CREATED=0

sed '$d' "${TEMP_ROOT}/cas.tsv" >"${TEMP_ROOT}/incomplete-cas.tsv"
if PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
    "${WORKER_DIR}/backup_database.sh" \
    "${TEMP_ROOT}/incomplete-backup" "${TEMP_ROOT}/incomplete-cas.tsv" \
    "${WRITE_FENCE_SHA256}" >"${TEMP_ROOT}/incomplete-backup.log" 2>&1; then
  die 'backup accepted an incomplete CAS manifest'
fi
[[ ! -e "${TEMP_ROOT}/incomplete-backup" ]] ||
  die 'failed CAS preflight published a backup directory'

# Once the caller-owned CAS manifest has been copied, replacing that caller
# path must not change the bytes hashed or used by the backup.
cp -- "${TEMP_ROOT}/cas.tsv" "${TEMP_ROOT}/backup-race-cas.tsv"
replace_cas_after_staging \
  "${TEMP_ROOT}" '.cas-race-backup.' '.input-cas-manifest.tsv' \
  "${TEMP_ROOT}/backup-race-cas.tsv" &
CAS_WATCHER_PID=$!
PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
  "${WORKER_DIR}/backup_database.sh" \
  "${TEMP_ROOT}/cas-race-backup" "${TEMP_ROOT}/backup-race-cas.tsv" \
  "${WRITE_FENCE_SHA256}"
wait "${CAS_WATCHER_PID}" || die 'backup did not privately stage its CAS manifest'
CAS_WATCHER_PID=''
CANONICAL_CAS_SHA256_LINE="$(sha256sum "${TEMP_ROOT}/cas.tsv")"
BACKUP_RACE_CAS_SHA256="$(
  awk -F '\t' '$1 == "cas_manifest_sha256" { print $2 }' \
    "${TEMP_ROOT}/cas-race-backup/manifest.tsv"
)"
[[ "${BACKUP_RACE_CAS_SHA256}" == "${CANONICAL_CAS_SHA256_LINE%% *}" ]] ||
  die 'backup manifest did not bind the privately staged CAS bytes'

PGUSER="${SOURCE_USER}" PGDATABASE="${SOURCE_DATABASE}" \
  "${WORKER_DIR}/backup_database.sh" \
  "${TEMP_ROOT}/backup" "${TEMP_ROOT}/cas.tsv" "${WRITE_FENCE_SHA256}"
readonly TRUSTED_MANIFEST_SHA256_LINE="$(sha256sum "${TEMP_ROOT}/backup/manifest.tsv")"
readonly TRUSTED_MANIFEST_SHA256="${TRUSTED_MANIFEST_SHA256_LINE%% *}"

create_scratch_database "${TARGET_DATABASE}"
TARGET_CREATED=1

if PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" \
    "${WORKER_DIR}/restore_database.sh" \
    "${TEMP_ROOT}/backup" "${TEMP_ROOT}/cas.tsv" \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    >"${TEMP_ROOT}/untrusted-restore.log" 2>&1; then
  die 'restore accepted an untrusted manifest digest'
fi
assert_no_macsad_schemas 'untrusted restore'

PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet \
  --command="SET ROLE macsad_owner; CREATE TYPE public.restore_preflight_sentinel AS ENUM ('dirty')"
if PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" \
    "${WORKER_DIR}/restore_database.sh" \
    "${TEMP_ROOT}/backup" "${TEMP_ROOT}/cas.tsv" \
    "${TRUSTED_MANIFEST_SHA256}" >"${TEMP_ROOT}/dirty-type-restore.log" 2>&1; then
  die 'restore accepted a public type in the scratch database'
fi
assert_no_macsad_schemas 'dirty-public-type restore'
PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet \
  --command='SET ROLE macsad_owner; DROP TYPE public.restore_preflight_sentinel'

PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet \
  --command='SET ROLE macsad_owner; GRANT USAGE ON SCHEMA public TO PUBLIC'
if PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" \
    "${WORKER_DIR}/restore_database.sh" \
    "${TEMP_ROOT}/backup" "${TEMP_ROOT}/cas.tsv" \
    "${TRUSTED_MANIFEST_SHA256}" >"${TEMP_ROOT}/dirty-acl-restore.log" 2>&1; then
  die 'restore accepted PUBLIC privileges on the scratch public schema'
fi
assert_no_macsad_schemas 'dirty-public-ACL restore'
PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet \
  --command='SET ROLE macsad_owner; REVOKE ALL ON SCHEMA public FROM PUBLIC'

mkdir -- "${TEMP_ROOT}/restore-stage-parent"
cp -- "${TEMP_ROOT}/cas.tsv" "${TEMP_ROOT}/restore-race-cas.tsv"
replace_cas_after_staging \
  "${TEMP_ROOT}/restore-stage-parent" 'macsad-restore-stage.' \
  'input_cas_manifest.tsv' "${TEMP_ROOT}/restore-race-cas.tsv" &
CAS_WATCHER_PID=$!
TMPDIR="${TEMP_ROOT}/restore-stage-parent" \
  PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" \
  "${WORKER_DIR}/restore_database.sh" \
  "${TEMP_ROOT}/backup" "${TEMP_ROOT}/restore-race-cas.tsv" \
  "${TRUSTED_MANIFEST_SHA256}"
wait "${CAS_WATCHER_PID}" || die 'restore did not privately stage its CAS manifest'
CAS_WATCHER_PID=''
PGUSER="${SOURCE_USER}" PGDATABASE="${TARGET_DATABASE}" \
  "${WORKER_DIR}/export_workspace_views.sh" \
  10000000-0000-4000-8000-000000000001 "${TEMP_ROOT}/restored-export.ndjson"
cmp --silent "${TEMP_ROOT}/export-one.ndjson" "${TEMP_ROOT}/restored-export.ndjson" ||
  die 'restored workspace export differs from the source snapshot'

printf 'MaCSad data-worker PostgreSQL 16 backup/restore round trip passed.\n'
