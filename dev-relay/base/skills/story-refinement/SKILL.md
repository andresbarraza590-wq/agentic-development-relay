---
name: story-refinement
description: "Evaluate Jira story quality before implementation begins. Score a story against a refinement scorecard, identify gaps in acceptance criteria, scope, and dependencies, and help the developer improve the story before the pipeline proceeds. Used by story-analyst at Step 1b."
---

# Story Refinement

Evaluate whether a Jira story is sufficiently refined for AI-assisted implementation. If it is not, guide the developer through improving it and route any approved Jira update through the invocation mode that permits the write.

## Purpose

- Assess story readiness before implementation starts.
- Score the story against the configured refinement criteria.
- Drive targeted improvements to acceptance criteria (AC), scope, and dependency clarity.

## When to Use

- Called by the **story-analyst agent** in `refine` mode after C1a developer Q&A is approved.
- Called manually when a developer wants to assess story readiness.

## Operating Contract

1. Score objectively against the configured criteria.
2. Provide concrete, testable refinements.
3. Keep the developer in control of the final story wording.
4. Do not block indefinitely when the developer chooses to proceed.
5. Record the score outcome for pipeline tracking.

## Required Inputs

1. Jira story fields (description, AC, points, sprint, epic, labels, components).
2. The approved C1a developer answers, including scope, exclusions, dependencies, and definition of done.
3. The refinement scoring rules from configuration.

## Procedure

### Step 1: Accept Resolved Scoring Criteria

Use the verified `story_refinement` section supplied by the caller. Story Analyst obtains it through the `configuration-resolution` skill. For a direct manual invocation without that input, invoke `configuration-resolution` in `read` mode for `story_refinement` before scoring. If verification fails, return its setup-validation blocker. Never read or merge the YAML sources directly.

### Step 2: Extract Story Fields

From the Jira ticket (already fetched by story-analyst):

- `description` — full text
- `Acceptance Criteria` — full text
- `Story Points` — numeric or null
- `Sprint` — assigned or null
- `Epic Link` — present or null
- `components` — list
- `labels` — list

### Step 3: Score Each Criterion

The scorecard's `required_fields` (`acceptance_criteria`, `description`) must be present for the story to be scoreable; a missing required field is an automatic gap. A required field is satisfied only by content present on the story itself — approved prior art, reuse lineage, a template from another ticket, or a reuse acceptance-criteria baseline adopted or referenced through the C1a developer answers is context for drafting suggestions, never a substitute for a missing required field, and must not be treated as if it were present when scoring. In particular, an acceptance-criteria baseline carried in from intake prior-art reuse does not make the story's `acceptance_criteria` field present; score that field only from acceptance criteria on the ticket itself. If the Jira ticket itself could not be read — the fetch failed, returned an error, or the required fields are otherwise unavailable — the story is unscoreable: return the read blocker rather than a score, and never let prior art, reuse lineage, or a cached template stand in for an unreadable ticket to manufacture a pass. Score each entry in `scored_criteria` and apply its configured weight using the fixed numeric mapping `high = 3`, `medium = 2`, and `low = 1`.

The supplied resolved `required_fields` and `scored_criteria` are the complete operative scorecard. The table below is a non-operative baseline example only; do not add or substitute its entries after an overlay replaces the configured sequences.

| Criterion | Weight | How to check |
| ----------- | -------- | -------------- |
| **AC is testable** | high | AC uses specific, measurable language ("when...then", "must", "should return"). Penalize vague words: "appropriate", "proper", "adequate", "as needed", "etc." |
| **Scope defined** | high | Description contains an objective or scope section (or user-story format: "As a...I want...so that"). |
| **Out of scope defined** | medium | Explicit exclusions are stated ("Out of Scope", "Not included", "Excluded"). |
| **Story points assigned** | low | Story points field is non-null. |
| **Sprint assigned** | low | Sprint field is non-null. |
| **Epic linked** | medium | Epic link is present. |
| **Dependencies noted** | medium | Description mentions dependencies or blockers ("depends on", "blocked by", "requires"). |

### Step 4: Compute Score

```text
score = sum(met_criteria x weight) / sum(all_criteria x weight)
```

Compare the result against the configured `pass_threshold`.

### Step 5: Present Results

The developer's optional refinement-drafting decision is continuation input requested only after the score, gaps, and choices below are presented. Jira mutation remains outside this skill.

**If score >= threshold:**

```text
Story JIRA-KEY passes the refinement check (score: 0.85)

Minor suggestions:
- Out of scope is not explicitly defined — consider adding.
- A Dependencies section would help the orchestrator plan subtasks.

Refinement complete; returning the outcome for C1b understanding confirmation...
```

**If score < threshold:**

```text
Story JIRA-KEY needs refinement before implementation (score: 0.42)

Acceptance Criteria: too vague
  Current:  "System should handle errors properly"
  Suggested: "When the upstream API returns HTTP 429, the service retries with
  exponential backoff (max 3 retries, 1s/2s/4s delays) and logs each retry
  attempt at WARNING level."

Out of Scope: not defined
  Suggested: add an "Out of Scope" section listing what this story
  intentionally excludes.

Dependencies: not mentioned
  Suggested: note any upstream stories or shared libraries this depends on.

Would you like me to:
1. `draft refinement improvements`
2. `proceed with refinement gaps`
3. `show refinement example`
```

### Step 6: Auto-Refine (If Approved)

When the caller resumes with the durably recorded `draft refinement improvements` decision:

1. Draft improved acceptance criteria using specific, testable language.
2. Draft an "Out of Scope" section based on the story context.
3. Add a "Dependencies" note if related epic issues exist.
4. Present the draft to the developer for review.
5. When called by story-analyst in `refine` mode, return the approved draft with Jira-update status `deferred to story-analyst enrich-jira`; do not write Jira. Deva persists the outcome and routes the eventual write through story-analyst's `enrich-jira` invocation.
6. In every invocation, return drafts only and set `Jira update: deferred to story-analyst enrich-jira`. Never mutate Jira directly. A caller that wants publication must route the exact approved draft through Story Analyst's `enrich-jira` mode, which owns target validation, original-description preservation, comment structure, managed handoff evidence, and audit continuity.
7. Re-score the approved draft to confirm whether it now passes.
8. Return the updated outcome to Story Analyst so it can complete the C1b brief.

## Output

Provide:

- the final refinement score,
- the pass/fail decision against the threshold,
- criterion-by-criterion gaps,
- proposed AC/scope/dependency improvements,
- the Jira-update status (`deferred to story-analyst enrich-jira`) and the relevant summary.

## Quality Heuristics for AC

**Good AC patterns:**

- "When [input], the system should [specific behavior]."
- "Given [state], when [action], then [observable result]."
- "Returns HTTP 404 with body `{error: 'not found'}` when the record is absent."
- Includes error scenarios, not just the happy path.
- Names specific data types, status codes, and field names.

**Bad AC patterns:**

- "System should work correctly." (vague)
- "Handle errors properly." (no specifics)
- "Good performance." (not measurable)
- "User-friendly." (subjective)
- Only the happy path, with no error or edge cases.

## Constraints

- Never invent requirements — only suggest improvements grounded in the story context.
- Present suggestions as drafts, not mandates — the developer decides.
- Do not block indefinitely — if the developer replies `proceed with refinement gaps`, continue with a warning.
- Return the refinement score and criterion-level evidence to the caller. When a managed Jira session exists, Deva passes that result to Pipeline Session for persistence; this skill never writes session state directly.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
