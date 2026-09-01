#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly MIGRATIONS_DIR="${SCRIPT_DIR}/migrations"
readonly VERIFY_SQL="${SCRIPT_DIR}/verify.sql"
readonly DATABASE_NAME="${PGDATABASE:-macsad}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_command psql
require_command sha256sum

[[ "${DATABASE_NAME}" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] ||
  die 'PGDATABASE must be a database name, not a connection URI'
[[ -d "${MIGRATIONS_DIR}" ]] || die "migration directory not found: ${MIGRATIONS_DIR}"
[[ -r "${VERIFY_SQL}" ]] || die "verification script not found: ${VERIFY_SQL}"

export PGDATABASE="${DATABASE_NAME}"
export PGHOST="${PGHOST:-/var/run/postgresql}"
export PGAPPNAME="macsad-migration-runner"

readonly -a PSQL=(
  psql
  --no-psqlrc
  --set=ON_ERROR_STOP=1
  --dbname="${DATABASE_NAME}"
)

sql_scalar() {
  "${PSQL[@]}" --quiet --tuples-only --no-align \
    --command "SET ROLE macsad_owner; $1"
}

lint_transaction_contract() {
  local file="$1"
  awk '
    {
      line = toupper($0)
      if (line ~ /^[[:space:]]*BEGIN[[:space:]]*;[[:space:]]*(--.*)?$/) begins++
      if (line ~ /^[[:space:]]*COMMIT[[:space:]]*;[[:space:]]*(--.*)?$/) commits++
      if (line ~ /PG_ADVISORY_XACT_LOCK[[:space:]]*\(/) locks++
      if (line ~ /MACSAD:SCHEMA-MIGRATION/) lockkeys++
      if (line ~ /MACSAD_META\.SCHEMA_MIGRATION/) ledgers++
      if (line ~ /MIGRATION_SHA256/) checksums++
    }
    END {
      if (begins != 1 || commits != 1 || locks < 1 || lockkeys < 1 || ledgers < 1 || checksums < 1) exit 1
    }
  ' "${file}" || die "migration violates transaction/lock/ledger contract: ${file}"
}

server_version_num="$(sql_scalar "SELECT current_setting('server_version_num')::integer;")"
[[ "${server_version_num}" =~ ^[0-9]+$ ]] || die 'could not read PostgreSQL server version'
(( server_version_num >= 160000 && server_version_num < 170000 )) ||
  die "PostgreSQL 16 is required; server_version_num=${server_version_num}"

shopt -s nullglob
migration_files=("${MIGRATIONS_DIR}"/[0-9][0-9][0-9][0-9]_*.sql)
shopt -u nullglob
((${#migration_files[@]} > 0)) || die "no migration files found in ${MIGRATIONS_DIR}"

declare -a local_names=()
declare -a local_paths=()
declare -a local_checksums=()
expected_version=1

for file in "${migration_files[@]}"; do
  base="$(basename -- "${file}")"
  [[ "${base}" =~ ^([0-9]{4})_([a-z0-9_]+)\.sql$ ]] ||
    die "invalid migration filename: ${base}"
  version=$((10#${BASH_REMATCH[1]}))
  (( version == expected_version )) ||
    die "migration versions must be contiguous; expected ${expected_version}, found ${version}"

  name="${base%.sql}"
  checksum="$(sha256sum -- "${file}")"
  checksum="${checksum%% *}"
  [[ "${checksum}" =~ ^[0-9a-f]{64}$ ]] || die "invalid SHA-256 for ${base}"
  lint_transaction_contract "${file}"

  local_names[version]="${name}"
  local_paths[version]="${file}"
  local_checksums[version]="${checksum}"
  ((expected_version += 1))
done

readonly latest_local_version=$((expected_version - 1))
ledger_exists="$(sql_scalar "SELECT to_regclass('macsad_meta.schema_migration') IS NOT NULL;")"
[[ "${ledger_exists}" == 't' || "${ledger_exists}" == 'f' ]] || die 'could not inspect migration ledger'

applied_version=0
if [[ "${ledger_exists}" == 't' ]]; then
  ledger_output="$(
    "${PSQL[@]}" --quiet --tuples-only --no-align --field-separator='|' --command \
      "SET ROLE macsad_owner;
       SELECT version, name, encode(script_sha256, 'hex')
       FROM macsad_meta.schema_migration
       ORDER BY version;"
  )"
  ledger_rows=()
  if [[ -n "${ledger_output}" ]]; then
    mapfile -t ledger_rows <<<"${ledger_output}"
  fi

  expected_applied=1
  for row in "${ledger_rows[@]}"; do
    IFS='|' read -r version name checksum <<<"${row}"
    [[ "${version}" =~ ^[0-9]+$ ]] || die 'migration ledger contains a non-numeric version'
    (( version == expected_applied )) ||
      die "migration ledger is not contiguous; expected ${expected_applied}, found ${version}"
    (( version <= latest_local_version )) ||
      die "database schema version ${version} is newer than this checkout (${latest_local_version})"
    [[ "${name}" == "${local_names[version]}" ]] ||
      die "migration name drift at version ${version}: ledger=${name}, file=${local_names[version]}"
    [[ "${checksum}" == "${local_checksums[version]}" ]] ||
      die "migration checksum drift at version ${version} (${name})"
    applied_version="${version}"
    ((expected_applied += 1))
  done
else
  stray_schema="$(sql_scalar "SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname IN ('macsad', 'macsad_meta'));")"
  [[ "${stray_schema}" == 'f' ]] ||
    die 'MaCSad schemas exist without a migration ledger; refusing to infer history'
fi

for ((version = applied_version + 1; version <= latest_local_version; version++)); do
  file="${local_paths[version]}"
  name="${local_names[version]}"
  checksum="${local_checksums[version]}"

  current_checksum="$(sha256sum -- "${file}")"
  current_checksum="${current_checksum%% *}"
  [[ "${current_checksum}" == "${checksum}" ]] ||
    die "migration changed during preflight: ${name}"

  if (( version > 1 )); then
    current_database_version="$(sql_scalar 'SELECT COALESCE(max(version), 0) FROM macsad_meta.schema_migration;')"
    (( current_database_version == version - 1 )) ||
      die "database changed during migration run; expected version $((version - 1)), found ${current_database_version}"
  fi

  printf 'Applying %s (sha256 %s)\n' "${name}" "${checksum}"
  "${PSQL[@]}" --set=migration_sha256="${checksum}" --file="${file}"

  ledger_match="$(sql_scalar \
    "SELECT EXISTS (
       SELECT 1
       FROM macsad_meta.schema_migration
       WHERE version = ${version}
         AND name = '${name}'
         AND script_sha256 = decode('${checksum}', 'hex')
     );")"
  [[ "${ledger_match}" == 't' ]] ||
    die "migration returned success without the exact ledger row: ${name}"
done

"${PSQL[@]}" --file="${VERIFY_SQL}"
printf 'MaCSad schema is current at version %d and verification passed.\n' "${latest_local_version}"
