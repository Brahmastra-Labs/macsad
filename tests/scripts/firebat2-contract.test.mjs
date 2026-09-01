import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import test from "node:test";

import {
  Firebat2ContractError,
  verifyFirebat2Contract,
} from "../../scripts/ci/verify-firebat2-contract.mjs";

const repositoryRoot = resolve(import.meta.dirname, "..", "..");
const foundationPath = ".github/workflows/foundation-ci.yml";
const ingestionPath = ".github/workflows/firebat2-ingestion.yml";
const reusablePath = ".github/workflows/firebat2-verify.yml";
const hostPath = "ops/firebat2/verify_verifier_host.sh";
const actionsAuditPath = "scripts/ci/audit-github-actions-settings.mjs";
const browserProbePath = "scripts/ci/browser-probe.mjs";
const verifierHarnessPath = "scripts/ci/firebat2-verify.sh";
const artifactManifestPath = "scripts/ci/artifact-manifest.mjs";

function commentOut(path, line) {
  const original = readFileSync(join(repositoryRoot, ...path.split("/")), "utf8");
  assert(original.includes(line), `fixture line missing from ${path}: ${line}`);
  const comment = path.endsWith(".mjs") ? "//" : "#";
  return original.replace(line, `${comment} ${line}`);
}

test("the checked-in Firebat2 trust and evidence contract is complete", () => {
  const result = verifyFirebat2Contract();
  assert.deepEqual(result.labels, ["self-hosted", "linux", "x64", "firebat2", "macsad-verifier"]);
  assert.deepEqual(result.browserProjects, ["logos/admin", "logos/public-site"]);
});

test("an inbound webhook trigger is rejected", () => {
  const original = readFileSync(join(repositoryRoot, ...ingestionPath.split("/")), "utf8");
  const unsafe = original.replace("  workflow_run:\n", "  repository_dispatch:\n  workflow_run:\n");
  assert.throws(
    () => verifyFirebat2Contract(new Map([[ingestionPath, unsafe]])),
    (error) =>
      error instanceof Firebat2ContractError &&
      error.message.includes("must not admit PR, manual, schedule, or inbound webhook events"),
  );
});

test("an unqualified workflow_run path is rejected", () => {
  const original = readFileSync(join(repositoryRoot, ...ingestionPath.split("/")), "utf8");
  const unsafe = original.replace(
    "[[ \"${FOUNDATION_RUN_PATH}\" == '.github/workflows/foundation-ci.yml@main' ]]",
    "[[ \"${FOUNDATION_RUN_PATH}\" == '.github/workflows/foundation-ci.yml' ]]",
  );
  assert.notEqual(unsafe, original);
  assert.throws(
    () => verifyFirebat2Contract(new Map([[ingestionPath, unsafe]])),
    (error) =>
      error instanceof Firebat2ContractError &&
      error.message.includes("missing exact main-qualified Foundation run path admission"),
  );
});

test("a secret-bearing verifier workflow is rejected", () => {
  const original = readFileSync(join(repositoryRoot, ...reusablePath.split("/")), "utf8");
  const unsafe = original.replace(
    "      - name: Prove the dedicated runner boundary before checkout",
    "      - name: Prove the dedicated runner boundary before checkout\n" +
      "        env:\n" +
      "          UNSAFE: ${{ secrets.UNSAFE }}",
  );
  assert.notEqual(unsafe, original);
  assert.throws(
    () => verifyFirebat2Contract(new Map([[reusablePath, unsafe]])),
    (error) =>
      error instanceof Firebat2ContractError && error.message.includes("must not reference Actions secrets"),
  );
});

test("disabling the Chromium sandbox is rejected", () => {
  const original = readFileSync(join(repositoryRoot, ...browserProbePath.split("/")), "utf8");
  const unsafe = original.replace(
    '    "--headless=new",',
    '    "--headless=new",\n    "--no-sandbox",',
  );
  assert.notEqual(unsafe, original);
  assert.throws(
    () => verifyFirebat2Contract(new Map([[browserProbePath, unsafe]])),
    (error) =>
      error instanceof Firebat2ContractError &&
      error.message.includes("Chromium sandbox must remain enabled"),
  );
});

test("a filtered Foundation push trigger is rejected", () => {
  const original = readFileSync(join(repositoryRoot, ...foundationPath.split("/")), "utf8");
  const unsafe = original.replace(
    "  push:\n",
    "  push:\n    paths:\n      - 'docs/**'\n",
  );
  assert.notEqual(unsafe, original);
  assert.throws(
    () => verifyFirebat2Contract(new Map([[foundationPath, unsafe]])),
    (error) =>
      error instanceof Firebat2ContractError &&
      error.message.includes("Foundation must retain the exact unfiltered push event"),
  );
});

test("commented-out high-risk bumpers cannot satisfy the contract", async (context) => {
  const cases = [
    {
      name: "Foundation workflow identity",
      path: foundationPath,
      line: "name: Foundation CI",
      failure: "Foundation workflow identity must remain exact for workflow_run ingestion",
    },
    {
      name: "Foundation push ingestion event",
      path: foundationPath,
      line: "  push:",
      failure: "Foundation must retain the exact unfiltered push event that feeds commit ingestion",
    },
    {
      name: "Foundation exact-SHA queue",
      path: foundationPath,
      line: "  group: foundation-${{ github.workflow }}-${{ github.event_name }}-${{ github.sha }}",
      failure: "Foundation must key candidates by event and exact SHA",
    },
    {
      name: "Foundation no-cancel contract",
      path: foundationPath,
      line: "  cancel-in-progress: false",
      failure: "Foundation must not cancel an earlier commit candidate",
    },
    {
      name: "Foundation fast timeout",
      path: foundationPath,
      line: "    timeout-minutes: 10",
      failure: "Foundation must fail closed within its fast ten-minute budget",
    },
    {
      name: "push-only admission",
      path: ingestionPath,
      line: "          [[ \"${FOUNDATION_EVENT}\" == 'push' ]]",
      failure: "missing push-only Foundation event admission",
    },
    {
      name: "SHA-specific no-cancel queue",
      path: ingestionPath,
      line: "  cancel-in-progress: false",
      failure: "must deduplicate only the same SHA without cancelling active verification",
    },
    {
      name: "restricted runner group",
      path: reusablePath,
      line: "      group: macsad-firebat2",
      failure: "must use the restricted Firebat2 runner group",
    },
    {
      name: "absolute trusted Bash shell",
      path: reusablePath,
      line: "        shell: /usr/bin/bash --noprofile --norc -e -o pipefail {0}",
      failure: "missing fixed absolute Bash shell",
    },
    {
      name: "trusted job PATH",
      path: reusablePath,
      line: "      PATH: /usr/bin:/bin",
      failure: "missing trusted job PATH",
    },
    {
      name: "runner belongs to only its private group",
      path: reusablePath,
      line: "          [[ \"$(id -nG)\" == 'macsad-verifier' ]]",
      failure: "missing only one supplementary-group identity",
    },
    {
      name: "runner has zero Linux capabilities",
      path: reusablePath,
      line: "            /^Cap(Inh|Prm|Eff|Amb):/ {",
      failure: "missing zero Linux capabilities",
    },
    {
      name: "runner has NoNewPrivs",
      path: reusablePath,
      line: "          grep -Eq '^NoNewPrivs:[[:space:]]+1$' /proc/self/status",
      failure: "missing NoNewPrivs process boundary",
    },
    {
      name: "Firebat2 fast timeout",
      path: reusablePath,
      line: "    timeout-minutes: 15",
      failure: "Firebat2 verification must fail closed within fifteen minutes",
    },
    {
      name: "credential-free checkout",
      path: reusablePath,
      line: "          persist-credentials: false",
      failure: "missing credential-free checkout",
    },
    {
      name: "post-run cleanup",
      path: reusablePath,
      line: "      - name: Remove per-run evidence from the disposable guest",
      failure: "missing post-run disposable-guest cleanup",
    },
    {
      name: "exact runner version",
      path: hostPath,
      line: "readonly EXPECTED_RUNNER_VERSION='2.334.0'",
      failure: "missing exact runner version host bumper",
    },
    {
      name: "host requires a private exact group",
      path: hostPath,
      line: "readonly EXPECTED_GROUP='macsad-verifier'",
      failure: "missing private exact group host bumper",
    },
    {
      name: "host fixes PATH before resolving its location",
      path: hostPath,
      line: "readonly TRUSTED_PATH='/usr/bin:/bin'",
      failure: "missing trusted system PATH before path discovery host bumper",
    },
    {
      name: "host requires NoNewPrivs",
      path: hostPath,
      line: "  grep -Eq '^NoNewPrivs:[[:space:]]+1$' /proc/self/status ||",
      failure: "missing NoNewPrivs process boundary host bumper",
    },
    {
      name: "organization-scoped runner registration",
      path: hostPath,
      line: 'if get("gitHubUrl", "GitHubUrl") != "https://github.com/Brahmastra-Labs":',
      failure: "missing organization runner registration host bumper",
    },
    {
      name: "fixed timeout binary",
      path: hostPath,
      line: "readonly TIMEOUT_BIN='/usr/bin/timeout'",
      failure: "missing fixed timeout host bumper",
    },
    {
      name: "immutable runner distribution",
      path: hostPath,
      line: "  root_owned_runner_tree \"${RUNNER_ROOT}\"",
      failure: "missing locked runner distribution host bumper",
    },
    {
      name: "immutable LOGOS toolchain parent",
      path: hostPath,
      line: "  root_owned_immutable_directory_node '/opt/macsad/toolchains'",
      failure: "missing immutable toolchain parent host bumper",
    },
    {
      name: "immutable system executable parent",
      path: hostPath,
      line: "  root_owned_immutable_directory_node '/usr/bin'",
      failure: "missing immutable system executable parents host bumper",
    },
    {
      name: "read-only default workflow token",
      path: actionsAuditPath,
      line: "  workflowPermissions.default_workflow_permissions !== \"read\" ||",
      failure: "GitHub Actions read-only audit is incomplete",
    },
    {
      name: "workflow token cannot approve pull requests",
      path: actionsAuditPath,
      line: "  workflowPermissions.can_approve_pull_request_reviews !== false",
      failure: "GitHub Actions read-only audit is incomplete",
    },
    {
      name: "runner group selected-repository boundary",
      path: actionsAuditPath,
      line: '  group.visibility !== "selected" ||',
      failure: "GitHub Actions read-only audit is incomplete",
    },
    {
      name: "runner group is organization-local",
      path: actionsAuditPath,
      line: "    group.inherited !== false ||",
      failure: "GitHub Actions read-only audit is incomplete",
    },
    {
      name: "quality stage speed budget",
      path: verifierHarnessPath,
      line: "readonly QUALITY_GATE_BUDGET_SECONDS=300",
      failure: "missing 300-second quality budget",
    },
    {
      name: "harness fixes PATH before resolving its location",
      path: verifierHarnessPath,
      line: "export PATH='/usr/bin:/bin'",
      failure: "missing trusted harness PATH before path discovery",
    },
    {
      name: "trusted Firebat2 harness PATH",
      path: verifierHarnessPath,
      line: "    PATH=/usr/bin:/bin \\",
      failure: "missing trusted harness PATH",
    },
    {
      name: "bundle stage speed budget",
      path: verifierHarnessPath,
      line: "readonly BUNDLE_BUILD_BUDGET_SECONDS=120",
      failure: "missing 120-second bundle budget",
    },
    {
      name: "browser stage speed budget",
      path: verifierHarnessPath,
      line: "readonly BROWSER_SMOKE_BUDGET_SECONDS=120",
      failure: "missing 120-second browser budget",
    },
    {
      name: "recorded quality stage budget",
      path: artifactManifestPath,
      line: '  ["quality-gate", 300],',
      failure: "manifest must lock quality-gate to 300s",
    },
    {
      name: "page WebSocket observation",
      path: browserProbePath,
      line: "    client.on(\"Network.webSocketCreated\", (event) => pageWebSockets.push(event.url ?? \"unknown\"));",
      failure: "missing page WebSocket observation",
    },
    {
      name: "page WebSocket failure boundary",
      path: browserProbePath,
      line: "      pageWebSockets.length ||",
      failure: "missing page WebSocket failure boundary",
    },
    {
      name: "page WebTransport observation",
      path: browserProbePath,
      line: "    client.on(\"Network.webTransportCreated\", (event) => pageWebTransports.push(event.url ?? \"unknown\"));",
      failure: "missing page WebTransport observation",
    },
    {
      name: "page WebTransport failure boundary",
      path: browserProbePath,
      line: "      pageWebTransports.length",
      failure: "missing page WebTransport failure boundary",
    },
  ];
  for (const fixture of cases) {
    await context.test(fixture.name, () => {
      assert.throws(
        () => verifyFirebat2Contract(new Map([[fixture.path, commentOut(fixture.path, fixture.line)]])),
        (error) =>
          error instanceof Firebat2ContractError && error.message.includes(fixture.failure),
      );
    });
  }
});
