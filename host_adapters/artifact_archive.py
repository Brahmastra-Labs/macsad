"""Deterministic ZIP bytes for an already authorized immutable file set.

No route, identity, classification, proof decision or database state lives here.
Callers must authorize the index before calling this mechanical adapter.
"""

import io
import zipfile

from host_adapters.worker_artifacts import read_file_set


class _BoundedBuffer(io.BytesIO):
    def __init__(self, limit):
        super().__init__()
        self.limit = limit

    def write(self, data):
        if self.tell() + len(data) > self.limit:
            raise ValueError('download archive exceeds max_archive_bytes')
        return super().write(data)


def archive_file_set(store, index_sha256, *, max_total_bytes,
                     max_archive_bytes, max_files=64):
    """Verify every referenced object and return one bounded reproducible ZIP.

    The index identifies bytes, not authority or proof success. No output is
    returned on a missing/corrupt object or limit violation. Input memory is
    bounded by LocalCAS.max_bytes; output memory by max_archive_bytes. Use a
    separately authorized streaming path for artifacts larger than these limits.
    ZIP_STORED avoids attacker-controlled compression work and decompression
    expansion. Members are regular, read-only files with fixed metadata.
    """
    if type(max_archive_bytes) is not int or max_archive_bytes < 0:
        raise ValueError('max_archive_bytes must be a nonnegative integer')
    facts = read_file_set(store, index_sha256, max_total_bytes=max_total_bytes,
                          max_files=max_files)
    with _BoundedBuffer(max_archive_bytes) as buffer:
        with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_STORED,
                             allowZip64=True) as archive:
            for name, fact in sorted(facts.items()):
                content = store.get(fact.sha256)
                if len(content) != fact.bytes:
                    raise ValueError('archive object size does not match index')
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100400 << 16
                info.compress_type = zipfile.ZIP_STORED
                archive.writestr(info, content)
        return buffer.getvalue()
