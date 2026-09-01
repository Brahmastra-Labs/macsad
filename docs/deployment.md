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

The checked-in Firebat2 ingestion and reusable verification workflows define
the next gate, but `FIREBAT2_ENABLED=false` and Firebat2 has no runner,
disposable VM controller, QEMU tooling, browser, or system Node installation.
They cannot produce execution evidence today. The capacity-one design and
activation boundary are in
[`docs/decisions/0002-firebat2-pipeline.md`](./decisions/0002-firebat2-pipeline.md).

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

## Firebat deployment topology

The private development environment is the checked-in Docker Compose project
at `ops/compose/compose.yaml`. Follow [`GETTING_STARTED.md`](../GETTING_STARTED.md)
for initial setup and [`docs/runbooks/`](./runbooks/) for routine operation,
upgrades, backup, restore, and incidents.

The steady state has four running containers plus one successful one-shot job:

| Service | Contract |
|---|---|
| `postgres` | PostgreSQL 16.15, durable named volume, internal `data` network only, no host-published database port |
| `migrate` | Waits for database health, applies checksum-locked migrations, verifies the schema, exits zero, and gates application startup |
| `logos-gateway` | Exact staged `largo` binary plus staged gateway source; currently serves only the LOGOS health contract and has no PostgreSQL adapter or mutation route |
| `logos-sites` | Unprivileged, read-only static server containing only emitted LOGOS admin/public bundles; shares the gateway network namespace |
| `pgadmin` | Authenticated database viewer with MFA; preconfigured to use ACL-constrained `macsad_viewer` with a read-only session default and strict timeouts |

Compose publishes exactly three endpoints on `MACSAD_BIND_IP`, which
`stack.sh configure` verifies is assigned to Firebat's Tailscale client:

- `18080`: admin site and same-origin health proxy;
- `18082`: public-site preview; and
- `8978`: pgAdmin.

The stack does not bind these ports to `0.0.0.0`, a LAN address, a public
interface, or Tailscale Funnel. Headscale identity and ACLs are the network
boundary for Alejandro and the other authorized team members. PostgreSQL stays
inside Compose and must never gain a `5432` host mapping.

The local `logicaffeine-private` checkout is a build input, not a runtime
mount. Before building, `stack.sh prepare` verifies the exact locked source,
toolchain, tests, and deterministic outputs. It stages only the exact `largo`
binary, emitted admin/public bundles, gateway manifest/source, and database
migration inputs into a revision-specific, digest-recorded directory. Image
builds consume only that staged closure; the private repository and developer
home directory are absent from running containers.

Cloudflare remains a separate production/publication destination. No
Cloudflare credential, ingress route, or public hostname is required by this
Firebat environment.

The current LOGOS release cannot yet express header-aware authenticated HTTP,
typed browser mutations, or a PostgreSQL adapter. Those RED framework contracts
are tracked in [`LOGOS_GAPS.md`](../LOGOS_GAPS.md). Until they are implemented and
promoted into a new exact toolchain lock, there is no mutation deployment and no
JavaScript or GET-mutation workaround.

## Credential and trust boundaries

No credential exists in this repository. When the platform is ready, create
GitHub environments named `staging` and `production` to scope credentials,
deployment history, and concurrency. Ordinary non-control-plane merge and
application promotion are autonomous after the required deterministic checks;
neither environment has a routine human approval gate. A control-plane change
first needs independent machine policy activation. Configure values in their
narrowest owner:

| Name | Location | Scope |
|---|---|---|
| `LOGOS_REPOSITORY_TOKEN` | GitHub Actions secret | Read only the private LOGOS repository; no MaCSad write permission. |
| `CLOUDFLARE_API_TOKEN` | GitHub environment secret | Deploy only the named MaCSad Workers and their versions; no account-wide administration. |
| `CLOUDFLARE_ACCOUNT_ID` | GitHub environment variable | Select the intended account; it is not an authentication secret. |
| Access audience and issuer | Future admin Worker and origin secret stores | Validate the one production admin Access application. |
| Origin service credential | Future Worker and origin secret stores | Dedicated Worker-to-origin authentication, rotated independently from human Access. |

Agents and the credential-free verifier receive none of these values. An
operator bootstraps them through GitHub and Cloudflare control planes; only the
fixed-function deployer identity may use the narrow environment credential.
Logs must redact authentication headers and must not serialize the environment.

## Release gates to add after credentials exist

The future Cloudflare release check must fail fast in this order:

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
   checks, and promote automatically only when every environment invariant is
   green.

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

## Cloudflare application release

The deployment workflow is separate from verification. A credential-free
Firebat2 verifier emits an exact byte manifest; a fixed-function deployer accepts
only a successful verifier identity, independently verifies that manifest, and
promotes those same bytes without checking out or compiling source. It must
reject missing secrets, an unexpected repository/ref/environment, a dirty
manifest, an incompatible schema range, or a failed Access/origin smoke test.
The narrow deploy credential cannot enter the verifier guest.

After those gates exist, a successful `main` candidate may deploy
automatically. No human approval click is required for an ordinary application
release. The emergency disable switch, credential rotation, runner-image
changes, and destructive data recovery remain operator actions.

Cloudflare Access must protect any future admin hostname. Its exact origin
transport remains a separately reviewed deployment decision. The admin Worker
forwards only an allowlisted method/path/body contract, strips caller-supplied
identity headers, inserts its validated reserved assertion, sets strict
body/time limits, and never retries a non-idempotent command without the
original idempotency key.

Rollback promotes the preceding known-good Worker version and immutable asset
manifest. Database rollback is never destructive: releases declare an inclusive
schema compatibility range and schema fixes roll forward with the next numbered
migration.

Only after staging and that rollback artifact exist, add two Firebat2 schedules:
a small black-box smoke against the currently deployed staging manifest at
off-hour minutes, and a nightly backup restore plus compatibility/rollback drill
using disposable storage. Both share Firebat2's capacity-one queue. Scheduled
checks monitor deployed state; they never replace exact per-main-SHA verification
and never trigger research publication.

## Public publication

Application deployment and research publication are different authorities. A
platform release may be automatic after CI, but it cannot make a finding public.
The daily research job creates a publication candidate only from eligible,
closed cases, fails closed on private or unclassified content, records the
evidence closure, and obtains the domain-policy seal. A sealed batch dispatches
a narrow GitHub workflow with its immutable batch and manifest digest. The
workflow verifies those exact bytes, publishes them to the public Worker,
smoke-tests the deployment, and only then advances the publication head.

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
- [ ] Docker Engine, Tailscale, and the four long-running Compose services are
      healthy after a Firebat restart; the migrator completes successfully.
- [ ] Only Firebat's exact tailnet address publishes `18080`, `18082`, and
      `8978`; PostgreSQL has no published host port and no Funnel is enabled.
- [ ] Admin Access, double validation, origin allowlisting, and negative tests
      are green.
- [ ] Preview, promotion, smoke, rollback, and sealed-publication paths are green
      using non-production test resources.
- [ ] Branch and environment protections require the complete release check,
      exact-artifact promotion, and autonomous failure-closed deployment.

Until then, Foundation is the only executable GitHub gate. Firebat2 workflows
remain disabled, and no checked-in workflow performs an external deployment
write.
