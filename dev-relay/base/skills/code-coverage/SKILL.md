---
name: code-coverage
description: 'Measure and ensure adequate test coverage. Use when verifying coverage targets are met, identifying uncovered branches, or generating coverage reports with per-file breakdown.'
---

# Code Coverage Analysis

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Measure test coverage against agreed thresholds and identify where additional tests are required.

## Operating Contract

1. Use repository-approved coverage workflow.
2. Report coverage transparently at total and per-scope levels.
3. Prioritize uncovered critical paths for remediation.
4. Preserve explicit exclusions in reports.

## When to Use

- After test authoring.
- During QA/test report preparation.
- When coverage thresholds are not met.

## Procedure

### Step 1: Confirm Coverage Command

Read the `coverage` command from `.github/config/agent-commands.yaml`. Run a command string as-is; if it is absent or empty, ask the developer rather than guessing; if it is `skip`, return `coverage: { status: not-applicable, source: agent-commands.yaml, reason: configured skip }` and stop this skill without running a command. Never substitute zero or another numeric value. Also confirm:

- focus areas,
- approved exclusions.

### Step 2: Execute Coverage

- Run the `coverage` command resolved in Step 1.

### Step 3: Evaluate Thresholds

Load thresholds from `.github/config/guardrails.yaml`:

- `governance.thresholds.coverage_minimum` for overall coverage,
- `governance.thresholds.coverage_business_logic` for core business-logic coverage.

Use current guardrail values as baseline defaults when validating runs.

### Step 4: Identify Gaps

- Highlight uncovered branches and critical missing lines.
- Classify gaps by risk and functional impact.

### Step 5: Report

Return:

- total coverage,
- per-file/module coverage,
- missing critical paths,
- recommended test additions.

For the configured `skip` path, return only the structured not-applicable coverage result defined in Step 1 plus any approved exclusions; numeric and per-file fields do not apply.

## Constraints

- Do not hide excluded files; label exclusions explicitly.
- Do not report threshold pass when critical-path coverage remains insufficient.
- Do not substitute line-only metrics for branch-risk analysis where available.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
