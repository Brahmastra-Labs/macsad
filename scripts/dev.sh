#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly STACK="${REPOSITORY_ROOT}/ops/compose/stack.sh"
readonly RUNTIME_ENV="${REPOSITORY_ROOT}/.runtime/compose/compose.env"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
MaCSad developer and Firebat operator harness

Usage: scripts/dev.sh COMMAND [ARGS]

Development:
  connect-logos      Connect an explicit private development directory.
                     --workspace PATH [--binary target/debug/largo]
  logos-status       Inspect its source observations and executable identity.
  logos [ARGS]       Run the connected development executable.
  test-lean-worker   Run mechanical and explicit Lean receipt policy controls.
  doctor             Inspect prerequisites and exact local toolchain state.
  test               Run the complete LOGOS/host/Compose gate; DB when configured.
  test-foundation    Run credential-free source, host, and Compose guardrails.
  lint-logos         Run the standalone LOGOS size, duplication, and debt gate.
  audit-actions MODE Read back GitHub Actions policy against an explicit state:
                     --expect-firebat2=disabled|disabled-ready|enabled-ready.

Firebat stack:
  configure          Create ignored tailnet/runtime config and generated secrets.
  prepare            Verify local LOGOS and stage minimal deterministic image inputs.
  compose-config     Resolve and validate the complete Compose model.
  build              Build all local images from staged inputs.
  up                 Prepare, build, start, wait, and verify the stack.
  verify             Recheck containers, HTTP surfaces, and schema compatibility.
  status             Show Compose service and health state.
  logs [SERVICE]     Follow bounded recent service logs.
  down               Stop containers while preserving database/viewer volumes.
  db-shell           Open a read-only psql session as macsad_viewer.

Start with GETTING_STARTED.md. Production-changing and destructive volume
operations are deliberately absent from this harness.
EOF
}

load_runtime_environment_if_present() {
  [[ -e "${RUNTIME_ENV}" ]] || return 0
  [[ -f "${RUNTIME_ENV}" && ! -L "${RUNTIME_ENV}" ]] ||
    die 'runtime environment is not a regular file'
  [[ "$(stat -c '%a' -- "${RUNTIME_ENV}")" == '600' ]] ||
    die 'runtime environment must have mode 0600'

  local line key value
  declare -A seen=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ^([A-Z][A-Z0-9_]*)=(.+)$ ]] ||
      die 'runtime environment contains a malformed line'
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    case "${key}" in
      MACSAD_BIND_IP|MACSAD_REPOSITORY_ROOT|MACSAD_RUNTIME_DIR|MACSAD_BUILD_DIR|\
      MACSAD_SECRETS_DIR|MACSAD_SOURCE_REVISION|LOGOS_WORKSPACE|PGADMIN_DEFAULT_EMAIL) ;;
      *) die "runtime environment contains an unexpected key: ${key}" ;;
    esac
    [[ -z "${seen[${key}]:-}" ]] || die "runtime environment repeats ${key}"
    [[ "${value}" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]] ||
      die "runtime environment value for ${key} is unsafe"
    seen["${key}"]=1
    printf -v "${key}" '%s' "${value}"
    export "${key}"
  done <"${RUNTIME_ENV}"

  local required
  for required in MACSAD_BIND_IP MACSAD_REPOSITORY_ROOT MACSAD_RUNTIME_DIR \
    MACSAD_BUILD_DIR MACSAD_SECRETS_DIR MACSAD_SOURCE_REVISION \
    LOGOS_WORKSPACE PGADMIN_DEFAULT_EMAIL; do
    [[ -n "${seen[${required}]:-}" ]] || die "runtime environment omitted ${required}"
  done
  [[ "${MACSAD_REPOSITORY_ROOT}" == "${REPOSITORY_ROOT}" ]] ||
    die 'runtime environment belongs to a different checkout'
  [[ "${MACSAD_RUNTIME_DIR}" == "${REPOSITORY_ROOT}/.runtime/compose" ]] ||
    die 'runtime environment has an unexpected runtime root'
  [[ "${MACSAD_SECRETS_DIR}" == "${MACSAD_RUNTIME_DIR}/secrets" ]] ||
    die 'runtime environment has an unexpected secrets root'
  [[ "${MACSAD_SOURCE_REVISION}" =~ ^[0-9a-f]{40}$ ]] ||
    die 'runtime environment has an invalid source revision'
  [[ "${MACSAD_BUILD_DIR}" == "${MACSAD_RUNTIME_DIR}/build/${MACSAD_SOURCE_REVISION}" ]] ||
    die 'runtime environment has an unexpected build root'
  [[ "$(git -C "${REPOSITORY_ROOT}" rev-parse --verify HEAD)" == "${MACSAD_SOURCE_REVISION}" ]] ||
    die 'runtime environment is stale for the current source revision'
  [[ "${MACSAD_BIND_IP}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ &&
     "${MACSAD_BIND_IP}" != '0.0.0.0' && "${MACSAD_BIND_IP}" != 127.* ]] ||
    die 'runtime environment has an unsafe bind address'
}

doctor() {
  local failures=0
  printf 'Repository: %s\n' "${REPOSITORY_ROOT}"
  printf 'Revision:   %s\n' "$(git -C "${REPOSITORY_ROOT}" rev-parse --short=12 HEAD)"
  if [[ -n "$(git -C "${REPOSITORY_ROOT}" status --porcelain)" ]]; then
    printf 'Tracked tree: DIRTY\n'
    failures=$((failures + 1))
  else
    printf 'Tracked tree: clean\n'
  fi

  local command
  for command in bash git node python3 openssl make; do
    if command -v "${command}" >/dev/null 2>&1; then
      printf '%-12s %s\n' "${command}:" "$(command -v "${command}")"
    else
      printf '%-12s MISSING\n' "${command}:"
      failures=$((failures + 1))
    fi
  done

  load_runtime_environment_if_present
  if [[ -n "${LOGOS_WORKSPACE:-}" ]]; then
    if "${REPOSITORY_ROOT}/scripts/logos.sh" --version; then
      printf 'LOGOS lock:  verified\n'
    else
      printf 'LOGOS lock:  FAILED\n'
      failures=$((failures + 1))
    fi
  else
    printf 'LOGOS lock:  not configured (set LOGOS_WORKSPACE or run configure)\n'
    failures=$((failures + 1))
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    printf 'Docker:      %s\n' "$(docker version --format '{{.Server.Version}}')"
    printf 'Compose:     %s\n' "$(docker compose version --short)"
  else
    printf 'Docker:      unavailable; run the Firebat host bootstrap\n'
    failures=$((failures + 1))
  fi

  if command -v tailscale >/dev/null 2>&1 && [[ -n "$(tailscale ip -4 2>/dev/null)" ]]; then
    printf 'Tailnet IP:  %s\n' "$(tailscale ip -4 | paste -sd, -)"
  else
    printf 'Tailnet:     unavailable or not enrolled\n'
    failures=$((failures + 1))
  fi

  ((failures == 0)) || die "doctor found ${failures} blocking prerequisite(s)"
  printf 'Doctor passed.\n'
}

test_foundation() {
  cd -- "${REPOSITORY_ROOT}"
  bash -n \
    scripts/dev.sh \
    scripts/logos.sh \
    scripts/quality-gate.sh \
    database/apply_migrations.sh \
    ops/compose/stack.sh \
    ops/compose/run-migrations.sh \
    ops/compose/postgres/010-bootstrap-macsad.sh \
    ops/firebat/bootstrap_container_host.sh \
    ops/firebat2/verify_verifier_host.sh \
    scripts/ci/browser-smoke.sh \
    scripts/ci/build-logos-evidence.sh \
    scripts/ci/firebat2-verify.sh
  node --check scripts/guardrails.mjs
  node --check scripts/logos-project.mjs
  node --check scripts/logos-source-lint.mjs
  node --check scripts/verify-logos-tests.mjs
  node --check scripts/compose-guardrails.mjs
  node --check scripts/ci/artifact-manifest.mjs
  node --check scripts/ci/audit-github-actions-settings.mjs
  node --check scripts/ci/browser-probe.mjs
  node --check scripts/ci/verify-firebat2-contract.mjs
  python3 -c 'compile(open("scripts/ci/static_server.py", encoding="utf-8").read(), "scripts/ci/static_server.py", "exec")'
  node --test \
    tests/scripts/logos-project.test.mjs \
    tests/scripts/logos-source-lint.test.mjs \
    tests/scripts/compose-guardrails.test.mjs \
    tests/scripts/artifact-manifest.test.mjs \
    tests/scripts/browser-probe.test.mjs \
    tests/scripts/firebat2-contract.test.mjs
  node scripts/guardrails.mjs
  node scripts/logos-project.mjs audit
  node scripts/logos-source-lint.mjs
  node scripts/compose-guardrails.mjs
  node scripts/ci/verify-firebat2-contract.mjs
  python3 -m unittest discover --start-directory host_adapters/tests --pattern 'test_*.py'
}

test_all() {
  load_runtime_environment_if_present
  [[ -n "${LOGOS_WORKSPACE:-}" ]] || die 'LOGOS_WORKSPACE is required; run configure or export it'
  exec "${REPOSITORY_ROOT}/scripts/quality-gate.sh"
}

db_shell() {
  load_runtime_environment_if_present
  "${STACK}" status >/dev/null
  exec docker compose \
    --project-directory "${REPOSITORY_ROOT}/ops/compose" \
    --env-file "${RUNTIME_ENV}" \
    --file "${REPOSITORY_ROOT}/ops/compose/compose.yaml" \
    exec postgres bash -ec '
      export PGPASSWORD="$(cat /run/secrets/macsad_viewer_password)"
      exec psql --no-psqlrc --host=127.0.0.1 --username=macsad_viewer --dbname=macsad
    '
}

main() {
  local command="${1:-}"
  [[ -n "${command}" ]] || {
    usage
    exit 2
  }
  shift
  case "${command}" in
    connect-logos) exec python3 "${REPOSITORY_ROOT}/host_adapters/logos_directory.py" connect "$@" ;;
    logos-status) (($# == 0)) || die 'logos-status accepts no arguments'; exec python3 "${REPOSITORY_ROOT}/host_adapters/logos_directory.py" inspect ;;
    logos) exec python3 "${REPOSITORY_ROOT}/host_adapters/logos_directory.py" run -- "$@" ;;
    test-lean-worker) (($# == 0)) || die 'test-lean-worker accepts no arguments'; cd -- "${REPOSITORY_ROOT}"; exec python3 -m unittest host_adapters.tests.test_logos_directory host_adapters.tests.test_lean_result host_adapters.tests.lean_worker_contract -v ;;
    doctor) (($# == 0)) || die 'doctor accepts no arguments'; doctor ;;
    test) (($# == 0)) || die 'test accepts no arguments'; test_all ;;
    test-foundation) (($# == 0)) || die 'test-foundation accepts no arguments'; test_foundation ;;
    lint-logos) (($# == 0)) || die 'lint-logos accepts no arguments'; exec node "${REPOSITORY_ROOT}/scripts/logos-source-lint.mjs" ;;
    audit-actions) exec node "${REPOSITORY_ROOT}/scripts/ci/audit-github-actions-settings.mjs" "$@" ;;
    configure) exec "${STACK}" configure "$@" ;;
    prepare) (($# == 0)) || die 'prepare accepts no arguments'; exec "${STACK}" prepare ;;
    compose-config) (($# == 0)) || die 'compose-config accepts no arguments'; exec "${STACK}" config ;;
    build) (($# == 0)) || die 'build accepts no arguments'; exec "${STACK}" build ;;
    up) (($# == 0)) || die 'up accepts no arguments'; exec "${STACK}" up ;;
    verify) (($# == 0)) || die 'verify accepts no arguments'; exec "${STACK}" verify ;;
    status) (($# == 0)) || die 'status accepts no arguments'; exec "${STACK}" status ;;
    logs) (($# <= 1)) || die 'logs accepts at most one service'; exec "${STACK}" logs "$@" ;;
    down) (($# == 0)) || die 'down accepts no arguments'; exec "${STACK}" down ;;
    db-shell) (($# == 0)) || die 'db-shell accepts no arguments'; db_shell ;;
    help|-h|--help) usage ;;
    *) die "unknown command: ${command}" ;;
  esac
}

main "$@"
