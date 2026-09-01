# LOGOS gaps and required framework gates

MaCSad pins the **local** `Brahmastra-Labs/logicaffeine-private` source at
LOGOS `0.10.1`, commit `132dc5346728e2d204df798dd7544e6405306a2c`,
tree `9f251ad38ed49834d8224bbf6b928cb5ba1aa1c5`. The build wrapper rejects
another commit, tree, Cargo lock, `largo` binary, dirty tracked source, or
unrelated origin. MaCSad does not install or resolve LOGOS from crates.io.

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

Current WASM-DOM exposes `fetchText(url, callback)`, which performs a GET and
returns only response text.

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

LOGOS has no PostgreSQL client or linked local path dependency implementation.

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

WASM-DOM currently has no native history/location router. The baseline uses
in-memory navigation. Before deep-linkable admin routes ship, LOGOS needs typed
location, push/replace navigation, pop-state handling, safe path parameters, and
browser tests for refresh/back/forward behavior.

## G5 — complete project assembly

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

Current `--tiers all` checks that VM computation does not raise a runtime error;
it does not compare output, state, DOM operations, AOT, or browser execution.

Required evidence:

- interpreter versus VM exact output and typed-result comparison;
- interpreter/VM/WASM exact DOM-operation comparison;
- AOT differential for supported programs;
- headless real-browser interaction tests; and
- a refusal, never a false pass, for unsupported tiers.

## G7 — deterministic static publication

WASM-DOM emits an empty host shell and renders client-side. MaCSad's public site
requires a deterministic static generator that can render sealed publication
input to complete HTML and assets without browser execution.

The generator must build twice to byte-identical output, include no private
endpoint or credential, fail on unclassified content, and emit a signed manifest
covering every public byte.

## G8 — binary HTTP response parity

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

On the pinned source revision, `largo check --deep` panics in
`apply_prelude` with the invariant that the prelude must prepend before span
translation. The supported `largo check --json` path, test runner, and
WASM-DOM emitter do not hit this panic for the Sprint 001 applications.

The baseline gate runs the supported checker and reports no deep-check evidence.
Deep checking becomes required only after an upstream regression fixture proves
that every MaCSad entry file completes without panic and produces stable,
source-mapped diagnostics.

## G10 — local dependency linking

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

## G11 — typed structured data

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
