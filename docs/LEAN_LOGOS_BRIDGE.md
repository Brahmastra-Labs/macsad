# Lean to LOGOS: delivery and compatibility contract

Status: implementation in progress; this header must be reconciled with the
evidence table before delivery. September 8–9, 2026.

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

This table is deliberately not pre-populated with expected successful outcomes.

| Layer | Observed outcome | Scope |
|---|---|---|
| Installed Lean runtime | Version query succeeded for Lean 4.31.0, commit `68218e876d2a38b1985b8590fff244a83c321783`. | Windows local trusted fixtures only; no contestant sandbox established. |
| Lean core exporter | Pending executable evidence. | No hand-authored node array is claimed as an authentic Lean export. |
| LOGOS mapping | RED fixtures authored; execution/implementation in progress. | Exact binders, operand order, malformed graph, unsupported constructors. |
| Target kernel recheck | Pending isolated executable evidence. | Existing kernel checker route, not generic submitted context admission. |
| Website integration | Not implemented by this increment. | No claim that the live preview can translate a user's project. |
| Whole Lean/Mathlib compatibility | Not implemented or demonstrated. | Remains the requested full product target. |

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
