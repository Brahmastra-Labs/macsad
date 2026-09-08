# LOGOS proof-loop demonstration

Status: a local, one-shot proof-evidence workflow. This is not the authenticated
website-to-database workflow and is not a deployed contestant service.

## What Alejandro can demonstrate

Supply a small, already formalized LOGOS problem. LOGOS searches for and checks
the supported theorem results. MaCSad retains the exact source, the requested
theorems, checker output, CLI diagnostic output, and the result of a second
run of the same source. Removing a necessary assumption changes the result
from `checked` to `not-proved`; malformed results cannot become a proof claim.

The policy which decides whether a report is internally consistent and answers
the exact requested targets is written in LOGOS. Python only runs fixed admitted
commands, bounds process/output resources, decodes strict primitive data, and
saves evidence. There is no model call, Python theorem prover, SQLite authority,
database mutation, automatic case acceptance, or automatic publication.

Do not say that this already solves arbitrary natural-language mathematics.
The submitted development must use mathematical syntax supported by the admitted
LOGOS theorem entry point. A proof is always relative to its supplied assumptions.

## Operator prerequisites

- Linux/POSIX with non-reaping `waitid`, Python 3.11 or later, Bash, Git and
  SHA256 tooling. The development evidence was exercised on Python 3.12.
- A MaCSad checkout with this work present. Work currently remains uncommitted;
  the base commit alone does not identify these changes.
- `LOGOS_WORKSPACE` must identify the checkout matching
  `.macsad/toolchains/logos.lock.toml`, currently source commit
  `132dc5346728e2d204df798dd7544e6405306a2c` and admitted binary SHA256
  `8c75eeb6180a7f4692ad5abba32b562d4a1cbc08792da95ae58770d4a3cc77f1`.
- Run as the local developer against trusted demonstration inputs. This helper
  is not an isolation boundary for arbitrary contestant code. See the incident
  report before enabling any multi-user worker.

The existing strict wrapper checks source identity, tree, tracked cleanliness,
origin, Cargo lock, binary and version. This command does not fetch, install,
rebuild or promote a toolchain. Do not point it at a newer checkout and weaken
the lock to make it run.

From the MaCSad repository root, with the admitted workspace already set:

```bash
: "${LOGOS_WORKSPACE:?Set the exact admitted LOGOS checkout locally}"
export LOGOS_WORKSPACE
mkdir -p -m 700 artifacts/proof-demo
python3 -m host_adapters.proof_demo tests/fixtures/proofs/tarski.lg \
  --target reflexivity --target symmetry --target transitivity \
  --output-directory artifacts/proof-demo
```

Use a private output directory. If that directory already exists, verify its
ownership and permissions first: `mkdir -p -m 700` does not repair existing
permissions. Do not use a shared or web-served output location.

The output includes two native `logos_status` values and `evidence_directory`.
Expected for this example: `checked` twice, identical raw reports, three exact
targets, two declared theory axioms. Process exit zero means **evidence was
captured**, not that a mathematical statement was proved. Always read the native
statuses. A null status means the native policy invocation did not produce a
valid result; no acceptance may be inferred.

The source in this example contains two axioms about segment congruence and
asks LOGOS to prove reflexivity, symmetry and transitivity. This is a small
formal reasoning demonstration, not a claim of a new mathematical discovery.

## Five-minute demonstration script

1. Open `tests/fixtures/proofs/tarski.lg`. Show the exact axioms and three goals.
2. Run the command above. Open the emitted `result.json`, `input.lg`, and
   `first/trace.stdout` inside its evidence directory.
   For these theory examples, `--trace` is only a short result summary, not
   proof terms or a detailed derivation. Do not present it as an exported certificate.
3. Explain that the evidence retains both the successful report and all source
   assumptions. It does not silently turn supplied axioms into proved facts.
4. Run the weakened development:

   ```bash
   python3 -m host_adapters.proof_demo tests/fixtures/proofs/weak_tarski.lg \
     --target reflexivity --output-directory artifacts/proof-demo
   ```

   Expected: `not-proved` twice. This means the checker did not prove the goal
   under those inputs; it is not a counterexample or a proof of falsehood.
5. Run `socrates.lg` with `--target Socrates`, then `unfounded_socrates.lg` with
   the same target. Expected: `checked`, then `not-proved`. Both JSON reports
   may say `axioms: 0`, because English `Given` premises are not counted there.
   The retained source and different source digests make the assumption change
   visible.
6. Deliberately request `--target unrelated-goal` for `socrates.lg`. Expected:
   `rejected`, even though LOGOS can prove the actual Socrates theorem.

## What is saved

Each completed run has a newly reserved `run-<UUID>/bundle` directory. Existing
run directories, including empty ones, are never overwritten.

| Artifact | Purpose |
|---|---|
| `input.lg` | Exact original UTF-8 source bytes, including assumptions |
| `request.json` | Exact ordered target names and source digest |
| `logos.lock.toml` | Toolchain admission record |
| `policy/` | Native LOGOS worker source snapshot |
| `mechanical-adapter/` | Host-adapter and admission-wrapper source snapshots |
| `first/`, `rerun/` | Fresh source copies, raw stdout/stderr and process observations |
| `first/trace.*` | Diagnostic source-run trace and its own process outcome |
| `result.json` | Native statuses, repeat comparison and explicit scope limitations |
| `manifest.json` | Byte lengths and SHA256 digests for the other saved files |

Artifacts are private local files, not tamper-proof records or authoritative
PostgreSQL case facts. Hashes detect changes relative to the recorded manifest;
they do not authenticate its author or prevent someone editing both.

Publication reserves a new directory and moves in the complete bundle. An
exception before publication leaves a `.partial-proof-*` directory for diagnosis.
A directory without `bundle/manifest.json` is not completed evidence. If the
final filesystem sync fails after the move, the error reports the actual visible
destination and explicitly says durability is unconfirmed. Preserve that state
for an operator; do not relabel it as successfully persisted.

## Enforced limits

- One nonempty, regular, non-symlink source, at most 32,768 bytes, strict UTF-8,
  no NUL. A FIFO is rejected without waiting for a writer.
- One to 32 unique requested targets, one to 256 UTF-8 bytes each, in exact
  theorem declaration order. Targets are data arguments, never generated code.
- Fixed commands, no shell expansion of source or theorem names, no inherited
  service credentials, bounded combined stdout/stderr and wall/CPU/resource
  limits. Cleanup verifies an exact safe PID, unreaped child ownership, process
  group and session before signalling only that owned group.
- Strict JSON field sets, primitive types and duplicate-key rejection prevent
  malformed reports becoming valid facts. Such reports still reach the native
  policy with an explicit invalid marker. LOGOS checks non-vacuity, exact names/order, unique
  targets, consistency of row results/errors/summary and expected process exit.
- Native wire parsing validates canonical decimal, bits, lower-case hex and
  UTF-8 before decoding text. Interpreter execution has explicit budgets.

These are bounded local ports, not a generic ETL framework or an adversarial
process sandbox. Aggregate descendant resources, network isolation, multi-user
quotas, tenant isolation and crash recovery need a separately tested worker
deployment design.

## Verification and maintenance

```bash
python3 -m unittest discover --start-directory host_adapters/tests --pattern 'test_*.py'
make test-proof-demo
make test
```

Run suites serially. `make test-proof-demo` uses the actual admitted LOGOS
executable, not a mocked proof engine. It covers the real positive/negative
developments, wrong/reordered/absent targets and adversarial report/wire inputs.
`make test` includes that tier, native leaf tests with fixed seed and finite
property proofs, source checks and deterministic browser bundle builds.

The database tier of `make test` is only valid against a **new, owned PostgreSQL
16 test database**. Without `DATABASE_URL`, it explicitly reports no PostgreSQL
evidence. Never point it at an existing research or recovered validation database.

Set `MACSAD_REQUIRE_DATABASE=1` for a gate which requires database evidence; it
fails if `DATABASE_URL` is accidentally absent. Supply credentials only through
the approved private operator mechanism, never in a committed command or log.

Finite Boolean properties in the application tests are not mathematical theorem
coverage. Two successful source runs use the same LOGOS tool: they are not a
preserved-certificate replay or independent checker agreement. Whole-program
definitions and imported developments are outside this baseline proof-entry
coverage. Consult `LOGOS_GAPS.md` and `ELECTRON_READINESS.md` before expanding it.

## Next steps toward the website loop

The complete September 8 gate passed: 196 Node tests, 31 Python mechanical
tests, 33 native LOGOS tests, 10 finite properties, and nine real-LOGOS integration
methods (eight fixture runs and 42 adversarial wire/report cases), with no
failures or skips. Fresh PostgreSQL 16.15 and deterministic bundle checks also
passed. See section 18.6 of `ELECTRON_READINESS.md` for source/log identities and
the two retained demonstration bundle IDs. This paragraph is a documentation-only
post-gate addition, not a new executable change.

1. Evaluate and explicitly admit an exact newer LOGOS candidate for the needed
   HTTP, structured-data, PostgreSQL and stable-input capabilities. MaCSad must
   not modify or push upstream LOGOS to do this.
2. Establish the proof trust route: pinned intended statement/assumptions,
   portable certificate/context validation and genuinely separated checking.
3. Complete authenticated, workspace-scoped command handling, idempotency,
   expected versions, event/receipt/outbox atomicity and negative PostgreSQL tests.
4. Store attempts and immutable evidence through those commands; do not write
   the existing domain tables directly from this demo.
5. Add a bounded proposal worker which can turn a problem into a candidate
   formalization, retaining original meaning, assumptions, provenance and budget.
   An AI proposal is not a proof; it must pass the checker path above.
6. Connect the existing LOGOS interface to that authenticated workflow and test
   typing/focus, pending/denied/failed states, retries and reproducibility.
7. Rehearse backup/restore, hostile inputs, resource exhaustion and operator
   recovery before contestant deployment. The local preview remains read-only.

The shared detailed direction remains `ELECTRON_READINESS.md`; the process-test
incident and recovery evidence are in `INCIDENT_2026-09-08_PROCESS_CLEANUP.md`.
