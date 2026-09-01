#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
readonly CHECKER_SQL="${SCRIPT_DIR}/representative_v1_field_coverage.sql"
readonly DATABASE_NAME="${PGDATABASE:-macsad}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ "$#" -eq 0 ]] || die 'usage: representative_v1_field_coverage.sh'
command -v psql >/dev/null 2>&1 || die 'required command not found: psql'
[[ "${DATABASE_NAME}" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] ||
  die 'PGDATABASE must be a database name, not a connection URI'
[[ -r "${CHECKER_SQL}" ]] || die "coverage checker is not readable: ${CHECKER_SQL}"
[[ -r "${REPOSITORY_ROOT}/database/fixtures/representative_v1_system_fields.tsv" ]] ||
  die 'representative-v1 system-field manifest is not readable'

server_version_num="$(
  psql --no-psqlrc --quiet --tuples-only --no-align --dbname="${DATABASE_NAME}" \
    --command="SELECT current_setting('server_version_num')::integer;"
)"
[[ "${server_version_num}" =~ ^[0-9]+$ ]] ||
  die 'could not read PostgreSQL server version'
(( server_version_num >= 160000 && server_version_num < 170000 )) ||
  die "PostgreSQL 16 is required; server_version_num=${server_version_num}"

cd -- "${REPOSITORY_ROOT}"
export PGAPPNAME='macsad-representative-v1-field-coverage'
psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --set=VERBOSITY=terse \
  --dbname="${DATABASE_NAME}" \
  --file="${CHECKER_SQL}"
