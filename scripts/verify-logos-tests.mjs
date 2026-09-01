#!/usr/bin/env node

import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const manifestPath = join(repositoryRoot, "tests", "logos-test-manifest.json");
const logosWrapper = join(repositoryRoot, "scripts", "logos.sh");

function fail(message) {
  process.stderr.write(`error: ${message}\n`);
  process.exit(1);
}

function requireInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail(`${label} must be a nonnegative safe integer`);
  }
}

function sortedUniqueStrings(values, label) {
  if (!Array.isArray(values) || values.length === 0) {
    fail(`${label} must be a nonempty array`);
  }
  if (values.some((value) => typeof value !== "string" || value.length === 0)) {
    fail(`${label} must contain nonempty strings`);
  }
  const sorted = [...values].sort((left, right) => left.localeCompare(right, "en"));
  if (new Set(sorted).size !== sorted.length) {
    fail(`${label} contains a duplicate`);
  }
  return sorted;
}

let manifest;
try {
  manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
} catch (error) {
  fail(`cannot read ${manifestPath}: ${error.message}`);
}

if (manifest.schema !== "macsad-logos-test-manifest/1") {
  fail("unsupported LOGOS test manifest schema");
}
requireInteger(manifest.seed, "manifest.seed");
if (manifest.seed !== 7 || manifest.tiers !== "all" || manifest.proveFiniteProperties !== true) {
  fail("test manifest must require seed 7, all tiers, and finite-property proof mode");
}
if (!Array.isArray(manifest.projects) || manifest.projects.length === 0) {
  fail("test manifest has no projects");
}

const projectNames = new Set();
for (const project of manifest.projects) {
  if (!project || typeof project !== "object" || Array.isArray(project)) {
    fail("each project manifest entry must be an object");
  }
  if (typeof project.name !== "string" || !/^[a-z][a-z0-9-]*$/.test(project.name)) {
    fail("each project needs a stable lowercase name");
  }
  if (projectNames.has(project.name)) {
    fail(`duplicate project name: ${project.name}`);
  }
  projectNames.add(project.name);
  if (typeof project.directory !== "string" || !/^logos\/[a-z][a-z0-9-]*$/.test(project.directory)) {
    fail(`${project.name}.directory must be one direct child of logos/`);
  }
  const expectedNames = sortedUniqueStrings(
    project.expectedTests,
    `${project.name}.expectedTests`,
  );
  requireInteger(project.minimumProperties, `${project.name}.minimumProperties`);
  requireInteger(project.minimumProven, `${project.name}.minimumProven`);
  if (typeof project.domBundle !== "boolean") {
    fail(`${project.name}.domBundle must be a boolean`);
  }

  const projectDirectory = join(repositoryRoot, project.directory);
  let testProjectDirectory = projectDirectory;
  let temporaryProject = null;
  if (project.testMode !== undefined && project.testMode !== "strip-server-main") {
    fail(`${project.name}.testMode is unsupported`);
  }
  if (project.testMode === "strip-server-main") {
    const sourcePath = join(projectDirectory, "src", "main.lg");
    const source = readFileSync(sourcePath, "utf8");
    const serverMain = /\n## Main\r?\nServe on port 18081 with handle\.\s*$/;
    if (!serverMain.test(source) || (source.match(/## Main/g) ?? []).length !== 1) {
      fail(`${project.name}: test wrapper expected exactly the reviewed port-18081 server Main`);
    }
    temporaryProject = mkdtempSync(join(tmpdir(), "macsad-logos-tests-"));
    mkdirSync(join(temporaryProject, "src"), { recursive: true });
    copyFileSync(join(projectDirectory, "Largo.toml"), join(temporaryProject, "Largo.toml"));
    writeFileSync(join(temporaryProject, "src", "main.lg"), source.replace(serverMain, "\n"));
    testProjectDirectory = temporaryProject;
  }
  const result = spawnSync(
    "bash",
    [
      logosWrapper,
      "test",
      "--seed",
      String(manifest.seed),
      "--format",
      "json",
      "--prove",
      "--tiers",
      manifest.tiers,
      "--color",
      "never",
    ],
    {
      cwd: testProjectDirectory,
      env: process.env,
      encoding: "utf8",
      maxBuffer: 16 * 1024 * 1024,
    },
  );
  if (temporaryProject !== null) {
    rmSync(temporaryProject, { recursive: true, force: true });
  }

  if (result.error) {
    fail(`${project.name}: could not start largo: ${result.error.message}`);
  }
  if (result.status !== 0) {
    if (result.stdout) process.stderr.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    fail(`${project.name}: largo test exited ${String(result.status)}`);
  }
  if (result.signal !== null) {
    fail(`${project.name}: largo test terminated on ${result.signal}`);
  }

  let report;
  try {
    report = JSON.parse(result.stdout);
  } catch (error) {
    if (result.stderr) process.stderr.write(result.stderr);
    fail(`${project.name}: stdout was not one JSON report: ${error.message}`);
  }

  requireInteger(report.seed, `${project.name}.report.seed`);
  requireInteger(report.passed, `${project.name}.report.passed`);
  requireInteger(report.failed, `${project.name}.report.failed`);
  requireInteger(report.skipped, `${project.name}.report.skipped`);
  requireInteger(report.properties, `${project.name}.report.properties`);
  requireInteger(report.proven, `${project.name}.report.proven`);
  if (report.seed !== manifest.seed) {
    fail(`${project.name}: runner reported seed ${report.seed}, expected ${manifest.seed}`);
  }
  if (!Array.isArray(report.outcomes) || report.outcomes.length === 0) {
    fail(`${project.name}: zero tests were discovered`);
  }

  const actualNames = sortedUniqueStrings(
    report.outcomes.map((outcome) => outcome?.name),
    `${project.name}.reported test names`,
  );
  if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
    fail(
      `${project.name}: test identity drift; expected ${JSON.stringify(expectedNames)}, received ${JSON.stringify(actualNames)}`,
    );
  }
  if (
    report.passed !== expectedNames.length ||
    report.failed !== 0 ||
    report.skipped !== 0 ||
    report.outcomes.length !== expectedNames.length
  ) {
    fail(
      `${project.name}: expected ${expectedNames.length} passed, 0 failed, 0 skipped; received ${report.passed} passed, ${report.failed} failed, ${report.skipped} skipped`,
    );
  }
  for (const outcome of report.outcomes) {
    if (
      outcome.verdict !== "passed" ||
      !Array.isArray(outcome.failures) ||
      outcome.failures.length !== 0 ||
      outcome.skip_reason !== null ||
      !Number.isSafeInteger(outcome.ops) ||
      outcome.ops < 0
    ) {
      fail(`${project.name}: malformed or non-passing outcome for ${String(outcome.name)}`);
    }
  }
  if (report.properties < project.minimumProperties) {
    fail(`${project.name}: expected at least ${project.minimumProperties} exercised properties`);
  }
  if (report.proven < project.minimumProven) {
    fail(`${project.name}: expected at least ${project.minimumProven} proved properties`);
  }
  if (report.proven > report.properties) {
    fail(`${project.name}: proved property count exceeds exercised property count`);
  }

  process.stdout.write(
    `LOGOS tests: ${project.name}: ${report.passed} passed, 0 failed, 0 skipped, ${report.proven} proved\n`,
  );
}
