---
name: error-handling
description: 'Ensure consistent, user-friendly, and debuggable error handling across application and infrastructure code. Use when implementing failure handling, reviewing error patterns, or standardizing error responses and operation outcomes.'
---

# Error Handling Patterns

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Provide consistent, diagnosable, and safe error handling patterns for application and infrastructure workflows.

## Operating Contract

1. Prefer specific failure handling over catch-all patterns.
2. Preserve root-cause traceability.
3. Return stable caller-facing error contracts.
4. Prevent sensitive-data leakage in logs and responses (guardrail PII-2 in `.github/config/guardrails.yaml`).

## When to Use

- During Implementation Partner code changes that include failure paths.
- During Quality Assurance (QA) review of error behavior.
- When standardizing service or infrastructure operation outcomes.

## Procedure

### Step 1: Enumerate Failure Modes

- Identify expected dependency, validation, and state failures.
- Classify each as retryable or non-retryable where applicable.

### Step 2: Implement Specific Handling

- Catch specific exception classes or explicit error conditions.
- Map failures to stable error codes/messages.
- Preserve cause metadata for diagnostics.

### Step 3: Log with Safe Context

- Include operation name, target, and trace identifier.
- Exclude credentials, secrets, and sensitive payloads.

### Step 4: Validate Caller-Facing Contract

- Confirm status/outcome semantics are consistent.
- Confirm internal traces are not exposed in user-facing responses.

### Step 5: Verify Operational Clarity

- Ensure operators can determine next action from logs and outcomes.

## Patterns

### Do

```text
# Handle specific failure modes with context and propagation
TRY
    result <- CALL dependency(target)
CATCH TimeoutError AS err
    LOG_ERROR("Dependency timeout", { target_id: SAFE_IDENTIFIER(target), error_type: TYPE(err), trace_id: TRACE_ID })
    RAISE UpstreamUnavailableError("Dependency timed out", cause=err)
CATCH ConnectionError AS err
    LOG_ERROR("Dependency connection failed", { target_id: SAFE_IDENTIFIER(target), error_type: TYPE(err), trace_id: TRACE_ID })
    RAISE UpstreamUnavailableError("Dependency unreachable", cause=err)
END
```

### Don't

```text
TRY
    result <- CALL dependency(target)
CATCH AnyError
    IGNORE  # Swallows failures and hides root cause
END
```

### Error Response Structure

```json
{
  "error": "Validation failed",
  "code": "INVALID_INPUT",
  "message": "Input violates required format",
  "details": {
    "field": "resourceName",
    "constraint": "must match naming policy"
  },
  "traceId": "request-or-operation-id"
}
```

Note: `traceId` is the correlation identifier your platform's log tooling searches on.

### Service Status Guide (when applicable)

| Status | When to Use |
| ------ | ------------ |
| 400 | Invalid request data |
| 401 | Missing or invalid authentication |
| 403 | Authenticated but not authorized |
| 404 | Requested object not found |
| 409 | Conflict with current state |
| 422 | Data is syntactically valid but semantically invalid |
| 500 | Unexpected internal failure (do not expose internals) |
| 503 | Required dependency is unavailable |

### Infrastructure Operation Outcomes

| Outcome | When to Use |
| ------ | ------------ |
| VALIDATION_FAILED | Configuration, schema, or policy checks fail before apply |
| PLAN_FAILED | Change planning cannot complete due to dependency or syntax issues |
| APPLY_FAILED | Provisioning/update operation fails and requires remediation |
| ROLLBACK_REQUIRED | Partial changes applied and rollback or manual recovery is needed |
| RETRYABLE_FAILURE | Temporary external issue; retry with backoff is appropriate |
| NON_RETRYABLE_FAILURE | Deterministic failure; requires config/code fix before retry |

### Rules of Thumb

- Catch and handle specific failures whenever possible; avoid blanket catch-all handlers.
- Log actionable context (operation, target, identifiers, trace ID), but never log secrets.
- Return stable error codes/messages for callers; keep internal stack traces out of user-facing responses.
- For infrastructure workflows, fail fast on validation errors and clearly distinguish retryable from non-retryable failures.
- Preserve root cause information when rethrowing or mapping errors.

## Constraints

- Do not swallow errors silently.
- Do not expose implementation internals to external callers.
- Do not use inconsistent status or outcome semantics across similar failure types.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
