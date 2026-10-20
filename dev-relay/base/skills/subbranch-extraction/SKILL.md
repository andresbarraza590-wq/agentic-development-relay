---
name: subbranch-extraction
description: 'Prepare direct or stacked review delivery from a regression-clean story branch, return an approval manifest, open the authorized draft pull request shape, and refresh delivery after reviewer feedback.'
---

# Subbranch Extraction

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Convert a completed parent story branch into the smallest correct review shape: direct feature integration for one slice or ordinal stacked review branches for multiple slices.

This skill executes an approved split plan. It does not design the split plan.

## Operating Contract

1. Execute only developer-approved split plans.
2. Preserve story branch as read-only source.
3. Keep extraction deterministic and auditable.
4. Open draft PRs only after C8b authorization.
5. Return dependency-ordered prepared and final manifests.
6. When `session_key` is supplied, route every durable side-effect-ledger write through the `pipeline-session` skill's `update-side-effect` operation; never edit `session.md` directly.
7. In a standalone sessionless run with no `session_key`, create no session or ledger. Reconcile Git and remote state immediately before each mutation and reuse any exact existing result.

Re-extraction runs once per reviewer-feedback cycle; the number of cycles is bounded by `governance.loop_budgets.reextract` and enforced by the pipeline engine, which stops and escalates at the cap (LOOP-1 in `.github/config/guardrails.yaml`).

## Delivery Modes

`slice_count: 1` requires `delivery_mode: direct`. The skill applies the complete validated story result additively to `feature_branch`, creates no review branch, proves feature/story tracked-tree equivalence, and prepares one draft `feature_branch` to `develop` PR.

`slice_count > 1` requires `delivery_mode: stacked`. The skill creates one ordinal review branch per slice and stacks each on the branch below it:

- A review branch whose `depends_on` names a parent ordinal targets **that parent's review branch** as its PR base.
- A subbranch with no dependency (a stack root) targets `feature_branch`.
- The public branch pattern is `feature/<user>/story/<PARENT-JIRA>-PR<N>`.
- Review branch `pr_ordinal: N` is exactly `feature/<user_segment>/story/<PARENT-JIRA>-PR<N>`.

**PR base resolution** (per subbranch, in dependency order):

- direct delivery → base = `develop`.
- `depends_on` is empty → base = `feature_branch` (stack root).
- `depends_on` names a parent → base = that parent ordinal's review branch. If a slice depends on more than one parent, return a failure so the plan is revised.

The result is a linear chain of PR bases — `feature_branch` → T1 → T2 → T3 … — where each dependent PR targets the branch immediately below it.

### Keeping a Stack in Sync

When `feature_branch` or the canonical story branch advances before collapse, classify the change against the approved extraction specification:

1. Apply and validate every accepted correction on `story_branch` first.
2. When delivery mode, scope, Acceptance Criteria mapping, owned paths/files, extraction mechanism, dependency order, slice count, and topology remain unchanged, update direct mode by applying an additive correction to feature, or update stacked mode by committing additively to the owning review branch and merging it upward through every dependent branch. Rerun affected focused and cumulative checks; never force-push or rewrite history.
3. When any plan field above changes, preserve the unaffected prefix and rebuild the affected suffix in dependency order, using new branches named `<existing-branch>-r<N>`, where `N` is the smallest positive integer not already used locally, remotely, or in the side-effect ledger.
4. Push each replacement branch as a new remote branch and open a replacement draft PR targeting its corresponding updated parent branch. Comment on every original PR in the replaced suffix that it is superseded, and return both references.
5. Recompute the cumulative tip tree and require it to equal the current canonical story tree before review resumes.

Review incremental slices from the **root toward the tip**. After feedback is resolved and the branches are frozen, merge the stack sequentially from the **tip toward the root** using PR merge commits. Immediately before each merge, require current approval and required checks bound to the live source and target SHAs. A child merge changes its parent, so rerun checks and obtain a fresh aggregate approval before that parent merges. Merge PR1 into `feature_branch` only after its tracked tree equals `story_branch`. After C8c accepts that landing, reactive Stage 8d creates or reconciles the separate `feature_branch` → `develop` draft PR and returns it for human validation, approval, and merge. Never squash, rebase-merge, force-push, or merge a parent before its dependent PRs.

## When to Use

- Initial extraction and manifest preparation: pipeline Step 8 after C8a.
- Approved draft-PR publication: pipeline Step 8 after C8b authorization.
- Re-extraction: pipeline Step 9 after reviewer-driven fix lands on story branch.

## Required Inputs

All modes require:

1. `parent_jira`: parent story key.
2. `user_segment`: normalized user branch segment used under `feature/<user>/...`.
3. `story_branch`: canonical `feature/<user>/story/<PARENT-JIRA>` branch.
4. `story_sha` and `story_tree`: pinned canonical source revision and tracked-tree identity.
5. `feature_branch`: `feature/<user>/<PARENT-JIRA>`, used as PR1's base.
6. `feature_sha`: pinned feature baseline revision.
7. `mode`: `initial`, `publish`, or `reextract`.
8. `delivery_mode`: `direct` when `slice_count` is one; `stacked` when it is greater than one.
9. `slice_count`: exact positive count of approved slices.

Optional pipeline-state input:

- `session_key`: supply the same value as `parent_jira` only for a Jira-keyed Deva run whose side effects must be persisted through Pipeline Session. Omit it for a standalone/sessionless invocation. `parent_jira` remains required because it determines canonical branch identity.

For `initial`, require `split_plan`: ordered entries with:

  - `pr_ordinal` (one-based integer; exactly `1` in direct mode and contiguous `1..N` in stacked mode)
  - `branch` (exact feature branch in direct mode; exact parent-jira ordinal review branch in stacked mode)
  - `scope`
  - `acceptance_criteria` (one or more AC identifiers or exact acceptance statements covered by the slice)
  - `extraction`: `path-based` | `hunk-level`
  - `paths` (required for `path-based`; use for files this slice owns exclusively)
  - `files` (required for `hunk-level`; use for files shared with another slice)
  - `depends_on`
  - `non_test_lines` (measured added plus deleted non-test lines)

Persist each approved exact `branch` unchanged through the prepared and final manifests and pass it as `entry` to every stateful `update-side-effect` call for that slice. Compute the operation's `idempotency_key` exactly as specified by `pipeline-session`; never substitute a descriptive label, bare ordinal, retry count, or newly generated value. An authorized replacement branch receives its own ledger entry; existing rows retain their original branch entry.

For `publish`, also require:

- `prepared_manifest`: the exact dependency-ordered manifest authorized at C8b

For `reextract`, also require:

- `persisted_extraction_spec`: the canonical full manifest from the completed split, including delivery mode and every slice's original extraction mechanism, owned `paths` or shared `files`, dependency, branch, and PR-base relationship
- `target_branch`: the feature branch in direct mode, or the review branch whose slice starts the affected stacked suffix
- `change_classification`: `ownership-preserving` | `plan-changing`

## Procedure: Initial Mode

### Step 1: Validate Plan

Before mutating feature or review branches, verify:

- both `story_branch` and `feature_branch` exist and are current,
- `feature_branch` equals `feature/<user_segment>/<PARENT-JIRA>` and `story_branch` equals `feature/<user_segment>/story/<PARENT-JIRA>`,
- the live feature and story revisions equal `feature_sha` and `story_sha`, and the live story tree equals `story_tree`,
- `slice_count` equals the number of plan entries and selects the required `delivery_mode`,
- `pr_ordinal` values are contiguous integers from one through `slice_count`,
- direct mode has exactly one entry whose branch equals `feature_branch`, whose base is `develop`, and whose dependency is empty,
- stacked-mode branch `N` is exactly `feature/<user_segment>/story/<PARENT-JIRA>-PR<N>`,
- stacked-mode dependencies form one acyclic linear chain rooted at PR1, with every non-root depending on the immediately preceding ordinal,
- each `path-based` glob matches at least one changed file,
- each `hunk-level` file is changed on `story_branch`,
- every deleted or renamed path is declared by the owning slice; a rename declares both its source and destination.
- every feature-vs-story changed file or hunk belongs to exactly one slice, with no missing story change and no duplicated ownership,
- every `non_test_lines` value was measured from the actual feature-vs-story diff and is at or below `governance.thresholds.pr_max_lines` from `.github/config/guardrails.yaml`.

If any validation fails, stop and return failure list.

### Step 2: Resolve Delivery Order

Order entries by `pr_ordinal`; require that order to match the dependency chain in stacked mode.

### Step 3: Prepare Branches

When `session_key` is supplied, maintain the durable per-entry ledger under `Artifacts > Subbranch Side-Effect Ledger` using the schema defined by the `pipeline-session` skill. For each operation, pass only these operation tokens: `integration-commit`, `branch-create`, `branch-push`, `pr-create`, `pr-comment`, and `supersede`. Before each matching external mutation, call `update-side-effect(..., status: intended, ...)` and wait for its durable result; do not perform the mutation if that write fails. After success, immediately call the same operation with `status: complete` and the returned commit, branch/ref, PR URL/id, or comment id before starting another external mutation. If the external result is uncertain, persist `partial`, reconcile the ledger with Git and the remote, and update that same row to `complete` when the result is found. On resume, reconcile every `intended` or `partial` row before acting: reuse a matching completed result, complete a recorded partial operation, and never create a duplicate.

In a standalone sessionless run with no `session_key`, do not call `pipeline-session`. Before each mutation, inspect Git and the remote for the exact commit, branch/ref, or head/base PR pair and reuse it when found. If a mutation's outcome is uncertain and cannot be reconciled, stop rather than retrying blindly.

When a plan-changing initial retry or registered C8b revision follows existing side effects, first reconcile uncertain outcomes without changing terminal disposition. After the developer accepts the recorded replacement, apply only the exact authorized disposition plan: mark a completed operation `superseded` when replacement work takes its place, or mark it `abandoned` when it will not proceed, retaining every returned identifier and reconciliation timestamp. A changed initial plan requires `pipeline-session finalize-split-plan-revision` to return `revised_plan_authorized`; C8a's earlier approval or the unfinalized decision alone is insufficient. Never delete an issue or branch, rewrite a published ref, silently reuse an entry for different scope, or surface a replacement manifest while an omitted or retargeted prior row lacks one of these terminal dispositions.

Create no Jira issue for a slice.

For direct mode, apply the complete tracked state represented by `story_tree` to `feature_branch` with one additive integration commit `<PARENT-JIRA>: integrate canonical story for review`. Do not reset, rebase, or rewrite feature history. Record the integration commit and feature push through the ledger when stateful, push the exact prepared feature ref before returning the manifest, and require the resulting feature tree to equal `story_tree`.

For stacked mode, use each exact approved ordinal branch name. Do not create an extra descriptive identifier.

### Step 4: Extract Stacked Slices

Skip this step in direct mode. In stacked mode, build the stack **cumulatively**: each review branch starts from its stack base and adds only its own slice, so a dependent branch already contains its parent's work.

For each subbranch in dependency order:

1. Create the subbranch from its **stack base** — the parent subbranch when the slice has a `depends_on`, otherwise `feature_branch`. Never cut a dependent subbranch from `feature_branch` when its parent is set so it inherits the parent's commits.
2. Apply **only this slice's own changes** on top of that base, taken from `story_branch`:
   - `path-based` — for files this slice owns exclusively, reproduce their exact `story_branch` state. Check out added/modified destinations, stage deletions with `git rm`, and reproduce renames by removing the source and checking out/staging the destination. Never skip a path merely because it no longer exists on `story_branch`.
   - `hunk-level` — for files shared with another slice, stage only this slice's hunks from `story_branch`, so the parent's (or a sibling's) hunks are neither duplicated nor reverted. A whole-file checkout of a shared file would pull in later slices' changes, so shared files must be `hunk-level`.
3. Create one commit with message `<PARENT-JIRA>: review slice PR<N>`.
4. Before any push, measure added plus deleted non-test lines in this subbranch versus its resolved stack base using repository test-path conventions. If the actual count exceeds `governance.thresholds.pr_max_lines` or differs from the approved plan's `non_test_lines`, stop and return the measured discrepancy for plan revision; do not push or prepare a manifest.
5. Push the subbranch when the applicable session ledger or standalone remote reconciliation shows that exact ref is not already published; record the published ref when `session_key` is supplied.

Never cherry-pick and never reset the base: applying the slice on top of the parent is what keeps every earlier change intact.

After the final slice, require the cumulative tip's tracked tree to equal `story_tree`. A mismatch means extraction omitted, duplicated, or altered story content; stop before C8b rather than publishing an incomplete stack.

### Step 5: Return Prepared Manifest

Return the dependency-ordered manifest for C8b review without opening any pull request. Include:

- `slice_count`
- `delivery_mode`
- `pr_ordinal`
- `scope`
- `acceptance_criteria`
- `branch`
- `head_sha`
- `head_tree`
- `pr_base`: `develop` for direct delivery; for stacked delivery, `feature_branch` for a stack root or the parent subbranch's branch for a dependent slice
- `pr_base_sha`
- `depends_on`
- `extraction`: the original `path-based` or `hunk-level` mechanism
- `paths`: exact owned paths for `path-based`, otherwise an empty list
- `files`: exact shared files for `hunk-level`, otherwise an empty list
- `non_test_lines`
- `pr_url`: pending C8b authorization

Also include top-level `feature_sha`, `story_sha`, and `story_tree`. Direct mode includes delivered `feature_head_sha`, `feature_tree`, and `story_tree_equivalent: true`. Stacked mode includes cumulative `tip_sha`, `tip_tree`, and `story_tree_equivalent: true`.

The returned head/base pairs are the complete publication scope. Do not add, remove, or retarget an entry after C8b without returning to plan review.

## Procedure: Publish Mode

Use only after the developer authorizes the prepared manifest at C8b. When `session_key` is supplied, `pipeline-session approve-checkpoint` must durably record that authorization before this mode starts.

1. Require `prepared_manifest`. When `session_key` is supplied, verify that C8b is approved while `split` remains `in_progress` and compare the manifest byte-for-byte with the session's persisted `Draft PR Manifest` artifact. In a standalone sessionless run, require explicit developer authorization of the exact manifest in the current conversation. Stop without mutation if the applicable condition is missing or the authorized manifest differs.
2. Reconcile the stateful side-effect ledger when present, plus remote branches and existing PRs. Before reconciliation, require the sole direct-delivery entry to carry exact `pr_base: develop`; never infer or default a missing direct base. For each manifest entry, verify that the recorded or remotely reconciled branch still resolves to the prepared commit and that its `pr_base` and dependency have not changed. A mismatch invalidates the authorization; stop and return the discrepancy for a new C8b review.
   - On `resume_split_publish`, this reconciliation is the entry point. Use the persisted C8b-authorized manifest, continue only incomplete or uncertain publication operations, and never rerun plan or initial extraction.
3. In delivery order, open a draft PR only when the applicable ledger and remote PR search show that the exact authorized head/base pair has no recorded PR:
   - base: the entry's authorized `pr_base`
   - head: the entry's `branch`
   - title: `<PARENT-JIRA>: <scope first line>`
   - body: canonical story context, delivery mode, acceptance coverage, and immediate dependency for a stacked slice
4. When `session_key` is supplied, use `pipeline-session update-side-effect` immediately before and after every PR mutation, following the same intended/partial/complete reconciliation rules as initial mode. In a standalone sessionless run, search the remote for the exact head/base pair immediately before opening it and stop on an uncertain result. Never open a PR whose head/base pair is absent from the authorized manifest.
5. Return the final manifest with the complete persisted extraction specification from initial mode, replacing only `pr_url` with the reconciled draft PR reference. Do not discard `slice_count`, `delivery_mode`, `pr_ordinal`, scope, extraction mechanism, paths/files, dependency, or branch relationship.

## Procedure: Reextract Mode

Use when reviewer feedback fix is already committed on story branch.

1. Require the canonical `persisted_extraction_spec`, `delivery_mode`, and `slice_count`. In direct mode, require `target_branch` to be feature and select its sole entry. In stacked mode, locate `target_branch` and derive the affected suffix. Stop if any slice lacks its original mechanism, paths/files, Acceptance Criteria mapping, branch, or PR-base relationship.
2. When `session_key` is supplied, require the exact staged reextract plan under `### Reextract Result`; its target branch, classification, affected entries, retained-prefix/disposition data, and extraction-specification hash must match this invocation. A missing or mismatched plan blocks before mutation. In a standalone run, require the developer to confirm the same exact plan in the current conversation.
3. Validate `change_classification` against the actual story diff. Return `plan_change_required` if the caller selected `ownership-preserving` but delivery mode, scope, Acceptance Criteria mapping, paths/files, extraction mechanism, dependency order, slice count, or topology changed.
4. Reconcile the stateful side-effect ledger when present, plus remote branches and PRs, before any mutation.
5. For `ownership-preserving`, direct mode computes the exact delta from the manifest's prior `story_sha` to the corrected story SHA and applies only that delta with additive commit `<PARENT-JIRA>: address review feedback`; it never replaces the complete feature tree, so any non-rewriting `develop` synchronization already present on feature is preserved. Verify every corrected story hunk is projected into feature with no unrelated removal, record `canonical_story_projection_verified: true`, and push additively. Stacked mode applies the corrected owning slice to its existing review branch with additive commit `<PARENT-JIRA>: address review feedback for PR<N>` and merges that update through each dependent branch. Push without rewriting history and record every mutation.
6. `plan-changing` is valid only in stacked mode with unchanged slice count. Preserve the unaffected prefix, create the target replacement as `<target_branch>-r<N>`, rebuild each dependent replacement, mark old suffix PRs superseded, and retain all references. A delivery-mode or slice-count change returns `review_delivery_restart_required` before mutation so Deva can restart Stage 8 authorization.
7. Rerun focused validation for the owning slice and cumulative validation for every changed stacked descendant. In direct mode, require `canonical_story_projection_verified: true`; when feature has no post-preparation integration-only commit, also require feature/story tree equality. In stacked mode, require the cumulative tip tree to equal the current `story_tree`.
8. Return the complete revised manifest, classification, commits, branches, PR references, validation results, current source/target SHAs, mode-specific delivery proof, `story_tree`, and superseded references when applicable. Direct mode returns `canonical_story_projection_verified: true` and the applicable tree-equivalence result; stacked mode returns `story_tree_equivalent: true`.

## Failure Modes

- path glob matches no changed files,
- hunk-level apply conflict not mechanically resolvable,
- subbranch naming collision,
- missing feature branch,
- changed feature or story revision after plan approval,
- missing, duplicated, or unexpected story diff ownership,
- direct Stage 8 feature/story tree mismatch or stacked cumulative tip/story tree mismatch,
- PR creation failure,
- dependency cycle,
- zero or multiple stack roots,
- a stack fork (one parent with multiple direct dependents),
- a subbranch not reachable from the stack root,
- stacked slice depends on more than one parent (cannot form a linear stack base),
- stacked parent branch missing when basing or restacking a dependent PR.

On failure, stop and return structured error details. Do not mutate plan silently.

## Constraints

- Never modify story branch.
- Never rebase story branch.
- Always open PRs as draft, and never open an initial-extraction PR before C8b authorization is durably recorded when `session_key` is supplied or explicitly confirmed in a standalone sessionless run.
- In direct mode, create no review branch; integrate additively into feature, prove feature/story tree equivalence, and target `develop` only through the authorized draft PR.
- In stacked mode, build each review branch on its immediate stack base and apply only its slice; PR1 targets feature and each dependent targets its parent review branch. No review PR targets `develop`.
- Never rewrite a published branch. In direct mode, project only the canonical story delta onto feature so later integration history is preserved. In stacked mode, recycle feedback with additive commits and upward propagation; use revisioned replacement branches only for a changed authorized same-count plan or topology.
- Review incremental PRs root-to-tip. Collapse them tip-to-root with PR merge commits only, requiring current source/target SHAs, current checks, and current approval before each merge.
- Never merge PR1 into `feature_branch` until its tracked tree equals `story_branch`; after it lands, integrate only through a separately validated and approved `feature_branch` → `develop` PR.
- Never squash, rebase-merge, force-push, or merge a parent before its dependent PRs.
- Never redesign split plan in this skill.
- Never replace a C8a/C8b plan or manifest until every side effect from the prior candidate is retained unchanged or durably marked `abandoned` or `superseded` in the stateful ledger.
- Never write PR-body text or any scratch/temp file into the live session cache directory (`<session_dir>/<JIRA-KEY>/`), which is reserved exclusively for `session.md`. Prefer passing the PR body inline; when a multi-line body must be staged to a file to avoid tool-argument quoting, write it to an OS temp path outside the pipeline trees and delete it once the PR is opened.
- Never run regression or Quality Assurance (QA) in this skill.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
