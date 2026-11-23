-- Mechanical invariants for 0005_factory_verifier.sql, exercised as macsad_app, the role the
-- coordinator's and the verifier's macsad_runtime login inherits.
--
-- Run this as a login that may SET ROLE macsad_app. Every fixture is discarded by the
-- unconditional ROLLBACK below. Each refusal is asserted by its exact error or constraint, so a
-- check that stopped refusing — or refused for a different reason — fails this file.

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';
SET LOCAL ROLE macsad_owner;
SET LOCAL ROLE macsad_app;

DO $invariants$
DECLARE
  statement_sha text := encode(sha256(convert_to('test5:s1:' || gen_random_uuid()::text, 'UTF8')), 'hex');
  key_hex text := repeat('5a', 1952);
  key_sha text := encode(sha256(decode(repeat('5a', 1952), 'hex')), 'hex');
  refused boolean;
  failed_constraint text;
BEGIN
  INSERT INTO factory.problem (id, title, source, cohort, collection, category, statement_informal, status)
  VALUES ('test5:P1', 'A test problem', 'test', 'cohort', 'collection', 'category', 'informal', 'open'),
         ('test5:P2', 'Another test problem', 'test', 'cohort', 'collection', 'category', 'informal', 'open');
  INSERT INTO factory.statement (id, problem_id, document, sha256, goal_name, route, review_state, author, model)
  VALUES ('test5:s1', 'test5:P1', 'Definition goal : Prop := True.', statement_sha, 'goal', 'C', 'accepted', 'a', 'm');
  INSERT INTO factory.work_unit (id, problem_id, kind, priority, state)
  VALUES ('test5:u1', 'test5:P1', 'prove', 10, 'done'), ('test5:u2', 'test5:P2', 'prove', 10, 'done');
  INSERT INTO factory.attempt VALUES
    ('test5:a1', 'test5:u1', 'test5:P1', 'c', 'm', 's', repeat('a', 64), repeat('b', 64), repeat('d', 64), repeat('c', 64), 'verified', '{}', 0, now(), now()),
    ('test5:a2', 'test5:u2', 'test5:P2', 'c', 'm', 's', repeat('a', 64), repeat('b', 64), repeat('d', 64), repeat('e', 64), 'verified', '{}', 0, now(), now());
  INSERT INTO factory.node (id, kind, label, problem_id, stage) VALUES ('test5:n1', 'problem', 'P1', 'test5:P1', 'formalized');

  -- The attestation that accepted the statement does not solve the problem.
  INSERT INTO factory.attestation (id, subject_kind, subject_id, statement_sha, document_sha, verdict_kind, verifier, toolchain_sha, public_key_sha, signature)
  VALUES ('test5:att-statement', 'statement', 'test5:s1', statement_sha, statement_sha, 'verified', 'verifier-1', repeat('f', 64), key_sha, 'ab');
  refused := false;
  BEGIN
    UPDATE factory.node SET stage = 'solved' WHERE id = 'test5:n1';
  EXCEPTION WHEN check_violation THEN
    refused := SQLERRM = 'factory.solved_without_attestation';
  END;
  ASSERT refused, 'a statement''s own attestation does not solve its problem';

  -- Nor does an attested attempt on another problem that names this statement's hash.
  INSERT INTO factory.attestation (id, subject_kind, subject_id, statement_sha, document_sha, verdict_kind, verifier, toolchain_sha, public_key_sha, signature)
  VALUES ('test5:att-elsewhere', 'attempt', 'test5:a2', statement_sha, repeat('d', 64), 'verified', 'verifier-1', repeat('f', 64), key_sha, 'ab');
  refused := false;
  BEGIN
    UPDATE factory.node SET stage = 'solved' WHERE id = 'test5:n1';
  EXCEPTION WHEN check_violation THEN
    refused := SQLERRM = 'factory.solved_without_attestation';
  END;
  ASSERT refused, 'an attempt on another problem does not solve this one';

  -- Nor does a rejected attestation of an attempt on it.
  INSERT INTO factory.attestation (id, subject_kind, subject_id, statement_sha, document_sha, verdict_kind, verifier, toolchain_sha, public_key_sha, signature)
  VALUES ('test5:att-rejected', 'attempt', 'test5:a1', statement_sha, repeat('d', 64), 'rejected', 'verifier-1', repeat('f', 64), key_sha, 'ab');
  refused := false;
  BEGIN
    UPDATE factory.node SET stage = 'solved' WHERE id = 'test5:n1';
  EXCEPTION WHEN check_violation THEN
    refused := SQLERRM = 'factory.solved_without_attestation';
  END;
  ASSERT refused, 'a rejected attestation does not solve a problem';

  -- A verified attestation of an attempt on it, against its accepted statement, does.
  INSERT INTO factory.attestation (id, subject_kind, subject_id, statement_sha, document_sha, verdict_kind, verifier, toolchain_sha, public_key_sha, signature)
  VALUES ('test5:att-proof', 'attempt', 'test5:a1', statement_sha, repeat('d', 64), 'verified', 'verifier-2', repeat('f', 64), key_sha, 'ab');
  UPDATE factory.node SET stage = 'solved' WHERE id = 'test5:n1';
  ASSERT (SELECT stage FROM factory.node WHERE id = 'test5:n1') = 'solved', 'an attested proof solves its problem';

  -- Verifier keys: published once under the hash and name they hash to, never rewritten.
  INSERT INTO factory.verifier_key (public_key_sha, verifier, public_key)
  VALUES (key_sha, 'verifier-' || left(key_sha, 12), key_hex);
  ASSERT (SELECT encode(sha256(decode(public_key, 'hex')), 'hex') FROM factory.verifier_key WHERE public_key_sha = key_sha) = key_sha,
    'a published key hashes to its name';

  failed_constraint := '';
  BEGIN
    INSERT INTO factory.verifier_key (public_key_sha, verifier, public_key)
    VALUES (repeat('1', 64), 'verifier-111111111111', repeat('5b', 1952));
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
  END;
  ASSERT failed_constraint = 'verifier_key_hash', 'a key that does not hash to its name is refused';

  failed_constraint := '';
  BEGIN
    INSERT INTO factory.verifier_key (public_key_sha, verifier, public_key)
    VALUES (encode(sha256(decode(repeat('5b', 32), 'hex')), 'hex'), 'verifier-' || left(encode(sha256(decode(repeat('5b', 32), 'hex')), 'hex'), 12), repeat('5b', 32));
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
  END;
  ASSERT failed_constraint = 'verifier_key_shape', 'a key that is not an ML-DSA-65 public key is refused';

  failed_constraint := '';
  BEGIN
    INSERT INTO factory.verifier_key (public_key_sha, verifier, public_key)
    VALUES (encode(sha256(decode(repeat('5c', 1952), 'hex')), 'hex'), 'verifier-somebody', repeat('5c', 1952));
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
  END;
  ASSERT failed_constraint = 'verifier_key_name', 'a verifier is named by its key''s hash';

  refused := false;
  BEGIN
    INSERT INTO factory.verifier_key (public_key_sha, verifier, public_key)
    VALUES (key_sha, 'verifier-' || left(key_sha, 12), key_hex);
  EXCEPTION WHEN unique_violation THEN
    refused := true;
  END;
  ASSERT refused, 'a key is published once';

  refused := false;
  BEGIN
    UPDATE factory.verifier_key SET public_key = repeat('5c', 1952) WHERE public_key_sha = key_sha;
  EXCEPTION WHEN insufficient_privilege THEN
    refused := true;
  END;
  ASSERT refused, 'the runtime cannot rewrite a published key';

  refused := false;
  BEGIN
    DELETE FROM factory.verifier_key WHERE public_key_sha = key_sha;
  EXCEPTION WHEN insufficient_privilege THEN
    refused := true;
  END;
  ASSERT refused, 'the runtime cannot withdraw a published key';

  ASSERT has_table_privilege('macsad_reader', 'factory.verifier_key', 'SELECT'), 'the viewer can read the published keys';
  ASSERT NOT has_table_privilege('macsad_reader', 'factory.verifier_key', 'INSERT'), 'the viewer cannot publish a key';
END
$invariants$;

ROLLBACK;
