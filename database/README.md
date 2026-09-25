# MaCSad PostgreSQL operations

MaCSad is configured to run PostgreSQL 16.15 in the Firebat Docker Compose stack after the one-time host bootstrap. PostgreSQL is the authority for mutable state; the content-addressed store (CAS) remains the authority for immutable bytes. The `postgres` service has no published host port and is reachable only by containers on Compose's internal `data` network.

## Firebat lifecycle

The checked-in entrypoint is [`ops/compose/stack.sh`](../ops/compose/stack.sh). Follow [`GETTING_STARTED.md`](../GETTING_STARTED.md) for host enrollment and first start, and use the procedures in [`docs/runbooks/`](../docs/runbooks/) for operation, recovery, and backup.

The stack defines four continuously running containers: `postgres`, `logos-gateway`, `logos-sites`, and `pgadmin`. The dedicated `migrate` service waits for PostgreSQL health, applies the checksum-verified migration ledger, verifies the schema, and exits successfully before the application containers start. Application startup never migrates.

The named `postgres_data` volume preserves database state across container replacement and `stack.sh down`. Compose applies `restart: unless-stopped` to the long-running services; the host bootstrap enables Docker Engine at Firebat boot. PostgreSQL credentials are generated into the ignored, mode-`0700` `.runtime/compose/secrets/` directory, mounted only into named consumers, and never printed or committed. Individual secret files are mode `0444` solely because local Compose file-backed secrets preserve host bind-mount ownership/mode and must be readable by non-root container UIDs.

PostgreSQL is not published on a host, LAN, or tailnet socket. Operators use the tailnet-only pgAdmin endpoint on port `8978`, which is preconfigured with the constrained `macsad_viewer` login, or execute reviewed administrative commands inside the `postgres` container. Do not add a `5432` host mapping.

## Role model

| Role | LOGIN | Purpose |
|---|---:|---|
| `macsad_owner` | no | Owns the database, schemas, types, tables, views, and routines. Never used by an application connection. |
| `macsad_migrator` | no | Deployment group allowed to `SET ROLE macsad_owner` only while applying reviewed migrations. |
| `macsad_app` | no | Runtime privilege group for a future service-specific LOGIN role. |
| `macsad_reader` | no | Read-only reporting privilege group. |
| `alejandro` | yes | Passwordless human compatibility/audit identity with a SET-only path through `macsad_migrator`; it is not used by unattended deployment. |
| `macsad_deployer` | yes | Nonhuman, `NOINHERIT` one-shot migration login. Its SET-only `macsad_migrator → macsad_owner` chain is available only to the migration container. |
| `macsad_runtime` | yes | Credentialed service login that inherits only `macsad_app`; reserved for the typed LOGOS database adapter. |
| `macsad_viewer` | yes | Credentialed pgAdmin login that inherits only `macsad_reader`, with a read-only session default and strict timeouts. ACLs still deny writes if a session changes that default. |

`PUBLIC` receives neither database connection/temporary privileges nor access to the `public` schema. The application never owns database objects. The PostgreSQL image initializes these roles and grants only when creating an empty data volume; migrations remain safe to rerun against an initialized volume.

## Greenfield `0001` contract

`0001_initial_schema.sql` creates 47 tables including `macsad_meta.schema_migration`, 50 native enum types, and exactly six read views: `macsad.case_board_v`, `macsad.budget_balance_v`, `macsad.model_cost_variance_v`, `macsad.publication_catalog_v`, `macsad.audit_timeline_v`, and `macsad.schema_version_v`.

The database enforces the core closure rules:

- `workspace.github_repository_id` is the immutable identity of the one watched project; owner/name and branch are mutable metadata.
- A tool revision accepts operation rows only before its one-time catalogue seal. Case pins distinguish `source_read` from `operation_invoke`; invocation requires the promoted, compatibility-checked, sealed closure.
- Compiler projections accept inserts only while their `policy_revision` is a candidate, reject updates/deletes, and cannot grow after activation.
- The first task is the compiled entry node. Every successor closes the previous finished task's exact compiled transition, next sequence, and semantically matching `task.transitioned` event.
- `human_decided` attestations require an active human actor and matching membership. Case disposition and eligibility `outcome_code` values must exactly match the selected typed values.
- All resource and money quantities use `numeric(30,12)`. Reservations require an active account period. A model commit settles the same call's exact reservation; corrections append `spend_adjustment` or zero-delta `usage_reconciliation` entries.
- Publication dossiers bind eligible cases to public-safe artifacts. Items are draft-only; preview allocates the batch sequence and freezes the closure/audit head; seal freezes the manifest/signature; a successful attempt is required before publish and before `publication_head` can select it.
- One `audit_stream` row per workspace serializes event sequence and previous-hash links. Inbound states are `received`, `processing`, `completed`, `rejected`, and `dead_letter`; outbox states are `pending`, `publishing`, `delivered`, and `dead_letter`.

## Migration contract

The canonical schema is the ordered set in `database/migrations/`; `0001_initial_schema.sql` is the single create script for the initial schema. The rules are deliberately small and strict:

1. Name files `NNNN_lowercase_slug.sql`, start at `0001`, and keep versions contiguous.
2. A migration is immutable after it is applied anywhere. Fix a mistake with the next numbered migration; never edit, reorder, squash, or delete an applied file.
3. Every file owns one `BEGIN`/`COMMIT`, calls `pg_advisory_xact_lock(hashtextextended('macsad:schema-migration', 0))`, and inserts exactly one row into `macsad_meta.schema_migration` using `decode(:'migration_sha256', 'hex')` before commit.
4. Run migrations only through `database/apply_migrations.sh`. It computes SHA-256 from the bytes on disk, rejects gaps and ledger drift, passes the checksum into `psql`, applies one file at a time with `ON_ERROR_STOP`, validates the resulting ledger row, then runs `database/verify.sql`.
5. Application startup never applies migrations. A deployment runs a dedicated migration step, runs verification, and only then starts the application.

The ledger's checksum is over the exact file bytes. Keep SQL files LF-normalized in Git. A checksum mismatch means history drift, not an invitation to update the ledger.

## Safe evolution

- Use native enums only for deliberately stable, closed state machines. Adding a value is normally the only single-release enum change. Renaming or removing a value requires an expand/backfill/contract sequence; provider names, model IDs, operation keys, and other open vocabularies remain constrained text backed by scoped relations and immutable digests.
- Use expand/backfill/contract for all breaking changes: first add compatible structures, then backfill in bounded and restartable batches, then switch readers/writers, and remove the old structure in a later deployment. Long backfills do not share a transaction with DDL.
- The application binary declares an inclusive minimum and maximum schema version. Startup reads `current_version` from the narrow `macsad.schema_version_v` view and refuses both an older schema and a schema newer than it understands. The application cannot access the migration ledger itself. This protects roll-forward and rollback deployments.
- `database/verify.sql` checks structural invariants and prints a normalized catalog fingerprint. CI or a release manifest records that fingerprint after applying migrations to an empty PostgreSQL 16 database; supplying it as `expected_schema_fingerprint` makes verification fail on catalog drift. Checksums detect migration-history drift; the fingerprint detects out-of-band DDL and grant/owner changes.
- Production fixes are forward-only. Restoring an old application against a newer schema is allowed only when its declared compatibility range includes that schema version.

Example compatibility and fingerprint verification:

```bash
psql --no-psqlrc --set=ON_ERROR_STOP=1 --dbname=macsad \
  --set=minimum_schema_version=1 \
  --set=maximum_schema_version=1 \
  --set=expected_schema_fingerprint=RELEASE_FINGERPRINT \
  --file=database/verify.sql
```

## Backup and restore discipline

A dump is not a backup until a clean restore has passed verification. The reviewed seed, deterministic workspace export, CAS manifest, whole-database backup, and scratch-only restore contracts are specified in [`DATA_WORKERS.md`](DATA_WORKERS.md). The bootstrap intentionally does not pretend to install a backup service or scheduler.

PostgreSQL and the CAS cannot be snapshotted atomically. At a backup boundary, stop new write-producing work (or establish a controller fence), record the highest durable domain-event/outbox positions and a CAS manifest digest, take both snapshots, then resume. Restore succeeds only when every database artifact reference resolves in the restored CAS; unreferenced CAS bytes are harmless, but missing referenced bytes are a failed restore. Never garbage-collect CAS content newer than the oldest retained database backup boundary.

The worker enforces one exported PostgreSQL snapshot for the database boundary, blob-reference list, and custom-format dump, then rejects a changed post-backup boundary. Cross-store quiescence is still an external controller responsibility. Retain the printed backup-manifest SHA-256 in an independent trusted ledger; do not trust a digest supplied only by the bundle it describes.

## Routine checks

```bash
bash ops/compose/stack.sh status
bash ops/compose/stack.sh verify
bash ops/compose/stack.sh logs postgres
bash ops/compose/stack.sh logs migrate
bash database/tests/data_workers_contract.sh
```

`stack.sh up` stages reviewed inputs, builds the images, runs the one-shot migrator, starts the four services, and performs endpoint plus schema checks. `stack.sh verify` proves the exact three tailnet bindings, absence of a database host port, admin/public/pgAdmin health, the `macsad_viewer` login and read-only default, schema version, and write denial after explicitly disabling that default. The migration runner remains safe to rerun: with no pending migrations it only revalidates history and the live schema.


## Lean transaction cohort in Foundation

Migration 0002 adds the fixed Lean command API; 0003 corrects deadline admission
without rewriting the 0002 bytes or ledger. PostgreSQL remains the transaction
authority; these routines do not authenticate browser fields or decide proofs.
The catalog verifier admits only the five exact routine signatures/owners,
return types, languages, volatility, search paths and privileges.

Foundation uses its existing isolated PostgreSQL 16 service and role bootstrap.
After the ordinary clean-database migrate/repeat/verify/invariant checks, it runs
`database/tests/lean_attempt_pg16.py` under a 300-second bound. That cohort creates
only random owned scratch databases. It never starts a service or creates roles.
It runs the original complete worker roundtrip and representative fixture at
schema1, the original schema2 transaction/concurrency/ACL and recovery controls,
then upgrades with 0003 and runs eleven deadline controls plus schema3 recovery.
Historical ledger rows must remain identical. Fresh schema2 and schema3 each
receive unchanged invariant checks and exact full-table recovery comparisons.
Original fixture assertions are not rewritten for the newer schema.

With the existing libpq test connection and a permitted test-admin identity:

```sh
python3 -m unittest discover --start-directory database/tests --pattern 'test_lean_pg16*.py'
MACSAD_TEST_ADMIN_USER=postgres timeout --signal=TERM --kill-after=15s 300s \
  python3 database/tests/lean_attempt_pg16.py --admission-version 3 \
    --evidence-dir /absolute/new-external-evidence-directory
```

The evidence parent must exist outside the checkout and its child must not
exist. It records source hashes, command logs, exact restore comparisons and
`result.json`; successful cleanup and all results are required. Foundation
retains this directory for 14 days, including failed attempts. Upload is not a
passing result. The full local quality gate invokes the same version-aware
cohort when DATABASE_URL is supplied; MACSAD_TEST_ADMIN_USER must have the
existing test-cluster create/drop-database and per-database role-setting rights.

`--admission-version 2` is a bounded regression reproduction, using the identical
new assertions after the unchanged historical 0002. It is expected to fail at
the expired-assignment counterexample; it never converts failure into success.
Foundation explicitly selects version3. An earlier setup failure is not the
intended RED. All migrations must be supplied even for that reproduction; the
cohort stages only the selected historical prefix into its owned databases.

The existing subprocess/direct-child cleanup semantics are retained. Outer
cancellation or a hard timeout can prevent nested cleanup; Foundation's runner
and service are disposable. This does not claim a general descendant-process
sandbox. No arbitrary process scan, process-group kill, backend termination or
forced database drop is added. Application/deployment must still consume the
committed command result through the separately reviewed LOGOS client.
