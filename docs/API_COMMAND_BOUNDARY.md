# MaCSad API and command boundary

This is the application boundary for the first MaCSad vertical slices. It keeps
the interface useful without turning the PostgreSQL schema into a remote table
editor.

## Meaning of complete CRUD

Complete CRUD means that a Director can finish each supported job through its
whole safe lifecycle. It does not mean exposing `POST`, `PATCH`, and `DELETE`
for every table.

- Mutable records use narrow commands with an expected version.
- Immutable records are created and read; corrections append a superseding
  record.
- Compiled policy, evidence, finance, audit, and publication-closure records
  have no generic write endpoint.
- Retirement, revocation, cancellation, and supersession replace destructive
  deletion.
- A board movement is a process transition command, never a direct column
  update.

## Command envelope

Every mutation uses one versioned envelope:

```json
{
  "schema": "macsad-command/1",
  "idempotency_key": "018f...",
  "expected_version": 7,
  "payload": {}
}
```

The authenticated transport supplies the actor and workspace. A request body
cannot choose either authority.

One PostgreSQL transaction must authenticate the identity, check the narrow
capability, acquire the command receipt, compare the request digest and
aggregate version, evaluate LOGOS policy, apply the allowlisted mutation,
append the domain event and any outbox request, persist the canonical result,
and commit. External network and process effects occur only after commit.

Reusing a key and digest returns the original result. Reusing a key with a
different digest fails. A stale aggregate version fails without a partial
write.

## Initial read and command surface

| Area | Reads | Commands |
|---|---|---|
| Workspace | workspace, exact snapshots, reconciliation status | onboard, update metadata, pause, resume, reconcile |
| Tool repositories | approved tools, immutable revisions, sealed operations | register, update metadata, resolve, promote, activate, disable |
| Policy | active/candidate revision, process graph, roles, decision matrices | compile candidate, activate reviewed revision |
| Virtual people | actors, memberships, role inboxes, capabilities | create, rename, pause, retire, bind/revoke identity, grant/revoke capability |
| Problems | immutable problem revisions | create revision, supersede with a new revision |
| Cases and board | board projection, case detail, current process node | create, prioritize, pause, block, resume, close |
| Tasks and handoffs | task detail, transition history, assignment state | offer, accept, reject, release, complete-and-transition |
| Chats | thread and ordered messages | append, reply, correct, archive thread |
| Execution and evidence | attempts, artifacts, claims, attestations | claim lease, heartbeat, complete attempt, submit claim, attest |
| Budget and model usage | balances, reservations, exact OpenRouter variance | create account, adjust limit, reserve, settle, reconcile charge |
| Publication | eligibility, preview, batch, catalog, deployment status | select, preview, seal, dispatch, retry, publish erratum |
| Operations | audit timeline, inbound deliveries, outbox and worker health | reconcile delivery, retry allowed effect, emergency stop |

No v1 endpoint deletes evidence, ledger entries, messages, events, audit links,
snapshots, policy projections, repository revisions, or publication items.

## Response classes

- `200` completed command or exact idempotent replay
- `201` newly created resource or immutable fact
- `202` accepted outbox-backed external work
- `400` malformed transport or envelope
- `401` missing or invalid identity
- `403` authenticated but capability denied
- `404` aggregate absent within the authenticated workspace
- `409` stale version, illegal state, or idempotency conflict
- `422` syntactically valid but invalid domain facts

Each error is typed and carries a stable code, correlation identifier, and the
current aggregate version when disclosure is safe.

## First executable slice

The first real write slice is one task-thread message:

1. read one task and its thread;
2. submit one idempotent append-message command;
3. authorize and commit the message plus audit event in PostgreSQL;
4. refetch the authoritative thread;
5. prove duplicate submission returns the original result;
6. prove changed payload, stale version, missing capability, and cross-workspace
   identifiers fail without writes.

This slice stays RED until LOGOS has a typed browser request API, header-aware
HTTP request/response bridge, and typed PostgreSQL transaction adapter. Their
acceptance contracts are in [`LOGOS_GAPS.md`](../LOGOS_GAPS.md).
