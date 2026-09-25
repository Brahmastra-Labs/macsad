"""Bounded local snapshots and process receipts; no Lean acceptance decisions."""
import hashlib
import os
from pathlib import Path

from host_adapters.local_cas import _open_root
from host_adapters.proof_demo import _json_bytes, write_new
from host_adapters.worker_artifacts import _read


def snapshot_tree(root, *, max_files=64, max_bytes=8*1024*1024):
    root = Path(root)
    descriptor = _open_root(root)
    try:
        result, total, entries = {}, 0, 0
        def fail_walk(error):
            raise error
        for directory, dirs, files in os.walk(root, followlinks=False, onerror=fail_walk):
            entries += len(dirs) + len(files)
            if entries > 128:
                raise ValueError('input tree exceeds entry limit')
            for name in dirs:
                if (Path(directory)/name).is_symlink():
                    raise ValueError('input tree contains a directory symlink')
            for name in sorted(files):
                if len(result) >= max_files:
                    raise ValueError('input tree exceeds file limit')
                relative = (Path(directory)/name).relative_to(root).as_posix()
                raw = _read(descriptor, relative, max_bytes-total)
                total += len(raw)
                result[relative] = raw
        if not result:
            raise ValueError('input tree is empty')
        return result
    finally:
        os.close(descriptor)


def save_tree(destination, files):
    destination.mkdir(mode=0o700)
    for name, content in files.items():
        path = destination/name
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        write_new(path, content)


def pins(files):
    return {name: {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)}
            for name, raw in files.items()}


def save_observation(root, label, argv, cwd, observation, seconds, cap):
    # Raw bytes precede any decoding, status or identity assertion.
    write_new(root/(label+'.stdout'), observation.stdout)
    write_new(root/(label+'.stderr'), observation.stderr)
    write_new(root/(label+'.process.json'), _json_bytes({
        'argv': argv, 'cwd': str(cwd), 'exit_code': observation.exit_code,
        'termination': observation.termination, 'timeout_seconds': seconds,
        'output_limit': cap,
    }))


def manifest_facts(package):
    from host_adapters.lean_result import _load
    if not package.exists():
        return None, None
    fd = _open_root(package)
    try:
        raw = _read(fd, 'manifest.json', 1024*1024)
    finally:
        os.close(fd)
    value = _load(raw)
    if type(value) is not dict or type(value.get('schema')) is not str:
        raise ValueError('package manifest is not a typed object')
    return hashlib.sha256(raw).hexdigest(), value['schema']


def exporter_snapshot(root):
    """Snapshot sources and compiled modules used by the pinned Lean export port."""
    root = Path(root)
    fd = _open_root(root)
    try:
        files = {name: _read(fd, name, 1024*1024) for name in ('Main.lean', 'Export.lean')}
    finally:
        os.close(fd)
    library = snapshot_tree(root/'.lake/build/lib', max_files=62,
                            max_bytes=8*1024*1024-sum(map(len, files.values())))
    files.update({'.lake/build/lib/'+name: raw for name, raw in library.items()})
    return files
