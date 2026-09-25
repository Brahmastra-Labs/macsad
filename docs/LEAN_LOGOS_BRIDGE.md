# Lean to LOGOS: delivery and compatibility contract

Status: working, isolated proof-transfer prototype; not full Lean compatibility,
an admitted MaCSad feature, or a deployed website. September 8–9, 2026.

Companions: [plain-language readiness](LOGOS_READINESS_PLAIN_LANGUAGE.md) and
[technical LOGOS blockers](LOGOS_BLOCKERS_TECHNICAL.md).

## Request contract

- Requested outcome: accept valid Lean theorems/projects of arbitrary finite
  size within declared version compatibility; check their Lean source in an
  isolated environment; translate definitions, statements and proofs into actual
  LOGOS mathematics; show correspondence; check output and report exact coverage.
- Current engineering increment: checked Lean core export, LOGOS-owned scope and
  constructor mapping, actual target proof serialization and a real kernel
  recheck, with negative cases. First regression examples do not define the
  final product's size or mathematics ceiling.
- Implementation repository: MaCSad only. No edits, commits or pushes to the
  shared LOGOS repository. Existing exact LOGOS source may be inspected and the
  already-authorized isolated candidate may be evaluated.
- No deployment, service restart, production database mutation, new schema, secret
  access, package installation or policy bypass is part of this increment.
- Existing source must be preserved. MaCSad's local checkout remains on main;
  remote-main activation must honor the independent control-policy requirement.
- Test method: observe RED for new behavior; implement the minimum actual
  mapping; rerun unchanged positive and negative tests; retain source/tool/output
  identities. Only one executable test/build runs at a time.

## Do not confuse these two meanings of LOGOS code

The translator implementation is written in MaCSad's imperative LOGOS language.
Its mathematical output uses the actual LOGOS kernel term language: propositions,
dependent function types, lambda proof terms and applications. The human-readable
kernel vernacular is not the same input language as `largo prove`'s English/Tarski
routes. A kernel certificate carries the exact target term representation.

We must not put arbitrary English in a `.lg` file and call it a translated proof,
nor suggest that a command accepts an output format it does not support.

## Target architecture

1. **Intake:** retain source/project bytes and requested theorem identity;
   resolve exact Lean/tool/library versions, not floating dependencies.
2. **Isolated Lean job:** compile/elaborate and check the source; retain diagnostics
   and distinguish admitted assumptions and proof holes from complete proofs.
3. **Core export:** obtain expressions and dependency declarations from Lean's
   actual checked environment. Preserve types, binding, universes and assumptions.
4. **LOGOS translation:** validate structure and supported semantics; translate
   statements and proof terms, retaining source-to-target correspondence.
5. **Target checking:** run an identified checker against the exact translated
   statement/proof, with a separately validated environment. A successful check
   is not a proof that all language features were translated faithfully.
6. **Evidence:** preserve all bytes, versions, mappings, diagnostics and status.
   Unsupported features and exhausted quotas are visible, saved outcomes.
7. **Application integration:** authenticated durable job submission, bounded
   worker ownership, cancellation, progress, artifacts and replay in MaCSad.

No step may silently invent an axiom, erase a hypothesis, replace `sorry`, swap
the target theorem for an easier theorem, or infer proof success from empty output.

## Evidence table

These are observed results, not expected outcomes. Source, logs and artifact
hashes are retained alongside the isolated candidate handoff.

| Layer | Observed outcome | Scope |
|---|---|---|
| Installed Lean runtime | Version query succeeded for Lean 4.31.0, commit `68218e876d2a38b1985b8590fff244a83c321783`. | Windows local trusted fixtures only; no contestant sandbox established. |
| Lean core exporter | Eight regression cases passed in separate bounded processes. Four positive exports repeated deterministically; exact declaration/type/proof roots asserted. | Actual Lean 4.31 source elaboration; invalid proof, missing proof, custom axiom and unknown input remain distinct. |
| LOGOS mapping and result policy | 23 tests and six finite Boolean properties passed; zero failures/skips. Missing-function REDs retained. | Admitted132 CLI/interpreter execution, not a separate AOT/VM/WASM agreement claim. |
| Target kernel checker | Existing exact-d9 example built in 10.03 seconds with unchanged locked dependencies; then accepted transferred proofs. | Fresh standard context, no submitted context; not the unrestricted TheoremCertificate route implicated by T01. |
| First actual combined bridge gate | Seven integration methods passed in 47.663 seconds. | Three different proofs checked; four positive kernel calls including repeated identity and one deliberately wrong-target kernel rejection. |
| Final mechanical/integration regression gate | 48 Python tests passed in 49.431 seconds, zero failures/skips: 31 existing mechanical tests, eight new transport tests, nine real bridge integration methods. | Repeats the bridge cases and adds export-path containment and nonblocking FIFO rejection. Not a complete new MaCSad Node/browser/PG release gate. |
| Website integration | Not implemented by this increment. | No claim that the live preview can translate a user's project. |
| Whole Lean/Mathlib compatibility | Not implemented or demonstrated. | Remains the requested full product target. |

### What really passed through both systems

The positive inputs were authored Lean source files, not hand-written claims
that Lean had accepted an AST:

- Proposition identity: from a proposition and its proof, return that proof.
- Implication composition: given `P → Q`, `Q → R`, and `P`, prove `R`.
- Repeated/shadowed display binders: preserve actual scoped references rather
  than accidentally identifying variables by their printed names.

Lean checked and exported the original type and proof. Native LOGOS application
code (executed by the admitted interpreter) translated raw core constructors
and scoped references. The separately built LOGOS kernel accepted the emitted
certificates. The emitted readable kernel term and serialized kernel term come
from one LOGOS traversal; no AI-generated paraphrase or renewed proof search
substitutes for the transferred proof.

The retained `translated.kernel.lg` is a kernel-vernacular presentation of the
same terms. The artifact actually rechecked is `certificate.json`. We have not
claimed that `largo prove` accepts that vernacular file or that its permissive
term parser independently validated every presentation byte. F14 remains open.

The correspondence artifact records source node IDs/raw tags and target
constructors. Original Lean binder names, de Bruijn indices, declaration identity
and selected type/proof roots remain in the export. This is useful structural
traceability, not a proved universal translation theorem or a completed
source-location/high-level explanation interface. Generated `b0`, `b1`, ...
names favor capture avoidance; human-friendly naming is still product work.

### Negative and capacity evidence

- Lean rejected the invalid original proof; the target checker was not invoked.
- A `sorry` input reached the exporter's 32-declaration closure quota. The result
  explicitly retains `sorryAx`, marks the closure incomplete and reports
  `resource-limit`; no graph is passed off as a complete proof.
- A complete custom-axiom export retains its actual axiom. The current LOGOS
  admission policy returns `unsupported`, not an unconditional checked result.
- A deliberately modified target certificate is rejected by the real kernel
  (exit 1) and by the LOGOS identity/result gate. The same proof's original target
  had passed; a bad identity flag alone is not the negative evidence.
- A mismatched expected export digest fails before output-directory creation.
- Lean successfully checked a 256-step composition proof: 3,465 source bytes,
  530 exported nodes and 32,260 export bytes. The translator reports its present
  128-node job limit explicitly. **This case has not been translated and checked
  in LOGOS.** It demonstrates a remaining limit, not long-proof support.

### Exact identities and replay artifacts

| Item | Identity |
|---|---|
| Lean 4.31 compiler commit | `68218e876d2a38b1985b8590fff244a83c321783` |
| Installed Lean executable SHA256 | `9b216deb50d37c32c829d1efaaa5bafd5560417d382df35a815489e31a31593f` |
| LOGOS application interpreter source | `132dc5346728e2d204df798dd7544e6405306a2c` |
| LOGOS kernel checker source | `d9baaff5b6749c961a13cd2eca427434c5959b17` |
| Kernel executable SHA256 | `56a4bc1fbb6b4a4495c67616c5f66d55929b0e78532145bbfb00ca5421353914` |
| Kernel build log SHA256 | `1a73c73e13018fcd1dbdb3a13669c2160fa2ebc9d389004f234c9c6178d26143` |
| Seven-method integration log SHA256 | `4a8b3bb7f47afaa09a7687c703bc4fd2d98db38cc634209cc59cc71857918963` |
| Final 48-test log SHA256 | `c1c55bef84fbf10671944a37867ec767b46079f5c772effda8fe042af44ee24a` |
| Identity certificate SHA256 | `a285e0e2730012c82bafab70bf9e5ab9c4d40b8731d997b188ce33cc1843e2dc` |
| Composition certificate SHA256 | `b97c187d52546c45e98602b2154c358fea5c00c69e1e470eed3d0149aa78334a` |
| Repeated-binder certificate SHA256 | `0865d2b73e8f767431126c42cf5a817b5d649c902f8be616302f9f3bc9c5b5d2` |

The certificate format is the existing LOGOS `Certificate` with pinned
`logos-coc-1` prelude, not a newly invented proof format. These closed propositional
terms use no imported global constants and Lean reports no axiom dependencies.
The kernel still supplies its standard context; the claim is not that the entire
kernel/prelude was proved sound or that a second independently implemented
checker agreed. A matching checker can replay the JSON without rerunning the
Lean source or proof search. General dependency-bearing portable certificates
remain blocked by validated-environment and compatibility work.

### Bugs found while building the prototype

These are MaCSad prototype issues, not additions to the LOGOS upstream count:

1. An early return in the Lean exporter produced `declarations: [10]` instead
   of the complete theorem object. A new exact-object/root regression failed
   before the fix and passed afterwards. Old `*-01.json` outputs are retained
   as invalid evidence and are never accepted by the bridge.
2. Export failure envelopes initially lost already-discovered axiom facts;
   `sorryAx` and incomplete-closure facts are now retained on resource failure.
3. Recursive shared proof/universe structures could expand disproportionately.
   LOGOS now preflights saturating work/byte costs; Lean universe serialization
   has an aggregate budget. They remain bounded prototypes, not scaling claims.
4. Oversized error details/source and diagnostic limits needed explicit handling.
   Current documented residual diagnostic-classification limitations remain in
   the exporter schema; these have not been silently declared solved.
5. Combined Lean tests accumulated memory. The final eight cases ran separately
   under unchanged per-process 4-GiB/120-second caps. Earlier capped runs remain
   resource-limited attempts, not successful or skipped cases.
6. Source review hardened checker reads against FIFO blocking, confined export
   basenames/roots, and made target/certificate identity facts explicit, including
   the deliberately altered-target control.

No original proof, test expectation or unsupported construct is repaired into
an axiom to obtain a green result.

## Security boundary

Lean source is executable code during elaboration and build. A temporary folder,
a timeout, or a separate process is not a security sandbox. The installed Windows
compiler can check our authored regression inputs; it must not be exposed as a
public arbitrary-source execution endpoint.

Public project intake needs an operator-provisioned isolation boundary with no
host credentials, no production network/database access, no other users' files,
bounded CPU/memory/disk/output/processes, and destruction of the owned job
environment. Dependency acquisition is a separate controlled stage. No such
contestant execution environment is established by this prototype.

## Full compatibility work still required

- Stable versioned Lean project/import and environment interchange.
- Exact universe levels, polymorphic constants, dependent inductives, mutual
  and nested inductives, recursors, projections and reduction behavior.
- Correct treatment of lets, literals, quotients, equality, proof irrelevance
  and Lean's admitted axioms/primitives; no machine-number substitution.
- Validated LOGOS declaration/environment import and target binding, resolving
  the separate certificate trust concern documented as T01.
- Declaration-level correspondence, derivation/rewrite explanations, source
  locations where genuinely supplied by Lean, and transparent generated helpers.
- Real Lean/Mathlib project corpus and differential/adversarial tests, including
  proof holes in dependencies, forged environments and checker disagreements.
- Large-project transport and scheduling. Expand or reuse DAGs deliberately,
  stream artifact data, cache only by complete immutable dependency identity,
  and report declared quotas as resource limits, not mathematical invalidity.
- Durable website/job/artifact integration and deployment/recovery evidence.

## Acceptance language

“Emitted” means target code was produced, not that the original source is valid.
“Kernel-checked” means a specified target proof was accepted by an identified
kernel under its stated environment; it is not unrestricted translation coverage,
an independent correctness theorem for the translator, or an autonomous solution
to a new problem. The final demonstration must retain all of these distinctions.

## Delivery and the next implementation boundary

The source, tests and evidence are retained as a MaCSad candidate proposal. They
are not installed into the admitted application's module graph or public UI.
New module/test inventory and checker/toolchain admission require the outstanding
independent control-policy activation work. The existing proposal explains that
separate dependency; this prototype does not install or bypass it.

The [candidate handoff](proposals/LEAN_LOGOS_BRIDGE_EVALUATION.md) retains the
26-file source patch, exact regression inventory, corrected Lean exports,
selected logs and replayable positive/negative certificates. Patch SHA256:
`03df0a7060f1a88a82fcbae24095d9c19378fde537b8a40327991b91eea06b3a`.
It is source preservation for an isolated evaluation, not an activation-ready
release patch. Module registration, selected test-runner integration, immutable
tool/environment admission and security isolation remain separate work.

The next useful increment is not another hand-picked identity theorem. It is a
versioned project-import and validated dependency-environment interface, larger
artifact/queue transport, a real isolated worker, and systematic construct/library
coverage. The current CLI deliberately accepts only reviewed fixture IDs;
the exporter has a generic trusted-source API, but exposing arbitrary source
before security isolation exists would be unsafe.

An accurate demonstration statement is: “We built and tested a Lean-to-LOGOS
proof-transfer prototype, including actual target certificates and negative
controls. Full Lean compatibility, friendly explanations and website deployment
remain unfinished.”
