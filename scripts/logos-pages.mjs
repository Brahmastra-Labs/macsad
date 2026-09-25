import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";

const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const portable = (path) => path.split(sep).join("/");
const reject = (message) => { throw new Error(message); };

function names(values, label, stop) {
  if (!Array.isArray(values) || values.length === 0 || values.some((value) =>
    typeof value !== "string" || !value || value.trim() !== value) ||
    new Set(values).size !== values.length) stop(`${label}: expected unique nonempty exact names`);
  return [...values].sort();
}

// Preserve the existing src graph contract; Pages are separate CLI closure roots.
export function inspectPages({ registration, projectRoot, entryPath, factByPath, sourceFacts, stop = reject }) {
  const registered = registration.pageSuites ?? [];
  if (!Array.isArray(registered)) stop("pageSuites must be an array");
  const pagesDirectory = join(projectRoot, "pages");
  const actual = [];
  if (existsSync(pagesDirectory)) {
    const info = lstatSync(pagesDirectory);
    if (info.isSymbolicLink() || !info.isDirectory()) stop("pages/ must be a real directory");
    for (const name of readdirSync(pagesDirectory).sort()) {
      const info = lstatSync(join(pagesDirectory, name));
      if (info.isSymbolicLink() || info.isDirectory()) stop("pages/ must contain direct regular files only");
      if (name.endsWith(".lg")) actual.push(`pages/${name}`);
    }
  }
  const inventory = new Set();
  const suites = [];
  for (const page of registered) {
    if (!page || !/^pages\/[a-z0-9_-]+\.lg$/.test(page.path ?? "")) stop("Page path must be canonical pages/*.lg");
    const allowed = ["path", "expectedTests", "mountedTests", "minimumProperties", "minimumProven"];
    if (Array.isArray(page) || Object.keys(page).some((key) => !allowed.includes(key))) stop("unknown Page suite registration field");
    if (inventory.has(page.path)) stop(`duplicate Page registration: ${page.path}`);
    inventory.add(page.path);
    if (!actual.includes(page.path)) stop(`registered Page does not exist: ${page.path}`);
    const expected = names(page.expectedTests, `${page.path}.expectedTests`, stop);
    const mounted = names(page.mountedTests, `${page.path}.mountedTests`, stop);
    if (mounted.some((name) => !expected.includes(name))) stop("mountedTests must be an exact expectedTests subset");
    for (const key of ["minimumProperties", "minimumProven"]) {
      if (!Number.isSafeInteger(page[key]) || page[key] < 0) stop(`${page.path}.${key} must be a nonnegative safe integer`);
    }
    const absolutePath = join(projectRoot, page.path);
    const source = readFileSync(absolutePath, "utf8");
    if ((source.match(/^## Page(?:[ \t]+[^\r\n]+)?[ \t]*\r?$/gm) ?? []).length !== 1) {
      stop(`${page.path} must contain exactly one Page`);
    }
    const pageFacts = sourceFacts(source, absolutePath, projectRoot);
    if (pageFacts.mainCount !== 0) stop("Page must not contain Main");
    const files = new Set([absolutePath]);
    const tests = [...pageFacts.tests];
    const state = new Map();
    const pending = pageFacts.imports.map((edge) => ({ path: edge.target, exit: false }));
    while (pending.length) {
      const { path, exit } = pending.pop();
      if (exit) { state.set(path, 2); continue; }
      if (path === entryPath) stop("Page closure must not import the server entry");
      if (!factByPath.has(path)) stop("Page imports must resolve to registered src modules");
      if (state.get(path) === 1) stop("Page source import cycle is forbidden");
      if (state.get(path) === 2) continue;
      const text = readFileSync(path, "utf8");
      if (/^## Page\b/m.test(text)) stop("Page closure contains a second Page");
      files.add(path);
      state.set(path, 1);
      const facts = factByPath.get(path);
      tests.push(...facts.tests);
      pending.push({ path, exit: true });
      pending.push(...facts.imports.map((edge) => ({ path: edge.target, exit: false })));
    }
    if (JSON.stringify(names(tests, `${page.path} closure tests`, stop)) !== JSON.stringify(expected)) {
      stop(`${page.path}: static Page test inventory drift`);
    }
    const copies = [...files].sort().map((path) => ({
      path: portable(relative(projectRoot, path)), absolutePath: path, sha256: digest(readFileSync(path)),
    }));
    suites.push({ ...page, kind: "page", absolutePath, copies,
      expectedTests: page.expectedTests.map((name) => `${page.path} › ${name}`),
      mountedTests: page.mountedTests.map((name) => `${page.path} › ${name}`),
    });
  }
  if (actual.some((path) => !inventory.has(path))) stop("every Page must have an exact pageSuites registration");
  return { files: actual.map((path) => join(projectRoot, path)), suites };
}

export function stagePageSuite(suite, destination) {
  for (const source of suite.copies) {
    const original = lstatSync(source.absolutePath);
    if (!original.isFile() || original.isSymbolicLink()) reject("Page closure source is no longer a regular file");
    const bytes = readFileSync(source.absolutePath);
    if (digest(bytes) !== source.sha256) reject("Page closure changed after inspection");
    const target = join(destination, source.path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, bytes, { flag: "wx" });
    const copy = lstatSync(target);
    if (copy.nlink !== 1 || (copy.dev === original.dev && copy.ino === original.ino) ||
      digest(readFileSync(target)) !== source.sha256) reject("Page staging must be an independent exact byte copy");
  }
  if (existsSync(join(destination, "src/main.lg"))) reject("Page staging would run an unintended default entry");
  writeFileSync(join(destination, "Largo.toml"),
    '[package]\nname = "macsad_page_test"\nversion = "0.1.0"\nauthors = []\n\n[test]\nskip_budget = 0\n',
    { flag: "wx" });
}

// Additional Page-only obligations; the caller retains every existing outcome/count/proof check.
export function verifyPageOutcomes(suite, outcomes) {
  if (suite.kind !== "page") return;
  for (const outcome of outcomes) {
    if (typeof outcome.mounted !== "boolean" || outcome.vacuous !== false || outcome.tier !== "agreed") {
      reject(`Page outcome needs nonvacuous agreed-tier evidence: ${outcome.name}`);
    }
    if (suite.mountedTests.includes(outcome.name) && outcome.mounted !== true) {
      reject(`declared UI control did not mount a Page: ${outcome.name}`);
    }
  }
}
