# MaCSad

**MaCSad — Mathematics and Computer Science Auto-Discovery** is a controlled research framework for producing reproducible, inspectable progress on bounded mathematics and computer-science problems.

MaCSad is designed to preserve every question, attempt, artifact, verification result, decision, and publication while preventing agents from treating plausible output or successful execution as verified truth.

> **Current status: design plus the canonical greenfield PostgreSQL schema and lifecycle tooling. Application implementation has not started.**
>
> This private repository is the trusted MaCSad platform and design repository. It does not yet contain a working service, user interface, deployment, or research runtime. PostgreSQL provisioning on Firebat One remains an explicit infrastructure step until the native service checks pass.

## Design document

The architecture, workflow model, security boundaries, acceptance criteria, and phased implementation plan are in [design_document.md](./design_document.md).

The product contract is in [user_story.md](./user_story.md), the relational model and ERDs are in [domain_model.md](./domain_model.md), and the database lifecycle contract is in [database/README.md](./database/README.md).

## Core model

- One watched GitHub repository is the sole research project and primary workspace.
- Approved tool repositories, such as the local LOGOS source, are read-only dependencies rather than additional projects; each case pins an exact preserved revision with `source_read` or `operation_invoke` access, and invocation additionally requires a promoted bundle plus sealed operation catalogue.
- Every case and execution is pinned to an exact primary-workspace snapshot, policy revision, problem revision, and tool-dependency closure.
- A Kanban board and navigable process graph jointly control research work.
- Virtual roles—initially Director, Investigator, and Verifier—work through explicit assignments, task threads, handoffs, budgets, and decision matrices.
- Creative discovery is kept separate from independent checking and publication approval.
- Agents may propose actions and produce evidence, but cannot approve their own budgets, claims, or publications.
- Publication items are selected only in draft, preview freezes the closure and audit head, sealing freezes the signed manifest, and only a successful deployment can produce a published batch and public head.

The current `0001` schema contains 47 tables including its migration ledger, 50 native enum types, and six read views: `case_board_v`, `budget_balance_v`, `model_cost_variance_v`, `publication_catalog_v`, `audit_timeline_v`, and `schema_version_v`.

## Planned architecture

MaCSad will be implemented primarily in **LOGOS**, using an exact reviewed and promoted version of the private `logicaffeine-private` toolchain.

The proposed system includes:

- a LOGOS control server as the sole policy and state-transition authority;
- one PostgreSQL 16 cluster on Firebat One for operational state, exact provider spend, schema history, and append-only hash-chained audit history;
- content-addressed storage for immutable artifacts and workspace snapshots;
- isolated, credential-free research workers on Firebat One;
- a private Cloudflare-protected admin application;
- a separately generated public static research site;
- a read-only GitHub App for watched research repositories; and
- GitHub Actions pipelines for validation and gated Cloudflare deployment.

Small trusted host adapters may provide mechanical capabilities such as database access, GitHub API calls, process isolation, and deployment handoff. Research policy, workflow decisions, verification rules, and publication eligibility remain MaCSad-owned logic.

## Initial implementation path

1. Build, test, pin, and promote the complete LOGOS toolchain closure.
2. Provision and verify the always-on PostgreSQL 16 service, then apply the canonical `0001` schema.
3. Prove one mathematics and one computer-science discovery-and-verification vertical slice.
4. Add watched-repository integration and the minimal board/thread interface.
5. Introduce the initial virtual roles and restricted MCP surface.
6. Deploy the protected admin application.
7. Add signed, sealed public publication batches.

Until these milestones begin, this repository should be treated as an architectural starting point rather than an operational research system.
