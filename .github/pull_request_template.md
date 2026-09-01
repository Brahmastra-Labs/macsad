## Outcome

Describe the user or operator outcome, not only the files changed.

## Contract and design

- [ ] The change has one clear owning layer: LOGOS, PostgreSQL, host adapter, or operations.
- [ ] Domain types/invariants and documentation still agree.
- [ ] No existing migration was edited.
- [ ] New dependencies, actions, or images are exact-version/digest pinned.

## Evidence

- [ ] The intended failing test was observed when practical.
- [ ] Targeted tests pass.
- [ ] `make test` passes with zero skipped tests.
- [ ] Database/browser/Compose evidence that did not run is stated explicitly.
- [ ] Generated output is deterministic where applicable.

## Security and operations

- [ ] No secret, credential, private artifact, or machine-specific path is committed.
- [ ] No wildcard/LAN/public database exposure was introduced.
- [ ] Failure, denial, replay, and recovery behavior were considered.
- [ ] Relevant runbooks and `LOGOS_GAPS.md` were updated.
