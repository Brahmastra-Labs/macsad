#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadBrowserContract } from "./artifact-manifest.mjs";
import { loadModuleManifest } from "../logos-project.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..", "..");

const paths = {
  foundation: ".github/workflows/foundation-ci.yml",
  ingestion: ".github/workflows/firebat2-ingestion.yml",
  reusable: ".github/workflows/firebat2-verify.yml",
  host: "ops/firebat2/verify_verifier_host.sh",
  runbook: "docs/runbooks/firebat2-verification.md",
  guardrails: "scripts/guardrails.mjs",
  builder: "scripts/ci/build-logos-evidence.sh",
  verifierHarness: "scripts/ci/firebat2-verify.sh",
  artifactManifest: "scripts/ci/artifact-manifest.mjs",
  browserProbe: "scripts/ci/browser-probe.mjs",
  actionsAudit: "scripts/ci/audit-github-actions-settings.mjs",
};

export class Firebat2ContractError extends Error {}

function activeContractText(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split(/\r?\n/)
    .filter((line) => !/^\s*(?:#|\/\/)/.test(line))
    .join("\n");
}

export function verifyFirebat2Contract(overrides = new Map()) {
  const failures = [];
  const read = (relativePath) =>
    overrides.has(relativePath)
      ? overrides.get(relativePath)
      : readFileSync(join(repositoryRoot, ...relativePath.split("/")), "utf8");
  const requirePattern = (relativePath, text, label, pattern) => {
    if (!pattern.test(activeContractText(text))) failures.push(`${relativePath}: ${label}`);
  };
  const rejectPattern = (relativePath, text, label, pattern) => {
    if (pattern.test(activeContractText(text))) failures.push(`${relativePath}: ${label}`);
  };

  const foundation = read(paths.foundation);
  requirePattern(
    paths.foundation,
    foundation,
    "Foundation workflow identity must remain exact for workflow_run ingestion",
    /^name: Foundation CI$/m,
  );
  requirePattern(
    paths.foundation,
    foundation,
    "Foundation must retain the exact unfiltered push event that feeds commit ingestion",
    /^on:\n  push:\n  pull_request:\n  workflow_dispatch:\n\npermissions:/m,
  );
  requirePattern(
    paths.foundation,
    foundation,
    "Foundation must key candidates by event and exact SHA",
    /^  group: foundation-\$\{\{ github\.workflow \}\}-\$\{\{ github\.event_name \}\}-\$\{\{ github\.sha \}\}$/m,
  );
  requirePattern(
    paths.foundation,
    foundation,
    "Foundation must not cancel an earlier commit candidate",
    /^  cancel-in-progress: false$/m,
  );
  rejectPattern(
    paths.foundation,
    foundation,
    "Foundation queue must not coalesce distinct commits by ref",
    /group: foundation-[^\n]*github\.ref/,
  );
  requirePattern(
    paths.foundation,
    foundation,
    "Foundation must fail closed within its fast ten-minute budget",
    /^    timeout-minutes: 10$/m,
  );

  const ingestion = read(paths.ingestion);
  requirePattern(paths.ingestion, ingestion, "must be triggered only by Foundation workflow_run", /^on:\n  workflow_run:\n    workflows:\n      - Foundation CI\n    types:\n      - completed$/m);
  rejectPattern(paths.ingestion, ingestion, "must not admit PR, manual, schedule, or inbound webhook events", /^  (?:pull_request|pull_request_target|push|repository_dispatch|schedule|workflow_dispatch):/m);
  rejectPattern(paths.ingestion, ingestion, "credential-free admission must not perform a second Git fetch", /\bgit fetch\b/);
  requirePattern(paths.ingestion, ingestion, "must remain disabled until the reviewed Firebat2 flag is true", /^    if: \$\{\{ vars\.FIREBAT2_ENABLED == 'true' \}\}$/m);
  requirePattern(paths.ingestion, ingestion, "must deduplicate only the same SHA without cancelling active verification", /^  group: firebat2-macsad-verification-\$\{\{ github\.event\.workflow_run\.head_sha \}\}\n  cancel-in-progress: false$/m);
  for (const [label, pattern] of [
    ["successful Foundation conclusion", /FOUNDATION_CONCLUSION.*\n[\s\S]*\[\[ "\$\{FOUNDATION_CONCLUSION\}" == 'success' \]\]/],
    ["push-only Foundation event", /\[\[ "\$\{FOUNDATION_EVENT\}" == 'push' \]\]/],
    ["exact Foundation definition path", /\[\[ "\$\{FOUNDATION_DEFINITION_PATH\}" == '\.github\/workflows\/foundation-ci\.yml' \]\]/],
    ["exact main-qualified Foundation run path", /\[\[ "\$\{FOUNDATION_RUN_PATH\}" == '\.github\/workflows\/foundation-ci\.yml@main' \]\]/],
    ["same-repository source", /\[\[ "\$\{CANDIDATE_REPOSITORY\}" == "\$\{EXPECTED_REPOSITORY\}" \]\]/],
    ["default-branch source", /\[\[ "\$\{CANDIDATE_BRANCH\}" == "\$\{DEFAULT_BRANCH\}" \]\]/],
    ["main-only default branch", /\[\[ "\$\{DEFAULT_BRANCH\}" == 'main' \]\]/],
    ["full source SHA", /CANDIDATE_SHA.*\^\[0-9a-f\]\{40\}/],
    ["exact checked-out source SHA", /git rev-parse --verify HEAD.*CANDIDATE_SHA/],
    ["only reviewed reusable workflow", /uses: \.\/\.github\/workflows\/firebat2-verify\.yml/],
  ]) requirePattern(paths.ingestion, ingestion, `missing ${label} admission`, pattern);

  const reusable = read(paths.reusable);
  requirePattern(paths.reusable, reusable, "must expose workflow_call and no direct event", /^on:\n  workflow_call:/m);
  rejectPattern(paths.reusable, reusable, "must never expose a PR, push, manual, schedule, or webhook trigger", /^  (?:pull_request|pull_request_target|push|repository_dispatch|schedule|workflow_dispatch|workflow_run):/m);
  rejectPattern(paths.reusable, reusable, "must not claim branch protection that is not configured", /Protected source ref/);
  requirePattern(paths.reusable, reusable, "must grant contents read only", /^permissions:\n  contents: read$/m);
  rejectPattern(paths.reusable, reusable, "must not reference Actions secrets", /\$\{\{\s*secrets\./);
  requirePattern(
    paths.reusable,
    reusable,
    "Firebat2 verification must fail closed within fifteen minutes",
    /^    timeout-minutes: 15$/m,
  );
  requirePattern(paths.reusable, reusable, "must use the restricted Firebat2 runner group", /^      group: macsad-firebat2$/m);
  for (const [label, pattern] of [
    ["workflow_run caller", /github\.event_name == 'workflow_run'/],
    ["successful caller", /github\.event\.workflow_run\.conclusion == 'success'/],
    ["push caller", /github\.event\.workflow_run\.event == 'push'/],
    ["Foundation definition path", /github\.event\.workflow\.path == '\.github\/workflows\/foundation-ci\.yml'/],
    ["main-qualified Foundation run path", /github\.event\.workflow_run\.path == '\.github\/workflows\/foundation-ci\.yml@main'/],
    ["main caller", /github\.event\.workflow_run\.head_branch == 'main'/],
    ["same-repository caller", /github\.event\.workflow_run\.head_repository\.full_name == github\.repository/],
    ["exact event/input SHA", /inputs\.source_sha == github\.event\.workflow_run\.head_sha/],
    ["exact event/input run ID", /MACSAD_FOUNDATION_RUN_ID.*MACSAD_EVENT_FOUNDATION_RUN_ID/],
  ]) requirePattern(paths.reusable, reusable, `missing ${label} job-level admission`, pattern);
  const labelsMatch = reusable.match(/      labels:\n((?:        - [a-z0-9-]+\n)+)/);
  const actualLabels = labelsMatch
    ? labelsMatch[1].trim().split(/\n/).map((line) => line.replace(/^\s*-\s*/, ""))
    : [];
  const expectedLabels = ["self-hosted", "linux", "x64", "firebat2", "macsad-verifier"];
  if (JSON.stringify(actualLabels) !== JSON.stringify(expectedLabels)) {
    failures.push(`${paths.reusable}: runner labels must be exactly ${expectedLabels.join(", ")}`);
  }
  for (const [label, pattern] of [
    ["fixed LOGOS workspace", /LOGOS_WORKSPACE: \/opt\/macsad\/toolchains\/logicaffeine-private/],
    ["trusted job PATH", /^      PATH: \/usr\/bin:\/bin$/m],
    ["fixed absolute Bash shell", /shell: \/usr\/bin\/bash --noprofile --norc -e -o pipefail \{0\}/],
    ["trusted precheckout PATH", /export PATH='\/usr\/bin:\/bin'/],
    ["private primary group", /\[\[ "\$\(id -gn\)" == 'macsad-verifier' \]\]/],
    ["only one supplementary-group identity", /\[\[ "\$\(id -nG\)" == 'macsad-verifier' \]\]/],
    ["zero Linux capabilities", /\^Cap\(Inh\|Prm\|Eff\|Amb\):/],
    ["NoNewPrivs process boundary", /\^NoNewPrivs:\[\[:space:\]\]\+1\$/],
    ["full-SHA checkout", /ref: \$\{\{ inputs\.source_sha \}\}/],
    ["credential-free checkout", /persist-credentials: false/],
    ["host invariant gate", /run: \/usr\/bin\/bash ops\/firebat2\/verify_verifier_host\.sh/],
    ["browser/LOGOS harness", /run: \/usr\/bin\/bash scripts\/ci\/firebat2-verify\.sh/],
    ["success-only evidence upload", /if: \$\{\{ success\(\) \}\}/],
    ["SHA-and-attempt artifact identity", /name: firebat2-\$\{\{ inputs\.source_sha \}\}-attempt-\$\{\{ github\.run_attempt \}\}/],
    ["pinned upload-artifact v7.0.1", /actions\/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/],
    ["post-run disposable-guest cleanup", /Remove per-run evidence from the disposable guest/],
  ]) requirePattern(paths.reusable, reusable, `missing ${label}`, pattern);

  const host = read(paths.host);
  for (const [label, pattern] of [
    ["dedicated account", /EXPECTED_USER='macsad-verifier'/],
    ["private exact group", /EXPECTED_GROUP='macsad-verifier'[\s\S]*id -gn[\s\S]*id -nG/],
    ["trusted system PATH before path discovery", /set -Eeuo pipefail\n\nreadonly TRUSTED_PATH='\/usr\/bin:\/bin'\nexport PATH="\$\{TRUSTED_PATH\}"\nreadonly SCRIPT_DIR/],
    ["zero process capabilities", /\^Cap\(Inh\|Prm\|Eff\|Amb\):[\s\S]*unsafe != 1/],
    ["NoNewPrivs process boundary", /\^NoNewPrivs:\[\[:space:\]\]\+1\$/],
    ["root-owned identity marker", /ROLE_FILE='\/etc\/macsad\/firebat2-runner-role'/],
    ["KVM or QEMU VM proof", /systemd-detect-virt[\s\S]*'kvm'[\s\S]*'qemu'/],
    ["ephemeral image marker", /EXPECTED_IMAGE_MARKER='macsad-firebat2-ephemeral-vm-v1'/],
    ["exact runner version", /EXPECTED_RUNNER_VERSION='2\.334\.0'/],
    ["ephemeral registration setting", /get\("ephemeral", "Ephemeral"\) is not True/],
    ["disabled runner update setting", /get\("disableUpdate", "DisableUpdate"\) is not True/],
    ["Node 24", /\^v24\\\.\[0-9\]\+\\\.\[0-9\]\+\$/],
    ["fixed Chromium", /CHROMIUM_BIN='\/usr\/bin\/chromium'/],
    ["fixed timeout", /TIMEOUT_BIN='\/usr\/bin\/timeout'[\s\S]*root_owned_read_only_path "\$\{TIMEOUT_BIN\}"[\s\S]*-x "\$\{TIMEOUT_BIN\}"/],
    ["fixed tee", /TEE_BIN='\/usr\/bin\/tee'[\s\S]*root_owned_read_only_path "\$\{TEE_BIN\}"[\s\S]*-x "\$\{TEE_BIN\}"/],
    ["fixed LOGOS workspace", /EXPECTED_LOGOS_WORKSPACE='\/opt\/macsad\/toolchains\/logicaffeine-private'/],
    ["immutable runner parent chain", /root_owned_immutable_directory_node '\/opt'[\s\S]*root_owned_immutable_directory_node '\/opt\/macsad'/],
    ["immutable toolchain parent", /root_owned_immutable_directory_node '\/opt\/macsad\/toolchains'/],
    ["immutable system executable parents", /root_owned_immutable_directory_node '\/usr'[\s\S]*root_owned_immutable_directory_node '\/usr\/bin'/],
    ["canonical usrmerge bin path", /-L \/bin[\s\S]*realpath -- \/bin[\s\S]*'\/usr\/bin'/],
    ["locked runner distribution", /root_owned_runner_tree "\$\{RUNNER_ROOT\}"/],
    ["narrow runner diagnostics carveout", /local diagnostics="\$\{path\}\/_diag"[\s\S]*EXPECTED_USER}:700/],
    ["ACL-aware runner distribution immutability", /-path "\$\{diagnostics\}" -prune -o[\s\S]*-perm \/022 -o -writable/],
    ["recursive immutable LOGOS tree", /find "\$\{LOGOS_WORKSPACE\}" -xdev[\s\S]*-type l -o ! -user root -o -writable/],
    ["no noninteractive sudo", /sudo -n true/],
    ["no Docker socket write", /-w \/var\/run\/docker\.sock/],
    ["20 GiB floor", /MINIMUM_AVAILABLE_BYTES=\$\(\(20 \* 1024 \* 1024 \* 1024\)\)/],
    ["4 GiB memory floor", /MINIMUM_AVAILABLE_MEMORY_KIB=\$\(\(4 \* 1024 \* 1024\)\)/],
    ["clean checkout", /status --porcelain --untracked-files=all/],
    ["locked LOGOS verification", /scripts\/logos\.sh" --version/],
    ["organization runner registration", /GitHubUrl"\) != "https:\/\/github\.com\/Brahmastra-Labs"/],
  ]) requirePattern(paths.host, host, `missing ${label} host bumper`, pattern);
  rejectPattern(paths.host, host, "host verifier must be read-only", /\b(?:apt|dnf|yum|pacman|git\s+(?:clone|pull|fetch|checkout|reset)|systemctl\s+(?:enable|start)|useradd|usermod)\b/);

  const runbook = read(paths.runbook);
  for (const phrase of [
    "FIREBAT2_ENABLED",
    "not registered",
    "No browser is installed",
    "No inbound webhook",
    "outbound long-polling",
    "branch protection",
    "HTTP 403",
    "Do not enable",
    "FIREBAT2_ENABLED=false",
    "--ephemeral --disableupdate",
    "destroy the entire VM overlay",
  ]) {
    if (!runbook.includes(phrase)) failures.push(`${paths.runbook}: missing current-state warning ${JSON.stringify(phrase)}`);
  }
  requirePattern(paths.runbook, runbook, "must forbid a direct bare-metal runner", /Running the Actions runner directly on bare Firebat2 is\s+forbidden/);

  const guardrails = read(paths.guardrails);
  requirePattern(paths.guardrails, guardrails, "must allow only the exact same-repository reusable workflow", /reference === "\.\/\.github\/workflows\/firebat2-verify\.yml"/);

  const builder = read(paths.builder);
  requirePattern(paths.builder, builder, "must emit each uploaded bundle twice", /macsad-upload-compare[\s\S]*logos\.sh" emit wasm-dom[\s\S]*logos\.sh" emit wasm-dom/);
  requirePattern(paths.builder, builder, "must byte-compare the uploaded and independent emissions", /hash_tree "\$\{output_directory\}"[\s\S]*hash_tree "\$\{comparison_directory\}"/);

  const verifierHarness = read(paths.verifierHarness);
  for (const [label, pattern] of [
    ["300-second quality budget", /readonly QUALITY_GATE_BUDGET_SECONDS=300/],
    ["120-second bundle budget", /readonly BUNDLE_BUILD_BUDGET_SECONDS=120/],
    ["120-second browser budget", /readonly BROWSER_SMOKE_BUDGET_SECONDS=120/],
    ["trusted harness PATH", /PATH=\/usr\/bin:\/bin/],
    ["trusted harness PATH before path discovery", /set -Eeuo pipefail\n\nexport PATH='\/usr\/bin:\/bin'\nreadonly SCRIPT_DIR/],
    ["hard process timeout", /--signal=TERM --kill-after=15s "\$\{budget_seconds\}s"/],
    ["ordered timing evidence", /metadata\/stage-timings\.tsv/],
    ["timed quality stage", /run_timed_stage quality-gate "\$\{QUALITY_GATE_BUDGET_SECONDS\}"/],
    ["timed bundle stage", /run_timed_stage bundle-build "\$\{BUNDLE_BUILD_BUDGET_SECONDS\}"/],
    ["timed browser stage", /run_timed_stage browser-smoke "\$\{BROWSER_SMOKE_BUDGET_SECONDS\}"/],
  ]) requirePattern(paths.verifierHarness, verifierHarness, `missing ${label}`, pattern);

  const artifactManifest = read(paths.artifactManifest);
  for (const [stage, budget] of [
    ["quality-gate", 300],
    ["bundle-build", 120],
    ["browser-smoke", 120],
  ]) {
    requirePattern(
      paths.artifactManifest,
      artifactManifest,
      `manifest must lock ${stage} to ${budget}s`,
      new RegExp(`\\["${stage}", ${budget}\\]`),
    );
  }

  const browserProbe = read(paths.browserProbe);
  rejectPattern(
    paths.browserProbe,
    browserProbe,
    "Chromium sandbox must remain enabled",
    /["']--no-sandbox["']/,
  );
  for (const [label, pattern] of [
    ["admin input drive", /input\.value = 'Firebat2 interaction proof'/],
    ["admin click drive", /button\.click\(\)/],
    ["admin reactive state assertion", /Draft staged in this browser only — no command was sent/],
    ["public filter drive", /mathematics\.click\(\)/],
    ["public admin-control absence", /adminControlCount !== 0/],
    ["remote-request denial", /remoteRequests\.length/],
    ["page WebSocket observation", /client\.on\("Network\.webSocketCreated"[\s\S]*pageWebSockets\.push/],
    ["page WebSocket failure boundary", /pageWebSockets\.length/],
    ["page WebTransport observation", /client\.on\("Network\.webTransportCreated"[\s\S]*pageWebTransports\.push/],
    ["page WebTransport failure boundary", /pageWebTransports\.length/],
    ["CDP screenshot", /Page\.captureScreenshot/],
  ]) requirePattern(paths.browserProbe, browserProbe, `missing ${label}`, pattern);

  const actionsAudit = read(paths.actionsAudit);
  rejectPattern(paths.actionsAudit, actionsAudit, "settings audit may issue GET requests only", /--method",\s*"(?!GET)/);
  for (const pattern of [
    /allowed_actions !== "selected"/,
    /sha_pinning_required !== true/,
    /github_owned_allowed !== true/,
    /verified_allowed !== false/,
    /default_workflow_permissions !== "read"/,
    /can_approve_pull_request_reviews !== false/,
    /!\["false", "true"\]\.includes\(variable\.value\)/,
    /group\.inherited !== false/,
    /group\.visibility !== "selected"/,
    /group\.allows_public_repositories !== false/,
    /group\.restricted_to_workflows !== true/,
    /group\.selected_workflows\[0\] !== admittedWorkflow/,
    /selectedRepositories\.repositories\[0\]\.full_name !== repository/,
    /selectedRepositories\.repositories\[0\]\.private !== true/,
  ]) requirePattern(paths.actionsAudit, actionsAudit, "GitHub Actions read-only audit is incomplete", pattern);
  requirePattern(
    paths.actionsAudit,
    actionsAudit,
    "GitHub Actions audit must read the default workflow-token policy",
    /actions\/permissions\/workflow/,
  );

  const browserDirectories = loadBrowserContract().projects.map((project) => project.directory).sort();
  const domDirectories = loadModuleManifest().projects
    .filter((project) => project.domBundle)
    .map((project) => project.directory)
    .sort();
  if (JSON.stringify(browserDirectories) !== JSON.stringify(domDirectories)) {
    failures.push("tests/browser-smoke-contract.json: every and only DOM project must have browser smoke evidence");
  }

  if (failures.length > 0) throw new Firebat2ContractError(failures.join("\n"));
  return { labels: actualLabels, browserProjects: browserDirectories };
}

function main() {
  const result = verifyFirebat2Contract();
  process.stdout.write(
    `Firebat2 contract passed: ${result.labels.length} exact labels, ${result.browserProjects.length} browser projects, no untrusted trigger.\n`,
  );
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`error: ${error.message}\n`);
    process.exit(1);
  }
}
