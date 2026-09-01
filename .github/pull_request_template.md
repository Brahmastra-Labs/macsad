## Outcome

Describe the user or operator outcome, not only the files changed.

Request/intake reference:

Candidate SHA and trusted base SHA:

Granted authority and explicit non-goals:

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

RED evidence and expected reason:

GitHub Foundation CI run:

Firebat2 evidence (`not admitted`, `queued`, `passed`, or `failed`) and exact run/attempt:

## Security and operations

- [ ] No secret, credential, private artifact, or machine-specific path is committed.
- [ ] No wildcard/LAN/public database exposure was introduced.
- [ ] Failure, denial, replay, and recovery behavior were considered.
- [ ] Relevant runbooks and `LOGOS_GAPS.md` were updated.
- [ ] Runner, workflow, admission, test-discovery, or toolchain-control changes are called out for separate human review.
- [ ] This ordinary change did not fetch, pull, rebuild, or repin `logicaffeine-private`; an authorized promotion instead follows `docs/runbooks/upgrading-logos.md`.
