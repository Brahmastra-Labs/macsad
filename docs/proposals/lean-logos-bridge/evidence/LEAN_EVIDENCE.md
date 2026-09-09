# Trusted Lean exporter evidence

Recorded 2026-09-09 01:15 UTC (September 8 local). Local isolated evaluation only;
no upstream source modification, production admission, upload execution, or LOGOS
acceptance is established by this record. All paths below are relative to this
evidence directory or the `work/lean-bridge` draft root; no private host paths or
credentials are needed to interpret the record.

## Exact source and compiler

| Artifact | SHA-256 |
|---|---|
| `../../lean/CoreExport.lean` | `dbef88cfcb9aa957014b1e95543e7bca6e5e912e2bab5fe4759a8c3e3040ef2a` |
| `../../lean/Export.lean` | `fa5083290050d63a267d44a070f8064ea222928ba151fd02c454008e889b3814` |
| `../../lean/Tests.lean` | `2600bd9e3266cf739e0dda91503fac512fe948b157e88e42b61c550ca2bad21f` |
| `CoreExport.olean` | `f5746aa17de74eb1ba029cb1aae11e4b0b1bf49b80f0f96077741beca39112fb` |
| Installed Windows `lean.exe` | `9b216deb50d37c32c829d1efaaa5bafd5560417d382df35a815489e31a31593f` |
| Installed Windows `lake.exe` (not used to build this exporter) | `a5be0113af1c08ba678c1fad07594e1c5de6b871fe0c4144da2998488eba88a1` |

Compiler reports Lean 4.31.0, x86_64-w64-windows-gnu, release,
commit `68218e876d2a38b1985b8590fff244a83c321783`. Exporter checks the version and
commit at runtime. Installed library closure hashes have not been fully captured;
this compiler pin is not production admission or evidence of later security fixes.

## RED history retained, not relabeled

1. Initial compile found source/API errors: reserved binder name, relative
   `include_str` path without a parent, unavailable `Options.setNat`, a missing
   `CoreM` annotation, and an exit-code type annotation. Compile 02 passed after
   correcting those. The first compiler diagnostics remain in the task tool record.
2. `tests-01` exceeded the then-explicit 2 GiB working-set limit. Root authorized
   a 4 GiB ceiling for subsequent owned trusted-source processes. This was not a
   mathematical failure. No global process-group signals were used.
3. `tests-02.stderr` records the initially incorrect test assumption that the
   actual `sorry` closure fits the fixed 32-declaration budget. It does not. Root
   explicitly approved the corrected contract: resource-limit, incomplete closure,
   retained `sorryAx`, no usable partial graph. The closure budget was not raised.
4. `identity-01.json` and `composition-01.json` are INVALID transport artifacts:
   their declaration arrays contain a numeric root, not declaration objects.
   A `return` in a value-producing monadic match returned from the enclosing
   declaration function, bypassing names, kind, roots and associated references.
   Do not feed these files to an acceptance pipeline. Their source/module before
   the earlier error-facts patch is retained as `CoreExport-before-errorfacts.*`.
5. `tests-declaration-red.stdout` records a reserved-name test-source compile
   error. Correcting the test name produced the intended regression RED in
   `tests-declaration-red-02.stderr`: `uncaught exception: object expected`.
   SHA-256 of that stderr is
   `faca21e3f0af425dfad0c343ca53974da16bc42c76000ce787b66ccafa199805`.
6. The early-return branch was changed to a nested `do` and `pure`. Compile 04
   returned 0 with empty stdout/stderr. The monolithic post-fix regression run
   exceeded its unchanged 4 GiB limit. Tests were isolated one fixture per process,
   retaining all assertions and the deterministic second export for positives.

## Corrected actual command outputs

Every `*-04.json` below is the actual compact stdout plus terminal newline from
the trusted fixture CLI. Each corresponding `*-04.stderr` is empty. Export status
is evidence transport, never a LOGOS checked-proof claim.

| File | Process exit | Status | Source bytes | Nodes | Declarations | Complete | Output bytes |
|---|---:|---|---:|---:|---:|---|---:|
| `identity-04.json` | 0 | exported | 89 | 10 | 1 | true | 1822 |
| `composition-04.json` | 0 | exported | 130 | 38 | 1 | true | 4817 |
| `repeated_binders-04.json` | 0 | exported | 130 | 18 | 1 | true | 3302 |
| `long_composition-04.json` | 0 | exported | 3465 | 530 | 1 | true | 32260 |
| `invalid_proof-04.json` | 1 | elaboration-error | 96 | 0 | 0 | false | 853 |
| `sorry-04.json` | 1 | resource-limit | 94 | 0 | 0 | false | 918 |
| `axiom_dependency-04.json` | 0 | exported | 120 | 11 | 2 | true | 2332 |

The four valid targets have `(typeRoot,valueRoot)` respectively `(5,10)`,
`(17,38)`, `(9,18)`, `(9,530)`. Each is a theorem object with its exact structured
name; statement root is `forallE`, actual proof root is `lam`.
`long_composition` elaborates 256 actual `apply step` tactics, not padding or
manually constructed IR. Its 530 nodes exceed the initial downstream 128-node
projection budget; this export alone does not establish long-proof transfer.
The sorry output retains `sorryAx`; the custom-axiom output retains the actual
`MaCSadFixture.unproven` axiom and its separate declaration.

| Fixture | Exact source SHA-256 (decoded retained UTF-8 bytes) | JSON file SHA-256 |
|---|---|---|
| identity | `25c888f2371ce0ca8a2cb9045183d3f65b90559c71ca6e088eaeab733d2e6db8` | `9acb705940bba343e249bcf494920f0a1b4a88299e06dd065fdd17a9637ab4b6` |
| composition | `a813d49e7923e087bd01c6141e0e5525c9cc64c71665ad6aba6dc081342f9f7f` | `b2a55f208502253bc1e26929a356c507d18355a42a2894ed41f2c906753fa44a` |
| repeated_binders | `dc0a991e6681bc42acc0f405892879bfbe421fb73e6a89bc0a41b1094480aa9d` | `629340613661760c0be0a16e0ecad73986a8730193b292a1b0217535fa29d9b5` |
| long_composition | `356ca324639ee707c96261ba365b8d21411a554b00bee0fc38926f5a8a5c5d54` | `4d71baf7305a536b8da3fcf7d640d66dfbbf89bacfc0e2f510a953bb9a8bd9cf` |
| invalid_proof | `f53eb7d67e5d8d3c9da9ebab9daee2b73a86f780876bb39378e90615515d66ae` | `0c276d4b7a34c2a4e6c62f657a3c994a2d1b4aba0a6ef2398db2fd458543c99d` |
| sorry | `840391d551107aefe7bbe37354e9b57c82542dac426a7750b4a127c3c870fcaf` | `635a0acc5d125038d655e546a53cd33e67ee58cd7d494851587e1bced91a7ad6` |
| axiom_dependency | `331be44a2d32a6bf1a4adbc8c37ba727fe9e04166b2a529798e9bf7c1eb6fdab` | `98c71bc9b4400a918bb2b528f9347a971882ebed88fa037a9be116609027fe38` |

## Eight regression process results

All eight `Tests.lean <case>` processes exited 0. This differs intentionally from
the exporter CLI's expected nonzero results for invalid and quota-limited input.
Logs are `test-<case>-04.stdout` and `.stderr`; all eight stderr files are empty.
Each positive case checks exact name/kind/level parameters/root IDs/root tags,
complete single-declaration closure, no axiom, and identical repeat export.

| Case | stdout SHA-256 |
|---|---|
| identity | `3775b871b7642185c9e768583f0829f098d9b7a928400ec7d5ae9a238be7b2c1` |
| composition | `aed8296fec403aa59a1bf2b4735b4d36d78dfe6488d9a5c739c8b5914463a51d` |
| repeated_binders | `826bcb8e52c12c115eadf97970361770ec1ecb18367ba4cadafadec0e6d8df2f` |
| long_composition | `2da82698e7fdbea4933f136a357d3a21288cc7e86d287a330ca0fd91d647b318` |
| invalid_proof | `409e05434c75d44d0d742c9e77287d815933d774fd5e7bf05fe048fe12b73a9b` |
| sorry | `14a495796120e796fc25008fc2b2b3dd78ea0e445116a3074d44ebd9d1e1ee04` |
| axiom_dependency | `1c508b4ee5a5887ec779198c05b41e877394df7e441f1b40160da49b49713ec9` |
| unknown_source | `a4be4aa4917170456b6abf23ea3948a791536fe6980e9c315071b22798432de5` |

## Limits and unclaimed properties

Each process had 120 seconds, 4 GiB sampled working-set and 1 MiB captured-output
limits. Cleanup used only its owned .NET Process object, never a numeric process
group. These sampled controls are not hard OS isolation. No arbitrary Lean input
is safe to run until a real sandbox exists. JSON resource bounds are separately
declared in `SCHEMA.md`. No target acceptance, source/target semantics theorem,
whole-project translation, mathlib coverage, malicious compiler rejection,
contestant concurrency, sandbox escape test, complete imported-library digest
closure, or production gate is claimed here. Elaborator quota errors returned in
Lean's MessageLog may still be classified as elaboration-error; that distinction
requires a dedicated regression and correction before broad input is admitted.
