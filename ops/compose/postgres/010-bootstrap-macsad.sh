#!/usr/bin/env bash
set -Eeuo pipefail

read_secret() {
  local name="$1"
  local path="/run/secrets/${name}"
  local value

  [[ -f "${path}" ]] || {
    printf 'error: required bootstrap secret is missing: %s\n' "${name}" >&2
    exit 1
  }
  IFS= read -r value <"${path}"
  [[ "${value}" =~ ^[0-9a-f]{64}$ ]] || {
    printf 'error: bootstrap secret %s must be 64 lowercase hexadecimal characters\n' "${name}" >&2
    exit 1
  }
  printf '%s' "${value}"
}

readonly deployer_password="$(read_secret macsad_deployer_password)"
readonly runtime_password="$(read_secret macsad_runtime_password)"
readonly viewer_password="$(read_secret macsad_viewer_password)"

[[ "${POSTGRES_USER:-}" == 'postgres' ]] || {
  printf 'error: bootstrap requires the fixed postgres initialization superuser\n' >&2
  exit 1
}

readonly bootstrap_sql='/opt/macsad/bootstrap/010-bootstrap-macsad.sql'
[[ -r "${bootstrap_sql}" ]] || {
  printf 'error: bootstrap SQL is unavailable\n' >&2
  exit 1
}

# Passwords travel only through psql stdin. They never appear in argv, the
# container environment, the image, PostgreSQL logs, or a generated SQL file.
psql --no-psqlrc --set=ON_ERROR_STOP=1 --username="${POSTGRES_USER}" --dbname=postgres <<SQL
\set deployer_password ${deployer_password}
\set runtime_password ${runtime_password}
\set viewer_password ${viewer_password}
\i ${bootstrap_sql}
SQL
