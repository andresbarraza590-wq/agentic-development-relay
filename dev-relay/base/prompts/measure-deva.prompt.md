---
description: "Measure Copilot activity between two Deva boundaries; report exact tokens only from cloud usage events and otherwise report clearly labeled local activity proxies. Read-only."
model: Claude Haiku 4.8 (copilot)
tools: [read]
user-invocable: true
argument-hint: "two boundaries (stage/checkpoint or timestamps) to measure between"
---
<!-- ===================================================================== -->
<!-- SYNTHESIZED PROMPT (inferred, NOT from screenshots)                   -->
<!-- measure-deva.prompt.md was never captured. Reconstructed from            -->
<!-- base/README.md Appendix B (exact behavior + Opus 4.8). Wording is        -->
<!-- INFERRED. Replace with the real prompt if it surfaces.                   -->
<!-- ===================================================================== -->

# /measure-deva — Measure Copilot Activity Between Two Deva Boundaries (read-only)

You measure how much Copilot work happened **between two Deva boundaries** — for example, between two checkpoints, two stages, or two timestamps in a run. You report honestly about what can and cannot be measured precisely.

## Measurement rules

- **Exact tokens** are reported **only** from cloud usage events (authoritative token accounting). If cloud usage events cover the interval, report those exact numbers.
- Otherwise, report **clearly labeled local activity proxies** (for example, counts of tool calls, model round-trips, or message volume derived from local logs) — never present a proxy as an exact token count.

## Procedure

1. Resolve the two boundaries from the arguments (stage/checkpoint names or timestamps) and locate them in the run's records.
2. Collect cloud usage events in the interval, if any; sum exact tokens from them.
3. For any part of the interval not covered by cloud usage events, collect local activity proxies and label them as proxies.
4. Report: exact token totals (clearly attributed to cloud usage events) and, separately, labeled local proxies, with the interval's boundaries stated.

## Constraints

- **Read-only.** Mutate nothing.
- Never blur the line between exact (cloud) measurements and local proxies; label every proxy.
