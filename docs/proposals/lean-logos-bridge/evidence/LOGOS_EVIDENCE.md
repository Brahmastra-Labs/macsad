# Native LOGOS helper and entry evidence

This stage uses the same isolated MaCSad archive and unchanged admitted132 wrapper
as CORE_TERM_RUNS.md. No canonical source, control policy or toolchain lock changed.
All unit inputs were exact hardlinks to the staged MaCSad-owned source. Before
overwriting them, original RED source bytes were retained as `red-source.lg.txt`.

Every leaf used the fixed command:

```text
test --quiet --seed 7 --format json --prove --tiers all --color never
```

| Leaf | Initial RED | Final GREEN |
|---|---|---|
| lean_core_terms | 5 missing mapper failures; later 1 missing JSON function | 5 tests, 1 property |
| lean_core_budget | 4 missing preflight failures; later 2 missing scalar-helper failures | 6 tests, 1 property |
| lean_core_certificate | 3 missing assembler failures | 3 tests, 1 property |
| lean_export_status | 3 missing policy failures | 3 tests, 1 property |
| lean_check_status | 3 missing policy failures | 3 tests, 1 property |
| lean_wire | 3 missing decoder/correspondence failures | 3 tests, 1 property |

Total: 23 passing tests, six proven finite properties, zero failures/skips.
No separate AOT/VM agreement fields were emitted; none is claimed.

The real application project is separate from the leaf harnesses and uses its
actual complete import graph with `entry = "src/main.lg"`. Its RED invocation
failed with `Unknown function: leanBridgeMain`. After implementation:

- Hand-authored identity core nodes emitted the exact proof, claimed type,
  serialized Certificate and ordered local constructor correspondence, exit zero.
- Synthetic exact checker facts produced native `kernel-checked`, exit zero.
  This only tests result classification; an actual kernel was not invoked in
  this call, and the nodes were not represented as real Lean exports.

Both entry invocations used `run --interpret --max-steps 500000 --timeout 10s
--seed 7 --` followed by direct data arguments. The ordinary application path,
not flattened/generated source, was executed. Its stdout, stderr and source
manifest are retained under `evidence/logos/`; per-leaf RED/GREEN logs, tested
source digests and original RED snapshots are in the corresponding subdirectories.

The largest module is 120 physical lines; the largest observed line is 175
characters. No full canonical quality gate or test-inventory admission was run
for this isolated application. The parent subsequently reported seven passing
real Lean/export/checker integration methods in 47.663 seconds, including positive,
wrong-target, source-binding, assumption and resource-limit cases. Its exact suite
log and configuration are retained by that task; the synthetic calls above are
not substituted for those real-tool results.

The inert machine-readable source/test inventory has SHA256
`d7e1e562450f775df7cd4cfdee738c089a922efa33fb88c1ba7f60c3bc50e50e`.
Exact operator paths and data-argument vectors are retained only in a private
run-context record, SHA256
`453167a6dfc36959f2c5ecd138b5dfcdfc792a607c00b56b4245f6e1767820a9`.
Do not publish that private record or replace it with a sanitized command and
claim the sanitized variant was executed. Public records retain identity hashes
and the fixed argument forms above instead.
