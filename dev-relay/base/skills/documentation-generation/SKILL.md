---
name: documentation-generation
description: 'Generate one final, Confluence-ready story document at pipeline Step 10 from pipeline outputs including intake context, implementation summary, QA findings, test coverage, and Acceptance Criteria (AC) status.'
---

# Documentation Generation

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Produce one consolidated Markdown document per parent Jira story after human review of the authorized direct or stacked PR delivery is complete.

This skill is a final-stage synthesis step invoked once at pipeline Step 10.

## Operating Contract

1. Run once per story wrap-up unless explicit re-run is requested.
2. Synthesize from validated pipeline artifacts only.
3. Preserve factual traceability to Jira, code, QA, and tests.
4. Keep output Confluence-ready Markdown.
5. Return the canonical `post_action_doc` payload defined below; callers must not reconstruct its fields.

## When to Use

- Primary use: pipeline Step 10.
- Re-run use: if accepted review or integration evidence changes after the applicable merge path completes and the controller requests a refresh before C10 acceptance and archival.

## Required Inputs

1. `parent_jira`
2. `story_title`
3. `story_branch`
4. `feature_branch`
5. `subbranch_manifest`
6. `pipeline_context` including:
   - intake summary and agreements,
   - implementation completion summary,
   - Quality Assurance (QA) findings summary,
   - tester coverage summary,
   - Acceptance Criteria (AC) status summary,
   - regression outcome,
   - human-review outcome and accepted review-delivery summary,
   - direct-mode Stage 8 feature/story equivalence plus canonical story-projection evidence after any feedback, or stacked-mode root-to-tip review, tip-to-root merge, PR1/story equivalence, and PR1-to-feature evidence,
   - feature-to-`develop` integration PR validation, approval, and merge, sourced from direct C8c or stacked C8d as applicable.
7. `report_identity`: for a managed invocation, the session's persisted lowercase UUID v4 `Run ID`, followed by `-` and the durable docs `handoff_id` with `:` replaced by `-`; for a standalone invocation, a caller-supplied filesystem-safe globally unique identity.

## Output Location

Write the final document to one immutable per-run path:

- `.github/artifacts/sessions/[PARENT-JIRA]/report.[REPORT-IDENTITY].md`

Require `REPORT-IDENTITY` to contain only ASCII letters, digits, `.`, `_`, or `-`; for a managed run it must equal the persisted Run ID plus the current docs handoff id with each `:` replaced by `-` (for example, `cb30f6d2-1b91-45d3-8ed4-29c8cb75e622-docs-documenter-default-1`). Create the directory path `.github/artifacts/sessions/[PARENT-JIRA]/` if it does not exist before writing the file. Write create-only: if the path exists, accept it only when its bytes exactly equal the newly rendered report for the same Run ID and handoff identity; otherwise return `report_identity_collision` without overwriting. Never reuse the fixed `report.md` path.

## Document Structure

Use this section order:

```markdown
# [PARENT-JIRA] - [Story Title]

## 1. Context
## 2. Scope and Agreements
## 3. Branching and Delivery Summary
## 4. Implementation Summary
## 5. QA Summary
## 6. Test and Coverage Summary
## 7. Acceptance Criteria Outcome
## 8. Regression Outcome
## 9. Human Review Outcome
## 10. Draft PR Manifest
## 11. Review Delivery and Integration
## 12. Risks, Follow-ups, and Notes
```

## Section Rules

### Context

- Summarize objective and key Jira context.

### Scope and Agreements

- Include in-scope, out-of-scope, and routing agreements.

### Branching and Delivery Summary

- Include canonical namespaced feature/story branches, their pinned revisions, and extraction approach summary.

### Implementation Summary

- Summarize implemented capabilities and key touched areas.

### QA Summary

- Include blocker and non-blocker findings with final disposition.

### Test and Coverage Summary

- Include executed test scope and either numeric coverage evidence from tester output or the exact structured not-applicable result (`status: not-applicable`, `source: agent-commands.yaml`, `reason: configured skip`). Never replace not-applicable coverage with zero.

### Acceptance Criteria Outcome

- Include status table using `Met`, `Partially Met`, `Not Met`, `Deviated`.

### Regression Outcome

- Record pass/fail and any caveats reported by developer.

### Human Review Outcome

- Record the C8c `review complete` decision and identify `slice_count`, `delivery_mode`, and the accepted manifest version.
- For direct mode, summarize the one feature-to-`develop` PR, Stage 8 feature/story equivalence, and canonical story-projection evidence after any feedback; do not invent review-subbranch or stack-collapse evidence.
- For stacked mode, summarize incremental root-to-tip slice review and the final disposition of every PR.
- For stacked mode, separately record C8d `integration complete`; never attribute final integration to C8c.
- When reactive feedback occurred, identify whether the accepted C9 cycle recycled an ownership-preserving suffix or created a plan-changing replacement suffix, without reproducing reviewer-sensitive content.

### Draft PR Manifest

- For direct mode, list the feature branch, `develop` base, Acceptance Criteria coverage, source/base revisions, and PR link.
- For stacked mode, list each ordinal review branch, dependency order, Acceptance Criteria coverage, source/base revisions, PR link, and recycled/replacement/superseded references.

### Review Delivery and Integration

- For direct mode, record Stage 8 feature/story tree equivalence, later canonical story-projection evidence when applicable, and the feature-to-`develop` PR's checks, approval, and merge.
- For stacked mode, record each incremental PR, tip-to-root collapse, PR1/story equivalence, PR1-to-feature landing, then the separate feature-to-`develop` PR and merge.
- Treat direct C8c or stacked C8d, respectively, as completed integration evidence. Step 10 must not instruct the developer to merge feature into `develop` again.

### Risks, Follow-ups, and Notes

- Capture deferred items and operational considerations.

## Formatting Rules

- Markdown only.
- Use consistent heading levels.
- Use tables for status where applicable.
- Avoid HTML blocks.
- Keep wording concise and evidence-based.

## Quality Checks Before Return

1. Confirm all required sections exist.
2. Confirm branch names and Jira keys are consistent.
3. Confirm Acceptance Criteria (AC) statuses match pipeline output.
4. Confirm coverage is either numeric and sourced from tester output, or exactly `status: not-applicable`, `source: agent-commands.yaml`, and `reason: configured skip` from the coverage skill. Reject missing, zero-substituted, or unsubstantiated coverage.
5. Confirm direct C8c includes final integration merge evidence; stacked C8c includes stack landing evidence and stacked C8d includes final integration merge evidence.
6. Confirm every parent approval/check identity matches the source and target revisions recorded immediately before its merge.
7. Confirm Stage 8 feature/story equivalence plus any required canonical story-projection proof in direct mode, or PR1/story equivalence and merge-commit-only collapse in stacked mode.
8. Confirm output path exists and file write succeeded.

## Return Payload

After the quality checks pass and the report is readable at the output path, return exactly this structured plain-text payload with concrete values:

```yaml
post_action_doc:
  path: ".github/artifacts/sessions/[PARENT-JIRA]/report.[REPORT-IDENTITY].md"
  sections_complete: true
  unresolved_followups: <non-negative integer>
  readiness: "confluence-ready"
  summary: "<one-line evidence-based report summary>"
```

The payload is the documentation stage's authoritative result. `sections_complete` may be `true` only after every required section and quality check passes. `unresolved_followups` counts the follow-ups recorded in the report; it does not decide whether they are acceptable. `readiness` describes the generated Markdown format and does not claim that a Confluence page was created. Do not include the full report body in this payload.

## Constraints

- Do not invent missing facts; mark unknowns explicitly.
- Do not modify source code or branches.
- Do not reopen QA, testing, or acceptance audits.
- Do not create Confluence pages directly in this skill.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
