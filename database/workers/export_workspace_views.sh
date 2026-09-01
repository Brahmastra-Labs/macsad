#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

[[ "$#" -eq 2 ]] ||
  die 'usage: export_workspace_views.sh WORKSPACE_ID OUTPUT.ndjson'
readonly WORKSPACE_ID="$1"
readonly OUTPUT_PATH="$2"

require_canonical_uuid "${WORKSPACE_ID}" 'workspace ID'
require_new_output "${OUTPUT_PATH}"
require_output_outside_repository "${OUTPUT_PATH}" "${REPOSITORY_ROOT}"
require_command mktemp
require_command mv
require_command psql
require_command realpath
require_postgresql_16 psql
require_server_postgresql_16

readonly OUTPUT_PARENT="$(realpath -- "$(dirname -- "${OUTPUT_PATH}")")"
readonly OUTPUT_NAME="$(basename -- "${OUTPUT_PATH}")"
readonly TEMP_OUTPUT="$(mktemp "${OUTPUT_PARENT}/.${OUTPUT_NAME}.XXXXXXXX")"

cleanup() {
  if [[ -n "${TEMP_OUTPUT:-}" && -f "${TEMP_OUTPUT}" ]]; then
    rm -f -- "${TEMP_OUTPUT}"
  fi
}
trap cleanup EXIT

export PGAPPNAME='macsad-export-workspace-views'
export TZ='UTC'
LC_ALL=C psql \
  --no-psqlrc \
  --quiet \
  --tuples-only \
  --no-align \
  --set=ON_ERROR_STOP=1 \
  --set=VERBOSITY=terse \
  --set=workspace_id="${WORKSPACE_ID}" \
  --file="${REPOSITORY_ROOT}/database/workers/sql/export_workspace_views.sql" \
  >"${TEMP_OUTPUT}"

[[ -s "${TEMP_OUTPUT}" ]] || die 'workspace export produced no records'
mv --no-clobber --no-target-directory -- "${TEMP_OUTPUT}" "${OUTPUT_PATH}"
[[ ! -e "${TEMP_OUTPUT}" && -f "${OUTPUT_PATH}" ]] ||
  die 'export output path appeared before atomic publication'
trap - EXIT
