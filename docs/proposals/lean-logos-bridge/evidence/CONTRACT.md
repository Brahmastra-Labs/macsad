# Lean core translation: first RED contract

Status: local isolated evaluation. All six LOGOS leaves have observed RED and
GREEN under the admitted CLI: 23 tests and six finite properties, zero failures
or skips. The actual CLI entry emitted a certificate from hand-authored identity
nodes; a separate synthetic checker-facts call exercised its native result gate.
Those calls are not actual Lean export or kernel integration evidence. Parent owns
the full real-tool pipeline, canonical integration, admission and test-slot control.

Subsequent parent-run integration passed seven real-tool methods in 47.663 seconds:
identity, composition and repeated binders reached kernel-checked; a changed target
was not kernel-checked; missing proof/custom axiom and invalid original proof did
not reach acceptance; bad source binding failed before effects; a valid 530-node
Lean example returned the current resource limit. This is an evaluated prototype,
not admitted or deployed arbitrary-project translation. The parent retains that
suite's exact inputs, configuration and logs separately from the leaf evidence.

## Outcome and scope

The product goal remains translation of arbitrary valid finite Lean projects,
including their proofs and dependency environments. Identity and implication
are first regressions, not a permanent product restriction. Coverage is expanded
construct by construct; unsupported input remains explicit failure, never a
replacement axiom or a weakened statement. Resource exhaustion is distinct from
unsupported syntax and from mathematical invalidity.

The first end-to-end acceptance is a real Lean-exported closed proof of
`forall P : Prop, P -> P`, translated by native LOGOS into a target kernel term
and its exact claimed type, then accepted by a separately pinned existing LOGOS
kernel checker. A second proof with a changed target must be rejected. A text
snapshot alone does not satisfy this acceptance.

## Interchange and ownership

The future versioned export envelope retains exact Lean version, exporter
identity, project/import artifact identities, declaration identity and kind,
universe parameters, complete referenced declaration closure, claimed type,
proof body, and actual axiom dependencies. These are immutable evidence, not
new domain database columns. Binder display names and binder annotations remain
metadata; binding identity comes from scoped de Bruijn references, not names.
No theorem becomes an axiom, no `sorryAx` is repaired, and no natural number is
converted to a machine integer without a separately proved representation map.

The Lean-side adapter should use the pinned Lean environment's elaborated core
expressions and declaration information, not regexes over source. It exports
structure mechanically, retains rather than erases declaration kinds, and does
not decide that LOGOS supports it. Building user Lean projects requires the
separate bounded worker/isolation contract because elaboration can execute code.
The parent subsequently confirmed an installed Windows Lean 4.31.0 executable
by its version output. The exporter agent owns actual Lean source/export tests;
no hand-authored node fixture here is represented as an authentic export.

LOGOS owns coverage, scope validation, mapping, canonical emission, and acceptance
of exact target/assumption/checker results. A host may strictly decode primitive
wire records, serialize already-selected target constructors mechanically, bound
processes, compute digests, and retain evidence. It must not select mappings,
repair terms, change hypotheses, or interpret a process exit as theorem acceptance.

## Executable leaf signature

`leanCoreText(tags: Seq of Text, left: Seq of Int, right: Seq of Int,
indices: Seq of Text, levels: Seq of Text, root: Int) -> Text`

The five equal-length sequences are a typed in-memory projection of core nodes,
not a claim to parse Lean or arbitrary JSON. Row IDs are one-based LOGOS sequence
positions; Lean bound indices remain zero-based. `root` selects the term. The
initial tags remain raw Lean `sort`, `bvar`, `forallE`, `lam`, and `app`:

- `sort`: references zero, index empty, and `levels` the raw Level constructor
  tag. Only `zero` maps to target `Prop` in this first slice, decided by LOGOS.
- `bvar`: `indices` is the exact nonnegative de Bruijn decimal text, references
  zero and level empty. The mapper compares it to actual scope positions without
  casting arbitrary Lean naturals to machine integers.
- `forallE` / `lam`: `left` is domain and `right` is body; index and level empty.
- `app`: `left` is function and `right` is argument; index and level empty.

Every nonzero child reference must be smaller than the owning row ID. This is a
serialization ordering, not a restriction on the source theorem's proof meaning.
Every row has a known tag and canonical unused slots. During rendering, a binder
enters scope only in its body, never its own domain. An out-of-scope index fails.
Binder names `b0`, `b1`, ... are generated from lexical depth; references use the
matching scope stack, so user Unicode names or repeated names cannot capture.
Domains may contain their own binders. The two sibling scopes can reuse a generated
name without denoting the same binding. Original display labels remain in the
export evidence and are not trusted as target source identifiers.

Success returns fully parenthesized kernel vernacular. Empty text means failure
and can never become an accepted empty theorem. Before production use, the driver
must retain a structured failure category and evidence path; this leaf is only
the initial deterministic rendering seam. It must not enforce an undisclosed
semantic theorem-size limit. Process/node/output budgets belong in the explicit
request and failure contract.

The fixture tests identity type/body, exact target constructor JSON, quantifier
order and distant references, application order, malformed references/open
variables, and refusal of unsupported constructors. It includes one finite Boolean
property. Original RED was five missing-function failures. Text implementation
then passed five tests/one property. Added target-JSON assertions first failed for
the missing JSON function; the final source passed all five tests and one property.
The initial JSON expected-literal syntax was corrected after the actual interpreter
showed it produced only `Pi`/`Lambda`, not the intended JSON; the required serialized
term meaning was unchanged. The current physical source is 120 lines and has SHA256
`d9453d2f696fdad0c6cae9e20479676322dfbd32d144f2b9c6d98247c953cb58`.
The CLI reported no separate AOT/VM agreement fields, so none is claimed.

`leanCoreTermJson` has the same six parameters and uses the exact same recursive
mapping as readable text. `lean_core_certificate.lg` has three passing tests
and one proven finite property for `leanCertificateJson(proof: Text, claim: Text)`, whose
private caller supplies only already mapped JSON terms. This assembler is not an
arbitrary-JSON validator. The selected source roots remain independent: changing
the requested target must change the emitted certificate, not silently substitute
the inferred proof type. A structurally valid wrong-target certificate is emitted
for the checker to reject; emission alone is never a proved status. Serialization
uses the existing kernel serde constructors. No new certificate format is invented.

The first job quota is at most 128 serialized nodes, a requested expansion-work
quota from 1 through 1,000,000, and a conservative combined-term byte bound of
65,408. These are visible evaluation resource limits, not the product's coverage
definition. The budget leaf computes saturating DAG expansion costs before
rendering either root. A tiny DAG can otherwise have exponential expanded output.
Early failed-child short circuit is already present in the mapper; process limits
remain necessary. The CLI driver calls this gate before the mapper, then checks
all scalar fields, exact indices and supported level tags. The 128-node doubling
DAG unit case returns resource-limit in 2,606 reported operations, rather than
materializing its expansion. Complete encoded output is capped at 32,768 bytes.

## Frozen executable wire

The evaluated local entry takes nine data arguments after the program name:
schema `macsad-lean-core-wire/1`; raw tags CSV; left-reference CSV; right-reference
CSV; exact index-text CSV; raw level-constructor-tag CSV; proof root; claim root;
facts CSV. The last argument has eight ordered fields: transport-valid bit,
source-identity-checked bit, closure-complete bit, exporter status, declaration
kind, axiom dependency count, universe parameter count, and work quota. Decimal
scalars are canonical and bounded; index strings are retained without conversion.

The result schema is `macsad-lean-core-result/1` with `status`, `proof_hex`,
`type_hex`, `certificate_hex`, and `mapping_hex`. Successful emission is `emitted`,
not checked. Failure is `invalid`, `unsupported`, or `resource-limit`; artifact
fields are empty. Mapping rows are `source-row|raw-tag|target-constructor` in source
order. This is local constructor correspondence, not a full semantic equivalence
proof; original bindings and declaration identity remain in retained export data.

A separate checker-facts dispatch takes schema `macsad-lean-check-wire/1`, a CSV
of four bits (transport/checker identity/certificate identity/target identity),
exit decimal, stdout text, and stderr text. Its result schema is
`macsad-lean-check-result/1` with native LOGOS `status`. Only exact successful
identity-bound output can become `kernel-checked`. No host interpretation of the
word VERIFIED becomes mathematical acceptance.

## Real target syntax and checker route

Both admitted132 and candidate d9 expose the Rust kernel `Term` model and public
kernel vernacular parser. The documented grammar includes `Prop`,
`forall x : T, body`, `fun x : T => body`, and application. This is distinct from
the imperative LOGOS application compiler and from the English/Tarski `largo prove`
inputs. Do not invoke `largo prove` on emitted vernacular and claim support.

The initial readable type and proof are:

```text
(forall b0 : Prop, (forall b1 : b0, b0))
(fun b0 : Prop => (fun b1 : b0 => b1))
```

For actual rechecking, emit the corresponding exact target `Term` constructor
records and a `Certificate` containing `proof_term`, `claimed_type`, and the pinned
prelude version. The existing kernel `examples/recheck.rs` deserializes this format
and calls `certificate::recheck`, rebuilding its own standard context. No Lean
mapping belongs in that host program. Its binary is not currently an admitted
MaCSad tool; evaluating a bounded isolated build requires separate authorization
and retained identity. No upstream edit is necessary for this first closed-term
case. The example's raw unbounded file/stdin reader requires an outer bounded
mechanical runner. A VERIFIED token alone is not enough: LOGOS must bind the
actual checker identity, exact certificate and exported target before acceptance.

Readable text and constructor output must derive from the same mapped term, with
an explicit structural mapping check. The kernel term parser currently returns
without an EOF assertion; parser success by itself is not evidence that all bytes
were consumed. Do not use it as a permissive source-validation shortcut.

## Completed acceptance stages and remaining coverage

1. Native emitter and policy RED/GREEN: complete, 23 tests and six properties;
   repeated final run also passed, with unchanged source bytes.
2. Actual pinned Lean source exports: the exporter owner produced corrected
   `*-04` artifacts and eight passing fixture regressions. Early `*-01` files had
   invalid numeric declarations and are not admissible evidence.
3. Exact target-constructor/certificate emission: complete for this profile.
   Both renderings share one mapping traversal. Ordered source-row/target-constructor
   correspondence and original de Bruijn references are retained, but are not a
   formal proof of whole-translator semantic preservation.
4. The parent built and evaluated the existing d9 recheck executable without
   upstream edits, then ran the full pipeline noted above. The checker binary SHA256
   is `56a4bc1fbb6b4a4495c67616c5f66d55929b0e78532145bbfb00ca5421353914`.
   That is a separate candidate checker, not a change to MaCSad's admitted132 lock.
5. Original source binding, assumption refusal, exact target selection and native
   checker-result acceptance have unit and real-pipeline negative evidence. A
   checked translated case does not establish every future Lean mapping.

Full coverage still needs complete declaration environments, dependent inductives
and recursors, universe semantics, lets/projections, quotients, primitive/numeric
representations, transparency/reduction behavior, and Lean's trusted primitives.
The simple existing Certificate format cannot transport arbitrary declarations.
The d9 TheoremCertificate context insertion is not a safe generic environment
importer. A validated environment API or a fully checked alternative encoding is
a real framework/trust work item, not something to bypass in a host adapter.
No already-admitted kernel-checker executable, universal mapping proof, or
whole-project translation is claimed by this native-leaf evidence. Corrected real
Lean exports and the separately evaluated d9 kernel checker are owned by the parent
integration task; do not substitute early invalid `*-01` exporter artifacts.

## Source evidence

MaCSad inspected clean main: `84e2afdbcf7ed3df68edb989f312109cc5aeeef6`.
Admitted LOGOS: `132dc5346728e2d204df798dd7544e6405306a2c`.
Candidate only: `d9baaff5b6749c961a13cd2eca427434c5959b17`.

- `crates/logicaffeine_kernel/src/interface/term_parser.rs:5` owns the grammar;
  lines 38-47 return parsed terms without requiring end of input.
- `crates/logicaffeine_kernel/src/interface/mod.rs:25` exposes TermParser/Repl.
- `crates/logicaffeine_kernel/src/term.rs:445` defines target term constructors.
- `crates/logicaffeine_kernel/src/certificate.rs:35` owns the baseline certificate;
  line 64 starts its exact proof-type recheck.
- `crates/logicaffeine_kernel/examples/recheck.rs:20` is the existing executable
  checker entry; its reader at line 53 is not an input resource boundary.
- `apps/logicaffeine_cli/src/repl/mod.rs:1` distinguishes imperative and FOL modes;
  neither is the kernel vernacular Repl.
- d9 `apps/logicaffeine_cli/src/commands/prove.rs:1` identifies actual proof inputs;
  `crates/logicaffeine_kernel/src/certificate.rs:197` rebuilds incoming context.

File references are repository-relative within the identified source revisions;
they are not copied private source or an instruction to execute upstream.
