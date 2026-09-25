"""Bounded immutable bytes on an operator-owned POSIX filesystem.

No authentication, classification, database mutation or proof acceptance lives
here. The existing root must be private to trusted storage writers. Directory
descriptors prevent symlink traversal; they do not defend against a malicious
writer already authorized to replace files inside that directory.
"""

import hashlib
import os
import re
import stat
import uuid


class CorruptObject(ValueError):
    """The addressed object is not regular, or its bytes do not match its key."""


class CommitUncertain(OSError):
    """Object is visible, but durability is unconfirmed; retry the same bytes."""

    def __init__(self, sha256):
        self.sha256 = sha256
        super().__init__('object ' + sha256 + ' visible; durability unconfirmed')


def _digest(value):
    if not isinstance(value, str) or re.fullmatch(r'[0-9a-f]{64}', value) is None:
        raise ValueError('SHA256 must be exactly 64 lowercase hexadecimal characters')
    return value


def _open_root(root):
    path = os.fspath(root)
    if not isinstance(path, str) or not path.startswith('/'):
        raise ValueError('storage root must be an existing absolute directory')
    parts = path.split('/')
    if any(part in ('.', '..') for part in parts):
        raise ValueError('storage root must not contain dot components')
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open('/', flags)
    try:
        for part in filter(None, parts):
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


class LocalCAS:
    """Flat SHA256 keys; context-managed handle, explicit per-object byte limit.

    Independent handles may put/read concurrently. Do not close a handle while
    another thread uses it. Root creation, quota, backup and garbage collection
    are operator responsibilities; this API never deletes committed objects.
    """

    def __init__(self, root, *, max_bytes):
        if type(max_bytes) is not int or max_bytes < 0:
            raise ValueError('max_bytes must be a nonnegative integer')
        self.max_bytes = max_bytes
        self._fd = _open_root(root)

    def close(self):
        if self._fd is not None:
            os.close(self._fd)
            self._fd = None

    def __enter__(self):
        self._directory()
        return self

    def __exit__(self, *exc):
        self.close()

    def _directory(self):
        if self._fd is None:
            raise ValueError('storage handle is closed')
        return self._fd

    def _read(self, digest, *, sync=False):
        fd = os.open(digest, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                     dir_fd=self._directory())
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode):
                raise CorruptObject('object is not a regular file')
            if info.st_size > self.max_bytes:
                raise ValueError('object exceeds max_bytes')
            chunks, total, hasher = [], 0, hashlib.sha256()
            while True:
                chunk = os.read(fd, min(65536, self.max_bytes - total + 1))
                if not chunk:
                    break
                total += len(chunk)
                if total > self.max_bytes:
                    raise ValueError('object exceeds max_bytes')
                hasher.update(chunk)
                chunks.append(chunk)
            if hasher.hexdigest() != digest:
                raise CorruptObject('object bytes do not match SHA256')
            if sync:
                try:
                    os.fsync(fd)
                except OSError as error:
                    raise CommitUncertain(digest) from error
            return b''.join(chunks)
        finally:
            os.close(fd)

    def get(self, sha256):
        """Return exact verified bytes or fail; never return an unchecked prefix."""
        return self._read(_digest(sha256))

    def put(self, content, *, expected_sha256=None):
        """Commit bytes without replacement; acknowledge only after file+dir sync.

        A failed/interrupted call may have published the object. Retry identical
        bytes: duplicates are read, hashed and synced again before success.
        """
        directory = self._directory()
        if type(content) is not bytes:
            raise TypeError('content must be immutable bytes')
        if len(content) > self.max_bytes:
            raise ValueError('content exceeds max_bytes')
        digest = hashlib.sha256(content).hexdigest()
        if expected_sha256 is not None and _digest(expected_sha256) != digest:
            raise ValueError('content does not match expected SHA256')
        try:
            self._read(digest, sync=True)
        except FileNotFoundError:
            pass
        else:
            self._sync_commit(digest)
            return digest
        pending = '.pending-' + uuid.uuid4().hex
        fd = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=directory)
        try:
            try:
                view = memoryview(content)
                offset = 0
                while offset < len(view):
                    count = os.write(fd, view[offset:offset + 65536])
                    if count <= 0:
                        raise OSError('object write made no progress')
                    offset += count
                os.fchmod(fd, 0o400)
                os.fsync(fd)
            finally:
                os.close(fd)
            try:
                # Same-directory hard link is atomic and refuses an existing
                # destination. It never replaces a committed object or symlink.
                os.link(pending, digest, src_dir_fd=directory,
                        dst_dir_fd=directory, follow_symlinks=False)
            except FileExistsError:
                pass
            # Both new objects and duplicates get exact readback. A previous
            # interrupted caller may have linked bytes without syncing the root.
            self._read(digest, sync=True)
        finally:
            os.unlink(pending, dir_fd=directory)
        self._sync_commit(digest)
        return digest

    def _sync_commit(self, digest):
        try:
            os.fsync(self._directory())
        except OSError as error:
            raise CommitUncertain(digest) from error
