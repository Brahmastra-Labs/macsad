import { isAbsolute, join, normalize } from "node:path";
import { spawnSync } from "node:child_process";

const SHA256 = /^[0-9a-f]{64}$/;
const EVIDENCE = ["binary.json", "copy.json", "largo-build.command.json", "source-inputs.json"];
const STATUS = ["schema", "mode", "release_admitted", "source_binary_correspondence", "candidate", "workspace",
  "binary_sha256", "source_inventory_sha256", "snapshot_binary", "evidence_sha256", "source_at_connection", "source_now"];
function keys(value, expected) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...expected].sort());
}
function sha(value) { return typeof value === "string" && SHA256.test(value); }
function absolute(value) { return typeof value === "string" && isAbsolute(value) && normalize(value) === value; }
function source(value, inventory) {
  return keys(value, ["files", "bytes", "members", "source_inventory_sha256"])
    && Number.isSafeInteger(value.files) && value.files > 0 && value.files <= 100000
    && Number.isSafeInteger(value.bytes) && value.bytes >= 0 && value.bytes <= 1000000000
    && value.source_inventory_sha256 === inventory
    && Array.isArray(value.members) && value.members.length > 0
    && value.members.every(member => typeof member === "string" && member.length > 0
      && !isAbsolute(member) && !member.split("/").some(part => ["", ".", ".."].includes(part)))
    && new Set(value.members).size === value.members.length;
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}
function fingerprint(value) { return JSON.stringify(canonical(value)); }
function readStatus(root, spawn) {
  const result = spawn("bash", [join(root, "scripts", "dev.sh"), "logos-status"], {
    cwd: root, env: process.env, encoding: "utf8", maxBuffer: 1024 * 1024,
  });
  if (result.error || result.status !== 0 || result.signal !== null || typeof result.stderr !== "string" || result.stderr.trim()) {
    throw new Error("development candidate status failed or produced unexpected diagnostics");
  }
  let value;
  try { value = JSON.parse(result.stdout); } catch { throw new Error("development candidate status is not one JSON record"); }
  if (!keys(value, STATUS) || value.schema !== "macsad-logos-built-candidate/1"
    || value.mode !== "development-built-candidate" || value.release_admitted !== false
    || value.source_binary_correspondence !== "local-build-evidence"
    || !absolute(value.candidate) || value.workspace !== join(value.candidate, "repo")
    || !sha(value.binary_sha256) || !sha(value.source_inventory_sha256)
    || value.snapshot_binary !== join(root, ".runtime", "logos-directory", `largo-${value.binary_sha256}`)
    || !keys(value.evidence_sha256, EVIDENCE) || !Object.values(value.evidence_sha256).every(sha)
    || value.evidence_sha256["source-inputs.json"] !== value.source_inventory_sha256
    || !source(value.source_at_connection, value.source_inventory_sha256)
    || !source(value.source_now, value.source_inventory_sha256)
    || fingerprint(value.source_now) !== fingerprint(value.source_at_connection)) {
    throw new Error("development candidate status is not a verified local build connection");
  }
  return value;
}

// The quality gate supplies no arguments and therefore cannot select a local
// candidate via environment variables. The CLI flag is a separate dev action.
export function selectTestRunner(args, root, { spawn = spawnSync, write = line => process.stdout.write(line) } = {}) {
  if (args.length === 0) return { prefix: [join(root, "scripts", "logos.sh")], verifyBeforeRun() {} };
  if (args.length !== 1 || args[0] !== "--development-candidate") throw new Error("unsupported LOGOS test arguments; expected no arguments or --development-candidate");
  const identity = readStatus(root, spawn);
  const original = fingerprint(identity);
  write(`LOGOS development candidate: ${JSON.stringify(identity)}\n`);
  return {
    prefix: [join(root, "scripts", "dev.sh"), "logos"],
    verifyBeforeRun() {
      if (fingerprint(readStatus(root, spawn)) !== original) throw new Error("development candidate identity changed during verification; restart explicitly");
    },
  };
}
