import assert from "node:assert/strict";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { inspectProject, inspectRegisteredProjects } from "../../scripts/logos-project.mjs";
import { stagePageSuite, verifyPageOutcomes } from "../../scripts/logos-pages.mjs";

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "macsad-page-guard-"));
  const project = join(root, "logos/fixture");
  const write = (path, text) => { const target = join(project, path); mkdirSync(dirname(target), { recursive: true }); writeFileSync(target, text); };
  write("Largo.toml", '[package]\nname = "fixture"\nversion = "0.1.0"\nentry = "src/main.lg"\n\n[test]\nskip_budget = 0\n');
  write("src/main.lg", '# Server\n\nImport App from "./app.lg".\nImport Policy from "./policy.lg".\n\n## Main\nShow 1.\n');
  write("src/app.lg", '# App\n\nImport Policy from "./policy.lg".\n\n## To value () -> Int:\n    Return 1.\n');
  write("src/policy.lg", '# Policy\n\n## Test: Policy is total\n    For all booleans value:\n        Expect that value is equal to value.\n');
  const pageSource = '# App\n\nImport App from "../src/app.lg".\n\n## Page /\nView:\n    <p id="message">ready</p>\n\n## Test: Page shows ready\nExpect that the text of "#message" is equal to "ready".\n';
  write("pages/app.lg", pageSource);
  const registration = { name: "fixture", directory: "logos/fixture", entry: "src/main.lg", logicalRoot: "src/app.lg",
    entryClosureLock: "pinned-transitive-scope-workaround", allowedDiagnostics: [], domBundle: false,
    testLeaves: [{ path: "src/policy.lg", expectedTests: ["Policy is total"], minimumProperties: 1, minimumProven: 1 }],
    pageSuites: [{ path: "pages/app.lg", expectedTests: ["Page shows ready", "Policy is total"], mountedTests: ["Page shows ready"], minimumProperties: 1, minimumProven: 1 }],
  };
  return { root, project, write, pageSource, registration, inspect: () => inspectProject(registration, root),
    cleanup: () => rmSync(root, { recursive: true }) };
}
function withFixture(body) { const f = fixture(); try { body(f); } finally { f.cleanup(); } }

test("Page closure adds exact inventory without changing source leaf rules", () => withFixture((f) => {
  const inspected = f.inspect();
  assert.deepEqual(inspected.closure, ["pages/app.lg", "src/app.lg", "src/main.lg", "src/policy.lg"]);
  assert.equal(inspected.suites[0].kind, undefined);
  assert.deepEqual(inspected.suites[1].expectedTests, ["pages/app.lg › Page shows ready", "pages/app.lg › Policy is total"]);
  assert.deepEqual(inspected.suites[1].copies.map((x) => x.path), ["pages/app.lg", "src/app.lg", "src/policy.lg"]);
  assert.equal(inspectRegisteredProjects({ projects: [f.registration] }, f.root).length, 1);
}));

test("unregistered Page and incorrect transitive test inventory are refused", () => withFixture((f) => {
  const saved = f.registration.pageSuites;
  delete f.registration.pageSuites;
  assert.throws(f.inspect, /every Page/);
  f.registration.pageSuites = saved;
  saved[0].expectedTests.pop();
  assert.throws(f.inspect, /inventory drift/);
}));

test("duplicate Page and undeclared mounted test registrations are refused", () => withFixture((f) => {
  f.registration.pageSuites.push({ ...f.registration.pageSuites[0] });
  assert.throws(f.inspect, /duplicate Page/);
  f.registration.pageSuites.pop();
  f.registration.pageSuites[0].mountedTests.push("Absent");
  assert.throws(f.inspect, /subset/);
}));

test("a Page cannot import the server entry or another Page", () => withFixture((f) => {
  f.write("pages/app.lg", f.pageSource.replace('../src/app.lg', '../src/main.lg'));
  assert.throws(f.inspect, /server entry/);
  f.write("pages/other.lg", '# Other\n\n## Page /other\nView:\n    <p>other</p>\n');
  f.write("pages/app.lg", f.pageSource.replace('../src/app.lg', './other.lg'));
  assert.throws(f.inspect, /registered src/);
}));

test("nested pages and symbolic links cannot evade direct-page inventory", () => withFixture((f) => {
  f.write("pages/nested/hidden.lg", f.pageSource);
  assert.throws(f.inspect, /direct regular/);
  rmSync(join(f.project, "pages/nested"), { recursive: true });
  symlinkSync(join(f.project, "pages/app.lg"), join(f.project, "pages/alias.lg"));
  assert.throws(f.inspect, /direct regular/);
}));

test("Page and leaf thresholds remain separate: zero UI properties is explicit", () => withFixture((f) => {
  f.registration.pageSuites[0].minimumProperties = 0;
  f.registration.pageSuites[0].minimumProven = 0;
  f.inspect();
  f.registration.testLeaves[0].minimumProperties = 0;
  assert.throws(f.inspect, /at least 1/);
}));

test("Page sources contribute to production closure identity", () => withFixture((f) => {
  const before = f.inspect().closureDigest;
  f.write("pages/app.lg", f.pageSource.replace('ready</p>', 'changed</p>'));
  assert.notEqual(f.inspect().closureDigest, before);
}));

test("Page staging is an exact independent copy with no backend entry", () => withFixture((f) => {
  const suite = f.inspect().suites[1];
  const destination = join(f.root, "staged");
  mkdirSync(destination);
  stagePageSuite(suite, destination);
  assert.equal(existsSync(join(destination, "src/main.lg")), false);
  assert.doesNotMatch(readFileSync(join(destination, "Largo.toml"), "utf8"), /entry\s*=/);
  for (const source of suite.copies) {
    const copy = join(destination, source.path);
    assert.deepEqual(readFileSync(copy), readFileSync(source.absolutePath));
    assert.equal(lstatSync(copy).nlink, 1);
    assert.equal(lstatSync(source.absolutePath).nlink, 1);
    assert.notEqual(lstatSync(copy).ino, lstatSync(source.absolutePath).ino);
  }
}));

test("Page staging refuses source changes after inspection", () => withFixture((f) => {
  const suite = f.inspect().suites[1];
  f.write("src/policy.lg", readFileSync(join(f.project, "src/policy.lg"), "utf8") + '\n');
  const destination = join(f.root, "staged");
  mkdirSync(destination);
  assert.throws(() => stagePageSuite(suite, destination), /changed after inspection/);
}));

test("Page reports require mounted controls and agreed nonvacuous outcomes", () => withFixture((f) => {
  const suite = f.inspect().suites[1];
  const outcomes = suite.expectedTests.map((name, i) => ({ name, mounted: i === 0, vacuous: false, tier: "agreed" }));
  verifyPageOutcomes(suite, outcomes);
  for (const mutation of [{ mounted: false }, { vacuous: true }, { tier: undefined }, { tier: { refused: { reason: "unsupported" } } }]) {
    assert.throws(() => verifyPageOutcomes(suite, [{ ...outcomes[0], ...mutation }, outcomes[1]]));
  }
  verifyPageOutcomes(f.inspect().suites[0], [{ name: "legacy" }]);
}));


test("Page-only src helpers need no decorative backend import", () => withFixture((f) => {
  f.write("src/page_dto.lg", '# DTO\n\n## A Answer has:\n    a id, which is Text.\n');
  f.write("pages/app.lg", f.pageSource.replace('Import App from "../src/app.lg".', 'Import Dto from "../src/page_dto.lg".'));
  f.registration.pageSuites[0].expectedTests = ["Page shows ready"];
  const inspected = f.inspect();
  assert.ok(inspected.closure.includes("src/page_dto.lg"));
  assert.equal(inspected.postorder.includes("src/page_dto.lg"), false);
  assert.deepEqual(inspected.suites[1].copies.map((x) => x.path), ["pages/app.lg", "src/page_dto.lg"]);
}));

test("Page-only source cycles and hidden Main remain rejected", () => withFixture((f) => {
  f.write("src/page_dto.lg", '# DTO\n\nImport Other from "./page_other.lg".\n\n## A Answer has:\n    a id, which is Text.\n');
  f.write("src/page_other.lg", '# Other\n\nImport Dto from "./page_dto.lg".\n\n## A More has:\n    a id, which is Text.\n');
  f.write("pages/app.lg", f.pageSource.replace('Import App from "../src/app.lg".', 'Import Dto from "../src/page_dto.lg".'));
  f.registration.pageSuites[0].expectedTests = ["Page shows ready"];
  assert.throws(f.inspect, /cycle/);
  f.write("src/page_other.lg", '# Other\n\n## Main\nShow 1.\n');
  assert.throws(f.inspect, /hidden ## Main/);
}));


test("unknown Page metadata and malformed paths fail closed", () => withFixture((f) => {
  const page = f.registration.pageSuites[0];
  page.browserPassed = true;
  assert.throws(f.inspect, /unknown Page/);
  delete page.browserPassed;
  page.path = "pages/../pages/app.lg";
  assert.throws(f.inspect, /canonical/);
}));
