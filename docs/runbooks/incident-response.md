# Incident response runbook

## Priorities

1. Protect people and private research material.
2. Stop unauthorized effects without destroying evidence.
3. Preserve exact logs, revisions, event positions, and artifact digests.
4. Restore a known-good, verified service.
5. Correct the cause with an executable regression test.

## Immediate containment

For suspected admin/viewer exposure, revoke the relevant Headscale ACL or take
the affected service down:

```bash
make status
make down
```

Do not delete volumes, rewrite Git history, truncate audit tables, or remove
logs as a first response. For credential exposure, revoke/rotate the narrow
credential at its owner before restarting consumers.

## Preserve evidence

Record without secret values:

- incident time range and reporting identity;
- current MaCSad and LOGOS revisions;
- `docker compose ps` state and exact image IDs;
- bounded service logs;
- Headscale/Tailscale device and ACL changes;
- migration/schema version;
- domain-event, audit, and outbox positions; and
- artifact/batch digests implicated in the incident.

Store evidence in the approved private incident location, not a public issue or
agent prompt.

## Recovery

1. Fix or revoke the compromised boundary.
2. Run the targeted regression test and `make test`.
3. Restore or deploy the exact reviewed revision.
4. Run `make up` and `make verify`.
5. Confirm old credentials/access paths fail.
6. Monitor logs and domain events for recurrence.

Database recovery uses the separate restore rehearsal in
`database-operations.md`; never improvise a live row merge.

## Follow-up

Write a private post-incident record with cause, timeline, impact, detection,
containment, recovery, and specific preventive work. Every preventive claim
must map to an owner and an executable test, policy, or alert.
