---
name: pr-scoping
description: 'Ensure pull requests stay small, focused, and reviewable. Use when validating subtask boundaries, splitting large pull requests, or enforcing the configured pull-request size limit.'
---

# Pull Request Scoping

> Public base skill — keep it generic. Team-specific names, repositories, frameworks, and commands belong in the private overlay, not here.

## Purpose

Keep pull requests small, focused, independently reviewable, and traceable to the approved work.

## Operating Contract

1. Keep each pull request focused on one logical concern.
2. Preserve buildable intermediate states when splitting work.
3. Measure scope from the actual diff rather than estimates or labels.
4. Keep branch and issue naming traceable to the approved Jira work.
5. Load the size limit from `governance.thresholds.pr_max_lines` in `.github/config/guardrails.yaml`; if the guardrail cannot be read, stop rather than inventing a limit.
6. For review-subbranch extraction, produce exactly one linear stack: one root, one parent per non-root, no forks, and no cycles.
7. Require every feature-versus-story changed file or hunk to belong to exactly one Acceptance Criteria (AC)-mapped slice; no story change may be missing or duplicated.

## When to Use

- When validating review-subbranch boundaries at pipeline Step 8.
- When a pull request is growing beyond the configured review limit.
- When reviewing whether a proposed split is focused and dependency-safe.

## Procedure

### Step 1: Load the Guardrail

Read `governance.thresholds.pr_max_lines` from `.github/config/guardrails.yaml`. Return a blocker if the file or value is unavailable; governance values have no local fallback.

### Step 2: Measure Each Slice

Measure added plus deleted lines from the actual feature-versus-story diff for every proposed slice. Exclude only paths recognized as tests by repository conventions, such as existing test roots, test manifests, or neighboring test naming. Do not exclude production support files merely because the plan labels them as tests.

Record `non_test_lines` for every slice. If a slice exceeds the configured limit, find a natural dependency-safe split and measure the resulting slices again before approval.

### Step 3: Validate Scope Quality

Confirm that each slice:

- addresses one logical concern,
- maps to one or more explicit Acceptance Criteria (AC),
- has explicit owned paths or hunks,
- includes the tests needed for its behavior,
- can be reviewed against its proposed base without unrelated changes,
- preserves a working intermediate state.

### Step 4: Validate the Delivery Shape

When the approved plan contains one slice, select direct delivery. Require the complete feature-to-story diff to belong to that slice, create no review subbranch, and require feature/story tree equivalence after additive integration.

When the approved plan contains multiple slices, require:

- exactly one stack root,
- each non-root names exactly one known parent,
- no parent has more than one direct child,
- the dependency graph is acyclic,
- every slice is reachable from the root.

Every stacked review branch follows `feature/<user>/story/<PARENT-JIRA>-PR<N>`. The root uses ordinal PR1 and targets `feature/<user>/<PARENT-JIRA>`; every dependent slice increments the ordinal and targets its immediate parent review branch. Review slices do not create Jira subtasks or carry descriptive slugs.

Order incremental review from root to tip so foundational slices are understood before their dependents. After feedback is resolved, collapse the stack from tip to root. A child merge changes its parent source and effective diff, so that parent must rerun required checks and receive current aggregate approval before it merges. PR1 merges into the feature branch only after its tracked tree equals the canonical `feature/<user>/story/<PARENT-JIRA>` tree. Feature-to-`develop` integration is a separate protected pull request.

### Step 5: Return the Decision

Return:

- scope decision (`good as-is` or `split required`),
- configured non-test line limit,
- measured non-test line count for every slice,
- proposed split plan when needed,
- dependency order and proposed base for every slice,
- naming recommendations grounded in the approved Jira work,
- complete ownership coverage and expected cumulative tip/story tree-equivalence requirements.

## Constraints

- Do not waive, round, or estimate the configured line limit.
- Do not infer test paths solely from a proposed plan label.
- Do not present a forest, fork, cycle, or oversized slice for approval.
- Do not create branches, issues, commits, pushes, or pull requests; this skill validates the plan only.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
