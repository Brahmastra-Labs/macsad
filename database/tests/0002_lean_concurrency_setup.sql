-- NEW committed concurrency fixture, sharing the same explicit offer/accept setup.
-- No original fixture or original assertion is altered.
-- Prerequisite: pristine PG16 database -> migration 0001 -> unchanged complete
-- representative_v1 (committed) -> migration 0002. Only this dedicated fresh test DB is used.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE macsad_owner;
SET LOCAL timezone='UTC';
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

CREATE FUNCTION pg_temp.require(p_ok boolean,p_message text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
 IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'control failed: %',p_message USING ERRCODE='P0999'; END IF;
END $$;
CREATE FUNCTION pg_temp.reject(p_sql text,p_code text,p_message text) RETURNS void
LANGUAGE plpgsql AS $$ DECLARE actual text; BEGIN
 BEGIN EXECUTE p_sql;
 EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE;
   IF actual<>p_code THEN RAISE EXCEPTION 'control %: wanted %, received % (%)',p_message,p_code,actual,SQLERRM; END IF;
   RETURN;
 END;
 RAISE EXCEPTION 'control % unexpectedly accepted',p_message USING ERRCODE='P0999';
END $$;
SELECT pg_temp.require(current_setting('server_version_num')::int BETWEEN 160000 AND 169999,'PG16 required');
SELECT pg_temp.require((SELECT current_version=2 FROM macsad.schema_version_v),'migration2 required');
SELECT pg_temp.require((SELECT count(*)=3 AND bool_and(state='closed') FROM macsad.research_case),'original fixture remains terminal');

-- NEW test-only policy/auth facts. These do not authenticate any real person.
-- The historical revoked grants/identity remain untouched.
INSERT INTO macsad.actor_identity(id,actor_id,issuer,subject,audience)
VALUES('91100000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000004','test://lean','worker','macsad-worker'),
 ('91100000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000005','test://lean','controller','macsad-controller');
INSERT INTO macsad.capability_grant(workspace_id,actor_id,capability_code,granted_by_actor_id,reason)
VALUES('10000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','lean.submit','11000000-0000-4000-8000-000000000001','NEW test-only submit authorization'),
 ('10000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000004','lean.worker','11000000-0000-4000-8000-000000000001','NEW test-only worker authorization'),
 ('10000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000005','lean.expire','11000000-0000-4000-8000-000000000001','NEW test-only expiry authorization');
INSERT INTO macsad.problem_revision(id,workspace_id,research_kind,title,original_question,definitions,assumptions,
 domain_bounds,success_criteria,refutation_criteria,inconclusive_criteria,kind_schema_id,kind_schema_version,kind_body,content_digest,created_by_actor_id)
SELECT '91700000-0000-4000-8000-000000000001',workspace_id,research_kind,'New Lean attempt control',original_question,definitions,assumptions,
 domain_bounds,success_criteria,refutation_criteria,inconclusive_criteria,kind_schema_id,kind_schema_version,kind_body,
 macsad.lean_digest('{"control":"new-lean-problem"}'),'11000000-0000-4000-8000-000000000001'
FROM macsad.problem_revision WHERE id='17000000-0000-4000-8000-000000000002';
INSERT INTO macsad.research_case(id,workspace_id,workspace_snapshot_id,policy_revision_id,problem_revision_id,process_key,tool_closure_digest)
SELECT '91800000-0000-4000-8000-000000000001',workspace_id,workspace_snapshot_id,policy_revision_id,
 '91700000-0000-4000-8000-000000000001',process_key,tool_closure_digest
FROM macsad.research_case WHERE id='18000000-0000-4000-8000-000000000002';
INSERT INTO macsad.task(id,workspace_id,research_case_id,policy_revision_id,problem_revision_id,process_key,node_key,
 sequence_no,board_phase,required_profile_key,required_profile_digest,input_closure_digest)
SELECT '91900000-0000-4000-8000-000000000001',workspace_id,'91800000-0000-4000-8000-000000000001',policy_revision_id,
 '91700000-0000-4000-8000-000000000001',process_key,node_key,1,board_phase,required_profile_key,required_profile_digest,input_closure_digest
FROM macsad.task WHERE id='19000000-0000-4000-8000-000000000001';
INSERT INTO macsad.task_assignment(id,workspace_id,task_id,offered_actor_id,offered_membership_id,offered_by_actor_id,
 policy_revision_id,profile_key,profile_digest,package_digest,reason)
SELECT '91940000-0000-4000-8000-000000000001',workspace_id,'91900000-0000-4000-8000-000000000001',offered_actor_id,
 offered_membership_id,offered_by_actor_id,policy_revision_id,profile_key,profile_digest,
 macsad.lean_digest('{"control":"new-reviewed-offer"}'),'NEW test-only reviewed offer'
FROM macsad.task_assignment WHERE id='19400000-0000-4000-8000-000000000002';

INSERT INTO macsad.blob(digest,byte_length,media_type,storage_provider,storage_locator,storage_class,stored_at,verified_at)
VALUES(sha256(convert_to('theorem t : True := True.intro','UTF8')),octet_length('theorem t : True := True.intro'),'text/plain','test','lean-source-control','private',clock_timestamp(),clock_timestamp());
INSERT INTO macsad.artifact(id,workspace_id,blob_digest,artifact_kind,classification,secret_scan_result,producing_actor_id)
VALUES('91200000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
 sha256(convert_to('theorem t : True := True.intro','UTF8')),'lean_source','private','passed','11000000-0000-4000-8000-000000000001');
CREATE TEMP TABLE lean_control_state(result jsonb);
GRANT SELECT,INSERT,UPDATE ON lean_control_state TO macsad_app;

-- No accepted-assignment shortcut: the real offer is refused, then the fixture
-- executes legal offer->accepted and offered->ready transitions explicitly.
SELECT pg_temp.reject($q$SELECT macsad.lean_submit('11100000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
 '91940000-0000-4000-8000-000000000001',0,'before-accept','91200000-0000-4000-8000-000000000001','t',
 '11000000-0000-4000-8000-000000000004',macsad.lean_digest('{}'),'{}',macsad.lean_digest('{}'))$q$,'55000','unaccepted assignment');
UPDATE macsad.task_assignment SET state='accepted',accepted_at=clock_timestamp(),version=1 WHERE id='91940000-0000-4000-8000-000000000001';
UPDATE macsad.task SET state='ready',version=1 WHERE id='91900000-0000-4000-8000-000000000001';
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
