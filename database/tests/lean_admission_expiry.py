"""Additive PG16 lock/expiry controls. No services or original fixture edits.

Imported only by the fresh-database cohort. Synchronization uses observed PG
blocking PIDs and database-clock predicates, never a blind sleep for expiry.
"""
import json
from pathlib import Path
import uuid

from lean_attempt_concurrency import Session, WORKSPACE, SOURCE, DIGEST, literal, app_sql, wait_until


def submit(fixture, key):
    return 'SELECT macsad.lean_submit(' + ','.join([
        literal(fixture['identity']), literal(WORKSPACE), literal(fixture['assignment']), '1',
        literal(key), literal(SOURCE), "'t'", literal(fixture['worker']), DIGEST, "'{}'", DIGEST]) + ')'


def advance(fixture, execution, version, key, action, outputs=(), seconds=60):
    return 'SELECT macsad.lean_advance(' + ','.join([
        literal(fixture['worker_identity']), literal(WORKSPACE), literal(execution), str(version),
        literal(key), literal(action), '0' if action == 'claim' else '1', str(seconds), "'{}'",
        literal('{' + ','.join(outputs) + '}') + '::uuid[]', DIGEST]) + ')'


def run(env):
    if not env.get('PGDATABASE', '').startswith('macsad_lean_upgrade_'):
        raise AssertionError('expiry controls require the harness-owned upgrade database')
    sessions = []
    results = {}

    def connection(label):
        s = Session(env, label)
        sessions.append(s)
        s.query("SET statement_timeout='15s'; SET lock_timeout='12s'")
        return s

    observer = connection('expiry-observer')
    observer.query('SET ROLE macsad_owner')

    def fresh(label):
        return json.loads(observer.query('SELECT pg_temp.lean_time_fixture(' + literal(label) + ')')[0])

    def durable_facts(execution=None):
        target = "'null'::jsonb" if execution is None else (
            '(SELECT to_jsonb(e) FROM macsad.execution e WHERE id=' + literal(execution) + ')')
        outbox = "'null'::jsonb" if execution is None else (
            "(SELECT COALESCE(jsonb_agg(to_jsonb(o) ORDER BY o.id),'[]'::jsonb) "
            + 'FROM macsad.outbox_message o WHERE o.workspace_id=' + literal(WORKSPACE)
            + ' AND o.message_key=' + literal(execution) + ')')
        sql = "SELECT jsonb_build_array(" + ','.join([
            '(SELECT count(*) FROM macsad.' + table + ')'
            for table in ['execution', 'command_receipt', 'domain_event', 'outbox_message', 'execution_artifact']
        ]) + ',to_jsonb(s),' + target + ',' + outbox + ') FROM macsad.audit_stream s WHERE workspace_id=' + literal(WORKSPACE)
        return json.loads(observer.query(sql)[0])

    def arm(table, key, field):
        return observer.query('UPDATE macsad.' + table + ' SET ' + field
            + "=clock_timestamp()+interval '4 seconds',version=version+1 WHERE id="
            + literal(key) + ' RETURNING ' + field)[0]

    def blocked_then_expired(holder, caller, marker, deadline, progressed_relations=()):
        wait_until(observer, f'SELECT {holder.pid}=ANY(pg_blocking_pids({caller.pid}))', 'observed expiry lock')
        for relation in progressed_relations:
            # SELECT execution FOR UPDATE holds RowShareLock, not this mode.
            # RowExclusiveLock proves the caller reached its guarded mutation
            # before waiting on the holder's sole audit-stream row lock.
            sql = (f'SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid={caller.pid} '
                + 'AND relation=' + literal('macsad.' + relation)
                + "::regclass AND mode='RowExclusiveLock' AND granted)")
            if observer.query(sql) != ['t']:
                raise AssertionError('caller did not reach guarded mutation on ' + relation)
        if observer.query('SELECT clock_timestamp()<' + literal(deadline) + '::timestamptz') != ['t']:
            raise AssertionError('fixture reached its deadline before observed lock; no race evidence')
        wait_until(observer, 'SELECT clock_timestamp()>=' + literal(deadline) + '::timestamptz', 'database deadline passed')
        holder.query('COMMIT')
        return marker

    try:
        observer.query((Path(__file__).with_name('lean_admission_expiry_setup.sql')).read_text())
        # Every limited fact is new. Task/worker blockers do not alter its row;
        # this specifically exercises passive expiry after an earlier check.
        for kind, table, field, error in [
            ('assignment', 'task_assignment', 'expires_at', ('55000', 'lean.assignment_not_accepted')),
            ('membership', 'membership', 'valid_until', ('42501', 'lean.performer_inactive')),
            ('identity', 'actor_identity', 'valid_until', ('42501', 'lean.identity_denied')),
            ('grant', 'capability_grant', 'valid_until', ('42501', 'lean.capability_denied')),
        ]:
            f = fresh('submit-' + kind)
            holder, caller = connection(kind + '-holder'), connection(kind + '-caller')
            target_table, target_id = ('actor', f['worker']) if kind == 'membership' else ('task', f['task'])
            holder.query('BEGIN; SELECT id FROM macsad.' + target_table + ' WHERE id=' + literal(target_id) + ' FOR UPDATE')
            deadline = arm(table, f[kind], field)
            before = durable_facts()
            key = 'expiry-submit-' + kind
            marker = caller.send(app_sql(submit(f, key)))
            blocked_then_expired(holder, caller, marker, deadline)
            caller.refusal(marker, *error)
            if durable_facts() != before:
                raise AssertionError(kind + ': expired submit persisted execution/receipt/event/outbox/link/audit changes')
            if observer.query('SELECT count(*) FROM macsad.command_receipt WHERE idempotency_key=' + literal(key)) != ['0']:
                raise AssertionError(kind + ': expired submit left a receipt')
            holder.close(); caller.close()
            results['submit_' + kind + '_expiry_after_observed_lock'] = 'passed'

        for kind in ['identity', 'grant']:
            f = fresh('advance-' + kind)
            e = json.loads(observer.query(app_sql(submit(f, 'advance-setup-' + kind)) + '; COMMIT')[0])['execution_id']
            observer.query(app_sql(advance(f, e, 0, 'advance-claim-' + kind, 'claim')) + '; COMMIT')
            holder, caller = connection('advance-' + kind + '-holder'), connection('advance-' + kind + '-caller')
            holder.query('BEGIN; SELECT id FROM macsad.execution WHERE id=' + literal(e) + ' FOR UPDATE')
            table = 'actor_identity' if kind == 'identity' else 'capability_grant'
            deadline = arm(table, f['worker_' + kind], 'valid_until')
            before = durable_facts(e)
            marker = caller.send(app_sql(advance(f, e, 1, 'advance-expired-' + kind, 'start')))
            blocked_then_expired(holder, caller, marker, deadline)
            caller.refusal(marker, '42501', 'lean.identity_denied' if kind == 'identity' else 'lean.capability_denied')
            if durable_facts(e) != before:
                raise AssertionError(kind + ': expired advance changed version, lease or durable facts')
            holder.close(); caller.close()
            results['advance_' + kind + '_expiry_after_execution_lock'] = 'passed'

        # Claim creates a lease before the audit trigger wait. Its uncommitted
        # deadline is invisible here, so a database-clock observation AFTER the
        # proven mutation plus the same two-second duration is an upper bound.
        f = fresh('late-claim')
        e = json.loads(observer.query(app_sql(submit(f, 'late-claim-submit')) + '; COMMIT')[0])['execution_id']
        holder, caller = connection('claim-audit-holder'), connection('claim-caller')
        holder.query('BEGIN; SELECT workspace_id FROM macsad.audit_stream WHERE workspace_id=' + literal(WORKSPACE) + ' FOR UPDATE')
        before = durable_facts(e)
        marker = caller.send(app_sql(advance(f, e, 0, 'late-refused-claim', 'claim', seconds=2)))
        wait_until(observer, f'SELECT {holder.pid}=ANY(pg_blocking_pids({caller.pid}))', 'observed claim audit lock')
        deadline = observer.query("SELECT clock_timestamp()+interval '2 seconds'")[0]
        blocked_then_expired(holder, caller, marker, deadline, ('execution', 'outbox_message'))
        caller.refusal(marker, '40001', 'lean.stale_lease')
        if durable_facts(e) != before:
            raise AssertionError('claim: expired provisional lease changed pending execution/outbox/receipt/audit facts')
        holder.close(); caller.close()
        results['claim_new_lease_expiry_during_audit_wait'] = 'passed'

        for action in ['heartbeat', 'complete']:
            f = fresh('late-' + action)
            e = json.loads(observer.query(app_sql(submit(f, 'late-submit-' + action)) + '; COMMIT')[0])['execution_id']
            observer.query(app_sql(advance(f, e, 0, 'late-claim-' + action, 'claim')) + '; COMMIT')
            observer.query(app_sql(advance(f, e, 1, 'late-start-' + action, 'start')) + '; COMMIT')
            outputs = []
            if action == 'complete':
                for kind in ['logos_source', 'logos_certificate', 'logos_package']:
                    artifact = str(uuid.uuid4()); outputs.append(artifact)
                    text = kind + artifact
                    observer.query("INSERT INTO macsad.blob(digest,byte_length,media_type,storage_provider,storage_locator,storage_class,stored_at,verified_at) VALUES("
                        + 'sha256(convert_to(' + literal(text) + ",'UTF8')),octet_length(" + literal(text)
                        + "),'application/octet-stream','test'," + literal(artifact) + ",'private',clock_timestamp(),clock_timestamp()); "
                        + 'INSERT INTO macsad.artifact(id,workspace_id,blob_digest,artifact_kind,classification,secret_scan_result,producing_actor_id,producing_execution_id) VALUES('
                        + ','.join([literal(artifact), literal(WORKSPACE), 'sha256(convert_to(' + literal(text) + ",'UTF8'))", literal(kind), "'private'", "'passed'", literal(f['worker']), literal(e)]) + ')')
            holder, caller = connection(action + '-audit-holder'), connection(action + '-caller')
            # The unchanged audit trigger takes this lock after the command's
            # old lease check, mutation, and (complete) all three output links.
            holder.query('BEGIN; SELECT workspace_id FROM macsad.audit_stream WHERE workspace_id=' + literal(WORKSPACE) + ' FOR UPDATE')
            deadline = arm('execution', e, 'lease_expires_at')
            before = durable_facts(e)
            marker = caller.send(app_sql(advance(f, e, 3, 'late-refused-' + action, action, outputs)))
            progressed = ('execution', 'execution_artifact') if action == 'complete' else ('execution',)
            blocked_then_expired(holder, caller, marker, deadline, progressed)
            caller.refusal(marker, '40001', 'lean.stale_lease')
            if durable_facts(e) != before:
                raise AssertionError(action + ': late audit wait persisted version/lease/outputs/event/receipt changes')
            holder.close(); caller.close()
            results[action + '_original_lease_expiry_during_audit_wait'] = 'passed'

        # Existing-result replay ignores changed assignment/task admission but
        # still requires current authority. It must not republish any facts.
        f = fresh('receipt-replay')
        request = submit(f, 'expiry-replay')
        original = json.loads(observer.query(app_sql(request) + '; COMMIT')[0])
        observer.query('UPDATE macsad.task_assignment SET expires_at=clock_timestamp(),version=version+1 WHERE id=' + literal(f['assignment']))
        before = durable_facts(original['execution_id'])
        replay = json.loads(observer.query(app_sql(request) + '; COMMIT')[0])
        if replay != original or durable_facts(original['execution_id']) != before:
            raise AssertionError('authorized historical receipt replay changed result or durable facts')
        observer.query('UPDATE macsad.actor_identity SET valid_until=clock_timestamp(),version=version+1 WHERE id=' + literal(f['identity']))
        caller = connection('replay-expired-authority')
        marker = caller.send(app_sql(request))
        caller.refusal(marker, '42501', 'lean.identity_denied')
        if durable_facts(original['execution_id']) != before:
            raise AssertionError('denied receipt replay changed original durable facts')
        results['historical_receipt_replay_requires_current_authority'] = 'passed'

        caller = connection('artifact-quarantine-is-immutable')
        marker = caller.send("BEGIN; SET LOCAL ROLE macsad_owner; UPDATE macsad.artifact SET quarantined=true WHERE id=" + literal(SOURCE))
        caller.refusal(marker, '55000', 'append-only')
        results['artifact_quarantine_update_is_not_a_legal_race'] = 'passed'
        return results
    finally:
        for session in sessions:
            session.close()
