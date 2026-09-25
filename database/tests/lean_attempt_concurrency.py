"""Real PG16 connection controls; invoked only by lean_attempt_pg16.py.

No server/role provisioning. Every mutation is confined to the harness-owned DB.
"""
import json
import os
import queue
import subprocess
import threading
import time
import uuid

PSQL = ['psql', '--no-psqlrc', '--quiet', '--tuples-only', '--no-align',
        '--set=ON_ERROR_STOP=1', '--set=VERBOSITY=verbose']
WORKSPACE = '10000000-0000-4000-8000-000000000001'
DIRECTOR = '11100000-0000-4000-8000-000000000001'
WORKER = '91100000-0000-4000-8000-000000000001'
ASSIGNMENT = '91940000-0000-4000-8000-000000000001'
SOURCE = '91200000-0000-4000-8000-000000000001'
DIGEST = "macsad.lean_digest('{}')"


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def submit(key, identity=DIRECTOR):
    return ('SELECT macsad.lean_submit(' + ','.join([
        literal(identity), literal(WORKSPACE), literal(ASSIGNMENT), '1',
        literal(key), literal(SOURCE), "'t'", "'11000000-0000-4000-8000-000000000004'",
        DIGEST, "'{}'", DIGEST]) + ')')


def advance(execution, version, key, action, fence):
    uuid.UUID(execution)
    return ('SELECT macsad.lean_advance(' + ','.join([
        literal(WORKER), literal(WORKSPACE), literal(execution), str(version),
        literal(key), literal(action), str(fence), '60', "'{}'", "'{}'", DIGEST]) + ')')


class Session:
    def __init__(self, env, label):
        self.lines = queue.Queue()
        self.label = label
        self.process = subprocess.Popen(PSQL, env=env, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        def read():
            for line in self.process.stdout:
                self.lines.put(line.rstrip('\n'))
            self.lines.put(None)
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()
        self.pid = int(self.query('SELECT pg_backend_pid()')[0])

    def send(self, sql):
        marker = 'end_' + uuid.uuid4().hex
        self.process.stdin.write(sql + ';\nSELECT ' + literal(marker) + ';\n')
        self.process.stdin.flush()
        return marker

    def receive(self, marker, timeout=10):
        deadline = time.monotonic() + timeout
        result = []
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(self.label + ': response timeout')
            line = self.lines.get(timeout=remaining)
            if line is None:
                raise AssertionError(self.label + ': psql ended: ' + '\n'.join(result))
            if line == marker:
                return result
            if line:
                result.append(line)

    def query(self, sql):
        return self.receive(self.send(sql))

    def refusal(self, marker, sqlstate, text):
        try:
            self.receive(marker)
        except AssertionError as error:
            message = str(error)
            if 'ERROR:  ' + sqlstate + ':' not in message or text not in message:
                raise
            if self.process.wait(timeout=5) != 3:
                raise AssertionError('expected psql ON_ERROR_STOP exit 3')
            return
        raise AssertionError(self.label + ': expected refusal but accepted')

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.write('ROLLBACK;\n\\q\n')
                self.process.stdin.flush()
                self.process.wait(timeout=5)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.process.kill()
                self.process.wait(timeout=5)
        self.process.stdin.close()
        self.reader.join(timeout=5)
        self.process.stdout.close()


def wait_until(observer, sql, label):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if observer.query(sql) == ['t']:
            return
        time.sleep(0.025)
    raise AssertionError(label + ': condition not observed')


def app_sql(sql):
    return 'BEGIN; SET LOCAL ROLE macsad_app; ' + sql


def run(env):
    if not env.get('PGDATABASE', '').startswith('macsad_lean_upgrade_'):
        raise AssertionError('concurrency controls require the harness-owned upgrade database')
    sessions = []
    def connection(label):
        s = Session(env, label)
        sessions.append(s)
        return s
    observer = connection('observer')
    try:
        for same_key in (False, True):
            suffix = 'same' if same_key else 'different'
            submitted = observer.query(app_sql(submit('concurrent-' + suffix)) + '; COMMIT')
            execution = json.loads(submitted[0])['execution_id']
            a = connection('winner-' + suffix)
            b = connection('contender-' + suffix)
            key = 'claim-' + suffix
            # Winner has changed the row but has not committed. Its response is
            # deliberately discarded by the caller in the same-key case.
            a.query(app_sql(advance(execution, 0, key, 'claim', 0)))
            pending = b.send(app_sql(advance(execution, 0, key if same_key else key + '-other', 'claim', 0)))
            wait_until(observer, f'SELECT {a.pid}=ANY(pg_blocking_pids({b.pid}))', 'claim contention')
            if same_key:
                # Send COMMIT without reading its response. An independent
                # connection proves durability before retry receives its answer.
                lost_marker = a.send('COMMIT')
                wait_until(observer, "SELECT state='leased' FROM macsad.execution WHERE id=" + literal(execution), 'lost response commit')
                replay = b.receive(pending)
                b.query('COMMIT')
                stored = observer.query("SELECT result_body FROM macsad.command_receipt WHERE workspace_id=" + literal(WORKSPACE)
                    + ' AND idempotency_key=' + literal(key))
                if json.loads(replay[0]) != json.loads(stored[0]):
                    raise AssertionError('same-key concurrent retry did not return stored receipt')
                # Do not receive lost_marker: simulate the submitting caller
                # losing that transport response, not merely an ordinary retry.
                a.close()
            else:
                a.query('COMMIT')
                b.refusal(pending, '40001', 'lean.stale_attempt')
            facts = observer.query("SELECT json_build_array(e.version,(SELECT count(*) FROM macsad.domain_event d WHERE d.aggregate_id=e.id),"
                "(SELECT count(*) FROM macsad.command_receipt r WHERE r.result_body->>'execution_id'=e.id::text),"
                "(SELECT state FROM macsad.outbox_message o WHERE o.topic='macsad.lean.execute' AND o.message_key=e.id::text)) "
                'FROM macsad.execution e WHERE e.id=' + literal(execution))
            if json.loads(facts[0]) != [1, 2, 2, 'delivered']:
                raise AssertionError('concurrent claim duplicated or partially committed facts: ' + facts[0])
            observer.query(app_sql(advance(execution, 1, 'start-' + suffix, 'start', 1)) + '; COMMIT')
            observer.query(app_sql(advance(execution, 2, 'fail-' + suffix, 'fail', 1)) + '; COMMIT')
            a.close()
            b.close()

        # End a credential lifetime after the caller captured its admission
        # clock but while it waits on this exact row. No sleep/race assumption.
        short_identity = '91100000-0000-4000-8000-000000000003'
        observer.query("BEGIN; SET LOCAL ROLE macsad_owner; INSERT INTO macsad.actor_identity(id,actor_id,issuer,subject,audience) VALUES("
            + literal(short_identity) + ",'11000000-0000-4000-8000-000000000001','test://lean','short-director','macsad-admin'); COMMIT")
        holder = connection('identity-lock-holder')
        caller = connection('identity-expiring-caller')
        holder.query('BEGIN; SELECT id FROM macsad.actor_identity WHERE id=' + literal(short_identity) + ' FOR UPDATE')
        pending = caller.send(app_sql(submit('expired-during-lock', short_identity)))
        wait_until(observer, f'SELECT {holder.pid}=ANY(pg_blocking_pids({caller.pid}))', 'identity lock contention')
        holder.query('UPDATE macsad.actor_identity SET valid_until=clock_timestamp(),version=version+1 WHERE id=' + literal(short_identity))
        holder.query('COMMIT')
        caller.refusal(pending, '42501', 'lean.authority_expired')
        if observer.query("SELECT count(*) FROM macsad.command_receipt WHERE idempotency_key='expired-during-lock'") != ['0']:
            raise AssertionError('expired identity created a receipt')
        return {'distinct_key_claim_race': 'passed', 'same_key_claim_lost_response': 'passed',
                'identity_expiry_during_observed_lock': 'passed'}
    finally:
        for session in sessions:
            session.close()
