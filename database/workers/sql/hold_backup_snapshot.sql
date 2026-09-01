\set ON_ERROR_STOP on
\set QUIET 1

BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE;
SET LOCAL ROLE macsad_owner;

SELECT pg_catalog.pg_export_snapshot() AS snapshot_id
\gset
\echo :snapshot_id

-- The backup worker releases stdin only after every snapshot consumer has
-- finished. Keeping this transaction open makes the exported snapshot valid.
\prompt release_signal

COMMIT;
