-- Deterministic, inert MaCSad v1 scenario data for a freshly migrated scratch
-- database. The caller owns the transaction and forces rollback on any error.
\set ON_ERROR_STOP on

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '2min';
SET LOCAL timezone = 'UTC';
SET LOCAL ROLE macsad_owner;
SET CONSTRAINTS ALL DEFERRED;

CREATE FUNCTION pg_temp.digest(value text, algorithm text)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
RETURNS NULL ON NULL INPUT
AS $digest$
  SELECT CASE algorithm
    WHEN 'sha256' THEN pg_catalog.sha256(pg_catalog.convert_to(value, 'UTF8'))
    ELSE NULL
  END
$digest$;

SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('macsad:seed:representative-v1', 0)
);

DO $preflight$
BEGIN
  IF (SELECT current_version FROM macsad.schema_version_v) <> 1 THEN
    RAISE EXCEPTION 'representative-v1 requires schema version 1';
  END IF;
  IF EXISTS (SELECT 1 FROM macsad.workspace)
      OR EXISTS (SELECT 1 FROM macsad.actor)
      OR EXISTS (SELECT 1 FROM macsad.blob) THEN
    RAISE EXCEPTION 'representative-v1 requires an empty migrated scratch database';
  END IF;
END
$preflight$;

INSERT INTO macsad.workspace (
  id, github_repository_id, owner_name, repository_name, default_branch,
  installation_id, state, version, created_at, updated_at
) VALUES (
  '10000000-0000-4000-8000-000000000001', 910000001,
  'Brahmastra-Labs', 'macsad-fixture', 'main', 920000001,
  'pending', 0, '2026-01-15T12:00:00.000000Z', '2026-01-15T12:00:00.000000Z'
);

UPDATE macsad.workspace
SET state = 'active', version = 1
WHERE id = '10000000-0000-4000-8000-000000000001';

INSERT INTO macsad.actor (
  id, kind, display_name, state, version, created_at, updated_at
) VALUES
  ('11000000-0000-4000-8000-000000000001', 'human', 'Fixture director', 'active', 0,
   '2026-01-15T12:00:01Z', '2026-01-15T12:00:01Z'),
  ('11000000-0000-4000-8000-000000000002', 'agent', 'Fixture investigator', 'active', 0,
   '2026-01-15T12:00:02Z', '2026-01-15T12:00:02Z'),
  ('11000000-0000-4000-8000-000000000003', 'agent', 'Fixture verifier', 'active', 0,
   '2026-01-15T12:00:03Z', '2026-01-15T12:00:03Z'),
  ('11000000-0000-4000-8000-000000000004', 'service', 'Fixture worker', 'active', 0,
   '2026-01-15T12:00:04Z', '2026-01-15T12:00:04Z'),
  ('11000000-0000-4000-8000-000000000005', 'service', 'Fixture controller', 'active', 0,
   '2026-01-15T12:00:05Z', '2026-01-15T12:00:05Z');

INSERT INTO macsad.actor_identity (
  id, actor_id, issuer, subject, audience, valid_from, valid_until, revoked_at,
  version, created_at, updated_at
) VALUES
  ('11100000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001',
   'https://access.example.invalid', 'director@example.invalid', 'macsad-admin',
   '2026-01-01T00:00:00Z', '2030-01-01T00:00:00Z', NULL, 0,
   '2026-01-15T12:00:06Z', '2026-01-15T12:00:06Z'),
  ('11100000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000004',
   'spiffe://fixture.invalid', 'worker/retired-certificate', 'macsad-worker',
   '2025-01-01T00:00:00Z', '2027-01-01T00:00:00Z', '2026-01-10T00:00:00Z', 0,
   '2026-01-15T12:00:07Z', '2026-01-15T12:00:07Z');

INSERT INTO macsad.blob (
  digest, byte_length, media_type, content_encoding, compression,
  provider_checksum, storage_provider, storage_locator, storage_class,
  stored_at, verified_at, created_at
)
SELECT
  pg_temp.digest(body, 'sha256'),
  pg_catalog.octet_length(pg_catalog.convert_to(body, 'UTF8')),
  media_type,
  content_encoding,
  compression,
  provider_checksum,
  'fixture_cas',
  'sha256/' || pg_catalog.encode(pg_temp.digest(body, 'sha256'), 'hex'),
  storage_class,
  stored_at,
  verified_at,
  created_at
FROM (VALUES
  ('workspace bundle v1', 'application/x-tar', 'identity', 'none', 'fixture:workspace', 'source',
   '2026-01-15T12:00:10Z'::timestamptz, '2026-01-15T12:00:11Z'::timestamptz,
   '2026-01-15T12:00:10Z'::timestamptz),
  ('tool source bundle v1', 'application/x-tar', NULL, NULL, NULL, 'source',
   '2026-01-15T12:00:12Z'::timestamptz, '2026-01-15T12:00:13Z'::timestamptz,
   '2026-01-15T12:00:12Z'::timestamptz),
  ('tool executable v1', 'application/octet-stream', NULL, NULL, NULL, 'executable',
   '2026-01-15T12:00:14Z'::timestamptz, '2026-01-15T12:00:15Z'::timestamptz,
   '2026-01-15T12:00:14Z'::timestamptz),
  ('compatibility evidence v1', 'application/json', 'utf-8', 'none', NULL, 'evidence',
   '2026-01-15T12:00:16Z'::timestamptz, '2026-01-15T12:00:17Z'::timestamptz,
   '2026-01-15T12:00:16Z'::timestamptz),
  ('semantic policy diff v1', 'text/plain', 'utf-8', 'none', NULL, 'evidence',
   '2026-01-15T12:00:18Z'::timestamptz, '2026-01-15T12:00:19Z'::timestamptz,
   '2026-01-15T12:00:18Z'::timestamptz),
  ('math prompt\nwith unicode λ', 'text/markdown', 'utf-8', 'none', NULL, 'private',
   '2026-01-15T12:00:20Z'::timestamptz, '2026-01-15T12:00:21Z'::timestamptz,
   '2026-01-15T12:00:20Z'::timestamptz),
  ('math response v1', 'application/json', 'utf-8', 'none', NULL, 'private',
   '2026-01-15T12:00:22Z'::timestamptz, '2026-01-15T12:00:23Z'::timestamptz,
   '2026-01-15T12:00:22Z'::timestamptz),
  ('public dossier v1', 'application/json', 'utf-8', 'none', NULL, 'public',
   '2026-01-15T12:00:24Z'::timestamptz, '2026-01-15T12:00:25Z'::timestamptz,
   '2026-01-15T12:00:24Z'::timestamptz),
  ('publication generator v1', 'application/octet-stream', NULL, NULL, NULL, 'executable',
   '2026-01-15T12:00:26Z'::timestamptz, '2026-01-15T12:00:27Z'::timestamptz,
   '2026-01-15T12:00:26Z'::timestamptz),
  ('sealed manifest v1', 'application/json', 'utf-8', 'none', NULL, 'public',
   '2026-01-15T12:00:28Z'::timestamptz, '2026-01-15T12:00:29Z'::timestamptz,
   '2026-01-15T12:00:28Z'::timestamptz)
) AS fixture_blob(
  body, media_type, content_encoding, compression, provider_checksum,
  storage_class, stored_at, verified_at, created_at
);

INSERT INTO macsad.artifact (
  id, workspace_id, blob_digest, artifact_kind, schema_id, schema_version,
  classification, secret_scan_result, quarantined, producing_actor_id,
  producing_execution_id, original_source, observed_at, license_expression,
  attribution, redistribution_allowed, export_decision, created_at
)
SELECT
  artifact_id,
  '10000000-0000-4000-8000-000000000001',
  pg_temp.digest(body, 'sha256'),
  artifact_kind,
  'macsad.fixture-artifact', 1,
  classification::macsad.artifact_classification,
  'passed', false,
  '11000000-0000-4000-8000-000000000001',
  NULL,
  'fixture://' || artifact_kind,
  observed_at,
  'CC0-1.0',
  'MaCSad deterministic fixture',
  classification = 'public_candidate',
  CASE classification
    WHEN 'public_candidate' THEN 'allowed-by-fixture-contract'
    ELSE 'retained-internally'
  END,
  observed_at
FROM (VALUES
  ('12000000-0000-4000-8000-000000000001'::uuid, 'workspace bundle v1', 'workspace_bundle', 'internal', '2026-01-15T12:00:30Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000002'::uuid, 'tool source bundle v1', 'tool_source_bundle', 'internal', '2026-01-15T12:00:31Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000003'::uuid, 'tool executable v1', 'tool_executable', 'internal', '2026-01-15T12:00:32Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000004'::uuid, 'compatibility evidence v1', 'compatibility_evidence', 'internal', '2026-01-15T12:00:33Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000005'::uuid, 'semantic policy diff v1', 'semantic_diff', 'internal', '2026-01-15T12:00:34Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000006'::uuid, 'math prompt\nwith unicode λ', 'model_prompt', 'private', '2026-01-15T12:00:35Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000007'::uuid, 'math response v1', 'model_response', 'private', '2026-01-15T12:00:36Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000008'::uuid, 'public dossier v1', 'publication_dossier', 'public_candidate', '2026-01-15T12:00:37Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000009'::uuid, 'publication generator v1', 'publication_generator', 'internal', '2026-01-15T12:00:38Z'::timestamptz),
  ('12000000-0000-4000-8000-000000000010'::uuid, 'sealed manifest v1', 'publication_manifest', 'public_candidate', '2026-01-15T12:00:39Z'::timestamptz)
) AS fixture_artifact(artifact_id, body, artifact_kind, classification, observed_at);

INSERT INTO macsad.workspace_snapshot (
  id, workspace_id, object_algorithm, commit_oid, tree_oid,
  observed_default_branch, observation_source, source_artifact_id,
  configuration_digest, repository_policy_result, repository_policy_schema_id,
  repository_policy_schema_version, repository_policy_body,
  repository_policy_digest, snapshot_digest, observed_at, preserved_at, created_at
) VALUES (
  '13000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'sha1', pg_catalog.repeat('a', 40), pg_catalog.repeat('b', 40),
  'main', 'reconciliation', '12000000-0000-4000-8000-000000000001',
  pg_temp.digest('fixture configuration v1', 'sha256'), 'accepted',
  'macsad.repository-policy', 1, '{"accepted":true,"source":"fixture"}',
  pg_temp.digest('{"accepted": true, "source": "fixture"}'::jsonb::text, 'sha256'),
  pg_temp.digest('fixture snapshot v1', 'sha256'),
  '2026-01-15T12:00:40Z', '2026-01-15T12:00:41Z', '2026-01-15T12:00:40Z'
);

INSERT INTO macsad.tool_repository (
  id, workspace_id, repository_key, purpose, source_kind,
  github_repository_id, owner_name, repository_name, default_branch,
  locator_key, connection_reference, default_classification, exposure,
  approved_by_actor_id, approved_at, state, version, created_at, updated_at
) VALUES (
  '14000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture-checker', 'Bounded deterministic checker', 'github',
  930000001, 'Brahmastra-Labs', 'fixture-checker', 'main',
  'github/brahmastra-labs/fixture-checker', 'secretref://fixture/github-installation',
  'internal', 'private_host', '11000000-0000-4000-8000-000000000001',
  '2026-01-15T12:00:42Z', 'active', 0,
  '2026-01-15T12:00:42Z', '2026-01-15T12:00:42Z'
);

INSERT INTO macsad.tool_repository_revision (
  id, workspace_id, tool_repository_id, object_algorithm, commit_oid, tree_oid,
  observed_branch, observation_source, source_artifact_id,
  access_policy_schema_id, access_policy_schema_version, access_policy_body,
  access_policy_digest, source_digest, manifest_digest, lock_digest,
  dependency_digest, build_environment_digest, promoted_bundle_artifact_id,
  promoted_executable_artifact_id, compatibility_evidence_artifact_id,
  operation_count, operation_catalog_digest, operations_sealed_by_actor_id,
  operations_sealed_at, revision_digest, observed_at, preserved_at, promoted_at,
  created_at
) VALUES (
  '14100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '14000000-0000-4000-8000-000000000001',
  'sha1', pg_catalog.repeat('c', 40), pg_catalog.repeat('d', 40), 'main',
  'reconciliation', '12000000-0000-4000-8000-000000000002',
  'macsad.tool-access', 1, '{"mode":"operation_invoke"}',
  pg_temp.digest('{"mode": "operation_invoke"}'::jsonb::text, 'sha256'),
  pg_temp.digest('tool source v1', 'sha256'),
  pg_temp.digest('tool manifest v1', 'sha256'),
  pg_temp.digest('tool lock v1', 'sha256'),
  pg_temp.digest('tool dependency closure v1', 'sha256'),
  pg_temp.digest('tool build environment v1', 'sha256'),
  '12000000-0000-4000-8000-000000000002',
  '12000000-0000-4000-8000-000000000003',
  '12000000-0000-4000-8000-000000000004',
  NULL, NULL, NULL, NULL,
  pg_temp.digest('tool revision v1', 'sha256'),
  '2026-01-15T12:00:43Z', '2026-01-15T12:00:44Z', '2026-01-15T12:00:45Z',
  '2026-01-15T12:00:43Z'
);

INSERT INTO macsad.tool_operation_manifest (
  id, workspace_id, tool_repository_revision_id, operation_key,
  operation_version, provider_key, provider_revision, effect_class,
  request_schema_id, request_schema_version, request_schema_digest,
  response_schema_id, response_schema_version, response_schema_digest,
  manifest_schema_id, manifest_schema_version, manifest_body, manifest_digest,
  created_at
) VALUES (
  '14200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '14100000-0000-4000-8000-000000000001',
  'fixture.check', 1, 'fixture-provider', '1.0.0', 'model_call',
  'macsad.fixture-request', 1, pg_temp.digest('fixture request schema v1', 'sha256'),
  'macsad.fixture-response', 1, pg_temp.digest('fixture response schema v1', 'sha256'),
  'macsad.tool-operation', 1, '{"operation":"fixture.check","bounded":true}',
  pg_temp.digest('{"bounded": true, "operation": "fixture.check"}'::jsonb::text, 'sha256'),
  '2026-01-15T12:00:46Z'
);

UPDATE macsad.tool_repository_revision
SET operation_count = 1,
    operation_catalog_digest = pg_temp.digest('fixture operation catalogue v1', 'sha256'),
    operations_sealed_by_actor_id = '11000000-0000-4000-8000-000000000001',
    operations_sealed_at = '2026-01-15T12:00:47Z'
WHERE id = '14100000-0000-4000-8000-000000000001';

INSERT INTO macsad.policy_revision (
  id, workspace_id, workspace_snapshot_id, prior_revision_id, source_path,
  source_digest, compiler_name, compiler_version, schema_id, schema_version,
  compiled_body, compiled_digest, validation_result, validation_schema_id,
  validation_schema_version, validation_body, validation_digest, validated_at,
  semantic_diff_artifact_id, state, activated_by_actor_id, activated_at,
  retired_at, version, created_at, updated_at
) VALUES
  (
    '15000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '13000000-0000-4000-8000-000000000001', NULL,
    '.macsad/policy-v0.json', pg_temp.digest('fixture policy source v0', 'sha256'),
    'macsad-policy-compiler', '1.0.0', 'macsad.policy', 1,
    '{"revision":0}', pg_temp.digest('{"revision": 0}'::jsonb::text, 'sha256'),
    'passed', 'macsad.policy-validation', 1, '{"valid":true}',
    pg_temp.digest('{"valid": true}'::jsonb::text, 'sha256'),
    '2026-01-15T12:00:48Z', NULL, 'candidate', NULL, NULL, NULL, 0,
    '2026-01-15T12:00:48Z', '2026-01-15T12:00:48Z'
  ),
  (
    '15000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '13000000-0000-4000-8000-000000000001',
    '15000000-0000-4000-8000-000000000001',
    '.macsad/policy.json', pg_temp.digest('fixture policy source v1', 'sha256'),
    'macsad-policy-compiler', '1.0.0', 'macsad.policy', 1,
    '{"revision":1,"processes":["discovery"]}',
    pg_temp.digest('{"processes": ["discovery"], "revision": 1}'::jsonb::text, 'sha256'),
    'passed', 'macsad.policy-validation', 1, '{"valid":true,"warnings":[]}',
    pg_temp.digest('{"valid": true, "warnings": []}'::jsonb::text, 'sha256'),
    '2026-01-15T12:00:49Z', '12000000-0000-4000-8000-000000000005',
    'candidate', NULL, NULL, NULL, 0,
    '2026-01-15T12:00:49Z', '2026-01-15T12:00:49Z'
  );

UPDATE macsad.policy_revision
SET state = 'active', activated_by_actor_id = '11000000-0000-4000-8000-000000000001',
    activated_at = '2026-01-15T12:00:50Z', version = 1
WHERE id = '15000000-0000-4000-8000-000000000001';
UPDATE macsad.policy_revision
SET state = 'retired', retired_at = '2026-01-15T12:00:51Z', version = 2
WHERE id = '15000000-0000-4000-8000-000000000001';

INSERT INTO macsad.policy_member_profile (
  id, workspace_id, policy_revision_id, profile_key, display_name, role_key,
  supervisor_profile_key, wip_limit, profile_schema_id, profile_schema_version,
  profile_body, profile_digest, created_at
) VALUES
  ('15100000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'director', 'Director', 'director', NULL, 4,
   'macsad.member-profile', 1, '{"role":"director"}',
   pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'), '2026-01-15T12:00:52Z'),
  ('15100000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'investigator', 'Investigator', 'investigator',
   'director', 2, 'macsad.member-profile', 1, '{"role":"investigator"}',
   pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'), '2026-01-15T12:00:53Z'),
  ('15100000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'verifier', 'Verifier', 'verifier',
   'director', 2, 'macsad.member-profile', 1, '{"role":"verifier"}',
   pg_temp.digest('{"role": "verifier"}'::jsonb::text, 'sha256'), '2026-01-15T12:00:54Z');

INSERT INTO macsad.policy_process (
  id, workspace_id, policy_revision_id, process_key, title, entry_node_key,
  process_schema_id, process_schema_version, process_body, graph_digest, created_at
) VALUES (
  '15200000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '15000000-0000-4000-8000-000000000002', 'discovery', 'Fixture discovery', 'investigate',
  'macsad.process', 1, '{"entry":"investigate","terminal":"done"}',
  pg_temp.digest('fixture graph v1', 'sha256'), '2026-01-15T12:00:55Z'
);

INSERT INTO macsad.policy_node (
  id, workspace_id, policy_revision_id, process_key, node_key, node_kind, title,
  board_phase, required_profile_key, timeout_seconds, retry_limit,
  node_schema_id, node_schema_version, node_body, node_digest, created_at
) VALUES
  ('15300000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'discovery', 'investigate', 'task',
   'Investigate', 'running', 'investigator', 600, 1, 'macsad.node', 1,
   '{"kind":"task","timeout_seconds":600}', pg_temp.digest('node investigate v1', 'sha256'),
   '2026-01-15T12:00:56Z'),
  ('15300000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'discovery', 'verify', 'task',
   'Verify', 'verify', 'verifier', 300, 0, 'macsad.node', 1,
   '{"kind":"task","timeout_seconds":300}', pg_temp.digest('node verify v1', 'sha256'),
   '2026-01-15T12:00:57Z'),
  ('15300000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'discovery', 'done', 'terminal',
   'Done', 'closed', NULL, NULL, 0, 'macsad.node', 1,
   '{"kind":"terminal"}', pg_temp.digest('node done v1', 'sha256'),
   '2026-01-15T12:00:58Z');

INSERT INTO macsad.policy_transition (
  id, workspace_id, policy_revision_id, process_key, transition_key,
  source_node_key, target_node_key, transition_kind, match_order, is_default,
  decision_code, assignment_profile_key, predicate_schema_id,
  predicate_schema_version, predicate_body, predicate_digest, created_at
) VALUES
  ('15400000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'discovery', 'investigate.success',
   'investigate', 'verify', 'success', 0, false, 'candidate_ready', 'verifier',
   'macsad.predicate', 1, '{"claim_outcome":"supported"}',
   pg_temp.digest('{"claim_outcome": "supported"}'::jsonb::text, 'sha256'),
   '2026-01-15T12:00:59Z'),
  ('15400000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'discovery', 'verify.default',
   'verify', 'done', 'default', 0, true, 'review_complete', NULL,
   NULL, NULL, NULL, NULL, '2026-01-15T12:01:00Z'),
  ('15400000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'discovery', 'investigate.cancel',
   'investigate', 'done', 'cancel', 1, false, 'cancelled_by_controller', NULL,
   'macsad.predicate', 1, '{"cancel_requested":true}',
   pg_temp.digest('{"cancel_requested": true}'::jsonb::text, 'sha256'),
   '2026-01-15T12:01:00Z');

INSERT INTO macsad.policy_node_tool_operation (
  id, workspace_id, policy_revision_id, process_key, node_key,
  tool_operation_manifest_id, max_invocations, required, created_at
) VALUES (
  '15500000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '15000000-0000-4000-8000-000000000002', 'discovery', 'investigate',
  '14200000-0000-4000-8000-000000000001', 2, true, '2026-01-15T12:01:01Z'
);

UPDATE macsad.policy_revision
SET state = 'active', activated_by_actor_id = '11000000-0000-4000-8000-000000000001',
    activated_at = '2026-01-15T12:01:02Z', version = 1
WHERE id = '15000000-0000-4000-8000-000000000002';

INSERT INTO macsad.membership (
  id, workspace_id, actor_id, policy_revision_id, profile_key, profile_digest,
  supervisor_actor_id, state, valid_from, valid_until, version, created_at, updated_at
) VALUES
  ('16000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '15000000-0000-4000-8000-000000000002',
   'director', pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'), NULL,
   'active', '2026-01-01T00:00:00Z', '2030-01-01T00:00:00Z', 0,
   '2026-01-15T12:01:03Z', '2026-01-15T12:01:03Z'),
  ('16000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000002', '15000000-0000-4000-8000-000000000002',
   'investigator', pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'),
   '11000000-0000-4000-8000-000000000001', 'active',
   '2026-01-01T00:00:00Z', '2030-01-01T00:00:00Z', 0,
   '2026-01-15T12:01:04Z', '2026-01-15T12:01:04Z'),
  ('16000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000003', '15000000-0000-4000-8000-000000000002',
   'verifier', pg_temp.digest('{"role": "verifier"}'::jsonb::text, 'sha256'),
   '11000000-0000-4000-8000-000000000001', 'active',
   '2026-01-01T00:00:00Z', '2030-01-01T00:00:00Z', 0,
   '2026-01-15T12:01:05Z', '2026-01-15T12:01:05Z');

INSERT INTO macsad.capability_grant (
  id, workspace_id, actor_id, capability_code, constraint_schema_id,
  constraint_schema_version, constraint_body, constraint_digest,
  granted_by_actor_id, valid_from, valid_until, revoked_at, reason, version,
  created_at, updated_at
) VALUES
  ('16100000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', 'publication.seal',
   'macsad.capability-constraint', 1, '{"workspace_only":true}',
   pg_temp.digest('{"workspace_only": true}'::jsonb::text, 'sha256'),
   '11000000-0000-4000-8000-000000000001', '2026-01-01T00:00:00Z',
   '2030-01-01T00:00:00Z', NULL, 'Fixture publication authority', 0,
   '2026-01-15T12:01:06Z', '2026-01-15T12:01:06Z'),
  ('16100000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000002', 'execution.start',
   NULL, NULL, NULL, NULL, '11000000-0000-4000-8000-000000000001',
   '2025-01-01T00:00:00Z', '2027-01-01T00:00:00Z', '2026-01-10T00:00:00Z',
   'Historical revoked fixture grant', 0,
   '2026-01-15T12:01:07Z', '2026-01-15T12:01:07Z');

INSERT INTO macsad.problem_revision (
  id, workspace_id, research_kind, prior_revision_id, title, original_question,
  definitions, assumptions, domain_bounds, success_criteria,
  refutation_criteria, inconclusive_criteria, revision_reason,
  kind_schema_id, kind_schema_version, kind_body, content_digest,
  created_by_actor_id, created_at
) VALUES
  ('17000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   'mathematics', NULL, 'Prior finite sum question', 'Does one plus one equal two?',
   'Natural numbers.', 'Peano arithmetic.', 'Integers from 0 through 2.',
   'A checked derivation of 1 + 1 = 2.', 'A checked countermodel.',
   'No admitted checker result.', NULL, 'macsad.math-problem', 1,
   '{"formal_statement":"1 + 1 = 2","seed":7}',
   pg_temp.digest('problem prior math v1', 'sha256'),
   '11000000-0000-4000-8000-000000000001', '2026-01-15T12:01:08Z'),
  ('17000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   'mathematics', '17000000-0000-4000-8000-000000000001',
   'Finite sum identity', 'Prove that one plus one equals two.',
   'Natural numbers with successor.', 'Peano arithmetic.', 'Integers from 0 through 2.',
   'A checker-attested derivation of 1 + 1 = 2.', 'A checked countermodel.',
   'Checker or semantic review remains unresolved.', 'Clarified the formal vocabulary.',
   'macsad.math-problem', 1, '{"formal_statement":"S(0) + S(0) = S(S(0))","seed":7}',
   pg_temp.digest('problem current math v1', 'sha256'),
   '11000000-0000-4000-8000-000000000001', '2026-01-15T12:01:09Z'),
  ('17000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   'computer_science', NULL, 'Bounded sort replay',
   'Does insertion sort reproduce the frozen output for seed 7?',
   'Integer arrays and stable order.', 'The fixture runtime is deterministic.',
   'Arrays of length at most 8.', 'Exact replay of the frozen output.',
   'A mismatching replay.', 'Resource exhaustion or ambiguous output.', NULL,
   'macsad.cs-problem', 1,
   '{"algorithm":"insertion_sort","maximum_length":8,"seed":7,"stopping_rule":"one replay"}',
   pg_temp.digest('problem cs v1', 'sha256'),
   '11000000-0000-4000-8000-000000000001', '2026-01-15T12:01:10Z');

INSERT INTO macsad.research_case (
  id, workspace_id, workspace_snapshot_id, policy_revision_id,
  problem_revision_id, process_key, tool_closure_digest, supersedes_case_id,
  state, control_state, priority, disposition_family, math_disposition,
  cs_disposition, administrative_disposition, disposition_attestation_id,
  editorial_decision, eligibility_attestation_id, opened_at, closed_at,
  version, created_at, updated_at
) VALUES
  ('18000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '13000000-0000-4000-8000-000000000001', '15000000-0000-4000-8000-000000000002',
   '17000000-0000-4000-8000-000000000001', 'discovery',
   pg_temp.digest('fixture tool closure v1', 'sha256'), NULL,
   'open', 'blocked', 10, NULL, NULL, NULL, NULL, NULL,
   'not_reviewed', NULL, '2026-01-15T12:01:11Z', NULL, 0,
   '2026-01-15T12:01:11Z', '2026-01-15T12:01:11Z'),
  ('18000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '13000000-0000-4000-8000-000000000001', '15000000-0000-4000-8000-000000000002',
   '17000000-0000-4000-8000-000000000002', 'discovery',
   pg_temp.digest('fixture tool closure v1', 'sha256'),
   '18000000-0000-4000-8000-000000000001',
   'open', 'normal', 80, NULL, NULL, NULL, NULL, NULL,
   'not_reviewed', NULL, '2026-01-15T12:01:12Z', NULL, 0,
   '2026-01-15T12:01:12Z', '2026-01-15T12:01:12Z'),
  ('18000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '13000000-0000-4000-8000-000000000001', '15000000-0000-4000-8000-000000000002',
   '17000000-0000-4000-8000-000000000003', 'discovery',
   pg_temp.digest('fixture tool closure v1', 'sha256'), NULL,
   'open', 'paused', 60, NULL, NULL, NULL, NULL, NULL,
   'not_reviewed', NULL, '2026-01-15T12:01:13Z', NULL, 0,
   '2026-01-15T12:01:13Z', '2026-01-15T12:01:13Z');

INSERT INTO macsad.research_case_tool_revision (
  id, workspace_id, research_case_id, tool_repository_id,
  tool_repository_revision_id, ordinal, access_mode, purpose, scope_schema_id,
  scope_schema_version, scope_body, scope_digest, pinned_by_actor_id, created_at
)
SELECT
  pin_id, '10000000-0000-4000-8000-000000000001', case_id,
  '14000000-0000-4000-8000-000000000001',
  '14100000-0000-4000-8000-000000000001', 0, 'operation_invoke',
  'Run the bounded fixture checker', 'macsad.tool-scope', 1,
  '{"maximum_invocations":2}',
  pg_temp.digest('{"maximum_invocations": 2}'::jsonb::text, 'sha256'),
  '11000000-0000-4000-8000-000000000001', '2026-01-15T12:01:14Z'
FROM (VALUES
  ('18100000-0000-4000-8000-000000000001'::uuid, '18000000-0000-4000-8000-000000000001'::uuid),
  ('18100000-0000-4000-8000-000000000002'::uuid, '18000000-0000-4000-8000-000000000002'::uuid),
  ('18100000-0000-4000-8000-000000000003'::uuid, '18000000-0000-4000-8000-000000000003'::uuid)
) AS pins(pin_id, case_id);

-- Two concurrent cases exercise a successful mathematics execution and a
-- controller-cancelled computer-science replay without relying on wall time.
INSERT INTO macsad.task (
  id, workspace_id, research_case_id, policy_revision_id, problem_revision_id,
  process_key, node_key, sequence_no, state, board_phase,
  required_profile_key, required_profile_digest, entered_via_policy_transition_id,
  input_closure_digest, output_closure_digest, deadline_at, opened_at,
  finished_at, version, created_at, updated_at
) VALUES
  ('19000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000002', '15000000-0000-4000-8000-000000000002',
   '17000000-0000-4000-8000-000000000002', 'discovery', 'investigate', 1,
   'offered', 'running', 'investigator',
   pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'), NULL,
   pg_temp.digest('math task input closure v1', 'sha256'),
   pg_temp.digest('math task output closure v1', 'sha256'),
   '2026-01-16T12:00:00Z', '2026-01-15T12:01:20Z', NULL, 0,
   '2026-01-15T12:01:20Z', '2026-01-15T12:01:20Z'),
  ('19000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000003', '15000000-0000-4000-8000-000000000002',
   '17000000-0000-4000-8000-000000000003', 'discovery', 'investigate', 1,
   'offered', 'running', 'investigator',
   pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'), NULL,
   pg_temp.digest('cs task input closure v1', 'sha256'),
   pg_temp.digest('cs task output closure v1', 'sha256'),
   '2026-01-16T12:30:00Z', '2026-01-15T12:01:21Z', NULL, 0,
   '2026-01-15T12:01:21Z', '2026-01-15T12:01:21Z');

INSERT INTO macsad.thread (
  id, workspace_id, research_case_id, task_id, kind, state, version,
  created_at, updated_at
) VALUES
  ('19200000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   NULL, NULL, 'workspace_operations', 'open', 0,
   '2026-01-15T12:01:22Z', '2026-01-15T12:01:22Z'),
  ('19200000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000002', NULL, 'case_primary', 'open', 0,
   '2026-01-15T12:01:23Z', '2026-01-15T12:01:23Z'),
  ('19200000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000002', '19000000-0000-4000-8000-000000000001',
   'task', 'open', 0, '2026-01-15T12:01:24Z', '2026-01-15T12:01:24Z'),
  ('19200000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000003', NULL, 'case_primary', 'open', 0,
   '2026-01-15T12:01:25Z', '2026-01-15T12:01:25Z'),
  ('19200000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000003', '19000000-0000-4000-8000-000000000003',
   'task', 'open', 0, '2026-01-15T12:01:26Z', '2026-01-15T12:01:26Z'),
  ('19200000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000001', NULL, 'case_primary', 'open', 0,
   '2026-01-15T12:01:27Z', '2026-01-15T12:01:27Z');

UPDATE macsad.thread
SET state = 'archived', version = 1
WHERE id = '19200000-0000-4000-8000-000000000001';

INSERT INTO macsad.message (
  id, workspace_id, thread_id, author_actor_id, task_id,
  reply_to_message_id, corrects_message_id, format, body, content_digest, created_at
) VALUES
  ('19300000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '19200000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000002',
   '19000000-0000-4000-8000-000000000001', NULL, NULL, 'markdown',
   E'Initial proof sketch\n\n- deterministic seed: `7`\n- symbol: λ',
   pg_temp.digest(E'Initial proof sketch\n\n- deterministic seed: `7`\n- symbol: λ', 'sha256'),
   '2026-01-15T12:01:28Z'),
  ('19300000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '19200000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000003',
   '19000000-0000-4000-8000-000000000001', '19300000-0000-4000-8000-000000000001',
   NULL, 'plain_text', 'Please make the successor step explicit.',
   pg_temp.digest('Please make the successor step explicit.', 'sha256'),
   '2026-01-15T12:01:29Z'),
  ('19300000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '19200000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000002',
   '19000000-0000-4000-8000-000000000001', '19300000-0000-4000-8000-000000000002',
   '19300000-0000-4000-8000-000000000001', 'markdown',
   'Correction: apply the successor axiom exactly once.',
   pg_temp.digest('Correction: apply the successor axiom exactly once.', 'sha256'),
   '2026-01-15T12:01:30Z'),
  ('19300000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001',
   '19200000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001',
   NULL, NULL, NULL, 'plain_text', 'Fixture restore drill scheduled.',
   pg_temp.digest('Fixture restore drill scheduled.', 'sha256'),
   '2026-01-15T12:01:31Z');

INSERT INTO macsad.message_mention (message_id, actor_id, created_at) VALUES
  ('19300000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000003',
   '2026-01-15T12:01:32Z'),
  ('19300000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000001',
   '2026-01-15T12:01:33Z');

INSERT INTO macsad.task_assignment (
  id, workspace_id, task_id, offered_actor_id, offered_membership_id,
  offered_by_actor_id, policy_revision_id, profile_key, profile_digest,
  prior_assignment_id, handoff_thread_id, package_digest, state, offered_at,
  accepted_at, rejected_at, expires_at, released_at, reason, version,
  created_at, updated_at
) VALUES
  ('19400000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '19000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002',
   '16000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'investigator',
   pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'), NULL,
   '19200000-0000-4000-8000-000000000002', pg_temp.digest('rejected offer package v1', 'sha256'),
   'offered', '2026-01-15T12:01:34Z', NULL, NULL, '2026-01-15T13:01:34Z', NULL,
   'Superseded by a corrected handoff package.', 0,
   '2026-01-15T12:01:34Z', '2026-01-15T12:01:34Z'),
  ('19400000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '19000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002',
   '16000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'investigator',
   pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'),
   '19400000-0000-4000-8000-000000000001', '19200000-0000-4000-8000-000000000003',
   pg_temp.digest('accepted offer package v1', 'sha256'), 'offered',
   '2026-01-15T12:01:35Z', NULL, NULL, '2026-01-15T14:01:35Z', NULL,
   'Corrected package accepted by the investigator.', 0,
   '2026-01-15T12:01:35Z', '2026-01-15T12:01:35Z'),
  ('19400000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '19000000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000002',
   '16000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', 'investigator',
   pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'), NULL,
   '19200000-0000-4000-8000-000000000005', pg_temp.digest('cs offer package v1', 'sha256'),
   'offered', '2026-01-15T12:01:36Z', NULL, NULL, '2026-01-15T14:01:36Z', NULL,
   'Bounded replay assignment.', 0, '2026-01-15T12:01:36Z', '2026-01-15T12:01:36Z');

UPDATE macsad.task_assignment
SET state = 'rejected', rejected_at = '2026-01-15T12:01:37Z', version = 1
WHERE id = '19400000-0000-4000-8000-000000000001';
UPDATE macsad.task_assignment
SET state = 'accepted', accepted_at = '2026-01-15T12:01:38Z', version = 1
WHERE id = '19400000-0000-4000-8000-000000000002';
UPDATE macsad.task_assignment
SET state = 'accepted', accepted_at = '2026-01-15T12:01:39Z', version = 1
WHERE id = '19400000-0000-4000-8000-000000000003';

UPDATE macsad.task SET state = 'ready', version = 1
WHERE id IN ('19000000-0000-4000-8000-000000000001', '19000000-0000-4000-8000-000000000003');
UPDATE macsad.task SET state = 'running', version = 2
WHERE id IN ('19000000-0000-4000-8000-000000000001', '19000000-0000-4000-8000-000000000003');

INSERT INTO macsad.execution (
  id, workspace_id, research_case_id, task_id, task_assignment_id,
  performing_actor_id, worker_actor_id, workspace_snapshot_id,
  policy_revision_id, problem_revision_id, profile_key, profile_digest,
  request_schema_id, request_schema_version, request_body, request_digest,
  environment_digest, resource_limit_schema_id, resource_limit_schema_version,
  resource_limit_body, resource_limit_digest, deterministic_seed,
  idempotency_key, state, lease_owner_actor_id, fencing_token, claimed_at,
  heartbeat_at, lease_expires_at, cancel_requested_at, cancel_reason,
  transport_outcome, termination_outcome, claim_outcome,
  result_envelope_digest, started_at, finished_at, version, created_at, updated_at
) VALUES
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000002', '19000000-0000-4000-8000-000000000001',
   '19400000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002',
   '11000000-0000-4000-8000-000000000004', '13000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', '17000000-0000-4000-8000-000000000002',
   'investigator', pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'),
   'macsad.execution-request', 1, '{"problem":"1+1=2","seed":7}',
   pg_temp.digest('{"problem": "1+1=2", "seed": 7}'::jsonb::text, 'sha256'),
   pg_temp.digest('fixture environment linux-amd64 v1', 'sha256'),
   'macsad.resource-limits', 1, '{"cpu_seconds":10,"memory_bytes":67108864}',
   pg_temp.digest('{"cpu_seconds": 10, "memory_bytes": 67108864}'::jsonb::text, 'sha256'),
   7, 'fixture:math-execution:1', 'pending', NULL, NULL, NULL, NULL, NULL,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0,
   '2026-01-15T12:01:40Z', '2026-01-15T12:01:40Z'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000003', '19000000-0000-4000-8000-000000000003',
   '19400000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000002',
   '11000000-0000-4000-8000-000000000004', '13000000-0000-4000-8000-000000000001',
   '15000000-0000-4000-8000-000000000002', '17000000-0000-4000-8000-000000000003',
   'investigator', pg_temp.digest('{"role": "investigator"}'::jsonb::text, 'sha256'),
   'macsad.execution-request', 1, '{"algorithm":"insertion_sort","seed":7}',
   pg_temp.digest('{"algorithm": "insertion_sort", "seed": 7}'::jsonb::text, 'sha256'),
   pg_temp.digest('fixture environment linux-amd64 v1', 'sha256'),
   'macsad.resource-limits', 1, '{"cpu_seconds":1,"memory_bytes":33554432}',
   pg_temp.digest('{"cpu_seconds": 1, "memory_bytes": 33554432}'::jsonb::text, 'sha256'),
   7, 'fixture:cs-execution:1', 'pending', NULL, NULL, NULL, NULL, NULL,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0,
   '2026-01-15T12:01:41Z', '2026-01-15T12:01:41Z');

UPDATE macsad.execution
SET state = 'leased', lease_owner_actor_id = '11000000-0000-4000-8000-000000000004',
    fencing_token = 1, claimed_at = '2026-01-15T12:01:42Z',
    heartbeat_at = '2026-01-15T12:01:42Z', lease_expires_at = '2026-01-15T12:06:42Z',
    version = 1
WHERE id IN ('20000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002');
UPDATE macsad.execution
SET state = 'running', started_at = '2026-01-15T12:01:43Z',
    heartbeat_at = '2026-01-15T12:01:44Z', version = 2
WHERE id IN ('20000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002');
UPDATE macsad.execution
SET state = 'cancel_requested', cancel_requested_at = '2026-01-15T12:01:45Z',
    cancel_reason = 'Fixture wall-time guard requested cancellation.',
    heartbeat_at = '2026-01-15T12:01:45Z', version = 3
WHERE id = '20000000-0000-4000-8000-000000000002';

INSERT INTO macsad.blob (
  digest, byte_length, media_type, content_encoding, compression,
  provider_checksum, storage_provider, storage_locator, storage_class,
  stored_at, verified_at, created_at
)
SELECT
  pg_temp.digest(body, 'sha256'),
  pg_catalog.octet_length(pg_catalog.convert_to(body, 'UTF8')),
  media_type, content_encoding, compression, provider_checksum, 'fixture_cas',
  'sha256/' || pg_catalog.encode(pg_temp.digest(body, 'sha256'), 'hex'),
  storage_class, stored_at, verified_at, created_at
FROM (VALUES
  ('math checker certificate v1', 'application/json', 'utf-8', 'none',
   'fixture:math-certificate', 'evidence', '2026-01-15T12:01:46Z'::timestamptz,
   '2026-01-15T12:01:47Z'::timestamptz, '2026-01-15T12:01:46Z'::timestamptz),
  ('cs cancellation diagnostic v1', 'text/plain', 'utf-8', 'none',
   'fixture:cs-diagnostic', 'diagnostic', '2026-01-15T12:01:48Z'::timestamptz,
   '2026-01-15T12:01:49Z'::timestamptz, '2026-01-15T12:01:48Z'::timestamptz),
  ('publication deployment response v1', 'application/json', 'utf-8', 'none',
   'fixture:deployment-response', 'publication', '2026-01-15T12:01:50Z'::timestamptz,
   '2026-01-15T12:01:51Z'::timestamptz, '2026-01-15T12:01:50Z'::timestamptz),
  ('model context v1', 'application/json', 'utf-8', 'none',
   'fixture:model-context', 'private', '2026-01-15T12:01:52Z'::timestamptz,
   '2026-01-15T12:01:53Z'::timestamptz, '2026-01-15T12:01:52Z'::timestamptz)
) AS fixture_blob(
  body, media_type, content_encoding, compression, provider_checksum,
  storage_class, stored_at, verified_at, created_at
);

INSERT INTO macsad.artifact (
  id, workspace_id, blob_digest, artifact_kind, schema_id, schema_version,
  classification, secret_scan_result, quarantined, producing_actor_id,
  producing_execution_id, original_source, observed_at, license_expression,
  attribution, redistribution_allowed, export_decision, created_at
) VALUES
  ('20200000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   pg_temp.digest('math checker certificate v1', 'sha256'), 'checker_certificate',
   'macsad.checker-certificate', 1, 'public_candidate', 'passed', false,
   '11000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001',
   'execution://20000000-0000-4000-8000-000000000001/certificate',
   '2026-01-15T12:01:54Z', 'CC0-1.0', 'MaCSad deterministic checker fixture', true,
   'allowed-by-fixture-contract', '2026-01-15T12:01:54Z'),
  ('20200000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   pg_temp.digest('cs cancellation diagnostic v1', 'sha256'), 'execution_diagnostic',
   'macsad.execution-diagnostic', 1, 'internal', 'passed', false,
   '11000000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-000000000002',
   'execution://20000000-0000-4000-8000-000000000002/diagnostic',
   '2026-01-15T12:01:55Z', 'LicenseRef-MaCSad-Internal',
   'MaCSad cancellation controller', false, 'retained-internally',
   '2026-01-15T12:01:55Z'),
  ('20200000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   pg_temp.digest('publication deployment response v1', 'sha256'), 'deployment_response',
   'macsad.deployment-response', 1, 'public_candidate', 'passed', false,
   '11000000-0000-4000-8000-000000000005', '20000000-0000-4000-8000-000000000001',
   'deployment://fixture/pages/1', '2026-01-15T12:01:56Z', 'CC0-1.0',
   'MaCSad publication fixture', true, 'allowed-by-fixture-contract',
   '2026-01-15T12:01:56Z'),
  ('20200000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001',
   pg_temp.digest('model context v1', 'sha256'), 'model_context',
   'macsad.model-context', 1, 'private', 'passed', false,
   '11000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001',
   'execution://20000000-0000-4000-8000-000000000001/context',
   '2026-01-15T12:01:57Z', 'LicenseRef-MaCSad-Private',
   'MaCSad private fixture', false, 'excluded-private', '2026-01-15T12:01:57Z');

INSERT INTO macsad.execution_artifact (
  workspace_id, execution_id, artifact_id, role, ordinal, created_at
) VALUES
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
   '12000000-0000-4000-8000-000000000006', 'input', 0, '2026-01-15T12:01:58Z'),
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
   '20200000-0000-4000-8000-000000000001', 'certificate', 0, '2026-01-15T12:01:59Z'),
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
   '20200000-0000-4000-8000-000000000004', 'environment_manifest', 0,
   '2026-01-15T12:02:00Z'),
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002',
   '20200000-0000-4000-8000-000000000002', 'diagnostic', 0, '2026-01-15T12:02:01Z');

INSERT INTO macsad.execution_tool_use (
  id, workspace_id, research_case_id, execution_id,
  policy_node_tool_operation_id, tool_repository_revision_id,
  tool_operation_manifest_id, invocation_sequence, request_artifact_id,
  response_artifact_id, request_digest, response_digest, state,
  transport_outcome, termination_outcome, started_at, finished_at,
  version, created_at, updated_at
) VALUES
  ('20300000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001',
   '15500000-0000-4000-8000-000000000001', '14100000-0000-4000-8000-000000000001',
   '14200000-0000-4000-8000-000000000001', 1,
   '12000000-0000-4000-8000-000000000006', NULL,
   pg_temp.digest('math prompt\nwith unicode λ', 'sha256'), NULL, 'pending',
   NULL, NULL, NULL, NULL, 0, '2026-01-15T12:02:02Z', '2026-01-15T12:02:02Z'),
  ('20300000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000002',
   '15500000-0000-4000-8000-000000000001', '14100000-0000-4000-8000-000000000001',
   '14200000-0000-4000-8000-000000000001', 1,
   '12000000-0000-4000-8000-000000000006', NULL,
   pg_temp.digest('cs bounded replay request v1', 'sha256'), NULL, 'pending',
   NULL, NULL, NULL, NULL, 0, '2026-01-15T12:02:03Z', '2026-01-15T12:02:03Z');

UPDATE macsad.execution_tool_use
SET state = 'running', started_at = '2026-01-15T12:02:04Z', version = 1
WHERE id IN ('20300000-0000-4000-8000-000000000001', '20300000-0000-4000-8000-000000000002');
UPDATE macsad.execution_tool_use
SET state = 'completed', response_artifact_id = '20200000-0000-4000-8000-000000000001',
    response_digest = pg_temp.digest('math checker certificate v1', 'sha256'),
    transport_outcome = 'accepted', termination_outcome = 'clean_exit',
    finished_at = '2026-01-15T12:02:05Z', version = 2
WHERE id = '20300000-0000-4000-8000-000000000001';
UPDATE macsad.execution_tool_use
SET state = 'cancelled', response_artifact_id = '20200000-0000-4000-8000-000000000002',
    response_digest = pg_temp.digest('cs cancellation diagnostic v1', 'sha256'),
    transport_outcome = 'accepted', termination_outcome = 'cancelled',
    finished_at = '2026-01-15T12:02:06Z', version = 2
WHERE id = '20300000-0000-4000-8000-000000000002';

INSERT INTO macsad.budget_account (
  id, workspace_id, research_case_id, resource_kind, unit_code, currency_code,
  period_start, period_end, initial_spending_limit, spending_limit,
  reserved_quantity, spent_quantity, version, created_at, updated_at
) VALUES (
  '22000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '18000000-0000-4000-8000-000000000002', 'currency', 'USD', 'USD',
  '2025-01-01T00:00:00Z', '2030-01-01T00:00:00Z',
  10.000000000000, 10.000000000000, 0.000000000000, 0.000000000000, 0,
  '2026-01-15T12:02:07Z', '2026-01-15T12:02:07Z'
);

INSERT INTO macsad.model_call (
  id, workspace_id, research_case_id, task_id, execution_id,
  execution_tool_use_id, requested_by_actor_id, controller_actor_id,
  budget_account_id, idempotency_key, provider_service, requested_model,
  resolved_model, resolved_provider, service_tier, router_strategy, data_region,
  byok, estimated_cost, reserved_cost, cost_currency, price_snapshot_digest,
  routing_policy_digest, max_output_tokens, stream_requested,
  credential_reference, credential_epoch, prompt_artifact_id,
  context_artifact_id, prompt_digest, context_digest, parameters_digest,
  openrouter_request_id, openrouter_generation_id, upstream_id,
  request_schema_id, request_schema_version, sanitized_request, request_digest,
  response_artifact_id, state, http_status, error_code, submitted_at,
  response_completed_at, usage_reconciled_at, version, created_at, updated_at
) VALUES (
  '22100000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '18000000-0000-4000-8000-000000000002', '19000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', '20300000-0000-4000-8000-000000000001',
  '11000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000005',
  '22000000-0000-4000-8000-000000000001', 'fixture:model-call:1', 'openrouter',
  'openai/gpt-5-fixture', NULL, NULL, 'standard', 'price_then_latency', 'us-west', true,
  0.800000000000, 1.000000000000, 'USD',
  pg_temp.digest('fixture price snapshot v1', 'sha256'),
  pg_temp.digest('fixture routing policy v1', 'sha256'), 512, true,
  'secretref://fixture/openrouter/byok', 3,
  '12000000-0000-4000-8000-000000000006', '20200000-0000-4000-8000-000000000004',
  pg_temp.digest('math prompt\nwith unicode λ', 'sha256'),
  pg_temp.digest('model context v1', 'sha256'),
  pg_temp.digest('{"max_output_tokens": 512, "temperature": 0}'::jsonb::text, 'sha256'),
  NULL, NULL, NULL, 'macsad.model-request', 1,
  '{"messages":[{"content":"fixture prompt","role":"user"}],"temperature":0}',
  pg_temp.digest('fixture sanitized model request v1', 'sha256'), NULL, 'reserved',
  NULL, NULL, NULL, NULL, NULL, 0,
  '2026-01-15T12:02:08Z', '2026-01-15T12:02:08Z'
);

SELECT macsad.record_budget_entry(
  p_budget_account_id := '22000000-0000-4000-8000-000000000001',
  p_kind := 'limit_adjustment', p_quantity := 2.000000000000,
  p_idempotency_key := 'fixture:budget:limit:1',
  p_request_digest := pg_temp.digest('fixture budget limit adjustment v1', 'sha256'),
  p_actor_id := '11000000-0000-4000-8000-000000000001',
  p_reason := 'Increase the deterministic fixture drill allowance.'
);
SELECT macsad.record_budget_entry(
  p_budget_account_id := '22000000-0000-4000-8000-000000000001',
  p_kind := 'reserve', p_quantity := 1.000000000000,
  p_idempotency_key := 'fixture:budget:model-reserve:1',
  p_request_digest := pg_temp.digest('fixture model reservation v1', 'sha256'),
  p_actor_id := '11000000-0000-4000-8000-000000000005',
  p_execution_id := '20000000-0000-4000-8000-000000000001',
  p_model_call_id := '22100000-0000-4000-8000-000000000001',
  p_reason := 'Reserve the bounded fixture model-call estimate.'
);

UPDATE macsad.model_call
SET state = 'submitted', resolved_model = 'openai/gpt-5-fixture-2026-01-15',
    resolved_provider = 'openai', openrouter_request_id = 'or-request-fixture-1',
    upstream_id = 'upstream-fixture-1', submitted_at = '2026-01-15T12:02:09Z',
    version = 1
WHERE id = '22100000-0000-4000-8000-000000000001';
UPDATE macsad.model_call
SET state = 'usage_pending', openrouter_generation_id = 'or-generation-fixture-1',
    response_artifact_id = '20200000-0000-4000-8000-000000000001',
    http_status = 200, response_completed_at = '2026-01-15T12:02:10Z', version = 2
WHERE id = '22100000-0000-4000-8000-000000000001';

INSERT INTO macsad.model_usage_observation (
  id, workspace_id, model_call_id, observation_sequence,
  supersedes_observation_id, source, is_final, openrouter_generation_id,
  resolved_model, resolved_provider, prompt_tokens, completion_tokens,
  total_tokens, reasoning_tokens, cache_read_tokens, cache_write_tokens,
  audio_input_tokens, audio_output_tokens, image_count, media_count,
  web_search_count, billed_amount, billed_currency, billed_credits,
  upstream_cost_amount, upstream_cost_currency, usage_schema_id,
  usage_schema_version, sanitized_usage, usage_digest, observed_at, created_at
) VALUES
  ('22200000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '22100000-0000-4000-8000-000000000001', 1, NULL, 'final_sse', true,
   'or-generation-fixture-1', 'openai/gpt-5-fixture-2026-01-15', 'openai',
   120, 30, 150, 12, 24, 4, 0, 0, 1, 1, 2,
   0.800000000000, 'USD', 0.800000000000, 0.600000000000, 'USD',
   'macsad.openrouter-usage', 1,
   '{"completion_tokens":30,"prompt_tokens":120,"total_tokens":150}',
   pg_temp.digest('fixture usage observation v1', 'sha256'),
   '2026-01-15T12:02:11Z', '2026-01-15T12:02:12Z');

DO $settle_first_usage$
DECLARE
  reservation_id uuid;
BEGIN
  SELECT id INTO STRICT reservation_id
  FROM macsad.budget_entry
  WHERE budget_account_id = '22000000-0000-4000-8000-000000000001'
    AND idempotency_key = 'fixture:budget:model-reserve:1';

  PERFORM macsad.record_budget_entry(
    p_budget_account_id := '22000000-0000-4000-8000-000000000001',
    p_kind := 'commit', p_quantity := 0.800000000000,
    p_idempotency_key := 'fixture:budget:model-commit:1',
    p_request_digest := pg_temp.digest('fixture model commit v1', 'sha256'),
    p_actor_id := '11000000-0000-4000-8000-000000000005',
    p_execution_id := '20000000-0000-4000-8000-000000000001',
    p_model_call_id := '22100000-0000-4000-8000-000000000001',
    p_model_usage_observation_id := '22200000-0000-4000-8000-000000000001',
    p_related_reservation_entry_id := reservation_id,
    p_reason := 'Commit the first final provider usage observation.'
  );
END
$settle_first_usage$;

UPDATE macsad.model_call
SET state = 'reconciled', usage_reconciled_at = '2026-01-15T12:02:13Z', version = 3
WHERE id = '22100000-0000-4000-8000-000000000001';
UPDATE macsad.model_call
SET state = 'usage_pending', usage_reconciled_at = NULL, version = 4
WHERE id = '22100000-0000-4000-8000-000000000001';

INSERT INTO macsad.model_usage_observation (
  id, workspace_id, model_call_id, observation_sequence,
  supersedes_observation_id, source, is_final, openrouter_generation_id,
  resolved_model, resolved_provider, prompt_tokens, completion_tokens,
  total_tokens, reasoning_tokens, cache_read_tokens, cache_write_tokens,
  audio_input_tokens, audio_output_tokens, image_count, media_count,
  web_search_count, billed_amount, billed_currency, billed_credits,
  upstream_cost_amount, upstream_cost_currency, usage_schema_id,
  usage_schema_version, sanitized_usage, usage_digest, observed_at, created_at
) VALUES
  ('22200000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '22100000-0000-4000-8000-000000000001', 2,
   '22200000-0000-4000-8000-000000000001', 'generation_reconcile', true,
   'or-generation-fixture-1', 'openai/gpt-5-fixture-2026-01-15', 'openai',
   120, 30, 150, 12, 24, 4, 0, 0, 1, 1, 2,
   0.900000000000, 'USD', 0.900000000000, 0.700000000000, 'USD',
   'macsad.openrouter-usage', 1,
   '{"billed_amount":"0.900000000000","correction":true,"total_tokens":150}',
   pg_temp.digest('fixture usage observation v2', 'sha256'),
   '2026-01-15T12:02:14Z', '2026-01-15T12:02:15Z');

SELECT macsad.record_budget_entry(
  p_budget_account_id := '22000000-0000-4000-8000-000000000001',
  p_kind := 'spend_adjustment', p_quantity := 0.100000000000,
  p_idempotency_key := 'fixture:budget:model-adjustment:1',
  p_request_digest := pg_temp.digest('fixture model adjustment v1', 'sha256'),
  p_actor_id := '11000000-0000-4000-8000-000000000005',
  p_execution_id := '20000000-0000-4000-8000-000000000001',
  p_model_call_id := '22100000-0000-4000-8000-000000000001',
  p_model_usage_observation_id := '22200000-0000-4000-8000-000000000002',
  p_reason := 'Apply the provider cost correction delta.'
);
UPDATE macsad.model_call
SET state = 'reconciled', usage_reconciled_at = '2026-01-15T12:02:16Z', version = 5
WHERE id = '22100000-0000-4000-8000-000000000001';
UPDATE macsad.model_call
SET state = 'usage_pending', usage_reconciled_at = NULL, version = 6
WHERE id = '22100000-0000-4000-8000-000000000001';

INSERT INTO macsad.model_usage_observation (
  id, workspace_id, model_call_id, observation_sequence,
  supersedes_observation_id, source, is_final, openrouter_generation_id,
  resolved_model, resolved_provider, prompt_tokens, completion_tokens,
  total_tokens, reasoning_tokens, cache_read_tokens, cache_write_tokens,
  audio_input_tokens, audio_output_tokens, image_count, media_count,
  web_search_count, billed_amount, billed_currency, billed_credits,
  upstream_cost_amount, upstream_cost_currency, usage_schema_id,
  usage_schema_version, sanitized_usage, usage_digest, observed_at, created_at
) VALUES
  ('22200000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '22100000-0000-4000-8000-000000000001', 3,
   '22200000-0000-4000-8000-000000000002', 'manual_reconciliation', true,
   'or-generation-fixture-1', 'openai/gpt-5-fixture-2026-01-15', 'openai',
   120, 30, 150, 12, 24, 4, 0, 0, 1, 1, 2,
   0.900000000000, 'USD', 0.900000000000, 0.700000000000, 'USD',
   'macsad.openrouter-usage', 1,
   '{"cost_equivalent":true,"manual_reconciliation":true,"total_tokens":150}',
   pg_temp.digest('fixture usage observation v3', 'sha256'),
   '2026-01-15T12:02:17Z', '2026-01-15T12:02:18Z');

SELECT macsad.record_budget_entry(
  p_budget_account_id := '22000000-0000-4000-8000-000000000001',
  p_kind := 'usage_reconciliation', p_quantity := 0.000000000000,
  p_idempotency_key := 'fixture:budget:model-reconciliation:1',
  p_request_digest := pg_temp.digest('fixture model zero delta reconciliation v1', 'sha256'),
  p_actor_id := '11000000-0000-4000-8000-000000000005',
  p_execution_id := '20000000-0000-4000-8000-000000000001',
  p_model_call_id := '22100000-0000-4000-8000-000000000001',
  p_model_usage_observation_id := '22200000-0000-4000-8000-000000000003',
  p_reason := 'Record a cost-equivalent metadata reconciliation.'
);
UPDATE macsad.model_call
SET state = 'reconciled', usage_reconciled_at = '2026-01-15T12:02:19Z', version = 7
WHERE id = '22100000-0000-4000-8000-000000000001';

DO $reserve_and_release$
DECLARE
  reservation_id uuid;
BEGIN
  reservation_id := macsad.record_budget_entry(
    p_budget_account_id := '22000000-0000-4000-8000-000000000001',
    p_kind := 'reserve', p_quantity := 0.250000000000,
    p_idempotency_key := 'fixture:budget:generic-reserve:1',
    p_request_digest := pg_temp.digest('fixture generic reservation v1', 'sha256'),
    p_actor_id := '11000000-0000-4000-8000-000000000005',
    p_execution_id := '20000000-0000-4000-8000-000000000001',
    p_reason := 'Reserve a bounded non-model worker operation.'
  );
  PERFORM macsad.record_budget_entry(
    p_budget_account_id := '22000000-0000-4000-8000-000000000001',
    p_kind := 'release', p_quantity := 0.250000000000,
    p_idempotency_key := 'fixture:budget:generic-release:1',
    p_request_digest := pg_temp.digest('fixture generic release v1', 'sha256'),
    p_actor_id := '11000000-0000-4000-8000-000000000005',
    p_execution_id := '20000000-0000-4000-8000-000000000001',
    p_related_reservation_entry_id := reservation_id,
    p_reason := 'Release the unused non-model worker reservation.'
  );
END
$reserve_and_release$;

UPDATE macsad.execution
SET state = 'completed', transport_outcome = 'accepted', termination_outcome = 'clean_exit',
    claim_outcome = 'supported', result_envelope_digest = pg_temp.digest('math result envelope v1', 'sha256'),
    heartbeat_at = '2026-01-15T12:02:20Z', finished_at = '2026-01-15T12:02:21Z', version = 3
WHERE id = '20000000-0000-4000-8000-000000000001';
UPDATE macsad.execution
SET state = 'failed', transport_outcome = 'accepted', termination_outcome = 'cancelled',
    claim_outcome = 'inconclusive', result_envelope_digest = pg_temp.digest('cs cancellation envelope v1', 'sha256'),
    heartbeat_at = '2026-01-15T12:02:20Z', finished_at = '2026-01-15T12:02:21Z', version = 4
WHERE id = '20000000-0000-4000-8000-000000000002';

UPDATE macsad.task
SET state = 'completed', finished_at = '2026-01-15T12:02:22Z', version = 3
WHERE id = '19000000-0000-4000-8000-000000000001';
UPDATE macsad.task
SET state = 'cancelled', finished_at = '2026-01-15T12:02:23Z', version = 3
WHERE id = '19000000-0000-4000-8000-000000000003';
UPDATE macsad.task_assignment
SET state = 'released', accepted_at = NULL, released_at = '2026-01-15T12:02:24Z',
    reason = 'Execution completed; release the accepted assignment.', version = 2
WHERE id = '19400000-0000-4000-8000-000000000002';

-- Authenticated ingress, command result, audit ordering, task movement, and
-- outbox publication are one explicit deterministic chain.
INSERT INTO macsad.command_receipt (
  id, workspace_id, actor_id, actor_identity_id, command_kind,
  idempotency_key, request_digest, correlation_id, causation_id, state,
  result_schema_id, result_schema_version, result_body, result_digest,
  lease_owner_actor_id, lease_expires_at, completed_at, version,
  created_at, updated_at
) VALUES
  ('23000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '11100000-0000-4000-8000-000000000001',
   'task.transition', 'fixture:command:transition:1',
   pg_temp.digest('fixture transition command request v1', 'sha256'),
   '23000000-0000-4000-8000-000000000101',
   '23000000-0000-4000-8000-000000000100', 'processing',
   NULL, NULL, NULL, NULL, '11000000-0000-4000-8000-000000000005',
   '2026-01-15T12:07:25Z', NULL, 0,
   '2026-01-15T12:02:25Z', '2026-01-15T12:02:25Z'),
  ('23000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '11100000-0000-4000-8000-000000000001',
   'publication.preview', 'fixture:command:rejected:1',
   pg_temp.digest('fixture rejected command request v1', 'sha256'),
   '23000000-0000-4000-8000-000000000102',
   '23000000-0000-4000-8000-000000000101', 'processing',
   NULL, NULL, NULL, NULL, '11000000-0000-4000-8000-000000000005',
   '2026-01-15T12:07:26Z', NULL, 0,
   '2026-01-15T12:02:26Z', '2026-01-15T12:02:26Z');

UPDATE macsad.command_receipt
SET state = 'completed', result_schema_id = 'macsad.command-result',
    result_schema_version = 1, result_body = '{"accepted":true,"task_count":3}',
    result_digest = pg_temp.digest('{"accepted": true, "task_count": 3}'::jsonb::text, 'sha256'),
    completed_at = '2026-01-15T12:02:27Z', version = 1
WHERE id = '23000000-0000-4000-8000-000000000001';
UPDATE macsad.command_receipt
SET state = 'rejected', result_schema_id = 'macsad.command-error',
    result_schema_version = 1, result_body = '{"error":"stale_preview"}',
    result_digest = pg_temp.digest('{"error": "stale_preview"}'::jsonb::text, 'sha256'),
    completed_at = '2026-01-15T12:02:28Z', version = 1
WHERE id = '23000000-0000-4000-8000-000000000002';

INSERT INTO macsad.inbound_delivery (
  id, workspace_id, provider, external_delivery_id, delivery_kind,
  payload_artifact_id, payload_digest, state, command_receipt_id,
  received_at, completed_at, version, created_at, updated_at
) VALUES
  ('23100000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   'github', 'fixture-delivery-0001', 'repository_dispatch',
   '12000000-0000-4000-8000-000000000008',
   pg_temp.digest('fixture inbound payload v1', 'sha256'), 'received',
   '23000000-0000-4000-8000-000000000001', '2026-01-15T12:02:29Z', NULL, 0,
   '2026-01-15T12:02:29Z', '2026-01-15T12:02:29Z'),
  ('23100000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   'github', 'fixture-delivery-0002', 'repository_dispatch',
   '12000000-0000-4000-8000-000000000008',
   pg_temp.digest('fixture malformed inbound payload v1', 'sha256'), 'received',
   '23000000-0000-4000-8000-000000000002', '2026-01-15T12:02:30Z', NULL, 0,
   '2026-01-15T12:02:30Z', '2026-01-15T12:02:30Z');

UPDATE macsad.inbound_delivery
SET state = 'processing', version = 1
WHERE id = '23100000-0000-4000-8000-000000000001';
UPDATE macsad.inbound_delivery
SET state = 'completed', completed_at = '2026-01-15T12:02:31Z', version = 2
WHERE id = '23100000-0000-4000-8000-000000000001';
UPDATE macsad.inbound_delivery
SET state = 'dead_letter', completed_at = '2026-01-15T12:02:32Z', version = 1
WHERE id = '23100000-0000-4000-8000-000000000002';

INSERT INTO macsad.domain_event (
  id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
  aggregate_version, event_kind, command_receipt_id, inbound_delivery_id,
  actor_id, correlation_id, causation_id, payload_schema_id,
  payload_schema_version, payload_body, payload_digest, previous_event_hash,
  event_hash, occurred_at, recorded_at
) VALUES (
  '23200000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  1, 'command_receipt', '23000000-0000-4000-8000-000000000001', 1,
  'command.completed', '23000000-0000-4000-8000-000000000001',
  '23100000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001',
  '23000000-0000-4000-8000-000000000101', '23000000-0000-4000-8000-000000000100',
  'macsad.command-event', 1, '{"state":"completed"}',
  pg_temp.digest('{"state": "completed"}'::jsonb::text, 'sha256'), NULL,
  pg_temp.digest('fixture event hash 1', 'sha256'), '2026-01-15T12:02:33Z',
  '2026-01-15T12:02:33Z'
);

INSERT INTO macsad.domain_event (
  id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
  aggregate_version, event_kind, command_receipt_id, inbound_delivery_id,
  actor_id, correlation_id, causation_id, payload_schema_id,
  payload_schema_version, payload_body, payload_digest, previous_event_hash,
  event_hash, occurred_at, recorded_at
) VALUES (
  '23200000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
  2, 'task', '19000000-0000-4000-8000-000000000001', 1, 'task.readied',
  '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
  '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
  '23200000-0000-4000-8000-000000000001', 'macsad.task-state-event', 1,
  '{"state":"ready"}', pg_temp.digest('{"state": "ready"}'::jsonb::text, 'sha256'),
  pg_temp.digest('fixture event hash 1', 'sha256'), pg_temp.digest('fixture event hash 2', 'sha256'),
  '2026-01-15T12:02:34Z', '2026-01-15T12:02:34Z'
);

INSERT INTO macsad.domain_event (
  id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
  aggregate_version, event_kind, command_receipt_id, inbound_delivery_id,
  actor_id, correlation_id, causation_id, payload_schema_id,
  payload_schema_version, payload_body, payload_digest, previous_event_hash,
  event_hash, occurred_at, recorded_at
) VALUES (
  '23200000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
  3, 'task', '19000000-0000-4000-8000-000000000001', 2, 'task.started',
  '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
  '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
  '23200000-0000-4000-8000-000000000002', 'macsad.task-state-event', 1,
  '{"state":"running"}', pg_temp.digest('{"state": "running"}'::jsonb::text, 'sha256'),
  pg_temp.digest('fixture event hash 2', 'sha256'), pg_temp.digest('fixture event hash 3', 'sha256'),
  '2026-01-15T12:02:35Z', '2026-01-15T12:02:35Z'
);

INSERT INTO macsad.domain_event (
  id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
  aggregate_version, event_kind, command_receipt_id, inbound_delivery_id,
  actor_id, correlation_id, causation_id, payload_schema_id,
  payload_schema_version, payload_body, payload_digest, previous_event_hash,
  event_hash, occurred_at, recorded_at
) VALUES (
  '23200000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001',
  4, 'task', '19000000-0000-4000-8000-000000000001', 3, 'task.transitioned',
  '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
  '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
  '23200000-0000-4000-8000-000000000003', 'macsad.task-transition-event', 1,
  '{"decision_code":"candidate_ready","policy_transition_id":"15400000-0000-4000-8000-000000000001","task_transition_id":"19100000-0000-4000-8000-000000000001"}',
  pg_temp.digest('fixture task transition payload 1', 'sha256'),
  pg_temp.digest('fixture event hash 3', 'sha256'), pg_temp.digest('fixture event hash 4', 'sha256'),
  '2026-01-15T12:02:36Z', '2026-01-15T12:02:36Z'
);

INSERT INTO macsad.task (
  id, workspace_id, research_case_id, policy_revision_id, problem_revision_id,
  process_key, node_key, sequence_no, state, board_phase,
  required_profile_key, required_profile_digest, entered_via_policy_transition_id,
  input_closure_digest, output_closure_digest, deadline_at, opened_at,
  finished_at, version, created_at, updated_at
) VALUES (
  '19000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
  '18000000-0000-4000-8000-000000000002', '15000000-0000-4000-8000-000000000002',
  '17000000-0000-4000-8000-000000000002', 'discovery', 'verify', 2,
  'offered', 'verify', 'verifier',
  pg_temp.digest('{"role": "verifier"}'::jsonb::text, 'sha256'),
  '15400000-0000-4000-8000-000000000001',
  pg_temp.digest('verify task input closure v1', 'sha256'),
  pg_temp.digest('verify task output closure v1', 'sha256'),
  '2026-01-16T13:00:00Z', '2026-01-15T12:02:37Z', NULL, 0,
  '2026-01-15T12:02:37Z', '2026-01-15T12:02:37Z'
);

INSERT INTO macsad.task_transition (
  id, workspace_id, research_case_id, policy_revision_id, process_key,
  from_task_id, to_task_id, policy_transition_id, decided_by_actor_id,
  fact_schema_id, fact_schema_version, fact_snapshot, fact_snapshot_digest,
  decision_code, matched_order, created_at, domain_event_id
) VALUES (
  '19100000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '18000000-0000-4000-8000-000000000002', '15000000-0000-4000-8000-000000000002',
  'discovery', '19000000-0000-4000-8000-000000000001',
  '19000000-0000-4000-8000-000000000002', '15400000-0000-4000-8000-000000000001',
  '11000000-0000-4000-8000-000000000001', 'macsad.transition-facts', 1,
  '{"claim_outcome":"supported","result":"accepted"}',
  pg_temp.digest('{"claim_outcome": "supported", "result": "accepted"}'::jsonb::text, 'sha256'),
  'candidate_ready', 0, '2026-01-15T12:02:38Z',
  '23200000-0000-4000-8000-000000000004'
);

INSERT INTO macsad.thread (
  id, workspace_id, research_case_id, task_id, kind, state, version,
  created_at, updated_at
) VALUES (
  '19200000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001',
  '18000000-0000-4000-8000-000000000002', '19000000-0000-4000-8000-000000000002',
  'task', 'open', 0, '2026-01-15T12:02:39Z', '2026-01-15T12:02:39Z'
);

INSERT INTO macsad.task_assignment (
  id, workspace_id, task_id, offered_actor_id, offered_membership_id,
  offered_by_actor_id, policy_revision_id, profile_key, profile_digest,
  prior_assignment_id, handoff_thread_id, package_digest, state, offered_at,
  accepted_at, rejected_at, expires_at, released_at, reason, version,
  created_at, updated_at
) VALUES (
  '19400000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001',
  '19000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000003',
  '16000000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000001',
  '15000000-0000-4000-8000-000000000002', 'verifier',
  pg_temp.digest('{"role": "verifier"}'::jsonb::text, 'sha256'), NULL,
  '19200000-0000-4000-8000-000000000007', pg_temp.digest('verify offer package v1', 'sha256'),
  'offered', '2026-01-15T12:02:40Z', NULL, NULL, '2026-01-15T14:02:40Z', NULL,
  'Independent verification handoff.', 0,
  '2026-01-15T12:02:40Z', '2026-01-15T12:02:40Z'
);
UPDATE macsad.task_assignment
SET state = 'accepted', accepted_at = '2026-01-15T12:02:41Z', version = 1
WHERE id = '19400000-0000-4000-8000-000000000004';
UPDATE macsad.task SET state = 'ready', version = 1
WHERE id = '19000000-0000-4000-8000-000000000002';
UPDATE macsad.task SET state = 'running', version = 2
WHERE id = '19000000-0000-4000-8000-000000000002';
UPDATE macsad.task
SET state = 'completed', finished_at = '2026-01-15T12:02:42Z', version = 3
WHERE id = '19000000-0000-4000-8000-000000000002';

INSERT INTO macsad.domain_event (
  id, workspace_id, workspace_sequence_no, aggregate_kind, aggregate_id,
  aggregate_version, event_kind, command_receipt_id, inbound_delivery_id,
  actor_id, correlation_id, causation_id, payload_schema_id,
  payload_schema_version, payload_body, payload_digest, previous_event_hash,
  event_hash, occurred_at, recorded_at
) VALUES
  ('23200000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001',
   5, 'task', '19000000-0000-4000-8000-000000000002', 1, 'task.readied',
   '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
   '23200000-0000-4000-8000-000000000004', 'macsad.task-state-event', 1,
   '{"state":"ready"}', pg_temp.digest('fixture task two ready payload', 'sha256'),
   pg_temp.digest('fixture event hash 4', 'sha256'), pg_temp.digest('fixture event hash 5', 'sha256'),
   '2026-01-15T12:02:43Z', '2026-01-15T12:02:43Z'),
  ('23200000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001',
   6, 'task', '19000000-0000-4000-8000-000000000002', 2, 'task.started',
   '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
   '23200000-0000-4000-8000-000000000005', 'macsad.task-state-event', 1,
   '{"state":"running"}', pg_temp.digest('fixture task two running payload', 'sha256'),
   pg_temp.digest('fixture event hash 5', 'sha256'), pg_temp.digest('fixture event hash 6', 'sha256'),
   '2026-01-15T12:02:44Z', '2026-01-15T12:02:44Z'),
  ('23200000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001',
   7, 'task', '19000000-0000-4000-8000-000000000002', 3, 'task.transitioned',
   '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
   '23200000-0000-4000-8000-000000000006', 'macsad.task-transition-event', 1,
   '{"decision_code":"review_complete","policy_transition_id":"15400000-0000-4000-8000-000000000002","task_transition_id":"19100000-0000-4000-8000-000000000002"}',
   pg_temp.digest('fixture task transition payload 2', 'sha256'),
   pg_temp.digest('fixture event hash 6', 'sha256'), pg_temp.digest('fixture event hash 7', 'sha256'),
   '2026-01-15T12:02:45Z', '2026-01-15T12:02:45Z'),
  ('23200000-0000-4000-8000-000000000008', '10000000-0000-4000-8000-000000000001',
   8, 'task', '19000000-0000-4000-8000-000000000003', 1, 'task.readied',
   '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
   '23200000-0000-4000-8000-000000000007', 'macsad.task-state-event', 1,
   '{"state":"ready"}', pg_temp.digest('fixture cs task ready payload', 'sha256'),
   pg_temp.digest('fixture event hash 7', 'sha256'), pg_temp.digest('fixture event hash 8', 'sha256'),
   '2026-01-15T12:02:46Z', '2026-01-15T12:02:46Z'),
  ('23200000-0000-4000-8000-000000000009', '10000000-0000-4000-8000-000000000001',
   9, 'task', '19000000-0000-4000-8000-000000000003', 2, 'task.started',
   '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
   '23200000-0000-4000-8000-000000000008', 'macsad.task-state-event', 1,
   '{"state":"running"}', pg_temp.digest('fixture cs task running payload', 'sha256'),
   pg_temp.digest('fixture event hash 8', 'sha256'), pg_temp.digest('fixture event hash 9', 'sha256'),
   '2026-01-15T12:02:47Z', '2026-01-15T12:02:47Z'),
  ('23200000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000001',
   10, 'task', '19000000-0000-4000-8000-000000000003', 3, 'task.transitioned',
   '23000000-0000-4000-8000-000000000001', '23100000-0000-4000-8000-000000000001',
   '11000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000101',
   '23200000-0000-4000-8000-000000000009', 'macsad.task-transition-event', 1,
   '{"decision_code":"cancelled_by_controller","policy_transition_id":"15400000-0000-4000-8000-000000000003","task_transition_id":"19100000-0000-4000-8000-000000000003"}',
   pg_temp.digest('fixture task transition payload 3', 'sha256'),
   pg_temp.digest('fixture event hash 9', 'sha256'), pg_temp.digest('fixture event hash 10', 'sha256'),
   '2026-01-15T12:02:48Z', '2026-01-15T12:02:48Z');

INSERT INTO macsad.task_transition (
  id, workspace_id, research_case_id, policy_revision_id, process_key,
  from_task_id, to_task_id, policy_transition_id, decided_by_actor_id,
  fact_schema_id, fact_schema_version, fact_snapshot, fact_snapshot_digest,
  decision_code, matched_order, created_at, domain_event_id
) VALUES
  ('19100000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000002', '15000000-0000-4000-8000-000000000002',
   'discovery', '19000000-0000-4000-8000-000000000002', NULL,
   '15400000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000001',
   'macsad.transition-facts', 1, '{"review":"complete"}',
   pg_temp.digest('{"review": "complete"}'::jsonb::text, 'sha256'),
   'review_complete', 0, '2026-01-15T12:02:49Z', '23200000-0000-4000-8000-000000000007'),
  ('19100000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '18000000-0000-4000-8000-000000000003', '15000000-0000-4000-8000-000000000002',
   'discovery', '19000000-0000-4000-8000-000000000003', NULL,
   '15400000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000001',
   'macsad.transition-facts', 1, '{"cancel_requested":true,"reason":"wall_time_guard"}',
   pg_temp.digest('{"cancel_requested": true, "reason": "wall_time_guard"}'::jsonb::text, 'sha256'),
   'cancelled_by_controller', 1, '2026-01-15T12:02:50Z',
   '23200000-0000-4000-8000-000000000010');

INSERT INTO macsad.outbox_message (
  id, workspace_id, domain_event_id, topic, message_key,
  payload_schema_id, payload_schema_version, payload_body, payload_digest,
  state, attempt_count, next_attempt_at, lease_owner_actor_id,
  lease_expires_at, delivered_at, last_error_code, version,
  created_at, updated_at
) VALUES
  ('23300000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '23200000-0000-4000-8000-000000000001', 'macsad.audit.command',
   'command:23000000-0000-4000-8000-000000000001', 'macsad.outbox-event', 1,
   '{"event_id":"23200000-0000-4000-8000-000000000001"}',
   pg_temp.digest('fixture outbox payload 1', 'sha256'), 'pending', 0,
   '2026-01-15T12:02:51Z', NULL, NULL, NULL, NULL, 0,
   '2026-01-15T12:02:51Z', '2026-01-15T12:02:51Z'),
  ('23300000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '23200000-0000-4000-8000-000000000002', 'macsad.audit.task',
   'task:19000000-0000-4000-8000-000000000001', 'macsad.outbox-event', 1,
   '{"event_id":"23200000-0000-4000-8000-000000000002"}',
   pg_temp.digest('fixture outbox payload 2', 'sha256'), 'pending', 0,
   '2026-01-15T12:02:52Z', NULL, NULL, NULL, NULL, 0,
   '2026-01-15T12:02:52Z', '2026-01-15T12:02:52Z'),
  ('23300000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '23200000-0000-4000-8000-000000000003', 'macsad.audit.task',
   'task:19000000-0000-4000-8000-000000000001', 'macsad.outbox-event', 1,
   '{"event_id":"23200000-0000-4000-8000-000000000003"}',
   pg_temp.digest('fixture outbox payload 3', 'sha256'), 'pending', 0,
   '2026-01-15T12:02:53Z', NULL, NULL, NULL, NULL, 0,
   '2026-01-15T12:02:53Z', '2026-01-15T12:02:53Z');

UPDATE macsad.outbox_message
SET state = 'publishing', attempt_count = 1,
    lease_owner_actor_id = '11000000-0000-4000-8000-000000000005',
    lease_expires_at = '2026-01-15T12:07:54Z', version = 1
WHERE id IN ('23300000-0000-4000-8000-000000000001', '23300000-0000-4000-8000-000000000002');
UPDATE macsad.outbox_message
SET state = 'delivered', lease_owner_actor_id = NULL, lease_expires_at = NULL,
    delivered_at = '2026-01-15T12:02:55Z', version = 2
WHERE id = '23300000-0000-4000-8000-000000000001';
UPDATE macsad.outbox_message
SET state = 'publishing', attempt_count = 2, next_attempt_at = '2026-01-15T12:07:56Z',
    last_error_code = 'fixture_transient_error', version = 2
WHERE id = '23300000-0000-4000-8000-000000000002';
UPDATE macsad.outbox_message
SET state = 'dead_letter', attempt_count = 1,
    last_error_code = 'fixture_permanent_error', version = 1
WHERE id = '23300000-0000-4000-8000-000000000003';

INSERT INTO macsad.claim (
  id, workspace_id, problem_revision_id, kind, canonical_text,
  payload_schema_id, payload_schema_version, payload_body, scope_bounds,
  content_digest, proposed_by_actor_id, source_execution_id, created_at
) VALUES
  ('21000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000002', 'formal_proposition',
   'Within Peano arithmetic, one plus one equals two.', 'macsad.formal-claim', 1,
   '{"conclusion":"S(0) + S(0) = S(S(0))","language":"fixture-peano"}',
   'Peano arithmetic with the frozen fixture definitions.',
   pg_temp.digest('fixture math claim v1', 'sha256'),
   '11000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001',
   '2026-01-15T12:03:00Z'),
  ('21000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000003', 'bounded_observation',
   'The frozen insertion-sort replay was cancelled before a conclusive output.',
   'macsad.bounded-observation', 1,
   '{"cancelled":true,"maximum_length":8,"seed":7}',
   'One frozen replay, arrays of length at most eight.',
   pg_temp.digest('fixture cs claim v1', 'sha256'),
   '11000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002',
   '2026-01-15T12:03:01Z');

INSERT INTO macsad.attestation (
  id, workspace_id, problem_revision_id, claim_id, execution_id,
  issuer_actor_id, issuer_membership_id, issuer_profile_key,
  issuer_profile_digest, kind, authority_class, value_schema_id,
  value_schema_version, value_body, value_digest, method_digest,
  outcome_code, limitations, producer_independent, environment_independent,
  method_independent, data_independent, supersedes_attestation_id,
  content_digest, created_at
) VALUES
  ('21100000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000002', '21000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000003',
   '16000000-0000-4000-8000-000000000003', 'verifier',
   pg_temp.digest('{"role": "verifier"}'::jsonb::text, 'sha256'),
   'checker_result', 'checker_attested', 'macsad.checker-result', 1,
   '{"checker":"fixture-checker","result":"accepted"}',
   pg_temp.digest('fixture checker result value v1', 'sha256'),
   pg_temp.digest('fixture checker method v1', 'sha256'), 'supported',
   'The fixture checker covers only the frozen Peano fragment.',
   true, true, false, true, NULL,
   pg_temp.digest('fixture checker attestation v1', 'sha256'), '2026-01-15T12:03:02Z'),
  ('21100000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000002', '21000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001',
   '16000000-0000-4000-8000-000000000001', 'director',
   pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'),
   'checker_result', 'human_decided', 'macsad.checker-result', 1,
   '{"reviewed":true,"result":"accepted"}',
   pg_temp.digest('fixture checker result value v2', 'sha256'),
   pg_temp.digest('fixture semantic review method v1', 'sha256'), 'supported',
   'Human review confirms scope, not universal soundness.',
   true, true, true, true, '21100000-0000-4000-8000-000000000001',
   pg_temp.digest('fixture checker attestation v2', 'sha256'), '2026-01-15T12:03:03Z'),
  ('21100000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000002', '21000000-0000-4000-8000-000000000001',
   NULL, '11000000-0000-4000-8000-000000000001',
   '16000000-0000-4000-8000-000000000001', 'director',
   pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'),
   'human_disposition', 'human_decided', 'macsad.case-disposition', 1,
   '{"disposition":"proved","reason":"checker_and_review_agree"}',
   pg_temp.digest('fixture math disposition value v1', 'sha256'),
   pg_temp.digest('fixture disposition method v1', 'sha256'), 'proved', '',
   true, true, true, true, NULL,
   pg_temp.digest('fixture math disposition attestation v1', 'sha256'),
   '2026-01-15T12:03:04Z'),
  ('21100000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000002', '21000000-0000-4000-8000-000000000001',
   NULL, '11000000-0000-4000-8000-000000000001',
   '16000000-0000-4000-8000-000000000001', 'director',
   pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'),
   'editorial_decision', 'human_decided', 'macsad.editorial-decision', 1,
   '{"decision":"eligible","license_checked":true}',
   pg_temp.digest('fixture math editorial value v1', 'sha256'),
   pg_temp.digest('fixture editorial method v1', 'sha256'), 'eligible', '',
   true, true, true, true, NULL,
   pg_temp.digest('fixture math editorial attestation v1', 'sha256'),
   '2026-01-15T12:03:05Z'),
  ('21100000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000003', '21000000-0000-4000-8000-000000000002',
   '20000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000001',
   '16000000-0000-4000-8000-000000000001', 'director',
   pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'),
   'human_disposition', 'human_decided', 'macsad.case-disposition', 1,
   '{"disposition":"inconclusive","reason":"controller_cancelled"}',
   pg_temp.digest('fixture cs disposition value v1', 'sha256'),
   pg_temp.digest('fixture disposition method v1', 'sha256'), 'inconclusive',
   'The bounded replay was cancelled before its stopping rule completed.',
   false, false, false, false, NULL,
   pg_temp.digest('fixture cs disposition attestation v1', 'sha256'),
   '2026-01-15T12:03:06Z'),
  ('21100000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000003', '21000000-0000-4000-8000-000000000002',
   NULL, '11000000-0000-4000-8000-000000000001',
   '16000000-0000-4000-8000-000000000001', 'director',
   pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'),
   'editorial_decision', 'human_decided', 'macsad.editorial-decision', 1,
   '{"decision":"private","reason":"inconclusive"}',
   pg_temp.digest('fixture cs editorial value v1', 'sha256'),
   pg_temp.digest('fixture editorial method v1', 'sha256'), 'private', '',
   false, false, false, false, NULL,
   pg_temp.digest('fixture cs editorial attestation v1', 'sha256'),
   '2026-01-15T12:03:07Z'),
  ('21100000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000001', NULL, NULL,
   '11000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000001',
   'director', pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'),
   'human_disposition', 'human_decided', 'macsad.case-disposition', 1,
   '{"disposition":"superseded","successor_case_id":"18000000-0000-4000-8000-000000000002"}',
   pg_temp.digest('fixture admin disposition value v1', 'sha256'),
   pg_temp.digest('fixture disposition method v1', 'sha256'), 'superseded', '',
   true, true, true, true, NULL,
   pg_temp.digest('fixture admin disposition attestation v1', 'sha256'),
   '2026-01-15T12:03:08Z'),
  ('21100000-0000-4000-8000-000000000008', '10000000-0000-4000-8000-000000000001',
   '17000000-0000-4000-8000-000000000001', NULL, NULL,
   '11000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000001',
   'director', pg_temp.digest('{"role": "director"}'::jsonb::text, 'sha256'),
   'editorial_decision', 'human_decided', 'macsad.editorial-decision', 1,
   '{"decision":"private","reason":"superseded"}',
   pg_temp.digest('fixture admin editorial value v1', 'sha256'),
   pg_temp.digest('fixture editorial method v1', 'sha256'), 'private', '',
   true, true, true, true, NULL,
   pg_temp.digest('fixture admin editorial attestation v1', 'sha256'),
   '2026-01-15T12:03:09Z');

INSERT INTO macsad.attestation_artifact (
  workspace_id, attestation_id, artifact_id, support_role, created_at
) VALUES
  ('10000000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000001',
   '20200000-0000-4000-8000-000000000001', 'checker_certificate',
   '2026-01-15T12:03:10Z'),
  ('10000000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000003',
   '12000000-0000-4000-8000-000000000008', 'public_dossier',
   '2026-01-15T12:03:11Z'),
  ('10000000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000005',
   '20200000-0000-4000-8000-000000000002', 'cancellation_diagnostic',
   '2026-01-15T12:03:12Z');

UPDATE macsad.research_case
SET state = 'closed', disposition_family = 'administrative',
    administrative_disposition = 'superseded',
    disposition_attestation_id = '21100000-0000-4000-8000-000000000007',
    editorial_decision = 'private',
    eligibility_attestation_id = '21100000-0000-4000-8000-000000000008',
    closed_at = '2026-01-15T12:03:13Z', version = 1
WHERE id = '18000000-0000-4000-8000-000000000001';
UPDATE macsad.research_case
SET state = 'closed', disposition_family = 'mathematics', math_disposition = 'proved',
    disposition_attestation_id = '21100000-0000-4000-8000-000000000003',
    editorial_decision = 'eligible',
    eligibility_attestation_id = '21100000-0000-4000-8000-000000000004',
    closed_at = '2026-01-15T12:03:14Z', version = 1
WHERE id = '18000000-0000-4000-8000-000000000002';
UPDATE macsad.research_case
SET state = 'closed', disposition_family = 'computer_science', cs_disposition = 'inconclusive',
    disposition_attestation_id = '21100000-0000-4000-8000-000000000005',
    editorial_decision = 'private',
    eligibility_attestation_id = '21100000-0000-4000-8000-000000000006',
    closed_at = '2026-01-15T12:03:15Z', version = 1
WHERE id = '18000000-0000-4000-8000-000000000003';

INSERT INTO macsad.publication_dossier (
  id, workspace_id, research_case_id, problem_revision_id, claim_id,
  dossier_artifact_id, closure_schema_id, closure_schema_version,
  closure_body, closure_digest, created_by_actor_id, created_at
) VALUES (
  '24000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '18000000-0000-4000-8000-000000000002', '17000000-0000-4000-8000-000000000002',
  '21000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000008',
  'macsad.publication-closure', 1,
  '{"artifact_count":3,"attestation_count":4,"license_expression":"CC0-1.0"}',
  pg_temp.digest('fixture publication closure v1', 'sha256'),
  '11000000-0000-4000-8000-000000000001', '2026-01-15T12:03:16Z'
);

INSERT INTO macsad.publication_batch (
  id, workspace_id, policy_revision_id, batch_sequence, corrects_batch_id,
  state, generator_artifact_id, toolchain_artifact_id,
  generator_revision_digest, platform_revision_digest,
  toolchain_closure_digest, evidence_closure_digest, artifact_closure_digest,
  audit_head_event_id, audit_head_sequence_no, audit_head_event_hash,
  manifest_artifact_id, manifest_digest, signature, sealed_by_actor_id,
  previewed_at, sealed_at, published_at, version, created_at, updated_at
) VALUES (
  '24100000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '15000000-0000-4000-8000-000000000002', NULL, NULL, 'draft',
  '12000000-0000-4000-8000-000000000009', '12000000-0000-4000-8000-000000000003',
  pg_temp.digest('publication generator revision v1', 'sha256'),
  pg_temp.digest('platform revision v1', 'sha256'),
  pg_temp.digest('toolchain closure v1', 'sha256'),
  pg_temp.digest('evidence closure v1', 'sha256'),
  pg_temp.digest('artifact closure v1', 'sha256'),
  '23200000-0000-4000-8000-000000000010', 10,
  pg_temp.digest('fixture event hash 10', 'sha256'),
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0,
  '2026-01-15T12:03:17Z', '2026-01-15T12:03:17Z'
);

INSERT INTO macsad.publication_item (
  id, workspace_id, publication_batch_id, research_case_id,
  problem_revision_id, claim_id, disposition_attestation_id,
  eligibility_attestation_id, publication_dossier_id, dossier_artifact_id,
  item_ordinal, item_digest, created_at
) VALUES (
  '24200000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '24100000-0000-4000-8000-000000000001', '18000000-0000-4000-8000-000000000002',
  '17000000-0000-4000-8000-000000000002', '21000000-0000-4000-8000-000000000001',
  '21100000-0000-4000-8000-000000000003', '21100000-0000-4000-8000-000000000004',
  '24000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000008',
  0, pg_temp.digest('fixture publication item v1', 'sha256'), '2026-01-15T12:03:18Z'
);

-- This deferred trigger validates that selection occurred while the batch was
-- still draft, so force it before advancing the batch lifecycle.
SET CONSTRAINTS macsad.publication_item_closure_ck IMMEDIATE;

UPDATE macsad.publication_batch
SET state = 'previewed', batch_sequence = 1, previewed_at = '2026-01-15T12:03:19Z',
    version = 1
WHERE id = '24100000-0000-4000-8000-000000000001';
UPDATE macsad.publication_batch
SET state = 'sealed', manifest_artifact_id = '12000000-0000-4000-8000-000000000010',
    manifest_digest = pg_temp.digest('sealed manifest v1', 'sha256'),
    signature = pg_catalog.decode(pg_catalog.repeat('ab', 32), 'hex'),
    sealed_by_actor_id = '11000000-0000-4000-8000-000000000001',
    sealed_at = '2026-01-15T12:03:20Z', version = 2
WHERE id = '24100000-0000-4000-8000-000000000001';

INSERT INTO macsad.publication_attempt (
  id, workspace_id, publication_batch_id, attempt_no, trigger_kind,
  target_environment, platform_revision_digest, generator_revision_digest,
  release_request_digest, github_repository_id, github_workflow,
  github_run_id, github_run_attempt, cloudflare_account_reference,
  cloudflare_project_name, cloudflare_version_id, cloudflare_deployment_id,
  deployment_url, state, response_artifact_id, started_at, finished_at,
  error_code, version, created_at, updated_at
) VALUES
  ('24300000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '24100000-0000-4000-8000-000000000001', 1, 'manual', 'fixture-preview',
   pg_temp.digest('platform revision v1', 'sha256'),
   pg_temp.digest('publication generator revision v1', 'sha256'),
   pg_temp.digest('release request failed v1', 'sha256'), 910000001,
   'publish-fixture.yml', NULL, NULL, 'secretref://fixture/cloudflare/account',
   'macsad-fixture', NULL, NULL, NULL, 'pending', NULL, NULL, NULL, NULL, 0,
   '2026-01-15T12:03:21Z', '2026-01-15T12:03:21Z'),
  ('24300000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   '24100000-0000-4000-8000-000000000001', 2, 'manual', 'fixture-production',
   pg_temp.digest('platform revision v1', 'sha256'),
   pg_temp.digest('publication generator revision v1', 'sha256'),
   pg_temp.digest('release request success v1', 'sha256'), 910000001,
   'publish-fixture.yml', NULL, NULL, 'secretref://fixture/cloudflare/account',
   'macsad-fixture', NULL, NULL, NULL, 'pending', NULL, NULL, NULL, NULL, 0,
   '2026-01-15T12:03:22Z', '2026-01-15T12:03:22Z');

UPDATE macsad.publication_attempt
SET state = 'running', started_at = '2026-01-15T12:03:23Z', version = 1
WHERE id IN ('24300000-0000-4000-8000-000000000001', '24300000-0000-4000-8000-000000000002');
UPDATE macsad.publication_attempt
SET state = 'failed', github_run_id = 810000001, github_run_attempt = 1,
    response_artifact_id = '20200000-0000-4000-8000-000000000003',
    finished_at = '2026-01-15T12:03:24Z', error_code = 'fixture_preview_rejected',
    version = 2
WHERE id = '24300000-0000-4000-8000-000000000001';
UPDATE macsad.publication_attempt
SET state = 'succeeded', github_run_id = 810000002, github_run_attempt = 1,
    cloudflare_version_id = 'cf-version-fixture-1',
    cloudflare_deployment_id = 'cf-deployment-fixture-1',
    deployment_url = 'https://fixture.invalid/deployments/1',
    response_artifact_id = '20200000-0000-4000-8000-000000000003',
    finished_at = '2026-01-15T12:03:25Z', version = 2
WHERE id = '24300000-0000-4000-8000-000000000002';

UPDATE macsad.publication_batch
SET state = 'published', published_at = '2026-01-15T12:03:26Z', version = 3
WHERE id = '24100000-0000-4000-8000-000000000001';

INSERT INTO macsad.publication_head (
  workspace_id, publication_batch_id, publication_attempt_id,
  version, created_at, updated_at
) VALUES (
  '10000000-0000-4000-8000-000000000001',
  '24100000-0000-4000-8000-000000000001',
  '24300000-0000-4000-8000-000000000002', 0,
  '2026-01-15T12:03:27Z', '2026-01-15T12:03:27Z'
);

INSERT INTO macsad.publication_batch (
  id, workspace_id, policy_revision_id, batch_sequence, corrects_batch_id,
  state, generator_artifact_id, toolchain_artifact_id,
  generator_revision_digest, platform_revision_digest,
  toolchain_closure_digest, evidence_closure_digest, artifact_closure_digest,
  audit_head_event_id, audit_head_sequence_no, audit_head_event_hash,
  manifest_artifact_id, manifest_digest, signature, sealed_by_actor_id,
  previewed_at, sealed_at, published_at, version, created_at, updated_at
) VALUES (
  '24100000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
  '15000000-0000-4000-8000-000000000002', NULL,
  '24100000-0000-4000-8000-000000000001', 'draft',
  '12000000-0000-4000-8000-000000000009', '12000000-0000-4000-8000-000000000003',
  pg_temp.digest('publication generator revision v1', 'sha256'),
  pg_temp.digest('platform revision v1', 'sha256'),
  pg_temp.digest('toolchain closure v1', 'sha256'),
  pg_temp.digest('evidence closure corrected v2', 'sha256'),
  pg_temp.digest('artifact closure corrected v2', 'sha256'),
  '23200000-0000-4000-8000-000000000010', 10,
  pg_temp.digest('fixture event hash 10', 'sha256'),
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0,
  '2026-01-15T12:03:28Z', '2026-01-15T12:03:28Z'
);

INSERT INTO macsad.publication_item (
  id, workspace_id, publication_batch_id, research_case_id,
  problem_revision_id, claim_id, disposition_attestation_id,
  eligibility_attestation_id, publication_dossier_id, dossier_artifact_id,
  item_ordinal, item_digest, created_at
) VALUES (
  '24200000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
  '24100000-0000-4000-8000-000000000002', '18000000-0000-4000-8000-000000000002',
  '17000000-0000-4000-8000-000000000002', '21000000-0000-4000-8000-000000000001',
  '21100000-0000-4000-8000-000000000003', '21100000-0000-4000-8000-000000000004',
  '24000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000008',
  0, pg_temp.digest('fixture publication item corrected v2', 'sha256'),
  '2026-01-15T12:03:29Z'
);

UPDATE macsad.publication_batch
SET state = 'previewed', batch_sequence = 2, previewed_at = '2026-01-15T12:03:30Z',
    version = 1
WHERE id = '24100000-0000-4000-8000-000000000002';
UPDATE macsad.publication_batch
SET state = 'sealed', manifest_artifact_id = '12000000-0000-4000-8000-000000000010',
    manifest_digest = pg_temp.digest('sealed manifest corrected v2', 'sha256'),
    signature = pg_catalog.decode(pg_catalog.repeat('cd', 32), 'hex'),
    sealed_by_actor_id = '11000000-0000-4000-8000-000000000001',
    sealed_at = '2026-01-15T12:03:31Z', version = 2
WHERE id = '24100000-0000-4000-8000-000000000002';

INSERT INTO macsad.publication_attempt (
  id, workspace_id, publication_batch_id, attempt_no, trigger_kind,
  target_environment, platform_revision_digest, generator_revision_digest,
  release_request_digest, github_repository_id, github_workflow,
  github_run_id, github_run_attempt, cloudflare_account_reference,
  cloudflare_project_name, cloudflare_version_id, cloudflare_deployment_id,
  deployment_url, state, response_artifact_id, started_at, finished_at,
  error_code, version, created_at, updated_at
) VALUES (
  '24300000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001',
  '24100000-0000-4000-8000-000000000002', 1, 'correction', 'fixture-production',
  pg_temp.digest('platform revision v1', 'sha256'),
  pg_temp.digest('publication generator revision v1', 'sha256'),
  pg_temp.digest('release request correction v2', 'sha256'), 910000001,
  'publish-fixture.yml', NULL, NULL, 'secretref://fixture/cloudflare/account',
  'macsad-fixture', NULL, NULL, NULL, 'pending', NULL, NULL, NULL, NULL, 0,
  '2026-01-15T12:03:32Z', '2026-01-15T12:03:32Z'
);
UPDATE macsad.publication_attempt
SET state = 'running', started_at = '2026-01-15T12:03:33Z', version = 1
WHERE id = '24300000-0000-4000-8000-000000000003';
UPDATE macsad.publication_attempt
SET state = 'succeeded', github_run_id = 810000003, github_run_attempt = 1,
    cloudflare_version_id = 'cf-version-fixture-2',
    cloudflare_deployment_id = 'cf-deployment-fixture-2',
    deployment_url = 'https://fixture.invalid/deployments/2',
    response_artifact_id = '20200000-0000-4000-8000-000000000003',
    finished_at = '2026-01-15T12:03:34Z', version = 2
WHERE id = '24300000-0000-4000-8000-000000000003';
UPDATE macsad.publication_batch
SET state = 'published', published_at = '2026-01-15T12:03:35Z', version = 3
WHERE id = '24100000-0000-4000-8000-000000000002';

UPDATE macsad.publication_head
SET publication_batch_id = '24100000-0000-4000-8000-000000000002',
    publication_attempt_id = '24300000-0000-4000-8000-000000000003', version = 1
WHERE workspace_id = '10000000-0000-4000-8000-000000000001';
UPDATE macsad.publication_batch
SET state = 'superseded', version = 4
WHERE id = '24100000-0000-4000-8000-000000000001';

SET CONSTRAINTS ALL IMMEDIATE;

DO $fixture_assertions$
DECLARE
  relation_name text;
  relation_has_row boolean;
BEGIN
  FOR relation_name IN
    SELECT c.relname
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'macsad' AND c.relkind = 'r'
    ORDER BY c.relname
  LOOP
    EXECUTE pg_catalog.format('SELECT EXISTS (SELECT 1 FROM macsad.%I)', relation_name)
      INTO relation_has_row;
    IF NOT relation_has_row THEN
      RAISE EXCEPTION 'representative-v1 left macsad.% empty', relation_name;
    END IF;
  END LOOP;

  IF (SELECT pg_catalog.count(*) FROM macsad.workspace) <> 1
      OR (SELECT pg_catalog.count(*) FROM macsad.domain_event) <> 10
      OR (SELECT pg_catalog.count(*) FROM macsad.research_case WHERE state = 'closed') <> 3
      OR (SELECT pg_catalog.count(*) FROM macsad.publication_batch WHERE state = 'published') <> 1
      OR (SELECT pg_catalog.count(*) FROM macsad.publication_batch WHERE state = 'superseded') <> 1 THEN
    RAISE EXCEPTION 'representative-v1 final row-count contract failed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM macsad.audit_stream
    WHERE workspace_id = '10000000-0000-4000-8000-000000000001'
      AND last_workspace_sequence = 10
      AND last_event_hash = pg_temp.digest('fixture event hash 10', 'sha256')
      AND version = 10
  ) OR EXISTS (
    SELECT 1
    FROM (
      SELECT workspace_sequence_no, previous_event_hash,
        pg_catalog.lag(event_hash) OVER (ORDER BY workspace_sequence_no) AS expected_previous
      FROM macsad.domain_event
      WHERE workspace_id = '10000000-0000-4000-8000-000000000001'
    ) AS chain
    WHERE previous_event_hash IS DISTINCT FROM expected_previous
  ) THEN
    RAISE EXCEPTION 'representative-v1 audit hash-chain contract failed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM macsad.publication_head AS head
    JOIN macsad.publication_batch AS batch ON batch.id = head.publication_batch_id
    JOIN macsad.publication_attempt AS attempt ON attempt.id = head.publication_attempt_id
    WHERE head.workspace_id = '10000000-0000-4000-8000-000000000001'
      AND batch.state = 'published' AND attempt.state = 'succeeded'
  ) THEN
    RAISE EXCEPTION 'representative-v1 publication head contract failed';
  END IF;
END
$fixture_assertions$;

SELECT 'representative-v1 deterministic scenario seeded' AS result;
