# Proposal: independent control-policy activation check

Status: **proposal only; not implemented, installed, or authorized for activation**.
Requested by Alejandro on September 8, 2026. This document does not change the
constitution, branch protection, workflow definitions, test inventory, LOGOS
lock, Firebat2 enablement, or deployment permissions.

## 1. Outcome and current blocker

Provide one independent machine check that can decide whether a proposed
change to MaCSad's admission machinery is permitted to activate. The code under
consideration must not get to define the rules that accept that same change.

Current owning contracts:

- [`AGENTS.md`](../../AGENTS.md), Control-plane mutation boundary;
- [`agent-request-intake.md`](../runbooks/agent-request-intake.md), sections 2–3;
- [`upgrading-logos.md`](../runbooks/upgrading-logos.md), separate promotion lane;
- [`firebat2-verification.md`](../runbooks/firebat2-verification.md), disabled
  isolated-runner lane.

At inspection, protected `main` required pull requests, the strict
`Credential-free governance and PostgreSQL 16` check, administrator inclusion,
and linear history. Force pushes and deletions were disabled. Zero approving
reviews were required. The independent control-policy check was absent.

Delivery PR #6 contains changes to `scripts/quality-gate.sh` and
`tests/logos-module-manifest.json`. These add tests, but are still control-path
changes. Neither a successful local gate nor Foundation CI grants permission
to activate them. The PR must also repair any failing ordinary required check.

This is not a proposal to add mandatory human code review, remove the existing
hold, or let a human waive a failed check.

## 2. Proposed architecture

Use a separately administered GitHub App as the authoritative check writer.
Proposed check name: `MaCSad independent policy activation / v1`.
This name is not an installed check identity.

The authority's release, policy, dependency closure and tests must live outside
the candidate checkout and be pinned to immutable digests. Its installation ID
and numeric App ID must be recorded during bootstrap, not guessed here. Branch
protection must require the check from that specific App, not merely match its
display name.

The controller reads GitHub metadata and Git objects as data. It does not execute
candidate scripts, workflow expressions, package hooks, generated binaries or
imported policy while holding credentials. Any candidate execution belongs in a
disposable, unprivileged worker with no App key, repository write token, host
checkout, SSH agent, deployment secret, or Docker socket. Use the established
isolated-verifier contract; do not attach the existing bare-metal user account.

The App requests only the repository metadata/contents/pull-request read
permissions and check-result write permission actually required by the chosen
implementation. It must not receive source-write, merge, administration,
deployment, or organization-runner management permissions. A human bootstrap
steward configures the required-check binding separately. App secrets stay in
the protected service's secret store, never in Git, agent prompts or logs.

## 3. Identity and freshness contract

Every decision binds all of these exact values:

1. GitHub repository numeric ID and canonical owner/name.
2. Pull-request number, same-repository head identity, and base ref exactly
   `refs/heads/main`; retargeting to another branch is not accepted.
3. Full current base and candidate commit SHAs; no moving tag/branch as proof.
4. The exact merge-result tree, or exact tested linear candidate, selected by
   the installed merge policy. A head-only test is not evidence for a different
   merged tree.
5. Authority release digest, policy digest and complete trusted dependency
   manifest digest.
6. Canonically sorted changed-path inventory, including old/new path, Git mode,
   object identity, and independently computed file-content SHA-256.
7. Required evidence identities, conclusions, attempt numbers and hashes.
8. Decision ID, start/finish timestamps and a bounded validity interval.

Use a specified canonical serialization with a versioned schema and fixed
encoding; hash its bytes. Reject duplicate fields, malformed hashes, missing
fields, unknown versions, unsafe paths and oversized records before effects.
Renames, copies, deletions, symlinks, submodules and file-mode changes must be
classified explicitly rather than treated as unchanged text.

On head update, base update, merge-queue change, authority revocation or policy
update, supersede the old result and require fresh evidence. Reconcile from the
GitHub API after webhook delivery; a webhook payload is a hint, not authority.
Authenticate original webhook bytes, deduplicate delivery IDs and bound retries.
Recheck the tuple immediately before publishing the terminal conclusion.

**Unresolved activation prerequisite:** GitHub Check Run metadata does not
itself enforce a custom expiry or revocation at the later instant of merge.
The implementation must select and prove an independent merge-time freshness
mechanism, including revocation after success and delayed webhook delivery.
Strict up-to-date checks alone must not be represented as that mechanism. Until
it is designed, installed and integration-tested, this proposal is not ready
for activation. Do not grant this check-writing App merge or administration
permission implicitly to fill the gap.

## 4. Protected path and dependency inventory

The initial policy should explicitly own the following conservative path set.
These are proposed literal paths/prefixes, not an active classifier:

| Path | Reason |
|---|---|
| `AGENTS.md` | Constitution and authority boundary |
| `.github/` | Workflows, local actions and CI configuration |
| `.macsad/` | Admission policies, schemas and toolchain identities |
| `Makefile` | Gate dispatch and required targets |
| `scripts/` | Gate entry points and executable transitive dependencies |
| `tests/` | Discovery, assertions, expected inventories and fixtures |
| `host_adapters/tests/` | Mechanical and real-adapter acceptance tests |
| `database/tests/` | Persistent invariants and data-worker acceptance tests |
| `database/verify.sql` | Catalog verification if present at the pinned base |
| `ops/` | Runtime, verifier, image, bootstrap and deployment controls |
| `docs/runbooks/agent-request-intake.md` | Admission procedure |
| `docs/runbooks/upgrading-logos.md` | Promotion authority |
| `docs/runbooks/testing-and-ci.md` | Required evidence contract |
| `docs/runbooks/firebat2-verification.md` | Verifier activation and isolation |

Before implementation, resolve actual files against the pinned base and expand
all evaluator/runner imports, sourced scripts, manifests, executable configuration
and test oracles. An executable dependency of the admission machinery outside
this list joins the trusted closure. Unknown or newly introduced admission
dependencies yield **hold**, never an ordinary-change pass. Candidate product
modules are untrusted inputs executed only in the worker, not additions to the
trusted authority. They still require complete independent discovery and tests.
Do not fetch tools or resolve unpinned dependencies while
deciding admission. Application code can contain executable test blocks too;
the trusted extractor must classify their semantic inventory independently of
the candidate's replacement manifest.

Keep the path policy in the independent authority. A PR editing a copy in
MaCSad cannot narrow the set used to evaluate that PR. Refining this conservative
set later is itself a separately versioned policy change.

## 5. Decision semantics

Use four explicit states: pending, accept, reject, and hold. Only accept produces
a successful required check. Missing data, unavailable infrastructure,
unsupported change class, timeout, crash, zero-test discovery or skipped
required evidence never produces success or a neutral result counted as success.

For an ordinary candidate, the authority independently verifies that no protected
path or trusted dependency changed, then accepts **classification only**. Product
correctness remains the responsibility of Foundation and other applicable gates.

For a control-plane candidate, evaluate a finite, explicitly supported change
class. Initial useful class: additive registration of new tests/modules without
removing or weakening previously admitted coverage. A permissive rule such as
"the test count increased" is insufficient. The independent evaluator must:

- preserve baseline test identities, assertions, source-quality limits, proof
  domains, zero-skip policy, operation/time budgets and failure propagation;
- independently discover all new test-bearing modules and reject orphaned,
  duplicated, unreachable or excluded tests;
- run unchanged baseline and added acceptance fixtures under the trusted runner,
  with exact inventory and adversarial cases;
- compare the proposed runner's discovery and outcomes to those trusted results;
- reject changed command routing, hidden filters, environment-controlled escapes,
  swallowed failures or an enlarged trusted dependency closure;
- require all applicable product/database/browser checks independently.

This does not claim arbitrary program equivalence is decidable. If the additive
class cannot be checked structurally and with its specified evidence, return
hold. A different change needs a versioned evaluator capability and its own
adversarial evidence in the independent control-policy lane. No candidate can
grant itself such a capability.

In particular, PR #6 is not assumed to fit the initial additive-only class:
it also moves existing test locations, changes called functions, and adds
integration dispatch/dependencies. Installing v1 may correctly leave that PR
held. Its actual diff needs an explicitly supported, independently tested
change class; bootstrap is not a promise of acceptance.

Changes to this authority, its credentials or the required-check binding use a
separate bootstrap/release process, never the product candidate it is checking.
Approving bootstrap is not approving an untested product revision.

## 6. Acceptance tests required before installation

The independent implementation needs RED/GREEN evidence for at least:

| Case | Required outcome |
|---|---|
| Ordinary source change, exact clean identity | Classification accepted; product gates still required |
| Additive supported test registration | Accept only after trusted old/new inventories and evidence agree |
| Deletion, rename or modification of a baseline test | Reject or hold; never count-only acceptance |
| Runner replaced with an always-green script | Reject |
| Hidden skip, zero discovered tests or zero-match filter | Reject |
| Changed policy allows its own forbidden edit | Reject using the trusted policy |
| Modified imported helper outside the obvious workflow | Protected dependency detected |
| Symlink/submodule/path traversal or malformed record | Reject before execution |
| Lookalike success check from a different App | Does not satisfy required identity |
| Stale head/base/merge tree or replayed old success | Invalidate and reevaluate |
| PR retargeted away from `refs/heads/main` | Reject for this lane |
| Revocation after success with delayed/missing webhook | Installed merge-time mechanism blocks stale acceptance |
| Fork PR or repository-ID mismatch | Hold outside the configured same-repository lane |
| Failed cleanup, worker timeout or unavailable evidence | Fail closed; retain failed attempt |
| Candidate attempts credential/network/host access | Denied; no secret or host state exposed |
| Duplicate/out-of-order webhook | Idempotent result for the reconciled current tuple |
| Revoked authority release or tampered evidence hash | Reject |

Exercise real GitHub required-check behavior in a separately approved test
repository: absent, pending, failing and wrong-App checks must each block merge.
Test a new base/head event, linear merge behavior and stale-check invalidation.
Local mocks do not replace this integration evidence.

## 7. Bootstrap and rollout sequence

1. Alejandro/Tristen assign a named human bootstrap steward and independent
   control-policy maintainer. Those responsibilities are not assigned by this
   proposal, and no agent is granted their credentials.
2. Implement and test the pinned authority and worker isolation in that separately
   approved location. Retain complete positive and adversarial evidence.
3. Choose the exact protected-path closure, check/App identity, merge-tree
   binding, size/time/retention limits and revocation procedure in its release
   manifest. Unresolved fields prevent activation.
4. Install the least-privileged App only in the approved test environment first;
   verify every required-check blocking case above.
5. Run read-only/shadow classification on MaCSad. Publish no success under the
   future production-required App/name binding; use a distinct shadow identity
   or no GitHub check result. Historical shadow successes must never satisfy
   the later required check. Shadow does not authorize any held PR to merge.
6. With explicit bootstrap authority, install the App for MaCSad and bind the
   required check to its numeric App ID. Keep Foundation, administrator
   enforcement, pull requests, strict freshness and linear history intact.
7. Re-read GitHub settings and verify absence/failure/wrong-identity blocking
   against the installed configuration. Record the authority and policy digests.
8. Reevaluate PR #6's then-current exact head/base. It still needs all required
   checks; do not reuse this document as an activation receipt.
9. Merge only through the protected linear path after acceptance. Toolchain
   promotion, Firebat2 activation and deployment remain separate transitions.

If rollout fails, leave held candidates blocked and disable/revoke the faulty
authority through its documented operator process. Do not remove the required
check as a convenience rollback or revive an old success for a new candidate.

## 8. Completion evidence and non-goals

Completion requires the independently pinned implementation, exact permission
inventory, passing adversarial and real GitHub tests, installed App identity,
read-back branch configuration and one fresh exact-candidate decision record.
None exists merely because this proposal was committed.

This proposal adds no database table, framework, public endpoint, secret,
unreviewed runner, new human review gate, upstream LOGOS change or deployment.
It resolves the requested design question, not the outstanding activation.
