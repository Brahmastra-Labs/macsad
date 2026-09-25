# Immutable artifact download bytes

`host_adapters.artifact_archive.archive_file_set` makes a reproducible ZIP from
an already authorized content-addressed file-set index. It returns bytes only
after every indexed file is retrieved, its SHA256 checked by `LocalCAS`, and its
size checked against the index. Missing, corrupt, ambiguous, or oversized input
raises an error and returns no archive.

The caller must authorize the specific index before invoking this function.
An index digest establishes byte identity; it does not establish permission,
classification, successful scanning, or theorem validity. This adapter does not
enable an HTTP route or make a PostgreSQL artifact record.

```python
from host_adapters.artifact_archive import archive_file_set
from host_adapters.local_cas import LocalCAS

with LocalCAS('/srv/macsad/cas', max_bytes=8 * 1024 * 1024) as store:
    download = archive_file_set(
        store, authorized_index_sha256,
        max_files=64,
        max_total_bytes=32 * 1024 * 1024,
        max_archive_bytes=33 * 1024 * 1024,
    )
```

Files have sorted names, fixed timestamps, read-only regular-file metadata, and
no compression. Nested paths and UTF-8 names are retained. Absolute paths,
dot components, backslashes, NULs, colon drive/stream separators, and a member
used as another member's parent directory are refused. This does not promise
that every valid POSIX filename is supported by every target filesystem.

Set all limits explicitly to fit the caller's request budget. Aggregate file
bytes and archive bytes have separate limits; ZIP headers and names consume
archive space. Memory is proportional to the configured archive limit plus the
largest object limit, and no compressed input is expanded. The complete ZIP is
assembled before returning, so an HTTP handler can avoid returning a successful
download response before integrity checks finish. Larger artifacts need a
separately designed streaming interface.

The existing Foundation test discovery includes
`host_adapters/tests/test_artifact_archive.py`. Tests cover deterministic exact
bytes, Unicode, missing/corrupt objects, wrong sizes, metadata/schema rejection,
duplicate JSON keys, unsafe paths, namespace conflicts, and exact byte limits.
