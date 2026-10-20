<!-- ===================================================================== -->
<!-- SYNTHESIZED DOCUMENT (inferred, NOT from screenshots)                 -->
<!--                                                                       -->
<!-- DESIGN-ROADMAP.md was never captured. base/README.md "Future Work"    -->
<!-- confirms it exists ("Deva and Do It Roadmap — Concise target-design   -->
<!-- overview, checkpoint journey, priorities, and delivery sequence") and  -->
<!-- lists the six target-design goals reproduced below. Everything here is  -->
<!-- reconstructed from that paragraph plus DESIGN-DEVA.md / DESIGN-DO-IT.md -->
<!-- structure; wording and the delivery-sequence specifics are INFERRED,   -->
<!-- not the original. These describe FUTURE direction, not current runtime -->
<!-- behavior. Replace with the real file if it surfaces.                   -->
<!-- ===================================================================== -->

# Deva and Do It Roadmap

> **Future direction, not current behavior.** This document describes a planned
> target design. Runtime behavior remains governed by the resolved configuration
> and the reached agent, skill, and prompt instructions. For the implemented
> architecture, see [Design of Deva](DESIGN-DEVA.md) and [Design of Do It](DESIGN-DO-IT.md).

## Table of Contents

- [Why a Target Design](#why-a-target-design)
- [Target-Design Goals](#target-design-goals)
- [The Checkpoint Journey](#the-checkpoint-journey)
- [Priorities](#priorities)
- [Delivery Sequence](#delivery-sequence)
- [Non-Goals](#non-goals)
- [Base Sources](#base-sources)

## Why a Target Design

The current pipeline works and is staged and checkpointed, but responsibility is spread across a large Deva orchestration surface, Do It routing, and the specialists. The target design preserves the staged-checkpoint approach while tightening ownership boundaries and making workflow state replay-safe, so the framework is easier to reason about, extend with overlays, and recover after interruption.

## Target-Design Goals

The six goals carried in the README's Future Work section:

1. **Clearer ownership boundaries** — each stage and artifact has exactly one owning agent, with no overlapping responsibility between Deva and its specialists.
2. **A smaller Deva orchestration kernel** — move stage-specific logic out of Deva into the specialists, leaving Deva a thin router/bookkeeper.
3. **Unified Do It routing** — one routing model shared by Do It and Deva single-stage runs, so a stage behaves identically whichever entry point reached it.
4. **Consistent checkpoint presentation** — every checkpoint renders with the same shape, decision vocabulary, and relay rules.
5. **Replay-safe workflow state** — session state that can be re-applied idempotently so a resumed or re-run stage never double-writes or corrupts the session.
6. **More efficient specialist handoffs** — fewer, cheaper handoffs with less context re-transfer between Deva and specialists.

## The Checkpoint Journey

The target design keeps the existing checkpoint spine (C0a setup → C0b architecture → C1a intake → C1b refine → C2 branch → C3 implement → C4 QA+tests → C5 acceptance → C6 push → C7 regression → C8a/C8b split → C8c review → C8d integration → C9 re-extraction → C10 docs/archive) but makes each checkpoint presentation uniform: one decision prompt, a fixed registered-reply vocabulary, and identical relay behavior through Do It and Deva. The journey itself does not change; its *presentation and state handling* become consistent.

## Priorities

1. **Replay-safe state first** — it underpins safe resume and is the prerequisite for shrinking the kernel.
2. **Ownership boundaries** — disentangle Deva from specialist logic.
3. **Unified routing and checkpoint presentation** — collapse the two entry points onto one model.
4. **Handoff efficiency** — optimize once boundaries are clean.

## Delivery Sequence

A backward-compatible, incremental sequence (each step shippable on its own):

1. Introduce replay-safe session records behind the current writers (no behavior change).
2. Migrate one stage at a time to owner-exclusive logic, de-scoping the Deva kernel as each lands.
3. Unify Do It and Deva single-stage routing onto the shared model.
4. Standardize checkpoint presentation and the registered-reply vocabulary across all checkpoints.
5. Optimize handoffs (reduced context re-transfer) once ownership is clean.

## Non-Goals

- Changing the branch model (`develop` → `feature/<user>/<PARENT-JIRA>` → `feature/<user>/story/<PARENT-JIRA>`).
- Changing the human-review and merge-authority rules at C8c/C8d.
- Replacing <BASE_ENGINEERING_ECOSYSTEM> compatibility or the MCP integrations.

## Base Sources

- `.github/README.md` — "Future Work" (the six goals).
- `.github/docs/DESIGN-DEVA.md` — current pipeline and checkpoints.
- `.github/docs/DESIGN-ROADMAP-DETAILS.md` — expanded rationale and acceptance criteria.

<!-- ===== END SYNTHESIZED DOCUMENT ===== -->
