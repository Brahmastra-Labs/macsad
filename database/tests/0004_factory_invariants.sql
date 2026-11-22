-- Mechanical invariants for 0004_factory.sql, exercised as macsad_app, the role the coordinator's macsad_runtime login inherits.
--
-- Run this as a login that may SET ROLE macsad_app. Every fixture is discarded by the
-- unconditional ROLLBACK below. Each refusal is asserted by its exact error, so a check that
-- stopped refusing — or refused for a different reason — fails this file.

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';
SET LOCAL ROLE macsad_owner;
SET LOCAL ROLE macsad_app;

DO $invariants$
DECLARE
  zeros text := repeat('0', 64);
  h1 text := encode(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 'hex');
  h2 text := encode(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 'hex');
  t1 bigint;
  t2 bigint;
  claimed record;
  refused boolean;
BEGIN
  INSERT INTO factory.problem (id, title, source, cohort, collection, category, statement_informal, status)
  VALUES ('test:P1', 'A test problem', 'test', 'cohort', 'collection', 'category', 'informal', 'open');

  -- The trail: genesis, then exactly the next link.
  INSERT INTO factory.trail_entry VALUES ('test:P1', 1, 0, 'progress', 'prove', 'c', 'm', 's', 'p', 'f', '{}', 'rejected', 1, '', 0, 'first', '{}', zeros, h1);

  refused := false;
  BEGIN
    INSERT INTO factory.trail_entry VALUES ('test:P1', 2, 0, 'progress', 'prove', 'c', 'm', 's', 'p', 'f', '{}', 'rejected', 1, '', 0, 'bad link', '{}', repeat('9', 64), h2);
  EXCEPTION WHEN check_violation THEN
    refused := SQLERRM = 'factory.trail_chain';
  END;
  ASSERT refused, 'a trail entry whose prev_hash is not the last hash is refused';

  refused := false;
  BEGIN
    INSERT INTO factory.trail_entry VALUES ('test:P1', 3, 0, 'progress', 'prove', 'c', 'm', 's', 'p', 'f', '{}', 'rejected', 1, '', 0, 'skip', '{}', h1, h2);
  EXCEPTION WHEN check_violation THEN
    refused := SQLERRM = 'factory.trail_chain';
  END;
  ASSERT refused, 'a trail entry that skips a seq is refused';

  refused := false;
  BEGIN
    INSERT INTO factory.trail_entry VALUES ('test:P1', 1, 0, 'progress', 'prove', 'c', 'm', 's', 'p', 'f', '{}', 'rejected', 1, '', 0, 'second genesis', '{}', zeros, h2);
  EXCEPTION WHEN unique_violation OR check_violation THEN
    refused := true;
  END;
  ASSERT refused, 'a second genesis is refused';

  INSERT INTO factory.trail_entry VALUES ('test:P1', 2, 0, 'progress', 'prove', 'c', 'm', 's', 'p', 'f', '{}', 'rejected', 1, '', 0, 'second', '{}', h1, h2);

  refused := false;
  BEGIN
    UPDATE factory.trail_entry SET summary = 'rewritten' WHERE problem_id = 'test:P1' AND seq = 1;
  EXCEPTION WHEN insufficient_privilege THEN
    refused := true;
  END;
  ASSERT refused, 'the runtime cannot rewrite the trail';

  refused := false;
  BEGIN
    DELETE FROM factory.trail_entry WHERE problem_id = 'test:P1';
  EXCEPTION WHEN insufficient_privilege THEN
    refused := true;
  END;
  ASSERT refused, 'the runtime cannot delete the trail';

  -- Leases: one holder per unit, strictly increasing tokens, a stale token changes nothing.
  INSERT INTO factory.work_unit (id, problem_id, kind, priority, state)
  VALUES ('test:u1', 'test:P1', 'prove', 10, 'ready'), ('test:u2', 'test:P1', 'prove', 5, 'ready');

  SELECT * INTO claimed FROM factory.claim_unit('worker-a', 60000, NULL);
  ASSERT claimed.unit_id = 'test:u1', 'the highest-priority ready unit is offered first';
  t1 := claimed.token;
  SELECT * INTO claimed FROM factory.claim_unit('worker-b', 60000, NULL);
  ASSERT claimed.unit_id = 'test:u2', 'a leased unit is not offered again';
  t2 := claimed.token;
  ASSERT t2 > t1, 'fencing tokens strictly increase';
  SELECT * INTO claimed FROM factory.claim_unit('worker-c', 60000, NULL);
  ASSERT claimed.unit_id IS NULL, 'nothing is offered when every unit is leased';

  ASSERT NOT factory.finish_unit('test:u1', t2, 'done'), 'another holder''s token cannot finish a unit';
  ASSERT factory.heartbeat_unit('test:u1', t1, 60000), 'the holder can extend its lease';
  ASSERT factory.finish_unit('test:u1', t1, 'done'), 'the holder finishes its unit';
  ASSERT NOT factory.finish_unit('test:u1', t1, 'done'), 'a unit is finished once';

  -- Dead ends are recorded once.
  INSERT INTO factory.attempt VALUES ('test:a1', 'test:u2', 'test:P1', 'c', 'm', 's', repeat('a', 64), repeat('b', 64), NULL, repeat('c', 64), 'rejected', '{}', 0, now(), now());
  INSERT INTO factory.dead_end (problem_id, approach_fingerprint, first_attempt_id) VALUES ('test:P1', repeat('c', 64), 'test:a1');
  refused := false;
  BEGIN
    INSERT INTO factory.dead_end (problem_id, approach_fingerprint, first_attempt_id) VALUES ('test:P1', repeat('c', 64), 'test:a1');
  EXCEPTION WHEN unique_violation THEN
    refused := true;
  END;
  ASSERT refused, 'the same dead end is not recorded twice';

  -- Solved needs a verified attestation of the accepted statement.
  refused := false;
  BEGIN
    INSERT INTO factory.node (id, kind, label, problem_id, stage) VALUES ('test:n1', 'problem', 'P1', 'test:P1', 'solved');
  EXCEPTION WHEN check_violation THEN
    refused := SQLERRM = 'factory.solved_without_attestation';
  END;
  ASSERT refused, 'a problem cannot be solved without an attestation';

  INSERT INTO factory.statement (id, problem_id, document, sha256, goal_name, route, review_state, author, model)
  VALUES ('test:s1', 'test:P1', 'Definition goal : Prop := True.', encode(sha256(convert_to('test:s1:' || gen_random_uuid()::text, 'UTF8')), 'hex'), 'goal', 'C', 'accepted', 'a', 'm');
  INSERT INTO factory.attestation (id, subject_kind, subject_id, statement_sha, document_sha, verdict_kind, verifier, toolchain_sha, public_key_sha, signature)
  VALUES ('test:att1', 'attempt', 'test:a1', (SELECT sha256 FROM factory.statement WHERE id = 'test:s1'), repeat('e', 64), 'verified', 'verifier-1', repeat('f', 64), repeat('0', 64), 'ab');
  INSERT INTO factory.node (id, kind, label, problem_id, stage) VALUES ('test:n1', 'problem', 'P1', 'test:P1', 'solved');

  refused := false;
  BEGIN
    UPDATE factory.statement SET review_state = 'accepted' WHERE id = 'test:s1';
    UPDATE factory.statement SET goal_name = 'other' WHERE id = 'test:s1';
  EXCEPTION WHEN insufficient_privilege OR object_not_in_prerequisite_state THEN
    refused := true;
  END;
  ASSERT refused, 'an accepted statement''s document and goal never change';
END
$invariants$;

ROLLBACK;
