#!/usr/bin/env bash
set -Eeuo pipefail

export PATH='/usr/bin:/bin'
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
readonly QUALITY_GATE_BUDGET_SECONDS=300
readonly BUNDLE_BUILD_BUDGET_SECONDS=120
readonly BROWSER_SMOKE_BUDGET_SECONDS=120
readonly TIMEOUT_BIN='/usr/bin/timeout'
readonly TEE_BIN='/usr/bin/tee'
harness_home=''

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_exact_environment() {
  [[ "${MACSAD_SOURCE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || die 'MACSAD_SOURCE_SHA is invalid'
  [[ "${MACSAD_SOURCE_REF:-}" == 'refs/heads/main' ]] || die 'only refs/heads/main is admitted'
  [[ "${MACSAD_FOUNDATION_RUN_ID:-}" =~ ^[1-9][0-9]*$ ]] ||
    die 'MACSAD_FOUNDATION_RUN_ID is invalid'
  [[ "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    die 'GITHUB_REPOSITORY is invalid'
  [[ "${GITHUB_RUN_ID:-}" =~ ^[1-9][0-9]*$ ]] || die 'GITHUB_RUN_ID is invalid'
  [[ "${GITHUB_RUN_ATTEMPT:-}" =~ ^[1-9][0-9]*$ ]] || die 'GITHUB_RUN_ATTEMPT is invalid'
  [[ "${LOGOS_WORKSPACE:-}" == '/opt/macsad/toolchains/logicaffeine-private' ]] ||
    die 'LOGOS_WORKSPACE is not the fixed Firebat2 path'
  [[ -n "${MACSAD_EVIDENCE_DIR:-}" && -n "${RUNNER_TEMP:-}" ]] ||
    die 'runner evidence paths are unset'
  local expected_evidence_root
  expected_evidence_root="$(realpath -- "${RUNNER_TEMP}")/macsad-firebat2-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
  [[ "$(realpath -- "${MACSAD_EVIDENCE_DIR}")" == "${expected_evidence_root}" ]] ||
    die 'evidence path escaped the exact runner-temporary location'
  [[ -d "${MACSAD_EVIDENCE_DIR}" && ! -L "${MACSAD_EVIDENCE_DIR}" ]] ||
    die 'evidence root is not a real directory'
  [[ -z "$(find "${MACSAD_EVIDENCE_DIR}" -mindepth 1 -print -quit)" ]] ||
    die 'evidence root was not empty at job start'
}

sanitized() {
  env -i \
    HOME="${harness_home}" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/usr/bin:/bin \
    TMPDIR="${RUNNER_TEMP}" \
    LOGOS_WORKSPACE="${LOGOS_WORKSPACE}" \
    MACSAD_SOURCE_SHA="${MACSAD_SOURCE_SHA}" \
    MACSAD_SOURCE_REF="${MACSAD_SOURCE_REF}" \
    MACSAD_FOUNDATION_RUN_ID="${MACSAD_FOUNDATION_RUN_ID}" \
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY}" \
    GITHUB_RUN_ID="${GITHUB_RUN_ID}" \
    GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT}" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_VALUE_0="${LOGOS_WORKSPACE}" \
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
    "$@"
}

run_timed_stage() {
  local stage="$1"
  local budget_seconds="$2"
  local log_path="$3"
  shift 3
  [[ "${stage}" =~ ^[a-z][a-z0-9-]*$ ]] || die "invalid stage identity: ${stage}"
  [[ "${budget_seconds}" =~ ^[1-9][0-9]*$ ]] || die "invalid stage budget: ${stage}"
  [[ -x "${TIMEOUT_BIN}" && -x "${TEE_BIN}" ]] || die 'fixed timeout/tee tools are unavailable'
  local started_at="${SECONDS}"
  local status
  if sanitized "${TIMEOUT_BIN}" --signal=TERM --kill-after=15s "${budget_seconds}s" "$@" \
    2>&1 | "${TEE_BIN}" "${log_path}"; then
    status='0'
  else
    status="$?"
  fi
  local elapsed_seconds=$((SECONDS - started_at))
  printf '%s\t%s\t%s\n' "${stage}" "${elapsed_seconds}" "${budget_seconds}" \
    >>"${MACSAD_EVIDENCE_DIR}/metadata/stage-timings.tsv"
  if [[ "${status}" == '124' || "${status}" == '137' ]]; then
    die "${stage} exceeded its ${budget_seconds}s execution budget"
  fi
  [[ "${status}" == '0' ]] || die "${stage} failed with status ${status}"
  ((elapsed_seconds <= budget_seconds)) || die "${stage} exceeded its recorded execution budget"
  printf '%s completed in %ss (budget %ss).\n' "${stage}" "${elapsed_seconds}" "${budget_seconds}"
}

main() {
  (($# == 0)) || die 'firebat2-verify.sh accepts no arguments'
  require_exact_environment
  cd -- "${REPOSITORY_ROOT}"
  [[ "$(git rev-parse --verify HEAD)" == "${MACSAD_SOURCE_SHA}" ]] ||
    die 'checkout does not match the admitted SHA'
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] ||
    die 'checkout is dirty before verification'
  SOURCE_DATE_EPOCH="$(git show -s --format=%ct "${MACSAD_SOURCE_SHA}")"
  export SOURCE_DATE_EPOCH
  [[ "${SOURCE_DATE_EPOCH}" =~ ^[1-9][0-9]*$ ]] || die 'commit timestamp is invalid'

  install -d -m 0700 \
    "${MACSAD_EVIDENCE_DIR}/logs" \
    "${MACSAD_EVIDENCE_DIR}/metadata" \
    "${MACSAD_EVIDENCE_DIR}/.home"
  harness_home="${MACSAD_EVIDENCE_DIR}/.home"
  : >"${MACSAD_EVIDENCE_DIR}/metadata/stage-timings.tsv"
  run_timed_stage quality-gate "${QUALITY_GATE_BUDGET_SECONDS}" \
    "${MACSAD_EVIDENCE_DIR}/logs/quality-gate.log" \
    bash scripts/quality-gate.sh
  run_timed_stage bundle-build "${BUNDLE_BUILD_BUDGET_SECONDS}" \
    "${MACSAD_EVIDENCE_DIR}/logs/build.log" \
    bash scripts/ci/build-logos-evidence.sh "${MACSAD_EVIDENCE_DIR}"
  run_timed_stage browser-smoke "${BROWSER_SMOKE_BUDGET_SECONDS}" \
    "${MACSAD_EVIDENCE_DIR}/logs/browser-smoke.log" \
    bash scripts/ci/browser-smoke.sh "${MACSAD_EVIDENCE_DIR}"

  find "${harness_home}" -depth -mindepth 1 -delete
  rmdir -- "${harness_home}"
  harness_home=''

  cat >"${MACSAD_EVIDENCE_DIR}/summary.md" <<EOF
# Firebat2 verification evidence

- Repository: \`${GITHUB_REPOSITORY}\`
- Exact source: \`${MACSAD_SOURCE_SHA}\`
- Source ref: \`${MACSAD_SOURCE_REF}\`
- Admitting Foundation run: \`${MACSAD_FOUNDATION_RUN_ID}\`
- GitHub verification run: \`${GITHUB_RUN_ID}\` attempt \`${GITHUB_RUN_ATTEMPT}\`
- LOGOS workspace policy: fixed, root-owned, read-only, and lock-verified
- Database evidence: owned by credential-free Foundation CI; not promoted by this artifact
- Stage budgets: quality gate ${QUALITY_GATE_BUDGET_SECONDS}s; bundle build ${BUNDLE_BUILD_BUDGET_SECONDS}s; browser smoke ${BROWSER_SMOKE_BUDGET_SECONDS}s

This artifact contains deterministic LOGOS/WASM website bundles, loopback-only
browser DOM and screenshots, bounded logs, and a byte-level evidence manifest.
EOF

  local evidence_digest
  evidence_digest="$(sanitized node scripts/ci/artifact-manifest.mjs write "${MACSAD_EVIDENCE_DIR}")"
  [[ "${evidence_digest}" =~ ^[0-9a-f]{64}$ ]] || die 'manifest writer returned an invalid digest'
  [[ "$(sanitized node scripts/ci/artifact-manifest.mjs verify "${MACSAD_EVIDENCE_DIR}")" == "${evidence_digest}" ]] ||
    die 'manifest verification changed the evidence digest'
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] ||
    die 'verification modified the admitted checkout'
  printf 'Firebat2 evidence tree sha256 %s\n' "${evidence_digest}"
}

main "$@"
