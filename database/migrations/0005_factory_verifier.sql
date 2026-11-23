-- The verifier's word, tightened and made checkable by anyone.
--
-- Forward-only. Migrations 0001-0004 remain immutable.
--
--   * A problem (or statement) node reaches `solved` only on the verifier's `verified` attestation
--     of an ATTEMPT on that problem, made against its accepted statement. In 0004 any verified
--     attestation naming the accepted statement's hash sufficed — including the attestation that
--     accepted the statement itself, which says the statement is well formed, never that it is
--     proved.
--   * `factory.verifier_key` publishes each verifier's ML-DSA-65 public key beside the SHA-256 every
--     attestation names, so a signature can be checked without trusting the coordinator: the
--     database refuses a key that does not hash to its name, and nobody rewrites or removes one.
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

SET LOCAL search_path = pg_catalog, factory;

-- ── solved means a proof attempt was attested ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION factory.node_solved_needs_attestation() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, factory AS $$
BEGIN
  IF NEW.stage = 'solved' AND NEW.kind IN ('problem', 'statement') THEN
    PERFORM 1 FROM factory.attestation a
      JOIN factory.attempt x ON x.id = a.subject_id AND x.problem_id = NEW.problem_id
      JOIN factory.statement s ON s.sha256 = a.statement_sha
     WHERE a.subject_kind = 'attempt' AND a.verdict_kind = 'verified'
       AND s.problem_id = NEW.problem_id AND s.review_state = 'accepted';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'factory.solved_without_attestation' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- ── the verifiers' public keys ──────────────────────────────────────────────────────────────────

-- An ML-DSA-65 public key is 1952 bytes: 3904 lowercase hex digits. A verifier is named by the
-- first twelve hex digits of its key's hash, as the factory's verifier names itself.
CREATE TABLE factory.verifier_key (
  public_key_sha factory.sha256 PRIMARY KEY,
  verifier       text NOT NULL UNIQUE,
  public_key     text NOT NULL,
  registered_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT verifier_key_shape CHECK (octet_length(public_key) = 3904 AND public_key ~ '^[0-9a-f]+$'),
  CONSTRAINT verifier_key_hash CHECK (public_key_sha::text = encode(sha256(decode(public_key, 'hex')), 'hex')),
  CONSTRAINT verifier_key_name CHECK (verifier = 'verifier-' || left(public_key_sha::text, 12))
);

-- ── grants: the runtime and the verifier publish a key; everyone may read one ─────────────────────

GRANT SELECT, INSERT ON factory.verifier_key TO macsad_app;
GRANT SELECT ON factory.verifier_key TO macsad_reader;

INSERT INTO macsad_meta.schema_migration(version,name,script_sha256)
VALUES(5,'0005_factory_verifier',decode(:'migration_sha256','hex'));
COMMIT;
