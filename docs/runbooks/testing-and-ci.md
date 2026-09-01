# Testing and CI runbook

## One test surface

Use the repository harness:

```bash
make test-foundation
make test
```

`test-foundation` is credential-free and covers repository policy, LOGOS module
registration, Compose security contracts, host-adapter tests, and their escape
hatches. `test` additionally verifies the exact private LOGOS toolchain, exact
named LOGOS tests/properties, supported cross-tier evidence, and deterministic
browser bundles. With a fresh `DATABASE_URL`, it also runs the migration,
repeat, catalog, and invariant suite.

## Evidence ladder

| Gate | What it proves |
|---|---|
| Static guardrails | Forbidden source/deployment shapes are absent |
| Exact LOGOS test gate | Registered tests ran, none vanished or skipped |
| Deterministic emit | Two independent bundle emissions match |
| Host adapter contracts | Mechanical boundary behavior matches its contract |
| PostgreSQL fresh gate | Clean migration, repeat, catalog and invariants pass |
| Compose config | The environment model resolves without unsafe exposure |
| Running-stack verify | Actual containers, routes and schema are healthy |
| Browser acceptance | User-visible behavior works; not yet implemented fully |

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
It executes the credential-free contracts and a clean PostgreSQL 16 database
gate. Full private-LOGOS and Firebat runtime evidence remains local until a
dedicated, isolated self-hosted runner is registered and reviewed. Do not run
untrusted pull-request code on the owned Firebat workstation.

## Failure triage

- Reproduce the exact failing command locally.
- Confirm the expected toolchain/version before changing code.
- Check for zero discovered tests or silently unavailable tools.
- Fix the product or harness contract; do not weaken the assertion.
- Keep the failing evidence in the handoff when blocked.
