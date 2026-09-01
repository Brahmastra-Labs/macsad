# Agent request intake and delivery runbook

This is the entrypoint for a human or coding agent changing MaCSad. It turns a
request into one bounded, machine-verifiable candidate with evidence. It is
inspired by the useful idea in `pit` that work should move through an explicit,
navigable process graph; the states, rules, roles, and evidence contract here
are MaCSad-owned and deliberately small.

A request grants only the authority recorded in its request contract. The
repository's pre-authorized pipeline may test, merge, and deploy an ordinary
candidate without a per-run human approval when every configured machine gate
accepts the exact SHA. A request never permits broader scope, credential
exposure, policy activation, an unscoped toolchain change, or a bypass of those
gates.

## The bumpers

Before doing any work:

- read `AGENTS.md`, `GETTING_STARTED.md`, this runbook, and the nearest owning
  design or operations document;
- inspect `git status --short`, the current branch, `HEAD`, and the files in
  scope; preserve every unrelated change;
- use the exact checked-in harness; do not invent a parallel build or test path;
- treat the commit SHA as candidate identity and test evidence as immutable;
- never give a coding agent a repository, Firebat, database, Cloudflare,
  OpenRouter, or private-toolchain credential;
- never execute an untrusted webhook body or untrusted pull-request code on an
  owned Firebat host; and
- stop at an exceptional authority boundary instead of bypassing a machine
  gate or acquiring a credential.

`logicaffeine-private` is currently pinned. An ordinary request must not fetch,
pull, check out, rebuild, or repin it. A separately scoped promotion follows
[`upgrading-logos.md`](upgrading-logos.md) and its machine-verifiable contract.

## 1. Write the request contract

Record this compact card in the task handoff, issue, or pull-request body. Do
not create a second database or board just for this record.

```text
Outcome:       one observable result
Job to be done: why the result matters to the requester
In scope:      exact behaviors and likely owning paths
Out of scope:  adjacent work that must remain unchanged
Authority:     read / edit / commit / push / operate / deploy, as granted
Acceptance:    executable evidence that decides success
Risk lane:     docs / LOGOS / database / operations / toolchain / control plane
Blockers:      missing access, decision, runtime, or framework primitive
```

Ask only when a missing answer would materially change the result or cross an
authority boundary. Otherwise state a narrow assumption and continue. Split a
request when it has more than one independently reviewable outcome.

The contract is invalid when its acceptance criterion is “looks good,” “the
command exited,” or “the agent says it works.” Select the owning behavior and a
test that can fail for the right reason.

## 2. Follow one control-flow graph

```mermaid
flowchart LR
    I[Intake] --> C[Contract]
    C --> R[RED evidence]
    R --> W[Smallest change]
    W --> T[Targeted gate]
    T -->|fail| X[Triage]
    X -->|contract still right| W
    X -->|contract conflict| C
    T -->|pass| F[Full local gate]
    F -->|fail| X
    F -->|pass| Q[Candidate commit]
    Q --> M{Protected control path changed?}
    M -->|no| G[GitHub Foundation intake]
    M -->|yes| Y[Independent control-policy gate]
    Y -->|hold or fail| X
    Y -->|pass| G
    G -->|fail| X
    G -->|pass| A[Automated merge to main]
    A --> K[Exact main SHA enters Firebat2 queue]
    K -->|lane disabled| D[Done without deploy]
    K -->|verify fail| X
    K -->|verify pass| P{Deploy lane configured?}
    P -->|no| D
    P -->|yes| E[Separate deploy identity verifies exact evidence]
    E -->|fail| X
    E -->|pass| D
    C -->|blocked or cancelled| H
    C -->|credential, destructive, incident, or editorial exception| H[Human hold]
```

The graph is a responsibility contract, not an authorization system. Role names
do not grant capabilities:

| Responsibility | Owns | Cannot substitute for |
|---|---|---|
| Requester/director | Outcome, bounds, priorities, exceptional authority | Test or verifier evidence |
| Working agent | RED evidence, smallest implementation, exact handoff | A required check, credential, or policy exception |
| Repository harness | Deterministic admission, test, merge, and configured promotion decisions | Editorial judgment or an exceptional authority grant |
| External control-policy gate | Evaluate control-path changes from a trusted base or separate GitHub App/ruleset identity | Candidate-defined admission or product correctness |
| Firebat2 worker | Isolated expensive/private test execution for an exact SHA | Merge policy, deploy identity, or a toolchain gate |
| Deploy worker | Re-verification and deployment of one admitted artifact with a separate narrow identity | Source compilation, candidate selection, or test authority |
| Human exception steward | Credential/bootstrap work, exceptional destructive actions, incident recovery, and explicit editorial research publication | A missing or failed required gate |

`main` now has active branch protection: pull requests are required; the strict
`Credential-free governance and PostgreSQL 16` check is required; administrators
are included; linear history is required; force pushes and deletions are
disabled; zero approving reviews and no last-pusher approval are required; and
repository auto-merge is enabled. Ordinary candidates therefore wait on
machine evidence, not a human review queue.

That ordinary lane excludes changes to workflows, admission predicates,
required guardrails, test discovery, toolchain locks, deployment policy, and
the engineering constitution. Those control-plane candidates need an
independent policy-activation check evaluated outside their replacement code.
The repository does not yet have that external check, so such a candidate is
held rather than self-merging. This is an activation gap, not a reason to add a
routine human approval to ordinary changes.

Firebat2 remains deliberately disabled with `FIREBAT2_ENABLED=false`. Its
blockers are the missing verified KVM image/controller, restricted organization
runner group and labels, one-job ephemeral runner lifecycle, and the GitHub
runner-management authority needed to configure them. The current CLI identity
receives `403` only for that organization runner administration—not for the
active branch protection above. Do not attach the privileged bare-metal
`alejandro` account as a runner. The complete enablement hold is in
[`firebat2-verification.md`](firebat2-verification.md).

### State rules

1. **Intake:** preserve the original request and identify granted authority.
2. **Contract:** select one outcome, owner, risk lane, non-goals, and executable
   acceptance criterion.
3. **RED:** observe the missing behavior fail when practical. Record why that
   failure is expected.
4. **Smallest change:** edit only the owning layer. Domain policy remains in
   LOGOS, durable invariants in PostgreSQL, and mechanical effects in narrow
   adapters.
5. **Targeted gate:** run the smallest real test. A zero-test, skipped, or
   unavailable required tier is a failure.
6. **Full local gate:** run the complete gate required by the lane below.
7. **Candidate commit:** review the diff, exclude runtime/generated/secret
   material, and bind the claim to the exact commit SHA.
8. **Control-policy classification:** when a protected control path changed,
   require an independent policy-activation result bound to the trusted base,
   exact candidate SHA, and exact path/digest set. Candidate-defined tests do
   not satisfy this authority. Hold the candidate while that gate is absent.
9. **GitHub intake:** Foundation CI evaluates each submitted commit. Its strict
   required check gates automatic merge for an admitted candidate; no agent may
   bypass it.
10. **Post-merge verification:** each merged `main` SHA becomes a durable
   Firebat2 queue item. Once enabled, the isolated worker adds append-only
   evidence keyed by SHA and attempt.
11. **Machine promotion:** a configured deploy job may advance only the exact
    Firebat2-verified artifact. Deployment uses a separate identity and
    rechecks the SHA plus hash manifest; the verifier never receives deploy
    credentials.
12. **Exceptional hold:** involve a human only for credential/bootstrap work,
    an exceptional destructive action, incident recovery, or explicit editorial
    research publication. Human action cannot waive failed required evidence.

Do not repeatedly rerun a deterministic product failure. Fix it in a new commit.
An infrastructure retry keeps the same SHA, increments the attempt, and records
the infrastructure reason; it never replaces the failed attempt.

## 3. Select the evidence lane

Use every row touched by the change, not merely the cheapest row:

| Changed contract | Targeted evidence | Required handoff evidence |
|---|---|---|
| Prose only | Link/path checks and owning-contract consistency | `git diff --check`; no false runtime claim |
| LOGOS source or UI policy | Exact registered leaf test and module audit | `make test`, deterministic WASM bundle digest, browser tier when the behavior requires it |
| PostgreSQL | New migration/invariant test against a fresh PG16 database | Migrate, repeat, catalog verify, invariants, and least-privilege negative checks |
| Host adapter | Unit test plus real-adapter contract when available | `make test`; unavailable live evidence named exactly |
| Compose/Firebat operations | Compose guardrail and resolved configuration | `make test`, then authorized running-stack checks on the intended host |
| GitHub workflow, runner, guardrail, or security boundary | Positive fixture plus an adversarial escape-path fixture | Credential-free CI; Firebat2 control-path evidence when enabled; no failed machine gate waived |
| LOGOS toolchain identity or framework-gap closure | Enter the separate promotion lane | Follow `upgrading-logos.md`; never silently update the lock |

`make test-foundation` is a fast iteration gate, not a substitute for `make
test`. Database, browser, running-stack, and private-toolchain evidence must be
described at the tier that actually ran.

## 4. Tie GitHub intake to Firebat2

GitHub commits and workflow runs are the durable ingestion queue for code
candidates. Firebat2 is a test worker, not a source of truth, merge authority,
or deployment identity.

The checked-in Firebat2 lane is currently disabled and uses GitHub Actions
itself as the queue. A Firebat2 controller may create and destroy ephemeral
guests, but it does not accept an inbound webhook or make admission decisions.
After the host and runner-group blockers above are closed:

1. successful `Foundation CI` completion triggers the protected
   `.github/workflows/firebat2-ingestion.yml` through `workflow_run`;
2. its GitHub-hosted admission job accepts only a successful `push` run from
   this repository's `main`, produced by the exact
   `.github/workflows/foundation-ci.yml` run and definition paths with matching
   workflow IDs;
3. it passes the exact SHA, `refs/heads/main`, and Foundation run ID to the
   reusable `.github/workflows/firebat2-verify.yml`;
4. the SHA-specific concurrency key coalesces only duplicate requests for the
   same candidate; distinct SHAs remain distinct GitHub jobs, while the
   controller's hard capacity of one serializes their execution without a
   shared pending slot replacing an older commit. GitHub's self-hosted runner
   service then long-polls for a worker in group
   `macsad-firebat2` with the exact `self-hosted`, `linux`, `x64`, `firebat2`,
   and `macsad-verifier` labels; and
5. a fresh unprivileged guest runs one admitted job, forwards bounded evidence,
   deregisters, and has its overlay destroyed on every terminal path.

Foundation CI also keys its own queue by event plus exact SHA and does not
cancel an older commit when a newer push arrives. Thus every distinct pushed
SHA that succeeds in Foundation can enter this queue; a newer push cannot erase
the earlier candidate before admission. Repeated requests for the same SHA may
coalesce, but distinct successful SHAs may not. The single ephemeral-runner
controller serializes actual execution; GitHub's observed queue order is
transport behavior, never research priority or authority. This prevents
concurrency-group replacement; it does not promise indefinite retention.
GitHub fails a self-hosted job that remains queued for more than 24 hours. Such
expiry is a visible failed candidate that requires an explicit same-SHA requeue
and new run attempt; it is never test evidence.

Each queued candidate is identified by this immutable tuple:

```text
repository identity
candidate commit SHA
refs/heads/main
Foundation CI run ID
protected ingestion/verification workflow revision
attempt number
```

The GitHub-hosted admission job performs credential-free structural checks
before requesting owned hardware. The reusable workflow is loaded from the
caller's protected default-branch revision. A candidate that changes runner or
control paths, action definitions, toolchain locks, test-discovery rules, or
admission policy must therefore pass the positive and adversarial governance
fixtures plus the required protected check. It does not gain a human bypass.
Keep `FIREBAT2_ENABLED=false` throughout controller/bootstrap work and enable it
only after the machine-verifiable host, image, runner-group, lifecycle, cleanup,
and negative-isolation contracts pass. If a custom webhook queue is ever
justified later, original-body signature verification, delivery deduplication,
and API reconciliation become mandatory then; they are not part of this
baseline.

Before a Firebat2 worker runs, the reusable verifier must prove:

- the repository and SHA are exact and still eligible;
- the default-branch control-workflow revision passed the protected governance
  and adversarial machine gates;
- the source is a same-repository trusted candidate, never fork code;
- the workspace is fresh and disposable, with no sibling checkout mounted;
- the worker has no SSH agent, host Docker socket, Firebat1 access, deployment
  secret, database credential, or writable private LOGOS checkout;
- outbound access and resource/time limits match the selected suite; and
- logs and artifacts have retention, size, and secret-redaction bounds.

The worker returns a conclusion, suite inventory, exact toolchain and source
identities, artifact digests, timing, and bounded logs. Its bounded
`firebat2-<40-character-sha>-attempt-<run_attempt>` artifact contains the
Foundation run/commit/ref, deterministic bundles, browser
DOM/screenshots/logs, exact stage elapsed times and budgets, and a hash manifest.
GitHub records that evidence against the candidate SHA and attempt for 14 days.
Accept it only when the final workflow conclusion is `success` and the artifact
manifest re-verifies; artifact presence before a failed cleanup or action
post-step is never evidence. A green job authorizes only the narrow transition
encoded in protected workflow policy.

A deploy job, when added, runs under a separate least-privileged identity and
consumes only an exact main-branch artifact whose required checks and manifest
re-verify. It does not share the Firebat2 verifier guest, runner labels, cache,
workspace, or credentials. Code deployment may be automatic; explicit
editorial research publication remains a separate human decision.

The speed contract is fail-closed: Foundation has a 10-minute job limit; the
Firebat2 job has a 15-minute limit; and its sequential `quality-gate`,
`bundle-build`, and `browser-smoke` stages have limits of 300, 120, and 120
seconds. A stage that times out or merely records elapsed time above its budget
fails the candidate. A successful artifact must contain exactly those three
ordered timing rows. An over-budget attempt produces failure evidence in the
Actions run, never a successful artifact or a silently enlarged budget.

The verified design requires a dedicated, unprivileged **one-job ephemeral
runner inside a freshly created KVM/QEMU guest**. The guest must register with
`--ephemeral --disableupdate`, start from the verified immutable image, and have
its entire overlay destroyed on every terminal path. Cleanup inside a persistent
runner, a reused VM, or direct execution on bare Firebat2 is not an acceptable
substitute. Until that controller, image, network, attestation, and destruction
contract is implemented and passes its machine gates, the lane remains disabled
and no actual Firebat2 execution is claimed.

## 5. Handoff without ambiguity

Every handoff states:

```text
Outcome and exact candidate SHA:
Changed contracts and files:
RED evidence observed:
Targeted evidence:
Full local evidence:
GitHub/Firebat2 evidence and attempt:
Recorded stage timings and budgets:
Unavailable evidence and reason:
Operational state changed:
Residual risk or decision required:
Smallest safe next step:
```

Call the work done only when `AGENTS.md`'s definition of done is satisfied. If
the task is blocked, preserve the evidence and name the missing decision or
capability; do not weaken the bumper to make the card move.
