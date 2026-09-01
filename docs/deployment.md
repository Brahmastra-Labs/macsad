# MaCSad deployment contract

Status: baseline contract; no Cloudflare credential or live deployment is configured.

## What is automated now

`Foundation CI` runs on pushes and pull requests without private-repository or
Cloudflare credentials. It checks the repository's mechanical guardrails, then
creates a clean PostgreSQL 16 database, applies the immutable migration set,
applies it again to prove idempotent history validation, runs catalog
verification, and exercises the high-value invariant suite.

That workflow is deliberately not named or represented as the complete CI
gate. It does **not** compile LOGOS, drive a browser, connect to Firebat One,
validate Cloudflare Access, or deploy anything. GitHub-hosted runner software is
also a mutable dependency; the future release gate must pin the application
toolchain rather than treating the runner image as release evidence.

The complete local baseline gate is:

```bash
LOGOS_WORKSPACE=/path/to/the/exact/pinned/logicaffeine-private \
DATABASE_URL='provided-out-of-band' \
MACSAD_REQUIRE_DATABASE=1 \
bash scripts/quality-gate.sh
```

Never put the URL in Git, a command transcript, an issue, or a workflow file.
The gate verifies the exact locked LOGOS version, Cargo lock digest, and largo
binary digest before every compiler invocation. It uses the supported JSON
checker; the current deep-check panic is a tracked RED framework gate. It runs projects sequentially,
rejects zero tests, rejects any skipped or failed test, requires exact test
names, invokes finite-property proof mode plus the available tier check, and
compares two independent WASM-DOM emissions byte-for-byte.

## Target topology

The smallest intended deployment has two public hostnames and one private
origin:

1. `admin.<domain>` is a Cloudflare Worker with Static Assets. Its Worker-side
   `/api/*` gateway validates the Cloudflare Access JWT before forwarding a
   narrow request through a Cloudflare Tunnel to Firebat One.
2. Firebat One hosts the LOGOS gateway and PostgreSQL on loopback/private
   interfaces. The origin validates the Access assertion again, maps transport
   identity to a MaCSad actor/capability, and never trusts a browser-supplied
   identity header.
3. `www.<domain>` is a separate public Worker with Static Assets. It receives
   only an immutable, sealed, public-safe projection. It has no database,
   tunnel, private repository, OpenRouter, or admin binding.

Workers VPC is not the baseline because it remains a beta dependency. A
Cloudflare Tunnel is the stable private-origin boundary. Static Asset requests
do not themselves carry trusted application identity, so the Worker must check
`Cf-Access-Jwt-Assertion`; Access is not replaced by hiding the origin URL.

The current LOGOS release cannot yet express header-aware authenticated HTTP,
typed browser mutations, or a PostgreSQL adapter. Those RED framework contracts
are tracked in [`LOGOS_GAPS.md`](../LOGOS_GAPS.md). Until they are implemented and
promoted into a new exact toolchain lock, there is no mutation deployment and no
JavaScript or GET-mutation workaround.

## Credential and trust boundaries

No credential exists in this repository. When the platform is ready, create
GitHub environments named `staging` and `production`; require human approval for
production. Configure values in their narrowest owner:

| Name | Location | Scope |
|---|---|---|
| `LOGOS_REPOSITORY_TOKEN` | GitHub Actions secret | Read only the private LOGOS repository; no MaCSad write permission. |
| `CLOUDFLARE_API_TOKEN` | GitHub environment secret | Deploy only the named MaCSad Workers and their versions; no account-wide administration. |
| `CLOUDFLARE_ACCOUNT_ID` | GitHub environment variable | Select the intended account; it is not an authentication secret. |
| Access audience and issuer | Admin Worker and Firebat secret stores | Validate the one admin Access application. |
| Tunnel token | Firebat service secret store | Run only the named admin-origin tunnel; never expose it to GitHub jobs or agents. |
| Origin service credential | Worker and Firebat secret stores | Dedicated Worker-to-origin authentication, rotated independently from human Access. |

Agents receive none of these values. A human configures them through GitHub and
Cloudflare control planes. Logs must redact authentication headers and must not
serialize the environment.

## Release gates to add after credentials exist

The future required check must fail fast in this order:

1. Preflight exact versions and digests for Node, the browser, rustc, cargo,
   LOGOS source/Cargo lock/largo binary, Wrangler, and every action/container.
2. Run the current governance, format, deep-check, exact-test, proof,
   deterministic-build, and clean-PostgreSQL gates.
3. Run real adapter contracts. This includes an explicitly selected ignored
   HTTP differential suite; an ignored test that was never selected is not
   evidence.
4. Run browser acceptance and accessibility suites against a real preview,
   including loading, empty, validation, stale-version, duplicate-submit,
   denial, server failure, keyboard, focus, contrast, reduced-motion, and
   responsive states.
5. Build admin and public artifacts once. Record their SHA-256 manifest, source
   revision, schema compatibility range, and locked toolchain closure. Deploy
   those same bytes; do not rebuild in the deployment job.
6. Generate an artifact attestation, deploy a preview/version, execute smoke
   checks, and only then promote the version after environment approval.

The planned workflow actions are exact commits, not tags:

| Component | Pinned release |
|---|---|
| `actions/checkout` | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` (`6.0.2`) |
| `actions/upload-artifact` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (`7.0.1`) |
| `actions/download-artifact` | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` (`8.0.1`) |
| `actions/attest-build-provenance` | `1e69f48acb82d1966a394da916b4c1698aa569d6` (`4.2.2`) |
| `cloudflare/wrangler-action` | `ebbaa1584979971c8614a24965b4405ff95890e0` (`4.0.0`) |
| Wrangler | exact package version `4.127.1` |

These pins are a reviewed readiness record, not permission to deploy. Recheck
their upstream provenance and compatibility when the deployment workflow is
implemented.

## Admin release

The first deployment workflow will be manual. It must reject missing secrets,
an unexpected repository/ref/environment, a dirty artifact manifest, an
unapproved production environment, or a failed Access/origin smoke test before
promotion. A push may produce a tested candidate, but it does not automatically
grant production authority.

Cloudflare Access protects the admin hostname. The admin Worker forwards only
an allowlisted method/path/body contract, strips caller-supplied identity
headers, inserts its validated reserved assertion, sets strict body/time limits,
and never retries a non-idempotent command without the original idempotency key.

Rollback promotes the preceding known-good Worker version and immutable asset
manifest. Database rollback is never destructive: releases declare an inclusive
schema compatibility range and schema fixes roll forward with the next numbered
migration.

## Public publication

The daily job is not a blind cron deployment. A controller on Firebat creates a
publication candidate from eligible, closed cases; fails closed on private or
unclassified content; records the evidence closure; and awaits the required
seal/editorial decision. A sealed batch dispatches a narrow GitHub workflow with
its immutable batch and manifest digest. The workflow verifies those exact
bytes, publishes them to the public Worker, smoke-tests the deployment, and only
then advances the publication head.

An empty or rejected batch publishes nothing and leaves the existing public
head intact. The public site never calls the admin origin at runtime.

## Readiness checklist

Do not enable a live workflow until all boxes are backed by executable evidence:

- [ ] The Cloudflare account, zone, final hostnames, Access application, and
      GitHub environment owners are confirmed.
- [ ] A real organization/team slug is confirmed before adding `CODEOWNERS`; no
      team name is invented in this baseline.
- [ ] Private LOGOS checkout works in a least-privilege CI job and its exact
      source/toolchain closure is attested.
- [ ] Header-aware LOGOS HTTP, typed browser command transport, and PostgreSQL
      adapter acceptance contracts are green.
- [ ] Firebat PostgreSQL and tunnel services are enabled at boot, active, and
      tested after a restart.
- [ ] Admin Access, double validation, origin allowlisting, and negative tests
      are green.
- [ ] Preview, promotion, smoke, rollback, and sealed-publication paths are green
      using non-production test resources.
- [ ] Branch and environment protections require the complete release check and
      human production approval.

Until then, `Foundation CI` is the only checked-in workflow and performs no
external write.
