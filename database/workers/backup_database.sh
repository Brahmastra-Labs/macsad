#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

[[ "$#" -eq 3 ]] ||
  die 'usage: backup_database.sh OUTPUT_DIRECTORY CAS_MANIFEST.tsv WRITE_FENCE_SHA256'
readonly OUTPUT_PATH="$1"
readonly CAS_MANIFEST_PATH="$2"
readonly WRITE_FENCE_SHA256="$3"

require_command awk
require_command comm
require_command cmp
require_command cp
require_command mktemp
require_command mv
require_command pg_dump
require_command pg_restore
require_command psql
require_command realpath
require_command sha256sum
require_command sort
require_command stat
require_cas_manifest "${CAS_MANIFEST_PATH}"
require_sha256 "${WRITE_FENCE_SHA256}" 'write-fence digest'
require_new_output "${OUTPUT_PATH}"
require_output_outside_repository "${OUTPUT_PATH}" "${REPOSITORY_ROOT}"
require_postgresql_16 pg_dump
require_postgresql_16 pg_restore
require_postgresql_16 psql

readonly OUTPUT_PARENT="$(realpath -- "$(dirname -- "${OUTPUT_PATH}")")"
readonly OUTPUT_NAME="$(basename -- "${OUTPUT_PATH}")"
readonly TEMP_ROOT="$(mktemp -d "${OUTPUT_PARENT}/.${OUTPUT_NAME}.XXXXXXXX")"
chmod 0700 -- "${TEMP_ROOT}"
readonly STAGED_CAS_MANIFEST_PATH="${TEMP_ROOT}/.input-cas-manifest.tsv"
cp --no-dereference -- "${CAS_MANIFEST_PATH}" "${STAGED_CAS_MANIFEST_PATH}"
[[ -f "${STAGED_CAS_MANIFEST_PATH}" && ! -L "${STAGED_CAS_MANIFEST_PATH}" ]] ||
  die 'staged CAS manifest is not a regular non-symlink file'
require_cas_manifest "${STAGED_CAS_MANIFEST_PATH}"
CAS_MANIFEST_SHA256_LINE="$(sha256sum "${STAGED_CAS_MANIFEST_PATH}")" ||
  die 'could not hash the CAS manifest'
readonly CAS_MANIFEST_SHA256_LINE
readonly CAS_MANIFEST_SHA256="${CAS_MANIFEST_SHA256_LINE%% *}"

SNAPSHOT_PROCESS_PID=''
SNAPSHOT_WRITE_FD=''

cleanup() {
  if [[ -n "${SNAPSHOT_PROCESS_PID:-}" ]] && kill -0 "${SNAPSHOT_PROCESS_PID}" 2>/dev/null; then
    if [[ -n "${SNAPSHOT_WRITE_FD:-}" ]]; then
      printf 'release\n' >&"${SNAPSHOT_WRITE_FD}" 2>/dev/null || true
    fi
    wait "${SNAPSHOT_PROCESS_PID}" 2>/dev/null || true
  fi
  if [[ -n "${TEMP_ROOT:-}" && -d "${TEMP_ROOT}" ]]; then
    rm -rf -- "${TEMP_ROOT}"
  fi
}
trap cleanup EXIT

export PGAPPNAME='macsad-backup-database'
VERIFY_OUTPUT="$(psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --set=VERBOSITY=terse \
  --file="${REPOSITORY_ROOT}/database/verify.sql")" ||
  die 'live database verification failed'
readonly VERIFY_OUTPUT
SCHEMA_FINGERPRINT="$(awk -F= '/^schema_fingerprint=/ { print $2 }' <<<"${VERIFY_OUTPUT}")" ||
  die 'could not extract the schema fingerprint'
readonly SCHEMA_FINGERPRINT
require_md5 "${SCHEMA_FINGERPRINT}" 'schema fingerprint'
SCHEMA_VERSION="$(psql \
  --no-psqlrc --quiet --set=ON_ERROR_STOP=1 --tuples-only --no-align \
  --command='SET ROLE macsad_owner; SELECT current_version FROM macsad.schema_version_v')" ||
  die 'could not read the live schema version'
readonly SCHEMA_VERSION
[[ "${SCHEMA_VERSION}" =~ ^[1-9][0-9]*$ ]] ||
  die "invalid live schema version: ${SCHEMA_VERSION}"
SERVER_VERSION_NUM="$(psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --tuples-only --no-align \
  --command='SHOW server_version_num')" ||
  die 'could not read the PostgreSQL server version'
readonly SERVER_VERSION_NUM
[[ "${SERVER_VERSION_NUM}" =~ ^16[0-9]{4}$ ]] ||
  die "database server must be PostgreSQL 16: ${SERVER_VERSION_NUM}"

coproc SNAPSHOT_HOLDER {
  psql \
    --no-psqlrc \
    --quiet \
    --set=ON_ERROR_STOP=1 \
    --set=VERBOSITY=terse \
    --file="${REPOSITORY_ROOT}/database/workers/sql/hold_backup_snapshot.sql"
}
SNAPSHOT_PROCESS_PID="${SNAPSHOT_HOLDER_PID}"
SNAPSHOT_WRITE_FD="${SNAPSHOT_HOLDER[1]}"
if ! IFS= read -r SNAPSHOT_ID <&"${SNAPSHOT_HOLDER[0]}"; then
  die 'could not acquire an exported backup snapshot'
fi
readonly SNAPSHOT_ID
[[ "${SNAPSHOT_ID}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{8}-[0-9A-Fa-f]+$ ]] ||
  die "database returned an invalid exported snapshot identifier: ${SNAPSHOT_ID}"

psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --set=snapshot_id="${SNAPSHOT_ID}" \
  --file="${REPOSITORY_ROOT}/database/workers/sql/backup_source_preflight.sql"

psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --tuples-only \
  --no-align \
  --field-separator=$'\t' \
  --set=snapshot_id="${SNAPSHOT_ID}" \
  --file="${REPOSITORY_ROOT}/database/workers/sql/backup_boundary.sql" \
  >"${TEMP_ROOT}/boundary.before.tsv"

psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --tuples-only \
  --no-align \
  --field-separator=$'\t' \
  --set=snapshot_id="${SNAPSHOT_ID}" \
  --file="${REPOSITORY_ROOT}/database/workers/sql/referenced_blobs.sql" \
  >"${TEMP_ROOT}/referenced_blobs.tsv"
awk -F '\t' '$1 == "blob" { print $2 "\t" $3 "\t" $4 "\t" $5 }' \
  "${STAGED_CAS_MANIFEST_PATH}" | LC_ALL=C sort >"${TEMP_ROOT}/cas_blobs.tsv"
LC_ALL=C comm -23 \
  "${TEMP_ROOT}/referenced_blobs.tsv" "${TEMP_ROOT}/cas_blobs.tsv" \
  >"${TEMP_ROOT}/missing_cas_blobs.tsv"
[[ ! -s "${TEMP_ROOT}/missing_cas_blobs.tsv" ]] ||
  die 'CAS manifest does not cover every referenced database blob'
rm -f -- "${TEMP_ROOT}/cas_blobs.tsv" "${TEMP_ROOT}/missing_cas_blobs.tsv"
rm -f -- "${STAGED_CAS_MANIFEST_PATH}"

pg_dump \
  --format=custom \
  --compress=none \
  --no-owner \
  --role=macsad_owner \
  --schema=macsad \
  --schema=macsad_meta \
  --strict-names \
  --snapshot="${SNAPSHOT_ID}" \
  --file="${TEMP_ROOT}/database.dump"
pg_restore --list "${TEMP_ROOT}/database.dump" >/dev/null

printf 'release\n' >&"${SNAPSHOT_WRITE_FD}" ||
  die 'could not release the exported backup snapshot'
wait "${SNAPSHOT_PROCESS_PID}" || die 'exported backup snapshot holder failed'
SNAPSHOT_PROCESS_PID=''
SNAPSHOT_WRITE_FD=''

psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --tuples-only \
  --no-align \
  --field-separator=$'\t' \
  --file="${REPOSITORY_ROOT}/database/workers/sql/backup_boundary.sql" \
  >"${TEMP_ROOT}/boundary.after.tsv"
cmp --silent "${TEMP_ROOT}/boundary.before.tsv" "${TEMP_ROOT}/boundary.after.tsv" ||
  die 'database boundary changed while the fenced backup was running'
psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --file="${REPOSITORY_ROOT}/database/workers/sql/backup_source_preflight.sql"
mv -- "${TEMP_ROOT}/boundary.before.tsv" "${TEMP_ROOT}/boundary.tsv"
rm -f -- "${TEMP_ROOT}/boundary.after.tsv"

ARCHIVE_SHA256="$(sha256sum "${TEMP_ROOT}/database.dump")" || die 'could not hash database.dump'
BOUNDARY_SHA256="$(sha256sum "${TEMP_ROOT}/boundary.tsv")" || die 'could not hash boundary.tsv'
REFERENCED_BLOBS_SHA256="$(sha256sum "${TEMP_ROOT}/referenced_blobs.tsv")" ||
  die 'could not hash referenced_blobs.tsv'
ARCHIVE_SIZE="$(stat --format='%s' "${TEMP_ROOT}/database.dump")" ||
  die 'could not read database.dump size'
readonly ARCHIVE_SHA256 BOUNDARY_SHA256 REFERENCED_BLOBS_SHA256 ARCHIVE_SIZE
PG_DUMP_VERSION="$(pg_dump --version | awk '{ print $3 }')" ||
  die 'could not read pg_dump version for the backup manifest'
readonly PG_DUMP_VERSION
[[ "${PG_DUMP_VERSION}" =~ ^16([.][0-9]+)*$ ]] ||
  die 'pg_dump returned an invalid PostgreSQL 16 version'
{
  printf 'format\tmacsad-database-backup/1\n'
  printf 'postgresql_major\t16\n'
  printf 'server_version_num\t%s\n' "${SERVER_VERSION_NUM}"
  printf 'pg_dump_version\t%s\n' "${PG_DUMP_VERSION}"
  printf 'schema_version\t%s\n' "${SCHEMA_VERSION}"
  printf 'schema_fingerprint\t%s\n' "${SCHEMA_FINGERPRINT}"
  printf 'archive_sha256\t%s\n' "${ARCHIVE_SHA256%% *}"
  printf 'archive_size\t%s\n' "${ARCHIVE_SIZE}"
  printf 'boundary_sha256\t%s\n' "${BOUNDARY_SHA256%% *}"
  printf 'referenced_blobs_sha256\t%s\n' "${REFERENCED_BLOBS_SHA256%% *}"
  printf 'cas_manifest_sha256\t%s\n' "${CAS_MANIFEST_SHA256}"
  printf 'write_fence_sha256\t%s\n' "${WRITE_FENCE_SHA256}"
  printf 'snapshot_consistency\texported_snapshot\n'
} >"${TEMP_ROOT}/manifest.tsv"

mv --no-clobber --no-target-directory -- "${TEMP_ROOT}" "${OUTPUT_PATH}"
[[ ! -e "${TEMP_ROOT}" && -d "${OUTPUT_PATH}" ]] ||
  die 'backup output path appeared before atomic publication'
trap - EXIT

MANIFEST_SHA256_LINE="$(sha256sum "${OUTPUT_PATH}/manifest.tsv")" ||
  die 'could not hash the published backup manifest'
printf 'Backup candidate published. Trusted manifest SHA-256: %s\n' \
  "${MANIFEST_SHA256_LINE%% *}"
