\set ON_ERROR_STOP on
\set QUIET 1

DO $preflight$
DECLARE
  database_owner name;
  bad_count bigint;
BEGIN
  IF current_setting('server_version_num')::integer < 160000
      OR current_setting('server_version_num')::integer >= 170000 THEN
    RAISE EXCEPTION 'restore target server must be PostgreSQL 16; found %',
      current_setting('server_version_num');
  END IF;

  SELECT pg_catalog.pg_get_userbyid(datdba)
  INTO STRICT database_owner
  FROM pg_catalog.pg_database
  WHERE datname = current_database();
  IF database_owner IS DISTINCT FROM 'macsad_owner'::name THEN
    RAISE EXCEPTION 'restore target must be owned by macsad_owner; found %', database_owner;
  END IF;

  SELECT pg_catalog.count(*) INTO bad_count
  FROM pg_catalog.pg_namespace AS namespace
  WHERE namespace.nspname NOT IN ('pg_catalog', 'information_schema', 'public')
    AND namespace.nspname !~ '^pg_toast';
  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'restore target contains non-template schemas';
  END IF;

  SELECT pg_catalog.count(*) INTO bad_count
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public';
  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'restore target public schema contains relations';
  END IF;

  SELECT pg_catalog.count(*) INTO bad_count
  FROM pg_catalog.pg_proc AS routine
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = routine.pronamespace
  WHERE namespace.nspname = 'public';
  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'restore target public schema contains routines';
  END IF;

  SELECT pg_catalog.count(*) INTO bad_count
  FROM pg_catalog.pg_database AS database
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(database.datacl, pg_catalog.acldefault('d', database.datdba))
  ) AS privilege
  WHERE database.datname = current_database()
    AND privilege.grantee = 0
    AND privilege.privilege_type IN ('CONNECT', 'TEMPORARY', 'CREATE');
  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'PUBLIC retains privileges on restore target database';
  END IF;
END
$preflight$;
