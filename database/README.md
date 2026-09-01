# MaCSad PostgreSQL operations

MaCSad targets native PostgreSQL 16 on Firebat One (Ubuntu 24.04). PostgreSQL is the authority for mutable state; the content-addressed store (CAS) remains the authority for immutable bytes.

The first native bootstrap requires one human-entered `sudo` authentication. The scripts never request, generate, print, or store a PostgreSQL password.

## First installation on Firebat One

From the repository root on Firebat One:

```bash
bash ops/firebat/bootstrap_postgresql.sh
PGDATABASE=macsad bash database/apply_migrations.sh
```

The bootstrap installs the Ubuntu PostgreSQL 16 packages, creates the `16/main` cluster if needed, binds it to localhost only, configures peer authentication for the local `alejandro` OS account, and enables both PostgreSQL systemd units at boot. The cluster unit is also configured to restart after a failure. Every run ends by checking `is-enabled`, `is-active`, `pg_isready`, the server major version, the listener setting, and the peer rule.

The migration runner uses libpq's normal environment variables and defaults to the local Unix socket and database `macsad`. Keep secrets out of command lines and repository files. In particular, do not put a password in a database URL. Firebat administration uses peer authentication; a future deployed service must receive its own LOGIN role and credential through the deployment secret store, then be granted only the `macsad_app` group role.

## Role model

| Role | LOGIN | Purpose |
|---|---:|---|
| `macsad_owner` | no | Owns the database, schemas, types, tables, views, and routines. Never used by an application connection. |
| `macsad_migrator` | no | Deployment group allowed to `SET ROLE macsad_owner` only while applying reviewed migrations. |
| `macsad_app` | no | Runtime privilege group for a future service-specific LOGIN role. |
| `macsad_reader` | no | Read-only reporting privilege group. |
| `alejandro` | yes | Matches the Firebat OS account through peer auth. It is `NOINHERIT` and must explicitly `SET ROLE` to migrate or administer. |

`PUBLIC` receives neither database connection/temporary privileges nor access to the `public` schema. The application never owns database objects. Bootstrap is idempotent and tightens these attributes again on every run.

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

A dump is not a backup until a clean restore has passed verification. Before MaCSad contains valuable state, establish a scheduled custom-format `pg_dump`, retain it outside Firebat, and regularly restore it into a separately named scratch database on the same PostgreSQL major version. Run `database/verify.sql`, application-level row-count checks, and a representative read-only query against that restore before declaring it usable. The bootstrap intentionally does not pretend to install a backup service.

PostgreSQL and the CAS cannot be snapshotted atomically. At a backup boundary, stop new write-producing work (or establish a controller fence), record the highest durable domain-event/outbox positions and a CAS manifest digest, take both snapshots, then resume. Restore succeeds only when every database artifact reference resolves in the restored CAS; unreferenced CAS bytes are harmless, but missing referenced bytes are a failed restore. Never garbage-collect CAS content newer than the oldest retained database backup boundary.

## Routine checks

```bash
systemctl is-enabled postgresql postgresql@16-main
systemctl is-active postgresql postgresql@16-main
sudo -u postgres pg_isready -h /var/run/postgresql -d postgres
PGDATABASE=macsad bash database/apply_migrations.sh
psql --no-psqlrc --set=ON_ERROR_STOP=1 --dbname=macsad \
  --file=database/verify.sql
```

`apply_migrations.sh` is safe to rerun: with no pending migrations it only revalidates history and the live schema.
