# Claude operating guide for MaCSad

`AGENTS.md` is the canonical engineering constitution for every coding agent.
Read it completely before acting. This file adapts that contract for Claude
Code and Claude-family tools without creating a second set of rules.

## Start every task this way

1. Read `AGENTS.md`, `GETTING_STARTED.md`, and the nearest relevant design or
   runbook document.
2. Inspect `git status --short`, the current branch, and the exact files in
   scope. Existing changes belong to the user unless proven otherwise.
3. State the narrow outcome and identify its executable acceptance test.
4. Check `LOGOS_GAPS.md` before assuming the framework can perform a transport,
   HTTP, browser, database, proof, or test-runner operation.
5. Work RED → GREEN → REFACTOR and run the smallest real test first.
6. Run `make test` before handoff. If database or browser evidence could not run,
   state that boundary exactly.

## Architectural routing

| Concern | Correct home |
|---|---|
| UI, state machine, authorization or research decision | LOGOS `.lg` source |
| Durable invariants and atomic live state | PostgreSQL migration/constraint |
| Mechanical I/O unavailable in LOGOS | Narrow host adapter plus contract test |
| Local multi-service lifecycle | `ops/compose/` and `scripts/dev.sh` |
| Human operations and recovery | `docs/runbooks/` |
| Framework defect or missing primitive | `LOGOS_GAPS.md` with a reproducer |

Do not move policy into Bash, Python, JavaScript, Rust, Nginx, Compose, or a
database-viewer configuration. Infrastructure can route, authenticate,
persist, limit, and observe; LOGOS remains the domain-decision authority.

## Firebat and secrets

- Firebat is owned infrastructure, not a disposable CI runner. Preserve its
  unrelated processes, volumes, repositories, and user changes.
- Use `scripts/dev.sh` or `make`; do not invent an alternate start/test path.
- Never expose PostgreSQL on a host port.
- Never bind admin or pgAdmin to `0.0.0.0` or the LAN address. The configured IP
  must be an address reported by `tailscale ip -4`.
- Never read, print, paste, log, or commit `.runtime/compose/secrets/*` unless a
  human explicitly asks to retrieve one for an operational login.
- Never pass Docker socket, host credentials, private repository credentials,
  or deployment credentials into an agent container.
- Do not run destructive volume commands. The supported harness deliberately
  provides none.

## Evidence language

Use only claims supported by the gate that actually ran:

- “source guardrails passed” is not “LOGOS compiled”;
- “LOGOS tests passed” is not “browser behavior passed”;
- “pg_isready passed” is not “schema migration passed”;
- “Compose config rendered” is not “containers ran”;
- “health returned 200” is not “CRUD is implemented”; and
- “agent output looks plausible” is never mathematical verification.

Treat zero discovered tests, skipped tests, missing tools, unavailable adapters,
or silently omitted tiers as failures—not as green evidence.

## Handoff

Report:

1. the outcome and exact commit;
2. changed files grouped by responsibility;
3. tests and runtime checks actually executed;
4. skipped/unavailable evidence and why;
5. operational state changed on Firebat; and
6. the smallest safe next step.

Do not claim completion while the working tree is dirty, required work is
unstaged, the pushed revision differs from the tested revision, or a required
service is unhealthy.
