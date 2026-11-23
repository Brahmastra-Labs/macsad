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
same runner and ledger the rest of MaCSad uses; `database/tests/0004_factory_invariants.sql` and
`database/tests/0005_factory_verifier_invariants.sql` check the factory schema's guarantees.

## Check the verifier's word yourself

The verifier's key is the 32-byte ML-DSA-65 seed in `.runtime/factory/secrets/macsad_verifier_key`
(64 hex digits, written by `secrets.sh`, never printed), mounted into the verifier container as
`/run/secrets/macsad_verifier_key` and named by `MACSAD_VERIFIER_KEY_FILE`. The seed never leaves that
container. Its public half does: the verifier publishes it in `factory.verifier_key` before it signs
anything, the database refuses a key that does not hash to the name it is published under, and nobody can
rewrite or withdraw one.

- `GET /api/v1/verifier-key` answers every published key, newest first:
  `[{"verifier": "verifier-<12 hex>", "publicKeySha": "<sha256>", "publicKey": "<3904 hex>", "registeredAt": <ms>}]`.
- `docker compose -f ops/factory/compose.yaml run --rm verifier verifier key` prints the same record for
  this deployment's key, from the key file, without touching the database — the copy to publish elsewhere.
- `GET /api/v1/problem/results?id=<problem>` answers each attestation with its `publicKeySha` and
  `signature`.

An attestation holds when `sha256(publicKey)` is its `publicKeySha` and its `signature` (hex) is an ML-DSA-65
(FIPS 204) signature, under the context string `macsad-attestation-v1`, of the UTF-8 bytes of

```text
{"schema":"macsad-attestation/1","subject_kind":…,"subject_id":…,"statement_sha":…,"document_sha":…,"verdict_kind":…,"verifier":…,"toolchain_sha":…,"public_key_sha":…}
```

with each value a JSON string, in exactly this order and with no spaces; the attestation's id is `att:` and
the SHA-256 of those bytes. A problem is `solved` only on a `verified` attestation of a proof attempt on
it, made against its accepted statement (`0005_factory_verifier.sql`); the attestation that accepted the
statement says the statement is well formed, never that it is proved.

## What a worker cannot do

A worker proposes; it never decides. It cannot mark anything verified (only the verifier's signed
attestation does), cannot rewrite or delete the trail (the database refuses), cannot finish a unit it no
longer holds (fencing tokens), and cannot buy the same dead end twice (`factory.dead_end`). An attempt that
repeats a dead end is refused `409 dead_end` and its lease is released at once, so the unit goes straight
back on the board; a worker refused that way twice in a row stops. A submission that redeclares a name the
statement or the prelude already binds is refused before the kernel runs.
