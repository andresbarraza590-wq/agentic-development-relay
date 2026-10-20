---
name: parallel-build-dispatch
description: 'Coordinate an approved multi-stream implementation plan with disjoint file ownership. Use serialized managed handoffs in the current file-backed runtime; permit physical overlap only when isolated workspaces and fenced handoffs are enforceable.'
---

# Parallel Build Dispatch

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Coordinate controlled multi-stream implementation for one parent Jira story while preserving a single source-of-truth branch.

This skill coordinates work. It does not implement code directly.

## Operating Contract

1. Use multi-stream planning only when its criteria are met and the exact plan is approved.
2. Enforce disjoint file ownership per stream.
3. In the current file-backed runtime, invoke one managed stream at a time in dependency order; only one stream may edit, stage, or commit in the shared checkout.
4. Keep all commits on the parent story branch.
5. Track stream state in structured status, not free-form narrative.
6. Return a single structured dispatch summary.
7. Permit physical overlap only when every stream has an isolated workspace, every managed handoff carries a valid fence, and file, branch/index, and external side-effect scopes are disjoint. If any guarantee is unavailable, use serialized execution.

## When to Use

Invoke from pipeline Step 3 only when at least one is true:

- story spans 3 or more repositories with no shared files,
- Acceptance Criteria (AC) map to independent components,
- story size is larger than one sprint of solo work,
- developer explicitly requests a multi-stream build.

If none apply, use one linear Implementation Partner run.

## Required Inputs

1. `parent_jira`: parent story key (for example, `PROJ-1234`).
2. `story_branch`: existing story branch name.
3. `feature_branch`: base feature branch name.
4. `draft_plan`: ordered stream candidates with:
   - `slug`
   - `scope`
   - `paths`
   - `acceptance_signal`
   - `depends_on`

The stream `slug` is an implementation-local identifier for dispatch and dependency references. It must never be reused as a Jira subtask, review-slice identity, review branch suffix, Stage 8/9 manifest key, or side-effect-ledger entry.

5. `jira_agreements`: `## Agreements` block from enriched parent Jira.
6. `plan_approval`: explicit developer approval for the exact validated plan revision. The pipeline engine supplies it only after validation and presentation; any plan change invalidates it.

## Procedure

### Step 1: Validate Stream Plan

Use the invoking agent's direct read/search tools to verify that stream path ownership is disjoint. This is an inline, read-only plan check, not a nested-agent invocation; do not dispatch `Explore` or create an auxiliary managed handoff for it.

Required verdict values:

- `DISJOINT`
- `OVERLAP`
- `UNRESOLVABLE`

If `OVERLAP`, merge streams or add prerequisite stream, then re-check.
If `UNRESOLVABLE`, stop and return failure to the pipeline engine.

Also validate:

- each stream has non-empty `scope` and `acceptance_signal`,
- `depends_on` is acyclic,
- dependency references point to known stream slugs.

### Step 2: Receive Approved Plan

Require `plan_approval` for the exact validated plan. Confirm that the pipeline engine presented the ordered streams, scopes, paths, acceptance signals, and dependencies and received explicit developer approval. If validation changed any of those fields, return the revised plan for presentation and stop; never dispatch against stale approval.

### Step 3: Initialize Stream Status Tracking

Create one status entry per stream:

- `not-started`
- `in-progress`
- `completed`
- `blocked`
- `scope-violation`

### Step 4: Dispatch Implementation Partner Runs

Dispatch each stream with:

- branch fixed to `story_branch`,
- strict owned-path boundary,
- required commit prefix: `[PARENT-JIRA]:`,
- no branch creation,
- no push.

Select the execution mode before dispatch:

- **Serialized compatibility mode (current default):** use the shared checkout and invoke one stream at a time. A stream completes its owned edits, validation, staging, and commit before the next eligible stream starts. Never leave two managed handoffs open.
- **Isolated fenced mode (future eligibility):** physical overlap is allowed only when each stream has an isolated workspace and immutable input package, the transition owner issued a distinct current fence for every handoff, all file and external-effect scopes are disjoint, and every participant rejects a stale fence before mutation and result recording. Shared integration and checkpoint decisions remain serialized.

If isolated workspace allocation, fence enforcement, external-scope proof, or serialized integration is unavailable or ambiguous, fall back to serialized compatibility mode. Never use a commit token as a substitute for isolating edits or fencing managed state and side effects.

Dispatch order:

1. prerequisite stream(s), if any,
2. independent streams one at a time in serialized compatibility mode, or concurrently only after isolated fenced eligibility is proven.

### Step 5: Monitor and Normalize Stream Results

For each stream return, record one-line normalized status:

- `completed`: commits and line delta,
- `blocked`: blocker reason,
- `scope-violation`: out-of-scope file touch.

If a stream returns no final text, verify landed changes through git state before deciding whether to re-dispatch. When no commit landed in a Jira-keyed run, call `pipeline-session consume-loop-budget(parent_jira, implementation_stream_silence, <silent-stream-handoff-id>)` before redispatch and continue only after that exact completed handoff is durably consumed. Stop on `loop_budget_exhausted`; never reset the count after interruption. In a keyless run, allow at most `governance.loop_budgets.implementation_stream_silence` redispatches.

### Step 6: Final Dispatch Summary

Before returning summary:

1. verify clean working tree for touched repositories,
2. verify commit prefix compliance,
3. verify each completed stream reported a distinct serialized commit SHA,
4. return structured summary only.

## Output Template

```yaml
streams_dispatched: <number>
execution_mode: serialized|isolated-fenced
streams_completed: <number>
streams_blocked: <number>
scope_violations: <number>
per_stream:
  - slug: <slug>
    status: completed|blocked|scope-violation
    commits: <number>
    commit_shas: [<full lowercase SHA for each verified serialized commit>]
    lines: <number>
ready_for_step_4: <true|false>
notes: "<optional blocker context>"
```

## Failure Modes

- Plan cannot be made disjoint.
- Dependency graph cycle.
- Stream blocked by unresolved dependency.
- Stream touches file outside owned paths.
- A second managed handoff is already open in serialized compatibility mode.
- Isolated workspace, current fence, or disjoint external scope cannot be proven; fall back to serialized execution.
- Silent stream return with no landed commits after one retry.

## Constraints

- Never implement code directly in this skill.
- Never create per-stream branches.
- Never bypass disjoint ownership rules.
- Never perform Acceptance Criteria (AC) audit.
- Never perform Quality Assurance (QA) review.
- Respect cross-project routing decisions in `jira_agreements`.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
