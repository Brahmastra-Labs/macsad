import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  EvidenceError,
  verifyManifest,
  writeManifest,
} from "../../scripts/ci/artifact-manifest.mjs";

const metadata = {
  MACSAD_SOURCE_SHA: "a".repeat(40),
  MACSAD_SOURCE_REF: "refs/heads/main",
  MACSAD_FOUNDATION_RUN_ID: "123",
  GITHUB_REPOSITORY: "Brahmastra-Labs/macsad",
  GITHUB_RUN_ID: "456",
  GITHUB_RUN_ATTEMPT: "1",
  SOURCE_DATE_EPOCH: "1700000000",
};

const projects = [
  {
    name: "admin",
    stem: "macsad_admin",
    markers: ["MaCSad", "Research work, made navigable."],
  },
  {
    name: "public-site",
    stem: "macsad_public",
    markers: ["MaCSad", "Evidence first"],
  },
];

function write(path, contents) {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, contents);
}

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), "macsad-evidence-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  write(join(root, "logs", "quality-gate.log"), "quality passed\n");
  write(join(root, "logs", "build.log"), "build passed\n");
  write(join(root, "logs", "browser-smoke.log"), "browser passed\n");
  write(
    join(root, "metadata", "stage-timings.tsv"),
    "quality-gate\t22\t300\nbundle-build\t4\t120\nbrowser-smoke\t8\t120\n",
  );
  write(join(root, "summary.md"), "# Firebat2 evidence\n");
  for (const project of projects) {
    const bundle = join(root, "bundles", project.name);
    write(join(bundle, `${project.stem}.html`), "<!doctype html><html><body><div id=\"root\"></div><script type=\"module\" src=\"./app.mjs\"></script></body></html>\n");
    write(join(bundle, `${project.stem}.js`), "export const glue = true;\n");
    write(join(bundle, `${project.stem}.mjs`), "export const boot = true;\n");
    write(join(bundle, `${project.stem}.wasm`), Buffer.from("0061736d01000000", "hex"));
    const browser = join(root, "browser", project.name);
    write(
      join(browser, "browser.log"),
      [
        "browser: Chromium 999.0.0.0",
        "loopback requests: 4",
        "observed remote page HTTP(S) requests: 0",
        "observed page WebSockets: 0",
        "observed page WebTransports: 0",
        "runtime exceptions: 0",
        "console errors: 0",
        "load failures: 0",
        "interaction: passed",
        "",
      ].join("\n"),
    );
    const reactiveState = project.name === "admin"
      ? "Draft staged in this browser only — no command was sent"
      : "Selected: Mathematics";
    write(join(browser, "dom.html"), `<html><body>${project.markers.join(" ")} ${reactiveState}</body></html>\n`);
    const interaction = project.name === "admin"
      ? {
          schema: "macsad-browser-interaction/1",
          project: "admin",
          action: "type-draft-and-click-stage-local-draft",
          inputValue: "Firebat2 interaction proof",
          assertedState: "Draft staged in this browser only — no command was sent",
          publicAdminControlCount: null,
        }
      : {
          schema: "macsad-browser-interaction/1",
          project: "public-site",
          action: "click-mathematics-filter",
          assertedState: "Selected: Mathematics",
          publicAdminControlCount: 0,
        };
    write(join(browser, "interaction.json"), `${JSON.stringify(interaction)}\n`);
    write(join(browser, "response-headers.txt"), "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n");
    write(join(browser, "screenshot.png"), Buffer.from("89504e470d0a1a0a00000000", "hex"));
    write(join(browser, "server.log"), "serving on loopback\n");
  }
  return root;
}

test("writes and re-verifies a bounded byte-level evidence manifest", (t) => {
  const root = fixture(t);
  const written = writeManifest(root, metadata);
  assert.equal(written.schema, "macsad-firebat2-artifact-manifest/1");
  assert.equal(written.files.length, 26);
  assert.match(written.bundleTreeSha256, /^[0-9a-f]{64}$/);
  assert.deepEqual(verifyManifest(root, metadata), written);
  assert.match(
    readFileSync(join(root, "artifact-manifest.sha256"), "utf8"),
    /^[0-9a-f]{64}  artifact-manifest\.json\n$/,
  );
});

test("fails when one emitted byte changes after the manifest", (t) => {
  const root = fixture(t);
  writeManifest(root, metadata);
  writeFileSync(join(root, "bundles", "admin", "macsad_admin.js"), "tampered\n");
  assert.throws(
    () => verifyManifest(root, metadata),
    (error) => error instanceof EvidenceError && error.message.includes("does not match evidence bytes"),
  );
});

test("fails closed on an extra artifact", (t) => {
  const root = fixture(t);
  write(join(root, "logs", "unreviewed.log"), "unexpected\n");
  assert.throws(
    () => writeManifest(root, metadata),
    (error) => error instanceof EvidenceError && error.message.includes("unexpected logs/unreviewed.log"),
  );
});

test("fails closed on a symbolic-link escape before hashing evidence", (t) => {
  const root = fixture(t);
  symlinkSync("quality-gate.log", join(root, "logs", "linked.log"));
  assert.throws(
    () => writeManifest(root, metadata),
    (error) =>
      error instanceof EvidenceError &&
      error.message.includes("symbolic links are forbidden in evidence: logs/linked.log"),
  );
});

test("fails closed when the public browser proof admits an admin control", (t) => {
  const root = fixture(t);
  const path = join(root, "browser", "public-site", "interaction.json");
  const interaction = JSON.parse(readFileSync(path, "utf8"));
  interaction.publicAdminControlCount = 1;
  writeFileSync(path, `${JSON.stringify(interaction)}\n`);
  assert.throws(
    () => writeManifest(root, metadata),
    (error) =>
      error instanceof EvidenceError &&
      error.message.includes("did not prove filtering and the absent admin surface"),
  );
});

test("fails closed when a Firebat2 stage exceeds its exact speed budget", (t) => {
  const root = fixture(t);
  writeFileSync(
    join(root, "metadata", "stage-timings.tsv"),
    "quality-gate\t301\t300\nbundle-build\t4\t120\nbrowser-smoke\t8\t120\n",
  );
  assert.throws(
    () => writeManifest(root, metadata),
    (error) =>
      error instanceof EvidenceError &&
      error.message.includes("quality-gate: recorded execution exceeded its 300s budget"),
  );
});

test("fails closed when stage timing order changes", (t) => {
  const root = fixture(t);
  writeFileSync(
    join(root, "metadata", "stage-timings.tsv"),
    "bundle-build\t4\t120\nquality-gate\t22\t300\nbrowser-smoke\t8\t120\n",
  );
  assert.throws(
    () => writeManifest(root, metadata),
    (error) =>
      error instanceof EvidenceError &&
      error.message.includes("quality-gate: stage timing identity or budget drifted"),
  );
});

test("fails closed when a speed budget is silently enlarged", (t) => {
  const root = fixture(t);
  writeFileSync(
    join(root, "metadata", "stage-timings.tsv"),
    "quality-gate\t22\t301\nbundle-build\t4\t120\nbrowser-smoke\t8\t120\n",
  );
  assert.throws(
    () => writeManifest(root, metadata),
    (error) =>
      error instanceof EvidenceError &&
      error.message.includes("quality-gate: stage timing identity or budget drifted"),
  );
});
