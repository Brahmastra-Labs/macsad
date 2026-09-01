-- MaCSad PostgreSQL 16 initial schema.
--
-- This file is immutable after it has been applied anywhere. The migration
-- runner must provide migration_sha256 as the lowercase hexadecimal SHA-256
-- of these exact bytes:
--
--   psql -v ON_ERROR_STOP=1 -v migration_sha256=<64-lowercase-hex> ... -f 0001_initial_schema.sql
--
-- The bootstrap creates the database and the NOLOGIN roles macsad_owner,
-- macsad_migrator, macsad_app, and macsad_reader before running this file.

\set ON_ERROR_STOP on

\if :{?migration_sha256}
SELECT (:'migration_sha256' ~ '^[0-9a-f]{64}$') AS migration_sha256_valid \gset
\if :migration_sha256_valid
\else
\echo 'migration_sha256 must be exactly 64 lowercase hexadecimal characters'
\quit 3
\endif
\else
\echo 'migration_sha256 psql variable is required'
\quit 3
\endif

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '5min';
SET LOCAL idle_in_transaction_session_timeout = '5min';
SET LOCAL ROLE macsad_owner;

-- Serialize every MaCSad migration in this database for the transaction.
SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('macsad:schema-migration', 0)
);

-- The application never creates objects in public. Keeping public unusable by
-- PUBLIC prevents search-path object substitution and accidental object drift.
REVOKE ALL ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA macsad_meta AUTHORIZATION macsad_owner;
CREATE SCHEMA macsad AUTHORIZATION macsad_owner;

REVOKE ALL ON SCHEMA macsad_meta FROM PUBLIC;
REVOKE ALL ON SCHEMA macsad FROM PUBLIC;

CREATE TABLE macsad_meta.schema_migration (
  version bigint PRIMARY KEY CHECK (version > 0),
  name text NOT NULL UNIQUE
    CHECK (name ~ '^[0-9]{4}_[a-z0-9_]+$'),
  script_sha256 bytea NOT NULL UNIQUE
    CHECK (pg_catalog.octet_length(script_sha256) = 32),
  applied_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  applied_by name NOT NULL DEFAULT session_user,
  postgresql_version integer NOT NULL
    DEFAULT pg_catalog.current_setting('server_version_num')::integer
    CHECK (postgresql_version >= 160000)
);

CREATE DOMAIN macsad.sha256_digest AS bytea
  CHECK (pg_catalog.octet_length(VALUE) = 32);

CREATE DOMAIN macsad.git_object_id AS text
  CHECK (VALUE ~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$');

CREATE DOMAIN macsad.nonnegative_quantity AS numeric(30, 12)
  CHECK (VALUE >= 0);

CREATE DOMAIN macsad.exact_money AS numeric(30, 12)
  CHECK (VALUE >= 0);

CREATE DOMAIN macsad.iso_currency_code AS text
  CHECK (VALUE ~ '^[A-Z]{3}$');

CREATE DOMAIN macsad.canonical_json AS jsonb
  CHECK (pg_catalog.jsonb_typeof(VALUE) = 'object');

CREATE TYPE macsad.actor_kind AS ENUM ('human', 'agent', 'service');
CREATE TYPE macsad.actor_state AS ENUM ('active', 'paused', 'retired');
CREATE TYPE macsad.workspace_state AS ENUM ('pending', 'active', 'paused', 'disconnected');
CREATE TYPE macsad.repository_source_kind AS ENUM ('github', 'local_checkout');
CREATE TYPE macsad.tool_repository_state AS ENUM ('active', 'disabled', 'disconnected');
CREATE TYPE macsad.tool_exposure AS ENUM ('private_host', 'controlled_network', 'public_source');
CREATE TYPE macsad.repository_observation_source AS ENUM ('github_webhook', 'reconciliation', 'manual_import');
CREATE TYPE macsad.repository_policy_result AS ENUM ('accepted', 'quarantined', 'rejected');
CREATE TYPE macsad.tool_access_mode AS ENUM ('source_read', 'operation_invoke');
CREATE TYPE macsad.tool_effect_class AS ENUM ('pure_check', 'bounded_compute', 'model_call', 'artifact_emit');
CREATE TYPE macsad.policy_revision_state AS ENUM ('candidate', 'active', 'retired');
CREATE TYPE macsad.policy_validation_result AS ENUM ('passed', 'failed');
CREATE TYPE macsad.policy_node_kind AS ENUM (
  'start', 'task', 'decision', 'gate', 'fork', 'join', 'handoff', 'wait', 'call', 'terminal'
);
CREATE TYPE macsad.transition_kind AS ENUM ('normal', 'success', 'failure', 'timeout', 'cancel', 'default');
CREATE TYPE macsad.kanban_phase AS ENUM ('inbox', 'ready', 'running', 'verify', 'review', 'closed');
CREATE TYPE macsad.membership_state AS ENUM ('active', 'paused', 'retired');
CREATE TYPE macsad.research_kind AS ENUM ('mathematics', 'computer_science');
CREATE TYPE macsad.case_state AS ENUM ('open', 'closed');
CREATE TYPE macsad.case_control_state AS ENUM ('normal', 'paused', 'blocked');
CREATE TYPE macsad.disposition_family AS ENUM ('mathematics', 'computer_science', 'administrative');
CREATE TYPE macsad.math_disposition AS ENUM ('proved', 'refuted', 'inconclusive', 'invalid_formalization');
CREATE TYPE macsad.cs_disposition AS ENUM (
  'observed_under_frozen_protocol', 'exactly_reproduced', 'refuted', 'inconclusive', 'invalid_experiment'
);
CREATE TYPE macsad.administrative_disposition AS ENUM ('superseded', 'cancelled', 'policy_denied');
CREATE TYPE macsad.editorial_decision AS ENUM ('not_reviewed', 'private', 'eligible');
CREATE TYPE macsad.task_state AS ENUM ('offered', 'ready', 'running', 'waiting', 'completed', 'cancelled');
CREATE TYPE macsad.assignment_state AS ENUM ('offered', 'accepted', 'rejected', 'expired', 'released');
CREATE TYPE macsad.thread_kind AS ENUM ('workspace_operations', 'case_primary', 'task');
CREATE TYPE macsad.thread_state AS ENUM ('open', 'archived');
CREATE TYPE macsad.message_format AS ENUM ('plain_text', 'markdown');
CREATE TYPE macsad.execution_state AS ENUM (
  'pending', 'leased', 'running', 'cancel_requested', 'completed', 'failed', 'expired'
);
CREATE TYPE macsad.transport_outcome AS ENUM ('accepted', 'rejected', 'unavailable', 'protocol_error');
CREATE TYPE macsad.termination_outcome AS ENUM (
  'clean_exit', 'step_limit', 'wall_timeout', 'out_of_memory', 'signal', 'cancelled',
  'policy_denied', 'tool_error', 'partial_output'
);
CREATE TYPE macsad.claim_outcome AS ENUM ('candidate', 'supported', 'rejected', 'unknown', 'inconclusive');
CREATE TYPE macsad.artifact_classification AS ENUM ('private', 'internal', 'public_candidate', 'public');
CREATE TYPE macsad.scan_result AS ENUM ('pending', 'passed', 'failed', 'not_applicable');
CREATE TYPE macsad.execution_artifact_role AS ENUM (
  'input', 'output', 'log', 'certificate', 'patch', 'diagnostic', 'environment_manifest'
);
CREATE TYPE macsad.tool_use_state AS ENUM ('pending', 'running', 'completed', 'failed', 'cancelled');
CREATE TYPE macsad.claim_kind AS ENUM (
  'formal_proposition', 'counterexample', 'bounded_observation', 'reproduction_statement', 'human_interpretation'
);
CREATE TYPE macsad.attestation_kind AS ENUM (
  'agent_assertion', 'tool_observation', 'semantic_review', 'checker_result',
  'counterexample_validation', 'reproduction', 'methodological_review',
  'human_disposition', 'editorial_decision'
);
CREATE TYPE macsad.authority_class AS ENUM (
  'agent_asserted', 'tool_observed', 'checker_attested', 'controller_derived', 'human_decided'
);
CREATE TYPE macsad.budget_resource_kind AS ENUM (
  'currency', 'model_tokens', 'cpu_seconds', 'wall_seconds', 'storage_bytes'
);
CREATE TYPE macsad.budget_entry_kind AS ENUM (
  'reserve', 'commit', 'release', 'spend_adjustment', 'usage_reconciliation', 'limit_adjustment'
);
CREATE TYPE macsad.model_call_state AS ENUM (
  'reserved', 'submitted', 'streaming', 'succeeded', 'failed', 'usage_pending', 'reconciled', 'cancelled'
);
CREATE TYPE macsad.usage_observation_source AS ENUM (
  'response', 'final_sse', 'generation_reconcile', 'manual_reconciliation'
);
CREATE TYPE macsad.publication_state AS ENUM ('draft', 'previewed', 'sealed', 'published', 'superseded');
CREATE TYPE macsad.publication_attempt_state AS ENUM ('pending', 'running', 'succeeded', 'failed');
CREATE TYPE macsad.publication_trigger_kind AS ENUM ('manual', 'scheduled', 'repository_push', 'correction');
CREATE TYPE macsad.command_state AS ENUM ('processing', 'completed', 'rejected');
CREATE TYPE macsad.delivery_state AS ENUM ('received', 'processing', 'completed', 'rejected', 'dead_letter');
CREATE TYPE macsad.outbox_state AS ENUM ('pending', 'publishing', 'delivered', 'dead_letter');

CREATE FUNCTION macsad.reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION '% is append-only; % is forbidden', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP
    USING ERRCODE = '55000';
END;
$$;

CREATE FUNCTION macsad.guard_versioned_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF NEW.version <> OLD.version + 1 THEN
    RAISE EXCEPTION 'expected %.version %, received %', TG_TABLE_NAME, OLD.version + 1, NEW.version
      USING ERRCODE = '40001';
  END IF;
  NEW.updated_at := pg_catalog.clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE FUNCTION macsad.guard_workspace_identity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF NEW.github_repository_id <> OLD.github_repository_id THEN
    RAISE EXCEPTION 'the watched GitHub repository identity is immutable'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION macsad.guard_tool_repository_identity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF ROW(NEW.workspace_id, NEW.repository_key, NEW.source_kind, NEW.github_repository_id)
      IS DISTINCT FROM
      ROW(OLD.workspace_id, OLD.repository_key, OLD.source_kind, OLD.github_repository_id) THEN
    RAISE EXCEPTION 'tool repository identity is immutable; reconcile mutable names and locators instead'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION macsad.guard_state_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
DECLARE
  old_state text := pg_catalog.to_jsonb(OLD) ->> 'state';
  new_state text := pg_catalog.to_jsonb(NEW) ->> 'state';
  transition_key text := old_state || '>' || new_state;
  allowed_transitions text[] := pg_catalog.string_to_array(TG_ARGV[0], ',');
  terminal_states text[] := pg_catalog.string_to_array(TG_ARGV[1], ',');
BEGIN
  IF old_state = ANY(terminal_states) THEN
    RAISE EXCEPTION '% row in terminal state % is immutable', TG_TABLE_NAME, old_state
      USING ERRCODE = '55000';
  END IF;
  IF new_state <> old_state AND NOT (transition_key = ANY(allowed_transitions)) THEN
    RAISE EXCEPTION 'invalid % state transition from % to %', TG_TABLE_NAME, old_state, new_state
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION macsad.guard_initial_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
DECLARE
  initial_state text := pg_catalog.to_jsonb(NEW) ->> 'state';
BEGIN
  IF initial_state <> TG_ARGV[0] THEN
    RAISE EXCEPTION 'new % rows must begin in state %', TG_TABLE_NAME, TG_ARGV[0]
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TABLE macsad.workspace (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  github_repository_id bigint NOT NULL UNIQUE CHECK (github_repository_id > 0),
  owner_name text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(owner_name)) > 0),
  repository_name text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(repository_name)) > 0),
  default_branch text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(default_branch)) > 0),
  installation_id bigint CHECK (installation_id > 0),
  state macsad.workspace_state NOT NULL DEFAULT 'pending',
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CHECK (updated_at >= created_at)
);

CREATE TABLE macsad.tool_repository (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  repository_key text NOT NULL CHECK (repository_key ~ '^[a-z][a-z0-9._-]*$'),
  purpose text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(purpose)) > 0),
  source_kind macsad.repository_source_kind NOT NULL,
  github_repository_id bigint CHECK (github_repository_id > 0),
  owner_name text,
  repository_name text,
  default_branch text,
  locator_key text NOT NULL CHECK (locator_key ~ '^[a-z][a-z0-9._/-]*$'),
  connection_reference text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(connection_reference)) > 0),
  default_classification macsad.artifact_classification NOT NULL,
  exposure macsad.tool_exposure NOT NULL,
  approved_by_actor_id uuid,
  approved_at timestamptz,
  state macsad.tool_repository_state NOT NULL DEFAULT 'disabled',
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, repository_key),
  CHECK (
    (source_kind = 'github'
      AND github_repository_id IS NOT NULL
      AND owner_name IS NOT NULL AND repository_name IS NOT NULL AND default_branch IS NOT NULL
      )
    OR
    (source_kind = 'local_checkout'
      AND locator_key IS NOT NULL)
  ),
  CHECK ((state = 'active') = (approved_by_actor_id IS NOT NULL AND approved_at IS NOT NULL)
    OR state IN ('disabled', 'disconnected')),
  CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX tool_repository_github_identity_uq
  ON macsad.tool_repository(workspace_id, github_repository_id)
  WHERE github_repository_id IS NOT NULL;
CREATE UNIQUE INDEX tool_repository_locator_uq
  ON macsad.tool_repository(workspace_id, locator_key);
CREATE INDEX tool_repository_workspace_idx ON macsad.tool_repository(workspace_id);

CREATE TABLE macsad.tool_repository_revision (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  tool_repository_id uuid NOT NULL,
  object_algorithm text NOT NULL CHECK (object_algorithm IN ('sha1', 'sha256')),
  commit_oid macsad.git_object_id NOT NULL,
  tree_oid macsad.git_object_id NOT NULL,
  observed_branch text,
  observation_source macsad.repository_observation_source NOT NULL,
  source_artifact_id uuid,
  access_policy_schema_id text NOT NULL,
  access_policy_schema_version integer NOT NULL CHECK (access_policy_schema_version > 0),
  access_policy_body macsad.canonical_json NOT NULL,
  access_policy_digest macsad.sha256_digest NOT NULL,
  source_digest macsad.sha256_digest NOT NULL,
  manifest_digest macsad.sha256_digest NOT NULL,
  lock_digest macsad.sha256_digest NOT NULL,
  dependency_digest macsad.sha256_digest NOT NULL,
  build_environment_digest macsad.sha256_digest NOT NULL,
  promoted_bundle_artifact_id uuid,
  promoted_executable_artifact_id uuid,
  compatibility_evidence_artifact_id uuid,
  operation_count integer CHECK (operation_count >= 0),
  operation_catalog_digest macsad.sha256_digest,
  operations_sealed_by_actor_id uuid,
  operations_sealed_at timestamptz,
  revision_digest macsad.sha256_digest NOT NULL,
  observed_at timestamptz NOT NULL,
  preserved_at timestamptz,
  promoted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, tool_repository_id, id),
  UNIQUE (tool_repository_id, revision_digest),
  UNIQUE (tool_repository_id, object_algorithm, commit_oid, access_policy_digest, revision_digest),
  FOREIGN KEY (workspace_id, tool_repository_id)
    REFERENCES macsad.tool_repository(workspace_id, id),
  CHECK (
    (object_algorithm = 'sha1' AND pg_catalog.length(commit_oid) = 40 AND pg_catalog.length(tree_oid) = 40)
    OR (object_algorithm = 'sha256' AND pg_catalog.length(commit_oid) = 64 AND pg_catalog.length(tree_oid) = 64)
  ),
  CHECK ((source_artifact_id IS NULL) = (preserved_at IS NULL)),
  CHECK (preserved_at IS NULL OR preserved_at >= observed_at),
  CHECK (promoted_at IS NULL OR (preserved_at IS NOT NULL AND promoted_at >= preserved_at)),
  CHECK ((promoted_bundle_artifact_id IS NULL) = (promoted_at IS NULL)),
  CHECK (promoted_executable_artifact_id IS NULL OR promoted_at IS NOT NULL),
  CHECK (compatibility_evidence_artifact_id IS NULL OR promoted_at IS NOT NULL),
  CHECK (
    (operation_count IS NULL AND operation_catalog_digest IS NULL
      AND operations_sealed_by_actor_id IS NULL AND operations_sealed_at IS NULL)
    OR
    (operation_count IS NOT NULL AND operation_catalog_digest IS NOT NULL
      AND operations_sealed_by_actor_id IS NOT NULL AND operations_sealed_at IS NOT NULL)
  ),
  CHECK (operations_sealed_at IS NULL OR operations_sealed_at >= created_at)
);

CREATE INDEX tool_repository_revision_repository_idx
  ON macsad.tool_repository_revision(tool_repository_id);

CREATE FUNCTION macsad.guard_tool_revision_seal()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  actual_operation_count integer;
BEGIN
  IF (pg_catalog.to_jsonb(NEW) - ARRAY[
      'operation_count', 'operation_catalog_digest',
      'operations_sealed_by_actor_id', 'operations_sealed_at'
    ]) IS DISTINCT FROM (pg_catalog.to_jsonb(OLD) - ARRAY[
      'operation_count', 'operation_catalog_digest',
      'operations_sealed_by_actor_id', 'operations_sealed_at'
    ]) THEN
    RAISE EXCEPTION 'tool revision source and promotion closure are immutable'
      USING ERRCODE = '55000';
  END IF;
  IF OLD.operations_sealed_at IS NOT NULL THEN
    RAISE EXCEPTION 'sealed tool operation catalog is immutable'
      USING ERRCODE = '55000';
  END IF;
  IF NEW.operations_sealed_at IS NULL THEN
    RAISE EXCEPTION 'tool revision update must atomically seal its operation catalog'
      USING ERRCODE = '23514';
  END IF;

  SELECT pg_catalog.count(*)::integer INTO actual_operation_count
  FROM macsad.tool_operation_manifest AS operation
  WHERE operation.tool_repository_revision_id = NEW.id;
  IF NEW.operation_count <> actual_operation_count THEN
    RAISE EXCEPTION 'tool operation count does not match the sealed catalog'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TABLE macsad.tool_operation_manifest (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  tool_repository_revision_id uuid NOT NULL,
  operation_key text NOT NULL CHECK (operation_key ~ '^[a-z][a-z0-9._-]*$'),
  operation_version integer NOT NULL CHECK (operation_version > 0),
  provider_key text NOT NULL CHECK (provider_key ~ '^[a-z][a-z0-9._-]*$'),
  provider_revision text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(provider_revision)) > 0),
  effect_class macsad.tool_effect_class NOT NULL,
  request_schema_id text NOT NULL,
  request_schema_version integer NOT NULL CHECK (request_schema_version > 0),
  request_schema_digest macsad.sha256_digest NOT NULL,
  response_schema_id text NOT NULL,
  response_schema_version integer NOT NULL CHECK (response_schema_version > 0),
  response_schema_digest macsad.sha256_digest NOT NULL,
  manifest_schema_id text NOT NULL,
  manifest_schema_version integer NOT NULL CHECK (manifest_schema_version > 0),
  manifest_body macsad.canonical_json NOT NULL,
  manifest_digest macsad.sha256_digest NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, tool_repository_revision_id, id),
  UNIQUE (tool_repository_revision_id, operation_key, operation_version),
  UNIQUE (manifest_digest),
  FOREIGN KEY (workspace_id, tool_repository_revision_id)
    REFERENCES macsad.tool_repository_revision(workspace_id, id)
);

CREATE INDEX tool_operation_manifest_revision_idx
  ON macsad.tool_operation_manifest(tool_repository_revision_id);

CREATE FUNCTION macsad.validate_tool_operation_manifest_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  PERFORM 1
  FROM macsad.tool_repository_revision AS revision
  WHERE revision.id = NEW.tool_repository_revision_id
    AND revision.workspace_id = NEW.workspace_id
    AND revision.operations_sealed_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tool operations may only be added before the revision catalog is sealed'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tool_operation_manifest_open_catalog
BEFORE INSERT ON macsad.tool_operation_manifest
FOR EACH ROW EXECUTE FUNCTION macsad.validate_tool_operation_manifest_insert();

CREATE TABLE macsad.workspace_snapshot (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  object_algorithm text NOT NULL CHECK (object_algorithm IN ('sha1', 'sha256')),
  commit_oid macsad.git_object_id NOT NULL,
  tree_oid macsad.git_object_id NOT NULL,
  observed_default_branch text NOT NULL,
  observation_source macsad.repository_observation_source NOT NULL,
  source_artifact_id uuid,
  configuration_digest macsad.sha256_digest NOT NULL,
  repository_policy_result macsad.repository_policy_result NOT NULL,
  repository_policy_schema_id text NOT NULL,
  repository_policy_schema_version integer NOT NULL CHECK (repository_policy_schema_version > 0),
  repository_policy_body macsad.canonical_json NOT NULL,
  repository_policy_digest macsad.sha256_digest NOT NULL,
  snapshot_digest macsad.sha256_digest NOT NULL UNIQUE,
  observed_at timestamptz NOT NULL,
  preserved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, object_algorithm, commit_oid),
  CHECK (
    (object_algorithm = 'sha1' AND pg_catalog.length(commit_oid) = 40 AND pg_catalog.length(tree_oid) = 40)
    OR (object_algorithm = 'sha256' AND pg_catalog.length(commit_oid) = 64 AND pg_catalog.length(tree_oid) = 64)
  ),
  CHECK (preserved_at IS NULL OR preserved_at >= observed_at)
);

CREATE INDEX workspace_snapshot_workspace_idx ON macsad.workspace_snapshot(workspace_id);

CREATE TABLE macsad.policy_revision (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  workspace_snapshot_id uuid NOT NULL,
  prior_revision_id uuid,
  source_path text NOT NULL,
  source_digest macsad.sha256_digest NOT NULL,
  compiler_name text NOT NULL,
  compiler_version text NOT NULL,
  schema_id text NOT NULL,
  schema_version integer NOT NULL CHECK (schema_version > 0),
  compiled_body macsad.canonical_json NOT NULL,
  compiled_digest macsad.sha256_digest NOT NULL UNIQUE,
  validation_result macsad.policy_validation_result NOT NULL,
  validation_schema_id text NOT NULL,
  validation_schema_version integer NOT NULL CHECK (validation_schema_version > 0),
  validation_body macsad.canonical_json NOT NULL,
  validation_digest macsad.sha256_digest NOT NULL,
  validated_at timestamptz NOT NULL,
  semantic_diff_artifact_id uuid,
  state macsad.policy_revision_state NOT NULL DEFAULT 'candidate',
  activated_by_actor_id uuid,
  activated_at timestamptz,
  retired_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, workspace_snapshot_id)
    REFERENCES macsad.workspace_snapshot(workspace_id, id),
  FOREIGN KEY (workspace_id, prior_revision_id)
    REFERENCES macsad.policy_revision(workspace_id, id),
  CHECK (
    (state = 'candidate' AND activated_by_actor_id IS NULL AND activated_at IS NULL AND retired_at IS NULL)
    OR (state = 'active' AND activated_by_actor_id IS NOT NULL AND activated_at IS NOT NULL
      AND retired_at IS NULL)
    OR (state = 'retired' AND activated_by_actor_id IS NOT NULL AND activated_at IS NOT NULL
      AND retired_at IS NOT NULL AND retired_at >= activated_at)
  ),
  CHECK (state <> 'active' OR validation_result = 'passed'),
  CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX policy_revision_one_active_uq
  ON macsad.policy_revision(workspace_id)
  WHERE state = 'active';
CREATE INDEX policy_revision_snapshot_idx ON macsad.policy_revision(workspace_snapshot_id);
CREATE INDEX policy_revision_prior_idx ON macsad.policy_revision(prior_revision_id);

CREATE FUNCTION macsad.guard_policy_revision_content()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF ROW(
      NEW.workspace_id, NEW.workspace_snapshot_id, NEW.prior_revision_id,
      NEW.source_path, NEW.source_digest, NEW.compiler_name, NEW.compiler_version,
      NEW.schema_id, NEW.schema_version, NEW.compiled_body, NEW.compiled_digest,
      NEW.validation_result, NEW.validation_schema_id, NEW.validation_schema_version,
      NEW.validation_body, NEW.validation_digest, NEW.validated_at,
      NEW.semantic_diff_artifact_id
    ) IS DISTINCT FROM ROW(
      OLD.workspace_id, OLD.workspace_snapshot_id, OLD.prior_revision_id,
      OLD.source_path, OLD.source_digest, OLD.compiler_name, OLD.compiler_version,
      OLD.schema_id, OLD.schema_version, OLD.compiled_body, OLD.compiled_digest,
      OLD.validation_result, OLD.validation_schema_id, OLD.validation_schema_version,
      OLD.validation_body, OLD.validation_digest, OLD.validated_at,
      OLD.semantic_diff_artifact_id
    ) THEN
    RAISE EXCEPTION 'compiled policy content is immutable' USING ERRCODE = '55000';
  END IF;
  IF NEW.state <> OLD.state AND NOT (
    (OLD.state = 'candidate' AND NEW.state = 'active')
    OR (OLD.state = 'active' AND NEW.state = 'retired')
  ) THEN
    RAISE EXCEPTION 'invalid policy revision state transition from % to %', OLD.state, NEW.state
      USING ERRCODE = '23514';
  END IF;
  IF NEW.state = OLD.state THEN
    RAISE EXCEPTION 'policy revisions only change through activation or retirement'
      USING ERRCODE = '55000';
  END IF;
  IF OLD.state = 'active' AND ROW(NEW.activated_by_actor_id, NEW.activated_at)
      IS DISTINCT FROM ROW(OLD.activated_by_actor_id, OLD.activated_at) THEN
    RAISE EXCEPTION 'policy activation authority and time are immutable'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION macsad.guard_policy_projection_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  PERFORM 1
  FROM macsad.policy_revision AS revision
  WHERE revision.id = NEW.policy_revision_id
    AND revision.workspace_id = NEW.workspace_id
    AND revision.state = 'candidate'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'compiled policy projections may only be added while the revision is a candidate'
      USING ERRCODE = '55000';
  END IF;
  IF TG_TABLE_NAME = 'policy_node_tool_operation' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM macsad.tool_operation_manifest AS operation
      JOIN macsad.tool_repository_revision AS revision
        ON revision.id = operation.tool_repository_revision_id
      WHERE operation.id = NEW.tool_operation_manifest_id
        AND operation.workspace_id = NEW.workspace_id
        AND revision.operations_sealed_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'policy operations must reference a sealed tool operation catalog'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TABLE macsad.policy_member_profile (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  profile_key text NOT NULL CHECK (profile_key ~ '^[a-z][a-z0-9._-]*$'),
  display_name text NOT NULL,
  role_key text NOT NULL CHECK (role_key ~ '^[a-z][a-z0-9._-]*$'),
  supervisor_profile_key text,
  wip_limit integer NOT NULL CHECK (wip_limit > 0),
  profile_schema_id text NOT NULL,
  profile_schema_version integer NOT NULL CHECK (profile_schema_version > 0),
  profile_body macsad.canonical_json NOT NULL,
  profile_digest macsad.sha256_digest NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, policy_revision_id, profile_key),
  UNIQUE (workspace_id, policy_revision_id, profile_key, profile_digest),
  UNIQUE (policy_revision_id, profile_key),
  FOREIGN KEY (workspace_id, policy_revision_id)
    REFERENCES macsad.policy_revision(workspace_id, id),
  FOREIGN KEY (policy_revision_id, supervisor_profile_key)
    REFERENCES macsad.policy_member_profile(policy_revision_id, profile_key),
  CHECK (supervisor_profile_key IS NULL OR supervisor_profile_key <> profile_key)
);

CREATE INDEX policy_member_profile_revision_idx
  ON macsad.policy_member_profile(policy_revision_id);

CREATE TABLE macsad.policy_process (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  process_key text NOT NULL CHECK (process_key ~ '^[a-z][a-z0-9._-]*$'),
  title text NOT NULL,
  entry_node_key text NOT NULL,
  process_schema_id text NOT NULL,
  process_schema_version integer NOT NULL CHECK (process_schema_version > 0),
  process_body macsad.canonical_json NOT NULL,
  graph_digest macsad.sha256_digest NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, policy_revision_id, process_key),
  UNIQUE (policy_revision_id, process_key),
  FOREIGN KEY (workspace_id, policy_revision_id)
    REFERENCES macsad.policy_revision(workspace_id, id)
);

CREATE INDEX policy_process_revision_idx ON macsad.policy_process(policy_revision_id);

CREATE TABLE macsad.policy_node (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  process_key text NOT NULL,
  node_key text NOT NULL CHECK (node_key ~ '^[a-z][a-z0-9._-]*$'),
  node_kind macsad.policy_node_kind NOT NULL,
  title text NOT NULL,
  board_phase macsad.kanban_phase NOT NULL,
  required_profile_key text,
  timeout_seconds integer CHECK (timeout_seconds > 0),
  retry_limit integer NOT NULL DEFAULT 0 CHECK (retry_limit >= 0),
  node_schema_id text NOT NULL,
  node_schema_version integer NOT NULL CHECK (node_schema_version > 0),
  node_body macsad.canonical_json NOT NULL,
  node_digest macsad.sha256_digest NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, policy_revision_id, process_key, node_key),
  UNIQUE (policy_revision_id, process_key, node_key),
  FOREIGN KEY (workspace_id, policy_revision_id, process_key)
    REFERENCES macsad.policy_process(workspace_id, policy_revision_id, process_key),
  FOREIGN KEY (workspace_id, policy_revision_id, required_profile_key)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key),
  CHECK ((node_kind IN ('start', 'decision', 'gate', 'fork', 'join', 'wait', 'terminal'))
    OR required_profile_key IS NOT NULL)
);

CREATE INDEX policy_node_process_idx
  ON macsad.policy_node(policy_revision_id, process_key);
CREATE INDEX policy_node_profile_idx
  ON macsad.policy_node(policy_revision_id, required_profile_key)
  WHERE required_profile_key IS NOT NULL;

ALTER TABLE macsad.policy_process
  ADD CONSTRAINT policy_process_entry_node_fk
  FOREIGN KEY (workspace_id, policy_revision_id, process_key, entry_node_key)
  REFERENCES macsad.policy_node(workspace_id, policy_revision_id, process_key, node_key)
  DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE macsad.policy_transition (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  process_key text NOT NULL,
  transition_key text NOT NULL CHECK (transition_key ~ '^[a-z][a-z0-9._-]*$'),
  source_node_key text NOT NULL,
  target_node_key text NOT NULL,
  transition_kind macsad.transition_kind NOT NULL,
  match_order integer NOT NULL CHECK (match_order >= 0),
  is_default boolean NOT NULL DEFAULT false,
  decision_code text NOT NULL CHECK (decision_code ~ '^[a-z][a-z0-9._-]*$'),
  assignment_profile_key text,
  predicate_schema_id text,
  predicate_schema_version integer,
  predicate_body macsad.canonical_json,
  predicate_digest macsad.sha256_digest,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, policy_revision_id, process_key, id),
  UNIQUE (policy_revision_id, process_key, transition_key),
  UNIQUE (policy_revision_id, process_key, source_node_key, match_order),
  FOREIGN KEY (workspace_id, policy_revision_id, process_key, source_node_key)
    REFERENCES macsad.policy_node(workspace_id, policy_revision_id, process_key, node_key),
  FOREIGN KEY (workspace_id, policy_revision_id, process_key, target_node_key)
    REFERENCES macsad.policy_node(workspace_id, policy_revision_id, process_key, node_key),
  FOREIGN KEY (workspace_id, policy_revision_id, assignment_profile_key)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key),
  CHECK (source_node_key <> target_node_key),
  CHECK (is_default = (transition_kind = 'default')),
  CHECK (
    (is_default AND predicate_schema_id IS NULL AND predicate_schema_version IS NULL
      AND predicate_body IS NULL AND predicate_digest IS NULL)
    OR
    (NOT is_default AND predicate_schema_id IS NOT NULL AND predicate_schema_version > 0
      AND predicate_body IS NOT NULL AND predicate_digest IS NOT NULL)
  )
);

CREATE UNIQUE INDEX policy_transition_one_default_uq
  ON macsad.policy_transition(policy_revision_id, process_key, source_node_key)
  WHERE is_default;
CREATE INDEX policy_transition_target_idx
  ON macsad.policy_transition(policy_revision_id, process_key, target_node_key);

CREATE TABLE macsad.policy_node_tool_operation (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  process_key text NOT NULL,
  node_key text NOT NULL,
  tool_operation_manifest_id uuid NOT NULL,
  max_invocations integer NOT NULL CHECK (max_invocations > 0),
  required boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, policy_revision_id, process_key, node_key, tool_operation_manifest_id),
  FOREIGN KEY (workspace_id, policy_revision_id, process_key, node_key)
    REFERENCES macsad.policy_node(workspace_id, policy_revision_id, process_key, node_key),
  FOREIGN KEY (workspace_id, tool_operation_manifest_id)
    REFERENCES macsad.tool_operation_manifest(workspace_id, id)
);

CREATE INDEX policy_node_tool_operation_manifest_idx
  ON macsad.policy_node_tool_operation(tool_operation_manifest_id);

DO $policy_projection_triggers$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'policy_member_profile', 'policy_process', 'policy_node',
    'policy_transition', 'policy_node_tool_operation'
  ] LOOP
    EXECUTE pg_catalog.format(
      'CREATE TRIGGER %I_candidate_only BEFORE INSERT ON macsad.%I '
      'FOR EACH ROW EXECUTE FUNCTION macsad.guard_policy_projection_insert()',
      table_name, table_name
    );
  END LOOP;
END
$policy_projection_triggers$;

CREATE TABLE macsad.actor (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  kind macsad.actor_kind NOT NULL,
  display_name text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(display_name)) > 0),
  state macsad.actor_state NOT NULL DEFAULT 'active',
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CHECK (updated_at >= created_at)
);

ALTER TABLE macsad.tool_repository
  ADD CONSTRAINT tool_repository_approver_fk
  FOREIGN KEY (approved_by_actor_id) REFERENCES macsad.actor(id);

ALTER TABLE macsad.tool_repository_revision
  ADD CONSTRAINT tool_repository_revision_operation_sealer_fk
  FOREIGN KEY (operations_sealed_by_actor_id) REFERENCES macsad.actor(id);

CREATE INDEX tool_repository_approver_idx
  ON macsad.tool_repository(approved_by_actor_id)
  WHERE approved_by_actor_id IS NOT NULL;
CREATE INDEX tool_repository_revision_operation_sealer_idx
  ON macsad.tool_repository_revision(operations_sealed_by_actor_id)
  WHERE operations_sealed_by_actor_id IS NOT NULL;

ALTER TABLE macsad.policy_revision
  ADD CONSTRAINT policy_revision_activator_fk
  FOREIGN KEY (activated_by_actor_id) REFERENCES macsad.actor(id);

CREATE INDEX policy_revision_activator_idx
  ON macsad.policy_revision(activated_by_actor_id)
  WHERE activated_by_actor_id IS NOT NULL;

CREATE TABLE macsad.actor_identity (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  issuer text NOT NULL,
  subject text NOT NULL,
  audience text NOT NULL,
  valid_from timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  valid_until timestamptz,
  revoked_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (issuer, subject, audience),
  UNIQUE (id, actor_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (revoked_at IS NULL OR revoked_at >= valid_from),
  CHECK (updated_at >= created_at)
);

CREATE INDEX actor_identity_actor_idx ON macsad.actor_identity(actor_id);

CREATE TABLE macsad.membership (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  policy_revision_id uuid NOT NULL,
  profile_key text NOT NULL,
  profile_digest macsad.sha256_digest NOT NULL,
  supervisor_actor_id uuid REFERENCES macsad.actor(id),
  state macsad.membership_state NOT NULL DEFAULT 'active',
  valid_from timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  valid_until timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, id, profile_key, profile_digest),
  UNIQUE (workspace_id, id, actor_id, policy_revision_id, profile_key, profile_digest),
  FOREIGN KEY (workspace_id, policy_revision_id, profile_key)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key),
  FOREIGN KEY (workspace_id, policy_revision_id, profile_key, profile_digest)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key, profile_digest),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (supervisor_actor_id IS NULL OR supervisor_actor_id <> actor_id),
  CHECK (updated_at >= created_at)
);

CREATE INDEX membership_workspace_actor_idx ON macsad.membership(workspace_id, actor_id);
CREATE INDEX membership_profile_idx ON macsad.membership(policy_revision_id, profile_key);
CREATE INDEX membership_supervisor_idx ON macsad.membership(supervisor_actor_id)
  WHERE supervisor_actor_id IS NOT NULL;

CREATE TABLE macsad.capability_grant (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  capability_code text NOT NULL CHECK (capability_code ~ '^[a-z][a-z0-9._-]*$'),
  constraint_schema_id text,
  constraint_schema_version integer,
  constraint_body macsad.canonical_json,
  constraint_digest macsad.sha256_digest,
  granted_by_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  valid_from timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  valid_until timestamptz,
  revoked_at timestamptz,
  reason text NOT NULL,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  CHECK (
    (constraint_schema_id IS NULL AND constraint_schema_version IS NULL
      AND constraint_body IS NULL AND constraint_digest IS NULL)
    OR
    (constraint_schema_id IS NOT NULL AND constraint_schema_version > 0
      AND constraint_body IS NOT NULL AND constraint_digest IS NOT NULL)
  ),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (revoked_at IS NULL OR revoked_at >= valid_from),
  CHECK (updated_at >= created_at)
);

CREATE INDEX capability_grant_workspace_actor_idx
  ON macsad.capability_grant(workspace_id, actor_id);
CREATE INDEX capability_grant_grantor_idx ON macsad.capability_grant(granted_by_actor_id);

CREATE TABLE macsad.problem_revision (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  research_kind macsad.research_kind NOT NULL,
  prior_revision_id uuid,
  title text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(title)) > 0),
  original_question text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(original_question)) > 0),
  definitions text NOT NULL,
  assumptions text NOT NULL,
  domain_bounds text NOT NULL,
  success_criteria text NOT NULL,
  refutation_criteria text NOT NULL,
  inconclusive_criteria text NOT NULL,
  revision_reason text,
  kind_schema_id text NOT NULL,
  kind_schema_version integer NOT NULL CHECK (kind_schema_version > 0),
  kind_body macsad.canonical_json NOT NULL,
  content_digest macsad.sha256_digest NOT NULL,
  created_by_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, content_digest),
  FOREIGN KEY (workspace_id, prior_revision_id)
    REFERENCES macsad.problem_revision(workspace_id, id)
);

CREATE INDEX problem_revision_prior_idx ON macsad.problem_revision(prior_revision_id);
CREATE INDEX problem_revision_creator_idx ON macsad.problem_revision(created_by_actor_id);

CREATE TABLE macsad.research_case (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  workspace_snapshot_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  problem_revision_id uuid NOT NULL,
  process_key text NOT NULL,
  tool_closure_digest macsad.sha256_digest NOT NULL,
  supersedes_case_id uuid,
  state macsad.case_state NOT NULL DEFAULT 'open',
  control_state macsad.case_control_state NOT NULL DEFAULT 'normal',
  priority smallint NOT NULL DEFAULT 50 CHECK (priority BETWEEN 0 AND 100),
  disposition_family macsad.disposition_family,
  math_disposition macsad.math_disposition,
  cs_disposition macsad.cs_disposition,
  administrative_disposition macsad.administrative_disposition,
  disposition_attestation_id uuid,
  editorial_decision macsad.editorial_decision NOT NULL DEFAULT 'not_reviewed',
  eligibility_attestation_id uuid,
  opened_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  closed_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (problem_revision_id),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, id, problem_revision_id),
  UNIQUE (workspace_id, id, policy_revision_id, process_key),
  UNIQUE (workspace_id, id, workspace_snapshot_id, policy_revision_id, problem_revision_id),
  UNIQUE (workspace_id, id, policy_revision_id, problem_revision_id, process_key),
  FOREIGN KEY (workspace_id, workspace_snapshot_id)
    REFERENCES macsad.workspace_snapshot(workspace_id, id),
  FOREIGN KEY (workspace_id, policy_revision_id)
    REFERENCES macsad.policy_revision(workspace_id, id),
  FOREIGN KEY (workspace_id, problem_revision_id)
    REFERENCES macsad.problem_revision(workspace_id, id),
  FOREIGN KEY (workspace_id, policy_revision_id, process_key)
    REFERENCES macsad.policy_process(workspace_id, policy_revision_id, process_key),
  FOREIGN KEY (workspace_id, supersedes_case_id)
    REFERENCES macsad.research_case(workspace_id, id),
  CHECK (supersedes_case_id IS NULL OR supersedes_case_id <> id),
  CHECK ((state = 'open' AND closed_at IS NULL) OR (state = 'closed' AND closed_at IS NOT NULL)),
  CHECK (
    (state = 'open'
      AND disposition_family IS NULL
      AND math_disposition IS NULL
      AND cs_disposition IS NULL
      AND administrative_disposition IS NULL
      AND disposition_attestation_id IS NULL)
    OR
    (state = 'closed' AND disposition_family = 'mathematics'
      AND math_disposition IS NOT NULL
      AND cs_disposition IS NULL AND administrative_disposition IS NULL
      AND disposition_attestation_id IS NOT NULL)
    OR
    (state = 'closed' AND disposition_family = 'computer_science'
      AND math_disposition IS NULL
      AND cs_disposition IS NOT NULL AND administrative_disposition IS NULL
      AND disposition_attestation_id IS NOT NULL)
    OR
    (state = 'closed' AND disposition_family = 'administrative'
      AND math_disposition IS NULL AND cs_disposition IS NULL
      AND administrative_disposition IS NOT NULL
      AND disposition_attestation_id IS NOT NULL)
  ),
  CHECK (
    (state = 'open' AND editorial_decision = 'not_reviewed' AND eligibility_attestation_id IS NULL)
    OR (state = 'closed' AND editorial_decision IN ('private', 'eligible')
      AND eligibility_attestation_id IS NOT NULL)
  ),
  CHECK (closed_at IS NULL OR closed_at >= opened_at),
  CHECK (updated_at >= created_at)
);

CREATE INDEX research_case_snapshot_idx ON macsad.research_case(workspace_snapshot_id);
CREATE INDEX research_case_policy_idx ON macsad.research_case(policy_revision_id);
CREATE INDEX research_case_supersedes_idx ON macsad.research_case(supersedes_case_id)
  WHERE supersedes_case_id IS NOT NULL;

CREATE FUNCTION macsad.guard_research_case_context()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  problem_kind macsad.research_kind;
BEGIN
  IF TG_OP = 'UPDATE' AND ROW(
      NEW.workspace_id, NEW.workspace_snapshot_id, NEW.policy_revision_id,
      NEW.problem_revision_id, NEW.process_key, NEW.tool_closure_digest, NEW.supersedes_case_id,
      NEW.opened_at, NEW.created_at
    ) IS DISTINCT FROM ROW(
      OLD.workspace_id, OLD.workspace_snapshot_id, OLD.policy_revision_id,
      OLD.problem_revision_id, OLD.process_key, OLD.tool_closure_digest, OLD.supersedes_case_id,
      OLD.opened_at, OLD.created_at
    ) THEN
    RAISE EXCEPTION 'research case frozen context is immutable'
      USING ERRCODE = '55000';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.state = 'closed' AND NEW.state <> OLD.state THEN
    RAISE EXCEPTION 'a closed research case cannot be reopened'
      USING ERRCODE = '23514';
  END IF;

  SELECT p.research_kind INTO STRICT problem_kind
  FROM macsad.problem_revision AS p
  WHERE p.workspace_id = NEW.workspace_id AND p.id = NEW.problem_revision_id;

  IF TG_OP = 'INSERT' AND NOT EXISTS (
    SELECT 1 FROM macsad.policy_revision AS policy
    WHERE policy.id = NEW.policy_revision_id
      AND policy.workspace_id = NEW.workspace_id
      AND policy.workspace_snapshot_id = NEW.workspace_snapshot_id
      AND policy.state = 'active'
      AND policy.validation_result = 'passed'
  ) THEN
    RAISE EXCEPTION 'case requires an active validated policy compiled from its exact workspace snapshot'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.disposition_family = 'mathematics' AND problem_kind <> 'mathematics' THEN
    RAISE EXCEPTION 'mathematics disposition cannot close a computer-science problem'
      USING ERRCODE = '23514';
  END IF;
  IF NEW.disposition_family = 'computer_science' AND problem_kind <> 'computer_science' THEN
    RAISE EXCEPTION 'computer-science disposition cannot close a mathematics problem'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER research_case_guard_context
BEFORE INSERT OR UPDATE ON macsad.research_case
FOR EACH ROW EXECUTE FUNCTION macsad.guard_research_case_context();

CREATE TABLE macsad.research_case_tool_revision (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  research_case_id uuid NOT NULL,
  tool_repository_id uuid NOT NULL,
  tool_repository_revision_id uuid NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  access_mode macsad.tool_access_mode NOT NULL,
  purpose text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(purpose)) > 0),
  scope_schema_id text,
  scope_schema_version integer,
  scope_body macsad.canonical_json,
  scope_digest macsad.sha256_digest,
  pinned_by_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, research_case_id, tool_repository_revision_id),
  UNIQUE (workspace_id, research_case_id, tool_repository_id),
  UNIQUE (workspace_id, research_case_id, ordinal),
  FOREIGN KEY (workspace_id, research_case_id)
    REFERENCES macsad.research_case(workspace_id, id),
  FOREIGN KEY (workspace_id, tool_repository_id, tool_repository_revision_id)
    REFERENCES macsad.tool_repository_revision(workspace_id, tool_repository_id, id),
  CHECK (
    (scope_schema_id IS NULL AND scope_schema_version IS NULL AND scope_body IS NULL AND scope_digest IS NULL)
    OR
    (scope_schema_id IS NOT NULL AND scope_schema_version > 0 AND scope_body IS NOT NULL AND scope_digest IS NOT NULL)
  )
);

CREATE INDEX research_case_tool_revision_revision_idx
  ON macsad.research_case_tool_revision(tool_repository_revision_id);
CREATE INDEX research_case_tool_revision_repository_idx
  ON macsad.research_case_tool_revision(tool_repository_id);
CREATE INDEX research_case_tool_revision_actor_idx
  ON macsad.research_case_tool_revision(pinned_by_actor_id);

CREATE FUNCTION macsad.validate_case_tool_pin()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM macsad.task AS t WHERE t.research_case_id = NEW.research_case_id
  ) THEN
    RAISE EXCEPTION 'case tool closure is frozen once its first task exists'
      USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM macsad.tool_repository AS repository
    JOIN macsad.tool_repository_revision AS revision
      ON revision.tool_repository_id = repository.id
    WHERE repository.id = NEW.tool_repository_id
      AND repository.workspace_id = NEW.workspace_id
      AND repository.state = 'active'
      AND revision.id = NEW.tool_repository_revision_id
      AND revision.preserved_at IS NOT NULL
      AND revision.source_artifact_id IS NOT NULL
      AND (
        NEW.access_mode = 'source_read'
        OR (
          revision.promoted_at IS NOT NULL
          AND revision.promoted_bundle_artifact_id IS NOT NULL
          AND revision.compatibility_evidence_artifact_id IS NOT NULL
          AND revision.operations_sealed_at IS NOT NULL
        )
      )
  ) THEN
    RAISE EXCEPTION 'case tool pin requires an active approved repository and preserved/promoted revision'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER research_case_tool_revision_validate
BEFORE INSERT ON macsad.research_case_tool_revision
FOR EACH ROW EXECUTE FUNCTION macsad.validate_case_tool_pin();

CREATE TABLE macsad.task (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  research_case_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  problem_revision_id uuid NOT NULL,
  process_key text NOT NULL,
  node_key text NOT NULL,
  sequence_no bigint NOT NULL CHECK (sequence_no > 0),
  state macsad.task_state NOT NULL DEFAULT 'offered',
  board_phase macsad.kanban_phase NOT NULL,
  required_profile_key text,
  required_profile_digest macsad.sha256_digest,
  entered_via_policy_transition_id uuid,
  input_closure_digest macsad.sha256_digest,
  output_closure_digest macsad.sha256_digest,
  deadline_at timestamptz,
  opened_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  finished_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (research_case_id, sequence_no),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, research_case_id, id),
  UNIQUE (workspace_id, research_case_id, id, node_key),
  FOREIGN KEY (workspace_id, research_case_id, policy_revision_id, problem_revision_id, process_key)
    REFERENCES macsad.research_case(workspace_id, id, policy_revision_id, problem_revision_id, process_key),
  FOREIGN KEY (workspace_id, policy_revision_id, process_key, node_key)
    REFERENCES macsad.policy_node(workspace_id, policy_revision_id, process_key, node_key),
  FOREIGN KEY (workspace_id, policy_revision_id, process_key, entered_via_policy_transition_id)
    REFERENCES macsad.policy_transition(workspace_id, policy_revision_id, process_key, id),
  FOREIGN KEY (workspace_id, policy_revision_id, required_profile_key)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key),
  FOREIGN KEY (workspace_id, policy_revision_id, required_profile_key, required_profile_digest)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key, profile_digest),
  CHECK ((required_profile_key IS NULL) = (required_profile_digest IS NULL)),
  CHECK ((state IN ('completed', 'cancelled')) = (finished_at IS NOT NULL)),
  CHECK (finished_at IS NULL OR finished_at >= opened_at),
  CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX task_one_live_per_case_uq
  ON macsad.task(research_case_id)
  WHERE state IN ('offered', 'ready', 'running', 'waiting');
CREATE INDEX task_policy_node_idx ON macsad.task(policy_revision_id, process_key, node_key);
CREATE INDEX task_entered_transition_idx ON macsad.task(entered_via_policy_transition_id)
  WHERE entered_via_policy_transition_id IS NOT NULL;

CREATE FUNCTION macsad.validate_task_projection()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  compiled_board_phase macsad.kanban_phase;
  compiled_profile_key text;
BEGIN
  IF TG_OP = 'UPDATE' AND ROW(
      NEW.workspace_id, NEW.research_case_id, NEW.policy_revision_id,
      NEW.problem_revision_id, NEW.process_key, NEW.node_key, NEW.sequence_no,
      NEW.board_phase, NEW.required_profile_key, NEW.required_profile_digest,
      NEW.entered_via_policy_transition_id, NEW.input_closure_digest,
      NEW.opened_at, NEW.created_at
    ) IS DISTINCT FROM ROW(
      OLD.workspace_id, OLD.research_case_id, OLD.policy_revision_id,
      OLD.problem_revision_id, OLD.process_key, OLD.node_key, OLD.sequence_no,
      OLD.board_phase, OLD.required_profile_key, OLD.required_profile_digest,
      OLD.entered_via_policy_transition_id, OLD.input_closure_digest,
      OLD.opened_at, OLD.created_at
    ) THEN
    RAISE EXCEPTION 'task identity and compiled projection are immutable'
      USING ERRCODE = '55000';
  END IF;

  SELECT n.board_phase, n.required_profile_key
    INTO STRICT compiled_board_phase, compiled_profile_key
    FROM macsad.policy_node AS n
    WHERE n.workspace_id = NEW.workspace_id
      AND n.policy_revision_id = NEW.policy_revision_id
      AND n.process_key = NEW.process_key
      AND n.node_key = NEW.node_key;

  IF NEW.board_phase <> compiled_board_phase
      OR NEW.required_profile_key IS DISTINCT FROM compiled_profile_key THEN
    RAISE EXCEPTION 'task board phase or required profile differs from compiled node'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER task_validate_projection
BEFORE INSERT OR UPDATE ON macsad.task
FOR EACH ROW EXECUTE FUNCTION macsad.validate_task_projection();

CREATE TABLE macsad.task_transition (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  research_case_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  process_key text NOT NULL,
  from_task_id uuid NOT NULL,
  to_task_id uuid,
  policy_transition_id uuid NOT NULL,
  decided_by_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  fact_schema_id text NOT NULL,
  fact_schema_version integer NOT NULL CHECK (fact_schema_version > 0),
  fact_snapshot macsad.canonical_json NOT NULL,
  fact_snapshot_digest macsad.sha256_digest NOT NULL,
  decision_code text NOT NULL,
  matched_order integer NOT NULL CHECK (matched_order >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (from_task_id),
  FOREIGN KEY (workspace_id, research_case_id, policy_revision_id, process_key)
    REFERENCES macsad.research_case(workspace_id, id, policy_revision_id, process_key),
  FOREIGN KEY (workspace_id, research_case_id, from_task_id)
    REFERENCES macsad.task(workspace_id, research_case_id, id),
  FOREIGN KEY (workspace_id, research_case_id, to_task_id)
    REFERENCES macsad.task(workspace_id, research_case_id, id),
  FOREIGN KEY (workspace_id, policy_revision_id, process_key, policy_transition_id)
    REFERENCES macsad.policy_transition(workspace_id, policy_revision_id, process_key, id),
  CHECK (to_task_id IS NULL OR to_task_id <> from_task_id)
);

CREATE INDEX task_transition_to_task_idx ON macsad.task_transition(to_task_id)
  WHERE to_task_id IS NOT NULL;
CREATE INDEX task_transition_policy_transition_idx ON macsad.task_transition(policy_transition_id);
CREATE INDEX task_transition_actor_idx ON macsad.task_transition(decided_by_actor_id);

CREATE FUNCTION macsad.validate_task_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  source_node text;
  source_sequence bigint;
  source_state macsad.task_state;
  source_policy_revision_id uuid;
  source_process_key text;
  target_node text;
  target_sequence bigint;
  target_entered_via uuid;
  declared_source text;
  declared_target text;
  declared_order integer;
  declared_code text;
  declared_kind macsad.transition_kind;
BEGIN
  SELECT t.node_key, t.sequence_no, t.state, t.policy_revision_id, t.process_key
    INTO STRICT source_node, source_sequence, source_state,
      source_policy_revision_id, source_process_key
    FROM macsad.task AS t
    WHERE t.workspace_id = NEW.workspace_id AND t.id = NEW.from_task_id;

  SELECT p.source_node_key, p.target_node_key, p.match_order, p.decision_code,
      p.transition_kind
    INTO STRICT declared_source, declared_target, declared_order, declared_code,
      declared_kind
    FROM macsad.policy_transition AS p
    WHERE p.workspace_id = NEW.workspace_id AND p.id = NEW.policy_transition_id;

  IF source_policy_revision_id <> NEW.policy_revision_id
      OR source_process_key <> NEW.process_key
      OR source_node <> declared_source
      OR NEW.matched_order <> declared_order
      OR NEW.decision_code <> declared_code THEN
    RAISE EXCEPTION 'task transition does not match its compiled decision row'
      USING ERRCODE = '23514';
  END IF;

  IF source_state NOT IN ('completed', 'cancelled')
      OR (source_state = 'cancelled') <> (declared_kind = 'cancel') THEN
    RAISE EXCEPTION 'task transition requires a finished source and matching cancellation semantics'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.to_task_id IS NOT NULL THEN
    SELECT t.node_key, t.sequence_no, t.entered_via_policy_transition_id
      INTO STRICT target_node, target_sequence, target_entered_via
      FROM macsad.task AS t
      WHERE t.workspace_id = NEW.workspace_id AND t.id = NEW.to_task_id;
    IF target_node <> declared_target
        OR target_sequence <> source_sequence + 1
        OR target_entered_via IS DISTINCT FROM NEW.policy_transition_id THEN
      RAISE EXCEPTION 'successor task does not match compiled target, sequence, or entering transition'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM macsad.policy_node AS n
      WHERE n.workspace_id = NEW.workspace_id
        AND n.policy_revision_id = NEW.policy_revision_id
        AND n.process_key = NEW.process_key
        AND n.node_key = declared_target
        AND n.node_kind = 'terminal'
    ) THEN
      RAISE EXCEPTION 'a task transition without a successor must target a terminal node'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION macsad.validate_task_path()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  entry_node text;
BEGIN
  IF NEW.sequence_no = 1 THEN
    SELECT process.entry_node_key INTO STRICT entry_node
    FROM macsad.policy_process AS process
    WHERE process.workspace_id = NEW.workspace_id
      AND process.policy_revision_id = NEW.policy_revision_id
      AND process.process_key = NEW.process_key;

    IF NEW.node_key <> entry_node OR NEW.entered_via_policy_transition_id IS NOT NULL THEN
      RAISE EXCEPTION 'the first task must be the compiled process entry node'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    IF NEW.entered_via_policy_transition_id IS NULL OR NOT EXISTS (
      SELECT 1
      FROM macsad.task AS prior
      JOIN macsad.task_transition AS movement
        ON movement.from_task_id = prior.id
       AND movement.to_task_id = NEW.id
      WHERE prior.workspace_id = NEW.workspace_id
        AND prior.research_case_id = NEW.research_case_id
        AND prior.sequence_no = NEW.sequence_no - 1
        AND movement.policy_transition_id = NEW.entered_via_policy_transition_id
    ) THEN
      RAISE EXCEPTION 'a successor task must close the preceding task transition path'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER task_transition_matches_policy_ck
AFTER INSERT ON macsad.task_transition
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW EXECUTE FUNCTION macsad.validate_task_transition();

CREATE CONSTRAINT TRIGGER task_path_closed_ck
AFTER INSERT ON macsad.task
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION macsad.validate_task_path();

CREATE TABLE macsad.thread (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  research_case_id uuid,
  task_id uuid,
  kind macsad.thread_kind NOT NULL,
  state macsad.thread_state NOT NULL DEFAULT 'open',
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, research_case_id)
    REFERENCES macsad.research_case(workspace_id, id),
  FOREIGN KEY (workspace_id, research_case_id, task_id)
    REFERENCES macsad.task(workspace_id, research_case_id, id),
  CHECK (
    (kind = 'workspace_operations' AND research_case_id IS NULL AND task_id IS NULL)
    OR (kind = 'case_primary' AND research_case_id IS NOT NULL AND task_id IS NULL)
    OR (kind = 'task' AND research_case_id IS NOT NULL AND task_id IS NOT NULL)
  ),
  CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX thread_one_workspace_operations_uq
  ON macsad.thread(workspace_id) WHERE kind = 'workspace_operations';
CREATE UNIQUE INDEX thread_one_case_primary_uq
  ON macsad.thread(research_case_id) WHERE kind = 'case_primary';
CREATE UNIQUE INDEX thread_one_per_task_uq
  ON macsad.thread(task_id) WHERE kind = 'task';

CREATE TABLE macsad.message (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  thread_id uuid NOT NULL,
  author_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  task_id uuid,
  reply_to_message_id uuid,
  corrects_message_id uuid,
  format macsad.message_format NOT NULL,
  body text NOT NULL CHECK (pg_catalog.length(body) > 0),
  content_digest macsad.sha256_digest NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, thread_id, id),
  FOREIGN KEY (workspace_id, thread_id)
    REFERENCES macsad.thread(workspace_id, id),
  FOREIGN KEY (workspace_id, task_id)
    REFERENCES macsad.task(workspace_id, id),
  FOREIGN KEY (workspace_id, thread_id, reply_to_message_id)
    REFERENCES macsad.message(workspace_id, thread_id, id),
  FOREIGN KEY (workspace_id, thread_id, corrects_message_id)
    REFERENCES macsad.message(workspace_id, thread_id, id),
  CHECK (reply_to_message_id IS NULL OR reply_to_message_id <> id),
  CHECK (corrects_message_id IS NULL OR corrects_message_id <> id)
);

CREATE INDEX message_thread_created_idx ON macsad.message(thread_id, created_at, id);
CREATE INDEX message_author_idx ON macsad.message(author_actor_id);
CREATE INDEX message_task_idx ON macsad.message(task_id) WHERE task_id IS NOT NULL;
CREATE INDEX message_reply_idx ON macsad.message(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL;
CREATE INDEX message_correction_idx ON macsad.message(corrects_message_id) WHERE corrects_message_id IS NOT NULL;

CREATE FUNCTION macsad.validate_message_context()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  thread_case_id uuid;
  thread_task_id uuid;
  thread_kind_value macsad.thread_kind;
BEGIN
  SELECT t.research_case_id, t.task_id, t.kind
    INTO STRICT thread_case_id, thread_task_id, thread_kind_value
    FROM macsad.thread AS t
    WHERE t.workspace_id = NEW.workspace_id AND t.id = NEW.thread_id;

  IF thread_kind_value = 'workspace_operations' AND NEW.task_id IS NOT NULL THEN
    RAISE EXCEPTION 'workspace operations messages cannot claim task context'
      USING ERRCODE = '23514';
  END IF;
  IF thread_kind_value = 'task' AND NEW.task_id IS DISTINCT FROM thread_task_id THEN
    RAISE EXCEPTION 'task-thread message must use the thread task context'
      USING ERRCODE = '23514';
  END IF;
  IF NEW.task_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM macsad.task AS task_row
    WHERE task_row.workspace_id = NEW.workspace_id
      AND task_row.id = NEW.task_id
      AND task_row.research_case_id = thread_case_id
  ) THEN
    RAISE EXCEPTION 'message task does not belong to the thread case'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER message_validate_context
BEFORE INSERT ON macsad.message
FOR EACH ROW EXECUTE FUNCTION macsad.validate_message_context();

CREATE TABLE macsad.message_mention (
  message_id uuid NOT NULL REFERENCES macsad.message(id),
  actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (message_id, actor_id)
);

CREATE INDEX message_mention_actor_idx ON macsad.message_mention(actor_id, created_at);

CREATE TABLE macsad.task_assignment (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  task_id uuid NOT NULL,
  offered_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  offered_membership_id uuid NOT NULL,
  offered_by_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  policy_revision_id uuid NOT NULL,
  profile_key text NOT NULL,
  profile_digest macsad.sha256_digest NOT NULL,
  prior_assignment_id uuid,
  handoff_thread_id uuid,
  package_digest macsad.sha256_digest NOT NULL,
  state macsad.assignment_state NOT NULL DEFAULT 'offered',
  offered_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  accepted_at timestamptz,
  rejected_at timestamptz,
  expires_at timestamptz,
  released_at timestamptz,
  reason text,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, task_id, id),
  UNIQUE (
    workspace_id, task_id, id, offered_actor_id,
    policy_revision_id, profile_key, profile_digest
  ),
  FOREIGN KEY (workspace_id, task_id)
    REFERENCES macsad.task(workspace_id, id),
  FOREIGN KEY (workspace_id, policy_revision_id, profile_key)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key),
  FOREIGN KEY (workspace_id, policy_revision_id, profile_key, profile_digest)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key, profile_digest),
  FOREIGN KEY (
    workspace_id, offered_membership_id, offered_actor_id,
    policy_revision_id, profile_key, profile_digest
  ) REFERENCES macsad.membership(
    workspace_id, id, actor_id, policy_revision_id, profile_key, profile_digest
  ),
  FOREIGN KEY (workspace_id, prior_assignment_id)
    REFERENCES macsad.task_assignment(workspace_id, id),
  FOREIGN KEY (workspace_id, handoff_thread_id)
    REFERENCES macsad.thread(workspace_id, id),
  CHECK (prior_assignment_id IS NULL OR prior_assignment_id <> id),
  CHECK ((state = 'accepted') = (accepted_at IS NOT NULL)),
  CHECK ((state = 'rejected') = (rejected_at IS NOT NULL)),
  CHECK ((state = 'released') = (released_at IS NOT NULL)),
  CHECK (expires_at IS NULL OR expires_at > offered_at),
  CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX task_assignment_one_accepted_uq
  ON macsad.task_assignment(task_id) WHERE state = 'accepted';
CREATE INDEX task_assignment_offered_actor_idx ON macsad.task_assignment(offered_actor_id, state);
CREATE INDEX task_assignment_membership_idx ON macsad.task_assignment(offered_membership_id);
CREATE INDEX task_assignment_offerer_idx ON macsad.task_assignment(offered_by_actor_id);
CREATE INDEX task_assignment_prior_idx ON macsad.task_assignment(prior_assignment_id)
  WHERE prior_assignment_id IS NOT NULL;
CREATE INDEX task_assignment_thread_idx ON macsad.task_assignment(handoff_thread_id)
  WHERE handoff_thread_id IS NOT NULL;

CREATE FUNCTION macsad.guard_task_assignment_content()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND ROW(
      NEW.workspace_id, NEW.task_id, NEW.offered_actor_id, NEW.offered_membership_id,
      NEW.offered_by_actor_id,
      NEW.policy_revision_id, NEW.profile_key, NEW.profile_digest,
      NEW.prior_assignment_id, NEW.handoff_thread_id, NEW.package_digest,
      NEW.offered_at, NEW.created_at
    ) IS DISTINCT FROM ROW(
      OLD.workspace_id, OLD.task_id, OLD.offered_actor_id, OLD.offered_membership_id,
      OLD.offered_by_actor_id,
      OLD.policy_revision_id, OLD.profile_key, OLD.profile_digest,
      OLD.prior_assignment_id, OLD.handoff_thread_id, OLD.package_digest,
      OLD.offered_at, OLD.created_at
    ) THEN
    RAISE EXCEPTION 'assignment offer and handoff package are immutable'
      USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM macsad.task AS t
    WHERE t.workspace_id = NEW.workspace_id
      AND t.id = NEW.task_id
      AND t.policy_revision_id = NEW.policy_revision_id
      AND t.required_profile_key = NEW.profile_key
      AND t.required_profile_digest = NEW.profile_digest
  ) THEN
    RAISE EXCEPTION 'assignment profile does not satisfy the task node requirement'
      USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM macsad.membership AS member
    WHERE member.id = NEW.offered_membership_id
      AND member.workspace_id = NEW.workspace_id
      AND member.actor_id = NEW.offered_actor_id
      AND member.policy_revision_id = NEW.policy_revision_id
      AND member.profile_key = NEW.profile_key
      AND member.profile_digest = NEW.profile_digest
      AND member.state = 'active'
      AND member.valid_from <= pg_catalog.clock_timestamp()
      AND (member.valid_until IS NULL OR member.valid_until > pg_catalog.clock_timestamp())
  ) THEN
    RAISE EXCEPTION 'assignment requires a currently active matching workspace membership'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER task_assignment_guard_content
BEFORE INSERT OR UPDATE ON macsad.task_assignment
FOR EACH ROW EXECUTE FUNCTION macsad.guard_task_assignment_content();

CREATE TABLE macsad.execution (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  research_case_id uuid NOT NULL,
  task_id uuid NOT NULL,
  task_assignment_id uuid NOT NULL,
  performing_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  worker_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  workspace_snapshot_id uuid NOT NULL,
  policy_revision_id uuid NOT NULL,
  problem_revision_id uuid NOT NULL,
  profile_key text NOT NULL,
  profile_digest macsad.sha256_digest NOT NULL,
  request_schema_id text NOT NULL,
  request_schema_version integer NOT NULL CHECK (request_schema_version > 0),
  request_body macsad.canonical_json NOT NULL,
  request_digest macsad.sha256_digest NOT NULL,
  environment_digest macsad.sha256_digest NOT NULL,
  resource_limit_schema_id text NOT NULL,
  resource_limit_schema_version integer NOT NULL CHECK (resource_limit_schema_version > 0),
  resource_limit_body macsad.canonical_json NOT NULL,
  resource_limit_digest macsad.sha256_digest NOT NULL,
  deterministic_seed bigint,
  idempotency_key text NOT NULL,
  state macsad.execution_state NOT NULL DEFAULT 'pending',
  lease_owner_actor_id uuid REFERENCES macsad.actor(id),
  fencing_token bigint CHECK (fencing_token > 0),
  claimed_at timestamptz,
  heartbeat_at timestamptz,
  lease_expires_at timestamptz,
  cancel_requested_at timestamptz,
  cancel_reason text,
  transport_outcome macsad.transport_outcome,
  termination_outcome macsad.termination_outcome,
  claim_outcome macsad.claim_outcome,
  result_envelope_digest macsad.sha256_digest,
  started_at timestamptz,
  finished_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, research_case_id, id),
  UNIQUE (workspace_id, research_case_id, id, task_id),
  UNIQUE (workspace_id, id, problem_revision_id),
  UNIQUE (workspace_id, idempotency_key),
  FOREIGN KEY (workspace_id, research_case_id, task_id)
    REFERENCES macsad.task(workspace_id, research_case_id, id),
  FOREIGN KEY (
    workspace_id, task_id, task_assignment_id, performing_actor_id,
    policy_revision_id, profile_key, profile_digest
  ) REFERENCES macsad.task_assignment(
    workspace_id, task_id, id, offered_actor_id,
    policy_revision_id, profile_key, profile_digest
  ),
  FOREIGN KEY (workspace_id, workspace_snapshot_id)
    REFERENCES macsad.workspace_snapshot(workspace_id, id),
  FOREIGN KEY (
    workspace_id, research_case_id, workspace_snapshot_id,
    policy_revision_id, problem_revision_id
  ) REFERENCES macsad.research_case(
    workspace_id, id, workspace_snapshot_id, policy_revision_id, problem_revision_id
  ),
  FOREIGN KEY (workspace_id, policy_revision_id)
    REFERENCES macsad.policy_revision(workspace_id, id),
  FOREIGN KEY (workspace_id, problem_revision_id)
    REFERENCES macsad.problem_revision(workspace_id, id),
  FOREIGN KEY (workspace_id, policy_revision_id, profile_key)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key),
  FOREIGN KEY (workspace_id, policy_revision_id, profile_key, profile_digest)
    REFERENCES macsad.policy_member_profile(workspace_id, policy_revision_id, profile_key, profile_digest),
  CHECK (
    (state IN ('leased', 'running', 'cancel_requested')
      AND lease_owner_actor_id IS NOT NULL AND fencing_token IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR state IN ('pending', 'completed', 'failed', 'expired')
  ),
  CHECK ((state IN ('completed', 'failed', 'expired')) = (finished_at IS NOT NULL)),
  CHECK (heartbeat_at IS NULL OR claimed_at IS NOT NULL),
  CHECK (lease_expires_at IS NULL OR claimed_at IS NOT NULL),
  CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at),
  CHECK (updated_at >= created_at)
);

CREATE INDEX execution_task_idx ON macsad.execution(task_id);
CREATE INDEX execution_assignment_idx ON macsad.execution(task_assignment_id);
CREATE INDEX execution_performer_idx ON macsad.execution(performing_actor_id);
CREATE INDEX execution_worker_idx ON macsad.execution(worker_actor_id);
CREATE INDEX execution_lease_owner_idx ON macsad.execution(lease_owner_actor_id)
  WHERE lease_owner_actor_id IS NOT NULL;
CREATE INDEX execution_state_lease_idx ON macsad.execution(state, lease_expires_at)
  WHERE state IN ('leased', 'running', 'cancel_requested');

CREATE FUNCTION macsad.guard_execution_content()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT EXISTS (
    SELECT 1 FROM macsad.task_assignment AS a
    WHERE a.id = NEW.task_assignment_id AND a.state = 'accepted'
  ) THEN
    RAISE EXCEPTION 'execution requires an accepted task assignment'
      USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'INSERT' AND NOT EXISTS (
    SELECT 1 FROM macsad.actor AS a
    WHERE a.id = NEW.worker_actor_id AND a.kind = 'service' AND a.state = 'active'
  ) THEN
    RAISE EXCEPTION 'execution worker must be an active service actor'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'UPDATE' AND ROW(
      NEW.workspace_id, NEW.research_case_id, NEW.task_id, NEW.task_assignment_id,
      NEW.performing_actor_id, NEW.worker_actor_id, NEW.workspace_snapshot_id,
      NEW.policy_revision_id, NEW.problem_revision_id, NEW.profile_key,
      NEW.profile_digest, NEW.request_schema_id, NEW.request_schema_version,
      NEW.request_body, NEW.request_digest, NEW.environment_digest,
      NEW.resource_limit_schema_id, NEW.resource_limit_schema_version,
      NEW.resource_limit_body, NEW.resource_limit_digest, NEW.deterministic_seed,
      NEW.idempotency_key, NEW.created_at
    ) IS DISTINCT FROM ROW(
      OLD.workspace_id, OLD.research_case_id, OLD.task_id, OLD.task_assignment_id,
      OLD.performing_actor_id, OLD.worker_actor_id, OLD.workspace_snapshot_id,
      OLD.policy_revision_id, OLD.problem_revision_id, OLD.profile_key,
      OLD.profile_digest, OLD.request_schema_id, OLD.request_schema_version,
      OLD.request_body, OLD.request_digest, OLD.environment_digest,
      OLD.resource_limit_schema_id, OLD.resource_limit_schema_version,
      OLD.resource_limit_body, OLD.resource_limit_digest, OLD.deterministic_seed,
      OLD.idempotency_key, OLD.created_at
    ) THEN
    RAISE EXCEPTION 'execution specification and frozen context are immutable'
      USING ERRCODE = '55000';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.state = 'pending' AND NEW.state = 'leased'
      AND (NEW.fencing_token <> 1 OR NEW.lease_owner_actor_id IS NULL
        OR NEW.claimed_at IS NULL OR NEW.lease_expires_at IS NULL) THEN
    RAISE EXCEPTION 'first lease acquisition requires fencing token 1 and a complete lease'
      USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.state IN ('leased', 'running', 'cancel_requested')
      AND ROW(NEW.lease_owner_actor_id, NEW.fencing_token)
        IS DISTINCT FROM ROW(OLD.lease_owner_actor_id, OLD.fencing_token) THEN
    RAISE EXCEPTION 'execution lease owner and fencing token are immutable after acquisition'
      USING ERRCODE = '55000';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.heartbeat_at IS NOT NULL
      AND OLD.heartbeat_at IS NOT NULL AND NEW.heartbeat_at < OLD.heartbeat_at THEN
    RAISE EXCEPTION 'execution heartbeat cannot move backward'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER execution_guard_content
BEFORE INSERT OR UPDATE ON macsad.execution
FOR EACH ROW EXECUTE FUNCTION macsad.guard_execution_content();

CREATE TABLE macsad.blob (
  digest macsad.sha256_digest PRIMARY KEY,
  byte_length bigint NOT NULL CHECK (byte_length >= 0),
  media_type text NOT NULL,
  content_encoding text,
  compression text,
  storage_provider text NOT NULL CHECK (storage_provider ~ '^[a-z][a-z0-9._-]*$'),
  storage_locator text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(storage_locator)) > 0),
  storage_class text NOT NULL,
  provider_checksum text,
  stored_at timestamptz NOT NULL,
  verified_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (storage_provider, storage_locator),
  CHECK (verified_at >= stored_at)
);

CREATE TABLE macsad.artifact (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  blob_digest macsad.sha256_digest NOT NULL REFERENCES macsad.blob(digest),
  artifact_kind text NOT NULL CHECK (artifact_kind ~ '^[a-z][a-z0-9._-]*$'),
  schema_id text,
  schema_version integer,
  classification macsad.artifact_classification NOT NULL,
  secret_scan_result macsad.scan_result NOT NULL,
  quarantined boolean NOT NULL DEFAULT false,
  producing_actor_id uuid REFERENCES macsad.actor(id),
  producing_execution_id uuid,
  original_source text,
  observed_at timestamptz,
  license_expression text,
  attribution text,
  redistribution_allowed boolean NOT NULL DEFAULT false,
  export_decision text,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, producing_execution_id)
    REFERENCES macsad.execution(workspace_id, id),
  CHECK ((schema_id IS NULL) = (schema_version IS NULL)),
  CHECK (schema_version IS NULL OR schema_version > 0),
  CHECK (NOT redistribution_allowed OR (classification IN ('public_candidate', 'public')
    AND secret_scan_result = 'passed' AND NOT quarantined))
);

CREATE INDEX artifact_blob_idx ON macsad.artifact(blob_digest);
CREATE INDEX artifact_producer_idx ON macsad.artifact(producing_actor_id)
  WHERE producing_actor_id IS NOT NULL;
CREATE INDEX artifact_execution_idx ON macsad.artifact(producing_execution_id)
  WHERE producing_execution_id IS NOT NULL;

ALTER TABLE macsad.workspace_snapshot
  ADD CONSTRAINT workspace_snapshot_source_artifact_fk
  FOREIGN KEY (workspace_id, source_artifact_id)
  REFERENCES macsad.artifact(workspace_id, id);

ALTER TABLE macsad.tool_repository_revision
  ADD CONSTRAINT tool_repository_revision_source_artifact_fk
  FOREIGN KEY (workspace_id, source_artifact_id)
  REFERENCES macsad.artifact(workspace_id, id),
  ADD CONSTRAINT tool_repository_revision_bundle_artifact_fk
  FOREIGN KEY (workspace_id, promoted_bundle_artifact_id)
  REFERENCES macsad.artifact(workspace_id, id),
  ADD CONSTRAINT tool_repository_revision_executable_artifact_fk
  FOREIGN KEY (workspace_id, promoted_executable_artifact_id)
  REFERENCES macsad.artifact(workspace_id, id),
  ADD CONSTRAINT tool_repository_revision_compatibility_artifact_fk
  FOREIGN KEY (workspace_id, compatibility_evidence_artifact_id)
  REFERENCES macsad.artifact(workspace_id, id);

ALTER TABLE macsad.policy_revision
  ADD CONSTRAINT policy_revision_semantic_diff_artifact_fk
  FOREIGN KEY (workspace_id, semantic_diff_artifact_id)
  REFERENCES macsad.artifact(workspace_id, id);

CREATE INDEX workspace_snapshot_source_artifact_idx ON macsad.workspace_snapshot(source_artifact_id)
  WHERE source_artifact_id IS NOT NULL;
CREATE INDEX tool_repository_revision_source_artifact_idx
  ON macsad.tool_repository_revision(source_artifact_id) WHERE source_artifact_id IS NOT NULL;
CREATE INDEX tool_repository_revision_bundle_artifact_idx
  ON macsad.tool_repository_revision(promoted_bundle_artifact_id)
  WHERE promoted_bundle_artifact_id IS NOT NULL;
CREATE INDEX tool_repository_revision_executable_artifact_idx
  ON macsad.tool_repository_revision(promoted_executable_artifact_id)
  WHERE promoted_executable_artifact_id IS NOT NULL;
CREATE INDEX tool_repository_revision_compatibility_artifact_idx
  ON macsad.tool_repository_revision(compatibility_evidence_artifact_id)
  WHERE compatibility_evidence_artifact_id IS NOT NULL;
CREATE INDEX policy_revision_semantic_diff_artifact_idx
  ON macsad.policy_revision(semantic_diff_artifact_id) WHERE semantic_diff_artifact_id IS NOT NULL;

CREATE TABLE macsad.execution_artifact (
  workspace_id uuid NOT NULL,
  execution_id uuid NOT NULL,
  artifact_id uuid NOT NULL,
  role macsad.execution_artifact_role NOT NULL,
  ordinal integer NOT NULL DEFAULT 0 CHECK (ordinal >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (execution_id, artifact_id, role),
  UNIQUE (execution_id, role, ordinal),
  FOREIGN KEY (workspace_id, execution_id)
    REFERENCES macsad.execution(workspace_id, id),
  FOREIGN KEY (workspace_id, artifact_id)
    REFERENCES macsad.artifact(workspace_id, id)
);

CREATE INDEX execution_artifact_artifact_idx ON macsad.execution_artifact(artifact_id);

CREATE TABLE macsad.execution_tool_use (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  research_case_id uuid NOT NULL,
  execution_id uuid NOT NULL,
  policy_node_tool_operation_id uuid NOT NULL,
  tool_repository_revision_id uuid NOT NULL,
  tool_operation_manifest_id uuid NOT NULL,
  invocation_sequence integer NOT NULL CHECK (invocation_sequence > 0),
  request_artifact_id uuid,
  response_artifact_id uuid,
  request_digest macsad.sha256_digest NOT NULL,
  response_digest macsad.sha256_digest,
  state macsad.tool_use_state NOT NULL DEFAULT 'pending',
  transport_outcome macsad.transport_outcome,
  termination_outcome macsad.termination_outcome,
  started_at timestamptz,
  finished_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, execution_id, id),
  UNIQUE (execution_id, policy_node_tool_operation_id, invocation_sequence),
  FOREIGN KEY (workspace_id, research_case_id, execution_id)
    REFERENCES macsad.execution(workspace_id, research_case_id, id),
  FOREIGN KEY (workspace_id, policy_node_tool_operation_id)
    REFERENCES macsad.policy_node_tool_operation(workspace_id, id),
  FOREIGN KEY (workspace_id, research_case_id, tool_repository_revision_id)
    REFERENCES macsad.research_case_tool_revision(workspace_id, research_case_id, tool_repository_revision_id),
  FOREIGN KEY (workspace_id, tool_repository_revision_id, tool_operation_manifest_id)
    REFERENCES macsad.tool_operation_manifest(workspace_id, tool_repository_revision_id, id),
  FOREIGN KEY (workspace_id, request_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  FOREIGN KEY (workspace_id, response_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  CHECK ((state IN ('completed', 'failed', 'cancelled')) = (finished_at IS NOT NULL)),
  CHECK ((response_artifact_id IS NULL) = (response_digest IS NULL)),
  CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at),
  CHECK (updated_at >= created_at)
);

CREATE INDEX execution_tool_use_execution_idx ON macsad.execution_tool_use(execution_id);
CREATE INDEX execution_tool_use_operation_idx ON macsad.execution_tool_use(tool_operation_manifest_id);
CREATE INDEX execution_tool_use_policy_mapping_idx
  ON macsad.execution_tool_use(policy_node_tool_operation_id);
CREATE INDEX execution_tool_use_request_artifact_idx
  ON macsad.execution_tool_use(request_artifact_id) WHERE request_artifact_id IS NOT NULL;
CREATE INDEX execution_tool_use_response_artifact_idx
  ON macsad.execution_tool_use(response_artifact_id) WHERE response_artifact_id IS NOT NULL;

CREATE FUNCTION macsad.guard_execution_tool_use_content()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF ROW(
      NEW.workspace_id, NEW.research_case_id, NEW.execution_id,
      NEW.policy_node_tool_operation_id, NEW.tool_repository_revision_id,
      NEW.tool_operation_manifest_id, NEW.invocation_sequence, NEW.request_artifact_id,
      NEW.request_digest, NEW.created_at
    ) IS DISTINCT FROM ROW(
      OLD.workspace_id, OLD.research_case_id, OLD.execution_id,
      OLD.policy_node_tool_operation_id, OLD.tool_repository_revision_id,
      OLD.tool_operation_manifest_id, OLD.invocation_sequence, OLD.request_artifact_id,
      OLD.request_digest, OLD.created_at
    ) THEN
    RAISE EXCEPTION 'execution tool-use request and admitted operation are immutable'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER execution_tool_use_guard_content
BEFORE UPDATE ON macsad.execution_tool_use
FOR EACH ROW EXECUTE FUNCTION macsad.guard_execution_tool_use_content();

CREATE FUNCTION macsad.validate_execution_tool_use()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM macsad.execution AS e
    JOIN macsad.task AS t ON t.id = e.task_id
    JOIN macsad.research_case_tool_revision AS pin
      ON pin.workspace_id = NEW.workspace_id
     AND pin.research_case_id = NEW.research_case_id
     AND pin.tool_repository_revision_id = NEW.tool_repository_revision_id
     AND pin.access_mode = 'operation_invoke'
    JOIN macsad.policy_node_tool_operation AS p
      ON p.id = NEW.policy_node_tool_operation_id
     AND p.workspace_id = NEW.workspace_id
    WHERE e.id = NEW.execution_id
      AND e.workspace_id = NEW.workspace_id
      AND p.policy_revision_id = e.policy_revision_id
      AND p.process_key = t.process_key
      AND p.node_key = t.node_key
      AND p.tool_operation_manifest_id = NEW.tool_operation_manifest_id
      AND NEW.invocation_sequence <= p.max_invocations
  ) THEN
    RAISE EXCEPTION 'tool use is not admitted by the execution task node'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER execution_tool_use_policy_ck
AFTER INSERT OR UPDATE OF policy_node_tool_operation_id, tool_operation_manifest_id
ON macsad.execution_tool_use
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW EXECUTE FUNCTION macsad.validate_execution_tool_use();

CREATE TABLE macsad.claim (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  problem_revision_id uuid NOT NULL,
  kind macsad.claim_kind NOT NULL,
  canonical_text text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(canonical_text)) > 0),
  payload_schema_id text,
  payload_schema_version integer,
  payload_body macsad.canonical_json,
  scope_bounds text NOT NULL,
  content_digest macsad.sha256_digest NOT NULL,
  proposed_by_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  source_execution_id uuid,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, id, problem_revision_id),
  UNIQUE (workspace_id, problem_revision_id, content_digest),
  FOREIGN KEY (workspace_id, problem_revision_id)
    REFERENCES macsad.problem_revision(workspace_id, id),
  FOREIGN KEY (workspace_id, source_execution_id, problem_revision_id)
    REFERENCES macsad.execution(workspace_id, id, problem_revision_id),
  CHECK (
    (payload_schema_id IS NULL AND payload_schema_version IS NULL AND payload_body IS NULL)
    OR (payload_schema_id IS NOT NULL AND payload_schema_version > 0 AND payload_body IS NOT NULL)
  )
);

CREATE INDEX claim_problem_idx ON macsad.claim(problem_revision_id);
CREATE INDEX claim_proposer_idx ON macsad.claim(proposed_by_actor_id);
CREATE INDEX claim_source_execution_idx ON macsad.claim(source_execution_id)
  WHERE source_execution_id IS NOT NULL;

CREATE TABLE macsad.attestation (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  problem_revision_id uuid NOT NULL,
  claim_id uuid,
  execution_id uuid,
  issuer_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  issuer_membership_id uuid,
  issuer_profile_key text,
  issuer_profile_digest macsad.sha256_digest,
  kind macsad.attestation_kind NOT NULL,
  authority_class macsad.authority_class NOT NULL,
  value_schema_id text NOT NULL,
  value_schema_version integer NOT NULL CHECK (value_schema_version > 0),
  value_body macsad.canonical_json NOT NULL,
  value_digest macsad.sha256_digest NOT NULL,
  method_digest macsad.sha256_digest,
  outcome_code text NOT NULL CHECK (outcome_code ~ '^[a-z][a-z0-9._-]*$'),
  limitations text NOT NULL DEFAULT '',
  producer_independent boolean NOT NULL DEFAULT false,
  environment_independent boolean NOT NULL DEFAULT false,
  method_independent boolean NOT NULL DEFAULT false,
  data_independent boolean NOT NULL DEFAULT false,
  supersedes_attestation_id uuid,
  content_digest macsad.sha256_digest NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, id, problem_revision_id),
  UNIQUE (workspace_id, problem_revision_id, content_digest),
  FOREIGN KEY (workspace_id, problem_revision_id)
    REFERENCES macsad.problem_revision(workspace_id, id),
  FOREIGN KEY (workspace_id, claim_id, problem_revision_id)
    REFERENCES macsad.claim(workspace_id, id, problem_revision_id),
  FOREIGN KEY (workspace_id, execution_id, problem_revision_id)
    REFERENCES macsad.execution(workspace_id, id, problem_revision_id),
  FOREIGN KEY (workspace_id, issuer_membership_id)
    REFERENCES macsad.membership(workspace_id, id),
  FOREIGN KEY (workspace_id, issuer_membership_id, issuer_profile_key, issuer_profile_digest)
    REFERENCES macsad.membership(workspace_id, id, profile_key, profile_digest),
  FOREIGN KEY (workspace_id, supersedes_attestation_id)
    REFERENCES macsad.attestation(workspace_id, id),
  CHECK ((issuer_membership_id IS NULL) = (issuer_profile_key IS NULL)),
  CHECK ((issuer_profile_key IS NULL) = (issuer_profile_digest IS NULL)),
  CHECK (supersedes_attestation_id IS NULL OR supersedes_attestation_id <> id),
  CHECK (
    (kind IN ('agent_assertion') AND authority_class = 'agent_asserted')
    OR (kind = 'tool_observation' AND authority_class = 'tool_observed')
    OR (kind IN ('checker_result', 'counterexample_validation', 'reproduction')
      AND authority_class IN ('checker_attested', 'human_decided'))
    OR (kind IN ('semantic_review', 'methodological_review', 'human_disposition', 'editorial_decision')
      AND authority_class = 'human_decided')
  )
);

CREATE INDEX attestation_problem_idx ON macsad.attestation(problem_revision_id);
CREATE INDEX attestation_claim_idx ON macsad.attestation(claim_id) WHERE claim_id IS NOT NULL;
CREATE INDEX attestation_execution_idx ON macsad.attestation(execution_id) WHERE execution_id IS NOT NULL;
CREATE INDEX attestation_issuer_idx ON macsad.attestation(issuer_actor_id);
CREATE INDEX attestation_membership_idx ON macsad.attestation(issuer_membership_id)
  WHERE issuer_membership_id IS NOT NULL;
CREATE INDEX attestation_supersedes_idx ON macsad.attestation(supersedes_attestation_id)
  WHERE supersedes_attestation_id IS NOT NULL;

CREATE FUNCTION macsad.validate_attestation_issuer()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF NEW.issuer_membership_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM macsad.membership AS membership
    WHERE membership.id = NEW.issuer_membership_id
      AND membership.workspace_id = NEW.workspace_id
      AND membership.actor_id = NEW.issuer_actor_id
      AND membership.profile_key = NEW.issuer_profile_key
      AND membership.profile_digest = NEW.issuer_profile_digest
      AND membership.state = 'active'
      AND membership.valid_from <= NEW.created_at
      AND (membership.valid_until IS NULL OR membership.valid_until > NEW.created_at)
  ) THEN
    RAISE EXCEPTION 'attestation issuer and profile must match the named active membership'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.authority_class = 'human_decided' AND (
      NEW.issuer_membership_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM macsad.actor AS actor
        WHERE actor.id = NEW.issuer_actor_id
          AND actor.kind = 'human'
          AND actor.state = 'active'
      )
    ) THEN
    RAISE EXCEPTION 'human-decided authority requires an active human issuer and matching membership'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER attestation_validate_issuer
BEFORE INSERT ON macsad.attestation
FOR EACH ROW EXECUTE FUNCTION macsad.validate_attestation_issuer();

CREATE TABLE macsad.attestation_artifact (
  workspace_id uuid NOT NULL,
  attestation_id uuid NOT NULL,
  artifact_id uuid NOT NULL,
  support_role text NOT NULL CHECK (support_role ~ '^[a-z][a-z0-9._-]*$'),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (attestation_id, artifact_id, support_role),
  FOREIGN KEY (workspace_id, attestation_id)
    REFERENCES macsad.attestation(workspace_id, id),
  FOREIGN KEY (workspace_id, artifact_id)
    REFERENCES macsad.artifact(workspace_id, id)
);

CREATE INDEX attestation_artifact_artifact_idx ON macsad.attestation_artifact(artifact_id);

ALTER TABLE macsad.research_case
  ADD CONSTRAINT research_case_disposition_attestation_fk
  FOREIGN KEY (workspace_id, disposition_attestation_id, problem_revision_id)
  REFERENCES macsad.attestation(workspace_id, id, problem_revision_id),
  ADD CONSTRAINT research_case_eligibility_attestation_fk
  FOREIGN KEY (workspace_id, eligibility_attestation_id, problem_revision_id)
  REFERENCES macsad.attestation(workspace_id, id, problem_revision_id);

CREATE INDEX research_case_disposition_attestation_idx
  ON macsad.research_case(disposition_attestation_id)
  WHERE disposition_attestation_id IS NOT NULL;
CREATE INDEX research_case_eligibility_attestation_idx
  ON macsad.research_case(eligibility_attestation_id)
  WHERE eligibility_attestation_id IS NOT NULL;

CREATE FUNCTION macsad.validate_case_attestations()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF NEW.disposition_attestation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM macsad.attestation AS a
    WHERE a.id = NEW.disposition_attestation_id
      AND a.workspace_id = NEW.workspace_id
      AND a.problem_revision_id = NEW.problem_revision_id
      AND a.kind = 'human_disposition'
      AND a.authority_class = 'human_decided'
      AND a.outcome_code = COALESCE(
        NEW.math_disposition::text,
        NEW.cs_disposition::text,
        NEW.administrative_disposition::text
      )
  ) THEN
    RAISE EXCEPTION 'case disposition requires a human_disposition attestation'
      USING ERRCODE = '23514';
  END IF;
  IF NEW.eligibility_attestation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM macsad.attestation AS a
    WHERE a.id = NEW.eligibility_attestation_id
      AND a.workspace_id = NEW.workspace_id
      AND a.problem_revision_id = NEW.problem_revision_id
      AND a.kind = 'editorial_decision'
      AND a.authority_class = 'human_decided'
      AND a.outcome_code = NEW.editorial_decision::text
  ) THEN
    RAISE EXCEPTION 'editorial status requires an editorial_decision attestation'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER research_case_attestations_ck
AFTER INSERT OR UPDATE OF disposition_attestation_id, eligibility_attestation_id
ON macsad.research_case
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW EXECUTE FUNCTION macsad.validate_case_attestations();

CREATE TABLE macsad.budget_account (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  research_case_id uuid,
  resource_kind macsad.budget_resource_kind NOT NULL,
  unit_code text NOT NULL CHECK (unit_code ~ '^[A-Za-z][A-Za-z0-9._/-]*$'),
  currency_code macsad.iso_currency_code,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  initial_spending_limit macsad.nonnegative_quantity NOT NULL,
  spending_limit macsad.nonnegative_quantity NOT NULL,
  reserved_quantity macsad.nonnegative_quantity NOT NULL DEFAULT 0,
  spent_quantity macsad.nonnegative_quantity NOT NULL DEFAULT 0,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE NULLS NOT DISTINCT (
    workspace_id, research_case_id, resource_kind, unit_code, currency_code,
    period_start, period_end
  ),
  FOREIGN KEY (workspace_id, research_case_id)
    REFERENCES macsad.research_case(workspace_id, id),
  CHECK (period_end > period_start),
  CHECK ((resource_kind = 'currency') = (currency_code IS NOT NULL)),
  CHECK (version > 0 OR spending_limit = initial_spending_limit),
  CHECK (updated_at >= created_at)
);

CREATE INDEX budget_account_case_idx ON macsad.budget_account(research_case_id)
  WHERE research_case_id IS NOT NULL;
CREATE INDEX budget_account_period_idx ON macsad.budget_account(workspace_id, period_end);

CREATE FUNCTION macsad.validate_budget_account_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF NEW.version <> 0
      OR NEW.spending_limit <> NEW.initial_spending_limit
      OR NEW.reserved_quantity <> 0
      OR NEW.spent_quantity <> 0 THEN
    RAISE EXCEPTION 'a budget account must begin at version zero with an unreconciled-free opening balance'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER budget_account_validate_insert
BEFORE INSERT ON macsad.budget_account
FOR EACH ROW EXECUTE FUNCTION macsad.validate_budget_account_insert();

CREATE TABLE macsad.model_call (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  research_case_id uuid NOT NULL,
  task_id uuid NOT NULL,
  execution_id uuid NOT NULL,
  execution_tool_use_id uuid NOT NULL,
  requested_by_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  controller_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  budget_account_id uuid NOT NULL,
  idempotency_key text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(idempotency_key)) > 0),
  provider_service text NOT NULL DEFAULT 'openrouter' CHECK (provider_service = 'openrouter'),
  requested_model text NOT NULL,
  resolved_model text,
  resolved_provider text,
  service_tier text,
  router_strategy text,
  data_region text,
  byok boolean NOT NULL DEFAULT false,
  estimated_cost macsad.exact_money NOT NULL,
  reserved_cost macsad.exact_money NOT NULL,
  cost_currency macsad.iso_currency_code NOT NULL,
  price_snapshot_digest macsad.sha256_digest NOT NULL,
  routing_policy_digest macsad.sha256_digest NOT NULL,
  max_output_tokens bigint NOT NULL CHECK (max_output_tokens > 0),
  stream_requested boolean NOT NULL,
  credential_reference text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(credential_reference)) > 0),
  credential_epoch bigint NOT NULL CHECK (credential_epoch > 0),
  prompt_artifact_id uuid NOT NULL,
  context_artifact_id uuid,
  prompt_digest macsad.sha256_digest NOT NULL,
  context_digest macsad.sha256_digest NOT NULL,
  parameters_digest macsad.sha256_digest NOT NULL,
  openrouter_request_id text,
  openrouter_generation_id text,
  upstream_id text,
  request_schema_id text NOT NULL,
  request_schema_version integer NOT NULL CHECK (request_schema_version > 0),
  sanitized_request macsad.canonical_json NOT NULL,
  request_digest macsad.sha256_digest NOT NULL,
  response_artifact_id uuid,
  state macsad.model_call_state NOT NULL DEFAULT 'reserved',
  http_status smallint CHECK (http_status BETWEEN 100 AND 599),
  error_code text,
  submitted_at timestamptz,
  response_completed_at timestamptz,
  usage_reconciled_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, idempotency_key),
  FOREIGN KEY (workspace_id, research_case_id, task_id)
    REFERENCES macsad.task(workspace_id, research_case_id, id),
  FOREIGN KEY (workspace_id, research_case_id, execution_id, task_id)
    REFERENCES macsad.execution(workspace_id, research_case_id, id, task_id),
  FOREIGN KEY (workspace_id, execution_id, execution_tool_use_id)
    REFERENCES macsad.execution_tool_use(workspace_id, execution_id, id),
  FOREIGN KEY (workspace_id, budget_account_id)
    REFERENCES macsad.budget_account(workspace_id, id),
  FOREIGN KEY (workspace_id, response_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  FOREIGN KEY (workspace_id, prompt_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  FOREIGN KEY (workspace_id, context_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  CHECK (estimated_cost <= reserved_cost),
  CHECK ((state = 'reserved') = (submitted_at IS NULL) OR state = 'cancelled'),
  CHECK ((state IN ('succeeded', 'failed', 'usage_pending', 'reconciled', 'cancelled'))
    = (response_completed_at IS NOT NULL)),
  CHECK ((state = 'reconciled') = (usage_reconciled_at IS NOT NULL)),
  CHECK (response_completed_at IS NULL OR submitted_at IS NULL OR response_completed_at >= submitted_at),
  CHECK (usage_reconciled_at IS NULL OR usage_reconciled_at >= response_completed_at),
  CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX model_call_openrouter_generation_uq
  ON macsad.model_call(openrouter_generation_id)
  WHERE openrouter_generation_id IS NOT NULL;
CREATE UNIQUE INDEX model_call_openrouter_request_uq
  ON macsad.model_call(openrouter_request_id)
  WHERE openrouter_request_id IS NOT NULL;
CREATE UNIQUE INDEX model_call_upstream_uq
  ON macsad.model_call(resolved_provider, upstream_id)
  WHERE resolved_provider IS NOT NULL AND upstream_id IS NOT NULL;
CREATE INDEX model_call_case_idx ON macsad.model_call(research_case_id);
CREATE INDEX model_call_task_idx ON macsad.model_call(task_id);
CREATE INDEX model_call_execution_idx ON macsad.model_call(execution_id)
  ;
CREATE INDEX model_call_tool_use_idx ON macsad.model_call(execution_tool_use_id);
CREATE INDEX model_call_actor_idx ON macsad.model_call(requested_by_actor_id);
CREATE INDEX model_call_controller_idx ON macsad.model_call(controller_actor_id);
CREATE INDEX model_call_budget_idx ON macsad.model_call(budget_account_id);
CREATE INDEX model_call_response_artifact_idx ON macsad.model_call(response_artifact_id)
  WHERE response_artifact_id IS NOT NULL;
CREATE INDEX model_call_prompt_artifact_idx ON macsad.model_call(prompt_artifact_id);
CREATE INDEX model_call_context_artifact_idx ON macsad.model_call(context_artifact_id)
  WHERE context_artifact_id IS NOT NULL;

CREATE FUNCTION macsad.guard_model_call_request()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF ROW(
      NEW.workspace_id, NEW.research_case_id, NEW.task_id, NEW.execution_id,
      NEW.execution_tool_use_id, NEW.requested_by_actor_id, NEW.controller_actor_id,
      NEW.budget_account_id, NEW.idempotency_key, NEW.provider_service,
      NEW.requested_model, NEW.service_tier, NEW.router_strategy, NEW.data_region,
      NEW.byok, NEW.estimated_cost, NEW.reserved_cost, NEW.cost_currency,
      NEW.price_snapshot_digest, NEW.routing_policy_digest, NEW.max_output_tokens,
      NEW.stream_requested, NEW.credential_reference, NEW.credential_epoch,
      NEW.prompt_artifact_id, NEW.context_artifact_id, NEW.prompt_digest,
      NEW.context_digest, NEW.parameters_digest,
      NEW.request_schema_id, NEW.request_schema_version,
      NEW.sanitized_request, NEW.request_digest, NEW.created_at
    ) IS DISTINCT FROM ROW(
      OLD.workspace_id, OLD.research_case_id, OLD.task_id, OLD.execution_id,
      OLD.execution_tool_use_id, OLD.requested_by_actor_id, OLD.controller_actor_id,
      OLD.budget_account_id, OLD.idempotency_key, OLD.provider_service,
      OLD.requested_model, OLD.service_tier, OLD.router_strategy, OLD.data_region,
      OLD.byok, OLD.estimated_cost, OLD.reserved_cost, OLD.cost_currency,
      OLD.price_snapshot_digest, OLD.routing_policy_digest, OLD.max_output_tokens,
      OLD.stream_requested, OLD.credential_reference, OLD.credential_epoch,
      OLD.prompt_artifact_id, OLD.context_artifact_id, OLD.prompt_digest,
      OLD.context_digest, OLD.parameters_digest,
      OLD.request_schema_id, OLD.request_schema_version,
      OLD.sanitized_request, OLD.request_digest, OLD.created_at
    ) THEN
    RAISE EXCEPTION 'model-call request, routing policy, and budget scope are immutable'
      USING ERRCODE = '55000';
  END IF;
  IF (OLD.openrouter_request_id IS NOT NULL
        AND NEW.openrouter_request_id IS DISTINCT FROM OLD.openrouter_request_id)
      OR (OLD.openrouter_generation_id IS NOT NULL
        AND NEW.openrouter_generation_id IS DISTINCT FROM OLD.openrouter_generation_id)
      OR (OLD.upstream_id IS NOT NULL AND NEW.upstream_id IS DISTINCT FROM OLD.upstream_id)
      OR (OLD.resolved_model IS NOT NULL
        AND NEW.resolved_model IS DISTINCT FROM OLD.resolved_model)
      OR (OLD.resolved_provider IS NOT NULL
        AND NEW.resolved_provider IS DISTINCT FROM OLD.resolved_provider) THEN
    RAISE EXCEPTION 'observed provider identities are write-once'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER model_call_guard_request
BEFORE UPDATE ON macsad.model_call
FOR EACH ROW EXECUTE FUNCTION macsad.guard_model_call_request();

CREATE TABLE macsad.model_usage_observation (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  model_call_id uuid NOT NULL,
  observation_sequence integer NOT NULL CHECK (observation_sequence > 0),
  supersedes_observation_id uuid,
  source macsad.usage_observation_source NOT NULL,
  is_final boolean NOT NULL DEFAULT false,
  openrouter_generation_id text NOT NULL,
  resolved_model text NOT NULL,
  resolved_provider text NOT NULL,
  prompt_tokens bigint CHECK (prompt_tokens >= 0),
  completion_tokens bigint CHECK (completion_tokens >= 0),
  total_tokens bigint CHECK (total_tokens >= 0),
  reasoning_tokens bigint CHECK (reasoning_tokens >= 0),
  cache_read_tokens bigint CHECK (cache_read_tokens >= 0),
  cache_write_tokens bigint CHECK (cache_write_tokens >= 0),
  audio_input_tokens bigint CHECK (audio_input_tokens >= 0),
  audio_output_tokens bigint CHECK (audio_output_tokens >= 0),
  image_count bigint CHECK (image_count >= 0),
  media_count bigint CHECK (media_count >= 0),
  web_search_count bigint CHECK (web_search_count >= 0),
  billed_amount macsad.exact_money,
  billed_currency macsad.iso_currency_code,
  billed_credits macsad.exact_money,
  upstream_cost_amount macsad.exact_money,
  upstream_cost_currency macsad.iso_currency_code,
  usage_schema_id text NOT NULL,
  usage_schema_version integer NOT NULL CHECK (usage_schema_version > 0),
  sanitized_usage macsad.canonical_json NOT NULL,
  usage_digest macsad.sha256_digest NOT NULL,
  observed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, model_call_id, id),
  UNIQUE (model_call_id, observation_sequence),
  UNIQUE (model_call_id, usage_digest),
  FOREIGN KEY (workspace_id, model_call_id)
    REFERENCES macsad.model_call(workspace_id, id),
  FOREIGN KEY (workspace_id, model_call_id, supersedes_observation_id)
    REFERENCES macsad.model_usage_observation(workspace_id, model_call_id, id),
  CHECK ((observation_sequence = 1) = (supersedes_observation_id IS NULL)),
  CHECK ((billed_amount IS NULL) = (billed_currency IS NULL)),
  CHECK ((upstream_cost_amount IS NULL) = (upstream_cost_currency IS NULL)),
  CHECK (observed_at <= created_at)
);

CREATE UNIQUE INDEX model_usage_observation_one_successor_uq
  ON macsad.model_usage_observation(supersedes_observation_id)
  WHERE supersedes_observation_id IS NOT NULL;
CREATE INDEX model_usage_observation_call_latest_idx
  ON macsad.model_usage_observation(model_call_id, observation_sequence DESC);

CREATE FUNCTION macsad.validate_model_usage_observation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  call_generation_id text;
  call_model text;
  call_provider text;
  call_state macsad.model_call_state;
  prior_sequence integer;
BEGIN
  SELECT c.openrouter_generation_id, c.resolved_model, c.resolved_provider, c.state
    INTO STRICT call_generation_id, call_model, call_provider, call_state
    FROM macsad.model_call AS c
    WHERE c.workspace_id = NEW.workspace_id AND c.id = NEW.model_call_id;

  IF ROW(NEW.openrouter_generation_id, NEW.resolved_model, NEW.resolved_provider)
      IS DISTINCT FROM ROW(call_generation_id, call_model, call_provider) THEN
    RAISE EXCEPTION 'usage observation generation/model/provider differs from model call closure'
      USING ERRCODE = '23514';
  END IF;
  IF call_state = 'reconciled' THEN
    RAISE EXCEPTION 'reopen a reconciled model call to usage_pending before appending a correction'
      USING ERRCODE = '55000';
  END IF;
  IF NEW.supersedes_observation_id IS NOT NULL THEN
    SELECT u.observation_sequence INTO STRICT prior_sequence
    FROM macsad.model_usage_observation AS u
    WHERE u.id = NEW.supersedes_observation_id;
    IF NEW.observation_sequence <> prior_sequence + 1 THEN
      RAISE EXCEPTION 'usage observation must directly supersede the preceding sequence'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER model_usage_observation_validate
BEFORE INSERT ON macsad.model_usage_observation
FOR EACH ROW EXECUTE FUNCTION macsad.validate_model_usage_observation();

CREATE TABLE macsad.budget_entry (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  budget_account_id uuid NOT NULL,
  execution_id uuid,
  model_call_id uuid,
  model_usage_observation_id uuid,
  kind macsad.budget_entry_kind NOT NULL,
  quantity numeric(30, 12) NOT NULL,
  reservation_released_quantity macsad.nonnegative_quantity NOT NULL DEFAULT 0,
  related_reservation_entry_id uuid,
  idempotency_key text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(idempotency_key)) > 0),
  request_digest macsad.sha256_digest NOT NULL,
  actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  reason text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(reason)) > 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (budget_account_id, idempotency_key),
  FOREIGN KEY (workspace_id, budget_account_id)
    REFERENCES macsad.budget_account(workspace_id, id),
  FOREIGN KEY (workspace_id, execution_id)
    REFERENCES macsad.execution(workspace_id, id),
  FOREIGN KEY (workspace_id, model_call_id)
    REFERENCES macsad.model_call(workspace_id, id),
  FOREIGN KEY (workspace_id, model_usage_observation_id)
    REFERENCES macsad.model_usage_observation(workspace_id, id),
  FOREIGN KEY (workspace_id, related_reservation_entry_id)
    REFERENCES macsad.budget_entry(workspace_id, id),
  CHECK (
    (kind = 'reserve' AND quantity > 0 AND reservation_released_quantity = 0
      AND related_reservation_entry_id IS NULL AND model_usage_observation_id IS NULL)
    OR
    (kind = 'commit' AND quantity >= 0
      AND ((related_reservation_entry_id IS NULL AND reservation_released_quantity = 0)
        OR (related_reservation_entry_id IS NOT NULL AND reservation_released_quantity > 0)))
    OR
    (kind = 'release' AND quantity > 0 AND reservation_released_quantity = quantity
      AND related_reservation_entry_id IS NOT NULL AND model_usage_observation_id IS NULL)
    OR
    (kind = 'spend_adjustment' AND quantity <> 0 AND reservation_released_quantity = 0
      AND related_reservation_entry_id IS NULL)
    OR
    (kind = 'usage_reconciliation' AND quantity = 0 AND reservation_released_quantity = 0
      AND related_reservation_entry_id IS NULL AND model_usage_observation_id IS NOT NULL
      AND model_call_id IS NOT NULL)
    OR
    (kind = 'limit_adjustment' AND quantity <> 0 AND reservation_released_quantity = 0
      AND related_reservation_entry_id IS NULL AND model_usage_observation_id IS NULL)
  ),
  CHECK (model_usage_observation_id IS NULL
    OR kind IN ('commit', 'spend_adjustment', 'usage_reconciliation'))
);

CREATE UNIQUE INDEX budget_entry_one_settlement_uq
  ON macsad.budget_entry(related_reservation_entry_id)
  WHERE related_reservation_entry_id IS NOT NULL;
CREATE INDEX budget_entry_account_created_idx
  ON macsad.budget_entry(budget_account_id, created_at, id);
CREATE INDEX budget_entry_execution_idx ON macsad.budget_entry(execution_id)
  WHERE execution_id IS NOT NULL;
CREATE INDEX budget_entry_model_call_idx ON macsad.budget_entry(model_call_id)
  WHERE model_call_id IS NOT NULL;
CREATE UNIQUE INDEX budget_entry_one_model_reservation_uq
  ON macsad.budget_entry(model_call_id)
  WHERE model_call_id IS NOT NULL AND kind = 'reserve';
CREATE UNIQUE INDEX budget_entry_usage_observation_uq
  ON macsad.budget_entry(model_usage_observation_id)
  WHERE model_usage_observation_id IS NOT NULL;
CREATE INDEX budget_entry_actor_idx ON macsad.budget_entry(actor_id);

CREATE FUNCTION macsad.record_budget_entry(
  p_budget_account_id uuid,
  p_kind macsad.budget_entry_kind,
  p_quantity numeric,
  p_idempotency_key text,
  p_request_digest macsad.sha256_digest,
  p_actor_id uuid,
  p_execution_id uuid DEFAULT NULL,
  p_model_call_id uuid DEFAULT NULL,
  p_model_usage_observation_id uuid DEFAULT NULL,
  p_related_reservation_entry_id uuid DEFAULT NULL,
  p_reason text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  account_row macsad.budget_account%ROWTYPE;
  existing_row macsad.budget_entry%ROWTYPE;
  reservation_row macsad.budget_entry%ROWTYPE;
  released_quantity numeric(30, 12) := 0;
  entry_id uuid := pg_catalog.gen_random_uuid();
BEGIN
  IF p_idempotency_key IS NULL OR pg_catalog.length(pg_catalog.btrim(p_idempotency_key)) = 0 THEN
    RAISE EXCEPTION 'budget idempotency key is required' USING ERRCODE = '22023';
  END IF;
  IF p_quantity IS NULL THEN
    RAISE EXCEPTION 'budget quantity is required' USING ERRCODE = '22023';
  END IF;
  IF p_request_digest IS NULL THEN
    RAISE EXCEPTION 'budget request digest is required' USING ERRCODE = '22023';
  END IF;
  IF p_reason IS NULL OR pg_catalog.length(pg_catalog.btrim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'budget entry reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO STRICT account_row
    FROM macsad.budget_account
    WHERE id = p_budget_account_id
    FOR UPDATE;

  IF p_kind = 'reserve' AND NOT (
      pg_catalog.clock_timestamp() >= account_row.period_start
      AND pg_catalog.clock_timestamp() < account_row.period_end
    ) THEN
    RAISE EXCEPTION 'budget reservations require an active account period'
      USING ERRCODE = '23514';
  END IF;

  IF p_execution_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM macsad.execution AS e
    WHERE e.id = p_execution_id AND e.workspace_id = account_row.workspace_id
  ) THEN
    RAISE EXCEPTION 'execution is outside the budget account workspace'
      USING ERRCODE = '23514';
  END IF;
  IF p_model_call_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM macsad.model_call AS c
    WHERE c.id = p_model_call_id
      AND c.workspace_id = account_row.workspace_id
      AND c.budget_account_id = account_row.id
      AND (p_kind <> 'reserve' OR (c.reserved_cost = p_quantity AND c.state = 'reserved'))
  ) THEN
    RAISE EXCEPTION 'model call is not charged to this budget account'
      USING ERRCODE = '23514';
  END IF;
  IF p_model_usage_observation_id IS NOT NULL AND (
      p_model_call_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM macsad.model_usage_observation AS u
        WHERE u.id = p_model_usage_observation_id
          AND u.workspace_id = account_row.workspace_id
          AND u.model_call_id = p_model_call_id
      )
    ) THEN
    RAISE EXCEPTION 'usage observation does not belong to the charged model call'
      USING ERRCODE = '23514';
  END IF;
  IF p_kind IN ('commit', 'spend_adjustment', 'usage_reconciliation')
      AND p_model_call_id IS NOT NULL AND (
      p_model_usage_observation_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM macsad.model_usage_observation AS u
        WHERE u.id = p_model_usage_observation_id AND u.is_final
      )
    ) THEN
    RAISE EXCEPTION 'model cost commit requires its final usage observation'
      USING ERRCODE = '23514';
  END IF;
  IF p_kind = 'commit' AND p_model_call_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM macsad.model_usage_observation AS usage
    WHERE usage.id = p_model_usage_observation_id
      AND usage.billed_currency = account_row.currency_code
      AND usage.billed_amount = p_quantity
  ) THEN
    RAISE EXCEPTION 'model commit must equal the final observed billed amount and currency'
      USING ERRCODE = '23514';
  END IF;
  IF p_kind = 'commit' AND p_model_call_id IS NOT NULL
      AND p_related_reservation_entry_id IS NULL THEN
    RAISE EXCEPTION 'a model-cost commit must settle that model call reservation'
      USING ERRCODE = '23514';
  END IF;
  IF p_kind = 'spend_adjustment' AND p_model_call_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM macsad.model_usage_observation AS corrected
    JOIN macsad.model_usage_observation AS prior
      ON prior.id = corrected.supersedes_observation_id
    WHERE corrected.id = p_model_usage_observation_id
      AND corrected.billed_currency = account_row.currency_code
      AND prior.billed_currency = corrected.billed_currency
      AND corrected.billed_amount - prior.billed_amount = p_quantity
  ) THEN
    RAISE EXCEPTION 'model spend adjustment must equal the superseding billed-cost delta'
      USING ERRCODE = '23514';
  END IF;
  IF p_kind = 'usage_reconciliation' AND (
      p_quantity <> 0 OR p_model_call_id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM macsad.model_usage_observation AS corrected
        JOIN macsad.model_usage_observation AS prior
          ON prior.id = corrected.supersedes_observation_id
        WHERE corrected.id = p_model_usage_observation_id
          AND corrected.billed_currency IS NOT DISTINCT FROM prior.billed_currency
          AND corrected.billed_amount IS NOT DISTINCT FROM prior.billed_amount
      )
    ) THEN
    RAISE EXCEPTION 'zero-delta usage reconciliation requires a cost-equivalent superseding observation'
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO existing_row
    FROM macsad.budget_entry
    WHERE budget_account_id = p_budget_account_id
      AND idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF existing_row.request_digest = p_request_digest THEN
      RETURN existing_row.id;
    END IF;
    RAISE EXCEPTION 'budget idempotency key was reused with different content'
      USING ERRCODE = '23505';
  END IF;

  IF p_kind = 'reserve' THEN
    IF p_quantity <= 0 OR p_related_reservation_entry_id IS NOT NULL
      OR p_model_usage_observation_id IS NOT NULL THEN
      RAISE EXCEPTION 'invalid reserve entry' USING ERRCODE = '22023';
    END IF;
    IF account_row.spent_quantity + account_row.reserved_quantity + p_quantity
        > account_row.spending_limit THEN
      RAISE EXCEPTION 'budget reservation exceeds remaining limit'
        USING ERRCODE = 'P0001';
    END IF;
    UPDATE macsad.budget_account
      SET reserved_quantity = reserved_quantity + p_quantity,
          version = version + 1
      WHERE id = p_budget_account_id;

  ELSIF p_kind IN ('commit', 'release') THEN
    IF p_kind = 'commit' AND p_quantity < 0 THEN
      RAISE EXCEPTION 'commit quantity cannot be negative' USING ERRCODE = '22023';
    END IF;
    IF p_kind = 'release' AND (p_quantity <= 0 OR p_related_reservation_entry_id IS NULL) THEN
      RAISE EXCEPTION 'release requires a positive quantity and reservation'
        USING ERRCODE = '22023';
    END IF;

    IF p_related_reservation_entry_id IS NOT NULL THEN
      SELECT * INTO STRICT reservation_row
        FROM macsad.budget_entry
        WHERE id = p_related_reservation_entry_id
          AND budget_account_id = p_budget_account_id
          AND kind = 'reserve'
        FOR SHARE;
      IF EXISTS (
        SELECT 1 FROM macsad.budget_entry
        WHERE related_reservation_entry_id = p_related_reservation_entry_id
      ) THEN
        RAISE EXCEPTION 'reservation has already been settled' USING ERRCODE = '23505';
      END IF;
      IF reservation_row.model_call_id IS DISTINCT FROM p_model_call_id
          OR reservation_row.execution_id IS DISTINCT FROM p_execution_id THEN
        RAISE EXCEPTION 'settlement scope differs from the reserved model call or execution'
          USING ERRCODE = '23514';
      END IF;
      released_quantity := reservation_row.quantity;
      IF account_row.reserved_quantity < released_quantity THEN
        RAISE EXCEPTION 'budget reserved projection is inconsistent with its ledger'
          USING ERRCODE = '23514';
      END IF;
    ELSIF p_kind = 'release' THEN
      RAISE EXCEPTION 'release requires a reservation' USING ERRCODE = '22023';
    END IF;

    IF p_kind = 'release' AND p_quantity <> released_quantity THEN
      RAISE EXCEPTION 'release quantity must equal the original reservation'
        USING ERRCODE = '22023';
    END IF;

    IF p_kind = 'commit' THEN
      -- Intentionally no spending-limit check here. External usage is a fact:
      -- it must be recorded even when it exceeds its reservation or limit.
      UPDATE macsad.budget_account
        SET reserved_quantity = reserved_quantity - released_quantity,
            spent_quantity = spent_quantity + p_quantity,
            version = version + 1
        WHERE id = p_budget_account_id;
    ELSE
      UPDATE macsad.budget_account
        SET reserved_quantity = reserved_quantity - released_quantity,
            version = version + 1
        WHERE id = p_budget_account_id;
    END IF;

  ELSIF p_kind = 'spend_adjustment' THEN
    IF p_quantity = 0 OR p_related_reservation_entry_id IS NOT NULL THEN
      RAISE EXCEPTION 'invalid spend adjustment' USING ERRCODE = '22023';
    END IF;
    IF account_row.spent_quantity + p_quantity < 0 THEN
      RAISE EXCEPTION 'spend adjustment cannot make recorded spend negative'
        USING ERRCODE = '22023';
    END IF;
    UPDATE macsad.budget_account
      SET spent_quantity = spent_quantity + p_quantity,
          version = version + 1
      WHERE id = p_budget_account_id;

  ELSIF p_kind = 'usage_reconciliation' THEN
    IF p_quantity <> 0 OR p_related_reservation_entry_id IS NOT NULL
      OR p_model_usage_observation_id IS NULL OR p_model_call_id IS NULL THEN
      RAISE EXCEPTION 'invalid zero-delta usage reconciliation' USING ERRCODE = '22023';
    END IF;
    UPDATE macsad.budget_account
      SET version = version + 1
      WHERE id = p_budget_account_id;

  ELSIF p_kind = 'limit_adjustment' THEN
    IF p_quantity = 0 OR p_related_reservation_entry_id IS NOT NULL
      OR p_model_usage_observation_id IS NOT NULL THEN
      RAISE EXCEPTION 'invalid limit adjustment' USING ERRCODE = '22023';
    END IF;
    IF account_row.spending_limit + p_quantity < 0 THEN
      RAISE EXCEPTION 'budget limit cannot become negative' USING ERRCODE = '22023';
    END IF;
    UPDATE macsad.budget_account
      SET spending_limit = spending_limit + p_quantity,
          version = version + 1
      WHERE id = p_budget_account_id;
  ELSE
    RAISE EXCEPTION 'unsupported budget entry kind' USING ERRCODE = '22023';
  END IF;

  INSERT INTO macsad.budget_entry (
    id, workspace_id, budget_account_id, execution_id, model_call_id,
    model_usage_observation_id, kind, quantity, reservation_released_quantity,
    related_reservation_entry_id, idempotency_key, request_digest, actor_id, reason
  ) VALUES (
    entry_id, account_row.workspace_id, p_budget_account_id, p_execution_id, p_model_call_id,
    p_model_usage_observation_id, p_kind, p_quantity, released_quantity,
    p_related_reservation_entry_id, p_idempotency_key, p_request_digest, p_actor_id, p_reason
  );

  RETURN entry_id;
END;
$$;

CREATE FUNCTION macsad.validate_model_call_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  latest_usage_id uuid;
  latest_usage_is_final boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM macsad.actor AS controller
    WHERE controller.id = NEW.controller_actor_id
      AND controller.kind = 'service'
      AND controller.state = 'active'
  ) THEN
    RAISE EXCEPTION 'model call controller must be an active service actor'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM macsad.budget_account AS a
    WHERE a.id = NEW.budget_account_id
      AND a.workspace_id = NEW.workspace_id
      AND a.resource_kind = 'currency'
      AND a.currency_code = NEW.cost_currency
      AND (a.research_case_id IS NULL OR a.research_case_id = NEW.research_case_id)
  ) THEN
    RAISE EXCEPTION 'model call cost must use a matching case or workspace currency budget'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM macsad.execution_tool_use AS u
    JOIN macsad.tool_operation_manifest AS m ON m.id = u.tool_operation_manifest_id
    WHERE u.id = NEW.execution_tool_use_id
      AND u.workspace_id = NEW.workspace_id
      AND u.execution_id = NEW.execution_id
      AND m.effect_class = 'model_call'
  ) THEN
    RAISE EXCEPTION 'model call must be admitted by a model_call tool operation'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.state IN ('succeeded', 'reconciled') THEN
    SELECT u.id, u.is_final INTO latest_usage_id, latest_usage_is_final
    FROM macsad.model_usage_observation AS u
    WHERE u.model_call_id = NEW.id
    ORDER BY u.observation_sequence DESC
    LIMIT 1;
    IF latest_usage_id IS NULL OR NOT latest_usage_is_final THEN
      RAISE EXCEPTION 'successful model call requires a final usage observation'
        USING ERRCODE = '23514';
    END IF;
    IF NEW.state = 'reconciled' AND NOT EXISTS (
      SELECT 1 FROM macsad.budget_entry AS e
      WHERE e.model_call_id = NEW.id
        AND e.model_usage_observation_id = latest_usage_id
        AND e.kind IN ('commit', 'spend_adjustment', 'usage_reconciliation')
    ) THEN
      RAISE EXCEPTION 'reconciled model call requires a ledger entry for latest usage'
        USING ERRCODE = '23514';
    END IF;
    IF NEW.state = 'reconciled' AND NOT EXISTS (
      SELECT 1
      FROM macsad.budget_entry AS reservation
      JOIN macsad.budget_entry AS settlement
        ON settlement.related_reservation_entry_id = reservation.id
       AND settlement.kind = 'commit'
       AND settlement.model_call_id = NEW.id
      WHERE reservation.model_call_id = NEW.id
        AND reservation.budget_account_id = NEW.budget_account_id
        AND reservation.kind = 'reserve'
    ) THEN
      RAISE EXCEPTION 'reconciled model call requires its exact reservation to be committed'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  IF TG_OP = 'UPDATE'
      AND OLD.state = 'reserved'
      AND NEW.state = 'submitted'
      AND NOT EXISTS (
        SELECT 1
        FROM macsad.budget_entry AS reservation
        WHERE reservation.model_call_id = NEW.id
          AND reservation.budget_account_id = NEW.budget_account_id
          AND reservation.kind = 'reserve'
          AND reservation.quantity = NEW.reserved_cost
          AND NOT EXISTS (
            SELECT 1 FROM macsad.budget_entry AS settlement
            WHERE settlement.related_reservation_entry_id = reservation.id
          )
      ) THEN
    RAISE EXCEPTION 'model call cannot be submitted without its open exact reservation'
      USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.state <> OLD.state AND NOT (
    (OLD.state = 'reserved' AND NEW.state IN ('submitted', 'cancelled'))
    OR (OLD.state = 'submitted' AND NEW.state IN ('streaming', 'succeeded', 'usage_pending', 'failed', 'cancelled'))
    OR (OLD.state = 'streaming' AND NEW.state IN ('succeeded', 'usage_pending', 'failed', 'cancelled'))
    OR (OLD.state = 'usage_pending' AND NEW.state IN ('succeeded', 'reconciled', 'failed'))
    OR (OLD.state = 'succeeded' AND NEW.state IN ('usage_pending', 'reconciled'))
    OR (OLD.state = 'reconciled' AND NEW.state = 'usage_pending')
  ) THEN
    RAISE EXCEPTION 'invalid model-call state transition from % to %', OLD.state, NEW.state
      USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.state = 'reconciled' AND NEW.state = 'reconciled' THEN
    RAISE EXCEPTION 'reconciled model call is immutable until explicitly reopened to usage_pending'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER model_call_validate_scope
BEFORE INSERT OR UPDATE ON macsad.model_call
FOR EACH ROW EXECUTE FUNCTION macsad.validate_model_call_scope();

CREATE TABLE macsad.publication_dossier (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  research_case_id uuid NOT NULL,
  problem_revision_id uuid NOT NULL,
  claim_id uuid NOT NULL,
  dossier_artifact_id uuid NOT NULL,
  closure_schema_id text NOT NULL,
  closure_schema_version integer NOT NULL CHECK (closure_schema_version > 0),
  closure_body macsad.canonical_json NOT NULL,
  closure_digest macsad.sha256_digest NOT NULL,
  created_by_actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (
    workspace_id, id, research_case_id, problem_revision_id,
    claim_id, dossier_artifact_id
  ),
  UNIQUE (research_case_id, claim_id, closure_digest),
  FOREIGN KEY (workspace_id, research_case_id, problem_revision_id)
    REFERENCES macsad.research_case(workspace_id, id, problem_revision_id),
  FOREIGN KEY (workspace_id, claim_id, problem_revision_id)
    REFERENCES macsad.claim(workspace_id, id, problem_revision_id),
  FOREIGN KEY (workspace_id, dossier_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id)
);

CREATE INDEX publication_dossier_case_idx ON macsad.publication_dossier(research_case_id);
CREATE INDEX publication_dossier_claim_idx ON macsad.publication_dossier(claim_id);
CREATE INDEX publication_dossier_artifact_idx ON macsad.publication_dossier(dossier_artifact_id);

CREATE FUNCTION macsad.validate_publication_dossier()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM macsad.research_case AS research_case
    JOIN macsad.artifact AS artifact
      ON artifact.id = NEW.dossier_artifact_id
     AND artifact.workspace_id = NEW.workspace_id
    WHERE research_case.id = NEW.research_case_id
      AND research_case.workspace_id = NEW.workspace_id
      AND research_case.problem_revision_id = NEW.problem_revision_id
      AND research_case.state = 'closed'
      AND research_case.editorial_decision = 'eligible'
      AND artifact.classification IN ('public_candidate', 'public')
      AND artifact.secret_scan_result = 'passed'
      AND NOT artifact.quarantined
      AND artifact.redistribution_allowed
  ) THEN
    RAISE EXCEPTION 'publication dossier requires an eligible closed case and public-safe artifact'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER publication_dossier_validate
BEFORE INSERT ON macsad.publication_dossier
FOR EACH ROW EXECUTE FUNCTION macsad.validate_publication_dossier();

CREATE TABLE macsad.publication_batch (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  policy_revision_id uuid NOT NULL,
  batch_sequence bigint CHECK (batch_sequence > 0),
  corrects_batch_id uuid,
  state macsad.publication_state NOT NULL DEFAULT 'draft',
  generator_artifact_id uuid,
  toolchain_artifact_id uuid,
  generator_revision_digest macsad.sha256_digest,
  platform_revision_digest macsad.sha256_digest,
  toolchain_closure_digest macsad.sha256_digest,
  evidence_closure_digest macsad.sha256_digest,
  artifact_closure_digest macsad.sha256_digest,
  audit_head_event_id uuid,
  audit_head_sequence_no bigint CHECK (audit_head_sequence_no > 0),
  audit_head_event_hash macsad.sha256_digest,
  manifest_artifact_id uuid,
  manifest_digest macsad.sha256_digest,
  signature bytea,
  sealed_by_actor_id uuid REFERENCES macsad.actor(id),
  previewed_at timestamptz,
  sealed_at timestamptz,
  published_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, policy_revision_id)
    REFERENCES macsad.policy_revision(workspace_id, id),
  FOREIGN KEY (workspace_id, corrects_batch_id)
    REFERENCES macsad.publication_batch(workspace_id, id),
  FOREIGN KEY (workspace_id, manifest_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  FOREIGN KEY (workspace_id, generator_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  FOREIGN KEY (workspace_id, toolchain_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  CHECK (corrects_batch_id IS NULL OR corrects_batch_id <> id),
  CHECK (
    state = 'draft'
    OR (
      generator_artifact_id IS NOT NULL AND toolchain_artifact_id IS NOT NULL
      AND generator_revision_digest IS NOT NULL AND platform_revision_digest IS NOT NULL
      AND toolchain_closure_digest IS NOT NULL AND evidence_closure_digest IS NOT NULL
      AND artifact_closure_digest IS NOT NULL AND audit_head_event_id IS NOT NULL
      AND audit_head_sequence_no IS NOT NULL AND audit_head_event_hash IS NOT NULL
    )
  ),
  CHECK (
    (state = 'draft'
      AND batch_sequence IS NULL
      AND previewed_at IS NULL AND sealed_at IS NULL AND published_at IS NULL
      AND manifest_artifact_id IS NULL AND manifest_digest IS NULL
      AND signature IS NULL AND sealed_by_actor_id IS NULL)
    OR
    (state = 'previewed'
      AND batch_sequence IS NOT NULL
      AND previewed_at IS NOT NULL AND sealed_at IS NULL AND published_at IS NULL
      AND manifest_artifact_id IS NULL AND manifest_digest IS NULL
      AND signature IS NULL AND sealed_by_actor_id IS NULL)
    OR
    (state = 'sealed'
      AND batch_sequence IS NOT NULL
      AND previewed_at IS NOT NULL AND sealed_at IS NOT NULL AND published_at IS NULL
      AND manifest_artifact_id IS NOT NULL AND manifest_digest IS NOT NULL
      AND signature IS NOT NULL AND sealed_by_actor_id IS NOT NULL)
    OR
    (state IN ('published', 'superseded')
      AND batch_sequence IS NOT NULL
      AND previewed_at IS NOT NULL AND sealed_at IS NOT NULL AND published_at IS NOT NULL
      AND manifest_artifact_id IS NOT NULL AND manifest_digest IS NOT NULL
      AND signature IS NOT NULL AND sealed_by_actor_id IS NOT NULL)
  ),
  CHECK (previewed_at IS NULL OR previewed_at >= created_at),
  CHECK (sealed_at IS NULL OR sealed_at >= previewed_at),
  CHECK (published_at IS NULL OR published_at >= sealed_at),
  CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX publication_batch_sequence_uq
  ON macsad.publication_batch(workspace_id, batch_sequence)
  WHERE batch_sequence IS NOT NULL;
CREATE INDEX publication_batch_correction_idx ON macsad.publication_batch(corrects_batch_id)
  WHERE corrects_batch_id IS NOT NULL;
CREATE INDEX publication_batch_manifest_idx ON macsad.publication_batch(manifest_artifact_id)
  WHERE manifest_artifact_id IS NOT NULL;
CREATE INDEX publication_batch_policy_idx ON macsad.publication_batch(policy_revision_id);
CREATE INDEX publication_batch_generator_idx ON macsad.publication_batch(generator_artifact_id)
  WHERE generator_artifact_id IS NOT NULL;
CREATE INDEX publication_batch_toolchain_idx ON macsad.publication_batch(toolchain_artifact_id)
  WHERE toolchain_artifact_id IS NOT NULL;
CREATE INDEX publication_batch_sealer_idx ON macsad.publication_batch(sealed_by_actor_id)
  WHERE sealed_by_actor_id IS NOT NULL;

CREATE FUNCTION macsad.guard_publication_batch_content()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF NEW.state <> OLD.state AND NOT (
    (OLD.state = 'draft' AND NEW.state = 'previewed')
    OR (OLD.state = 'previewed' AND NEW.state = 'sealed')
    OR (OLD.state = 'sealed' AND NEW.state = 'published')
    OR (OLD.state = 'published' AND NEW.state = 'superseded')
  ) THEN
    RAISE EXCEPTION 'invalid publication batch state transition from % to %', OLD.state, NEW.state
      USING ERRCODE = '23514';
  END IF;
  IF OLD.state = 'superseded' THEN
    RAISE EXCEPTION 'a superseded publication batch is terminal and immutable'
      USING ERRCODE = '55000';
  END IF;
  IF OLD.state = 'published' AND NEW.state = 'published' THEN
    RAISE EXCEPTION 'published batches only change by becoming superseded'
      USING ERRCODE = '55000';
  END IF;
  IF OLD.state = 'published' AND NEW.published_at IS DISTINCT FROM OLD.published_at THEN
    RAISE EXCEPTION 'publication time is immutable'
      USING ERRCODE = '55000';
  END IF;
  IF OLD.state = 'draft' AND NEW.state = 'previewed' THEN
    IF NOT EXISTS (
      SELECT 1 FROM macsad.publication_item AS item
      WHERE item.publication_batch_id = NEW.id
    ) THEN
      RAISE EXCEPTION 'a publication batch must contain at least one item before preview acceptance'
        USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM macsad.audit_stream AS stream
      JOIN macsad.domain_event AS event
        ON event.workspace_id = stream.workspace_id
       AND event.workspace_sequence_no = stream.last_workspace_sequence
       AND event.event_hash = stream.last_event_hash
      WHERE stream.workspace_id = NEW.workspace_id
        AND event.id = NEW.audit_head_event_id
        AND event.workspace_sequence_no = NEW.audit_head_sequence_no
        AND event.event_hash = NEW.audit_head_event_hash
    ) THEN
      RAISE EXCEPTION 'accepted preview must close over the current workspace audit head'
        USING ERRCODE = '40001';
    END IF;
  END IF;
  IF OLD.state = 'previewed' AND NEW.state = 'sealed' THEN
    IF NOT EXISTS (
      SELECT 1 FROM macsad.publication_item AS item
      WHERE item.publication_batch_id = NEW.id
    ) THEN
      RAISE EXCEPTION 'a publication batch must contain at least one item before sealing'
        USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM macsad.artifact AS manifest
      WHERE manifest.id = NEW.manifest_artifact_id
        AND manifest.workspace_id = NEW.workspace_id
        AND manifest.classification IN ('public_candidate', 'public')
        AND manifest.secret_scan_result = 'passed'
        AND NOT manifest.quarantined
        AND manifest.redistribution_allowed
    ) THEN
      RAISE EXCEPTION 'sealed publication manifest is not public-safe'
      USING ERRCODE = '23514';
    END IF;
  END IF;
  IF OLD.state = 'sealed' AND NEW.state = 'published' AND NOT EXISTS (
    SELECT 1 FROM macsad.publication_attempt AS attempt
    WHERE attempt.publication_batch_id = NEW.id
      AND attempt.workspace_id = NEW.workspace_id
      AND attempt.state = 'succeeded'
  ) THEN
    RAISE EXCEPTION 'publication requires a successful reconciled deployment attempt'
      USING ERRCODE = '23514';
  END IF;
  IF OLD.state IN ('previewed', 'sealed', 'published', 'superseded')
    AND ROW(NEW.workspace_id, NEW.policy_revision_id, NEW.batch_sequence, NEW.corrects_batch_id,
      NEW.generator_artifact_id, NEW.toolchain_artifact_id,
      NEW.generator_revision_digest, NEW.platform_revision_digest,
      NEW.toolchain_closure_digest, NEW.evidence_closure_digest,
      NEW.artifact_closure_digest, NEW.audit_head_event_id,
      NEW.audit_head_sequence_no, NEW.audit_head_event_hash, NEW.previewed_at,
      NEW.created_at)
      IS DISTINCT FROM
      ROW(OLD.workspace_id, OLD.policy_revision_id, OLD.batch_sequence, OLD.corrects_batch_id,
      OLD.generator_artifact_id, OLD.toolchain_artifact_id,
      OLD.generator_revision_digest, OLD.platform_revision_digest,
      OLD.toolchain_closure_digest, OLD.evidence_closure_digest,
      OLD.artifact_closure_digest, OLD.audit_head_event_id,
      OLD.audit_head_sequence_no, OLD.audit_head_event_hash, OLD.previewed_at,
      OLD.created_at) THEN
    RAISE EXCEPTION 'previewed publication closure is immutable' USING ERRCODE = '55000';
  END IF;
  IF OLD.state IN ('sealed', 'published', 'superseded')
    AND ROW(NEW.workspace_id, NEW.policy_revision_id, NEW.batch_sequence, NEW.corrects_batch_id,
      NEW.generator_artifact_id, NEW.toolchain_artifact_id,
      NEW.generator_revision_digest, NEW.platform_revision_digest,
      NEW.toolchain_closure_digest, NEW.evidence_closure_digest,
      NEW.artifact_closure_digest, NEW.audit_head_event_id,
      NEW.audit_head_sequence_no, NEW.audit_head_event_hash,
      NEW.manifest_artifact_id, NEW.manifest_digest, NEW.signature,
      NEW.sealed_by_actor_id, NEW.sealed_at)
      IS DISTINCT FROM
      ROW(OLD.workspace_id, OLD.policy_revision_id, OLD.batch_sequence, OLD.corrects_batch_id,
      OLD.generator_artifact_id, OLD.toolchain_artifact_id,
      OLD.generator_revision_digest, OLD.platform_revision_digest,
      OLD.toolchain_closure_digest, OLD.evidence_closure_digest,
      OLD.artifact_closure_digest, OLD.audit_head_event_id,
      OLD.audit_head_sequence_no, OLD.audit_head_event_hash,
      OLD.manifest_artifact_id, OLD.manifest_digest, OLD.signature,
      OLD.sealed_by_actor_id, OLD.sealed_at) THEN
    RAISE EXCEPTION 'sealed publication signature and content are immutable' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TABLE macsad.publication_item (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  publication_batch_id uuid NOT NULL,
  research_case_id uuid NOT NULL,
  problem_revision_id uuid NOT NULL,
  claim_id uuid NOT NULL,
  disposition_attestation_id uuid NOT NULL,
  eligibility_attestation_id uuid NOT NULL,
  publication_dossier_id uuid NOT NULL,
  dossier_artifact_id uuid NOT NULL,
  item_ordinal integer NOT NULL CHECK (item_ordinal >= 0),
  item_digest macsad.sha256_digest NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (publication_batch_id, item_ordinal),
  UNIQUE (publication_batch_id, research_case_id),
  FOREIGN KEY (workspace_id, publication_batch_id)
    REFERENCES macsad.publication_batch(workspace_id, id),
  FOREIGN KEY (workspace_id, research_case_id)
    REFERENCES macsad.research_case(workspace_id, id),
  FOREIGN KEY (workspace_id, claim_id, problem_revision_id)
    REFERENCES macsad.claim(workspace_id, id, problem_revision_id),
  FOREIGN KEY (workspace_id, disposition_attestation_id, problem_revision_id)
    REFERENCES macsad.attestation(workspace_id, id, problem_revision_id),
  FOREIGN KEY (workspace_id, eligibility_attestation_id, problem_revision_id)
    REFERENCES macsad.attestation(workspace_id, id, problem_revision_id),
  FOREIGN KEY (
    workspace_id, publication_dossier_id, research_case_id,
    problem_revision_id, claim_id, dossier_artifact_id
  ) REFERENCES macsad.publication_dossier(
    workspace_id, id, research_case_id,
    problem_revision_id, claim_id, dossier_artifact_id
  )
);

CREATE INDEX publication_item_case_idx ON macsad.publication_item(research_case_id);
CREATE INDEX publication_item_claim_idx ON macsad.publication_item(claim_id);
CREATE INDEX publication_item_disposition_idx ON macsad.publication_item(disposition_attestation_id);
CREATE INDEX publication_item_eligibility_idx ON macsad.publication_item(eligibility_attestation_id);
CREATE INDEX publication_item_dossier_idx ON macsad.publication_item(publication_dossier_id);
CREATE INDEX publication_item_dossier_artifact_idx ON macsad.publication_item(dossier_artifact_id);

CREATE FUNCTION macsad.validate_publication_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  PERFORM 1
  FROM macsad.publication_batch AS batch
  WHERE batch.id = NEW.publication_batch_id
    AND batch.workspace_id = NEW.workspace_id
    AND batch.state = 'draft'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication items can only be selected while a batch is draft'
      USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM macsad.research_case AS c
    WHERE c.id = NEW.research_case_id
      AND c.workspace_id = NEW.workspace_id
      AND c.problem_revision_id = NEW.problem_revision_id
      AND c.state = 'closed'
      AND c.editorial_decision = 'eligible'
      AND c.disposition_attestation_id = NEW.disposition_attestation_id
      AND c.eligibility_attestation_id = NEW.eligibility_attestation_id
  ) THEN
    RAISE EXCEPTION 'publication item does not select an eligible closed case closure'
      USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM macsad.artifact AS a
    WHERE a.id = NEW.dossier_artifact_id
      AND a.workspace_id = NEW.workspace_id
      AND a.classification IN ('public_candidate', 'public')
      AND a.secret_scan_result = 'passed'
      AND NOT a.quarantined
      AND a.redistribution_allowed
  ) THEN
    RAISE EXCEPTION 'publication dossier is not public-safe' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER publication_item_closure_ck
AFTER INSERT ON macsad.publication_item
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW EXECUTE FUNCTION macsad.validate_publication_item();

CREATE TABLE macsad.publication_attempt (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  publication_batch_id uuid NOT NULL,
  attempt_no integer NOT NULL CHECK (attempt_no > 0),
  trigger_kind macsad.publication_trigger_kind NOT NULL,
  target_environment text NOT NULL,
  platform_revision_digest macsad.sha256_digest NOT NULL,
  generator_revision_digest macsad.sha256_digest NOT NULL,
  release_request_digest macsad.sha256_digest NOT NULL,
  github_repository_id bigint NOT NULL CHECK (github_repository_id > 0),
  github_workflow text NOT NULL,
  github_run_id bigint CHECK (github_run_id > 0),
  github_run_attempt integer CHECK (github_run_attempt > 0),
  cloudflare_account_reference text NOT NULL,
  cloudflare_project_name text NOT NULL,
  cloudflare_version_id text,
  cloudflare_deployment_id text,
  deployment_url text,
  state macsad.publication_attempt_state NOT NULL DEFAULT 'pending',
  response_artifact_id uuid,
  started_at timestamptz,
  finished_at timestamptz,
  error_code text,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, publication_batch_id, id),
  UNIQUE (publication_batch_id, attempt_no),
  FOREIGN KEY (workspace_id, publication_batch_id)
    REFERENCES macsad.publication_batch(workspace_id, id),
  FOREIGN KEY (workspace_id, response_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  CHECK (
    (state = 'pending' AND started_at IS NULL AND finished_at IS NULL)
    OR (state = 'running' AND started_at IS NOT NULL AND finished_at IS NULL)
    OR (state = 'succeeded' AND started_at IS NOT NULL
      AND finished_at IS NOT NULL AND error_code IS NULL)
    OR (state = 'failed' AND finished_at IS NOT NULL AND error_code IS NOT NULL)
  ),
  CHECK ((github_run_id IS NULL) = (github_run_attempt IS NULL)),
  CHECK (state <> 'succeeded' OR (
    github_run_id IS NOT NULL AND cloudflare_version_id IS NOT NULL
    AND cloudflare_deployment_id IS NOT NULL AND deployment_url IS NOT NULL
  )),
  CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at),
  CHECK (updated_at >= created_at)
);

CREATE INDEX publication_attempt_batch_idx ON macsad.publication_attempt(publication_batch_id);
CREATE INDEX publication_attempt_response_idx ON macsad.publication_attempt(response_artifact_id)
  WHERE response_artifact_id IS NOT NULL;

CREATE FUNCTION macsad.guard_publication_attempt_request()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM macsad.publication_batch AS b
    WHERE b.id = NEW.publication_batch_id
      AND b.workspace_id = NEW.workspace_id
      AND b.platform_revision_digest = NEW.platform_revision_digest
      AND b.generator_revision_digest = NEW.generator_revision_digest
      AND b.state IN ('sealed', 'published', 'superseded')
  ) THEN
    RAISE EXCEPTION 'publication attempt revisions do not match a sealed batch'
      USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'UPDATE' AND ROW(
      NEW.workspace_id, NEW.publication_batch_id, NEW.attempt_no, NEW.trigger_kind,
      NEW.target_environment, NEW.platform_revision_digest,
      NEW.generator_revision_digest, NEW.release_request_digest,
      NEW.github_repository_id, NEW.github_workflow,
      NEW.cloudflare_account_reference, NEW.cloudflare_project_name,
      NEW.created_at
    ) IS DISTINCT FROM ROW(
      OLD.workspace_id, OLD.publication_batch_id, OLD.attempt_no, OLD.trigger_kind,
      OLD.target_environment, OLD.platform_revision_digest,
      OLD.generator_revision_digest, OLD.release_request_digest,
      OLD.github_repository_id, OLD.github_workflow,
      OLD.cloudflare_account_reference, OLD.cloudflare_project_name,
      OLD.created_at
    ) THEN
    RAISE EXCEPTION 'publication release request and deployment target are immutable'
      USING ERRCODE = '55000';
  END IF;
  IF TG_OP = 'UPDATE' AND (
      (OLD.github_run_id IS NOT NULL
        AND ROW(NEW.github_run_id, NEW.github_run_attempt)
          IS DISTINCT FROM ROW(OLD.github_run_id, OLD.github_run_attempt))
      OR (OLD.cloudflare_version_id IS NOT NULL
        AND NEW.cloudflare_version_id IS DISTINCT FROM OLD.cloudflare_version_id)
      OR (OLD.cloudflare_deployment_id IS NOT NULL
        AND NEW.cloudflare_deployment_id IS DISTINCT FROM OLD.cloudflare_deployment_id)
      OR (OLD.deployment_url IS NOT NULL
        AND NEW.deployment_url IS DISTINCT FROM OLD.deployment_url)
      OR (OLD.response_artifact_id IS NOT NULL
        AND NEW.response_artifact_id IS DISTINCT FROM OLD.response_artifact_id)
    ) THEN
    RAISE EXCEPTION 'observed deployment identities are write-once'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER publication_attempt_guard_request
BEFORE INSERT OR UPDATE ON macsad.publication_attempt
FOR EACH ROW EXECUTE FUNCTION macsad.guard_publication_attempt_request();

CREATE TABLE macsad.publication_head (
  workspace_id uuid PRIMARY KEY REFERENCES macsad.workspace(id),
  publication_batch_id uuid NOT NULL,
  publication_attempt_id uuid NOT NULL,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  FOREIGN KEY (workspace_id, publication_batch_id, publication_attempt_id)
    REFERENCES macsad.publication_attempt(workspace_id, publication_batch_id, id),
  CHECK (updated_at >= created_at)
);

CREATE INDEX publication_head_batch_idx ON macsad.publication_head(publication_batch_id);
CREATE INDEX publication_head_attempt_idx ON macsad.publication_head(publication_attempt_id);

CREATE FUNCTION macsad.validate_publication_head()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM macsad.publication_attempt AS a
    JOIN macsad.publication_batch AS b ON b.id = a.publication_batch_id
    WHERE a.id = NEW.publication_attempt_id
      AND a.workspace_id = NEW.workspace_id
      AND a.publication_batch_id = NEW.publication_batch_id
      AND a.state = 'succeeded'
      AND b.state IN ('published', 'superseded')
  ) THEN
    RAISE EXCEPTION 'publication head requires a reconciled successful deployment'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER publication_head_success_ck
AFTER INSERT OR UPDATE ON macsad.publication_head
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW EXECUTE FUNCTION macsad.validate_publication_head();

CREATE TABLE macsad.command_receipt (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  actor_identity_id uuid REFERENCES macsad.actor_identity(id),
  command_kind text NOT NULL CHECK (command_kind ~ '^[a-z][a-z0-9._-]*$'),
  idempotency_key text NOT NULL,
  request_digest macsad.sha256_digest NOT NULL,
  correlation_id uuid NOT NULL,
  causation_id uuid,
  state macsad.command_state NOT NULL DEFAULT 'processing',
  result_schema_id text,
  result_schema_version integer,
  result_body macsad.canonical_json,
  result_digest macsad.sha256_digest,
  lease_owner_actor_id uuid REFERENCES macsad.actor(id),
  lease_expires_at timestamptz,
  completed_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, idempotency_key),
  FOREIGN KEY (actor_identity_id, actor_id)
    REFERENCES macsad.actor_identity(id, actor_id),
  CHECK (
    (result_schema_id IS NULL AND result_schema_version IS NULL
      AND result_body IS NULL AND result_digest IS NULL)
    OR
    (result_schema_id IS NOT NULL AND result_schema_version > 0
      AND result_body IS NOT NULL AND result_digest IS NOT NULL)
  ),
  CHECK ((state IN ('completed', 'rejected')) = (completed_at IS NOT NULL)),
  CHECK ((lease_owner_actor_id IS NULL) = (lease_expires_at IS NULL)),
  CHECK (updated_at >= created_at)
);

CREATE INDEX command_receipt_actor_idx ON macsad.command_receipt(actor_id);
CREATE INDEX command_receipt_identity_idx ON macsad.command_receipt(actor_identity_id)
  WHERE actor_identity_id IS NOT NULL;
CREATE INDEX command_receipt_lease_idx ON macsad.command_receipt(lease_expires_at)
  WHERE state = 'processing';

CREATE TABLE macsad.inbound_delivery (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES macsad.workspace(id),
  provider text NOT NULL CHECK (provider ~ '^[a-z][a-z0-9._-]*$'),
  external_delivery_id text NOT NULL,
  delivery_kind text NOT NULL,
  payload_artifact_id uuid,
  payload_digest macsad.sha256_digest NOT NULL,
  state macsad.delivery_state NOT NULL DEFAULT 'received',
  command_receipt_id uuid,
  received_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  completed_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (provider, external_delivery_id),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, payload_artifact_id)
    REFERENCES macsad.artifact(workspace_id, id),
  FOREIGN KEY (workspace_id, command_receipt_id)
    REFERENCES macsad.command_receipt(workspace_id, id),
  CHECK ((state IN ('completed', 'rejected', 'dead_letter')) = (completed_at IS NOT NULL)),
  CHECK (updated_at >= created_at)
);

CREATE INDEX inbound_delivery_workspace_state_idx
  ON macsad.inbound_delivery(workspace_id, state, received_at);
CREATE INDEX inbound_delivery_payload_idx ON macsad.inbound_delivery(payload_artifact_id)
  WHERE payload_artifact_id IS NOT NULL;
CREATE INDEX inbound_delivery_command_idx ON macsad.inbound_delivery(command_receipt_id)
  WHERE command_receipt_id IS NOT NULL;

CREATE TABLE macsad.audit_stream (
  workspace_id uuid PRIMARY KEY REFERENCES macsad.workspace(id),
  last_workspace_sequence bigint NOT NULL DEFAULT 0 CHECK (last_workspace_sequence >= 0),
  last_event_hash macsad.sha256_digest,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CHECK ((last_workspace_sequence = 0) = (last_event_hash IS NULL)),
  CHECK (updated_at >= created_at)
);

CREATE FUNCTION macsad.create_workspace_audit_stream()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  INSERT INTO macsad.audit_stream(workspace_id) VALUES (NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER workspace_create_audit_stream
AFTER INSERT ON macsad.workspace
FOR EACH ROW EXECUTE FUNCTION macsad.create_workspace_audit_stream();

CREATE TABLE macsad.domain_event (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  workspace_sequence_no bigint NOT NULL CHECK (workspace_sequence_no > 0),
  aggregate_kind text NOT NULL CHECK (aggregate_kind ~ '^[a-z][a-z0-9._-]*$'),
  aggregate_id uuid NOT NULL,
  aggregate_version bigint NOT NULL CHECK (aggregate_version > 0),
  event_kind text NOT NULL CHECK (event_kind ~ '^[a-z][a-z0-9._-]*$'),
  command_receipt_id uuid,
  inbound_delivery_id uuid,
  actor_id uuid NOT NULL REFERENCES macsad.actor(id),
  correlation_id uuid NOT NULL,
  causation_id uuid,
  payload_schema_id text NOT NULL,
  payload_schema_version integer NOT NULL CHECK (payload_schema_version > 0),
  payload_body macsad.canonical_json NOT NULL,
  payload_digest macsad.sha256_digest NOT NULL,
  previous_event_hash macsad.sha256_digest,
  event_hash macsad.sha256_digest NOT NULL UNIQUE,
  occurred_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, id, workspace_sequence_no, event_hash),
  UNIQUE (workspace_id, workspace_sequence_no),
  UNIQUE (workspace_id, aggregate_kind, aggregate_id, aggregate_version),
  FOREIGN KEY (workspace_id)
    REFERENCES macsad.audit_stream(workspace_id),
  FOREIGN KEY (workspace_id, command_receipt_id)
    REFERENCES macsad.command_receipt(workspace_id, id),
  FOREIGN KEY (workspace_id, inbound_delivery_id)
    REFERENCES macsad.inbound_delivery(workspace_id, id),
  CHECK ((workspace_sequence_no = 1) = (previous_event_hash IS NULL)),
  CHECK (occurred_at <= recorded_at)
);

CREATE INDEX domain_event_aggregate_idx
  ON macsad.domain_event(workspace_id, aggregate_kind, aggregate_id, aggregate_version);
CREATE INDEX domain_event_command_idx ON macsad.domain_event(command_receipt_id)
  WHERE command_receipt_id IS NOT NULL;
CREATE INDEX domain_event_delivery_idx ON macsad.domain_event(inbound_delivery_id)
  WHERE inbound_delivery_id IS NOT NULL;
CREATE INDEX domain_event_actor_idx ON macsad.domain_event(actor_id);
CREATE INDEX domain_event_correlation_idx ON macsad.domain_event(workspace_id, correlation_id);

CREATE FUNCTION macsad.advance_workspace_audit_stream()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, macsad
AS $$
DECLARE
  stream_row macsad.audit_stream%ROWTYPE;
  expected_aggregate_version bigint;
BEGIN
  SELECT * INTO STRICT stream_row
  FROM macsad.audit_stream
  WHERE workspace_id = NEW.workspace_id
  FOR UPDATE;

  IF NEW.workspace_sequence_no <> stream_row.last_workspace_sequence + 1
      OR NEW.previous_event_hash IS DISTINCT FROM stream_row.last_event_hash THEN
    RAISE EXCEPTION 'domain event does not extend the current workspace audit head'
      USING ERRCODE = '40001';
  END IF;

  SELECT COALESCE(pg_catalog.max(e.aggregate_version), 0) + 1
    INTO expected_aggregate_version
  FROM macsad.domain_event AS e
  WHERE e.workspace_id = NEW.workspace_id
    AND e.aggregate_kind = NEW.aggregate_kind
    AND e.aggregate_id = NEW.aggregate_id;

  IF NEW.aggregate_version <> expected_aggregate_version THEN
    RAISE EXCEPTION 'domain event aggregate version is not the next version'
      USING ERRCODE = '40001';
  END IF;

  UPDATE macsad.audit_stream
    SET last_workspace_sequence = NEW.workspace_sequence_no,
        last_event_hash = NEW.event_hash,
        version = version + 1
    WHERE workspace_id = NEW.workspace_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER domain_event_advance_workspace_stream
BEFORE INSERT ON macsad.domain_event
FOR EACH ROW EXECUTE FUNCTION macsad.advance_workspace_audit_stream();

ALTER TABLE macsad.publication_batch
  ADD CONSTRAINT publication_batch_audit_head_fk
  FOREIGN KEY (
    workspace_id, audit_head_event_id, audit_head_sequence_no, audit_head_event_hash
  ) REFERENCES macsad.domain_event(
    workspace_id, id, workspace_sequence_no, event_hash
  );

CREATE INDEX publication_batch_audit_head_idx
  ON macsad.publication_batch(audit_head_event_id)
  WHERE audit_head_event_id IS NOT NULL;

ALTER TABLE macsad.task_transition
  ADD COLUMN domain_event_id uuid NOT NULL,
  ADD CONSTRAINT task_transition_domain_event_fk
  FOREIGN KEY (workspace_id, domain_event_id)
  REFERENCES macsad.domain_event(workspace_id, id)
  DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT task_transition_domain_event_uq UNIQUE (domain_event_id);

CREATE INDEX task_transition_domain_event_idx ON macsad.task_transition(domain_event_id);

CREATE FUNCTION macsad.validate_task_transition_event()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, macsad
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM macsad.domain_event AS event
    JOIN macsad.task AS source_task
      ON source_task.id = NEW.from_task_id
     AND source_task.workspace_id = NEW.workspace_id
    WHERE event.id = NEW.domain_event_id
      AND event.workspace_id = NEW.workspace_id
      AND event.aggregate_kind = 'task'
      AND event.aggregate_id = NEW.from_task_id
      AND event.aggregate_version = source_task.version
      AND event.event_kind = 'task.transitioned'
      AND event.payload_body ->> 'task_transition_id' = NEW.id::text
      AND event.payload_body ->> 'policy_transition_id' = NEW.policy_transition_id::text
      AND event.payload_body ->> 'decision_code' = NEW.decision_code
  ) THEN
    RAISE EXCEPTION 'task transition event does not describe the exact source version and decision'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER task_transition_event_semantics_ck
AFTER INSERT ON macsad.task_transition
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION macsad.validate_task_transition_event();

CREATE TABLE macsad.outbox_message (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id uuid NOT NULL,
  domain_event_id uuid NOT NULL,
  topic text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(topic)) > 0),
  message_key text NOT NULL,
  payload_schema_id text NOT NULL,
  payload_schema_version integer NOT NULL CHECK (payload_schema_version > 0),
  payload_body macsad.canonical_json NOT NULL,
  payload_digest macsad.sha256_digest NOT NULL,
  state macsad.outbox_state NOT NULL DEFAULT 'pending',
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  lease_owner_actor_id uuid REFERENCES macsad.actor(id),
  lease_expires_at timestamptz,
  delivered_at timestamptz,
  last_error_code text,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (workspace_id, id),
  UNIQUE (domain_event_id, topic),
  FOREIGN KEY (workspace_id, domain_event_id)
    REFERENCES macsad.domain_event(workspace_id, id),
  CHECK ((lease_owner_actor_id IS NULL) = (lease_expires_at IS NULL)),
  CHECK ((state = 'delivered') = (delivered_at IS NOT NULL)),
  CHECK (updated_at >= created_at)
);

CREATE INDEX outbox_message_ready_idx
  ON macsad.outbox_message(state, next_attempt_at)
  WHERE state IN ('pending', 'publishing');
CREATE INDEX outbox_message_event_idx ON macsad.outbox_message(domain_event_id);
CREATE INDEX outbox_message_lease_actor_idx ON macsad.outbox_message(lease_owner_actor_id)
  WHERE lease_owner_actor_id IS NOT NULL;

-- Read models deliberately expose arithmetic and provenance rather than badges.
CREATE VIEW macsad.case_board_v AS
SELECT
  c.workspace_id,
  c.id AS research_case_id,
  p.title,
  p.research_kind,
  c.state AS case_state,
  c.control_state,
  c.priority,
  c.process_key,
  t.id AS live_task_id,
  t.sequence_no AS live_task_sequence,
  t.node_key AS live_node_key,
  t.board_phase,
  t.state AS task_state,
  a.id AS accepted_assignment_id,
  a.offered_actor_id AS assigned_actor_id,
  a.profile_key AS assigned_profile_key,
  t.deadline_at,
  c.updated_at
FROM macsad.research_case AS c
JOIN macsad.problem_revision AS p ON p.id = c.problem_revision_id
LEFT JOIN macsad.task AS t
  ON t.research_case_id = c.id
 AND t.state IN ('offered', 'ready', 'running', 'waiting')
LEFT JOIN macsad.task_assignment AS a
  ON a.task_id = t.id AND a.state = 'accepted';

CREATE VIEW macsad.budget_balance_v AS
WITH ledger AS (
  SELECT
    e.budget_account_id,
    COALESCE(
      pg_catalog.sum(e.quantity) FILTER (WHERE e.kind = 'reserve'), 0::numeric
    ) - COALESCE(
      pg_catalog.sum(e.reservation_released_quantity), 0::numeric
    ) AS ledger_reserved_quantity,
    COALESCE(
      pg_catalog.sum(e.quantity) FILTER (WHERE e.kind IN ('commit', 'spend_adjustment')), 0::numeric
    ) AS ledger_spent_quantity,
    COALESCE(
      pg_catalog.sum(e.quantity) FILTER (WHERE e.kind = 'limit_adjustment'), 0::numeric
    ) AS ledger_limit_adjustment
  FROM macsad.budget_entry AS e
  GROUP BY e.budget_account_id
)
SELECT
  a.id AS budget_account_id,
  a.workspace_id,
  a.research_case_id,
  a.resource_kind,
  a.unit_code,
  a.currency_code,
  a.period_start,
  a.period_end,
  a.initial_spending_limit,
  a.spending_limit,
  a.reserved_quantity,
  a.spent_quantity,
  a.initial_spending_limit + COALESCE(l.ledger_limit_adjustment, 0::numeric)
    AS ledger_spending_limit,
  COALESCE(l.ledger_reserved_quantity, 0::numeric) AS ledger_reserved_quantity,
  COALESCE(l.ledger_spent_quantity, 0::numeric) AS ledger_spent_quantity,
  a.spending_limit - a.spent_quantity AS spend_variance,
  GREATEST(a.spent_quantity - a.spending_limit, 0::numeric) AS overrun_quantity,
  GREATEST(a.spending_limit - a.spent_quantity - a.reserved_quantity, 0::numeric)
    AS available_to_reserve,
  (a.spent_quantity + a.reserved_quantity < a.spending_limit) AS can_reserve,
  (
    a.spending_limit = a.initial_spending_limit
      + COALESCE(l.ledger_limit_adjustment, 0::numeric)
    AND a.reserved_quantity = COALESCE(l.ledger_reserved_quantity, 0::numeric)
    AND a.spent_quantity = COALESCE(l.ledger_spent_quantity, 0::numeric)
  ) AS projection_is_consistent,
  a.version,
  a.updated_at
FROM macsad.budget_account AS a
LEFT JOIN ledger AS l ON l.budget_account_id = a.id;

CREATE VIEW macsad.model_cost_variance_v AS
WITH latest_usage AS (
  SELECT DISTINCT ON (u.model_call_id)
    u.*
  FROM macsad.model_usage_observation AS u
  ORDER BY u.model_call_id, u.observation_sequence DESC
), reservations AS (
  SELECT DISTINCT ON (e.model_call_id)
    e.model_call_id, e.id AS reservation_entry_id, e.quantity AS reserved_quantity
  FROM macsad.budget_entry AS e
  WHERE e.kind = 'reserve' AND e.model_call_id IS NOT NULL
  ORDER BY e.model_call_id, e.created_at, e.id
), settlements AS (
  SELECT DISTINCT ON (e.model_call_id)
    e.model_call_id, e.id AS settlement_entry_id, e.kind AS settlement_kind,
    e.quantity AS settled_quantity, e.reservation_released_quantity
  FROM macsad.budget_entry AS e
  WHERE e.kind IN ('commit', 'release') AND e.model_call_id IS NOT NULL
  ORDER BY e.model_call_id, e.created_at DESC, e.id DESC
), spend_adjustments AS (
  SELECT e.model_call_id, pg_catalog.sum(e.quantity) AS adjustment_quantity
  FROM macsad.budget_entry AS e
  WHERE e.kind = 'spend_adjustment' AND e.model_call_id IS NOT NULL
  GROUP BY e.model_call_id
)
SELECT
  c.id AS model_call_id,
  c.workspace_id,
  c.research_case_id,
  c.task_id,
  c.execution_id,
  c.requested_model,
  c.resolved_model,
  c.resolved_provider,
  c.service_tier,
  c.byok,
  c.openrouter_generation_id,
  c.state AS model_call_state,
  c.estimated_cost,
  c.reserved_cost,
  c.cost_currency,
  a.id AS budget_account_id,
  a.unit_code AS budget_unit,
  a.currency_code AS budget_currency,
  r.reservation_entry_id,
  r.reserved_quantity,
  u.id AS latest_usage_observation_id,
  u.is_final AS usage_is_final,
  u.prompt_tokens,
  u.completion_tokens,
  u.total_tokens,
  u.reasoning_tokens,
  u.cache_read_tokens,
  u.cache_write_tokens,
  u.audio_input_tokens,
  u.audio_output_tokens,
  u.image_count,
  u.media_count,
  u.web_search_count,
  u.billed_amount,
  u.billed_currency,
  u.billed_credits,
  u.upstream_cost_amount,
  u.upstream_cost_currency,
  s.settlement_entry_id,
  s.settlement_kind,
  s.settled_quantity,
  s.reservation_released_quantity,
  COALESCE(x.adjustment_quantity, 0::numeric) AS spend_adjustment_quantity,
  CASE WHEN s.settlement_kind = 'commit'
    THEN s.settled_quantity + COALESCE(x.adjustment_quantity, 0::numeric)
    ELSE COALESCE(x.adjustment_quantity, 0::numeric)
  END AS recorded_spend_quantity,
  CASE WHEN s.settlement_kind = 'commit' AND r.reserved_quantity IS NOT NULL
    THEN s.settled_quantity + COALESCE(x.adjustment_quantity, 0::numeric)
      - r.reserved_quantity END AS reservation_variance,
  CASE WHEN (s.settlement_kind = 'commit' OR x.adjustment_quantity IS NOT NULL)
      AND u.billed_amount IS NOT NULL
      AND a.currency_code = u.billed_currency
    THEN COALESCE(s.settled_quantity, 0::numeric)
      + COALESCE(x.adjustment_quantity, 0::numeric)
      - u.billed_amount END AS reconciliation_variance,
  (u.id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM macsad.budget_entry AS reconciled_entry
    WHERE reconciled_entry.model_usage_observation_id = u.id
  )) AS usage_needs_reconciliation,
  (s.settlement_kind = 'commit' AND r.reserved_quantity IS NOT NULL
    AND s.settled_quantity + COALESCE(x.adjustment_quantity, 0::numeric)
      > r.reserved_quantity) AS exceeded_reservation
FROM macsad.model_call AS c
JOIN macsad.budget_account AS a ON a.id = c.budget_account_id
LEFT JOIN latest_usage AS u ON u.model_call_id = c.id
LEFT JOIN reservations AS r ON r.model_call_id = c.id
LEFT JOIN settlements AS s ON s.model_call_id = c.id
LEFT JOIN spend_adjustments AS x ON x.model_call_id = c.id;

CREATE VIEW macsad.publication_catalog_v AS
SELECT
  b.workspace_id,
  b.id AS publication_batch_id,
  b.batch_sequence,
  b.published_at,
  i.item_ordinal,
  i.research_case_id,
  i.problem_revision_id,
  i.claim_id,
  i.dossier_artifact_id,
  i.item_digest,
  h.publication_attempt_id
FROM macsad.publication_batch AS b
JOIN macsad.publication_item AS i ON i.publication_batch_id = b.id
LEFT JOIN macsad.publication_head AS h ON h.publication_batch_id = b.id
WHERE b.state IN ('published', 'superseded');

CREATE VIEW macsad.audit_timeline_v AS
SELECT
  e.workspace_id,
  e.workspace_sequence_no,
  e.aggregate_kind,
  e.aggregate_id,
  e.aggregate_version,
  e.event_kind,
  e.actor_id,
  e.correlation_id,
  e.causation_id,
  e.payload_schema_id,
  e.payload_schema_version,
  e.payload_digest,
  e.event_hash,
  e.occurred_at,
  e.recorded_at
FROM macsad.domain_event AS e;

CREATE VIEW macsad.schema_version_v AS
SELECT pg_catalog.max(m.version) AS current_version
FROM macsad_meta.schema_migration AS m;

-- Append-only and no-delete enforcement. State-bearing rows use optimistic
-- versions and are updated only by the controller role.
DO $triggers$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'workspace_snapshot', 'tool_operation_manifest',
    'policy_member_profile', 'policy_process', 'policy_node', 'policy_transition',
    'policy_node_tool_operation', 'problem_revision', 'research_case_tool_revision',
    'task_transition', 'message', 'message_mention', 'blob', 'artifact',
    'execution_artifact', 'claim', 'attestation', 'attestation_artifact',
    'model_usage_observation', 'budget_entry', 'publication_dossier',
    'publication_item', 'domain_event'
  ] LOOP
    EXECUTE pg_catalog.format(
      'CREATE TRIGGER %I_reject_mutation BEFORE UPDATE OR DELETE ON macsad.%I '
      'FOR EACH ROW EXECUTE FUNCTION macsad.reject_mutation()',
      table_name, table_name
    );
  END LOOP;
END
$triggers$;

CREATE TRIGGER schema_migration_reject_mutation
BEFORE UPDATE OR DELETE ON macsad_meta.schema_migration
FOR EACH ROW EXECUTE FUNCTION macsad.reject_mutation();

DO $versions$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'workspace', 'tool_repository', 'policy_revision', 'actor', 'actor_identity',
    'membership', 'capability_grant', 'research_case', 'task', 'thread',
    'task_assignment', 'execution', 'execution_tool_use', 'budget_account',
    'model_call', 'publication_batch', 'publication_attempt', 'publication_head',
    'command_receipt', 'inbound_delivery', 'audit_stream', 'outbox_message'
  ] LOOP
    EXECUTE pg_catalog.format(
      'CREATE TRIGGER %I_guard_version BEFORE UPDATE ON macsad.%I '
      'FOR EACH ROW EXECUTE FUNCTION macsad.guard_versioned_update()',
      table_name, table_name
    );
    EXECUTE pg_catalog.format(
      'CREATE TRIGGER %I_reject_delete BEFORE DELETE ON macsad.%I '
      'FOR EACH ROW EXECUTE FUNCTION macsad.reject_mutation()',
      table_name, table_name
    );
  END LOOP;
END
$versions$;

CREATE TRIGGER policy_revision_guard_content
BEFORE UPDATE ON macsad.policy_revision
FOR EACH ROW EXECUTE FUNCTION macsad.guard_policy_revision_content();

CREATE TRIGGER workspace_guard_identity
BEFORE UPDATE ON macsad.workspace
FOR EACH ROW EXECUTE FUNCTION macsad.guard_workspace_identity();

CREATE TRIGGER tool_repository_guard_identity
BEFORE UPDATE ON macsad.tool_repository
FOR EACH ROW EXECUTE FUNCTION macsad.guard_tool_repository_identity();

CREATE TRIGGER tool_repository_revision_guard_seal
BEFORE UPDATE ON macsad.tool_repository_revision
FOR EACH ROW EXECUTE FUNCTION macsad.guard_tool_revision_seal();

CREATE TRIGGER tool_repository_revision_reject_delete
BEFORE DELETE ON macsad.tool_repository_revision
FOR EACH ROW EXECUTE FUNCTION macsad.reject_mutation();

CREATE TRIGGER publication_batch_guard_content
BEFORE UPDATE ON macsad.publication_batch
FOR EACH ROW EXECUTE FUNCTION macsad.guard_publication_batch_content();

CREATE TRIGGER actor_state_guard
BEFORE UPDATE ON macsad.actor
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'active>paused,active>retired,paused>active,paused>retired', 'retired'
);
CREATE TRIGGER workspace_state_guard
BEFORE UPDATE ON macsad.workspace
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'pending>active,pending>disconnected,active>paused,active>disconnected,paused>active,paused>disconnected,disconnected>pending,disconnected>active', ''
);
CREATE TRIGGER tool_repository_state_guard
BEFORE UPDATE ON macsad.tool_repository
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'disabled>active,disabled>disconnected,active>disabled,active>disconnected,disconnected>disabled,disconnected>active', ''
);
CREATE TRIGGER membership_state_guard
BEFORE UPDATE ON macsad.membership
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'active>paused,active>retired,paused>active,paused>retired', 'retired'
);
CREATE TRIGGER research_case_state_guard
BEFORE UPDATE ON macsad.research_case
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition('open>closed', 'closed');
CREATE TRIGGER task_state_guard
BEFORE UPDATE ON macsad.task
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'offered>ready,offered>cancelled,ready>running,ready>cancelled,running>waiting,running>completed,running>cancelled,waiting>ready,waiting>running,waiting>completed,waiting>cancelled',
  'completed,cancelled'
);
CREATE TRIGGER task_assignment_state_guard
BEFORE UPDATE ON macsad.task_assignment
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'offered>accepted,offered>rejected,offered>expired,accepted>released',
  'rejected,expired,released'
);
CREATE TRIGGER execution_state_guard
BEFORE UPDATE ON macsad.execution
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'pending>leased,pending>expired,leased>running,leased>cancel_requested,leased>expired,running>cancel_requested,running>completed,running>failed,running>expired,cancel_requested>completed,cancel_requested>failed,cancel_requested>expired',
  'completed,failed,expired'
);
CREATE TRIGGER execution_tool_use_state_guard
BEFORE UPDATE ON macsad.execution_tool_use
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'pending>running,pending>failed,pending>cancelled,running>completed,running>failed,running>cancelled',
  'completed,failed,cancelled'
);
CREATE TRIGGER model_call_state_guard
BEFORE UPDATE ON macsad.model_call
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'reserved>submitted,reserved>cancelled,submitted>streaming,submitted>succeeded,submitted>usage_pending,submitted>failed,submitted>cancelled,streaming>succeeded,streaming>usage_pending,streaming>failed,streaming>cancelled,usage_pending>succeeded,usage_pending>reconciled,usage_pending>failed,succeeded>usage_pending,succeeded>reconciled,reconciled>usage_pending',
  'failed,cancelled'
);
CREATE TRIGGER publication_attempt_state_guard
BEFORE UPDATE ON macsad.publication_attempt
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'pending>running,pending>failed,running>succeeded,running>failed',
  'succeeded,failed'
);
CREATE TRIGGER command_receipt_state_guard
BEFORE UPDATE ON macsad.command_receipt
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'processing>completed,processing>rejected', 'completed,rejected'
);
CREATE TRIGGER inbound_delivery_state_guard
BEFORE UPDATE ON macsad.inbound_delivery
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'received>processing,received>completed,received>rejected,received>dead_letter,processing>completed,processing>rejected,processing>dead_letter',
  'completed,rejected,dead_letter'
);
CREATE TRIGGER outbox_message_state_guard
BEFORE UPDATE ON macsad.outbox_message
FOR EACH ROW EXECUTE FUNCTION macsad.guard_state_transition(
  'pending>publishing,pending>dead_letter,publishing>pending,publishing>delivered,publishing>dead_letter',
  'delivered,dead_letter'
);

CREATE TRIGGER policy_revision_initial_state
BEFORE INSERT ON macsad.policy_revision
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('candidate');
CREATE TRIGGER research_case_initial_state
BEFORE INSERT ON macsad.research_case
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('open');
CREATE TRIGGER task_initial_state
BEFORE INSERT ON macsad.task
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('offered');
CREATE TRIGGER task_assignment_initial_state
BEFORE INSERT ON macsad.task_assignment
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('offered');
CREATE TRIGGER execution_initial_state
BEFORE INSERT ON macsad.execution
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('pending');
CREATE TRIGGER execution_tool_use_initial_state
BEFORE INSERT ON macsad.execution_tool_use
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('pending');
CREATE TRIGGER model_call_initial_state
BEFORE INSERT ON macsad.model_call
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('reserved');
CREATE TRIGGER publication_batch_initial_state
BEFORE INSERT ON macsad.publication_batch
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('draft');
CREATE TRIGGER publication_attempt_initial_state
BEFORE INSERT ON macsad.publication_attempt
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('pending');
CREATE TRIGGER command_receipt_initial_state
BEFORE INSERT ON macsad.command_receipt
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('processing');
CREATE TRIGGER inbound_delivery_initial_state
BEFORE INSERT ON macsad.inbound_delivery
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('received');
CREATE TRIGGER outbox_message_initial_state
BEFORE INSERT ON macsad.outbox_message
FOR EACH ROW EXECUTE FUNCTION macsad.guard_initial_state('pending');

-- Ownership, defaults, and least privilege. The application may insert new
-- immutable facts but cannot rewrite or delete them. Budget entries are only
-- created through the mechanical SECURITY DEFINER function above.
ALTER DEFAULT PRIVILEGES FOR ROLE macsad_owner IN SCHEMA macsad
  REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE macsad_owner IN SCHEMA macsad
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA macsad_meta FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA macsad FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA macsad FROM PUBLIC;

GRANT USAGE ON SCHEMA macsad_meta TO macsad_migrator, macsad_reader;
GRANT USAGE ON SCHEMA macsad TO macsad_migrator, macsad_app, macsad_reader;

GRANT SELECT ON macsad_meta.schema_migration TO macsad_migrator, macsad_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA macsad TO macsad_migrator, macsad_app, macsad_reader;
GRANT INSERT ON ALL TABLES IN SCHEMA macsad TO macsad_app;
REVOKE INSERT ON macsad.budget_entry, macsad.audit_stream FROM macsad_app;
REVOKE INSERT ON
  macsad.case_board_v,
  macsad.budget_balance_v,
  macsad.model_cost_variance_v,
  macsad.publication_catalog_v,
  macsad.audit_timeline_v,
  macsad.schema_version_v
FROM macsad_app;

GRANT UPDATE (
  operation_count,
  operation_catalog_digest,
  operations_sealed_by_actor_id,
  operations_sealed_at
) ON macsad.tool_repository_revision TO macsad_app;

GRANT UPDATE ON
  macsad.workspace,
  macsad.tool_repository,
  macsad.policy_revision,
  macsad.actor,
  macsad.actor_identity,
  macsad.membership,
  macsad.capability_grant,
  macsad.research_case,
  macsad.task,
  macsad.thread,
  macsad.task_assignment,
  macsad.execution,
  macsad.execution_tool_use,
  macsad.model_call,
  macsad.publication_batch,
  macsad.publication_attempt,
  macsad.publication_head,
  macsad.command_receipt,
  macsad.inbound_delivery,
  macsad.outbox_message
TO macsad_app;

GRANT EXECUTE ON FUNCTION macsad.record_budget_entry(
  uuid, macsad.budget_entry_kind, numeric, text, macsad.sha256_digest,
  uuid, uuid, uuid, uuid, uuid, text
) TO macsad_app, macsad_migrator;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA macsad_meta TO macsad_migrator;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA macsad TO macsad_migrator;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA macsad TO macsad_migrator;

INSERT INTO macsad_meta.schema_migration(version, name, script_sha256)
VALUES (
  1,
  '0001_initial_schema',
  pg_catalog.decode(:'migration_sha256', 'hex')
);

COMMIT;
