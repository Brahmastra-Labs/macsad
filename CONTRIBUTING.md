# Contributing to MaCSad

MaCSad is intentionally small, but its evidence rules are strict. Start with
`AGENTS.md`, then run the complete gate before handing off a change:

```bash
LOGOS_WORKSPACE=/path/to/the/exact/locked/logicaffeine-private \
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
| `docs` | Architecture, deployment, API boundary, and sprint decisions. |

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
6. Run `node scripts/logos-project.mjs audit` to inspect closure sizes/digests,
   then run the complete quality gate. The gate checks the real assembled entry,
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
