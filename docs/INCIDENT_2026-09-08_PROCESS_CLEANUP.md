# Incident: unsafe process cleanup during MaCSad development

Date: 2026-09-08. Times below are UTC.

Status: the five identified pre-existing Firebat services and the Windows
preview tunnel have been restored. The direct process-cleanup defect has a
targeted regression suite reported green. Recovery is not equivalent to full
data-integrity verification or deployment readiness.

This is a private working draft for the main task to integrate into the
canonical readiness record. It is not authorization to restart, deploy, change
permissions, run migrations, commit, or push. No upstream LOGOS defect is
alleged: this was our mistake in new, uncommitted MaCSad host-adapter code and
its test setup.

## 1. What happened

A test of invalid execution bounds replaced `subprocess.Popen` with a mock.
The earlier implementation accepted a fractional output limit, reached process
creation, and then encountered an error in the capture path. Its cleanup still
called the real `os.killpg(process.pid, SIGKILL)` with an unvalidated mock PID.

The root task traced the mock-to-integer path to PID/group argument `1` and the
Linux `killpg(1, ...)` path to `kill(-1, ...)`. That is not a narrow child-group
cleanup: it can signal the broad set of processes the current user is permitted
to signal. The exact syscall instant was not captured by an operating-system
trace; distinguish the reconstructed mechanism from independently observed
process and service loss.

The SSH session disconnected. Both previously running PostgreSQL clusters and
all three previously running preview processes were then absent. The Windows
SSH forwarding process and its local listeners were also gone. The host itself
remained reachable and recovery did not require a host reboot.

The safety gap had three parts:

1. Invalid primitive values were not completely rejected before effects.
2. Cleanup treated an object's PID attribute as sufficient authority to signal
   a process group, without proving a real, unreaped child/session identity.
3. The test mocked process creation but left the destructive cleanup primitive
   real. Tests must not be able to signal unrelated processes when a mock is
   accidentally consumed.

## 2. Timeline and provenance

| Time | Observation or action | Evidence qualification |
|---|---|---|
| Before the incident | A frozen baseline plus the one-line LOGOS test-count correction passed the full gate using a newly owned disposable PG16 cluster. That cluster was stopped. | Baseline evidence only; not evidence for the new proof adapter or later feature source. |
| Approximately 22:22:29 | A user-systemd restart was observed around the invalid-bounds test and SSH disconnection. | Approximate incident marker from investigation; not an exact signal timestamp. |
| After disconnection | The two original PostgreSQL processes, gateway, admin preview and public preview were absent; the Windows forwarding process/listeners were absent. | Read-only process/listener inspection. Other user background processes were not completely inventoried. |
| 22:27:39 | First original PostgreSQL cluster restarted with its recorded configuration, PID `469943`. | Process start time; recovery log subsequently reached ready. |
| 22:28:26 | Second original PostgreSQL cluster restarted with its recorded configuration, PID `470104`. | Process start time; recovery log subsequently reached ready. |
| 22:28:55 | Original admitted-binary LOGOS gateway restored, PID `470229`. | Local health and listener verified. |
| 22:29:12 | Original admin preview restored, PID `470333`. | Local HTML, health proxy and assets verified. |
| 22:29:17 | Original public preview restored, PID `470440`. | Local HTML and assets verified. |
| Approximately 22:31 | Root ran `python3 -m unittest host_adapters.tests.test_proof_process -v`: 19 tests passed in 0.446 seconds. | Root-reported terminal evidence; a separately retained log file was not available for this draft. Gateway health remained HTTP 200 afterward. |
| After preview verification | Root restored Windows tunnel PID `23364`; local admin health and public HTML returned HTTP 200. | Root-reported local checks at ports `18180` and `18182`. |
| Subsequent bounded recovery check | Read-only restored-data assertions passed on five accessible MaCSad databases; the full catalog verifier failed on each for role/ownership configuration. | Individual outcomes are recorded below. The denied-access database was not altered or retried. |

Recovery was explicitly authorized for the five identified original services,
using their previous roots, ports, configuration and admitted binary. It did
not authorize new service features, broader network exposure or Compose
provisioning. The manually launched development services remain an existing
runtime exception, not the supported production Compose topology.

## 3. Known impact and limits of the inventory

| Service | Previous PID | Recovered PID | Recovered exposure |
|---|---:|---:|---|
| PG16 validation cluster | 36846 | 469943 | Original Unix socket, port 55432; no TCP |
| PG16 schema-validation cluster | 38205 | 470104 | Original Unix socket, port 55433; no TCP |
| Admitted LOGOS health gateway | 141302 | 470229 | `127.0.0.1:18081` only |
| Admin development preview | 81953 | 470333 | `127.0.0.1:18080` only |
| Public development preview | 82740 | 470440 | `127.0.0.1:18082` only |
| Windows two-port SSH forwarding | Not retained | 23364 | Local `18180` and `18182`, restored by root |

Known consequence: previews were unavailable and PostgreSQL required crash
recovery. In-flight transactions or other work may have been interrupted. We
have not established a pre-incident list of every process, transaction, event
head or row count, so the total affected background workload and any lost
uncommitted work remain unknown. Do not describe the five identified services
as an exhaustive blast-radius inventory.

There is no observed evidence here of source deletion, secret exposure, remote
pushes, a network-exposure change or PostgreSQL corruption. Those absences are
not a comprehensive forensic assurance. There is also no evidence that an
upstream LOGOS change caused this incident.

## 4. Recovery performed

### PostgreSQL

- Started each original cluster separately, checking that the relevant service
  was absent and inspecting its recorded `postmaster.opts` first.
- Used the original extracted PostgreSQL 16.15 executable and libraries.
- Let `pg_ctl` and PostgreSQL handle stale process/socket state. No PID file,
  socket file, WAL file or database file was manually removed.
- Preserved the original socket-only configuration and port for each cluster.
  The first cluster also retained its recorded `fsync=on` option.
- Inspected bounded recovery logs and performed read-only SQL before moving to
  the next cluster.
- Both logs showed automatic WAL recovery, completed redo, an end-of-recovery
  checkpoint and readiness. An end-of-WAL `invalid record length` message was
  followed by successful recovery; that message alone is not proof of damage.
- Read-only SQL confirmed PostgreSQL 16.15, the expected port, empty
  `listen_addresses`, `pg_is_in_recovery=false` and the existing database
  catalogs.

### Gateway and previews

- Confirmed each original localhost port was free before starting its service.
- Reused the admitted gateway binary, not the different binary in the active
  upstream working checkout.
- Compared gateway source and the admin static adapter with the preserved
  baseline copy before recovery; they matched.
- Reused the existing generated bundles. No rebuild or feature activation was
  part of recovery.
- Added no optional demo snapshot or new backend flag.
- The gateway and admin health proxy returned their original response:

  `MaCSad gateway ready | persistence: not connected | mutations: disabled`

- Both preview servers remained bound to IPv4 localhost. PostgreSQL acquired
  no TCP listener. Unrelated listeners were left alone.
- The public server's existing directory-listing behavior at `/` was not
  changed during recovery; its application HTML remains at
  `/macsad_public.html`.

### HTTP asset identity

All eight served files matched their existing on-disk SHA256. This proves
byte identity of the recovered serving path, not that the browser renders or
all interactions work correctly.

| Asset | SHA256 |
|---|---|
| Admin HTML | `5f3cba79c4e94fc5fa4133704ff42aa4d7c3a2b3390fede626e2f8fcf54ff227` |
| Admin JS | `13d4eb876d6fd6a6f87394e6f35ba25cfbe16599465354c99da306d6fd55c3ee` |
| Admin MJS | `eed795e34a9938f2d5529ccd96931c3d9515284908ce65a3c633835bb251ab3c` |
| Admin WASM | `9489b996a97acf5ef49037a567269765b9b38fdacaac7f64d412e17adc1689bf` |
| Public HTML | `a63527993fb701fc44b1c604487f163ffc7757d1ee82eb1331a3c1cbd4421bbb` |
| Public JS | `bf8e4ad8e9e39725eb657060525a5aaf82201ebfb6d71699fecbee154deb556c` |
| Public MJS | `c66a6a2b2772f27d549ddd2ed61694fafe88ab221b14f3fb6e396a64aa1a65e4` |
| Public WASM | `17562458ea566db186710c28e7618f444f698879aba0bb7bf3857cf82f984c53` |

## 5. Read-only database verification after recovery

Both existing SQL files were inspected before execution:

- `database/verify.sql` uses a read-only transaction and checks catalog,
  ownership, roles, grants, constraints, selected projections and the migration
  ledger. A failure early in its assertion block prevents later checks and
  fingerprint generation; do not imply those later checks ran.
- `database/workers/sql/verify_restored_data.sql` uses a repeatable-read,
  read-only transaction. It checks gapless workspace event numbering and
  previous-hash links, audit-stream sequence/count consistency and artifact
  references to blob metadata. It does not verify stored blob bytes or
  independently recompute every event digest.

Each invocation had a read-only session default, a 30-second statement limit,
5-second lock limit, 30-second idle-transaction limit, no password prompt,
explicit Unix socket/port/database/user and a 40-second external timeout.
No fixture, migration, permission change or invariant-writing test was run
against the recovered databases.

| Existing database | Cluster port | `verify.sql` | `verify_restored_data.sql` |
|---|---:|---|---|
| `macsad_arch_review` | 55432 | FAIL, exit 3: required role attributes missing or unsafe | PASS, exit 0 |
| `macsad_invariant_final` | 55432 | FAIL, exit 3: required role attributes missing or unsafe | PASS, exit 0 |
| `macsad_invariant_review` | 55432 | FAIL, exit 3: owner `alejandro`, expected `macsad_owner` | PASS, exit 0 |
| `macsad_invariant_review2` | 55432 | FAIL, exit 3: required role attributes missing or unsafe | PASS, exit 0 |
| `macsad_schema_test` | 55433 | FAIL, exit 3: required role attributes missing or unsafe | PASS, exit 0 |
| `macsad_final_qa` | 55433 | NOT RUN: previously observed CONNECT denial; no permission change | NOT RUN for the same reason |

The five catalog failures are current configuration incompatibilities with the
checked-in verifier. Without a matching pre-incident catalog comparison, they
cannot be attributed to the crash. We did not weaken the verifier or change
roles/ownership to make it pass. The independent restored-data checks can pass
even on empty tables; this run did not establish a pre/post row-count equality
or prove that every expected research record is present.

Two initial shell wrappers failed to parse before their database-loop bodies
executed because of the Windows-to-shell input framing. A corrected wrapper
then recorded the outcomes above. Individual verifier exit codes, not the
diagnostic wrapper's overall exit code, determine the result.

## 6. Process-safety correction and regression evidence

The current MaCSad helper now:

- requires an exact bounded integer output limit, excluding booleans and
  fractions, and a supported finite timeout before `Popen`;
- requires a PID whose exact type is `int`, greater than 1, and different from
  the current process and process-group IDs;
- calls non-reaping `waitid` to establish that the process remains our child;
- requires both the process-group and session IDs to match that child's PID
  before group signalling;
- preserves the leader's PID until group cleanup and performs only a bounded
  two-second reap wait, reporting failure if cleanup cannot be confirmed;
- rejects a FIFO/non-regular source without waiting for a writer; and
- retains bounded output capture and exact typed JSON framing. Mathematical
  acceptance remains a LOGOS decision, not a Python interpretation.

Root's targeted run reports **19 passed, zero failed**, including refusal of
special/mock/current PIDs, a process in another group, a session leader that is
not our child, invalid bounds before process creation, bounded reap failure,
timeout, output cap, closed-output timeout, descendant cleanup and FIFO input.
Dangerous signal primitives are mocked in negative cleanup identity tests.

This is not a general process sandbox. The CLI remains for trusted, fixed,
admitted commands. It does not establish containment against malicious code,
descendants that deliberately escape their session, network effects, a shared
multi-user worker threat model or arbitrary uploaded executable content.

Source identity at the draft's inspection:

| Item | Identity |
|---|---|
| MaCSad checked-out base | `f95e22be1ceb270a714b8936e8cd0d1b3f6050e5` on `main`, with uncommitted work |
| `host_adapters/proof_process.py` | SHA256 `1a0f596954119dbf8c235acfbf7d21f1b300b8b6a5c28d7645d6ee643ecef9fc` |
| `host_adapters/tests/test_proof_process.py` | SHA256 `08fb1d390d79d73e38341f3f0bba7e50e9e87b83f9b8f0ad2268d16ff4d562b4` |
| `database/verify.sql` | SHA256 `25cf3c1a2a08d36e4841fab2d736e39a08de91a8982624a7debc6540e574025e` |
| `database/workers/sql/verify_restored_data.sql` | SHA256 `eddd2365c7132da50a217173d381e3648bb23d95ddca72f8f1450564d8971c86` |
| Recovered admitted `largo` | SHA256 `8c75eeb6180a7f4692ad5abba32b562d4a1cbc08792da95ae58770d4a3cc77f1` |

The base commit alone does not identify the new helper. If the helper changes,
its evidence must be rebound to the new bytes. The 19-test terminal result was
reported by root rather than independently rerun by this recovery task.

## 7. Remaining actions, with owners and acceptance

1. **Main implementation owner:** retain a bounded log of the corrected
   process suite and rerun the complete required gate serially on the exact
   final candidate. Acceptance: discovered inventories, no skips, exact source
   identities and explicit unavailable tiers. Earlier baseline green evidence
   cannot stand in for final feature evidence.
2. **Database operator:** compare current ownership/role differences against
   known prior cluster configuration. Acceptance: classify each catalog
   failure as pre-existing drift, intentional scratch configuration or new
   discrepancy. Any repair requires separate authority; do not silently grant
   access or change ownership, especially for `macsad_final_qa`.
3. **Database/data owner:** reconcile event heads, row counts and expected
   research artifacts against retained pre-incident evidence if available.
   Acceptance: explicit discrepancies or a bounded consistency conclusion.
   If no baseline exists, record that limit; do not manufacture certainty.
4. **Backup/recovery owner:** arrange a separately authorized backup and
   restoration rehearsal into a new, owned scratch target, then verify
   catalog, ledger, event continuity and actual immutable artifact bytes.
   Acceptance: digest-bound backup/restore evidence and a tested recovery
   procedure. No restore, fixture loading or invariant-writing test belongs
   on the recovered original databases.
5. **Host operator:** inventory any other background jobs that were active
   around the incident. Acceptance: each known lost task is recovered or
   explicitly closed; no automatic resurrection of unidentified services.
6. **Host-adapter/test owner:** preserve the exact-ID/ownership tests and the
   rule that invalid-input tests prove no process creation. Acceptance: a
   future regression cannot exercise a real broad signal through a mock.
7. **Operations owner:** evaluate a separately authorized isolated execution
   boundary before accepting untrusted contestant work. Acceptance must cover
   same-user blast radius, process escape, network, files, resource budgets
   and cleanup failure. Do not mistake the helper's resource limits for this
   boundary or deploy a new service under the incident-recovery authority.

## 8. Repeatable read-only verification commands

These are future-use commands, not authorization to run them on a new target.
They reuse existing SQL. The operator supplies private absolute roots locally;
machine-specific developer paths and credentials must not be committed here.

`MACSAD_REPO` must identify the reviewed MaCSad checkout.
`MACSAD_RECOVERY_CACHE` must identify the parent directory containing the two
existing `macsad-pg16-validation` and `macsad-pg16-schema-validation` directories.
The extracted client and libraries belong to the former directory.

Run one explicit database/script pair at a time from a Linux shell. Select the
target from the recorded inventory; do not discover and loop through unrelated
databases or retry a denied connection with another identity. The following
example selects an accessible database and the narrow restored-data check:

```bash
: "${MACSAD_REPO:?Set the reviewed MaCSad checkout path locally}"
: "${MACSAD_RECOVERY_CACHE:?Set the existing recovery cache parent locally}"

RECOVERY_CLUSTER=validation
RECOVERY_DATABASE=macsad_arch_review
RECOVERY_SCRIPT=database/workers/sql/verify_restored_data.sql

case "${RECOVERY_CLUSTER}:${RECOVERY_DATABASE}" in
  validation:macsad_arch_review|validation:macsad_invariant_final|validation:macsad_invariant_review|validation:macsad_invariant_review2)
    RECOVERY_SOCKET="${MACSAD_RECOVERY_CACHE}/macsad-pg16-validation/socket"
    RECOVERY_PORT=55432
    ;;
  schema-validation:macsad_schema_test)
    RECOVERY_SOCKET="${MACSAD_RECOVERY_CACHE}/macsad-pg16-schema-validation/socket"
    RECOVERY_PORT=55433
    ;;
  *) printf '%s\n' 'Unapproved recovery target; stop.' >&2; exit 2 ;;
esac

case "${RECOVERY_SCRIPT}" in
  database/verify.sql|database/workers/sql/verify_restored_data.sql) ;;
  *) printf '%s\n' 'Unapproved verification script; stop.' >&2; exit 2 ;;
esac

RECOVERY_PG_ROOT="${MACSAD_RECOVERY_CACHE}/macsad-pg16-validation/root"
cd "${MACSAD_REPO}" || exit 1

timeout --signal=TERM 40s env -i \
  PATH=/usr/bin:/bin \
  LD_LIBRARY_PATH="${RECOVERY_PG_ROOT}/usr/lib/x86_64-linux-gnu" \
  PGPASSFILE=/dev/null \
  PGCONNECT_TIMEOUT=5 \
  PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=30000 -c lock_timeout=5000 -c idle_in_transaction_session_timeout=30000' \
  "${RECOVERY_PG_ROOT}/usr/lib/postgresql/16/bin/psql" \
  -X -w -v ON_ERROR_STOP=1 \
  -h "${RECOVERY_SOCKET}" -p "${RECOVERY_PORT}" \
  -U alejandro -d "${RECOVERY_DATABASE}" -f "${RECOVERY_SCRIPT}"
```

For the catalog check, select `RECOVERY_SCRIPT=database/verify.sql` before
running the validated command. Preserve its nonzero exit and actual message.
An early role/owner failure means later data checks in that file did not run;
the independent read-only restored-data check does not erase that failure.
Inspect any changed SQL before reusing this procedure. If access requires a
credential or permission change, stop and request operator direction.

Do **not** substitute `make test`, `make up`, `make verify`, migration/seed
scripts, `database/tests/0001_invariants.sql`, field-coverage fixtures or the
backup/restore roundtrip suite for these explicit read-only commands. Some of
those are appropriate only on newly owned scratch targets or operate the
Compose stack, which is not what was recovered here.
