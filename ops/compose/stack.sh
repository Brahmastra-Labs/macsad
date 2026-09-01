#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
readonly COMPOSE_FILE="${SCRIPT_DIR}/compose.yaml"
readonly DEFAULT_RUNTIME_DIR="${REPOSITORY_ROOT}/.runtime/compose"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage:
  ops/compose/stack.sh configure [--bind-ip IP] [--logos-workspace PATH] [--pgadmin-email EMAIL]
  ops/compose/stack.sh prepare
  ops/compose/stack.sh config
  ops/compose/stack.sh build
  ops/compose/stack.sh up
  ops/compose/stack.sh verify
  ops/compose/stack.sh status
  ops/compose/stack.sh logs [SERVICE]
  ops/compose/stack.sh down

`configure` writes only ignored runtime configuration and generated secrets.
`prepare` admits the exact local LOGOS toolchain and stages minimal build inputs.
`down` preserves PostgreSQL and pgAdmin volumes. There is no destructive volume command.
EOF
}

runtime_dir() {
  if [[ -n "${MACSAD_RUNTIME_DIR:-}" && "${MACSAD_RUNTIME_DIR}" != "${DEFAULT_RUNTIME_DIR}" ]]; then
    die "MACSAD_RUNTIME_DIR is fixed at ${DEFAULT_RUNTIME_DIR}"
  fi
  printf '%s' "${DEFAULT_RUNTIME_DIR}"
}

environment_file() {
  printf '%s/compose.env' "$(runtime_dir)"
}

validate_environment_value() {
  local name="$1"
  local value="$2"
  [[ -n "${value}" && "${value}" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]] ||
    die "${name} contains characters unsafe for the generated environment file"
}

write_secret_if_missing() {
  local path="$1"
  local value
  if [[ -e "${path}" ]]; then
    [[ -f "${path}" && ! -L "${path}" ]] || die "secret path is not a regular file: ${path}"
    value="$(<"${path}")"
    [[ "${value}" =~ ^[0-9a-f]{64}$ ]] || die "existing secret has an invalid shape: ${path}"
    # Compose implements local file-backed secrets as bind mounts and cannot
    # remap their mode/owner. The 0700 parent protects host access; 0444 lets
    # the explicitly mounted file be read by the container's non-root UID.
    chmod 0444 -- "${path}"
    return
  fi
  value="$(openssl rand -hex 32)"
  [[ "${value}" =~ ^[0-9a-f]{64}$ ]] || die 'openssl returned an invalid secret'
  (umask 0333; printf '%s\n' "${value}" >"${path}")
}

configure() {
  require_command git
  require_command openssl
  require_command realpath
  require_command tailscale

  local bind_ip=''
  local logos_workspace=''
  local pgadmin_email="${PGADMIN_DEFAULT_EMAIL:-}"
  while (($#)); do
    case "$1" in
      --bind-ip)
        (($# >= 2)) || die '--bind-ip requires a value'
        bind_ip="$2"
        shift 2
        ;;
      --logos-workspace)
        (($# >= 2)) || die '--logos-workspace requires a value'
        logos_workspace="$2"
        shift 2
        ;;
      --pgadmin-email)
        (($# >= 2)) || die '--pgadmin-email requires a value'
        pgadmin_email="$2"
        shift 2
        ;;
      *) die "unknown configure option: $1" ;;
    esac
  done

  if [[ -z "${bind_ip}" ]]; then
    bind_ip="$(tailscale ip -4 2>/dev/null | sed -n '1p')"
  fi
  [[ "${bind_ip}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] ||
    die 'a tailnet IPv4 address is required; join Firebat to Headscale first'
  tailscale ip -4 | grep -Fqx -- "${bind_ip}" ||
    die "${bind_ip} is not assigned to this Firebat Tailscale client"
  [[ "${bind_ip}" != '0.0.0.0' && "${bind_ip}" != 127.* ]] ||
    die 'the stack must not bind a wildcard or loopback address'

  if [[ -z "${logos_workspace}" ]]; then
    logos_workspace="${LOGOS_WORKSPACE:-/home/alejandro/projects/logicaffeine-private}"
  fi
  logos_workspace="$(realpath -- "${logos_workspace}")"
  [[ -d "${logos_workspace}" ]] || die "LOGOS workspace not found: ${logos_workspace}"
  [[ "${pgadmin_email}" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] ||
    die 'an explicit pgAdmin owner email with a valid shape is required'

  local source_revision
  source_revision="$(git -C "${REPOSITORY_ROOT}" rev-parse --verify HEAD)"
  [[ "${source_revision}" =~ ^[0-9a-f]{40}$ ]] || die 'could not resolve the MaCSad source revision'
  [[ -z "$(git -C "${REPOSITORY_ROOT}" status --porcelain)" ]] ||
    die 'MaCSad must have no tracked or untracked deploy inputs before configuration'

  LOGOS_WORKSPACE="${logos_workspace}" "${REPOSITORY_ROOT}/scripts/logos.sh" --version >/dev/null

  local root_runtime secrets_dir build_dir env_file
  root_runtime="$(runtime_dir)"
  secrets_dir="${root_runtime}/secrets"
  build_dir="${root_runtime}/build/${source_revision}"
  env_file="${root_runtime}/compose.env"
  [[ ! -L "${root_runtime}" && ! -L "${REPOSITORY_ROOT}/.runtime" ]] ||
    die 'the repository runtime directory must not be a symbolic link'
  install -d -m 0700 -- "${root_runtime}" "${secrets_dir}" "${root_runtime}/build"
  write_secret_if_missing "${secrets_dir}/postgres_superuser_password"
  write_secret_if_missing "${secrets_dir}/macsad_deployer_password"
  write_secret_if_missing "${secrets_dir}/macsad_runtime_password"
  write_secret_if_missing "${secrets_dir}/macsad_viewer_password"
  write_secret_if_missing "${secrets_dir}/pgadmin_admin_password"

  validate_environment_value MACSAD_BIND_IP "${bind_ip}"
  validate_environment_value MACSAD_REPOSITORY_ROOT "${REPOSITORY_ROOT}"
  validate_environment_value MACSAD_RUNTIME_DIR "${root_runtime}"
  validate_environment_value MACSAD_BUILD_DIR "${build_dir}"
  validate_environment_value MACSAD_SECRETS_DIR "${secrets_dir}"
  validate_environment_value MACSAD_SOURCE_REVISION "${source_revision}"
  validate_environment_value LOGOS_WORKSPACE "${logos_workspace}"
  validate_environment_value PGADMIN_DEFAULT_EMAIL "${pgadmin_email}"

  (umask 077; cat >"${env_file}" <<EOF
MACSAD_BIND_IP=${bind_ip}
MACSAD_REPOSITORY_ROOT=${REPOSITORY_ROOT}
MACSAD_RUNTIME_DIR=${root_runtime}
MACSAD_BUILD_DIR=${build_dir}
MACSAD_SECRETS_DIR=${secrets_dir}
MACSAD_SOURCE_REVISION=${source_revision}
LOGOS_WORKSPACE=${logos_workspace}
PGADMIN_DEFAULT_EMAIL=${pgadmin_email}
EOF
  )
  printf 'Configured MaCSad for Firebat tailnet address %s.\n' "${bind_ip}"
  printf 'Secrets were generated or retained under %s and were not printed.\n' "${secrets_dir}"
}

load_environment() {
  require_command stat
  local env_file
  env_file="$(environment_file)"
  [[ -f "${env_file}" && ! -L "${env_file}" ]] ||
    die 'runtime environment is missing; run stack.sh configure'
  [[ "$(stat -c '%a' -- "${env_file}")" == '600' ]] ||
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
    validate_environment_value "${key}" "${value}"
    seen["${key}"]=1
    printf -v "${key}" '%s' "${value}"
    export "${key}"
  done <"${env_file}"

  local name
  for name in MACSAD_BIND_IP MACSAD_REPOSITORY_ROOT MACSAD_RUNTIME_DIR \
    MACSAD_BUILD_DIR MACSAD_SECRETS_DIR MACSAD_SOURCE_REVISION \
    LOGOS_WORKSPACE PGADMIN_DEFAULT_EMAIL; do
    [[ -n "${!name:-}" ]] || die "runtime environment omitted ${name}"
  done
  [[ "${MACSAD_REPOSITORY_ROOT}" == "${REPOSITORY_ROOT}" ]] ||
    die 'runtime environment belongs to a different checkout'
  [[ "${MACSAD_RUNTIME_DIR}" == "${DEFAULT_RUNTIME_DIR}" ]] ||
    die 'runtime environment points outside the repository-owned .runtime directory'
  [[ "${MACSAD_SECRETS_DIR}" == "${DEFAULT_RUNTIME_DIR}/secrets" ]] ||
    die 'runtime environment has an unexpected secrets directory'
  case "${MACSAD_BUILD_DIR}" in
    "${DEFAULT_RUNTIME_DIR}"/build/*) ;;
    *) die 'runtime environment has an unexpected build directory' ;;
  esac
  [[ "${MACSAD_SOURCE_REVISION}" =~ ^[0-9a-f]{40}$ ]] || die 'invalid source revision in runtime environment'
  [[ "${MACSAD_BIND_IP}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ &&
     "${MACSAD_BIND_IP}" != '0.0.0.0' && "${MACSAD_BIND_IP}" != 127.* ]] ||
    die 'runtime environment has an unsafe bind address'
  [[ "${MACSAD_BUILD_DIR}" == "${DEFAULT_RUNTIME_DIR}/build/${MACSAD_SOURCE_REVISION}" ]] ||
    die 'runtime environment build directory does not match its exact source revision'
  [[ "$(git -C "${REPOSITORY_ROOT}" rev-parse --verify HEAD)" == "${MACSAD_SOURCE_REVISION}" ]] ||
    die 'runtime environment is stale; rerun stack.sh configure at the current commit'
}

assert_tailnet_binding() {
  require_command tailscale
  tailscale ip -4 | grep -Fqx -- "${MACSAD_BIND_IP}" ||
    die "configured bind address is not assigned to this Firebat Tailscale client: ${MACSAD_BIND_IP}"
}

cleanup_stage() {
  local stage="${1:-}"
  [[ -n "${stage}" ]] || return
  case "${stage}" in
    "${MACSAD_RUNTIME_DIR}"/build/.stage-*) rm -rf -- "${stage}" ;;
    *) die "refusing to remove unexpected staging path: ${stage}" ;;
  esac
}

copy_tracked_tree() {
  local source_relative="$1"
  local destination_root="$2"
  local tracked relative count=0
  while IFS= read -r -d '' tracked; do
    [[ "${tracked}" == "${source_relative}/"* ]] ||
      die "tracked staging path escaped ${source_relative}: ${tracked}"
    relative="${tracked#"${source_relative}/"}"
    install -D -m 0444 -- "${REPOSITORY_ROOT}/${tracked}" "${destination_root}/${relative}"
    count=$((count + 1))
  done < <(git -C "${REPOSITORY_ROOT}" ls-files -z -- "${source_relative}")
  ((count > 0)) || die "no tracked files found under ${source_relative}"
}

prepare() {
  load_environment
  require_command find
  require_command git
  require_command sha256sum

  [[ -z "$(git -C "${REPOSITORY_ROOT}" status --porcelain)" ]] ||
    die 'MaCSad must have no tracked or untracked deploy inputs before staging images'
  LOGOS_WORKSPACE="${LOGOS_WORKSPACE}" "${REPOSITORY_ROOT}/scripts/quality-gate.sh"

  local stage
  stage="${MACSAD_RUNTIME_DIR}/build/.stage-$$"
  [[ ! -e "${stage}" ]] || die "staging path already exists: ${stage}"
  install -d -m 0700 -- \
    "${stage}/admin-bundle" \
    "${stage}/public-bundle" \
    "${stage}/logos-runtime" \
    "${stage}/gateway-source/src" \
    "${stage}/database-source/migrations"
  trap 'cleanup_stage "${stage}"' EXIT

  (
    cd "${REPOSITORY_ROOT}/logos/admin"
    LOGOS_WORKSPACE="${LOGOS_WORKSPACE}" "${REPOSITORY_ROOT}/scripts/logos.sh" \
      emit wasm-dom -o "${stage}/admin-bundle/macsad_admin.wasm"
  )
  (
    cd "${REPOSITORY_ROOT}/logos/public-site"
    LOGOS_WORKSPACE="${LOGOS_WORKSPACE}" "${REPOSITORY_ROOT}/scripts/logos.sh" \
      emit wasm-dom -o "${stage}/public-bundle/macsad_public.wasm"
  )

  local artifact
  for artifact in \
    admin-bundle/macsad_admin.html \
    admin-bundle/macsad_admin.js \
    admin-bundle/macsad_admin.mjs \
    admin-bundle/macsad_admin.wasm \
    public-bundle/macsad_public.html \
    public-bundle/macsad_public.js \
    public-bundle/macsad_public.mjs \
    public-bundle/macsad_public.wasm; do
    [[ -s "${stage}/${artifact}" ]] || die "LOGOS emission omitted ${artifact}"
  done

  install -m 0555 -- "${LOGOS_WORKSPACE}/target/debug/largo" "${stage}/logos-runtime/largo"
  install -m 0444 -- "${REPOSITORY_ROOT}/logos/gateway/Largo.toml" \
    "${stage}/gateway-source/Largo.toml"
  copy_tracked_tree "logos/gateway/src" "${stage}/gateway-source/src"
  install -m 0444 -- "${REPOSITORY_ROOT}/database/apply_migrations.sh" \
    "${stage}/database-source/apply_migrations.sh"
  install -m 0444 -- "${REPOSITORY_ROOT}/database/verify.sql" \
    "${stage}/database-source/verify.sql"
  copy_tracked_tree "database/migrations" \
    "${stage}/database-source/migrations"

  (
    cd "${stage}"
    find . -type f ! -name manifest.sha256 -print0 |
      sort -z |
      xargs -0 sha256sum >manifest.sha256
  )

  [[ "$(git -C "${REPOSITORY_ROOT}" rev-parse --verify HEAD)" == "${MACSAD_SOURCE_REVISION}" ]] ||
    die 'MaCSad changed while build inputs were being staged'

  if [[ -d "${MACSAD_BUILD_DIR}" ]]; then
    diff -qr -- "${stage}" "${MACSAD_BUILD_DIR}" >/dev/null ||
      die 'existing staged inputs differ for the same source revision'
    cleanup_stage "${stage}"
  else
    install -d -m 0700 -- "$(dirname -- "${MACSAD_BUILD_DIR}")"
    mv -- "${stage}" "${MACSAD_BUILD_DIR}"
  fi
  trap - EXIT
  printf 'Staged minimal, digest-recorded image inputs for %s.\n' "${MACSAD_SOURCE_REVISION}"
}

compose() {
  load_environment
  require_command docker
  case "${1:-}" in
    up|start|create|run) assert_tailnet_binding ;;
  esac
  docker compose --project-directory "${SCRIPT_DIR}" --env-file "$(environment_file)" \
    --file "${COMPOSE_FILE}" "$@"
}

config() {
  load_environment
  assert_tailnet_binding
  compose config --quiet
  printf 'Compose configuration is valid.\n'
}

build() {
  [[ -d "$(runtime_dir)/build" ]] || die 'build inputs are missing; run stack.sh prepare'
  compose build --pull
}

up() {
  prepare
  compose config --quiet
  compose build --pull
  compose up --detach --remove-orphans --wait --wait-timeout 240
  verify
}

verify() {
  load_environment
  assert_tailnet_binding
  require_command curl
  compose ps

  local admin_health public_page pgadmin_health viewer_state published
  published="$(compose port logos-gateway 8080)"
  [[ "${published}" == "${MACSAD_BIND_IP}:18080" ]] ||
    die "admin port is not bound only to the reviewed tailnet address: ${published}"
  published="$(compose port logos-gateway 8082)"
  [[ "${published}" == "${MACSAD_BIND_IP}:18082" ]] ||
    die "public preview port is not bound only to the reviewed tailnet address: ${published}"
  published="$(compose port pgadmin 8080)"
  [[ "${published}" == "${MACSAD_BIND_IP}:8978" ]] ||
    die "pgAdmin port is not bound only to the reviewed tailnet address: ${published}"
  if published="$(compose port postgres 5432 2>/dev/null)" && [[ -n "${published}" ]]; then
    die "PostgreSQL must not have a published host port: ${published}"
  fi

  admin_health="$(curl --fail --silent --show-error --max-time 5 \
    "http://${MACSAD_BIND_IP}:18080/api/v1/health")"
  [[ "${admin_health}" == *'MaCSad gateway ready'* ]] || die 'admin health response is not the LOGOS contract'
  public_page="$(curl --fail --silent --show-error --max-time 5 \
    "http://${MACSAD_BIND_IP}:18082/")"
  [[ "${public_page}" == *'macsad_public'* || "${public_page}" == *'MaCSad'* ]] ||
    die 'public LOGOS page did not load'
  pgadmin_health="$(curl --fail --silent --show-error --max-time 5 \
    "http://${MACSAD_BIND_IP}:8978/misc/ping")"
  [[ -n "${pgadmin_health}" ]] || die 'pgAdmin health response was empty'

  viewer_state="$(compose exec --no-TTY postgres bash -ec '
    export PGPASSWORD="$(cat /run/secrets/macsad_viewer_password)"
    psql --no-psqlrc --quiet --tuples-only --no-align \
      --field-separator="|" \
      --host=127.0.0.1 --username=macsad_viewer --dbname=macsad \
      --command="SELECT current_setting('\''default_transaction_read_only'\''), current_version FROM macsad.schema_version_v;"
  ')"
  [[ "${viewer_state}" == 'on|1' ]] ||
    die "viewer login, read-only default, or schema version is wrong: ${viewer_state}"
  if compose exec --no-TTY postgres bash -ec '
    export PGPASSWORD="$(cat /run/secrets/macsad_viewer_password)"
    psql --no-psqlrc --quiet --set=ON_ERROR_STOP=1 \
      --host=127.0.0.1 --username=macsad_viewer --dbname=macsad \
      --command="SET default_transaction_read_only=off; UPDATE macsad.workspace SET id = id WHERE false;"
  ' >/dev/null 2>&1; then
    die 'macsad_viewer unexpectedly performed a write'
  fi
  printf 'Firebat stack verified: exact tailnet ports, no database port, admin, public, pgAdmin, LOGOS gateway, schema v1, and viewer write denial are healthy.\n'
}

main() {
  local command="${1:-}"
  [[ -n "${command}" ]] || {
    usage
    exit 2
  }
  shift
  case "${command}" in
    configure) configure "$@" ;;
    prepare) (($# == 0)) || die 'prepare accepts no arguments'; prepare ;;
    config) (($# == 0)) || die 'config accepts no arguments'; config ;;
    build) (($# == 0)) || die 'build accepts no arguments'; build ;;
    up) (($# == 0)) || die 'up accepts no arguments'; up ;;
    verify) (($# == 0)) || die 'verify accepts no arguments'; verify ;;
    status) (($# == 0)) || die 'status accepts no arguments'; compose ps ;;
    logs)
      (($# <= 1)) || die 'logs accepts at most one service name'
      compose logs --follow --tail=200 "$@"
      ;;
    down) (($# == 0)) || die 'down accepts no arguments'; compose down --remove-orphans ;;
    -h|--help|help) usage ;;
    *) die "unknown command: ${command}" ;;
  esac
}

main "$@"
