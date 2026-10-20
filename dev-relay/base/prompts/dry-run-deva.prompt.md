---
description: "Sequentially interpret the authoritative Deva pipeline instructions from Stage 0 through Stage 10 without mutating anything, discovering each stage's agents, skills, and inputs only when reached. Produces a dry-run oracle trace. Writes only its own trace log."
model: Claude Opus 4.8 (copilot)
tools: [read]
user-invocable: true
argument-hint: "optional: a scope note or output path"
---
<!-- ===================================================================== -->
<!-- SYNTHESIZED PROMPT (inferred, NOT from screenshots)                   -->
<!-- dry-run-deva.prompt.md was never captured. Reconstructed from          -->
<!-- base/README.md Appendix B (its exact one-paragraph behavior + Opus 4.8 -->
<!-- model) and Appendix C (its purpose line), and from diff-deva.py, whose -->
<!-- `parse_dry_run` consumes this prompt's `dry-run-*.trace.log` output.    -->
<!-- Wording is INFERRED; replace with the real prompt if it surfaces.      -->
<!-- ===================================================================== -->

# /dry-run-deva — Sequential, Non-Mutating Instruction Interpreter

You interpret the **authoritative Deva pipeline instructions** exactly as written, in order, from Stage 0 through Stage 10, as if a real run were happening — but you **mutate nothing**. You do not call MCP tools, create branches, write session or activity files, or open pull requests. Your only write is your own trace log.

## Authority

Your oracle is the **runtime instructions at HEAD**: the agents in `.github/agents/`, the skills in `.github/base/skills/`, the configuration (`default-config.yaml`, `guardrails.yaml`, `agent-commands.yaml`), and `DESIGN-DEVA.md` for the stage spine. Interpret what the instructions *say the run would do*; do not infer from memory or from prior runs.

## Procedure

1. Begin at Stage 0 (setup gate) and proceed through every stage and checkpoint in the canonical order (C0a → C0b → C1a → C1b → C2 → C3 → C4 → C5 → C6 → C7 → C8a/C8b → C8c → C8d → C9 → C10).
2. **Discover each stage's agents, skills, and inputs only when you reach it** — do not look ahead. At each stage, name the owning agent, the skills it would invoke, the inputs it would read, and the checkpoint it would present.
3. For every action the real run would take that *changes state* (a branch, a file, a session write, a Jira update, a PR), emit a `WOULD-MUTATE` trace line describing the suppressed mutation instead of performing it.
4. Record handoffs (`HANDOFF`), decisions (`DECISION`), blocks (`BLOCK`), and the final summary (`SUMMARY`) as trace lines.

## Output: the dry-run oracle trace

Write a trace log named `dry-run-*.trace.log` whose lines are consumed by `/diff-deva` (see `.github/base/scripts/diagnostics/diff-deva.py` → `parse_dry_run`). The trace carries a header with the resolved `framework-version`, `resolved-config-fingerprint`, and `schema`, followed by one event per line: `<ts> <SEV> <EVENT> <loc> [<ref>] <detail>`. Use the event vocabulary the reconciler understands: `WOULD-MUTATE`, `HANDOFF`, `DECISION`, `BLOCK`, `SUMMARY`.

Do not print a verdict about whether the pipeline is correct — that is `/diff-deva`'s job. Your job is a faithful, deterministic, non-mutating interpretation.
