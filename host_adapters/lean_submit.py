"""Capture a local Lean project → LOGOS package → fresh replay evidence loop.

Explicit development connection only. No server queue, DB write, auth service,
release promotion or Python proof decision. Exit zero means evidence captured;
read the two LOGOS worker statuses and their retained raw receipts.
"""
import argparse
import hashlib
import os
from pathlib import Path
import tempfile
import uuid

from host_adapters.artifact_archive import archive_file_set
from host_adapters.lean_capture import exporter_snapshot, manifest_facts, pins, save_observation, save_tree, snapshot_tree
from host_adapters.lean_package_capture import capture_lean_package
from host_adapters.lean_result import lean_import_policy_arguments, lean_replay_policy_arguments
from host_adapters.local_cas import LocalCAS
from host_adapters.logos_directory import digest as file_digest, execution_environment, inspect_connection, regular
from host_adapters.proof_demo import _json_bytes, publish_evidence, write_new
from host_adapters.proof_process import read_source, run_bounded
from host_adapters.worker_artifacts import capture_published_evidence

REPOSITORY = Path(__file__).resolve().parents[1]
ADAPTERS = ('logos_directory.py', 'logos_built_candidate.py', 'proof_process.py',
            'lean_result.py', 'lean_submit.py', 'lean_capture.py', 'lean_package_capture.py',
            'local_cas.py', 'worker_artifacts.py', 'artifact_archive.py', 'proof_demo.py')
IMPORT_STATUSES = ('verified', 'invalid_source', 'unsupported_feature',
                  'disallowed_assumptions', 'resource_limit', 'infrastructure_failure',
                  'rejected_contract')
REPLAY_STATUSES = ('rejected_contract', 'replayed', 'replay_failed')
OBJECT_BYTES = 8*1024*1024
TOTAL_BYTES = 64*1024*1024


def run_submission(project, target, output_directory, exporter, cas_directory, *,
                   runner, expected_logos=None):
    if runner != 'development-directory':
        raise ValueError('explicit development-directory runner is required')
    if type(target) is not str or not target or len(target.encode('utf-8')) > 256 or '\0' in target:
        raise ValueError('target must be nonempty bounded UTF-8 text')
    expected_logos = target if expected_logos is None else expected_logos
    if type(expected_logos) is not str or not expected_logos or len(expected_logos.encode('utf-8')) > 256 or '\0' in expected_logos:
        raise ValueError('expected LOGOS target must be nonempty bounded UTF-8 text')
    output = Path(output_directory)
    if output.is_symlink() or not output.is_dir():
        raise ValueError('output directory must already exist without a symlink')
    output = output.resolve(strict=True)
    project_files = snapshot_tree(Path(project))
    exporter_files = exporter_snapshot(Path(exporter))
    connection = inspect_connection(REPOSITORY)
    if connection['mode'] not in ('development-directory', 'development-built-candidate') or connection['release_admitted'] is not False:
        raise ValueError('explicit measured development connection required')
    policy_files = snapshot_tree(REPOSITORY/'logos/proof-worker')
    source_files = {'scripts/dev.sh': read_source(REPOSITORY/'scripts/dev.sh')}
    source_files.update({'host_adapters/'+name: read_source(REPOSITORY/'host_adapters'/name) for name in ADAPTERS})
    pending = Path(tempfile.mkdtemp(prefix='.partial-lean-', dir=output))
    # Resolve through the existing strict connector once, then execute exactly
    # its measured private snapshot. No raw/unverified executable override.
    wrapper = [connection['snapshot_binary']]
    home = str(Path.home())
    environment = {'PATH': home+'/.cargo/bin:'+home+'/.elan/bin:'+os.environ.get('PATH', os.defpath),
                   'HOME': home, 'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8'}
    if 'ELAN_HOME' in os.environ:
        environment['ELAN_HOME'] = os.environ['ELAN_HOME']
    environment = execution_environment(connection, environment)

    def identity():
        snapshot = Path(connection['snapshot_binary'])
        regular(snapshot, executable=True)
        if file_digest(snapshot) != connection['binary_sha256']:
            raise RuntimeError('measured development executable changed')
        for name, content in source_files.items():
            if read_source(REPOSITORY/name) != content:
                raise RuntimeError('mechanical adapter source changed')
        if snapshot_tree(REPOSITORY/'logos/proof-worker') != policy_files:
            raise RuntimeError('LOGOS worker source changed')
        if snapshot_tree(pending/'policy') != policy_files or snapshot_tree(pending/'project') != project_files:
            raise RuntimeError('copied policy or submitted project changed')
        if exporter_snapshot(Path(exporter)) != exporter_files or exporter_snapshot(pending/'exporter') != exporter_files:
            raise RuntimeError('selected exporter sources or compiled modules changed')

    def invoke(label, arguments, cwd, seconds, cap):
        identity()
        argv = wrapper+arguments
        observed = run_bounded(argv, cwd=cwd, environment=environment,
                               timeout_seconds=seconds, output_limit=cap)
        save_observation(pending, label, argv, cwd, observed, seconds, cap)
        identity()
        if observed.termination != 'exited' or type(observed.exit_code) is not int or not 0 <= observed.exit_code <= 255:
            raise RuntimeError('process did not return a normal exit; raw evidence retained')
        return observed

    def classify(label, facts, statuses):
        observed = invoke(label, ['run', '--interpret', '--max-steps', '1000000',
                                  '--timeout', '5s', '--seed', '7', '--quiet', '--color', 'never', '--', *facts],
                          pending/'policy', 15, 4096)
        if observed.exit_code != 0 or observed.stderr or observed.stdout not in tuple((s+'\n').encode() for s in statuses):
            raise RuntimeError('LOGOS worker did not return a recognized status')
        return observed.stdout.decode('ascii').strip()

    try:
        save_tree(pending/'project', project_files)
        save_tree(pending/'policy', policy_files)
        save_tree(pending/'exporter', exporter_files)
        save_tree(pending/'mechanical-adapter', source_files)
        write_new(pending/'connection.json', _json_bytes(connection))
        request = {'schema': 'macsad-lean-local-request/1', 'target': target,
                   'expected_logos': expected_logos, 'source_files': pins(project_files),
                   'exporter': str(Path(exporter).absolute()), 'exporter_files': pins(exporter_files),
                   'tool_discovery': environment, 'runner': runner,
                   'policy_files': pins(policy_files), 'adapter_files': pins(source_files)}
        write_new(pending/'request.json', _json_bytes(request))
        package = pending/'package'
        imported = invoke('import', ['lean', 'import', '--project', str(pending/'project'),
                                     '--target', target, '--out', str(package),
                                     '--exporter', str(pending/'exporter')], pending, 60, 32768)
        digest, schema = manifest_facts(package)
        facts = lean_import_policy_arguments(imported.stdout, exit_code=imported.exit_code,
                    expected_lean=target, expected_logos=expected_logos,
                    expected_package_path=str(package), observed_manifest_sha256=digest,
                    observed_package_schema=schema)
        import_status = classify('import-policy', facts, IMPORT_STATUSES)
        summary = {'schema': 'macsad-lean-local-evidence/1', 'connection': connection,
                   'import_policy_status': import_status, 'replay_policy_status': None,
                   'package_file_set': None, 'manifest_sha256': digest,
                   'scope': 'Private local evidence capture; no release admission, DB authorization or web publication'}
        with LocalCAS(cas_directory, max_bytes=OBJECT_BYTES) as store:
            if digest is not None:
                # Presence drives mechanical replay; Python does not reinterpret worker acceptance.
                index = capture_lean_package(package, digest, store, max_total_bytes=TOTAL_BYTES)
                replayed = invoke('replay', ['lean', 'replay', str(package)], pending, 60, 32768)
                if manifest_facts(package) != (digest, schema):
                    raise RuntimeError('package manifest changed during replay')
                replay_facts = lean_replay_policy_arguments(replayed.stdout, exit_code=replayed.exit_code,
                                                            expected_manifest_sha256=digest)
                summary['replay_policy_status'] = classify('replay-policy', replay_facts, REPLAY_STATUSES)
                # Recheck all package bytes after replay before making a downloadable archive.
                after = capture_lean_package(package, digest, store, max_total_bytes=TOTAL_BYTES)
                if after != index:
                    raise RuntimeError('package file set changed during replay')
                summary['package_file_set'] = {'sha256': index.sha256, 'bytes': index.bytes}
                archive = archive_file_set(store, index.sha256, max_total_bytes=TOTAL_BYTES,
                                            max_archive_bytes=TOTAL_BYTES+1024*1024)
                write_new(pending/'package.zip', archive)
                summary['package_archive_sha256'] = hashlib.sha256(archive).hexdigest()
            identity()
            if inspect_connection(REPOSITORY) != connection:
                raise RuntimeError('full development connection identity changed')
            write_new(pending/'result.json', _json_bytes(summary))
            destination = publish_evidence(pending, 'run-'+str(uuid.uuid4()), {'schema': 'macsad-lean-local-files/1'})
            index = capture_published_evidence(destination, store, max_total_bytes=TOTAL_BYTES,
                                               max_files=256)
        return dict(summary, evidence_directory=str(destination),
                    evidence_file_set={'sha256': index.sha256, 'bytes': index.bytes})
    except Exception as error:
        retained = locals().get('destination', pending)
        raise RuntimeError('Lean capture incomplete; partial evidence retained at '+str(retained)) from error


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--logos-target', help='expected emitted LOGOS name; defaults to the requested Lean name')
    parser.add_argument('--exporter', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--cas-directory', type=Path, required=True)
    parser.add_argument('--runner', choices=['development-directory'], required=True)
    options = parser.parse_args(argv)
    try:
        result = run_submission(options.project, options.target, options.output_directory,
                                options.exporter, options.cas_directory, runner=options.runner,
                                expected_logos=options.logos_target)
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(2, str(error)+'\n')
    print(_json_bytes(result).decode('utf-8'), end='')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
