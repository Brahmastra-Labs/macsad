\set ON_ERROR_STOP on
\set QUIET 1

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE macsad_owner;
SET LOCAL search_path = pg_catalog;
SET LOCAL timezone = 'UTC';
SET LOCAL datestyle = 'ISO, YMD';
SET LOCAL bytea_output = 'hex';
SET LOCAL extra_float_digits = 3;

SELECT EXISTS (
  SELECT 1 FROM macsad.workspace WHERE id = :'workspace_id'::uuid
) AS workspace_exists
\gset

\if :workspace_exists
\else
  \echo 'error: workspace does not exist'
  \quit 4
\endif

WITH export_record AS (
  SELECT
    0 AS record_group,
    ''::text AS record_key,
    pg_catalog.jsonb_build_object(
      'format', 'macsad-workspace-views/1',
      'schema_version', (SELECT current_version::text FROM macsad.schema_version_v),
      'workspace_id', :'workspace_id'::uuid::text,
      'wire_contract', pg_catalog.jsonb_build_object(
        'boolean', 'json-boolean',
        'bytea', 'lowercase-hex',
        'integer', 'decimal-string',
        'jsonb', 'postgresql-16-normalized-json',
        'null', 'json-null',
        'numeric', 'decimal-string-12-fractional-digits',
        'text', 'stored-utf8-no-unicode-normalization',
        'timestamptz', 'utc-rfc3339-microseconds',
        'uuid', 'lowercase-canonical-string'
      )
    ) AS body

  UNION ALL

  SELECT
    10,
    pg_catalog.concat_ws(':', research_case_id::text, COALESCE(live_task_id::text, '')),
    pg_catalog.jsonb_build_object(
      'record_type', 'case_board',
      'record_schema', 'macsad.case-board-view/1',
      'row', pg_catalog.jsonb_build_object(
        'workspace_id', workspace_id::text,
        'research_case_id', research_case_id::text,
        'title', title,
        'research_kind', research_kind::text,
        'case_state', case_state::text,
        'control_state', control_state::text,
        'priority', priority::text,
        'process_key', process_key,
        'live_task_id', live_task_id::text,
        'live_task_sequence', live_task_sequence::text,
        'live_node_key', live_node_key,
        'board_phase', board_phase::text,
        'task_state', task_state::text,
        'accepted_assignment_id', accepted_assignment_id::text,
        'assigned_actor_id', assigned_actor_id::text,
        'assigned_profile_key', assigned_profile_key,
        'deadline_at', CASE WHEN deadline_at IS NULL THEN NULL ELSE
          pg_catalog.to_char(deadline_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END
      )
    )
  FROM macsad.case_board_v
  WHERE workspace_id = :'workspace_id'::uuid

  UNION ALL

  SELECT
    20,
    budget_account_id::text,
    pg_catalog.jsonb_build_object(
      'record_type', 'budget_balance',
      'record_schema', 'macsad.budget-balance-view/1',
      'row', pg_catalog.jsonb_build_object(
        'budget_account_id', budget_account_id::text,
        'workspace_id', workspace_id::text,
        'research_case_id', research_case_id::text,
        'resource_kind', resource_kind::text,
        'unit_code', unit_code,
        'currency_code', currency_code::text,
        'period_start', pg_catalog.to_char(
          period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'period_end', pg_catalog.to_char(
          period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'initial_spending_limit', (initial_spending_limit::numeric(30,12))::text,
        'spending_limit', (spending_limit::numeric(30,12))::text,
        'reserved_quantity', (reserved_quantity::numeric(30,12))::text,
        'spent_quantity', (spent_quantity::numeric(30,12))::text,
        'ledger_spending_limit', (ledger_spending_limit::numeric(30,12))::text,
        'ledger_reserved_quantity', (ledger_reserved_quantity::numeric(30,12))::text,
        'ledger_spent_quantity', (ledger_spent_quantity::numeric(30,12))::text,
        'spend_variance', (spend_variance::numeric(30,12))::text,
        'overrun_quantity', (overrun_quantity::numeric(30,12))::text,
        'available_to_reserve', (available_to_reserve::numeric(30,12))::text,
        'can_reserve', can_reserve,
        'projection_is_consistent', projection_is_consistent,
        'version', version::text
      )
    )
  FROM macsad.budget_balance_v
  WHERE workspace_id = :'workspace_id'::uuid

  UNION ALL

  SELECT
    30,
    model_call_id::text,
    pg_catalog.jsonb_build_object(
      'record_type', 'model_cost_variance',
      'record_schema', 'macsad.model-cost-variance-view/1',
      'row', pg_catalog.jsonb_build_object(
        'model_call_id', model_call_id::text,
        'workspace_id', workspace_id::text,
        'research_case_id', research_case_id::text,
        'task_id', task_id::text,
        'execution_id', execution_id::text,
        'requested_model', requested_model,
        'resolved_model', resolved_model,
        'resolved_provider', resolved_provider,
        'service_tier', service_tier,
        'byok', byok,
        'openrouter_generation_id', openrouter_generation_id,
        'model_call_state', model_call_state::text,
        'estimated_cost', (estimated_cost::numeric(30,12))::text,
        'reserved_cost', (reserved_cost::numeric(30,12))::text,
        'cost_currency', cost_currency::text,
        'budget_account_id', budget_account_id::text,
        'budget_unit', budget_unit,
        'budget_currency', budget_currency::text,
        'reserved_quantity', (reserved_quantity::numeric(30,12))::text,
        'latest_usage_observation_id', latest_usage_observation_id::text,
        'usage_is_final', usage_is_final,
        'prompt_tokens', prompt_tokens::text,
        'completion_tokens', completion_tokens::text,
        'total_tokens', total_tokens::text,
        'reasoning_tokens', reasoning_tokens::text,
        'cache_read_tokens', cache_read_tokens::text,
        'cache_write_tokens', cache_write_tokens::text,
        'audio_input_tokens', audio_input_tokens::text,
        'audio_output_tokens', audio_output_tokens::text,
        'image_count', image_count::text,
        'media_count', media_count::text,
        'web_search_count', web_search_count::text,
        'billed_amount', (billed_amount::numeric(30,12))::text,
        'billed_currency', billed_currency::text,
        'billed_credits', (billed_credits::numeric(30,12))::text,
        'upstream_cost_amount', (upstream_cost_amount::numeric(30,12))::text,
        'upstream_cost_currency', upstream_cost_currency::text,
        'settlement_kind', settlement_kind::text,
        'settled_quantity', (settled_quantity::numeric(30,12))::text,
        'reservation_released_quantity',
          (reservation_released_quantity::numeric(30,12))::text,
        'spend_adjustment_quantity', (spend_adjustment_quantity::numeric(30,12))::text,
        'recorded_spend_quantity', (recorded_spend_quantity::numeric(30,12))::text,
        'reservation_variance', (reservation_variance::numeric(30,12))::text,
        'reconciliation_variance', (reconciliation_variance::numeric(30,12))::text,
        'usage_needs_reconciliation', usage_needs_reconciliation,
        'exceeded_reservation', exceeded_reservation
      )
    )
  FROM macsad.model_cost_variance_v
  WHERE workspace_id = :'workspace_id'::uuid

  UNION ALL

  SELECT
    40,
    pg_catalog.concat_ws(
      ':', pg_catalog.lpad(batch_sequence::text, 20, '0'),
      pg_catalog.lpad(item_ordinal::text, 10, '0'), publication_batch_id::text
    ),
    pg_catalog.jsonb_build_object(
      'record_type', 'publication_catalog',
      'record_schema', 'macsad.publication-catalog-view/1',
      'row', pg_catalog.jsonb_build_object(
        'workspace_id', workspace_id::text,
        'publication_batch_id', publication_batch_id::text,
        'batch_sequence', batch_sequence::text,
        'published_at', pg_catalog.to_char(
          published_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'item_ordinal', item_ordinal::text,
        'research_case_id', research_case_id::text,
        'problem_revision_id', problem_revision_id::text,
        'claim_id', claim_id::text,
        'dossier_artifact_id', dossier_artifact_id::text,
        'item_digest', pg_catalog.encode(item_digest, 'hex'),
        'publication_attempt_id', publication_attempt_id::text
      )
    )
  FROM macsad.publication_catalog_v
  WHERE workspace_id = :'workspace_id'::uuid

  UNION ALL

  SELECT
    50,
    pg_catalog.lpad(workspace_sequence_no::text, 20, '0'),
    pg_catalog.jsonb_build_object(
      'record_type', 'audit_timeline',
      'record_schema', 'macsad.audit-timeline-view/1',
      'row', pg_catalog.jsonb_build_object(
        'workspace_id', workspace_id::text,
        'workspace_sequence_no', workspace_sequence_no::text,
        'aggregate_kind', aggregate_kind,
        'aggregate_id', aggregate_id::text,
        'aggregate_version', aggregate_version::text,
        'event_kind', event_kind,
        'actor_id', actor_id::text,
        'correlation_id', correlation_id::text,
        'causation_id', causation_id::text,
        'payload_schema_id', payload_schema_id,
        'payload_schema_version', payload_schema_version::text,
        'payload_digest', pg_catalog.encode(payload_digest, 'hex'),
        'event_hash', pg_catalog.encode(event_hash, 'hex'),
        'occurred_at', pg_catalog.to_char(
          occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'recorded_at', pg_catalog.to_char(
          recorded_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      )
    )
  FROM macsad.audit_timeline_v
  WHERE workspace_id = :'workspace_id'::uuid
)
SELECT body::text
FROM export_record
ORDER BY record_group, record_key;

COMMIT;
