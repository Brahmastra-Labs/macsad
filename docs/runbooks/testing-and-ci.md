# Testing and CI runbook

## One test surface

Use the repository harness:

```bash
make lint-logos
make test-foundation
make test
```

`lint-logos` is the standalone size, duplication, unfinished-marker, orphan,
and exact scoped-style debt gate described in
[`../standards/logos-source-quality.md`](../standards/logos-source-quality.md).
`test-foundation` includes that linter and its adversarial fixtures, then covers
repository policy, LOGOS module registration, Compose security contracts,
host-adapter tests, and their escape hatches. `test` additionally verifies the
exact private LOGOS toolchain, exact
named LOGOS tests/properties, supported cross-tier evidence, and deterministic
browser bundles. With a fresh `DATABASE_URL`, it also runs the migration,
repeat, catalog, and invariant suite.

## Evidence ladder

| Gate | What it proves |
|---|---|
| Static guardrails | Forbidden source/deployment shapes are absent |
| Workflow semantic lint | Every GitHub workflow parses under pinned `actionlint` before its queue contract is trusted |
| LOGOS source-quality gate | Size and copied-behavior thresholds hold; baseline CSS debt did not move, change, or grow |
| Exact LOGOS test gate | Registered tests ran, none vanished or skipped |
| Deterministic emit | Two independent bundle emissions match |
| Host adapter contracts | Mechanical boundary behavior matches its contract |
| PostgreSQL fresh gate | Clean migration, repeat, catalog and invariants pass |
| Compose config | The environment model resolves without unsafe exposure |
| Running-stack verify | Actual containers, routes and schema are healthy |
| Browser acceptance | Firebat2 CDP drives admin state and public filtering, rejects public admin controls; defined but disabled pending the VM lane |

Never promote evidence upward. A lower gate cannot substitute for a missing
higher gate.

## Adding a test

1. Write the smallest failing behavior at the owning layer.
2. Observe the expected failure.
3. Register LOGOS test leaves and exact names in
   `tests/logos-module-manifest.json`.
4. Add negative and boundary cases before implementation grows.
5. Run the targeted test, then `make test`.
6. Do not introduce skips, retries that hide failure, or snapshots blessed by
   CI.

## CI

`Foundation CI` runs on every push and pull request without private credentials.
It keys runs by event and exact SHA without cancelling an older commit, runs a
pinned, checksum-verified GitHub workflow semantic linter, then executes the
credential-free contracts and a clean PostgreSQL 16 database gate under a
10-minute job limit. Its successful push-on-main `workflow_run` is
the only automatic Firebat2 ingestion event. Once the currently disabled lane
is provisioned and explicitly enabled, every distinct successful main SHA is a
separate queue item; only duplicate pending requests for the same SHA may
coalesce. One ephemeral runner executes one item at a time, so different SHAs
remain independently queued without concurrency-group cancellation. GitHub's
transport order never establishes research priority or permission, and its
24-hour self-hosted queue limit still applies. An expired item is a visible
failure requiring an explicit same-SHA requeue, not test evidence. Pull
requests, manual dispatch, schedules, and inbound webhooks never execute on the
owned runner.

The Firebat2 lane is currently disabled with the repository variable read back
as `FIREBAT2_ENABLED=false`. Repository Actions settings were also read back as
selected GitHub-owned actions only with full-SHA pinning required. Audit those
settings without mutation:

```bash
node scripts/ci/audit-github-actions-settings.mjs
```

Do not enable the lane until branch protection is available and the mandatory
one-job ephemeral KVM/QEMU VM controller, `--ephemeral --disableupdate` runner,
browser, immutable LOGOS checkout, and guaranteed overlay destruction all pass
[`firebat2-verification.md`](firebat2-verification.md). A persistent runner on
bare Firebat2 is forbidden. Missing browser or isolation is a red required lane,
never a skip.

When provisioned, Firebat2 has a 15-minute job limit and three sequential hard
stage budgets: 300 seconds for `quality-gate`, 120 seconds for `bundle-build`,
and 120 seconds for `browser-smoke`. The success artifact
`firebat2-<sha>-attempt-<run_attempt>` records each stage's elapsed seconds and
budget in `metadata/stage-timings.tsv`; its manifest rejects missing, reordered,
changed, or over-budget timing rows. Timeout or elapsed-time overrun fails the
attempt. It is never converted into a skip, retry loop, larger implicit budget,
or successful artifact.

Artifact presence by itself is not a passing result: upload occurs before
cleanup and action post-steps. Evidence consumers must require the final
workflow conclusion to be `success` and independently verify the byte manifest.
Any later red step invalidates that attempt even if an artifact is visible.

These workflow and harness contracts are checked in, but actual Firebat2
execution remains unprovisioned and disabled. Do not report browser, private
LOGOS, timing, or ephemeral-VM evidence until a real enabled run produces it.

## Failure triage

- Reproduce the exact failing command locally.
- Confirm the expected toolchain/version before changing code.
- Check for zero discovered tests or silently unavailable tools.
- Fix the product or harness contract; do not weaken the assertion.
- Keep the failing evidence in the handoff when blocked.
