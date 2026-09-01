# Sprint 001 — trustworthy visible baseline

## Sprint goal

Deliver a website visibly authored and bundled by LOGOS, establish the repository
and PostgreSQL quality gates, and leave explicit RED contracts for the framework
capabilities needed by the first real CRUD slice.

This sprint is a template and guardrail sprint. It does not implement all MaCSad
features.

## Demonstrable outcome

At sprint review a developer can:

1. run the pinned local `largo` from the MaCSad repository;
2. execute deterministic zero-skip LOGOS tests;
3. build the admin and public WASM-DOM bundles twice identically;
4. serve the admin website and interact with its LOGOS signals, navigation,
   bound form, and Kanban prototype;
5. call a same-origin LOGOS health endpoint through the LOGOS gateway;
6. apply and verify the PostgreSQL schema on PostgreSQL 16; and
7. see precise RED framework gates rather than fake CRUD.

## In scope

- Root engineering constitution and automated shortcut scan.
- Exact local LOGOS source/toolchain lock.
- Single-file LOGOS admin application.
- Single-file LOGOS public-site application.
- Single-file LOGOS development gateway and health contract.
- Deterministic LOGOS unit/property tests with exact test-manifest locking.
- Admin visual system, responsive shell, board, role/process view, research
  overview, operations view, and local-only intake interaction.
- Public discovery landing-page template.
- Sequential quality gate and PostgreSQL schema gate.
- Credential-free GitHub CI foundation.
- Cloudflare deployment contract, variable names, and disabled-until-provisioned
  workflow templates.

## Explicitly out of scope

- Pretend or GET-based mutations.
- PostgreSQL writes from LOGOS before the typed adapter exists.
- Production authentication or Cloudflare Access configuration.
- Agent execution, OpenRouter calls, or theorem campaigns.
- All 47-table UI coverage.
- Automatic publication or domain purchase.
- Deep-link routing before the LOGOS router contract exists.

## Work packages

### WP1 — toolchain and quality gate

- Pin LOGOS source, tree, Cargo lock, and local binary contract.
- Fail on missing/wrong version, zero tests, any skip/failure, changed test names,
  unformatted source, nondeterministic bundle, or forbidden shortcut.
- Run tests with seed 7, `--prove`, and `--tiers all` while documenting the
  current tier-evidence limitation.

### WP2 — visible LOGOS admin

- Use Components, Views, signals, bound inputs, events, keyed collections, and
  CSS from LOGOS source.
- Render the six board phases and a concise operations/research shell.
- Make navigation and local intake interaction functional without claiming a
  server commit.
- Expose loading/offline/backend-health states honestly.

### WP3 — gateway and database readiness

- Serve the generated admin HTML/JS/WASM and `/api/v1/health` from LOGOS.
- Keep every mutation endpoint absent until G1–G3 are green.
- Run the existing migration runner twice and the adversarial invariant suite on
  a fresh PostgreSQL 16 database.
- Prepare the native Firebat bootstrap; one human `sudo` authentication remains
  the installation boundary.

### WP4 — public template

- Produce a distinct public LOGOS bundle with evidence-first discovery cards,
  limitations, reproduction affordances, and correction language.
- Treat it as a visual bundle template, not the final static publication
  generator. G7 remains RED.

### WP5 — delivery pipeline

- Add no-secret CI with strict aggregate required check design.
- Pin every third-party action to a full commit.
- Keep production deploy workflows manual and fail-fast until Cloudflare
  account, Access, Tunnel, domains, environments, and tokens are provisioned.

## Acceptance criteria

- The admin and public entry files pass `largo check --json`.
- Every expected LOGOS test is discovered; no test is skipped or failed.
- At least one finite-domain property earns PROVEN under `--prove`.
- Admin and public `wasm-dom` outputs build twice to identical SHA-256 digests.
- The browser shows the LOGOS admin shell and interactive navigation/form state.
- The gateway health endpoint is served by LOGOS and is same-origin.
- Gateway static serving is development-interpreter evidence only; the current
  native file helpers and binary response parity remain explicit RED gates.
- No mutation route exists.
- PostgreSQL clean apply, repeat apply, verification, and invariant suite pass.
- CI contains no floating action references or error-swallowing step.
- Git contains no credential or developer-specific secret path.

## Exit and next sprint

Sprint 002 begins only after G1–G3 have an accepted implementation path. Its
vertical slice is append-message: read one task thread, submit one idempotent
message command, commit it with audit history in PostgreSQL, refetch, and prove
duplicate-submit and unauthorized cases.
