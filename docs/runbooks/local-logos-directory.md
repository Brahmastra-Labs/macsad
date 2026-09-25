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
