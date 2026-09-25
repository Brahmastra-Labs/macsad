import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from host_adapters.local_cas import LocalCAS
from host_adapters.artifact_archive import archive_file_set


class ArtifactArchiveTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.store = LocalCAS(str(Path(self.directory.name).resolve()), max_bytes=65536)
        self.addCleanup(self.store.close)

    def index(self, entries):
        files = {}
        for name, value in entries.items():
            files[name] = {'sha256': self.store.put(value), 'bytes': len(value)}
        return self.put_index(files)

    def put_index(self, files):
        value = {'schema': 'macsad-cas-file-set/1', 'files': files}
        return self.store.put((json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode())

    def archive(self, index, **changes):
        limits = dict(max_total_bytes=65536, max_archive_bytes=131072, max_files=64)
        limits.update(changes)
        return archive_file_set(self.store, index, **limits)

    def test_exact_files_unicode_and_deterministic_bytes(self):
        entries = {'source/theorem.lean': b'example : True := True.intro\n',
                   'transport.lg': 'Theorem α\n'.encode(), 'certificate.json': b'{}',
                   'empty': b'', 'source/α.txt': b'unicode filename'}
        index = self.index(entries)
        first = self.archive(index)
        self.assertEqual(first, self.archive(index))
        with zipfile.ZipFile(io.BytesIO(first)) as result:
            self.assertEqual(result.namelist(), sorted(entries))
            for name, content in entries.items():
                info = result.getinfo(name)
                self.assertEqual(result.read(name), content)
                self.assertEqual(info.date_time, (1980, 1, 1, 0, 0, 0))
                self.assertEqual(info.external_attr >> 16, 0o100400)
                self.assertEqual(info.compress_type, zipfile.ZIP_STORED)

    def test_missing_or_corrupt_object_produces_no_archive(self):
        digest = self.store.put(b'file')
        missing = self.put_index({'file': {'sha256': '0' * 64, 'bytes': 4}})
        with self.assertRaises(FileNotFoundError):
            self.archive(missing)
        path = Path(self.directory.name) / digest
        path.chmod(0o600)
        path.write_bytes(b'evil')
        with self.assertRaises(ValueError):
            self.archive(self.put_index({'file': {'sha256': digest, 'bytes': 4}}))

    def test_wrong_size_and_total_file_archive_limits(self):
        index = self.index({'a': b'abc', 'b': b'defg'})
        for changes in ({'max_files': 1}, {'max_total_bytes': 6}, {'max_archive_bytes': 22}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.archive(index, **changes)
        self.assertTrue(self.archive(index, max_files=2, max_total_bytes=7))
        wrong = self.put_index({'a': {'sha256': self.store.put(b'abc'), 'bytes': 2}})
        with self.assertRaises(ValueError):
            self.archive(wrong)

    def test_path_aliases_and_parent_file_collisions_refused(self):
        for name in ('../x', '/x', 'a/../x', 'a//x', './x', 'x/', 'C:/x', 'a\\b', 'a\0b'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.archive(self.index({name: b'x'}))
        with self.assertRaises(ValueError):
            self.archive(self.index({'a': b'a', 'a/b': b'b'}))

    def test_duplicate_index_fields_schema_and_metadata_refused(self):
        digest = self.store.put(b'x')
        record = json.dumps({'sha256': digest, 'bytes': 1})
        duplicate = ('{"schema":"macsad-cas-file-set/1","files":{"a":' + record + ',"a":' + record + '}}').encode()
        with self.assertRaises(ValueError):
            self.archive(self.store.put(duplicate))
        for record in ({'sha256': digest, 'bytes': True}, {'sha256': digest, 'bytes': -1},
                       {'sha256': digest, 'bytes': 1, 'url': 'https://example.invalid'},
                       {'sha256': digest.upper(), 'bytes': 1}):
            with self.subTest(record=record), self.assertRaises(ValueError):
                self.archive(self.put_index({'a': record}))
        for value in ({'schema': 'unknown', 'files': {}}, {'schema': 'macsad-cas-file-set/1', 'files': {}, 'extra': 1}):
            with self.assertRaises(ValueError):
                self.archive(self.store.put(json.dumps(value).encode()))

    def test_invalid_limits_and_oversize_archive_are_refused(self):
        index = self.index({'a': b'x'})
        for key in ('max_total_bytes', 'max_archive_bytes', 'max_files'):
            for value in (True, -1, '10', None):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    self.archive(index, **{key: value})
        archive = self.archive(index)
        self.assertEqual(archive, self.archive(index, max_archive_bytes=len(archive)))
        with self.assertRaises(ValueError):
            self.archive(index, max_archive_bytes=len(archive) - 1)


if __name__ == '__main__':
    unittest.main()
