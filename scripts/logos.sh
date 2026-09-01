#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly TOOLCHAIN_LOCK="${REPOSITORY_ROOT}/.macsad/toolchains/logos.lock.toml"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

lock_string() {
  local section="$1"
  local key="$2"

  awk -v wanted_section="${section}" -v wanted_key="${key}" '
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      current = $0
      gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", current)
      next
    }
    current == wanted_section && $0 ~ "^[[:space:]]*" wanted_key "[[:space:]]*=" {
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      sub(/[[:space:]]*(#.*)?$/, "", value)
      if (value !~ /^"[^"]*"$/) exit 2
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      print value
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "${TOOLCHAIN_LOCK}"
}

require_command awk
require_command git
require_command realpath
require_command sha256sum
[[ -r "${TOOLCHAIN_LOCK}" ]] || die "toolchain lock not found: ${TOOLCHAIN_LOCK}"

readonly workspace_environment="$(lock_string runtime workspace_environment)"
readonly binary_relative_path="$(lock_string runtime binary_relative_path)"
readonly expected_version="$(lock_string source version)"
readonly expected_repository="$(lock_string source repository)"
readonly expected_commit="$(lock_string source commit)"
readonly expected_tree="$(lock_string source tree)"
readonly expected_cargo_lock_sha256="$(lock_string source cargo_lock_sha256)"
readonly expected_binary_sha256="$(lock_string runtime observed_binary_sha256)"

[[ "${workspace_environment}" == 'LOGOS_WORKSPACE' ]] ||
  die "unsupported workspace environment in toolchain lock: ${workspace_environment}"
[[ "${binary_relative_path}" =~ ^[A-Za-z0-9._/-]+$ ]] ||
  die 'binary_relative_path contains unsupported characters'
[[ "${binary_relative_path}" != /* && "${binary_relative_path}" != *'..'* ]] ||
  die 'binary_relative_path must remain inside LOGOS_WORKSPACE'
[[ "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  die 'source.version is not an exact semantic version'
[[ "${expected_repository}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  die 'source.repository is not an exact owner/name identity'
[[ "${expected_commit}" =~ ^[0-9a-f]{40}$ ]] ||
  die 'source.commit is not a Git commit OID'
[[ "${expected_tree}" =~ ^[0-9a-f]{40}$ ]] ||
  die 'source.tree is not a Git tree OID'
[[ "${expected_cargo_lock_sha256}" =~ ^[0-9a-f]{64}$ ]] ||
  die 'source.cargo_lock_sha256 is not a SHA-256 digest'
[[ "${expected_binary_sha256}" =~ ^[0-9a-f]{64}$ ]] ||
  die 'runtime.observed_binary_sha256 is not a SHA-256 digest'

[[ -n "${LOGOS_WORKSPACE:-}" ]] ||
  die 'LOGOS_WORKSPACE must point to the exact pinned logicaffeine-private checkout'
readonly logos_workspace="$(realpath -- "${LOGOS_WORKSPACE}")"
readonly largo_binary="$(realpath -- "${logos_workspace}/${binary_relative_path}")"
readonly cargo_lock="${logos_workspace}/Cargo.lock"

[[ "${largo_binary}" == "${logos_workspace}/"* ]] ||
  die 'the resolved largo binary escaped LOGOS_WORKSPACE'
[[ -x "${largo_binary}" ]] || die "pinned largo binary is not executable: ${largo_binary}"
[[ -r "${cargo_lock}" ]] || die "Cargo.lock not found in LOGOS_WORKSPACE"

git -C "${logos_workspace}" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  die 'LOGOS_WORKSPACE is not a Git worktree'
actual_commit="$(git -C "${logos_workspace}" rev-parse --verify HEAD)"
[[ "${actual_commit}" == "${expected_commit}" ]] ||
  die "local LOGOS source commit mismatch: expected ${expected_commit}, received ${actual_commit}"
actual_tree="$(git -C "${logos_workspace}" rev-parse --verify 'HEAD^{tree}')"
[[ "${actual_tree}" == "${expected_tree}" ]] ||
  die "local LOGOS source tree mismatch: expected ${expected_tree}, received ${actual_tree}"
[[ -z "$(git -C "${logos_workspace}" status --porcelain --untracked-files=all)" ]] ||
  die 'local LOGOS source has tracked or untracked modifications'
origin_url="$(git -C "${logos_workspace}" remote get-url origin)"
case "${origin_url}" in
  *"${expected_repository}"|*"${expected_repository}.git") ;;
  *) die "local LOGOS origin does not match ${expected_repository}" ;;
esac

actual_cargo_lock_sha256="$(sha256sum -- "${cargo_lock}")"
actual_cargo_lock_sha256="${actual_cargo_lock_sha256%% *}"
[[ "${actual_cargo_lock_sha256}" == "${expected_cargo_lock_sha256}" ]] ||
  die "LOGOS Cargo.lock digest mismatch; promote a reviewed toolchain lock before continuing"

actual_binary_sha256="$(sha256sum -- "${largo_binary}")"
actual_binary_sha256="${actual_binary_sha256%% *}"
[[ "${actual_binary_sha256}" == "${expected_binary_sha256}" ]] ||
  die "largo binary digest mismatch; rebuild and promote a reviewed toolchain lock before continuing"

actual_version="$("${largo_binary}" --version)"
[[ "${actual_version}" == "largo ${expected_version}" ]] ||
  die "largo version mismatch: expected largo ${expected_version}, received ${actual_version}"

(($# > 0)) || die 'a largo command is required'
exec "${largo_binary}" "$@"
