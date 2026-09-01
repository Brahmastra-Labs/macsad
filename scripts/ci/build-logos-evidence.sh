#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
temporary_root=''

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

cleanup() {
  [[ -n "${temporary_root}" ]] || return 0
  local temporary_base
  temporary_base="$(realpath -- "${TMPDIR:-/tmp}")"
  [[ "${temporary_root}" == "${temporary_base}/macsad-upload-compare."* ]] ||
    die "refusing to clean unexpected comparison path: ${temporary_root}"
  [[ -d "${temporary_root}" && ! -L "${temporary_root}" ]] ||
    die "comparison path is no longer a real directory: ${temporary_root}"
  find "${temporary_root}" -depth -mindepth 1 -delete
  rmdir -- "${temporary_root}"
  temporary_root=''
}
trap cleanup EXIT

hash_tree() {
  local directory="$1"
  (
    cd -- "${directory}"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
  )
}

main() {
  (($# == 1)) || die 'usage: scripts/ci/build-logos-evidence.sh EVIDENCE_ROOT'
  require_command find
  require_command mkdir
  require_command mktemp
  require_command node
  require_command realpath
  require_command sha256sum
  require_command sort
  require_command wc
  require_command xargs

  local evidence_root="$1"
  [[ -d "${evidence_root}" && ! -L "${evidence_root}" ]] ||
    die 'evidence root must be an existing real directory'
  evidence_root="$(realpath -- "${evidence_root}")"
  local bundles_root="${evidence_root}/bundles"
  [[ ! -e "${bundles_root}" ]] || die 'bundles evidence directory already exists'
  mkdir -m 0700 -- "${bundles_root}"
  local temporary_base
  temporary_base="$(realpath -- "${TMPDIR:-/tmp}")"
  temporary_root="$(mktemp -d "${temporary_base}/macsad-upload-compare.XXXXXXXX")"

  local project_name project_directory bundle_stem output_directory comparison_directory
  while IFS=$'\t' read -r project_name project_directory bundle_stem; do
    [[ "${project_name}" =~ ^[a-z][a-z0-9-]*$ ]]
    [[ "${project_directory}" =~ ^logos/[a-z][a-z0-9-]*$ ]]
    [[ "${bundle_stem}" =~ ^[a-z][a-z0-9_]*$ ]]
    output_directory="${bundles_root}/${project_name}"
    comparison_directory="${temporary_root}/${project_name}"
    mkdir -m 0700 -- "${output_directory}"
    mkdir -m 0700 -- "${comparison_directory}"
    (
      cd -- "${REPOSITORY_ROOT}/${project_directory}"
      "${REPOSITORY_ROOT}/scripts/logos.sh" emit wasm-dom \
        --output "${output_directory}/${bundle_stem}.wasm" \
        --color never
      "${REPOSITORY_ROOT}/scripts/logos.sh" emit wasm-dom \
        --output "${comparison_directory}/${bundle_stem}.wasm" \
        --color never
    )
    local extension
    for extension in html js mjs wasm; do
      [[ -s "${output_directory}/${bundle_stem}.${extension}" ]] ||
        die "${project_name} did not emit ${bundle_stem}.${extension}"
    done
    [[ "$(find "${output_directory}" -maxdepth 1 -type f | wc -l)" == '4' ]] ||
      die "${project_name} emitted an unexpected file set"
    [[ "$(find "${comparison_directory}" -maxdepth 1 -type f | wc -l)" == '4' ]] ||
      die "${project_name} comparison emission has an unexpected file set"
    [[ "$(hash_tree "${output_directory}")" == "$(hash_tree "${comparison_directory}")" ]] ||
      die "${project_name} uploaded emission differs byte-for-byte from its independent emission"
    printf '%s uploaded bundle matched its independent byte-for-byte emission.\n' "${project_name}"
  done < <(node "${SCRIPT_DIR}/artifact-manifest.mjs" projects)

  [[ "$(find "${bundles_root}" -mindepth 1 -maxdepth 1 -type d | wc -l)" == '2' ]] ||
    die 'browser contract must emit exactly two website bundles'
  cleanup
  printf 'Two exact website bundles passed independent emission comparison.\n'
}

main "$@"
