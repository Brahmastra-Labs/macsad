"""Additive real-PG recovery checks. Mechanical test orchestration only."""
import hashlib
import json

# All rows, including generated UUIDs, times, audit/event/outbox/receipt state,
# are compared exactly within one database backup. No fixture exclusions.
SNAPSHOT_SQL = r"""
\set QUIET 1
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE macsad_owner;
SET LOCAL timezone = 'UTC';
SET LOCAL extra_float_digits = 3;
SELECT format(
  'SELECT jsonb_build_object(''table'', %L, ''rows'', COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text COLLATE "C"), ''[]''::jsonb))::text FROM %I.%I AS t;',
  n.nspname || '.' || c.relname, n.nspname, c.relname)
FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname IN ('macsad', 'macsad_meta') AND c.relkind IN ('r', 'p')
ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C"
\gexec
COMMIT;
"""


def snapshot(h, env):
    output = h.run(['psql', '--no-psqlrc', '--quiet', '--tuples-only', '--no-align',
                    '--set=ON_ERROR_STOP=1'], env, stdin=SNAPSHOT_SQL)
    lines = output.splitlines()
    rows = [json.loads(line, parse_float=str) for line in lines]
    if len(rows) != 47 or len({row['table'] for row in rows}) != 47:
        raise AssertionError('recovery snapshot must include exactly all 47 v1/v2 tables')
    # Compare canonical PostgreSQL text, not host floats: numeric(30,12) must
    # remain exact even beyond IEEE-754 precision. JSON parsing checks shape only.
    return lines


def assert_empty(h, env):
    if h.sql("SELECT count(*) FROM pg_namespace WHERE nspname IN ('macsad','macsad_meta')", env) != '0':
        raise AssertionError('rejected restore mutated the target')


def recovery(h, staged, source, label):
    if h.sql('SELECT current_version FROM macsad.schema_version_v', source) != '2':
        raise AssertionError('v2 recovery requires exactly schema 2')
    before = snapshot(h, source)
    ledger = h.ledger(source)
    case_dir = h.evidence / label
    case_dir.mkdir()
    workers = staged / 'database/workers'
    refs = h.run(['psql', '--no-psqlrc', '--quiet', '--tuples-only', '--no-align',
                  '--field-separator=\t', '--set=ON_ERROR_STOP=1',
                  '--file', str(workers/'sql/referenced_blobs.sql')], source)
    cas = case_dir / 'cas.tsv'
    cas.write_text('format\tmacsad-cas-manifest/1\n' +
                   ''.join('blob\t' + line + '\n' for line in refs.splitlines()))
    # Only this harness owns/writes these scratch databases. The digest is a
    # test fence, not evidence that production writers were fenced or CAS bytes
    # were copied. Existing worker metadata-closure checks still run unchanged.
    fence = hashlib.sha256(('isolated PG16 recovery test: ' + source['PGDATABASE']).encode()).hexdigest()
    bundle = case_dir / 'backup'
    h.run(['bash', str(workers/'backup_database.sh'), str(bundle), str(cas), fence], source, cwd=staged)
    manifest = bundle/'manifest.tsv'
    if 'schema_version\t2' not in manifest.read_text().splitlines():
        raise AssertionError('backup did not bind schema version 2')
    trusted = hashlib.sha256(manifest.read_bytes()).hexdigest()
    target = h.create('restore')
    restore = ['bash', str(workers/'restore_database.sh'), str(bundle), str(cas)]
    wrong = ('0' if trusted[0] != '0' else '1') + trusted[1:]
    h.run(restore + [wrong], target, expected_error='manifest.tsv does not match the externally trusted digest', cwd=staged)
    assert_empty(h, target)
    h.sql("CREATE TYPE public.macsad_recovery_control AS ENUM ('blocked')", target)
    h.run(restore + [trusted], target, expected_error='restore target public schema contains types', cwd=staged)
    assert_empty(h, target)
    h.sql('DROP TYPE public.macsad_recovery_control', target)
    h.run(restore + [trusted], target, cwd=staged)
    if h.ledger(target) != ledger or snapshot(h, target) != before:
        raise AssertionError('restored v2 ledger or table rows differ from source')
    if snapshot(h, source) != before:
        raise AssertionError('source changed during isolated recovery')
    # Refusal remains atomic even after a legitimate restore; no --clean path.
    h.run(restore + [trusted], target, expected_error='restore target contains non-template schemas', cwd=staged)
    if h.ledger(target) != ledger or snapshot(h, target) != before:
        raise AssertionError('rejected second restore changed existing data')
    (case_dir/'comparison.json').write_text(json.dumps({
        'schema': 'macsad-recovery-test/1', 'source_schema': 2,
        'exact_tables': 47, 'exact_rows_and_ledger': True,
        'manifest_sha256': trusted,
        'snapshot_sha256': hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest(),
        'production_fence_or_cas_bytes_verified': False,
    }, indent=2, sort_keys=True)+'\n')
    h.results[label] = 'passed'
