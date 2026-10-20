---
name: pipeline-session
description: 'Read, evaluate, and update the per-Jira pipeline session, including checkpoint milestone publication, so SDLC stages become composable. Use when running a single pipeline stage on its own, resuming a story, deciding which stages a full run may skip, or checking whether a completed stage has gone stale.'
---

# Pipeline Session

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Own the contract for per-Jira pipeline state and checkpoint milestones so that the pipeline's stages are composable: each stage can run on its own and records its result, a later full run **skips** whatever is already complete-and-fresh, and each approved checkpoint has one durable Jira audit comment.

This skill is the sole managed-state writer and operational pipeline mutation API for `session.md`, and the single publisher of pipeline checkpoint milestones to Jira. Read-only diagnostic prompts may inspect persisted session and activity files without becoming state owners or writers. The **stage list, dependency graph (`needs`), checkpoint declarations, and precondition policy live in `pipeline:` in `.github/config/guardrails.yaml`** — this skill reads them from there. Deva uses the full operation set to run, inspect, and record stages and invokes this checkpoint operation after every approval. Every pipeline specialist invokes a read-only entry guard: normal stage work uses `check-preconditions(<stage>)`, while explicitly registered repair and secondary modes use `check-managed-handoff`; specialists never mutate session state through either check.

## Operating Contract

1. Treat `pipeline:` in `.github/config/guardrails.yaml` as the source of truth for stages, `needs`, `checkpoint`, optional ordered `checkpoints`, `checkpoint_decisions`, `kind`, optional `execution`, optional `trigger`, `source_ref`, `standalone_safe`, and `precondition_policy`. Never duplicate that graph here. A stage with `checkpoints` uses those human-facing gates in order and keeps `checkpoint` as its completion gate; every other stage has the single human-facing gate in `checkpoint`. Every gate has non-empty `advance` and `revise` reply lists in `checkpoint_decisions`; all replies are exact, lowercase, whole-message phrases, and every reply is globally unique.
2. Persist approved / complete stage work as **resumable**. You may also persist **in-progress** state for live progress visibility, but never treat an in-progress (or rejected) work as resumable or skippable — only `complete`-and-fresh stages are skippable.
3. A stage may run only when every stage in its `needs` is `complete` **and** not `stale`.
4. Recompute staleness on every read — never trust a stale-looking `complete` blindly.
5. Record, never invent: only write a `source_ref`, timestamp, or artifact you actually observed.
6. Never write secrets, tokens, credentials, or PII into the session file (PII-1 in `.github/config/guardrails.yaml`).
7. **Initialize first.** The first session operation of every run is `init`, before any `status`, `mark-in-progress`, `write-stage`, or precondition check, so `session.md` and `activity.log` are both created up front rather than lazily on the first stage write or first logged event.
8. **Flush every state transition immediately (no buffering).** Each state transition writes the complete file to disk in a single `edit`-tool call the moment the change happens — never buffer, batch, or defer. An operation may own multiple ordered transitions when an external post-condition separates them; for example, `approve-checkpoint` first persists approval with `milestone: pending`, then promotes that to `milestone: posted` only after Jira and activity evidence verify. Each transition is independently written and read back, so an external observer sees every observable boundary as it occurs.
9. **One consistent snapshot.** The four regions of `session.md` — the header block, the Stage Status table, the Checkpoint Ledger table, and the Artifacts — describe the same moment, and every write leaves them in agreement. Never advance the Stage Status table while leaving the header, a ledger row, or an artifact lagging a checkpoint behind; the stage table is not the live truth with the rest catching up later.
10. **Checkpoint Ledger updates are canonical keyed table-row replacements, never row insertions.** The schema-8 ledger is one Markdown table with columns `checkpoint`, `status`, `decision-reply`, `milestone`, and `updated`. `init` creates two registry checkpoint rows, in registry order, including reactive C8d. Before any later operation mutates the ledger, parse the complete table between `## Checkpoint Ledger` and `## Artifacts`, derive the expected ordered checkpoint set from the registry, and require one uniquely valid data row after the header and separator. Update only existing keyed rows in that in-memory map, render the **entire** table in registry order, and replace the complete ledger table region in the same snapshot write. Never implement a ledger mutation by replacing a short run of table rows, appending a row, or inserting a later gate: every gate already exists from `init`. `approve-checkpoint` changes only the current gate, except an explicit multi-checkpoint special case may also update a pre-existing sibling gate of the same stage (C8a → C8b). A later, separate `mark-in-progress` call updates the next stage's gate. Read the persisted table back from disk and require the exact header, key, cardinality, order, and updated field values before returning or publishing any activity or Jira milestone.
11. **Persistence leads narration; an exact semantic decision leads completion.** Every stage entry is persisted through `mark-in-progress` before narration. A stage completes only through `approve-checkpoint` after the entire checkpoint's registered `advance` replies. A registered `revise` reply keeps the checkpoint pending and routes correction or stop behavior without milestone publication. C0b completes `architecture`, C1a completes `intake`, and C1b separately completes `refine`; none authorizes another. Never infer a decision from a record, earlier checkpoint, autonomous/full-run wording, or a model-generated claim.
12. **One Jira milestone per checkpoint.** After local checkpoint state is durable, publish exactly one redacted Jira milestone identified by `<JIRA-KEY>:<checkpoint>`. Check existing comments before posting, so retries and fresh Deva instances cannot duplicate a milestone. A publication failure blocks advancement but never rolls back the durable local approval; a retry resumes publication from that state.
13. **Record external side effects before and after execution.** The `subbranch-extractor` invokes `update-side-effect` around review-delivery branch, push, pull-request, comment, and supersede mutations. The `integration-publisher` invokes `update-integration-side-effect` around final integration pull-request creation and refresh. Each operation updates only its fixed side-effect ledger and the header timestamp; neither advances a stage or checkpoint or appends a stage activity event.
14. **Pin runtime configuration.** `init` records the verified resolved-configuration source fingerprint. A later run with a different fingerprint blocks until the developer explicitly adopts the new configuration; adoption marks prior completed work stale before any stage continues.
15. **Archive completion is an attested post-condition.** Only `archive` may promote or move a completed live session into the archive, rotate archives, mutate the reuse index, or emit archive lifecycle events. The sole removal exception is `discard(JIRA-KEY, confirmed=true)`, which deletes an explicitly abandoned live session without archiving it and preserves all prior archive state. For a full run, `archive` is also the sole owner of `event=run_complete`, which it appends only after the promoted hash, exact index entry, lifecycle events, and cache removal all verify. It returns success only with concrete, read-back-verified evidence for those post-conditions. Callers never reproduce these actions or synthesize `archive_complete` or `run_complete_verified`.
16. **Every actual subagent invocation has one durable handoff lifecycle.** Immediately before invoking a nested agent, Deva calls `begin-subagent-handoff`; immediately after the invocation returns or fails, Deva calls `complete-subagent-handoff` with its real outcome. Each invocation has one stable `handoff_id` and one terminal ledger outcome. When the event severity clears the configured threshold, it also has one INFO `[Subagent:<name>] event=enter` and exactly one terminal `event=return` at INFO, WARN, or ERROR according to outcome; an intentionally suppressed INFO event returns `threshold_skipped: true` and never replaces the durable row. Retries and multiple modes within one stage are separate handoffs. A skipped stage, controller-owned step, or external human wait creates no handoff row and uses its applicable stage event instead.
17. **Retry budgets are durable and idempotent.** Every session-managed bounded retry consumes one stable attempt identity through `consume-loop-budget` before retry work begins. The fixed Loop Budget Ledger is append-only; a repeated identity is an idempotent recovery, while a new identity at the configured cap returns `loop_budget_exhausted` before another repair handoff or mutation. Never count retries from chat memory, handoff row count, stage timestamps, or side-effect attempts.

## When to Use

- **Single-stage run** — Deva runs one stage out of band (routed from do-it) and records it.
- **Full-run skip decision** — Deva decides which stages to skip vs. run.
- **Resume** — a story is picked back up and state must be restored.
- **Status display** — Deva shows a ticket's per-stage progress.

## Session File Location

- Before resolving any location, limit, retention period, or log threshold, read its `pipeline.*` value from `.github/config/guardrails.yaml`. If a required key cannot be read, stop and return a blocker rather than substituting a local value.
- One **live** file per Jira key: `<session_dir>/<JIRA-KEY>/session.md`, where `<session_dir>` is `pipeline.session_dir` in `.github/config/guardrails.yaml`. This is the working copy a run reads, resumes, and skips against.
- `<JIRA-KEY>` is the story key used in `feature/<user>/<PARENT-JIRA>` and canonical `feature/<user>/story/<PARENT-JIRA>`.
- The `init` operation creates the `<JIRA-KEY>` directory and `session.md` up front as the first session operation of every run; every write flushes to disk immediately. Human-readable markdown. The `<session_dir>/<JIRA-KEY>/` directory is reserved **exclusively** for `session.md` — no other consumer may write scratch, report, or PR-body files into it (`activity.log` lives in the separate `pipeline.log_dir` tree). Stage any transient content (for example a multi-line draft-PR body) in an OS temp path outside the pipeline trees, so the cache directory stays a single-file, cleanly archivable unit.
- **On full-run completion the session is archived, not wiped.** The `archive` operation identifies the completed session by content hash, durably records archive intent, prepares the reuse-index entry while the live source remains recoverable, promotes the session into `<archive_dir>/<JIRA-KEY>/session.md`, verifies both promoted content and index, then removes only the empty cache directory. A retry resumes from the persisted archive identity rather than rotating or moving the same run again. Archived sessions are **local-only** (the configured archive tree is gitignored) and retained for `pipeline.archive_retention_days`, after which age-known artifacts become prunable; within that window they support audit, troubleshooting, and follow-up similar stories. A re-run of the same key rotates any prior archive to the single path persisted by the new archive intent. A **single-stage** run never archives, and a **discard** deletes the cache without archiving (see the `archive` operation and Constraints).

## session.md Format (schema 8)

```text
# Session: [JIRA-KEY]

- Schema: 8
- Status: IN_PROGRESS | COMPLETE
- Run ID: <lowercase UUID v4>
- Configuration Fingerprint: <lowercase-sha256>
- Active Stage: <stage-id>
- Active Checkpoint: <registered C0a..C10, including C8c and C8d>
- Updated: <ISO-8601 timestamp>

## Stage Status
- state: not_started | in_progress | complete | stale
- source_ref: value captured at completion (used to detect staleness); "-" when the stage has none
- checkpoint: the stage's completion gate from the registry — STATIC, never rewritten at runtime.
#   A multi-checkpoint stage keeps its completion gate here; earlier sub-gates appear only in
#   the header's Active Checkpoint while live.
| stage           | state        | checkpoint         | source_ref            | updated (ISO-8601)    | by                      |
|-----------------|--------------|--------------------|-----------------------|-----------------------|-------------------------|
| <registry stage id> | not_started  | <registry checkpoint> | -                     | -                     | -                       |

## Checkpoint Ledger
| checkpoint | status  | decision-reply | milestone | updated |
| ---------- | ------ | -------------- | ------- | ------- |
| <registry checkpoint> | pending | - | - | - |

## Artifacts
<!-- Fixed set of named subsections, one each. Writing an artifact replaces the body
     under its heading in place; never duplicate a heading or add a second copy. -->
### Setup Result
<cached setup validation outcome>

### Understanding / Scope / Agreements
<confirmed summary from C1b>

**Prior-Art Search Evidence:**
- Local reuse index: <read | missing | unreadable>
- Archived-session fallback: <enumerated; candidates | enumerated; none | missing | unreadable>
- Federated sources: <Jira/architecture/repository/Confluence/Stack Overflow/<BASE_ENGINEERING_ECOSYSTEM> outcomes>
- Candidates: <source keys/documents | none>
- Reuse decision: <pending C1a | approved | trimmed | rejected | none found>

### Agreement Revision History
<!-- Preserve the original C1b agreement and every later revision decision. At most one revision is pending. -->
<ordered revision entries containing stable id, source/document, prior agreement,
 proposed agreement, delta/reason, affected AC/ownership, stale-from stage, status,
 developer decision, Jira publication state, and timestamps; or none>

### Architecture Context
<pre-existing | generated | refreshed | refresh declined | refresh failed (existing metadata preserved) | skipped | absent (generation failed)>

### Branch Info
- user-segment: <normalized branch segment>
- feature-branch: feature/<user>/<PARENT-JIRA>
- feature-sha: <full lowercase commit SHA>
- story-branch: feature/<user>/story/<PARENT-JIRA>
- story-sha: <full lowercase commit SHA>
- story-tree: <full lowercase Git tree SHA>
- base-branch: <develop | approved existing feature branch>
- base-sha: <full lowercase commit SHA>

### Implementation
<implemented scope, changed files, validation, and known limitations>

### QA Findings
- Resolved: <list>
- Open: <list>

### Test Report
- Coverage: <n>% / target <m>% | status: not-applicable; source: agent-commands.yaml; reason: configured skip
- Added: <list>

### Acceptance Criteria
<AC status table: Met | Partially Met | Not Met | Deviated>

### Pushed Ref
<remote story-branch ref and observed commit SHA>

### Regression
- Request: <not requested | awaiting developer result>
- Round ID: <stable non-empty identity | ->
- Checklist: <exact checklist | ->
- Result: <not recorded | pass | fail + notes>

### Subbranch Manifest
<`slice_count`, `delivery_mode`, feature/story baseline SHAs and trees; entries containing
 `pr_ordinal`, acceptance_criteria, scope, branch, head_sha, head_tree, pr_base,
 pr_base_sha, depends_on, extraction, paths, files, non_test_lines, pr_url, validation,
 and any recycled/replacement/superseded references. Direct mode has one entry whose
 branch is the feature branch and requires feature/story tree equivalence. Stacked mode
 has ordinal review branches and requires cumulative tip/story tree equivalence.>

### Draft PR Manifest
<exact prepared manifest authorized at C8b, or not authorized>

### Subbranch Side-Effect Ledger
<!-- One row per externally visible operation. Write the intended operation before executing it,
     then update that same row after reconciliation or success; never append a duplicate attempt. -->
| entry | operation | idempotency_key | intended_target | status | returned_identifier | reconciled_at |
|-------|-----------|-----------------|-----------------|--------|---------------------|---------------|
| <exact-approved-branch> | <branch-create, branch-push, integration-commit, pr-create, pr-comment, or supersede> | <lowercase SHA-256> | <ref/head-base/PR target> | <intended, partial, complete, abandoned, or superseded> | <ref/commit/PR URL or id/comment id, or -> | <ISO-8601 timestamp or -> |

### Subagent Handoff Ledger
<!-- One row per actual nested-agent invocation. begin-subagent-handoff creates the row and
     complete-subagent-handoff terminates that same row; never infer a row from stage state. -->
| handoff_id | stage | subagent | mode | status | outcome | started_at | completed_at | reason |
|------------|-------|----------|------|--------|---------|------------|--------------|--------|
| <stage>:<subagent>:<mode>:<ordinal> | <stage> | <agent> | <mode-or-default> | <started|complete> | <pending|ok|blocked|fail|empty> | <ISO-8601> | <ISO-8601 or -> | <redacted reason or -> |

### Loop Budget Ledger
<!-- One row per consumed session-managed retry. Stable attempt identities make interrupted
     retries idempotent and keep configured caps enforceable across chats and resumes. -->
| budget | attempt_id | ordinal | consumed_at |
|--------|------------|---------|-------------|
| <governance.loop_budgets key> | <stable single-line identity> | <positive integer> | <ISO-8601> |

### Reextract Result
<direct ownership-preserving story-delta projection with canonical_story_projection_verified,
 stacked ownership-preserving recycled suffix, stacked plan-changing replacement/superseded
 suffix, or review-delivery-restart-required; validation, source/target SHAs, and mode-specific
 delivery proof; or not run>

### Human Review
<pending | complete result matching the Subbranch Manifest delivery_mode. Direct mode contains
 Stage 8 feature/story tree equivalence, canonical story projection after any feedback, plus
 feature-to-develop PR validation, current approval, and merge.
 Stacked mode contains incremental root-to-tip review evidence; every tip-to-root source/target
 SHA, current approval, required-check SHA, and merge reference; PR1/story tree equivalence;
 and PR1-to-feature merge. Final feature-to-develop integration belongs to C8d.>

### Integration PR
<not applicable for direct delivery | pending stacked C8c | stacked integration_pr candidate
 containing parent/story/feature/target revisions, evidence hash, PR id/url, draft status,
 publication outcome, projection proof, and C8d checks/approval/merge status>

### Integration Side-Effect Ledger
<!-- One row per externally visible final integration operation. -->
| entry | operation | idempotency_key | intended_target | status | returned_identifier | reconciled_at |
|-------|-----------|-----------------|-----------------|--------|---------------------|---------------|
| <feature-branch> | <integration-commit, branch-push, pr-create, or pr-update> | <lowercase SHA-256> | <story-delta, feature ref, head/base, or PR/evidence target> | <intended, partial, or complete> | <commit/ref/PR URL or id, or -> | <ISO-8601 timestamp or -> |

### Post-Action Document
<persisted post_action_doc path, section-completion flag, unresolved-followup count, readiness, and one-line summary; never the full report body>

### Reuse Digest
<!-- Written at docs/C10 for follow-up similar stories: structured and greppable.
     SECRET/PII SCRUB (PII-1): before writing, scrub every field — never emit tokens,
     credentials, connection strings, internal hostnames/IPs, or sensitive Jira content.
     The leak-prone fields are Files changed, Commands run, Gotchas, and Links: redact any
     embedded secret or host to a placeholder rather than copying it verbatim. -->
- Tags: <component / module / platform / entity / endpoint keywords for similarity search>
     <!-- If the overlay pins a canonical tag vocabulary, pick from it FIRST; add a freeform
     tag only when no canonical tag fits. With no overlay vocabulary, tags are freeform. -->
- Related Jira: <parent / epic / linked | duplicate issue keys — one per line, or "-">
- Files changed: <path — one-line rationale> (one per line)
- Prior art reused: <libraries, shared helpers, patterns adopted>
- Key decisions: <decision — rationale> (one per line)
- Rejected alternatives: <option — why not>
- Tests added: <coverage <n>% (target <m>%) | coverage not-applicable (source: agent-commands.yaml; reason: configured skip)
- Commands run: <build/test commands and outcomes>
- Gotchas: <pitfalls encountered>
- Links: story-branch <branch>; PRs <urls>; Jira <key>; post-action <artifacts/sessions/[JIRA-KEY]/report.[REPORT-IDENTITY].md>
```

Rebuild the Stage Status table row set from `pipeline.stages` in `.github/config/guardrails.yaml` (id order = `step` order), so it always matches the registry. Build the Checkpoint Ledger table from each stage's ordered `checkpoints` list when present, otherwise from its single `checkpoint` value. New rows start with `status: pending`, `decision-reply: -`, `milestone: -`, and `updated: -`.

Map every stage's registry `produces` value to exactly one fixed artifact subsection:

| `produces` | Fixed subsection |
| --- | --- |
| `setup_result` | `### Setup Result` |
| `architecture_context` | `### Architecture Context` |
| `understanding` / `refined_understanding` | `### Understanding / Scope / Agreements` |
| `branch_info` | `### Branch Info` |
| `implementation` | `### Implementation` |
| `qa_findings` | `### QA Findings` |
| `test_report` | `### Test Report` |
| `ac_status` | `### Acceptance Criteria` |
| `pushed_ref` | `### Pushed Ref` |
| `regression_result` | `### Regression` |
| `subbranch_manifest` | `### Subbranch Manifest` |
| `review_outcome` | `### Human Review` |
| `integration_result` | `### Integration PR` |
| `reextract_result` | `### Reextract Result` |
| `post_action_doc` | `### Post-Action Document` |

This table is the complete artifact-write map. A registry stage whose `produces` value is absent from it is `artifact_mapping_missing` and cannot start or complete until the source contract is updated. Intake writes the initial shared understanding; refine replaces that same subsection with the confirmed implementation-ready understanding. The split stage additionally owns its authorization and side-effect subsections under the explicit C8a/C8b rules below. Reactive `integration` stays `not applicable` for direct delivery and remains pending until stacked C8c approval; reactive `reextract` keeps `not run` when unused.

## Activity Log

A per-Jira, append-only activity stream that records what the pipeline actually did, for debugging and post-mortem. **Only the deva feeds it** — no other agent writes activity.

- One file per Jira key: `<log_dir>/<JIRA-KEY>/activity.log`, where `<log_dir>` is `pipeline.log_dir` in `.github/config/guardrails.yaml`.
- The `init` operation creates the `<JIRA-KEY>` directory and the (empty) `activity.log` up front as the first session operation; no other operation creates or re-creates live state.
- It lives in a **separate tree** from the session cache and from the archived sessions, so archiving or discarding a live session does not remove it. It is retained for `pipeline.archive_retention_days` and becomes prunable only when its latest parseable event timestamp is older than that TTL. On completion the archived `session.md` is promoted into the artifact tree at `<archive_dir>/<JIRA-KEY>/session.md`, while this log stays in `<log_dir>/<JIRA-KEY>/activity.log`.
- Append-only: never rewrite, reorder, or truncate existing lines; new events are appended in chronological order.

### Line format

One event per line:

```text
<ISO8601-UTC> sess=<JIRA-KEY> <LEVEL> [<Component>:<name>] event=<verb> key=val ...
```

- `<LEVEL>` — `DEBUG | INFO | WARN | ERROR` (severity order `DEBUG < INFO < WARN < ERROR`). Which lines are actually written is gated by `pipeline.log_level` (see **Log level**).
- `<Component>` — `Agent | Subagent | Stage | Checkpoint | Skill | Tool`.
- `event=<verb>` plus any `key=val` pairs carry the detail; keep values short and space-free (quote if a value must contain a space).

Examples:

```text
2026-08-11T14:03:21Z sess=PROJ-1234 INFO [Agent:deva] event=run_start mode=full
2026-08-11T14:03:22Z sess=PROJ-1234 INFO [Stage:implement] event=enter owner=implementation-partner
2026-08-11T14:03:23Z sess=PROJ-1234 INFO [Subagent:implementation-partner] event=enter handoff_id=implement:implementation-partner:default:1 stage=implement mode=default
2026-08-11T14:18:44Z sess=PROJ-1234 INFO [Subagent:implementation-partner] event=return handoff_id=implement:implementation-partner:default:1 stage=implement mode=default outcome=ok
2026-08-11T14:19:05Z sess=PROJ-1234 INFO [Checkpoint:C3] event=approved decision="run quality checks"
2026-08-11T15:02:10Z sess=PROJ-1234 WARN [Stage:push] event=blocked reason=suite_red
2026-08-11T15:40:33Z sess=PROJ-1234 DEBUG [Stage:qa] event=skip reason=complete_fresh
```

**The line shape above is mandatory and must not be restyled between runs.** Emit every field in this exact order — `<ISO8601-UTC>`, `sess=<JIRA-KEY>`, a bare `<LEVEL>`, one `[<Component>:<name>]` tag, `event=<verb>`, then optional `key=val` pairs — on every line of every run. The surface form is fixed evidence that downstream diagnostics parse, not free narration.

- Never drop `sess=<JIRA-KEY>` or the bare `<LEVEL>` token, and never bracket the level (`INFO`, not `[INFO]`).
- `<Component>` is the closed set `Agent | Subagent | Stage | Checkpoint | Skill | Tool`. Never invent tags such as `[Run:<uuid>]`, `[Run]`, `[Handoff:...]`, or `[Archive]`; carry a run identifier, when useful, as a `run_id` pair rather than in the component tag.
- Record nested-agent handoffs as `[Subagent:<name>] event=enter` / `event=return` — never `[Handoff:...]` and never the verbs `handoff_start` / `handoff_end`.
- `[Stage:<id>] event=enter` carries `owner=<registry runs-value>`, the real specialist for that stage — never a generic `owner=deva`.

### Events to record (full touchpoint set)

Each event has a fixed severity; `pipeline.log_level` decides which are actually written.

- `event=run_start` — **INFO** — `[Agent:deva]`, with `mode=full|single`.
- `event=enter` — **INFO** for `[Stage:<id>]` with `owner=<registry runs-value>` when a stage starts; this never proves that a nested agent ran. **INFO** for `[Subagent:<name>]`, with `handoff_id=<id> stage=<stage> mode=<mode>` immediately before every actual nested-agent invocation.
- `event=return` — **INFO** for `[Subagent:<name>]` on `outcome=ok|empty`, **WARN** on `outcome=blocked`, and **ERROR** on `outcome=fail`; include `handoff_id=<id> stage=<stage> mode=<mode>` and a short redacted `reason=` when not `ok`. Every subagent enter has exactly one return, including blockers, failures, empty results, and retries.
- `event=stage_complete` — **INFO** — `[Stage:<id>]`, used when one sibling of a shared checkpoint completes while the checkpoint remains pending (`checkpoint=<Cx> milestone=deferred`), or when `split` finalizes after C8b was already approved (`checkpoint=C8b`).
- `event=approved` / `event=rejected` — **INFO** — `[Checkpoint:<Cx>]`, with `decision="<exact-registered-reply>"` (approval fires alongside `write-stage`; rejection fires through `record-revision`).
- `event=revision_selected` — **INFO** — `[Checkpoint:<Cx>]`, with `choice=<exact-registered-revise-reply>` when a revision path is durably selected while the gate remains pending.
- `event=milestone_posted` — **INFO** — `[Checkpoint:<Cx>]` after the idempotent Jira milestone is confirmed.
- `event=milestone_failed` — **ERROR** — `[Checkpoint:<Cx>]`, with a short redacted `reason=`; advancement remains blocked until publication succeeds.
- `event=checkpoint_ledger_reconciled` — **WARN** — `[Checkpoint:<Cx>]`, only after explicit developer confirmation repairs a pending table row from matching complete stage, artifact, approval-activity, Jira-marker, and milestone-activity evidence.
- `event=regression_request_staged` — **INFO**, non-filterable — `[Agent:deva]`, with `round_id=<redacted-single-line-id>` after the exact checklist request is durably staged before the hard turn.
- `event=regression_result_staged` — **INFO**, non-filterable — `[Agent:deva]`, with `round_id=<redacted-single-line-id> outcome=pass|fail` after the identity-matched developer result is durably staged before C7 or repair.
- `event=repair_baseline_recorded` — **INFO**, non-filterable — `[Stage:implement]`, with the persisted owner, handoff, attempt, and transition identities before a repair loop resumes.
- `event=on_demand_authorized` / `event=on_demand_completed` — **INFO**, non-filterable — `[Stage:architecture]`, with `authorization_id=<id>` when an on-demand architecture request is authorized and when its result is persisted.
- `event=operation_authorization_staged` / `event=operation_authorization_recorded` — **INFO**, non-filterable — `[Agent:deva]`, with stage, action, and payload hash when an external-operation decision is staged and recorded.
- `event=refinement_decision_recorded` — **INFO**, non-filterable — `[Agent:deva]`, with decision and assessment hash after a pending refinement decision is consumed.
- `event=result_recorded` / `event=round_replaced` — **INFO**, non-filterable — `[Stage:reextract]`, with the persisted round identities when a result lands on an authorized replacement supersedes it.
- `event=review_delivery_restarted` / `event=integration_review_restarted` — **INFO**, non-filterable — `[Agent:deva]`, with the prior-delivery identity needed to resume replacement split planning.
- `event=skip` — **DEBUG** — `[Stage:<id>]`, `reason=complete_fresh` when a full run skips a fresh stage.
- `event=rerun` — **DEBUG** — `[Stage:<id>]`, `reason=stale` when a stale stage is re-run.
- `event=blocked` — **WARN** — `[Stage:<id>]`, `reason=<missing_dep|stale_upstream|precondition>` on a precondition failure or escalation.
- `event=run_complete` — **INFO**, non-filterable — `[Agent:deva]`; for a full run, owned by `archive` and appended with `archive_id=<id> status=COMPLETE` only after archive promotion, reuse-index verification, lifecycle verification, and cache removal succeed. For a single-stage `docs` run, Deva appends it with `mode=single status=COMPLETE` after C10 completes because that mode does not archive.
- `event=configuration_adopted` — **INFO** — `[Agent:deva]` after explicit developer approval adopts the current configuration fingerprint; include no configuration content.
- `event=agreement_revision_requested` — **INFO** — `[Agent:deva]`, with `revision_id=<id> source_stage=<stage>` after a scope-changing proposal is durably staged.
- `event=agreement_revision_rejected` — **INFO** — `[Agent:deva]`, with `revision_id=<id>` after `keep current agreement` is durably recorded.
- `event=agreement_revision_accepted` — **INFO** — `[Agent:deva]`, with `revision_id=<id> stale_from=<stage>` after `confirm revised agreement` updates the canonical agreement and invalidates affected descendants.
- `event=agreement_revision_finalized` — **INFO** — `[Agent:deva]`, with `revision_id=<id> jira_source_ref=<ref>` after the accepted revision's Jira enrichment is observed and persisted.
- `event=jira_enrichment_authorized` / `event=jira_enrichment_declined` — **INFO** — `[Agent:deva]`, with `brief_hash=<sha256>` after the exact non-checkpoint decision is persisted.
- `event=jira_enrichment_completed` — **INFO** — `[Agent:deva]`, with `brief_hash=<sha256> handoff_id=<id> jira_source_ref=<ref>` after ordinary refinement enrichment is observed and finalized.
- `event=split_plan_candidate_rejected` — **INFO** — `[Agent:deva]`, with `candidate_hash=<sha256>` after the exact C8a revision selection retires a staged candidate before replacement planning.
- `event=split_plan_revision_requested` — **INFO** — `[Agent:deva]`, with `revision_id=<id>` after a plan-changing initial-extraction retry is staged with reconciled side-effect dispositions.
- `event=split_plan_revision_rejected` — **INFO** — `[Agent:deva]`, with `revision_id=<id>` after `keep approved split plan` is durably recorded.
- `event=split_plan_revision_accepted` — **INFO** — `[Agent:deva]`, with `revision_id=<id>` after `confirm revised split plan` authorizes its exact disposition plan.
- `event=split_plan_revision_finalized` — **INFO** — `[Agent:deva]`, with `revision_id=<id>` after those dispositions verify and one replacement initial-extraction attempt becomes authorized.
- `event=prune_intended` / `event=prune_completed` — **INFO** — `[Agent:deva]`, with `prune_id=<sha256>` and the validated archive target; these form the resumable per-story session/report prune pair.
- `event=report_prune_intended` / `event=report_prune_completed` / `event=report_age_evidence` — **INFO**, non-filterable — the global prune journal evidence for rejected reports and their retained age authority.
- `event=log_prune_intended` / `event=log_prune_completed` — **INFO**, non-filterable — the global prune journal pair for one age-verified activity log.
- `event=discarded` — **INFO** — `[Agent:deva]`, with `outcome=live_session_removed` after explicit developer abandonment and before deleting the live story session.
- `event=archive_intended` — **INFO** — `[Agent:deva]`, with `archive_id=<sha256-of-completed-session>`, `target=<archive-session-path>`, and `rotation=<planned-prior-archive-path-or-none>` before index preparation or filesystem promotion.
- `event=archive_promoted` — **INFO** — `[Agent:deva]`, with the same `archive_id` and `target` after the archived file is present and its hash matches.
- `event=reuse_index_appended` — **INFO** — `[Agent:deva]`, `index=<reuse_index_file>` after the `archive` operation has written **and verified** this run's reuse-index line.
- `event=reuse_index_append_failed` — **ERROR** — `[Agent:deva]`, with a short redacted `reason=`; the reuse-index line did not land, so archival is incomplete and run completion stays blocked until the line is written and verified on retry.
- `event=archive_cache_not_empty` — **ERROR** — `[Agent:deva]`, with `archive_id=<id>` and `reason=unexpected_residue`; promotion and index verification succeeded, but unknown live-cache content blocks cleanup and archive completion.
- `event=archive_cache_removed` — **INFO** — `[Agent:deva]`, with `archive_id=<id>` after the exact live story-cache directory is verified absent.

### Log level

The threshold is `pipeline.log_level` in `.github/config/guardrails.yaml`. `append-activity` normally writes an event only when its severity is at or above the configured level, using the order `DEBUG < INFO < WARN < ERROR`. State-critical checkpoint events (`approved`, `rejected`, `revision_selected`, `milestone_posted`, and `checkpoint_ledger_reconciled`), regression-request events, repair-baseline events, on-demand architecture events, operation-authorization events, refinement-decision events, Jira-enrichment events, agreement-revision events, split-plan-revision events, re-extraction round events, review-restart events, discard events, prune events, archive lifecycle events, and terminal `run_complete` are non-filterable and are always appended because session consistency and recovery require their durable evidence.

- **DEBUG** — write everything, including stage `skip` and `rerun` mechanics. Best for troubleshooting.
- **INFO** — retain stage entries, every actual subagent handoff enter/return, run start/complete, and checkpoint approvals/rejections; drop DEBUG `skip` and `rerun` mechanics.
- **WARN** — non-filterable lifecycle evidence plus stage blockers, blocked subagent returns, and failures.
- **ERROR** — non-filterable lifecycle evidence plus failures (`return outcome=fail` and `milestone_failed`).

The level gates **writing only** — it never changes stage behavior, checkpoints, or `session.md`.

## Reuse Index

A single managed index across completed stories, so prior-art lookups have one cheap place to scan before opening any archived session. **Only the deva writes it** as part of the `archive` operation.

- One file for the whole log tree: `<reuse_index_file>`, where `<reuse_index_file>` is `pipeline.reuse_index_file` in `.github/config/guardrails.yaml`. It lives in the same gitignored, local-only log tree as the activity logs.
- The `archive` operation adds **one line per completed story**. It may update an earlier line when archive rotation changes that line's target, and removes lines when their archives expire under the retention policy. It is created on first archive if missing. The append is a **verified post-condition**: `archive` re-reads the index after writing and blocks on `reuse_index_append_failed` when this run's line is absent, so a completed archive can never silently skip its index entry.
- Each line is a compact pointer: the Jira key, the completion date, the digest `Tags`, a one-line summary, and a relative link to the archived `session.md`. Apply the same secret/PII scrub as the digest (PII-1) — the summary and tags must carry no secrets, hosts, or sensitive Jira content.

<!-- markdownlint-disable-next-line MD024 -->
### Line format

One story per line, in completion order:

```text
| <JIRA-KEY> | <YYYY-MM-DD> | <tag, tag, tag> | <one-line summary> | [session](../artifacts/sessions/<JIRA-KEY>/session.md) |
```

When a re-run rotates a prior archive, update the earlier line to point at the rotated `session.<timestamp>.md`, then add the new line for the current `session.md`. When an archive is pruned under the TTL, drop its index line in the same pass.

## Stage States and Staleness

- **not_started** — never run.
- **in_progress** — started but not yet approved/complete; not skippable and normally rerun. It is resumable only when `status`/`next-stage` returns one of the explicitly defined durable continuation actions for staged decisions, authorized secondary work, split extraction/review/publication, or reviewer correction. No unlisted in-progress shape is resumable.
- **complete** — approved and recorded, with a `source_ref` (when the stage defines one) and timestamp.
- **stale** — was `complete`, but an input changed. A stale stage is treated as **not done** for skip decisions and must be re-run.

A `complete` stage is **stale** when any of these hold:

1. **Its own `source_ref` changed.** For `source_ref: story_branch_head`, the story branch HEAD advanced since the recorded sha. For `source_ref: jira`, compare the latest externally-owned Jira revision with the recorded revision. Ignore pipeline-owned writes: Story Analyst enrichment performed as part of `refine` completion, and milestone comments carrying this pipeline's exact `Milestone-ID: <JIRA-KEY>:<checkpoint>` marker. Capture the `refine` source reference after its required enrichment write, so the completed intake includes all pipeline-owned changes — the same pipeline-owned enrichment never makes the already-complete `intake` stale either. Stages with no `source_ref` have no self-staleness.
2. **An upstream changed.** Any stage in its `needs` is `stale`, or was re-completed with a newer `updated` timestamp than this stage's.
3. **The approved review delivery changed.** Completing reactive `reextract` at C9 replaces the canonical `Subbranch Manifest`. Mark any completed stacked `integration` result and `docs` result stale; set the session `Status` back to `IN_PROGRESS`. The integration pull request and Post-Action report must be refreshed from current evidence.
4. **Stacked integration changed.** A C8d feedback repair, feature update, target revision change, or integration PR refresh marks any completed `docs` result stale until C8d is completed again with current evidence.
5. **The resolved configuration changed and was explicitly adopted.** Compare the session's `Configuration Fingerprint` with the current fingerprint returned by `configuration-resolution` verification. Before adoption, return `configuration_changed` and do not mutate the session. After explicit adoption, replace the fingerprint, set `Status: IN_PROGRESS`, and mark every `complete` stage `stale`; the normal dependency graph then controls reruns. Never combine results produced under different configuration fingerprints silently.

Staleness **propagates downstream**: if `implement` goes stale, then `qa`, `tests`, `acceptance`, and everything after them are stale too.

## Operations

> **Run `init` first.** Every run's first session operation is `init` (below), so `session.md` and `activity.log` both exist before any other session operation. Every operation writes its file to disk immediately — a single `edit` per change, never buffered or batched (see Operating Contract items 7–8). Deva uses `approve-checkpoint` only with a valid registered advancing decision; that operation coordinates the local write and Jira milestone publication.

### init(JIRA-KEY, mode, requested_stage, config_fingerprint, adopt_configuration=false)

Run this as the **first session operation** of every run (full or single) — before `status`, `mark-in-progress`, `write-stage`, or any precondition check. It makes the session artifacts exist up front so they are created consistently, not lazily.

1. Require `config_fingerprint` to be the lowercase SHA-256 returned by `configuration-resolution` `verify-setup-cache`; reject a missing or malformed value. Create `<session_dir>/<JIRA-KEY>/` and `session.md` from the schema-8 template immediately when they do not exist (all stages `not_started`, `Status: IN_PROGRESS`), generate one cryptographically random lowercase UUID v4 as `Run ID`, and record that fingerprint. Preserve the Run ID on every retry and mutation. For a single-stage `requested_stage`, when the live session is absent but `<archive_dir>/<JIRA-KEY>/session.md` exists, copy that archived snapshot into the live session first, preserve its Run ID and the archive, and set the live `Status` to `IN_PROGRESS`; this restores the completed `split` dependency and prior manifest without fabricating state. Reactive `integration` is never a standalone requested stage. A fresh full run after archival creates a new UUID and never derives identity from a timestamp, Jira key, or handoff ordinal.
2. Create `<log_dir>/<JIRA-KEY>/` and an empty `activity.log` immediately, so the log file exists from the start of the run **regardless of `pipeline.log_level`** (the level gates which event *lines* are appended, not whether the file exists). If it already exists, leave it.
3. If a live or restored session has the same fingerprint, leave its progress intact. If it has no fingerprint, treat it as an older schema and require explicit adoption. If it has a different fingerprint and `adopt_configuration` is false, emit `event=run_start` (`mode=full|single`) via `append-activity` only when the log has no matching unresolved `run_start` for this run, then return `configuration_changed` with the recorded and current fingerprints and `session_created: true | false`. Do not mutate session progress and do not append `event=configuration_adopted`; ask whether to adopt the validated configuration and rerun stale work or stop. If explicit adoption is supplied, update the fingerprint, mark every `complete` stage `stale`, set `Status: IN_PROGRESS`, and append `event=configuration_adopted` with no configuration content. Treat that adoption event as the retry's run-opening event; do not append a second `run_start`.
4. Set `Updated` to now (ISO-8601).
5. Before the write, apply every eligible schema migration in memory, including schema 6→7, schema 7→8, and legacy schema-6 ledger normalization. A pre-2.2.3 schema-6 session without `Run ID` receives one UUID v4 during this `init` write only; a pure read never invents it. Flush both files to disk right away (Operating Contract item 8), then re-read `session.md` and run `schema-shape-check` before returning. A newly created or normalized session must contain the canonical header fields including Run ID, complete Stage Status table, five-column Checkpoint Ledger table, Agreement Revision History, every fixed artifact subsection, Subbranch and Integration Side-Effect Ledgers, Subagent Handoff Ledger, and Loop Budget Ledger exactly once. Return `checkpoint_ledger_corrupt` for conflicting list/table evidence; return `session_schema_corrupt` and do not begin setup/C0a validation when it is otherwise partial or hand-rolled.
6. Emit `event=run_start` (`mode=full|single`) via `append-activity` unless step 3 already emitted or reused a pending `run_start`, or this invocation emitted `configuration_adopted`.
7. Return `session_created: true` when step 1 created `session.md`; otherwise return `session_created: false`. This explicit value is the controller's cold-start discriminator and must not be reconstructed from in-memory state.

### status (read-only)

1. Read `session.md`. If absent → all stages `not_started`, `Status: (none)`.
2. If `Schema` is missing or `1`, first apply **v1 → v2 back-compat** (below) in memory.
3. Apply the versioned compatibility parser in memory before strict shape validation, including schema 6→7 and schema 7→8. For a schema-6 list-form ledger, parse it into the canonical keyed table map before writing; conflicting or coexisting list/table evidence returns `checkpoint_ledger_corrupt`. Then run `schema-shape-check` against the normalized in-memory representation before staleness or stage selection. Return `session_schema_corrupt` with the missing, duplicate, malformed, or unknown regions when it fails; do not persist normalization or silently infer missing evidence during a read.
4. Run **staleness-scan** and return the per-stage state map, the `Active Stage`/`Active Checkpoint`, and the next actionable stage. Before normal selection, compare every complete stage with its checkpoint table row while the activity log contains exactly one registered `event=approved` decision and exactly one `event=milestone_posted` for that gate, return `checkpoint_ledger_recovery_required` with the ordered affected checkpoints and do not select or resume a stage; this is a corruption blocker, not proof of approval. Return the same Jira-enrichment, split-plan-revision, review-delivery-restart, and integration publication/refresh resume actions defined by `next-stage` whenever their durable state is unresolved. Preserve the existing split continuation rules. When `regression` is `in_progress`, and `### Regression` contains one valid request with `Request: awaiting developer result`, return `resume_action: resume_regression_result` with that exact persisted request. When that subsection instead contains one identity-matched result with `Result: pending C7 decision`, return `resume_action: resume_C7_decision` with the exact persisted result; do not invoke Regression Runner again or begin repair before consuming it. When `review` is `in_progress` and C8c is pending with `decision-reply: review changes requested`, return `resume_action: resume_review_changes`. When stacked C8c is approved and `integration` is `in_progress` with a partial or intended publication row, return `resume_action: resume_integration_publish`; when C8d has `decision-reply: integration changes requested` and refreshed evidence is pending, return `resume_action: resume_integration_refresh`.

### staleness-scan

For each `complete` stage, in `step` order, apply the staleness rules above; downgrade to `stale` where they hold, propagating downstream. Configuration-fingerprint mismatch is handled by `init` before this scan and requires explicit adoption. This is in-memory for a read; persist it only as part of a `write-stage`. Schema upgrades are also applied in memory on a pure read and persisted only by the next approved `write-stage`. Schema 6→7 adds the integration stage/checkpoint/artifacts through its explicit migration; schema 7→8 adds the empty durable Loop Budget Ledger without inventing historical attempts. Never infer C8d approval, an integration PR, or a prior retry count from existing prose or timestamps.

### check-preconditions(stage)

1. Run `subagent-handoff-consistency-check(all, allow_active_stage=stage)` before evaluating a new stage. Permit at most one `started` handoff only when this stage equals `stage`, its subagent equals that stage's registry `runs` value, and no other handoff is open; this is the current specialist invocation that Deva durably began immediately before dispatch. Any prior, unrelated, duplicate, or conflicting open handoff blocks with its returned handoff id. If Agreement Revision History contains a pending decision or an accepted revision awaiting Jira publication, return its agreement-revision resume action and do not evaluate a normal stage. Then load the stage's `needs` from the registry.
2. For every dependency, require both its stage row to be `complete` and its registered checkpoint ledger entry to be `approved` with either (a) `decision-reply: <registered advance reply for that checkpoint>`, or (b) the legacy `approval-token: approve <checkpoint>` already persisted by an older framework version. Also require a matching `[Checkpoint:<checkpoint>] event=milestone_posted` activity line and confirm Jira contains exactly one comment with `Milestone-ID: <JIRA-KEY>:<checkpoint>`. A `complete` row without valid decision and publication evidence is inconsistent and blocked; never infer approval or publication from the row, artifact, successful outcome, or unrelated files. Legacy decision evidence is read-only compatibility for an already-approved session and is never emitted for a new decision; it still requires the milestone evidence. **Reactive re-extraction exception:** for stage `reextract` only, permit dependency `split` to be `stale` after the reviewer-fix commit advances the story branch, but still require durable C8b approval, its publication evidence, and the canonical `Subbranch Manifest` re-extraction exists to replace that stale approved stack. In addition, require `review` to be `in_progress` and C8c to remain pending with exact `decision-reply: review changes requested` C9 when this trigger evidence is absent. No other stage may consume a stale dependency or use pending revision evidence as authorization.
3. If any dependency is not `complete`, is `stale`, lacks the evidence-bearing approved checkpoint, or lacks either milestone copy → **blocked**, except for the exact `reextract`/`stale`-`split` case defined in step 2. Return `checkpoint_milestone_pending: <checkpoint>` when the decision is approved but Jira or activity evidence is absent or duplicated; otherwise return the earliest unresolved checkpoint and apply `precondition_policy.on_missing_dep`: name the missing, stale, or pending upstream stage and refuse to start the requested stage until that checkpoint is explicitly resolved. (For a stale upstream, apply `on_stale_upstream`.) Recover a milestone blocker only through `recover-milestone`, which reads the persisted decision itself; never pass that old reply as a synthetic current developer message, and never post or append outside the owning operation.
   - For `integration`, require the canonical manifest to have `delivery_mode: stacked`, `review` complete, C8c approved with exact `decision-reply: review complete`, current C8c milestone evidence, complete stack-collapse evidence, and C8d not complete. Return `integration_not_applicable: direct` for direct delivery.
   - For `docs`, direct delivery requires current C8c approval and merged feature-to-`develop` evidence in Human Review. Stacked delivery additionally requires `integration` complete, C8d approved with exact `decision-reply: integration complete`, current C8d milestone evidence, and merged Integration PR evidence. Return `checkpoint_pending: C8d` when stacked integration is absent or pending.
4. If the stage's `standalone_safe` is `false` → also require its heavy precondition (stated in the stage `description`, for example local suite green and AC met for `push`); surface it explicitly and require confirmation before running.
5. Otherwise → **ready**.

### check-managed-handoff(handoff_id, subagent, mode)

Use this read-only operation instead of `check-preconditions(stage)` only when a specialist is invoked inside another stage's bounded repair or agreement-revision flow. It validates the exact durable invocation without reopening the specialist's normal registry stage or changing any checkpoint.

1. Require exactly one `started` Subagent Handoff Ledger row matching `handoff_id`, `subagent`, and `mode`, and require no other open handoff. Require the row's `stage` to be the owning pipeline stage supplied to `begin-subagent-handoff`, not the specialist's ordinary registry stage.
2. Permit only these combinations:
   - `subagent: implementation-partner`, `mode: repair`, owner stage `qa`, `acceptance`, `regression`, `review`, or `integration`;
   - `subagent: tester`, `mode: repair`, owner stage `qa`, `tests`, or `integration`;
   - `subagent: story-analyst`, `mode: revise-agreement`, owner stage `implement` with that stage `in_progress` and one complete `scope_change_required` evidence bundle returned by its latest completed Implementation Partner handoff; the proposed revision does not exist yet because this handoff produces it;
   - `subagent: story-analyst`, `mode: enrich-jira`, owner stage `refine`, with `refine` `in_progress`, C1a and its milestone current, and the canonical understanding carrying `Jira Enrichment Authorization` status `authorized`, exact `decision-reply: enrich jira`, and a brief hash matching the brief supplied to this handoff;
   - `subagent: story-analyst`, `mode: enrich-jira`, owner stage equal to an agreement revision's persisted `source_stage`, with that revision in `accepted_jira_pending` state.
3. For repair modes, require the owner stage to be `in_progress`, its upstream checkpoints and milestones to remain current, and `check-loop-budget` for the owning loop to report `remaining > 0` or the current stable attempt identity to be already consumed. For `revise-agreement`, require the owner stage `in_progress` and the source evidence described above, but never require a staged candidate before the candidate-producing handoff. For ordinary `refine` enrichment, require the durable authorization to remain current for the supplied brief. For agreement-revision `enrich-jira`, permit the exact owner row to be `stale` because accepting the candidate deliberately invalidates it before Jira publication. No other stale, complete, or not-started row is valid.
4. Run `subagent-handoff-consistency-check(all, allow_handoff_id=<id>)`. Return `ready` only when the row and any required enter event are current. Otherwise return the exact handoff, agreement-revision, milestone, or loop-budget blocker. This operation never marks a stage in progress, changes a ledger gate, or treats a repair result as completion of the specialist's normal stage.

### record-repair-implementation-baseline(JIRA-KEY, owner_stage, handoff_id, attempt_id, result, source_ref)

Call immediately after an `implementation-partner` / `repair` managed handoff completes and before any refreshed QA, tests, acceptance, publication, regression, re-extraction, or integration work. This operation advances the durable implementation baseline to the repaired story-branch HEAD without reopening C3 or inventing another implementation approval.

1. Require `owner_stage` to be `qa`, `acceptance`, `regression`, `review`, or `integration`, with that owner `in_progress`. Require exactly one completed `implementation-partner` / `repair` handoff matching `handoff_id`, owned by that stage, with `outcome: ok`, and no open handoff. Require `attempt_id` to identify the consumed loop-budget row that authorized this repair; its budget must be the owner stage's registered repair budget and `check-loop-budget` must report `attempt_consumed: true` for that identity.
2. Require `implement` to have been complete at C3 before the repair, with substantive canonical `### Implementation` evidence, C3 approved through a registered advancing decision, and current C3 milestone evidence. Require `result` to be the unchanged substantive repair result returned by that repair. Reject a missing, unchanged, non-commit, or caller-reconstructed `source_ref` and any placeholder result without mutation.
3. Preserve the original C3 decision reply, approval timestamp, Jira milestone, approval activity, and prior implementation evidence. Append one keyed repair-baseline entry to `### Implementation` containing `owner_stage`, `handoff_id`, `attempt_id`, the unchanged repair result, observed `source_ref`, and timestamp. Set only the `implement` row to `complete` at that source reference with the new timestamp and `by: implementation-partner`; never append another C3 approval or milestone event.
4. Run `staleness-scan` after updating `implement`. This newer completion timestamp deliberately marks previously completed downstream evidence stale, while the repaired `implement` row itself remains complete and fresh so `check-preconditions(qa)` and `check-preconditions(tests)` can authorize their refresh. Keep the repair owner `in_progress`, its checkpoint pending with the existing revision evidence, and the header bound to that owner and checkpoint.
5. Write and read back the complete schema-8 snapshot, proving the C3 evidence is unchanged, the repair entry and source reference match the supplied values, downstream completed stages are stale, and the owner remains in progress. Append exactly one non-filterable `[Stage:implement] event=repair_baseline_recorded owner=<owner_stage> handoff_id=<handoff_id> attempt_id=<redacted-attempt-id> transition=<timestamp>` activity line and verify it. Return `repair_implementation_baseline_recorded` with the current implementation source reference. An exact retry is idempotent; changed evidence for the same handoff or attempt is `repair_implementation_baseline_conflict`.

This operation records implementation evidence only. It does not complete the repair owner, approve a checkpoint, consume a budget, or treat refreshed QA, tests, acceptance, publication, or regression as complete.

### mark-in-progress(stage)

Call when a stage **starts** (at the handoff into its subagent), to keep `session.md` current in real time rather than only at checkpoint approval.

1. Require both `session.md` and `activity.log` to exist. If either is absent, return `init_required` without creating or mutating state. Before changing anything, apply `check-preconditions(stage)` inside this operation. If it is blocked, return `checkpoint_pending` with the earliest unresolved blocker and do not mutate the session or append activity. This makes the dependency barrier mandatory even when the caller forgot to check it.
2. Set the stage row: `state: in_progress`, `updated` (now, ISO-8601), `by` (the `runs` value). Leave `source_ref` as `-` until completion, and leave the row's `checkpoint` column at its static registry value — never overwrite it with a sub-gate id (the two-checkpoint `split` stays `C8b`; single-checkpoint stages keep their own gate, `intake` `C1a` and `refine` `C1b`).
3. In the **same write**, bring the header and ledger into agreement with that row so none of them lag: set `Active Stage`/`Updated` to this now-`in_progress` stage (never an earlier one), and set `Active Checkpoint` to the gate now live for it — the two-checkpoint `split` stage's first sub-gate (`C8a`) while that gate is running, otherwise the stage's single completion gate (for example `intake` → `C1a`, `refine` → `C1b`). `Active Checkpoint` is always a checkpoint **of** `Active Stage`; it never holds a different stage's value (for example `Active Stage: architecture` with `Active Checkpoint: C0a` — C0a is setup's gate in a broken view). Update that live gate's existing Checkpoint Ledger table row to `status: pending`, `decision-reply: -`, `milestone: -`, and `updated: <now>`. Apply Operating Contract item 10: update that gate's existing keyed table row in the parsed map and replace the complete ledger table region. Never insert this stage's gate after the preceding checkpoint; it has existed since `init`.
4. Write the file with the `edit` tool. Do **not** mark the stage `complete` — that happens only in `write-stage` after the checkpoint is approved.
5. Immediately after the session write, append the paired fixed-severity **INFO** `event=enter` activity line via `append-activity` for `[Stage:<id>]`, with `owner=<the runs value>` and `transition=<the row's updated timestamp>`. This is stage ownership only; an actual nested invocation requires the separate INFO Subagent enter/return lifecycle. If the append fails, return `activity_append_pending` and stop before narration or the next pipeline action. On retry, detect the durable `in_progress` row and append the missing event idempotently with that same transition id before continuing; do not rewrite the session timestamp or emit a duplicate event.
6. `in_progress` is **not** skippable and normally reruns from the start. The only resumable exceptions are exact continuation actions returned by `status`/`next-stage`; each consumes its persisted payload and must not call `mark-in-progress` again or repeat already-completed planning, research, extraction, or authorization.

### record-on-demand-architecture-request(JIRA-KEY, request_text, source)

Persist the explicit authorization for a Jira-keyed architecture run requested after C0a recorded `skip architecture`. This is an out-of-band refresh of the architecture context, not a replay of the completed architecture stage.

1. Require `source` to be `direct` or `do-it`. For `direct`, require the trimmed entire top-level developer message to equal `run architecture on <JIRA-KEY>` case-sensitively. For `do-it`, require the unchanged routed payload to identify the developer-selected architecture stage and the same Jira key; a parent-authored paraphrase or inferred intent is invalid.
2. Require `setup` and `architecture` complete and fresh, C0a approved with exact `decision-reply: skip architecture`, C0b approved with valid decision and milestone evidence, `Architecture Context: skipped`, no unresolved architecture authorization, and no open managed handoff. Never alter either checkpoint, any stage row, or downstream state.
3. Persist one On-Demand Architecture Authorization entry containing a new stable authorization id, source, redacted exact request, request hash, `status: authorized`, and timestamp. Append the non-filterable `[Stage:architecture] event=on_demand_authorized authorization_id=<id>` activity line and read back both records. An exact retry returns the same id; conflicting or fabricated evidence returns `on_demand_architecture_unauthorized` without mutation.
4. Return `on_demand_architecture_authorized: true` and the authorization id. This operation does not call `mark-in-progress`, reopen C0b, or authorize a normal full-run stage transition.

### check-on-demand-architecture-authorization(JIRA-KEY, authorization_id)

Read the persisted On-Demand Architecture Authorization and return `authorized` only when exactly one matching entry is still authorized, its request hash and activity event are current, the Jira key matches, C0a/C0b evidence remains unchanged, and no other architecture invocation has consumed it. Otherwise return `on_demand_architecture_unauthorized`. This operation is read-only and never treats a parent claim or the old C0a skip reply as authorization.

### record-on-demand-architecture-result(JIRA-KEY, authorization_id, result)

Call immediately after the authorized architecture-bootstrapper managed handoff completes. Require its exact usable outcome, no open handoff, and the matching authorization still `authorized`. Replace only `Architecture Context: skipped` with the unchanged validated outcome, mark the authorization `completed`, append `[Stage:architecture] event=on_demand_completed authorization_id=<id>`, and read back the session and activity records. Preserve every stage row, source reference, checkpoint decision, checkpoint milestone, and downstream artifact byte-for-byte. A failed or blocked specialist result remains recorded on the authorization without being promoted as architecture context. Exact retries are idempotent; mismatched ids or outcomes return `on_demand_architecture_conflict`.

### record-stage-result(JIRA-KEY, stage, result)

Durably stage a specialist result that must survive the hard turn boundary before its checkpoint decision. This operation owns two hard-turn candidates: `push` before C6 and `docs` before C10. It records candidate evidence but never approves the checkpoint or completes the stage.

1. Require `stage` to be `push` or `docs`, an existing session/activity pair, that stage's row `in_progress`, and its checkpoint (C6 or C10) pending. Otherwise return `checkpoint_pending: <C6|C10>` or `init_required` without mutation.
2. Validate the unchanged owning-specialist payload:
   - For `push`, require exactly one `pushed_ref` mapping with `story_branch`, `remote_ref`, `head_sha`, `push_result`, `test_command`, `test_summary`, `tests_passed`, `acceptance_disposition`, `force_push`, `protected_branches_touched`, `subbranches_or_prs_created`, and `blockers`. Require `remote_ref` to equal `origin/<story_branch>`, `head_sha` to be a full lowercase commit SHA, `push_result` to be an observed SHA range or `already-up-to-date`, `test_command` and `test_summary` to be non-empty single lines, `tests_passed` to be `true`, `acceptance_disposition` to be `all-met` or `deferred-gaps`, both safety booleans to be `false`, and both counts to be zero. On failure return `artifact_missing: pushed_ref` without changing state.
   - For `docs`, require exactly one `post_action_doc` mapping with `path`, `sections_complete`, `unresolved_followups`, `readiness`, and `summary`. Require `sections_complete` to be boolean `true`, `unresolved_followups` to equal a non-negative integer (not boolean), `readiness` to equal `confluence-ready`, and `summary` to be a non-empty single line. Require `path` to match `.github/artifacts/sessions/<JIRA-KEY>/report.<REPORT-IDENTITY>.md`, where the identity contains only ASCII letters, digits, `.`, `_`, or `-` and equals the session's persisted Run ID followed by `-` and the completed docs handoff id with `:` replaced by `-`. Require the report writer's create-only result: an existing path is valid only for a byte-identical retry of this identity; a collision is `artifact_missing: post_action_doc` with reason `report_identity_collision`. Apply the same readable/non-empty report checks defined for `write-stage(docs, ...)`. On failure return `artifact_missing: post_action_doc` without changing state. Persist only those fields; do not store the full report in `session.md`.
3. Replace the registry-mapped fixed artifact body with the validated fields and a pending marker: `Approval: pending C6` under `### Pushed Ref`, or `Acceptance: pending C10` under `### Post-Action Document`. Keep the stage `in_progress`, keep its checkpoint pending, and keep the header on that stage/checkpoint. Update the header `Updated` timestamp, but do not mark any stage complete, publish Jira, fill the Reuse Digest, or archive.
4. Write and read back the full session snapshot, proving the persisted fields exactly match the unchanged specialist result. For docs, re-read the referenced report and prove it remains readable and non-empty.
5. Do not append a subagent stage event here. The caller must already have terminated the exact invocation through `complete-subagent-handoff`; this operation owns artifact durability, not handoff history. Require `subagent-handoff-consistency-check(stage)` to be current before returning.
6. Return `result_recorded: <push|docs>`. A later approval consumes only this persisted candidate. A revision or rerun replaces it through this same operation. Persisting a candidate does not make the stage complete, fresh, resumable, or skippable.

### record-shared-gate-stage-result(JIRA-KEY, stage, result, source_ref)

Durably complete one `qa` or `tests` sibling stage without approving shared checkpoint C4. Call this immediately after the sibling's managed handoff completes, in both full and single-stage runs.

1. Require an existing session/activity pair, `stage` equal to `qa` or `tests`, that stage `in_progress`, C4 pending with no advancing decision, no open managed handoff, and the sibling no further than `complete`. Validate `result` through the same artifact-map and substantive-Markdown rules as `write-stage`; require the observed story-branch `source_ref`. Reject any other stage, approved/revision-selected C4, placeholder result, missing artifact mapping, or stale/conflicting sibling without mutation.
2. Set only the supplied stage row to `complete` with its registry owner, C4, source reference, and one completion timestamp. Replace only its fixed artifact subsection with the unchanged result. Re-run staleness and update the header to the furthest active or completed row, but keep the one C4 ledger row `status: pending`, `decision-reply: -`, and `milestone: -`. This is the explicit exception that permits either or both complete-and-fresh C4 siblings to coexist with a pending shared gate before the developer decides.
3. Write and read back the complete schema-8 snapshot, proving the stage, source reference, artifact, sibling state, and pending C4 row. Append exactly one `[Stage:<stage>] event=stage_complete checkpoint=C4 milestone=deferred transition=<completion-timestamp>` through `append-activity`, then run `consistency-check` with the shared-gate exception.
4. Return `shared_gate_stage_recorded: <qa|tests>`, `checkpoint_pending: C4`, and `shared_gate_ready: true|false`, where true requires both siblings complete and fresh. An exact retry against the same completed row/artifact/source reference repairs a missing matching event once and otherwise returns idempotently; changed evidence is `shared_gate_stage_result_conflict`.

This operation never accepts a checkpoint decision, appends `event=approved`, publishes Jira, or fills a milestone. A single-stage run stops after the successful return. A full run records the other sibling when needed and surfaces C4 only when `shared_gate_ready: true`.

### stage-regression-request(JIRA-KEY, regression_request)

Call immediately after Regression Runner returns in `request` mode and before relaying the checklist or ending the turn.

1. Require an existing session/activity pair, `regression` `in_progress`, C7 pending, and no open managed handoff. Require exactly one mapping with a non-empty single-line `round_id`, a substantive exact `checklist`, and `outcome: awaiting developer result`.
2. If one unresolved request is already persisted, compare its Round ID, Checklist bytes, and outcome with the supplied mapping before treating it as a conflict. An exact match is an idempotent retry: do not rewrite the session. Require exactly one matching `event=regression_request_staged round_id=<redacted-single-line-id>`; append it once when absent, accept it when present once, and return `regression_request_conflict` when duplicated or inconsistent. A different unresolved identity, checklist, or outcome is `regression_request_conflict` without mutation.
3. When no unresolved request exists, replace `### Regression` with `Request: awaiting developer result`, the exact Round ID and Checklist, and `Result: not recorded`. Keep regression in progress, C7 pending, and the header on regression/C7.
4. Write and read back the complete session, proving the identity, checklist bytes, outcome, stage, and checkpoint are unchanged. Append the non-filterable identity-bearing `event=regression_request_staged round_id=<redacted-single-line-id>` through `append-activity`, then verify exactly one matching event exists.
5. Return `regression_request_staged` with the exact persisted request. Both a first write and an exact recovered retry have the same return shape.

On the later developer response, Deva obtains the request only from `status` `resume_regression_result` and supplies its exact `round_id` to Regression Runner `record-result`. The runner's returned `regression_result` must carry that same identity. Reject a missing, reconstructed, translated, or mismatched identity as `regression_request_conflict`; never recover it from chat memory. A failed result may enter the bounded repair path while retaining the round evidence; a new request replaces `### Regression` only after that repair starts a new regression round.

### stage-regression-result(JIRA-KEY, regression_result)

Call immediately after Regression Runner returns in `record-result` mode and before presenting C7, advancing, or beginning repair.

1. Require an existing session/activity pair, `regression` `in_progress`, C7 pending, no open managed handoff, and one unresolved persisted request. Require exactly one result mapping whose non-empty single-line `round_id` exactly matches that request, whose `outcome` is `pass` or `fail`, and whose developer-supplied evidence is present. A missing or mismatched identity is `regression_request_conflict` without mutation.
2. Preserve the exact Round ID and Checklist, replace `Request: awaiting developer result` with `Request: result received`, and persist the unchanged result as `Result: pending C7 decision`, including its outcome and evidence. Keep regression in progress, C7 pending, and the header on regression/C7.
3. Write and read back the complete session, proving the request identity, checklist bytes, result bytes, and checkpoint are unchanged. Append exactly one non-filterable `event=regression_result_staged round_id=<redacted-single-line-id> outcome=pass|fail` through `append-activity`.
4. Return `regression_result_staged` with the exact persisted result. An identical retry is idempotent and repairs a missing matching event once; a changed result for that round is `regression_result_conflict`.

Only the persisted result may drive C7. A pass remains staged until the exact `regression passed` decision completes C7. A fail remains staged throughout the bounded repair path; starting the next request-mode round replaces it only after repair and republishing have begun a new regression round.

### stage-split-plan-candidate(JIRA-KEY, proposed_plan)

Call immediately after the Subbranch Extractor `plan` handoff completes and before surfacing C8a. Require `split` `in_progress`, C8a pending, no open handoff, and a substantive exact plan. Persist `C8a Candidate Plan`, its lowercase SHA-256, and `Authorization: pending C8a` under `### Draft PR Manifest`; write/read back byte-for-byte and return `split_plan_candidate_staged`. An identical retry is idempotent; a different unresolved candidate is `split_plan_candidate_conflict`.

### reject-split-plan-candidate(JIRA-KEY, revision_reply)

Call immediately after `approve-checkpoint` returns `revision_selected` for C8a and `record-revision` persists exact `revision_reply: revise split plan`. Require C8a pending, one staged C8a Candidate Plan, no open handoff, and the matching `revision_selected` activity event. Preserve the rejected candidate, hash, reply, and timestamp in Draft PR Manifest history, clear the current pending planning, and set `C8a Candidate Plan: pending replacement planning`. Append non-filterable `event=split_plan_candidate_rejected` keyed by the candidate hash and return `split_plan_candidate_rejected`. Only then may the planning handoff produce and stage one replacement candidate. An identical retry is idempotent; conflicting evidence is `split_plan_candidate_conflict`.

### record-split-prepared-manifest(JIRA-KEY, prepared_manifest, approved_plan_hash)

Call immediately after the successful initial-preparation handoff and before surfacing C8b. Require `split` `in_progress`, C8a approved and milestone-current, C8b pending, the exact persisted C8a Approved Plan hash matching `approved_plan_hash`, every initial side-effect row reconciled, and no open handoff. Validate `slice_count`, `delivery_mode`, full lowercase `feature_sha`, `story_sha`, and `story_tree`, `story_tree_equivalent: true`; complete one-slice ownership of the pinned feature-to-story diff; and each entry's `pr_ordinal`, `acceptance_criteria`, exact branch, `head_sha`, `head_tree`, `pr_base`, and `pr_base_sha`. Require the entry count to equal `slice_count` and ordinals to be contiguous. For `direct`, require exactly one entry whose branch is the canonical feature branch and whose PR base is `develop`; require `feature_head_sha` and `feature_tree`, with `feature_tree` equal to `story_tree`; reject `tip_sha`, review-subbranch dependencies, or review-branch entries. For `stacked`, require more than one entry, full lowercase `tip_sha` and `tip_tree`, PR1 based on feature, every dependent based on its immediate ordinal parent, no PR base equal to `develop`, and `tip_tree` equal to `story_tree`. Reject a missing or unsupported mode and any mode/count mismatch. Then replace only the `Prepared Manifest` body under `### Draft PR Manifest` with that exact payload plus `Authorization: pending C8b`, preserving the C8a Approved Plan. Write/read back byte-for-byte and return `split_prepared_manifest_recorded`. An identical retry is idempotent; a changed payload is `split_prepared_manifest_conflict`.

### record-integration-pr(JIRA-KEY, integration_pr)

Call after Integration Publisher's managed handoff completes and before surfacing or re-presenting C8d.

1. Require canonical `delivery_mode: stacked`, `integration` `in_progress`, C8d pending, review complete, C8c approved and milestone-current, one completed `integration-publisher` handoff in `publish` or `refresh` mode, and no open handoff.
2. Validate exactly one `integration_pr` mapping with `delivery_mode`, `parent_jira`, `story_branch`, `story_sha`, `feature_branch`, `feature_sha`, `target_branch`, `target_sha`, `evidence_hash`, `pr_id`, `pr_url`, `draft`, `publication`, `canonical_story_projection_verified`, `checks`, `approval`, and `merge`. Require stacked mode, target `develop`, full lowercase SHAs and evidence hash, non-empty stable PR identity, `draft: true`, publication `created|reconciled|refreshed`, projection verified, and all three human outcome fields pending C8d.
3. Reconcile the Integration Side-Effect Ledger. Require exactly one completed `pr-create` row for first publication. For refresh, require completed `integration-commit` and `branch-push` rows bound to the prior-story-to-corrected-story delta and resulting feature SHA, plus one completed `pr-update` row bound to the persisted PR identity and evidence hash. A missing, partial, ambiguous, or contradictory row returns `integration_publication_pending` without replacing the artifact.
4. Replace `### Integration PR` with the exact candidate plus `Acceptance: pending C8d`; keep integration in progress and C8d pending. Write/read back the whole schema-8 session and require exact field equality.
5. Return `integration_pr_recorded`. An identical retry is idempotent; a changed PR identity is `integration_pr_identity_conflict`.

### update-integration-side-effect(JIRA-KEY, entry, operation, idempotency_key, intended_target, status, returned_identifier, reconciled_at)

Use only for Integration Publisher's final feature-to-`develop` publication and C8d feedback-refresh mutations.

1. Require `entry` to equal the canonical feature branch from the accepted stacked manifest. Require `operation` to be `integration-commit`, `branch-push`, `pr-create`, or `pr-update`. Require `intended_target` to identify, respectively, the exact prior-story-to-corrected-story delta and feature base, the exact feature ref and commit, the exact head/base pair, or the persisted PR plus evidence hash.
2. Require `idempotency_key` to equal lowercase SHA-256 over `<entry>\n<operation>\n<intended_target>` using exact UTF-8 values.
3. Require `status` to be `intended`, `partial`, or `complete`. Find the row by idempotency key under `### Integration Side-Effect Ledger`; accept a new row only as `intended` and require exact identity on every update.
4. Enforce monotonic `intended → partial → complete`, allowing `intended → complete`; identical retries are no-ops. Never overwrite a different returned identifier or leave `complete`.
5. For `complete`, require the observed identifier, pushed ref, or PR ID/URL appropriate to the operation plus the reconciliation timestamp. Replace only that ledger row and header timestamp, preserving all stage/checkpoint/artifact bytes.
6. Return the persisted row. Do not append stage activity or authorize C8d.

### approve-checkpoint(JIRA-KEY, checkpoint, stage_updates, note, decision_reply, authorization_artifact?)

Deva calls this on the turn after the developer explicitly resolves a checkpoint and before any narration or next pipeline action. This is the owning checkpoint operation: local state becomes durable first, then the Jira milestone is published. `decision_reply` must be the caller's entire current developer message, unchanged. `stage_updates` is an ordered list of zero or more `{ stage, result, source_ref }` entries. It is empty for the intermediate `C8a` sub-gate and for the first, authorization-only C8b call; it normally has one entry (`C0b` records `architecture`, C1a `intake`, C1b `refine`, C8c `review`, and C8d `integration`) and has both `qa` and `tests` for shared checkpoint C4. Accept `authorization_artifact` only for C8a or C8b with empty `stage_updates` and `split` `in_progress`.

1. Run `subagent-handoff-consistency-check` for every stage represented by this gate and block on any unpaired handoff. Then validate the decision before changing state. Load the active checkpoint's `advance` and `revise` lists from `pipeline.checkpoint_decisions`. Accept advancement only when `decision_reply.Trim()` case-sensitively equals one registered `advance` reply and contains no additional text. If it exactly equals a registered `revise` reply, return `revision_selected` with that phrase and no approval mutation or Jira publication; the caller must immediately invoke `record-revision` before running the correction path. Reject missing, inferred, extracted, translated, model-generated, subagent-generated, same-turn, generic (`yes`, `no`, `continue`, `go ahead`, `approved`), checkpoint-ID (`approve Cx`), or unknown values as `invalid_decision` without mutation or publication. Require `checkpoint` to be the active checkpoint ledger gate and every supplied stage to exist; an already-approved gate is not a new decision and must use recovery. Require C0b to update only `architecture`, C1a only `intake`, C1b only `refine`, C4 exactly the already-complete `qa` and `tests` with `result: persisted-shared-gate-result`, C6 exactly one completed `push` with `result: persisted-stage-result`, C8c only `review`, C8d only `integration`, C9 exactly one `reextract` update with `result: persisted-reextract-result`, and C10 exactly one completed `docs` update with `result: persisted-stage-result`; one checkpoint cannot authorize another stage.
2. Redact `note` before persistence. Append `decision-reply: <exact registered advance reply>` to the ledger note. Never emit a new `approval-token:` field or persist free-form claims such as `autonomous run authorized` as decision evidence.
3. **Persist locally first.** Apply `write-stage` completion semantics to all `stage_updates` entries in registry step order and flush one final schema-8 snapshot in which every supplied row, the header, ledger, and artifacts agree. This approval mutation updates the current checkpoint's existing ledger row and must not add or rewrite the next stage's checkpoint; the explicit C8a special case may also update the pre-existing C8b sibling row. Starting integration after stacked C8c is a later `mark-in-progress(integration)` operation. For a shared checkpoint, persist whichever sibling stages were supplied; when any sibling remains incomplete, keep the ledger gate pending, append `event=stage_complete checkpoint=<Cx> milestone=deferred` for each supplied stage, and do not publish approval or Jira evidence. Once all sibling stages are complete and fresh, approve and publish the shared gate exactly once.

After the snapshot write, re-read `session.md` from disk and parse the Checkpoint Ledger table again. Before appending `event=approved decision="<exact registered advance reply>"` or reading/writing Jira, require `status: approved`, the exact `decision-reply`, `milestone: pending`, and the approval timestamp; for C4 also require both `qa` and `tests` rows to persist as complete-and-fresh. If the row is missing, still pending, malformed, duplicated, or disagrees with the completed stage rows, return `checkpoint_ledger_write_failed: <checkpoint>` and stop without approval activity or Jira publication. Never treat a successful stage/artifact write as proof that the ledger table write also succeeded.

Special cases:

- **C5 acceptance-outcome decision.** Before mutating C5, re-read the fixed `ac_status` artifact under `### Acceptance Criteria` and parse every criterion's status. Require a substantive status table containing only `Met`, `Partially Met`, `Not Met`, or `Deviated`; otherwise return `artifact_missing: ac_status` without mutation or publication. When every criterion is `Met`, accept `publish story` and reject `defer acceptance gaps` as `invalid_decision`. When any criterion is `Partially Met`, `Not Met`, or `Deviated`, accept `defer acceptance gaps` and reject `publish story` as `invalid_decision`. The registered revise reply `fix acceptance gaps` remains valid for either outcome and follows the normal revision path. Never derive this outcome from the checkpoint prompt, ledger note, caller claim, or conversational memory.
- **C8a intermediate approval.** Require `stage-split-plan-candidate` evidence and byte-for-byte equality between `authorization_artifact` and the persisted C8a Candidate Plan. With no completed stage, update C8a's table row to `status: approved` with its exact decision reply and approval timestamp, keep C8b's row `pending`, keep `split` `in_progress`, advance the header to `Active Checkpoint: C8b`, and promote the candidate in `### Draft PR Manifest` to `C8a Approved Plan:`, preserving its hash, with `Prepared Manifest: pending initial extraction` and `Authorization: C8a approved`. Update `Updated` and read back the exact plan/hash before milestone publication. Any later initial-preparation blocker keeps C8a approved and milestone-current, keep C8b's row `pending`, keep `split` in progress; recovery uses that exact approved plan or the registered split-plan revision path and never reopens C8a implicitly.
- **C1a/C1b prior-art evidence.** Resolve `pipeline.reuse_index_file` from `.github/config/guardrails.yaml` as `<reuse_index_file>`. Before completing `intake`, require `### Understanding / Scope / Agreements` to contain a non-placeholder `Prior-Art Search Evidence` block with explicit outcomes for the direct configured `<reuse_index_file>` read and direct `.github/artifacts/sessions/` enumeration fallback, plus federated-source outcomes, candidate sources, and the developer's reuse decision (`approved`, `trimmed`, `rejected`, or `none found`). Revalidate the same evidence before completing `refine`; its artifact replacement may add verification but must preserve the approved source set and decision. On missing, incomplete, broadened, or erased evidence, return `artifact_missing: prior_art_search_evidence`; keep C1a or C1b pending and do not publish its Jira milestone or advance.
- **C4 shared-gate acceptance.** Require both `qa` and `tests` to be complete and fresh from `record-shared-gate-stage-result`, with substantive fixed artifacts and exactly one matching `event=stage_complete` per sibling transition. Accept only `result: persisted-shared-gate-result` for both updates; revalidate the persisted artifacts and promote only the C4 ledger row to approved. Do not rewrite either artifact, stage row, source reference, completion timestamp, or sibling event.
- **C6 pushed-ref acceptance.** Require the earlier `record-stage-result(push, ...)` operation to have persisted a valid `Pushed Ref` candidate. Pass `result: persisted-stage-result` into `write-stage`; do not accept a checkpoint note, Branch Info text, Git reconstruction, or conversational memory as the artifact. `write-stage` revalidates the candidate before promotion. Any `artifact_missing: pushed_ref` result leaves C6 pending and blocks Jira milestone publication and regression.
- **C8b manifest authorization.** On the first C8b call with no completed stage, require `record-split-prepared-manifest` evidence and byte-for-byte equality between `authorization_artifact` and its Prepared Manifest. Preserve the C8a Approved Plan, mark that manifest `Authorization: C8b approved`, mark C8b `approved`, keep `split` `in_progress`, keep the header on `split`/C8b, and update `Updated`. This one snapshot durably authorizes the extractor to open only the persisted head/base pairs. Never accept a changed manifest under the same C8b approval.
- **C8b split finalization.** This is not another checkpoint decision. After publication reconciles, call `finalize-approved-stage` with the completed `split` update; it preserves the original C8b approval and milestone evidence and appends only `event=stage_complete checkpoint=C8b`.
- **C8c review completion.** Read `delivery_mode` from the canonical manifest. For `direct`, require Stage 8 feature/story equivalence, required projection proof, and the feature-to-`develop` PR's current checks, approval, merge-commit method, and merged commit; set `### Integration PR` to `not applicable for direct delivery`. For `stacked`, require every incremental PR disposition, root-to-tip review evidence, each tip-to-root merge's current source/target/check/approval identities and merge commit, PR1/story equality, and PR1-to-feature merge. Do not require or accept feature-to-`develop` evidence in Human Review. Keep Integration PR pending stacked publication. C8c approval completes review; direct mode may proceed to docs, while stacked mode must start integration before C8d.
- **C8d stacked integration completion.** Require the persisted Integration PR candidate and live PR identity to agree. Require current source and target SHAs, required checks bound to current feature SHA, current approval, no unresolved review blocker, merge method `merge-commit`, merged commit, and target containment. Replace Integration PR pending fields with accepted evidence, complete `integration`, and approve C8d. A direct manifest or missing candidate returns `artifact_missing: integration_result` and keeps C8d pending.
- **C9 revised-delivery acceptance.** Require `record-reextract-result` to have persisted exactly one `status: completed-candidate`, and accept only `result: persisted-reextract-result`; never consume a handoff result or chat reconstruction directly at the checkpoint. Revalidate that candidate's classification as `ownership-preserving` or `plan-changing`, full revised manifest, and current validation evidence. Direct mode requires additive prior-story-to-current-story projection, `canonical_story_projection_verified: true`, and refreshed feature-to-`develop` PR evidence; it does not require live feature tree equality after an accepted `develop` synchronization. A delivery-mode or slice-count change is accepted only through `restart-review-preparation` and fresh C8a/C8b authorization. Stacked mode requires `story_tree_equivalent: true`; ownership-preserving work requires additive commits and propagation through every dependent, while same-count plan-changing work requires a retained unaffected prefix plus replacement and superseded references for the affected suffix. Replace the fixed `### Subbranch Manifest` body with the revised manifest and apply staleness rule 3 in full, including any completed stacked `integration` result and `docs` result. Replace `### Reextract Result` with the persisted round's evidence. Re-baseline `split` as `complete` at the accepted manifest's observed source while preserving its C8a/C8b decision evidence, then restore `review` to `in_progress` with C8c pending. Never leave an outdated manifest as the documentation input or proceed directly to docs.
- **C10 report acceptance.** Require the earlier `record-stage-result` operation to have persisted a valid `Post-Action Document` candidate. Pass `result: persisted-stage-result` into `write-stage`; do not accept a caller-supplied reconstruction of the report path, readiness, follow-up count, or summary. `write-stage` revalidates the persisted payload and report before promotion. Any `artifact_missing: post_action_doc` result leaves C10 pending and blocks Jira milestone publication and archival.

4. Build the stable idempotency marker `Milestone-ID: <JIRA-KEY>:<checkpoint>`. Call `getJiraComments(JIRA-KEY)` and count comments containing that exact marker. When there is one `milestone_duplicate: <checkpoint>` and blocks; never post or delete automatically. If zero exists, continue directly to step 5 without appending milestone activity or promoting the ledger `milestone` field. If exactly one exists, do not post again: count matching canonical activity lines by component and event, `[Checkpoint:<checkpoint>] event=milestone_posted`. More than one is `milestone_activity_duplicate: <checkpoint>` and blocks. If none exists, append it with `outcome=already_present`; then re-read the log and require exactly one matching line. In one session write, promote only the current checkpoint table row from `milestone: pending` to `milestone: posted`, preserving its status, decision reply, and approval timestamp plus every unrelated byte. Re-read the table and require exactly one matching row with `milestone: posted`; otherwise return `checkpoint_ledger_write_failed: <checkpoint>`. Run `milestone-consistency-check(checkpoint)` and return `milestone: already-posted` only when it returns `milestones: current`.
5. Otherwise call `createJiraComment()` through the caller's Jira MCP tools using this compact format:

```text
Pipeline milestone approved
Checkpoint: <checkpoint>
Stage: <active stage, or qa + tests for C4>
Outcome: <redacted note>
Milestone-ID: <JIRA-KEY>:<checkpoint>
```

6. On Jira write success, call `getJiraComments(JIRA-KEY)` again and require exactly one comment containing the marker. Zero returns `milestone_verification_failed: <checkpoint>`; more than one returns `milestone_duplicate: <checkpoint>`. Append the canonical `[Checkpoint:<checkpoint>] event=milestone_posted` line at INFO via `append-activity`, then re-read the log and require exactly one matching line. Zero returns `milestone_activity_missing`; more than one returns `milestone_activity_duplicate: <checkpoint>`. In one session write, promote only the current checkpoint table row from `milestone: pending` to `milestone: posted`, preserving its status, decision reply, and approval timestamp plus every unrelated byte. Re-read the table and require exactly one matching row with `milestone: posted`; otherwise return `checkpoint_ledger_write_failed: <checkpoint>`. Run `milestone-consistency-check(checkpoint)` and only after it returns `milestones: current` may this operation return `milestone: posted`. If the Jira write succeeds but verification, activity append, or ledger promotion fails, a retry detects the marker in Jira and must not duplicate the comment.
7. On Jira read or write failure, append `event=milestone_failed checkpoint=<checkpoint> reason=<short-redacted-reason>` at ERROR, return `milestone: blocked`, and stop before the next pipeline action. The local approval remains authoritative; the caller must invoke `recover-milestone(JIRA-KEY, checkpoint)`, which checks Jira first and either confirms the existing marker or posts the missing comment.

### recover-milestone(JIRA-KEY, checkpoint)

Use only when local state already records the checkpoint as approved but Jira, activity, or the ledger's milestone field is missing. This is publication recovery, not a new developer decision: it accepts no `decision_reply`, performs no stage update, and may change only the current checkpoint row's `milestone` from `pending` to `posted` after both external copies verify. It never changes checkpoint status, decision reply, approval timestamp, artifacts, or approval activity.

1. Require exactly one Checkpoint Ledger table data row for `checkpoint`, with `status: approved` and either a registered persisted `decision-reply` or a legacy approval token preserved from a normalized older session. Validate that evidence against `pipeline.checkpoint_decisions`; reject a pending gate, missing evidence, or conflicting decision as `invalid_recovery_evidence`.
2. Run `consistency-check` before publication recovery. For C8b, additionally require `split` to remain `in_progress` or `complete` and require the fixed Draft PR Manifest to contain the authorized manifest; never reconstruct it.
3. Execute the Jira marker, activity milestone, and ledger-field reconciliation defined in approve-checkpoint steps 4-7, deriving the redacted milestone outcome from the persisted decision evidence. Do not append `event=approved` again. Promote `milestone: pending` to `milestone: posted` only after exactly one Jira marker and one milestone activity line verify.
4. Run `milestone-consistency-check(checkpoint)`. Return `milestone: posted` or `milestone: already-posted` only after it returns `milestones: current`; otherwise return its blocker.

### finalize-approved-stage(JIRA-KEY, checkpoint, stage_update)

Use only for a stage whose checkpoint authorized external work before the stage itself could complete. The sole supported case is C8b finalizing `split` after all authorized draft-PR operations are reconciled. This is continuation of prior authority, not another checkpoint decision, so it accepts no `decision_reply` and publishes no Jira milestone.

1. Require `checkpoint: C8b`, exactly one completed `split` update, `split` `in_progress`, C8b approved with persisted `decision-reply: open draft pull requests`, an authorized Draft PR Manifest, and `milestone-consistency-check(C8b)` returning current.
2. Require every authorized PR operation in the side-effect ledger to be `complete` and require the final substantive manifest to match the authorized head/base set. Reject missing, partial, broadened, or retargeted work.
3. Apply `write-stage` completion semantics to `split` while preserving the original C8b ledger note, decision evidence, approval timestamp, Jira marker, and milestone-posted event. Append exactly one `[Stage:split] event=stage_complete checkpoint=C8b`; never append another C8b `event=approved` or milestone event.
4. Run both consistency checks and return `stage_finalized: split` only when the session, activity log, and milestone evidence are current.

### milestone-consistency-check(checkpoint | all-approved)

Use this read-only operation after `approve-checkpoint` publication, from `check-preconditions`, on resume/next-stage selection, and before archive. Derive checkpoint membership and order from the registry; never use a hard-coded checkpoint list.

1. For each selected ledger gate marked `approved`, require its table row to carry `milestone: posted`, valid registered semantic decision evidence (or a persisted legacy approval token), exactly one canonical `[Checkpoint:<checkpoint>] event=approved decision="<registered advance reply>"` activity line whose decision equals the ledger reply, exactly one Jira comment containing `Milestone-ID: <JIRA-KEY>:<checkpoint>`, and exactly one canonical `[Checkpoint:<checkpoint>] event=milestone_posted` activity line. A row that remains `milestone: pending` after the external evidence exists returns `checkpoint_ledger_write_failed: <checkpoint>`; it is not current. C8b split finalization must use `event=stage_complete` and must not add a second C8b approval or milestone event.
2. For a selected gate that is `pending`, require no Jira marker and no milestone-posted event unless the gate has a durable registered revision selection, which still publishes no milestone. A reactive checkpoint that never ran, such as C9 on the normal path, remains pending and requires no milestone-posted event.
3. A missing Jira marker or milestone-posted line returns `checkpoint_milestone_pending: <checkpoint>`. A duplicate Jira marker, approval event, or milestone-posted event returns `milestone_duplicate: <checkpoint>` or `milestone_activity_duplicate: <checkpoint>` and blocks; never delete or rewrite evidence automatically. A missing or duplicate approval event returns `checkpoint_activity_corrupt: <checkpoint>`.
4. Return `milestones: current` only when every selected checkpoint satisfies the applicable rule. `approve-checkpoint` may return `milestone: posted` or `milestone: already-posted` only after this operation returns current for that checkpoint. Archive requires `all-approved` to return current before any filesystem mutation.

### record-revision(JIRA-KEY, checkpoint, revision_reply, note)

Call immediately after `approve-checkpoint` returns `revision_selected`, before any correction, stop, feedback collection, or reactive-stage work. This operation keeps the checkpoint pending while durably recording the selected registered revision path.

1. Require `checkpoint` to be the active pending ledger gate. Load its `revise` choices from `pipeline.checkpoint_decisions` and require the entire trimmed `revision_reply` to case-sensitively equal one registered choice. Reject inferred, translated, assistant-authored, subagent-authored, generic, or longer text.
2. For a new selection, keep that checkpoint's table row `status: pending`, persist the exact registered revise reply in its decision field as revision evidence, keep `milestone: -`, and update its timestamp. If the row already contains that exact pending revision evidence, treat the call as a retry: preserve its existing valid timestamp as the transition id and do not rewrite the snapshot. Never mark the gate approved and never publish a Jira milestone.
3. For a new selection, update the session header timestamp without changing any stage row or artifact, then write and read back the full schema-8 snapshot, preserving every unrelated byte and proving the gate remains pending.
4. Append `event=rejected decision="<exact registered revise reply>"`, then `event=revision_selected choice=<space-free-normalized-reply>`, for `[Checkpoint:<checkpoint>]` through `append-activity`. Use the same session update timestamp as both events' transition id. Read back the log and require exactly one matching rejection and one matching revision-selection event for that transition before returning. An identical retry with the same ledger evidence and events appends only whichever matching event is absent and is otherwise an idempotent success; a duplicate returns `checkpoint_activity_corrupt: <checkpoint>`. A different revision reply for the same unresolved selection requires the caller to return to the checkpoint and obtain a new exact developer message.
5. For C8c with `review changes requested`, return `resume_action: resume_review_changes`. This evidence is the only valid reactive trigger for `reextract`; C9 approval clears it when returning revised delivery to C8c.
6. For C8d with `integration changes requested`, return `resume_action: resume_integration_changes`. For `restart review preparation from integration`, return `resume_action: resume_integration_review_restart`. Both keep C8d pending and publish no milestone.

### stage-operation-authorization(JIRA-KEY, stage, action, payload, choices)

Persist an exact non-checkpoint operation proposal before a hard turn when later developer consent will authorize or decline an external mutation. This operation supports only `architecture` / `refresh` with choices `continue | skip`, and `branch` / `create-and-push` with choices `create and push branches | change branch plan`.

1. Normally require the named stage to be `in_progress`, its entry checkpoint to be approved, no open managed handoff, and no unresolved operation authorization for that action/stage. For `branch` / `create-and-push` only, permit `branch` to be `not_started`: run the dependency/checkpoint and handoff checks from `check-preconditions(branch)` but defer its standalone-unsafe mutation confirmation to this authorization flow. Require `refine` complete and fresh with current C1b decision and milestone evidence. In the same proposal-staging transition, set `branch` to `in_progress`, set the header to `branch` at C2, keep C2 pending, and append the canonical branch `event=enter`; no Git mutation is authorized yet. A blocked dependency or existing branch authorization returns its normal blocker without changing stage state.
2. Persist the exact lowercase SHA-256, choices, `status: awaiting decision`, and timestamp under the owning fixed artifact (`### Architecture Context` or `### Branch Info`). The exact payload is recovery evidence; a summary or hash alone is insufficient. For the branch special case, write the stage/header/ledger transition and proposal as one complete schema snapshot before appending the paired enter and authorization-staged events.
3. Write and read back the full snapshot, proving the payload bytes, hash, choices, stage state, and pending status are unchanged. Append non-filterable `event=operation_authorization_staged stage=<stage> action=<action> payload_hash=<hash>`.
4. Return `operation_authorization_staged` with the exact payload and choices. An identical retry is idempotent; a different unresolved proposal returns `operation_authorization_conflict`.

### record-operation-authorization(JIRA-KEY, stage, action, decision_reply)

Consume one staged non-checkpoint proposal on a later top-level developer turn. Never accept caller-supplied payload reconstruction.

1. Require one matching `awaiting decision` proposal and require the entire trimmed `decision_reply` to equal one of its persisted choices. Reject inferred, translated, synthetic, assistant-authored, subagent-authored, same-turn, or longer text.
2. On `continue` or `create and push branches`, set `status: authorized`; on `skip` or `change branch plan`, set `status: declined`. Preserve the exact payload, hash, choices, reply, and timestamp in authorization history.
3. Write/read back the snapshot and append non-filterable `event=operation_authorization_recorded stage=<stage> action=<action> decision=<normalized-reply> payload_hash=<hash>`.
4. Return the persisted payload and `operation_authorized` or `operation_declined`. Only `operation_authorized` permits the named mutation. A matching retry is idempotent; conflicting evidence returns `operation_authorization_conflict`.

When a later approved stage write promotes `Architecture Context` or `Branch Info`, preserve its complete operation-authorization history alongside the outcome. Never overwrite the evidence that authorized an external mutation.

### stage-agreement-revision(JIRA-KEY, source_stage, source, current_agreement, proposed_agreement, reason, affected, stale_from)

Use only for a `scope_change_required` result after `intake` is already approved. Require no other pending agreement revision, require the milestone to be current, require `source_stage` to be in progress, and require `stale_from` to be `branch` or `implement`. Architecture-changing proposals require refreshed architecture evidence before staging.

Persist one new pending revision with a stable ordinal id, the exact prior and proposed agreements, source, reason, affected Acceptance Criteria (AC)/ownership, stale-from stage, and timestamp. Keep every stage and checkpoint unchanged, preserve the original C1b approval and milestone, append `event=agreement_revision_requested revision_id=<id> source_stage=<stage>`, and return the revision id plus the exact choices from `pipeline.agreement_revision_decisions`. An identical retry returns the same pending revision; a different proposal while one is pending is `agreement_revision_conflict`.

### stage-jira-enrichment-candidate(JIRA-KEY, refined_brief)

Call immediately after the normal Story Analyst `refine` handoff completes and before surfacing the Jira-enrichment decision. Require `refine` `in_progress`, C1a and its milestone current, a substantive exact brief, and no open handoff. Persist the exact brief and lowercase SHA-256 in the next ordinal `Jira Enrichment Authorization` entry with `status: awaiting decision`; write/read back byte-for-byte and return `jira_enrichment_candidate_staged`. An identical retry is idempotent; a different unresolved candidate is `jira_enrichment_conflict`.

### stage-refinement-choice-candidate(JIRA-KEY, refinement_assessment)

Use only after the normal Story Analyst `refine` handoff returns a score below the configured threshold and before an implementation-ready brief or Jira-enrichment candidate exists. Require `refine` `in_progress`, C1a and its milestone current, no open handoff, and one substantive exact assessment containing the score, threshold, criterion gaps, and proposed improvements. Persist that payload and its lowercase SHA-256 in the next ordinal `Refinement Choice` history entry under `### Understanding / Scope / Agreements`, with the exact choices from `pipeline.refinement_decisions`, `status: awaiting decision`, and a timestamp. Write/read back the payload bytes, hash, choices, and status before returning. An identical retry is idempotent; a different unresolved assessment is `refinement_choice_conflict`.

### record-refinement-decision(JIRA-KEY, decision_reply)

Consume only the persisted `awaiting decision` refinement assessment on a later top-level developer turn. Require the entire trimmed `decision_reply` to equal one registered `pipeline.refinement_decisions` value; never accept a caller-supplied reconstruction, synonym, synthetic message, or same-turn reply. Preserve the exact assessment, hash, choices, reply, and timestamp in history and append non-filterable `event=refinement_decision_recorded decision=<normalized-reply> assessment_hash=<hash>`.

On `draft refinement improvements`, set `status: draft authorized` and return `resume_refine_draft` with the exact assessment. On `proceed with refinement gaps`, set `status: gaps accepted` and return `resume_refine_with_gaps` with the exact assessment; this records the remaining gaps but is not C1b approval. On `show refinement example`, set `status: example requested` and return `resume_refine_example` with the exact assessment and its persisted `assessment_hash`. Identical retries are idempotent and conflicting evidence returns `refinement_choice_conflict`.

### restore-refinement-choice(JIRA-KEY, assessment_hash)

Call only after Story Analyst returns the requested refinement example. Require `refine` `in_progress`, C1a and its milestone current, no open handoff, and exactly one latest `Refinement Choice` entry with `status: example requested` whose persisted lowercase SHA-256 equals `assessment_hash`. Never accept a caller-supplied assessment, choices, or reconstructed hash.

On a new restoration, preserve the exact assessment, hash, registered choices, prior decision reply, and history timestamp; change only its current `status` to `awaiting decision` and update the session header timestamp. Write and read back the complete schema-8 snapshot, proving those fields and the restored status are unchanged before returning `refinement_choice_restored` with the exact persisted assessment and choices. Do not create a brief, approve a checkpoint, permit Jira enrichment, or append another refinement-decision event. A retry against the same already-restored entry returns the same result without mutation; a missing entry, different hash, or incompatible status returns `refinement_choice_conflict`.

### record-jira-enrichment-decision(JIRA-KEY, decision_reply)

Use only while normal `refine` is `in_progress`, after `stage-jira-enrichment-candidate` persisted the exact implementation-ready brief and before any Jira mutation. Require C1a and its milestone current, no open handoff, one `awaiting decision` candidate, and the entire trimmed `decision_reply` to equal one value in `pipeline.jira_enrichment_decisions`. Consume the persisted brief and hash; never accept or reconstruct them from caller memory.

Persist an ordered `Jira Enrichment Authorization` history inside the canonical `### Understanding / Scope / Agreements` artifact; each entry carries a stable ordinal, status, exact decision reply, the exact authorized refined brief, its hash, and timestamp. The exact brief is required recovery payload, not a reconstruction target; read-back must reproduce its bytes and hash. On `enrich jira`, set the current entry `status: authorized`, append non-filterable `event=jira_enrichment_authorized`, and return `jira_enrichment_authorized` with the hash. On `do not enrich jira`, set it `status: declined`, append non-filterable `event=jira_enrichment_declined`, return `refine_revision_or_stop`, and do not permit C1b because normal refinement's required Jira product is absent. This is not checkpoint approval and publishes no Jira milestone. An identical retry is idempotent. A different reply or brief when an entry is `authorized` is `jira_enrichment_conflict`; after a `declined` entry, a later exact decision may append the next ordinal entry while preserving the decline history.

### finalize-jira-enrichment(JIRA-KEY, handoff_id, jira_source_ref, refined_brief)

Require a completed ordinary `refine`/`story-analyst`/`enrich-jira` handoff, the same exact brief hash as the durable authorization, and concrete confirmation that the original Jira description was preserved and the enrichment description/comment were observed. Record `status: complete`, the handoff id, Jira source reference, and completion timestamp in the same authorization block. Append non-filterable `event=jira_enrichment_completed` with those identities. Return `jira_enrichment_complete` only after read-back verifies the block and event. Missing or conflicting evidence leaves the authorization pending and blocks C1b.

### resolve-agreement-revision(JIRA-KEY, revision_id, decision_reply)

Require the entire trimmed reply to match one registered `pipeline.agreement_revision_decisions` choice. On `keep current agreement`, mark the revision rejected, preserve canonical understanding and all stage/checkpoint evidence, append `event=agreement_revision_rejected revision_id=<id>`, and return `resume_implementation`.

On `confirm revised agreement`, preserve the prior agreement in history, replace canonical `### Understanding / Scope / Agreements` with the staged proposal, mark the revision `accepted_jira_pending`, mark `stale_from` and every downstream in-progress stage stale, keep the original C1b ledger and milestone unchanged, append `event=agreement_revision_accepted revision_id=<id> stale_from=<stage>`, and return `jira_enrichment_required`. A conflicting retry is `agreement_revision_corrupt`; an identical retry is idempotent. Do not select another stage while Jira publication is pending.

### finalize-agreement-revision(JIRA-KEY, revision_id, jira_source_ref)

Require an accepted revision awaiting Jira publication and concrete confirmation that Story Analyst enriched Jira with the accepted agreement. Publish or reconcile one revision-specific Jira audit marker, record the observed Jira source reference, mark the revision complete, and append `event=agreement_revision_finalized revision_id=<id> jira_source_ref=<ref>`. Only then return the earliest stale stage for rerun. Missing Jira evidence leaves the revision pending and blocks all normal stage selection. This revision milestone is separate from and never replaces or duplicates the original C1b checkpoint milestone.

### stage-split-plan-revision(JIRA-KEY, current_plan, proposed_plan, reason, trigger)

Use for either `trigger: initial-extraction-failure` when a failed C8a-authorized extraction needs a changed plan, or `trigger: c8b-manifest-revision` after the developer selects `revise draft pull requests` for a successfully prepared manifest. Require `split` to remain `in_progress`, C8a and its milestone to be current, C8b pending, no open handoff, and no existing split-plan revision decision. For the C8b trigger, additionally require C8b's pending ledger row to carry exact revision evidence `decision-reply: revise draft pull requests` plus its one `revision_selected` activity event. Reconcile uncertain external outcomes to `complete` or a confirmed still-unperformed `intended` state, but do not mark anything `abandoned` or `superseded` before the developer selects the revision. Capture the rows the proposed plan would retain, abandon, or supersede as the proposed disposition plan.

Persist the current approved/prepared plan, trigger, proposed replacement, reason, proposed side-effect dispositions, and timestamp as one pending revision under `### Draft PR Manifest` with `Authorization: pending split-plan revision`. Append the non-filterable `event=split_plan_revision_requested revision_id=<stable-id>` activity event and return the exact choices from `pipeline.split_plan_revision_decisions`. Do not change C8a, C8b, the split row, side-effect rows, Jira milestones, branches, or issues. An identical retry returns the same revision; a different proposal while one is pending is `split_plan_revision_conflict`.

### resolve-split-plan-revision(JIRA-KEY, revision_id, decision_reply)

Require the entire trimmed reply to equal one registered split-plan revision choice. On `keep approved split plan`, mark the candidate rejected and restore its exact prior artifact: for `initial-extraction-failure`, restore the C8a Approved Plan with `Prepared Manifest: pending initial extraction` and return `resume_initial`; for `c8b-manifest-revision`, restore the prior Prepared Manifest with `Authorization: pending C8b` and return `resume_split_C8b_review`. Preserve the rejected revision in history and append `event=split_plan_revision_rejected`; never replace the canonical artifact with `not authorized`. On `confirm revised split plan`, mark the candidate `accepted_disposition_pending`, preserve its full decision history and proposed disposition plan, append `event=split_plan_revision_accepted`, and return `reconcile_split_plan_side_effects`. This decision authorizes only the recorded `abandoned`/`superseded` transitions; it does not yet authorize extraction, approve C8b, or authorize a PR. Never reuse the original C8a approval alone as authority for changed scope.

### finalize-split-plan-revision(JIRA-KEY, revision_id)

Require the revision to be `accepted_disposition_pending`. Verify every row named by its disposition plan now carries exactly the authorized terminal state and preserved external identifier, no relevant row remains uncertain, and no unlisted row changed terminal disposition. Mark the revision `complete`, append non-filterable `event=split_plan_revision_finalized revision_id=<id>`, and return `revised_plan_authorized` with the exact accepted plan. Only this result permits one new `initial` extraction attempt. An identical retry is idempotent; a mismatch is `split_plan_revision_disposition_conflict`.

### stage-reextract-plan(JIRA-KEY, target_branch, classification, affected_entries, extraction_spec_hash)

Call from Subbranch Extractor after the C8c `review changes requested` trigger and fresh story-branch repair evidence are current, but before any review-branch mutation.

1. Require `reextract` `in_progress`, C8c pending with exact `decision-reply: review changes requested`, the canonical Subbranch Manifest, no unresolved staged reextract plan, and no open subagent handoff. Require `classification` to be `ownership-preserving` or `plan-changing` and `extraction_spec_hash` to match the canonical manifest. Read and validate its `delivery_mode` and `slice_count`. This controller-owned planning write occurs before `begin-subagent-handoff`; only `reextract_plan_staged` permits Deva to start the extractor handoff.
2. If the corrected diff requires a different `delivery_mode` or `slice_count`, persist `status: review-delivery-restart-required`, the observed old/new mode and count, reason, specification hash, and timestamp without branch or PR mutation. Return `review_delivery_restart_required` with the registered C9 choice `restart review preparation`; do not stage a re-extraction plan.
3. For `direct`, require `classification: ownership-preserving`, `target_branch` equal to the canonical feature branch, and `affected_entries` to contain exactly that one manifest entry. For `stacked`, require `affected_entries` to begin at `target_branch` and contain exactly every dependent in canonical ordinal order. Stacked `ownership-preserving` requires unchanged scope, Acceptance Criteria mapping, paths/files, extraction mechanism, dependency, slice count, and branch relationship. Stacked `plan-changing` persists the exact retained prefix plus replacement/supersede dispositions for every affected branch.
4. Persist the target, classification, exact affected entries, retained prefix/dispositions when applicable, specification hash, and timestamp under `### Reextract Result` with `status: staged`. Write/read back byte-for-byte while keeping the stage in progress and C9 pending.
5. Return `reextract_plan_staged` and the exact plan. An identical retry is idempotent; a changed unresolved plan is `reextract_plan_conflict`.

### record-reextract-result(JIRA-KEY, handoff_id, result)

Call immediately after the Subbranch Extractor `reextract` handoff completes and before presenting C9 or ending the turn.

1. Require `reextract` `in_progress`, C8c pending with `decision-reply: review changes requested`, C9 pending, one `status: staged` re-extraction plan, no open handoff, and exactly one completed `subbranch-extractor` / `reextract` handoff matching `handoff_id` with `outcome: ok`. Reject a result reconstructed from chat or any handoff other than that plan's single authorized execution.
2. Validate the unchanged result against the staged target, classification, affected entries, retained-prefix/disposition plan, extraction-specification hash, and current side-effect ledger. Require classification `ownership-preserving` or `plan-changing`, the full revised manifest, all affected branch/PR identities, current focused and cumulative validation evidence, and the mode-specific delivery proof required by C9. A blocker, placeholder, partial manifest, stale proof, or mismatch returns `artifact_missing: reextract_result` without mutation.
3. Replace the staged artifact with `status: completed-candidate`, `round_id: <handoff_id>`, the immutable staged plan, and the unchanged validated result. Keep `reextract` in progress and C9 pending. Write/read back the complete snapshot and append exactly one `[Stage:reextract] event=result_recorded round_id=<redacted-handoff-id>` activity line.
4. Return `reextract_result_recorded` and the exact persisted candidate. An exact retry is idempotent; changed evidence for the same round or a second completed candidate is `reextract_result_conflict`.

This operation makes the candidate durable but does not complete `reextract`, approve C9, replace the canonical Subbranch Manifest, or publish a milestone.

### replace-reextract-round(JIRA-KEY, revision_id, prior_round_id)

Call after `approve-checkpoint(C9, decision_reply: revise delivery)` returns `revision_selected`, and `record-revision(C9, ...)` persists that exact reply, and `consume-loop-budget(JIRA-KEY, reextract, revision_id)` consumes the replacement attempt.

1. Require `reextract` `in_progress`, C8c pending with `review changes requested`, C9 revision pending with exact `decision-reply: revise delivery`, no open handoff, a single `status: completed-candidate` whose `round_id` equals `prior_round_id`, and the matching consumed `reextract` budget row for `revision_id`.
2. Move the complete prior plan, result, round identity, C9 revision identity, and side-effect references into immutable Reextract Round History. Preserve all branch/PR identities and terminal dispositions; never delete, close, retarget, reset, or rewrite an external side effect.
3. Replace the current `### Reextract Result` body with `status: awaiting-replacement-plan`, `prior_round_id`, `revision_id`, and timestamp. Keep `reextract` in progress, C8c and C9 pending, and the header on reextract/C9. This state is not an unresolved staged plan, so exactly one subsequent `stage-reextract-plan` call may replace it; all other stage progression remains blocked.
4. Write/read back the complete snapshot, require exactly one historical row and one `[Stage:reextract] event=round_replaced prior_round_id=<redacted-id> revision_id=<redacted-id>` activity line, then return `reextract_round_replaced`. Exact retries are idempotent; mismatched identities, evidence, or budget state return `reextract_round_conflict` without mutation.

### restart-review-preparation(JIRA-KEY, decision_reply)

Use only after `stage-reextract-plan` returned and persisted `review-delivery-restart-required` because reviewer feedback changed `delivery_mode` or `slice_count`.

1. Require `reextract` `in_progress`, C8c pending with `decision-reply: review changes requested`, C9 pending, the restart-required evidence, no open handoff, and the entire trimmed `decision_reply` to equal the registered C9 choice `restart review preparation`. Require `approve-checkpoint` to have returned `revision_selected` and `record-revision(C9, ...)` to have durably recorded that exact reply.
2. Preserve the prior C8a/C8b decisions, approved plan, prepared/final manifests, C8c revision evidence, C9 restart decision, and all side-effect rows in immutable review-delivery history. Do not delete, close, retarget, or rewrite a branch or pull request; later Stage 8 plan reconciliation determines retained, abandoned, or superseded dispositions.
3. Set `split` to `in_progress`; set `review` and `reextract` to `not_started`; reset C8a and C8b to pending with empty current decision fields while retaining their prior evidence in history; keep C8c and C9 pending with empty current decision fields; set `### Draft PR Manifest` to `C8a Candidate Plan: pending replacement planning`; set `### Reextract Result` to `not run`; and set the header to `Active Stage: split` / `Active Checkpoint: C8a`.
4. Write/read back the complete session, append non-filterable `event=review_delivery_restarted prior_mode=<mode> prior_slice_count=<count>`, run consistency checks, and return `resume_split_planning`. A matching retry is idempotent; missing history or conflicting state is `review_delivery_restart_corrupt`.

### restart-review-preparation-from-integration(JIRA-KEY, decision_reply)

Use only after C8d records exact revision `restart review preparation from integration` because integration feedback changes delivery mode, slice count, accepted ownership, or stack topology.

1. Require stacked delivery, `integration` in progress, C8d pending with that exact revision reply, approved C8c evidence, persisted Integration PR identity, no open managed handoff, and one matching revision-selected activity event.
2. Preserve prior C8a/C8b/C8c decisions, manifests, Human Review, Integration PR, Integration Side-Effect Ledger, C8d restart decision, and every remote identifier in immutable review-delivery history. Never close, delete, retarget, or rewrite published branches or pull requests automatically.
3. Set `split` to `in_progress`; set `review`, `integration`, and `reextract` to `not_started`; reset C8a, C8b, C8c, C8d, and C9 current rows to pending while retaining prior evidence in history. Set Draft PR Manifest to pending replacement planning, Reextract Result to `not run`, Integration PR and both current delivery ledgers to empty canonical tables while preserving prior rows in history.
4. Set the header to `Active Stage: split` / `Active Checkpoint: C8a`, append non-filterable `event=integration_review_restarted`, verify schema consistency, and return `resume_split_planning`. A retry is idempotent; conflicting evidence is `integration_review_restart_corrupt`.

### write-stage(stage, result, source_ref)

This is an internal completion primitive used by `approve-checkpoint` after an advancing decision is validated; callers do not use it to bypass a checkpoint. C8b is the deliberate exception to immediate stage completion: `open draft pull requests` authorizes PR creation while `split` remains `in_progress`; the stage completes only after those authorized PR operations finish or reconcile. A successful stage result, passing setup cache, skipped or pre-existing architecture, an earlier checkpoint choice, subagent recommendation, or model judgment is not decision evidence.

1. Require both `session.md` and `activity.log` to exist. If either is absent, return `init_required` without creating or mutating state.
2. For stage `push`, `docs`, or `reextract`, read the matching persisted-result sentinel and read the candidate previously written under its fixed artifact subsection: `persisted-stage-result` for push/docs, `persisted-reextract-result` for reextract. Re-run the owning record-operation validation and require its pending marker (`Approval: pending C6`, `Acceptance: pending C10`, or `status: completed-candidate`). For docs, also resolve and re-read the immutable handoff-report path. On any missing, malformed, mismatched, mutable, or empty value, return `artifact_missing: <pushed_ref|post_action_doc|reextract_result>` with the reason and do not mutate `session.md`, append activity, publish the checkpoint, start regression, or archive. Do not reconstruct a result from a ledger note, Branch Info, Git state, another artifact, or conversational memory.
3. Resolve the stage's `produces` value from `pipeline.stages` and its fixed subsection from the artifact-write map above. For every stage except `push`, `docs`, and `reextract`, require the supplied `result` to render as substantive Markdown after trimming. Empty or whitespace-only content, a bare `-`, an unchanged angle-bracket template body, `(not yet captured)`, `pending`, and `not run` are not completed-stage results. On an absent mapping or invalid result, return `artifact_mapping_missing` or `artifact_missing: <produces>` without changing the stage row, header, ledger, artifacts, activity log, or Jira. Do not reconstruct a missing result from a ledger note, another artifact, branch state, a specialist summary remembered in chat, or model inference; rerun or escalate the owning specialist result.
4. Set the stage row: `state: complete`, `checkpoint` (the static registry value — never a sub-gate id), `source_ref` (the observed value, or `-`), `updated` (now, ISO-8601), `by` (the `runs` value).
5. Re-run **staleness-scan** and downgrade any now-stale downstream stages to `stale`.
6. In the **same write**, bring every region into agreement with the stage row you just set — the header, Checkpoint Ledger, and Artifacts are one snapshot with the Stage Status table and must never trail it:
   - **Header** — set `Active Stage`/`Active Checkpoint`/`Updated` to the stage just completed (its completion gate), or, if a later stage is already `in_progress`, to that stage and its live gate. `Active Checkpoint` is always a checkpoint **of** `Active Stage`; it never holds a different stage's value. Leave every row's `checkpoint` column at its static registry value. Never leave the header pointing at an earlier stage than the furthest row that has advanced past `not_started`.
   - **Checkpoint Ledger** — update this stage's existing checkpoint table row to `status: approved`, persist the exact `decision-reply`, set `milestone: pending` until publication is verified, and record the approval timestamp. A `complete` stage row may never coexist with a pending ledger table row for the same checkpoint except `qa` and/or `tests` completed through `record-shared-gate-stage-result` while shared C4 awaits its developer decision; for the two-checkpoint `split` stage (C8a→C8b) mark **both** of** checkpoint rows approved when the stage row is complete. Preserve the existing C8b decision and approval timestamp when finalizing the authorized `split` work.
   - **Artifacts** — replace the body under the registry-mapped fixed subsection with the unchanged substantive stage result in place. A `complete` stage must show that real content, never an invalid placeholder. One subsection per artifact type (see the template) — never add a second subsection with the same heading, and never append a fresh copy below the existing one. Refine replaces the earlier intake content in their shared subsection. A completed reactive `reextract` fills `### Reextract Result` with its replacement/superseded references. For `push`, preserve the validated persisted fields under `### Pushed Ref` and replace `Approval: pending C6` with `Approval: accepted at C6`. For `docs`, preserve the validated persisted fields under `### Post-Action Document`, replace `Acceptance: pending C10` with `Acceptance: accepted at C10`, and never copy the report body.
   Each `write-stage` rewrites the whole file, so the result is a single well-formed, internally consistent document: exactly one `# Session:` header, exactly one of each `### <subsection>`, and header/ledger/artifacts all matching the Stage Status table.
7. When the final stage (`docs`) completes, set `Status: COMPLETE` **and** fill the `Reuse Digest` artifact (structured facts for follow-up similar stories — see the template). Do not archive in this write; archival is the separate `archive` operation the caller runs immediately after (see **archive**).
8. Before writing, verify the four regions agree (header, Stage Status table, Checkpoint Ledger, and Artifacts); then write the whole file with the `edit` tool in one flush. For `docs`, require `### Post-Action Document` to contain the validated path and readiness metadata with `Acceptance: accepted at C10`; `Acceptance: pending C10` is stale after completion. Never batch or defer this write, and never flush a file whose checkpoint or artifacts lag the table.
9. Immediately after the session write, append the paired activity line via `append-activity`, using `transition=<the completed row's updated timestamp>`; normally `event=approved decision="<the exact registered decision-reply persisted in the ledger>"` for `[Checkpoint:<the stage's checkpoint>]`; when this write completes only one sibling of a still-pending shared checkpoint, append `event=stage_complete` for `[Stage:<id>]` instead. Completing `docs` does **not** append `event=run_complete` here: a full run's terminal event belongs to `archive`, and a single-stage docs run appends its explicit non-archive terminal event after C10. If an append fails, return `activity_append_pending` and stop before narration, milestone publication, archival, or the next pipeline action. On retry, derive the expected missing event, exact persisted decision reply, and transition id from the durable session state and append it idempotently before continuing; do not rewrite the session timestamp or duplicate an existing event. Apply this recovery through `docs`/C10 so later stages never advance while the log is behind.

### append-activity(event, transition_id?, handoff_id?, archive_id?, archive_target?, prune_id?, prune_target?)

Append one activity line to `<log_dir>/<JIRA-KEY>/activity.log`. Only deva calls this. The file already exists from `init`, so appends never race file creation.

1. Resolve the event's severity (see **Events to record**) against `pipeline.log_level`. Always append state-critical checkpoint, regression-request, operation-authorization, Jira-enrichment, agreement-revision, split-plan-revision, archive lifecycle, and terminal `run_complete` events regardless of the threshold. For any other event below the threshold, **skip the line** and return `activity_appended: false, threshold_skipped: true, idempotent: false` without appending (the file itself still exists from `init`).
2. Require `<log_dir>/<JIRA-KEY>/activity.log` to exist. Normally also require the live `session.md`; if either required file is absent, return `init_required` without creating or appending state. Two narrow exceptions exist:
   - An archive-lifecycle append after promotion (`archive_promoted`, `archive_cache_removed`, full-run `run_complete`), or a documented post-promotion archive failure) may supply `archive_id` and `archive_target`. Resolve the target as configured, require it to exist, and require its lowercase SHA-256 to equal `archive_id`.
   - A `prune_intended` append may supply `prune_id` and the exact eligible archived `prune_target`; require that target to exist and its lowercase SHA-256 to equal `prune_id`. A later `prune_completed` append may use the matching unresolved `prune_intended` activity line as its state anchor only after the prune operation verifies the target, tombstone, report, and index entry are all absent as planned. A different, duplicate, or missing intent is `prune_recovery_corrupt`.
3. For an event paired to a session transition, require `transition_id` to equal the durable stage row's `updated` timestamp and include it as `transition=<transition_id>`. Before appending, scan the log for the same `sess`, component/name, `event`, and `transition` tuple. If present, return `activity_appended: false, threshold_skipped: false, idempotent: true` without appending; this is the idempotent retry path. Subagent handoff events omit `transition_id`, require `handoff_id`, and use the same idempotency rule keyed by `sess`, component/name, event, and handoff id. Other events omit `transition_id` and retain their existing append-only behavior.
4. Compose one line per the **Line format** above with a fresh ISO-8601 UTC event timestamp; apply the same secret/PII guard as `session.md` (never write tokens, credentials, or sensitive Jira content — PII-1).
5. Read the entire existing log and retain its exact content and byte length as the required prefix. Append the new line at end-of-file with an append-only primitive (`Add-Content` or an equivalent append operation) and flush immediately. Once the file exists, `Set-Content`, `create_file`, output redirection, a here-string piped to a writer, whole-file replacement, and any edit that does not preserve the complete prefix are forbidden. Deva never writes this file directly; it invokes this operation.
6. Read the file back and require that it begins byte-for-byte with the retained prefix, has not shrunk, and contains exactly one new canonical line (or no new line on an idempotent retry). If prefix or length verification fails, return `activity_append_corrupt` and block before narration, milestone publication, archival, or the next pipeline action. Never accept a shorter log merely because its newest event matches the session. After a verified new line, return `activity_appended: true, threshold_skipped: false, idempotent: false`.

### schema-shape-check (read-only)

Validate the complete persisted document shape before interpreting progress. Derive stage and checkpoint rows from `pipeline.stages`; derive stage-owned artifact headings from the artifact-write map; add the fixed non-stage headings `Agreement Revision History`, `Draft PR Manifest`, `Subbranch Side-Effect Ledger`, `Integration Side-Effect Ledger`, `Subagent Handoff Ledger`, and `Reuse Digest`.

1. Require exactly one session H1, one schema-8 header block containing exactly one valid lowercase UUID v4 `Run ID`, one `## Stage Status`, one `## Checkpoint Ledger`, and one `## Artifacts` region in that order. Require every fixed `###` artifact heading exactly once, including Loop Budget Ledger, and reject unknown duplicate fixed headings.
2. Require the Stage Status table's canonical columns and exactly one data row per registry stage in registry order. Require the Checkpoint Ledger table's canonical columns `checkpoint`, `status`, `decision-reply`, `milestone`, and `updated`, with exactly one data row per registry gate in registry order.
3. Require the Subbranch Side-Effect Ledger, Integration Side-Effect Ledger, Subagent Handoff Ledger, and Loop Budget Ledger canonical table headers even when they contain no data rows. The Loop Budget Ledger header is exactly `| budget | attempt_id | ordinal | consumed_at |`. Require Agreement Revision History to exist even when its body is `_None._`.
4. Return `schema_shape: current` only when all required regions, headings, table headers, and key sets are present exactly once. Otherwise return `session_schema_corrupt` with structured `missing`, `duplicate`, `malformed`, and `unknown` lists. This operation is read-only: it never inserts a section, converts evidence, or repairs content.

### consistency-check (run before returning from `mark-in-progress`, `record-stage-result`, `approve-checkpoint`, or `write-stage`)

Every mutating operation ends with this check. Verify each invariant against what you just wrote and repair any failure **in the same operation**. If the paired activity append cannot be repaired, return `activity_append_pending` with the durable session transition intact and block all further progression; this is the only permitted partial return:

1. **The complete schema shape exists.** Run `schema-shape-check` against the persisted file before evaluating values. Every fixed region and artifact heading exists exactly once, including the exact Loop Budget Ledger header and separator, and the Stage Status and Checkpoint Ledger key sets exactly match the registry. A missing section is not repaired by borrowing content from another artifact or chat memory. Return `session_schema_corrupt` before milestone publication, progression, or archival when the shape is incomplete or ambiguous.
2. **Header binds to the active row.** `Active Stage` names the current `in_progress` stage (or, if none is running, the furthest `complete` stage), and `Active Checkpoint` is a checkpoint **of** that stage — never a different stage's checkpoint. C8b after C8a approval and through authorized PR creation, or the stage's single completion gate — never a different stage's checkpoint. The Stage Status `checkpoint` column stays at each stage's static registry value; the header is exactly one five-column Markdown table with one keyed data row for every registry gate in step order, including both sub-gates of the two-checkpoint `split` stage, with no duplicate or unknown rows; each checkpoint row is at least as advanced as its state. A `complete` stage has a pending-free `status: approved`, a valid registered decision-reply, and a non-placeholder milestone timestamp (both checkpoint rows for the two-checkpoint `split` stage), except complete-and-fresh `qa` and/or `tests` rows may retain pending C4 before the shared decision. That exception requires completed sibling's substantive artifact and exact transition-keyed `event=stage_complete`, and forbids approval or milestone evidence. An `in_progress` stage normally has a pending live gate; the other allowed exception is `split` after C8b approval while the authorized PR operations are still running. No other complete stage may retain a pending checkpoint row. After every write, re-read the persisted table and compare its row values with the Stage Status table and the activity evidence before returning. If a write would produce a missing, duplicate, unknown, out-of-order, malformed, or lagging row, rebuild the table from the registry before flushing while preserving each checkpoint's one valid current decision and milestone evidence. For the narrow stale-template case where duplicate rows contain one pending value and one approved value with valid registered decision evidence, retain the approved row and discard the stale pending row. If duplicates contain conflicting approved decisions, multiple approved rows, or no uniquely valid state, return `checkpoint_ledger_corrupt` without writing, publishing a milestone, advancing, or archiving; never guess which row is authoritative.
3. **Checkpoint Ledger table matches the Stage Status table and registry exactly.** Derive the ordered checkpoint set from each stage's `checkpoints` list when present, otherwise its single `checkpoint`. Between `## Checkpoint Ledger` and `## Artifacts`, require exactly one canonical table header, one separator row, and one data row for every derived checkpoint in that order, with no duplicate or unknown keys. Every checkpoint mutation replaces its existing keyed data row in place and then replaces the complete table region; it never appends a second row. Every `complete` stage row has a `status: approved`, a valid registered decision-reply, and a non-placeholder milestone (both checkpoint rows for the two-checkpoint `split` stage), except complete-and-fresh `qa` and/or `tests` rows may retain pending C4 before the shared decision. That exception requires completed sibling's substantive artifact and exact transition-keyed `event=stage_complete`, and forbids approval or milestone evidence. An `in_progress` stage normally has a pending live gate; the other allowed exception is `split` after C8b approval while the authorized PR operations are still running. No other complete stage may retain a pending checkpoint row. After every write, re-read the persisted table and compare its row values with the Stage Status table and the activity evidence before returning.
4. **Artifacts match the table and registry.** For every stage, resolve `produces` and its fixed subsection through the artifact-write map. Require every fixed artifact subsection from the schema template exactly once. Every complete stage has substantive mapped content. A not-started `reextract` may retain `not run`; not-started direct-mode `integration` may retain `not applicable for direct delivery`. Stacked integration may retain pending C8c before C8c approval. An in-progress integration with a recorded candidate requires `Acceptance: pending C8d`; complete integration requires accepted C8d evidence and no pending marker. Docs retains its existing pending/accepted C10 report rules. Never infer artifact content.
5. **The activity log is not behind or truncated.** The log retains its complete prior prefix, grows with the run-opening history, and its last line is at least as advanced as the session: a `mark-in-progress` left a matching `event=enter`; every Subagent Handoff Ledger row satisfies `subagent-handoff-consistency-check`; a first checkpoint approval left `event=approved`; and a stage completed after its checkpoint was already approved, or one sibling of a shared checkpoint completed while the gate remained pending, left `event=stage_complete`. Full-run `run_complete` is deliberately absent until `archive` verifies its terminal post-condition; a single-stage docs caller appends its own non-archive terminal event after C10. Match stage-transition events by their durable transition timestamp and handoff events by `handoff_id`. If the session moved but a paired append is missing, append it idempotently with the owning key. A missing `run_start` or earlier stage/handoff enter after later events exist is truncation, not an invitation to reconstruct or rewrite history; return `activity_append_corrupt` and block. If repair fails, return `activity_append_pending` with durable state intact and block advancement. A retry performs this repair before any new transition. `pipeline.log_level` gates only whether a composed line clears the threshold — it never excuses a missing paired append for an event at or above the level.

### reconcile-checkpoint-ledger(JIRA-KEY, checkpoints, confirmed=false)

Use only to recover a schema-8 Checkpoint Ledger table whose rows remained pending even though the same transition durably completed elsewhere. This operation repairs no stage, artifact, activity approval, or Jira milestone and never creates a new checkpoint decision. It requires a direct, explicit developer request for this recovery after the mismatch is surfaced.

1. Require `confirmed: true` and a non-empty ordered `checkpoints` list equal to the affected list returned by `status`; otherwise return `checkpoint_ledger_recovery_confirmation_required` without mutation. Require no open subagent handoff, pending agreement revision, duplicate checkpoint row, or conflicting ledger evidence.
2. For each checkpoint, require every stage represented by that gate to be `complete` and fresh, with the expected registry-mapped artifact present and substantive. For C4, require both `qa` and `tests` complete and fresh. Require the ledger table row to be uniquely present and still `pending`; an already-approved or missing row is not eligible.
3. Read the append-only activity log and require exactly one canonical `[Checkpoint:<checkpoint>] event=approved decision="<exact registered advance reply>"` line, plus exactly one canonical `[Checkpoint:<checkpoint>] event=milestone_posted` line. Require the approval timestamp to equal the completed stage transition timestamp, or for shared C4 the later sibling completion timestamp. Reject missing, duplicate, unregistered, or contradictory activity as `checkpoint_ledger_recovery_conflict: <checkpoint>`.
4. Read Jira comments and require exactly one `Milestone-ID: <JIRA-KEY>:<checkpoint>` marker whose checkpoint and redacted outcome agree with the activity decision. Reject zero or duplicates. Activity or Jira evidence alone is insufficient; all stage, artifact, activity, and Jira checks must agree.
5. In one session write, update only each eligible Checkpoint Ledger table row: set `status: approved`, copy the exact registered `decision-reply`, set `milestone: posted`, and use the verified approval timestamp. Preserve the header, Stage Status table, artifacts, agreement history, side-effect ledger, and handoff ledger byte-for-byte. Re-read the full file and require the canonical table, registered approved values, registry order, and all consistency invariants.
6. Append one WARN `[Checkpoint:<checkpoint>] event=checkpoint_ledger_reconciled` line per repaired gate through `append-activity`, keyed by the verified approval transition timestamp so retries are idempotent. Re-read the log and require exactly one reconciliation event per repaired gate.
7. Run `consistency-check` and `milestone-consistency-check(all-approved)`. Return `checkpoint_ledger_reconciled: [<ordered checkpoints>]` only when both are current. Any failed check returns its blocker and prevents normal progression; never partially report success.

### next-stage (for a full run)

Run `subagent-handoff-consistency-check(all)` first. If any handoff is missing its enter or terminal return, return `subagent_handoff_pending: <handoff_id>` or `subagent_handoff_corrupt: <handoff_id>` and do not select or resume a stage.

If Agreement Revision History contains a pending developer decision, return `resume_agreement_revision_decision` with its stable revision id and registered choices. If it contains an accepted revision awaiting Jira publication, return `resume_agreement_revision_enrichment`. Do not select a normal stage until the revision is resolved and finalized.

If `refine` is `in_progress` and its latest `Refinement Choice` is `awaiting decision`, return `resume_refine_decision` with the exact persisted assessment and registered choices. For `draft authorized`, return `resume_refine_draft`; for `gaps accepted`, return `resume_refine_with_gaps`; for `example requested`, return `resume_refine_example` with the exact persisted assessment, registered choices, and persisted `assessment_hash`. Never construct or stage a Jira-enrichment candidate until Story Analyst consumes the persisted advancing outcome and returns the implementation-ready brief.

If `refine` is `in_progress` and its Jira Enrichment Authorization is `awaiting decision`, return `resume_refine_enrichment_decision` with the exact persisted brief and registered choices. If it is `authorized` but not complete, return `resume_refine_enrichment` with the exact persisted brief and hash. If it is `declined`, return `resume_refine_revision_or_stop`. Never surface C1b until ordinary enrichment is complete.

If the Draft PR Manifest contains a pending split-plan revision decision, return `resume_split_plan_revision_decision` with its id and registered choices. If it is `accepted_disposition_pending`, return `resume_split_plan_dispositions` with the exact disposition plan. If it is complete and the replacement extraction is not started, return `resume_revised_initial_extraction` with the exact authorized plan. Never restart split planning or proceed to C8b while one of these states is unresolved.

If `### Reextract Result` has `status: review-delivery-restart-required` while C9 is pending, return `resume_review_delivery_restart_decision` with the persisted evidence and all registered C9 choices until the exact `restart review preparation` revision is durable but before reset completes, return `resume_review_preparation_restart`; never rerun re-extraction or mutate review branches in either state.

If `### Reextract Result` has `status: completed-candidate` while C9 is pending, return `resume_C9_decision` with that exact persisted candidate and registered C9 choices. If it has `status: awaiting-replacement-plan`, return `resume_reextract_replacement_plan` with the persisted prior round and revision identities. Never reconstruct the candidate from a completed handoff, rerun the prior round, or present C9 without a completed candidate.

If C8d is pending with `decision-reply: integration changes requested`, return `resume_integration_changes` until refreshed repair evidence is complete, then `resume_integration_refresh`. If C8d carries `restart review preparation from integration`, return `resume_integration_review_restart` until the reset operation completes. Never create a second integration PR or restart C8c in these states.

When no split-plan revision is unresolved and `split` is `in_progress`, return `resume_split_c8a_review` from the persisted exact C8a Candidate Plan when C8a is pending, `resume_split_initial` from the persisted exact C8a Approved Plan when initial extraction is pending, or `resume_split_c8b_review` from the persisted Prepared Manifest when it awaits C8b. Never reconstruct any payload from a checkpoint note or chat memory.

When C8a is pending with no candidate and the latest completed planning handoff has no staged payload, return `resume_split_planning`. This exception reruns only the read-only planning handoff, creates a new handoff id, and stages its result before C8a; it never repeats extraction or external mutation.

Run `milestone-consistency-check(all-approved)` before selecting or resuming any stage. If it returns a blocker, return that blocker and do not select a stage; recover a missing publication only through `recover-milestone`, which reads the persisted decision without synthesizing a developer message.

Before the normal walk, detect the exact C8b continuation state: `split` is `in_progress`, C8b is approved with `decision-reply: open draft pull requests`, and the authorized Draft PR Manifest exists. Return `resume_split_publish` with no stage reset. If C8b is approved but the manifest is unusable, return a blocker rather than rerunning split or reconstructing authorization.

Before the normal walk, inspect the canonical delivery mode. For stacked delivery with review complete and C8c approved:

- when `integration` is `not_started`, return `start_stacked_integration`;
- when `integration` is `in_progress` and Integration Side-Effect Ledger has `intended` or `partial` publication, return `resume_integration_publish`;
- when Integration PR contains a recorded candidate with `Acceptance: pending C8d`, return `resume_integration_c8d_review` and surface C8d without republishing;
- when `integration` is complete but C8d lacks current approval/milestone evidence, return `checkpoint_pending: C8d`.

For direct delivery, require `integration` to remain `not_started`, Integration PR to state `not applicable for direct delivery`, and C8d to remain pending with no milestone; then continue the normal walk to docs after C8c. Any direct integration stage activity is `integration_mode_corrupt`.

Otherwise walk `pipeline.stages` in `step` order, excluding reactive stages. Before selecting a later stage, inspect every earlier non-reactive stage and checkpoint ledger entry. Treat a stage as skippable only when it is `complete` and fresh and its checkpoint is approved with a valid registered `decision-reply`, or with legacy `approval-token: approve <checkpoint>` evidence already stored by an older version. If an earlier stage is pending or complete without valid evidence, return `checkpoint_pending` for the earliest gate; never select a downstream stage.

### begin-subagent-handoff(JIRA-KEY, stage, subagent, mode=default, authorization_id=-)

Call immediately before every actual nested-agent invocation, after the owning stage is `in_progress`. Controller-owned work, a skipped stage, and an external human wait do not call this operation.

1. Require the live session/activity pair, a known owning `stage`, a non-empty kebab-case `subagent`, and a non-empty space-free `mode`. Normally require `authorization_id: -` and require that owner stage to be `in_progress`. The first state exception is agreement-revision `story-analyst` mode `enrich-jira`: permit the proposal revision's exact `source_stage` to be `stale` only while that revision is `accepted_jira_pending`, still with `authorization_id: -`. The second is `stage: architecture`, `subagent: architecture-bootstrapper`, and `mode: on-demand`: require a non-empty authorization id, permit the architecture stage to remain `complete` and fresh, and require `check-on-demand-architecture-authorization(JIRA-KEY, authorization_id)` to return `authorized`; never reopen the stage or C0b. Reject a supplied authorization id for every other role. Validate normal stage/subagent ownership from the registry or the complete `check-managed-handoff` matrix above; reject every other cross-role combination as `subagent_handoff_invalid` without mutation.
2. Under `### Subagent Handoff Ledger`, inspect every `started` row. If exactly one open row matches `stage`, `subagent`, and `mode`, re-run the idempotent enter append check: require the existing event when INFO clears the threshold, or `threshold_skipped: true` when WARN or ERROR suppresses it. Then return `handoff_started: true`, the existing `handoff_id`, and that check's `threshold_skipped: true | false`; this is recovery for that same interrupted invocation. Any other open row blocks with `subagent_handoff_pending: <handoff_id>`; more than one open row is `subagent_handoff_corrupt`. Never overlap nested invocations.
3. Otherwise choose the next positive ordinal after all matching rows and construct `handoff_id=<stage>:<subagent>:<mode>:<ordinal>`. Append exactly one row with `status=started`, `outcome=pending`, `started_at=now`, and terminal fields `-`. Set the session header `Updated` to now without changing stage/checkpoint state or any other artifact.
4. Write and read back the session, requiring exactly one new row with that `handoff_id`. Append one INFO `[Subagent:<subagent>] event=enter handoff_id=<id> stage=<stage> mode=<mode>` through `append-activity`, keyed idempotently by `handoff_id` rather than a stage transition timestamp. When INFO clears `pipeline.log_level` require the explicit append; otherwise return `threshold_skipped: true` and require exactly one matching event. When an explicit WARN or ERROR threshold suppresses it, require `append-activity` to return `threshold_skipped: true`; the durable handoff row remains the invocation record.
5. Return `handoff_started: true`, `handoff_id`, and `threshold_skipped: true | false` copied unchanged from the enter-event append result. Deva may invoke the nested agent only after this durable result and the threshold-specific evidence in step 4.

### complete-subagent-handoff(JIRA-KEY, handoff_id, outcome, reason=-)

Call immediately after every nested-agent invocation terminates, before interpreting, staging, narrating, retrying, or advancing. Use `ok` for any usable returned report, checkpoint, or question; `blocked` for an explicit blocker; `fail` for tool/agent failure; and `empty` for no usable result.

1. Require `outcome` to be `ok`, `blocked`, `fail`, or `empty`, and require exactly one handoff row. A missing/duplicate row is `subagent_handoff_corrupt`.
2. If the row is already `complete` with the same outcome and redacted reason, re-run the idempotent terminal append check: require the existing event when its severity clears the threshold, or `threshold_skipped: true` when suppressed. Then return `handoff_completed: true`, `handoff_id`, `outcome`, and that check's `threshold_skipped: true | false`. A different terminal result for the same `handoff_id` is `subagent_handoff_corrupt`; never overwrite history.
3. Require the row to be `started`; replace it in place with `status=complete`, the supplied outcome, `completed_at=now`, and a short PII-scrubbed reason (`-` for `ok`). Update only the header timestamp and this fixed ledger row; never change stage, checkpoint, or result artifacts.
4. Write and read back the complete session. Append `[Subagent:<subagent>] event=return handoff_id=<id> stage=<stage> mode=<mode> outcome=<outcome>` at INFO for `ok`/`empty`, WARN for `blocked`, or ERROR for `fail`, adding the redacted reason when applicable. Key idempotency by component, event, and `handoff_id`. When the event clears `pipeline.log_level`, re-read the log and require exactly one matching return event. When an explicit threshold suppresses an INFO or WARN return, require `threshold_skipped: true`; ERROR failures are never below a supported threshold.
5. Run `subagent-handoff-consistency-check(stage)` and require `handoff_completed: true`, `handoff_id`, `outcome`, and `threshold_skipped: true | false` copied unchanged from the return-append result only when it is current. On append/read-back failure return `subagent_handoff_pending: <id>` and block before another invocation or pipeline mutation.

### subagent-handoff-consistency-check(stage | all, allow_active_stage?, allow_handoff_id?)

1. For every selected row, require exactly one INFO `[Subagent:<subagent>] event=enter` with the row's `handoff_id`, stage, and mode when INFO clears the configured threshold. At WARN or ERROR, the durable row remains required but an intentionally suppressed INFO enter is not corruption.
2. A `started` row may have no return only while its invocation is actively in flight. When `allow_active_stage` is supplied, accept exactly one such row only when the stage equals that allowance and this stage's registry `runs` value. When `allow_handoff_id` is supplied by `check-managed-handoff`, accept exactly that one row only after the managed-handoff matrix and owner-state checks pass. Reject a second, mismatched, or unregistered open row. Without either narrow allowance, before checkpoint approval, result staging, another handoff, next-stage selection, or archive, a `started` row without a return is `subagent_handoff_pending: <handoff_id>`.
3. A `complete` row requires exactly one terminal return with matching handoff id, stage, mode, and outcome when that event's severity clears the configured threshold. An intentionally suppressed INFO or WARN return remains represented by the completed row; an ERROR failure always requires its event. Missing required or duplicate events, duplicate rows, an enter without a row, or a return without a row is `subagent_handoff_corrupt: <handoff_id>`.
4. Return `subagent_handoffs: current` only when every selected invocation is paired. Stages with no actual nested invocation require no row; represent their lifecycle with `skip`, controller-owned stage events, or the external human-review state instead.

### check-loop-budget(JIRA-KEY, budget, attempt_id=-) (read-only)

1. Require `budget` to name a positive integer under `governance.loop_budgets`; reject an unknown or non-positive key as `loop_budget_invalid`.
2. Parse the complete Loop Budget Ledger. Require exactly one canonical header `| budget | attempt_id | ordinal | consumed_at |` before parsing rows. For each budget, require unique attempt identities and positive ordinals contiguous from 1; a missing or altered header, or malformed, duplicate, skipped, or conflicting rows, are `loop_budget_ledger_corrupt`.
3. Return `used`, configured `cap`, and `remaining = cap - used`. When the supplied `attempt_id` already has exactly one row, also return `attempt_consumed: true` and its ordinal. Never infer usage from chat history, handoff rows, timestamps, regression prose, or side-effect attempts.

### consume-loop-budget(JIRA-KEY, budget, attempt_id)

Call immediately before each session-managed retry and before its repair handoff or external mutation. The initial stage attempt consumes no retry budget.

1. Run `check-loop-budget`. Require a non-empty, trimmed, single-line `attempt_id` derived from durable triggering evidence such as a failed handoff id, regression `round_id`, or a checkpoint-revision id; reject timestamps and newly generated retry ids.
2. If `attempt_consumed: true`, return the existing row unchanged with `changed: false`; interruption recovery never consumes twice.
3. If `remaining` is zero, return `loop_budget_exhausted` without modifying session state or beginning retry work.
4. Otherwise append one row with `ordinal = used + 1` and `consumed_at = now`. Update only the header timestamp and Loop Budget Ledger.
5. Write and read back the session, rerun `check-loop-budget`, and require exactly one matching row and the expected count. Return `loop_budget_consumed`, the persisted row, counts, and `changed: true`; conflicting evidence is `loop_budget_ledger_corrupt`.

### update-side-effect(JIRA-KEY, entry, operation, idempotency_key, intended_target, status, returned_identifier, reconciled_at)

Use this operation for immediate, mid-stage durability around externally visible subbranch-extraction mutations. `subbranch-extractor` calls it directly through this skill; Deva must initialize the session before the handoff and pass the same `<JIRA-KEY>` as `parent_jira`.

1. Require `entry` to equal the exact `branch` from the C8a-approved plan or persisted manifest that authorizes the operation. Direct mode uses the feature branch; stacked mode uses the exact parent-Jira ordinal review branch. An authorized replacement branch receives its own exact entry and never relabels an existing ledger row. Reject a missing, translated, descriptive, ordinal-only, or caller-invented entry before mutation.
2. Require `operation` to be exactly `branch-create`, `branch-push`, `integration-commit`, `pr-create`, `pr-comment`, or `supersede`. Require `intended_target` to be a non-empty, trimmed single-line string identifying, respectively, the exact new branch and authorized base, published branch/ref and commit, story delta and destination base, authorized head/base pair, persisted pull request and fixed comment purpose, or prior external identifier and authorized replacement reference. Reject an operation whose target does not carry its required identity.
3. Require `idempotency_key` to equal the lowercase SHA-256 hex digest of the UTF-8 bytes of `<entry>\n<operation>\n<intended_target>`, using one line-feed separator and the exact validated component values. Never use a retry count, timestamp, returned identifier, or conversational value in the key.
4. Require `status` to be `intended`, `partial`, `complete`, `abandoned`, or `superseded`. `abandoned` and `superseded` are terminal historical dispositions used only after a registered C8a/C8b plan revision or a staged stacked `plan-changing` reextract plan. For a changed initial plan, require the exact pending disposition in `accepted_disposition_pending` split-plan revision; for C8b use its recorded revision selection; for reviewer feedback require the entry and terminal transition to match the exact affected-entry disposition persisted by `stage-reextract-plan`. An `ownership-preserving` reextract plan may add intended/complete correction and propagation operations but cannot abandon or supersede any existing branch or PR. A restart-required result authorizes no ledger disposition. These states never authorize deletion or rewriting of a remote side effect.
5. Find the row with that `idempotency_key` under `### Subbranch Side-Effect Ledger`.
   - If absent, accept only `status: intended`; append exactly one row with `returned_identifier: -` and `reconciled_at: -`.
   - If present, require `entry`, `operation`, and `intended_target` to match exactly. A mismatch is a collision: stop without changing the file.
6. Enforce monotonic transitions: `intended → partial → complete`, allowing `intended → complete`; after a registered C8a/C8b revision selection or exact staged `plan-changing` reextract disposition, allow an authorized nonterminal row to become `abandoned` and an authorized `complete` row to become `superseded`. An identical retry is an idempotent no-op. Never regress or leave a terminal state, append a duplicate attempt, delete the recorded external identifier, or replace a non-empty returned identifier with a different value.
7. For `partial`, record any observed identifier and reconciliation timestamp available. For `complete`, require the observed issue key, branch/ref, PR URL/id, or comment id in `returned_identifier`; set `reconciled_at` to the supplied observed timestamp or now when completion was observed directly. For `abandoned` or `superseded`, preserve any observed identifier and require a reconciliation timestamp proving the disposition was recorded before replacement planning proceeds.
8. Replace that one ledger row in place, set the session header `Updated` to now, and preserve every Stage Status row, checkpoint line, and other artifact byte-for-byte. Write the whole `session.md` once with the `edit` tool and flush immediately.
9. Do not call `append-activity`: this operation records a nested external side effect, not a stage transition or checkpoint. Before returning, verify there is exactly one row for the idempotency key and that the stage/header checkpoint binding remains unchanged.
10. Return the persisted row and `changed: true | false`. The caller may perform the external mutation only after an `intended` row is durably returned; after success or reconciliation, it must call this operation again before performing another external mutation.

### discard(JIRA-KEY, confirmed=false)

Run this only after Deva receives explicit developer intent to abandon the live story session. This operation owns every filesystem decision; Deva supplies the confirmed intent and responds to the result.

1. Require `confirmed: true`. Otherwise return `status: blocked` without reading or changing state.
2. Resolve `<session_dir>`, `<log_dir>`, and `<archive_dir>` from `pipeline` in `.github/config/guardrails.yaml`. Validate `JIRA-KEY` as one safe path segment and prove the target is exactly `<session_dir>/<JIRA-KEY>/`; never accept an absolute path, separator, traversal segment, or the setup-validation cache as the target.
3. If the live session directory is absent, return `status: already-absent`. Do not create or change a log, archive, index, or setup artifact.
4. Before deletion, append one fixed, non-filterable activity event to the existing `<log_dir>/<JIRA-KEY>/activity.log` using the canonical line format: `<ISO8601-UTC> sess=<JIRA-KEY> INFO [Agent:deva] event=discarded outcome=live_session_removed`. Apply PII-1 and idempotency: if a terminal discard event with that `sess`, component, event, and outcome already exists, do not append it again. A missing or failed activity log append blocks deletion so the retained audit trail cannot silently lose the reason for removal.
5. Delete only `<session_dir>/<JIRA-KEY>/` and its live contents. Preserve `<session_dir>/setup-validation.md`, the entire activity-log directory, every archived session under `<archive_dir>`, and the reuse index.
6. Return `status: discarded`, `jira_key`, `activity_log_preserved: true`, and `archives_preserved: true`. A retry after success returns `already-absent` and remains side-effect free.

### archive(JIRA-KEY)

Run this **once, at the end of a full run**, immediately after `write-stage(docs, …)` has set `Status: COMPLETE` and filled the Reuse Digest. It promotes the finished session out of the ephemeral cache into the durable artifact tree so it survives for audit, troubleshooting, and follow-up similar stories. A **single-stage** run never archives.

**Completed-retry guard (before step 1):** when the live session is absent, inspect the activity log before unresolved-intent preflight. If the latest archive lifecycle has exactly one matching `archive_intended`, `archive_promoted`, `reuse_index_appended`, `archive_cache_removed`, and `run_complete` carrying the same `archive_id` for one id with no later unresolved intent, require its target hash, immutable report, and exactly one Reuse-Digest-derived index line resolving to that target. Return the same complete attestation idempotently from those read-back values. Conflicting or incomplete evidence continues to the unresolved-intent rules below or returns `archive_recovery_corrupt`; never start a new archive merely because the prior successful call was interrupted before returning.

**Index-failure evidence:** every `reuse_index_append_failed` outcome, including initial index preparation before promotion, appends and verifies one idempotent non-filterable `event=reuse_index_append_failed archive_id=<id> reason=<redacted>` before returning. When the live session still exists it is the event anchor; after promotion use the verified archive anchor.

1. Select a read-only preflight snapshot before any archive mutation. Normally this is the live session. When the live session is absent, require exactly one unresolved `event=archive_intended`, require its recorded current target to exist with lowercase SHA-256 equal to the recorded `archive_id`, and use that promoted snapshot only for archive-recovery preflight; otherwise return `archive_recovery_corrupt`. Run the full `consistency-check` and `milestone-consistency-check(all-approved)` against the selected snapshot, including the exact decision/activity/Jira evidence but never rewrite an archived session. If either check would require a session repair, or returns `checkpoint_ledger_corrupt`, `artifact_mapping_missing`, `checkpoint_milestone_pending`, a milestone duplicate, or any other blocker, return that result without creating, moving, rotating, pruning, or indexing anything. Then confirm the selected snapshot is `Status: COMPLETE`, the `docs` row is `complete`, and the C10 ledger entry is `approved` with `decision-reply: archive session` or legacy `approval-token: approve C10`. Also require `### Post-Action Document` to contain the validated canonical report and readiness metadata with `Acceptance: accepted at C10` or `Acceptance: pending C10` placeholder, and re-read the referenced report to prove it is still present and non-empty. If the decision/state conditions are absent, return `checkpoint_pending: C10`; if the document artifact is absent or stale, return `artifact_missing: post_action_doc`. In either case, do not create, move, rotate, prune, or index anything. Never infer C10 approval from the report, completed row, status, prompt prompt, or claimed autonomous execution.
2. **Establish or recover archive identity.** Before hashing a live session or deriving any target or rotation plan, scan the activity log for unresolved `event=archive_intended` evidence for this Jira key. An intent remains unresolved until both its matching `event=archive_cache_removed archive_id=<id>` and terminal `event=run_complete archive_id=<id>` exist; `reuse_index_appended` or cache removal alone does not resolve it. When exactly one unresolved intent exists, reuse its `archive_id`, target, and rotation path unchanged regardless of whether the live session still exists; never recompute them from the retry timestamp or current archive-tree shape. Require either the live session or the recorded current target to have that exact hash, and require any already-created recorded rotation file to agree with the persisted plan. If the evidence conflicts, neither candidate has the expected hash, or multiple unresolved intents exist, return `archive_recovery_corrupt` without changing anything. Only when no unresolved intent exists may a new operation compute `archive_id` as lowercase SHA-256 of the live session's exact bytes, choose the current target `<archive_dir>/<JIRA-KEY>/session.md` and, when that target holds a prior run, choose one deterministic rotation path `session.<yyyyMMddTHHmmssZ>.md` from the current operation's UTC intent timestamp. Append one idempotent `event=archive_intended archive_id=<id> target=<target> rotation=<path|none>` before changing the index or archive tree. A missing live session with no unresolved intent is `archive_recovery_corrupt`.
3. **Prepare and verify the reuse index while the source is recoverable.** Ensure the archive directory exists. Build the exact current-run `index_entry` from the completed Reuse Digest using the documented line format; point its persisted rotation link to the persisted rotation filename when rotation is required, and add exactly that one line for this `archive_id` pointing to the current target. Create the index if absent and scrub secrets/PII (PII-1). Re-read it and require the complete planned line set plus exactly one byte-for-byte match for `index_entry` before rotating or moving a file. If preparation fails while the live session still exists, return `reuse_index_append_failed`; the live source remains in place for an identical retry.
4. **Promote idempotently.** If the persisted archive path is not `<none>`, rename the prior target to that exact path only when the rotation file is absent; if it is already present with the expected prior content, do not rotate again. Move the live session to the current target only when the target does not already contain `archive_id`. On retry after a partial move, accept the target only when its hash equals `archive_id`; any different target hash is `archive_recovery_corrupt` and blocks without overwrite.
5. Append one idempotent `event=archive_promoted archive_id=<id> target=<target>` through `append-activity` with the persisted `archive_id` and current target only after that target exists and its SHA-256 equals `archive_id`; retain this successful comparison as `target_hash_verified: true`. Re-read the reuse index and require exactly one byte-for-byte `index_entry` match resolving to that target plus the correct rotated prior link when applicable; retain this as `index_entry_verified: true`. If final index verification fails after promotion, append the documented failure through the same archive-lifecycle mode and return `reuse_index_append_failed`; a retry resumes from the persisted intent and promoted archive rather than requiring the removed live file or rotating again.
6. Only after the promoted hash and final index both verify, append one idempotent `event=reuse_index_appended archive_id=<id> index=<reuse_index_file>` through `append-activity` with the same persisted archive anchor. Then remove the now-empty `<session_dir>/<JIRA-KEY>/` directory and verify that directory is absent. If unexpected residue remains, append one idempotent `event=archive_cache_not_empty archive_id=<id> reason=unexpected_residue` through the same archive-lifecycle mode and return `archive_cache_not_empty` instead of deleting unknown content; the archive remains unresolved for an identical retry. After absence verifies, append one idempotent `event=archive_cache_removed archive_id=<id>` through the same archive-lifecycle mode. Re-read the activity log and require exactly one matching `archive_intended`, `archive_promoted`, `reuse_index_appended`, and `archive_cache_removed` event for this `archive_id`; retain these as `archive_events_verified: true` and `cache_removed: true`. Only after those checks pass, append one idempotent `event=run_complete archive_id=<id> status=COMPLETE` through the same verified archive anchor. Re-read the log and require exactly one matching terminal event; retain this as `run_complete_verified: true`. Leave `<session_dir>/setup-validation.md` untouched.
7. `session_archived`, `reuse_index_updated`, and a `run_complete` event without the matching `archive_id` are unregistered shorthand. Never emit them, translate them into the required lifecycle events, or return a successful run attestation from them. A promoted archive and index entry may coexist temporarily with the live cache only as an unresolved archive intent; while the exact cache directory still exists, return an archive blocker and never report completion.
8. Do not prune retention artifacts inside `archive`. Pruning is the separate `prune-expired` operation below and never changes whether this archive completed. A pruning failure therefore cannot reopen or corrupt a resolved archive intent.
9. Return the following exact attestation only after steps 2-6 succeed; every boolean is derived from its named read-back check, never from caller input or narration:

```yaml
archive_complete: true
archive_id: "<lowercase-sha256>"
target: "<archive-session-path>"
target_hash_verified: true
index: "<reuse-index-path>"
index_entry: "<exact verified current-run line>"
index_entry_verified: true
archive_events_verified: true
cache_removed: true
run_complete_verified: true
```

Archived sessions and logs are **local-only** (the `artifacts/sessions/` and `logs/` trees are gitignored). Archive never removes a current activity log; only the separate `prune-expired` operation may remove an age-proven expired log. Any absent or false field means archive is incomplete and must return the applicable blocker instead of this payload.

### prune-expired

Run only after `archive` returns its complete attestation, or as an explicit maintenance operation. It never requires or recreates a live story session and never changes an archive attestation. `pipeline.archive_retention_days` governs archived sessions, their immutable reports, rejected report candidates, and activity logs. Unknown-age and in-window artifacts are never touched.

1. Maintain an append-only global journal at `<log_dir>/prune.log`; create it on first maintenance run. Apply the same prefix-preserving append/read-back discipline as `append-activity`. This journal is the durable anchor for activity-log pruning because the target log cannot record completion after it is deleted. Determine age only from trusted lifecycle evidence: the current archived `session.md` uses its matching `archive_cache_removed` event timestamp; a rotated `session.<timestamp>.md` uses the persisted rotation timestamp from the matching later `archive_intended` event and requires the filename timestamp to agree; a report referenced by a retained session inherits that session's age and is never evaluated independently; an unreferenced rejected report uses its create-only `started_at` from the matching completed handoff row in a retained session or prune journal. Before selecting any session for pruning, inventory every rejected report whose age authority exists only in that session and append/read-back one immutable `report_age_evidence` journal row in dependency order with its source path, content hash, handoff id, and authoritative `started_at`. Do not prune the session unless every such row is verified; this preserves report age authority after the session disappears. Filesystem timestamps, index display dates, report prose, and session `Updated` are never age authority. Missing, duplicate, conflicting, future-dated, or unparsable evidence means unknown age and preserves the artifact. Eligibility requires `now - authoritative_timestamp > archive_retention_days` using UTC; equality remains in-window.
2. For each eligible archived `session.md` or `session.<timestamp>.md`, compute `prune_id` as lowercase SHA-256 of its exact bytes. Append idempotent `prune_intended` to the story activity log through `append-activity(prune_id, prune_target)`, recording the validated report path and index-entry hash. Atomically remove that session's index entry and verify the planned index, then move the session to `.pruning-<prune_id>` in the same directory. Delete the report only after scanning every retained live session and other tombstone proves none references it. Delete this tombstone last, append `prune_completed` through the unresolved-intent exception, and verify exactly one intent/completion pair. A retry resumes the one unresolved id from the observed boundary.
3. For each eligible unreferenced rejected report, append `report_prune_intended` to the global journal with its path, age evidence, and content hash; delete only that file, verify absence, then append `report_prune_completed`. Resume unresolved journal intents idempotently.
4. For each eligible `activity.log`, append `log_prune_intended` to the global journal with the path, latest parseable timestamp, and content hash. Move it to deterministic `<path>.pruning-<hash>`, verify the original path absent and tombstone hash, delete the tombstone, then append `log_prune_completed`. A retry resolves the journal intent from the original/tombstone state and never recreates or truncates the old log.
5. Return counts and exact completed prune ids only after every selected intent is resolved. A conflict or failed read-back returns `prune_recovery_corrupt` and leaves unrelated artifacts untouched.

## Back-Compat (v1 → v2 → v3 → v4 → v5 → v6 → v7 → v8)

Older **schema-1** sessions have no `## Stage Status` table and a single `Last Approved Checkpoint: <Cx>` line. Read them as follows:

1. Map each historical stage to `complete` when its `checkpoint` is at or before `<Cx>` in `step` order; the rest are `not_started`. (For shared gates: `qa`/`tests` at C4 and `split` at C8b follow their own `step` order.) Never derive the schema-5 `review` stage or C8c from a v1 checkpoint, including an old C9 or C10: when `split` maps complete, initialize `review` as `in_progress` with C8c pending; otherwise initialize it as `not_started`.
2. Set `source_ref` to `-` (unknown) for the derived-complete stages — so the first full run treats them as fresh unless a real input change is detected.
3. After explicit configuration adoption, apply every remaining migration through schema 8 and persist the result on the next approved `write-stage` (add the configuration fingerprint, Stage Status table, canonical Checkpoint Ledger table, and fixed artifact subsections). Do not rewrite a v1 file on a pure read.

**Schema 2 → 3.** A schema-2 session (stage table present, `Schema: 2`, no `### Reuse Digest`) is read as-is; on the next approved `write-stage`, set `Schema: 3` and add an empty `### Reuse Digest` subsection. The change is purely additive — no stage rows, `source_ref` values, or ledger lines change.

**Schema 3 → 4.** A schema-3 session has no `Configuration Fingerprint`. `init` returns `configuration_changed` until the developer explicitly adopts the current verified fingerprint. Adoption sets `Schema: 4`, records the fingerprint, and marks every completed stage stale. Never infer that historical work used the current configuration.

**Schema 4 → 5.** Schema 5 adds the controller-owned `review` stage, C8c ledger line, and `### Human Review` artifact. Apply this migration in memory on read and persist it on the next approved write:

1. Insert the `review` row in registry order and add C8c as `pending`; never synthesize `review complete`, a `decision-reply`, or a legacy approval token.
2. If `split` is not complete, set `review` to `not_started`. If `split` is complete, set `review` to `in_progress`, set `Active Checkpoint: C8c`, and initialize `### Human Review` to `pending`.
3. If `docs` was already complete under schema 4, mark it `stale` and set `Status: IN_PROGRESS`; the developer must explicitly complete C8c before that report can be accepted or archived under schema 5.
4. Set `Schema: 5` only when the migrated snapshot contains the new row, ledger line, and artifact exactly once. Preserve every existing stage result, checkpoint decision, source reference, manifest, and side-effect entry byte-for-byte otherwise.

**Schema 5 → 6.** Schema 6 adds `### Agreement Revision History`. Insert an empty `none` history in memory on read and persist it only on the next authorized write. Never infer a historical revision from changed Jira text, chat history, or overwritten understanding. Preserve the original C1b approval and every existing artifact unchanged.

**Schema 6 → 7.** Schema 7 adds reactive `integration` / C8d, `### Integration PR`, and `### Integration Side-Effect Ledger`.

1. Insert the integration stage row in registry order and C8d as pending. Never infer C8d approval or a final integration PR from C8c prose, existing feature commits, or remote state.
2. Read the canonical Subbranch Manifest. For direct delivery, set integration `not_started`, Integration PR to `not applicable for direct delivery`, and leave C8d pending with no decision or milestone. Existing direct C8c completion remains valid.
3. For stacked delivery whose review/C8c is incomplete, set integration `not_started` and Integration PR `pending stacked C8c`.
4. For stacked delivery whose C8c was previously approved under schema 6 with feature-to-develop merge evidence embedded in Human Review, preserve that evidence but do not migrate it. Mark review complete, initialize integration `in_progress`, move the integration identity into Integration PR as `legacy evidence awaiting C8d reconciliation`, set C8d pending, mark docs stale, and require explicit C8d completion after remote read-back. This fail-closed migration avoids silently approving a new checkpoint.
5. Add the empty canonical Integration Side-Effect Ledger and set `Schema: 7` only when all new rows and headings exist exactly once. Preserve all other decisions, milestones, artifacts, and side-effect identifiers.

**Schema 7 → 8.** Schema 8 adds `### Loop Budget Ledger`. Insert one empty canonical table in memory on read and persist it only on the next authorized mutation. Historical retry counts cannot be reconstructed safely from handoff rows, stage timestamps, regression prose, activity events, or side-effect attempts, so migration records no rows and never claims prior budget consumption. Set `Schema: 8` only when the new heading and table exist exactly once; preserve all earlier state and evidence byte-for-byte.

**Schema-6 ledger normalization.** Older or model-authored schema-6 sessions may contain the former list-form ledger instead of the canonical Markdown table. Parse either representation on read, but normalize it to the five-column table on the next authorized mutation. Preserve each uniquely valid checkpoint status, registered decision evidence, milestone state, and timestamp. If list and table forms coexist or evidence conflicts, return `checkpoint_ledger_corrupt`; never merge by choosing the more advanced-looking value. A canonical table that has a complete stage paired with a pending checkpoint is already corrupt evidence, not a harmless formatting variant: block normal progression and require explicit recovery from the verified activity and Jira milestone records.

## Constraints

- Run `init` first on every run; never let `session.md` or `activity.log` be created lazily.
- Require the verified configuration fingerprint on `init`; never create, resume, or mutate stage progress across a fingerprint mismatch without explicit adoption.
- Flush every mutating operation to disk immediately in a single `edit` write — never buffer, batch, or defer session or activity-log updates.
- Never advance a stage to `complete` without `approve-checkpoint` validating an exact registered semantic `advance` reply from the entire current developer message. Architecture/C0b, intake/C1a, and refine/C1b are separate decisions and completions.
- Never skip a stage whose state is `stale`, `in_progress`, or `not_started`. `resume_split_publish` is a continuation of the existing C8b-authorized `split`, not a skip or restart.
- Never run a stage whose `needs` are unsatisfied — escalate per `precondition_policy` instead.
- Never persist rejected work as resumable; overwrite that stage on the next approved write.
- Never write PII, secrets, tokens, or credentials into `session.md` or `activity.log` (PII-1).
- Every externally visible subbranch-extraction mutation has one stable row in `### Subbranch Side-Effect Ledger`: persist `intended` before acting, then monotonically update that same row to `partial` or `complete` after success or reconciliation; an explicitly accepted revision may transition a recorded row to terminal `abandoned` or `superseded` without deleting its external identifier. Only `update-side-effect` may mutate these rows.
- Every final integration PR create/update has one stable row in `### Integration Side-Effect Ledger`. Only `update-integration-side-effect` may mutate these rows; persist intended before acting and reconcile partial or complete immediately afterward.
- Every actual nested-agent invocation has one stable row in `### Subagent Handoff Ledger`: `begin-subagent-handoff` creates a `started` row and its threshold-governed INFO enter event; only `complete-subagent-handoff` terminates that row and appends its threshold-governed INFO/WARN/ERROR return. Never infer a row from a stage enter event, proceed, retry, approve, or archive with an unpaired handoff.
- Every session-managed retry has one stable row in `### Loop Budget Ledger`. Only `consume-loop-budget` may append one, and it must do so before retry work begins. Reusing the same durable attempt identity is idempotent; a new identity at the cap blocks. Never reset or reconstruct counts on resume, schema migration, stage staleness, review restart, or configuration adoption.
- `## Artifacts` is a fixed set of named subsections (one each). Writing an artifact **replaces** the body under its heading in place — never duplicate a `### <subsection>` heading (for example a second `### Test Report`) and never append a fresh block below the existing one. Every write rewrites the whole file as one well-formed document: exactly one `# Session:` header and one of each subsection.
- **Header, Stage Status, Checkpoint Ledger, and Artifacts are one snapshot** — every write leaves them mutually consistent, never lazily trailing the stage table. The header's `Active Stage` matches the current `in_progress` (or, if none, the furthest `complete`) stage, and `Active Checkpoint` is a checkpoint **of** that stage (the two-checkpoint `split` stage's live sub-gate at its completion gate). Stage Status `checkpoint` column stays at each stage's static registry value; the ledger is exactly one five-column Markdown table with one keyed data row for every registry gate in step order, including both sub-gates of the two-checkpoint `split` stage, with no duplicate or unknown rows; each checkpoint row is at least as advanced as its completion state. A `complete` stage row has a `status: approved` with registered decision evidence and timestamp — both rows for the two-checkpoint `split` stage; an `in_progress` stage → its live gate remains pending unless it is the authorized C8b exception); and every `complete` stage that owns an artifact shows real content, not its template placeholder (`(not yet captured)`, or `not run` for a `complete` `reextract`).
- A `session.md` write and its paired `activity.log` append form one **recoverable transition**: `mark-in-progress` pairs with the Stage `event=enter`, each handoff row pairs with its Subagent enter/return events, and `write-stage` pairs with `event=approved`. Stage events use `transition=<updated timestamp>` as their retry id; handoff events use `handoff_id`. Full-run `run_complete` belongs only to successful `archive`; single-stage docs appends its explicit non-archive terminal event after C10. Durable state leads append. If append fails, block and repair idempotently before narration or progression. `pipeline.log_level` gates only whether the composed line clears the threshold, never whether the owning operation is valid.
- The activity log is **append-only** and **written only by deva** — never rewrite it, and never let another agent feed it.
- Never wipe `activity.log` merely because a live session is archived or discarded. Like archived sessions, it is retained for `pipeline.archive_retention_days`; only an age-known log older than that TTL is prunable.
- Only `discard(JIRA-KEY, confirmed=true)` may remove a live session. It preserves setup validation, activity logs, archives, and the reuse index, and it records the fixed discard event before deletion.
- On **full-run completion**, archive through the resumable `archive` state machine: persist an `archive_id` and deterministic rotation path, prepare and verify the index while the live session is recoverable, promote and hash-verify the session, verify the final index, then remove only the empty cache directory. Never rotate or move the same `archive_id` twice. Archived sessions are **local-only** (the configured archive tree is gitignored); only age-known artifacts older than that TTL are prunable, never newer ones. Only a **discard** (an abandoned story) deletes a live session outright; it does not itself delete the activity log or any prior archive.
- The `archive` operation maintains one line per completed story in the **reuse index** at `pipeline.reuse_index_file` — links are updated on rotation, expired entries are pruned with their archives, and all content is scrubbed of secrets/PII (PII-1). Prior-art lookups scan this index first, then open the linked archive. Index preparation and final verification are both required: `reuse_index_append_failed` blocks run completion, while the persisted `archive_intended` / `archive_promoted` identity lets a retry continue from either the live source or the matching promoted archive without data loss or repeated rotation.
- The **Reuse Digest** `Tags` field follows the overlay's canonical tag vocabulary when one is pinned (pick from it first; freeform only when nothing fits), and carries a `Related Jira` list. Treat Files changed, Commands run, Gotchas, and Links as the leak-prone fields and scrub every embedded secret or host before writing (PII-1).

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
