"""Mechanical worker evidence persistence; no toolchain or proof decision."""
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from host_adapters.local_cas import LocalCAS, CorruptObject
from host_adapters.worker_artifacts import FileFact, capture_files, capture_published_evidence, read_file_set


class WorkerArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.bundle = self.root/'bundle'; self.bundle.mkdir()
        self.objects = self.root/'cas'; self.objects.mkdir()
        self.store = LocalCAS(self.objects, max_bytes=4096)
        self.addCleanup(self.store.close)

    def fact(self, name, content, *, size=True):
        path = self.bundle/name; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return FileFact(hashlib.sha256(content).hexdigest(), len(content) if size else None)

    def index(self, result):
        raw = self.store.get(result.sha256)
        self.assertEqual(len(raw), result.bytes)
        return json.loads(raw)

    def test_exact_nested_binary_files_and_index_survive_reopen(self):
        facts = {'source/input.lean':self.fact('source/input.lean', b'\xff\x00\r\n'),
                 'stdout':self.fact('stdout', b''), 'certificate.json':self.fact('certificate.json', b'{}')}
        result = capture_files(self.bundle, facts, self.store, max_total_bytes=6)
        self.store.close()
        self.store = LocalCAS(self.objects, max_bytes=4096)
        self.addCleanup(self.store.close)
        index = self.index(result)
        self.assertEqual(index['schema'], 'macsad-cas-file-set/1')
        for name, fact in facts.items():
            row = index['files'][name]
            self.assertEqual(row, {'sha256':fact.sha256, 'bytes':fact.bytes})
            self.assertEqual(self.store.get(row['sha256']), (self.bundle/name).read_bytes())

    def test_caller_supplied_hash_only_facts_support_lean_package_layout(self):
        facts = {'document.lg':self.fact('document.lg', b'LG', size=False),
                 'source/export.ndjson':self.fact('source/export.ndjson', b'{}\n', size=False)}
        first = capture_files(self.bundle, facts, self.store, max_total_bytes=5)
        second = capture_files(self.bundle, dict(reversed(list(facts.items()))), self.store, max_total_bytes=5)
        self.assertEqual(first, second)
        self.assertEqual(self.index(first)['files']['source/export.ndjson']['bytes'], 3)

    def test_missing_wrong_hash_and_wrong_size_never_commit_an_index(self):
        good = self.fact('file', b'body')
        for facts in ({'missing':good}, {'file':FileFact('0'*64,4)}, {'file':FileFact(good.sha256,3)}):
            with self.subTest(facts=facts), self.assertRaises((OSError,ValueError)):
                capture_files(self.bundle, facts, self.store, max_total_bytes=20)
        self.assertEqual(list(self.objects.iterdir()), [])

    def test_paths_symlink_leaf_and_parent_are_refused(self):
        good = self.fact('file', b'body')
        (self.bundle/'alias').symlink_to(self.bundle, target_is_directory=True)
        (self.bundle/'link').symlink_to(self.bundle/'file')
        for name in ('../file','/file','a/../file','./file','a//file','alias/file','link','a\\file'):
            with self.subTest(name=name), self.assertRaises((OSError,ValueError)):
                capture_files(self.bundle, {name:good}, self.store, max_total_bytes=20)

    def test_file_count_size_and_aggregate_limits(self):
        facts = {'a':self.fact('a',b'aa'), 'b':self.fact('b',b'bb')}
        with self.assertRaises(ValueError):
            capture_files(self.bundle, facts, self.store, max_total_bytes=4,max_files=1)
        with self.assertRaises(ValueError):
            capture_files(self.bundle, facts, self.store, max_total_bytes=3)
        large = {'big':self.fact('big',b'x'*4097)}
        with self.assertRaises(ValueError):
            capture_files(self.bundle, large, self.store, max_total_bytes=8192)
        self.assertEqual(list(self.objects.iterdir()), [])

    def test_corrupt_cas_object_refuses_without_overwrite(self):
        fact = self.fact('file',b'body')
        (self.objects/fact.sha256).write_bytes(b'bad')
        with self.assertRaises(CorruptObject):
            capture_files(self.bundle, {'file':fact}, self.store, max_total_bytes=4)
        self.assertEqual((self.objects/fact.sha256).read_bytes(), b'bad')
        self.assertEqual(len(list(self.objects.iterdir())),1)

    def test_interrupted_index_commit_leaves_bytes_but_no_false_completion(self):
        fact = self.fact('file',b'body')
        put = self.store.put
        def fail_index(content, **kwargs):
            if content.startswith(b'{'):
                raise OSError('index unavailable')
            return put(content, **kwargs)
        with patch.object(self.store,'put',side_effect=fail_index), self.assertRaises(OSError):
            capture_files(self.bundle, {'file':fact}, self.store,max_total_bytes=4)
        self.assertEqual([p.name for p in self.objects.iterdir()], [fact.sha256])
        result = capture_files(self.bundle, {'file':fact}, self.store,max_total_bytes=4)
        self.assertEqual(self.index(result)['files']['file']['sha256'], fact.sha256)

    def test_published_evidence_preserves_manifest_bytes_and_ignores_unlisted_files(self):
        fact = self.fact('input.lg', b'source')
        raw = json.dumps({'schema':'macsad-proof-evidence/1','files':{'input.lg':fact.__dict__},
                          'request':{'uninterpreted':'anything'}}, indent=2).encode()+b'\n'
        (self.bundle/'manifest.json').write_bytes(raw)
        (self.bundle/'unlisted').write_bytes(b'not selected')
        result = capture_published_evidence(self.bundle,self.store,max_total_bytes=4096)
        index = self.index(result)
        self.assertEqual(set(index['files']),{'input.lg','manifest.json'})
        self.assertEqual(self.store.get(index['files']['manifest.json']['sha256']),raw)

    def test_ambiguous_manifest_is_rejected(self):
        for raw in (b'{"files":{},"files":{}}', b'{"files":{"../escape":{"sha256":"bad","bytes":0}}}',
                    b'{"files":{"manifest.json":{"sha256":"bad","bytes":0}}}'):
            (self.bundle/'manifest.json').write_bytes(raw)
            with self.assertRaises(ValueError):
                capture_published_evidence(self.bundle,self.store,max_total_bytes=4096)

    def test_proof_demo_manifest_cannot_omit_exact_size_with_null(self):
        fact = self.fact('file', b'body', size=False)
        (self.bundle/'manifest.json').write_text(json.dumps({'files':{'file':fact.__dict__}}))
        with self.assertRaises(ValueError):
            capture_published_evidence(self.bundle,self.store,max_total_bytes=4096)
        self.assertEqual(list(self.objects.iterdir()), [])

    def test_published_capture_rejects_invalid_limits_before_reading(self):
        for value in (None, '64', True, 0, -1, 1.5):
            with self.subTest(max_files=value),self.assertRaises(ValueError):
                capture_published_evidence(self.bundle,self.store,max_total_bytes=100,max_files=value)
        for value in (None, '100', True, -1, 1.5):
            with self.subTest(max_total_bytes=value),self.assertRaises(ValueError):
                capture_published_evidence(self.bundle,self.store,max_total_bytes=value)

    def test_reader_checks_schema_counts_hashes_sizes_paths_and_namespace(self):
        fact = self.fact('file',b'body')
        result = capture_files(self.bundle, {'file':fact}, self.store,max_total_bytes=4)
        self.assertEqual(read_file_set(self.store,result.sha256,max_total_bytes=4),{'file':fact})
        with self.assertRaises(ValueError):
            read_file_set(self.store,result.sha256,max_total_bytes=3)
        row = {'sha256':fact.sha256,'bytes':4}
        for files in ({'../escape':row},{'/abs':row},{'C:x':row},{'a//b':row},{'a/':row},{'a':row,'a/b':row},
                      {'file':dict(row,bytes=True)},{'file':dict(row,sha256='bad')},{'file':dict(row,extra=True)},{}):
            raw=json.dumps({'schema':'macsad-cas-file-set/1','files':files}).encode()
            sha=self.store.put(raw)
            with self.subTest(files=files),self.assertRaises(ValueError):
                read_file_set(self.store,sha,max_total_bytes=10)
        for raw in (b'{"schema":"macsad-cas-file-set/1","schema":"bad","files":{}}',
                    b'{"schema":"macsad-cas-file-set/2","files":{}}'):
            with self.assertRaises(ValueError):
                read_file_set(self.store,self.store.put(raw),max_total_bytes=10)
        with self.assertRaises(ValueError):
            capture_files(self.bundle,{'file':fact,'file/child':fact},self.store,max_total_bytes=8)


if __name__=='__main__':unittest.main()
