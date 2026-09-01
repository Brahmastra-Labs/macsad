#!/usr/bin/env bash
set -Eeuo pipefail

export PATH='/usr/bin:/bin'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
readonly ACTIONLINT_VERSION='1.7.12'
readonly ACTIONLINT_ARCHIVE_SHA256='8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8'
readonly ACTIONLINT_ARCHIVE="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
readonly ACTIONLINT_URL="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${ACTIONLINT_ARCHIVE}"
readonly TEMP_BASE="$(realpath -- "${TMPDIR:-/tmp}")"
readonly TEMP_ROOT="$(mktemp -d "${TEMP_BASE}/macsad-actionlint.XXXXXXXX")"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ "${TEMP_ROOT}" != "${TEMP_BASE}/macsad-actionlint."* || ! -d "${TEMP_ROOT}" ]]; then
    printf 'error: refusing to remove unexpected actionlint directory: %s\n' "${TEMP_ROOT}" >&2
    return 1
  fi
  rm -rf -- "${TEMP_ROOT}"
}
trap cleanup EXIT

for command_name in curl mktemp realpath sha256sum tar; do
  command -v "${command_name}" >/dev/null 2>&1 || die "required command not found: ${command_name}"
done

cd -- "${REPOSITORY_ROOT}"
readonly ARCHIVE_PATH="${TEMP_ROOT}/${ACTIONLINT_ARCHIVE}"
/usr/bin/curl \
  --fail \
  --location \
  --proto '=https' \
  --retry 2 \
  --show-error \
  --silent \
  --tlsv1.2 \
  --output "${ARCHIVE_PATH}" \
  "${ACTIONLINT_URL}"
printf '%s  %s\n' "${ACTIONLINT_ARCHIVE_SHA256}" "${ARCHIVE_PATH}" | sha256sum --check --status - ||
  die 'actionlint archive digest did not match the pinned release'
tar -xzf "${ARCHIVE_PATH}" -C "${TEMP_ROOT}" actionlint
[[ -f "${TEMP_ROOT}/actionlint" && ! -L "${TEMP_ROOT}/actionlint" ]] ||
  die 'actionlint archive did not contain the expected regular file'
chmod 0500 "${TEMP_ROOT}/actionlint"

"${TEMP_ROOT}/actionlint" \
  -config-file .github/actionlint.yaml \
  -no-color \
  .github/workflows/*.yml
