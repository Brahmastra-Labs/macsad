# MaCSad data-worker contracts

These commands are narrow PostgreSQL 16 operator tools. They seed one reviewed
scenario, export read-only workspace projections, and create or verify a whole
database disaster-recovery bundle. They are not an application persistence
adapter, a generic ETL framework, or a workspace merge facility.

There is deliberately no generic importer. The v1 schema has no row-level
security, its application and reader roles can read every table, and `actor`,
`actor_identity`, and `blob` are global rather than workspace-owned. Importing
one workspace while preserving foreign-key closure, append-only history,
idempotency, global identities, and the audit hash chain therefore needs a
separate reviewed domain design. The workspace export is an operator-only
observational package; authorization of the requested workspace remains the
caller's responsibility.

## Representative scenario and field coverage

`database/fixtures/representative_v1.sql` is an inert scenario for a freshly
migrated scratch database. It uses fixed semantic UUIDs, UTC timestamps, JSON,
digests, quantities, repository identities, and state transitions. One
transaction validates that the target is empty, populates every domain table,
forces deferred constraints, checks final row counts and the complete ten-event
audit chain, and commits only when every assertion passes. The migration runner
separately owns and populates the schema-migration ledger, leaving every one of
the 47 v1 base tables exercised.

The scenario covers mathematics and computer-science cases; collaboration,
handoff, execution lease/cancellation/outcomes, tool and model usage, all budget
entry kinds, command/inbound/event/outbox causation, attestation, and initial and
correcting publication lifecycles. Routine-generated budget-entry UUIDs and
trigger-maintained timestamps are operational results rather than semantic
fixture inputs. They are exercised, preserved in backups, and intentionally
excluded from the deterministic workspace projection package.

Run it only against a disposable, empty, migrated database:

```bash
PGDATABASE=macsad_scratch bash database/apply_migrations.sh
PGDATABASE=macsad_scratch bash database/workers/seed_representative_v1.sh
PGDATABASE=macsad_scratch bash database/tests/representative_v1_field_coverage.sh
```

The field checker reads the PostgreSQL catalog and fails on a new, missing,
duplicate, stale, or redundantly classified field. Its v1 result is exactly 792
base-table fields: 785 non-null fixture-covered fields and seven reviewed
exceptions. Six exceptions are the migration ledger's runner/database-owned
provenance; the seventh is `model_call.error_code`, which is correctly null in
the successful reconciled scenario and belongs to a dedicated failed-call
scenario. Each exception records its owner, invariant, lifecycle, and reason in
`database/fixtures/representative_v1_system_fields.tsv`.

## Deterministic workspace view export

```bash
PGDATABASE=macsad database/workers/export_workspace_views.sh \
  10000000-0000-4000-8000-000000000001 /secure/output/workspace.ndjson
```

The worker validates the canonical UUID, PostgreSQL client/server major, and a
new output path outside the repository before opening a read-only repeatable-read
transaction. It selects only the requested workspace from the five operational
views, uses fixed record groups and sort keys, and atomically publishes without
overwriting an existing path.

The first line is a `macsad-workspace-views/1` header. Every later line has an
explicit record schema; whole-row JSON conversion is forbidden. The wire types
are lowercase canonical UUID strings, lowercase hexadecimal digests, decimal
integer strings, exact 12-fractional-digit numeric strings, UTC RFC 3339
timestamps with six fractional digits, JSON booleans/nulls, PostgreSQL 16
normalized JSON, and stored UTF-8 text without added Unicode normalization.
Tests parse every line, compare unchanged runs, compare two independent fresh
seeds byte for byte, and use a second-workspace sentinel to reject tenant bleed.

This package is deterministic. A custom-format `pg_dump` is not: it is a
whole-database recovery archive and is not promised to be byte-identical across
runs.

## CAS manifest

Backup and restore accept a tab-separated `macsad-cas-manifest/1` file:

```text
format<TAB>macsad-cas-manifest/1
blob<TAB>sha256_lower_hex<TAB>byte_length<TAB>provider_key<TAB>storage_locator_utf8_hex
```

The header alone is valid for an empty database. Blob digests must be unique;
length is a nonnegative decimal integer; provider keys use
`[a-z][a-z0-9._-]*`; and the locator is even-length lowercase hex encoding of
the exact stored UTF-8 bytes, so tabs and newlines cannot corrupt framing. The
manifest contains references, not credentials. Never place a secret in a
storage locator or in a repository file. Both backup and restore copy the
caller-owned manifest into private staging, then validate, hash, compare, and
reuse only those staged bytes.

## Whole-database backup

First establish a real controller fence that stops new PostgreSQL and CAS
writes, persist auditable evidence of that fence, and calculate the evidence
file's SHA-256. The digest argument records that external evidence; the shell
worker cannot itself prove that an application controller is quiescent.

```bash
PGDATABASE=macsad database/workers/backup_database.sh \
  /secure/backups/macsad-2026-08-31 \
  /secure/manifests/cas.tsv \
  WRITE_FENCE_EVIDENCE_SHA256
```

The worker verifies the live schema, PostgreSQL 16, input manifests, CAS
closure, and output destination. One exported serializable, read-only,
deferrable snapshot is shared by the 47-table boundary, referenced-blob list,
and `pg_dump`. A post-snapshot boundary comparison also rejects concurrent
database mutation. Mismatch comparisons stream through temporary files rather
than shell variables. Snapshot and post-backup preflights reject any unreviewed
user schema, and `pg_dump` is independently restricted to `macsad` and
`macsad_meta`, so unrelated database objects cannot enter the archive.

The private, atomically published directory contains exactly:

- `database.dump` — uncompressed PostgreSQL custom-format archive;
- `boundary.tsv` — explicit table counts and durable workspace heads;
- `referenced_blobs.tsv` — sorted exact blob references from the same snapshot;
- `manifest.tsv` — versions, schema fingerprint, sizes, digests, fence evidence,
  and snapshot-consistency declaration.

Record the printed `manifest.tsv` SHA-256 in an independent trusted release or
backup ledger. A manifest stored only beside its archive is self-described, not
authenticated.

## Scratch-only restore

Create a new PostgreSQL 16 database from `template0`, owned by `macsad_owner`,
with the reviewed roles and locked-down `public` ACL. Its name must begin with
`macsad_restore_`. Never point the worker at a live database.

```bash
PGDATABASE=macsad_restore_drill database/workers/restore_database.sh \
  /secure/backups/macsad-2026-08-31 \
  /secure/manifests/cas.tsv \
  EXTERNALLY_TRUSTED_MANIFEST_SHA256
```

Before `pg_restore` can execute archive SQL, the worker copies the exact
four-file bundle into private staging, verifies the externally trusted manifest
digest, all member digests and sizes, the CAS manifest, both PostgreSQL 16
clients, the target server, target name, owner, schemas, objects, and ACLs.
Restore uses `--single-transaction --exit-on-error --no-owner
--role=macsad_owner`; it never uses `--clean`, `--create`, disabled triggers,
parallel restore, or data-only restore.

After the archive transaction, verification checks the exact archived schema,
runs only forward migrations, checks the complete gapless audit chain and
artifact/blob metadata, regenerates and exact-compares the restored boundary
and referenced-blob list, and verifies restored CAS closure. The current v1
contract fails closed unless the checkout can verify the archive's exact schema;
support for restoring an older schema will require a version-specific pre-migrate
verifier. A post-restore verification failure can leave only the separately
named scratch database for inspection; the worker never promotes it or mutates a
live database.

Run the validation-before-effects contract without PostgreSQL, and the full
credential-free drill with an administrative test role:

```bash
bash database/tests/data_workers_contract.sh
MACSAD_TEST_ADMIN_USER=postgres bash database/tests/data_workers_roundtrip.sh
```

The drill includes synchronized caller-manifest replacement during backup and
restore, an unreviewed source schema containing code and data, an incomplete
CAS, an untrusted bundle digest, dirty public type and ACL targets, two
independent seeds, a second-workspace isolation sentinel, and the successful
end-to-end restore. Every rejected backup leaves no published directory and
every rejected restore leaves the scratch database unmodified.

## Schema audit notes requiring coordination

No schema change is authorized or included in this workstream. All current
fields were retained and either fixture-covered or explicitly justified. The
audit found two potential invariant gaps that need a domain decision and RED
test before any forward migration is proposed:

- `message_mention` can name a global actor without proving active membership
  in the message workspace. Collaboration/inbox ownership, the intended
  cross-workspace behavior, and the mention lifecycle must be settled first.
- A redistribution-allowed public artifact can currently pass publication
  dossier checks with null license and attribution. Publication must define
  when those values are mandatory before tightening the validator.

The audit also flags clusters for a later bloat review, not deletion:
supervisor fields on policy/membership records; duplicated locator/connection
and provenance/license concepts; blob encoding/compression/provider checksums;
the several repository/toolchain/manifest closure digests; optional provider
tail fields on model calls; and state/version on threads. Each remains in v1 and
is exercised. A future proposal must provide a concrete real-world use case,
domain owner, invariant, lifecycle, compatibility plan, and test for every field
it adds, retains with new meaning, or removes.
