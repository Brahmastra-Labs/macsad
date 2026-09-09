# LOGOS, Lean and the mathematics-production goal

For Alejandro, Tristan and the MaCSad team. Assessment: September 8–9, 2026.

This is a plain-language companion to [the technical register](LOGOS_BLOCKERS_TECHNICAL.md).
It records known findings, not a claim that every possible bug has been discovered.
The implementation and evidence for the translator belong in
[the bridge delivery record](LEAN_LOGOS_BRIDGE.md); this document does not certify
an unfinished translator by describing the desired product.

## The answer in one minute

LOGOS has real mathematical checking machinery, a compiler, web tools and database
tools. It is not merely an English-writing interface. Substantial new work has
landed upstream. MaCSad also has tested database rules and a tested, bounded proof
worker. That is meaningful progress.

But the evidence does **not** yet support either of these claims:

- “LOGOS has no obvious bugs and is already interchangeable with Lean.”
- “Our public website accepts arbitrary mathematics and reliably returns a
  faithfully formalized, independently checked solution.”

We have reproduced two compiler failures in the September 7 LOGOS version. We
also identified a separate concern in how a proof certificate can supply its own
mathematical environment. Neither compiler failure demonstrates a false theorem.
The certificate concern deserves priority precisely because proof trust is a
different question from whether a program crashes.

The Lean-to-LOGOS project is worthwhile. Its full target is **any valid finite
Lean theorem or project within a declared compatible Lean version**, including
long proofs and their libraries. It must preserve the mathematics, not merely
produce convincing English. We are not redefining the product as a translator
for short classroom examples. Small examples are regression tests while the
general machinery is built.

## What each component does

**Lean** is a language, a proof-checking system and an ecosystem of mathematical
libraries. Lean turns a proof script into a detailed proof that its kernel can
check. Much mathematical work relies on imported library definitions and theorems,
not just the text pasted into a box.

**LOGOS** is the language and checking/runtime platform that MaCSad intends to
use. Its readable syntax may make formal work more approachable. Readability,
however, does not establish that all Lean definitions, proofs or libraries have
the same meaning in LOGOS.

**MaCSad** is the application around the mathematics: the website, research
tasks, stored problems, attempts, evidence, budgets and publication decisions.
It must keep these records reliable even when an AI attempt fails or a computer
stops halfway through.

**An AI worker** proposes formalizations and proofs. A proposal is not a proof
merely because an AI sounds certain. Checking a proof also does not establish
that the statement being proved accurately expresses the original problem.

## There are three different achievements

| Achievement | What it establishes | What it does not establish |
|---|---|---|
| A readable explanation | A person can understand a proposed mathematical argument. | That the argument is valid or faithfully translated. |
| A checked translation | Particular source statements/proofs have an explicitly supported translation and the output passes the specified checks. | Full Lean compatibility or the absence of translation mistakes outside the tested contract. |
| Autonomous mathematical research | The service formulates problems, searches, checks, stores and reports results under explicit constraints. | That all mathematical questions are solvable automatically. |

The translator improves **proof readability and traceability**. It does not,
by itself, reveal how a neural network internally arrived at a proof. That latter
research area is usually called mechanistic interpretability.

## Why “any Lean theorem” requires more than a text converter

Lean users can write tactics: instructions telling Lean how to construct a proof.
Many different tactics can construct the same underlying proof. Translating
those instructions word by word would require reproducing an enormous ecosystem
and would still be fragile.

The stronger approach is to let the exact Lean version elaborate the source,
then translate the resulting definitions, types and proof terms together with
their dependencies. Think of transferring the completed mathematical structure,
not guessing its structure from the prose or tactic names.

This requires all of the following:

1. Accept a file or a complete project, with the Lean version and dependency
   versions fixed. Pasting text is a convenience, not the only input method.
2. Check the source in an isolated environment. Lean projects can run code while
   being processed; an uploaded proof must not gain access to our server's files,
   passwords or other contestants' work.
3. Extract the actual theorem, its proof and the full definitions/axioms it uses.
   A theorem containing `sorry`, or depending on a theorem that does, cannot be
   advertised as a completed proof. Legitimate declared assumptions must remain
   visible rather than silently disappear.
4. Translate the mathematical structures without changing their meanings.
   For example, unbounded natural numbers cannot silently become fixed-size
   machine integers. The order and scope of “for every” and “there exists” must
   survive exactly.
5. Produce actual LOGOS mathematical code and a correspondence record. Every
   translated declaration must point back to its Lean origin; invented helper
   declarations must be distinguishable from the user's original declarations.
6. Check the LOGOS proof against the translated statement in a validated
   environment. Preserve the exact checker versions and assumptions.
7. Check fidelity separately: proving two statements does not prove that they
   say the same thing. Translation validation, cross-system tests and eventually
   stronger correctness arguments are part of this work.
8. Return the code, evidence and precise status. “Unsupported,” “resource limit,”
   “source invalid,” “checker disagreement” and “verified under these assumptions”
   must not all become a generic green tick.

Large proofs should use queued jobs, progress reporting, reusable dependency
artifacts and bounded processing. There can be resource quotas and explicit
inconclusive results; there cannot honestly be a promise of infinite RAM or time.
A large input is not inherently mathematically unsupported. Conversely, a tiny
input may use a currently unsupported feature.

## What is actually working, and where

The distinction between **code that exists**, **code that passed a test**, and
**code currently running in the website** is essential.

| Component | Evidence retained | Current limitation |
|---|---|---|
| MaCSad database rules and deterministic seed data | Full admitted-baseline gate includes PostgreSQL 16 tests and coverage of 792 schema fields: 785 fixture-covered and 7 operational/system-managed. | This does not mean the live browser is connected to those records. |
| Prepared LOGOS proof execution | A bounded worker preserves exact input, results and evidence; positive and negative controls were run. | It is not a general natural-language formalizer or an independent portable-proof checker. |
| New LOGOS upstream candidate | Exact September 7 source built; 113 selected upstream tests passed. | These are selected tests, not every test or a proof of mathematical soundness. |
| Native LOGOS database reads | Seven integration methods passed against a fresh real PostgreSQL 16 fixture after two local compiler workarounds. | This is an isolated evaluation, not the running website, and not a production authentication test. |
| Website preview | A preview exists. | Last inspected gateway explicitly said persistence was not connected and mutations were disabled. |
| Durable Git handoff | Earlier completed work is committed and pushed to MaCSad PR #6. | Remote main has not received that PR; an independent policy activation check is missing. |

The exact admitted LOGOS baseline is `132dc534…`; the separately evaluated newer
candidate is `d9baaff5…`. Evidence from one is not silently evidence for the other.
See the technical register for complete identities and retained test references.

## Known LOGOS problems, without jargon

The count is deliberately conservative: **11 retained open LOGOS
core/runtime/interface findings**, plus **2 example-program findings**,
**1 static-file containment limitation**, and **1 separate certificate trust
concern**. These categories are not an exhaustive defect count or a count of
independent ways to prove false mathematics. Within the 11, exactly **2 compiler
failures were reproduced on the current evaluated candidate**; the other 9 are
source-established findings requiring their own executable regression evidence.

### Problems that can break the website or long-running work

- **B02 — Long text can exceed a browser memory allocation.** A large proof is
  exactly the sort of input that makes this important. The implementation needs
  correct allocation or an explicit safe rejection, with large Unicode tests.
- **B03 — Download limits do not consistently count real bytes.** A response can
  be fully buffered before it is rejected, and JavaScript character counts do
  not equal UTF-8 byte counts. Limits must protect memory before it is exhausted.
- **F01 — Reused screen items may not move into the requested order.** A board
  can show the wrong ordering after an update even when its internal data changed.
- **F02 — Browser bookkeeping can accumulate during a long session.** It needs
  cleanup and endurance tests, not just a successful initial page load.
- **F03 — A request can time out while its underlying work continues.** A user
  might retry while the first operation still writes data or consumes a budget.
  Work must have owned lifetimes and safe retry rules.
- **B05 — Failed database startup/authentication paths can retain a connection
  handle.** Repeated failures could eventually exhaust available resources.
- **F10 — One blocked TCP operation can hold a global lock.** Unrelated network
  work can then stall behind it; this matters when many proofs or users run.

### Problems in the proof/tooling path

- **F04 — Different LOGOS interfaces expose different proof capabilities.** An
  automated worker using one interface must not assume it has the same checking
  and certificate behavior as the command-line interface.
- **F12 — The compiler sometimes generates code that reuses a value after
  moving it.** We reproduced this while using real database results and a
  workspace parameter. The generated native program would not compile.
- **F13 — The compiler sometimes generates a reference that lives too long.**
  Another real database read failed to compile for this reason. We found a local
  rearrangement that compiled; that is a workaround, not an upstream repair.
- **F14 — A mathematical term parser does not require all input to be consumed.**
  It can return after parsing a term without insisting that nothing remains.
  A bridge must not treat this alone as proof that an entire submitted output
  was checked. This is a source-established gap; no false proof was demonstrated.

### Separate findings that must not inflate the core bug count

- **F05/F06:** the upstream replacement todo example can report success after
  failed storage and cannot safely frame all user text in its file format.
  These are example-program problems, not evidence that PostgreSQL lost data.
- **L03:** static-file containment needs qualification, particularly around
  symbolic links. A web server must not expose files outside its intended root.
- **T01:** a certificate can supply declarations used to judge its own proof,
  without sufficient validation at the identified boundary. This needs a focused
  adversarial test and repair or a safe route that does not trust that supplied
  environment. No forged certificate or false theorem was executed in this audit.

The technical register also preserves three historical regressions that need
exact-version retesting. They are not three newly reproduced current bugs. The
old typing-focus and idle-client mechanisms have source-level changes addressing
them, but the actual rebuilt MaCSad application still needs the relevant tests.

## Why the certificate concern has a different priority

A proof is checked relative to definitions and assumptions. Suppose a submitted
package is allowed to redefine a name or declare an arbitrary proposition as a
trusted fact. A checker can then accept a derivation relative to that package
without establishing the original intended claim.

This is an illustration of the risk, **not a claim that we demonstrated that
specific attack in LOGOS**. The actual finding is a source-level validation gap.
The repair needs a clear rule for which declarations are trusted, validation of
definitions and dependencies, rejection of conflicting names, explicit axiom
reporting, and independent binding to the expected theorem. Running two checkers
against the same inadequately validated environment is not automatically enough.

Until this is resolved, we must not advertise arbitrary uploaded LOGOS
certificates as independently trustworthy portable proofs.

## Things MaCSad must fix that are not Tristan's compiler bugs

Four separate application findings are retained: budget-retry ordering (F07),
the public preview's directory listing (F08), a browser test that bypasses real
typing (F09), and a title decoder that can trap on malformed UTF-8 (F11).
They belong in MaCSad's work queue, not in a demand that LOGOS upstream fix
everything.

The service also needs authenticated users, durable problem/attempt records,
safe worker queues, artifact storage, budget enforcement, recoverable failure,
backup/restore practice, and tested participant isolation. Some foundations
already exist; their end-to-end integration is not established by isolated tests.

There is a separate delivery-policy issue: changes to test admission controls
require an independent activation check that has not been installed. A proposal
exists. A green ordinary test run does not grant authority to remove that control.
No LOGOS upstream edits or pushes are part of this MaCSad handoff.

## What to ask Tristan for, in priority order

1. **Proof trust:** agree on the intended certificate trust boundary and resolve
   T01 with invalid-environment and tampered-proof tests. State which checker and
   which axiom policy the product is willing to trust.
2. **A supported kernel interchange interface:** expose exact typed proof terms,
   definitions, universes, inductives and validated dependency environments with
   a stable machine-readable success/error contract. The existing English and
   kernel routes must not be confused with Lean compatibility.
3. **Compiler regressions:** turn the retained F12/F13 source fixtures into
   upstream tests and fix them. Keep MaCSad's workarounds until its own exact
   candidate build and tests pass without them.
4. **Long-input and sustained-use safety:** address B02/B03/F02, cancellation,
   connection cleanup and F10; test substantial proofs and repeated jobs, not
   only fast successful examples.
5. **Cross-system coverage:** work through Lean features and real library
   dependencies with declaration-level mappings, negative tests and explicit
   unsupported statuses. Publish compatibility by version and feature rather
   than saying “Lean 2.0” before the evidence exists.
6. **Joint demonstration contract:** choose what the audience will actually see
   and label it accurately: a research prototype, a supported translation, or a
   deployed service. Do not use one label as evidence for another.

## What Alejandro can usefully decide

You do not need to learn SQL or Rust to make the central product decisions.

- Which mathematical families and real Lean projects matter first for the
  hackathon? Provide examples of genuinely useful inputs, including difficult
  and long ones. These guide milestones without changing the full target.
- Which axioms are acceptable, and how should the interface explain them?
- What evidence would convince you that a translation preserved the original
  mathematical question? A readable source/output correspondence is useful for
  that review, but must not hide unsupported definitions.
- What should a contestant see when the system cannot finish? A saved attempt
  with an honest reason is useful; a false success is harmful.
- Which result is worth showing tomorrow even if it is a prototype? The answer
  should be a reproducible mathematical result with its limitations visible,
  not a claim that all mathematics is already automated.

## Honest demonstration and release language

Only after the bridge delivery record lists a successful executable test may
we say: “We translated these specified Lean proofs into LOGOS's supported
mathematical representation and checked the resulting proofs under these exact
versions and assumptions.” That sentence must name the supported coverage.

We may not yet say: “Any Lean theorem works,” “the two languages are equivalent,”
“LOGOS has no bugs,” or “we have a fully autonomous Mathematics Factory.”

For full release, require a real project import, large dependency closure,
faithful statement/proof translation, safe execution, durable website workflow,
negative/tampered-input rejection, and a replayable evidence bundle. The same
test must start from a clean environment so that it does not depend on a
developer's machine accidentally supplying missing files or libraries.

## Source and update discipline

The detailed code locations, exact revisions and acceptance tests are in the
technical register and the existing MaCSad `docs/ELECTRON_READINESS.md` and
`LOGOS_GAPS.md`. Treat a finding as closed only when its original failing case
passes on the exact proposed release, with negative controls still rejecting.

Lean's own documentation distinguishes mathematical validity, faithful intended
meaning, axiom tracking and the danger of executing untrusted source. Those are
useful standards for this bridge too:
[Validating Proofs](https://lean-lang.org/doc/reference/latest/ValidatingProofs/).
Its documented elaboration pipeline is why the bridge should work from checked
structure rather than tactic text:
[Elaboration and Compilation](https://lean-lang.org/doc/reference/latest/Elaboration-and-Compilation/).
The breadth of imported mathematics is visible in the
[Mathlib overview](https://leanprover-community.github.io/mathlib-overview).

These documents should be updated with evidence, not optimistic percentages.
