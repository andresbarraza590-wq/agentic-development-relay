---
name: security-basics
description: 'Catch common security issues during code review. Use when checking for hardcoded secrets, SQL injection, input validation, or OWASP Top 10 vulnerabilities in code.'
---

# Security Basics

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Provide baseline security checks for changed code before review and release handoff.

## Operating Contract

1. Focus on high-risk, common vulnerability classes.
2. Require evidence for each finding.
3. Distinguish blocker security defects from advisory improvements.
4. Recommend specific fixes.

## When to Use

- Quality Assurance (QA) security pass.
- Pre-Pull Request (PR) hardening review.
- Re-review after security fixes.

## Core Checks

Each check below maps to a governance rule in `.github/config/guardrails.yaml` where an identifier is noted.

1. No hardcoded secrets (keys, passwords, tokens, credentials) (PII-1).
2. Query safety (parameterized access; no string-concatenated query input).
3. Input validation and sanitization at trust boundaries.
4. Response safety (no stack traces, local paths, or query internals leaked) (PII-2).
5. Least-privilege access scope.
6. Dependency risk awareness for known vulnerable packages.
7. Transport security (Hypertext Transfer Protocol Secure (HTTPS) in production paths).
8. Sensitive data exclusion from logs (for example, Personally Identifiable Information (PII), tokens, secrets) (PII-1/PII-2).

## Output Template

```text
Security Findings
- [severity] <finding>
  - Evidence: <file/symbol/behavior>
  - Impact: <risk>
  - Recommended Fix: <action>
```

## Constraints

- Do not claim full penetration-test coverage.
- Do not ignore medium/high risk findings due to schedule pressure.
- Do not log or reproduce sensitive values in reports.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
