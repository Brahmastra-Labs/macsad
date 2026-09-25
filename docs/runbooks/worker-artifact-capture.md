# Worker artifact byte capture

`worker_artifacts.capture_files` stores an explicit file inventory in local CAS.
It verifies the caller's SHA256 facts, optional exact sizes, path safety, file
count, per-object and aggregate byte limits. It commits a canonical file-set
index last and returns its `FileFact(sha256, bytes)`. No index is returned on an
error. Failed calls can leave unreferenced immutable blobs; retry the same facts.
CAS publication is not atomic with a database transaction.

## Existing delivered Lean packages

The archived `logos-lean-package/1` manifest uses `files: {relative_path: sha256}`,
not proof_demo's `{relative_path: {sha256, bytes}}`. The generic API accepts both
needs through explicit `FileFact` values; it never interprets proof claims,
schema admission, assumptions, artifact kind, provenance, scan status or rights.
The calling LOGOS flow must decide which already authorized file facts to supply.

```python
from host_adapters.local_cas import LocalCAS
from host_adapters.worker_artifacts import FileFact, capture_files, read_file_set

# pinned_files is the caller-supplied mapping, including manifest.json itself.
# Pin the manifest bytes externally; do not invent a self-referential hash.
facts = {name: FileFact(sha) for name, sha in pinned_files.items()}
with LocalCAS('/srv/macsad/cas', max_bytes=16 * 1024 * 1024) as store:
    captured = capture_files('/private/owned/package', facts, store,
                             max_total_bytes=64 * 1024 * 1024, max_files=64)
    recovered = read_file_set(store, captured.sha256,
                              max_total_bytes=64 * 1024 * 1024, max_files=64)
    for name, fact in recovered.items():
        content = store.get(fact.sha256)
        if len(content) != fact.bytes:
            raise ValueError('file-set byte count mismatch')
```

`read_file_set` checks the index hash/strict JSON/schema/facts/limits. It does not
load every object: callers must use `store.get` and check length as above.
This permits separate-process readback and bounded mechanical archive generation.
The index schema `macsad-cas-file-set/1` maps names to digest/size only; it is not
a package-verification receipt, database artifact row, or permission to download.

## Existing proof-demo integration

The optional `proof_demo --cas-directory PATH` captures the already-published
manifest-listed evidence files plus exact `manifest.json` bytes. Configure
`--cas-max-object-bytes` (default8MiB) and `--cas-max-total-bytes` (default64MiB).
The returned result additionally includes `cas_file_set`; existing LOGOS statuses
and on-disk proof result are unchanged. When optional capture fails, the command
reports the completed local evidence location rather than a vanished pending
directory. The existing proof demo is a source-rerun demonstration, not a Lean
conversion/execution loop. This addition makes no broader verification claim.

## Mechanical contract and limits

- Paths are bounded relative names; absolute/dot/empty components, backslashes,
  NULs, colons, excessive depth/length and file-as-parent collisions are refused.
  Every path component is opened without symlink following under an anchored
  existing root. Storage and source roots must have trusted writers.
- Only explicit file facts are read. Extra directory files are not captured and
  this is not a recursive tree-completeness assertion.
- `max_total_bytes` covers selected files; the generated index separately obeys
  LocalCAS's object-size limit. Inputs are processed one at a time; memory is
  proportional to object limit plus bounded index. Count limit is explicit,
  defaults64 and cannot exceed4096. Do not choose impractical caller budgets.
- Content hash and exact observed size are checked before each CAS put. Original
  expected facts stay authoritative even if a source changes between passes.
  The captured objects remain immutable bytes; storage does not attest to their
  truth, authenticity, secret status, or independent proof verification.
- No automatic garbage collection, domain row insertion, HTTP route, deployment,
  native process launch, or publication permission is introduced.

Foundation discovers the additive `test_worker_artifacts.py` and
`test_proof_demo_cas.py` controls. Their fake worker process port is explicit;
real filesystem capture/readback and failure handling are tested, not proof
execution. Full Foundation and a real delivered-package readback remain separate
integration evidence.
