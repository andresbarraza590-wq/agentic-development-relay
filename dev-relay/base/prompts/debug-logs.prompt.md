---
description: "Correlate a story's activity.log, session.md, and Copilot debug logs into one time-sequential run timeline — pipeline events, end-state, and raw trace woven together. Read-only."
model: Claude Sonnet 4.8 (copilot)
tools: [read]
user-invocable: true
argument-hint: "a Jira key (optional; else the latest run)"
---
<!-- ===================================================================== -->
<!-- SYNTHESIZED PROMPT (inferred, NOT from screenshots)                   -->
<!-- debug-logs.prompt.md was never captured. Reconstructed from             -->
<!-- base/README.md Appendix B ("Correlates activity.log, session.md, and    -->
<!-- debug logs into one time-sequential run timeline (read-only)") and      -->
<!-- Appendix C. Wording is INFERRED. Replace with the real prompt if it      -->
<!-- surfaces.                                                                -->
<!-- ===================================================================== -->

# /debug-logs — Unified Multi-Source Run Timeline (read-only)

You reconstruct a **whole story's run** in time order by weaving together its three sources: the pipeline `activity.log`, the `session.md` end-state, and Copilot's raw debug-log trace. The result is one chronological timeline a developer can read to understand the full run, not just a single chat session.

## Inputs

- `.github/logs/<JIRA-KEY>/activity.log` — the Dev Assistant's per-Jira pipeline event log.
- `.github/cache/sessions/<JIRA-KEY>/session.md` (live) or `.github/artifacts/sessions/<JIRA-KEY>/session.md` (archived) — the run's recorded state and checkpoints.
- The Copilot debug-log trace for the run's sessions (via `render-agent-trace.ps1`).

## Procedure

1. Resolve the target: the supplied Jira key, else the most recent run.
2. Parse each source and normalize every event to a timestamp.
3. Merge into one time-sequential timeline, labeling each entry with its source (activity / session / trace) and the stage/checkpoint it belongs to.
4. Summarize the run's end-state from `session.md`, then present the merged timeline, then call out gaps (events in one source with no counterpart in another) and the first failure.

## Constraints

- **Read-only.** Mutate nothing.
- Align by timestamp and stage; do not fabricate ordering where timestamps are missing — mark such entries as unordered.
- For one chat session's trace alone, use `/debug-sessions`.
