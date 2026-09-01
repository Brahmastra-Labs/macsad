-- Verify that every MaCSad base-table column has exactly one representative-v1
-- coverage status: at least one non-NULL fixture value, or one reviewed
-- system/operational exception in representative_v1_system_fields.tsv.
-- Run through representative_v1_field_coverage.sh from a migrated database
-- containing only the representative-v1 scenario.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '2min';
SET LOCAL timezone = 'UTC';
SET LOCAL ROLE macsad_owner;

CREATE TEMP TABLE representative_v1_system_field_raw (
  manifest_line bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  schema_name text,
  table_name text,
  column_name text,
  classification text,
  owner text,
  invariant text,
  lifecycle text,
  justification text
) ON COMMIT DROP;

\copy representative_v1_system_field_raw(schema_name, table_name, column_name, classification, owner, invariant, lifecycle, justification) FROM 'database/fixtures/representative_v1_system_fields.tsv' WITH (FORMAT csv, DELIMITER E'\t', QUOTE '"', ESCAPE '"', ENCODING 'UTF8')

DO $manifest_header$
DECLARE
  header representative_v1_system_field_raw%ROWTYPE;
BEGIN
  SELECT * INTO header
  FROM representative_v1_system_field_raw
  WHERE manifest_line = 1;

  IF NOT FOUND OR ROW(
      header.schema_name,
      header.table_name,
      header.column_name,
      header.classification,
      header.owner,
      header.invariant,
      header.lifecycle,
      header.justification
    ) IS DISTINCT FROM ROW(
      'schema_name'::text,
      'table_name'::text,
      'column_name'::text,
      'classification'::text,
      'owner'::text,
      'invariant'::text,
      'lifecycle'::text,
      'justification'::text
    ) THEN
    RAISE EXCEPTION 'representative-v1 system-field manifest has an invalid header'
      USING ERRCODE = '22023';
  END IF;
END
$manifest_header$;

DELETE FROM representative_v1_system_field_raw WHERE manifest_line = 1;

CREATE TEMP TABLE representative_v1_catalog_field (
  schema_name text NOT NULL,
  table_name text NOT NULL,
  column_name text NOT NULL,
  ordinal_position integer NOT NULL,
  PRIMARY KEY (schema_name, table_name, column_name)
) ON COMMIT DROP;

INSERT INTO representative_v1_catalog_field (
  schema_name,
  table_name,
  column_name,
  ordinal_position
)
SELECT
  column_catalog.table_schema,
  column_catalog.table_name,
  column_catalog.column_name,
  column_catalog.ordinal_position
FROM information_schema.columns AS column_catalog
JOIN information_schema.tables AS table_catalog
  ON table_catalog.table_schema = column_catalog.table_schema
 AND table_catalog.table_name = column_catalog.table_name
WHERE table_catalog.table_type = 'BASE TABLE'
  AND column_catalog.table_schema IN ('macsad', 'macsad_meta');

DO $catalog_contract$
DECLARE
  actual_column_count bigint;
  actual_table_count bigint;
BEGIN
  SELECT
    pg_catalog.count(*),
    pg_catalog.count(DISTINCT ROW(schema_name, table_name))
  INTO actual_column_count, actual_table_count
  FROM representative_v1_catalog_field;

  IF actual_table_count <> 47 OR actual_column_count <> 792 THEN
    RAISE EXCEPTION
      'representative-v1 coverage expects 47 base tables and 792 columns; found % tables and % columns',
      actual_table_count,
      actual_column_count
      USING ERRCODE = '55000';
  END IF;
END
$catalog_contract$;

DO $seed_contract$
BEGIN
  IF (SELECT current_version FROM macsad.schema_version_v) <> 1 THEN
    RAISE EXCEPTION 'representative-v1 coverage requires schema version 1'
      USING ERRCODE = '55000';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM macsad.workspace) <> 1
      OR NOT EXISTS (
        SELECT 1
        FROM macsad.workspace
        WHERE id = '10000000-0000-4000-8000-000000000001'
      ) THEN
    RAISE EXCEPTION 'representative-v1 coverage requires only the fixed representative workspace'
      USING ERRCODE = '55000';
  END IF;
END
$seed_contract$;

DO $manifest_shape$
DECLARE
  failures text;
BEGIN
  SELECT pg_catalog.string_agg(
    pg_catalog.format('line %s', manifest_line),
    ', ' ORDER BY manifest_line
  )
  INTO failures
  FROM representative_v1_system_field_raw
  WHERE schema_name IS NULL OR pg_catalog.btrim(schema_name) = ''
     OR table_name IS NULL OR pg_catalog.btrim(table_name) = ''
     OR column_name IS NULL OR pg_catalog.btrim(column_name) = ''
     OR classification IS NULL OR pg_catalog.btrim(classification) = ''
     OR owner IS NULL OR pg_catalog.btrim(owner) = ''
     OR invariant IS NULL OR pg_catalog.btrim(invariant) = ''
     OR lifecycle IS NULL OR pg_catalog.btrim(lifecycle) = ''
     OR justification IS NULL OR pg_catalog.btrim(justification) = '';

  IF failures IS NOT NULL THEN
    RAISE EXCEPTION 'system-field manifest contains blank required values at %', failures
      USING ERRCODE = '22023';
  END IF;

  SELECT pg_catalog.string_agg(
    pg_catalog.format('line %s=%L', manifest_line, classification),
    ', ' ORDER BY manifest_line
  )
  INTO failures
  FROM representative_v1_system_field_raw
  WHERE classification NOT IN ('operational', 'system_managed');

  IF failures IS NOT NULL THEN
    RAISE EXCEPTION 'system-field manifest contains unknown classifications: %', failures
      USING ERRCODE = '22023';
  END IF;

  SELECT pg_catalog.string_agg(field_key, ', ' ORDER BY field_key)
  INTO failures
  FROM (
    SELECT pg_catalog.format('%I.%I.%I', schema_name, table_name, column_name) AS field_key
    FROM representative_v1_system_field_raw
    GROUP BY schema_name, table_name, column_name
    HAVING pg_catalog.count(*) > 1
    ORDER BY schema_name, table_name, column_name
    LIMIT 20
  ) AS duplicate_field;

  IF failures IS NOT NULL THEN
    RAISE EXCEPTION 'system-field manifest contains duplicate classifications: %', failures
      USING ERRCODE = '23505';
  END IF;

  SELECT pg_catalog.string_agg(field_key, ', ' ORDER BY field_key)
  INTO failures
  FROM (
    SELECT pg_catalog.format('%I.%I.%I', manifest.schema_name, manifest.table_name,
      manifest.column_name) AS field_key
    FROM representative_v1_system_field_raw AS manifest
    LEFT JOIN representative_v1_catalog_field AS catalog
      USING (schema_name, table_name, column_name)
    WHERE catalog.column_name IS NULL
    ORDER BY manifest.schema_name, manifest.table_name, manifest.column_name
    LIMIT 20
  ) AS stale_field;

  IF failures IS NOT NULL THEN
    RAISE EXCEPTION 'system-field manifest contains unknown or stale fields: %', failures
      USING ERRCODE = '42703';
  END IF;
END
$manifest_shape$;

CREATE TEMP TABLE representative_v1_field_observation (
  schema_name text NOT NULL,
  table_name text NOT NULL,
  column_name text NOT NULL,
  has_non_null_fixture_value boolean NOT NULL,
  PRIMARY KEY (schema_name, table_name, column_name)
) ON COMMIT DROP;

DO $observe_fixture$
DECLARE
  field_record record;
  has_non_null_value boolean;
BEGIN
  FOR field_record IN
    SELECT schema_name, table_name, column_name
    FROM representative_v1_catalog_field
    ORDER BY schema_name, table_name, ordinal_position
  LOOP
    IF field_record.schema_name = 'macsad_meta'
        AND field_record.table_name = 'schema_migration' THEN
      -- The ledger exists before representative-v1 is applied. Its values are
      -- migration provenance, never fixture coverage, even though they are
      -- necessarily non-NULL in a migrated database.
      has_non_null_value := false;
    ELSE
      EXECUTE pg_catalog.format(
        'SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I IS NOT NULL)',
        field_record.schema_name,
        field_record.table_name,
        field_record.column_name
      ) INTO has_non_null_value;
    END IF;

    INSERT INTO representative_v1_field_observation (
      schema_name,
      table_name,
      column_name,
      has_non_null_fixture_value
    ) VALUES (
      field_record.schema_name,
      field_record.table_name,
      field_record.column_name,
      has_non_null_value
    );
  END LOOP;
END
$observe_fixture$;

DO $exclusive_classification$
DECLARE
  failures text;
BEGIN
  SELECT pg_catalog.string_agg(field_key, ', ' ORDER BY field_key)
  INTO failures
  FROM (
    SELECT pg_catalog.format('%I.%I.%I', observation.schema_name,
      observation.table_name, observation.column_name) AS field_key
    FROM representative_v1_field_observation AS observation
    JOIN representative_v1_system_field_raw AS manifest
      USING (schema_name, table_name, column_name)
    WHERE observation.has_non_null_fixture_value
    ORDER BY observation.schema_name, observation.table_name, observation.column_name
    LIMIT 20
  ) AS redundant_field;

  IF failures IS NOT NULL THEN
    RAISE EXCEPTION
      'system-field manifest contains stale or duplicate fixture classifications: %',
      failures
      USING ERRCODE = '23505';
  END IF;

  SELECT pg_catalog.string_agg(field_key, ', ' ORDER BY field_key)
  INTO failures
  FROM (
    SELECT pg_catalog.format('%I.%I.%I', observation.schema_name,
      observation.table_name, observation.column_name) AS field_key
    FROM representative_v1_field_observation AS observation
    LEFT JOIN representative_v1_system_field_raw AS manifest
      USING (schema_name, table_name, column_name)
    WHERE NOT observation.has_non_null_fixture_value
      AND manifest.column_name IS NULL
    ORDER BY observation.schema_name, observation.table_name, observation.column_name
    LIMIT 20
  ) AS uncovered_field;

  IF failures IS NOT NULL THEN
    RAISE EXCEPTION 'representative-v1 has uncovered base-table columns: %', failures
      USING ERRCODE = '23514';
  END IF;
END
$exclusive_classification$;

SELECT
  pg_catalog.count(*) FILTER (WHERE observation.has_non_null_fixture_value)
    AS fixture_covered_columns,
  pg_catalog.count(*) FILTER (WHERE NOT observation.has_non_null_fixture_value)
    AS justified_system_columns,
  pg_catalog.count(*) AS total_base_table_columns
FROM representative_v1_field_observation AS observation;

ROLLBACK;
