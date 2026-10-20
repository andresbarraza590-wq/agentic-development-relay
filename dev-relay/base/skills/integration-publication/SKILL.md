---
name: integration-publication
description: 'Automatically create, reconcile, and refresh the evidence-rich final stacked feature-to-develop draft pull request after C8c, while preserving human approval and merge control.'
---

# Integration Publication

> Public base skill — keep it generic. Team-specific names, repositories, pull-request hosts, and commands belong in the private overlay or repository-native tooling.

## Purpose

Publish exactly one final draft `feature_branch` to `develop` pull request for an accepted stacked review delivery, attach the complete review and validation evidence, and refresh that same pull request after integration feedback.

This skill never approves or merges a pull request.

## Operating Contract

1. Run only for `delivery_mode: stacked` with `slice_count > 1`.
2. Treat the canonical story branch as the implementation source of truth and the feature branch as the protected-integration source after stack collapse.
3. Require C8c-approved stack review/collapse evidence before publication.
4. Detect synchronization or conflicts before creating or refreshing the pull request; never resolve semantic conflicts autonomously.
5. Reconcile by exact repository, source branch, target branch, and persisted pull-request identity so retries are idempotent.
6. Create draft pull requests only. Never approve, merge, decline, delete, force-push, rebase, or squash.
7. When `session_key` is supplied, route every durable side-effect write through Pipeline Session `update-integration-side-effect`; never edit `session.md` directly.
8. In a sessionless invocation, return `integration_pipeline_context_required` without mutation.

## Required Inputs

All modes require:

1. `mode`: `publish` | `refresh`.
2. `parent_jira`.
3. `story_branch`, `story_sha`, and accepted `story_tree`.
4. `feature_branch` and current `feature_sha`.
5. `develop_branch`: `develop` and current `develop_sha`.
6. canonical stacked `subbranch_manifest`.
7. accepted `human_review` evidence from C8c.
8. current `quality_evidence`: QA, tests, Acceptance Criteria, publication, and regression.
9. `session_key`: equal to `parent_jira`.

`refresh` also requires:

- persisted `integration_pr`,
- actionable `integration_feedback`,
- the persisted candidate's prior `story_sha`,
- corrected story SHA,
- refreshed validation evidence.

## Procedure

### Step 1: Validate Applicability and Authority

Require:

- `delivery_mode: stacked`,
- `slice_count > 1`,
- contiguous PR ordinals and expected parent bases,
- `story_tree_equivalent: true` for the accepted stack tip,
- `review` complete,
- C8c approved with `decision-reply: review complete`,
- every incremental PR's final disposition,
- complete tip-to-root merge chain with current source/target/check/approval identities,
- PR1/story tree equivalence,
- PR1-to-feature merge reference.

Return `integration_not_applicable: direct` for direct mode. Return `artifact_missing: stacked_review_outcome` for incomplete evidence.

### Step 2: Verify Feature and Target Revisions

Read the live local and remote feature and `develop` revisions. Require the feature revision to contain the accepted PR1-to-feature merge. In `publish`, also require every C8c-accepted canonical story change. In `refresh`, require the persisted candidate's prior story revision and verify that the live feature still contains its accepted projection before applying the new correction.

If `develop` advanced after the accepted evidence:

- determine whether a non-rewriting merge into feature is required,
- return `integration_synchronization_required` with the observed revisions when synchronization has not occurred,
- after caller-provided synchronization, require refreshed aggregate validation before continuing.

If a conflict exists, return `integration_conflict_resolution_required`. Never choose conflict semantics or modify `develop`.

For `refresh`, before building new evidence:

1. Compare the correction with the accepted manifest. If it changes delivery mode, slice count, accepted ownership, or stack topology, return `integration_review_restart_required` without mutation so Deva can obtain the registered restart decision and fresh C8a/C8b authorization.
2. Require the corrected story revision to descend from or have an unambiguous additive correction relative to the persisted candidate's prior `story_sha`; otherwise return `integration_review_restart_required` without mutation.
3. Compute exactly the prior-story-to-corrected-story delta. Persist `integration-commit` as `intended`, apply only that delta additively to feature, and persist the observed commit as `complete`. Never replace the complete feature tree, discard non-rewriting `develop` synchronization, or include unrelated changes.
4. Persist `branch-push` as `intended`, push the exact updated feature ref, and persist the observed remote ref as `complete`. On uncertainty, persist `partial` and reconcile before retry.
5. Verify every corrected story change is represented in feature with no unrelated removal, set `canonical_story_projection_verified: true`, and use the resulting feature revision for the evidence document and PR update. An identical retry reconciles the recorded commit and push instead of creating another commit.

### Step 3: Build Canonical Evidence

Render a deterministic evidence document containing:

- parent Jira key,
- story branch, SHA, and tree,
- feature branch and SHA,
- target branch and SHA,
- PR1 through PRN links in ordinal order,
- per-slice scope and Acceptance Criteria coverage,
- root-to-tip review disposition,
- tip-to-root merge chain,
- renewed checks and approvals for each changed parent,
- PR1/story equivalence,
- PR1-to-feature merge,
- aggregate QA, test, coverage, acceptance, publication, and regression evidence,
- replacement and superseded PR references,
- canonical story-projection evidence after any C8d feedback.

Scrub secrets, credentials, URL user information, tokens, sensitive query parameters or fragments, unrelated internal hosts or addresses, and sensitive Jira content under PII-1. The evidence artifact may retain the exact authenticated PR1-through-PRN and final integration pull-request URLs supplied by the approved internal pull-request host because those links are required traceability evidence; sanitize them before persistence and never retain credentials or sensitive URL components. When policy forbids a full URL, record the stable PR identity plus the approved safe-link representation instead. Compute `evidence_hash` as lowercase SHA-256 over the exact UTF-8 evidence bytes.

Use a concise title grounded in the parent Jira, for example `<PARENT-JIRA>: integrate accepted stacked delivery`.

### Step 4: Reconcile Existing State

Before mutation, reconcile the Integration Side-Effect Ledger and pull-request host for the exact feature/develop head-base pair.

- If the persisted PR exists with the expected source and target, reuse it.
- If a matching remote PR exists but the ledger is incomplete, persist the reconciled identity.
- If multiple matching open PRs exist, return `integration_pr_ambiguous`; never choose one silently.
- If the persisted PR points to another source or target, return `integration_pr_identity_conflict`.
- If an earlier merged PR exists but current feature has new commits, require explicit current open-PR reconciliation rather than reopening or mutating the merged PR.

### Step 5: Publish or Refresh

For `publish`:

1. Persist `intended` for `pr-create` with the exact feature/develop target.
2. Create one draft PR only when reconciliation found none.
3. Persist `complete` with PR ID and URL immediately after observed success.
4. If the outcome is uncertain, persist `partial`, reconcile once, and stop on ambiguity.

For `refresh`:

1. Require the persisted open PR identity.
2. Verify the source branch contains the recorded additive correction and current projection proof produced in Step 2.
3. Persist `intended` for `pr-update` with PR ID and new evidence hash.
4. Update the PR description and observed source/target revision binding without changing draft status.
5. Persist `complete` after read-back verifies the evidence hash and revisions.

Never create a replacement PR merely because its source SHA advanced; an open branch-based PR normally updates with the branch. Create a replacement only after a separately authorized identity/topology change.

### Step 6: Return Candidate

Return the canonical `integration_pr` mapping defined by Integration Publisher with:

- exact branch and SHA identities,
- target SHA,
- evidence hash,
- PR ID and URL,
- `draft: true`,
- publication outcome,
- projection verification,
- checks/approval/merge pending C8d.

## C8d Completion Evidence

The later C8d approval is owned by Pipeline Session, not this skill. It must verify against the persisted candidate:

- live PR ID and URL,
- current source and target SHAs,
- required checks bound to the current source SHA,
- current approval,
- no unresolved review blocker,
- merge method `merge-commit`,
- merged commit and target containment.

The skill never infers `integration complete` from PR state and never sends a checkpoint decision.

## Feedback and Restart Boundaries

For ordinary C8d feedback:

1. Correct the canonical story branch first through the owning implementation flow.
2. Refresh stale QA, tests, acceptance, story publication, and regression evidence.
3. In `refresh`, project only the exact persisted-story-to-corrected-story delta additively into feature and push it through the integration side-effect ledger.
4. Require `canonical_story_projection_verified: true` after read-back.
5. Refresh the existing integration PR without changing its identity and return to C8d.

When feedback changes delivery mode, slice count, accepted ownership, or stack topology, return `integration_review_restart_required` without PR mutation. Deva must obtain the exact registered restart decision and return to Stage 8.

## Failure Modes

- direct delivery supplied,
- missing or stale C8c evidence,
- incomplete stack merge chain,
- PR1/story mismatch,
- PR1 not contained in feature,
- develop synchronization required,
- conflict resolution required,
- ambiguous or conflicting pull-request identity,
- evidence rendering or hash failure,
- pull-request create/update failure,
- side-effect ledger persistence failure,
- retry budget exhausted.

## Constraints

- Never mutate the canonical story branch.
- Never push directly to `develop`.
- Never rewrite feature or review history.
- Never approve or merge a pull request.
- Never create more than one current feature-to-`develop` PR for the accepted integration identity.
- Never store scratch or PR-body files under the live session cache directory.
- Never continue on uncertain external state without ledger reconciliation.

## Skill Continuity Protocol

1. Keep a live step ledger with mode, persisted PR identity, evidence hash, current status, blocker, and next action.
2. Reconcile durable and remote state before every retry.
3. Preserve the same PR identity across ordinary feedback refreshes.
4. Return questions and blockers to the invoking agent; never prompt interactively.
5. On context loss, recover from Pipeline Session and remote read-back rather than conversational memory.
