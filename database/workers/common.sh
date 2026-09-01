#!/usr/bin/env bash

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_postgresql_16() {
  local command_name="$1"
  local version_output
  version_output="$(${command_name} --version)" ||
    die "could not read ${command_name} version"
  [[ "${version_output}" =~ \(PostgreSQL\)[[:space:]]+16([.][0-9]+)*([[:space:]]|$) ]] ||
    die "${command_name} must be PostgreSQL 16: ${version_output}"
}

require_server_postgresql_16() {
  local server_version_num
  server_version_num="$(psql \
    --no-psqlrc --set=ON_ERROR_STOP=1 --tuples-only --no-align \
    --command='SHOW server_version_num')" ||
    die 'could not read the PostgreSQL server version'
  [[ "${server_version_num}" =~ ^16[0-9]{4}$ ]] ||
    die "database server must be PostgreSQL 16: ${server_version_num}"
}

require_canonical_uuid() {
  local value="$1"
  local label="$2"
  [[ "${value}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] ||
    die "${label} must be a canonical lowercase UUID"
}

require_sha256() {
  local value="$1"
  local label="$2"
  [[ "${value}" =~ ^[0-9a-f]{64}$ ]] ||
    die "${label} must be 64 lowercase hexadecimal characters"
}

require_md5() {
  local value="$1"
  local label="$2"
  [[ "${value}" =~ ^[0-9a-f]{32}$ ]] ||
    die "${label} must be 32 lowercase hexadecimal characters"
}

require_new_output() {
  local output="$1"
  [[ -n "${output}" ]] || die 'output path must not be empty'
  [[ ! -e "${output}" && ! -L "${output}" ]] ||
    die "output path already exists: ${output}"
  local parent
  parent="$(dirname -- "${output}")"
  [[ -d "${parent}" && ! -L "${parent}" && -w "${parent}" ]] ||
    die "output parent must be an existing non-symlink directory: ${parent}"
  realpath -- "${parent}" >/dev/null
}

require_output_outside_repository() {
  local output="$1"
  local repository_root="$2"
  local output_parent
  local resolved_repository
  output_parent="$(realpath -- "$(dirname -- "${output}")")"
  resolved_repository="$(realpath -- "${repository_root}")"
  case "${output_parent}/" in
    "${resolved_repository}/"*)
      die "output must be outside the Git repository: ${output}"
      ;;
  esac
}

require_cas_manifest() {
  local manifest="$1"
  [[ -f "${manifest}" && ! -L "${manifest}" ]] ||
    die "CAS manifest must be a regular non-symlink file: ${manifest}"
  awk -F '\t' '
    NR == 1 {
      if (NF != 2 || $1 != "format" || $2 != "macsad-cas-manifest/1") exit 1
      next
    }
    {
      if (NF != 5 || $1 != "blob" || $2 !~ /^[0-9a-f]{64}$/ ||
          $3 !~ /^(0|[1-9][0-9]*)$/ ||
          $4 !~ /^[a-z][a-z0-9._-]*$/ || $5 !~ /^([0-9a-f][0-9a-f])+$/ ||
          seen[$2]++) exit 1
      count += 1
    }
    END { if (NR == 0) exit 1 }
  ' "${manifest}" || die 'CAS manifest has an invalid format, blob row, or duplicate digest'
}

require_backup_manifest() {
  local manifest="$1"
  [[ -f "${manifest}" && ! -L "${manifest}" ]] ||
    die "backup manifest must be a regular non-symlink file: ${manifest}"
  awk -F '\t' '
    BEGIN {
      split("format postgresql_major server_version_num pg_dump_version schema_version schema_fingerprint archive_sha256 archive_size boundary_sha256 referenced_blobs_sha256 cas_manifest_sha256 write_fence_sha256 snapshot_consistency", expected, " ")
      for (i in expected) required[expected[i]] = 1
    }
    NF != 2 || $1 == "" || $2 == "" || seen[$1]++ || !($1 in required) { exit 1 }
    { found[$1] = 1 }
    END {
      if (NR != 13) exit 1
      for (key in required) if (!(key in found)) exit 1
    }
  ' "${manifest}" || die 'backup manifest has an unknown, missing, duplicate, or malformed row'
}

manifest_value() {
  local manifest="$1"
  local key="$2"
  local value
  value="$(awk -F '\t' -v wanted="${key}" '$1 == wanted { count += 1; value = $2 } END { if (count == 1) print value; else exit 1 }' "${manifest}")" ||
    die "backup manifest must contain exactly one ${key} row"
  [[ -n "${value}" ]] || die "backup manifest ${key} value must not be empty"
  printf '%s' "${value}"
}
