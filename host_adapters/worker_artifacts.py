"""Bounded immutable file capture; no proof, scan, classification or DB decision."""
from dataclasses import dataclass
import hashlib
import json
import os
import stat

from host_adapters.local_cas import _digest, _open_root


@dataclass(frozen=True)
class FileFact:
    sha256: str
    bytes: int | None = None


def _name(name):
    if (not isinstance(name, str) or not name or len(name.encode('utf-8')) > 1024
        or '\\' in name or ':' in name or '\0' in name or len(name.split('/')) > 64
        or any(part in ('', '.', '..') for part in name.split('/'))):
        raise ValueError('file name must be a bounded relative path without dot components')
    return name


def _namespace(names):
    for name in names:
        _name(name)
        parts = name.split('/')
        if any('/'.join(parts[:end]) in names for end in range(1, len(parts))):
            raise ValueError('file and parent-directory names collide')


def _open_file(root_fd, name):
    # Reuse LocalCAS's no-follow directory anchoring; every descendant is also
    # opened relative to a descriptor, never resolved through an unchecked path.
    directory = os.dup(root_fd)
    try:
        parts = _name(name).split('/')
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            raise ValueError('artifact must be a regular file')
        return fd
    finally:
        os.close(directory)


def _read(root_fd, name, limit):
    fd = _open_file(root_fd, name)
    try:
        before = os.fstat(fd)
        if before.st_size > limit:
            raise ValueError('artifact exceeds byte limit')
        chunks, total = [], 0
        while True:
            block = os.read(fd, min(65536, limit - total + 1))
            if not block:
                break
            total += len(block)
            if total > limit:
                raise ValueError('artifact exceeds byte limit')
            chunks.append(block)
        after = os.fstat(fd)
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise ValueError('artifact changed during read')
        return b''.join(chunks)
    finally:
        os.close(fd)


def _limits(max_total_bytes, max_files):
    if (type(max_total_bytes) is not int or max_total_bytes < 0
        or type(max_files) is not int or not 1 <= max_files <= 4096):
        raise ValueError('invalid capture limits')


def capture_files(root, facts, store, *, max_total_bytes, max_files=64):
    """Capture only explicit pinned files; commit their byte-locator index last.

    `max_total_bytes` bounds the selected file bytes. The index has its own
    store.max_bytes limit. Failures may leave unreferenced blobs, never imply
    domain acceptance, and must be retried with the same expected file facts.
    """
    _limits(max_total_bytes, max_files)
    if not isinstance(facts, dict) or not 1 <= len(facts) <= max_files:
        raise ValueError('invalid capture file count')
    selected = {}
    for name, fact in facts.items():
        _name(name)
        if not isinstance(fact, FileFact):
            raise ValueError('explicit FileFact required')
        _digest(fact.sha256)
        if fact.bytes is not None and (type(fact.bytes) is not int or fact.bytes < 0):
            raise ValueError('invalid expected byte count')
        selected[name] = fact
    _namespace(selected)
    root_fd = _open_root(root)
    try:
        rows, total = {}, 0
        # Admit sizes/index before committing any file. Recheck actual bytes
        # later: paths are trusted writer inputs, not assumed immutable by name.
        for name in sorted(selected):
            fd = _open_file(root_fd, name)
            try:
                size = os.fstat(fd).st_size
            finally:
                os.close(fd)
            fact = selected[name]
            if size > store.max_bytes or (fact.bytes is not None and size != fact.bytes):
                raise ValueError('artifact size does not match capture limits/facts')
            total += size
            if total > max_total_bytes:
                raise ValueError('aggregate artifact bytes exceed limit')
            rows[name] = {'sha256': fact.sha256, 'bytes': size}
        index = json.dumps({'schema': 'macsad-cas-file-set/1', 'files': rows},
                           sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode() + b'\n'
        if len(index) > store.max_bytes:
            raise ValueError('capture index exceeds object limit')
        for name, row in rows.items():
            content = _read(root_fd, name, row['bytes'])
            if len(content) != row['bytes'] or hashlib.sha256(content).hexdigest() != row['sha256']:
                raise ValueError('artifact bytes do not match pinned file facts')
            store.put(content, expected_sha256=row['sha256'])
        return FileFact(store.put(index), len(index))
    finally:
        os.close(root_fd)


def _unique(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError('duplicate evidence manifest key')
        result[name] = value
    return result


def read_file_set(store, index_sha256, *, max_total_bytes, max_files=64):
    """Validate bounded immutable index facts; caller must still get each blob.

    Each blob must be hash-verified by store.get and length-checked against its
    fact. An index confers no authority to download or publish its contents.
    """
    _limits(max_total_bytes, max_files)
    value = json.loads(store.get(index_sha256), object_pairs_hook=_unique)
    if (not isinstance(value, dict) or set(value) != {'schema', 'files'}
        or value['schema'] != 'macsad-cas-file-set/1' or not isinstance(value['files'], dict)
        or not 1 <= len(value['files']) <= max_files):
        raise ValueError('invalid file-set index')
    facts, total = {}, 0
    _namespace(value['files'])
    for name, row in value['files'].items():
        _name(name)
        if (not isinstance(row, dict) or set(row) != {'sha256', 'bytes'}
            or type(row['bytes']) is not int or not 0 <= row['bytes'] <= store.max_bytes):
            raise ValueError('invalid file-set fact')
        _digest(row['sha256'])
        total += row['bytes']
        if total > max_total_bytes:
            raise ValueError('file-set aggregate exceeds limit')
        facts[name] = FileFact(row['sha256'], row['bytes'])
    return facts


def capture_published_evidence(root, store, *, max_total_bytes, max_files=64):
    """Read proof_demo's mechanical manifest; preserve it as opaque bytes too.

    This adapter is specific to proof_demo's size+hash file inventory. Call
    capture_files with explicit FileFacts for other manifest formats (including
    Lean packages); there is no package schema interpretation or verification.
    """
    _limits(max_total_bytes, max_files)
    fd = _open_root(root)
    try:
        raw = _read(fd, 'manifest.json', store.max_bytes)
    finally:
        os.close(fd)
    manifest = json.loads(raw, object_pairs_hook=_unique)
    if not isinstance(manifest, dict) or not isinstance(manifest.get('files'), dict):
        raise ValueError('evidence manifest needs an explicit files mapping')
    if len(manifest['files']) >= max_files or 'manifest.json' in manifest['files']:
        raise ValueError('ambiguous or oversized evidence inventory')
    facts = {}
    for name, row in manifest['files'].items():
        if (not isinstance(row, dict) or set(row) != {'sha256', 'bytes'}
            or type(row['bytes']) is not int or row['bytes'] < 0):
            raise ValueError('evidence file needs exact hash and size')
        facts[name] = FileFact(row['sha256'], row['bytes'])
    facts['manifest.json'] = FileFact(hashlib.sha256(raw).hexdigest(), len(raw))
    return capture_files(root, facts, store, max_total_bytes=max_total_bytes, max_files=max_files)
