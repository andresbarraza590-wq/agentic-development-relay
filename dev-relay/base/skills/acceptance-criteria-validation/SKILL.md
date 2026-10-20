---
name: acceptance-criteria-validation
description: 'Validate implemented code against Jira acceptance criteria. Use when checking if code satisfies story requirements, auditing AC compliance, or producing alignment reports with Met/Partially Met/Not Met/Deviated status.'
---

# Acceptance Criteria Validation

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Audit implementation against Jira-defined Acceptance Criteria (AC) using explicit evidence and consistent status outcomes.

## Operating Contract

1. Evaluate criteria one by one.
2. Require evidence for every status.
3. Separate requirement gaps from quality/style concerns.
4. Produce actionable remediation for non-met items.

## When to Use

- After implementation before Pull Request (PR) submission.
- During Acceptance Checker compliance audits.
- Whenever completion status against requirements is questioned.

## Procedure

### Step 1: Normalize Criteria List

- Split each Acceptance Criteria (AC) item into independent checks.
- Preserve verbatim requirement text for traceability.

### Step 2: Collect Evidence

- Inspect code, configuration, and tests related to each criterion.
- Record concrete file/symbol/test references.

### Step 3: Assign Status

Use one status per criterion:

- `Met`
- `Partially Met`
- `Not Met`
- `Deviated`

### Step 4: Explain Gaps

- For `Partially Met` and `Not Met`, state missing behavior explicitly.
- For `Deviated`, describe variance from requirement intent.

### Step 5: Recommend Fixes

- Provide specific next actions per non-met criterion.
- Prioritize blockers first.

## Output Template

```markdown
## Alignment Report: [Jira Key]

### Summary
- Total: <n>
- Met: <n>
- Partially Met: <n>
- Not Met: <n>
- Deviated: <n>

### Criteria Detail
#### AC1: "<verbatim criterion>"
- Status: Met | Partially Met | Not Met | Deviated
- Evidence: <file/symbol/test reference>
- Gap: <if any>
- Recommended Fix: <if needed>
```

## Constraints

- Never rewrite Acceptance Criteria (AC) text.
- Never mark `Met` without evidence.
- Never replace requirement validation with style review.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
