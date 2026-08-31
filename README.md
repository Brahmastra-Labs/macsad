# MaCSad

**MaCSad — Mathematics and Computer Science Auto-Discovery** is a controlled research framework for producing reproducible, inspectable progress on bounded mathematics and computer-science problems.

MaCSad is designed to preserve every question, attempt, artifact, verification result, decision, and publication while preventing agents from treating plausible output or successful execution as verified truth.

> **Current status: design only. Implementation has not started.**
>
> This private repository is the trusted MaCSad platform and design repository. It does not yet contain a working service, user interface, deployment, or research runtime.

## Design document

The architecture, workflow model, security boundaries, acceptance criteria, and phased implementation plan are in [design_document.md](./design_document.md).

## Core model

- One connected GitHub repository is one research project and workspace.
- Every task, run, artifact, and conclusion is pinned to an exact workspace commit.
- A Kanban board and navigable process graph jointly control research work.
- Virtual roles—initially Director, Investigator, and Verifier—work through explicit assignments, task threads, handoffs, budgets, and decision matrices.
- Creative discovery is kept separate from independent checking and publication approval.
- Agents may propose actions and produce evidence, but cannot approve their own budgets, claims, or publications.
- Only approved, sealed research batches become public.

## Planned architecture

MaCSad will be implemented primarily in **LOGOS**, using an exact reviewed and promoted version of the private `logicaffeine-private` toolchain.

The proposed system includes:

- a LOGOS control server as the sole policy and state-transition authority;
- PostgreSQL for operational state and append-only, hash-chained audit history;
- content-addressed storage for immutable artifacts and workspace snapshots;
- isolated, credential-free research workers on Firebat One;
- a private Cloudflare-protected admin application;
- a separately generated public static research site;
- a read-only GitHub App for watched research repositories; and
- GitHub Actions pipelines for validation and gated Cloudflare deployment.

Small trusted host adapters may provide mechanical capabilities such as database access, GitHub API calls, process isolation, and deployment handoff. Research policy, workflow decisions, verification rules, and publication eligibility remain MaCSad-owned logic.

## Initial implementation path

1. Build, test, pin, and promote the complete LOGOS toolchain closure.
2. Prove one mathematics and one computer-science discovery-and-verification vertical slice.
3. Add watched-repository integration and the minimal board/thread interface.
4. Introduce the initial virtual roles and restricted MCP surface.
5. Deploy the protected admin application.
6. Add signed, sealed public publication batches.

Until these milestones begin, this repository should be treated as an architectural starting point rather than an operational research system.
