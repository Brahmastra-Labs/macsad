# MaCSad engineering constitution

This repository is the trusted platform for MaCSad. Its application code is
authored in LOGOS. PostgreSQL is the sole authority for mutable domain state.
Generated public output is an immutable projection, never a second control
plane.

These rules are requirements, not suggestions.

## Source-of-truth map

- `design_document.md` owns product and authority boundaries.
- `domain_model.md` and immutable files under `database/migrations/` own the
  persistence contract; the migration SQL wins if prose drifts.
- `ops/compose/postgres/010-bootstrap-macsad.sql` owns cluster roles,
  memberships, login defaults, and empty-volume database creation.
- `.macsad/toolchains/logos.lock.toml` owns the exact admitted local LOGOS
  source and runtime identity.
- `.macsad/policies/logos-source-quality.json` owns LOGOS module, definition,
  line-length, duplication, unfinished-marker, and exact scoped-style debt limits.
- `tests/logos-module-manifest.json` owns LOGOS project, module-closure, and
  exact test inventory.
- `ops/compose/compose.yaml` owns the Firebat service topology.
- `GETTING_STARTED.md` is the canonical operator/developer quickstart;
  `docs/runbooks/` owns routine and recovery procedures.
- `docs/runbooks/agent-request-intake.md` owns the bounded request-to-evidence
  control flow; `docs/runbooks/upgrading-logos.md` owns LOGOS promotion and
  rollback.

When two sources disagree, stop at the conflict and repair the contract plus
its executable check. Do not choose the more convenient interpretation.

## The working loop

Enter every task through `docs/runbooks/agent-request-intake.md`. A pushed
commit is immutable test input and neither a green check nor Firebat2 evidence
grants merge, deployment, policy-activation, or toolchain-promotion authority.
Firebat2 remains disabled while the required ruleset/admission control is a
visible RED governance gap.

Use RED, GREEN, REFACTOR for every behavior:

1. Write or select the failing acceptance test.
2. Observe the expected failure for the expected reason.
3. Implement the smallest correct behavior at the proper architectural layer.
4. Run the targeted test.
5. Run `scripts/quality-gate.sh` before handing work off.
6. Refactor only while the complete gate remains green.

Never weaken, delete, skip, ignore, quarantine, or silently re-record a failing
test to make an implementation pass. If the product contract genuinely changes,
surface the conflict and obtain an explicit decision before changing its RED
test.

Run one test suite at a time. Do not leave duplicate suites or servers running.

## Firebat Compose runtime

- Compose is the sole authority for long-running MaCSad processes on Firebat.
  Do not start undocumented background services beside it.
- Pulled images use reviewed immutable digests. Locally built images are tied
  to an exact clean MaCSad revision and admitted staged inputs.
- PostgreSQL is never published on a host port. Application startup never runs
  migrations; the one-shot migration service applies and verifies them first.
- Persistent services have named volumes where needed, explicit health checks,
  restart policy, least privilege, and bounded logs. `depends_on` alone is not
  readiness evidence.
- Never mount the Docker socket, private source checkout, repository
  credentials, or host secrets into an application/viewer container.
- Never run a volume-destroying reset, destructive restore, or unattended
  stateful image upgrade without explicit human authorization and recovery
  evidence.

## Tailnet and operator access

- Admin, public preview, and pgAdmin bind only to an IPv4 address actually
  reported by Firebat's Tailscale client. Never substitute `0.0.0.0`, the LAN,
  loopback, Funnel, or an internet-facing proxy.
- Tailnet reachability is a network boundary, not application authorization.
  Headscale ACLs and the service's own human login are both required.
- pgAdmin uses individual MFA-enabled human accounts and the inherited
  `macsad_reader` database role. It never uses a PostgreSQL superuser, owner,
  migrator, or runtime application identity.

## Truth and authority

- PostgreSQL constraints and transactions are the final live-state guard.
- LOGOS owns domain policy, workflow decisions, authorization decisions, and
  deterministic generation.
- Host adapters may perform typed mechanical effects only. They may not contain
  domain decisions or reinterpret outcomes.
- Kanban columns are projections of pinned process nodes. A UI drag is never
  itself a state transition.
- Immutable facts are corrected by a new superseding fact, never overwritten.
- Browser state may cache preferences and read projections. It may not become
  authoritative domain state.
- Agents never receive database, GitHub deployment, Cloudflare, OpenRouter, or
  private-repository credentials.

## Every mutation

Every accepted mutation must be:

- authenticated from transport identity;
- authorized by an active narrow capability;
- bound to one workspace and aggregate;
- expected-version checked;
- idempotent under a request key and canonical request digest;
- committed atomically with its domain event;
- atomically outboxed when an external effect follows; and
- replayable to the same result for the same accepted command.

There are no GET mutations and no generic table CRUD. Append-only, compiled,
sealed, financial, evidence, audit, and publication-closure tables never receive
raw resource endpoints.

## Tests are the scaffold

The gate must remain strict:

- LOGOS `skip_budget` is always zero.
- LOGOS source must pass the exact size/duplication policy; a new or changed
  scoped-CSS debt fingerprint is a failure, not an invitation to re-record it.
- A suite with zero discovered tests fails.
- A filter matching zero tests fails.
- Any skipped or failed test fails.
- Every LOGOS suite runs with a fixed seed, deterministic operation budget,
  finite-domain proof mode, and the available cross-tier check.
- Real PostgreSQL integration tests use a fresh PostgreSQL 16 database.
- Mocked ports require a separate real-adapter contract suite.
- Generated bundles are built twice and their digests must match.
- Snapshot changes are reviewed artifacts; CI never blesses snapshots.
- Network is disabled in deterministic tests unless a test declares a live
  capability and the separate live gate is deliberately invoked.
- Browser tests cover loading, empty, success, validation, stale-version,
  duplicate-submit, denial, and failure states.
- Accessibility tests cover keyboard operation, focus, names, contrast, reduced
  motion, and responsive layouts.
- Publication tests prove that private or unclassified material fails closed.

## Forbidden shortcuts

Do not introduce:

- `Skip this test`, ignored tests, focused-only tests, `xfail`, or a nonzero skip
  budget;
- `continue-on-error`, `allow_failure`, `set +e`, swallowed exit codes, or
  fallback success paths;
- floating branches, tags, action versions, model aliases, or unpinned toolchains;
- handwritten JavaScript or Rust containing MaCSad domain policy;
- GET endpoints that change state;
- broad `DELETE`, raw SQL, or generic PATCH endpoints;
- optimistic UI changes that pretend a command committed before the server says
  it did;
- secrets, tokens, database URLs, private keys, or developer absolute paths in
  Git;
- test-only production branches or mocks presented as integration evidence;
- automatic policy activation, self-verification, or automatic publication; or
- changes to an applied migration. Add the next numbered migration instead.

## Current LOGOS boundary

The pinned LOGOS release provides Components, Views, signals, bound inputs,
events, scoped CSS, WASM-DOM emission, deterministic tests, proof tooling, and a
LOGOS HTTP server. It does not yet provide the authenticated browser mutation
transport or PostgreSQL adapter required for honest CRUD. Do not bypass this gap
with raw JavaScript, GET mutations, or prose-only claims. The acceptance contract
is in `LOGOS_GAPS.md`.

Each LOGOS application is an explicit local import graph rooted at the exact
entry in `Largo.toml`. Every `src/**/*.lg` file must be reachable both through
the physical entry closure and through the logical application root registered
in `tests/logos-module-manifest.json`; orphan, decorative, cyclic, symlinked,
bare-imported, registry-backed, and Markdown-link-imported modules fail the
gate.

The pinned scope checker currently misattributes nested Component calls to the
entry module. Until the focused upstream fix is promoted, each entry explicitly
imports the full physical module closure in addition to the proper local import
edges. The manifest labels this compatibility lock. Do not mistake those
redundant entry edges for domain architecture or remove the local edges.

The pinned `largo test` reads only its selected entry and does not assemble
imports. Put executable properties in registered, import-free leaf modules with
no `## Main`. The repository test harness hard-links each exact leaf source as
a temporary entry, checks its exact test names/count/properties/proofs, and
rejects all tests found outside registered leaves. Never copy, flatten, or
rewrite product source to manufacture test evidence.

## Definition of done

Work is done only when:

1. the acceptance test existed and was observed RED when practical;
2. targeted tests pass;
3. the complete quality gate passes without skips;
4. generated outputs are deterministic;
5. security and failure behavior are tested, not merely described;
6. documentation and machine contracts agree;
7. no secret or machine-specific path entered Git; and
8. the repository is clean at the pushed commit.

## Repository and documentation discipline

- Inspect status before editing; unrelated changes belong to their author.
- Keep commits small, coherent, reviewable, and free of generated/runtime
  state. Do not force-push or rewrite shared history.
- A command in documentation must run against the checked-in layout. Clearly
  distinguish intended, configured, and actually verified runtime state.
- Infrastructure changes require negative exposure checks, clean bootstrap,
  restart, persistence, and health evidence proportional to the change.
- Update the owning runbook and machine guardrail in the same change when an
  operational contract changes.
