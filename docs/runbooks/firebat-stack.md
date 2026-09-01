# Firebat stack runbook

## Preconditions

- Firebat is Ubuntu 24.04 amd64.
- An approved human can authenticate with sudo.
- The Headscale control-server HTTPS URL and ACL owner are known.
- The MaCSad and pinned Logicaffeine checkouts are clean.

## First host bootstrap

```bash
sudo bash ops/firebat/bootstrap_container_host.sh \
  --login-server=https://YOUR-HEADSCALE-CONTROL-SERVER
```

Reconnect, then verify exact services and enrollment:

```bash
docker version
docker compose version
systemctl is-enabled docker tailscaled
systemctl is-active docker tailscaled
tailscale status
tailscale ip -4
```

The bootstrap adds `alejandro` to the root-equivalent `docker` group. Do not
use that account to execute untrusted pull-request branches or arbitrary image
definitions. The script writes the reviewed Docker log/restore policy only
when `/etc/docker/daemon.json` is absent; if it already exists, stop and review
the existing daemon policy rather than overwriting it.

Ask the Headscale administrator to grant only the intended human identities
access to Firebat TCP ports `18080`, `18082`, and `8978`. Never enable Funnel.

## Configure and launch

```bash
bash scripts/dev.sh configure \
  --logos-workspace /home/alejandro/projects/logicaffeine-private \
  --pgadmin-email YOUR-REAL-OWNER-EMAIL
make doctor
make up
```

Success means `make up` exits zero after all of these checks:

- PostgreSQL is healthy but has no published host port;
- the migration service exited successfully;
- schema version is exactly supported by this checkout;
- LOGOS gateway health is served through the admin site;
- both LOGOS sites load from the configured tailnet address; and
- pgAdmin `/misc/ping` responds.

## Live access acceptance

Before calling shared access ready, complete and record all of these human
checks without recording passwords:

1. The named pgAdmin owner signs in with the generated bootstrap password,
   enrolls authenticator MFA, and creates a separate MFA-enrolled account for
   every other approved human.
2. The owner, Alejandro, and Collin each reach only the approved tailnet ports
   from their own authorized identity; no LAN or internet route succeeds.
3. A tailnet identity omitted from the Headscale ACL cannot reach any of the
   three ports.
4. `make verify` proves exact published addresses, no PostgreSQL host port,
   the viewer login/defaults, and ACL-backed write denial.

Offboarding is two-boundary work: revoke the person's Headscale access/device,
disable their pgAdmin account, and rotate the shared `macsad_viewer` database
credential because a former user may remember it. Confirm the old tailnet path,
pgAdmin login, and database password all fail.

## Routine operation

```bash
make status
make verify
bash scripts/dev.sh logs logos-gateway
bash scripts/dev.sh logs postgres
make down
```

`make down` preserves the named PostgreSQL and pgAdmin volumes. There is no
supported “down with volumes” command.

## Restart and persistence acceptance

After first launch and after a Docker upgrade:

```bash
make verify
sudo systemctl restart docker
make verify
make down
make up
make verify
```

The first restart proves `restart: unless-stopped`; the down/up cycle proves
the schema and pgAdmin account state survive container replacement through the
named volumes. Confirm an existing individual pgAdmin account still signs in
with MFA. Do not use `down -v` in this test.

## Upgrade application images

1. Pull the reviewed MaCSad commit with `git pull --ff-only`.
2. Confirm the Logicaffeine lock or promote a separately reviewed lock change.
3. Run `PGADMIN_DEFAULT_EMAIL=YOUR-REAL-OWNER-EMAIL make configure` to bind
   runtime state to the new exact source revision.
4. Run `make test`.
5. Take and verify a database backup when the change includes stateful images or
   migrations.
6. Run `make up`; it stages and builds exact new images before replacement.
7. Run `make verify` and inspect bounded logs.

Never use Watchtower, floating tags, or an unattended stateful image upgrade.

## Upgrade Docker or Tailscale packages

The bootstrap holds the exact reviewed packages. To upgrade, first review the
release notes and update the version constants in
`ops/firebat/bootstrap_container_host.sh` through a tested pull request. At an
approved maintenance window, take/verify a database backup, then run:

```bash
sudo apt-mark unhold \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
  docker-compose-plugin tailscale
sudo bash ops/firebat/bootstrap_container_host.sh \
  --login-server=https://YOUR-HEADSCALE-CONTROL-SERVER
```

The bootstrap installs the newly reviewed exact versions and re-applies the
holds. Reconnect, then run `make up` and `make verify`. Do not run a general
unattended distribution upgrade as a substitute for this procedure.

## Network failure checks

```bash
tailscale status
tailscale netcheck
tailscale ip -4
ss -ltn
```

If the configured address is no longer assigned, stop the stack, rerun
`configure`, and review Headscale ACLs. Do not fall back to `0.0.0.0` or the LAN.
