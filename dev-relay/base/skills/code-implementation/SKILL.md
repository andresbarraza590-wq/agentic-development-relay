---
name: code-implementation
description: 'Write clean, idiomatic, production-ready implementation artifacts following project conventions. Use when implementing new features, writing modules, or applying coding and infrastructure standards across languages and IaC stacks.'
---

# Code Implementation

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Implement production-ready changes that align with repository patterns, assigned scope, and operational constraints.

## Operating Contract

1. Implement only approved scope.
2. Follow repository-native architecture and style.
3. Optimize for maintainability and clarity.
4. Validate changes using the `build`, `lint`, and `test` commands from `.github/config/agent-commands.yaml`. Run each command string as-is. For `build` and `lint`, ask the developer when the value is empty and skip the step when its value is `skip`. For `test`, an empty or `skip` value requires a concrete developer-supplied command and a passing result before completion. Run a separate type check only when the repository defines one; do not invent a command.
5. Report deviations and risks explicitly.

## When to Use

- During Implementation Partner execution.
- When creating or updating functions, services, modules, templates, or infrastructure definitions.
- When scope requires code changes rather than review-only output.

## Procedure

### Step 1: Prepare Implementation Context

- Review nearby code for established patterns.
- Confirm behavioral contract: inputs, outputs, side effects, dependencies.
- Create a short plan of targeted edits.

### Step 2: Implement Safely

- Use clear interfaces (types/schemas/contracts where supported).
- Keep units focused on one responsibility.
- Apply explicit failure-path handling.
- Replace literals with named constants where appropriate.
- Externalize configuration and environment-specific values.
- Never hardcode credentials, identifiers, or secrets.

### Step 3: Preserve Repository Conventions

- Match naming and file organization patterns.
- Match import and dependency patterns.
- Match documentation style for public interfaces.
- When the repository does not define a convention, apply the verified
  `language_style_defaults.coding` section supplied by Implementation Partner.
  Do not read or merge the source YAML files in this skill.
- Match infrastructure conventions when editing Infrastructure as Code (IaC).

### Step 4: Validate Changes

- Run the configured build, lint, and test checks. Run the repository-native type check when one is defined separately or confirm it is included in those commands.
- Verify behavior against assigned Acceptance Criteria (AC).
- Confirm no unintended file or behavior drift.

### Step 5: Return Implementation Summary

Provide concise output:

- scope implemented,
- key files changed,
- validation commands run,
- result and any known limitations.

## Output Template

```text
Implementation Summary
- Scope: <implemented scope>
- Files: <paths>
- Validation: <commands and outcomes>
- Risks/Deviations: <if any>
```

## Constraints

- Do not include unrelated refactors in scoped work.
- Do not bypass project-required validation checks.
- Do not claim Acceptance Criteria (AC) compliance without evidence.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
