#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
readonly WORKER_DIR="${REPOSITORY_ROOT}/database/workers"
readonly TEMP_BASE="$(realpath -- "${TMPDIR:-/tmp}")"
readonly TEMP_ROOT="$(mktemp -d "${TEMP_BASE}/macsad-data-worker-contract.XXXXXXXX")"

cleanup() {
  if [[ "${TEMP_ROOT}" != "${TEMP_BASE}/macsad-data-worker-contract."* || ! -d "${TEMP_ROOT}" ]]; then
    printf 'error: refusing to remove unexpected temporary path: %s\n' "${TEMP_ROOT}" >&2
    return 1
  fi
  rm -rf -- "${TEMP_ROOT}"
}
trap cleanup EXIT

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  local expected_fragment="$1"
  shift
  local output
  if output="$({ "$@"; } 2>&1)"; then
    fail "command unexpectedly succeeded: $*"
  fi
  [[ "${output}" == *"${expected_fragment}"* ]] ||
    fail "failure did not contain '${expected_fragment}': ${output}"
}

readonly -a WORKERS=(
  seed_representative_v1.sh
  export_workspace_views.sh
  backup_database.sh
  restore_database.sh
)

for worker in "${WORKERS[@]}"; do
  path="${WORKER_DIR}/${worker}"
  [[ -x "${path}" ]] || fail "worker is missing or not executable: ${path}"
  bash -n "${path}"
done

mkdir -- "${TEMP_ROOT}/fake-bin"
cat >"${TEMP_ROOT}/fake-bin/psql" <<'FAKE'
#!/usr/bin/env bash
printf 'psql invoked\n' >>"${MACSAD_FAKE_EFFECT_LOG}"
exit 97
FAKE
cat >"${TEMP_ROOT}/fake-bin/pg_dump" <<'FAKE'
#!/usr/bin/env bash
printf 'pg_dump invoked\n' >>"${MACSAD_FAKE_EFFECT_LOG}"
exit 97
FAKE
cat >"${TEMP_ROOT}/fake-bin/pg_restore" <<'FAKE'
#!/usr/bin/env bash
printf 'pg_restore invoked\n' >>"${MACSAD_FAKE_EFFECT_LOG}"
exit 97
FAKE
chmod +x "${TEMP_ROOT}/fake-bin/psql" "${TEMP_ROOT}/fake-bin/pg_dump" \
  "${TEMP_ROOT}/fake-bin/pg_restore"

export PATH="${TEMP_ROOT}/fake-bin:${PATH}"
export MACSAD_FAKE_EFFECT_LOG="${TEMP_ROOT}/effects.log"
: >"${MACSAD_FAKE_EFFECT_LOG}"

expect_failure 'workspace ID must be a canonical lowercase UUID' \
  "${WORKER_DIR}/export_workspace_views.sh" \
  'NOT-A-UUID' "${TEMP_ROOT}/export.ndjson"
[[ ! -e "${TEMP_ROOT}/export.ndjson" ]] || fail 'invalid export created output'
[[ ! -s "${MACSAD_FAKE_EFFECT_LOG}" ]] || fail 'invalid export invoked PostgreSQL'

expect_failure 'CAS manifest must be a regular non-symlink file' \
  "${WORKER_DIR}/backup_database.sh" \
  "${TEMP_ROOT}/backup" "${TEMP_ROOT}/missing-cas.tsv" "$(printf '2%.0s' {1..64})"
[[ ! -e "${TEMP_ROOT}/backup" ]] || fail 'invalid backup created output'
[[ ! -s "${MACSAD_FAKE_EFFECT_LOG}" ]] || fail 'invalid backup invoked PostgreSQL'

printf 'format\tmacsad-cas-manifest/1\nblob\t%s\t1\ttest-cas\t%s\n' \
  "$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..32})" >"${TEMP_ROOT}/cas.tsv"
expect_failure 'output must be outside the Git repository' \
  "${WORKER_DIR}/backup_database.sh" \
  "${REPOSITORY_ROOT}/contract-backup-output" "${TEMP_ROOT}/cas.tsv" \
  "$(printf '2%.0s' {1..64})"
[[ ! -s "${MACSAD_FAKE_EFFECT_LOG}" ]] || fail 'repository-local backup invoked PostgreSQL'

expect_failure 'write-fence digest must be 64 lowercase hexadecimal characters' \
  "${WORKER_DIR}/backup_database.sh" \
  "${TEMP_ROOT}/backup" "${TEMP_ROOT}/cas.tsv" invalid
[[ ! -e "${TEMP_ROOT}/backup" ]] || fail 'invalid backup created output'
[[ ! -s "${MACSAD_FAKE_EFFECT_LOG}" ]] || fail 'invalid backup invoked PostgreSQL'

mkdir -- "${TEMP_ROOT}/not-a-bundle"
expect_failure 'missing regular non-symlink manifest.tsv' \
  "${WORKER_DIR}/restore_database.sh" "${TEMP_ROOT}/not-a-bundle" \
  "${TEMP_ROOT}/cas.tsv" "$(printf 'c%.0s' {1..64})"
[[ ! -s "${MACSAD_FAKE_EFFECT_LOG}" ]] || fail 'invalid restore invoked PostgreSQL'

expect_failure 'trusted manifest digest must be 64 lowercase hexadecimal characters' \
  "${WORKER_DIR}/restore_database.sh" "${TEMP_ROOT}/not-a-bundle" \
  "${TEMP_ROOT}/cas.tsv" invalid
[[ ! -s "${MACSAD_FAKE_EFFECT_LOG}" ]] || fail 'untrusted restore invoked PostgreSQL'

mkdir -- "${TEMP_ROOT}/digest-mismatch-bundle"
printf 'not the trusted manifest\n' >"${TEMP_ROOT}/digest-mismatch-bundle/manifest.tsv"
printf 'archive\n' >"${TEMP_ROOT}/digest-mismatch-bundle/database.dump"
printf 'boundary\n' >"${TEMP_ROOT}/digest-mismatch-bundle/boundary.tsv"
printf 'references\n' >"${TEMP_ROOT}/digest-mismatch-bundle/referenced_blobs.tsv"
expect_failure 'manifest.tsv does not match the externally trusted digest' \
  "${WORKER_DIR}/restore_database.sh" "${TEMP_ROOT}/digest-mismatch-bundle" \
  "${TEMP_ROOT}/cas.tsv" "$(printf 'd%.0s' {1..64})"
[[ ! -s "${MACSAD_FAKE_EFFECT_LOG}" ]] || fail 'digest-mismatch restore invoked PostgreSQL'

printf 'MaCSad data-worker validation-before-effects contracts passed.\n'
