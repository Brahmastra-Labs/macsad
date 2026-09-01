# MaCSad

New contributors and operators should start with
[GETTING_STARTED.md](GETTING_STARTED.md). Engineering changes follow the exact
local-module, test-leaf, and no-false-green workflow in
[CONTRIBUTING.md](CONTRIBUTING.md).

**MaCSad — Mathematics and Computer Science Auto-Discovery** is a controlled
research framework for producing reproducible, inspectable progress on bounded
mathematics and computer-science problems.

MaCSad preserves each question, attempt, artifact, verification result,
decision, and publication while preventing an agent from treating plausible
output or successful execution as verified truth.

> **Current status: Sprint 001 foundation.** The repository contains responsive
> LOGOS admin and public templates, a read-only LOGOS health gateway, the
> canonical PostgreSQL 16 schema, a private Firebat Compose environment, and
> strict build/test guardrails. Firebat still needs its one-time privileged
> Docker/Tailscale bootstrap before that environment can run. Domain mutations,
> PostgreSQL connectivity from LOGOS, agent workers, and live Cloudflare
> deployment are intentionally not claimed yet.

## Repository map

| Path | Responsibility |
|---|---|
| `.macsad/` | Machine-readable project and exact local-toolchain policy |
| `logos/admin/` | Private administration portal, authored in LOGOS |
| `logos/public-site/` | Evidence-first public site, authored in LOGOS |
| `logos/gateway/` | Narrow LOGOS HTTP boundary; health only in Sprint 001 |
| `host_adapters/` | Mechanical capabilities that LOGOS cannot yet provide |
| `database/` | PostgreSQL schema, migrations, verification, and invariant tests |
| `tests/` | Cross-project test manifests and governance fixtures |
| `scripts/` | Reproducible local build and quality entry points |
| `ops/compose/` | Pinned Firebat containers, private networking, and lifecycle harness |
| `ops/firebat/` | One-time Docker/Tailscale host bootstrap |
| `.github/workflows/` | Protected foundation CI; deployment stays credential-gated |
| `docs/runbooks/` | Executable operations, database, testing, and incident procedures |
| `docs/` | API, deployment, decisions, and bounded sprint records |

The dependency direction is deliberate: LOGOS owns product views and domain
decisions; narrow hosts provide mechanical I/O; PostgreSQL owns durable truth.
Generated bundles, credentials, registry-resolved LOGOS packages, and
developer-specific absolute paths do not belong in Git.

## LOGOS source map

The frontend code is ordinary, reviewable `.lg` source under `logos/`:

```text
logos/
├── admin/src/
│   ├── main.lg                # browser entry and mount
│   ├── admin_app.lg           # navigation and application composition
│   ├── admin_header.lg        # private control-plane masthead
│   ├── board_workspace.lg     # board, health read, and local draft state
│   ├── read_only_panels.lg    # organization, research, operations panels
│   └── admin_policy.lg        # tested Kanban/terminal-state rules
├── public-site/src/
│   ├── main.lg                # browser entry and mount
│   ├── public_app.lg          # public composition root
│   ├── public_masthead.lg     # public identity and evidence seal
│   ├── public_hero.lg         # publication empty-state hero
│   ├── research_ledger.lg     # filter state and evidence-oriented record UI
│   ├── public_closing.lg      # principles and footer components
│   └── publication_policy.lg  # tested fail-closed visibility rule
└── gateway/src/
    ├── main.lg                # loopback listener
    ├── gateway_http.lg        # LOGOS request handler
    └── gateway_routing.lg     # tested read-only route policy
```

`main.lg` files own process entry only. Application files compose components;
state-owning components keep state beside the view; import-free policy leaves
hold executable rules and their exact tests. The module manifest rejects any
`.lg` file that is not part of the real production import graph.

## Build from the local LOGOS source

MaCSad does **not** use a LOGOS or Logicaffeine crate published to crates.io.
The source, commit, tree, Cargo lock, and observed `largo` binary digest are
recorded in [`.macsad/toolchains/logos.lock.toml`](.macsad/toolchains/logos.lock.toml).
Point `LOGOS_WORKSPACE` at that exact clean local checkout and run one gate:

```bash
export LOGOS_WORKSPACE=/path/to/logicaffeine-private
bash scripts/quality-gate.sh
```

The wrapper rejects a different repository origin, commit, tree, Cargo lock,
binary digest, version, or tracked source modification. The gate verifies the
required repository structure, formatting, supported LOGOS checks, exact named
test inventory with zero skips, finite proof counts, deterministic browser
bundles, and mechanical host contract. When `DATABASE_URL` is supplied, it also
runs the PostgreSQL verification and invariant suite.

## Fully LOGOS-authored product boundary

All MaCSad screens, state machines, transition and authorization decisions,
research logic, and publication rules are authored in LOGOS. The current
admin, public, and gateway application sources are `.lg` files; there is no
handwritten JavaScript or Rust application layer.

The pinned LOGOS framework cannot yet serve binary assets reliably, perform
authenticated browser mutations, read HTTP identity headers, or transact with
PostgreSQL. The Firebat environment therefore uses an unprivileged static edge
container to serve generated LOGOS bytes and proxy one allowlisted read-only
health check to the LOGOS gateway. It is infrastructure, not product logic: it
has no domain decisions, no mutation, and no database access.
Every such boundary and its required upstream acceptance test is recorded in
[`LOGOS_GAPS.md`](LOGOS_GAPS.md). MaCSad will not disguise a framework gap with
GET mutations, raw JavaScript, generic CRUD, or a registry crate.

## Current runnable slice

- Admin: responsive LOGOS board shell with the six fixed phases, navigable
  areas, an honest health read, and browser-local drafting.
- Public: responsive LOGOS publication shell that fails closed when evidence is
  incomplete.
- Gateway: `GET /api/v1/health` only; it reports that persistence is not
  connected and mutations are disabled.
- Firebat runtime: PostgreSQL, generated LOGOS sites, the health-only LOGOS
  gateway, and read-only pgAdmin are defined as a tailnet-bound Compose stack.

These templates are visible and testable; they are not presented as CRUD. The
first mutation slice is the typed append-message command in
[`docs/API_COMMAND_BOUNDARY.md`](docs/API_COMMAND_BOUNDARY.md), after identity,
PostgreSQL, and framework-boundary tests are green.

## Engineering workflow

Every behavior follows RED → GREEN → REFACTOR. Read [`AGENTS.md`](AGENTS.md)
before editing. Never weaken or skip a test, create an optimistic false success,
or move policy into a host adapter to make a gate pass. The complete definition
of done includes a clean pushed commit.

The bounded baseline and deploy contracts are:

- [`docs/sprints/001_baseline.md`](docs/sprints/001_baseline.md)
- [`docs/deployment.md`](docs/deployment.md)
- [`LOGOS_GAPS.md`](LOGOS_GAPS.md)

Routine commands and recovery procedures live in
[`docs/runbooks/README.md`](docs/runbooks/README.md). The repository landing
page intentionally does not duplicate those runbooks.

## Product and data contracts

- [`design_document.md`](design_document.md) — purpose, authority, workflow,
  execution, publication, and deployment design.
- [`user_story.md`](user_story.md) — minimal personas, jobs, feature map, and
  acceptance outcomes.
- [`domain_model.md`](domain_model.md) — PostgreSQL domain model, invariants,
  ERDs, and schema-management policy.
- [`database/README.md`](database/README.md) — PostgreSQL 16 migration,
  verification, backup, and operations runbook.

## Core model

- One watched GitHub repository is the sole project and primary workspace.
- Approved local tool repositories are read-only dependencies, pinned to exact
  preserved revisions and admitted operations; they are never extra projects.
- Every case and execution pins an exact workspace snapshot, policy revision,
  problem revision, and tool closure.
- Kanban columns are projections of a pinned process graph, not freely mutable
  statuses.
- Director, Investigator, and Verifier roles operate through explicit
  capabilities, assignments, task threads, handoffs, budgets, and decision
  matrices.
- Creative discovery is separate from independent checking and human
  publication approval.
- Publication freezes an evidence closure and advances the public head only
  after an exact sealed deployment succeeds.

The greenfield `0001` schema contains 47 tables including its migration ledger,
50 native enum types, and six read views. It is applied by a one-shot,
checksum-verifying Compose migration job; application startup never migrates.

## Next vertical slice

1. Complete Firebat's privileged Docker/Tailscale bootstrap, join it to the
   approved Headscale tailnet, and bring up the verified Compose environment.
2. Add authenticated host transport and a tested transaction adapter without
   moving lifecycle policy out of LOGOS.
3. Implement one typed command end to end: append a message to an existing task
   thread with idempotency, expected version, audit event, and outbox in one
   transaction.
4. Expose that exact command in the admin template only after negative, race,
   replay, authorization, and browser tests pass.
5. Add a sealed public projection only after its evidence closure is
   reproducible.
