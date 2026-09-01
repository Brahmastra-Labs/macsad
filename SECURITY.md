# MaCSad security policy

MaCSad is a private research-control system. Security reports, suspected secret
exposure, authorization failures, unsafe publication, and evidence-integrity
problems are treated as release blockers.

## Reporting

Do not open a public issue containing exploit details, credentials, private
repository material, research artifacts, or personal data. Notify the
Brahmastra Labs repository owners through the private organization channel and
include only the minimum evidence needed to reproduce the issue.

If a credential may have been exposed:

1. stop using it;
2. identify its narrow owner and scope;
3. rotate or revoke it in that control plane;
4. preserve relevant audit evidence without copying secret values;
5. search Git history, CI logs, container configuration, and runtime logs for
   exposure; and
6. record the remediation and any required follow-up test.

Deleting the visible string is not sufficient remediation.

## Trust boundaries

- PostgreSQL is never published on a host port.
- Admin and database-viewer traffic is private to the approved tailnet during
  development. Tailnet membership alone does not replace ACLs or application
  login.
- Public output is generated from a sealed public-safe closure and has no
  database or private-origin access.
- Agents do not receive database, Headscale, GitHub, Cloudflare, OpenRouter, or
  private-repository credentials.
- pgAdmin uses individual human accounts, required MFA, a read-only database
  role, and no saved database password.
- Docker-group membership on Firebat is root-equivalent and restricted to
  approved human operators. Untrusted pull-request or agent-generated container
  definitions never run under it.
- All pulled container images and GitHub Actions are immutable-digest pinned.
  Local application images are tagged by the exact clean source revision and
  built only from admitted staged inputs.

## Unsupported shortcuts

Never work around an access or framework problem by adding a public port,
wildcard bind, LAN bind, Funnel, shared superuser account, committed `.env`, raw
SQL endpoint, GET mutation, disabled authorization, or broad database grant.

For operational containment and recovery, follow
`docs/runbooks/incident-response.md`.
