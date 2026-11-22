# MaCSad on latest LOGOS: comprehensive Lean→LOGOS + a distributed, self-improving math factory

## Context
RSI House hack #7: build a *closed autonomous loop* that keeps working after the hack — humans **on**
the loop, memory from the start, the loop checks itself. For mathematics the self-check is the
**LOGOS kernel**. MaCSad already holds the right ideas (evidence before belief, Investigator ≠
Verifier, math-discovery flow `macsad/design_document.md:636`), but its code is old (LOGOS 0.10.1,
Python host adapters). We rebuild it **fully in LOGOS** on the latest local logicaffeine (HEAD
`595714c`, 0.11.0+, unreleased OK) as an open, distributed proving network:

- anyone runs a container with **their own OpenRouter key + budget** (key never leaves their machine);
- workers **pick problems off a shared board** via leases — no repeated work;
- every attempt is appended to a hash-chained **problem trail** (what was tried, model/strategy, kernel
  verdict, why it failed) that the next attempt reads first — the RSI memory;
- agents write **LOGOS-native proofs**; the **LOGOS prover is their tool**; the **LOGOS kernel** decides;
- problems come from Alejandro's organization; Lean statements reach LOGOS through a
  **comprehensive Lean→LOGOS translator** (new versions, Mathlib, statements and proofs);
- results land in a git results repo and on **macsad.com** (Cloudflare) as a hierarchical graph over the
  OPDP atlas, showing stage, rank and solved status.

User decisions: fully LOGOS · LOGOS kernel = truth · LOGOS-native proofs · comprehensive Lean→LOGOS ·
add `process.lg` native now · RSI = strategies auto-evolve, kernel/policy frozen · containerized +
Cloudflare (macsad.com, R2) · intake: formal-conjectures + Alejandro's 200 + OPDP atlas, more lists as
adapters · no OpenRouter key yet (replay provider until then).

## Ground truth (read from code)
- **OPDP atlas** (github `alejandrozu/ulam-opdp-difficulty-atlas`): remote main **v1.8 = 102,819
  records** (UnsolvedMath 15,458 + MathDB 87,105 + ProofAtlas 256); local clone v1.2 (5,426) at
  `logicaffeine/external/ulam-opdp-difficulty-atlas`. Per record: difficulty T1–T5, AI fit, tractability
  T0–T10 + progress probability, formalization/verification burden, tool leverage, route, category,
  collection, cohort, catalog_status; key = numeric `problem_id` (keep null≠0, T namespaces separate).
- **formalization-lab** 200 pinned open statements: `logicaffeine/logs/alejandro200/references/formalization-lab/open-problems/manifest.json`.
- **formal-conjectures** built w/ Mathlib, Lean 4.33.1: `logicaffeine/logs/alejandro200/references/formal-conjectures`
  (~1.4k open / 1.7k solved / 1.8k test / 176 textbook; 529 files use `answer(sorry)`).
- **Alejandro's 248-case Lean 4.14 conformance corpus**: `logicaffeine/work/alejandro` (T00–T12).
- **LOGOS app stack**: `## Route`s, sessions/CSRF, derived JSON codecs, `Serve`, LGX `## Page` → WASM,
  `largo serve|build --release` one binary (`docs/web.md`, `docs/frontend.md`, `examples/fullstack_todo`).
  Std (`crates/logicaffeine_compile/assets/std/`): `postgres.lg`, `tcp.lg` (+`tcpConnectTls`), `json.lg`,
  `crypto.lg` (sha256, hmacSha256, ML-DSA), `file.lg` (read/write only), `env.lg`, `time.lg`, `uuid`,
  `regex`, `strings`; tasks/pipes (`--threads` for real parallelism); libp2p `Sync`/`Mount`.
  **Missing**: subprocess, file append/list/mkdir, native HTTP client (browser `Get/Post` only),
  Cloudflare Worker target, in-process kernel calls.
- **Kernel/prover**: kernel vernacular (`Inductive/Definition/Theorem … := by <tactics>`, `Print Axioms`),
  tactics (intro/apply/cases/induction/rw/simp/calc/decide/ring/omega/linarith/crush/auto),
  `largo check --kernel --json`, `largo prove --json --certificate` (`commands/prove.rs:282-380`),
  `recheck`, `largo sat --proof`, `largo mcp` (6 tools, `apps/logicaffeine_cli/src/mcp/tools.rs`).
  Prelude: Nat, Int (+laws), List, Option, Prod, Sum, Sigma, Subtype, Fin, Array, Setoid; no Real/Set/Finset.
- **Lean bridge today**: `largo lean check [--dual]` (dag core) checks Mathlib in ~400 G instr vs Lean's
  11.6 T (67–320 s vs 2,610 s), accepts 4.33.1 exports, but no axiom policy, no statement binding, no
  cache. `largo lean import` is pinned to Lean 4.14 (`interface/lean/intake.rs:38-44,269-285`), refuses
  Lake deps (`commands/lean/project.rs:372-414`), declines nondep lets (`interface/lean/metadata.rs:63-69`),
  has no statement-only mode. Unmerged candidate (nondep + statement packages):
  `logs/alejandro200/statement-current-api-payload-20260928/{kernel,cli}/composed.patch`,
  notes `work/alejandro200/PROGRESS_20260927.md` (0 statement packages completed).
  Structural lean4export builds: `logs/alejandro200/references/lean4export-{4.28,4.33.1,4.34.0-rc1}-structural/`.
- **logicaffeine rules** (`CLAUDE.md`): no git, TDD RED→GREEN, never modify red tests, one test suite at
  a time (`./scripts/run-all-tests-fast.sh` for full), start and end all-green. Shared tree with other
  sessions → build into our own `CARGO_TARGET_DIR` (e.g. `/mnt/build/macsad-target`), heavy runs under `~/bin/guarded`.

## Track S — LOGOS std additions (logicaffeine; unblocks everything)
Pattern for natives: impl in `crates/logicaffeine_system/src/<mod>.rs` → interpreter seam
(`crates/logicaffeine_compile/src/interpreter.rs` ~10567) → AOT map (`codegen/program.rs` ~3763) → C
runtime refusal/impl → `SYSTEM_NATIVES` in `crates/logicaffeine_tests/tests/native_kernel_lock.rs`;
honour `testworld` sealing (`logicaffeine_system/src/testworld.rs`).
- **S1 `std/process.lg`**: `## To native runProcess (program: Text) and (args: Seq of Text) and
  (cwd: Text) and (env: Map of Text to Text) and (timeoutMs: Int) and (maxOutput: Int) -> Result of
  ProcessResult and Text` (`exitCode`, `stdout`, `stderr`, `timedOut`, `truncated`); own process group,
  kill group on timeout, no shell. Cross-tier lock tests (tree-walker/VM refusal policy/AOT), timeout,
  output cap, sealed-test behaviour.
- **S2 `file.lg`**: `append`, `exists`, `listDir`, `makeDirs`, `rename` (atomic write = write tmp + rename),
  wired the same way (Rust side already in `logicaffeine_system/src/fs/mod.rs:132-147`).
- **S3 `std/httpclient.lg`** (pure LOGOS over `tcpConnectTls`): `httpsRequest(method, url, headers, body,
  timeoutMs) -> Result of HttpReply and Text`; Content-Length + chunked decoding, redirects off, header
  validation reusing `http.lg` guards. Tests against a local TLS server as in `tests/tcp_tls_natives.rs`.
- **S4 `std/s3.lg`**: AWS SigV4 (sha256/hmacSha256/urlEncode) PUT/GET for R2 (`UNSIGNED-PAYLOAD`), vector tests.

## Track L — comprehensive Lean→LOGOS translator (logicaffeine)
Goal: any declaration of any supported Lean version, in any Lake project (incl. Mathlib) → LOGOS literate
document + certificate package, for **proofs (/1)** and **statements (/2)**, at Mathlib scale, every
stage receipted, replayable, independently rechecked.
- **L1 Version profiles**: replace the single Stage-A pin with a versioned profile registry (toolchain,
  lean4export rev + structural patch hash, export format 3.x) for 4.14.0, 4.28.0, 4.33.1, 4.34.0-rc1,
  4.34.1; exporter registry `~/.logos/lean/exporters/<ver>/` built reproducibly from the structural
  sources (build script + receipt); `--project` selects the profile from `lean-toolchain`.
- **L2 Lake dependency projects**: accept pinned `lake-manifest.json` deps (Mathlib): verify manifest
  identities, isolated copy using the project's prebuilt `.lake` (or `lake exe cache get`), build only
  the target module, record dependency identities in the receipt.
- **L3 nondep let**: implement the elaborator-have translation contract (agrees with dag core
  `dag/export.rs:905-910`), porting from the composed candidate; RED tests from the five recorded refusals
  (OP175 line 4334, OP197 3797, OP198 3882, OP199/200 3747).
- **L4 Statement packages (/2)**: `largo lean import --statement`: source-bound theorem-type selection,
  Prop-def value preservation, unfinished-dependency disclosure (OP133/144/184), `answer(sorry)` as an
  open template, strict /2 contract, replay + tamper controls; proof path /1 unchanged.
- **L5 Scale + library packages**: streaming intake (no whole-file read / 1 GiB cap), hash-consed DAG
  import, `THREADS` parallel checking; **library package mode** — translate a whole closure (all of
  Mathlib at the formal-conjectures pin) once into sharded `.lg` + `EnvironmentCertificate`; later
  imports reference it by hash instead of re-checking (incremental). Measured budgets, no silent quotas.
- **L6 `largo lean check` policy**: add `--assumptions lean` (allow only propext/Quot.sound/Classical.choice,
  refuse sorryAx/ofReduceBool/trustCompiler), `--bind <orig> <new>` statement binding, `--json` output.
- **L7 Prover reach**: LOGOS tactics (`omega/ring/decide/simp/crush`) recognize translated Lean
  arithmetic (instance-wrapped `HAdd`/`HMul`/`LE` over prelude Nat/Int unfold to prelude ops); exporter
  extension to emit `@[simp]`/instance attributes so `simp` can use translated Mathlib lemma sets.
- **L8 Conformance ledgers**: 248-case corpus (T00–T12), the 200 statements (target 200/200 /2 packages
  replayed), a formal-conjectures solved/test sample (/1), arena agreement with `largo lean check`.
  Every refusal is a typed diagnostic; ledgers are regression-locked tests.

## Track F — MaCSad factory, fully in LOGOS (macsad repo)
- **F0 Re-pin**: `macsad/.macsad/toolchains/logos.lock.toml` → local HEAD build (sha256-pinned,
  `LOGOS_WORKSPACE=/home/tristen/logicaffeine` so compiled builds use local crates); update
  `scripts/logos.sh`. Old `logos/{gateway,admin,public-site,proof-worker,corpus}` and Python
  `host_adapters/` are superseded by the new project and retired once it covers them.
- **F1 Project `macsad/logos/factory/`** (one binary, role from `args()`: `coordinator | worker | verifier |
  ingest | local`). `src/shared.lg` records: Problem, Node, Statement, WorkUnit, Lease, Attempt,
  TrailEntry, Lemma, Strategy, Verdict, Contributor (derived JSON codecs = the wire contract). Costs in
  integer micro-dollars (JSON decoders handle Int/Bool/Text/Record).
- **Stages** (per node state machine):
  1. *Triage/Rank* — adapters: OPDP v1.8 (download release payload; gunzip via `runProcess`),
     formal-conjectures, formalization-lab 200 → hierarchy cohort → collection → category → problem.
     Rank (scheduler priority, never an agent reward) from progress-probability, AI fit, tool leverage,
     ↓formalization/verification burden, LOGOS expressibility, formal-statement availability, trail
     signals (verified progress ↑, repeated identical failures ↓), contributor focus. Cross-links
     (Erdős #/title/source) with ambiguous matches as `link` units.
  2. *Formalize into LOGOS* — route A: Lean statement → `largo lean import --statement` (Track L).
     Route B: informal-only → LLM writes a Lean statement, then route A. Route C (day one, before L lands,
     and for prelude-fragment problems): LLM writes kernel vernacular directly. Gates: `largo check
     --kernel --json` clean, no admissions in the statement, **independent semantic review** by a
     different model with fresh context (≥2 agreeing), triviality smoke test (instant `decide/omega/crush`
     ⇒ suspicious). A mechanical route-A statement supersedes an LLM one, with a correspondence check.
  3. *Progress* — units: `prove`, `decompose` (lemma DAG; parent checks modulo child `Axiom`
     placeholders, each child a node), `special_case` (bounded n ≤ N by `decide`), `counterexample`
     (`largo sat --proof` / `logos_run`; refutation = kernel-checked negation), `repair` (with kernel
     diagnostics), `summarize_trail`. Context = LOGOS statement document + trail digest + verified-lemma
     library + strategy playbook + LOGOS tactic reference. Tools = `largo prove/check --kernel`, `largo mcp`.
  4. *Solved* — the trusted verifier re-runs `largo prove --kernel --json --certificate` in a pinned
     image, requires every block checked, `Print Axioms` ⊆ {propext, Quot.sound, Classical.choice},
     `recheck` two-kernel agreement, and statement hash = accepted statement hash; emits an
     ML-DSA-signed attestation → `proved`/`refuted`/`partial`; results repo commit (git via `runProcess`)
     + R2 artifacts; graph node turns green. Human review is a separate on-the-loop flag.
- **Trail + dedup**: `trail_entry` append-only with `prev_hash` chain per problem (fields above);
  coordinator alone creates units; one live lease per unit (TTL, heartbeat, fencing token — macsad's
  `lean_advance` semantics); `approach_fingerprint` = sha256(kind, statement hash, strategy, normalized
  tactic skeleton) — duplicate failed fingerprints refused; global lemma library deduped by statement hash.
- **Tokens in**: `docker run -e OPENROUTER_API_KEY -e MACSAD_BUDGET_USD=5 [-e MACSAD_FOCUS=…]
  macsad/worker`; pre-call worst-case reservation from OpenRouter `/api/v1/models` pricing, reconcile from
  `usage`; honest stop at budget (trail entry); spend reported, key never sent. Providers: `openrouter`,
  `replay` (recorded fixtures), `mock`.
- **RSI**: `strategy` = versioned data (prompts per unit kind, attack mix, context rules, model per
  stage); calibration ladder (formal-conjectures test/textbook/solved translated via Track L, plus the
  248-case corpus with proofs stripped); `improve_strategy` unit proposes a mutated playbook → budgeted
  calibration batch → promoted only if it beats the incumbent (bandit), audit + rollback. Checker,
  acceptance rules, budget caps, LOGOS code: not agent-editable. Aggregated translator refusals form a
  ranked "toolchain gap" queue for Track L.
- **Coordinator**: Postgres via `postgres.lg` (new `database/migrations/0004_factory.sql`: problem,
  node, statement, work_unit, lease, attempt, trail_entry, lemma, strategy, strategy_eval, contributor,
  attestation); `## Route`s `/api/v1/{lease,heartbeat,attempt,trail/:id,problems,graph}`.
- **Website** (LGX pages served by the coordinator): `/` hierarchical atlas graph (aggregates at upper
  levels, lazy-loaded children, colour = stage, order = rank), `/problem/:id` (OPDP profile, statements,
  lemma DAG, trail timeline, certificates), `/board`, `/contribute` (docker command + focus picker),
  `/leaderboard`.
- **Containers + Cloudflare** (`macsad/ops/compose`): `postgres`, `coordinator`, `verifier`,
  `cloudflared` (macsad.com tunnel → coordinator); `ops/worker/Dockerfile`: Lean toolchains + exporters
  (Track L), formal-conjectures + Mathlib cache, LOGOS `largo` + factory binary. R2 via `s3.lg`.
  (No LOGOS Worker target exists, so the edge is Tunnel + R2, with optional `largo build --static` for Pages.)

## Execution order (S unblocks F; L runs alongside)
1. S1–S3 TDD in logicaffeine → own pinned build. 2. F0–F1 + `macsad local` with Route C: **milestone =
replay provider drives an attempt → `largo prove --kernel` verifies → trail + results repo entry**; then
real OpenRouter key. 3. L1→L3→L4 (formal-conjectures statements start flowing into route A), then L6,
L5, L7, L8. 4. Coordinator + worker container + verifier + tunnel + R2 (S4). 5. Atlas ingest + website.
6. RSI loop. Subagents can split S/L (logicaffeine, one test suite at a time, shared lock) and F (macsad).

## Verification
- logicaffeine: RED/GREEN per feature; targeted `cargo nextest run -E 'test(<name>)'`; full
  `./scripts/run-all-tests-fast.sh` before/after each track step (one suite at a time, under `guarded`).
- Translator: ledgers — 248-case verdicts, 200/200 statement packages with `largo lean replay`, tamper
  controls fail, OP175/197–200 pass the nondep stage; `largo lean check --assumptions lean` rejects a
  sorry-backed proof.
- Factory: `largo test` in `logos/factory` (route-table tests, page tests, sealed time/files). E2E
  `macsad local --provider replay`: a correct proof → `verified`; a wrong proof → `rejected` with
  diagnostics; an unsupported Lean feature → typed refusal in the trail; budget exhaustion → honest stop
  (Alejandro's roadmap demo set).
- Distributed: `docker compose up` → worker container leases a unit, posts an attempt, verifier re-checks
  and signs, macsad.com graph shows the node green with its trail, results repo has the commit.

---

## Status — 2026-11-22 (work in progress, pushed mid-hack)

Landed and verified:

- **Track S (LOGOS std, in the local logicaffeine tree — uncommitted there):** `process.lg` (`runProcess`: bounded,
  no shell, process-group cleanup, empty stdin, sealed in `## Test` unless `This test may use the real processes.`),
  file.lg `appendFile`/`fileExists`/`listDir`/`makeDirs`/`renameFile`, `httpclient.lg` (HTTP/1.1 + TLS in LOGOS,
  live 200 from openrouter.ai), `s3.lg` (SigV4 for R2, AWS vectors exact). Lock tests: `process_natives` (24),
  `file_ops_natives` (13), `httpclient_lock` (14), `s3_sigv4_lock` (4), plus the ratchets/goldens they touch.
  Known pre-existing failures not caused by this work: `builtin_overloads` makeMoment overflow (debug build),
  `item_growth_lock` accumbound guard.
- **Coordinator schema:** `database/migrations/0004_factory.sql` (schema `factory`) applied by
  `database/apply_migrations.sh` on PG16 with verification at schema version 4; invariants in
  `database/tests/0004_factory_invariants.sql` pass (hash-chained append-only trail, fenced leases, dead-end dedup,
  solved-needs-attestation, immutable statements).
- **Factory (`logos/factory/`, lands in a follow-up PR once it passes the LOGOS source-quality lint):** shared records, trail hashing, OPDP ranking, formal-conjectures/OPDP ingest,
  OpenRouter request/response + pricing, replay provider, kernel verdict parsing, submission integrity checks
  (no redefinition of existing names — see `LOGOS_ISSUES.md` #2), prompts with a LOGOS tactic reference; roles
  being wired.
- **Data:** OPDP atlas v1.8 payload (102,819 records, 62 MB gz) fetched into `.runtime/factory/data/`.

In flight: the `factory local` end-to-end loop and worker/verifier roles; the coordinator API + LGX website
(hierarchical atlas graph); the comprehensive Lean→LOGOS translator in logicaffeine (version profiles 4.14→4.34.x,
Lake/Mathlib projects, nondep let, statement packages); containers (`ops/factory/`) and the Cloudflare tunnel.

Toolchain note: the factory builds LOGOS from the PUBLIC repository (github.com/Brahmastra-Labs/logicaffeine) at the
exact commit in `ops/factory/logos.pin` (`ops/factory/build.sh` → `ops/factory/bin/toolchain.receipt.json`), never from
the private repository. The std additions the factory needs (`process.lg`, file ops, `httpclient.lg`, `s3.lg`) must be
published there first; `build.sh` refuses a pinned revision without them. The original MaCSad projects keep their
0.10.1 lock until a promotion through `docs/runbooks/upgrading-logos.md`.
