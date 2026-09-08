# MaCSad runbooks

Runbooks are executable operator procedures, not architecture proposals. Keep
commands copyable, preconditions explicit, secrets out of examples, and success
criteria mechanical.

| Runbook | Use it for |
|---|---|
| `agent-request-intake.md` | Agent entrypoint, bounded request flow, evidence lane and GitHub/Firebat2 handoff |
| `firebat-stack.md` | Host bootstrap, Tailnet enrollment, start/stop, health and upgrades |
| `firebat2-verification.md` | Capacity-one disposable KVM queue, activation hold, verifier/deployer split, continuous checks, host bumpers, and evidence |
| `database-operations.md` | Migrations, read-only inspection, backup/restore and credential rotation |
| `testing-and-ci.md` | Local gates, CI evidence, failure triage and adding tests |
| `upgrading-logos.md` | Human-authorized, immutable LOGOS candidate validation, promotion and rollback |
| `incident-response.md` | Containment, evidence preservation, recovery and post-incident work |

The quick path is `GETTING_STARTED.md`. If a runbook and executable behavior
disagree, stop and fix the contract; do not improvise around it.
