# Getting started with MaCSad

This is the shortest supported path from a fresh Firebat checkout to a tested,
private development environment. MaCSad uses one operator harness—`make` or
`scripts/dev.sh`—so local development, CI evidence, and runbook commands do not
drift into separate conventions.

## Defined Firebat environment

The checked-in Firebat environment defines four long-running containers and one
one-shot migration job:

| Component | Purpose | Host exposure |
|---|---|---|
| PostgreSQL 16.15 | Authoritative MaCSad domain database | None; Compose-internal only |
| LOGOS gateway | Current health-only LOGOS backend | None; shared with the sites container |
| LOGOS sites | Generated admin and public LOGOS applications | Tailnet ports `18080` and `18082` |
| pgAdmin 4 | Authenticated, read-only database inspection | Tailnet port `8978` |
| Migration job | Applies and verifies numbered migrations | Runs to completion, then exits |

The gateway still reports that persistence and mutations are unavailable. That
is intentional: authenticated browser mutation transport and the LOGOS
PostgreSQL adapter remain executable framework gaps in `LOGOS_GAPS.md`.
The live environment is not running until the one-time Docker/Tailscale
bootstrap and Headscale enrollment below are completed.

This runtime is Firebat One. Firebat2 is the separate test/deploy-pipeline host;
its checked-in lane remains disabled until its isolated one-job KVM runner
contract is provisioned and verified.

## Prerequisites

On Firebat One:

- Ubuntu 24.04 amd64;
- access to the private MaCSad and Logicaffeine repositories;
- the exact clean Logicaffeine checkout pinned by
  `.macsad/toolchains/logos.lock.toml`;
- one human who can authenticate with `sudo` for the host bootstrap;
- the HTTPS URL of the self-hosted Headscale control server; and
- approved tailnet identities and ACLs for the intended human operators.

Docker and Tailscale are not application dependencies checked into the repo.
The Firebat bootstrap installs exact verified versions and holds them until a
deliberate upgrade.

## 1. Inspect the checkout

```bash
ssh firebat-1
cd /home/alejandro/projects/Brahmastra-Labs/macsad
git status --short
git pull --ff-only
make doctor
```

On a new host, `make doctor` is expected to report missing Docker or tailnet
enrollment. It must not be made green with a LAN bind or wildcard port.

## 2. Bootstrap the Firebat host once

This requires Alejandro—or another approved human—to enter a sudo password:

```bash
sudo bash ops/firebat/bootstrap_container_host.sh \
  --login-server=https://YOUR-HEADSCALE-CONTROL-SERVER
```

Follow the interactive enrollment URL. Do not place a reusable Headscale auth
key in Git, shell history, an issue, or an agent prompt. After installation,
leave the SSH session and reconnect so Docker group membership is effective.
Membership in the `docker` group is effectively root-equivalent on Firebat.
Only approved human operators may hold it; never run untrusted branches,
pull-request code, or agent-provided container definitions with that authority.

Verify the host explicitly:

```bash
docker version
docker compose version
tailscale status
tailscale ip -4
```

Firebat must have a real tailnet IPv4 address before the stack is configured.
The LAN address `192.168.86.30`, `0.0.0.0`, and localhost are not substitutes
for shared access.

## 3. Configure ignored runtime state

The default LOGOS path on Firebat is detected automatically:

```bash
bash scripts/dev.sh configure \
  --logos-workspace /home/alejandro/projects/logicaffeine-private \
  --pgadmin-email YOUR-REAL-OWNER-EMAIL
```

Configuration verifies that the selected bind address belongs to Firebat's
Tailscale client. It creates `.runtime/compose/compose.env` and five random
secret files beneath `.runtime/compose/secrets/`, all ignored by Git. The
directory is mode `0700`; its files are mode `0444` because local Compose
file-backed secrets are bind mounts that must be readable by each container's
non-root UID. Only explicitly named secret files are mounted into each service.
Existing valid secrets are retained and no secret value is printed.

## 4. Test and start

```bash
make test
make up
```

`make up` does the complete work in order:

1. verifies the exact local LOGOS source, tree, lock file, binary, and tests;
2. emits deterministic admin/public bundles;
3. stages only the verified bundles, gateway source, migration files, and exact
   `largo` binary into the ignored build area;
4. builds locally tagged images from digest-pinned bases;
5. starts PostgreSQL and waits for readiness;
6. runs the checksum migration service and catalog verification;
7. starts the LOGOS gateway, sites, and pgAdmin; and
8. checks HTTP health and `macsad.schema_version_v`.

The private Logicaffeine checkout is never sent as a Docker build context or
mounted into a running container.

## 5. Open the private tools

Get Firebat's address without copying it into the repository:

```bash
TAILNET_IP="$(tailscale ip -4 | sed -n '1p')"
printf 'Admin:   http://%s:18080/\n' "${TAILNET_IP}"
printf 'Public:  http://%s:18082/\n' "${TAILNET_IP}"
printf 'pgAdmin: http://%s:8978/\n' "${TAILNET_IP}"
```

The tunnel is WireGuard-encrypted, but these initial development endpoints are
HTTP. Never route them onto the LAN or internet. Private TLS can be added only
after the Headscale environment's certificate/Serve behavior is verified.

For first pgAdmin login, an approved Firebat operator retrieves the bootstrap
password locally and shares it out of band:

```bash
sed -n '1p' .runtime/compose/secrets/pgadmin_admin_password
```

Immediately create individual pgAdmin accounts for each approved human and
complete required authenticator MFA. The pre-registered `MaCSad — Firebat —
read only` server uses `macsad_viewer`; enter its separate password per session:

```bash
sed -n '1p' .runtime/compose/secrets/macsad_viewer_password
```

pgAdmin is configured not to save database passwords. PostgreSQL grants and
role defaults enforce read-only access; the UI label is not the security
boundary.

## Everyday development

For an explicitly authorized connection to a working private LOGOS directory,
use [the development-directory runbook](docs/runbooks/local-logos-directory.md).
`scripts/dev.sh logos` runs that recorded executable. The standard `make test`,
doctor, and Compose commands retain the admitted release pin; connecting a
development directory does not change release admission or start services.

```bash
make help              # discover the supported commands
make doctor            # validate the workstation/Firebat prerequisites
make test              # run the complete available quality gate
make verify            # verify the running stack and schema
make status            # inspect container health
make logs              # follow bounded recent logs
make db-shell           # read-only psql session
make down               # stop containers; preserve both data volumes
```

Use a short branch, commit small coherent changes, and open a pull request. Each
commit is an immutable GitHub queue item. Protected `main` requires the strict
`Credential-free governance and PostgreSQL 16` check, administrator enforcement,
and linear history while forbidding force pushes and deletions. It requires zero
approving reviews and no last-pusher approval, so auto-merge may advance an
ordinary non-control-plane candidate as soon as its machine gates accept the
exact SHA. A control-plane candidate is held until an independent policy gate
evaluates it outside its replacement implementation.

Do not give an agent or Firebat2 verifier credentials to make that automation
work. When a deployment lane is enabled, a separate least-privileged deploy
identity must re-verify the admitted main-branch artifact and hash manifest.
Firebat2 currently stays disabled with `FIREBAT2_ENABLED=false` until its KVM
image/controller, restricted organization runner group, ephemeral cleanup, and
runner-management authority are ready. Human action is limited to
credential/bootstrap work, exceptional destructive actions, incident recovery,
and explicit editorial research publication; it cannot waive a failed required
gate.

The change loop and evidence rules are in `CONTRIBUTING.md`; agent-specific
rules are canonical in `AGENTS.md`.

## When something fails

Do not reset volumes, edit migration history, switch to a wildcard bind, or
weaken a test. Use the runbooks:

- `docs/runbooks/firebat-stack.md`
- `docs/runbooks/firebat2-verification.md`
- `docs/runbooks/database-operations.md`
- `docs/runbooks/testing-and-ci.md`
- `docs/runbooks/incident-response.md`
