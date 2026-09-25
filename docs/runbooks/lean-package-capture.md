# Retaining Lean proof-package bytes

`host_adapters.lean_package_capture.capture_lean_package` connects the current
`logos-lean-package/1` file inventory to the immutable local CAS. It uses the
existing bounded file capture and archive adapters. It does not decide proof
validity, statement correspondence, artifact classification or scan results.

```python
from host_adapters.local_cas import LocalCAS
from host_adapters.lean_package_capture import capture_lean_package
from host_adapters.artifact_archive import archive_file_set

# package_directory and private_cas_directory are existing private directories.
# expected_manifest_sha256 is the caller's separately pinned manifest identity.
with LocalCAS(private_cas_directory, max_bytes=8 * 1024 * 1024) as store:
    index = capture_lean_package(
        package_directory, expected_manifest_sha256, store,
        max_total_bytes=64 * 1024 * 1024,
    )
    archive = archive_file_set(
        store, index.sha256, max_total_bytes=64 * 1024 * 1024,
        max_archive_bytes=65 * 1024 * 1024,
    )
```

The manifest is retained byte for byte alongside every explicitly listed file.
Unlisted files are excluded. Duplicate JSON fields, malformed inventories,
self-referential manifests, unsafe paths, symlinks, excess sizes and changed
file digests fail. The file-set index is committed only after all selected bytes
have been persisted. Failure can leave unreferenced blobs; it never returns a
successful index for an incomplete package. Retrying the same pinned bytes is
idempotent.

The manifest limit defaults to 1 MiB and can be reduced. The file count and
aggregate byte limit include the manifest itself. Existing CAS object limits
also apply. Resource limits are application inputs, not proof outcomes.

The semantic fields in the manifest remain opaque. A package whose receipt
says `failed` can be retained for diagnosis. Only the separate LOGOS replay and
policy interfaces establish their respective verification results. A CAS index
is not permission to publish, download or attach artifacts to a database job.

Run the mechanical regression tests from the repository root:

```bash
python3 -m unittest host_adapters.tests.test_lean_package_capture
```

The actual retained six-file transport package was also captured and archived:
its resulting archive matched the prior byte-verified archive exactly. That
storage check did not rerun its proof or broaden its one-target coverage.
