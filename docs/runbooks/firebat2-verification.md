# Firebat2 verification and predeploy appliance

## Purpose and current hold

Firebat2 supplies scarce, trusted integration capacity after credential-free
Foundation CI. It is a capacity-one appliance, not a second scheduler and not a
general-purpose development host. GitHub workflow runs are the queue.

The lane is disabled today. The audited state on 2026-09-01 is:

- `main` branch protection is active with the strict Foundation check,
  administrator enforcement, linear history, and force-push/deletion
  protection; ordinary merging requires zero approving reviews;
- repository auto-merge is enabled;
- repository variable `FIREBAT2_ENABLED` is exactly `false`;
- the GitHub Actions runner is **not registered**;
- Firebat2 has hardware KVM support, but no QEMU/VM lifecycle tools, VM image,
  or controller. No browser is installed;
- no executable `/usr/bin/node` exists on Firebat2; a user-local Node install is
  not an admitted runner toolchain;
- Docker and Tailscale are absent and are not verifier prerequisites; and
- the current GitHub CLI identity receives HTTP 403 from organization runner
  and runner-group administration.

Do not enable the lane; keep `FIREBAT2_ENABLED=false` until every activation
check below is green.
A skipped disabled lane is not evidence.
Running the Actions runner directly on bare Firebat2 is forbidden. Never run it
as `alejandro` or root.

The owning architecture decision is
[`../decisions/0002-firebat2-pipeline.md`](../decisions/0002-firebat2-pipeline.md).

## Queue and trust flow

After activation, each successful Foundation run for a push to `main` enters
one path:

1. `.github/workflows/firebat2-ingestion.yml` receives the completed
   `workflow_run`.
2. A GitHub-hosted admission job proves success, event `push`, repository and
   workflow identity, default branch `main`, exact source SHA, and exact
   Foundation run ID.
3. A SHA-specific concurrency key coalesces only duplicate requests for the
   same candidate. Distinct SHAs remain distinct jobs, and controller capacity
   one serializes their execution without a shared pending slot replacing an
   older commit.
4. The reusable `.github/workflows/firebat2-verify.yml` requests runner group
   `macsad-firebat2` with labels `self-hosted`, `linux`, `x64`, `firebat2`, and
   `macsad-verifier`.
5. The Firebat2 controller has already created one clean standby KVM/QEMU
   overlay and registered its runner with `--ephemeral --disableupdate`. That
   runner's outbound long-poll accepts the queued job; no second guest exists.
6. The guest proves its identity and immutability before checkout, checks out
   only the admitted SHA, and runs the bounded LOGOS, deterministic WASM, and
   real Chromium gates.
7. GitHub receives the bounded evidence artifact and final conclusion. The
   controller forwards runner diagnostics and powers off the guest. It must
   destroy the entire VM overlay on every terminal path, and only then register
   a fresh standby replacement.

The runner uses **outbound long-polling** over HTTPS. No inbound webhook,
listener, or testing port exists. A queued self-hosted job expires after GitHub's
24-hour limit; expiry is a visible failed candidate and requires an explicit
same-SHA rerun. It never authorizes skipping that revision. GitHub queue order
is transport order, not MaCSad research priority.

See GitHub's [self-hosted runner reference](https://docs.github.com/en/enterprise-cloud@latest/actions/reference/runners/self-hosted-runners),
[runner-group access controls](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/manage-runners/self-hosted-runners/manage-access),
and [workflow concurrency](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).

## Bare-metal controller contract

The controller is the only new long-running Firebat2 process. It is small,
root-owned, and has no repository-defined plugin mechanism. It must:

- reconcile and remove orphaned local overlays and stale ephemeral runner
  registrations before admitting work;
- maintain exactly one clean registered standby guest while enabled, using the
  runner's outbound long-poll as the queue wake-up signal;
- hold one host semaphore covering create, boot, run, evidence-forwarding, and
  destruction plus standby replacement;
- create a fresh copy-on-write overlay from a reviewed immutable base image;
- obtain a short-lived registration token without placing it in the image,
  shell history, logs, or repository;
- restrict guest egress to the GitHub Actions and artifact endpoints required
  for the job, with tested denial of direct-IP and alternate browser egress;
- stream controller, VM, and runner diagnostics to storage outside the guest;
- enforce wall-clock and resource limits; and
- power off and destroy the overlay after success, failure, cancellation,
  timeout, lost runner connection, controller restart, or Firebat2 reboot.

The controller never mounts the host repository, Docker socket, SSH agent,
home directory, deployment credentials, or production data into a guest. Its
destruction canaries must prove all terminal paths, including a hard-killed
runner and interrupted host process.

## Credential-free verifier contract

`ops/firebat2/verify_verifier_host.sh` is read-only and fails unless the guest
satisfies all of these bumpers:

- the process is dedicated user and group `macsad-verifier`, never root, with
  no supplementary groups, sudo, Docker socket access, Linux capabilities, or
  reusable credentials, and `NoNewPrivileges` is active;
- `systemd-detect-virt --vm` proves KVM/QEMU, and root-owned exact image and role
  markers identify the one-job verifier image;
- runner settings prove `Ephemeral=true`, `DisableUpdate=true`, the expected
  work directory, Brahmastra-Labs organization, and selected runner group;
- Actions Runner is exactly `2.337.0` at the fixed root-owned path. The official
  Linux x64 archive SHA-256 is
  `70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613`.
  The guest retains that root-owned archive and the exact checked-in release
  lock; the host verifier compares archive digest, complete extracted-tree
  membership, modes, file hashes, and contained symlink targets;
- root-owned Node 24 exists at `/usr/bin/node`, Chromium exists at
  `/usr/bin/chromium`, and the workflow uses only `/usr/bin:/bin`;
- `/opt/macsad/toolchains/logicaffeine-private` is root-owned, read-only,
  symlink-free, clean, and matches `.macsad/toolchains/logos.lock.toml` exactly;
- the MaCSad checkout is clean and equals the admitted 40-character SHA; and
- at least 20 GiB disk and 4 GiB available memory remain.

The runner distribution, toolchain, `/usr`, and role markers are immutable to
the verifier. Only the exact private work, temporary, diagnostics, and evidence
directories are writable. Missing tools fail; no workflow step downloads a
compiler, resolves LOGOS from crates.io, pulls `logicaffeine-private`, weakens a
test, or substitutes a mock.

## Activation checklist

The lane may change from false to true only when all items have executable
evidence:

- [ ] An organization owner grants a narrowly scoped identity organization
      self-hosted-runner write access; runner-group API reads no longer return
      HTTP 403.
- [ ] Runner group `macsad-firebat2` selects only the private MaCSad repository
      and only
      `Brahmastra-Labs/macsad/.github/workflows/firebat2-verify.yml@refs/heads/main`.
- [ ] The root-owned controller, immutable base image, capacity-one semaphore,
      log forwarding, reboot reconciliation, and guaranteed overlay destruction
      pass adversarial canaries.
- [ ] With the lane enabled in an isolated canary organization/repository, one
      pre-registered standby accepts a queued job through outbound long-poll,
      is destroyed, and is replaced by exactly one new clean standby. A missing
      standby leaves work queued and never causes bare-metal execution.
- [ ] The guest has exact runner `2.337.0`, Node 24, Chromium with its sandbox
      enabled, the admitted LOGOS checkout, and every identity/privilege bumper.
- [ ] Running
      `LOGOS_WORKSPACE=/opt/macsad/toolchains/logicaffeine-private /usr/bin/bash ops/firebat2/verify_verifier_host.sh`
      as `macsad-verifier` succeeds in a canary guest.
- [ ] A canary verification with the variable still false exercises the local
      harness, records logs outside the guest, and proves runner deregistration
      plus overlay destruction on success, failure, cancellation, and timeout.
- [ ] The GitHub Actions settings audit confirms action pinning, read-only
      default token, selected workflow/group access, exactly one online idle
      standby with the exact five labels, and the expected false lane state by
      running
      `node scripts/ci/audit-github-actions-settings.mjs --expect-firebat2=disabled-ready`.
- [ ] A separate read-only
      `gh api --method GET repos/Brahmastra-Labs/macsad/branches/main/protection`
      confirms the required Foundation check, administrator enforcement, pull
      requests, linear history, and force-push/deletion denial.

Only then set `FIREBAT2_ENABLED=true`, rerun the settings audit with
`--expect-firebat2=enabled-ready`, and require the next successful Foundation
push to create exactly one valid Firebat2 artifact.
Revert the variable to false immediately on drift. Ephemeral KVM isolation is a
prerequisite, not future hardening.

## Execution budgets and evidence

| Boundary | Hard budget | Failure rule |
|---|---:|---|
| Foundation CI job | 10 minutes | Timeout never admits Firebat2 work |
| Firebat2 job | 15 minutes | Attempt fails and guest is destroyed |
| `quality-gate` | 300 seconds | Exact elapsed time recorded; overrun fails |
| `bundle-build` | 120 seconds | Exact elapsed time recorded; overrun fails |
| `browser-smoke` | 120 seconds | Exact elapsed time recorded; overrun fails |

Do not enlarge a timeout to hide a regression. Submit a new SHA after fixing
the product or owned environment.

The success artifact is named
`firebat2-<source-sha>-attempt-<run_attempt>` and retained for 14 days. It holds
only allowlisted bundles, browser DOM/screenshots/headers/logs, harness logs,
the exact stage timing table, source and run metadata, and a byte manifest plus
checksum. Consumers require both final workflow conclusion `success` and an
independently verified manifest. Artifact presence alone is insufficient
because a later cleanup or action post-step can still fail the run.

The manifest rejects symlinks, unexpected paths, empty or oversized files,
remote HTML resources, malformed WASM, missing visible DOM markers, non-200
responses, browser errors, and invalid screenshots. PostgreSQL evidence comes
from the linked Foundation run; the per-commit verifier does not duplicate that
service fixture.

## Predeploy and continuous lanes

The verifier never receives Cloudflare, SSH, database, or GitHub write
credentials. Deployment is a later, separate job and identity:

- a fixed-function deployer accepts only a successful verifier identity and
  byte-verified artifact;
- it does not check out or compile source and deploys exactly those bytes;
- its narrow credential can affect only the named environment; and
- ordinary deployment is automatic after deterministic gates, with no human
  approval gate.

Do not create scheduled staging checks until a staging target and rollback
artifact exist. At that point add two capacity-one queue consumers:

- fast black-box smoke at off-hour minutes against the currently deployed
  staging manifest, deferring whenever a commit candidate is waiting; and
- nightly restore/recovery against disposable storage, followed by invariant
  and rollback checks.

Schedules may be delayed and run the latest default-branch workflow definition,
so they are health evidence, not per-commit admission or a hard real-time
monitor. The smoke lane stays small; recovery holds the expensive work. Neither
lane may publish research content. See GitHub's
[scheduled workflow behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).

## Failure, incident, and updates

For an ordinary red run, leave the SHA red, identify the first failed bumper,
reproduce through the checked-in harness, fix the source or owned environment,
and rerun only after the cause is understood. Never weaken a digest, retry-loop
away a failure, install from crates.io, or hand-edit generated output.

For suspected compromise or host drift:

1. set `FIREBAT2_ENABLED=false`;
2. cancel queued/running jobs and remove repository access from the runner
   group;
3. stop the controller through an authorized administrator session;
4. preserve GitHub logs, externally forwarded runner diagnostics, artifact
   digests, VM identity, and timestamps without executing repository code;
5. treat every guest, overlay, runner registration, and credential touched by
   that lane as tainted; and
6. rebuild from reviewed immutable inputs before re-enabling.

Runner, image, controller, Node, Chromium, and LOGOS updates are independent
changes. Update checked-in expected versions and tests first, keep the lane
disabled during host work, and follow `upgrading-logos.md` for LOGOS. GitHub
requires disabled-update runners to be refreshed within its supported release
window; an unreviewed self-update is not the fallback.

## Read-only GitHub audit

From an authenticated administrator workstation:

```bash
node scripts/ci/audit-github-actions-settings.mjs --expect-firebat2=disabled
gh api --method GET repos/Brahmastra-Labs/macsad/branches/main/protection
```

The branch-protection read is expected to succeed now. Organization runner and
runner-group reads remain blocked until the authenticated identity receives the
narrow organization permission described above.
