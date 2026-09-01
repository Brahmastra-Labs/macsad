#!/usr/bin/env bash
set -Eeuo pipefail

readonly secret_path='/run/secrets/macsad_deployer_password'
readonly passfile='/tmp/pgpass'
readonly database_dir='/opt/macsad/database'

[[ -f "${secret_path}" ]] || {
  printf 'error: migration credential is unavailable\n' >&2
  exit 1
}
IFS= read -r password <"${secret_path}"
[[ "${password}" =~ ^[0-9a-f]{64}$ ]] || {
  printf 'error: migration credential has an invalid shape\n' >&2
  exit 1
}
[[ "${PGHOST:-}" =~ ^[a-z][a-z0-9-]*$ ]] || {
  printf 'error: PGHOST must be a Compose service name\n' >&2
  exit 1
}
[[ "${PGPORT:-}" == '5432' ]] || {
  printf 'error: PGPORT must be 5432\n' >&2
  exit 1
}
[[ "${PGDATABASE:-}" == 'macsad' && "${PGUSER:-}" == 'macsad_deployer' ]] || {
  printf 'error: migration identity or database is not the reviewed contract\n' >&2
  exit 1
}

umask 077
printf '%s:%s:%s:%s:%s\n' \
  "${PGHOST}" "${PGPORT}" "${PGDATABASE}" "${PGUSER}" "${password}" >"${passfile}"
unset password
export PGPASSFILE="${passfile}"
export PGAPPNAME='macsad-compose-migrator'

bash "${database_dir}/apply_migrations.sh"
