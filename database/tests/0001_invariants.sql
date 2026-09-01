-- High-value mechanical invariants for 0001_initial_schema.sql.
--
-- Run this as a login that may SET ROLE macsad_owner.  Every fixture and every
-- successful assertion is discarded by the unconditional ROLLBACK below.

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '2min';
SET LOCAL ROLE macsad_owner;

DO $invariants$
DECLARE
  v_workspace_id uuid := pg_catalog.gen_random_uuid();
  v_other_workspace_id uuid := pg_catalog.gen_random_uuid();
  v_snapshot_id uuid := pg_catalog.gen_random_uuid();
  v_other_snapshot_id uuid := pg_catalog.gen_random_uuid();
  v_policy_revision_id uuid := pg_catalog.gen_random_uuid();
  v_admin_actor_id uuid := pg_catalog.gen_random_uuid();
  v_researcher_actor_id uuid := pg_catalog.gen_random_uuid();
  v_worker_actor_id uuid := pg_catalog.gen_random_uuid();
  v_admin_membership_id uuid := pg_catalog.gen_random_uuid();
  v_membership_id uuid := pg_catalog.gen_random_uuid();
  v_problem_id uuid := pg_catalog.gen_random_uuid();
  v_other_problem_id uuid := pg_catalog.gen_random_uuid();
  v_case_id uuid := pg_catalog.gen_random_uuid();
  v_other_case_id uuid := pg_catalog.gen_random_uuid();
  v_tool_repository_id uuid := pg_catalog.gen_random_uuid();
  v_other_tool_repository_id uuid := pg_catalog.gen_random_uuid();
  v_late_tool_repository_id uuid := pg_catalog.gen_random_uuid();
  v_tool_revision_id uuid := pg_catalog.gen_random_uuid();
  v_second_tool_revision_id uuid := pg_catalog.gen_random_uuid();
  v_other_tool_revision_id uuid := pg_catalog.gen_random_uuid();
  v_late_tool_revision_id uuid := pg_catalog.gen_random_uuid();
  v_source_read_manifest_id uuid := pg_catalog.gen_random_uuid();
  v_model_manifest_id uuid := pg_catalog.gen_random_uuid();
  v_source_read_policy_operation_id uuid := pg_catalog.gen_random_uuid();
  v_model_policy_operation_id uuid := pg_catalog.gen_random_uuid();
  v_policy_transition_id uuid := pg_catalog.gen_random_uuid();
  v_terminal_policy_transition_id uuid := pg_catalog.gen_random_uuid();
  v_task_id uuid := pg_catalog.gen_random_uuid();
  v_successor_task_id uuid := pg_catalog.gen_random_uuid();
  v_task_transition_id uuid := pg_catalog.gen_random_uuid();
  v_assignment_id uuid := pg_catalog.gen_random_uuid();
  v_execution_id uuid := pg_catalog.gen_random_uuid();
  v_model_tool_use_id uuid := pg_catalog.gen_random_uuid();
  v_model_call_id uuid := pg_catalog.gen_random_uuid();
  v_other_model_call_id uuid := pg_catalog.gen_random_uuid();
  v_usage_observation_id uuid := pg_catalog.gen_random_uuid();
  v_corrected_usage_observation_id uuid := pg_catalog.gen_random_uuid();
  v_blob_digest macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('01', 32), 'hex');
  v_public_artifact_id uuid := pg_catalog.gen_random_uuid();
  v_budget_account_id uuid := pg_catalog.gen_random_uuid();
  v_expired_budget_account_id uuid := pg_catalog.gen_random_uuid();
  v_reservation_entry_id uuid;
  v_event_one_id uuid := pg_catalog.gen_random_uuid();
  v_event_two_id uuid := pg_catalog.gen_random_uuid();
  v_task_ready_event_id uuid := pg_catalog.gen_random_uuid();
  v_task_running_event_id uuid := pg_catalog.gen_random_uuid();
  v_task_event_id uuid := pg_catalog.gen_random_uuid();
  v_claim_id uuid := pg_catalog.gen_random_uuid();
  v_disposition_attestation_id uuid := pg_catalog.gen_random_uuid();
  v_eligibility_attestation_id uuid := pg_catalog.gen_random_uuid();
  v_other_claim_id uuid := pg_catalog.gen_random_uuid();
  v_other_disposition_attestation_id uuid := pg_catalog.gen_random_uuid();
  v_other_eligibility_attestation_id uuid := pg_catalog.gen_random_uuid();
  v_publication_batch_id uuid := pg_catalog.gen_random_uuid();
  v_publication_dossier_id uuid := pg_catalog.gen_random_uuid();
  v_other_publication_dossier_id uuid := pg_catalog.gen_random_uuid();
  v_publication_attempt_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp() - interval '1 minute';
  d02 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('02', 32), 'hex');
  d03 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('03', 32), 'hex');
  d04 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('04', 32), 'hex');
  d05 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('05', 32), 'hex');
  d06 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('06', 32), 'hex');
  d07 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('07', 32), 'hex');
  d08 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('08', 32), 'hex');
  d09 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('09', 32), 'hex');
  d10 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('0a', 32), 'hex');
  d11 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('0b', 32), 'hex');
  d12 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('0c', 32), 'hex');
  d13 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('0d', 32), 'hex');
  d14 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('0e', 32), 'hex');
  d15 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('0f', 32), 'hex');
  d16 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('10', 32), 'hex');
  d17 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('11', 32), 'hex');
  d18 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('12', 32), 'hex');
  d19 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('13', 32), 'hex');
  d20 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('14', 32), 'hex');
  d21 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('15', 32), 'hex');
  d22 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('16', 32), 'hex');
  d23 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('17', 32), 'hex');
  d24 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('18', 32), 'hex');
  d25 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('19', 32), 'hex');
  d26 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('1a', 32), 'hex');
  d27 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('1b', 32), 'hex');
  d28 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('1c', 32), 'hex');
  d29 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('1d', 32), 'hex');
  d30 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('1e', 32), 'hex');
  d31 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('1f', 32), 'hex');
  d32 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('20', 32), 'hex');
  d33 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('21', 32), 'hex');
  d34 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('22', 32), 'hex');
  d35 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('23', 32), 'hex');
  d36 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('24', 32), 'hex');
  d37 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('25', 32), 'hex');
  d38 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('26', 32), 'hex');
  d39 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('27', 32), 'hex');
  d40 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('28', 32), 'hex');
  d41 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('29', 32), 'hex');
  d42 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('2a', 32), 'hex');
  d43 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('2b', 32), 'hex');
  d44 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('2c', 32), 'hex');
  d45 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('2d', 32), 'hex');
  d46 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('2e', 32), 'hex');
  d47 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('2f', 32), 'hex');
  d48 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('30', 32), 'hex');
  d49 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('31', 32), 'hex');
  d50 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('32', 32), 'hex');
  d51 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('33', 32), 'hex');
  d52 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('34', 32), 'hex');
  d53 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('35', 32), 'hex');
  d54 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('36', 32), 'hex');
  d55 macsad.sha256_digest := pg_catalog.decode(pg_catalog.repeat('37', 32), 'hex');
BEGIN
  ---------------------------------------------------------------------------
  -- A workspace creates exactly one empty audit stream. Its watched-repository
  -- identity is stable, and mutable state uses optimistic versioning.
  ---------------------------------------------------------------------------
  INSERT INTO macsad.workspace (
    id, github_repository_id, owner_name, repository_name, default_branch
  ) VALUES (
    v_workspace_id, 910000001, 'Brahmastra-Labs', 'invariant-fixture', 'main'
  );

  INSERT INTO macsad.workspace (
    id, github_repository_id, owner_name, repository_name, default_branch
  ) VALUES (
    v_other_workspace_id, 910000002, 'Brahmastra-Labs', 'other-fixture', 'main'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM macsad.audit_stream AS stream
    WHERE stream.workspace_id = v_workspace_id
      AND stream.last_workspace_sequence = 0
      AND stream.last_event_hash IS NULL
      AND stream.version = 0
  ) OR (SELECT pg_catalog.count(*) FROM macsad.audit_stream
        WHERE workspace_id = v_workspace_id) <> 1 THEN
    RAISE EXCEPTION 'workspace did not create exactly one empty audit stream';
  END IF;

  BEGIN
    UPDATE macsad.workspace
    SET github_repository_id = 910000099, version = version + 1
    WHERE id = v_workspace_id;
    RAISE EXCEPTION 'expected SQLSTATE 55000 for watched-repository identity mutation'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  BEGIN
    UPDATE macsad.workspace SET state = 'active' WHERE id = v_workspace_id;
    RAISE EXCEPTION 'expected SQLSTATE 40001 for a stale workspace update'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '40001' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  UPDATE macsad.workspace
  SET state = 'active', version = version + 1
  WHERE id = v_workspace_id;

  ---------------------------------------------------------------------------
  -- Actors and one content-addressed, public-safe artifact used by the compact
  -- fixture. Reusing the artifact keeps the fixture small without weakening
  -- any relationship under test.
  ---------------------------------------------------------------------------
  INSERT INTO macsad.actor (id, kind, display_name)
  VALUES
    (v_admin_actor_id, 'human', 'Invariant administrator'),
    (v_researcher_actor_id, 'agent', 'Invariant researcher'),
    (v_worker_actor_id, 'service', 'Invariant worker');

  INSERT INTO macsad.blob (
    digest, byte_length, media_type, storage_provider, storage_locator,
    storage_class, stored_at, verified_at
  ) VALUES (
    v_blob_digest, 1, 'application/octet-stream', 'test_store',
    'invariants/0001/shared', 'test', v_now, v_now
  );

  INSERT INTO macsad.artifact (
    id, workspace_id, blob_digest, artifact_kind, classification,
    secret_scan_result, quarantined, producing_actor_id,
    redistribution_allowed, export_decision
  ) VALUES (
    v_public_artifact_id, v_workspace_id, v_blob_digest, 'test_fixture',
    'public_candidate', 'passed', false, v_admin_actor_id, true,
    'allowed_for_invariant_test'
  );

  ---------------------------------------------------------------------------
  -- A validated candidate is compiled first, then activated as one frozen
  -- policy projection for the exact snapshot used by every case.
  ---------------------------------------------------------------------------
  INSERT INTO macsad.workspace_snapshot (
    id, workspace_id, object_algorithm, commit_oid, tree_oid,
    observed_default_branch, observation_source, configuration_digest,
    repository_policy_result, repository_policy_schema_id,
    repository_policy_schema_version, repository_policy_body,
    repository_policy_digest, snapshot_digest, observed_at
  ) VALUES (
    v_snapshot_id, v_workspace_id, 'sha1', pg_catalog.repeat('a', 40),
    pg_catalog.repeat('b', 40), 'main', 'reconciliation', d02, 'accepted',
    'macsad.repository-policy', 1, '{"accepted":true}'::jsonb, d03, d04, v_now
  );

  INSERT INTO macsad.workspace_snapshot (
    id, workspace_id, object_algorithm, commit_oid, tree_oid,
    observed_default_branch, observation_source, configuration_digest,
    repository_policy_result, repository_policy_schema_id,
    repository_policy_schema_version, repository_policy_body,
    repository_policy_digest, snapshot_digest, observed_at
  ) VALUES (
    v_other_snapshot_id, v_workspace_id, 'sha1', pg_catalog.repeat('c', 40),
    pg_catalog.repeat('d', 40), 'main', 'reconciliation', d02, 'accepted',
    'macsad.repository-policy', 1, '{"accepted":true}'::jsonb, d03, d05, v_now
  );

  INSERT INTO macsad.policy_revision (
    id, workspace_id, workspace_snapshot_id, source_path, source_digest,
    compiler_name, compiler_version, schema_id, schema_version, compiled_body,
    compiled_digest, validation_result, validation_schema_id,
    validation_schema_version, validation_body, validation_digest, validated_at
  ) VALUES (
    v_policy_revision_id, v_workspace_id, v_snapshot_id,
    '.macsad/policy.json', d06, 'macsad-policy-compiler', '1.0.0',
    'macsad.policy', 1, '{"processes":["discovery"]}'::jsonb, d07,
    'passed', 'macsad.policy-validation', 1, '{"valid":true}'::jsonb,
    d08, v_now
  );

  INSERT INTO macsad.policy_member_profile (
    workspace_id, policy_revision_id, profile_key, display_name, role_key,
    wip_limit, profile_schema_id, profile_schema_version, profile_body,
    profile_digest
  ) VALUES
    (
      v_workspace_id, v_policy_revision_id, 'researcher', 'Researcher',
      'researcher', 1, 'macsad.member-profile', 1,
      '{"job":"investigate"}'::jsonb, d09
    ),
    (
      v_workspace_id, v_policy_revision_id, 'reviewer', 'Human reviewer',
      'reviewer', 2, 'macsad.member-profile', 1,
      '{"job":"decide"}'::jsonb, d29
    );

  INSERT INTO macsad.policy_process (
    workspace_id, policy_revision_id, process_key, title, entry_node_key,
    process_schema_id, process_schema_version, process_body, graph_digest
  ) VALUES (
    v_workspace_id, v_policy_revision_id, 'discovery', 'Discovery', 'investigate',
    'macsad.process', 1, '{"entry":"investigate"}'::jsonb, d10
  );

  INSERT INTO macsad.policy_node (
    workspace_id, policy_revision_id, process_key, node_key, node_kind, title,
    board_phase, required_profile_key, node_schema_id, node_schema_version,
    node_body, node_digest
  ) VALUES
    (
      v_workspace_id, v_policy_revision_id, 'discovery', 'investigate', 'task',
      'Investigate', 'running', 'researcher', 'macsad.node', 1,
      '{"kind":"task"}'::jsonb, d11
    ),
    (
      v_workspace_id, v_policy_revision_id, 'discovery', 'verify', 'task',
      'Verify', 'verify', 'researcher', 'macsad.node', 1,
      '{"kind":"task"}'::jsonb, d12
    ),
    (
      v_workspace_id, v_policy_revision_id, 'discovery', 'done', 'terminal',
      'Done', 'closed', NULL, 'macsad.node', 1,
      '{"kind":"terminal"}'::jsonb, d30
    );

  INSERT INTO macsad.policy_transition (
    id, workspace_id, policy_revision_id, process_key, transition_key,
    source_node_key, target_node_key, transition_kind, match_order, is_default,
    decision_code, predicate_schema_id, predicate_schema_version,
    predicate_body, predicate_digest
  ) VALUES
    (
      v_policy_transition_id, v_workspace_id, v_policy_revision_id, 'discovery',
      'investigate.success', 'investigate', 'verify', 'success', 0, false,
      'complete', 'macsad.predicate', 1, '{"result":"accepted"}'::jsonb, d13
    ),
    (
      v_terminal_policy_transition_id, v_workspace_id, v_policy_revision_id,
      'discovery', 'verify.success', 'verify', 'done', 'success', 0, false,
      'publishable', 'macsad.predicate', 1, '{"result":"accepted"}'::jsonb, d31
    );

  -- Tool operation catalogs are closed before they can be compiled into an
  -- active policy. The second repository is promoted for controlled invocation;
  -- the first remains source-readable only.
  INSERT INTO macsad.tool_repository (
    id, workspace_id, repository_key, purpose, source_kind,
    github_repository_id, owner_name, repository_name, default_branch,
    locator_key, connection_reference, default_classification, exposure,
    approved_by_actor_id, approved_at, state
  ) VALUES
    (
      v_tool_repository_id, v_workspace_id, 'fixture-tool', 'Fixture checker',
      'github', 920000001, 'Brahmastra-Labs', 'fixture-tool', 'main',
      'github/brahmastra-labs/fixture-tool', 'github-installation:test',
      'internal', 'private_host', v_admin_actor_id, v_now, 'active'
    ),
    (
      v_other_tool_repository_id, v_workspace_id, 'model-gateway',
      'Controlled OpenRouter gateway', 'github', 920000002, 'Brahmastra-Labs',
      'model-gateway', 'main', 'github/brahmastra-labs/model-gateway',
      'github-installation:test', 'internal', 'private_host',
      v_admin_actor_id, v_now, 'active'
    ),
    (
      v_late_tool_repository_id, v_workspace_id, 'late-fixture-tool',
      'Late checker used for the freeze assertion', 'github', 920000003,
      'Brahmastra-Labs', 'late-fixture-tool', 'main',
      'github/brahmastra-labs/late-fixture-tool', 'github-installation:test',
      'internal', 'private_host', v_admin_actor_id, v_now, 'active'
    );

  INSERT INTO macsad.tool_repository_revision (
    id, workspace_id, tool_repository_id, object_algorithm, commit_oid, tree_oid,
    observed_branch, observation_source, source_artifact_id,
    access_policy_schema_id, access_policy_schema_version, access_policy_body,
    access_policy_digest, source_digest, manifest_digest, lock_digest,
    dependency_digest, build_environment_digest, promoted_bundle_artifact_id,
    compatibility_evidence_artifact_id, revision_digest, observed_at,
    preserved_at, promoted_at
  ) VALUES
    (
      v_tool_revision_id, v_workspace_id, v_tool_repository_id, 'sha1',
      pg_catalog.repeat('1', 40), pg_catalog.repeat('2', 40), 'main',
      'reconciliation', v_public_artifact_id, 'macsad.tool-access', 1,
      '{"mode":"source_read"}'::jsonb, d17, d18, d19, d20, d21, d22,
      NULL, NULL, d23, v_now, v_now, NULL
    ),
    (
      v_second_tool_revision_id, v_workspace_id, v_tool_repository_id, 'sha1',
      pg_catalog.repeat('3', 40), pg_catalog.repeat('4', 40), 'main',
      'reconciliation', v_public_artifact_id, 'macsad.tool-access', 1,
      '{"mode":"source_read"}'::jsonb, d17, d18, d19, d20, d21, d22,
      NULL, NULL, d24, v_now, v_now, NULL
    ),
    (
      v_other_tool_revision_id, v_workspace_id, v_other_tool_repository_id, 'sha1',
      pg_catalog.repeat('5', 40), pg_catalog.repeat('6', 40), 'main',
      'reconciliation', v_public_artifact_id, 'macsad.tool-access', 1,
      '{"mode":"operation_invoke"}'::jsonb, d17, d18, d19, d20, d21, d22,
      v_public_artifact_id, v_public_artifact_id, d25, v_now, v_now, v_now
    ),
    (
      v_late_tool_revision_id, v_workspace_id, v_late_tool_repository_id, 'sha1',
      pg_catalog.repeat('7', 40), pg_catalog.repeat('8', 40), 'main',
      'reconciliation', v_public_artifact_id, 'macsad.tool-access', 1,
      '{"mode":"source_read"}'::jsonb, d17, d18, d19, d20, d21, d22,
      NULL, NULL, d32, v_now, v_now, NULL
    );

  INSERT INTO macsad.tool_operation_manifest (
    id, workspace_id, tool_repository_revision_id, operation_key,
    operation_version, provider_key, provider_revision, effect_class,
    request_schema_id, request_schema_version, request_schema_digest,
    response_schema_id, response_schema_version, response_schema_digest,
    manifest_schema_id, manifest_schema_version, manifest_body, manifest_digest
  ) VALUES
    (
      v_source_read_manifest_id, v_workspace_id, v_tool_revision_id,
      'check-fixture', 1, 'fixture-checker', '1.0.0', 'pure_check',
      'fixture.request', 1, d33, 'fixture.response', 1, d34,
      'macsad.tool-operation', 1, '{"operation":"check-fixture"}'::jsonb, d35
    ),
    (
      v_model_manifest_id, v_workspace_id, v_other_tool_revision_id,
      'openrouter-completion', 1, 'openrouter', 'v1', 'model_call',
      'openrouter.request', 1, d36, 'openrouter.response', 1, d37,
      'macsad.tool-operation', 1, '{"operation":"openrouter-completion"}'::jsonb,
      d38
    );

  UPDATE macsad.tool_repository_revision
  SET operation_count = 1, operation_catalog_digest = d39,
      operations_sealed_by_actor_id = v_admin_actor_id,
      operations_sealed_at = pg_catalog.clock_timestamp()
  WHERE id = v_tool_revision_id;

  UPDATE macsad.tool_repository_revision
  SET operation_count = 1, operation_catalog_digest = d40,
      operations_sealed_by_actor_id = v_admin_actor_id,
      operations_sealed_at = pg_catalog.clock_timestamp()
  WHERE id = v_other_tool_revision_id;

  BEGIN
    INSERT INTO macsad.tool_operation_manifest (
      workspace_id, tool_repository_revision_id, operation_key,
      operation_version, provider_key, provider_revision, effect_class,
      request_schema_id, request_schema_version, request_schema_digest,
      response_schema_id, response_schema_version, response_schema_digest,
      manifest_schema_id, manifest_schema_version, manifest_body, manifest_digest
    ) VALUES (
      v_workspace_id, v_tool_revision_id, 'late-operation', 1,
      'fixture-checker', '1.0.0', 'pure_check', 'fixture.request', 1, d41,
      'fixture.response', 1, d42, 'macsad.tool-operation', 1,
      '{"operation":"late-operation"}'::jsonb, d43
    );
    RAISE EXCEPTION 'expected SQLSTATE 55000 for a post-seal tool operation'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.policy_node_tool_operation (
    id, workspace_id, policy_revision_id, process_key, node_key,
    tool_operation_manifest_id, max_invocations, required
  ) VALUES
    (
      v_source_read_policy_operation_id, v_workspace_id, v_policy_revision_id,
      'discovery', 'investigate', v_source_read_manifest_id, 1, false
    ),
    (
      v_model_policy_operation_id, v_workspace_id, v_policy_revision_id,
      'discovery', 'investigate', v_model_manifest_id, 2, false
    );

  SET CONSTRAINTS macsad.policy_process_entry_node_fk IMMEDIATE;

  UPDATE macsad.policy_revision
  SET state = 'active', activated_by_actor_id = v_admin_actor_id,
      activated_at = pg_catalog.clock_timestamp(), version = version + 1
  WHERE id = v_policy_revision_id;

  BEGIN
    INSERT INTO macsad.policy_member_profile (
      workspace_id, policy_revision_id, profile_key, display_name, role_key,
      wip_limit, profile_schema_id, profile_schema_version, profile_body,
      profile_digest
    ) VALUES (
      v_workspace_id, v_policy_revision_id, 'late-profile', 'Late profile',
      'late-profile', 1, 'macsad.member-profile', 1, '{"late":true}'::jsonb, d44
    );
    RAISE EXCEPTION 'expected SQLSTATE 55000 for an active-policy projection insert'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  IF NOT EXISTS (
    SELECT 1
    FROM macsad.policy_process AS process
    JOIN macsad.policy_node AS source
      ON source.policy_revision_id = process.policy_revision_id
     AND source.process_key = process.process_key
     AND source.node_key = process.entry_node_key
    JOIN macsad.policy_transition AS edge
      ON edge.policy_revision_id = process.policy_revision_id
     AND edge.process_key = process.process_key
     AND edge.source_node_key = source.node_key
    JOIN macsad.policy_transition AS terminal_edge
      ON terminal_edge.policy_revision_id = edge.policy_revision_id
     AND terminal_edge.process_key = edge.process_key
     AND terminal_edge.source_node_key = edge.target_node_key
    JOIN macsad.policy_node AS target
      ON target.policy_revision_id = terminal_edge.policy_revision_id
     AND target.process_key = terminal_edge.process_key
     AND target.node_key = terminal_edge.target_node_key
    WHERE process.policy_revision_id = v_policy_revision_id
      AND process.process_key = 'discovery'
      AND source.board_phase = 'running'
      AND target.node_kind = 'terminal'
  ) THEN
    RAISE EXCEPTION 'compiled process/node/edge projection is incomplete';
  END IF;

  INSERT INTO macsad.membership (
    id, workspace_id, actor_id, policy_revision_id, profile_key,
    profile_digest, state
  ) VALUES
    (
      v_membership_id, v_workspace_id, v_researcher_actor_id,
      v_policy_revision_id, 'researcher', d09, 'active'
    ),
    (
      v_admin_membership_id, v_workspace_id, v_admin_actor_id,
      v_policy_revision_id, 'reviewer', d29, 'active'
    );

  INSERT INTO macsad.problem_revision (
    id, workspace_id, research_kind, title, original_question, definitions,
    assumptions, domain_bounds, success_criteria, refutation_criteria,
    inconclusive_criteria, kind_schema_id, kind_schema_version, kind_body,
    content_digest, created_by_actor_id
  ) VALUES
    (
      v_problem_id, v_workspace_id, 'mathematics', 'Fixture theorem',
      'Does the fixture theorem hold?', 'Fixture definitions', 'None',
      'Finite fixture domain', 'A checked proof', 'A checked counterexample',
      'No decisive evidence', 'macsad.math-problem', 1, '{"kind":"theorem"}'::jsonb,
      d14, v_admin_actor_id
    ),
    (
      v_other_problem_id, v_workspace_id, 'mathematics', 'Other fixture theorem',
      'Does the other fixture theorem hold?', 'Fixture definitions', 'None',
      'Finite fixture domain', 'A checked proof', 'A checked counterexample',
      'No decisive evidence', 'macsad.math-problem', 1, '{"kind":"theorem"}'::jsonb,
      d15, v_admin_actor_id
    );

  BEGIN
    INSERT INTO macsad.research_case (
      workspace_id, workspace_snapshot_id, policy_revision_id,
      problem_revision_id, process_key, tool_closure_digest
    ) VALUES (
      v_workspace_id, v_other_snapshot_id, v_policy_revision_id,
      v_other_problem_id, 'discovery', d16
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 for policy/snapshot mismatch'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.research_case (
    id, workspace_id, workspace_snapshot_id, policy_revision_id,
    problem_revision_id, process_key, tool_closure_digest
  ) VALUES (
    v_case_id, v_workspace_id, v_snapshot_id, v_policy_revision_id,
    v_problem_id, 'discovery', d16
  );

  ---------------------------------------------------------------------------
  -- A case pins at most one revision of each approved repository, and its
  -- complete tool closure freezes at task 1.
  ---------------------------------------------------------------------------
  INSERT INTO macsad.research_case_tool_revision (
    workspace_id, research_case_id, tool_repository_id,
    tool_repository_revision_id, ordinal, access_mode, purpose,
    pinned_by_actor_id
  ) VALUES (
    v_workspace_id, v_case_id, v_tool_repository_id, v_tool_revision_id,
    0, 'source_read', 'Run the fixture checker', v_admin_actor_id
  );

  INSERT INTO macsad.research_case_tool_revision (
    workspace_id, research_case_id, tool_repository_id,
    tool_repository_revision_id, ordinal, access_mode, purpose,
    pinned_by_actor_id
  ) VALUES (
    v_workspace_id, v_case_id, v_other_tool_repository_id,
    v_other_tool_revision_id, 1, 'operation_invoke',
    'Invoke the controlled model gateway', v_admin_actor_id
  );

  BEGIN
    INSERT INTO macsad.research_case_tool_revision (
      workspace_id, research_case_id, tool_repository_id,
      tool_repository_revision_id, ordinal, access_mode, purpose,
      pinned_by_actor_id
    ) VALUES (
      v_workspace_id, v_case_id, v_tool_repository_id, v_second_tool_revision_id,
      1, 'source_read', 'Conflicting revision', v_admin_actor_id
    );
    RAISE EXCEPTION 'expected SQLSTATE 23505 for a second revision of one case tool'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23505' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  IF (SELECT pg_catalog.count(*)
      FROM macsad.research_case_tool_revision
      WHERE research_case_id = v_case_id AND tool_repository_id = v_tool_repository_id) <> 1 THEN
    RAISE EXCEPTION 'case retained more than one revision of one tool repository';
  END IF;

  ---------------------------------------------------------------------------
  -- A task is a fixed projection of its compiled node, and an assignment is
  -- inseparable from a current membership matching that node's profile.
  ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO macsad.task (
      workspace_id, research_case_id, policy_revision_id, problem_revision_id,
      process_key, node_key, sequence_no, state, board_phase,
      required_profile_key, required_profile_digest, finished_at
    ) VALUES (
      v_workspace_id, v_case_id, v_policy_revision_id, v_problem_id,
      'discovery', 'verify', 1, 'offered', 'verify', 'researcher', d09,
      NULL
    );
    SET CONSTRAINTS macsad.task_path_closed_ck IMMEDIATE;
    RAISE EXCEPTION 'expected SQLSTATE 23514 for a non-entry first task'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  BEGIN
    INSERT INTO macsad.task (
      workspace_id, research_case_id, policy_revision_id, problem_revision_id,
      process_key, node_key, sequence_no, state, board_phase,
      required_profile_key, required_profile_digest
    ) VALUES (
      v_workspace_id, v_case_id, v_policy_revision_id, v_problem_id,
      'discovery', 'investigate', 1, 'offered', 'review', 'researcher', d09
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 for a non-compiled Kanban phase'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.task (
    id, workspace_id, research_case_id, policy_revision_id, problem_revision_id,
    process_key, node_key, sequence_no, state, board_phase,
    required_profile_key, required_profile_digest
  ) VALUES (
    v_task_id, v_workspace_id, v_case_id, v_policy_revision_id, v_problem_id,
    'discovery', 'investigate', 1, 'offered', 'running', 'researcher', d09
  );

  SET CONSTRAINTS macsad.task_path_closed_ck IMMEDIATE;
  SET CONSTRAINTS macsad.task_path_closed_ck DEFERRED;

  UPDATE macsad.task
  SET state = 'ready', version = version + 1
  WHERE id = v_task_id;

  BEGIN
    INSERT INTO macsad.research_case_tool_revision (
      workspace_id, research_case_id, tool_repository_id,
      tool_repository_revision_id, ordinal, access_mode, purpose,
      pinned_by_actor_id
    ) VALUES (
      v_workspace_id, v_case_id, v_late_tool_repository_id,
      v_late_tool_revision_id, 2, 'source_read', 'Late tool pin', v_admin_actor_id
    );
    RAISE EXCEPTION 'expected SQLSTATE 55000 after the first case task freezes tools'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  BEGIN
    INSERT INTO macsad.task_assignment (
      workspace_id, task_id, offered_actor_id, offered_membership_id,
      offered_by_actor_id, policy_revision_id, profile_key, profile_digest,
      package_digest
    ) VALUES (
      v_workspace_id, v_task_id, v_admin_actor_id, v_membership_id,
      v_admin_actor_id, v_policy_revision_id, 'researcher', d09, d26
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 for actor/membership mismatch'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.task_assignment (
    id, workspace_id, task_id, offered_actor_id, offered_membership_id,
    offered_by_actor_id, policy_revision_id, profile_key, profile_digest,
    package_digest
  ) VALUES (
    v_assignment_id, v_workspace_id, v_task_id, v_researcher_actor_id,
    v_membership_id, v_admin_actor_id, v_policy_revision_id, 'researcher',
    d09, d26
  );

  UPDATE macsad.task_assignment
  SET state = 'accepted', accepted_at = pg_catalog.clock_timestamp(),
      version = version + 1
  WHERE id = v_assignment_id;

  IF NOT EXISTS (
    SELECT 1
    FROM macsad.task_assignment AS assignment
    JOIN macsad.membership AS member
      ON member.id = assignment.offered_membership_id
     AND member.workspace_id = assignment.workspace_id
     AND member.actor_id = assignment.offered_actor_id
     AND member.policy_revision_id = assignment.policy_revision_id
     AND member.profile_key = assignment.profile_key
     AND member.profile_digest = assignment.profile_digest
    WHERE assignment.id = v_assignment_id
      AND assignment.state = 'accepted'
      AND member.state = 'active'
  ) THEN
    RAISE EXCEPTION 'accepted assignment is not bound to its active membership';
  END IF;

  INSERT INTO macsad.execution (
    id, workspace_id, research_case_id, task_id, task_assignment_id,
    performing_actor_id, worker_actor_id, workspace_snapshot_id,
    policy_revision_id, problem_revision_id, profile_key, profile_digest,
    request_schema_id, request_schema_version, request_body, request_digest,
    environment_digest, resource_limit_schema_id, resource_limit_schema_version,
    resource_limit_body, resource_limit_digest, deterministic_seed,
    idempotency_key
  ) VALUES (
    v_execution_id, v_workspace_id, v_case_id, v_task_id, v_assignment_id,
    v_researcher_actor_id, v_worker_actor_id, v_snapshot_id,
    v_policy_revision_id, v_problem_id, 'researcher', d09,
    'macsad.execution-request', 1, '{"task":"investigate"}'::jsonb, d30,
    d31, 'macsad.resource-limits', 1, '{"wall_seconds":60}'::jsonb, d32,
    1, 'invariants:execution-1'
  );

  BEGIN
    INSERT INTO macsad.execution_tool_use (
      workspace_id, research_case_id, execution_id,
      policy_node_tool_operation_id, tool_repository_revision_id,
      tool_operation_manifest_id, invocation_sequence, request_digest
    ) VALUES (
      v_workspace_id, v_case_id, v_execution_id,
      v_source_read_policy_operation_id, v_tool_revision_id,
      v_source_read_manifest_id, 1, d33
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 when invoking a source-read-only tool'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.execution_tool_use (
    id, workspace_id, research_case_id, execution_id,
    policy_node_tool_operation_id, tool_repository_revision_id,
    tool_operation_manifest_id, invocation_sequence, request_digest
  ) VALUES (
    v_model_tool_use_id, v_workspace_id, v_case_id, v_execution_id,
    v_model_policy_operation_id, v_other_tool_revision_id,
    v_model_manifest_id, 1, d34
  );

  ---------------------------------------------------------------------------
  -- Composite workspace keys prevent cross-workspace artifact linkage.
  ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO macsad.workspace_snapshot (
      workspace_id, object_algorithm, commit_oid, tree_oid,
      observed_default_branch, observation_source, source_artifact_id,
      configuration_digest, repository_policy_result,
      repository_policy_schema_id, repository_policy_schema_version,
      repository_policy_body, repository_policy_digest, snapshot_digest,
      observed_at, preserved_at
    ) VALUES (
      v_other_workspace_id, 'sha1', pg_catalog.repeat('7', 40),
      pg_catalog.repeat('8', 40), 'main', 'reconciliation', v_public_artifact_id,
      d02, 'accepted', 'macsad.repository-policy', 1,
      '{"accepted":true}'::jsonb, d03, d27, v_now, v_now
    );
    RAISE EXCEPTION 'expected SQLSTATE 23503 for a cross-workspace artifact link'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23503' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  ---------------------------------------------------------------------------
  -- Workspace audit events form one gapless ordered chain and advance the
  -- materialized hash head atomically.
  ---------------------------------------------------------------------------
  INSERT INTO macsad.domain_event (
    id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
    aggregate_version, event_kind, actor_id, correlation_id,
    payload_schema_id, payload_schema_version, payload_body, payload_digest,
    previous_event_hash, event_hash, occurred_at
  ) VALUES (
    v_event_one_id, v_workspace_id, 1, 'workspace', v_workspace_id, 1,
    'workspace.fixture_started', v_admin_actor_id, pg_catalog.gen_random_uuid(),
    'macsad.event', 1, '{"step":1}'::jsonb, d02, NULL, d19, v_now
  );

  BEGIN
    INSERT INTO macsad.domain_event (
      workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
      aggregate_version, event_kind, actor_id, correlation_id,
      payload_schema_id, payload_schema_version, payload_body, payload_digest,
      previous_event_hash, event_hash, occurred_at
    ) VALUES (
      v_workspace_id, 3, 'workspace', v_workspace_id, 2,
      'workspace.out_of_order', v_admin_actor_id, pg_catalog.gen_random_uuid(),
      'macsad.event', 1, '{"step":3}'::jsonb, d03, d19, d18, v_now
    );
    RAISE EXCEPTION 'expected SQLSTATE 40001 for a non-successor audit event'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '40001' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.domain_event (
    id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
    aggregate_version, event_kind, actor_id, correlation_id,
    payload_schema_id, payload_schema_version, payload_body, payload_digest,
    previous_event_hash, event_hash, occurred_at
  ) VALUES (
    v_event_two_id, v_workspace_id, 2, 'workspace', v_workspace_id, 2,
    'workspace.fixture_ready', v_admin_actor_id, pg_catalog.gen_random_uuid(),
    'macsad.event', 1, '{"step":2}'::jsonb, d03, d19, d20, v_now
  );

  IF NOT EXISTS (
    SELECT 1 FROM macsad.audit_stream
    WHERE workspace_id = v_workspace_id
      AND last_workspace_sequence = 2
      AND last_event_hash = d20
      AND version = 2
  ) OR NOT EXISTS (
    SELECT 1 FROM macsad.domain_event
    WHERE id = v_event_two_id
      AND workspace_sequence_no = 2
      AND previous_event_hash = d19
      AND event_hash = d20
  ) THEN
    RAISE EXCEPTION 'audit stream head does not match its ordered hash chain';
  END IF;

  ---------------------------------------------------------------------------
  -- Task movement closes a finished source, creates the exact successor path,
  -- and is backed by an event describing the source version and decision.
  ---------------------------------------------------------------------------
  UPDATE macsad.task
  SET state = 'running', version = version + 1
  WHERE id = v_task_id;

  UPDATE macsad.task
  SET state = 'completed', finished_at = pg_catalog.clock_timestamp(),
      version = version + 1
  WHERE id = v_task_id;

  BEGIN
    UPDATE macsad.task
    SET state = 'running', finished_at = NULL, version = version + 1
    WHERE id = v_task_id;
    RAISE EXCEPTION 'expected SQLSTATE 55000 when reopening a terminal task'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.domain_event (
    id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
    aggregate_version, event_kind, actor_id, correlation_id,
    payload_schema_id, payload_schema_version, payload_body, payload_digest,
    previous_event_hash, event_hash, occurred_at
  ) VALUES (
    v_task_ready_event_id, v_workspace_id, 3, 'task', v_task_id, 1,
    'task.readied', v_admin_actor_id, pg_catalog.gen_random_uuid(),
    'macsad.task-state-event', 1, '{"state":"ready"}'::jsonb, d51,
    d20, d51, v_now
  );

  -- Separate statements make lock/head sequencing explicit; SQL does not
  -- promise trigger execution order among rows of one multi-row INSERT.
  INSERT INTO macsad.domain_event (
    id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
    aggregate_version, event_kind, actor_id, correlation_id,
    payload_schema_id, payload_schema_version, payload_body, payload_digest,
    previous_event_hash, event_hash, occurred_at
  ) VALUES (
    v_task_running_event_id, v_workspace_id, 4, 'task', v_task_id, 2,
    'task.started', v_admin_actor_id, pg_catalog.gen_random_uuid(),
    'macsad.task-state-event', 1, '{"state":"running"}'::jsonb, d52,
    d51, d52, v_now
  );

  BEGIN
    INSERT INTO macsad.domain_event (
      id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
      aggregate_version, event_kind, actor_id, correlation_id,
      payload_schema_id, payload_schema_version, payload_body, payload_digest,
      previous_event_hash, event_hash, occurred_at
    ) VALUES (
      v_task_event_id, v_workspace_id, 5, 'task', v_task_id, 3,
      'task.transitioned', v_admin_actor_id, pg_catalog.gen_random_uuid(),
      'macsad.task-transition-event', 1,
      pg_catalog.jsonb_build_object(
        'task_transition_id', v_task_transition_id,
        'policy_transition_id', v_policy_transition_id,
        'decision_code', 'wrong-decision'
      ), d44, d52, d53, v_now
    );

    INSERT INTO macsad.task (
      id, workspace_id, research_case_id, policy_revision_id,
      problem_revision_id, process_key, node_key, sequence_no, state,
      board_phase, required_profile_key, required_profile_digest,
      entered_via_policy_transition_id
    ) VALUES (
      v_successor_task_id, v_workspace_id, v_case_id, v_policy_revision_id,
      v_problem_id, 'discovery', 'verify', 2, 'offered', 'verify',
      'researcher', d09, v_policy_transition_id
    );

    INSERT INTO macsad.task_transition (
      id, workspace_id, research_case_id, policy_revision_id, process_key,
      from_task_id, to_task_id, policy_transition_id, decided_by_actor_id,
      fact_schema_id, fact_schema_version, fact_snapshot, fact_snapshot_digest,
      decision_code, matched_order, domain_event_id
    ) VALUES (
      v_task_transition_id, v_workspace_id, v_case_id, v_policy_revision_id,
      'discovery', v_task_id, v_successor_task_id, v_policy_transition_id,
      v_admin_actor_id, 'macsad.transition-facts', 1,
      '{"result":"accepted"}'::jsonb, d46, 'complete', 0, v_task_event_id
    );

    SET CONSTRAINTS macsad.task_transition_event_semantics_ck IMMEDIATE;
    RAISE EXCEPTION 'expected SQLSTATE 23514 for a mismatched transition event'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.domain_event (
    id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
    aggregate_version, event_kind, actor_id, correlation_id,
    payload_schema_id, payload_schema_version, payload_body, payload_digest,
    previous_event_hash, event_hash, occurred_at
  ) VALUES (
    v_task_event_id, v_workspace_id, 5, 'task', v_task_id, 3,
    'task.transitioned', v_admin_actor_id, pg_catalog.gen_random_uuid(),
    'macsad.task-transition-event', 1,
    pg_catalog.jsonb_build_object(
      'task_transition_id', v_task_transition_id,
      'policy_transition_id', v_policy_transition_id,
      'decision_code', 'complete'
    ), d47, d52, d53, v_now
  );

  INSERT INTO macsad.task (
    id, workspace_id, research_case_id, policy_revision_id,
    problem_revision_id, process_key, node_key, sequence_no, state,
    board_phase, required_profile_key, required_profile_digest,
    entered_via_policy_transition_id
  ) VALUES (
    v_successor_task_id, v_workspace_id, v_case_id, v_policy_revision_id,
    v_problem_id, 'discovery', 'verify', 2, 'offered', 'verify',
    'researcher', d09, v_policy_transition_id
  );

  INSERT INTO macsad.task_transition (
    id, workspace_id, research_case_id, policy_revision_id, process_key,
    from_task_id, to_task_id, policy_transition_id, decided_by_actor_id,
    fact_schema_id, fact_schema_version, fact_snapshot, fact_snapshot_digest,
    decision_code, matched_order, domain_event_id
  ) VALUES (
    v_task_transition_id, v_workspace_id, v_case_id, v_policy_revision_id,
    'discovery', v_task_id, v_successor_task_id, v_policy_transition_id,
    v_admin_actor_id, 'macsad.transition-facts', 1,
    '{"result":"accepted"}'::jsonb, d46, 'complete', 0, v_task_event_id
  );

  SET CONSTRAINTS macsad.task_transition_event_semantics_ck,
    macsad.task_path_closed_ck IMMEDIATE;

  UPDATE macsad.task
  SET state = 'ready', version = version + 1
  WHERE id = v_successor_task_id;

  IF NOT EXISTS (
    SELECT 1 FROM macsad.audit_stream
    WHERE workspace_id = v_workspace_id
      AND last_workspace_sequence = 5
      AND last_event_hash = d53
      AND version = 5
  ) THEN
    RAISE EXCEPTION 'task transition event did not become the workspace audit head';
  END IF;

  ---------------------------------------------------------------------------
  -- Model calls are scoped to the execution's exact task. Budget admission is
  -- period-aware and strict; settlement is tied to the same call/execution but
  -- preserves actual overrun and later provider correction facts.
  ---------------------------------------------------------------------------
  INSERT INTO macsad.budget_account (
    id, workspace_id, research_case_id, resource_kind, unit_code, currency_code,
    period_start, period_end, initial_spending_limit, spending_limit
  ) VALUES
    (
      v_budget_account_id, v_workspace_id, v_case_id, 'currency', 'USD', 'USD',
      v_now - interval '1 hour', v_now + interval '1 day', 10, 10
    ),
    (
      v_expired_budget_account_id, v_workspace_id, v_case_id, 'currency',
      'USD-expired', 'USD', v_now - interval '2 days', v_now - interval '1 day',
      10, 10
    );

  BEGIN
    PERFORM macsad.record_budget_entry(
      v_expired_budget_account_id, 'reserve', 1, 'invariants:expired-reserve', d48,
      v_admin_actor_id, NULL, NULL, NULL, NULL, 'Expired reservation'
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 for an inactive budget period'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  BEGIN
    INSERT INTO macsad.model_call (
      workspace_id, research_case_id, task_id, execution_id,
      execution_tool_use_id, requested_by_actor_id, controller_actor_id,
      budget_account_id, idempotency_key, requested_model, resolved_model,
      resolved_provider, estimated_cost, reserved_cost, cost_currency,
      price_snapshot_digest, routing_policy_digest, max_output_tokens,
      stream_requested, credential_reference, credential_epoch,
      prompt_artifact_id, prompt_digest, context_digest, parameters_digest,
      openrouter_generation_id, request_schema_id, request_schema_version,
      sanitized_request, request_digest
    ) VALUES (
      v_workspace_id, v_case_id, v_successor_task_id, v_execution_id,
      v_model_tool_use_id, v_researcher_actor_id, v_worker_actor_id,
      v_budget_account_id, 'invariants:mismatched-model-call', 'openai/test',
      'openai/test', 'test-provider', 1, 1, 'USD', d30, d31, 100, false,
      'secret://openrouter/test', 1, v_public_artifact_id, d32, d33, d34,
      'generation-mismatch', 'openrouter.request', 1, '{"model":"openai/test"}'::jsonb,
      d35
    );
    RAISE EXCEPTION 'expected SQLSTATE 23503 for model-call task/execution mismatch'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23503' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.model_call (
    id, workspace_id, research_case_id, task_id, execution_id,
    execution_tool_use_id, requested_by_actor_id, controller_actor_id,
    budget_account_id, idempotency_key, requested_model, resolved_model,
    resolved_provider, estimated_cost, reserved_cost, cost_currency,
    price_snapshot_digest, routing_policy_digest, max_output_tokens,
    stream_requested, credential_reference, credential_epoch,
    prompt_artifact_id, prompt_digest, context_digest, parameters_digest,
    openrouter_generation_id, request_schema_id, request_schema_version,
    sanitized_request, request_digest
  ) VALUES
    (
      v_model_call_id, v_workspace_id, v_case_id, v_task_id, v_execution_id,
      v_model_tool_use_id, v_researcher_actor_id, v_worker_actor_id,
      v_budget_account_id, 'invariants:model-call-1', 'openai/test', 'openai/test',
      'test-provider', 5, 8, 'USD', d30, d31, 100, false,
      'secret://openrouter/test', 1, v_public_artifact_id, d32, d33, d34,
      'generation-1', 'openrouter.request', 1, '{"model":"openai/test"}'::jsonb,
      d36
    ),
    (
      v_other_model_call_id, v_workspace_id, v_case_id, v_task_id, v_execution_id,
      v_model_tool_use_id, v_researcher_actor_id, v_worker_actor_id,
      v_budget_account_id, 'invariants:model-call-2', 'openai/test', 'openai/test',
      'test-provider', 1, 1, 'USD', d37, d38, 100, false,
      'secret://openrouter/test', 1, v_public_artifact_id, d39, d40, d41,
      'generation-2', 'openrouter.request', 1, '{"model":"openai/test"}'::jsonb,
      d42
    );

  v_reservation_entry_id := macsad.record_budget_entry(
    v_budget_account_id, 'reserve', 8, 'invariants:reserve', d25,
    v_admin_actor_id, v_execution_id, v_model_call_id, NULL, NULL,
    'Reserve expected OpenRouter spend'
  );

  BEGIN
    PERFORM macsad.record_budget_entry(
      v_budget_account_id, 'reserve', 3, 'invariants:reserve-over-limit', d26,
      v_admin_actor_id, NULL, NULL, NULL, NULL, 'Rejected excess reservation'
    );
    RAISE EXCEPTION 'expected SQLSTATE P0001 for over-limit reservation'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  BEGIN
    PERFORM macsad.record_budget_entry(
      v_budget_account_id, 'release', 8, 'invariants:wrong-call-settlement', d27,
      v_admin_actor_id, v_execution_id, v_other_model_call_id, NULL,
      v_reservation_entry_id, 'Wrong-call release'
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 for cross-call settlement'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.model_usage_observation (
    id, workspace_id, model_call_id, observation_sequence, source, is_final,
    openrouter_generation_id, resolved_model, resolved_provider,
    prompt_tokens, completion_tokens, total_tokens, billed_amount,
    billed_currency, usage_schema_id, usage_schema_version, sanitized_usage,
    usage_digest, observed_at
  ) VALUES (
    v_usage_observation_id, v_workspace_id, v_model_call_id, 1,
    'generation_reconcile', true, 'generation-1', 'openai/test',
    'test-provider', 10, 5, 15, 15, 'USD', 'openrouter.usage', 1,
    '{"cost":15}'::jsonb, d43, v_now
  );

  PERFORM macsad.record_budget_entry(
    v_budget_account_id, 'commit', 15, 'invariants:commit-overrun', d27,
    v_admin_actor_id, v_execution_id, v_model_call_id, v_usage_observation_id,
    v_reservation_entry_id, 'Record actual provider charge without clamping'
  );

  INSERT INTO macsad.model_usage_observation (
    id, workspace_id, model_call_id, observation_sequence,
    supersedes_observation_id, source, is_final, openrouter_generation_id,
    resolved_model, resolved_provider, prompt_tokens, completion_tokens,
    total_tokens, billed_amount, billed_currency, usage_schema_id,
    usage_schema_version, sanitized_usage, usage_digest, observed_at
  ) VALUES (
    v_corrected_usage_observation_id, v_workspace_id, v_model_call_id, 2,
    v_usage_observation_id, 'manual_reconciliation', true, 'generation-1',
    'openai/test', 'test-provider', 10, 5, 15, 17, 'USD',
    'openrouter.usage', 1, '{"cost":17}'::jsonb, d44, v_now
  );

  PERFORM macsad.record_budget_entry(
    v_budget_account_id, 'spend_adjustment', 2,
    'invariants:spend-adjustment', d28, v_admin_actor_id, v_execution_id,
    v_model_call_id, v_corrected_usage_observation_id, NULL,
    'Record corrected provider charge delta'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM macsad.budget_balance_v AS balance
    WHERE balance.budget_account_id = v_budget_account_id
      AND balance.spending_limit = 10
      AND balance.reserved_quantity = 0
      AND balance.spent_quantity = 17
      AND balance.ledger_spending_limit = 10
      AND balance.ledger_reserved_quantity = 0
      AND balance.ledger_spent_quantity = 17
      AND balance.overrun_quantity = 7
      AND balance.available_to_reserve = 0
      AND NOT balance.can_reserve
      AND balance.projection_is_consistent
  ) THEN
    RAISE EXCEPTION 'budget ledger and account projection diverged after overrun settlement';
  END IF;

  ---------------------------------------------------------------------------
  -- Build one eligible case and seal a real publication batch. Once sealed,
  -- no further publication item may be added.
  ---------------------------------------------------------------------------
  INSERT INTO macsad.claim (
    id, workspace_id, problem_revision_id, kind, canonical_text, scope_bounds,
    content_digest, proposed_by_actor_id
  ) VALUES (
    v_claim_id, v_workspace_id, v_problem_id, 'formal_proposition',
    'The fixture theorem holds.', 'Finite fixture domain', d13,
    v_researcher_actor_id
  );

  BEGIN
    INSERT INTO macsad.attestation (
      workspace_id, problem_revision_id, claim_id, issuer_actor_id,
      issuer_membership_id, issuer_profile_key, issuer_profile_digest, kind,
      authority_class, value_schema_id, value_schema_version, value_body,
      value_digest, outcome_code, content_digest
    ) VALUES (
      v_workspace_id, v_problem_id, v_claim_id, v_researcher_actor_id,
      v_membership_id, 'researcher', d09, 'human_disposition', 'human_decided',
      'macsad.human-disposition', 1, '{"disposition":"proved"}'::jsonb,
      d48, 'proved', d48
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 for agent-issued human authority'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  BEGIN
    INSERT INTO macsad.attestation (
      workspace_id, problem_revision_id, claim_id, issuer_actor_id,
      issuer_membership_id, issuer_profile_key, issuer_profile_digest, kind,
      authority_class, value_schema_id, value_schema_version, value_body,
      value_digest, outcome_code, content_digest
    ) VALUES (
      v_workspace_id, v_problem_id, v_claim_id, v_admin_actor_id,
      v_membership_id, 'researcher', d09, 'human_disposition', 'human_decided',
      'macsad.human-disposition', 1, '{"disposition":"proved"}'::jsonb,
      d49, 'proved', d49
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 for issuer/membership mismatch'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.attestation (
    id, workspace_id, problem_revision_id, claim_id, issuer_actor_id,
    issuer_membership_id, issuer_profile_key, issuer_profile_digest, kind,
    authority_class, value_schema_id, value_schema_version, value_body,
    value_digest, outcome_code, content_digest
  ) VALUES
    (
      v_disposition_attestation_id, v_workspace_id, v_problem_id, v_claim_id,
      v_admin_actor_id, v_admin_membership_id, 'reviewer', d29,
      'human_disposition', 'human_decided',
      'macsad.human-disposition', 1, '{"disposition":"proved"}'::jsonb,
      d14, 'proved', d14
    ),
    (
      v_eligibility_attestation_id, v_workspace_id, v_problem_id, v_claim_id,
      v_admin_actor_id, v_admin_membership_id, 'reviewer', d29,
      'editorial_decision', 'human_decided',
      'macsad.editorial-decision', 1, '{"decision":"eligible"}'::jsonb,
      d15, 'eligible', d15
    );

  BEGIN
    INSERT INTO macsad.publication_dossier (
      workspace_id, research_case_id, problem_revision_id, claim_id,
      dossier_artifact_id, closure_schema_id, closure_schema_version,
      closure_body, closure_digest, created_by_actor_id
    ) VALUES (
      v_workspace_id, v_case_id, v_problem_id, v_claim_id,
      v_public_artifact_id, 'macsad.publication-closure', 1,
      '{"case":"still-open"}'::jsonb, d48, v_admin_actor_id
    );
    RAISE EXCEPTION 'expected SQLSTATE 23514 for a dossier from an open case'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23514' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  UPDATE macsad.research_case
  SET state = 'closed', disposition_family = 'mathematics',
      math_disposition = 'proved',
      disposition_attestation_id = v_disposition_attestation_id,
      editorial_decision = 'eligible',
      eligibility_attestation_id = v_eligibility_attestation_id,
      closed_at = pg_catalog.clock_timestamp(), version = version + 1
  WHERE id = v_case_id;

  INSERT INTO macsad.publication_dossier (
    id, workspace_id, research_case_id, problem_revision_id, claim_id,
    dossier_artifact_id, closure_schema_id, closure_schema_version,
    closure_body, closure_digest, created_by_actor_id
  ) VALUES (
    v_publication_dossier_id, v_workspace_id, v_case_id, v_problem_id,
    v_claim_id, v_public_artifact_id, 'macsad.publication-closure', 1,
    '{"case":"closed","eligible":true}'::jsonb, d49, v_admin_actor_id
  );

  INSERT INTO macsad.research_case (
    id, workspace_id, workspace_snapshot_id, policy_revision_id,
    problem_revision_id, process_key, tool_closure_digest
  ) VALUES (
    v_other_case_id, v_workspace_id, v_snapshot_id, v_policy_revision_id,
    v_other_problem_id, 'discovery', d16
  );

  INSERT INTO macsad.claim (
    id, workspace_id, problem_revision_id, kind, canonical_text, scope_bounds,
    content_digest, proposed_by_actor_id
  ) VALUES (
    v_other_claim_id, v_workspace_id, v_other_problem_id, 'formal_proposition',
    'The other fixture theorem holds.', 'Finite fixture domain', d16,
    v_researcher_actor_id
  );

  INSERT INTO macsad.attestation (
    id, workspace_id, problem_revision_id, claim_id, issuer_actor_id,
    issuer_membership_id, issuer_profile_key, issuer_profile_digest, kind,
    authority_class, value_schema_id, value_schema_version, value_body,
    value_digest, outcome_code, content_digest
  ) VALUES
    (
      v_other_disposition_attestation_id, v_workspace_id, v_other_problem_id,
      v_other_claim_id, v_admin_actor_id, v_admin_membership_id, 'reviewer', d29,
      'human_disposition', 'human_decided',
      'macsad.human-disposition', 1, '{"disposition":"proved"}'::jsonb,
      d17, 'proved', d17
    ),
    (
      v_other_eligibility_attestation_id, v_workspace_id, v_other_problem_id,
      v_other_claim_id, v_admin_actor_id, v_admin_membership_id, 'reviewer', d29,
      'editorial_decision', 'human_decided',
      'macsad.editorial-decision', 1, '{"decision":"eligible"}'::jsonb,
      d18, 'eligible', d18
    );

  UPDATE macsad.research_case
  SET state = 'closed', disposition_family = 'mathematics',
      math_disposition = 'proved',
      disposition_attestation_id = v_other_disposition_attestation_id,
      editorial_decision = 'eligible',
      eligibility_attestation_id = v_other_eligibility_attestation_id,
      closed_at = pg_catalog.clock_timestamp(), version = version + 1
  WHERE id = v_other_case_id;

  INSERT INTO macsad.publication_dossier (
    id, workspace_id, research_case_id, problem_revision_id, claim_id,
    dossier_artifact_id, closure_schema_id, closure_schema_version,
    closure_body, closure_digest, created_by_actor_id
  ) VALUES (
    v_other_publication_dossier_id, v_workspace_id, v_other_case_id,
    v_other_problem_id, v_other_claim_id, v_public_artifact_id,
    'macsad.publication-closure', 1,
    '{"case":"closed","eligible":true}'::jsonb, d50, v_admin_actor_id
  );

  INSERT INTO macsad.publication_batch (
    id, workspace_id, policy_revision_id
  ) VALUES (
    v_publication_batch_id, v_workspace_id, v_policy_revision_id
  );

  INSERT INTO macsad.publication_item (
    workspace_id, publication_batch_id, research_case_id, problem_revision_id,
    claim_id, disposition_attestation_id, eligibility_attestation_id,
    publication_dossier_id, dossier_artifact_id, item_ordinal, item_digest
  ) VALUES (
    v_workspace_id, v_publication_batch_id, v_case_id, v_problem_id,
    v_claim_id, v_disposition_attestation_id, v_eligibility_attestation_id,
    v_publication_dossier_id, v_public_artifact_id, 0, d26
  );

  BEGIN
    INSERT INTO macsad.publication_item (
      workspace_id, publication_batch_id, research_case_id, problem_revision_id,
      claim_id, disposition_attestation_id, eligibility_attestation_id,
      publication_dossier_id, dossier_artifact_id, item_ordinal, item_digest
    ) VALUES (
      v_workspace_id, v_publication_batch_id, v_other_case_id,
      v_other_problem_id, v_other_claim_id,
      v_other_disposition_attestation_id, v_other_eligibility_attestation_id,
      v_publication_dossier_id, v_public_artifact_id, 1, d27
    );
    RAISE EXCEPTION 'expected SQLSTATE 23503 for dossier/case closure mismatch'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '23503' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  UPDATE macsad.publication_batch
  SET state = 'previewed', batch_sequence = 1,
      generator_artifact_id = v_public_artifact_id,
      toolchain_artifact_id = v_public_artifact_id,
      generator_revision_digest = d21, platform_revision_digest = d22,
      toolchain_closure_digest = d23, evidence_closure_digest = d24,
      artifact_closure_digest = d25, audit_head_event_id = v_task_event_id,
      audit_head_sequence_no = 5, audit_head_event_hash = d53,
      previewed_at = pg_catalog.clock_timestamp(), version = version + 1
  WHERE id = v_publication_batch_id;

  BEGIN
    INSERT INTO macsad.publication_item (
      workspace_id, publication_batch_id, research_case_id, problem_revision_id,
      claim_id, disposition_attestation_id, eligibility_attestation_id,
      publication_dossier_id, dossier_artifact_id, item_ordinal, item_digest
    ) VALUES (
      v_workspace_id, v_publication_batch_id, v_other_case_id,
      v_other_problem_id, v_other_claim_id,
      v_other_disposition_attestation_id, v_other_eligibility_attestation_id,
      v_other_publication_dossier_id, v_public_artifact_id, 1, d27
    );
    RAISE EXCEPTION 'expected SQLSTATE 55000 when adding an item after draft'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  UPDATE macsad.publication_batch
  SET state = 'sealed', manifest_artifact_id = v_public_artifact_id,
      manifest_digest = d27, signature = pg_catalog.decode('a1', 'hex'),
      sealed_by_actor_id = v_admin_actor_id,
      sealed_at = pg_catalog.clock_timestamp(), version = version + 1
  WHERE id = v_publication_batch_id;

  BEGIN
    INSERT INTO macsad.publication_item (
      workspace_id, publication_batch_id, research_case_id, problem_revision_id,
      claim_id, disposition_attestation_id, eligibility_attestation_id,
      publication_dossier_id, dossier_artifact_id, item_ordinal, item_digest
    ) VALUES (
      v_workspace_id, v_publication_batch_id, v_other_case_id,
      v_other_problem_id, v_other_claim_id,
      v_other_disposition_attestation_id, v_other_eligibility_attestation_id,
      v_other_publication_dossier_id, v_public_artifact_id, 1, d28
    );
    RAISE EXCEPTION 'expected SQLSTATE 55000 when adding an item after sealing'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  INSERT INTO macsad.publication_attempt (
    id, workspace_id, publication_batch_id, attempt_no, trigger_kind,
    target_environment, platform_revision_digest, generator_revision_digest,
    release_request_digest, github_repository_id, github_workflow,
    cloudflare_account_reference, cloudflare_project_name
  ) VALUES (
    v_publication_attempt_id, v_workspace_id, v_publication_batch_id, 1,
    'manual', 'test', d22, d21, d28, 910000001, 'publish.yml',
    'cloudflare:test-account', 'macsad-test'
  );

  UPDATE macsad.publication_attempt
  SET state = 'failed', error_code = 'fixture_failure',
      finished_at = pg_catalog.clock_timestamp(), version = version + 1
  WHERE id = v_publication_attempt_id;

  BEGIN
    UPDATE macsad.publication_attempt
    SET state = 'running', error_code = NULL, finished_at = NULL,
        started_at = pg_catalog.clock_timestamp(), version = version + 1
    WHERE id = v_publication_attempt_id;
    RAISE EXCEPTION 'expected SQLSTATE 55000 when reopening a terminal publication attempt'
      USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
    WHEN OTHERS THEN RAISE;
  END;

  RAISE NOTICE '0001 high-value invariant tests passed; transaction will be rolled back';
END;
$invariants$;

ROLLBACK;
