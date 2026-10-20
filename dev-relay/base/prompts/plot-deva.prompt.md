---
description: "Chart where a run spends its minutes — per-stage/checkpoint duration and cumulative time for one story's latest completed run, or a box-and-whisker across every completed run. In 'ai' mode, set aside evidenced human-pause samples and disclose each exclusion. Writes self-contained HTML with inline SVG (default output rotates that chart family with --keep)."
model: Claude Sonnet 4.8 (copilot)
tools: [read]
user-invocable: true
argument-hint: "a Jira key, optional mode (ai), and optional --keep / output path"
---
<!-- ===================================================================== -->
<!-- SYNTHESIZED PROMPT (inferred, NOT from screenshots)                   -->
<!-- plot-deva.prompt.md was never captured. Reconstructed from              -->
<!-- base/README.md Appendix B (exact behavior) and Appendix C, which also   -->
<!-- lists a diagnostics/plot-deva.py core (likewise not captured — see      -->
<!-- RECONSTRUCTION-GAPS.md). Wording is INFERRED. Replace with the real      -->
<!-- prompt if it surfaces.                                                   -->
<!-- ===================================================================== -->

# /plot-deva — Chart a Run's Timing (self-contained HTML + inline SVG)

You chart **where a run spends its minutes**. The deterministic rendering is done by the plotter core (`.github/base/scripts/diagnostics/plot-deva.py`, per README Appendix C); you choose the chart, interpret it, and present it.

## Chart families

- **Single run (default):** per-stage and per-checkpoint duration plus cumulative time for one story's **latest completed run**.
- **Across runs:** a box-and-whisker distribution of per-stage/checkpoint duration over **every completed run** for the story.

## Modes

- **default** — use wall-clock durations as recorded.
- **ai** — additionally set aside evidenced **human-pause** samples (time a checkpoint waited on a human) and **disclose each exclusion** explicitly, so the chart reflects agent time rather than human wait.

## Procedure

1. Resolve the target story (supplied Jira key).
2. Read the run timing from the activity log / session records.
3. Choose the chart family (single run vs across runs); in `ai` mode, identify and set aside evidenced human-pause intervals and record each one for disclosure.
4. Render **self-contained HTML with inline SVG** (no external assets), and in `ai` mode include the exclusion disclosures in the output.

## Output

- Writes a self-contained HTML file with inline SVG.
- On default output, rotate the chart family with `--keep` (retain prior charts rather than overwriting).

## Constraints

- Read-only with respect to pipeline state; the only write is the HTML chart file.
- Every excluded sample in `ai` mode must be disclosed; never silently drop time.
