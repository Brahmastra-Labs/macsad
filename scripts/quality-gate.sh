#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly TEMP_BASE="$(realpath -- "${TMPDIR:-/tmp}")"
readonly TEMP_ROOT="$(mktemp -d "${TEMP_BASE}/macsad-quality.XXXXXXXX")"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ "${TEMP_ROOT}" != "${TEMP_BASE}/macsad-quality."* || ! -d "${TEMP_ROOT}" ]]; then
    printf 'error: refusing to remove unexpected temporary path: %s\n' "${TEMP_ROOT}" >&2
    return 1
  fi
  rm -rf -- "${TEMP_ROOT}"
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_command bash
require_command find
require_command mktemp
require_command mkdir
require_command node
require_command python3
require_command realpath
require_command sha256sum
require_command sort
require_command wc
require_command xargs

cd -- "${REPOSITORY_ROOT}"

printf '== Governance and source guardrails ==\n'
node --check scripts/guardrails.mjs
node --check scripts/verify-logos-tests.mjs
node scripts/guardrails.mjs

printf '== Mechanical development adapter tests ==\n'
python3 -m unittest discover --start-directory host_adapters/tests --pattern 'test_*.py'

readonly -a LOGOS_PROJECTS=(
  'logos/admin'
  'logos/public-site'
  'logos/gateway'
)

printf '== LOGOS format and supported type checks ==\n'
for project in "${LOGOS_PROJECTS[@]}"; do
  [[ -f "${project}/Largo.toml" && -f "${project}/src/main.lg" ]] ||
    die "incomplete LOGOS project: ${project}"
  (
    cd -- "${project}"
    "${REPOSITORY_ROOT}/scripts/logos.sh" fmt --check --color never
    "${REPOSITORY_ROOT}/scripts/logos.sh" check --json --color never
  )
done

printf '== LOGOS exact test manifest ==\n'
node scripts/verify-logos-tests.mjs

hash_tree() {
  local directory="$1"
  local file_count
  file_count="$(find "${directory}" -type f -printf '.' | wc -c)"
  ((file_count > 0)) || die "bundle directory is empty: ${directory}"
  (
    cd -- "${directory}"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
  )
}

assert_dom_bundle_shape() {
  local directory="$1"
  local extension
  for extension in html js mjs wasm; do
    [[ -n "$(find "${directory}" -type f -name "*.${extension}" -print -quit)" ]] ||
      die "wasm-dom bundle lacks a .${extension} artifact: ${directory}"
  done
}

printf '== Deterministic WASM-DOM bundles ==\n'
for project in 'logos/admin' 'logos/public-site'; do
  project_name="${project##*/}"
  first_output="${TEMP_ROOT}/${project_name}-first"
  second_output="${TEMP_ROOT}/${project_name}-second"
  mkdir -- "${first_output}" "${second_output}"
  (
    cd -- "${project}"
    "${REPOSITORY_ROOT}/scripts/logos.sh" emit wasm-dom --output "${first_output}/${project_name}.wasm" --color never
    "${REPOSITORY_ROOT}/scripts/logos.sh" emit wasm-dom --output "${second_output}/${project_name}.wasm" --color never
  )
  assert_dom_bundle_shape "${first_output}"
  assert_dom_bundle_shape "${second_output}"
  first_manifest="$(hash_tree "${first_output}")"
  second_manifest="$(hash_tree "${second_output}")"
  [[ "${first_manifest}" == "${second_manifest}" ]] ||
    die "nondeterministic wasm-dom output for ${project}"
  bundle_digest="$(printf '%s' "${first_manifest}" | sha256sum)"
  printf '%s bundle manifest sha256 %s\n' "${project_name}" "${bundle_digest%% *}"
done

printf '%s\n' \
  'Gateway evidence: supported checker + exact pure tests only.' \
  'Native/static-file serving remains a tracked RED framework gate; production bytes belong to Cloudflare Static Assets.'

database_evidence='not-run'
if [[ -n "${DATABASE_URL:-}" ]]; then
  printf '== Fresh PostgreSQL 16 migration and invariant gate ==\n'
  REPOSITORY_ROOT="${REPOSITORY_ROOT}" DATABASE_URL="${DATABASE_URL}" node --input-type=module <<'NODE'
import { spawnSync } from "node:child_process";
import { join } from "node:path";

function stop(message) {
  process.stderr.write(`error: ${message}\n`);
  process.exit(1);
}

let connection;
try {
  connection = new URL(process.env.DATABASE_URL);
} catch {
  stop("DATABASE_URL is not a valid URL");
}
if (!["postgres:", "postgresql:"].includes(connection.protocol)) {
  stop("DATABASE_URL must use the postgres or postgresql scheme");
}
if (connection.hash || [...connection.searchParams.keys()].some((key) => key !== "sslmode")) {
  stop("DATABASE_URL contains an unsupported fragment or connection parameter");
}
const databaseName = decodeURIComponent(connection.pathname.replace(/^\//, ""));
if (!/^[A-Za-z_][A-Za-z0-9_-]*$/.test(databaseName) || databaseName.includes("/")) {
  stop("DATABASE_URL must select one database by name");
}
if (!connection.hostname || !connection.username) {
  stop("DATABASE_URL must include a host and user");
}

const databaseEnvironment = {
  ...process.env,
  PGHOST: connection.hostname,
  PGPORT: connection.port || "5432",
  PGUSER: decodeURIComponent(connection.username),
  PGDATABASE: databaseName,
  PGAPPNAME: "macsad-quality-gate",
};
if (connection.password) databaseEnvironment.PGPASSWORD = decodeURIComponent(connection.password);
if (connection.searchParams.has("sslmode")) {
  databaseEnvironment.PGSSLMODE = connection.searchParams.get("sslmode");
}
delete databaseEnvironment.DATABASE_URL;

const repositoryRoot = process.env.REPOSITORY_ROOT;
function run(command, args, capture = false) {
  const result = spawnSync(command, args, {
    cwd: repositoryRoot,
    env: databaseEnvironment,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit",
  });
  if (result.error) stop(`${command} could not start: ${result.error.message}`);
  if (result.status !== 0 || result.signal !== null) {
    if (capture && result.stdout) process.stderr.write(result.stdout);
    if (capture && result.stderr) process.stderr.write(result.stderr);
    stop(`${command} failed with status ${String(result.status)} and signal ${String(result.signal)}`);
  }
  return capture ? result.stdout : "";
}

const cleanCount = run(
  "psql",
  [
    "--no-psqlrc",
    "--set=ON_ERROR_STOP=1",
    "--tuples-only",
    "--no-align",
    "--command",
    "SELECT count(*) FROM pg_namespace WHERE nspname IN ('macsad', 'macsad_meta');",
  ],
  true,
).trim();
if (cleanCount !== "0") stop("database is not clean; MaCSad schemas already exist");

const migrationRunner = join(repositoryRoot, "database", "apply_migrations.sh");
run("bash", [migrationRunner]);
run("bash", [migrationRunner]);
run("psql", [
  "--no-psqlrc",
  "--set=ON_ERROR_STOP=1",
  `--dbname=${databaseName}`,
  `--file=${join(repositoryRoot, "database", "verify.sql")}`,
]);
run("psql", [
  "--no-psqlrc",
  "--set=ON_ERROR_STOP=1",
  `--dbname=${databaseName}`,
  `--file=${join(repositoryRoot, "database", "tests", "0001_invariants.sql")}`,
]);
NODE
  database_evidence='clean-migrate-repeat-verify-invariants'
elif [[ "${MACSAD_REQUIRE_DATABASE:-0}" == '1' ]]; then
  die 'MACSAD_REQUIRE_DATABASE=1 but DATABASE_URL is unset'
else
  printf 'PostgreSQL evidence not run: DATABASE_URL is unset.\n'
fi

printf 'Quality gate completed; PostgreSQL evidence: %s.\n' "${database_evidence}"
