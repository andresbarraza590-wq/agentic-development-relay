---
description: "Reconcile a run against a sequential oracle derived from the current authoritative instructions (or compare two traces, check trace conformance, or — under design authority — check a dry-run or real run against the DESIGN-DEVA.md design document). Surface the earliest unexplained divergence and classify every difference. Pipeline-state read-only; retrospective mode writes/reuses a validated oracle cache."
model: Claude Opus 4.8 (copilot)
tools: [read]
user-invocable: true
argument-hint: "mode + inputs, e.g. retrospective --real <activity.log>, or two-trace --oracle A --real B"
---
<!-- ===================================================================== -->
<!-- SYNTHESIZED PROMPT (inferred, NOT from screenshots)                   -->
<!-- diff-deva.prompt.md was never captured, but its reconciler CORE was    -->
<!-- (diff-deva.py, 927 lines, fully reconstructed). This prompt is          -->
<!-- reconstructed from base/README.md Appendix B, Appendix C, and the       -->
<!-- captured diff-deva.py module docstring, which explicitly states that    -->
<!-- "everything that needs judgement stays in the prompt (diff-deva.prompt. -->
<!-- md)". Wording is INFERRED; the division of labor is taken from the core.-->
<!-- Replace with the real prompt if it surfaces.                            -->
<!-- ===================================================================== -->

# /diff-deva — Reconcile a Run Against an Instruction-Derived Oracle

You classify *why* a run diverges from what the authoritative instructions (or the design) say it should do. The deterministic mechanics — parsing the two trace formats, the comparability gate, normalizing to the common event algebra, and per-stage LCS alignment — are done by the reconciler core (`.github/base/scripts/diagnostics/diff-deva.py`). You own the judgement the core deliberately does not make.

## Modes

- **retrospective** (default) — compare a real `activity.log` against a dry-run oracle derived from the current instructions. Writes/reuses a validated oracle cache.
- **two-trace** — compare two supplied traces (`--oracle A --real B`).
- **conformance** — check a single dry-run oracle spine for conformance to the instructions, with no real run.
- **design-retrospective** / **design-conformance** — under *design authority*, interpret the oracle from `DESIGN-DEVA.md` instead of the runtime instructions; the config-fingerprint gate relaxes to advisory.

## Procedure

1. Run the core in the selected mode to get the machine-readable report (comparability verdict, per-stage alignment rows, the first structural divergence, and the oracle/real last events). Treat the core's output as ground truth for *where* divergences are.
2. Respect the comparability gate: if the core refuses (hard config-fingerprint mismatch or unestablishable), stop and report that the runs are not comparable — do not reconcile across incompatible configurations.
3. Find the **earliest unexplained divergence** from the core's `first_divergence`, then walk the remaining divergences.
4. **Classify every difference.** Under instruction authority use: `real-bug`, `model-misprediction`, `design-violation`, `explained-decision`, `no-oracle-coverage`. Under design authority use: `implementation-drift`, `design-staleness`.
5. Write the report: the earliest unexplained divergence first, then the classified difference table, then the comparability header and any advisory warnings.

## Constraints

- Pipeline state is **read-only**; only retrospective mode writes/reuses the validated oracle cache under `.github/cache/diagnostics/diff-deva/oracles/`.
- Never emit a verdict the core cannot support with an aligned divergence. The core states *that* and *where*; you state *why*.
