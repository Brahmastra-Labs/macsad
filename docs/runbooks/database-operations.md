# Database operations runbook

## Authority and access

PostgreSQL 16 is the sole mutable-state authority. It is reachable only on the
Compose `data` network. Humans authenticate through pgAdmin or CLI as
`macsad_viewer`, which inherits the NOLOGIN `macsad_reader` privilege group;
applications use `macsad_runtime`, which inherits only `macsad_app`.

## Apply and verify migrations

Normal deployments run the one-shot migration service automatically. To
recheck the whole environment:

```bash
make up
make verify
```

The migration job computes checksums from immutable files, takes the migration
advisory lock, verifies the ledger, applies each pending migration transaction,
and runs `database/verify.sql`. Never invoke an individual migration file or
edit an applied migration.

## Read-only inspection

```bash
make db-shell
```

The shell authenticates as `macsad_viewer`, whose inherited grants and database
defaults reject writes. pgAdmin registers the same identity and never stores
its password.

## Backup readiness gate

Automated encrypted off-host backup and scratch-restore verification are not
yet provisioned. Material or irreplaceable research data must not be admitted
until the data-worker export/restore task lands and its scheduled run succeeds.

A dump is not a backup until a clean restore passes. A valid future backup
record includes:

- exact PostgreSQL major and image digest;
- custom-format database dump digest;
- schema version and migration-ledger head;
- highest domain-event and outbox positions;
- corresponding immutable-artifact/CAS manifest; and
- a successful scratch restore and application-level check.

Do not claim filesystem volume copying while PostgreSQL is running as a backup.

## Restore rehearsal

Restore only into a separately named scratch database/container on PostgreSQL
16. Run migration-history validation, `database/verify.sql`, field/row-count
checks, and representative reads. Never merge arbitrary dump rows into the live
database; whole-database restore and explicitly typed imports are separate
operations.

## Credential rotation

Compose secret files are bootstrap/runtime inputs, not self-rotating passwords.
For a database login:

1. generate a new value without printing it;
2. alter the exact login role through a controlled administrative session;
3. atomically replace the corresponding mode-0444 secret file inside the
   mode-0700 `.runtime/compose/secrets/` directory;
4. recreate only the consuming service;
5. verify successful new authentication and failed old authentication; and
6. record the rotation without recording the value.

Changing only a secret file does not change PostgreSQL. Changing only
PostgreSQL can strand a service. Rotate both as one operation.
