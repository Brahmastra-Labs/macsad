-- NEW controls; no edits to representative_v1 or any original assertions.
-- Prerequisite: pristine PG16 database -> migration 0001 -> unchanged complete
-- representative_v1 (committed) -> migration 0002. This script rolls itself back.
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
SET LOCAL ROLE macsad_app;

DO $controls$
DECLARE w uuid:='10000000-0000-4000-8000-000000000001'; identity uuid:='11100000-0000-4000-8000-000000000001';
 worker uuid:='91100000-0000-4000-8000-000000000001'; assignment uuid:='91940000-0000-4000-8000-000000000001';
 source uuid:='91200000-0000-4000-8000-000000000001'; d bytea:=macsad.lean_digest('{}'); first_result jsonb; next_result jsonb; e uuid;
 count_receipts bigint; count_events bigint; request_sql text;
BEGIN
 SELECT count(*) INTO count_receipts FROM macsad.command_receipt;
 SELECT count(*) INTO count_events FROM macsad.domain_event;
 request_sql:=format('SELECT macsad.lean_submit(%L,%L,%L,1,%L,%L,%L,%L,%L::bytea,%L::jsonb,%L::bytea)',
 identity,w,assignment,'submit-control',source,'t','11000000-0000-4000-8000-000000000004',d,'{}',d);
 PERFORM pg_temp.reject(replace(request_sql,quote_literal(identity::text),quote_literal('11100000-0000-4000-8000-000000000002')),'42501','revoked identity');
 PERFORM pg_temp.reject(replace(request_sql,quote_literal(identity::text),quote_literal(worker::text)),'42501','worker lacks submit capability');
 PERFORM pg_temp.reject(replace(request_sql,quote_literal(w::text),quote_literal('99900000-0000-4000-8000-000000000001')),'42501','wrong workspace');
 PERFORM pg_temp.reject(replace(request_sql,',1,',',0,'),'40001','stale task version');
 PERFORM pg_temp.require((SELECT count(*)=count_receipts FROM macsad.command_receipt),'refusal leaves no receipt');
 PERFORM pg_temp.require((SELECT count(*)=count_events FROM macsad.domain_event),'refusal leaves no audit event');
 EXECUTE request_sql INTO first_result;
 EXECUTE request_sql INTO next_result;
 PERFORM pg_temp.require(first_result=next_result,'exact replay returns identical receipt result');
 PERFORM pg_temp.require((SELECT count(*)=count_receipts+1 FROM macsad.command_receipt),'one receipt for duplicate');
 PERFORM pg_temp.require((SELECT count(*)=count_events+1 FROM macsad.domain_event),'one event for duplicate');
 e:=(first_result->>'execution_id')::uuid;
 PERFORM pg_temp.require((SELECT count(*)=1 FROM macsad.outbox_message WHERE topic='macsad.lean.execute' AND message_key=e::text),'atomic dispatch');
 PERFORM pg_temp.require((SELECT count(*)=1 FROM macsad.execution_artifact WHERE execution_id=e AND role='input'),'atomic source link');
 PERFORM pg_temp.reject(replace(request_sql,quote_literal('t'),quote_literal('different')),'40001','same key changed digest');
 PERFORM pg_temp.reject(replace(request_sql,quote_literal('submit-control'),quote_literal('second-live')),'40001','second live attempt refused');
 next_result:=macsad.lean_advance(worker,w,e,0,'claim-control','claim',0,60,'{}','{}',d);
 PERFORM pg_temp.require(next_result->>'state'='leased' AND next_result->>'fencing_token'='1','claim returns token1');
 PERFORM pg_temp.require((SELECT state='delivered' FROM macsad.outbox_message WHERE topic='macsad.lean.execute' AND message_key=e::text),'claim atomically consumes dispatch');
 PERFORM pg_temp.require(next_result=macsad.lean_advance(worker,w,e,0,'claim-control','claim',0,60,'{}','{}',d),'claim replay stable');
 PERFORM pg_temp.reject(format('SELECT macsad.lean_advance(%L,%L,%L,0,%L,%L,0,60,%L,%L,%L::bytea)',worker,w,e,'claim-other','claim','{}','{}',d),'40001','duplicate claim with new key');
 next_result:=macsad.lean_advance(worker,w,e,1,'start-control','start',1,60,'{}','{}',d);
 PERFORM pg_temp.reject(format('SELECT macsad.lean_advance(%L,%L,%L,2,%L,%L,2,60,%L,%L,%L::bytea)',worker,w,e,'wrong-fence','heartbeat','{}','{}',d),'40001','wrong fence');
 next_result:=macsad.lean_advance(worker,w,e,2,'heartbeat-control','heartbeat',1,60,'{}','{}',d);
 PERFORM pg_temp.require(next_result->>'version'='3','heartbeat increments version');
 INSERT INTO lean_control_state VALUES(next_result);
END $controls$;

-- Mechanical CAS registration is separate; all bytes would be verified by the
-- real host adapter. These tiny dummy blobs test DB linkage, NOT proof validity.
SET LOCAL ROLE macsad_owner;
INSERT INTO macsad.blob(digest,byte_length,media_type,storage_provider,storage_locator,storage_class,stored_at,verified_at)
SELECT sha256(convert_to(kind,'UTF8')),octet_length(kind),'application/octet-stream','test',kind,'private',clock_timestamp(),clock_timestamp()
FROM unnest(ARRAY['logos_source','logos_certificate','logos_package']) kind;
INSERT INTO macsad.artifact(id,workspace_id,blob_digest,artifact_kind,classification,secret_scan_result,producing_actor_id,producing_execution_id)
SELECT ('91200000-0000-4000-8000-00000000000'||ordinal)::uuid,'10000000-0000-4000-8000-000000000001',sha256(convert_to(kind,'UTF8')),kind,
 'private','passed','11000000-0000-4000-8000-000000000004',(SELECT (result->>'execution_id')::uuid FROM lean_control_state)
FROM (VALUES(2,'logos_source'),(3,'logos_certificate'),(4,'logos_package')) kinds(ordinal,kind);
SET LOCAL ROLE macsad_app;
DO $completion$
DECLARE e uuid:=(SELECT (result->>'execution_id')::uuid FROM lean_control_state); w uuid:='10000000-0000-4000-8000-000000000001';
 worker uuid:='91100000-0000-4000-8000-000000000001'; d bytea:=macsad.lean_digest('{}'); out_ids uuid[]:=ARRAY[
 '91200000-0000-4000-8000-000000000002','91200000-0000-4000-8000-000000000003','91200000-0000-4000-8000-000000000004']::uuid[];
 result jsonb; bad_ids uuid[]; before_events bigint;
BEGIN
 before_events:=(SELECT count(*) FROM macsad.domain_event);
 bad_ids:=out_ids; bad_ids[3]:='91200000-0000-4000-8000-000000000001';
 -- The third output fails after the first two link inserts: all must roll back.
 PERFORM pg_temp.reject(format('SELECT macsad.lean_advance(%L,%L,%L,3,%L,%L,1,60,%L,%L::uuid[],%L::bytea)',
 worker,w,e,'bad-completion','complete','{}',bad_ids,d),'22023','partial output set rolled back');
 PERFORM pg_temp.require((SELECT count(*)=1 FROM macsad.execution_artifact WHERE execution_id=e),'no partial finalized refs');
 PERFORM pg_temp.require((SELECT state='running' AND version=3 FROM macsad.execution WHERE id=e),'failed completion unchanged');
 PERFORM pg_temp.require((SELECT count(*)=before_events FROM macsad.domain_event),'failed completion no event');
 result:=macsad.lean_advance(worker,w,e,3,'complete-control','complete',1,60,'{"receipt":"opaque-policy-result"}',out_ids,d);
 PERFORM pg_temp.require(result->>'state'='completed','completed durable state');
 PERFORM pg_temp.require((SELECT count(*)=4 FROM macsad.execution_artifact WHERE execution_id=e),'full output closure linked');
 PERFORM pg_temp.require((SELECT claim_outcome='unknown' FROM macsad.execution WHERE id=e),'no SQL proof upgrade');
 PERFORM pg_temp.require(result=macsad.lean_advance(worker,w,e,3,'complete-control','complete',1,60,'{"receipt":"opaque-policy-result"}',out_ids,d),'terminal completion replay');
 PERFORM pg_temp.reject(format('SELECT macsad.lean_advance(%L,%L,%L,4,%L,%L,1,60,%L,%L::uuid[],%L::bytea)',
 worker,w,e,'terminal-rewrite','complete','{}',out_ids,d),'40001','terminal rewrite refused');
END $completion$;

-- New attempt uses the same legitimate still-accepted assignment; never reset
-- the terminal execution or transfer its immutable lease owner.
INSERT INTO lean_control_state
SELECT macsad.lean_submit('11100000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
 '91940000-0000-4000-8000-000000000001',1,'expiry-submit','91200000-0000-4000-8000-000000000001','t',
 '11000000-0000-4000-8000-000000000004',macsad.lean_digest('{}'),'{}',macsad.lean_digest('{}'));
SELECT macsad.lean_advance('91100000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
 (result->>'execution_id')::uuid,0,'expiry-claim','claim',0,60,'{}','{}',macsad.lean_digest('{}')) FROM lean_control_state WHERE result->>'state'='pending';
SET LOCAL ROLE macsad_owner;
-- Deterministic tiny expiry fixture: legal leased state, no sleeps, no disabled
-- triggers. The production API never accepts a caller-supplied clock.
UPDATE macsad.execution SET lease_expires_at=clock_timestamp()-interval '1 second',version=version+1
WHERE id=(SELECT (result->>'execution_id')::uuid FROM lean_control_state WHERE result->>'state'='pending');
SET LOCAL ROLE macsad_app;
DO $expiry$
DECLARE e uuid:=(SELECT (result->>'execution_id')::uuid FROM lean_control_state WHERE result->>'state'='pending');
 w uuid:='10000000-0000-4000-8000-000000000001'; d bytea:=macsad.lean_digest('{}'); result jsonb;
BEGIN
 PERFORM pg_temp.reject(format('SELECT macsad.lean_advance(%L,%L,%L,2,%L,%L,1,60,%L,%L,%L::bytea)',
 '91100000-0000-4000-8000-000000000001',w,e,'late-heartbeat','heartbeat','{}','{}',d),'40001','expiry cannot be revived');
 PERFORM pg_temp.reject(format('SELECT macsad.lean_advance(%L,%L,%L,2,%L,%L,1,60,%L,%L::uuid[],%L::bytea)',
 '91100000-0000-4000-8000-000000000001',w,e,'late-completion','complete','{}',
 '{91200000-0000-4000-8000-000000000002,91200000-0000-4000-8000-000000000003,91200000-0000-4000-8000-000000000004}',d),
 '40001','stale completion rejected before artifacts');
 result:=macsad.lean_advance('91100000-0000-4000-8000-000000000002',w,e,2,'expire-control','expire',1,60,'{}','{}',d);
 PERFORM pg_temp.require(result->>'state'='expired','expiry terminal');
 PERFORM pg_temp.reject(format('SELECT macsad.lean_advance(%L,%L,%L,3,%L,%L,1,60,%L,%L,%L::bytea)',
 '91100000-0000-4000-8000-000000000001',w,e,'late-start','start','{}','{}',d),'40001','stale worker cannot start');
 PERFORM pg_temp.require((SELECT count(*)=1 FROM macsad.execution_artifact WHERE execution_id=e),'expiry publishes no outputs');
END $expiry$;
-- Reconstruct committed event hashes from stored facts in another timezone.
-- Existing v1 fixture hashes use a separate fixture convention and are excluded.
SET LOCAL timezone='Pacific/Honolulu';
SELECT pg_temp.require(NOT EXISTS (
 SELECT 1 FROM macsad.domain_event e JOIN macsad.command_receipt r ON r.id=e.command_receipt_id
 WHERE e.payload_schema_id='macsad.lean-command-event' AND (
  e.payload_digest<>macsad.lean_digest(e.payload_body) OR
  e.event_hash<>macsad.lean_digest(jsonb_build_object('schema','macsad.lean-event-hash/1','id',e.id,
   'workspace',e.workspace_id,'sequence',e.workspace_sequence_no,'previous',encode(e.previous_event_hash,'hex'),
   'execution',e.aggregate_id,'aggregate_version',e.aggregate_version,'receipt',r.id,'actor',e.actor_id,
   'correlation',e.correlation_id,'occurred_at',to_char(e.occurred_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'payload',e.payload_body)))
),'event hash reconstructs independently of session timezone');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
