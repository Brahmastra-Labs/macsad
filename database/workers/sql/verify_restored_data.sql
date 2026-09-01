\set ON_ERROR_STOP on

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE macsad_owner;
SET LOCAL search_path = pg_catalog;

DO $verify_restored_data$
DECLARE
  bad_count bigint;
BEGIN
  SELECT pg_catalog.count(*)
  INTO bad_count
  FROM (
    SELECT
      event.workspace_id,
      event.workspace_sequence_no,
      event.previous_event_hash,
      pg_catalog.row_number() OVER (
        PARTITION BY event.workspace_id
        ORDER BY event.workspace_sequence_no
      ) AS expected_sequence,
      pg_catalog.lag(event.event_hash) OVER (
        PARTITION BY event.workspace_id
        ORDER BY event.workspace_sequence_no
      ) AS expected_previous_hash
    FROM macsad.domain_event AS event
  ) AS chain
  WHERE chain.workspace_sequence_no <> chain.expected_sequence
     OR chain.previous_event_hash IS DISTINCT FROM chain.expected_previous_hash;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% restored domain event(s) break the gapless previous-hash chain', bad_count;
  END IF;

  SELECT pg_catalog.count(*)
  INTO bad_count
  FROM macsad.audit_stream AS stream
  LEFT JOIN LATERAL (
    SELECT
      pg_catalog.count(*) AS event_count,
      pg_catalog.max(event.workspace_sequence_no) AS last_sequence
    FROM macsad.domain_event AS event
    WHERE event.workspace_id = stream.workspace_id
  ) AS events ON true
  WHERE stream.last_workspace_sequence <> COALESCE(events.last_sequence, 0)
     OR stream.version <> events.event_count;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% restored audit stream(s) disagree with complete event history', bad_count;
  END IF;

  SELECT pg_catalog.count(*)
  INTO bad_count
  FROM macsad.artifact AS artifact
  LEFT JOIN macsad.blob AS blob ON blob.digest = artifact.blob_digest
  WHERE blob.digest IS NULL;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% restored artifact metadata row(s) lack blob metadata', bad_count;
  END IF;
END
$verify_restored_data$;

COMMIT;
\echo 'MaCSad restored-data verification passed.'
