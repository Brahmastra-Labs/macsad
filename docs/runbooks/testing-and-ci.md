# Testing and CI runbook

## One local test surface

Use the repository harness:

```bash
make lint-logos
make test-foundation
make test
```

`lint-logos` enforces source size, duplication, unfinished-marker, orphan, and
exact scoped-style debt limits. `test-foundation` adds repository policy, LOGOS
module registration, workflow semantics, Compose security, host-adapter
contracts, and adversarial escape-hatch fixtures. `test` additionally verifies
the exact private LOGOS checkout, named tests/properties, supported cross-tier
evidence, and two byte-identical browser bundles. With a fresh `DATABASE_URL`,
it also runs migration, repeat, catalog, and invariant tests.

Run the smallest relevant test first, then the complete gate. A missing tool,
zero discovered tests, a skipped test, or an unavailable required adapter is
red—not a reduced green result.

## Evidence ladder

| Gate | What it proves |
|---|---|
| Static guardrails | Forbidden repository and deployment shapes are absent |
| Workflow semantic lint | Workflows parse and retain their trust, queue, pinning, and timeout contracts |
| LOGOS source-quality | Size and copied-behavior thresholds hold; scoped-style debt did not drift |
| Exact LOGOS tests | Registered tests ran and none vanished, failed, or skipped |
| Deterministic emit | Two independent bundle emissions match byte-for-byte |
| Host-adapter contracts | Mechanical boundaries obey their declared contract |
| PostgreSQL fresh gate | Clean migration, repeat, catalog, and invariants pass on PostgreSQL 16 |
| Compose verification | Actual private services, routes, health, and schema are correct |
| Firebat2 verifier | Exact admitted SHA passed private LOGOS, deterministic WASM, and real-browser gates in a disposable guest |
| Staging smoke | The exact deployed staging manifest works from outside its process boundary |
| Recovery drill | A real backup restores into disposable storage and the deployed compatibility/rollback contract holds |

Never promote evidence upward. A green Foundation run does not prove a browser
or deployment; an uploaded artifact does not prove a workflow finished green;
a staging smoke does not prove backup recovery.

## Adding or changing a test

1. Write the smallest failing behavior at the owning layer.
2. Observe failure for the expected reason.
3. Register LOGOS leaf tests and exact names in
   `tests/logos-module-manifest.json`.
4. Add denial, duplicate, boundary, and failure cases before implementation
   grows.
5. Run the targeted test, then `make test`.
6. Do not introduce skips, fallback success, hidden retries, or CI-blessed
   snapshots.

## Pipeline shape

`Foundation CI` runs on every push and pull request on a GitHub-hosted runner.
It is credential-free, has a 10-minute limit, uses pinned actions and a
checksum-verified workflow linter, and exercises a clean PostgreSQL 16 fixture.
This is the fast admission path and the strict required `main` check.

For a successful push of an exact SHA to `main`, `Firebat2 Commit Ingestion`
validates the `workflow_run` identity. Its SHA-specific concurrency key
coalesces only duplicate requests for the same candidate, while each distinct
main SHA remains a distinct GitHub job. A capacity-one Firebat2 controller
creates a fresh KVM guest and
one-job ephemeral runner for `Firebat2 Reusable Verification`. No job runs on
the bare-metal Firebat2 account. The lane has no inbound webhook: GitHub runner
long-polling is the queue transport.

GitHub expires a self-hosted job after 24 hours. Expiry is a failed candidate,
not permission to drop it; explicitly rerun the same SHA after fixing capacity.
Queue order does not establish research priority. See the architecture and
activation contract in
[`../decisions/0002-firebat2-pipeline.md`](../decisions/0002-firebat2-pipeline.md)
and [`firebat2-verification.md`](firebat2-verification.md).

## Current operational truth

As of 2026-09-01, `main` protection and autonomous merge settings are active,
but `FIREBAT2_ENABLED=false`. Firebat2 has no QEMU tooling, VM controller,
guest image, runner, Chromium, or `/usr/bin/node`, and the current GitHub CLI
identity receives HTTP 403 from organization runner administration. Therefore:

- Foundation CI is real and required;
- Firebat2 workflow contracts are checked in but cannot execute;
- a disabled/skipped Firebat2 workflow is not verification evidence; and
- no deployment, scheduled staging smoke, or nightly recovery evidence exists.

Audit GitHub settings without mutation:

```bash
node scripts/ci/audit-github-actions-settings.mjs --expect-firebat2=disabled
gh api --method GET repos/Brahmastra-Labs/macsad/branches/main/protection
```

Do not enable Firebat2 until the organization permission, selected workflow
runner group, disposable controller/image, fixed toolchain/browser, external
runner-log forwarding, and destructive cleanup canaries all pass.

## Fast, continuous, and recovery lanes

Keep each lane focused:

- **Foundation:** every change; fast static, domain, database, and workflow
  admission.
- **Firebat2 per-main-SHA:** every admitted main commit; full private LOGOS,
  deterministic bundle, and real-browser evidence under a 15-minute limit.
- **Staging smoke:** only after staging exists; small black-box probes against
  the currently deployed manifest at off-hour schedule minutes.
- **Nightly recovery:** only after backup and rollback fixtures exist; restore
  into disposable storage, verify schema/data invariants, and exercise rollback.

The three per-commit Firebat2 stage budgets are 300 seconds for
`quality-gate`, 120 seconds for `bundle-build`, and 120 seconds for
`browser-smoke`. The evidence manifest requires their exact order, names,
budgets, and observed duration. Do not increase them to make a slow revision
green.

Scheduled workflows can be delayed and run the latest default-branch workflow
definition. They are monitoring and recovery evidence, not real-time guarantees
or substitutes for per-SHA verification. The fast smoke must not rebuild the
application; it probes exact deployed bytes. The nightly lane owns expensive
restore work. Both share Firebat2's physical capacity, defer while a commit
candidate is waiting, and cannot start a second VM.

## Deploy and publication boundaries

Verification is credential-free. A separate fixed-function deployer may later
consume only a successful Firebat2 evidence identity and verified artifact,
then promote those exact bytes. It does not compile source or reuse the verifier
identity. Ordinary non-control-plane merge and application deployment are
autonomous after all required checks; they do not wait for a human approval
click. A candidate that changes its admission or deployment policy first needs
the independent control-policy result defined in `AGENTS.md`.

Application deployment is not research publication. CI may ship platform code,
but only the MaCSad domain flow can make an eligible, evidence-closed,
policy-sealed publication batch. Scheduled tests never create or seal one.

## Failure triage

- Reproduce the first failing command at the same layer.
- Confirm the expected SHA, runner image, toolchain, and evidence identity.
- Check for zero tests, missing tools, silently unavailable adapters, or queue
  expiry before changing product code.
- Fix the product or owned environment; never weaken an assertion, digest,
  identity check, timeout, or cleanup condition.
- Preserve the failed run and diagnostic linkage in the handoff.
