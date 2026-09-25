# Prepare original Alejandro problems in LOGOS

`logos/corpus` prepares immutable problem revisions from the original 248-case Lean4.14 corpus. Its application logic, strict JSON decoders, provenance checks, canonical identity and existing database-column mapping are LOGOS. It performs no database write and does not grant workspace authority.

The command consumes five arguments after its program name:

```text
CASE_ID MANIFEST SOURCE LEDGER APPROVED_PINS
```

Use the original manifest, the selected original Lean file, its recorded bridge ledger and the approved pin-index supplied with the corpus audit. The pin index is operational input retained outside Git; its exact SHA256 is checked in `decodeAlejandroPins`. The index pins all 248 cases and exact source/ledger byte identities. An arbitrary replacement index is refused. Input byte limits are checked after file reads; the enclosing worker must enforce memory and filesystem limits.

The reusable entry is `prepareAlejandroProblem(manifestRaw, sourceRaw, ledgerRaw, pins)`. The output is an immutable draft for the existing `problem_revision` contract, preserving original source, historical expectations, declarations, recorded observations and provenance. Stable keys are `alejandro/lean414/<case-id>`. A changed approved ledger creates a new content revision under that stable identity.

`prepared` means a source-bound draft was produced. It does not mean the problem was saved, solved, verified or independently replayed. A recorded `bridged` observation remains `recorded_ledger_only` with proof-package verification `not_performed`. Missing evidence and unsupported work retain their distinctions. The authenticated domain transaction must assign workspace/actor/version/idempotency/event identities and commit accepted revisions.

Validation for this checkpoint: full source/module audit passes and the actual pinned LGX compiler returned `logos-check/1` with `ok:true`. Fourteen exact entry compatibility-import warnings are recorded in the additive project registration. Sixteen regression tests across five import-free leaves are present; execution and complete corpus preparation are still pending the serialized test window. No existing test assertion or source-quality rule changed.
