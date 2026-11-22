# The math factory — running it and contributing to it

The factory turns tokens into kernel-checked mathematics. Problems come from Alejandro Zarzuelo's
organization of open mathematics (the OPDP difficulty atlas, the formalization-lab corpus and Google
DeepMind's formal-conjectures). Statements are LOGOS documents, proofs are LOGOS, and a result counts only
when the LOGOS kernel checks it — first on the contributor's machine, then again on the trusted verifier,
which signs what it accepts. Every attempt, accepted or not, is appended to the problem's hash-chained
trail, so the next attempt starts from what was already tried and nobody pays twice for a dead end.

## Contribute tokens

All a contributor needs is Docker and an OpenRouter key. Create a dedicated key with a credit limit at
<https://openrouter.ai/settings/keys>; the key stays on your machine and is never sent to MaCSad.

```bash
docker run --rm \
  -e OPENROUTER_API_KEY=sk-or-... \
  -e MACSAD_BUDGET_USD=5 \
  -e MACSAD_CONTRIBUTOR=your-handle \
  -e MACSAD_COORDINATOR=https://macsad.com \
  macsad/factory:local worker
```

Optional: `MACSAD_FOCUS` picks what your budget works on (a problem id or a category from the site's
board), `MACSAD_MODEL` overrides the strategy's model. The worker stops on its own when the budget is
spent, and records that on the trail.

## Run the factory

LOGOS comes from the public repository, github.com/Brahmastra-Labs/logicaffeine, at the exact commit in
`ops/factory/logos.pin`. The factory needs the std modules `process.lg`, `httpclient.lg` and `s3.lg`; `build.sh`
refuses a pinned revision that lacks them, so pin a public commit that includes them.


```bash
ops/factory/build.sh      # builds largo from public LOGOS at ops/factory/logos.pin + the factory binary
ops/factory/secrets.sh    # creates local credentials under .runtime/factory/secrets (never printed)
docker build -t macsad/factory:local -f ops/factory/factory.Dockerfile ops/factory
docker compose -f ops/factory/compose.yaml up -d                      # database, coordinator, verifier
docker compose -f ops/factory/compose.yaml --profile public up -d     # + the macsad.com tunnel
docker compose -f ops/factory/compose.yaml --profile contribute up    # + a local worker
```

The coordinator is published on `127.0.0.1:18090` only. The public site is reached through a Cloudflare
Tunnel: create a tunnel for `macsad.com` in Cloudflare Zero Trust, route it to `http://coordinator:8080`,
and paste its token into `.runtime/factory/secrets/cloudflare_tunnel_token`. Artifacts go to R2 when
`.runtime/factory/secrets/macsad_r2_credentials` holds `ACCESS_KEY_ID:SECRET_ACCESS_KEY` and
`MACSAD_R2_ENDPOINT`/`MACSAD_R2_BUCKET` name the bucket; otherwise they stay in the coordinator's volume.

PostgreSQL is never published to the host. Migrations are applied by `database/apply_migrations.sh`, the
same runner and ledger the rest of MaCSad uses; `database/tests/0004_factory_invariants.sql` checks the
factory schema's guarantees.

## What a worker cannot do

A worker proposes; it never decides. It cannot mark anything verified (only the verifier's signed
attestation does), cannot rewrite or delete the trail (the database refuses), cannot finish a unit it no
longer holds (fencing tokens), and cannot buy the same dead end twice (`factory.dead_end`). A submission
that redeclares a name the statement or the prelude already binds is refused before the kernel runs.
