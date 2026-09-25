"""Capture a Lean package's pinned bytes, without interpreting proof claims."""
import hashlib
import os

from host_adapters.lean_result import _load
from host_adapters.local_cas import _digest, _open_root
from host_adapters.worker_artifacts import FileFact, _limits, _read, capture_files


def capture_lean_package(root, expected_manifest_sha256, store, *,
                         max_total_bytes, max_files=64, max_manifest_bytes=1024*1024):
    """Persist exactly the files named by a separately pinned manifest.

    This is a bounded file-inventory decoder, not package verification. Source,
    correspondence, certificate, assumptions and receipts remain opaque bytes.
    A returned CAS index proves byte persistence only. Call the LOGOS replay
    and policy interfaces for their respective semantic decisions.
    """
    _digest(expected_manifest_sha256)
    _limits(max_total_bytes, max_files)
    if type(max_manifest_bytes) is not int or not 1 <= max_manifest_bytes <= 1024*1024:
        raise ValueError('manifest byte limit must be in 1..1048576')
    descriptor = _open_root(root)
    try:
        raw = _read(descriptor, 'manifest.json', min(max_manifest_bytes, store.max_bytes))
    finally:
        os.close(descriptor)
    if hashlib.sha256(raw).hexdigest() != expected_manifest_sha256:
        raise ValueError('Lean manifest does not match the expected byte identity')
    manifest = _load(raw)
    if (type(manifest) is not dict or manifest.get('schema') != 'logos-lean-package/1'
        or type(manifest.get('files')) is not dict or not manifest['files']
        or len(manifest['files']) >= max_files or 'manifest.json' in manifest['files']):
        raise ValueError('invalid or oversized Lean package file inventory')
    facts = {}
    for name, digest in manifest['files'].items():
        _digest(digest)
        facts[name] = FileFact(digest)
    facts['manifest.json'] = FileFact(expected_manifest_sha256, len(raw))
    # capture_files validates the complete namespace before writing, reads all
    # selected files with no-follow descriptors, rechecks each hash, and only
    # then publishes the file-set index. A replaced manifest cannot go unnoticed.
    return capture_files(root, facts, store, max_total_bytes=max_total_bytes, max_files=max_files)
