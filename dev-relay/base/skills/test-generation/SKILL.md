---
name: test-generation
description: 'Create comprehensive automated tests covering logical paths and operational outcomes. Use when writing tests for application code and infrastructure code, designing cases for success/error/edge scenarios, and following project test conventions.'
---

# Test Generation

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Design and implement deterministic tests that validate intended behavior, failure paths, and coverage goals.

## Operating Contract

1. Prioritize in-scope changed behavior.
2. Ensure deterministic and isolated test execution.
3. Cover happy, edge, and failure paths.
4. Tag every AI-generated test file with the canonical provenance marker.
5. Report coverage and known gaps transparently.

These map to the test-quality guardrails in `.github/config/guardrails.yaml`: require real behavioral assertions rather than assertion-free or trivially-passing tests (TQ-1), never mock the code under test (TQ-2), and keep execution deterministic and isolated (TQ-3).

## When to Use

- Tester execution for new or modified code.
- Coverage-gap remediation work.
- Regression-risk validation before review handoff.

## Procedure

### Step 1: Analyze Test Surface

For each target unit, identify:

- input ranges and invalid inputs,
- control-flow branches,
- side effects,
- external dependencies,
- environment assumptions.

### Step 2: Build Test Matrix

Prioritize:

1. happy path,
2. error handling,
3. edge and boundary cases,
4. external dependency failures,
5. idempotency/re-run behavior where relevant.

### Step 3: Implement Tests

- Use repository-standard framework and fixtures.
- Mock/stub/fake external boundaries.
- Keep one primary assertion intent per test.
- Use clear assertion messages.
- Add `ai-generated: <JIRA-KEY> / tester-agent / <YYYY-MM-DD>` to every AI-generated test file using the language-native comment syntax. Use `KEYLESS` when no Jira key exists. A project-approved wrapper or annotation may accompany the marker but must not replace its canonical text.

### Step 4: Validate and Measure

- Run required project quality gates.
- Invoke the `code-coverage` skill as the coverage contract. When it returns numeric evidence, validate it against `.github/config/guardrails.yaml` thresholds (`coverage_minimum` and `coverage_business_logic`) and capture metrics plus missing-critical-path details. When it returns exactly `coverage: { status: not-applicable, source: agent-commands.yaml, reason: configured skip }`, preserve that result unchanged, run no coverage command, and never substitute zero or another number.

### Step 5: Report

Return:

- test files created/updated,
- provenance-marker status for every AI-generated test file,
- scenario coverage summary,
- numeric coverage evidence or the exact structured not-applicable coverage result,
- unresolved gaps and rationale.

## Constraints

- Do not modify production behavior while adding tests.
- Do not claim full coverage when excluded areas remain.
- Do not skip negative-path tests for changed business logic.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
