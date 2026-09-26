"""Mechanical CLI controls; fake processes never claim native/kernel validation."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from host_adapters import lean_submit as subject
from host_adapters.proof_process import ProcessObservation
from host_adapters.tests.test_lean_result import report, receipt, wire


class LeanSubmitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / 'repo'
        for name in ('scripts/dev.sh', 'host_adapters/logos_directory.py',
                     'host_adapters/logos_built_candidate.py', 'host_adapters/proof_process.py',
                     'host_adapters/lean_result.py', 'host_adapters/lean_submit.py',
                     'host_adapters/lean_capture.py', 'host_adapters/lean_package_capture.py',
                     'host_adapters/local_cas.py', 'host_adapters/worker_artifacts.py',
                     'host_adapters/artifact_archive.py', 'host_adapters/proof_demo.py',
                     'logos/proof-worker/Largo.toml', 'logos/proof-worker/src/main.lg'):
            file = self.repo / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('# fixture source identity only\n')
        self.project = self.root / 'project'; self.project.mkdir()
        (self.project / 'Demo.lean').write_text('theorem example : True := True.intro\n')
        self.output = self.root / 'output'; self.output.mkdir()
        self.cas = self.root / 'cas'; self.cas.mkdir()
        exporter = self.root/'exporter'
        (exporter/'.lake/build/lib').mkdir(parents=True)
        for name in ('Main.lean', 'Export.lean', '.lake/build/lib/Export.olean'):
            (exporter/name).write_bytes(b'fixture exporter bytes\n')
        binary = self.root/'largo'; binary.write_bytes(b'fixture executable identity\n'); binary.chmod(0o700)
        self.connection = dict(mode='development-directory', release_admitted=False,
                               source_binary_correspondence='unverified', binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                               workspace=str(self.root / 'workspace'), snapshot_binary=str(binary))
        self.calls = []
        self.policies = iter((b'verified\n', b'replayed\n'))
        self.import_transform = lambda value: value
        self.replay_transform = lambda value: value

    def fake_process(self, argv, *, cwd, **limits):
        self.calls.append((argv, cwd, limits))
        if 'import' in argv:
            self.package = Path(argv[argv.index('--out') + 1]); self.package.mkdir()
            (self.package / 'proof.lg').write_bytes(b'# actual emitted bytes fixture\n')
            (self.package / 'certificate.json').write_bytes(b'{"opaque":"fixture"}\n')
            manifest = {'schema': 'logos-lean-package/1', 'document': 'proof.lg',
                        'files': {n: hashlib.sha256((self.package/n).read_bytes()).hexdigest()
                                  for n in ('proof.lg', 'certificate.json')}}
            (self.package / 'manifest.json').write_bytes(wire(manifest))
            self.digest = hashlib.sha256(wire(manifest)).hexdigest()
            value = report(); value['target'] = {'lean': 'T.example', 'logos': 'T.example'}
            value['package'] = {'path': str(self.package), 'manifest_sha256': self.digest}
            return ProcessObservation(0, wire(self.import_transform(value)), b'import diagnostics\n', 'exited')
        if 'replay' in argv:
            value = receipt(); value['manifest_sha256'] = self.digest
            return ProcessObservation(0, wire(self.replay_transform(value)), b'', 'exited')
        return ProcessObservation(0, next(self.policies), b'', 'exited')

    def run_capture(self, process=None, connections=None):
        with patch.object(subject, 'REPOSITORY', self.repo), \
             patch.object(subject, 'inspect_connection', side_effect=connections or (lambda _: self.connection)), \
             patch.object(subject, 'run_bounded', side_effect=process or self.fake_process):
            return subject.run_submission(self.project, 'T.example', self.output,
                                          self.root / 'exporter', self.cas,
                                          runner='development-directory')

    def test_success_uses_actual_policy_and_fresh_replay_and_cas_archive(self):
        value = self.run_capture()
        self.assertEqual(value['import_policy_status'], 'verified')
        self.assertEqual(value['replay_policy_status'], 'replayed')
        self.assertNotIn('verified', value)
        self.assertIs(value['connection']['release_admitted'], False)
        self.assertEqual(sum('replay' in c[0] for c in self.calls), 1)
        self.assertEqual(sum('run' in c[0] for c in self.calls), 2)
        self.assertIn('--project', self.calls[0][0])
        self.assertNotEqual(self.calls[0][0][self.calls[0][0].index('--project')+1], str(self.project))
        bundle = Path(value['evidence_directory'])
        self.assertEqual((bundle/'import.stdout').read_bytes(), wire(self.import_transform(json.loads((bundle/'import.stdout').read_bytes()))))
        with zipfile.ZipFile(bundle/'package.zip') as archive:
            self.assertEqual(archive.read('proof.lg'), b'# actual emitted bytes fixture\n')
            self.assertEqual(archive.read('certificate.json'), b'{"opaque":"fixture"}\n')
            self.assertEqual(hashlib.sha256(archive.read('manifest.json')).hexdigest(), self.digest)
        self.assertTrue(value['evidence_file_set']['sha256'])
        self.assertTrue(value['package_file_set']['sha256'])

    def test_python_does_not_promote_rejected_policy_from_claimed_verified(self):
        self.policies = iter((b'rejected_contract\n', b'replay_failed\n'))
        value = self.run_capture()
        self.assertEqual(value['import_policy_status'], 'rejected_contract')
        self.assertEqual(value['replay_policy_status'], 'replay_failed')

    def test_raw_malformed_receipt_survives_decode_failure(self):
        def malformed(*a, **k):
            return ProcessObservation(0, b'{"schema":', b'original stderr', 'exited')
        with self.assertRaisesRegex(RuntimeError, 'partial evidence retained'):
            self.run_capture(malformed)
        partial, = self.output.glob('.partial-lean-*')
        self.assertEqual((partial/'import.stdout').read_bytes(), b'{"schema":')
        self.assertEqual((partial/'import.stderr').read_bytes(), b'original stderr')

    def test_timeout_is_not_synthesized_into_lean_outcome(self):
        def timeout(*a, **k):
            return ProcessObservation(None, b'partial', b'', 'timeout')
        with self.assertRaisesRegex(RuntimeError, 'partial evidence retained'):
            self.run_capture(timeout)
        partial, = self.output.glob('.partial-lean-*')
        self.assertEqual(json.loads((partial/'import.process.json').read_bytes())['termination'], 'timeout')
        self.assertFalse((partial/'result.json').exists())

    def test_identity_change_after_process_refuses_but_retains_raw(self):
        changed = dict(self.connection, binary_sha256='b'*64)
        with self.assertRaisesRegex(RuntimeError, 'partial evidence retained'):
            self.run_capture(connections=iter((self.connection, changed)))
        partial, = self.output.glob('.partial-lean-*')
        self.assertTrue((partial/'import.stdout').is_file())

    def test_unknown_policy_output_never_becomes_status(self):
        self.policies = iter((b'accepted-by-python\n',))
        with self.assertRaisesRegex(RuntimeError, 'partial evidence retained'):
            self.run_capture()
        partial, = self.output.glob('.partial-lean-*')
        self.assertEqual((partial/'import-policy.stdout').read_bytes(), b'accepted-by-python\n')

    def test_symlink_source_refused_before_process(self):
        (self.project/'linked.lean').symlink_to(self.project/'Demo.lean')
        with self.assertRaises((ValueError, RuntimeError, OSError)):
            self.run_capture()
        self.assertEqual(self.calls, [])

    def test_runner_selection_is_explicit_no_environment_default(self):
        with self.assertRaises(ValueError):
            subject.run_submission(self.project, 'T.example', self.output, self.root/'exporter',
                                   self.cas, runner='admitted')

    def test_invalid_source_no_manifest_is_classified_without_replay(self):
        def invalid(argv, *, cwd, **limits):
            self.calls.append((argv, cwd, limits))
            if 'import' in argv:
                value = report(); value['outcome'] = 'invalid_source'
                value['package'] = None; value['target']['logos'] = None
                value['stages'] = dict.fromkeys(value['stages'], 'not_run')
                return ProcessObservation(1, wire(value), b'Lean syntax error', 'exited')
            return ProcessObservation(0, b'invalid_source\n', b'', 'exited')
        result = self.run_capture(invalid)
        self.assertEqual(result['import_policy_status'], 'invalid_source')
        self.assertIsNone(result['package_file_set'])
        self.assertIsNone(result['replay_policy_status'])
        self.assertEqual(len(self.calls), 2)
        self.assertFalse((Path(result['evidence_directory'])/'package.zip').exists())

    def test_expected_target_and_observed_manifest_do_not_echo_claims(self):
        self.import_transform = lambda v: dict(v, target={'lean': 'Other', 'logos': 'Other'},
                                              package={'path': '/forged', 'manifest_sha256': 'f'*64})
        self.policies = iter((b'rejected_contract\n', b'replayed\n'))
        result = self.run_capture()
        policy_argv = self.calls[1][0]
        fields = policy_argv[policy_argv.index('macsad-lean-facts/1')+1:]
        fields = [bytes.fromhex(v).decode() if v != '-' else '' for v in fields]
        self.assertEqual(fields[4:8], ['Other', 'Other', 'T.example', 'T.example'])
        self.assertEqual(fields[10], 'f'*64)
        self.assertEqual(fields[11], self.digest)
        self.assertEqual(result['import_policy_status'], 'rejected_contract')

    def test_copied_policy_mutation_stops_before_any_classification(self):
        def changed(argv, *, cwd, **limits):
            result = self.fake_process(argv, cwd=cwd, **limits)
            (Path(cwd)/'policy/src/main.lg').write_text('# changed after import\n')
            return result
        with self.assertRaisesRegex(RuntimeError, 'partial evidence retained'):
            self.run_capture(changed)
        self.assertEqual(len(self.calls), 1)
        partial, = self.output.glob('.partial-lean-*')
        self.assertTrue((partial/'import.stdout').is_file())

    def test_import_cannot_receive_replay_kind_as_worker_status(self):
        self.policies = iter((b'replayed\n',))
        with self.assertRaisesRegex(RuntimeError, 'partial evidence retained'):
            self.run_capture()

    def test_exporter_bytes_are_snapshotted_and_mutation_is_refused(self):
        def changed(argv, *, cwd, **limits):
            result = self.fake_process(argv, cwd=cwd, **limits)
            original = self.root/'exporter/.lake/build/lib/Export.olean'
            original.write_bytes(b'changed exporter')
            return result
        with self.assertRaisesRegex(RuntimeError, 'partial evidence retained'):
            self.run_capture(changed)
        partial, = self.output.glob('.partial-lean-*')
        self.assertEqual((partial/'exporter/.lake/build/lib/Export.olean').read_bytes(), b'fixture exporter bytes\n')
        self.assertNotEqual(self.calls[0][0][-1], str(self.root/'exporter'))
        self.assertEqual(len(self.calls), 1)

    def test_tool_discovery_uses_allowlisted_home_and_excludes_secret_environment(self):
        with patch.dict('os.environ', {'ELAN_HOME': '/explicit/elan', 'TEST_SECRET': 'never-forward'}):
            value = self.run_capture()
        environment = self.calls[0][2]['environment']
        self.assertEqual(environment['ELAN_HOME'], '/explicit/elan')
        self.assertTrue(environment['HOME'])
        self.assertIn('/.elan/bin:', environment['PATH'])
        self.assertNotIn('TEST_SECRET', environment)
        self.assertEqual(self.calls[0][0][0], self.connection['snapshot_binary'])

    def test_unreadable_subtree_cannot_disappear_from_source_inventory(self):
        def walk(root, **kwargs):
            yield str(root), [], ['Demo.lean']
            if kwargs.get('onerror') is not None:
                kwargs['onerror'](PermissionError('unreadable nested directory'))
        with patch('host_adapters.lean_capture.os.walk', side_effect=walk):
            with self.assertRaises(PermissionError):
                subject.snapshot_tree(self.project)


if __name__ == '__main__':
    unittest.main()
