# LOGOS: known defects and acceptance blockers for Lean-level mathematics

Technical problem statement and acceptance handoff — 8 September 2026 Pacific / 9 September UTC.

Audience: LOGOS maintainers, Lean-bridge implementers, MaCSad mathematical-verification and infrastructure owners.

Status: documentation only. This document neither changes upstream LOGOS nor admits a toolchain, deploys a service, approves a proof, or activates policy. Proposed tests below are requirements, not tests claimed to have run.

## 1. Conclusion and scope

LOGOS has real theorem evaluation, proof terms, kernel checking and, in the evaluated newer source, theorem certificates and a second checking implementation. It must not be described as merely an LLM printing a verdict. Conversely, the tested compiler is not bug-free, and the available evidence does not establish parity with Lean in mathematical expressiveness, library coverage, autoformalization accuracy, proof-search success, trust hardening, or industrial throughput.

The product target is **any valid finite Lean theorem or project under an explicitly supported, pinned Lean environment**, including large projects, long proofs, substantial imports, custom definitions and mathematically infinite domains. Small examples are initial regression fixtures, not a permanent small-theorem product boundary. Finite input does not mean finite-domain mathematics. It also does not mean unlimited memory, time, storage, workers or money: a particular execution may exhaust its declared resources and must report that honestly.

Three objectives must remain distinct:

1. Ingest, preserve, elaborate and check an existing Lean project through its actual compatible toolchain.
2. Translate between LOGOS and Lean while preserving the meaning, assumptions, definitions and proof obligations of the intended theorem.
3. Discover or generate proofs automatically for new problems.

Success at one does not establish the others. A complete project bridge is not automatically a semantics-preserving translator; a checked proof is not evidence that the original informal question was formalized correctly. No promise to find every proof automatically is made.

“Known” here means the findings and unresolved contracts retained by the MaCSad audit and subsequent isolated evaluation. This is not an exhaustive audit of all LOGOS source, branches, platforms, tactics or mathematical theories. No total count of all bugs in LOGOS is supportable.

### Version identities

| Role | Exact identity | Meaning |
|---|---|---|
| Admitted MaCSad LOGOS baseline | `132dc5346728e2d204df798dd7544e6405306a2c`; tree `9f251ad38ed49834d8224bbf6b928cb5ba1aa1c5` | Existing admitted application toolchain; not replaced by this report. |
| Evaluated LOGOS candidate | `d9baaff5b6749c961a13cd2eca427434c5959b17`; tree `34f712714619bc9049a4dc9c1d22962dd67d63c4` | Also the upstream `main` observed in the last authenticated read. Every “d9” source claim below means this immutable revision, not a floating latest. |
| Candidate Cargo.lock | SHA256 `341398289909e4b5c85520e1554308bb285f081cae3935147efb282ab4bf23c2` | Root compiler dependency lock. |
| Candidate CLI | `largo 0.10.1`; SHA256 `b937f4ea8e8d3f6067bf119add89c3476066924422794da61440cc83d246ad5b` | Measured isolated debug build; the version string alone is not identity. |
| MaCSad read-evaluation base | `13f503a6b70708c1d0b5026aa76b5b98628d6025` | Separate candidate application snapshot, not a production integration. |
| Lean compatibility environment | Must be selected and pinned per supported version/project | The official documentation consulted identifies `4.34.0-rc2`; consulting it does not admit or install that release candidate. |

A later fix is neither ruled out nor assumed. Re-run the original fixture against its exact proposed fixing revision before changing status. Older `92c31ecf…` evaluation notes in `LOGOS_GAPS.md` are historical, not the newest-source assessment.

### Positive evidence that must not be lost

- The exact d9 CLI built successfully offline with its root lock unchanged, two build jobs and an outer time bound.
- Four selected framework targets passed **113 tests, zero failed, ignored or filtered**: strict typed JSON 17; native PostgreSQL frame/parser locks 2; PostgreSQL protocol 27; PostgreSQL wire 67. Protocol exchanges exercised interpreter/VM paths with owned loopback peers. The two AOT tests were not native concurrent database tests.
- A subsequent candidate-only native MaCSad read, after the application workarounds for F12/F13, passed seven methods against an owned PostgreSQL 16.15 fixture. It returned the three synthetic closed cases deterministically and preserved all 47 table fingerprints. Its generated closure passed a retained locked-offline rebuild. This is not authenticated website, SCRAM/TLS, mutation, multi-user or production acceptance.
- The admitted baseline supports a real `largo prove --json` demonstration and a LOGOS-authored report policy. Its repeated source run is source replay, not portable proof-certificate replay or independent-kernel agreement.

Evidence records: MaCSad `LOGOS_GAPS.md`, `docs/ELECTRON_READINESS.md` sections 5, 7 and 19, and `docs/proposals/logos-d9-website-evaluation/evidence.json`. Historical statements in those documents must be read with their later amendments.

## 2. Evidence classes, priorities and counting

Subsequent MaCSad-only bridge increment: a real Lean4.31 exporter, LOGOS-owned
closed-core mapping and an isolated exact-d9 `Certificate` rechecker passed the
first seven-method end-to-end gate. Three distinct closed propositional proofs
were transferred; a changed target was rejected by the real kernel. This does
not use the submitted-context `TheoremCertificate` route, close T01/F14, admit
the checker, or establish whole-Lean compatibility. The separately documented
[bridge delivery record](LEAN_LOGOS_BRIDGE.md) owns its exact evidence, quotas,
new-work bugs and residual coverage. The upstream finding counts below do not
increase because of bugs in that MaCSad prototype.

Use these labels in issue trackers and release decisions:

- **D9 reproduced:** the exact candidate executed or compiled the original failing case and failed observably.
- **Source-established:** inspected control/data flow establishes the described implementation behavior; no claim about measured frequency, heap growth or an unexecuted end-to-end exploit.
- **Older reproduction + d9 source:** the earlier implementation failed in a harness or browser, and the same relevant mechanism remains in d9; not a new d9 runtime reproduction.
- **Source-addressed / historical pending:** newer code addresses the earlier mechanism, or the affected example disappeared; exact application regression/admission may remain open.
- **Capability/acceptance gap:** a required interface, trust contract or operational result is missing or unestablished; not automatically a code bug.

P0 blocks the affected proof/authority claim. P1 blocks reliable use of the affected integration or sustained service. P2 denotes an example-only or narrower defect. Severity does not upgrade evidence confidence.

The following counts are deliberately scoped to the named registers, not to every requirement in this document:

| Register slice | Count | Included IDs |
|---|---:|---|
| Retained open LOGOS core/runtime/interface findings | 11 | B02, B03, B05, F01, F02, F03, F04, F10, F12, F13, F14 |
| Of those, exact-d9 reproduced native compiler findings | 2 | F12 and F13; F12 contains two failing constructs, not two additional IDs |
| Of those, other source-established mechanisms/interface gaps | 9 | Remaining IDs above; B02 also has an older exact-implementation reproduction |
| Upstream example-only findings | 2 | F05, F06; not defects in an adopted MaCSad database backend |
| Other earlier B IDs retained for continuity | 3 | B01, B04, B06: source-addressed or replaced, not added to the open-d9 count |
| Separate trust concern | 1 | T01: missing validation boundary established by source; forgery hypothesis unexecuted |
| Historical failures awaiting exact closure | 3 | H01–H03; newer relevant tests exist, so do not call these three current reproduced failures |
| Separately retained static-serving limitation | 1 | L03 |
| MaCSad/application/preview/test findings within F register | 4 | F07, F08, F09, F11; not LOGOS bugs |
| MaCSad schema/policy questions | 2 | S01, S02; not LOGOS bugs |
| Overlapping capability families | 17 | G1–G17; not 17 extra defects and not additive to the rows above |

G10 also contains two newer build-closure/artifact-handling source findings. G3 contains deadline/authentication/TLS/result-budget limitations. These stay under their existing families rather than being silently promoted into additional B/F counts. There is intentionally no grand total.

## 3. Earlier B register: retain status, do not recycle stale defects

All source paths in this section are LOGOS repository-relative at d9 unless otherwise stated.

| ID / owner | Current evidence and impact | Required acceptance |
|---|---|---|
| **B01 — input focus replacement; LOGOS runtime + MaCSad browser acceptance; P1** | Sequential typing failed on the older served MaCSad bundle: first input event lost focus. d9 has in-place reconciliation addressing that mechanism. It was not the bundle used in the older live reproduction. | Build the exact application assets and type sequential real keys; test selection, backspace, paste, IME and asynchronous repaint. Preserve node identity, focus, selection, value and handler identity. Do not substitute whole-value assignment for typing. See G17/F09. |
| **B02 — text allocation crosses a single fresh memory page; LOGOS; P1** | `crates/logicaffeine_compile/assets/web/runtime.js:56–61` grows one 64-KiB page without allocating all pages required by the encoded text. Earlier fresh-memory harness failed at 65,521 and 100,000 ASCII bytes; the relevant d9 mechanism remains. These numbers are fixture boundaries, not universal size limits. Long theorem/proof output is directly exposed. | Original boundary RED; then multibyte, multi-page, repeated and near-limit allocation. Allocate enough memory or reject before writes. Prove text is untruncated and errors do not corrupt the browser. |
| **B03 — transport size unit/buffering mismatch; LOGOS; P1** | `runtime.js:97–114` uses UTF-16 string length and checks after whole-response buffering. A configured byte budget is not enforced as a UTF-8 streaming bound. | Equal UTF-8-byte limits across browser/mock/native boundaries; multibyte input; chunked oversized response; abort before unbounded buffering; explicit failure rather than truncated success. |
| **B04 — zero-based PG example access; upstream example; historical** | The affected PG todo example was removed; its replacement is file-backed. Removal is not evidence that the original PG handler was corrected. | Retain an actual native PG handler regression if reintroduced. Do not switch MaCSad's authoritative store to the replacement file example. |
| **B05 — failed startup/authentication loses an open TCP handle; LOGOS; P1** | `assets/std/postgres.lg:724–794,818–847`: several authentication/error exits and failed startup send return without closing. The timeout-arming failure branch alone closes correctly. The caller cannot close an unreturned handle. | Repeated failed startup, wrong credentials, truncated/closed/silent peers; open handles and OS sockets return to baseline. Check native and async tiers with bounded owned peers. |
| **B06 — idle HTTP clients exhaust slots indefinitely; LOGOS; source-addressed** | A read deadline now exists in `crates/logicaffeine_system/src/http/server.rs:461–467`. Do not report the earlier missing-timeout mechanism as unchanged. | Real idle/slow client, overload, permit-recovery and drain regressions against the used native engine. F03 still separately applies to handler work. |

## 4. Additional F register

### 4.1 LOGOS core/runtime/interface findings

**F01 — keyed reconciliation matches nodes without moving them. P1; source-established.**

Owner: LOGOS browser runtime. `runtime.js:154–165,180–191`: old real order `[A,B]`, new keyed order `[B,A]` matches and patches B then A but does not physically move the existing nodes. Fresh nodes append. The patch-stream `beginPaint` path also reaches this reconciler (`runtime.js:331`), so LGX is not automatically exempt. Sorted cases or proof steps can display the wrong order and associate the wrong apparent position with a control.

Acceptance: real DOM reorder, insertion at beginning/middle, deletion/reinsertion, stable keyed identity and handler-to-record binding; retain focus/selection where appropriate. Assert physical child order, not only virtual output.

**F02 — browser bookkeeping retains state across repeated work. P1 for sustained use; source-established, no heap profile.**

Owner: LOGOS runtime. `runtime.js:73–74,83–115,132,164,193–208` grows node slots, retains removed-node/handler state and leaves completed fetch records without a demonstrated release path. The retained rate and practical exhaustion threshold have not been measured.

Acceptance: thousands of fixed-size render/fetch/remove cycles, registry counts and post-collection retained heap, teardown and navigation, outstanding consumers, aborted responses and long proof output. Define ownership/release semantics; do not free a legitimate consumer's live result or claim a leak rate without measurement.

**F03 — HTTP timeout releases admission while work continues. P1; source-established.**

Owner: LOGOS HTTP lifecycle; MaCSad owns ambiguous-command reconciliation. `crates/logicaffeine_system/src/http/server.rs:569–585` runs the handler on `spawn_blocking`; a timed-out response becomes 503 and its admission guard drops while the handler remains detached. A later database effect is possible after the client sees timeout; repeated requests can leave more work executing/queued than the nominal HTTP slot budget.

Acceptance: blocked handlers stay within a real execution budget; repeated deadlines cannot create unbounded work. Distinguish response expiry, cancellation request, actual completion and transaction outcome. Reconcile timed-out writes by the same idempotency key rather than blindly retrying. HTTP timeout is not rollback.

**F04 — MCP proof interface lacks the newer CLI contract. P1 for autonomous integration; interface gap.**

Owner: LOGOS MCP/proof maintainer. `apps/logicaffeine_cli/src/mcp/tools.rs:137–147,217–235` uses selected raw-file input and older status/axiom-count output rather than the CLI's project closure, full declaration inventory and certificate envelope. A manual CLI success does not establish that an agent using MCP checked the same problem.

Acceptance: identical multi-file problem through each supported entry identifies the same closure, targets, assumptions and actual proof artifacts. Unsupported certificate/closure contracts must refuse explicitly. Preserve per-target failure and partial completion; never synthesize a missing certificate field.

**F10 — native TCP holds a global registry lock during blocking I/O. P1; source-established.**

Owner: LOGOS native runtime. `crates/logicaffeine_system/src/tcp.rs:140–185` holds the process-global registry mutex through send/receive. Registration (`100–109`) and close (`189–193`) require it too. One blocked connection can delay another, including registration of the connection intended to send cancellation. A sequential one-shot read is not concurrency evidence.

Acceptance: in the native/AOT tier, stall one owned socket while another completes exchange, registration and close within its own budget; it must not wait for the stalled socket's deadline. Exercise multiple HTTP requests and cleanup without touching existing services. Interpreter/VM mocks and pure frame parsers do not cover this behavior.

**F12 — generated ownership handling moves values before reuse. P1; exact-d9 reproduced.**

Owner: LOGOS compiler. One finding with two observed constructs:

1. Passing `result's rows` to `boardResultShapeAccepted` emitted a move of that record field, then emitted iteration over the field again.
2. Passing `[workspace]` to `pgQueryParams` emitted a vector containing the moved string, then reused `workspace` to produce the result.

Both produced Rust `E0382`. The generated-Rust diagnostic explicitly classified the failure as a LOGOS compiler bug. This is neither a database error nor a successful native build.

Original MaCSad source: `docs/proposals/logos-d9-website-evaluation/source-history/board_database.codegen-red.lg.txt:43,46,80,82`; SHA256 `b7eeff89eaa7a3b5569f794f9a33e9b449e2c38f566452a40ec8914d64c7a35f`. Original full build-log SHA256 `9aaa5ccedbb02fd03fe561d1e91e586de2427f4b7cb6392048814e9e44a36ff1`. Retained artifact identity `macsad-board-build.BvFL8HPL`; log lines 6971/6982 contain the two errors. Exit 1, capture successful, zero overflow. No private filesystem paths are needed to identify the evidence.

Acceptance: preserve the original LOGOS source forms; compile natively and compare results with supported interpreter/VM paths. Add minimal reused record-field and sequence-literal-element regressions. MaCSad's named-row local and fresh interpolated parameter are tested application workarounds, not upstream fixes.

**F13 — terminal Inspect prolongs a temporary sequence borrow. P1; exact-d9 reproduced.**

Owner: LOGOS compiler. After the F12 call sites were rewritten, `Inspect pgQueryParams(connection, sql, parameters)` at the end of a function emitted a terminal Rust `match` holding `parameters.borrow()` past the local's lifetime. Both LOGOS branches returned; generated Rust still failed with `E0597`.

Original MaCSad source: `docs/proposals/logos-d9-website-evaluation/source-history/board_database.borrow-red.lg.txt:81–86`; SHA256 `4b4c10d4bb22d5437bb25d117aa44bc9b2bb87d01c097e107ef1ef566de5f5c5`. Original full build-log SHA256 `0d35a7c7944a849ac1cbfad077985993d31419419862dc39ee1df3ba4c797e39`; artifact identity `macsad-board-build.CfvyM9Pt`, diagnostic at log line 6971. Exit 1, capture successful, zero overflow.

Acceptance: unchanged terminal-Inspect source compiles and runs with the same semantics across supported tiers. Cover borrowed sequence/map arguments and both return branches. Evaluating the query into a named result before `Inspect` ends the borrow earlier and worked in the isolated application; it does not repair the compiler's original form.

**F14 — public term parser does not require full input consumption. P1 at an exact textual-target boundary; source-established, no malformed-input execution.**

Owner: LOGOS kernel interface. `crates/logicaffeine_kernel/src/interface/term_parser.rs:38–47` parses one term, skips whitespace, then returns success without requiring its position to equal the input length. The public `parse` wrapper delegates to that method (`32–33`), and the command parser uses it for a type (`interface/command_parser.rs:92`). This establishes the absent end-of-input check; it does not establish that every proposed suffix is accepted by the complete command pipeline.

Impact: successful parsing alone is insufficient evidence that the entire submitted textual theorem or type was consumed. A bridge must not bind the intended challenge to a parsed prefix while silently treating the remaining text as validated. This is separate from T01's certificate-environment reconstruction and is not a demonstrated kernel soundness break.

Acceptance: require full non-whitespace input consumption at exact-input entry points; if prefix parsing is necessary internally, expose it with an explicit remainder contract. Add valid-term-plus-unmatched-delimiter/trailing-junk negative controls, differing tails after the same valid prefix, and whole-command tests, while preserving valid nested grammar. No such runtime regression has been run for this finding. Exact serialized kernel terms and certificate checks still require their own target-binding and environment validation; they are not justified by textual parser success.

### 4.2 Upstream examples, not the MaCSad production store

| ID / severity | Evidence and owner | Acceptance |
|---|---|---|
| **F05 / P2** | Upstream todo example: `examples/fullstack_todo/src/server.lg:53–62,96–97,107–108,116–117`. `saveTodos=false` is ignored while the proposed list is returned; read errors are treated as empty data. Source-established. | Inject write denial/full disk/read corruption. Never report persistence success after failure; distinguish absent initial storage from unreadable existing data. |
| **F06 / P2** | Same example: `server.lg:39–47,53–58,88–97`. Unescaped `id|text|done` lines cannot preserve pipe/newline-containing text. Source-established. | Round-trip pipes, CR/LF, Unicode and long text; corrupt framing fails explicitly. Separately test the intended ID contract: `max+1` may reuse a deleted largest ID. That related identity risk is not counted again. |

### 4.3 MaCSad-owned findings: do not attribute these to LOGOS

| ID / owner | Evidence and impact | Required regression |
|---|---|---|
| **F07 / database-command owner / P1** | Source-inferred reservation replay defect: `database/migrations/0001_initial_schema.sql:2656–2661,2671–2679` checks mutable lifecycle/expiry before replay lookup at `2745–2754`. Not runtime reproduced. | Replay an accepted identical reservation after valid lifecycle advance and expiry; return original identity with no balance/event mutation. Same key/different digest must conflict. Correct through a forward migration, not editing applied schema history. |
| **F08 / preview-operations owner / P1** | The public-preview root returned a directory listing in the earlier live GET. This document does not re-observe current service state or establish a private-data disclosure. | Intended root page, correct MIME, intentional unknown-route response, no directory enumeration. Record the actual served artifact and route when declaring fixed. |
| **F09 / browser-test owner / P1** | `scripts/ci/browser-probe.mjs:125–132` assigns a complete value and synthetic events instead of sequential keyboard input. It can miss B01. Source-established test gap. | Real typing/selection/backspace/paste/IME and async repaint; verify focus after each step. Do not count it as another runtime instance of B01. |
| **F11 / admin application owner / P1** | `logos/admin/src/board_row_decoder.lg` checks lowercase hex but calls trapping `fromHex` without UTF-8 validation. Source finding; malformed-wire regression was not executed in this record. | `ff`, `c0af`, `eda080`, `f4908080`, truncated `e282` reject without a trap; valid ASCII/Greek/four-byte Unicode pass the 4096-byte title limit. The proof-worker's separate UTF-8 protection does not protect this call site. |

## 5. T01: proof-context trust boundary

**Priority P0 for accepting untrusted supplied certificates. Owner: LOGOS kernel/certificate maintainers, with MaCSad responsible for admission policy.**

At d9, `crates/logicaffeine_kernel/src/certificate.rs:197–209` creates a standard context and installs certificate-supplied definitions and declarations directly. `context.rs:434–443` inserts them into maps without checking bodies or rejecting collisions at that boundary. `get_global` returns declared types (`context.rs:449–463`); the primary checker (`type_checker.rs:62–66`) and secondary checker (`recheck.rs:804–808`) both consult it.

Established: the reconstruction path does not establish that submitted definition bodies have their declared types or that submitted names respect the trusted environment. Two checkers sharing an invalid environment are not two independent validations of that environment.

Not established: an end-to-end forged external certificate accepted through the actual public path. No hostile-certificate execution has been performed for this finding. **Do not call T01 a demonstrated kernel soundness break.** Conversely, a successful genuine theorem does not test this hostile boundary.

Declarations as explicit assumptions are legitimate mathematics; accepting a theorem conditional on disclosed, approved assumptions is not inherently a bug. The failures to prevent are an unvalidated definition masquerading as an established fact, an unapproved assumption treated as approved, a trusted-name collision, or substitution of the requested target.

Required acceptance suite:

1. Ill-typed definition body under a superficially acceptable declared type, then a proof referring to it.
2. Definitions/declarations colliding with trusted or previously supplied names, including contradictory duplicates.
3. Unapproved assumptions and an assumption equal to the requested conclusion.
4. Cyclic/forward dependencies, invalid universes, unresolved terms, malformed or oversized contexts.
5. Certificate claimed type differing from the independently trusted challenge.
6. One-bit artifact changes, changed imports/prelude/checker and replay in a fresh environment.
7. Each checker failing, disagreeing or reporting incomplete coverage; do not turn missing coverage into agreement.

The boundary must validate definitions in a legitimate dependency order, enforce name/assumption policy and bind the checked conclusion to an independently obtained target. Until resolved for the used route, exclude untrusted certificate-context admission or use a separately reviewed trusted-context path. This restriction is a trust safeguard, not a permanent mathematical-language subset.

`recheck_theorem` is genuine term checking: it infers the proof type, compares the claimed goal, then invokes the secondary checker (`certificate.rs:221–277`). It can return `rechecks=true` and `two_kernel_agreement=false` for `MainOnlyReCheckerIncomplete`. Preserve that distinction: neither two completed agreeing checks nor a demonstrated disagreement.

## 6. Historical failures and other retained limitations

| ID / owner | Status after d9 evaluation | What remains necessary |
|---|---|---|
| **H01 / LOGOS PG** | Earlier failed-SCRAM hang. d9 includes a 5000-ms socket timeout and its selected failed-SCRAM and full-SCRAM protocol tests passed. | Reproduce the original real-server failure against the exact native/async route. Timeout is armed after TCP connect and resets per operation; it is not an absolute authentication deadline. |
| **H02 / LOGOS PG + caller** | Earlier cancellation hit a subsequent query. d9 `pgCancelInFlight(false)` no-op and exact cancellation-packet tests passed. | Native concurrent cancellation/reuse race with generation ownership. The caller Boolean is not atomic correlation; legacy cancel supplies true. F10 can delay the fresh cancellation connection. |
| **H03 / LOGOS WASM compiler** | Earlier real V8 rejection: an emitted call expected i32 and received i64. The exact original fixture was not rerun in this evaluation. | Recover and execute it in pinned real V8/browser; name the module/source/hash and exact affected tier. General WASM successes do not close it. |
| **L03 / LOGOS static serving** | `apps/logicaffeine_cli/src/commands/serve_web.rs:414–431` follows symlinks without establishing canonical root containment. Source limitation, not demonstrated production disclosure. | Reject symlinks/path traversal escaping the admitted asset root; test serve and export. Do not serve arbitrary private source directories. |
| **S01 / MaCSad schema/policy** | Mention references do not themselves establish source-workspace membership. Policy/enforcement question, not a LOGOS bug. | Explicit allowed cross-workspace semantics and negative membership tests at acceptance. |
| **S02 / MaCSad publication policy** | Public dossier checks do not themselves require complete license/attribution fields. Policy/enforcement question. | Explicit license/attribution/not-applicable rules; reject incomplete public-release evidence. |

Earlier labels L01 (PG admission), L02 (production HTTP) and L04 (proof closure) describe integration limitations, not three additional independent bugs. Their current contracts are covered below by G3/G15 and the baseline/d9 proof distinction. In particular, d9 CLI closure support must not be confused with baseline raw-file behavior or MCP F04.

## 7. G1–G17: capability and industrial acceptance map

These are overlapping acceptance families. Baseline descriptions in the historical ledger are not automatically true of d9. New implementation is not automatically promoted application evidence.

| Family | Current distinction and unresolved acceptance | Primary owner |
|---|---|---|
| **G1 typed browser requests** | d9 has correlated method/body/header/status/error/abort/timeout substrate. Close B02/B03/F02 and real command transport. Legacy GET-only/global-response behavior is baseline context. Retain the older CSS-at-rule scoping regression (`@media`, `@supports`, keyframes); exact d9 status was not re-established. | LOGOS runtime; MaCSad contracts |
| **G2 header-aware HTTP** | d9 Request has headers/query and Response supports headers/bytes. Reserved authenticated identity must be overwritten/verified server-side; caller headers are not authority. Test duplicate/spoofed headers, malformed encoding and response splitting. | LOGOS transport; MaCSad/security |
| **G3 typed PostgreSQL** | d9 has simple/prepared/parameterized queries, NULL masks, OIDs, exact-value getters, transactions, timeout and cancellation. B05/F10, absolute deadlines, total result budgets, pooling and deployment authentication/TLS remain. The seven-method native fixture narrows only the controlled read path. | LOGOS PG; MaCSad/DB/ops |
| **G4 routing/navigation** | New pages/history substrate exists; deep links, refresh, back/forward, unknown routes and actual workspace selection require application browser evidence. | LOGOS UI; MaCSad |
| **G5 project assembly** | New closure support exists. Prove that check/test/prove/serve/emit/build use the intended graph and report every target/test. Test nested imported changes and Main/Serve isolation; zero discovery/filter matches must not masquerade as success. | LOGOS loader/CLI; MaCSad gate |
| **G6 honest cross-tier evidence** | Distinguish interpreter, VM, WASM, AOT and actual browser results. A named “all” mode or non-error result is not a universal differential. Compare output, values, state and DOM; unsupported routes explicitly refuse. | LOGOS tests; verifier owner |
| **G7 deterministic static publication** | d9 static/release substrate is not a sealed scientific publication workflow. Build complete artifacts twice; exclude secrets/private bytes; validate L03 and exact reviewed publication input. | LOGOS emission; MaCSad publication |
| **G8 binary HTTP/file parity** | New byte/file bindings address old deficits by source. Assert status, headers, compression, byte length and body across used tiers, including empty/WASM/arbitrary bytes. Do not repeat baseline “no bytes” as d9 fact. | LOGOS codegen/HTTP |
| **G9 deep checking** | Older baseline prelude/span panic; newer mapped/deep-check tests exist. Exact MaCSad graph must complete with stable file/line diagnostics before old workarounds retire. | LOGOS checker/loader |
| **G10 immutable dependencies and build artifacts** | New local dependency support exists, but preserve source/runtime/tool closure. d9 generated apps use semver dependencies and Cargo without `--locked`; nondefault-target artifact selection also needs verification. Detailed gate below. | LOGOS build; toolchain owner |
| **G11 typed structured data** | d9 strict duplicate rejection/typed extractors passed 17 selected tests. Still define depth/bytes/Unicode/number profile, lexical versus numeric integer requirements, exact decimals/UUIDs/nullability and native deployed behavior. Strict JSON support does not imply full Lean proof representation. | LOGOS serialization; adapter owner |
| **G12 actual engine identity** | Earlier MCP labels could reach the same routine/fallback. Whole d9 interface not exhaustively re-audited. Record actual implementations and deliberate refusal, not merely requested labels. | LOGOS MCP/runtime |
| **G13 proof semantics** | Real native proof paths and newer inventory/certificates exist. T01/F04/F14, target/assumption binding, certificate-route coverage and finite/unrestricted evidence remain material. | LOGOS proof; mathematical verifier |
| **G14 external tools and selected gates** | Missing required compiler/Node/browser/checker must fail the selected gate. Count ignored/optional skips explicitly. Framework CI job failure is not an individual bug count; inspect assertion versus infrastructure cause. | LOGOS CI; MaCSad CI/ops |
| **G15 serving/lifecycle** | d9 offers loopback binding, readiness/drain and request/read limits. F03/F10 and real command outcomes remain. Test shutdown, malformed clients, backpressure and bounded residual work on the selected engine. | LOGOS HTTP; MaCSad/ops |
| **G16 component scope attribution** | Baseline needs redundant entry imports and exact warning allowances. Recheck defining-module attribution on d9 before removing scaffolding; reject genuine private-name leaks. | LOGOS scope checker; MaCSad |
| **G17 real browser/WASM behavior** | Original focus mechanism addressed in source; F01/F02/F09 and H03 still require exact generated-bundle and real-user interaction evidence. | LOGOS runtime/compiler; MaCSad browser |

### G3 details relevant to an industrial reader

`assets/std/postgres.lg:818–847` calls native connect before arming the authentication timeout and clears it on success (`792`). Rearm positive socket and statement timeouts; the native connection API uses `TcpStream::connect` without an explicit connect deadline (`system/src/tcp.rs:100`). `pgQueryParams` sends text parameters and requests all rows (`postgres.lg:1562–1587`); rows accumulate in memory (`1402–1459`). SQL LIMIT plus field and total-byte policy is necessary, but post-read validation alone does not bound transport allocation.

The URL parser discards query options (`postgres.lg:475–477`). An `sslmode=require` string therefore does not prove TLS. Pin/validate the allowed transport instead of silently accepting security intent. The narrow fixture rejected such options before connection and used test-only loopback trust authentication; it is not credentialed deployment evidence.

Validate exact columns, typeOids, row counts, per-row lengths and nullMask before indexing. Text-format values do not imply text OIDs. Explicit SQL casts and statement parameters avoid accidental type inference. Do not use the legacy NULL-to-empty projection where absence matters.

Additional source risk, not a new counted B/F ID: DataRow parsers directly index body fields and treat every negative cell length as NULL (`postgres.lg:1296–1320`). Result-typed top-level APIs are not a proof that every malformed peer frame is a total error. Add hostile frame lengths, counts and UTF-8 to the protocol qualification suite.

### G10 details: pin the application, not merely its compiler

`apps/logicaffeine_cli/src/project/build.rs:431–549` stages local runtime sources when correctly bound, but emits dependencies such as `tokio = "1"` and does not itself invoke Cargo with `--locked`. `crates/logicaffeine_compile/src/compile.rs:3161–3215,3453–3498` can fall back to published runtime crates when workspace discovery fails. A matching `0.10.1` label is insufficient.

Preserve the complete generated source, runtime inputs, Cargo.lock, feature selection, compiler/tool versions and artifact digests. Require a locked-offline rebuild from that retained closure. Also verify the actual artifact and stable copy: `project/build.rs:678–712` uses a best-effort copy and its returned binary path does not fully follow `CARGO_TARGET_DIR`. A stale executable must never serve as evidence for a failed new build.

The isolated MaCSad workaround artifact satisfied these checks. General deterministic builds and portable replay across machines remain separate qualification work.

### G15 details: native loopback HTTP is available, not the blocker

Native `Serve` calls `env_bind_address(env_port_override(port))` (`codegen/stmt.rs:2306`). `LOGOS_HOST=127.0.0.1` is explicit and supported; `LOGOS_PORT=0` requests an ephemeral port (`system/src/http/server.rs:65–128`). Plain Serve does not expose the assigned port as a LOGOS handle; fixture supervision must discover the exact owned child's listener, not attach to an arbitrary open port.

Pin the engine. The tokio path handles SIGTERM/SIGINT and drain (`server.rs:418–428`; `http/lifecycle.rs:384–405`), whereas the io_uring Serve branch awaits indefinitely (`server.rs:666–677`). Plain Serve starts marked ready (`367–370`); built-in probe routes bypass application handling (`532–542`) and do not establish database or mathematical-worker readiness. Probe actual dependency-aware application outcomes. Do not bypass production authentication to obtain a green fixture.

## 8. Native LOGOS mathematical-proof contract

The baseline and newer routes must not be mixed:

| Route | Actual evidence | Remaining distinction |
|---|---|---|
| Baseline `largo test --prove` | Supported finite property checking/enumeration | Not all theorem blocks and not unrestricted mathematical proof by default. Record the quantified domain. |
| Baseline `largo prove --json` | Actual selected theorem reports; MaCSad LOGOS policy validates exact requested target names and report consistency | `axioms=0` does not account for all English Given premises. Preserve source. Re-running is source replay, not retained proof-term replay. |
| d9 CLI prove | Project-closure evaluation, declaration inventory, richer theorem/certificate/recheck output in supported routes | Inspect every target's actual evidence, not only top-level success. Tarski and English-theorem paths need not export the same portable certificate. |
| d9 `recheck_theorem` | Type checking of retained term and comparison to claimed type; second-checker coverage explicitly reported | T01, independent challenge binding and incomplete secondary coverage remain. |
| d9 MCP proof | Older raw-file/status surface | F04 until it meets the selected full-closure/artifact contract or explicitly refuses it. |

Source references: `apps/logicaffeine_cli/src/commands/prove.rs:118–184,263–305`; `mcp/tools.rs:137–147,217–235`; `crates/logicaffeine_compile/src/ui_bridge.rs:3221`; kernel certificate references in section 5.

Mandatory receipt semantics for any accepted mathematical result:

- Exact problem revision and trusted elaborated target, including domain, quantifiers, definitions and assumptions.
- Exact source/import/library/toolchain/checker/prelude identities, plus actual invoked settings and route.
- Actual proof/certificate bytes where that route promises artifacts; retained logs and exact producer/checker outcomes.
- Complete assumption disclosure, including indirect dependencies; separate “checked under these assumptions” from “assumption-free.”
- Clear states for proved-under-policy, not proved, rejected input, unsupported route, interrupted, resource-exhausted, checker disagreement and incomplete secondary coverage.
- No success from zero requested targets, unrelated true targets, an assumed conclusion, missing obligations, finite-only tests mislabeled as unrestricted proof, or stale artifacts.
- A proof result does not authorize durable scientific acceptance, publication, spend or deployment by itself.

A valid implication over an empty antecedent can be a genuine theorem. The acceptance defect is an unintended weaker/empty-domain formalization or violation of the admitted task contract, not vacuity in the abstract. An external Lean checker is not universally mandatory for a well-evidenced native LOGOS kernel route; claims of cross-system/independent checking must name what actually ran.

## 9. Full Lean compatibility: required bridge contract

This is a target and acceptance specification, not a claim that a bridge already exists. The original small native demonstration remains useful evidence but does not define the finished product's expressiveness or project-size ceiling.

### 9.1 Preserve the complete project environment

Lean projects use a toolchain selection, a Lake project configuration, a dependency manifest and transitive sources/artifacts. Lake updates can change dependencies and the toolchain. A bridge must freeze and verify the exact environment rather than silently update it during checking. [Official Lake documentation](https://lean-lang.org/doc/reference/latest/Build-Tools-and-Distribution/Lake/)

Required retained inputs: `lean-toolchain`, `lakefile.lean` or `lakefile.toml`, `lake-manifest.json`, every source/import and local/Git dependency, generated declarations needed for replay, configuration/options, selected targets, tool/checker binary digests and platform-dependent/native dependencies where used. Preserve input bytes and provenance. Do not paste one file into a scratch project and claim full-project compatibility.

Missing dependencies, incompatible versions, malformed projects and execution-budget exhaustion are distinct outcomes. Do not silently rewrite imports, use a convenient different mathlib version, flatten namespaces, omit hard files or certify only the easiest target. An unsupported valid project is a reported compatibility gap, not a passing compatibility case.

### 9.2 Preserve semantics across systems

Lean's kernel checks proof terms in dependent type theory; its tactic/elaboration layer is expressive and extensible. A bridge that supports a few surface patterns has not implemented that entire environment. [Lean reference overview](https://lean-lang.org/doc/reference/4.34.0-rc2/)

For native translation, specify and test universe levels/polymorphism, dependent functions and pairs, inductive families and recursors, structures, quotients, equality, proof irrelevance, reduction/definitional equality, recursion/termination, coercions, type-class resolution, implicit arguments, notation/macros, namespaces and imported extensions. These are compatibility obligations to validate, not assertions that each is currently absent from LOGOS. No item may be silently replaced by an axiom or an uninterpreted constant while claiming the original proof was preserved.

For project ingestion using Lean itself, preserve the original language and let the admitted Lean toolchain elaborate it. That can deliver useful full-project support before a native translation is complete, but must be labeled “Lean-backed checking,” not “LOGOS independently checked every Lean construct.” A LOGOS interface around Lean is not evidence of a reimplemented Lean kernel.

For LOGOS-to-Lean generation, retain the original intent and a separately approved formal target. Generated statements and imported definitions must match that target, not merely be similar text. For Lean-to-LOGOS translation, require preserved elaborated conclusions and assumptions, plus rechecked proof artifacts or a justified translation-validation argument. Round-trip pretty-printing alone is not semantic equivalence.

### 9.3 Preserve proof evidence and check the right claim

Lean's own validation guidance distinguishes proof validity from theorem meaning, recommends inspecting indirect axioms, and describes fresh replay and stronger sandboxed challenge comparison for hostile submissions. It explicitly discusses incomplete dependencies and malicious metaprograms. Merely getting an editor checkmark or a successful process exit is not the complete high-risk acceptance boundary. [Lean: validating proofs](https://lean-lang.org/doc/reference/4.34.0-rc2/ValidatingProofs/)

A bridge acceptance receipt must bind the trusted challenge, exact target names, elaborated types, assumption set, project closure, retained proof/export bytes and checker identity. Version-specific features such as native-evaluation trust markers must be recognized under the selected Lean version rather than treated as timeless assumptions. `sorryAx`, undisclosed custom axioms, altered target interpretation or skipped kernel checking cannot masquerade as an unconditional solved problem. Legitimate custom axioms may be preserved and reported as conditional mathematics; an application admission policy can decline a claim without falsely calling the Lean project syntactically invalid.

Use an explicitly admitted replay/comparison path. The official comparator project provides one relevant design/reference: sandbox production, retain exported proof data and compare against a separately trusted challenge. Its presence in this document is not evidence that MaCSad installed, ran or admitted it. [Official comparator repository](https://github.com/leanprover/comparator)

### 9.4 Library breadth and large proofs

The mathlib import index spans major areas including algebra, analysis, topology, measure theory, number theory, geometry and category theory. Supporting a handful of propositional examples does not establish comparable library access or semantics. [Mathlib module index](https://leanprover-community.github.io/mathlib4_docs/Mathlib.html)

Qualification must grow from minimal reproductions to representative multi-file projects and large retained developments. Track dependency loading, theorem/definition inventory, generated proof size, peak memory, wall/CPU time, cache correctness, interruption/restart and fresh replay. The full compatibility target remains all valid finite inputs under the declared supported environment; a staged test corpus is evidence toward that target, not a whitelist defining the eventual product.

Do not reuse the current demonstration's small command-line payload limit as a permanent theorem-size ceiling. Large source/proof inputs need immutable artifact references, validated streaming or chunking, explicit aggregate limits, and out-of-band logs/artifacts rather than one huge browser string or command argument. B02/B03/F02 are especially relevant here.

### 9.5 Autoformalization and theorem-discovery comparison

No matched LOGOS-versus-Lean autoformalization benchmark has been run in this work. Operational codegen failures do not themselves rank mathematical accuracy; passing framework tests do not establish parity either.

Define a reproducible benchmark before claiming equivalence: representative domains and difficulty, held-out original problems, fixed source/library/model/tool versions, equal compute/cost budgets and prompts, independent assessment of statement faithfulness, mechanically checked proofs, complete assumptions, repeated runs, failures/unsupported cases and resource use. Report separately formulation correctness, checker acceptance, search success, proof/library coverage, replay success and throughput. Do not count duplicate lemmas, assumed targets or weakened statements as new solved problems.

## 10. Industrial mathematics and multi-worker operation

These requirements are not all LOGOS bugs. They are the controls needed to turn proof-capable components into a dependable Mathematics Factory.

| Blocker / owner | Acceptance required |
|---|---|
| Mathematical specification and units — mathematical/domain owners | Preserve original data/problem, units, domains, quantifiers, error tolerances and definitions. Separate a model's proven property from evidence that the model represents the industrial system. |
| Numerical/certified-computation boundary — LOGOS/library + verifier owners | State exact versus approximate arithmetic, integer overflow policy, rounding/error bounds and oracle assumptions. A floating-point simulation or external solver's success is not automatically a theorem certificate. Validate required certificates or mark the result empirical/conditional. |
| Multi-stage formalization — MaCSad/research owner | Version decomposition, intermediate lemmas and assumptions; propagate invalidation when premises change. Preserve failed/inconclusive attempts. OPDP is a potential input/method tool, not a proof oracle or an already integrated autonomous pipeline. |
| Worker isolation — operations/security | Untrusted Lean tactics, build scripts, native code, LOGOS inputs and model output run without database/provider/repository/deployment credentials. No writable trusted cache or control policy. Restrict network and filesystem; bound descendants, CPU/RAM/disk/output and cleanup. |
| Scheduling/cost — MaCSad command + operations | Fenced execution leases, bounded concurrency, fair queues, worst-case reservations and idempotent retries. Timeouts/OOM/cancellation must not become false mathematical failure or false success. Address F07 before paid autonomous replay reliance. |
| Durable authority — MaCSad/database | Authenticate users; derive workspace/role server-side; validate capability, expected version and idempotency. Commit command/result/event/outbox atomically. A process report is not permission to mutate research state. |
| Artifacts and recovery — storage/operations | Immutable source, proofs, logs, closure manifests and provenance/rights. Backup actual bytes, not only digest rows; restore on a fresh host and replay a real retained result. Model reproducibility and proof replay are separate properties. |
| Publication — MaCSad/scientific owner | Review the mathematical claim and provenance, enforce privacy/license/attribution, produce an immutable approved public projection. No LLM verdict, green UI card or checker result alone publishes a discovery. |
| Release/control policy — delivery/security | Candidate evaluation is not promotion. Preserve exact tested revisions, real independent controller/verifier evidence and rollback. A proposal or runner label does not implement independent policy activation. No automatic human code-review requirement is inferred here. |
| Measured service capacity — LOGOS/runtime + operations | Concurrent native DB/HTTP/browser/proof load, adversarial inputs, prolonged operation, bounded abandoned work, restart and recovery. Name measured supported capacity and SLOs; do not infer them from single-user fixtures. |

The prior process-cleanup incident belongs to MaCSad's mechanical helper/test implementation, not LOGOS. Its owned-PID safeguards and service recovery evidence must remain in the incident record; neither conceal it nor inflate the LOGOS defect count with it. Upstream failed CI jobs likewise require triage into product assertions, infrastructure and unexecuted tiers before any regression count.

## 11. Required next acceptance work

This ordering prioritizes trust and reusable foundations while preserving the full compatibility target:

1. **Freeze the contract and evidence identities.** Choose supported Lean versions and bridge directions; retain d9/baseline source, failing forms and the actual original logs. Name owners and expected outcomes before changing code.
2. **Reproduce and repair F12/F13 upstream.** Keep their LOGOS inputs unchanged; add focused native regressions and supported-tier differentials. Do not close them with MaCSad workarounds.
3. **Exercise T01 and F14 at their actual boundaries.** Include valid controls, adversarial contexts/targets and exact textual-input consumption; establish the checker trust base. Restrict the affected path until its boundary is validated. These are separate findings, not two demonstrated soundness breaks.
4. **Implement full project/target preservation.** Nested imports, local/Git dependencies, multiple targets, custom notation/type classes, changed dependencies and deliberately missing imports. No source flattening or zero-target success.
5. **Deliver the Lean-backed project route and explicit receipts.** Real pinned toolchain, preserved artifacts, assumption inventory and trusted challenge comparison. This is a milestone toward broad support, not evidence that native LOGOS translation is complete.
6. **Expand semantic/proof-translation coverage.** Test the constructs and libraries in section 9, both valid and deliberately altered/invalid controls. Report unsupported coverage honestly while closing it; do not silently weaken the target.
7. **Scale beyond toy fixtures.** Large imports, long proof terms, high memory demand, repeated jobs, streaming artifacts, interruption and fresh replay. Measure scaling without dropping the original theorem or obligations.
8. **Qualify the full native/browser/database path.** B02/B03/B05/F01/F02/F03/F10, H regressions, actual authenticated workspace reads and then atomic commands. Keep fixture-only trust/TLS exceptions out of production.
9. **Run the complete required release gates.** Exact inventories, no hidden skips, genuine engine identities, real browser and native behavior, generated application locks/artifacts, independent evidence, clean rollback/recovery.
10. **Benchmark the mathematical claim.** Only after statement/proof/assumption integrity is protected, compare autoformalization and research throughput using the matched criteria above.

For every finding's closure, provide: original RED source and environment; immutable fixing SHA; unchanged regression GREEN; hostile/negative cases; affected tiers actually run; exact output/artifact identities; integration/promotion state; residual limitations. A source patch, parser check, unselected ignored test, rewritten demo or successful archive upload is not sufficient by itself.

## 12. Evidence and source index

### Retained execution evidence

| Evidence | SHA256 / identity |
|---|---|
| Isolated d9 CLI build log | `d73e8401bf061dd992e193a23ce94606ec984d533e712ee39fbf2264d6974cfb` |
| Four-target 113-test log | `0202c0f5fc8121641bffbe2de4edcc427c34472d43578d948616e21e776767a1`; 8 September 23:09:25–23:29:59 UTC |
| F12 original failing build log | `9aaa5ccedbb02fd03fe561d1e91e586de2427f4b7cb6392048814e9e44a36ff1` |
| F13 original failing build log | `0d35a7c7944a849ac1cbfad077985993d31419419862dc39ee1df3ba4c797e39` |
| Workaround native executable | `a766b4393255e3b48daf4280d857ba0ce9e9bed1b9e74adb4ce980a30c4dd860` |
| Workaround generated Cargo.lock | `1da98e786e9723e5592fe52a70d089446e4bd2a02100fbbbc9c28ceb11a5a9bf` |
| Seven-method real-PG fixture GREEN log | `49fb899168ce9a793d18476e349831fd2e540e911578c0eec1b020ed24687658` |

Original failing logs and archived MaCSad source hashes were rechecked read-only while preparing this handoff. The proposal archive deliberately omits private generated Rust, framework binaries, credentials, database contents and developer-specific absolute paths. Its sanitized excerpts identify, but are not replacements for, the retained full original evidence. The archival patch is inert input, not automatic activation or a complete runnable distribution.

### Immutable LOGOS source pointers

- [d9 browser runtime](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/crates/logicaffeine_compile/assets/web/runtime.js)
- [d9 PostgreSQL library](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/crates/logicaffeine_compile/assets/std/postgres.lg)
- [d9 native TCP runtime](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/crates/logicaffeine_system/src/tcp.rs)
- [d9 HTTP runtime](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/crates/logicaffeine_system/src/http/server.rs)
- [d9 certificate reconstruction/recheck](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/crates/logicaffeine_kernel/src/certificate.rs)
- [d9 kernel context](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/crates/logicaffeine_kernel/src/context.rs)
- [d9 public kernel term parser](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/crates/logicaffeine_kernel/src/interface/term_parser.rs)
- [d9 CLI proof interface](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/apps/logicaffeine_cli/src/commands/prove.rs)
- [d9 MCP tools](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/apps/logicaffeine_cli/src/mcp/tools.rs)
- [d9 generated application build](https://github.com/Brahmastra-Labs/logicaffeine-private/blob/d9baaff5b6749c961a13cd2eca427434c5959b17/apps/logicaffeine_cli/src/project/build.rs)

These links require the reader's existing repository access; they contain no credentials. Source locations describe inspected snapshots and may move in later revisions. This document adds no evidence that unexecuted adversarial, full-suite, benchmark, production or full-Lean compatibility gates have passed.
