# Firebat2 verification runner

## Purpose and current hold

Firebat2 is the isolated evidence lane for revisions that already passed
credential-free Foundation CI. It is not a deployer and never receives
Cloudflare, database, SSH, GitHub write, or application secrets.

The lane is deliberately disabled today. The audited Firebat2 state is:

- the GitHub Actions runner is **not registered**;
- No browser is installed, so required browser smoke would fail rather than
  skip;
- Docker and Tailscale are absent and are not prerequisites for this lane;
- Node 24 is present;
- KVM is present, but no VM lifecycle tooling has been provisioned; and
- repository branch protection/ruleset administration returned **HTTP 403**.

The repository's Actions policy was read back as enabled, GitHub-owned actions
only, `allowed_actions=selected`, `sha_pinning_required=true`, verified-publisher
actions disabled, no additional allow patterns, a read-only default workflow
token, and workflow-token pull-request approvals disabled. The repository
variable was also read back as exactly `FIREBAT2_ENABLED=false` on 2026-08-31.

`FIREBAT2_ENABLED` must remain exactly `false`. **Do not enable** the lane until
the branch protection hold, one-job VM controller, guaranteed overlay
destruction, and every provisioning check below are resolved and proven by an
organization/repository administrator. A skipped disabled lane is not
Firebat2 evidence. Running the Actions runner directly on bare Firebat2 is
forbidden.

## Queue and trust flow

The following automatic path is checked in but not operational. With
`FIREBAT2_ENABLED=false` and no runner/controller provisioned, ingestion cannot
queue an executable Firebat2 job. After every enablement prerequisite is green,
there is one path:

1. `Foundation CI` completes for a push.
2. `.github/workflows/firebat2-ingestion.yml` receives its `workflow_run`.
3. A GitHub-hosted admission job requires success, event `push`, repository
   identity, the exact workflow definition path plus GitHub's exact
   main-qualified run path (`.github/workflows/foundation-ci.yml@main`),
   `main`, and the full commit SHA reported by the successful Foundation run.
4. The caller passes that exact SHA and Foundation run ID to the reusable
   `.github/workflows/firebat2-verify.yml`.
5. A controller must create a fresh KVM/QEMU VM and register a one-job
   `--ephemeral --disableupdate` runner. GitHub queues it only for runner group
   `macsad-firebat2` with the exact
   labels `self-hosted`, `linux`, `x64`, `firebat2`, and `macsad-verifier`.
6. The VM independently checks its image marker, ephemeral runner settings,
   SHA, and host invariants, then runs the
   LOGOS tests, two-pass deterministic WASM gate, evidence emission, and real
   Chromium smoke tests.

Foundation itself keys concurrency by event plus the exact commit SHA and does
not cancel an earlier commit when a newer push arrives. Each successful
per-SHA push run therefore reaches the disabled ingestion workflow today and
becomes its own Firebat2 queue item only after enablement; repeated pending runs
for the same SHA may coalesce without dropping a distinct candidate.
Foundation's job timeout is 10 minutes; a timed-out SHA is failed and never
admitted as successful.

Concurrency keys by the full source SHA and `cancel-in-progress` is false, so
only duplicate requests for the same SHA coalesce. The external controller must
expose capacity for only one ephemeral verifier at a time; different SHAs then
remain independently queued without concurrency-group replacement. GitHub queue
order is transport behavior, not research priority, workflow authority, or
permission to skip a revision. This is bounded rather than lossless: GitHub
fails a self-hosted job queued for more than 24 hours. Queue expiry remains a
visible failed candidate, requires an explicit same-SHA requeue with a new run
attempt, and is never Firebat2 evidence. Pull requests, manual dispatch,
schedules, and repository dispatch do not enter the owned runner. The runner
uses GitHub Actions **outbound long-polling** over HTTPS.
There is **No inbound webhook**, webhook listener, or exposed testing port.
GitHub's runner connection is the ingestion queue.

The caller's `./.github/workflows/firebat2-verify.yml` reference is the sole
local-workflow exception to the repository's full-SHA action rule. GitHub's
same-repository reusable-workflow syntax does not accept an `@sha` suffix; it
uses the caller's commit. The source guardrail allowlists only this exact path.
That mutable workflow trust is another reason branch protection and the
disabled flag are mandatory before Firebat2 can execute.

See GitHub's guidance on [secure use of self-hosted runners](https://docs.github.com/en/actions/reference/security/secure-use),
[runner groups](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/manage-access),
and [reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows).

## Mandatory host contract

`ops/firebat2/verify_verifier_host.sh` is read-only and fails unless all of
these bumpers are up:

- the process runs as dedicated user `macsad-verifier`, never root;
- `systemd-detect-virt --vm` proves KVM/QEMU, and the root-owned image marker
  contains exactly `macsad-firebat2-ephemeral-vm-v1`;
- that user belongs only to the private `macsad-verifier` group, all four Linux
  capability sets are zero, `/proc/self/status` reports `NoNewPrivs: 1`, it has
  no noninteractive sudo, and it cannot write `/var/run/docker.sock`;
- root-owned `/etc/macsad/firebat2-runner-role` has mode `0444` or `0644` and
  contains exactly `macsad-firebat2-verifier-v1`;
- `/opt`, `/opt/macsad`, and the runner root have safe root-owned parent
  directories; every distribution entry except the exact runtime `_diag`
  subtree is root-owned, free of symlinks and group/world writes, and
  verifier-read-only; `_diag` alone is verifier-owned mode `0700`, is created
  under umask `0077`, and contains no links, foreign owners, or group/world
  access; the listener is exactly Actions Runner `2.334.0` at
  `/opt/macsad/actions-runner/bin/Runner.Listener`;
- root-owned `.runner` settings prove `Ephemeral=true`,
  `DisableUpdate=true`, work folder `/var/lib/macsad-runner/_work`, exact
  Brahmastra-Labs organization registration, and runner group; the read-only
  GitHub settings audit separately proves that the group selects only the
  private MaCSad repository and exact verifier workflow;
- `/usr/bin/node` reports Node 24 and `/usr/bin/chromium` is an executable
  root-owned Chromium binary; `/usr/bin/timeout` and `/usr/bin/tee` are fixed,
  root-owned executables used by the bounded stage harness; `/usr`, `/usr/bin`,
  and the canonical `/bin -> /usr/bin` link are verifier-read-only, and
  repository commands use only `/usr/bin:/bin`;
- `/opt/macsad/toolchains/logicaffeine-private` is root-owned, read-only to the
  verifier at every descendant, contains no symlinks, is clean, and matches
  `.macsad/toolchains/logos.lock.toml` exactly;
- at least 20 GiB disk and 4 GiB available memory remain; and
- the MaCSad checkout is clean and is the admitted source SHA.

The workflow repeats the highest-risk identity, privilege, role-marker, path,
and SHA checks inline before it executes repository harness code. Missing
tools are failures. No step downloads a compiler, resolves a registry LOGOS
crate, pulls `logicaffeine-private`, weakens a test, or substitutes a mock.

## Human provisioning checklist — not yet authorized

These are acceptance criteria, not permission to mutate Firebat2. The runner
must exist inside a fresh VM and disappear with its overlay after exactly one
job. An administrator builds the controller/image in a separate reviewed
change and records evidence without pasting a one-time runner token into a
ticket, shell history, base image, or repository.

- [ ] Resolve the HTTP 403 and enforce branch protection/rulesets for `main`:
      pull requests, required `Foundation CI`, no force pushes, no deletion,
      reviewed workflow changes, and restricted administrator bypass.
- [ ] Implement and adversarially test a root-controlled Firebat2 KVM launcher
      that creates one fresh overlay per queued job, exposes at most one active
      verifier VM/runner, restricts guest network
      egress to GitHub Actions/artifact endpoints, records VM identity, and
      guarantees power-off plus overlay deletion after success, failure,
      cancellation, timeout, or host restart. This repository intentionally
      does not implement that privileged controller yet.
- [ ] Create `macsad-verifier` inside the guest with state home
      `/var/lib/macsad-runner`, no
      privileged supplementary groups, no sudo rule, and no reusable secrets,
      SSH keys, cloud credentials, or production mounts.
- [ ] Download Actions Runner `2.334.0` Linux x64 from GitHub's official
      release; verify SHA-256
      `048024cd2c848eb6f14d5646d56c13a4def2ae7ee3ad12122bee960c56f3d271`;
      install root-owned under `/opt/macsad/actions-runner`; register each VM
      with `--ephemeral --disableupdate` and
      `--work=/var/lib/macsad-runner/_work` so unreviewed drift and reuse fail
      closed. Start it with umask `0077`; provision only its exact `_diag`
      directory as verifier-owned mode `0700`, leaving every other distribution
      path immutable to the verifier.
- [ ] Create runner group `macsad-firebat2`, grant it only the private MaCSad
      repository, and restrict workflow access to
      `Brahmastra-Labs/macsad/.github/workflows/firebat2-verify.yml@refs/heads/main`.
- [ ] Register exactly the five required labels. Do not share this runner or
      group with another repository.
- [ ] Provision root-owned Node 24 and Chromium at the fixed paths. Chromium
      must work as the unprivileged account with its sandbox enabled; never add
      `--no-sandbox`.
- [ ] Following `upgrading-logos.md`, provision the currently admitted LOGOS
      commit at the fixed root-owned read-only path. Do not pull or upgrade it
      as part of runner registration.
- [ ] Create both exact role/image markers and ensure the one-job runner starts
      as `macsad-verifier`, not Alejandro, the bare-metal host, or root. Give it
      only its private `macsad-verifier` primary group, zero supplementary
      groups, zero inherited/permitted/effective/ambient Linux capabilities,
      and `NoNewPrivileges=yes`.
- [ ] Run `LOGOS_WORKSPACE=/opt/macsad/toolchains/logicaffeine-private
      /usr/bin/bash ops/firebat2/verify_verifier_host.sh` as `macsad-verifier` and retain
      its output with the change record.
- [ ] With the repository variable still false, run the local verifier harness
      inside a throwaway canary VM; prove the runner is ephemeral and the
      controller destroys the overlay on each terminal path. Inspect artifact
      boundaries from a separate trusted machine.
- [ ] Only after every item passes, set repository variable
      `FIREBAT2_ENABLED=true`. Immediately rerun
      `node scripts/ci/audit-github-actions-settings.mjs`; revert the variable
      to `false` on any failure before accepting a candidate. Then verify the
      next successful Foundation push produces exactly one Firebat2 artifact.

Ephemeral KVM isolation is a prerequisite, not future hardening. A persistent
bare-metal runner, a reused VM, `--once` without `--ephemeral`, or cleanup that
only empties `_work` keeps the lane RED and disabled.

## Execution budgets

Speed is part of the acceptance contract, not advisory telemetry:

| Boundary | Hard budget | Evidence and failure rule |
|---|---:|---|
| Foundation CI job | 10 minutes | GitHub run timing; timeout cannot trigger Firebat2 admission |
| Firebat2 verification job | 15 minutes | GitHub run timing; timeout fails the attempt and the guest is destroyed |
| `quality-gate` | 300 seconds | Exact elapsed seconds and budget in `metadata/stage-timings.tsv` |
| `bundle-build` | 120 seconds | Exact elapsed seconds and budget in `metadata/stage-timings.tsv` |
| `browser-smoke` | 120 seconds | Exact elapsed seconds and budget in `metadata/stage-timings.tsv` |

The three Firebat2 stages run sequentially. `/usr/bin/timeout` terminates a
stage at its boundary, and the harness also rejects a recorded elapsed value
greater than the budget. The evidence-manifest verifier requires exactly these
three ordered timing rows and rejects a missing, renamed, reordered, enlarged,
or over-budget value.

Do not increase a timeout to make a slow change green. Diagnose the regression
and submit a new SHA. Any intentional budget change is a separately reviewed
performance-contract change with adversarial fixtures. The 15-minute job limit
bounds checkout, host verification, stages, manifesting, and upload as well as
the 540 seconds of stage budgets.

## Evidence and success criteria

The success-only artifact is named
`firebat2-<40-character-source-sha>-attempt-<run_attempt>` and is retained for 14
days. The source SHA, Foundation run ID, workflow run ID, and attempt are the
evidence identity; queue position is not. It contains only an allowlisted shape:

- exact admin and public `.html`, `.js`, `.mjs`, and `.wasm` bundles;
- Chromium DOM, PNG screenshot, response headers, and bounded browser/server
  logs for both sites;
- quality, emission, and browser harness logs;
- `metadata/stage-timings.tsv` containing the exact three stage elapsed times
  and fixed budgets;
- source/Foundation/run metadata and a short summary; and
- `artifact-manifest.json` plus its SHA-256 checksum.

The manifest hashes every admitted byte, rejects symlinks, unexpected paths,
empty/oversized files, remote HTML resources, missing WASM magic, missing
visible DOM markers, non-200 entries, browser runtime/load errors, and invalid
screenshots. The per-run evidence directory is deleted from the guest after
upload, and the external controller must then destroy the entire VM overlay.
An artifact can exist before a later cleanup or action post-step makes the final
workflow conclusion fail. Consumers must require both a final workflow
conclusion of `success` and a freshly verified manifest; artifact presence alone
is never evidence. An over-budget run fails before upload: its timeout and stage
failure remain visible on the SHA/attempt, but it cannot emit an artifact.

The browser probe's request log is evidence about HTTP(S) requests observed on
the attached page target, not proof that a hostile browser process had no other
egress mechanism. The mandatory VM controller firewall/network namespace is the
egress boundary; it must deny direct-IP, WebSocket, WebRTC, worker, and other
non-admitted traffic independently of Chromium. The lane remains disabled until
that negative network test exists.

Firebat2 does not rerun the PostgreSQL service fixture. The Foundation run ID
links that separate database evidence without promoting or duplicating it.

## Failure and incident procedure

For an ordinary red run:

1. leave the failing revision red;
2. inspect the first failed bumper and Foundation run linkage;
3. reproduce through the same checked-in harness;
4. fix source or the owned environment—never skip, retry-loop, relax a digest,
   install from crates.io, or hand-edit generated output; and
5. use GitHub's rerun on the same admitted workflow only after the underlying
   cause is understood.

For suspected compromise or unexpected host drift:

1. set `FIREBAT2_ENABLED` to `false` or remove it;
2. cancel queued/running verification and disable/remove the runner in GitHub;
3. stop the runner service through an authorized administrator session;
4. preserve GitHub logs, artifact digests, runner diagnostics, timestamps, and
   the role/toolchain metadata without executing repository code again;
5. assume the guest checkout, overlay, and runner state are tainted; investigate
   from a separate trusted machine; and
6. rebuild the verifier identity/runtime from reviewed inputs before any
   re-registration. Do not merely clean the work directory.

Offboarding removes repository access from the runner group first, stops the VM
controller, removes any outstanding ephemeral registration, and verifies no
overlay remains. Deleting base images, role markers, or toolchains is a separate
explicit, reviewed destructive operation.

## Controlled updates

- VM image/controller, runner, Node, browser, and LOGOS updates are independent
  changes.
- Update the checked-in expected runner version/digest and tests in a reviewed
  pull request before changing Firebat2. Keep the lane disabled during the
  host change, run the read-only host verifier, then re-enable.
- Use `upgrading-logos.md` for LOGOS. The Firebat2 workflow never pulls it.
- Browser updates must pass both sites with the sandbox enabled and create new
  evidence. Node must remain major 24 until this contract is reviewed.
- After any runner-image or identity change, confirm there are no privileged
  groups, Docker access, credentials, stale checkouts, or unexpected artifacts.

## Read-only GitHub settings audit

From an authenticated administrator workstation, this command makes only
GitHub API `GET` requests and fails on repository policy or variable/group
drift appropriate to the current enabled state:

```bash
node scripts/ci/audit-github-actions-settings.mjs
```

Branch protection remains a separate blocker. Recheck it without mutation:

```bash
gh api --method GET repos/Brahmastra-Labs/macsad/branches/main/protection
```

Until that request returns the reviewed protection contract instead of HTTP
403, leave `FIREBAT2_ENABLED=false`.
