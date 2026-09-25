"""Explicit real Lean/native tier. Never included in default unit discovery.

Requires a connected private runtime, an actual supported Lean project, built
exporter and fresh evidence/CAS directories. No skipping or process mocks.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import zipfile

from host_adapters.lean_capture import save_observation
from host_adapters.lean_result import lean_replay_policy_arguments
from host_adapters.lean_submit import REPOSITORY, run_submission
from host_adapters.logos_directory import execution_environment, inspect_connection
from host_adapters.proof_demo import _json_bytes, write_new
from host_adapters.proof_process import run_bounded


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--logos-target', required=True)
    parser.add_argument('--exporter', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args(argv)
    args.evidence.mkdir(mode=0o700)
    output = args.evidence/'runs'; output.mkdir(mode=0o700)
    cas = args.evidence/'cas'; cas.mkdir(mode=0o700)
    terminal = {'passed': False, 'native_execution': True}
    try:
        summary = run_submission(args.project, args.target, output, args.exporter, cas,
                                 runner='development-directory', expected_logos=args.logos_target)
        write_new(args.evidence/'capture.json', _json_bytes(summary))
        assert summary['import_policy_status'] == 'verified', summary['import_policy_status']
        assert summary['replay_policy_status'] == 'replayed', summary['replay_policy_status']
        bundle = Path(summary['evidence_directory'])
        downloaded = args.evidence/'downloaded'; downloaded.mkdir(mode=0o700)
        # Use only our own manifest-bound archive. Still validate paths before
        # writing, so this contract never becomes a general archive extractor.
        with zipfile.ZipFile(bundle/'package.zip') as archive:
            assert len(archive.infolist()) <= 64
            for entry in archive.infolist():
                relative = Path(entry.filename)
                assert not relative.is_absolute() and all(p not in ('', '.', '..') for p in relative.parts)
                assert not entry.is_dir() and entry.file_size <= 8*1024*1024
                path = downloaded/relative; path.parent.mkdir(parents=True, exist_ok=True)
                write_new(path, archive.read(entry))
        assert hashlib.sha256((downloaded/'manifest.json').read_bytes()).hexdigest() == summary['manifest_sha256']
        connection = inspect_connection(REPOSITORY)
        assert connection == summary['connection']
        environment = execution_environment(connection, {'PATH': os.defpath, 'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8'})
        command = [connection['snapshot_binary'], 'lean', 'replay', str(downloaded.absolute())]
        observed = run_bounded(command, cwd=downloaded, environment=environment, timeout_seconds=60, output_limit=32768)
        save_observation(args.evidence, 'download-replay', command, downloaded, observed, 60, 32768)
        assert observed.termination == 'exited'
        facts = lean_replay_policy_arguments(observed.stdout, exit_code=observed.exit_code,
                                             expected_manifest_sha256=summary['manifest_sha256'])
        command = [connection['snapshot_binary'], 'run', '--interpret', '--max-steps', '1000000',
                   '--timeout', '5s', '--seed', '7', '--quiet', '--color', 'never', '--', *facts]
        observed = run_bounded(command, cwd=bundle/'policy', environment=environment, timeout_seconds=15, output_limit=4096)
        save_observation(args.evidence, 'download-policy', command, bundle/'policy', observed, 15, 4096)
        assert observed.termination == 'exited' and observed.exit_code == 0
        assert observed.stdout == b'replayed\n' and observed.stderr == b''
        assert inspect_connection(REPOSITORY) == connection
        terminal['passed'] = True
    except BaseException as error:
        terminal['error'] = type(error).__name__+': '+str(error)
        raise
    finally:
        write_new(args.evidence/'terminal.json', _json_bytes(terminal))
    print(json.dumps(terminal))


if __name__ == '__main__':
    main()
