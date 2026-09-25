#!/usr/bin/env python3
"""Additive PG16 cohort, using the existing migration/fixture mechanics.

Requires an already bootstrapped dedicated test cluster. Never starts a service,
creates a role, uses a source database, or changes the checkout. Evidence output
must be a new directory. This file is testing-only, not an application adapter.
"""
import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid

from lean_attempt_concurrency import run as concurrency_run
from lean_admission_expiry import run as admission_expiry_run
from lean_recovery_pg16 import recovery
from lean_recovery_v3_pg16 import recovery as recovery_v3

ROLE_PATHS = {
    'alejandro': 'pg_catalog', 'macsad_deployer': 'pg_catalog',
    'macsad_owner': 'macsad, macsad_meta, pg_catalog',
    'macsad_migrator': 'macsad, macsad_meta, pg_catalog',
    'macsad_app': 'macsad, pg_catalog', 'macsad_reader': 'macsad, pg_catalog',
    'macsad_runtime': 'macsad, pg_catalog', 'macsad_viewer': 'macsad, pg_catalog',
}
INPUTS = [
    'database/apply_migrations.sh', 'database/verify.sql',
    'database/migrations/0001_initial_schema.sql',
    'database/migrations/0002_lean_attempt_boundary.sql',
    'database/fixtures/representative_v1.sql',
    'database/fixtures/representative_v1_system_fields.tsv',
    'database/workers/common.sh', 'database/workers/seed_representative_v1.sh',
    'database/workers/export_workspace_views.sh',
    'database/workers/backup_database.sh', 'database/workers/restore_database.sh',
    'database/workers/sql/backup_boundary.sql',
    'database/workers/sql/backup_source_preflight.sql',
    'database/workers/sql/export_workspace_views.sql',
    'database/workers/sql/hold_backup_snapshot.sql',
    'database/workers/sql/referenced_blobs.sql',
    'database/workers/sql/restore_target_preflight.sql',
    'database/workers/sql/verify_restored_data.sql',
    'database/tests/data_workers_roundtrip.sh',
    'database/tests/lean_recovery_pg16.py',
    'database/tests/0001_invariants.sql',
    'database/tests/representative_v1_field_coverage.sh',
    'database/tests/representative_v1_field_coverage.sql',
    'database/tests/0002_lean_attempt_controls.sql',
    'database/tests/0002_lean_concurrency_setup.sql',
    'database/tests/lean_attempt_concurrency.py', 'database/tests/lean_attempt_pg16.py',
    'database/tests/lean_admission_expiry.py', 'database/tests/lean_admission_expiry_setup.sql',
    'database/migrations/0003_lean_admission_deadlines.sql',
    'database/tests/lean_recovery_v3_pg16.py',
]
PSQL = ['psql', '--no-psqlrc', '--quiet', '--tuples-only', '--no-align',
        '--set=ON_ERROR_STOP=1', '--set=VERBOSITY=verbose']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


MIGRATIONS = ('database/migrations/0001_initial_schema.sql',
              'database/migrations/0002_lean_attempt_boundary.sql')


FORWARD_MIGRATION = 'database/migrations/0003_lean_admission_deadlines.sql'
CURRENT_MIGRATIONS = MIGRATIONS + (FORWARD_MIGRATION,)


def source_manifest(root, expected_migrations=MIGRATIONS):
    migrations = sorted(str(path.relative_to(root)) for path in
                        (root / 'database/migrations').glob('*.sql'))
    if migrations != list(expected_migrations):
        raise ValueError('cohort requires exactly migrations ' + ', '.join(expected_migrations))
    sources = {}
    for relative in INPUTS:
        path = root / relative
        if not path.is_file() or path.is_symlink():
            raise ValueError('required regular source missing: ' + relative)
        sources[relative] = digest(path)
    return sources


def copy_pinned(root, staged, relative, sources):
    source = root / relative
    if source.is_symlink() or digest(source) != sources[relative]:
        raise ValueError('source changed before staging: ' + relative)
    target = staged / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)  # Workers are invoked directly by original drill.
    if digest(target) != sources[relative]:
        raise ValueError('source changed while staging: ' + relative)


def stage_v1(root, staged, sources):
    for relative in INPUTS:
        if not relative.startswith('database/migrations/') or relative == MIGRATIONS[0]:
            copy_pinned(root, staged, relative, sources)
    if sorted(p.name for p in (staged/'database/migrations').glob('*.sql')) != ['0001_initial_schema.sql']:
        raise ValueError('v1 fixture stage contains a later migration')


class Harness:
    def __init__(self, root, evidence):
        self.root, self.evidence = root, evidence
        self.env = os.environ.copy()
        self.env.pop('DATABASE_URL', None)
        self.env['PGUSER'] = self.env.get('MACSAD_TEST_ADMIN_USER', self.env.get('PGUSER', 'postgres'))
        self.env['PGDATABASE'] = 'postgres'
        self.env['PGAPPNAME'] = 'macsad-lean-pg16-controls'
        self.env['PGOPTIONS'] = '-c statement_timeout=30000 -c lock_timeout=10000 -c idle_in_transaction_session_timeout=30000'
        self.created = []
        self.number = 0
        self.results = {}

    def run(self, args, env=None, stdin=None, expected_error=None, cwd=None):
        self.number += 1
        result = subprocess.run(args, env=env or self.env, cwd=cwd or self.root,
            input=stdin, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        (self.evidence / f'{self.number:03d}.log').write_text(result.stdout)
        if expected_error:
            if result.returncode == 0 or expected_error not in result.stdout:
                raise AssertionError('expected exact refusal missing: ' + expected_error)
        elif result.returncode != 0:
            raise AssertionError(f'command {self.number} failed ({result.returncode}); see evidence log')
        return result.stdout.strip()

    def sql(self, sql, env=None):
        return self.run(PSQL + ['--command', sql], env)

    def create(self, label):
        prefix = 'macsad_restore_lean_' if label == 'restore' else 'macsad_lean_' + label + '_'
        name = prefix + uuid.uuid4().hex[:16]
        if not re.fullmatch(r'(macsad_lean_(legacy|upgrade|fresh)_|macsad_restore_lean_)[a-f0-9]{16}', name):
            raise AssertionError('invalid owned scratch name')
        self.run(['createdb', '--template=template0', '--owner=macsad_owner', name])
        self.created.append(name)  # Own it only after creation succeeded.
        quoted = '"' + name + '"'
        connect_roles = ', '.join(ROLE_PATHS)
        self.sql(f'REVOKE ALL ON DATABASE {quoted} FROM PUBLIC; GRANT CONNECT ON DATABASE {quoted} TO {connect_roles};')
        settings = [f'ALTER DATABASE {quoted} SET search_path = pg_catalog;']
        settings += [f'ALTER ROLE {role} IN DATABASE {quoted} SET search_path = {path};' for role, path in ROLE_PATHS.items()]
        settings += [f'ALTER ROLE macsad_viewer IN DATABASE {quoted} SET {key}={value};' for key, value in [
            ('default_transaction_read_only', 'on'), ('statement_timeout', "'30s'"),
            ('lock_timeout', "'5s'"), ('idle_in_transaction_session_timeout', "'30s'")]]
        self.sql('\n'.join(settings))
        env = dict(self.env, PGDATABASE=name)
        self.sql('REVOKE ALL ON SCHEMA public FROM PUBLIC', env)
        return env

    def ledger(self, env):
        return self.sql("SELECT jsonb_agg(jsonb_build_array(version,name,encode(script_sha256,'hex'),applied_at,applied_by) ORDER BY version) FROM macsad_meta.schema_migration", env)

    def migrate_twice(self, staged, env, label):
        runner = ['bash', str(staged / 'database/apply_migrations.sh')]
        self.run(runner, env, cwd=staged)
        before = self.ledger(env)
        self.run(runner, env, cwd=staged)
        if before != self.ledger(env):
            raise AssertionError(label + ': repeated migration changed exact ledger')
        self.results[label] = 'passed'

    def verifier_negative_controls(self, staged, env):
        verify = PSQL + ['--file', str(staged / 'database/verify.sql')]
        # Unrelated app-executable function still refuses. No broad prefix grant.
        self.sql('SET ROLE macsad_owner; CREATE FUNCTION macsad.lean_acl_unapproved_control() RETURNS integer LANGUAGE sql AS $$SELECT 1$$; GRANT EXECUTE ON FUNCTION macsad.lean_acl_unapproved_control() TO macsad_app;', env)
        self.run(verify, env, expected_error='macsad_app can execute a routine outside the approved API')
        self.sql('SET ROLE macsad_owner; DROP FUNCTION macsad.lean_acl_unapproved_control()', env)
        # A missing expected permission must not disappear from a NOT IN list.
        self.sql('SET ROLE macsad_owner; REVOKE EXECUTE ON FUNCTION macsad.lean_digest(jsonb) FROM macsad_app', env)
        self.run(verify, env, expected_error='approved Lean API contract differs: macsad.lean_digest(jsonb)')
        self.sql('SET ROLE macsad_owner; GRANT EXECUTE ON FUNCTION macsad.lean_digest(jsonb) TO macsad_app', env)
        # Absent expected identity and altered execution/security config refuse.
        self.sql('SET ROLE macsad_owner; ALTER FUNCTION macsad.lean_digest(jsonb) RENAME TO lean_digest_missing_control', env)
        self.run(verify, env, expected_error='approved Lean API is missing: macsad.lean_digest(jsonb)')
        self.sql('SET ROLE macsad_owner; ALTER FUNCTION macsad.lean_digest_missing_control(jsonb) RENAME TO lean_digest', env)
        self.sql('SET ROLE macsad_owner; ALTER FUNCTION macsad.lean_digest(jsonb) SECURITY DEFINER', env)
        self.run(verify, env, expected_error='approved Lean API contract differs: macsad.lean_digest(jsonb)')
        self.sql('SET ROLE macsad_owner; ALTER FUNCTION macsad.lean_digest(jsonb) SECURITY INVOKER', env)
        self.sql('SET ROLE macsad_owner; GRANT EXECUTE ON FUNCTION macsad.lean_digest(jsonb) TO PUBLIC', env)
        self.run(verify, env, expected_error='PUBLIC retains EXECUTE on MaCSad routines')
        self.sql('SET ROLE macsad_owner; REVOKE EXECUTE ON FUNCTION macsad.lean_digest(jsonb) FROM PUBLIC', env)
        self.run(verify, env)
        self.results['exact_acl_positive_and_five_negative_controls'] = 'passed'

    def close(self):
        failures = []
        for name in reversed(self.created[:]):
            try:
                self.run(['dropdb', '--', name])
                self.created.remove(name)
            except Exception as error:
                failures.append(f'{name}: {error}')
        if failures:
            raise AssertionError('owned scratch cleanup failed: ' + '; '.join(failures))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--admission-version', type=int, choices=(2, 3), default=3,
        help='2 runs the unchanged negative regression against original v2; never treats its failure as success')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    evidence = args.evidence_dir.resolve()
    if evidence == root or root in evidence.parents:
        raise SystemExit('evidence must be outside the repository')
    evidence.mkdir(parents=False, exist_ok=False)
    for tool in ('psql', 'pg_dump', 'pg_restore', 'createdb', 'dropdb', 'bash', 'sha256sum', 'awk', 'cmp', 'comm', 'sort', 'stat', 'realpath', 'python3'):
        if shutil.which(tool) is None:
            raise SystemExit('required test tool missing: ' + tool)
    sources = source_manifest(root, CURRENT_MIGRATIONS)
    (evidence / 'source-manifest.json').write_text(json.dumps(sources, indent=2, sort_keys=True) + '\n')
    h = Harness(root, evidence)
    outcome = {'schema': 'macsad-lean-pg16-evidence/1', 'passed': False, 'tests': {},
               'admission_schema': args.admission_version}
    def interrupted(signum, frame):
        raise InterruptedError('PG16 cohort received termination signal')
    previous_term = signal.signal(signal.SIGTERM, interrupted)
    try:
        if not re.search(r'\(PostgreSQL\) 16(?:\.|\s)', h.run(['psql', '--version'])):
            raise AssertionError('psql16 required')
        if not 160000 <= int(h.sql('SHOW server_version_num')) < 170000:
            raise AssertionError('PG16 server required')
        with tempfile.TemporaryDirectory(prefix='macsad-lean-migration-stage.') as temporary:
            staged = Path(temporary)
            stage_v1(root, staged, sources)
            # Full original v1 recovery drill and assertions, with only migration
            # 0001 visible to BOTH its initial and independent second seed.
            legacy = h.create('legacy')
            h.migrate_twice(staged, legacy, 'v1_recovery_fresh_repeat')
            legacy_env = dict(legacy, MACSAD_TEST_ADMIN_USER=h.env['PGUSER'])
            legacy_env.pop('MACSAD_ROUNDTRIP_SKIP_SEED', None)
            legacy_scratch = h.sql("SELECT COALESCE(jsonb_agg(datname ORDER BY datname),'[]') FROM pg_database WHERE datname ~ '^macsad_(restore|seed)_contract_'")
            h.run(['bash', str(staged/'database/tests/data_workers_roundtrip.sh')],
                  legacy_env, cwd=staged)
            if h.sql("SELECT COALESCE(jsonb_agg(datname ORDER BY datname),'[]') FROM pg_database WHERE datname ~ '^macsad_(restore|seed)_contract_'") != legacy_scratch:
                raise AssertionError('original v1 roundtrip left a scratch database behind')
            h.results['unchanged_complete_v1_worker_roundtrip'] = 'passed'
            upgrade = h.create('upgrade')
            h.migrate_twice(staged, upgrade, 'v1_fresh_repeat')
            h.run(PSQL + ['--file', str(staged/'database/tests/0001_invariants.sql')], upgrade)
            h.run(['bash', str(staged/'database/workers/seed_representative_v1.sh')], upgrade, cwd=staged)
            h.run(['bash', str(staged/'database/tests/representative_v1_field_coverage.sh')], upgrade, cwd=staged)
            h.results['unchanged_v1_invariants_fixture_field_coverage'] = 'passed'
            v1_ledger = json.loads(h.ledger(upgrade))
            copy_pinned(root, staged, MIGRATIONS[1], sources)
            h.migrate_twice(staged, upgrade, 'v1_to_v2_upgrade_repeat')
            if json.loads(h.ledger(upgrade))[:1] != v1_ledger:
                raise AssertionError('upgrade changed historical v1 ledger provenance')
            h.run(PSQL + ['--file', str(staged/'database/tests/0002_lean_attempt_controls.sql')], upgrade)
            h.results['new_transaction_controls'] = 'passed'
            h.run(PSQL + ['--file', str(staged/'database/tests/0002_lean_concurrency_setup.sql')], upgrade)
            h.results.update(concurrency_run(upgrade))
            h.verifier_negative_controls(staged, upgrade)
            recovery(h, staged, upgrade, 'v2_upgraded_recovery')
            fresh = h.create('fresh')
            h.migrate_twice(staged, fresh, 'v2_fresh_repeat')
            h.run(PSQL + ['--file', str(staged/'database/tests/0001_invariants.sql')], fresh)
            h.results['unchanged_invariants_on_fresh_v2'] = 'passed'
            recovery(h, staged, fresh, 'v2_fresh_recovery')
            # Preserve all original v2 controls/recoveries before upgrading.
            # RED is a real nonzero run of the identical assertions against v2.
            if args.admission_version == 3:
                v2_ledger = json.loads(h.ledger(upgrade))
                copy_pinned(root, staged, FORWARD_MIGRATION, sources)
                h.migrate_twice(staged, upgrade, 'v2_to_v3_upgrade_repeat')
                if json.loads(h.ledger(upgrade))[:2] != v2_ledger:
                    raise AssertionError('forward upgrade changed historical v1/v2 ledger provenance')
            h.results.update(admission_expiry_run(upgrade))
            if args.admission_version == 3:
                h.verifier_negative_controls(staged, upgrade)
                recovery_v3(h, staged, upgrade, 'v3_upgraded_recovery')
                current = h.create('fresh')
                h.migrate_twice(staged, current, 'v3_fresh_repeat')
                h.run(PSQL + ['--file', str(staged/'database/tests/0001_invariants.sql')], current)
                h.results['unchanged_invariants_on_fresh_v3'] = 'passed'
                recovery_v3(h, staged, current, 'v3_fresh_recovery')
        if any(digest(root / relative) != expected for relative, expected in sources.items()):
            raise AssertionError('test source changed during execution')
        outcome['passed'] = True
    except BaseException as error:
        outcome['error'] = str(error)
        raise
    finally:
        outcome['tests'] = h.results
        try:
            h.close()
        except BaseException as error:
            outcome['passed'] = False
            outcome['cleanup_error'] = str(error)
            raise
        finally:
            (evidence/'result.json').write_text(json.dumps(outcome, indent=2, sort_keys=True)+'\n')
            signal.signal(signal.SIGTERM, previous_term)
    print(json.dumps(outcome, sort_keys=True))


if __name__ == '__main__':
    main()
