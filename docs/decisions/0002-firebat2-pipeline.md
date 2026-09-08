# ADR 0002: Firebat2 is a capacity-one disposable test and predeploy appliance

Status: accepted

## Context

MaCSad needs a fast autonomous path from a commit on `main` to trustworthy test
evidence and, later, a staging deployment. Firebat2 is owned hardware, but
repository code must not execute as its privileged host user or retain state
between revisions. A full runner-orchestration platform would add more control
plane than a single four-core machine and one low-volume repository need.

GitHub already records each commit and workflow run durably enough to be the
queue authority. Firebat2 should contribute scarce integration capacity, not
become a second scheduler. GitHub recommends ephemeral runners for autoscaling
and warns that an ephemeral runner's diagnostic logs must be forwarded before
it is discarded; those requirements shape this design. See GitHub's
[self-hosted runner reference](https://docs.github.com/en/enterprise-cloud@latest/actions/reference/runners/self-hosted-runners)
and [runner-group access controls](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/manage-runners/self-hosted-runners/manage-access).

## Decision

Treat successful GitHub workflow runs as the queue and Firebat2 as a
capacity-one execution appliance:

```text
commit / pull request
        |
        v
Foundation CI (GitHub-hosted, fast, credential-free)
        |
        | successful push of the exact SHA to main
        v
Firebat2 exact-SHA jobs (one available runner slot)
        |
        v
fresh KVM overlay + one-job verifier runner
        |
        v
LOGOS / WASM / browser evidence for that SHA
        |
        +--> fixed-function deployer --> staging --> black-box smoke
        |
        `--> no successful evidence: no deploy
```

Foundation CI remains the admission gate for every pull request and push. Each
successful `main` push identifies one immutable candidate by source SHA and its
Foundation run ID. Its SHA-specific concurrency key coalesces only duplicate
requests for that candidate; distinct SHAs remain distinct jobs. Firebat2
exposes capacity for exactly one guest, so GitHub leaves the other matching jobs
queued instead of replacing them through a shared pending slot. GitHub's
24-hour self-hosted-job limit still bounds the queue: an
expired run is a visible failure and must be explicitly requeued at the same
SHA; it is never test evidence. The exact semantics are governed by GitHub's
[workflow concurrency contract](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).

The bare-metal host runs only a small root-owned controller. While the lane is
enabled, it maintains exactly one clean standby KVM guest and registers that
guest with `--ephemeral --disableupdate` before work exists. The runner's own
outbound HTTPS long-poll is therefore the queue wake-up mechanism; the
controller does not need an inbound webhook or execute repository-defined queue
logic. After the guest accepts one job, the controller forwards diagnostics,
destroys its copy-on-write overlay on every terminal path, and provisions a new
standby. If no standby is healthy, GitHub keeps matching jobs queued until the
controller restores capacity. The controller reconciles orphaned registrations
and overlays before advertising the replacement slot. Running the Actions
runner directly as `alejandro`, root, or any other bare-metal account is
forbidden.

The verifier guest has no reusable secret, deployment credential, database
credential, SSH key, Docker socket, host checkout, writable toolchain, or host
mount. It checks the exact clean source SHA and root-owned toolchain before
running the bounded LOGOS, deterministic-bundle, and real-browser gates. Its
success artifact is evidence only when the workflow concludes successfully and
the recorded manifest verifies byte-for-byte.

Deployment uses a separate fixed-function identity and runner group. It does
not compile source or reuse the verifier guest. It accepts only a successful
verification identity `(source SHA, Foundation run ID, verification run and
attempt)`, verifies the artifact manifest, and promotes those exact bytes. Its
credential can affect only the named staging or production application, and
its root-owned deploy command exposes an allowlisted operation rather than a
general interactive shell. Ordinary non-control-plane merge and application
deployment use automated checks and have no human approval gate. A candidate
that changes admission, required guardrails, a toolchain lock, or deployment
policy first needs an independent machine policy-activation result evaluated
outside the replacement code; it cannot approve its own authority. Emergency
disablement, credential rotation, destructive data operations, runner-image
changes, and break-glass recovery remain explicit operator actions.

## Scheduled validation

Scheduled work is added only after a staging target and rollback artifact
exist. A schedule is observability, not a substitute for per-commit admission:

| Lane | Candidate | Purpose | Result |
|---|---|---|---|
| Per-main-SHA verify | Exact Foundation-admitted SHA | Predeploy LOGOS, WASM, browser, and manifest checks | Required evidence for that SHA |
| Fast staging smoke | Currently deployed staging manifest | Black-box health, static assets, admin denial, and public-read behavior | Alert and block further promotion on red |
| Nightly recovery | Latest non-production backup plus deployed schema/artifact identity | Restore into disposable storage, verify migrations/invariants, then exercise rollback | Recovery evidence; never writes production |

Schedules run from the latest default-branch workflow definition and may be
delayed by GitHub, so they use off-hour minutes and never carry correctness
deadlines. The fast smoke is intentionally small; it does not rebuild or rerun
the complete commit suite. Nightly recovery is the expensive lane. Both use the
same physical capacity and defer whenever a commit candidate is waiting. See
GitHub's [scheduled workflow behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).

## Deployment is not publication

An application deployment changes platform code or infrastructure. It may be
fully automatic after deterministic verification and environment-specific
smoke checks. Research publication changes the public corpus and is a separate
MaCSad domain transition. A deployed application cannot publish a finding merely
because CI passed. Publication still requires an eligible closed case, complete
evidence closure, policy-authorized seal, immutable publication manifest, and
successful publication-specific checks. This distinction keeps CI authority
out of the research domain.

## Current state and activation boundary

As audited on 2026-09-01:

- `main` branch protection is active, with the strict Foundation check,
  administrator enforcement, linear history, and force-push/deletion
  protection; ordinary merging requires no approving review;
- repository auto-merge is enabled;
- `FIREBAT2_ENABLED=false`;
- Firebat2 has hardware KVM support, but has no QEMU/VM lifecycle tools, runner,
  guest image, controller, Chromium, or `/usr/bin/node`;
- the current GitHub CLI identity receives HTTP 403 from organization runner
  and runner-group administration;
- no staging target, deployer, scheduled staging smoke, or nightly recovery
  lane exists; and
- the independent control-policy gate for control-path changes is not yet
  installed, so those changes are held outside the ordinary autonomous lane.

The commit lane stays disabled until the organization grants narrowly scoped
runner administration, the controller and verifier image pass their destructive
cleanup canaries, the selected-repository/workflow runner group is verified,
the standby-register/run/destroy/replace cycle is proven, and a real canary
produces valid evidence. The deploy and scheduled lanes stay
disabled until staging, exact-artifact promotion, smoke, rollback, and recovery
fixtures exist. A skipped disabled job does not count as evidence.

## Consequences

- The design is deliberately one repository, one queue, one guest at a time.
  Add capacity only after measured queue pressure justifies it.
- GitHub remains the observable queue and source-revision authority; no custom
  Kanban state or database row schedules CI.
- A compromised verifier loses a disposable, credential-free guest rather than
  the Firebat2 host or deployment identity.
- Deploy credentials never enter a verifier and repository code never executes
  as the bare-metal owner.
- Per-commit verification stays comprehensive; continuous smoke stays fast;
  recovery validation stays scheduled and isolated.
- GitHub deployment environments and concurrency can record deployment state
  without adding routine manual approval. See GitHub's
  [deployment controls](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/control-deployments).
