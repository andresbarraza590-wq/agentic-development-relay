---
name: code-review
description: 'Systematically review code for bugs, robustness, security, and maintainability issues. Use when reviewing changed files, evaluating code quality, or performing pre-PR code inspection.'
---

# Code Review

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Perform systematic quality review on changed code to identify defects, risks, and remediation actions before review handoff.

## Operating Contract

1. Focus on changed scope and direct impact.
2. Report evidence-based findings.
3. Prioritize functional and security risk over style preference.
4. Provide actionable remediation guidance.

When a finding touches a guardrail domain in `.github/config/guardrails.yaml`, reference the matching rule: sensitive-data or secret leakage (PII-1/PII-2), untrusted-input and injection risk (PIT-1), and weak or trivially-passing tests (TQ-1).

## When to Use

- Quality Assurance (QA) review pass.
- Pre-Pull Request (PR) quality gate.
- Re-review after fixes.

## Procedure

### Step 1: Understand Intended Behavior

- Confirm what changed and why.
- Identify impacted interfaces, callers, and side effects.

### Step 2: Evaluate by Review Domains

#### Correctness

- behavior matches requirement intent,
- control-flow paths are handled,
- returned values and side effects are correct.

#### Robustness

- null/None, empty, and boundary inputs are handled,
- failure behavior for dependency outages/timeouts is defined.

#### Security

- input handling and query construction are safe,
- secrets are not hardcoded,
- privilege and access scope are minimal.

#### Maintainability

- modules are focused and readable,
- naming and structure are clear,
- duplication and overly complex blocks are flagged.

#### Performance (when relevant)

- avoid avoidable repeated work and query amplification,
- flag hotspots that may regress at scale.

### Step 3: Produce Review Output

For each finding include:

- severity,
- evidence,
- impact,
- recommended fix.

### Step 4: Re-review After Fixes

- Verify each blocker is resolved.
- Verify no new regressions introduced.

## Constraints

- Do not rewrite code in this skill.
- Do not elevate style-only preferences to blockers.
- Do not replace Acceptance Criteria (AC) audit responsibilities.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
