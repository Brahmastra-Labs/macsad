# Contributing to MaCSad

MaCSad is intentionally small, but its evidence rules are strict. Start with
`GETTING_STARTED.md` and `AGENTS.md`. Choose one bounded outcome, name its
acceptance test, and work RED → GREEN → REFACTOR. Run the complete gate before
handing off a change:

```bash
LOGOS_WORKSPACE=/path/to/the/exact/locked/logicaffeine \
bash scripts/quality-gate.sh
```

Set `DATABASE_URL` to a fresh PostgreSQL 16 test database and
`MACSAD_REQUIRE_DATABASE=1` when producing full database evidence. Never commit
that URL or place it in a shell transcript.

## Repository layout

| Path | Responsibility |
|---|---|
| `logos/admin` | Private administrative browser application, authored in LOGOS. |
| `logos/public-site` | Public evidence-first projection template, authored in LOGOS. |
| `logos/gateway` | Read-only development gateway while authenticated command transport remains RED. |
| `host_adapters` | Mechanical capabilities absent from the pinned LOGOS revision; no domain policy. |
| `database` | Immutable PostgreSQL migrations, verification, and invariant tests. |
| `tests/logos-module-manifest.json` | Exact project entries and test-bearing leaf contracts. |
| `scripts` | Pinned toolchain, import-closure, no-false-green, and deterministic-build gates. |
| `ops/compose` | Firebat service topology, pinned image builds, and private runtime lifecycle. |
| `ops/firebat` | Privileged one-time host bootstrap only. |
| `docs` | Architecture, deployment, API boundary, and sprint decisions. |

## Test matrix

| Command | Intended use | Evidence |
|---|---|---|
| `make lint-logos` | Fast LOGOS source-shape iteration | Exact module/definition/line limits, behavior duplication, markers, orphan audit, and immutable scoped-CSS debt |
| `make test-foundation` | Fast credential-free iteration | Source/module/Compose guardrails and host-adapter unit contracts |
| `make test` | Required local handoff gate | Exact private LOGOS tests and deterministic bundles, plus the foundation gate |
| `MACSAD_REQUIRE_DATABASE=1 DATABASE_URL=… make test` | Schema or persistence work | Fresh PG16 migrate/repeat/verify/invariants in addition to the full gate |
| `make compose-config` | Environment or container change | Fully resolved Compose model after local configuration |
| `make up && make verify` | Firebat runtime change | Built containers, startup ordering, routes, and schema compatibility |

Never describe `compose config` as a running-stack test or a health response as
CRUD evidence. Record the exact command and outcome in the pull request without
including environment contents, connection strings, or secrets.

## Adding or moving a LOGOS module

1. Use a lowercase `src/**/*.lg` filename. Do not place LOGOS source elsewhere
   in the project and do not use symlinks.
2. Import with one explicit contained path per line, for example:

   ```logos
   Import Board from "./board.lg".
   ```

   Imports must be the single, contiguous first nonempty paragraph after the
   module's `#` title. A blank line, prose paragraph, or `##` section ends the
   pinned compiler's import scan; any later `Import` therefore fails the audit.
   Bare imports, selective aliases, Markdown-link imports, `## Requires`, and
   every `Largo.toml` dependency form are forbidden. MaCSad uses only the exact
   local source and binary locked in `.macsad/toolchains/logos.lock.toml`.
3. Preserve the logical edge from the module that actually owns the dependency.
   The current entry must also import every non-entry module as a clearly
   registered compiler-scope compatibility lock. This redundant entry closure
   is temporary framework scaffolding, not application layering.
4. Keep the logical graph rooted at the manifest's `logicalRoot`; cycles and
   modules reachable only from the compatibility lock fail.
5. Put `## Test` blocks only in import-free leaf modules with no `## Main`.
   Register the leaf and its exact test names in the module manifest. A new or
   moved test that is not registered fails before LOGOS runs.
6. Run `make lint-logos`, then `node scripts/logos-project.mjs audit` to inspect
   closure sizes/digests. The source policy and its honest baseline-debt rules
   are documented in `docs/standards/logos-source-quality.md`.
7. Run the complete quality gate. The gate checks the real assembled entry,
   rejects every diagnostic outside the exact compatibility-warning identities
   committed beside the entry lock, and runs each exact leaf source through a
   hard-linked temporary project so imported tests cannot disappear.

## Change discipline

- Add the next numbered migration; never edit an applied migration.
- Keep domain decisions in LOGOS and live-state constraints in PostgreSQL.
- Add host code only for a capability LOGOS cannot express, with a contract test
  proving that the adapter remains mechanical.
- Never weaken a test, skip budget, manifest identity, toolchain pin, action
  digest, or deployment boundary to get green.
- Do not commit generated `target/`, local environments, credentials, caches, or
  machine-specific paths.

## PostgreSQL changes

1. Add the next contiguous, immutable numbered migration. Every migration owns
   its transaction, advisory lock, ledger row, and checksum marker.
2. Prefer typed columns, domains, enums, foreign keys, and explicit checks for
   durable concepts. Use JSONB only for versioned/evolving payloads with a
   documented schema and digest.
3. Add invariant/race tests at the same time. Run against an empty PG16 database
   and repeat the migration runner to prove idempotent orchestration.
4. Use expand → backfill → contract across releases for destructive shape
   changes. Never edit an applied migration or infer missing history.

## Compose and operations changes

- Keep `.env.example`, `compose.yaml`, the runtime generator, documentation, and
  guardrail expectations in sync. Examples contain shapes only, never values.
- Every pulled image is tag-and-digest pinned; every local build consumes only
  exact staged inputs. Do not mount a source repository at runtime.
- Prove health/readiness, least privilege, named-volume persistence, and the
  absence of wildcard/LAN/database exposure.
- Update the relevant runbook and ADR when a cross-cutting operating decision
  changes.
- The deployment harness admits only a fully committed tree: image tags and
  staged inputs are bound to `HEAD`, and any untracked file fails closed. On a
  feature branch, review and commit a coherent local checkpoint, run
  `PGADMIN_DEFAULT_EMAIL=YOUR-REAL-OWNER-EMAIL make configure`, then exercise
  `make up && make verify`. Fix failures in a follow-up local commit. Do not
  push the branch until its required gates pass.

## Commits and pull requests

- Branch from current `main`; keep one concern per branch and coherent commit.
- Do not include unrelated user work, generated bundles, `.runtime/`, dumps, or
  credentials. Review `git diff --check` and the full staged diff.
- Explain the user-visible outcome, architectural boundary, test evidence,
  limitations, and any operator action. A red or unavailable gate is surfaced,
  never hidden with retries, skips, or weakened assertions.
- Foundation CI is credential-free. Never execute untrusted pull-request code
  on the owned Firebat host; a future self-hosted runner requires isolation and
  a separate security decision.
