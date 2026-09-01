## Outcome

Describe the user or operator outcome, not only the files changed.

Request/intake reference:

Candidate SHA and trusted base SHA:

Granted authority and explicit non-goals:

Requested machine transition (`merge`, `merge + configured deploy`, or `test only`):

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

Deploy artifact SHA-256/manifest and exact target (`not configured` when absent):

## Security and operations

- [ ] No secret, credential, private artifact, or machine-specific path is committed.
- [ ] No wildcard/LAN/public database exposure was introduced.
- [ ] Failure, denial, replay, and recovery behavior were considered.
- [ ] Relevant runbooks and `LOGOS_GAPS.md` were updated.
- [ ] Runner, workflow, admission, test-discovery, guardrail, toolchain-lock, or deployment-policy changes are classified as a control-plane candidate, include positive/adversarial fixtures, and have independent policy-activation evidence from the trusted base or external policy identity.
- [ ] The candidate does not redefine the authority that admits it; a missing independent control-policy gate is a hold, not an ordinary merge.
- [ ] No required machine gate is bypassed or made advisory; an ordinary non-control-plane merge and configured deployment need no human approval.
- [ ] A deploy worker, when applicable, consumes only the exact admitted artifact through a separate least-privileged identity unavailable to agents and test runners.
- [ ] This ordinary change did not fetch, pull, rebuild, or repin `logicaffeine-private`; a separately scoped promotion instead follows `docs/runbooks/upgrading-logos.md`.
- [ ] Any credential/bootstrap action, exceptional destructive action, incident recovery, or editorial research publication is identified as an explicit human exception rather than hidden in this ordinary lane.
