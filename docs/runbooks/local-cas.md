# Local content-addressed bytes

`host_adapters.local_cas.LocalCAS` is a mechanical POSIX filesystem adapter for
the local byte store described in `domain_model.md` section2.2. It does not
create blob metadata, classify artifacts, authorize access, scan uploads, verify
proofs, or decide publication. LOGOS and PostgreSQL retain those responsibilities.

## Provision and call

An operator provisions a persistent directory, owned by the storage service,
with mode0700. Give only trusted storage writers access. Supply its absolute,
symlink-free path and an explicit per-object limit. The adapter opens every path
component with `O_DIRECTORY|O_NOFOLLOW`; relative paths, dot components, and
symlinks are refused. On systems where `/var` or `/tmp` is an alias, configure
the actual path deliberately. The adapter does not call `resolve()` for callers.

```python
from host_adapters.local_cas import LocalCAS

with LocalCAS('/srv/macsad/cas', max_bytes=8 * 1024 * 1024) as store:
    digest = store.put(b'exact input bytes')
    same_bytes = store.get(digest)
```

The optional `expected_sha256=` parameter on `put` refuses a mismatched claimed
digest before creating anything. Keys must be64 lowercase hex characters.
`get` checks the entire object hash before returning bytes. Reads and puts are
bounded by `max_bytes`; the caller must bound incoming input before allocating
the bytes argument. Chunked I/O uses at most64KiB per operation; byte assembly
and verification use memory proportional to the configured limit. This is not
a total disk quota or a streaming upload API.

## Commit and failure contract

The adapter creates an exclusive randomly named temporary file under the open
root, writes all bytes, makes the file read-only(mode0400), and fsyncs it. A
same-directory hard link publishes the SHA256 name atomically without replacing
an existing name. Both new and duplicate objects receive hash-verified readback
and file sync; temporary cleanup precedes final directory sync. Success is
returned only after the directory sync. Duplicate puts preserve the existing
inode; corruption, oversized files, symlinks and nonregular objects never return
success and are never repaired or overwritten implicitly.

`CommitUncertain` includes `.sha256`: bytes are visible but their durability is
unconfirmed. Any exception or process interruption may leave a visible object;
do not infer absence from a failed call. Retry the identical bytes. A retry
verifies and syncs the existing object and directory again. This filesystem
commit does not make a PostgreSQL transaction atomic with the byte store.
Record provider metadata only through the separately authorized domain flow.

A hard interruption can leave `.pending-*` files. They are never object keys.
There is no automatic garbage collection; an operator can reconcile abandoned
temporaries only while all writers are stopped. Never delete another live
writer's temporary file, and never treat temporary filenames as proof of data
acceptance. Committed objects are never deleted by this adapter.

Use a local POSIX filesystem supporting hard links and directory fsync. No
durability claim extends beyond successful OS fsync semantics or faulty hardware.
The opened directory remains anchored if its pathname is later renamed; this
prevents redirection into a replacement symlink. A malicious process with write
access inside the trusted root is outside this adapter's threat boundary.
Independent handles support concurrent puts/reads. Do not close a handle during
another thread's operation. No deployment or Compose volume change is included.

## Validation

Foundation already discovers this additive test file:

```sh
python3 -m unittest discover --start-directory host_adapters/tests --pattern 'test_local_cas.py' -v
```

The tests use real temporary files, a separate-process reopen after writer close,
eight concurrent independent handles,
corruption, path replacement, nonblocking FIFO rejection, boundary-sized data,
and deterministic write/fsync/interruption faults. Injected faults test the
acknowledgement contract; they do not simulate physical power-loss recovery.
The full protected Foundation/quality gates remain required before integration.
