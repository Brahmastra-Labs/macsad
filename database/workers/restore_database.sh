#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

[[ "$#" -eq 3 ]] ||
  die 'usage: restore_database.sh BACKUP_DIRECTORY CAS_MANIFEST.tsv TRUSTED_MANIFEST_SHA256'
readonly SOURCE_BUNDLE_PATH="$1"
readonly CAS_MANIFEST_PATH="$2"
readonly TRUSTED_MANIFEST_SHA256="$3"

require_command awk
require_command bash
require_command cmp
require_command comm
require_command cp
require_command find
require_command mktemp
require_command pg_restore
require_command psql
require_command sha256sum
require_command sort
require_command stat
require_sha256 "${TRUSTED_MANIFEST_SHA256}" 'trusted manifest digest'
require_cas_manifest "${CAS_MANIFEST_PATH}"

[[ -d "${SOURCE_BUNDLE_PATH}" && ! -L "${SOURCE_BUNDLE_PATH}" ]] ||
  die "backup bundle must be a non-symlink directory: ${SOURCE_BUNDLE_PATH}"
for expected_name in manifest.tsv database.dump boundary.tsv referenced_blobs.tsv; do
  [[ -f "${SOURCE_BUNDLE_PATH}/${expected_name}" && ! -L "${SOURCE_BUNDLE_PATH}/${expected_name}" ]] ||
    die "backup bundle is missing regular non-symlink ${expected_name}"
done
UNEXPECTED_PATH="$(find "${SOURCE_BUNDLE_PATH}" -mindepth 1 -maxdepth 1 \
  ! -name boundary.tsv ! -name database.dump ! -name manifest.tsv \
  ! -name referenced_blobs.tsv -print -quit)" ||
  die 'could not inspect backup bundle contents'
[[ -z "${UNEXPECTED_PATH}" ]] || die 'backup bundle contains an unexpected file'

readonly TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/macsad-restore-stage.XXXXXXXX")"
chmod 0700 -- "${TEMP_ROOT}"
cleanup() {
  if [[ -n "${TEMP_ROOT:-}" && -d "${TEMP_ROOT}" ]]; then
    rm -rf -- "${TEMP_ROOT}"
  fi
}
trap cleanup EXIT

# Copy the four validated inputs into private staging. Every subsequent hash,
# archive read, and restore uses this stable copy rather than caller paths.
for expected_name in manifest.tsv database.dump boundary.tsv referenced_blobs.tsv; do
  cp --no-dereference -- "${SOURCE_BUNDLE_PATH}/${expected_name}" "${TEMP_ROOT}/${expected_name}"
  [[ -f "${TEMP_ROOT}/${expected_name}" && ! -L "${TEMP_ROOT}/${expected_name}" ]] ||
    die "staged backup member is not a regular non-symlink file: ${expected_name}"
done
readonly STAGED_CAS_MANIFEST_PATH="${TEMP_ROOT}/input_cas_manifest.tsv"
cp --no-dereference -- "${CAS_MANIFEST_PATH}" "${STAGED_CAS_MANIFEST_PATH}"
[[ -f "${STAGED_CAS_MANIFEST_PATH}" && ! -L "${STAGED_CAS_MANIFEST_PATH}" ]] ||
  die 'staged CAS manifest is not a regular non-symlink file'
require_cas_manifest "${STAGED_CAS_MANIFEST_PATH}"
readonly MANIFEST_PATH="${TEMP_ROOT}/manifest.tsv"
readonly ARCHIVE_PATH="${TEMP_ROOT}/database.dump"
readonly BOUNDARY_PATH="${TEMP_ROOT}/boundary.tsv"
readonly REFERENCED_BLOBS_PATH="${TEMP_ROOT}/referenced_blobs.tsv"

ACTUAL_MANIFEST_SHA256_LINE="$(sha256sum "${MANIFEST_PATH}")" ||
  die 'could not hash staged manifest.tsv'
[[ "${ACTUAL_MANIFEST_SHA256_LINE%% *}" == "${TRUSTED_MANIFEST_SHA256}" ]] ||
  die 'manifest.tsv does not match the externally trusted digest'
require_backup_manifest "${MANIFEST_PATH}"

readonly FORMAT="$(manifest_value "${MANIFEST_PATH}" format)"
[[ "${FORMAT}" == 'macsad-database-backup/1' ]] ||
  die "unsupported backup format: ${FORMAT}"
readonly POSTGRESQL_MAJOR="$(manifest_value "${MANIFEST_PATH}" postgresql_major)"
[[ "${POSTGRESQL_MAJOR}" == '16' ]] ||
  die "backup requires PostgreSQL major 16: ${POSTGRESQL_MAJOR}"
readonly BACKUP_SERVER_VERSION="$(manifest_value "${MANIFEST_PATH}" server_version_num)"
[[ "${BACKUP_SERVER_VERSION}" =~ ^16[0-9]{4}$ ]] ||
  die 'backup server version is not PostgreSQL 16'
readonly PG_DUMP_VERSION="$(manifest_value "${MANIFEST_PATH}" pg_dump_version)"
[[ "${PG_DUMP_VERSION}" =~ ^16([.][0-9]+)*$ ]] ||
  die 'backup pg_dump version is not PostgreSQL 16'
readonly EXPECTED_SCHEMA_VERSION="$(manifest_value "${MANIFEST_PATH}" schema_version)"
[[ "${EXPECTED_SCHEMA_VERSION}" =~ ^[1-9][0-9]*$ ]] ||
  die 'backup schema version must be a positive integer'
readonly EXPECTED_FINGERPRINT="$(manifest_value "${MANIFEST_PATH}" schema_fingerprint)"
require_md5 "${EXPECTED_FINGERPRINT}" 'backup schema fingerprint'
readonly EXPECTED_ARCHIVE_SHA256="$(manifest_value "${MANIFEST_PATH}" archive_sha256)"
readonly EXPECTED_ARCHIVE_SIZE="$(manifest_value "${MANIFEST_PATH}" archive_size)"
readonly EXPECTED_BOUNDARY_SHA256="$(manifest_value "${MANIFEST_PATH}" boundary_sha256)"
readonly EXPECTED_REFERENCED_BLOBS_SHA256="$(manifest_value "${MANIFEST_PATH}" referenced_blobs_sha256)"
readonly EXPECTED_CAS_MANIFEST_SHA256="$(manifest_value "${MANIFEST_PATH}" cas_manifest_sha256)"
readonly WRITE_FENCE_SHA256="$(manifest_value "${MANIFEST_PATH}" write_fence_sha256)"
readonly SNAPSHOT_CONSISTENCY="$(manifest_value "${MANIFEST_PATH}" snapshot_consistency)"
require_sha256 "${EXPECTED_ARCHIVE_SHA256}" 'archive digest'
[[ "${EXPECTED_ARCHIVE_SIZE}" =~ ^[1-9][0-9]*$ ]] || die 'archive size must be positive'
require_sha256 "${EXPECTED_BOUNDARY_SHA256}" 'boundary digest'
require_sha256 "${EXPECTED_REFERENCED_BLOBS_SHA256}" 'referenced-blobs digest'
require_sha256 "${EXPECTED_CAS_MANIFEST_SHA256}" 'CAS manifest digest'
require_sha256 "${WRITE_FENCE_SHA256}" 'write-fence digest'
[[ "${SNAPSHOT_CONSISTENCY}" == 'exported_snapshot' ]] ||
  die 'backup does not declare exported-snapshot consistency'

ACTUAL_ARCHIVE_SHA256_LINE="$(sha256sum "${ARCHIVE_PATH}")" ||
  die 'could not hash staged database.dump'
ACTUAL_BOUNDARY_SHA256_LINE="$(sha256sum "${BOUNDARY_PATH}")" ||
  die 'could not hash staged boundary.tsv'
ACTUAL_REFERENCED_BLOBS_SHA256_LINE="$(sha256sum "${REFERENCED_BLOBS_PATH}")" ||
  die 'could not hash staged referenced_blobs.tsv'
ACTUAL_CAS_MANIFEST_SHA256_LINE="$(sha256sum "${STAGED_CAS_MANIFEST_PATH}")" ||
  die 'could not hash the supplied CAS manifest'
ACTUAL_ARCHIVE_SIZE="$(stat --format='%s' "${ARCHIVE_PATH}")" ||
  die 'could not read staged database.dump size'
[[ "${ACTUAL_ARCHIVE_SHA256_LINE%% *}" == "${EXPECTED_ARCHIVE_SHA256}" ]] ||
  die 'database.dump digest does not match manifest'
[[ "${ACTUAL_ARCHIVE_SIZE}" == "${EXPECTED_ARCHIVE_SIZE}" ]] ||
  die 'database.dump size does not match manifest'
[[ "${ACTUAL_BOUNDARY_SHA256_LINE%% *}" == "${EXPECTED_BOUNDARY_SHA256}" ]] ||
  die 'boundary.tsv digest does not match manifest'
[[ "${ACTUAL_REFERENCED_BLOBS_SHA256_LINE%% *}" == "${EXPECTED_REFERENCED_BLOBS_SHA256}" ]] ||
  die 'referenced_blobs.tsv digest does not match manifest'
[[ "${ACTUAL_CAS_MANIFEST_SHA256_LINE%% *}" == "${EXPECTED_CAS_MANIFEST_SHA256}" ]] ||
  die 'supplied CAS manifest digest does not match backup manifest'

awk -F '\t' '$1 == "blob" { print $2 "\t" $3 "\t" $4 "\t" $5 }' \
  "${STAGED_CAS_MANIFEST_PATH}" | LC_ALL=C sort >"${TEMP_ROOT}/cas_blobs.tsv"
LC_ALL=C comm -23 \
  "${REFERENCED_BLOBS_PATH}" "${TEMP_ROOT}/cas_blobs.tsv" \
  >"${TEMP_ROOT}/missing_cas_blobs.tsv"
[[ ! -s "${TEMP_ROOT}/missing_cas_blobs.tsv" ]] ||
  die 'supplied CAS manifest does not cover every bundled database blob reference'

require_postgresql_16 pg_restore
require_postgresql_16 psql
pg_restore --list "${ARCHIVE_PATH}" >/dev/null

export PGAPPNAME='macsad-restore-database'
TARGET_DATABASE="$(psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --tuples-only --no-align \
  --command='SELECT current_database()')" ||
  die 'could not read restore target database name'
readonly TARGET_DATABASE
[[ "${TARGET_DATABASE}" =~ ^macsad_restore_[a-z0-9_]+$ ]] ||
  die 'restore target database name must start with macsad_restore_'
TARGET_SERVER_VERSION="$(psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 --tuples-only --no-align \
  --command='SHOW server_version_num')" ||
  die 'could not read restore target server version'
[[ "${TARGET_SERVER_VERSION}" =~ ^16[0-9]{4}$ ]] ||
  die "restore target server must be PostgreSQL 16: ${TARGET_SERVER_VERSION}"
psql \
  --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file="${REPOSITORY_ROOT}/database/workers/sql/restore_target_preflight.sql"

pg_restore \
  --single-transaction \
  --exit-on-error \
  --no-owner \
  --role=macsad_owner \
  --dbname="${TARGET_DATABASE}" \
  "${ARCHIVE_PATH}"

psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --set=minimum_schema_version="${EXPECTED_SCHEMA_VERSION}" \
  --set=maximum_schema_version="${EXPECTED_SCHEMA_VERSION}" \
  --set=expected_schema_fingerprint="${EXPECTED_FINGERPRINT}" \
  --file="${REPOSITORY_ROOT}/database/verify.sql"
bash "${REPOSITORY_ROOT}/database/apply_migrations.sh"
psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --file="${REPOSITORY_ROOT}/database/workers/sql/verify_restored_data.sql"

psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --tuples-only \
  --no-align \
  --field-separator=$'\t' \
  --file="${REPOSITORY_ROOT}/database/workers/sql/backup_boundary.sql" \
  >"${TEMP_ROOT}/restored_boundary.tsv"
cmp --silent "${BOUNDARY_PATH}" "${TEMP_ROOT}/restored_boundary.tsv" ||
  die 'restored data boundary differs from the backup manifest'

psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --tuples-only \
  --no-align \
  --field-separator=$'\t' \
  --file="${REPOSITORY_ROOT}/database/workers/sql/referenced_blobs.sql" \
  >"${TEMP_ROOT}/restored_referenced_blobs.tsv"
cmp --silent "${REFERENCED_BLOBS_PATH}" "${TEMP_ROOT}/restored_referenced_blobs.tsv" ||
  die 'restored database blob references differ from the backup snapshot'
LC_ALL=C comm -23 \
  "${TEMP_ROOT}/restored_referenced_blobs.tsv" "${TEMP_ROOT}/cas_blobs.tsv" \
  >"${TEMP_ROOT}/restored_missing_cas_blobs.tsv"
[[ ! -s "${TEMP_ROOT}/restored_missing_cas_blobs.tsv" ]] ||
  die 'supplied CAS manifest does not cover every restored database blob reference'

printf 'Restore, data boundary, audit chain, and CAS closure verified.\n'
