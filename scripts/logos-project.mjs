#!/usr/bin/env node

import {
  createHash,
} from "node:crypto";
import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
} from "node:fs";
import {
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = resolve(scriptDirectory, "..");
export const defaultModuleManifestPath = join(
  repositoryRoot,
  "tests",
  "logos-module-manifest.json",
);

export class LogosProjectError extends Error {
  constructor(message) {
    super(message);
    this.name = "LogosProjectError";
  }
}

function stop(message) {
  throw new LogosProjectError(message);
}

export function portablePath(path) {
  return path.split(sep).join("/");
}

function relativeTo(root, path) {
  return portablePath(relative(root, path));
}

function isWithin(root, candidate) {
  return candidate === root || candidate.startsWith(`${root}${sep}`);
}

function readUtf8(path) {
  try {
    return readFileSync(path, "utf8");
  } catch (error) {
    stop(`cannot read ${path}: ${error.message}`);
  }
}

function regularFilesBelow(root) {
  const files = [];
  function walk(directory) {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const stats = lstatSync(path);
      if (stats.isSymbolicLink()) {
        stop(`symbolic links are forbidden in a LOGOS source tree: ${path}`);
      }
      if (stats.isDirectory()) {
        walk(path);
      } else if (stats.isFile()) {
        files.push(path);
      }
    }
  }
  walk(root);
  return files;
}

function tomlSection(text, sectionName) {
  const lines = text.split(/\r?\n/);
  let current = null;
  const values = new Map();
  let sectionCount = 0;
  for (const rawLine of lines) {
    const line = rawLine.replace(/\s+#.*$/, "").trim();
    if (line.length === 0) continue;
    const section = line.match(/^\[([^\]]+)\]$/);
    if (section) {
      current = section[1];
      if (current === sectionName) sectionCount += 1;
      continue;
    }
    if (current !== sectionName) continue;
    const assignment = line.match(/^([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(.+)$/);
    if (!assignment) stop(`unsupported ${sectionName} manifest line: ${rawLine}`);
    if (values.has(assignment[1])) stop(`duplicate ${sectionName}.${assignment[1]}`);
    values.set(assignment[1], assignment[2].trim());
  }
  if (sectionCount !== 1) stop(`Largo.toml must contain exactly one [${sectionName}] section`);
  return values;
}

function exactTomlString(values, key, label) {
  const raw = values.get(key);
  if (raw === undefined || !/^"[^"\r\n]+"$/.test(raw)) {
    stop(`${label} must be one exact quoted string`);
  }
  return raw.slice(1, -1);
}

export function readLargoManifest(projectDirectory) {
  const manifestPath = join(projectDirectory, "Largo.toml");
  const text = readUtf8(manifestPath);
  const sections = [...text.matchAll(/^\s*\[([^\]]+)\]\s*(?:#.*)?$/gm)].map(
    (match) => match[1],
  );
  for (const section of sections) {
    if (section !== "package" && section !== "test") {
      stop(
        `${relativeTo(repositoryRoot, manifestPath)}: [${section}] is forbidden; MaCSad LOGOS projects have no registry, Git, path, workspace, or inert manifest dependencies`,
      );
    }
  }
  if (/^\s*dependencies\s*=/m.test(text)) {
    stop(`${relativeTo(repositoryRoot, manifestPath)}: inline dependencies are forbidden`);
  }

  const packageValues = tomlSection(text, "package");
  const testValues = tomlSection(text, "test");
  const name = exactTomlString(packageValues, "name", "package.name");
  const entry = exactTomlString(packageValues, "entry", "package.entry");
  if (
    isAbsolute(entry) ||
    entry.includes("\\") ||
    !entry.startsWith("src/") ||
    !entry.endsWith(".lg") ||
    entry.split("/").includes("..")
  ) {
    stop(`${relativeTo(repositoryRoot, manifestPath)}: package.entry must be a contained src/**/*.lg path`);
  }
  if (testValues.get("skip_budget") !== "0") {
    stop(`${relativeTo(repositoryRoot, manifestPath)}: [test] skip_budget must be exactly 0`);
  }
  return { entry, manifestPath, name, text };
}

function sourceFacts(source, sourcePath, sourceRoot) {
  if (/^\s*##\s+Requires\b/m.test(source)) {
    stop(`${relativeTo(repositoryRoot, sourcePath)}: ## Requires is registry-backed and forbidden`);
  }

  const imports = [];
  const aliases = new Set();
  const targets = new Set();
  function addImport(line) {
    const match = line.match(
      /^Import ([A-Z][A-Za-z0-9_]*) from "((?:\.\.\/|\.\/)[a-z0-9_.\/-]+\.lg)"\.$/,
    );
    if (!match) {
      stop(
        `${relativeTo(repositoryRoot, sourcePath)}: imports must use exactly Import Alias from "./relative_file.lg".`,
      );
    }
    const alias = match[1];
    const literal = match[2];
    if (
      literal.includes("//") ||
      literal.includes("/./") ||
      literal.split("/").some((segment) => segment.length === 0)
    ) {
      stop(`${relativeTo(repositoryRoot, sourcePath)}: import path is not canonical: ${literal}`);
    }
    const unresolvedTarget = resolve(dirname(sourcePath), literal);
    const relativeTarget = portablePath(relative(dirname(sourcePath), unresolvedTarget));
    const canonicalLiteral = relativeTarget.startsWith("../")
      ? relativeTarget
      : `./${relativeTarget}`;
    if (literal !== canonicalLiteral) {
      stop(
        `${relativeTo(repositoryRoot, sourcePath)}: import path is not canonical; use ${canonicalLiteral}`,
      );
    }
    if (!isWithin(sourceRoot, unresolvedTarget)) {
      stop(`${relativeTo(repositoryRoot, sourcePath)}: import escapes src/: ${literal}`);
    }
    if (!existsSync(unresolvedTarget) || !lstatSync(unresolvedTarget).isFile()) {
      stop(`${relativeTo(repositoryRoot, sourcePath)}: import does not resolve to a file: ${literal}`);
    }
    if (lstatSync(unresolvedTarget).isSymbolicLink()) {
      stop(`${relativeTo(repositoryRoot, sourcePath)}: imported symbolic links are forbidden`);
    }
    const target = realpathSync(unresolvedTarget);
    if (!isWithin(sourceRoot, target) || extname(target) !== ".lg") {
      stop(`${relativeTo(repositoryRoot, sourcePath)}: import must resolve to a contained .lg file`);
    }
    if (aliases.has(alias)) {
      stop(`${relativeTo(repositoryRoot, sourcePath)}: duplicate import alias ${alias}`);
    }
    if (targets.has(target)) {
      stop(`${relativeTo(repositoryRoot, sourcePath)}: duplicate import target ${literal}`);
    }
    aliases.add(alias);
    targets.add(target);
    imports.push({ alias, literal, target });
  }

  const lines = source.split(/\r?\n/);
  const firstContent = lines.findIndex((line) => line.trim().length > 0);
  if (firstContent < 0 || !/^# [^#\r\n].*$/.test(lines[firstContent].trim())) {
    stop(`${relativeTo(repositoryRoot, sourcePath)}: first nonempty line must be one # Module title`);
  }
  const otherTitles = lines
    .map((line, index) => ({ index, line: line.trim() }))
    .filter(({ index, line }) => index !== firstContent && /^# [^#\r\n].*$/.test(line));
  if (otherTitles.length > 0) {
    stop(`${relativeTo(repositoryRoot, sourcePath)}: module must contain exactly one # title`);
  }

  const firstSection = lines.findIndex(
    (line, index) => index > firstContent && line.trim().startsWith("## "),
  );
  const abstractEnd = firstSection < 0 ? lines.length : firstSection;
  for (let index = firstContent + 1; index < abstractEnd; index += 1) {
    const line = lines[index].trim();
    if (/(?<!!)\[[^\]\r\n]+\]\([^)\r\n]+\)/.test(line)) {
      stop(
        `${relativeTo(repositoryRoot, sourcePath)}: Markdown-link imports are forbidden; use one explicit relative Import per line`,
      );
    }
  }

  let cursor = firstContent + 1;
  while (cursor < lines.length && lines[cursor].trim().length === 0) cursor += 1;
  if (cursor < lines.length && /^import\b/i.test(lines[cursor].trim())) {
    while (cursor < lines.length && lines[cursor].trim().length > 0) {
      const line = lines[cursor].trim();
      if (!/^import\b/i.test(line)) {
        stop(
          `${relativeTo(repositoryRoot, sourcePath)}: the first abstract paragraph must contain only explicit Import lines`,
        );
      }
      addImport(line);
      cursor += 1;
    }
  }
  for (; cursor < lines.length; cursor += 1) {
    if (/^import\b/i.test(lines[cursor].trim())) {
      stop(
        `${relativeTo(repositoryRoot, sourcePath)}: Import appears outside the compiler-scanned first abstract paragraph`,
      );
    }
  }

  const tests = [...source.matchAll(/^## Test: ([^\r\n]+?)[ \t]*\r?$/gm)].map(
    (match) => match[1],
  );
  if (new Set(tests).size !== tests.length) {
    stop(`${relativeTo(repositoryRoot, sourcePath)}: duplicate ## Test names`);
  }
  const malformedTests = source.match(/^## Test(?::)?[^\r\n]*$/gm) ?? [];
  if (malformedTests.length !== tests.length) {
    stop(`${relativeTo(repositoryRoot, sourcePath)}: every test header must be ## Test: <unique prose name>`);
  }
  const mainCount = (source.match(/^## Main[ \t]*\r?$/gm) ?? []).length;
  const sectionCount = (source.match(/^## [^\r\n]+/gm) ?? []).length;
  if (sectionCount === 0) {
    stop(`${relativeTo(repositoryRoot, sourcePath)}: module contributes no LOGOS section`);
  }
  return { imports, mainCount, tests };
}

function validateProjectRegistration(registration) {
  if (!registration || typeof registration !== "object" || Array.isArray(registration)) {
    stop("each LOGOS project registration must be an object");
  }
  if (typeof registration.name !== "string" || !/^[a-z][a-z0-9-]*$/.test(registration.name)) {
    stop("each LOGOS project needs a stable lowercase name");
  }
  if (
    typeof registration.directory !== "string" ||
    !/^logos\/[a-z][a-z0-9-]*$/.test(registration.directory)
  ) {
    stop(`${String(registration.name)}.directory must be one direct child of logos/`);
  }
  if (
    typeof registration.entry !== "string" ||
    !/^src\/(?:[a-z0-9_-]+\/)*[a-z0-9_-]+\.lg$/.test(registration.entry)
  ) {
    stop(`${registration.name}.entry must be a canonical src/**/*.lg path`);
  }
  if (
    typeof registration.logicalRoot !== "string" ||
    !/^src\/(?:[a-z0-9_-]+\/)*[a-z0-9_-]+\.lg$/.test(registration.logicalRoot) ||
    registration.logicalRoot === registration.entry
  ) {
    stop(`${registration.name}.logicalRoot must name one non-entry src/**/*.lg module`);
  }
  if (registration.entryClosureLock !== "pinned-transitive-scope-workaround") {
    stop(
      `${registration.name}.entryClosureLock must explicitly acknowledge the pinned transitive-scope workaround`,
    );
  }
  if (!Array.isArray(registration.allowedDiagnostics)) {
    stop(`${registration.name}.allowedDiagnostics must be an explicit array`);
  }
  if (typeof registration.domBundle !== "boolean") {
    stop(`${registration.name}.domBundle must be a boolean`);
  }
  if (!Array.isArray(registration.testLeaves) || registration.testLeaves.length === 0) {
    stop(`${registration.name}.testLeaves must be nonempty`);
  }
}

export function loadModuleManifest(path = defaultModuleManifestPath) {
  let manifest;
  try {
    manifest = JSON.parse(readUtf8(path));
  } catch (error) {
    if (error instanceof LogosProjectError) throw error;
    stop(`${path}: invalid JSON: ${error.message}`);
  }
  if (manifest.schema !== "macsad-logos-module-manifest/1") {
    stop(`${path}: unsupported module manifest schema`);
  }
  if (
    manifest.seed !== 7 ||
    manifest.tiers !== "all" ||
    manifest.proveFiniteProperties !== true
  ) {
    stop(`${path}: seed, tiers, and proof settings must remain exact`);
  }
  if (!Array.isArray(manifest.projects) || manifest.projects.length === 0) {
    stop(`${path}: projects must be nonempty`);
  }
  const names = new Set();
  const directories = new Set();
  for (const registration of manifest.projects) {
    validateProjectRegistration(registration);
    if (names.has(registration.name)) stop(`${path}: duplicate project name ${registration.name}`);
    if (directories.has(registration.directory)) {
      stop(`${path}: duplicate project directory ${registration.directory}`);
    }
    names.add(registration.name);
    directories.add(registration.directory);
  }
  return manifest;
}

export function inspectProject(registration, root = repositoryRoot) {
  validateProjectRegistration(registration);
  const projectDirectory = resolve(root, registration.directory);
  const expectedProjectDirectory = join(root, ...registration.directory.split("/"));
  if (projectDirectory !== expectedProjectDirectory || !existsSync(projectDirectory)) {
    stop(`${registration.name}: project directory is missing or escaped the repository`);
  }
  if (lstatSync(projectDirectory).isSymbolicLink()) {
    stop(`${registration.name}: project directory cannot be a symbolic link`);
  }
  const projectRoot = realpathSync(projectDirectory);
  const sourceDirectory = join(projectRoot, "src");
  if (!existsSync(sourceDirectory) || !lstatSync(sourceDirectory).isDirectory()) {
    stop(`${registration.name}: src/ directory is missing`);
  }
  if (lstatSync(sourceDirectory).isSymbolicLink()) {
    stop(`${registration.name}: src/ cannot be a symbolic link`);
  }
  const sourceRoot = realpathSync(sourceDirectory);
  const largo = readLargoManifest(projectRoot);
  if (largo.entry !== registration.entry) {
    stop(
      `${registration.name}: module manifest entry ${registration.entry} does not match Largo.toml ${largo.entry}`,
    );
  }
  const entryPath = realpathSync(join(projectRoot, ...registration.entry.split("/")));
  if (!isWithin(sourceRoot, entryPath)) stop(`${registration.name}: entry escaped src/`);

  const allSourceFiles = regularFilesBelow(sourceRoot)
    .filter((path) => extname(path) === ".lg")
    .map((path) => realpathSync(path));
  if (allSourceFiles.length === 0) stop(`${registration.name}: src/ has no .lg files`);

  const factByPath = new Map();
  for (const path of allSourceFiles) {
    factByPath.set(path, sourceFacts(readUtf8(path), path, sourceRoot));
  }

  const state = new Map();
  const stack = [];
  const postorder = [];
  function visit(path) {
    const current = state.get(path) ?? 0;
    if (current === 2) return;
    if (current === 1) {
      const cycleStart = stack.indexOf(path);
      const cycle = [...stack.slice(cycleStart), path]
        .map((item) => relativeTo(projectRoot, item))
        .join(" -> ");
      stop(`${registration.name}: import cycle is forbidden: ${cycle}`);
    }
    const facts = factByPath.get(path);
    if (!facts) stop(`${registration.name}: import reached an unregistered non-.lg source`);
    state.set(path, 1);
    stack.push(path);
    for (const edge of facts.imports) visit(edge.target);
    stack.pop();
    state.set(path, 2);
    postorder.push(path);
  }
  visit(entryPath);

  const reachable = new Set(postorder);
  const orphans = allSourceFiles.filter((path) => !reachable.has(path));
  if (orphans.length > 0) {
    stop(
      `${registration.name}: orphan/decorative .lg module(s) are outside the entry import closure: ${orphans
        .map((path) => relativeTo(projectRoot, path))
        .sort()
        .join(", ")}`,
    );
  }

  const entryFacts = factByPath.get(entryPath);
  if (entryFacts.mainCount !== 1) {
    stop(`${registration.name}: entry must contain exactly one ## Main`);
  }
  for (const path of allSourceFiles) {
    if (path !== entryPath && factByPath.get(path).mainCount !== 0) {
      stop(`${registration.name}: imported module has a hidden ## Main: ${relativeTo(projectRoot, path)}`);
    }
  }

  const nonEntryPaths = allSourceFiles.filter((path) => path !== entryPath);
  const entryTargets = new Set(entryFacts.imports.map((edge) => edge.target));
  const missingEntryLocks = nonEntryPaths.filter((path) => !entryTargets.has(path));
  const unexpectedEntryLocks = [...entryTargets].filter((path) => path === entryPath);
  if (
    missingEntryLocks.length > 0 ||
    entryTargets.size !== nonEntryPaths.length ||
    unexpectedEntryLocks.length > 0
  ) {
    stop(
      `${registration.name}: pinned compiler scope workaround requires the entry to import every non-entry module exactly once; missing ${missingEntryLocks
        .map((path) => relativeTo(projectRoot, path))
        .sort()
        .join(", ") || "none"}`,
    );
  }

  const entryAliases = new Set(entryFacts.imports.map((edge) => edge.alias));
  const diagnosticIdentities = new Set();
  for (const diagnostic of registration.allowedDiagnostics) {
    if (!diagnostic || typeof diagnostic !== "object" || Array.isArray(diagnostic)) {
      stop(`${registration.name}: each allowed diagnostic must be an object`);
    }
    const identity = JSON.stringify(diagnostic);
    if (diagnosticIdentities.has(identity)) {
      stop(`${registration.name}: duplicate allowed diagnostic identity`);
    }
    diagnosticIdentities.add(identity);
    const message =
      typeof diagnostic.message === "string"
        ? diagnostic.message.match(/^`Import ([A-Z][A-Za-z0-9_]*)` is unused — no name from it is referenced here\.$/)
        : null;
    if (
      diagnostic.code !== "unused-import" ||
      diagnostic.severity !== "warning" ||
      diagnostic.file !== registration.entry ||
      !message ||
      !entryAliases.has(message[1])
    ) {
      stop(
        `${registration.name}: only an exact entry-level unused compatibility import warning may be allowlisted`,
      );
    }
  }

  const logicalRootPath = realpathSync(
    join(projectRoot, ...registration.logicalRoot.split("/")),
  );
  if (logicalRootPath === entryPath || !factByPath.has(logicalRootPath)) {
    stop(`${registration.name}: logicalRoot is missing from src/`);
  }
  const logicalState = new Map();
  const logicalStack = [];
  const logicalReachable = new Set();
  function visitLogical(path) {
    if (path === entryPath) {
      stop(`${registration.name}: a logical module imports the entry`);
    }
    const current = logicalState.get(path) ?? 0;
    if (current === 2) return;
    if (current === 1) {
      const cycleStart = logicalStack.indexOf(path);
      const cycle = [...logicalStack.slice(cycleStart), path]
        .map((item) => relativeTo(projectRoot, item))
        .join(" -> ");
      stop(`${registration.name}: logical import cycle is forbidden: ${cycle}`);
    }
    logicalState.set(path, 1);
    logicalStack.push(path);
    logicalReachable.add(path);
    for (const edge of factByPath.get(path).imports) visitLogical(edge.target);
    logicalStack.pop();
    logicalState.set(path, 2);
  }
  visitLogical(logicalRootPath);
  const logicalOrphans = nonEntryPaths.filter((path) => !logicalReachable.has(path));
  if (logicalOrphans.length > 0) {
    stop(
      `${registration.name}: module(s) are present only through the compatibility entry lock, not the logical graph rooted at ${registration.logicalRoot}: ${logicalOrphans
        .map((path) => relativeTo(projectRoot, path))
        .sort()
        .join(", ")}`,
    );
  }

  const leafRegistrations = new Map();
  for (const leaf of registration.testLeaves) {
    if (!leaf || typeof leaf !== "object" || Array.isArray(leaf)) {
      stop(`${registration.name}: each test leaf registration must be an object`);
    }
    if (
      typeof leaf.path !== "string" ||
      !/^src\/(?:[a-z0-9_-]+\/)*[a-z0-9_-]+\.lg$/.test(leaf.path)
    ) {
      stop(`${registration.name}: test leaf path must be canonical src/**/*.lg`);
    }
    if (leafRegistrations.has(leaf.path)) {
      stop(`${registration.name}: duplicate test leaf ${leaf.path}`);
    }
    if (!Array.isArray(leaf.expectedTests) || leaf.expectedTests.length === 0) {
      stop(`${registration.name}:${leaf.path}: expectedTests must be nonempty`);
    }
    if (
      leaf.expectedTests.some(
        (name) => typeof name !== "string" || name.length === 0 || name.trim() !== name,
      ) ||
      new Set(leaf.expectedTests).size !== leaf.expectedTests.length
    ) {
      stop(`${registration.name}:${leaf.path}: expectedTests must be unique exact prose names`);
    }
    if (!Number.isSafeInteger(leaf.minimumProperties) || leaf.minimumProperties < 1) {
      stop(`${registration.name}:${leaf.path}: minimumProperties must be at least 1`);
    }
    if (!Number.isSafeInteger(leaf.minimumProven) || leaf.minimumProven < 1) {
      stop(`${registration.name}:${leaf.path}: minimumProven must be at least 1`);
    }
    leafRegistrations.set(leaf.path, leaf);
  }

  const globalTestNames = new Map();
  const suites = [];
  for (const path of allSourceFiles) {
    const sourcePath = relativeTo(projectRoot, path);
    const facts = factByPath.get(path);
    const leaf = leafRegistrations.get(sourcePath);
    if (facts.tests.length > 0 && !leaf) {
      stop(
        `${registration.name}: tests in ${sourcePath} would be invisible to the leaf runner; register that import-free leaf`,
      );
    }
    if (leaf && facts.tests.length === 0) {
      stop(`${registration.name}: registered test leaf has no tests: ${sourcePath}`);
    }
    if (!leaf) continue;
    if (facts.imports.length !== 0) {
      stop(`${registration.name}: test-bearing module must be an import-free leaf: ${sourcePath}`);
    }
    if (facts.mainCount !== 0) {
      stop(`${registration.name}: test-bearing leaf must not contain ## Main: ${sourcePath}`);
    }
    const actualTests = [...facts.tests].sort((left, right) => left.localeCompare(right, "en"));
    const expectedTests = [...leaf.expectedTests].sort((left, right) =>
      left.localeCompare(right, "en"),
    );
    if (JSON.stringify(actualTests) !== JSON.stringify(expectedTests)) {
      stop(
        `${registration.name}:${sourcePath}: static test inventory drift; expected ${JSON.stringify(expectedTests)}, found ${JSON.stringify(actualTests)}`,
      );
    }
    for (const name of actualTests) {
      if (globalTestNames.has(name)) {
        stop(
          `${registration.name}: test name ${JSON.stringify(name)} is duplicated in ${globalTestNames.get(name)} and ${sourcePath}`,
        );
      }
      globalTestNames.set(name, sourcePath);
    }
    suites.push({ ...leaf, absolutePath: path });
  }
  for (const path of leafRegistrations.keys()) {
    if (!allSourceFiles.some((file) => relativeTo(projectRoot, file) === path)) {
      stop(`${registration.name}: registered test leaf does not exist: ${path}`);
    }
  }

  const closureHash = createHash("sha256");
  const closure = [...allSourceFiles].sort((left, right) =>
    relativeTo(projectRoot, left).localeCompare(relativeTo(projectRoot, right), "en"),
  );
  for (const path of closure) {
    const sourcePath = relativeTo(projectRoot, path);
    closureHash.update(sourcePath, "utf8");
    closureHash.update("\0");
    closureHash.update(readFileSync(path));
    closureHash.update("\0");
  }

  return {
    closure: closure.map((path) => relativeTo(projectRoot, path)),
    closureDigest: closureHash.digest("hex"),
    entryPath,
    largo,
    postorder: postorder.map((path) => relativeTo(projectRoot, path)),
    projectDirectory: projectRoot,
    registration,
    suites,
  };
}

export function inspectRegisteredProjects(manifest, root = repositoryRoot) {
  const projects = manifest.projects.map((registration) => inspectProject(registration, root));
  const logosDirectory = join(root, "logos");
  if (!existsSync(logosDirectory) || !lstatSync(logosDirectory).isDirectory()) {
    stop("repository logos/ directory is missing");
  }
  if (lstatSync(logosDirectory).isSymbolicLink()) {
    stop("repository logos/ directory cannot be a symbolic link");
  }

  const logosRoot = realpathSync(logosDirectory);
  const repositoryLogosFiles = regularFilesBelow(logosRoot);
  const actualSources = repositoryLogosFiles
    .filter((path) => extname(path) === ".lg")
    .map((path) => realpathSync(path));
  const registeredSources = projects.flatMap((project) =>
    project.closure.map((path) =>
      realpathSync(join(project.projectDirectory, ...path.split("/"))),
    ),
  );
  const registeredSourceSet = new Set(registeredSources);
  const unregisteredSources = actualSources.filter((path) => !registeredSourceSet.has(path));
  if (
    unregisteredSources.length > 0 ||
    registeredSourceSet.size !== registeredSources.length ||
    registeredSourceSet.size !== actualSources.length
  ) {
    stop(
      `every repository .lg file must belong to exactly one registered production closure; unregistered ${unregisteredSources
        .map((path) => relativeTo(root, path))
        .sort()
        .join(", ") || "none"}`,
    );
  }

  const actualManifests = repositoryLogosFiles
    .filter((path) => path.endsWith(`${sep}Largo.toml`))
    .map((path) => realpathSync(path));
  const registeredManifests = new Set(
    projects.map((project) => realpathSync(project.largo.manifestPath)),
  );
  const unregisteredManifests = actualManifests.filter(
    (path) => !registeredManifests.has(path),
  );
  if (
    unregisteredManifests.length > 0 ||
    registeredManifests.size !== actualManifests.length
  ) {
    stop(
      `every LOGOS Largo.toml must belong to exactly one registered project; unregistered ${unregisteredManifests
        .map((path) => relativeTo(root, path))
        .sort()
        .join(", ") || "none"}`,
    );
  }
  return projects;
}

function main() {
  const command = process.argv[2];
  const manifest = loadModuleManifest();
  if (command === "projects") {
    for (const project of manifest.projects) process.stdout.write(`${project.directory}\n`);
    return;
  }
  if (command === "dom-projects") {
    for (const project of manifest.projects) {
      if (project.domBundle) process.stdout.write(`${project.directory}\n`);
    }
    return;
  }
  if (command === "audit") {
    for (const project of inspectRegisteredProjects(manifest)) {
      process.stdout.write(
        `${project.registration.name}: ${project.closure.length} reachable module(s), ${project.suites.length} exact leaf suite(s), closure sha256 ${project.closureDigest}\n`,
      );
    }
    return;
  }
  stop("usage: node scripts/logos-project.mjs {audit|projects|dom-projects}");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`error: ${error.message}\n`);
    process.exit(1);
  }
}
