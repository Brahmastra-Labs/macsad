# MaCSad runbooks

Runbooks are executable operator procedures, not architecture proposals. Keep
commands copyable, preconditions explicit, secrets out of examples, and success
criteria mechanical.

| Runbook | Use it for |
|---|---|
| `firebat-stack.md` | Host bootstrap, Tailnet enrollment, start/stop, health and upgrades |
| `database-operations.md` | Migrations, read-only inspection, backup/restore and credential rotation |
| `testing-and-ci.md` | Local gates, CI evidence, failure triage and adding tests |
| `incident-response.md` | Containment, evidence preservation, recovery and post-incident work |

The quick path is `GETTING_STARTED.md`. If a runbook and executable behavior
disagree, stop and fix the contract; do not improvise around it.
