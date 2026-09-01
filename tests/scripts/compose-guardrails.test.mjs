import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, sep } from "node:path";
import test from "node:test";
import {
  ComposeGuardrailError,
  inspectComposeSource,
  inspectPgAdminServers,
  validateRepository,
} from "../../scripts/compose-guardrails.mjs";

const digestA = "a".repeat(64);
const digestB = "b".repeat(64);
const temporaryBase = realpathSync(tmpdir());

function validCompose() {
  return `name: macsad-firebat

services:
  postgres:
    image: "macsad/postgres:\${MACSAD_SOURCE_REVISION:?run stack configure}"
    build:
      context: .
      dockerfile: images/postgres.Dockerfile
      additional_contexts:
        database-source: "\${MACSAD_BUILD_DIR:?run stack prepare}/database-source"
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_superuser_password
    secrets:
      - postgres_superuser_password
      - macsad_deployer_password
      - macsad_runtime_password
      - macsad_viewer_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - data

  migrate:
    image: "macsad/postgres:\${MACSAD_SOURCE_REVISION:?run stack configure}"
    environment:
      PGUSER: macsad_deployer
    secrets:
      - macsad_deployer_password
    networks:
      - data
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

  logos-gateway:
    image: "macsad/logos-gateway:\${MACSAD_SOURCE_REVISION:?run stack configure}"
    build:
      context: .
      dockerfile: images/logos-gateway.Dockerfile
      additional_contexts:
        gateway-source: "\${MACSAD_BUILD_DIR:?run stack prepare}/gateway-source"
        logos-runtime: "\${MACSAD_BUILD_DIR:?run stack prepare}/logos-runtime"
    networks:
      - data
      - edge
    ports:
      - "\${MACSAD_BIND_IP:?set MACSAD_BIND_IP}:18080:8080"
      - "\${MACSAD_BIND_IP:?set MACSAD_BIND_IP}:18082:8082"
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

  logos-sites:
    image: "macsad/logos-sites:\${MACSAD_SOURCE_REVISION:?run stack configure}"
    build:
      context: .
      dockerfile: images/logos-sites.Dockerfile
      additional_contexts:
        admin-bundle: "\${MACSAD_BUILD_DIR:?run stack prepare}/admin-bundle"
        public-bundle: "\${MACSAD_BUILD_DIR:?run stack prepare}/public-bundle"
    network_mode: service:logos-gateway
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

  pgadmin:
    image: dpage/pgadmin4:9.17@sha256:${digestB}
    environment:
      PGADMIN_DEFAULT_EMAIL: "\${PGADMIN_DEFAULT_EMAIL:?set PGADMIN_DEFAULT_EMAIL}"
      PGADMIN_DEFAULT_PASSWORD_FILE: /run/secrets/pgadmin_admin_password
      PGADMIN_CONFIG_ALLOW_SAVE_PASSWORD: "False"
    secrets:
      - pgadmin_admin_password
    configs:
      - source: pgadmin_servers
        target: /pgadmin4/servers.json
        mode: 0444
    networks:
      - data
    ports:
      - "\${MACSAD_BIND_IP:?set MACSAD_BIND_IP}:8978:8080"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

networks:
  data:
    internal: true
  edge:
    internal: true

volumes:
  postgres_data:
  pgadmin_data:

configs:
  pgadmin_servers:
    file: ./pgadmin/servers.json

secrets:
  postgres_superuser_password:
    file: "\${MACSAD_SECRETS_DIR:?run stack configure}/postgres_superuser_password"
  macsad_deployer_password:
    file: "\${MACSAD_SECRETS_DIR:?run stack configure}/macsad_deployer_password"
  macsad_runtime_password:
    file: "\${MACSAD_SECRETS_DIR:?run stack configure}/macsad_runtime_password"
  macsad_viewer_password:
    file: "\${MACSAD_SECRETS_DIR:?run stack configure}/macsad_viewer_password"
  pgadmin_admin_password:
    file: "\${MACSAD_SECRETS_DIR:?run stack configure}/pgadmin_admin_password"
`;
}

function validServers() {
  return JSON.stringify({
    Servers: {
      1: {
        Host: "postgres",
        MaintenanceDB: "macsad",
        Name: "MaCSad read only",
        Port: 5432,
        SharedUsername: "macsad_viewer",
        Username: "macsad_viewer",
      },
    },
  });
}

function inspect(source) {
  return inspectComposeSource(source, {
    repositoryRoot: "C:/fixture/macsad",
    sourcePath: "ops/compose/compose.yaml",
  });
}

function assertViolation(source, pattern) {
  assert.throws(
    () => inspect(source),
    (error) => error instanceof ComposeGuardrailError && pattern.test(error.message),
  );
}

function replaceOnce(source, before, after) {
  assert.equal(source.includes(before), true, `fixture is missing replacement source: ${before}`);
  return source.replace(before, after);
}

function write(path, contents) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, contents, { encoding: "utf8", flag: "wx" });
}

function safeEnvironmentParser(environmentName, valueCheck) {
  return `  local line key value
  declare -A seen=()
  while IFS= read -r line || [[ -n "\${line}" ]]; do
    [[ "\${line}" =~ ^([A-Z][A-Z0-9_]*)=(.+)$ ]] || die malformed
    key="\${BASH_REMATCH[1]}"
    value="\${BASH_REMATCH[2]}"
    case "\${key}" in
      MACSAD_BIND_IP|MACSAD_REPOSITORY_ROOT|MACSAD_RUNTIME_DIR|MACSAD_BUILD_DIR|MACSAD_SECRETS_DIR|MACSAD_SOURCE_REVISION|LOGOS_WORKSPACE|PGADMIN_DEFAULT_EMAIL) ;;
      *) die unexpected ;;
    esac
    [[ -z "\${seen[\${key}]:-}" ]] || die duplicate
    ${valueCheck}
    seen["\${key}"]=1
    printf -v "\${key}" '%s' "\${value}"
    export "\${key}"
  done <"\${${environmentName}}"
`;
}

function safeStackHarness() {
  return `readonly DEFAULT_RUNTIME_DIR="\${REPOSITORY_ROOT}/.runtime/compose"
die() { exit 1; }
validate_environment_value() { [[ -n "$2" ]]; }
load_environment() {
  local env_file="\${DEFAULT_RUNTIME_DIR}/compose.env"
  [[ -f "\${env_file}" && ! -L "\${env_file}" ]] || die invalid
  [[ "$(stat -c '%a' -- "\${env_file}")" == '600' ]] || die mode
${safeEnvironmentParser("env_file", 'validate_environment_value "${key}" "${value}"')}  [[ "\${MACSAD_REPOSITORY_ROOT}" == "\${REPOSITORY_ROOT}" ]] || die repository
  [[ "\${MACSAD_RUNTIME_DIR}" == "\${DEFAULT_RUNTIME_DIR}" ]] || die runtime
  [[ "\${MACSAD_SECRETS_DIR}" == "\${DEFAULT_RUNTIME_DIR}/secrets" ]] || die secrets
  [[ "\${MACSAD_BUILD_DIR}" == "\${DEFAULT_RUNTIME_DIR}/build/\${MACSAD_SOURCE_REVISION}" ]] || die build
  [[ "\${MACSAD_SOURCE_REVISION}" =~ ^[0-9a-f]{40}$ ]] || die revision
  [[ "$(git -C "\${REPOSITORY_ROOT}" rev-parse --verify HEAD)" == "\${MACSAD_SOURCE_REVISION}" ]] || die head
}
runtime_dir() {
  [[ -n "\${MACSAD_RUNTIME_DIR:-}" && "\${MACSAD_RUNTIME_DIR}" != "\${DEFAULT_RUNTIME_DIR}" ]] && die runtime
  printf '%s' "\${DEFAULT_RUNTIME_DIR}"
}
secrets_dir="\${root_runtime}/secrets"
build_dir="\${root_runtime}/build/\${source_revision}"
MACSAD_BUILD_DIR MACSAD_SECRETS_DIR
tailscale ip -4 | grep -Fqx -- "\${bind_ip}"
[[ "\${bind_ip}" != '0.0.0.0' && "\${bind_ip}" != 127.* ]]
"\${REPOSITORY_ROOT}/scripts/logos.sh" --version
install "\${LOGOS_WORKSPACE}/target/debug/largo" "\${stage}/logos-runtime/largo"
git -C "\${REPOSITORY_ROOT}" status --porcelain
git -C "\${REPOSITORY_ROOT}" status --porcelain
`;
}

function safeDevHarness() {
  return `readonly RUNTIME_ENV="\${REPOSITORY_ROOT}/.runtime/compose/compose.env"
die() { exit 1; }
load_environment() {
  [[ -f "\${RUNTIME_ENV}" && ! -L "\${RUNTIME_ENV}" ]] || die invalid
  [[ "$(stat -c '%a' -- "\${RUNTIME_ENV}")" == '600' ]] || die mode
${safeEnvironmentParser("RUNTIME_ENV", '[[ "${value}" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]] || die value')}  [[ "\${MACSAD_REPOSITORY_ROOT}" == "\${REPOSITORY_ROOT}" ]] || die repository
  [[ "\${MACSAD_RUNTIME_DIR}" == "\${REPOSITORY_ROOT}/.runtime/compose" ]] || die runtime
  [[ "\${MACSAD_SECRETS_DIR}" == "\${MACSAD_RUNTIME_DIR}/secrets" ]] || die secrets
  [[ "\${MACSAD_SOURCE_REVISION}" =~ ^[0-9a-f]{40}$ ]] || die revision
  [[ "\${MACSAD_BUILD_DIR}" == "\${MACSAD_RUNTIME_DIR}/build/\${MACSAD_SOURCE_REVISION}" ]] || die build
  [[ "$(git -C "\${REPOSITORY_ROOT}" rev-parse --verify HEAD)" == "\${MACSAD_SOURCE_REVISION}" ]] || die head
}
git -C "\${REPOSITORY_ROOT}" status --porcelain
`;
}

function fixtureRepository({ stack = safeStackHarness(), dev = safeDevHarness() } = {}) {
  const root = mkdtempSync(join(temporaryBase, "macsad-compose-guard-"));
  write(join(root, ".gitignore"), ".runtime/\n");
  write(join(root, "ops", "compose", "compose.yaml"), validCompose());
  write(join(root, "ops", "compose", "pgadmin", "servers.json"), validServers());
  write(join(root, "ops", "compose", "stack.sh"), stack);
  write(join(root, "scripts", "dev.sh"), dev);
  return root;
}

function removeFixture(root) {
  const canonical = realpathSync(root);
  if (!canonical.startsWith(`${temporaryBase}${sep}macsad-compose-guard-`)) {
    throw new Error(`refusing to remove unexpected fixture path: ${canonical}`);
  }
  rmSync(canonical, { recursive: true });
}

function assertRepositoryViolation(options, pattern) {
  const root = fixtureRepository(options);
  try {
    assert.throws(
      () => validateRepository(root),
      (error) => error instanceof ComposeGuardrailError && pattern.test(error.message),
    );
  } finally {
    removeFixture(root);
  }
}

test("accepts the exact five-service staged-artifact topology", () => {
  const result = inspect(validCompose());
  assert.deepEqual(result.services, [
    "postgres",
    "migrate",
    "logos-gateway",
    "logos-sites",
    "pgadmin",
  ]);
  assert.equal(result.pgadminConfigFile, "./pgadmin/servers.json");
});

test("validates a repository and its credential-free pgAdmin config", () => {
  const root = fixtureRepository();
  try {
    const result = validateRepository(root);
    assert.equal(result.services.length, 5);
  } finally {
    removeFixture(root);
  }
});

test("rejects executable or weakly parsed runtime environment files", async (context) => {
  await context.test("stack sources compose.env", () => {
    assertRepositoryViolation(
      {
        stack: replaceOnce(
          safeStackHarness(),
          "load_environment() {\n",
          'load_environment() {\n  source "${env_file}"\n',
        ),
      },
      /must never be sourced as shell code/,
    );
  });
  await context.test("developer harness sources compose.env", () => {
    assertRepositoryViolation(
      {
        dev: replaceOnce(
          safeDevHarness(),
          "load_environment() {\n",
          'load_environment() {\n  . "${RUNTIME_ENV}"\n',
        ),
      },
      /must never be sourced as shell code/,
    );
  });
  await context.test("developer harness evaluates a parsed value", () => {
    assertRepositoryViolation(
      { dev: `${safeDevHarness()}\neval "\${MACSAD_BUILD_DIR}"\n` },
      /eval is forbidden/,
    );
  });
  await context.test("allowlist grows an unreviewed key", () => {
    assertRepositoryViolation(
      {
        stack: replaceOnce(
          safeStackHarness(),
          "MACSAD_BIND_IP|MACSAD_REPOSITORY_ROOT",
          "ATTACKER_VALUE|MACSAD_BIND_IP|MACSAD_REPOSITORY_ROOT",
        ),
      },
      /runtime environment keys must be exactly/,
    );
  });
  await context.test("safe-character validation is removed", () => {
    assertRepositoryViolation(
      {
        dev: replaceOnce(
          safeDevHarness(),
          '    [[ "${value}" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]] || die value\n',
          "    true\n",
        ),
      },
      /strict safe-character allowlist/,
    );
  });
});

test("locks runtime identity, source revision, and complete Git cleanliness", async (context) => {
  await context.test("developer runtime root check is removed", () => {
    assertRepositoryViolation(
      {
        dev: replaceOnce(
          safeDevHarness(),
          '  [[ "${MACSAD_RUNTIME_DIR}" == "${REPOSITORY_ROOT}/.runtime/compose" ]] || die runtime\n',
          "",
        ),
      },
      /runtime root must be fixed inside the checkout/,
    );
  });
  await context.test("developer source revision check is removed", () => {
    assertRepositoryViolation(
      {
        dev: replaceOnce(
          safeDevHarness(),
          '  [[ "$(git -C "${REPOSITORY_ROOT}" rev-parse --verify HEAD)" == "${MACSAD_SOURCE_REVISION}" ]] || die head\n',
          "",
        ),
      },
      /source revision must equal the current checkout HEAD/,
    );
  });
  await context.test("stack hides untracked files", () => {
    assertRepositoryViolation(
      {
        stack: replaceOnce(
          safeStackHarness(),
          "status --porcelain",
          "status --porcelain --untracked-files=no",
        ),
      },
      /may not hide untracked files/,
    );
  });
  await context.test("developer harness omits full cleanliness check", () => {
    assertRepositoryViolation(
      {
        dev: replaceOnce(
          safeDevHarness(),
          'git -C "${REPOSITORY_ROOT}" status --porcelain\n',
          'git -C "${REPOSITORY_ROOT}" diff --quiet\n',
        ),
      },
      /full tracked-and-untracked Git cleanliness check/,
    );
  });
});

test("rejects service and image supply-chain escape hatches", async (context) => {
  await context.test("extra service", () => {
    assertViolation(
      replaceOnce(validCompose(), "services:\n", "services:\n  surprise:\n    image: busybox:1.37@sha256:" + digestA + "\n"),
      /services must be exactly/,
    );
  });
  await context.test("floating image tag", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "macsad/postgres:\${MACSAD_SOURCE_REVISION:?run stack configure}",
        "macsad/postgres:latest",
      ),
      /pulled images require a tag and sha256 digest|migrate must reuse/,
    );
  });
  await context.test("tag without digest", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        `dpage/pgadmin4:9.17@sha256:${digestB}`,
        "dpage/pgadmin4:9.17",
      ),
      /pulled images require a tag and sha256 digest/,
    );
  });
});

test("rejects unsafe publication including fallback and database ports", async (context) => {
  await context.test("wildcard literal", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "\${MACSAD_BIND_IP:?set MACSAD_BIND_IP}:18080:8080",
        "0.0.0.0:18080:8080",
      ),
      /published port must bind/,
    );
  });
  await context.test("wildcard fallback", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "\${MACSAD_BIND_IP:?set MACSAD_BIND_IP}:18080:8080",
        "\${MACSAD_BIND_IP:-0.0.0.0}:18080:8080",
      ),
      /published port must bind/,
    );
  });
  await context.test("postgres host port", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    networks:\n      - data\n\n  migrate:",
        "    networks:\n      - data\n    ports:\n      - \"\${MACSAD_BIND_IP:?required}:15432:5432\"\n\n  migrate:",
      ),
      /PostgreSQL must not publish|direct PostgreSQL publication/,
    );
  });
  await context.test("database target on another service", () => {
    assertViolation(
      replaceOnce(validCompose(), ":8978:8080", ":8978:5432"),
      /direct PostgreSQL publication/,
    );
  });
  await context.test("unapproved but safely bound port", () => {
    assertViolation(
      replaceOnce(validCompose(), ":18080:8080", ":18081:8080"),
      /published ports must be exactly/,
    );
  });
});

test("rejects host control and container privilege escape hatches", async (context) => {
  for (const [name, addition, pattern] of [
    ["privileged", "    privileged: true\n", /may not declare privileged/],
    ["capability addition", "    cap_add:\n      - SYS_ADMIN\n", /may not declare cap_add/],
    ["Docker socket", "    volumes:\n      - /var/run/docker.sock:/var/run/docker.sock\n", /Docker socket|runtime bind mounts/],
    ["host network", "    network_mode: host\n", /forbidden network_mode/],
    ["environment file", "    env_file: ./secrets.env\n", /may not declare env_file/],
  ]) {
    await context.test(name, () => {
      assertViolation(
        replaceOnce(validCompose(), "  pgadmin:\n", `  pgadmin:\n${addition}`),
        pattern,
      );
    });
  }
});

test("rejects runtime source mounts and build contexts outside the staging root", async (context) => {
  await context.test("private LOGOS checkout mount", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    networks:\n      - data\n      - edge\n",
        "    volumes:\n      - \"\${LOGOS_WORKSPACE:?required}:/opt/logos:ro\"\n    networks:\n      - data\n      - edge\n",
      ),
      /runtime bind mounts|private LOGOS checkout/,
    );
  });
  await context.test("repository build context", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "context: .",
        "context: ../../..",
      ),
      /primary build context must be/,
    );
  });
  await context.test("missing verified local LOGOS runtime", () => {
    assertViolation(
      replaceOnce(validCompose(), "logos-runtime:", "unverified-runtime:"),
      /additional contexts must be exactly|must consume the staged logos-runtime context/,
    );
  });
  await context.test("registry LOGOS install", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    network_mode: service:logos-gateway\n",
        "    network_mode: service:logos-gateway\n    command: cargo install largo\n",
      ),
      /registry LOGOS dependency/,
    );
  });
});

test("rejects plaintext and incorrectly wired secrets", async (context) => {
  await context.test("plaintext password environment", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "POSTGRES_PASSWORD_FILE: /run/secrets/postgres_superuser_password",
        "POSTGRES_PASSWORD: hunter2",
      ),
      /sensitive environment value POSTGRES_PASSWORD/,
    );
  });
  await context.test("secret environment interpolation", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    networks:\n      - data\n      - edge\n",
        "    environment:\n      DATABASE_URL: \${DATABASE_URL:?required}\n    networks:\n      - data\n      - edge\n",
      ),
      /sensitive environment value DATABASE_URL/,
    );
  });
  await context.test("secret file inside checkout", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "file: \"\${MACSAD_SECRETS_DIR:?run stack configure}/pgadmin_admin_password\"",
        "file: ./secrets/pgadmin_admin_password",
      ),
      /must use required \$\{MACSAD_SECRETS_DIR/,
    );
  });
  await context.test("file variable references unmounted secret", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    networks:\n      - data\n      - edge\n",
        "    environment:\n      DATABASE_URL_FILE: /run/secrets/not_mounted\n    networks:\n      - data\n      - edge\n",
      ),
      /undeclared service secret not_mounted/,
    );
  });
});

test("rejects network and publication coupling violations", async (context) => {
  await context.test("non-internal data network", () => {
    assertViolation(replaceOnce(validCompose(), "internal: true", "internal: false"), /internal: true/);
  });
  await context.test("sites own network", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    network_mode: service:logos-gateway\n",
        "    network_mode: service:logos-gateway\n    networks:\n      - data\n",
      ),
      /logos-sites must publish no ports or networks|direct database connection/,
    );
  });
  await context.test("sites direct database environment", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    network_mode: service:logos-gateway\n",
        "    network_mode: service:logos-gateway\n    environment:\n      PGHOST: postgres\n",
      ),
      /direct database connection/,
    );
  });
  await context.test("sites do not share an arbitrary namespace", () => {
    assertViolation(
      replaceOnce(validCompose(), "network_mode: service:logos-gateway", "network_mode: host"),
      /forbidden network_mode|must share only/,
    );
  });
  await context.test("extra top-level network", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "  edge:\n    internal: true\n",
        "  edge:\n    internal: true\n  surprise:\n    internal: true\n",
      ),
      /top-level networks must be exactly/,
    );
  });
  await context.test("extra service network", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    volumes:\n      - pgadmin_data:/var/lib/pgadmin\n",
        "    volumes:\n      - pgadmin_data:/var/lib/pgadmin\n    networks:\n      - edge\n",
      ),
      /duplicate service pgadmin key networks|networks must be exactly/,
    );
  });
});

test("rejects volume and config indirection escape hatches", async (context) => {
  await context.test("named volume backed by a host bind", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "  postgres_data:\n",
        "  postgres_data:\n    driver: local\n    driver_opts:\n      type: none\n      o: bind\n      device: /srv/postgres\n",
      ),
      /engine-managed with no driver, driver_opts, device, or external source/,
    );
  });
  await context.test("extra named volume", () => {
    assertViolation(
      replaceOnce(validCompose(), "  pgadmin_data:\n", "  pgadmin_data:\n  host_data:\n"),
      /top-level volumes must be exactly/,
    );
  });
  await context.test("extra top-level config", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "  pgadmin_servers:\n    file: ./pgadmin/servers.json\n",
        "  pgadmin_servers:\n    file: ./pgadmin/servers.json\n  hidden_config:\n    file: ./hidden.conf\n",
      ),
      /top-level configs must contain only/,
    );
  });
});

test("locks the exact container hardening profile", async (context) => {
  await context.test("read-only root removed", () => {
    assertViolation(
      replaceOnce(validCompose(), "    read_only: true\n", ""),
      /must declare read_only: true/,
    );
  });
  await context.test("capability retained", () => {
    assertViolation(replaceOnce(validCompose(), "      - ALL\n", "      - NET_ADMIN\n"), /drop exactly ALL/);
  });
  await context.test("no-new-privileges removed", () => {
    assertViolation(
      replaceOnce(validCompose(), "      - no-new-privileges:true\n", ""),
      /must set exactly no-new-privileges:true/,
    );
  });
  await context.test("unsupported pgAdmin read-only override", () => {
    assertViolation(
      replaceOnce(validCompose(), "  pgadmin:\n", "  pgadmin:\n    read_only: true\n"),
      /must not override the read_only contract/,
    );
  });
  await context.test("migration role changed", () => {
    assertViolation(
      replaceOnce(validCompose(), "PGUSER: macsad_deployer", "PGUSER: postgres"),
      /migrate PGUSER must be exactly macsad_deployer/,
    );
  });
});

test("rejects YAML ambiguity and GET mutation camouflage", async (context) => {
  await context.test("anchor and merge", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "  postgres:\n",
        "  postgres:\n    environment: &shared_environment\n      POSTGRES_DB: macsad\n    <<: *shared_environment\n",
      ),
      /anchors, aliases, and merge keys|duplicate service postgres key environment/,
    );
  });
  await context.test("duplicate direct key", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        '    image: "macsad/postgres:\${MACSAD_SOURCE_REVISION:?run stack configure}"',
        '    image: "macsad/postgres:\${MACSAD_SOURCE_REVISION:?run stack configure}"\n' +
          '    image: "macsad/postgres:\${MACSAD_SOURCE_REVISION:?run stack configure}"',
      ),
      /duplicate service postgres key image/,
    );
  });
  await context.test("GET command endpoint", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    network_mode: service:logos-gateway\n",
        "    network_mode: service:logos-gateway\n    healthcheck:\n      test: \"GET /api/publish\"\n",
      ),
      /GET may not be used for a mutation/,
    );
  });
  await context.test("GET command split over list entries", () => {
    assertViolation(
      replaceOnce(
        validCompose(),
        "    network_mode: service:logos-gateway\n",
        "    network_mode: service:logos-gateway\n    healthcheck:\n      test:\n        - GET\n        - /api/archive\n",
      ),
      /GET may not be used for a mutation/,
    );
  });
});

test("pgAdmin definitions reject stored credentials and wrong hosts", async (context) => {
  assert.equal(inspectPgAdminServers(validServers()).serverCount, 1);
  await context.test("password field", () => {
    const document = JSON.parse(validServers());
    document.Servers[1].Password = "secret";
    assert.throws(
      () => inspectPgAdminServers(JSON.stringify(document)),
      (error) => error instanceof ComposeGuardrailError && /credential-bearing/.test(error.message),
    );
  });
  await context.test("embedded URL credential", () => {
    const document = JSON.parse(validServers());
    document.Servers[1].TunnelHost = "ssh://person:secret@firebat";
    assert.throws(
      () => inspectPgAdminServers(JSON.stringify(document)),
      (error) => error instanceof ComposeGuardrailError && /embedded credentials/.test(error.message),
    );
  });
  await context.test("external database host", () => {
    const document = JSON.parse(validServers());
    document.Servers[1].Host = "db.example.com";
    assert.throws(
      () => inspectPgAdminServers(JSON.stringify(document)),
      (error) => error instanceof ComposeGuardrailError && /internal postgres service/.test(error.message),
    );
  });
  await context.test("wrong viewer identity", () => {
    const document = JSON.parse(validServers());
    document.Servers[1].Username = "postgres";
    assert.throws(
      () => inspectPgAdminServers(JSON.stringify(document)),
      (error) => error instanceof ComposeGuardrailError && /must be macsad_viewer/.test(error.message),
    );
  });
});
