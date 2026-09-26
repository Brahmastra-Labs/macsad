# Local Lean submission and independent package replay

The local command connects a Lean project to the existing LOGOS importer,
LOGOS result policy, fresh package replay and immutable artifact storage. It
preserves the generated LOGOS document, certificate, source correspondence,
raw process receipts and a downloadable ZIP.

## Run

Use Python 3.11 or newer on Linux. First configure and inspect an explicit
[local LOGOS development connection](local-logos-directory.md). This command
uses that connection's measured executable; it does not promote a toolchain
or replace the repository's admitted release lock.

Set the variables below to an existing supported Lean project, a built
`lean4export` directory, and existing private output/CAS directories. The
project must include its `lean-toolchain` and the requested declaration's
Lean sources. The exporter must contain `Main.lean`, `Export.lean` and its
built `.lake/build/lib` modules.

```bash
python3 -m host_adapters.lean_submit \
  --runner development-directory \
  --project "$LEAN_PROJECT" \
  --target "$LEAN_TARGET" \
  --exporter "$LEAN_EXPORTER" \
  --output-directory "$LEAN_EVIDENCE" \
  --cas-directory "$LEAN_CAS"
```

The expected LOGOS name defaults to the submitted Lean name. Supply
`--logos-target` when the expected emitted name differs. It is a request input,
never inferred from a result's claim.

This is a trusted local developer command using the selected host's Lean/elan
installation. It is not the isolated, authenticated website submission worker.

## Read the result

Exit zero means evidence capture completed. Read the returned
`import_policy_status` and `replay_policy_status`: successful verification and
fresh replay are reported separately as `verified` and `replayed`. LOGOS owns
both decisions. Refused or unsuccessful inputs keep their actual policy
status; Python does not turn a process exit code into a proof decision.

The returned `evidence_directory` contains:

- The exact copied project, exporter inputs and LOGOS result-policy source.
- The measured development connection and request/file identities.
- Raw import, policy and replay stdout/stderr plus process observations.
- The package and `package.zip` when a package was produced and captured.
- `result.json` and the complete evidence file manifest.

`package_file_set` and `evidence_file_set` identify separately persisted CAS
inventories. The archive can be reconstructed through the existing
[artifact download adapter](artifact-downloads.md). These locators grant no
publication, download or database authorization.

Package replay runs in a fresh process and checks the preserved certificate
and statement correspondence. It does not rerun Lean acceptance. The package
records its trusted base, assumptions and translation losses; retain those
disclosures with the code and certificate.

## Bounds and failures

The command keeps the existing process limits: 60 seconds for import/replay,
15 seconds for each policy process, and 32 KiB combined stdout/stderr for
import/replay. The policy interpreter also has its existing one-million-step
and five-second limits. The selected source project is bounded to 64 files,
128 entries and 8 MiB. Exporter inputs have their own 8 MiB snapshot bound.
The CAS has an 8 MiB object bound and a 64 MiB aggregate evidence bound,
including copied inputs, generated package and archive.

A changed input, compiler, policy or package fails capture. An abnormal process
or malformed receipt is retained as incomplete evidence. The error names the
retained directory; it does not synthesize a successful proof result. A failure
after local publication names the published directory, even when final CAS
capture did not finish. Retry creates a new run and preserves earlier evidence.

## Regression and real execution tiers

The ordinary unit suite covers mechanical invocation, byte identity and failure
handling with controlled process observations. It does not prove a real Lean
conversion passed.

The explicit real tier runs the command, extracts its own package archive into
a fresh directory, and requires another actual LOGOS replay and policy result:

```bash
python3 -m host_adapters.tests.lean_submission_contract \
  --project "$LEAN_PROJECT" --target "$LEAN_TARGET" \
  --logos-target "$LOGOS_TARGET" --exporter "$LEAN_EXPORTER" \
  --evidence "$FRESH_CONTRACT_EVIDENCE"
```

The contract evidence directory must not already exist. On a shared validation
host, invoke this tier through the established serialized test harness. No
result from the local CLI establishes authenticated HTTP intake, database job
completion, source scanning, whole-corpus coverage or production deployment.
