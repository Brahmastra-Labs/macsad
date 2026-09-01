# Sprint 001 — trustworthy visible baseline

Status: **in progress**. Source, schema, LOGOS, Compose-model, and CI gates are
implemented. Live Firebat acceptance remains pending the one-time sudo Docker/
Tailscale bootstrap and Headscale enrollment.

## Sprint goal

Deliver websites visibly authored and bundled by LOGOS, establish the repository
and PostgreSQL quality gates, run the private development environment as a
reproducible Firebat Docker Compose stack, and leave explicit RED contracts for
the framework capabilities needed by the first real CRUD slice.

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
6. start the Firebat Compose stack and apply and verify the PostgreSQL schema;
7. open the admin, public preview, and read-only database viewer over the
   Headscale-managed tailnet; and
8. see precise RED framework gates rather than fake CRUD.

## In scope

- Root engineering constitution and automated shortcut scan.
- Exact local LOGOS source/toolchain lock.
- Modular LOGOS admin application with a manifest-locked import closure.
- Modular LOGOS public-site application with a manifest-locked import closure.
- Modular LOGOS development gateway and health contract.
- Deterministic LOGOS unit/property tests with exact test-manifest locking.
- Admin visual system, responsive shell, board, role/process view, research
  overview, operations view, and local-only intake interaction.
- Public discovery landing-page template.
- Sequential quality gate and PostgreSQL schema gate.
- Pinned, hardened Firebat Docker Compose services for PostgreSQL, the LOGOS
  gateway, emitted LOGOS sites, and read-only pgAdmin, plus a one-shot migrator.
- Exact tailnet-IP publication of admin `18080`, public preview `18082`, and
  pgAdmin `8978`; no database host port, wildcard/LAN binding, or Funnel.
- Getting-started and operational runbooks covering the repeatable lifecycle.
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
- Bootstrap Firebat's pinned Docker Engine, Compose, and Tailscale services;
  one human `sudo` authentication and Headscale enrollment remain host
  administration boundaries.
- Build images only from a revision-specific, digest-recorded staging closure:
  the verified `largo` binary, emitted bundles, gateway source/manifest, and
  database migrations. Never mount `logicaffeine-private` into a container.
- Start four restartable services behind the successful one-shot migrator;
  retain PostgreSQL and pgAdmin named volumes across ordinary shutdown.
- Configure pgAdmin with the ACL-constrained `macsad_viewer` login, read-only
  session default, and make
  PostgreSQL reachable only on Compose's internal data network.

### WP4 — public template

- Produce a distinct public LOGOS bundle with evidence-first discovery cards,
  limitations, reproduction affordances, and correction language.
- Treat it as a visual bundle template, not the final static publication
  generator. G7 remains RED.

### WP5 — delivery pipeline

- Add no-secret CI with strict aggregate required check design.
- Pin every third-party action to a full commit.
- Add no production deploy workflow until the Cloudflare account, Access,
  Tunnel, domains, environments, tokens, exact-artifact gate, smoke test, and
  rollback path are provisioned. Once those machine contracts are green, an
  ordinary application release may promote autonomously without a human click.

## Acceptance criteria

- The admin and public entry files pass `largo check --json`.
- Every expected LOGOS test is discovered; no test is skipped or failed.
- At least one finite-domain property earns PROVEN under `--prove`.
- Admin and public `wasm-dom` outputs build twice to identical SHA-256 digests.
- The browser shows the LOGOS admin shell and interactive navigation/form state.
- The gateway health endpoint is served by LOGOS and is same-origin.
- The current health-only gateway has no PostgreSQL adapter and no mutation
  route; neither the UI nor deployment documentation claims CRUD readiness.
- Gateway static serving is development-interpreter evidence only; the current
  native file helpers and binary response parity remain explicit RED gates.
- No mutation route exists.
- PostgreSQL clean apply, repeat apply, verification, and invariant suite pass.
- Compose configuration and policy guardrails pass; `postgres` has no published
  host port and only Firebat's verified tailnet IP publishes `18080`, `18082`,
  and `8978`.
- The four long-running containers become healthy after a Firebat/Docker
  restart, while `migrate` exits successfully and remains safe to rerun.
- pgAdmin can execute representative reads through `macsad_viewer` and cannot
  mutate domain data or perform DDL.
- CI contains no floating action references or error-swallowing step.
- Git contains no credential or developer-specific secret path.

## Exit and next sprint

Sprint 002 begins only after G1–G3 have an accepted implementation path. Its
vertical slice is append-message: read one task thread, submit one idempotent
message command, commit it with audit history in PostgreSQL, refetch, and prove
duplicate-submit and unauthorized cases.
