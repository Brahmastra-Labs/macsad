#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (( EUID == 0 )); then
  readonly -a SUDO=()
  as_postgres() { runuser -u postgres -- "$@"; }
else
  command -v sudo >/dev/null 2>&1 || die 'sudo is required for the Firebat bootstrap'
  printf 'Firebat bootstrap requires one human-entered sudo authentication. No password is stored.\n'
  sudo -v
  readonly -a SUDO=(sudo)
  as_postgres() { sudo -u postgres -- "$@"; }
fi

[[ -r /etc/os-release ]] || die 'cannot identify the operating system'
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == 'ubuntu' && "${VERSION_ID:-}" == '24.04' ]] ||
  die "this bootstrap targets Ubuntu 24.04; found ${PRETTY_NAME:-unknown}"

"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  postgresql-16 postgresql-client-16

if ! pg_lsclusters --no-header | awk '$1 == "16" && $2 == "main" { found=1 } END { exit !found }'; then
  "${SUDO[@]}" pg_createcluster 16 main --start
fi

readonly START_CONF='/etc/postgresql/16/main/start.conf'
start_policy="$("${SUDO[@]}" cat "${START_CONF}" | tr -d '[:space:]')"
if [[ "${start_policy}" != 'auto' ]]; then
  printf 'auto\n' | "${SUDO[@]}" tee "${START_CONF}" >/dev/null
fi

readonly DROP_IN_DIR='/etc/systemd/system/postgresql@16-main.service.d'
"${SUDO[@]}" install -d -o root -g root -m 0755 "${DROP_IN_DIR}"
printf '%s\n' \
  '[Service]' \
  'Restart=on-failure' \
  'RestartSec=5s' |
  "${SUDO[@]}" tee "${DROP_IN_DIR}/macsad-restart.conf" >/dev/null

"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable --now postgresql.service postgresql@16-main.service

as_postgres psql --no-psqlrc --set=ON_ERROR_STOP=1 --dbname=postgres <<'SQL'
ALTER SYSTEM SET listen_addresses = 'localhost';
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SQL

hba_file="$(as_postgres psql --no-psqlrc --tuples-only --no-align --dbname=postgres --command='SHOW hba_file;')"
[[ "${hba_file}" == '/etc/postgresql/16/main/pg_hba.conf' ]] ||
  die "unexpected PostgreSQL 16 HBA path: ${hba_file}"

managed_begin_count="$("${SUDO[@]}" awk '$0 == "# BEGIN MACSAD FIREBAT PEER AUTH" { count++ } END { print count+0 }' "${hba_file}")"
managed_end_count="$("${SUDO[@]}" awk '$0 == "# END MACSAD FIREBAT PEER AUTH" { count++ } END { print count+0 }' "${hba_file}")"
if [[ "${managed_begin_count}:${managed_end_count}" != '0:0'
   && "${managed_begin_count}:${managed_end_count}" != '1:1' ]]; then
  die 'the managed pg_hba.conf block is malformed; refusing to rewrite the file'
fi
if [[ "${managed_begin_count}:${managed_end_count}" == '1:1' ]] \
   && ! "${SUDO[@]}" awk '
     $0 == "# BEGIN MACSAD FIREBAT PEER AUTH" { begin_line=NR }
     $0 == "# END MACSAD FIREBAT PEER AUTH" { end_line=NR }
     END { exit !(begin_line > 0 && end_line > begin_line) }
   ' "${hba_file}"; then
  die 'the managed pg_hba.conf markers are out of order; refusing to rewrite the file'
fi

readonly HBA_BACKUP='/etc/postgresql/16/main/pg_hba.conf.before-macsad'
if ! "${SUDO[@]}" test -e "${HBA_BACKUP}"; then
  "${SUDO[@]}" install -o postgres -g postgres -m 0640 "${hba_file}" "${HBA_BACKUP}"
fi

hba_tmp="$(mktemp)"
cleanup() { rm -f -- "${hba_tmp}"; }
trap cleanup EXIT
{
  printf '%s\n' \
    '# BEGIN MACSAD FIREBAT PEER AUTH' \
    '# Local administrator only; service roles receive separate deployment-managed auth.' \
    'local   macsad   alejandro   peer' \
    'local   macsad   postgres    peer' \
    'local   postgres postgres    peer' \
    '# END MACSAD FIREBAT PEER AUTH'
  "${SUDO[@]}" awk '
    $0 == "# BEGIN MACSAD FIREBAT PEER AUTH" { managed=1; next }
    $0 == "# END MACSAD FIREBAT PEER AUTH" { managed=0; next }
    !managed { print }
  ' "${hba_file}"
} >"${hba_tmp}"
"${SUDO[@]}" install -o postgres -g postgres -m 0640 "${hba_tmp}" "${hba_file}"

"${SUDO[@]}" systemctl restart postgresql@16-main.service

as_postgres psql --no-psqlrc --set=ON_ERROR_STOP=1 --dbname=postgres <<'SQL'
DO $bootstrap$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_owner') THEN
    CREATE ROLE macsad_owner;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_migrator') THEN
    CREATE ROLE macsad_migrator;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_app') THEN
    CREATE ROLE macsad_app;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_reader') THEN
    CREATE ROLE macsad_reader;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alejandro') THEN
    CREATE ROLE alejandro LOGIN;
  END IF;
END
$bootstrap$;

ALTER ROLE macsad_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE macsad_migrator NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE macsad_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE macsad_reader NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE alejandro LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;

GRANT macsad_owner TO macsad_migrator WITH INHERIT FALSE;
GRANT macsad_owner TO macsad_migrator WITH SET TRUE;
GRANT macsad_owner TO macsad_migrator WITH ADMIN FALSE;
GRANT macsad_owner, macsad_migrator TO alejandro WITH INHERIT FALSE;
GRANT macsad_owner, macsad_migrator TO alejandro WITH SET TRUE;
GRANT macsad_owner, macsad_migrator TO alejandro WITH ADMIN FALSE;

SELECT 'CREATE DATABASE macsad OWNER macsad_owner ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'macsad')
\gexec

ALTER DATABASE macsad OWNER TO macsad_owner;
REVOKE ALL ON DATABASE macsad FROM PUBLIC;
GRANT CONNECT ON DATABASE macsad TO macsad_owner, macsad_migrator, macsad_app, macsad_reader, alejandro;

ALTER DATABASE macsad SET search_path = pg_catalog;
ALTER ROLE alejandro IN DATABASE macsad SET search_path = pg_catalog;
ALTER ROLE macsad_owner IN DATABASE macsad SET search_path = macsad, macsad_meta, pg_catalog;
ALTER ROLE macsad_migrator IN DATABASE macsad SET search_path = macsad, macsad_meta, pg_catalog;
ALTER ROLE macsad_app IN DATABASE macsad SET search_path = macsad, pg_catalog;
ALTER ROLE macsad_reader IN DATABASE macsad SET search_path = macsad, pg_catalog;

\connect macsad
ALTER SCHEMA public OWNER TO macsad_owner;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
SQL

"${SUDO[@]}" systemctl enable postgresql.service postgresql@16-main.service >/dev/null
"${SUDO[@]}" systemctl is-enabled --quiet postgresql.service
"${SUDO[@]}" systemctl is-enabled --quiet postgresql@16-main.service
"${SUDO[@]}" systemctl is-active --quiet postgresql.service
"${SUDO[@]}" systemctl is-active --quiet postgresql@16-main.service

server_version_num="$(as_postgres psql --no-psqlrc --tuples-only --no-align --dbname=postgres \
  --command="SELECT current_setting('server_version_num')::integer;")"
(( server_version_num >= 160000 && server_version_num < 170000 )) ||
  die "PostgreSQL 16 verification failed: server_version_num=${server_version_num}"

listen_addresses="$(as_postgres psql --no-psqlrc --tuples-only --no-align --dbname=postgres \
  --command='SHOW listen_addresses;')"
[[ "${listen_addresses}" == 'localhost' ]] ||
  die "PostgreSQL must listen on localhost only; found ${listen_addresses}"

hba_errors="$(as_postgres psql --no-psqlrc --tuples-only --no-align --dbname=postgres \
  --command='SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL;')"
[[ "${hba_errors}" == '0' ]] || die "pg_hba.conf has ${hba_errors} parse error(s)"

peer_rule="$(as_postgres psql --no-psqlrc --tuples-only --no-align --dbname=postgres --command="
  SELECT auth_method
  FROM pg_hba_file_rules
  WHERE type = 'local'
    AND ('macsad' = ANY(database) OR 'all' = ANY(database))
    AND ('alejandro' = ANY(user_name) OR 'all' = ANY(user_name))
  ORDER BY line_number
  LIMIT 1;")"
[[ "${peer_rule}" == 'peer' ]] || die 'effective local alejandro/macsad authentication is not peer'

database_encoding="$(as_postgres psql --no-psqlrc --tuples-only --no-align --dbname=postgres \
  --command="SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = 'macsad';")"
[[ "${database_encoding}" == 'UTF8' ]] || die "macsad database encoding is ${database_encoding}, not UTF8"

as_postgres pg_isready --host=/var/run/postgresql --dbname=postgres >/dev/null
printf 'PostgreSQL 16 is installed, enabled, active, localhost-only, and ready on Firebat One.\n'
printf 'Next: PGDATABASE=macsad bash database/apply_migrations.sh\n'
