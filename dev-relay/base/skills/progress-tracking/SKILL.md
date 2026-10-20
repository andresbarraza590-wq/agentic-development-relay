---
name: progress-tracking
description: 'Monitor implementation progress against approved work units and acceptance criteria. Use when tracking implementation completion, mapping changed files to AC, or estimating remaining effort.'
---

# Progress Tracking

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Track execution progress against planned scope and Acceptance Criteria (AC) with clear status and remaining-work visibility.

## Operating Contract

1. Track progress using objective evidence.
2. Tie file changes to requirement outcomes.
3. Distinguish in-scope progress from scope creep.
4. Provide practical next-step guidance.

## When to Use

- Pipeline engine stream monitoring.
- Acceptance Checker progress visibility.
- Mid-implementation checkpoint reviews.

## Procedure

### Step 1: Compare Planned vs Changed Scope

- Compare changed files to the approved linear scope or implementation-stream ownership. These work units are not Jira review subtasks and do not define Stage 8 review branches.
- Flag files outside planned ownership as potential scope creep.

### Step 2: Map Work to Criteria

- Map each material change to one or more Acceptance Criteria (AC) items.

### Step 3: Assign Progress Status

Use statuses:

- `Met`
- `Partially Met`
- `Not Met`
- `Deviated`

Report out-of-scope changes under Scope Coverage; the Criteria Status count covers `Met`, `Partially Met`, `Not Met`, and `Deviated`.

### Step 4: Estimate Remaining Work

- Identify incomplete criteria and missing validations.
- Estimate effort by unresolved work clusters.

### Step 5: Recommend Next Actions

- Prioritize actions needed to reach `Met` for all required criteria.

## Output Template

```text
Progress Summary
- Scope Coverage: <in-scope vs out-of-scope changes>
- Criteria Status: <Met/Partially Met/Not Met/Deviated counts>
- Remaining Work: <top unresolved items>
- Next Actions: <ordered list>
```

## Constraints

- Do not mark criteria complete without evidence.
- Do not hide scope creep; surface it explicitly.
- Do not replace requirement progress with subjective confidence.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
