-- Additive test-only fixture factory. Execute on the observer session after the
-- unchanged v1 fixture and existing 0002_lean_concurrency_setup.sql. All rows
-- here are NEW; no original fixture or accepted-assignment bypass is used.
CREATE FUNCTION pg_temp.lean_time_fixture(p_label text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE w uuid:='10000000-0000-4000-8000-000000000001';
 actor_id uuid:=gen_random_uuid(); identity_id uuid:=gen_random_uuid(); grant_id uuid:=gen_random_uuid();
 worker_id uuid:=gen_random_uuid(); worker_identity uuid:=gen_random_uuid(); worker_grant uuid:=gen_random_uuid();
 problem_id uuid:=gen_random_uuid(); case_id uuid:=gen_random_uuid(); new_task uuid:=gen_random_uuid();
 membership_id uuid:=gen_random_uuid(); assignment_id uuid:=gen_random_uuid();
BEGIN
 INSERT INTO macsad.actor(id,kind,display_name) VALUES(actor_id,'human','Expiry submitter '||p_label),
   (worker_id,'service','Expiry worker '||p_label);
 INSERT INTO macsad.actor_identity(id,actor_id,issuer,subject,audience)
 VALUES(identity_id,actor_id,'test://lean-time',identity_id::text,'test-only'),
   (worker_identity,worker_id,'test://lean-time',worker_identity::text,'test-only');
 INSERT INTO macsad.capability_grant(id,workspace_id,actor_id,capability_code,granted_by_actor_id,reason)
 VALUES(grant_id,w,actor_id,'lean.submit','11000000-0000-4000-8000-000000000001','NEW expiry control'),
   (worker_grant,w,worker_id,'lean.worker','11000000-0000-4000-8000-000000000001','NEW expiry control');
 INSERT INTO macsad.problem_revision(id,workspace_id,research_kind,title,original_question,definitions,assumptions,
   domain_bounds,success_criteria,refutation_criteria,inconclusive_criteria,kind_schema_id,kind_schema_version,
   kind_body,content_digest,created_by_actor_id)
 SELECT problem_id,workspace_id,research_kind,'Expiry control '||p_label,original_question,definitions,assumptions,
   domain_bounds,success_criteria,refutation_criteria,inconclusive_criteria,kind_schema_id,kind_schema_version,
   kind_body,macsad.lean_digest(jsonb_build_object('test',p_label)),actor_id
 FROM macsad.problem_revision WHERE id='91700000-0000-4000-8000-000000000001';
 INSERT INTO macsad.research_case(id,workspace_id,workspace_snapshot_id,policy_revision_id,problem_revision_id,
   process_key,tool_closure_digest)
 SELECT case_id,workspace_id,workspace_snapshot_id,policy_revision_id,problem_id,process_key,tool_closure_digest
 FROM macsad.research_case WHERE id='91800000-0000-4000-8000-000000000001';
 INSERT INTO macsad.task(id,workspace_id,research_case_id,policy_revision_id,problem_revision_id,process_key,node_key,
   sequence_no,board_phase,required_profile_key,required_profile_digest,input_closure_digest)
 SELECT new_task,workspace_id,case_id,policy_revision_id,problem_id,process_key,node_key,
   1,board_phase,required_profile_key,required_profile_digest,input_closure_digest
 FROM macsad.task WHERE id='91900000-0000-4000-8000-000000000001';
 INSERT INTO macsad.membership(id,workspace_id,actor_id,policy_revision_id,profile_key,profile_digest)
 SELECT membership_id,m.workspace_id,m.actor_id,m.policy_revision_id,m.profile_key,m.profile_digest
 FROM macsad.membership m JOIN macsad.task_assignment a ON a.offered_membership_id=m.id
 WHERE a.id='91940000-0000-4000-8000-000000000001';
 INSERT INTO macsad.task_assignment(id,workspace_id,task_id,offered_actor_id,offered_membership_id,offered_by_actor_id,
   policy_revision_id,profile_key,profile_digest,package_digest,reason)
 SELECT assignment_id,workspace_id,new_task,offered_actor_id,membership_id,actor_id,
   policy_revision_id,profile_key,profile_digest,macsad.lean_digest(jsonb_build_object('offer',p_label)),'NEW expiry control offer'
 FROM macsad.task_assignment WHERE id='91940000-0000-4000-8000-000000000001';
 UPDATE macsad.task_assignment SET state='accepted',accepted_at=clock_timestamp(),version=1 WHERE id=assignment_id;
 UPDATE macsad.task SET state='ready',version=1 WHERE id=new_task;
 RETURN jsonb_build_object('identity',identity_id,'grant',grant_id,'worker',worker_id,'worker_identity',worker_identity,
   'worker_grant',worker_grant,'assignment',assignment_id,'membership',membership_id,'task',new_task);
END $$;
