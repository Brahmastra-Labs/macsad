"""Mechanical package persistence, without accepting any proof claims."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from host_adapters.local_cas import LocalCAS
from host_adapters.worker_artifacts import read_file_set
from host_adapters.lean_package_capture import capture_lean_package


class LeanPackageCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'package'
        self.root.mkdir()
        self.cas = self.base / 'cas'
        self.cas.mkdir()
        self.store = LocalCAS(self.cas, max_bytes=8192)
        self.addCleanup(self.store.close)

    def package(self, files=None, **extra):
        if files is None:
            files = {'theorem.lg': b'LOGOS', 'certificate.json': b'{}',
                     'source/input.lean': 'theorem λ'.encode()}
        digests = {}
        for name, content in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            digests[name] = hashlib.sha256(content).hexdigest()
        return self.manifest(dict(schema='logos-lean-package/1', files=digests, **extra))

    def manifest(self, value):
        raw = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode()
        (self.root / 'manifest.json').write_bytes(raw)
        return hashlib.sha256(raw).hexdigest()

    def capture(self, digest, **limits):
        return capture_lean_package(self.root, digest, self.store,
                                    **dict({'max_total_bytes': 8192}, **limits))

    def test_exact_files_and_raw_manifest_survive_store_reopen(self):
        digest = self.package(receipt={'fresh_replay': {'status': 'not_run'}})
        result = self.capture(digest)
        self.assertEqual(result, self.capture(digest))
        self.store.close()
        self.store = LocalCAS(self.cas, max_bytes=8192)
        self.addCleanup(self.store.close)
        facts = read_file_set(self.store, result.sha256, max_total_bytes=8192)
        self.assertEqual(set(facts), {'manifest.json', 'theorem.lg', 'certificate.json', 'source/input.lean'})
        for name, fact in facts.items():
            self.assertEqual(self.store.get(fact.sha256), (self.root / name).read_bytes())
        self.assertEqual(facts['manifest.json'].sha256, digest)

    def test_claims_are_opaque_and_unlisted_files_are_not_uploaded(self):
        digest = self.package(receipt={'primary_check': {'status': 'failed'}}, outcome='unsupported')
        (self.root / 'unlisted').write_bytes(b'not selected')
        result = self.capture(digest)
        facts = read_file_set(self.store, result.sha256, max_total_bytes=8192)
        self.assertNotIn('unlisted', facts)
        self.assertEqual(self.store.get(facts['manifest.json'].sha256), (self.root / 'manifest.json').read_bytes())

    def test_manifest_identity_is_external_and_checked_before_any_put(self):
        self.package()
        with self.assertRaises(ValueError):
            self.capture('0' * 64)
        self.assertEqual(list(self.cas.iterdir()), [])

    def test_schema_duplicates_shape_and_nonfinite_json_are_rejected(self):
        cases = [b'{"schema":"logos-lean-package/1","files":{},"files":{}}',
                 b'{"schema":"logos-lean-package/1","files":{},"opaque":NaN}',
                 b'{"schema":"logos-lean-package/1","files":{"a":"x","a":"x"}}',
                 {'schema':'logos-lean-package/2','files':{'a':'0'*64}},
                 {'schema':'logos-lean-package/1','files':[]},
                 {'schema':'logos-lean-package/1','files':{}}, []]
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.capture(self.manifest(value))
        self.assertEqual(list(self.cas.iterdir()), [])

    def test_manifest_self_reference_invalid_digest_and_paths_are_rejected(self):
        for name, digest in [('manifest.json','0'*64), ('../escape','0'*64),
                             ('/absolute','0'*64), ('a\\b','0'*64), ('C:file','0'*64),
                             ('a', None), ('a', {'sha256':'0'*64}), ('a','A'*64)]:
            with self.subTest(name=name,digest=digest), self.assertRaises(ValueError):
                self.capture(self.manifest({'schema':'logos-lean-package/1','files':{name:digest}}))
        self.assertEqual(list(self.cas.iterdir()), [])

    def test_missing_or_corrupted_file_does_not_return_index(self):
        digest = self.package()
        (self.root/'theorem.lg').write_bytes(b'wrong')
        with self.assertRaises(ValueError):
            self.capture(digest)
        (self.root/'theorem.lg').unlink()
        with self.assertRaises(OSError):
            self.capture(digest)

    def test_symlink_manifest_and_file_are_rejected(self):
        digest = self.package()
        (self.root/'manifest.json').rename(self.base/'manifest.json')
        (self.root/'manifest.json').symlink_to(self.base/'manifest.json')
        with self.assertRaises(OSError):
            self.capture(digest)
        (self.root/'manifest.json').unlink()
        (self.base/'manifest.json').rename(self.root/'manifest.json')
        (self.root/'theorem.lg').rename(self.base/'theorem.lg')
        (self.root/'theorem.lg').symlink_to(self.base/'theorem.lg')
        with self.assertRaises(OSError):
            self.capture(digest)

    def test_manifest_replacement_between_observation_and_capture_is_rejected(self):
        digest = self.package()
        from host_adapters.worker_artifacts import capture_files
        def replace(*args, **kwargs):
            self.package(receipt='changed')
            return capture_files(*args, **kwargs)
        with patch('host_adapters.lean_package_capture.capture_files', side_effect=replace):
            with self.assertRaises(ValueError):
                self.capture(digest)

    def test_byte_count_file_count_and_manifest_budgets_include_manifest(self):
        digest = self.package()
        total = sum(p.stat().st_size for p in self.root.rglob('*') if p.is_file())
        self.capture(digest, max_total_bytes=total, max_files=4)
        for limits in ({'max_total_bytes':total-1}, {'max_files':3},
                       {'max_manifest_bytes':1}):
            with self.subTest(limits=limits),self.assertRaises(ValueError):
                self.capture(digest, **limits)

    def test_invalid_limits_and_digest_fail_before_reading(self):
        for limits in ({'max_manifest_bytes':True}, {'max_manifest_bytes':0},
                       {'max_manifest_bytes':1.5}, {'max_files':True},
                       {'max_total_bytes':-1}):
            with self.subTest(limits=limits),self.assertRaises(ValueError):
                self.capture('0'*64, **limits)
        for digest in ('bad', None, 'A'*64):
            with self.subTest(digest=digest), self.assertRaises(ValueError):
                self.capture(digest)

    def test_deep_or_invalid_utf8_manifest_fails_with_bounded_error(self):
        for raw in (b'['*1000+b']'*1000, b'\xff', b'{"files":{}} trailing'):
            with self.subTest(length=len(raw)),self.assertRaises(ValueError):
                self.capture(self.manifest(raw))


if __name__ == '__main__':
    unittest.main()
