# LOGOS gaps and required framework gates

MaCSad pins the **local** `Brahmastra-Labs/logicaffeine-private` source at
LOGOS `0.10.1`, commit `132dc5346728e2d204df798dd7544e6405306a2c`,
tree `9f251ad38ed49834d8224bbf6b928cb5ba1aa1c5`. The build wrapper rejects
another commit, tree, Cargo lock, `largo` binary, dirty tracked source, or
unrelated origin. MaCSad does not install or resolve LOGOS from crates.io.

## September 8, 2026 integration update

The admitted toolchain is still `132dc5346728e2d204df798dd7544e6405306a2c`.
Its matching local checkout is `logicaffeine-macsad-admitted`; using that copy
does not promote the newer LOGOS checkout. No upstream edits or pushes are
part of this MaCSad workstream.

The later source-only readiness audit inspected upstream
`d9baaff5b6749c961a13cd2eca427434c5959b17`. See
[the shared readiness report](docs/ELECTRON_READINESS.md), especially its
version-scoped inventory and T01 proof-context trust finding. Newer source
availability is not completed runtime, security or promotion evidence.
The candidate snapshot below is retained as historical evidence, not as a
claim that it is the latest upstream commit.

MaCSad now has a native LOGOS proof-report policy and a bounded argument port
under `logos/proof-worker`. The baseline can run `largo prove --json`, validate
the exact requested targets through LOGOS, preserve the source and observations,
and repeat the same-source check. This narrows G13 for a local demonstration;
it does not close the complete mathematical trust/publication contract.

The completed MaCSad gate at this admitted baseline passed 33 native LOGOS
tests, 10 finite application properties and nine real-LOGOS integration methods
(eight demonstration runs and 42 adversarial wire/report cases), alongside the
existing Node/Python, deterministic-bundle and fresh PostgreSQL 16 tiers.
Exact snapshot/log identities and the retained demonstration bundles are in
section 18.6 of the readiness report. These are not newest-upstream gate results.

Baseline limitations directly relevant to this integration:

- `prove` JSON's `axioms` field counts theory axioms, not English `Given`
  premises. Zero there is not an assumption-free result. Preserve `input.lg`.
- Running `prove` again is source replay, not replay of a retained proof-term
  certificate. The baseline CLI does not provide the required portable
  certificate export/replay interface. Do not claim independent checker
  agreement from its `all_verified` field.
- For the retained theory examples, `prove --trace` emits a short checked-result
  summary, not an exported proof term or detailed derivation. Save it honestly
  as CLI diagnostics; it does not substitute for certificate evidence.
- The supported theorem blocks are checked; whole-program definitions and
  import-closure coverage are not established by this entry point.
- Baseline interpreter console input and strict JSON object decoding cannot
  supply this worker's complete typed input boundary. The narrow workaround
  uses bounded host-side structural JSON decoding and canonical data arguments;
  mathematical report classification remains LOGOS code.
- `fromHex` can throw on invalid UTF-8 rather than returning a typed decoding
  failure. The MaCSad argument boundary now validates canonical UTF-8 before
  calling it; adversarial tests cover overlong encodings, surrogates and invalid
  continuation bytes. This workaround is not a general upstream parser fix.

The local process-cleanup incident is a MaCSad implementation/test defect,
not a LOGOS bug. Its recovery and residual verification limits are recorded in
[the incident report](docs/INCIDENT_2026-09-08_PROCESS_CLEANUP.md).

## Exact d9 website-integration evaluation

Alejandro authorized evaluating `d9baaff5b6749c961a13cd2eca427434c5959b17`
in a separate copy. The admitted `132dc534` toolchain is unchanged. The isolated
offline, locked, two-job CLI build succeeded in 179 seconds. Candidate tree:
`34f712714619bc9049a4dc9c1d22962dd67d63c4`; Cargo.lock SHA256:
`341398289909e4b5c85520e1554308bb285f081cae3935147efb282ab4bf23c2`;
CLI SHA256:
`b937f4ea8e8d3f6067bf119add89c3476066924422794da61440cc83d246ad5b`.
This is build evidence, not promotion, byte-reproducibility, full upstream test
success or completed website/database integration.

The selected upstream invocation subsequently passed **113 tests, zero failed,
zero ignored and zero filtered**: `json_typed_decode_lock` 17,
`postgres_aot_lock` 2, `postgres_protocol` 27 and `postgres_wire` 67. It ran
September 8, 23:09:25–23:29:59 UTC (20 minutes 34 seconds including compilation),
offline with two build jobs and serialized tests. Retained log SHA256:
`0202c0f5fc8121641bffbe2de4edcc427c34472d43578d948616e21e776767a1`.
The candidate Cargo.lock stayed unchanged and tracked source remained clean.
The AOT cases test native frame/parser behavior; the protocol exchanges use
owned loopback mock peers. These results are **not** a native MaCSad/real-PG16
round trip, full upstream-suite acceptance or evidence that the source findings
below have been fixed.

Focused evaluation uses an isolated temporary/cache directory and explicitly
binds `LOGOS_WORKSPACE` to the exact candidate. Otherwise a CLI binary outside
its source checkout can discover published runtime crates with the same version
string. MaCSad must retain the exact source/runtime closure, not only a binary.

F10 and F11 below are additional source findings; neither is a runtime
reproduction or closure of the historical G1–G17 contracts. F12 and F13 are later
observed native compilation failures. Existing timeout, socket-cleanup, TLS and
JSON-number-token issues are not counted again.

The subsequent MaCSad candidate-only read experiment passed all seven methods
against a newly owned PostgreSQL 16.15 fixture cluster, using an actually native
LOGOS executable and the existing schema. It returned three closed cases twice
identically and preserved all 47 table fingerprints. This narrows the G3/G15
application-read uncertainty; it does not promote d9 or connect the live website.
The full TDD sequence and exact evidence are in readiness section 19.5 and the
[inert evaluation proposal](docs/proposals/LOGOS_D9_WEBSITE_EVALUATION.md).

### F10 — native TCP registry serializes blocking I/O — P1

Owner: LOGOS upstream; MaCSad documents only. In exact d9
`crates/logicaffeine_system/src/tcp.rs`, `send`, `recv` and `recv_exact` hold the
process-global registry mutex while performing blocking socket I/O (lines
140–185). Connection registration and close need the same lock (100–109,
189–193). Therefore separate native database connections can block one another;
even establishing a cancellation connection can wait behind the target read.
This is distinct from the HTTP handler-lifetime finding F03.

Required runtime RED: one owned loopback peer stalls while a different native
connection performs a bounded exchange or close; the second operation must not
wait for the first socket's read deadline. Exercise the AOT/native tier, not
only interpreter mocks or pure PostgreSQL frame parsers. Confirm all owned
connections and processes are cleaned up. Until then, an isolated sequential
board-read test is not evidence for concurrent multi-user database service.

### F11 — MaCSad board title decoder can throw on invalid UTF-8 — P1

Owner: MaCSad application. `logos/admin/src/board_row_decoder.lg` validates
lowercase hex shape, then calls `fromHex` without UTF-8 prevalidation. Inputs
such as `ff`, `c0af`, `eda080`, `f4908080` and truncated `e282` can reach the
trapping decoder instead of returning a rejected row. Source finding only at
this record; the malformed-wire runtime regression remains to execute.

Required RED: each invalid input returns false without a thrown runtime error;
valid ASCII, Greek and four-byte Unicode remain accepted at the existing
4096-byte title bound. Reuse candidate `validUtf8` only in an explicitly tested
candidate; that function is absent from the admitted baseline. The proof-worker
prevalidation already implemented does not automatically protect this separate
admin call site. Do not copy policy across projects or weaken the module-closure
guard to conceal the missing reuse boundary.

### F12 — native ownership emission loses reused values — P1

Owner: LOGOS upstream; MaCSad documents only. The exact d9 native MaCSad board
build failed with two Rust `E0382` errors after accepting the LOGOS source:

- Passing `result's rows` to the shape validator emitted a move of the record
  field, then attempted to iterate that same field again.
- Passing `[workspace]` to `pgQueryParams` emitted `vec![workspace]`, then
  attempted to reuse the moved string when serializing the result.

Count this as one ownership-code-generation finding with two observed cases,
not two failures of PostgreSQL itself. The CLI explicitly classified the
generated-Rust failure as a compiler bug. The failed build's retained log
SHA256 is
`9aaa5ccedbb02fd03fe561d1e91e586de2427f4b7cb6392048814e9e44a36ff1`.
The existing stable executable was not accepted or run as a successful build.

The candidate-only MaCSad workaround binds rows to a named local before
validation/reuse and constructs a fresh interpolated parameter string. Native
rebuild and real-PG contract results must be recorded separately; merely
rewriting the application source does not close F12. Upstream should add
native regression cases for reused record fields and sequence-literal elements
and compare behavior with interpreter/VM tiers. No upstream patch was made.

### F13 — terminal Inspect retains a temporary sequence borrow — P1

Owner: LOGOS upstream; MaCSad documents only. After the two F12 move sites were
rewritten, the next exact d9 native build failed with Rust `E0597`: a named
parameter sequence did not live long enough. The generated terminal `match`
for `Inspect pgQueryParams(connection, sql, parameters)` kept the temporary
`parameters.borrow()` guard alive past the local's destruction. Both LOGOS
branches returned; the generated Rust still failed lifetime checking.

This is a separately observed borrow-lifetime failure, not a database error or
a repeated count of the earlier moves. Retained build-log SHA256:
`0d35a7c7944a849ac1cbfad077985993d31419419862dc39ee1df3ba4c797e39`.
The candidate-only workaround evaluates the query into a named result before
`Inspect`, ending the argument borrow at the preceding statement. Record the
subsequent native build and real-PG evidence before claiming the workaround
works. Upstream needs a focused terminal-inspection/native borrow regression;
MaCSad made no upstream edit.

F12/F13 workaround outcome: the final native artifact passed its explicit
locked-offline rebuild and all seven real-PG methods. Executable SHA256:
`a766b4393255e3b48daf4280d857ba0ce9e9bed1b9e74adb4ce980a30c4dd860`.
That accepts the bounded application workaround in this isolated evaluation,
not the unfixed original source forms or general upstream ownership/lifetime
correctness. Both upstream findings remain open.

## Historical candidate snapshot status

The commit above remains the **admitted baseline** in the MaCSad toolchain
lock. A newer LOGOS `0.10.1` snapshot is under evaluation, not promoted:

- commit `92c31ecf2ca42ab7d36f6695c550ec24b835b6d5`;
- tree `434ce407d21dd45d54d3c99890113a2c1143011c`;
- `Cargo.lock` SHA-256
  `76807e6579a73a6771fad5693a2fe98d44afce524fb6152a6d606269f670f41d`; and
- locally built `largo` SHA-256
  `49cbeae65af7a27b47d05f0d8f357c7547a4c1583d0c19961de0051b58b4d1b7`.

This candidate includes the full-stack LOGOS campaign at `257e9f4f`, followed
by focused fixes for native-only TCP/Serve tier classification and documented
reactive-control syntax. The focused `wasm_aot_lock` suite is 6/6 green and the
extension grammar ratchet plus all four unchanged corpus snapshots are green.
The official extension job, including its VS Code integration tests, is green
at the candidate commit. The official workflow is not green overall: its
archive job failed and other jobs were still running when this snapshot was
recorded. This ledger update does not change the MaCSad toolchain lock.

Focused Firebat One evidence for this unpromoted snapshot:

- G1: correlated browser requests now expose method, body, headers, status,
  errors, timeout, and abort substrate; the complete bounded adversarial MaCSad
  contract and stable bound-control behavior remain open.
- G2: request headers/query values and response-header controls exist, while a
  trusted, overwrite-safe identity boundary is still absent.
- G3: a real PostgreSQL 16.15 cleartext round trip and typed getters pass on
  the interpreter and VM. The serialized live suite then found two blockers:
  a best-effort cancel can cancel the following query, and a failed SCRAM
  authentication reaches PostgreSQL's authentication timeout then leaves the
  client blocked on a closed socket. The run was stopped rather than reported
  green. Earlier cases in that run passed cleartext, decimal/UUID/enum,
  SQLSTATE recovery, MD5, and prepared-NULL coverage.
- G5: project-closure support has landed, but complete MaCSad promotion
  evidence is pending.
- G8: binary HTTP and file-I/O parity support has landed; the new exact
  native-only census classifies only TCP and Serve as unsupported by WASM.
- G9: deep-check mapping support has advanced; the complete candidate gate is
  pending.
- G11: JSON support has advanced, but duplicate object keys are still
  last-write-wins and bounded typed decoding is absent.
- G15: native TCP, HTTP workers, and full-stack build/serve are useful
  substrate, while read deadlines, graceful drain, containment, and production
  lifecycle evidence remain open.
- G17: a real browser reproduction proves each bound-input keystroke replaces
  the active DOM node, losing focus and preventing multi-character entry. A
  focused same-node reconciliation regression and implementation are in local
  TDD and are not admitted evidence yet.

The safe MaCSad integration boundary remains read-only: process health, exact
schema readiness, and a fixed, bounded workspace board query. Database
mutations remain unavailable until authentication, idempotency, expected
versions, command/event/outbox atomicity, cancellation, and bounded failure
behavior are proved. None of these focused results overrides the full promotion
rule.

Status legend:

- **Open** — no candidate yet satisfies the required contract.
- **Partial upstream** — useful implementation or coverage has landed, but the
  required contract remains incomplete.
- **Upstream candidate / promotion pending** — focused upstream work exists,
  but the promotion rule at the end of this document has not passed.
- **Local RED / fix in progress** — a reproducible defect and focused test or
  patch exist locally, but no upstream commit or promotion evidence exists.
- **Closed** — the complete contract passed the promotion rule and was pinned
  by MaCSad. No gap is closed in the current admitted baseline.

The gap bodies below remain the acceptance requirements and admitted-baseline
findings. A status records current evidence; it does not weaken or replace any
required contract.

| Gap | Status |
| --- | --- |
| G1 | Partial upstream |
| G2 | Partial upstream |
| G3 | Partial upstream |
| G4 | Partial upstream |
| G5 | Upstream candidate / promotion pending |
| G6 | Partial upstream |
| G7 | Open |
| G8 | Upstream candidate / promotion pending |
| G9 | Upstream candidate / promotion pending |
| G10 | Open |
| G11 | Partial upstream |
| G12 | Open |
| G13 | Open |
| G14 | Open |
| G15 | Partial upstream |
| G16 | Open |
| G17 | Local RED / fix in progress |

The baseline intentionally uses only framework behavior demonstrated by that
revision. This is the complete gap register found while building Sprint 001.
Each gap is a RED capability gate: it must be fixed in the local source,
regression-tested there, and promoted by updating the exact MaCSad toolchain
lock before MaCSad claims the affected behavior.

All MaCSad product views, state machines, decision functions, research logic,
and publication rules are authored in LOGOS. A small non-LOGOS host may perform
only a capability LOGOS cannot currently express—static byte serving,
authentication/header transport, PostgreSQL calls, process isolation, or a
deployment handoff. Such a host is infrastructure, not an alternative
application layer: it accepts typed commands, contains no MaCSad policy, and
must disappear or narrow when LOGOS gains the capability.

## G1 — typed browser requests

**Status: Partial upstream.** The candidate adds correlated browser requests
with method, body, headers, response status/body, structured error, timeout,
and abort substrate. The complete bounded contract and stable bound-control
behavior are not yet promoted.

The admitted WASM-DOM baseline exposes `fetchText(url, callback)`, which
performs a GET and returns only response text. The candidate's broader request
surface still needs the adversarial and browser evidence below before MaCSad
uses it for commands.

Required contract:

- method, URL, canonical body, and allowlisted headers;
- status, response headers, response body, and structured transport error;
- abort and timeout;
- request body and response size limits;
- same behavior in the browser host and deterministic mock host;
- no implicit retry of an ambiguous mutation; and
- DOM tests proving success, denial, conflict, validation, timeout, abort, and
  malformed-response paths.

The current host also stores one global response body, supplies a constant
callback identifier, and has no rejection path. The new contract must correlate
each response to its request and prove concurrent responses cannot overwrite or
misdeliver one another. Sprint 001 therefore permits only one serialized,
read-only health probe through `fetchText`.

Component-scoped CSS also prefixes an at-rule as
.logos-component @media`, so the browser drops the responsive block. Sprint
001 uses intrinsic flex/grid wrapping and an unscoped LOGOS body reset; an
upstream fixture must preserve `@media`, `@supports`, and keyframes while
scoping only their nested selectors.

The API must support idempotency keys and expected aggregate versions. GET must
remain side-effect free.

## G2 — header-aware LOGOS HTTP

**Status: Partial upstream.** Header transport has advanced, but the trusted,
overwrite-safe identity boundary and the full adversarial contract remain open.

Current LOGOS `Request` exposes method, path, and body. It drops parsed headers
and query values at the language bridge. `Response` cannot set arbitrary headers.

Required contract:

- typed, case-insensitive request-header lookup;
- query access without lossy manual path parsing;
- response headers with a denylist for hop-by-hop headers;
- bounded body parsing and explicit content-type handling;
- propagation of Cloudflare Access identity assertions only through reserved,
  overwrite-safe headers; and
- tests for spoofed identity headers, duplicate headers, oversized input,
  malformed encodings, and response splitting.

## G3 — typed PostgreSQL adapter

**Status: Partial upstream.** PostgreSQL and TCP work has landed as useful
substrate, but it does not yet provide this typed adapter contract. TCP support
alone does not close G3.

The admitted baseline has no PostgreSQL client. The candidate adds a native
wire client with simple and prepared queries, text-format parameters, NULL
masks, typed result getters, transaction/isolation calls, statement timeout,
and cancellation. It is not yet the bounded typed adapter MaCSad requires:

- transport is plain TCP with no require-SCRAM/TLS policy;
- credential-bearing URL options are not a complete typed connection contract;
- connection establishment, protocol frames, result rows, and pools are not
  bounded by the MaCSad caller;
- failed SCRAM authentication can block after the server closes the socket;
- an out-of-band cancel can race and cancel the following query;
- prepared inputs are parallel text/NULL sequences rather than exact typed
  statement records; and
- the example full-stack PostgreSQL list path uses zero-based row indexes even
  though the public getters are one-based, while its lock test substitutes an
  in-memory transform instead of exercising the real handler.

MaCSad therefore permits only a fixed, read-only readiness/board slice with
closed statement text, exact column/name/OID/nullability checks, strict row and
byte caps, a fixed server-owned workspace, generic errors, and guaranteed
connection cleanup. It does not permit browser-supplied SQL or mutations.

The first adapter must be narrow and mechanical:

- prepared statements only;
- explicit transaction boundaries and isolation;
- exact decimal and UUID mappings;
- typed nullable values and PostgreSQL enum mappings;
- statement timeout, lock timeout, cancellation, and pool bounds;
- schema compatibility check through `macsad.schema_version_v`;
- no arbitrary SQL supplied by browser, agent, or workflow payload; and
- integration tests against a fresh PostgreSQL 16 database.

Domain decisions remain LOGOS. The adapter executes reviewed statement IDs and
returns typed rows; it never decides authorization, transitions, or outcomes.

The preferred narrow seam is a LOGOS library exporting typed records, enums,
and decision functions through its generated universal ABI. A small host owns
HTTP authentication and PostgreSQL mechanics, validates the ABI version, and
marshals only typed values. Contract tests must load the real library, exercise
valid, invalid, null, and stale-handle paths, free every returned handle/string,
and compare decisions with LOGOS reference fixtures.

## G4 — routing and navigation

**Status: Partial upstream.** Typed candidate routing exists, but native
history/location, deep-link refresh, and back/forward browser evidence remain
open.

WASM-DOM currently has no native history/location router. The baseline uses
in-memory navigation. Before deep-linkable admin routes ship, LOGOS needs typed
location, push/replace navigation, pop-state handling, safe path parameters, and
browser tests for refresh/back/forward behavior.

## G5 — complete project assembly

**Status: Upstream candidate / promotion pending.** The focused
`closure_lock` regression is green locally; the complete promotion rule still
applies.

`largo test` reads only the entry file. DOM watch mode also reads the entry file
and watches only its immediate directory. Imported test modules can therefore be
missed while the suite reports success.

The runner also executes a server entry point while running each test. A project
whose `## Main` calls `Serve` blocks or collides on its port instead of isolating
its pure tests. The MaCSad wrapper tests the gateway from a temporary copy only
after verifying and removing the exact reviewed `Serve on port 18081` main; a
separate runtime smoke test must still exercise the unmodified gateway.

Required contract:

- serve, check, test, emit, and native build consume the same assembled module
  closure;
- the watcher tracks every file in that closure;
- zero discovered tests and zero-match filters fail;
- the report exposes exact discovered test identities; and
- fixtures prove a nested imported test change rebuilds and reruns.

MaCSad does not hide this gap by invoking `largo test` on a multi-file entry. A
credential-free module audit discovers the exact explicit import graph, rejects
every `src/**/*.lg` file outside both the physical entry closure and logical
application graph, and rejects tests outside registered import-free leaves. The
private-toolchain gate runs `largo check` against the real assembled production
entry, then hard-links each exact test-bearing leaf source as the entry of an
ephemeral zero-skip project. It requires the committed names, nonzero count,
zero failures/skips, finite properties, and proved properties. No source is
copied, flattened, or rewritten to manufacture evidence.

This repository scaffold prevents imported tests from silently disappearing;
it does not close the framework gap. `largo test`, watch mode, runtime smoke,
and every compiler tier must still consume and report one native module closure
before the leaf harness can be retired.

## G6 — honest cross-tier evidence

**Status: Partial upstream.** Candidate AOT/WASM capability classification now
refuses native-only TCP and Serve explicitly, and focused differential coverage
has advanced. Complete cross-tier state/DOM/browser evidence remains open.

Current `--tiers all` checks that VM computation does not raise a runtime error;
it does not compare output, state, DOM operations, AOT, or browser execution.

Required evidence:

- interpreter versus VM exact output and typed-result comparison;
- interpreter/VM/WASM exact DOM-operation comparison;
- AOT differential for supported programs;
- headless real-browser interaction tests; and
- a refusal, never a false pass, for unsupported tiers.

## G7 — deterministic static publication

**Status: Open (unchanged).**

WASM-DOM emits an empty host shell and renders client-side. MaCSad's public site
requires a deterministic static generator that can render sealed publication
input to complete HTML and assets without browser execution.

The generator must build twice to byte-identical output, include no private
endpoint or credential, fail on unclassified content, and emit a signed manifest
covering every public byte.

## G8 — binary HTTP response parity

**Status: Upstream candidate / promotion pending.** Focused binary HTTP and
file-I/O parity fixtures exist upstream, but they have not passed the complete
MaCSad promotion rule.

The interpreter honors the byte payload produced by `bytesResponse`, while the
current native HTTP code generator serializes only the text body. A native
LOGOS service can therefore return different or empty bytes for a WASM or image
response even when interpreter testing is green.

The native generator also leaves `readText` and `readBytes` unresolved in the
generated Rust for the development gateway. A source file can pass the LOGOS
checker and run in the interpreter but fail native compilation when it serves
files.

The Sprint 001 gateway is development-only. Cloudflare Static Assets serves
production frontend bytes. Native LOGOS binary serving remains blocked until a
focused interpreter-versus-AOT regression proves exact status, headers, length,
and body bytes for empty, text, WASM, and arbitrary binary responses, with
working native `readText` and `readBytes` bindings.

## G9 — deep-check stability

**Status: Upstream candidate / promotion pending.** Deep-check source mapping
and regression coverage have advanced in the candidate. The complete candidate
workflow and MaCSad promotion gate are not green yet.

On the pinned source revision, `largo check --deep` panics in
`apply_prelude` with the invariant that the prelude must prepend before span
translation. The supported `largo check --json` path, test runner, and
WASM-DOM emitter do not hit this panic for the Sprint 001 applications.

The baseline gate runs the supported checker and reports no deep-check evidence.
Deep checking becomes required only after an upstream regression fixture proves
that every MaCSad entry file completes without panic and produces stable,
source-mapped diagnostics.

## G10 — local dependency linking

**Status: Open (unchanged).**

`Largo.toml` accepts dependency entries using version, path, or Git forms, but
the inspected project assembly does not link those declarations into the
compiled LOGOS program. `## Requires` resolves a crates.io package and is AOT
specific; it cannot name the local private workspace closure MaCSad requires.
Treating either syntax as a working local dependency would be a false build.

Sprint 001 therefore has no application dependency table and invokes the exact
local `target/debug/largo` through `scripts/logos.sh`. Required upstream work:

- path dependencies must resolve relative to a canonical project root;
- Git dependencies must require an exact commit and preserved source closure;
- local package identity, feature selection, and transitive closure must appear
  in a machine-readable build manifest;
- interpreter, VM, test, emit, and AOT must consume the identical closure; and
- fixtures must prove that registry access is unnecessary and disabled for a
  fully local build.

No MaCSad change may add `## Requires`, a registry LOGOS crate, `cargo install
largo`, or a floating local checkout as a workaround.

Exact d9 source review adds two generated-native-build requirements, without
claiming that the older dependency-linking findings still describe every newer
API. `apps/logicaffeine_cli/src/project/build.rs` stages local runtime sources
when `LOGOS_WORKSPACE` is bound, but emits semver dependencies such as `tokio =
"1"` and invokes Cargo without `--locked` (lines 431–549). An offline locked
compiler build is therefore not proof of a locked generated application.
Retain the generated Cargo.lock and source/runtime manifest, then require an
explicit locked-offline rebuild and unchanged identities for application
evaluation. Do not infer deployment reproducibility from a successful compile.

The same file's stable-artifact copy is best-effort (678–712), while its returned
binary path does not follow `CARGO_TARGET_DIR`. With a nondefault target directory,
verify the actual built binary and any copied artifact byte-for-byte; do not trust
an old stable file or infer that `largo run` will execute the new output. This
remains a source-scoped G10 handoff, not an upstream patch or a promoted workaround.

## G11 — typed structured data

**Status: Partial upstream.** JSON support and conformance coverage have
advanced, but duplicate-key handling, bounded decoding, and total typed
decoding do not yet satisfy this contract.

The pure-LOGOS JSON parser on the pinned revision can represent a `JStr`
variant, but the parser surface inspected for Sprint 001 does not correctly
cover ordinary JSON objects and strings, negative numbers, decimals, escapes,
or robust rejection of trailing/invalid input. Arrays, positive integers,
booleans, and null are not enough for command envelopes, attestations, or
publication manifests.

Required contract:

- RFC-compatible parsing and deterministic canonical serialization for the
  admitted JSON profile;
- total, typed decoding into LOGOS records and tagged enums;
- duplicate-key, depth, size, Unicode, number-range, invalid-escape, and
  trailing-input rejection tests;
- exact round-trip and malformed-input properties; and
- no authorization or money decision based on an untyped JSON field.

Until this is green, a host may decode a versioned transport envelope and
marshal typed ABI values, but LOGOS still validates and decides the command.

## G12 — genuine engine differentiation

**Status: Open (unchanged).**

The MCP `logos_run` labels `tw` and `vm` are not reliable differential
evidence. On the inspected source, the two paths can reach the same synchronous
VM/JIT routine, and that routine may silently fall back to the tree walker.
Selecting two labels can therefore execute one engine twice.

Required contract:

- strict tree-walker and strict VM modes that never silently substitute;
- a reported engine identity in structured output;
- exact outcome, stdout, error, and state comparison;
- explicit refusal when a program is unsupported by one tier; and
- host-level regression tests using the real tree-walker and VM seams.

`LOGOS_ENGINE_TRACE=1` can help diagnose a run but does not by itself prove
cross-engine parity.

## G13 — proof semantics and non-vacuity

**Status: Open (unchanged).**

`largo test --prove` proves supported finite `For all` properties. It does not
prove every `## Theorem`; theorem and axiom declarations are not automatically
executed as test obligations. A test with no `Expect`, a tautology, zero
discovered tests, or an unselected live test can look green without proving the
intended rule.

MaCSad's wrapper currently locks exact test names, requires nonzero tests,
zero skips, nonzero finite properties, and nonzero proven properties. Upstream
must additionally provide:

- a machine-readable inventory separating examples, properties, theorems,
  axioms, and admitted assumptions;
- failure for vacuous/no-assertion tests and zero-match filters;
- explicit theorem proof status with no theorem/axiom name collision;
- bounded-domain disclosure and counterexample output; and
- a proof certificate or independently checkable evidence format for claims
  that exceed executable finite testing.

Finite enumeration remains valuable testing evidence; it is not silently
promoted into an unrestricted mathematical proof.

## G14 — honest external-tool preflights

**Status: Open (unchanged).**

Some upstream Rust tests print `SKIP` and return from an ordinary test when an
AOT toolchain or Node is unavailable, causing Cargo to report PASS. The
WASM-DOM emitter test can omit JavaScript syntax validation when Node cannot
start. The HTTP differential is ignored by default. A default green Cargo run
therefore does not establish AOT, browser, Node, or HTTP parity.

Required contract:

- required executables and exact versions are preflighted and missing tools
  fail the selected gate;
- optional capability skips are machine-readable and counted against an
  explicit zero/default budget;
- ignored differentials are selected explicitly by the release gate;
- emitted browser files are executed in a real pinned browser; and
- CI reports which tiers and external validators actually ran.

## G15 — production server and lifecycle

**Status: Partial upstream.** TCP, HTTP workers, and full-stack build/serve are
useful substrate, but readiness, drain, cancellation, read deadlines, bounded
backpressure, static containment, and the production lifecycle contract remain
open. TCP support alone does not close G15.

`largo serve --watch` is an interpreter development facility, not production
evidence. On the pinned revision it does not assemble/watch the same imported
closure as all other commands, the language HTTP boundary lacks authentication
headers, and binary/AOT parity is open. There is also no native graceful
shutdown, readiness/drain, structured request cancellation, or proven
backpressure contract suitable for the MaCSad control plane.

Required contract:

- one assembled source closure across serve/test/build;
- separate liveness and dependency-aware readiness;
- bounded concurrency, request body, response body, time, and memory;
- graceful drain and cancellation without double-committing effects;
- structured correlation/causation identifiers and secret-safe logs; and
- restart, overload, malformed-request, and in-flight-shutdown tests.

Sprint 001's LOGOS gateway exposes only an honest read-only health response on
loopback. It does not claim production CRUD.

## G16 — nested Component scope attribution

**Status: Open (unchanged).**

The pinned scope checker can attribute a function call inside an imported
Component body to the entry `main.lg` rather than the Component's defining
module. A valid local chain such as entry → application Component → policy can
therefore fail with a claim that the policy function is not imported by the
entry, even though the Component imports it correctly.

MaCSad preserves the proper local dependency edges and temporarily requires the
entry to import every non-entry module exactly once. The module audit treats
these entry edges as a named `pinned-transitive-scope-workaround`, then
independently traverses from the registered logical root. A module reachable
only from the redundant entry closure fails as decorative/orphan code. This is
compiler compatibility scaffolding, not flattened architecture.

The redundant entry edge to each transitive policy/routing leaf currently emits
an `unused-import` warning. The module manifest allowlists only the exact warning
code, severity, entry file, and import-alias message observed for that required
edge. A missing, additional, moved, renamed, or reworded diagnostic fails the
gate; warnings are recorded compatibility evidence, not globally suppressed.

Required upstream contract:

- scope attribution uses each assembled source segment's defining module,
  including nested Component Views, event bodies, signals, and interpolations;
- a transitive local import succeeds without an entry-level duplicate;
- a genuine transitive scope leak still fails at the correct source file;
- component, function, type, selective-import, and private-name fixtures agree
  across check, interpreter, VM, WASM-DOM, and AOT; and
- removing the duplicate entry imports produces no diagnostic or behavior
  change after the fixed toolchain is promoted.

## G17 — stable bound-control DOM reconciliation

**Status: Local RED / fix in progress.** A real browser reproduction on the
candidate proves that the first input event replaces the active input node.
Focus and selection are lost, so sequential typing stops after one character.
This is LOGOS host reconciliation behavior, not a Codex browser renderer issue.

A focused regression must prove all of the following while a bound signal and
the surrounding view update live:

- the connected input remains the exact same DOM node across multiple input
  events;
- focus, selection direction/range, and horizontal scroll remain intact;
- the bound value and derived text update after every character;
- unrelated page/navigation state remains unchanged;
- framework-managed handlers are refreshed without duplicate callbacks;
- compatible text, attributes, style, and children patch in place while stale
  children and handlers are removed; and
- the generated host passes deterministic DOM coverage plus a real-browser
  interaction on the admitted WASM bundle.

The first real-WASM form fixture also exposed an independent candidate emitter
failure: V8 rejected the generated module because one call expected `i32` and
received `i64`. The reconciliation test is being kept narrow with a
deterministic host ABI fixture; a separate exact compiler regression is required
before the real-WASM browser gate can close G17.

## Promotion rule

A gap closes only when all of the following are true:

1. the fix exists in the local `logicaffeine-private` source;
2. a focused regression fails before the fix and passes after it;
3. an adversarial or negative fixture covers the original false-green path;
4. the relevant interpreter/VM/WASM/AOT/browser tiers are named and actually
   run rather than inferred;
5. MaCSad's quality gate is updated without weakening an existing assertion;
6. the source commit, tree, Cargo lock, `largo` binary, and required runtime
   closure are promoted to a new reviewed lock; and
7. the MaCSad sprint using the capability pins that new lock.

Prose, a successful parser check, an unselected ignored test, a registry crate,
or a local uncommitted patch does not close a gap.
