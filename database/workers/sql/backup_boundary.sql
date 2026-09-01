\set ON_ERROR_STOP on
\set QUIET 1

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
\if :{?snapshot_id}
SET TRANSACTION SNAPSHOT :'snapshot_id';
\endif
SET LOCAL ROLE macsad_owner;

WITH table_count_arrays AS (
  SELECT
    ARRAY[
      'macsad_meta.schema_migration',
      'macsad.actor',
      'macsad.actor_identity',
      'macsad.artifact',
      'macsad.attestation',
      'macsad.attestation_artifact',
      'macsad.audit_stream',
      'macsad.blob',
      'macsad.budget_account',
      'macsad.budget_entry',
      'macsad.capability_grant',
      'macsad.claim',
      'macsad.command_receipt',
      'macsad.domain_event',
      'macsad.execution',
      'macsad.execution_artifact',
      'macsad.execution_tool_use',
      'macsad.inbound_delivery',
      'macsad.membership',
      'macsad.message',
      'macsad.message_mention',
      'macsad.model_call',
      'macsad.model_usage_observation',
      'macsad.outbox_message',
      'macsad.policy_member_profile',
      'macsad.policy_node',
      'macsad.policy_node_tool_operation',
      'macsad.policy_process',
      'macsad.policy_revision',
      'macsad.policy_transition',
      'macsad.problem_revision',
      'macsad.publication_attempt',
      'macsad.publication_batch',
      'macsad.publication_dossier',
      'macsad.publication_head',
      'macsad.publication_item',
      'macsad.research_case',
      'macsad.research_case_tool_revision',
      'macsad.task',
      'macsad.task_assignment',
      'macsad.task_transition',
      'macsad.thread',
      'macsad.tool_operation_manifest',
      'macsad.tool_repository',
      'macsad.tool_repository_revision',
      'macsad.workspace',
      'macsad.workspace_snapshot'
    ]::text[] AS relation_names,
    ARRAY[
      (SELECT pg_catalog.count(*) FROM macsad_meta.schema_migration),
      (SELECT pg_catalog.count(*) FROM macsad.actor),
      (SELECT pg_catalog.count(*) FROM macsad.actor_identity),
      (SELECT pg_catalog.count(*) FROM macsad.artifact),
      (SELECT pg_catalog.count(*) FROM macsad.attestation),
      (SELECT pg_catalog.count(*) FROM macsad.attestation_artifact),
      (SELECT pg_catalog.count(*) FROM macsad.audit_stream),
      (SELECT pg_catalog.count(*) FROM macsad.blob),
      (SELECT pg_catalog.count(*) FROM macsad.budget_account),
      (SELECT pg_catalog.count(*) FROM macsad.budget_entry),
      (SELECT pg_catalog.count(*) FROM macsad.capability_grant),
      (SELECT pg_catalog.count(*) FROM macsad.claim),
      (SELECT pg_catalog.count(*) FROM macsad.command_receipt),
      (SELECT pg_catalog.count(*) FROM macsad.domain_event),
      (SELECT pg_catalog.count(*) FROM macsad.execution),
      (SELECT pg_catalog.count(*) FROM macsad.execution_artifact),
      (SELECT pg_catalog.count(*) FROM macsad.execution_tool_use),
      (SELECT pg_catalog.count(*) FROM macsad.inbound_delivery),
      (SELECT pg_catalog.count(*) FROM macsad.membership),
      (SELECT pg_catalog.count(*) FROM macsad.message),
      (SELECT pg_catalog.count(*) FROM macsad.message_mention),
      (SELECT pg_catalog.count(*) FROM macsad.model_call),
      (SELECT pg_catalog.count(*) FROM macsad.model_usage_observation),
      (SELECT pg_catalog.count(*) FROM macsad.outbox_message),
      (SELECT pg_catalog.count(*) FROM macsad.policy_member_profile),
      (SELECT pg_catalog.count(*) FROM macsad.policy_node),
      (SELECT pg_catalog.count(*) FROM macsad.policy_node_tool_operation),
      (SELECT pg_catalog.count(*) FROM macsad.policy_process),
      (SELECT pg_catalog.count(*) FROM macsad.policy_revision),
      (SELECT pg_catalog.count(*) FROM macsad.policy_transition),
      (SELECT pg_catalog.count(*) FROM macsad.problem_revision),
      (SELECT pg_catalog.count(*) FROM macsad.publication_attempt),
      (SELECT pg_catalog.count(*) FROM macsad.publication_batch),
      (SELECT pg_catalog.count(*) FROM macsad.publication_dossier),
      (SELECT pg_catalog.count(*) FROM macsad.publication_head),
      (SELECT pg_catalog.count(*) FROM macsad.publication_item),
      (SELECT pg_catalog.count(*) FROM macsad.research_case),
      (SELECT pg_catalog.count(*) FROM macsad.research_case_tool_revision),
      (SELECT pg_catalog.count(*) FROM macsad.task),
      (SELECT pg_catalog.count(*) FROM macsad.task_assignment),
      (SELECT pg_catalog.count(*) FROM macsad.task_transition),
      (SELECT pg_catalog.count(*) FROM macsad.thread),
      (SELECT pg_catalog.count(*) FROM macsad.tool_operation_manifest),
      (SELECT pg_catalog.count(*) FROM macsad.tool_repository),
      (SELECT pg_catalog.count(*) FROM macsad.tool_repository_revision),
      (SELECT pg_catalog.count(*) FROM macsad.workspace),
      (SELECT pg_catalog.count(*) FROM macsad.workspace_snapshot)
    ]::bigint[] AS row_counts
), table_count AS (
  SELECT
    relation_names[ordinal] AS relation_name,
    row_counts[ordinal] AS row_count
  FROM table_count_arrays
  CROSS JOIN LATERAL pg_catalog.generate_subscripts(relation_names, 1)
    AS subscript(ordinal)
), boundary AS (
  SELECT
    'global'::text AS record_type,
    ''::text AS record_key,
    (SELECT current_version::text FROM macsad.schema_version_v) AS value_1,
    (SELECT pg_catalog.count(*)::text FROM macsad.workspace) AS value_2,
    (SELECT pg_catalog.count(*)::text FROM macsad.actor) AS value_3,
    (SELECT pg_catalog.count(*)::text FROM macsad.blob) AS value_4,
    (SELECT COALESCE(pg_catalog.sum(blob.byte_length), 0)::text
       FROM macsad.blob AS blob
       WHERE EXISTS (SELECT 1 FROM macsad.artifact AS artifact
                     WHERE artifact.blob_digest = blob.digest)) AS value_5,
    (SELECT pg_catalog.count(*)::text FROM macsad.domain_event) AS value_6,
    (SELECT pg_catalog.count(*)::text FROM macsad.outbox_message) AS value_7,
    (SELECT pg_catalog.count(*)::text FROM macsad.artifact) AS value_8

  UNION ALL

  SELECT
    'table',
    relation_name,
    row_count::text,
    '', '', '', '', '', '', ''
  FROM table_count

  UNION ALL

  SELECT
    'workspace',
    stream.workspace_id::text,
    stream.last_workspace_sequence::text,
    COALESCE(pg_catalog.encode(stream.last_event_hash, 'hex'), ''),
    stream.version::text,
    (SELECT pg_catalog.count(*)::text
       FROM macsad.domain_event AS event
       WHERE event.workspace_id = stream.workspace_id),
    (SELECT pg_catalog.count(*)::text
       FROM macsad.outbox_message AS message
       WHERE message.workspace_id = stream.workspace_id),
    COALESCE((
      SELECT pg_catalog.max(event.workspace_sequence_no)::text
      FROM macsad.outbox_message AS message
      JOIN macsad.domain_event AS event ON event.id = message.domain_event_id
      WHERE message.workspace_id = stream.workspace_id
    ), ''),
    (SELECT pg_catalog.count(*)::text
       FROM macsad.inbound_delivery AS delivery
       WHERE delivery.workspace_id = stream.workspace_id),
    (SELECT pg_catalog.count(*)::text
       FROM macsad.command_receipt AS receipt
       WHERE receipt.workspace_id = stream.workspace_id)
  FROM macsad.audit_stream AS stream
)
SELECT
  record_type,
  record_key,
  value_1,
  value_2,
  value_3,
  value_4,
  value_5,
  value_6,
  value_7,
  value_8
FROM boundary
ORDER BY record_type, record_key;

COMMIT;
