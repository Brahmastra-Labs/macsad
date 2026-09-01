#!/usr/bin/env node

import {
  linkSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import {
  inspectRegisteredProjects,
  loadModuleManifest,
  portablePath,
} from "./logos-project.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
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
  if (new Set(sorted).size !== sorted.length) fail(`${label} contains a duplicate`);
  return sorted;
}

function runLogos(projectName, cwd, arguments_) {
  const result = spawnSync("bash", [logosWrapper, ...arguments_], {
    cwd,
    env: process.env,
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) fail(`${projectName}: could not start largo: ${result.error.message}`);
  if (result.status !== 0 || result.signal !== null) {
    if (result.stdout) process.stderr.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    fail(
      `${projectName}: largo exited ${String(result.status)} with signal ${String(result.signal)}`,
    );
  }
  return result;
}

let manifest;
let projects;
try {
  manifest = loadModuleManifest();
  projects = inspectRegisteredProjects(manifest, repositoryRoot);
} catch (error) {
  fail(error.message);
}

for (const project of projects) {
  const projectName = project.registration.name;
  const check = runLogos(projectName, project.projectDirectory, [
    "check",
    "--quiet",
    "--json",
    "--color",
    "never",
  ]);
  let checkReport;
  try {
    checkReport = JSON.parse(check.stdout);
  } catch (error) {
    if (check.stderr) process.stderr.write(check.stderr);
    fail(`${projectName}: check stdout was not one JSON envelope: ${error.message}`);
  }
  if (
    checkReport.schema !== "logos-check/1" ||
    checkReport.ok !== true ||
    !Array.isArray(checkReport.diagnostics)
  ) {
    fail(`${projectName}: malformed or non-green logos-check/1 envelope`);
  }
  const actualDiagnostics = checkReport.diagnostics.map((diagnostic) => {
    if (
      !diagnostic ||
      typeof diagnostic !== "object" ||
      typeof diagnostic.file !== "string" ||
      typeof diagnostic.code !== "string" ||
      typeof diagnostic.severity !== "string" ||
      typeof diagnostic.message !== "string"
    ) {
      fail(`${projectName}: malformed compiler diagnostic`);
    }
    const diagnosticPath = resolve(project.projectDirectory, diagnostic.file);
    const sourcePath = portablePath(relative(project.projectDirectory, diagnosticPath));
    if (sourcePath === ".." || sourcePath.startsWith("../")) {
      fail(`${projectName}: compiler diagnostic escaped the project: ${diagnostic.file}`);
    }
    return {
      code: diagnostic.code,
      severity: diagnostic.severity,
      file: sourcePath,
      message: diagnostic.message,
    };
  });
  const identity = (diagnostic) =>
    `${diagnostic.file}\0${diagnostic.code}\0${diagnostic.severity}\0${diagnostic.message}`;
  actualDiagnostics.sort((left, right) => identity(left).localeCompare(identity(right), "en"));
  const expectedDiagnostics = project.registration.allowedDiagnostics
    .map((diagnostic) => ({ ...diagnostic }))
    .sort((left, right) => identity(left).localeCompare(identity(right), "en"));
  if (JSON.stringify(actualDiagnostics) !== JSON.stringify(expectedDiagnostics)) {
    fail(
      `${projectName}: compiler diagnostic identity drift; expected ${JSON.stringify(expectedDiagnostics)}, received ${JSON.stringify(actualDiagnostics)}`,
    );
  }
  if (check.stderr.trim().length !== 0) {
    fail(`${projectName}: compiler wrote unexpected diagnostics to stderr: ${check.stderr.trim()}`);
  }
  process.stdout.write(
    `LOGOS closure: ${projectName}: ${project.closure.length} reachable module(s), ${actualDiagnostics.length} exact compatibility warning(s), sha256 ${project.closureDigest}\n`,
  );

  for (const suite of project.suites) {
    const suiteLabel = `${projectName}:${suite.path}`;
    const targetRoot = join(project.projectDirectory, "target");
    mkdirSync(targetRoot, { recursive: true });
    const canonicalTarget = realpathSync(targetRoot);
    const temporaryProject = mkdtempSync(join(canonicalTarget, "macsad-logos-tests-"));
    const canonicalTemporary = realpathSync(temporaryProject);
    if (!canonicalTemporary.startsWith(`${canonicalTarget}${sep}macsad-logos-tests-`)) {
      fail(`${suiteLabel}: refusing unexpected temporary project path`);
    }

    let result;
    try {
      const temporarySourceDirectory = join(canonicalTemporary, "src");
      mkdirSync(temporarySourceDirectory);
      const linkedEntry = join(temporarySourceDirectory, "main.lg");
      linkSync(suite.absolutePath, linkedEntry);
      const originalStats = statSync(suite.absolutePath);
      const linkedStats = statSync(linkedEntry);
      if (
        originalStats.dev !== linkedStats.dev ||
        originalStats.ino !== linkedStats.ino ||
        originalStats.size !== linkedStats.size
      ) {
        fail(`${suiteLabel}: temporary test entry is not the exact hard-linked source file`);
      }
      writeFileSync(
        join(canonicalTemporary, "Largo.toml"),
        `[package]\nname = "macsad_${projectName.replaceAll("-", "_")}_leaf_test"\nversion = "0.1.0"\nauthors = []\nentry = "src/main.lg"\n\n[test]\nskip_budget = 0\n`,
        { encoding: "utf8", flag: "wx" },
      );
      result = runLogos(suiteLabel, canonicalTemporary, [
        "test",
        "--quiet",
        "--seed",
        String(manifest.seed),
        "--format",
        "json",
        "--prove",
        "--tiers",
        manifest.tiers,
        "--color",
        "never",
      ]);
    } finally {
      if (!canonicalTemporary.startsWith(`${canonicalTarget}${sep}macsad-logos-tests-`)) {
        fail(`${suiteLabel}: refusing to remove unexpected temporary project path`);
      }
      rmSync(canonicalTemporary, { recursive: true });
    }

    let report;
    try {
      report = JSON.parse(result.stdout);
    } catch (error) {
      if (result.stderr) process.stderr.write(result.stderr);
      fail(`${suiteLabel}: stdout was not one JSON report: ${error.message}`);
    }

    requireInteger(report.seed, `${suiteLabel}.report.seed`);
    requireInteger(report.passed, `${suiteLabel}.report.passed`);
    requireInteger(report.failed, `${suiteLabel}.report.failed`);
    requireInteger(report.skipped, `${suiteLabel}.report.skipped`);
    requireInteger(report.properties, `${suiteLabel}.report.properties`);
    requireInteger(report.proven, `${suiteLabel}.report.proven`);
    if (report.seed !== manifest.seed) {
      fail(`${suiteLabel}: runner reported seed ${report.seed}, expected ${manifest.seed}`);
    }
    if (!Array.isArray(report.outcomes) || report.outcomes.length === 0) {
      fail(`${suiteLabel}: zero tests were discovered`);
    }

    const expectedNames = sortedUniqueStrings(suite.expectedTests, `${suiteLabel}.expectedTests`);
    const actualNames = sortedUniqueStrings(
      report.outcomes.map((outcome) => outcome?.name),
      `${suiteLabel}.reported test names`,
    );
    if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
      fail(
        `${suiteLabel}: test identity drift; expected ${JSON.stringify(expectedNames)}, received ${JSON.stringify(actualNames)}`,
      );
    }
    if (
      report.passed !== expectedNames.length ||
      report.failed !== 0 ||
      report.skipped !== 0 ||
      report.outcomes.length !== expectedNames.length
    ) {
      fail(
        `${suiteLabel}: expected ${expectedNames.length} passed, 0 failed, 0 skipped; received ${report.passed} passed, ${report.failed} failed, ${report.skipped} skipped`,
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
        fail(`${suiteLabel}: malformed or non-passing outcome for ${String(outcome.name)}`);
      }
    }
    if (report.properties < suite.minimumProperties) {
      fail(`${suiteLabel}: expected at least ${suite.minimumProperties} exercised properties`);
    }
    if (report.proven < suite.minimumProven) {
      fail(`${suiteLabel}: expected at least ${suite.minimumProven} proved properties`);
    }
    if (report.proven > report.properties) {
      fail(`${suiteLabel}: proved property count exceeds exercised property count`);
    }

    process.stdout.write(
      `LOGOS leaf tests: ${suiteLabel}: ${report.passed} passed, 0 failed, 0 skipped, ${report.proven} proved\n`,
    );
  }
}
