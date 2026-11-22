-- The math factory: problems, statements, work units, leases, attempts, the problem trail,
-- lemmas, strategies and attestations — the coordinator's durable state.
--
-- Forward-only. Migrations 0001-0003 remain immutable. Everything lives in its own `factory`
-- schema so the original MaCSad domain model is untouched.
--
-- Invariants the database itself enforces (the LOGOS coordinator decides everything else):
--   * the problem trail is APPEND-ONLY and hash-chained: an entry's seq is one past the last, its
--     prev_hash is the last entry's hash (64 zeros for the first), and no entry is ever updated or
--     deleted;
--   * a work unit is leased to at most one holder at a time, under a fencing token that strictly
--     increases, so a stale holder's late completion is refused;
--   * a failed approach (problem, fingerprint) is recorded once and refused thereafter, so
--     distributed contributors never pay twice for the same dead end;
--   * a statement's document is immutable once written, and a node can reach `solved` only with a
--     verifier attestation for its statement.
\set ON_ERROR_STOP on
\if :{?migration_sha256}
SELECT (:'migration_sha256' ~ '^[0-9a-f]{64}$') AS migration_sha256_valid \gset
\if :migration_sha256_valid
\else
\quit 3
\endif
\else
\quit 3
\endif
BEGIN;
SET LOCAL ROLE macsad_owner;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '5min';
SELECT pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('macsad:schema-migration', 0));

CREATE SCHEMA factory AUTHORIZATION macsad_owner;
SET LOCAL search_path = pg_catalog, factory;

CREATE DOMAIN factory.sha256 AS text CHECK (VALUE ~ '^[0-9a-f]{64}$');

-- ── problems and the hierarchy ──────────────────────────────────────────────────────────────────

CREATE TABLE factory.problem (
  id                 text PRIMARY KEY CHECK (length(id) BETWEEN 1 AND 200),
  title              text NOT NULL CHECK (length(title) <= 1000),
  source             text NOT NULL,
  cohort             text NOT NULL,
  collection         text NOT NULL,
  category           text NOT NULL,
  statement_informal text NOT NULL,
  lean_statement     text,
  lean_module        text,
  lean_declaration   text,
  external_key       text,
  cross_ref          text,
  status             text NOT NULL CHECK (status IN ('open', 'solved_upstream', 'disputed', 'ill_posed', 'unknown')),
  opdp               jsonb CHECK (opdp IS NULL OR jsonb_typeof(opdp) = 'object'),
  rank               integer NOT NULL DEFAULT 0,
  created_at         timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX problem_rank_idx ON factory.problem (rank DESC);
CREATE INDEX problem_collection_idx ON factory.problem (cohort, collection, category);

CREATE TABLE factory.node (
  id         text PRIMARY KEY,
  parent_id  text REFERENCES factory.node (id),
  kind       text NOT NULL CHECK (kind IN ('root', 'cohort', 'collection', 'category', 'problem', 'statement', 'lemma')),
  label      text NOT NULL,
  problem_id text REFERENCES factory.problem (id),
  stage      text NOT NULL CHECK (stage IN ('ranked', 'formalizing', 'formalized', 'in_progress', 'partial', 'solved', 'refuted', 'invalid_formalization')),
  rank       integer NOT NULL DEFAULT 0,
  CHECK ((kind IN ('problem', 'statement', 'lemma')) = (problem_id IS NOT NULL))
);
CREATE INDEX node_parent_idx ON factory.node (parent_id, rank DESC);

-- ── statements (formal LOGOS documents) ─────────────────────────────────────────────────────────

CREATE TABLE factory.statement (
  id           text PRIMARY KEY,
  problem_id   text NOT NULL REFERENCES factory.problem (id),
  document     text NOT NULL CHECK (octet_length(document) <= 4194304),
  sha256       factory.sha256 NOT NULL UNIQUE,
  goal_name    text NOT NULL CHECK (goal_name ~ '^[A-Za-z_][A-Za-z0-9_.]*$'),
  route        text NOT NULL CHECK (route IN ('A', 'B', 'C')),
  review_state text NOT NULL CHECK (review_state IN ('draft', 'reviewing', 'accepted', 'rejected', 'superseded')),
  author       text NOT NULL,
  model        text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX statement_one_accepted_per_problem
  ON factory.statement (problem_id) WHERE review_state = 'accepted';

-- The document a statement names is what its hash says, forever.
CREATE FUNCTION factory.statement_document_immutable() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF NEW.document IS DISTINCT FROM OLD.document OR NEW.sha256 IS DISTINCT FROM OLD.sha256
     OR NEW.goal_name IS DISTINCT FROM OLD.goal_name OR NEW.problem_id IS DISTINCT FROM OLD.problem_id THEN
    RAISE EXCEPTION 'factory.statement_immutable' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER statement_document_immutable BEFORE UPDATE ON factory.statement
  FOR EACH ROW EXECUTE FUNCTION factory.statement_document_immutable();
CREATE TRIGGER statement_never_deleted BEFORE DELETE ON factory.statement
  FOR EACH ROW EXECUTE FUNCTION factory.statement_document_immutable();

-- ── contributors and strategies ─────────────────────────────────────────────────────────────────

CREATE TABLE factory.contributor (
  id            text PRIMARY KEY CHECK (id ~ '^[A-Za-z0-9_.:-]{1,80}$'),
  display_name  text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 120),
  budget_micros bigint NOT NULL CHECK (budget_micros >= 0),
  spent_micros  bigint NOT NULL DEFAULT 0 CHECK (spent_micros >= 0),
  focus         text NOT NULL DEFAULT '',
  joined_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE factory.strategy (
  id             text PRIMARY KEY,
  version        integer NOT NULL CHECK (version >= 1),
  parent_id      text REFERENCES factory.strategy (id),
  unit_kind      text NOT NULL,
  model          text NOT NULL,
  temperature_bp integer NOT NULL CHECK (temperature_bp BETWEEN 0 AND 20000),
  max_tokens     integer NOT NULL CHECK (max_tokens BETWEEN 1 AND 1000000),
  playbook       text NOT NULL,
  context_rules  text NOT NULL,
  status         text NOT NULL CHECK (status IN ('candidate', 'active', 'retired')),
  created_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE factory.strategy_eval (
  strategy_id     text NOT NULL REFERENCES factory.strategy (id),
  calibration_set text NOT NULL,
  attempts        integer NOT NULL CHECK (attempts >= 0),
  verified        integer NOT NULL CHECK (verified BETWEEN 0 AND attempts),
  cost_micros     bigint NOT NULL CHECK (cost_micros >= 0),
  evaluated_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (strategy_id, calibration_set, evaluated_at)
);

-- ── work units and leases ───────────────────────────────────────────────────────────────────────

CREATE SEQUENCE factory.lease_token;

CREATE TABLE factory.work_unit (
  id             text PRIMARY KEY,
  problem_id     text NOT NULL REFERENCES factory.problem (id),
  statement_id   text REFERENCES factory.statement (id),
  parent_unit_id text REFERENCES factory.work_unit (id),
  kind           text NOT NULL CHECK (kind IN ('formalize', 'review', 'prove', 'decompose', 'special_case', 'counterexample', 'repair', 'summarize_trail', 'link', 'improve_strategy', 'verify')),
  priority       integer NOT NULL,
  state          text NOT NULL CHECK (state IN ('ready', 'leased', 'done', 'failed', 'cancelled')),
  holder         text,
  lease_token    bigint,
  leased_at      timestamptz,
  expires_at     timestamptz,
  heartbeat_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK ((state = 'leased') = (holder IS NOT NULL AND lease_token IS NOT NULL AND expires_at IS NOT NULL))
);
CREATE INDEX work_unit_ready_idx ON factory.work_unit (priority DESC, created_at) WHERE state = 'ready';

-- Leases that outlived their holder return to `ready`; a unit is offered to one holder at a time.
CREATE FUNCTION factory.claim_unit(p_holder text, p_ttl_ms integer, p_kinds text[])
RETURNS TABLE (unit_id text, token bigint, problem_id text, statement_id text, kind text)
LANGUAGE plpgsql SET search_path = pg_catalog, factory AS $$
DECLARE u factory.work_unit; t bigint;
BEGIN
  IF p_holder IS NULL OR length(p_holder) NOT BETWEEN 1 AND 80 OR p_ttl_ms NOT BETWEEN 1000 AND 86400000 THEN
    RAISE EXCEPTION 'factory.invalid_claim' USING ERRCODE = '22023';
  END IF;
  UPDATE factory.work_unit w SET state = 'ready', holder = NULL, lease_token = NULL,
         leased_at = NULL, expires_at = NULL, heartbeat_at = NULL
   WHERE w.state = 'leased' AND w.expires_at < clock_timestamp();
  SELECT * INTO u FROM factory.work_unit w
   WHERE w.state = 'ready' AND (p_kinds IS NULL OR w.kind = ANY (p_kinds))
   ORDER BY w.priority DESC, w.created_at
   LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN; END IF;
  t := nextval('factory.lease_token');
  UPDATE factory.work_unit w SET state = 'leased', holder = p_holder, lease_token = t,
         leased_at = clock_timestamp(), heartbeat_at = clock_timestamp(),
         expires_at = clock_timestamp() + make_interval(secs => p_ttl_ms / 1000.0)
   WHERE w.id = u.id;
  RETURN QUERY SELECT u.id, t, u.problem_id, u.statement_id, u.kind;
END $$;

CREATE FUNCTION factory.heartbeat_unit(p_unit text, p_token bigint, p_ttl_ms integer)
RETURNS boolean LANGUAGE plpgsql SET search_path = pg_catalog, factory AS $$
BEGIN
  UPDATE factory.work_unit w SET heartbeat_at = clock_timestamp(),
         expires_at = clock_timestamp() + make_interval(secs => p_ttl_ms / 1000.0)
   WHERE w.id = p_unit AND w.state = 'leased' AND w.lease_token = p_token AND w.expires_at >= clock_timestamp();
  RETURN FOUND;
END $$;

-- Only the holder of the CURRENT token finishes a unit; a stale holder's completion changes nothing.
CREATE FUNCTION factory.finish_unit(p_unit text, p_token bigint, p_state text)
RETURNS boolean LANGUAGE plpgsql SET search_path = pg_catalog, factory AS $$
BEGIN
  IF p_state NOT IN ('done', 'failed', 'ready') THEN
    RAISE EXCEPTION 'factory.invalid_finish' USING ERRCODE = '22023';
  END IF;
  UPDATE factory.work_unit w SET state = p_state, holder = NULL, lease_token = NULL,
         leased_at = NULL, expires_at = NULL, heartbeat_at = NULL
   WHERE w.id = p_unit AND w.state = 'leased' AND w.lease_token = p_token;
  RETURN FOUND;
END $$;

-- ── attempts and the dead ends nobody should pay for twice ─────────────────────────────────────

CREATE TABLE factory.attempt (
  id                   text PRIMARY KEY,
  unit_id              text NOT NULL REFERENCES factory.work_unit (id),
  problem_id           text NOT NULL REFERENCES factory.problem (id),
  contributor          text NOT NULL,
  model                text NOT NULL,
  strategy_id          text NOT NULL,
  prompt_sha           factory.sha256 NOT NULL,
  response_sha         factory.sha256 NOT NULL,
  document_sha         factory.sha256,
  approach_fingerprint factory.sha256 NOT NULL,
  verdict_kind         text NOT NULL CHECK (verdict_kind IN ('verified', 'rejected', 'admitted_axiom', 'infrastructure', 'refused_submission', 'budget_exhausted')),
  verdict              jsonb NOT NULL CHECK (jsonb_typeof(verdict) = 'object'),
  cost_micros          bigint NOT NULL CHECK (cost_micros >= 0),
  started_at           timestamptz NOT NULL,
  finished_at          timestamptz NOT NULL CHECK (finished_at >= started_at)
);
CREATE INDEX attempt_problem_idx ON factory.attempt (problem_id, finished_at);

CREATE TABLE factory.dead_end (
  problem_id           text NOT NULL REFERENCES factory.problem (id),
  approach_fingerprint factory.sha256 NOT NULL,
  first_attempt_id     text NOT NULL REFERENCES factory.attempt (id),
  recorded_at          timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (problem_id, approach_fingerprint)
);

-- ── the problem trail: append-only and hash-chained ─────────────────────────────────────────────

CREATE TABLE factory.trail_entry (
  problem_id           text NOT NULL REFERENCES factory.problem (id),
  seq                  bigint NOT NULL CHECK (seq >= 1),
  ts                   bigint NOT NULL,
  stage                text NOT NULL,
  kind                 text NOT NULL,
  contributor          text NOT NULL,
  model                text NOT NULL,
  strategy_id          text NOT NULL,
  prompt_sha           text NOT NULL,
  approach_fingerprint text NOT NULL,
  artifact_shas        text[] NOT NULL,
  verdict              text NOT NULL,
  exit_code            integer NOT NULL,
  diagnostics          text NOT NULL CHECK (octet_length(diagnostics) <= 65536),
  cost_micros          bigint NOT NULL CHECK (cost_micros >= 0),
  summary              text NOT NULL CHECK (octet_length(summary) <= 16384),
  next_suggestions     text[] NOT NULL,
  prev_hash            factory.sha256 NOT NULL,
  hash                 factory.sha256 NOT NULL UNIQUE,
  PRIMARY KEY (problem_id, seq)
);

CREATE FUNCTION factory.trail_append_only() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, factory AS $$
DECLARE last factory.trail_entry;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'factory.trail_append_only' USING ERRCODE = '55000';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('factory:trail:' || NEW.problem_id, 0));
  SELECT * INTO last FROM factory.trail_entry t WHERE t.problem_id = NEW.problem_id ORDER BY t.seq DESC LIMIT 1;
  IF NOT FOUND THEN
    IF NEW.seq <> 1 OR NEW.prev_hash <> repeat('0', 64) THEN
      RAISE EXCEPTION 'factory.trail_genesis' USING ERRCODE = '23514';
    END IF;
  ELSIF NEW.seq <> last.seq + 1 OR NEW.prev_hash <> last.hash THEN
    RAISE EXCEPTION 'factory.trail_chain' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trail_append_only BEFORE INSERT OR UPDATE OR DELETE ON factory.trail_entry
  FOR EACH ROW EXECUTE FUNCTION factory.trail_append_only();

-- ── lemmas and attestations ─────────────────────────────────────────────────────────────────────

CREATE TABLE factory.lemma (
  id            text PRIMARY KEY,
  name          text NOT NULL,
  statement     text NOT NULL,
  statement_sha factory.sha256 NOT NULL UNIQUE,
  problem_id    text NOT NULL REFERENCES factory.problem (id),
  document_sha  factory.sha256 NOT NULL,
  status        text NOT NULL CHECK (status IN ('verified', 'retracted')),
  axioms        text[] NOT NULL
);

CREATE TABLE factory.attestation (
  id             text PRIMARY KEY,
  subject_kind   text NOT NULL CHECK (subject_kind IN ('attempt', 'statement', 'lemma')),
  subject_id     text NOT NULL,
  statement_sha  factory.sha256 NOT NULL,
  document_sha   factory.sha256 NOT NULL,
  verdict_kind   text NOT NULL CHECK (verdict_kind IN ('verified', 'rejected', 'admitted_axiom', 'infrastructure')),
  verifier       text NOT NULL,
  toolchain_sha  factory.sha256 NOT NULL,
  public_key_sha factory.sha256 NOT NULL,
  signature      text NOT NULL CHECK (signature ~ '^[0-9a-f]+$'),
  created_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (subject_kind, subject_id, verifier)
);

-- A problem node is `solved` only on a verified attestation of its accepted statement.
CREATE FUNCTION factory.node_solved_needs_attestation() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, factory AS $$
BEGIN
  IF NEW.stage = 'solved' AND NEW.kind IN ('problem', 'statement') THEN
    PERFORM 1 FROM factory.attestation a
      JOIN factory.statement s ON s.sha256 = a.statement_sha
     WHERE s.problem_id = NEW.problem_id AND s.review_state = 'accepted' AND a.verdict_kind = 'verified';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'factory.solved_without_attestation' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER node_solved_needs_attestation BEFORE INSERT OR UPDATE ON factory.node
  FOR EACH ROW EXECUTE FUNCTION factory.node_solved_needs_attestation();

-- ── grants: the runtime reads and appends; only the owner changes the shape ─────────────────────

GRANT USAGE ON SCHEMA factory TO macsad_app;
GRANT SELECT ON ALL TABLES IN SCHEMA factory TO macsad_app;
GRANT INSERT ON factory.problem, factory.node, factory.statement, factory.contributor, factory.strategy,
  factory.strategy_eval, factory.work_unit, factory.attempt, factory.dead_end, factory.trail_entry,
  factory.lemma, factory.attestation TO macsad_app;
GRANT UPDATE (rank, status, opdp) ON factory.problem TO macsad_app;
GRANT UPDATE (stage, rank) ON factory.node TO macsad_app;
GRANT UPDATE (review_state) ON factory.statement TO macsad_app;
GRANT UPDATE (spent_micros, focus, display_name) ON factory.contributor TO macsad_app;
GRANT UPDATE (status) ON factory.strategy, factory.lemma TO macsad_app;
GRANT UPDATE (state, holder, lease_token, leased_at, expires_at, heartbeat_at) ON factory.work_unit TO macsad_app;
GRANT USAGE ON SEQUENCE factory.lease_token TO macsad_app;
GRANT EXECUTE ON FUNCTION factory.claim_unit(text, integer, text[]), factory.heartbeat_unit(text, bigint, integer),
  factory.finish_unit(text, bigint, text) TO macsad_app;
GRANT SELECT ON ALL TABLES IN SCHEMA factory TO macsad_reader;
GRANT USAGE ON SCHEMA factory TO macsad_reader;

INSERT INTO macsad_meta.schema_migration(version,name,script_sha256)
VALUES(4,'0004_factory',decode(:'migration_sha256','hex'));
COMMIT;
