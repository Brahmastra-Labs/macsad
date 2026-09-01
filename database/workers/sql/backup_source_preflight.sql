\set ON_ERROR_STOP on
\set QUIET 1

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
\if :{?snapshot_id}
SET TRANSACTION SNAPSHOT :'snapshot_id';
\endif
SET LOCAL ROLE macsad_owner;
SET LOCAL search_path = pg_catalog;

DO $preflight$
DECLARE
  bad_count bigint;
BEGIN
  SELECT pg_catalog.count(*)
  INTO bad_count
  FROM pg_catalog.pg_namespace AS namespace
  WHERE namespace.nspname NOT IN (
      'pg_catalog', 'information_schema', 'public', 'macsad', 'macsad_meta'
    )
    AND namespace.nspname NOT LIKE 'pg_toast%'
    AND namespace.nspname NOT LIKE 'pg_temp_%';

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% unreviewed source schema(s) make backup unsafe', bad_count;
  END IF;

  IF pg_catalog.to_regnamespace('macsad') IS NULL
      OR pg_catalog.to_regnamespace('macsad_meta') IS NULL THEN
    RAISE EXCEPTION 'reviewed MaCSad source schemas are missing';
  END IF;
END
$preflight$;

COMMIT;
