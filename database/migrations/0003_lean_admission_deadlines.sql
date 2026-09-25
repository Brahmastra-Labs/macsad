-- Forward-only deadline admission correction. Migration 0002 remains immutable.
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

CREATE OR REPLACE FUNCTION macsad.lean_begin_command(
 p_identity uuid, p_workspace uuid, p_capability text, p_kind text,
 p_key text, p_request jsonb
) RETURNS macsad.command_receipt
LANGUAGE plpgsql SET search_path = pg_catalog, macsad AS $$
DECLARE a uuid; r macsad.command_receipt; now_at timestamptz;
 identity_row macsad.actor_identity; grant_row macsad.capability_grant;
BEGIN
 IF p_identity IS NULL OR p_workspace IS NULL OR p_key IS NULL
    OR length(p_key) NOT BETWEEN 1 AND 200 OR p_request IS NULL
    OR jsonb_typeof(p_request) <> 'object' OR octet_length(p_request::text) > 65536 THEN
   RAISE EXCEPTION 'lean.invalid_command' USING ERRCODE = '22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('macsad:lean:'||p_workspace::text,0));
 PERFORM 1 FROM macsad.audit_stream WHERE workspace_id = p_workspace;
 IF NOT FOUND THEN RAISE EXCEPTION 'lean.workspace_absent' USING ERRCODE = '42501'; END IF;
 now_at := clock_timestamp();
 SELECT i.* INTO identity_row FROM macsad.actor_identity i JOIN macsad.actor actor ON actor.id=i.actor_id
 WHERE i.id=p_identity AND i.revoked_at IS NULL AND i.valid_from<=now_at
   AND (i.valid_until IS NULL OR i.valid_until>now_at) AND actor.state='active'
 FOR SHARE OF i, actor;
 IF NOT FOUND THEN RAISE EXCEPTION 'lean.identity_denied' USING ERRCODE = '42501'; END IF;
 a:=identity_row.actor_id;
 -- Only unconstrained narrow grants are supported here. LOGOS must evaluate
 -- any future constrained-grant form rather than SQL ignoring its predicates.
 SELECT g.* INTO grant_row FROM macsad.capability_grant g
 WHERE g.workspace_id=p_workspace AND g.actor_id=a AND g.capability_code=p_capability
   AND g.revoked_at IS NULL AND g.valid_from<=now_at
   AND (g.valid_until IS NULL OR g.valid_until>now_at) AND g.constraint_body IS NULL
 ORDER BY g.id LIMIT 1 FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'lean.capability_denied' USING ERRCODE = '42501'; END IF;
 SELECT * INTO r FROM macsad.command_receipt WHERE workspace_id=p_workspace AND idempotency_key=p_key FOR UPDATE;
 -- Identity, grant and receipt row waits can outlive authority. Check the exact
 -- locked facts again at admission, rather than trusting the pre-wait clock.
 now_at:=clock_timestamp();
 IF (identity_row.valid_until IS NOT NULL AND identity_row.valid_until<=now_at)
    OR (grant_row.valid_until IS NOT NULL AND grant_row.valid_until<=now_at) THEN
   RAISE EXCEPTION 'lean.authority_expired' USING ERRCODE='42501';
 END IF;
 IF FOUND THEN
   IF r.actor_id<>a OR r.actor_identity_id IS DISTINCT FROM p_identity
      OR r.command_kind<>p_kind OR r.request_digest<>macsad.lean_digest(p_request) THEN
     RAISE EXCEPTION 'lean.idempotency_conflict' USING ERRCODE = '40001';
   END IF;
   IF r.state<>'completed' THEN RAISE EXCEPTION 'lean.command_in_progress' USING ERRCODE = '40001'; END IF;
   RETURN r;
 END IF;
 INSERT INTO macsad.command_receipt(workspace_id,actor_id,actor_identity_id,command_kind,idempotency_key,request_digest,correlation_id)
 VALUES(p_workspace,a,p_identity,p_kind,p_key,macsad.lean_digest(p_request),gen_random_uuid()) RETURNING * INTO r;
 RETURN r;
END $$;

CREATE OR REPLACE FUNCTION macsad.lean_submit(
 p_identity uuid, p_workspace uuid, p_assignment uuid, p_expected_task_version bigint,
 p_key text, p_source_artifact uuid, p_target text, p_worker uuid,
 p_environment macsad.sha256_digest, p_limits jsonb, p_policy_decision macsad.sha256_digest
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, macsad AS $$
DECLARE request jsonb; r macsad.command_receipt; a macsad.task_assignment; t macsad.task;
 c macsad.research_case; source macsad.artifact; e uuid:=gen_random_uuid(); result jsonb;
 member_row macsad.membership; admitted_at timestamptz;
BEGIN
 IF p_target IS NULL OR length(p_target) NOT BETWEEN 1 AND 4096 OR p_environment IS NULL
    OR p_policy_decision IS NULL OR p_limits IS NULL OR jsonb_typeof(p_limits)<>'object'
    OR p_expected_task_version IS NULL OR p_assignment IS NULL OR p_worker IS NULL THEN
   RAISE EXCEPTION 'lean.invalid_submit' USING ERRCODE='22023'; END IF;
 request:=jsonb_build_object('schema','macsad.lean-submit/1','assignment',p_assignment,'task_version',p_expected_task_version,
   'source',p_source_artifact,'target',p_target,'worker',p_worker,'environment',encode(p_environment,'hex'),
   'limits',p_limits,'policy_decision',encode(p_policy_decision,'hex'));
 r:=macsad.lean_begin_command(p_identity,p_workspace,'lean.submit','lean.submitted',p_key,request);
 IF r.state='completed' THEN RETURN r.result_body; END IF;
 SELECT * INTO a FROM macsad.task_assignment WHERE workspace_id=p_workspace AND id=p_assignment FOR SHARE;
 IF NOT FOUND OR a.state<>'accepted' OR (a.expires_at IS NOT NULL AND a.expires_at<=clock_timestamp()) THEN
   RAISE EXCEPTION 'lean.assignment_not_accepted' USING ERRCODE='55000'; END IF;
 SELECT * INTO STRICT t FROM macsad.task WHERE workspace_id=p_workspace AND id=a.task_id FOR UPDATE;
 IF t.version<>p_expected_task_version OR t.state NOT IN ('ready','running') THEN
   RAISE EXCEPTION 'lean.task_version_or_state' USING ERRCODE='40001'; END IF;
 SELECT * INTO STRICT c FROM macsad.research_case WHERE workspace_id=p_workspace AND id=t.research_case_id FOR SHARE;
 IF c.state<>'open' OR c.control_state<>'normal' THEN RAISE EXCEPTION 'lean.case_not_runnable' USING ERRCODE='55000'; END IF;
 SELECT m.* INTO member_row FROM macsad.membership m JOIN macsad.actor actor ON actor.id=m.actor_id
 WHERE m.id=a.offered_membership_id AND m.state='active' AND actor.state='active'
   AND m.valid_from<=clock_timestamp() AND (m.valid_until IS NULL OR m.valid_until>clock_timestamp()) FOR SHARE OF m,actor;
 IF NOT FOUND THEN RAISE EXCEPTION 'lean.performer_inactive' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM macsad.actor WHERE id=p_worker AND kind='service' AND state='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'lean.worker_inactive' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM macsad.execution WHERE task_id=t.id AND state IN ('pending','leased','running','cancel_requested')) THEN
   RAISE EXCEPTION 'lean.task_attempt_live' USING ERRCODE='40001'; END IF;
 SELECT * INTO source FROM macsad.artifact WHERE id=p_source_artifact AND workspace_id=p_workspace;
 IF NOT FOUND OR source.artifact_kind<>'lean_source' OR source.quarantined OR source.secret_scan_result<>'passed'
    OR source.classification<>'private' THEN RAISE EXCEPTION 'lean.source_not_admitted' USING ERRCODE='22023'; END IF;
 INSERT INTO macsad.execution(id,workspace_id,research_case_id,task_id,task_assignment_id,performing_actor_id,worker_actor_id,
   workspace_snapshot_id,policy_revision_id,problem_revision_id,profile_key,profile_digest,
   request_schema_id,request_schema_version,request_body,request_digest,environment_digest,
   resource_limit_schema_id,resource_limit_schema_version,resource_limit_body,resource_limit_digest,idempotency_key)
 VALUES(e,p_workspace,c.id,t.id,a.id,a.offered_actor_id,p_worker,c.workspace_snapshot_id,c.policy_revision_id,c.problem_revision_id,
   a.profile_key,a.profile_digest,'macsad.lean-submit',1,request,macsad.lean_digest(request),p_environment,
   'macsad.lean-resource-limits',1,p_limits,macsad.lean_digest(p_limits),p_key);
 INSERT INTO macsad.execution_artifact(workspace_id,execution_id,artifact_id,role,ordinal)
 VALUES(p_workspace,e,source.id,'input',0);
 result:=jsonb_build_object('schema','macsad.lean-command-result/1','execution_id',e,'state','pending','version',0);
 result:=macsad.lean_finish_command(r.id,e,result,true);
 -- Final admission follows every potentially blocking effect, including the
 -- audit trigger. This exact receipt replay reuses current narrow authority.
 -- Raising here rolls back execution, event, outbox and receipt together.
 PERFORM macsad.lean_begin_command(p_identity,p_workspace,'lean.submit','lean.submitted',p_key,request);
 admitted_at:=clock_timestamp();
 IF a.expires_at IS NOT NULL AND a.expires_at<=admitted_at THEN
   RAISE EXCEPTION 'lean.assignment_not_accepted' USING ERRCODE='55000'; END IF;
 IF member_row.valid_until IS NOT NULL AND member_row.valid_until<=admitted_at THEN
   RAISE EXCEPTION 'lean.performer_inactive' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION macsad.lean_advance(
 p_identity uuid, p_workspace uuid, p_execution uuid, p_expected_version bigint,
 p_key text, p_action text, p_fence bigint, p_lease_seconds integer,
 p_result jsonb, p_outputs uuid[], p_policy_decision macsad.sha256_digest
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, macsad AS $$
DECLARE request jsonb; r macsad.command_receipt; e macsad.execution; now_at timestamptz;
 result jsonb; n integer; artifact macsad.artifact; expected_kind text; artifact_role macsad.execution_artifact_role; ordinal integer;
BEGIN
 IF p_action IS NULL OR p_action NOT IN ('claim','start','heartbeat','complete','fail','expire')
    OR p_execution IS NULL OR p_expected_version IS NULL OR p_policy_decision IS NULL
    OR p_outputs IS NULL OR cardinality(p_outputs)>3 OR p_result IS NULL OR jsonb_typeof(p_result)<>'object'
    OR p_lease_seconds IS NULL OR p_lease_seconds NOT BETWEEN 1 AND 600 THEN
   RAISE EXCEPTION 'lean.invalid_advance' USING ERRCODE='22023'; END IF;
 IF p_action='complete' AND (cardinality(p_outputs)<>3 OR array_ndims(p_outputs)<>1 OR array_lower(p_outputs,1)<>1)
    OR p_action<>'complete' AND cardinality(p_outputs)<>0 THEN
   RAISE EXCEPTION 'lean.invalid_outputs' USING ERRCODE='22023'; END IF;
 request:=jsonb_build_object('schema','macsad.lean-advance/1','execution',p_execution,'version',p_expected_version,
   'action',p_action,'fence',p_fence,'lease_seconds',p_lease_seconds,'result',p_result,'outputs',p_outputs,
   'policy_decision',encode(p_policy_decision,'hex'));
 r:=macsad.lean_begin_command(p_identity,p_workspace,CASE WHEN p_action='expire' THEN 'lean.expire' ELSE 'lean.worker' END,
   'lean.'||p_action,p_key,request);
 IF r.state='completed' THEN RETURN r.result_body; END IF;
 SELECT * INTO e FROM macsad.execution WHERE workspace_id=p_workspace AND id=p_execution FOR UPDATE;
 IF NOT FOUND OR e.request_schema_id<>'macsad.lean-submit' OR e.version<>p_expected_version
    OR e.state IN ('completed','failed','expired') THEN RAISE EXCEPTION 'lean.stale_attempt' USING ERRCODE='40001'; END IF;
 now_at:=clock_timestamp();
 IF p_action='claim' THEN
   IF e.state<>'pending' OR r.actor_id<>e.worker_actor_id OR p_fence IS DISTINCT FROM 0 THEN
     RAISE EXCEPTION 'lean.claim_denied' USING ERRCODE='40001'; END IF;
   UPDATE macsad.execution SET state='leased',lease_owner_actor_id=r.actor_id,fencing_token=1,claimed_at=now_at,
     heartbeat_at=now_at,lease_expires_at=now_at+make_interval(secs=>p_lease_seconds),version=version+1 WHERE id=e.id;
   -- Delivery means the trusted worker durably accepted this notification,
   -- not that its external computation completed. Lease expiry remains visible.
   UPDATE macsad.outbox_message SET state='publishing',attempt_count=attempt_count+1,
     lease_owner_actor_id=r.actor_id,lease_expires_at=now_at+make_interval(secs=>p_lease_seconds),version=version+1
   WHERE workspace_id=p_workspace AND topic='macsad.lean.execute' AND message_key=e.id::text AND state='pending';
   IF NOT FOUND THEN RAISE EXCEPTION 'lean.dispatch_not_pending' USING ERRCODE='40001'; END IF;
   UPDATE macsad.outbox_message SET state='delivered',delivered_at=clock_timestamp(),
     lease_owner_actor_id=NULL,lease_expires_at=NULL,version=version+1
   WHERE workspace_id=p_workspace AND topic='macsad.lean.execute' AND message_key=e.id::text
     AND state='publishing' AND lease_owner_actor_id=r.actor_id;
 ELSIF p_action='expire' THEN
   IF e.state NOT IN ('leased','running','cancel_requested') OR e.lease_expires_at>now_at
      OR p_fence IS DISTINCT FROM e.fencing_token THEN RAISE EXCEPTION 'lean.not_expired' USING ERRCODE='40001'; END IF;
   UPDATE macsad.execution SET state='expired',finished_at=now_at,transport_outcome='unavailable',
     termination_outcome='wall_timeout',claim_outcome='inconclusive',result_envelope_digest=macsad.lean_digest(p_result),
     version=version+1 WHERE id=e.id;
 ELSE
   IF e.state NOT IN ('leased','running') OR r.actor_id<>e.worker_actor_id OR r.actor_id<>e.lease_owner_actor_id
      OR p_fence IS DISTINCT FROM e.fencing_token OR e.lease_expires_at<=now_at THEN
     RAISE EXCEPTION 'lean.stale_lease' USING ERRCODE='40001'; END IF;
   IF p_action='start' THEN
     IF e.state<>'leased' THEN RAISE EXCEPTION 'lean.not_leased' USING ERRCODE='40001'; END IF;
     UPDATE macsad.execution SET state='running',started_at=now_at,version=version+1 WHERE id=e.id;
   ELSIF p_action='heartbeat' THEN
     UPDATE macsad.execution SET heartbeat_at=now_at,lease_expires_at=greatest(e.lease_expires_at,now_at+make_interval(secs=>p_lease_seconds)),
       version=version+1 WHERE id=e.id;
   ELSE
     IF e.state<>'running' THEN RAISE EXCEPTION 'lean.not_running' USING ERRCODE='40001'; END IF;
     IF p_action='complete' THEN
       FOR n IN 1..3 LOOP
         expected_kind:=CASE n WHEN 1 THEN 'logos_source' WHEN 2 THEN 'logos_certificate' ELSE 'logos_package' END;
         SELECT * INTO artifact FROM macsad.artifact WHERE id=p_outputs[n] AND workspace_id=p_workspace;
         IF NOT FOUND OR artifact.artifact_kind<>expected_kind OR artifact.producing_execution_id IS DISTINCT FROM e.id
            OR artifact.producing_actor_id IS DISTINCT FROM r.actor_id OR artifact.classification<>'private'
            OR artifact.secret_scan_result<>'passed' OR artifact.quarantined THEN
           RAISE EXCEPTION 'lean.output_not_admitted' USING ERRCODE='22023'; END IF;
         artifact_role:=CASE WHEN n=2 THEN 'certificate'::macsad.execution_artifact_role ELSE 'output'::macsad.execution_artifact_role END;
         ordinal:=CASE WHEN n=3 THEN 1 ELSE 0 END;
         INSERT INTO macsad.execution_artifact(workspace_id,execution_id,artifact_id,role,ordinal)
         VALUES(p_workspace,e.id,artifact.id,artifact_role,ordinal);
       END LOOP;
     END IF;
     -- A completed conversion is not a supported theorem/claim. LOGOS owns
     -- detailed result grading; this persistence boundary records unknown.
     UPDATE macsad.execution SET state=CASE p_action WHEN 'complete' THEN 'completed'::macsad.execution_state ELSE 'failed'::macsad.execution_state END,
       finished_at=now_at,transport_outcome='accepted',termination_outcome=CASE p_action WHEN 'complete' THEN 'clean_exit'::macsad.termination_outcome ELSE 'tool_error'::macsad.termination_outcome END,
       claim_outcome='unknown',result_envelope_digest=macsad.lean_digest(p_result),version=version+1 WHERE id=e.id;
   END IF;
 END IF;
 SELECT jsonb_build_object('schema','macsad.lean-command-result/1','execution_id',id,'state',state,'version',version,
   'fencing_token',fencing_token,'lease_expires_at',lease_expires_at,'result',p_result,'artifacts',p_outputs)
 INTO result FROM macsad.execution WHERE id=e.id;
 result:=macsad.lean_finish_command(r.id,e.id,result,false);
 PERFORM macsad.lean_begin_command(p_identity,p_workspace,
   CASE WHEN p_action='expire' THEN 'lean.expire' ELSE 'lean.worker' END,
   'lean.'||p_action,p_key,request);
 now_at:=clock_timestamp();
 -- The original lease must cover this command; a heartbeat cannot legitimize
 -- itself by comparing only its newly extended deadline after a late wait.
 IF p_action IN ('start','heartbeat','complete','fail') AND e.lease_expires_at<=now_at THEN
   RAISE EXCEPTION 'lean.stale_lease' USING ERRCODE='40001'; END IF;
 IF p_action='claim' AND (result->>'lease_expires_at')::timestamptz<=now_at THEN
   RAISE EXCEPTION 'lean.stale_lease' USING ERRCODE='40001'; END IF;
 RETURN result;
END $$;

INSERT INTO macsad_meta.schema_migration(version,name,script_sha256)
VALUES(3,'0003_lean_admission_deadlines',decode(:'migration_sha256','hex'));
COMMIT;
