#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, posix, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

export class EvidenceError extends Error {}

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..", "..");
const defaultContractPath = join(repositoryRoot, "tests", "browser-smoke-contract.json");
const toolchainLockPath = join(repositoryRoot, ".macsad", "toolchains", "logos.lock.toml");
const excludedManifestFiles = new Set(["artifact-manifest.json", "artifact-manifest.sha256"]);
const expectedBundleExtensions = ["html", "js", "mjs", "wasm"];
const expectedBrowserFiles = ["browser.log", "dom.html", "interaction.json", "response-headers.txt", "screenshot.png", "server.log"];
const maximumFileBytes = 100 * 1024 * 1024;
const maximumTreeBytes = 250 * 1024 * 1024;
const expectedStageBudgets = [
  ["quality-gate", 300],
  ["bundle-build", 120],
  ["browser-smoke", 120],
];

function stop(message) {
  throw new EvidenceError(message);
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    stop(`${path}: invalid JSON: ${error.message}`);
  }
}

function isWithin(root, candidate) {
  return candidate === root || candidate.startsWith(`${root}${sep}`);
}

function canonicalRoot(path) {
  const absolute = resolve(path);
  if (!existsSync(absolute)) stop(`evidence root does not exist: ${absolute}`);
  if (!lstatSync(absolute).isDirectory() || lstatSync(absolute).isSymbolicLink()) {
    stop(`evidence root must be a real directory: ${absolute}`);
  }
  const canonical = realpathSync(absolute);
  if (canonical !== absolute) stop(`evidence root must already be canonical: ${absolute}`);
  return canonical;
}

function regularFilesBelow(root) {
  const files = [];
  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      const relativePath = relative(root, path).split(sep).join("/");
      if (!/^[A-Za-z0-9._/-]+$/.test(relativePath) || relativePath.includes("//")) {
        stop(`unsafe evidence path: ${relativePath}`);
      }
      const details = lstatSync(path);
      if (details.isSymbolicLink()) stop(`symbolic links are forbidden in evidence: ${relativePath}`);
      if (details.isDirectory()) {
        visit(path);
      } else if (details.isFile()) {
        files.push(path);
      } else {
        stop(`non-regular evidence entry is forbidden: ${relativePath}`);
      }
    }
  }
  visit(root);
  return files;
}

export function loadBrowserContract(path = defaultContractPath) {
  const contract = readJson(path);
  if (contract.schema !== "macsad-browser-smoke-contract/1") {
    stop(`${path}: unsupported contract schema`);
  }
  if (!Array.isArray(contract.projects) || contract.projects.length === 0) {
    stop(`${path}: projects must be nonempty`);
  }
  const names = new Set();
  const directories = new Set();
  const stems = new Set();
  for (const project of contract.projects) {
    if (!project || typeof project !== "object" || Array.isArray(project)) {
      stop(`${path}: each project must be an object`);
    }
    if (typeof project.name !== "string" || !/^[a-z][a-z0-9-]*$/.test(project.name)) {
      stop(`${path}: project name is not canonical`);
    }
    if (
      typeof project.directory !== "string" ||
      !/^logos\/[a-z][a-z0-9-]*$/.test(project.directory)
    ) {
      stop(`${path}: ${String(project.name)} has an unsafe LOGOS directory`);
    }
    if (typeof project.bundleStem !== "string" || !/^[a-z][a-z0-9_]*$/.test(project.bundleStem)) {
      stop(`${path}: ${String(project.name)} has an unsafe bundle stem`);
    }
    if (
      !Array.isArray(project.expectedText) ||
      project.expectedText.length < 2 ||
      project.expectedText.some(
        (value) =>
          typeof value !== "string" ||
          value.trim() !== value ||
          value.length < 3 ||
          /[\u0000-\u001f]/.test(value),
      ) ||
      new Set(project.expectedText).size !== project.expectedText.length
    ) {
      stop(`${path}: ${String(project.name)} needs at least two unique visible-text assertions`);
    }
    if (names.has(project.name) || directories.has(project.directory) || stems.has(project.bundleStem)) {
      stop(`${path}: browser projects, directories, and stems must be unique`);
    }
    names.add(project.name);
    directories.add(project.directory);
    stems.add(project.bundleStem);
  }
  return contract;
}

function readToolchainLock() {
  const source = readFileSync(toolchainLockPath, "utf8");
  function value(section, key, pattern) {
    const sectionMatch = source.match(new RegExp(`\\[${section}\\]([\\s\\S]*?)(?=\\n\\[|$)`));
    if (!sectionMatch) stop(`toolchain lock omitted [${section}]`);
    const keyMatch = sectionMatch[1].match(new RegExp(`^${key}\\s*=\\s*"([^"]+)"\\s*$`, "m"));
    if (!keyMatch || !pattern.test(keyMatch[1])) {
      stop(`toolchain lock has invalid ${section}.${key}`);
    }
    return keyMatch[1];
  }
  return {
    repository: value("source", "repository", /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/),
    version: value("source", "version", /^\d+\.\d+\.\d+$/),
    commit: value("source", "commit", /^[0-9a-f]{40}$/),
    tree: value("source", "tree", /^[0-9a-f]{40}$/),
    cargoLockSha256: value("source", "cargo_lock_sha256", /^[0-9a-f]{64}$/),
    binarySha256: value("runtime", "observed_binary_sha256", /^[0-9a-f]{64}$/),
  };
}

function expectedPaths(contract) {
  const paths = new Set([
    "logs/browser-smoke.log",
    "logs/build.log",
    "logs/quality-gate.log",
    "metadata/run.json",
    "metadata/stage-timings.tsv",
    "summary.md",
  ]);
  for (const project of contract.projects) {
    for (const extension of expectedBundleExtensions) {
      paths.add(`bundles/${project.name}/${project.bundleStem}.${extension}`);
    }
    for (const file of expectedBrowserFiles) paths.add(`browser/${project.name}/${file}`);
  }
  return paths;
}

function assertStageTimings(root) {
  const source = readFileSync(join(root, "metadata", "stage-timings.tsv"), "utf8");
  const lines = source.endsWith("\n") ? source.slice(0, -1).split("\n") : [];
  if (lines.length !== expectedStageBudgets.length) {
    stop("stage timing evidence must contain exactly three ordered stages and a final newline");
  }
  for (let index = 0; index < expectedStageBudgets.length; index += 1) {
    const [expectedStage, expectedBudget] = expectedStageBudgets[index];
    const match = lines[index].match(/^([a-z][a-z0-9-]*)\t(0|[1-9][0-9]*)\t([1-9][0-9]*)$/);
    if (!match || match[1] !== expectedStage || Number(match[3]) !== expectedBudget) {
      stop(`${expectedStage}: stage timing identity or budget drifted`);
    }
    if (!Number.isSafeInteger(Number(match[2])) || Number(match[2]) > expectedBudget) {
      stop(`${expectedStage}: recorded execution exceeded its ${expectedBudget}s budget`);
    }
  }
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function assertBundleAndBrowserEvidence(root, contract) {
  for (const project of contract.projects) {
    const bundleRoot = join(root, "bundles", project.name);
    const browserRoot = join(root, "browser", project.name);
    const wasm = readFileSync(join(bundleRoot, `${project.bundleStem}.wasm`));
    if (wasm.length < 8 || !wasm.subarray(0, 4).equals(Buffer.from([0x00, 0x61, 0x73, 0x6d]))) {
      stop(`${project.name}: emitted .wasm lacks the WebAssembly magic header`);
    }
    const html = readFileSync(join(bundleRoot, `${project.bundleStem}.html`), "utf8");
    if (!/<html\b/i.test(html) || !/<body\b/i.test(html)) {
      stop(`${project.name}: emitted HTML lacks html/body structure`);
    }
    if (/\b(?:src|href)\s*=\s*["'](?:https?:)?\/\//i.test(html)) {
      stop(`${project.name}: emitted HTML contains a remote resource URL`);
    }
    const dom = readFileSync(join(browserRoot, "dom.html"), "utf8");
    for (const marker of project.expectedText) {
      if (!dom.includes(marker)) stop(`${project.name}: browser DOM omitted ${JSON.stringify(marker)}`);
    }
    const browserLog = readFileSync(join(browserRoot, "browser.log"), "utf8");
    if (/(?:uncaught|compileerror|runtimeerror|failed to load resource|net::err_|webassembly.{0,80}(?:fail|error))/i.test(browserLog)) {
      stop(`${project.name}: browser log contains a runtime/load failure`);
    }
    for (const marker of [
      "observed remote page HTTP(S) requests: 0",
      "observed page WebSockets: 0",
      "observed page WebTransports: 0",
      "runtime exceptions: 0",
      "console errors: 0",
      "load failures: 0",
      "interaction: passed",
    ]) {
      if (!browserLog.split(/\r?\n/).includes(marker)) {
        stop(`${project.name}: browser log omitted required evidence ${JSON.stringify(marker)}`);
      }
    }
    const interaction = readJson(join(browserRoot, "interaction.json"));
    if (interaction.schema !== "macsad-browser-interaction/1" || interaction.project !== project.name) {
      stop(`${project.name}: browser interaction evidence has the wrong identity`);
    }
    if (typeof interaction.assertedState !== "string" || !dom.includes(interaction.assertedState)) {
      stop(`${project.name}: browser DOM does not contain the claimed post-interaction state`);
    }
    if (project.name === "admin") {
      if (
        interaction.action !== "type-draft-and-click-stage-local-draft" ||
        interaction.inputValue !== "Firebat2 interaction proof" ||
        interaction.assertedState !== "Draft staged in this browser only — no command was sent"
      ) {
        stop("admin: browser interaction did not prove the reactive local-draft state");
      }
    } else if (
      interaction.action !== "click-mathematics-filter" ||
      interaction.assertedState !== "Selected: Mathematics" ||
      interaction.publicAdminControlCount !== 0
    ) {
      stop("public-site: browser interaction did not prove filtering and the absent admin surface");
    }
    const headers = readFileSync(join(browserRoot, "response-headers.txt"), "utf8");
    if (!/^HTTP\/\S+ 200\b/m.test(headers)) stop(`${project.name}: static entry did not return HTTP 200`);
    const screenshot = readFileSync(join(browserRoot, "screenshot.png"));
    if (screenshot.length < 8 || !screenshot.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex"))) {
      stop(`${project.name}: browser screenshot is not a PNG`);
    }
  }
}

function normalizedMetadata(metadata = process.env) {
  const sourceSha = metadata.MACSAD_SOURCE_SHA;
  const sourceRef = metadata.MACSAD_SOURCE_REF;
  const foundationRunId = metadata.MACSAD_FOUNDATION_RUN_ID;
  const repository = metadata.GITHUB_REPOSITORY;
  const runId = metadata.GITHUB_RUN_ID;
  const runAttempt = metadata.GITHUB_RUN_ATTEMPT;
  const sourceDateEpoch = metadata.SOURCE_DATE_EPOCH;
  if (!/^[0-9a-f]{40}$/.test(sourceSha ?? "")) stop("MACSAD_SOURCE_SHA must be a full Git SHA");
  if (sourceRef !== "refs/heads/main") stop("MACSAD_SOURCE_REF must be refs/heads/main");
  for (const [label, value] of [
    ["MACSAD_FOUNDATION_RUN_ID", foundationRunId],
    ["GITHUB_RUN_ID", runId],
    ["GITHUB_RUN_ATTEMPT", runAttempt],
    ["SOURCE_DATE_EPOCH", sourceDateEpoch],
  ]) {
    if (
      !/^[1-9][0-9]*$/.test(value ?? "") ||
      !Number.isSafeInteger(Number(value))
    ) stop(`${label} must be a positive safe integer`);
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? "")) {
    stop("GITHUB_REPOSITORY must be an owner/name identity");
  }
  return {
    repository,
    sourceSha,
    sourceRef,
    sourceDateEpoch: Number(sourceDateEpoch),
    foundationRunId: Number(foundationRunId),
    githubRunId: Number(runId),
    githubRunAttempt: Number(runAttempt),
  };
}

export function buildManifest(rootPath, metadata = process.env, contractPath = defaultContractPath) {
  const root = canonicalRoot(rootPath);
  const contract = loadBrowserContract(contractPath);
  const admitted = normalizedMetadata(metadata);
  const runMetadataPath = join(root, "metadata", "run.json");
  mkdirSync(dirname(runMetadataPath), { recursive: true, mode: 0o700 });
  const runMetadata = {
    schema: "macsad-firebat2-run/1",
    ...admitted,
    logos: readToolchainLock(),
  };
  writeFileSync(runMetadataPath, `${JSON.stringify(runMetadata, null, 2)}\n`, { mode: 0o600 });

  const allowedPaths = expectedPaths(contract);
  const files = regularFilesBelow(root)
    .map((path) => ({ path, relativePath: relative(root, path).split(sep).join("/") }))
    .filter(({ relativePath }) => !excludedManifestFiles.has(relativePath))
    .sort((left, right) => left.relativePath.localeCompare(right.relativePath, "en"));
  const actualPaths = new Set(files.map(({ relativePath }) => relativePath));
  const missing = [...allowedPaths].filter((path) => !actualPaths.has(path));
  const unexpected = [...actualPaths].filter((path) => !allowedPaths.has(path));
  if (missing.length > 0 || unexpected.length > 0 || actualPaths.size !== files.length) {
    stop(`evidence shape drift; missing ${missing.join(", ") || "none"}; unexpected ${unexpected.join(", ") || "none"}`);
  }

  let totalBytes = 0;
  const records = files.map(({ path, relativePath }) => {
    const details = statSync(path);
    if (details.size <= 0 || details.size > maximumFileBytes) {
      stop(`${relativePath}: evidence file size is outside the admitted range`);
    }
    totalBytes += details.size;
    return { path: relativePath, bytes: details.size, sha256: sha256(readFileSync(path)) };
  });
  if (totalBytes > maximumTreeBytes) stop("evidence tree exceeds 250 MiB");
  assertStageTimings(root);
  assertBundleAndBrowserEvidence(root, contract);

  const bundleRecords = records.filter((record) => record.path.startsWith("bundles/"));
  const recordLine = (record) => `${record.sha256}  ${record.bytes}  ${record.path}\n`;
  return {
    schema: "macsad-firebat2-artifact-manifest/1",
    source: admitted,
    logos: readToolchainLock(),
    bundleTreeSha256: sha256(bundleRecords.map(recordLine).join("")),
    evidenceTreeSha256: sha256(records.map(recordLine).join("")),
    totalBytes,
    files: records,
  };
}

export function writeManifest(rootPath, metadata = process.env, contractPath = defaultContractPath) {
  const root = canonicalRoot(rootPath);
  const manifest = buildManifest(root, metadata, contractPath);
  const manifestPath = join(root, "artifact-manifest.json");
  const serialized = `${JSON.stringify(manifest, null, 2)}\n`;
  writeFileSync(manifestPath, serialized, { mode: 0o600 });
  writeFileSync(join(root, "artifact-manifest.sha256"), `${sha256(serialized)}  artifact-manifest.json\n`, { mode: 0o600 });
  return manifest;
}

export function verifyManifest(rootPath, metadata = process.env, contractPath = defaultContractPath) {
  const root = canonicalRoot(rootPath);
  const expected = buildManifest(root, metadata, contractPath);
  const actual = readJson(join(root, "artifact-manifest.json"));
  if (JSON.stringify(actual) !== JSON.stringify(expected)) stop("artifact manifest does not match evidence bytes");
  const serialized = `${JSON.stringify(actual, null, 2)}\n`;
  const checksum = readFileSync(join(root, "artifact-manifest.sha256"), "utf8");
  if (checksum !== `${sha256(serialized)}  artifact-manifest.json\n`) {
    stop("artifact manifest checksum does not match");
  }
  return actual;
}

function printProjects() {
  for (const project of loadBrowserContract().projects) {
    process.stdout.write(`${project.name}\t${project.directory}\t${project.bundleStem}\n`);
  }
}

function main() {
  const [command, root] = process.argv.slice(2);
  if (command === "projects" && !root) return printProjects();
  if ((command !== "write" && command !== "verify") || !root || process.argv.length !== 4) {
    stop("usage: node scripts/ci/artifact-manifest.mjs {projects|write ROOT|verify ROOT}");
  }
  const manifest = command === "write" ? writeManifest(root) : verifyManifest(root);
  process.stdout.write(`${manifest.evidenceTreeSha256}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`error: ${error.message}\n`);
    process.exit(1);
  }
}
