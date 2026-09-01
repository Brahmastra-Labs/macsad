#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
readonly PYTHON_BIN='/usr/bin/python3'
readonly CURL_BIN='/usr/bin/curl'
readonly NODE_BIN='/usr/bin/node'
readonly CHROMIUM_BIN='/usr/bin/chromium'

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup_pid=''
cleanup() {
  if [[ -n "${cleanup_pid}" ]] && kill -0 "${cleanup_pid}" >/dev/null 2>&1; then
    local kill_status wait_status
    if kill "${cleanup_pid}" >/dev/null 2>&1; then
      kill_status='0'
    else
      kill_status="$?"
    fi
    if wait "${cleanup_pid}" >/dev/null 2>&1; then
      wait_status='0'
    else
      wait_status="$?"
    fi
    [[ "${kill_status}" == '0' ]] || die "could not terminate static server ${cleanup_pid}"
    [[ "${wait_status}" == '0' || "${wait_status}" == '143' ]] ||
      die "static server exited unexpectedly with status ${wait_status}"
  fi
}
trap cleanup EXIT

require_root_owned_binary() {
  local path="$1"
  [[ -x "${path}" ]] || die "required fixed binary is unavailable: ${path}"
  local canonical
  canonical="$(realpath -- "${path}")"
  [[ -f "${canonical}" && "$(stat -c '%u' -- "${canonical}")" == '0' ]] ||
    die "fixed binary target is not a root-owned file: ${path}"
  [[ ! -w "${canonical}" ]] || die "fixed binary target is writable by the runner: ${path}"
}

main() {
  (($# == 1)) || die 'usage: scripts/ci/browser-smoke.sh EVIDENCE_ROOT'
  require_root_owned_binary "${PYTHON_BIN}"
  require_root_owned_binary "${CURL_BIN}"
  require_root_owned_binary "${NODE_BIN}"
  require_root_owned_binary "${CHROMIUM_BIN}"

  local evidence_root="$1"
  [[ -d "${evidence_root}" && ! -L "${evidence_root}" ]] ||
    die 'evidence root must be an existing real directory'
  evidence_root="$(realpath -- "${evidence_root}")"
  local browser_root="${evidence_root}/browser"
  [[ ! -e "${browser_root}" ]] || die 'browser evidence directory already exists'
  mkdir -m 0700 -- "${browser_root}"

  local project_name project_directory bundle_stem bundle_directory output_directory
  while IFS=$'\t' read -r project_name project_directory bundle_stem; do
    bundle_directory="${evidence_root}/bundles/${project_name}"
    output_directory="${browser_root}/${project_name}"
    [[ -s "${bundle_directory}/${bundle_stem}.html" ]] ||
      die "browser entry is missing for ${project_name}"
    mkdir -m 0700 -- "${output_directory}"
    local port_file="${output_directory}/port"
    local profile_directory="${output_directory}/profile"
    mkdir -m 0700 -- "${profile_directory}"

    "${PYTHON_BIN}" "${SCRIPT_DIR}/static_server.py" \
      --directory "${bundle_directory}" \
      --port-file "${port_file}" \
      2>"${output_directory}/server.log" &
    cleanup_pid="$!"
    local attempt
    for attempt in {1..100}; do
      [[ -s "${port_file}" ]] && break
      kill -0 "${cleanup_pid}" >/dev/null 2>&1 || die "static server exited for ${project_name}"
      sleep 0.05
    done
    [[ -s "${port_file}" ]] || die "static server did not publish a port for ${project_name}"
    local port
    port="$(<"${port_file}")"
    [[ "${port}" =~ ^[1-9][0-9]{3,4}$ && "${port}" -le 65535 ]] ||
      die "static server returned an unsafe port for ${project_name}"
    local url="http://127.0.0.1:${port}/${bundle_stem}.html"

    "${CURL_BIN}" --fail --silent --show-error \
      --connect-timeout 2 --max-time 10 \
      --dump-header "${output_directory}/response-headers.txt" \
      --output /dev/null \
      "${url}"
    "${NODE_BIN}" "${SCRIPT_DIR}/browser-probe.mjs" \
      --project "${project_name}" \
      --url "${url}" \
      --output-directory "${output_directory}" \
      --profile-directory "${profile_directory}" \
      --chromium "${CHROMIUM_BIN}"

    cleanup
    cleanup_pid=''
    rm -f -- "${port_file}"
    find "${profile_directory}" -depth -mindepth 1 -delete
    rmdir -- "${profile_directory}"
    [[ -s "${output_directory}/dom.html" && -s "${output_directory}/screenshot.png" ]] ||
      die "browser produced incomplete evidence for ${project_name}"
    printf '%s CDP interaction, state assertion, screenshot, and runtime boundary passed.\n' \
      "${project_name}"
  done < <("${NODE_BIN}" "${SCRIPT_DIR}/artifact-manifest.mjs" projects)
  printf 'Both website browser contracts passed without a skipped interaction.\n'
}

main "$@"
