# MaCSad user stories and feature map

> **Status:** Draft v1 product contract
>
> **Date:** 2026-08-31
>
> **Source:** [`design_document.md`](./design_document.md)
>
> **Companion:** [`domain_model.md`](./domain_model.md)

## 1. Purpose

This document translates the MaCSad design into the smallest coherent set of jobs, user stories, features, and acceptance outcomes.

MaCSad's v1 product promise is:

> A human can admit one bounded mathematics or computer-science question, give an agent a controlled attempt, have a different actor verify the result, close the work with an honest disposition, and publish only a sealed public-safe batch.

That single journey is the scope test. A proposed feature belongs in v1 only when it enables that journey or protects its integrity.

## 2. Simplicity rules

1. **One project is one watched GitHub repository.** MaCSad never invents a second workspace identity.
2. **One research case is one card.** The card, task drawer, process position, and thread are views of the same aggregate.
3. **One sequential workflow first.** No user-authored loops, forks, joins, or subworkflows in v1.
4. **One active Investigator attempt at a time.** Global worker concurrency begins at one.
5. **One authoritative relational store.** PostgreSQL owns control state; Cloudflare services do not become competing workflow databases.
6. **One immutable evidence path.** Attempts produce artifacts; typed attestations interpret them; no `verified` Boolean exists.
7. **One human-controlled publication path.** Research completion and editorial eligibility are separate decisions.
8. **Static before dynamic.** The public site is generated from sealed material and does not query private state.
9. **Polling before realtime.** No WebSockets, presence, or live collaboration infrastructure until measured need exists.
10. **Cloudflare primitives earn their place.** Using every available service would increase, not reduce, complexity.

## 3. People and authority

V1 has five product perspectives. These are responsibility boundaries, not necessarily five paid people.

| Perspective | Primary job | May decide | Must not decide |
|---|---|---|---|
| **Research Director / admin** | Scope, fund, supervise, and honestly close research | Intake, priority, budget, pause/cancel, disposition, exact policy activation | Mechanical checker results or verifier independence by decree |
| **Investigator agent** | Perform one bounded research attempt and submit evidence | What allowed approach to try and what candidate to propose | Its own budget increase, verification, final disposition, or publication |
| **Independent Verifier** | Check, replay, or attack a candidate using fresh bounded context | Its attestation and stated limitations | Mutation of the candidate while claiming independent verification |
| **Publisher / curator (human)** | Construct and release an exact public-safe closure | Batch contents, public wording, release, retry, erratum under a narrow publication capability | Upgrading weak evidence into a stronger research claim |
| **Public reader** | Understand, scrutinize, and reproduce released work | What to read or independently reproduce | Private workflow or control-plane state |

The Director may also hold the Publisher capability in the first deployment. Operational controls live in the Director interface; v1 does not invent a separate operator product or staffed operations role.

Roles guide work. Permissions come from authenticated principals and explicit capability grants.

## 4. One end-to-end v1 journey

1. The Director connects one approved GitHub repository and activates one reviewed policy revision.
2. The Director freezes one problem revision and approves a bounded budget.
3. The Investigator accepts the assignment and completes one bounded attempt against an exact repository snapshot.
4. The Investigator registers immutable artifacts and proposes a transition to verification.
5. A different Verifier receives a fresh-context evidence closure, checks or replays it, and records an immutable attestation.
6. The Director reviews the evidence and chooses an honest research disposition.
7. As the workflow closes, an authenticated human holding the separate eligibility capability records `private` or `eligible`; eligibility is not implied by the disposition or the Director role.
8. The Publisher previews, seals, signs, and deploys one exact public batch.
9. A public reader sees a static page that distinguishes proof-checker acceptance, validated counterexample, observation, uncertainty, and human interpretation.

The first release is successful when this journey works for one adjudicated math fixture and one deterministic CS fixture—including failure, pause, cancellation, budget exhaustion, and inconclusive outcomes.

## 5. Minimal feature map

| ID | Feature | Job completed | Included in v1 | Explicitly not included |
|---|---|---|---|---|
| **F1** | Repository workspace | Establish one exact, reconcilable project boundary | Stable GitHub repository ID, authenticated events, default-branch reconciliation, immutable snapshots, candidate policy changes | Multiple watched repositories, direct agent pushes, automatic policy activation |
| **F2** | Problem intake | Turn an idea into a question that cannot drift silently | Math/CS kind, statement, definitions, assumptions, bounds, success/refutation/inconclusive criteria, permitted sources/tools, initial budget | General knowledge intake, unrestricted web research, arbitrary problem types |
| **F3** | Work control | Make ownership and legal next steps obvious | Fixed `Inbox → Ready → Running → Verify → Review → Closed` board derived from the live task's pinned `board_phase`, active workflow node, assignment, typed handoff, task thread, process ribbon, WIP=1, pause/resume/block/cancel | General workflow builder, graph canvas, teams, DMs, presence, realtime editing |
| **F4** | Bounded investigation | Let one agent try useful work without ambient authority | Exact snapshot, allowlisted typed MaCSad MCP/LOGOS tool adapters, one lease, resource limits, model budget, immutable outputs, transition proposal | Generic shell, raw ambient MCP, credentials in workers, recursive agents, swarms, unrestricted plugins |
| **F5** | Independent verification | Separate candidate generation from belief | Different verifier, fresh/blind context record, checker/replay/attack method, immutable attestation | Self-verification, mutable attestations, universal claims from a test pass |
| **F6** | Human disposition | Close work without confusing completion with truth | Exact evidence review, typed math/CS outcome, limitations, editorial eligibility as a separate decision | One scalar score, agent-declared breakthrough, automatic publication |
| **F7** | Batch publication | Release only an exact, safe, reproducible closure | Preview checks, signed manifest, monotonic batch, exact deployment attempt, retry, erratum | Live database-backed public pages, silent rewrites, donations, public accounts |
| **F8** | Public reading | Let readers judge what was actually established | Static discovery pages, claim kind, evidence, method, limitations, provenance, hashes, corrections | Draft/private data, comments, voting, live control-plane API |
| **F9** | Essential operations | Keep a one-worker system safe and understandable | Health, lease, spend, reconciliation, audit trail, emergency stop, scheduled digest/compaction trigger | Fleet management, multi-region scheduler, standalone observability platform |

## 6. User stories and jobs to be done

### 6.1 Research Director / admin

#### US-D1 — Connect the workspace

**When** I begin a campaign, **I want** to connect one approved GitHub repository, **so that** every decision and artifact belongs to one unambiguous workspace.

Maps to: **F1**

Accepted when:

- MaCSad records the stable numeric repository ID, display owner/name, default branch, and installation identity;
- webhook signatures are verified against the original body and delivery IDs are deduplicated;
- reconciliation resolves an exact commit and preserves an immutable snapshot independently of a floating branch;
- repository rename does not create a new project; and
- no worker receives a long-lived GitHub credential.

#### US-D2 — Freeze a research question

**When** I admit an idea, **I want** to turn it into a bounded immutable problem revision, **so that** an agent cannot silently change what success means.

Maps to: **F2**

Accepted when:

- the original question, domain kind, definitions, assumptions, bounds, and allowed methods are explicit;
- success, refutation, and inconclusive criteria are all present;
- the problem pins an exact workspace snapshot and active policy revision;
- math intake records a formalization/reverse-paraphrase path, while CS intake records an executable protocol; and
- any semantic edit creates a new revision with a visible diff and supersession link.

#### US-D3 — Authorize bounded work

**When** a scoped case is ready, **I want** to set priority and approve a bounded budget, **so that** work starts only within my intent.

Maps to: **F2, F3, F4**

Accepted when:

- the case cannot enter `Ready` until required intake fields and assignments exist;
- `Ready → Running` atomically reserves budget, creates one execution, and issues one fenced lease;
- inability to reserve worst-case cost prevents the execution from starting;
- one Investigator cannot exceed WIP=1; and
- raising a ceiling requires a narrow human capability, reason, and audit event.

#### US-D4 — Understand and control current work

**When** research is running, **I want** one coherent view of status, owner, process node, thread, artifacts, blockers, lease, and spend, **so that** I can intervene safely.

Maps to: **F3, F9**

Accepted when:

- the board, task drawer, process ribbon, and member inbox agree because they project the same state;
- the board phase is derived from the active task and cannot be edited independently;
- pause, resume, block, cancel, and emergency stop are expected-version checked, reasoned, idempotent, and audited;
- late worker results cannot revive a cancelled or superseded execution;
- chat messages can discuss an action but cannot perform it; and
- a compact morning/operations digest shows completed, failed, blocked, verification/review, proposed-budget, spend, and next-action items; compaction may summarize context but never deletes the raw event or artifact history.

#### US-D5 — Decide the research disposition

**When** independent review is complete, **I want** to close the case with an honest typed outcome, **so that** workflow completion is never mistaken for truth.

Maps to: **F5, F6**

Accepted when:

- the decision binds the exact problem revision, claim, attempts, artifacts, and attestations reviewed;
- math outcomes distinguish `proved`, `refuted`, `inconclusive`, and `invalid_formalization`;
- CS outcomes distinguish `observed_under_frozen_protocol`, `exactly_reproduced`, `refuted`, `inconclusive`, and `invalid_experiment`;
- administrative closure distinguishes `superseded`, `cancelled`, and `policy_denied` from research conclusions;
- timeout, parser success, model confidence, and ordinary test success cannot satisfy stronger gates; and
- the narrow `publication.eligibility.decide` capability, not role name or generic admin status, records `private` or `eligible` in the same closing transaction.

#### US-D6 — Review a process change

**When** a repository push changes `.macsad/`, **I want** to inspect a semantic diff and activate an exact policy digest, **so that** active organizational rules never change silently.

Maps to: **F1, F9**

Accepted when:

- a push creates only a schema-validated candidate policy revision;
- broken references, cycles, unsupported node kinds, missing defaults, and authority mismatches fail closed;
- activation names the exact compiled digest and authenticated approver; and
- existing cases remain pinned to their prior policy revision unless explicitly migrated.

### 6.2 Investigator agent

#### US-I1 — Understand the assignment

**When** I receive work, **I want** the frozen question, exact repository snapshot, active node, allowed tools, evidence requirements, deadline, and remaining budget, **so that** I can act without guessing.

Maps to: **F3, F4**

Accepted when:

- the authenticated assignment exposes exactly that bounded context;
- the agent can read its task thread and relevant evidence but not unrelated private material;
- the effective role and permissions are server-derived rather than supplied in a prompt; and
- accepting an assignment does not grant a worker lease or new capability.

#### US-I2 — Perform one bounded attempt

**When** I investigate, **I want** approved research tools and a task thread, **so that** I can produce a useful candidate while preserving provenance.

Maps to: **F3, F4**

Accepted when:

- execution occurs in a credential-free isolated source tree at the exact snapshot;
- time, compute, process, disk, output, token, and currency ceilings are enforced outside agent control;
- the attempt records request, actor/profile, tool/model versions, seed, environment, limits, transport state, termination state, and research outcome separately;
- model credentials and control-plane credentials never enter the child sandbox; and
- retry creates a new execution rather than overwriting history.

#### US-I3 — Submit evidence or a blockage

**When** I have a result or cannot proceed, **I want** to register immutable artifacts and propose the next step, **so that** the controller can evaluate my work without accepting my narration as authority.

Maps to: **F3, F4**

Accepted when:

- the server hashes, scans, classifies, and records each artifact before accepting it;
- every claim and attestation names the exact problem revision and supporting closure;
- a transition proposal is evaluated against the pinned workflow and typed facts;
- missing or unknown facts route only through explicit fail-closed paths;
- the Investigator cannot approve its own evidence, extend its budget, or bypass a gate; and
- a verification handoff offers the exact snapshot/problem/policy/evidence package and acceptance criteria, while the Investigator remains owner until acceptance.

### 6.3 Independent Verifier

#### US-V1 — Receive an independent review package

**When** a candidate reaches verification, **I want** a fresh-context package containing the frozen problem and exact evidence closure, **so that** I can review without inheriting the Investigator's persuasion.

Maps to: **F3, F5**

Accepted when:

- verifier and candidate-producing actor are different authenticated principals;
- candidate files and artifacts are read-only;
- the package records which context was withheld or freshly reconstructed;
- assignment acceptance records the exact problem, policy, snapshot, and evidence digests; and
- acceptance atomically transfers ownership to the Verifier; clarification, rejection, expiry, or escalation never transfers it silently.

#### US-V2 — Check or attack the candidate

**When** I verify math or CS work, **I want** an admitted checker, replay, differential, metamorphic, property, or methodological review path, **so that** I can reproduce, refute, or report uncertainty.

Maps to: **F5**

Accepted when:

- the method, toolchain, environment, seed, limits, and inputs are pinned;
- outputs and diagnostics are immutable artifacts;
- every accepted deterministic execution is replayed on a clean worker and compares exact expected hashes; non-executable semantic or methodological review instead records its admitted method and limitations;
- infrastructure failure remains distinct from research outcome; and
- an unsupported method records an attempt/check-layer `unknown` fact that routes fail-closed; if the case closes without admitted support or refutation, its research disposition is `inconclusive`.

#### US-V3 — Record a typed attestation

**When** my review ends, **I want** to submit an immutable typed attestation, **so that** a gate can use exact evidence rather than prose or a generic badge.

Maps to: **F5, F6**

Accepted when:

- the attestation records kind, authority class, issuer, method, outcome, schema, limitations, and content digest;
- it binds the same problem revision as the claim it assesses;
- supporting artifacts are an explicit immutable closure;
- independence dimensions are recorded individually; and
- correction creates a superseding attestation rather than mutating the original.

### 6.4 Publisher / curator (human)

#### US-P1 — Preview an eligible release

**When** closed cases are editorially eligible, **I want** to preview the exact public-safe closure, **so that** secrets, private data, licensing problems, missing evidence, and inflated claims cannot escape.

Maps to: **F7**

Accepted when:

- selection names exact case, problem, claim, attestation, artifact, policy, toolchain, and source revisions;
- privacy, secret, citation, license/export, link, artifact-closure, audit-chain, and claim-language checks pass;
- the preview shows the exact public diff; and
- any failed check blocks sealing.

#### US-P2 — Seal and release exact bytes

**When** a preview is acceptable, **I want** to seal and sign one immutable batch and deploy those exact bytes, **so that** the public release is traceable and repeatable.

Maps to: **F7**

Accepted when:

- the batch receives a monotonic sequence, manifest digest, audit head, signature, and previous-batch link;
- an authenticated human with the narrow publication capability and configured recent/step-up identity check seals and authorizes the exact manifest;
- a separate audited `platform-publisher` service principal performs the GitHub Actions/Cloudflare deployment under one manifest-scoped release authority, without exposing deploy credentials to the human browser or watched-repository identity;
- the deployment request names the exact manifest, platform/generator revision, release sequence, and trigger kind;
- CI validates and smoke-tests the uploaded version before promotion; and
- public `latest` advances only after observed deployment success.

#### US-P3 — Retry or correct without rewriting history

**When** delivery fails or a published finding changes, **I want** a safe retry or explicit erratum, **so that** history remains honest.

Maps to: **F7**

Accepted when:

- an exact retry reuses the same release-request identity;
- a platform/template redeploy creates a new deployment attempt without resealing research content;
- a research correction creates a linked erratum or new batch; and
- superseded public pages keep visible correction links.

### 6.5 Public reader

#### US-R1 — Browse trustworthy summaries

**When** I visit MaCSad, **I want** static, readable discovery pages, **so that** I can understand released work without access to the private system.

Maps to: **F8**

Accepted when:

- only sealed public content is deployed;
- the site contains no admin code, private API endpoint, credentials, or direct storage listing;
- pages load as cacheable static assets; and
- the notice “Machine-generated/internal research; not external peer review” is visible.

#### US-R2 — Judge what a claim means

**When** I read a result, **I want** the bounded question, claim kind, evidence method, verifier independence, limitations, and provenance, **so that** I can distinguish proof-checker acceptance from observation or uncertainty.

Maps to: **F8**

Accepted when:

- definitions, assumptions, bounds, frozen statement, and approved formalization diff are visible;
- checker acceptance is phrased as acceptance of a named artifact for a named formal statement;
- observations state the exact protocol and scope;
- human interpretation remains visually separate from mechanical evidence; and
- source commit, batch identity, and trusted-computing-base limitations are present.

#### US-R3 — Reproduce and follow corrections

**When** I scrutinize a result, **I want** public-safe artifacts, hashes, instructions, and correction links, **so that** I can retrace the work and see how it changed.

Maps to: **F8**

Accepted when:

- the page links the immutable public artifact closure and batch manifest;
- instructions name exact versions and expected hashes;
- inaccessible private inputs are disclosed as a limitation rather than implied reproducible; and
- errata and supersession form a navigable chain.

## 7. Supporting system jobs

These are acceptance obligations, not extra personas or products.

| ID | System job | Features | Acceptance outcome |
|---|---|---|---|
| **SJ-1** | Reconcile GitHub | F1, F9 | A signed push yields one deduplicated receipt and exact preserved snapshot; reconciliation detects a missed event |
| **SJ-2** | Enforce commands | F3–F6, F9 | Every mutation is authenticated, expected-version checked, request-hash idempotent, audited, and atomically outboxed where needed |
| **SJ-3** | Bound spending and execution | F4, F9 | Reservation precedes work; cancellation, expiry, delayed usage, and late completion cannot create untracked spend or accepted state |
| **SJ-4** | Preserve evidence | F4–F8 | Artifact bytes match their digest; lineage and attestations are immutable; a clean deterministic replay matches exact outputs |
| **SJ-5** | Schedule without inventing content | F7, F9 | Periodic work reconciles and compacts state; no publication is generated when no new sealed batch exists |
| **SJ-6** | Recover | F1–F9 | PostgreSQL, artifact storage, snapshots, policy revisions, and signing state restore into a clean environment and reproduce both fixtures and one batch |
| **SJ-7** | Deploy the trusted platform | F7–F9 | A protected platform-main push that passes required CI deploys the exact attested admin artifact; privileged jobs never execute pull-request-authored code, and a code deployment cannot publish an unsealed research batch |

## 8. Cloudflare responsibility map

The first Cloudflare deployment should use a few primitives deeply and leave the rest out.

| Cloudflare primitive | V1 responsibility | Feature mapping | Authority rule |
|---|---|---|---|
| **Admin web edge (proposed)** | Prefer a Worker Static Assets shell plus thin `/api/*` gateway; use the Access-protected tunneled origin directly if the Phase 0 identity-forwarding fixture fails | F1–F7, F9 | The gateway authenticates/routes; the LOGOS controller remains domain-transition authority |
| **Cloudflare Access** | Protect the complete admin hostname and supply authenticated identity evidence | F1–F7, F9 | The API validates `Cf-Access-Jwt-Assertion` issuer, audience, signature, expiry, and human/service claims before mapping a MaCSad principal; it does not rely on `ctx.access` when Static Assets are configured |
| **Cloudflare Tunnel** | Reach the private LOGOS service on Firebat without opening a general inbound origin | F1–F7, F9 | Bind only the intended service; no public origin bypass |
| **Workers Static Assets: public** | Deploy the independently generated public site | F7, F8 | Public deployment has no private API, database, or controller binding |
| **Cloudflare CDN/static-asset cache** | Cache immutable public files and hash-addressed artifacts | F8 | Cache is a performance layer, never evidence or workflow authority |
| **R2 Standard (optional public replication)** | Replicate sealed public bundles if static-deployment artifact retention is insufficient | F7, F8 | Private evidence and snapshots remain in the Firebat CAS for v1; public export uses a separate bucket/binding and only classified, sealed, digest-verified bytes |
| **One Cron Trigger** | Wake reconciliation, digest/compaction, and publication-candidate checks | F7, F9 | Cron only submits an idempotent command; PostgreSQL/controller state decides what actually runs |

The public deployment remains separate from the private admin surface. The preferred admin Worker topology is conditional on an integration test because Cloudflare's Static Assets router does not currently pass `ctx.access` to user Worker code. The combined gateway must validate the Access assertion header explicitly; the already-designed fallback serves the admin app through the Access-protected Tunnel with the same API contract. [Access and `ctx.access` limitations](https://developers.cloudflare.com/workers/configuration/cloudflare-access/#ctxaccess-limitations), [validating Access JWTs](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/)

### Why D1 and Durable Objects are not v1 authorities

The requested domain target is PostgreSQL. D1 is a separate SQLite database, so using both for writable control state would create dual-write and consistency problems. D1 may later hold a disposable public search/catalog projection rebuilt from sealed manifests, but v1's static public site does not need it.

Durable Objects are valuable for per-entity global serialization and realtime/WebSocket coordination. PostgreSQL transactions, optimistic versions, one controller, and one worker already serialize v1. Add a Durable Object only after a measured edge-coordination requirement appears.

Likewise:

- **Hyperdrive** is unnecessary while the Worker calls the private LOGOS controller and that controller owns local PostgreSQL transactions. If the controller later runs inside Workers, use Hyperdrive and disable query caching on correctness-sensitive read-after-write paths.
- **Workers VPC** is beta and would still use Cloudflare Tunnel as the private-network on-ramp for this topology; defer it until direct Tunnel routing proves insufficient.
- **Queues** are deferred until webhook volume or origin downtime demonstrates a need for Cloudflare-side buffering. Consumers must remain idempotent because delivery is at least once.
- **Workflows** must not become a second research process engine. MaCSad's own workflow is domain state; Cloudflare Workflows may later orchestrate deployment mechanics only.
- **KV** and the Workers **Cache API** are not authoritative stores. Static Assets and ordinary CDN caching cover the first public site; the Cache API is currently unavailable for Workers fronted by Access.

### Free-tier posture as of 2026-08-31

Limits are operating guardrails, not permanent architecture. Recheck them before deployment.

- Workers Free currently allows 100,000 dynamic requests per day and 10 ms CPU per invocation, while Static Asset requests are free and unlimited. The Cron handler must therefore be a tiny wake-up/fetch handler rather than the batch job itself. [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Static Assets billing](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/)
- R2 Standard currently includes 10 GB-month, one million Class A operations, and ten million Class B operations per month before usage charges; egress is free. These are metered allowances, not a hard free-plan ceiling. [R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- Access's free plan currently supports up to 50 users. [Cloudflare Zero Trust pricing](https://www.cloudflare.com/plans/zero-trust-services/)
- D1 Free currently includes five million rows read and 100,000 rows written per day, but it remains SQLite and is deliberately not a second MaCSad authority. [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/)
- Queues Free currently includes 10,000 operations per day with 24-hour retention; it is an optional transport, not durable domain history. [Queues pricing](https://developers.cloudflare.com/queues/platform/pricing/)

## 9. Delivery slices

### Slice A — prove the research loop locally

Features: **F2–F6, minimal F9**

- One manually selected exact repository snapshot.
- One math fixture and one CS fixture.
- One sequential workflow, one worker, one Investigator, one Verifier.
- PostgreSQL state, immutable artifacts, bounded execution, and honest closure.

### Slice B — connect the repository and admin edge

Features: **F1, F3, F9**

- Read-only GitHub integration and reconciliation.
- Cloudflare Access-protected admin edge, with the Worker/static-shell gateway selected only after the JWT-forwarding fixture passes.
- Private Cloudflare Tunnel route to the LOGOS controller.
- Board, task/thread drawer, evidence review, and operations view.

### Slice C — publish one sealed batch

Features: **F7, F8**

- Local-CAS public-safe closure and deterministic static generator; optional separate R2 replication only if deployment retention requires it.
- Separate public Worker/static deployment.
- Exact release request, smoke test, promotion, retry, and erratum.

## 10. Explicit deferrals

- Multiple watched repositories, tenants, or active organizations.
- Teams, departments, org charts, arbitrary channels, DMs, presence, rich notification rules, and Slack replacement breadth.
- Generic workflow authoring, forks, joins, loops, reusable subflows, and an ambitious graph canvas.
- Agent swarms, recursive delegation, autonomous committees, multiple providers, or multiple active workers.
- Unrestricted web retrieval, generic shell, ambient plugins, direct repository mutation, automatic merge, or automatic policy activation.
- Live public APIs, accounts, comments, voting, donations, or user-directed spending.
- Dynamic D1-backed public search, Durable Objects, WebSockets, and general realtime collaboration.
- Private-artifact R2 migration and Workers VPC until local CAS or direct Tunnel no longer fits.
- Cloudflare Workflows as a research scheduler.
- Statistical/performance claims beyond explicitly frozen protocols.
- Automatic domain purchase.

## 11. V1 product acceptance

MaCSad v1 is product-ready only when:

1. both fixed fixtures complete the end-to-end journey;
2. every failure state remains honest and recoverable;
3. no agent can self-fund, self-verify, self-publish, or obtain ambient authority;
4. the Director can understand and control the system from the four compact admin surfaces;
5. public output is static, sealed, reproducible to the stated extent, and visibly caveated; and
6. a proposed feature that is not required by this contract remains deferred.
