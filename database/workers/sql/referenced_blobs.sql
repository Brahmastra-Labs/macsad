\set ON_ERROR_STOP on
\set QUIET 1

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
\if :{?snapshot_id}
SET TRANSACTION SNAPSHOT :'snapshot_id';
\endif
SET LOCAL ROLE macsad_owner;

SELECT
  pg_catalog.encode(blob.digest, 'hex'),
  blob.byte_length::text,
  blob.storage_provider,
  pg_catalog.encode(pg_catalog.convert_to(blob.storage_locator, 'UTF8'), 'hex')
FROM macsad.blob AS blob
WHERE EXISTS (
  SELECT 1
  FROM macsad.artifact AS artifact
  WHERE artifact.blob_digest = blob.digest
)
ORDER BY blob.digest;

COMMIT;
