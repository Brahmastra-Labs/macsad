#!/usr/bin/env node

import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { dirname, extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import {
  defaultModuleManifestPath,
  inspectRegisteredProjects,
  loadModuleManifest,
} from "./logos-project.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const failures = [];

function repositoryPath(path) {
  return relative(repositoryRoot, path).split(sep).join("/");
}

function fail(path, message) {
  failures.push(`${repositoryPath(path)}: ${message}`);
}

function read(path) {
  try {
    return readFileSync(path, "utf8");
  } catch (error) {
    fail(path, `cannot be read: ${error.message}`);
    return "";
  }
}

function filesBelow(path) {
  if (!existsSync(path)) return [];
  const result = [];
  for (const entry of readdirSync(path).sort()) {
    const child = join(path, entry);
    const stats = statSync(child);
    if (stats.isDirectory()) {
      if (entry !== "target" && entry !== "node_modules" && entry !== ".git") {
        result.push(...filesBelow(child));
      }
    } else if (stats.isFile()) {
      result.push(child);
    }
  }
  return result;
}

const requiredFiles = [
  ".editorconfig",
  ".gitattributes",
  "AGENTS.md",
  "CONTRIBUTING.md",
  "LOGOS_GAPS.md",
  ".github/ISSUE_TEMPLATE/change_request.yml",
  ".github/ISSUE_TEMPLATE/config.yml",
  ".github/pull_request_template.md",
  ".macsad/toolchains/logos.lock.toml",
  ".macsad/policies/logos-source-quality.json",
  ".macsad/schemas/logos-source-quality-v1.schema.json",
  "docs/runbooks/agent-request-intake.md",
  "docs/runbooks/upgrading-logos.md",
  "docs/standards/logos-source-quality.md",
  "tests/logos-module-manifest.json",
  "tests/browser-smoke-contract.json",
  "scripts/logos.sh",
  "scripts/logos-project.mjs",
  "scripts/logos-source-lint.mjs",
  "tests/scripts/logos-source-lint.test.mjs",
  "scripts/ci/firebat2-verify.sh",
  "scripts/ci/browser-probe.mjs",
  "scripts/ci/audit-github-actions-settings.mjs",
  "scripts/ci/verify-firebat2-contract.mjs",
  "ops/firebat2/verify_verifier_host.sh",
  "database/apply_migrations.sh",
  "database/verify.sql",
];
for (const requiredFile of requiredFiles) {
  const path = join(repositoryRoot, requiredFile);
  if (!existsSync(path)) fail(path, "required governance file is missing");
}

const intakeTemplatePath = join(
  repositoryRoot,
  ".github",
  "ISSUE_TEMPLATE",
  "change_request.yml",
);
const intakeTemplate = read(intakeTemplatePath);
for (const requiredField of [
  "outcome",
  "job",
  "scope",
  "authority",
  "risk_lane",
  "acceptance",
  "blockers",
  "boundaries",
]) {
  if (!new RegExp(`^\\s+id:\\s*${requiredField}\\s*$`, "m").test(intakeTemplate)) {
    fail(intakeTemplatePath, `required intake field is missing: ${requiredField}`);
  }
}
if ((intakeTemplate.match(/^\s+required:\s*true\s*$/gm) ?? []).length < 10) {
  fail(intakeTemplatePath, "request intake fields and authority checks must fail closed");
}
const issueConfigPath = join(repositoryRoot, ".github", "ISSUE_TEMPLATE", "config.yml");
if (!/^blank_issues_enabled:\s*false\s*$/m.test(read(issueConfigPath))) {
  fail(issueConfigPath, "blank issues must remain disabled");
}

const lockPath = join(repositoryRoot, ".macsad", "toolchains", "logos.lock.toml");
const lock = read(lockPath);
for (const [label, pattern] of [
  ["lock schema", /^schema\s*=\s*"macsad-logos-toolchain-lock\/1"\s*$/m],
  ["exact source version", /^version\s*=\s*"\d+\.\d+\.\d+"\s*$/m],
  ["source commit", /^commit\s*=\s*"[0-9a-f]{40}"\s*$/m],
  ["source tree", /^tree\s*=\s*"[0-9a-f]{40}"\s*$/m],
  ["Cargo.lock digest", /^cargo_lock_sha256\s*=\s*"[0-9a-f]{64}"\s*$/m],
  ["runtime binary digest", /^observed_binary_sha256\s*=\s*"[0-9a-f]{64}"\s*$/m],
  ["zero skip budget", /^skip_budget\s*=\s*0\s*$/m],
  ["fixed seed", /^deterministic_seed\s*=\s*7\s*$/m],
  ["all tiers", /^test_tiers\s*=\s*"all"\s*$/m],
  ["finite proof mode", /^prove_finite_properties\s*=\s*true\s*$/m],
]) {
  if (!pattern.test(lock)) fail(lockPath, `${label} is absent or unpinned`);
}
if (/default_workspace\s*=/.test(lock) || /(?:[A-Za-z]:\\Users\\|\/home\/[^/]+\/)/.test(lock)) {
  fail(lockPath, "toolchain lock contains a developer-specific absolute path");
}

const logosWrapperPath = join(repositoryRoot, "scripts", "logos.sh");
const logosWrapper = read(logosWrapperPath);
for (const [label, pattern] of [
  ["required LOGOS_WORKSPACE", /\[\[ -n "\$\{LOGOS_WORKSPACE:-\}" \]\]/],
  ["exact HEAD commit", /git -C "\$\{logos_workspace\}" rev-parse --verify HEAD/],
  ["exact HEAD tree", /git -C "\$\{logos_workspace\}" rev-parse --verify 'HEAD\^\{tree\}'/],
  ["clean complete source", /git -C "\$\{logos_workspace\}" status --porcelain --untracked-files=all/],
  ["exact origin identity", /git -C "\$\{logos_workspace\}" remote get-url origin/],
  ["Cargo lock digest", /sha256sum -- "\$\{cargo_lock\}"/],
  ["largo binary digest", /sha256sum -- "\$\{largo_binary\}"/],
  ["largo version", /"\$\{largo_binary\}" --version/],
]) {
  if (!pattern.test(logosWrapper)) fail(logosWrapperPath, `${label} enforcement is missing`);
}
if (/LOGOS_WORKSPACE:-[^}]+/.test(logosWrapper)) {
  fail(logosWrapperPath, "LOGOS_WORKSPACE may not have a fallback checkout");
}

if (existsSync(defaultModuleManifestPath)) {
  try {
    const moduleManifest = loadModuleManifest(defaultModuleManifestPath);
    inspectRegisteredProjects(moduleManifest, repositoryRoot);
  } catch (error) {
    fail(defaultModuleManifestPath, error.message);
  }
}

const executableCandidates = [
  ...filesBelow(join(repositoryRoot, "scripts")),
  ...filesBelow(join(repositoryRoot, ".github", "workflows")),
  ...filesBelow(join(repositoryRoot, "logos")),
  ...filesBelow(join(repositoryRoot, "host_adapters")),
].filter((path) => path !== join(repositoryRoot, "scripts", "guardrails.mjs"));

for (const path of executableCandidates) {
  const extension = extname(path).toLowerCase();
  if (![".sh", ".mjs", ".js", ".py", ".yml", ".yaml", ".lg", ".toml"].includes(extension)) {
    continue;
  }
  const text = read(path);
  for (const [label, pattern] of [
    ["continue-on-error", /continue-on-error\s*:/i],
    ["allow_failure", /allow_failure\s*[:=]/i],
    ["disabled shell error handling", /(^|[;&|]\s*)set\s+\+e(?:\s|$)/m],
    ["swallowed shell failure", /\|\|\s*true(?:\s|$)/m],
    ["pull_request_target", /\bpull_request_target\s*:/],
    ["write-all permission", /permissions\s*:\s*write-all/i],
    ["developer Windows path", /[A-Za-z]:\\Users\\/],
    ["developer Unix home", /\/home\/[^/]+\//],
    ["remote install pipe", /(?:curl|wget)[^\n|]*\|\s*(?:ba)?sh\b/],
    ["registry LOGOS installation", /cargo\s+(?:add|install)\s+[^\n]*(?:logos|logicaffeine|largo)/i],
  ]) {
    if (pattern.test(text)) fail(path, `forbidden ${label}`);
  }
  if (extension === ".js" && repositoryPath(path).startsWith("logos/")) {
    fail(path, "handwritten JavaScript is forbidden in a LOGOS application");
  }
  if (extension === ".lg" && /fetchText\s*\([^)]*(?:delete|patch|post|put)/i.test(text)) {
    fail(path, "fetchText cannot be presented as mutation transport");
  }
  if (extension === ".lg" && /^\s*##\s+Requires\b/m.test(text)) {
    fail(path, "## Requires resolves registry crates on this LOGOS revision; MaCSad must use the locked local source closure");
  }
}

for (const workflow of filesBelow(join(repositoryRoot, ".github", "workflows"))) {
  if (![".yml", ".yaml"].includes(extname(workflow).toLowerCase())) continue;
  const text = read(workflow);
  for (const match of text.matchAll(/^\s*uses:\s*([^\s#]+)(?:\s+#.*)?$/gm)) {
    const reference = match[1];
    if (reference === "./.github/workflows/firebat2-verify.yml") continue;
    const separator = reference.lastIndexOf("@");
    if (separator < 1 || !/^[0-9a-f]{40}$/.test(reference.slice(separator + 1))) {
      fail(workflow, `action is not pinned to a full commit SHA: ${reference}`);
    }
  }
  for (const match of text.matchAll(/^\s*image:\s*([^\s#]+)(?:\s+#.*)?$/gm)) {
    if (!/@sha256:[0-9a-f]{64}$/.test(match[1])) {
      fail(workflow, `container is not pinned to an image digest: ${match[1]}`);
    }
  }
}

const migrationsDirectory = join(repositoryRoot, "database", "migrations");
const migrations = filesBelow(migrationsDirectory)
  .filter((path) => /[\\/]\d{4}_[a-z0-9_]+\.sql$/.test(path))
  .sort();
if (migrations.length === 0) {
  fail(migrationsDirectory, "no numbered migrations found");
} else {
  migrations.forEach((path, index) => {
    const expectedPrefix = String(index + 1).padStart(4, "0");
    if (!repositoryPath(path).split("/").at(-1).startsWith(`${expectedPrefix}_`)) {
      fail(path, `migration sequence is not contiguous at ${expectedPrefix}`);
    }
    const text = read(path);
    const begins = text.match(/^\s*BEGIN\s*;\s*(?:--.*)?$/gim) ?? [];
    const commits = text.match(/^\s*COMMIT\s*;\s*(?:--.*)?$/gim) ?? [];
    if (begins.length !== 1 || commits.length !== 1) {
      fail(path, "migration must own exactly one BEGIN and COMMIT");
    }
    if (!/pg_advisory_xact_lock\s*\(/i.test(text) || !/macsad:schema-migration/i.test(text)) {
      fail(path, "migration advisory-lock contract is missing");
    }
    if (!/macsad_meta\.schema_migration/i.test(text) || !/migration_sha256/i.test(text)) {
      fail(path, "migration ledger/checksum contract is missing");
    }
  });
}

if (failures.length > 0) {
  for (const failure of failures.sort()) process.stderr.write(`error: ${failure}\n`);
  process.stderr.write(`guardrails failed with ${failures.length} violation(s)\n`);
  process.exit(1);
}

process.stdout.write("guardrails passed\n");
