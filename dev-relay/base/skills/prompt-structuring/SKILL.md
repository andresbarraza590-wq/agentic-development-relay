---
name: prompt-structuring
description: 'Transform raw requirements into structured, self-contained prompts that a coding agent can execute without clarification. Use when producing developer-ready task descriptions from Jira stories or feature requests.'
---

# Prompt Structuring

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Convert requirements into execution-ready prompts that downstream coding agents can run without additional clarification.

## Operating Contract

1. Keep prompts self-contained.
2. Preserve requirement fidelity.
3. Separate scope from assumptions.
4. Make completion criteria explicit.

## When to Use

- Story Analyst handoff preparation.
- Pipeline engine implementation handoff packaging.
- Any workflow that requires deterministic execution prompts.

## Procedure

### Step 1: Define Objective

- Write one concise objective paragraph.
- State expected business or technical outcome.

### Step 2: Define Scope Surface

- List affected repositories and file groups.
- Identify ownership boundaries and key integration points.

### Step 3: Capture Technical Context

- Include architecture constraints, dependencies, and runtime assumptions.
- Include relevant repository conventions.

### Step 4: Include Acceptance Criteria

- Copy Acceptance Criteria verbatim from source.
- Preserve numbering and wording.

### Step 5: Add Implementation Guidance

- Include pragmatic hints based on existing patterns.
- Explicitly identify out-of-scope items.

### Step 6: Add Definition of Done

- Provide concrete, testable completion checklist.

## Output Template

```markdown
## Task: [Jira Key] - [Summary]
### Objective
### Affected Repositories and Files
### Technical Context
### Acceptance Criteria (Verbatim)
### Implementation Hints
### Out of Scope
### Definition of Done
```

## Quality Checks

- Prompt can execute without clarification.
- Acceptance Criteria are testable and preserved.
- File paths and module names are accurate.
- Scope and out-of-scope are unambiguous.

## Constraints

- Do not invent requirements.
- Do not modify Acceptance Criteria wording.
- Do not include unresolved assumptions without labeling them.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
