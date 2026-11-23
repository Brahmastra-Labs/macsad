# LOGOS 0.11.0 promotion record: public toolchain

This branch moves the MaCSad frontend to LOGOS 0.11.0 (LGX Components, Views,
scoped styles, Pages, typed HTTP callbacks). It also proposes a toolchain lock
for the public `Brahmastra-Labs/logicaffeine` source. The lock is a candidate
until the reviewed promotion merges. Compiling the applications does not
establish a deployment.

## Target identity

| Field | Value |
|---|---|
| Authorizing request | User, through the coordinating session: promote to public `main` |
| Repository and origin | `Brahmastra-Labs/logicaffeine`, `https://github.com/Brahmastra-Labs/logicaffeine.git` |
| Version | `largo 0.11.0` |
| Commit | `c67b633d102b6c4f00715129c22f20cbabb94262` (PR #40, std process/file/HTTP/S3) |
| Tree | `43416c35b8eba40fd1f39d3280df4d6c80d9b112` |
| `Cargo.lock` SHA-256 | `1c53ac62fa3af819cb0a55c1e4575415ce1d6421cdf839f15dbb74dfc0c4b213` |
| `target/debug/largo` SHA-256 | `7fbea20a44e215d89c4e52770a3837ab913f968b6595a04b8a739fa720e45118` |
| Build | `cargo build --locked -p logicaffeine-cli --bin largo`, rustc/cargo 1.96.0, x86_64 Linux |
| Previous lock | `logicaffeine-private` 0.10.1, `132dc5346728e2d204df798dd7544e6405306a2c` |
| Rollback | Revert the promotion commit; the 0.10.1 lock returns from Git history |

The checkout was a fresh clone with `origin` set to the public URL and detached
at the exact commit. `target/` is ignored there, so
`git status --porcelain --untracked-files=all` stayed empty after the build.
One debug build was made. Byte-reproducible compiler builds are not claimed.

The first candidate was public `8ce95bd31f92a75670cc6e003c48a664b795e433`
(tree `05c21c8cce573ca60539151c9e4392fcae502ce3`, same `Cargo.lock`, binary
`580dd79e57c2e86c36662906735672926a9d2e11ef9785e1914700fc847ff72c`). It
lacked the std modules the factory needs. The lock was moved to `c67b633d`
when that commit reached public `main`, and the gate was rerun there.

## Commands and results at `c67b633d`

Every command ran from the MaCSad root (rebased on `main` `936aa63`) with
`LOGOS_WORKSPACE=<public checkout>`, one LOGOS suite at a time.

On this host, `make test` stops at its host-adapter step for the environment
reason under "Not established". To get evidence past that point,
`scripts/quality-gate.sh` was then run with only its two process-spawning
steps removed: the host-adapter discovery and the proof-loop contracts. That
run exited 0 and printed "PostgreSQL evidence: not-run."

- **Credential-free contracts** (the Foundation CI step, verbatim):
  `node --test` ran 236 tests, 236 passed, 0 skipped. Guardrails, the module
  audit, the source lint (189 files, 0 debt items), the Compose guardrails, the
  Firebat2 contract and the data-worker contracts passed. The PG16 unit tests
  ran 8 and passed. The host-adapter discovery passed 124 of 125; see "Not
  established".
- **`largo fmt --check`**: all six projects pass.
- **`node scripts/verify-logos-tests.mjs`**: exit 0. `largo check --json`
  reports exactly the registered diagnostics for every project. All 63 suites
  ran 209 tests: 209 passed, 0 failed, 0 skipped, 58 properties proved. The
  frontend share is 20 suites and 65 tests, with 19 proved:
  - admin: 3 leaves and `pages/admin.lg` (3 mounted, VM-agreed).
  - public-site: 2 leaves.
  - gateway: 3 leaves and `pages/lean.lg` (3 mounted, VM-agreed).
  - proof-worker: 5 leaves.
  - corpus: 5 leaves.

  The factory share is 43 suites and 144 tests, with 39 proved. Its sources
  and manifest entry are byte-identical to `main`.
- **Deterministic WASM-DOM**: admin and public-site were each emitted twice,
  and both inventories matched. Bundle manifest SHA-256:
  - admin: `8d8c094acead7919f259b0a397c3745224beaa979a6f00752e65ef67d3f940ca`
  - public-site: `f07e85f8505b2e0e012939a6ea6d110d445503caa3ab6858223ad61eb40bf4b4`
- **PostgreSQL**: not run, because `DATABASE_URL` was unset. No database
  behavior changed.

### Supplementary browser observations

These checks are not the gate, and they are not the Firebat2 browser contract.

- `largo test --browser` with headless Google Chrome 154 ran byte copies of the
  two Page closures and the `research_selection` leaf. All 9 tests passed on
  the lowered-VM and browser tiers.
- The emitted admin and public bundles were served on loopback and rendered in
  headless Chrome. Admin shows six lanes, two example cards, "The board has 6
  phases." from the policy-bound root, and the terminal Closed rule. Public
  shows no administrative control.
- A scratch copy of `scripts/ci/browser-probe.mjs` passed both interaction
  contracts. The copy accepted a "Google Chrome" version string and used
  longer CDP timeouts. The checked-in smoke needs a root-owned
  `/usr/bin/chromium`, which this host lacks, so it did not run.

## Application changes

- **Pages cannot import tested modules.** A Page's test run also runs its
  import closure's tests and refuses those that call functions (LOGOS_GAPS
  "G5 (observed)"). The admin Page therefore mounts `AdminShell`, a
  presentation shell with no policy imports, and passes the policy outcomes in
  explicitly. The production root `MacsAdAdmin` (`src/admin_app.lg`) binds
  `kanbanColumnCount()` and `closedAcceptsOrdinaryWork(false)` from the tested
  leaves to the same shell. No test was removed. The Page lists only its own 3
  tests, and they now also assert the terminal Closed text.
- **Mount target.** The 0.11.0 HTML shell has no `#root`, so the entries use
  `Mount MacsAdAdmin.` and `Mount MacsAdPublic.`. The dead `:global(#root)`
  selectors were dropped.
- **Topic status.** The live "Selected: …" status no longer uses CSS uppercase.
  Its visible text now matches the text the browser contract and screen
  readers read.
- **Debt and formatting.** Cohesive components replaced the four oversized
  scoped styles, and their debt records were removed without relaxing a limit.
  The corpus and proof-worker edits do two things. First, they apply the
  `Import` order that `largo fmt` 0.11 requires. Second, the corpus decoders
  gain explicit `When Ok` arms carried from the migration work. `largo check`
  at `c67b633d` also accepts those decoders without the arms, so the arms are
  not claimed as a compiler requirement.
- **Gateway.** The gateway Page keeps the source after a denial, navigates only
  after the server accepts the job, and resends the same body and key on
  retry. The backend routes it calls are still not implemented.

## Not established

- **Proof loop and host adapter.** The proof-loop contracts
  (`host_adapters.tests.proof_demo_contract`, `proof_worker_contract`,
  `lean_worker_contract`) and the host-adapter test
  `test_descendant_holding_output_is_terminated_with_owned_group` did not run
  to a verdict on the development host. `run_bounded` sets `RLIMIT_NPROC=256`.
  That limit counts every task the user owns, and other sessions held about
  670, so `fork()` returned `EAGAIN`. This is not a LOGOS or MaCSad result.
  GitHub CI runs the host-adapter discovery. The proof-loop contracts need a
  host where the test user owns few tasks.
- **Not covered.** No browser tests beyond the supplementary checks, no
  authenticated routes, no PostgreSQL integration and no Firebat2 evidence.
- **Earlier private candidate.** Its build identities and its raw-Style
  dedent reproduction were not re-run against this public toolchain.
