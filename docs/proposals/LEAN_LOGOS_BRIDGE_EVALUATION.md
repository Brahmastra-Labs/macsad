# Lean-to-LOGOS bridge: evaluated prototype handoff

September 8–9, 2026. MaCSad-owned source and evidence; no upstream edits/pushes.

## Outcome

A real Lean4.31 source-to-core export, LOGOS-owned constructor/scope mapping,
portable closed-term certificate, and actual LOGOS kernel recheck passed the
retained integration tests. See the [complete delivery record](../LEAN_LOGOS_BRIDGE.md)
for exact claims and limitations. This is not full Lean/Mathlib compatibility or
a deployed website. Three distinct propositional proofs passed; the longer
530-node example correctly reports the prototype's job quota.

The final evidence is 23 LOGOS tests/six finite properties, eight Lean fixture
regression cases, and 48 Python tests including nine real bridge methods. These
are selected evaluation results, not a complete release gate.

## Archive contents

The sibling `lean-logos-bridge/` directory contains:

- `application.patch`: 26 new MaCSad-owned files, preserving the tested LOGOS
  modules, strict mechanical ports, tests, trusted Lean exporter and fixtures.
- `leaf-inventory.proposal.json`: all ten modules, six test leaves, 23 exact test
  names, six finite properties and source hashes. It is explicitly not an active
  registration file.
- `evaluation-config.example.json`: replacement path placeholders plus the
  exact known fixture/checker identities. It is not ready-to-run deployment
  configuration and has no secrets or private host paths.
- `exports/`: only the corrected `*-04.json` Lean exports. Earlier malformed
  exports are failure evidence, not admissible input.
- `certificates/`: the three positive certificates and a deliberately altered
  target negative control. The negative certificate must not be presented as a
  proved result.
- `evidence/`: selected final/RED reports, manifests and source/evidence notes.
  Full private execution context remains in the owning workspace; its hashes
  are retained without copying developer paths into Git.

Patch SHA256:
`03df0a7060f1a88a82fcbae24095d9c19378fde537b8a40327991b91eea06b3a`.

## Important admission boundary

**Do not apply this archive to the live checkout and call it a release.**
The patch preserves source that was run in an isolated MaCSad84e2 snapshot. It
does not edit `.macsad/toolchains/logos.lock.toml`, register a new active project,
or wire its prerequisites into the production quality runner. If applied alone
to an ordinary checkout, missing graph registration and required test inputs
are expected blockers—not reasons to disable assertions or hide tests.

The application interpreter remains admitted132. The separate mathematical
checker is an explicitly evaluated exact-d9 build, not a promoted replacement
for that interpreter. Lean4.31 is separately identified. All three identities
belong in a future admitted bridge tool/environment contract; version strings
alone are insufficient.

The missing independent control-policy activation mechanism is documented in
[the separate proposal](INDEPENDENT_POLICY_ACTIVATION.md). This archive does not
install that mechanism or satisfy its evidence by reviewing itself. No new
human-independent-review requirement is being invented here.

## How the retained evaluation was run

These describe the bounded evaluation, not authorization to run contestant code.
Use an owned isolated MaCSad snapshot and inspect the archive before applying it.

1. Verify the patch SHA and use `git apply --check` against the chosen unchanged
   MaCSad snapshot. Applying it is an explicit separate evaluation operation.
2. Read `tools/lean-bridge/SCHEMA.md`. It specifies exact Lean4.31 invocation,
   trusted fixture IDs, environment setup and the separate per-case test process
   contract. Retain all output/exit codes; unknown source paths are rejected.
3. Compile the authored exporter using the exact pinned Lean executable; run the
   eight regression cases separately with the same bounds. The generic source
   API is trusted-only. Do not expose it to uploaded files without a sandbox.
4. Export each fixture and compare its compiler/source/target identity and exact
   bytes. Only corrected complete declarations are accepted. `sorry` is an
   explicitly incomplete resource-limited export retaining `sorryAx`.
5. Exercise each import-free LOGOS leaf as an exact hardlink entry in an owned
   temporary harness, using the unchanged MaCSad wrapper with admitted132,
   `test --prove --tiers all`, deterministic seed7 and exact inventory checks.
   This invocation produced CLI/interpreter evidence, not independent AOT parity.
6. Build the existing kernel `recheck` example in the authorized exact-d9 source
   copy with `cargo build --locked --offline --jobs 2 -p logicaffeine-kernel
   --example recheck --features serde`. The retained dependency lock and source
   must remain unchanged; verify the resulting checker identity. Do not fetch
   floating packages or modify upstream source to make the check pass.
7. Fill only the path placeholders in the example configuration for that owned
   evaluation. Keep fixture and checker hashes bound to the actual recorded
   tool job. A different build requires new evidence and deliberate identity
   review, not silently overwriting the expected digest.
8. Set `MACSAD_LEAN_BRIDGE_EVIDENCE` to a new owned directory containing that
   `evaluation-config.json`. Run the Python bridge integration tests through the
   existing bounded mechanical process port. The actual app uses `src/main.lg`
   and the LOGOS driver's versioned wire protocol; the host does not generate
   LOGOS source from user text.
9. Inspect retained `input.lean`, `lean-export.json`, `raw-facts.json`, target
   terms, `correspondence.txt`, `certificate.json`, checker observations and
   `result.json`. Verify that bad targets, bad source identities and quota
   failures do not produce a checked result. Reserve a new evidence directory
   for each run; do not overwrite earlier evidence.

Replaying a positive certificate is the identified `recheck` executable with
the JSON file as its single argument. Preserve its exit, stdout and stderr;
only the LOGOS result policy may classify the complete bound observation.
The emitted `.kernel.lg` presentation is not the input language of `largo prove`.

## Required next work

1. Establish real untrusted-code isolation before generic Lean project intake.
2. Define and admit exact project/library/checker closure and complete source
   artifacts, including the remaining exporter diagnostic/library-manifest
   limitations documented in `SCHEMA.md`.
3. Replace the small prototype wire/job quotas with bounded artifact/queue
   transport and measured large-project behavior. The 256-step case is currently
   a capacity rejection, not a completed translation.
4. Add validated definition/environment import and systematic Lean constructor,
   universe, inductive/recursor, quotient and library compatibility. T01/F14 stay
   open; no fallback axiom or changed statement is acceptable.
5. Integrate module/test inventories and required real-tool test execution
   through the separate control-policy admission process. Do not remove failing
   tests to make applying this preservation patch appear green.
6. Provide declaration/source correspondence, readable naming/explanations and
   authenticated durable website jobs. No database schema change is proposed
   here; use the existing artifact and research-attempt model first.
