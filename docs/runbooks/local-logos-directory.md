# Use a private LOGOS development directory

This is an explicit development connection authorized by the workspace owner.
It leaves `.macsad/toolchains/logos.lock.toml` and the default admitted launcher
unchanged. It does not admit a release, start services, or close a framework gap.

From the MaCSad checkout:

```bash
bash scripts/dev.sh connect-logos --workspace /path/to/private-checkout
bash scripts/dev.sh logos-status
bash scripts/dev.sh logos --version
bash scripts/dev.sh logos lean --help
MACSAD_LEAN_WORKER_RUNNER=development-directory bash scripts/dev.sh test-lean-worker
```

`--binary` selects an executable relative to that directory and defaults to
`target/debug/largo`. The connection verifies it is a regular executable within
the directory, independently copies its bytes into ignored `.runtime` state,
and records SHA-256. Each invocation checks both the directory executable and
the copy. Rebuilding the directory executable requires an explicit reconnect.
There is no automatic build, pull, checkout, source modification, or fallback.

The connection records source commit/tree, dirty status and its status digest,
and Cargo.lock digest separately. A Git status digest is not a source-content
digest. Source observations do not prove that the existing executable was built
from those sources: `source_binary_correspondence` remains `unverified`.
`logos-status` and the last-invocation record include the current observations.
No production provenance claim can be based on this development connection.

The existing `make test`, doctor, admitted launcher, and Compose entrypoints
retain their exact release pin. Pointing `LOGOS_WORKSPACE` at a different
directory does not satisfy that pin. Development connection tests and explicit
Lean-worker controls are separate evidence; full release compatibility still
requires a tested toolchain migration. Run one suite at a time on a shared host
and preserve other agents' processes.

`test-lean-worker` exercises mechanical receipt decoding plus the real LOGOS
policy interpreter. Its development selection is explicit and prints the
measured runtime identity. It does not compile Lean projects or count synthetic
receipts as proof-generation evidence. Without the development selection, its
interpreter checks require the admitted release as before.

The connection and binary copy contain machine paths and stay ignored beneath
`.runtime/logos-directory/`; never commit them. The adapter never copies a
credential or mounts the private repository into an application container.

The current Lean import/replay worker integration is separate from the older
`largo prove` demo. Re-running source is not an independent replay receipt.
Authenticated jobs, durable execution, and private downloads need their own
passing integration checks before the website is described as usable.

## Connect an independently built source candidate

For an independent copy with no `.git`, use the separate built-candidate mode.
This requires Python 3.11 or newer for the standard TOML reader. Obtain the
expected binary and inventory SHA-256 values from the owning build handoff;
do not infer release approval from evidence stored beside a binary.

```bash
python3 host_adapters/logos_directory.py connect-built-candidate \
  --candidate /path/to/independent-candidate \
  --expected-binary-sha256 EXPECTED_64_HEX_BINARY_SHA256 \
  --expected-source-inventory-sha256 EXPECTED_64_HEX_INVENTORY_SHA256
bash scripts/dev.sh logos-status
bash scripts/dev.sh logos --version
```

The expected layout is `repo/`, `build/`, and `evidence/`. The evidence must
contain `copy.json`, `source-inputs.json`, `binary.json`, a successful
`largo-build.command.json`, and its frozen `largo-SHA256` executable. The
candidate must remain at its recorded path: the source root may be embedded in
build/test artifacts. The connector never runs `candidate.py`, Cargo, Git, or
an evidence-supplied command. It does not build, download, install, or execute
the candidate while connecting/inspecting.

Connection and every invocation check the supplied binary/inventory pins,
evidence cross-links and build command, all source file byte hashes/sizes/modes,
and the independently reconstructed workspace/path-dependency/literal-include
source selection. Source fixtures have no changed-file exception. Symlinks and
hardlinks in checked inputs are refused. Generated `target*`, `.lake`, and other
copy-driver exclusions are not source inputs. Candidate binary snapshots are
independent files with link count one. Evidence bytes are pinned in the local
connection, so modifying build/copy metadata requires an explicit reconnect,
even when the binary remains unchanged. Verification refuses missing, added,
changed or omitted selected source inputs before execution.

The record uses `macsad-logos-built-candidate/1`, mode
`development-built-candidate`, `release_admitted: false`, and
`source_binary_correspondence: local-build-evidence`. This means the local
copy/build records and current bytes agree with the selected identities. It is
not a signed attestation, a hermetic dependency audit, independent rebuild
reproduction, or release admission. Shared toolchains/caches and generated
exporter artifacts are not certified by these source checks. The older
`development-directory` schema/behavior stays available and continues to label
its binary/source relationship `unverified`.

Bounds are 100,000 source entries, 1 GB of source bytes, 8 MiB inventory JSON,
64 KiB each small evidence record, 16 MiB per parsed source/manifest, and
512 MiB executable. Ordinary local verification does not protect against a
concurrent hostile actor with the same OS account changing files between their
last check and execution. Keep the candidate private and quiescent. No machine
paths, connection records, source copies or binary snapshots belong in Git.

After connection, the separate development test command is:

```bash
node scripts/verify-logos-tests.mjs --development-candidate
```

This explicit option requires `logos-status` to report the strict built-candidate
schema, verified source inventory and local-build provenance. It prints that
identity with `release_admitted: false`, rechecks the same connection before
each compiler/test invocation, and then uses `scripts/dev.sh logos`, which
verifies the source and executable again. A directory-mode connection, changed
identity, failed status, unknown option or unexpected status record is refused.
The no-argument command used by the quality gate continues to use
`scripts/logos.sh` and the admitted release; environment variables cannot select
development mode. Development results do not satisfy production promotion.
