# ADR 0001: Firebat development runs as a private Compose stack

Status: accepted

## Context

MaCSad needs a continuously available PostgreSQL authority, a LOGOS backend and
sites, and a safe browser database viewer on owned Firebat hardware. The current
LOGOS gateway binds loopback and remains health-only. Human access is through a
self-hosted Headscale/Tailscale network.

## Decision

Run four long-lived containers—PostgreSQL 16, LOGOS gateway, LOGOS sites, and
pgAdmin—with a one-shot migration service. PostgreSQL has no host port. The
sites container shares the gateway network namespace only because the pinned
gateway cannot yet select a non-loopback bind address. Admin, public preview,
and pgAdmin bind only to Firebat's verified tailnet IPv4.

Builds verify the exact local Logicaffeine source and stage only admitted
artifacts, gateway files, migrations, and the exact runtime binary. No private
checkout or Docker socket enters a running container.

## Consequences

- Firebat needs one privileged Docker/Tailscale bootstrap and Headscale
  enrollment.
- pgAdmin is a human inspection tool, never a domain API.
- The shared-network-namespace compatibility measure is removed when the LOGOS
  bind-address gap is fixed and promoted.
- Current runtime proves environment health, not PostgreSQL-backed CRUD.
- Container and tailnet upgrades are reviewed, pinned, and operator-driven.
