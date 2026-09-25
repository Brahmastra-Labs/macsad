import assert from "node:assert/strict";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { selectTestRunner } from "../../scripts/logos-test-runner.mjs";

const root = "/private/example/macsad";
const sha = "a".repeat(64);
function status() {
  const source = { files: 1, bytes: 5, members: ["apps/cli"], source_inventory_sha256: sha };
  return { schema: "macsad-logos-built-candidate/1", mode: "development-built-candidate",
    release_admitted: false, source_binary_correspondence: "local-build-evidence",
    candidate: "/private/example/candidate", workspace: "/private/example/candidate/repo",
    binary_sha256: sha, source_inventory_sha256: sha,
    snapshot_binary: `${root}/.runtime/logos-directory/largo-${sha}`,
    evidence_sha256: Object.fromEntries(["copy.json", "binary.json", "source-inputs.json", "largo-build.command.json"].map(name => [name, sha])),
    source_at_connection: source, source_now: structuredClone(source) };
}
function result(value = status()) { return { status: 0, signal: null, stdout: JSON.stringify(value), stderr: "" }; }
function fixture(reply = () => result()) {
  const calls = [], output = [];
  const runner = selectTestRunner(["--development-candidate"], root, {
    spawn(command, args, options) { calls.push({ command, args, options }); return reply(); },
    write(line) { output.push(line); },
  });
  return { calls, output, runner };
}

test("default has only the admitted wrapper, irrespective of development environment", () => {
  const before = process.env.MACSAD_DEVELOPMENT_CANDIDATE;
  process.env.MACSAD_DEVELOPMENT_CANDIDATE = "1";
  try {
    const runner = selectTestRunner([], root, { spawn() { assert.fail("default must not inspect development status"); }, write() { assert.fail("default output changed"); } });
    assert.deepEqual(runner.prefix, [`${root}/scripts/logos.sh`]);
    runner.verifyBeforeRun();
  } finally { if (before === undefined) delete process.env.MACSAD_DEVELOPMENT_CANDIDATE; else process.env.MACSAD_DEVELOPMENT_CANDIDATE = before; }
});

test("unknown, repeated, positional and combined arguments refuse before any process", () => {
  for (const args of [["--other"], ["--development-candidate", "--development-candidate"], ["candidate"], ["--development-candidate", "extra"]]) {
    assert.throws(() => selectTestRunner(args, root, { spawn() { assert.fail("unknown arguments started process"); } }), /arguments/);
  }
});

test("explicit selection validates status and records exact local nonadmitted identity", () => {
  const f = fixture();
  assert.deepEqual(f.runner.prefix, [`${root}/scripts/dev.sh`, "logos"]);
  assert.deepEqual(f.calls[0].args, [`${root}/scripts/dev.sh`, "logos-status"]);
  assert.equal(f.calls[0].command, "bash");
  assert.equal(f.calls[0].options.cwd, root);
  const identity = JSON.parse(f.output[0].slice("LOGOS development candidate: ".length));
  assert.equal(identity.release_admitted, false);
  assert.equal(identity.binary_sha256, sha);
  assert.equal(identity.source_inventory_sha256, sha);
  assert.equal(identity.source_binary_correspondence, "local-build-evidence");
  f.runner.verifyBeforeRun();
  assert.equal(f.calls.length, 2);
});

test("directory mode, false provenance and malformed candidate status are refused", () => {
  for (const change of [
    s => { s.schema = "macsad-logos-directory/1"; }, s => { s.mode = "development-directory"; },
    s => { s.release_admitted = true; }, s => { s.source_binary_correspondence = "unverified"; },
    s => { s.binary_sha256 = "bad"; }, s => { s.workspace += "/wrong"; },
    s => { s.snapshot_binary = "/tmp/elsewhere"; }, s => { delete s.evidence_sha256["copy.json"]; },
    s => { s.evidence_sha256["source-inputs.json"] = "b".repeat(64); },
    s => { s.source_now.bytes++; }, s => { s.source_now = null; }, s => { s.unexpected = true; },
  ]) { const value = status(); change(value); assert.throws(() => fixture(() => result(value)), /status/); }
});

test("failed, signalled, noisy, invalid JSON or unavailable status fails closed", () => {
  for (const value of [{ ...result(), status: 1 }, { ...result(), signal: "TERM" },
    { ...result(), stderr: "warning" }, { ...result(), stdout: "not JSON" },
    { error: new Error("missing"), status: null, signal: null }, result(null)]) {
    assert.throws(() => fixture(() => value), /status/);
  }
});

test("reconnection cannot silently switch identity between project invocations", () => {
  let value = status();
  const f = fixture(() => result(value));
  value = status(); value.evidence_sha256["copy.json"] = "b".repeat(64);
  assert.throws(() => f.runner.verifyBeforeRun(), /changed/);
});


test("actual verifier CLI rejects an unknown flag before loading projects or running LOGOS", () => {
  const script = fileURLToPath(new URL("../../scripts/verify-logos-tests.mjs", import.meta.url));
  const response = spawnSync(process.execPath, [script, "--not-a-real-option"], { encoding: "utf8" });
  assert.equal(response.status, 1);
  assert.equal(response.stdout, "");
  assert.match(response.stderr, /unsupported LOGOS test arguments/);
});
