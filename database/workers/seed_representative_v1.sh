#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

[[ "$#" -eq 0 ]] || die 'usage: seed_representative_v1.sh'
require_command psql
require_postgresql_16 psql
require_server_postgresql_16

export PGAPPNAME='macsad-seed-representative-v1'
psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --set=VERBOSITY=terse \
  --single-transaction \
  --file="${REPOSITORY_ROOT}/database/fixtures/representative_v1.sql"
