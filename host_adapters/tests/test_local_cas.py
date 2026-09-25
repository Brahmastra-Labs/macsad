"""Real filesystem checks of mechanical byte storage, never domain acceptance."""

import hashlib
import os
from pathlib import Path
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import unittest
from unittest.mock import patch

from host_adapters.local_cas import LocalCAS, CorruptObject, CommitUncertain


class LocalCASTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        # macOS /var is a symlink. Select the real fixture root explicitly;
        # the adapter itself must never resolve an untrusted symlink.
        self.root = Path(self.temp.name).resolve() / 'cas'
        self.root.mkdir(mode=0o700)
        self.cas = LocalCAS(self.root, max_bytes=131072)
        self.addCleanup(self.cas.close)

    def digest(self, content):
        return hashlib.sha256(content).hexdigest()

    def test_exact_roundtrip_binary_unicode_empty_and_chunk_boundary(self):
        for content in (b'', bytes(range(256)), 'λ café\r\n'.encode(), b'x' * 131072):
            with self.subTest(size=len(content)):
                digest = self.cas.put(content)
                self.assertEqual(digest, self.digest(content))
                self.assertEqual(self.cas.get(digest), content)
                self.assertEqual((self.root / digest).read_bytes(), content)
                self.assertEqual(stat.S_IMODE((self.root / digest).stat().st_mode), 0o400)

    def test_duplicate_checks_bytes_and_preserves_inode(self):
        digest = self.cas.put(b'original')
        inode = (self.root / digest).stat().st_ino
        self.assertEqual(self.cas.put(b'original'), digest)
        self.assertEqual((self.root / digest).stat().st_ino, inode)
        self.assertEqual(len(list(self.root.iterdir())), 1)

    def test_corrupt_existing_object_never_overwritten_or_accepted(self):
        digest = self.digest(b'original')
        (self.root / digest).write_bytes(b'corrupt!')
        inode = (self.root / digest).stat().st_ino
        for operation in (lambda: self.cas.get(digest), lambda: self.cas.put(b'original')):
            with self.assertRaises(CorruptObject):
                operation()
        self.assertEqual((self.root / digest).read_bytes(), b'corrupt!')
        self.assertEqual((self.root / digest).stat().st_ino, inode)
        self.assertEqual(len(list(self.root.iterdir())), 1)

    def test_expected_digest_mismatch_and_size_refuse_before_creation(self):
        with self.assertRaises(ValueError):
            self.cas.put(b'x', expected_sha256=self.digest(b'y'))
        with self.assertRaises(ValueError):
            self.cas.put(b'x' * 131073)
        with self.assertRaises(TypeError):
            self.cas.put(bytearray(b'x'))
        self.assertEqual(list(self.root.iterdir()), [])

    def test_read_size_limit_and_nonregular_object(self):
        content = b'x' * 131073
        digest = self.digest(content)
        (self.root / digest).write_bytes(content)
        with self.assertRaises(ValueError):
            self.cas.get(digest)
        (self.root / digest).unlink()
        os.mkfifo(self.root / digest)
        with self.assertRaises(CorruptObject):
            self.cas.get(digest)

    def test_digest_path_escape_and_noncanonical_names(self):
        for name in ('../escape', '/tmp/escape', 'a' * 63, 'A' * 64, 'g' * 64, 'a' * 64 + '\n', '', None):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.cas.get(name)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_object_symlink_never_followed_by_read_or_duplicate(self):
        outside = self.root.parent / 'outside'
        outside.write_bytes(b'original')
        digest = self.digest(b'original')
        (self.root / digest).symlink_to(outside)
        for operation in (lambda: self.cas.get(digest), lambda: self.cas.put(b'original')):
            with self.assertRaises(OSError):
                operation()
        self.assertTrue((self.root / digest).is_symlink())
        self.assertEqual(outside.read_bytes(), b'original')

    def test_symlink_in_any_root_component_and_parent_escape_refused(self):
        alias = self.root.parent / 'alias'
        alias.symlink_to(self.root.parent, target_is_directory=True)
        for root in (alias / 'cas', self.root / '..' / 'cas'):
            with self.subTest(root=root), self.assertRaises((OSError, ValueError)):
                LocalCAS(root, max_bytes=1)
        leaf = self.root.parent / 'leaf'
        leaf.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError):
            LocalCAS(leaf, max_bytes=1)

    def test_open_directory_anchor_does_not_follow_later_path_swap(self):
        moved = self.root.parent / 'original-root'
        self.root.rename(moved)
        other = self.root.parent / 'other'
        other.mkdir()
        self.root.symlink_to(other, target_is_directory=True)
        digest = self.cas.put(b'anchored')
        self.assertEqual((moved / digest).read_bytes(), b'anchored')
        self.assertEqual(list(other.iterdir()), [])

    def test_concurrent_duplicate_commits_have_one_exact_object(self):
        barrier = Barrier(8)
        def write(_):
            with LocalCAS(self.root, max_bytes=131072) as store:
                barrier.wait(timeout=5)
                return store.put(b'same bytes' * 5000)
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(write, range(8)))
        self.assertEqual(set(results), {self.digest(b'same bytes' * 5000)})
        self.assertEqual([p.name for p in self.root.iterdir()], [results[0]])
        self.assertEqual(self.cas.get(results[0]), b'same bytes' * 5000)

    def test_file_sync_failure_never_publishes_digest(self):
        with patch('host_adapters.local_cas.os.fsync', side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):
                self.cas.put(b'new')
        self.assertEqual(list(self.root.iterdir()), [])

    def test_directory_sync_failure_reports_uncertainty_and_retry_verifies(self):
        real_sync = os.fsync
        def fail_directory(fd):
            if stat.S_ISDIR(os.fstat(fd).st_mode):
                raise OSError('directory sync failure')
            real_sync(fd)
        digest = self.digest(b'new')
        with patch('host_adapters.local_cas.os.fsync', side_effect=fail_directory):
            with self.assertRaises(CommitUncertain) as caught:
                self.cas.put(b'new')
        self.assertEqual(caught.exception.sha256, digest)
        self.assertEqual((self.root / digest).read_bytes(), b'new')
        self.assertEqual(self.cas.put(b'new'), digest)
        self.assertEqual([p.name for p in self.root.iterdir()], [digest])

    def test_duplicate_durability_failure_is_not_success(self):
        digest = self.cas.put(b'existing')
        with patch('host_adapters.local_cas.os.fsync', side_effect=OSError('sync failed')):
            with self.assertRaises(CommitUncertain):
                self.cas.put(b'existing')
        self.assertEqual(self.cas.get(digest), b'existing')

    def test_interruption_before_link_removes_only_owned_temporary(self):
        unrelated = self.root / '.pending-other'
        unrelated.write_bytes(b'not ours')
        with patch('host_adapters.local_cas.os.link', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.cas.put(b'interrupted')
        self.assertEqual(list(self.root.iterdir()), [unrelated])
        self.assertEqual(unrelated.read_bytes(), b'not ours')

    def test_interruption_after_link_returns_no_ack_and_retry_recovers(self):
        real_read = self.cas._read
        calls = 0
        def interrupt_readback(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise KeyboardInterrupt
            return real_read(*args, **kwargs)
        digest = self.digest(b'visible but interrupted')
        with patch.object(self.cas, '_read', side_effect=interrupt_readback):
            with self.assertRaises(KeyboardInterrupt):
                self.cas.put(b'visible but interrupted')
        self.assertEqual([p.name for p in self.root.iterdir()], [digest])
        self.assertEqual(self.cas.put(b'visible but interrupted'), digest)

    def test_partial_writes_and_no_progress_cannot_commit_truncated_bytes(self):
        real_write = os.write
        def short_write(fd, data):
            return real_write(fd, data[:3])
        with patch('host_adapters.local_cas.os.write', side_effect=short_write):
            digest = self.cas.put(b'longer than one write')
        self.assertEqual(self.cas.get(digest), b'longer than one write')
        with patch('host_adapters.local_cas.os.write', return_value=0):
            with self.assertRaises(OSError):
                self.cas.put(b'cannot complete')
        self.assertEqual([p.name for p in self.root.iterdir()], [digest])

    def test_zero_limit_accepts_only_empty_bytes(self):
        with LocalCAS(self.root, max_bytes=0) as store:
            digest = store.put(b'')
            self.assertEqual(store.get(digest), b'')
            with self.assertRaises(ValueError):
                store.put(b'x')

    def test_closed_writer_reopens_exact_bytes_in_separate_process(self):
        content = b'restart\x00\xff\r\n'
        digest = self.cas.put(content)
        self.cas.close()
        program = (
            'import sys; from host_adapters.local_cas import LocalCAS\n'
            'with LocalCAS(sys.argv[1], max_bytes=128) as store:\n'
            ' print(store.get(sys.argv[2]).hex())\n'
        )
        result = subprocess.run([sys.executable, '-c', program, str(self.root), digest],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, content.hex() + '\n')
        self.assertEqual(result.stderr, '')

    def test_missing_closed_and_invalid_limits(self):
        with self.assertRaises(FileNotFoundError):
            self.cas.get('0' * 64)
        for limit in (-1, True, 1.5):
            with self.assertRaises(ValueError):
                LocalCAS(self.root, max_bytes=limit)
        self.cas.close()
        self.cas.close()
        with self.assertRaises(ValueError):
            self.cas.get('0' * 64)
        with self.assertRaises(ValueError):
            self.cas.put(b'x')


if __name__ == '__main__':
    unittest.main()
