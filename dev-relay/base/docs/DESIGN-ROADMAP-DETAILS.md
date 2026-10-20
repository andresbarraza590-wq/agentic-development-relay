<!-- ===================================================================== -->
<!-- SYNTHESIZED DOCUMENT (inferred, NOT from screenshots)                 -->
<!--                                                                       -->
<!-- DESIGN-ROADMAP-DETAILS.md was never captured. base/README.md confirms  -->
<!-- it exists ("Deva and Do It Roadmap Details — Original expanded design  -->
<!-- with detailed rationale, ownership boundaries, checkpoint impacts, and  -->
<!-- acceptance criteria"). This is reconstructed from that description plus  -->
<!-- DESIGN-ROADMAP.md, DESIGN-DEVA.md, and DESIGN-DO-IT.md. Wording and the  -->
<!-- specific acceptance criteria are INFERRED, not the original text. These  -->
<!-- describe FUTURE direction, not current runtime behavior. Replace with   -->
<!-- the real file if it surfaces.                                           -->
<!-- ===================================================================== -->

# Deva and Do It Roadmap — Details

> **Future direction, not current behavior.** Runtime behavior remains governed by
> the resolved configuration and the reached agent, skill, and prompt instructions.
> See [Design of Deva](DESIGN-DEVA.md) for the implemented architecture, and
> [Deva and Do It Roadmap](DESIGN-ROADMAP.md) for the concise overview.

## Table of Contents

- [Scope](#scope)
- [Ownership Boundaries](#ownership-boundaries)
- [The Deva Orchestration Kernel](#the-deva-orchestration-kernel)
- [Unified Routing](#unified-routing)
- [Checkpoint Impacts](#checkpoint-impacts)
- [Replay-Safe Workflow State](#replay-safe-workflow-state)
- [Specialist Handoffs](#specialist-handoffs)
- [Acceptance Criteria](#acceptance-criteria)
- [Risks and Mitigations](#risks-and-mitigations)
- [Base Sources](#base-sources)

## Scope

This document expands the six target-design goals from [the roadmap](DESIGN-ROADMAP.md) into rationale, concrete ownership boundaries, per-checkpoint impacts, and testable acceptance criteria. It covers both Deva (the orchestrator) and Do It (the guided router), because the two share the specialist roster and should converge on one routing and checkpoint model.

## Ownership Boundaries

The guiding rule: **each stage, artifact, and decision has exactly one owning agent.** Today some logic is duplicated between Deva and the specialists (for example, precondition knowledge and session-write details). The target state:

- **Deva** owns: stage sequencing, session lifecycle, checkpoint presentation and relay, staleness/discard decisions, and high-risk decomposition decisions. It does not contain stage-specific implementation logic.
- **Each specialist** owns: its stage's preconditions, its single declared output, and its own effects (files, reports, caches, Git, Jira, PRs). A specialist is runnable stateless (via Do It) and stateful (via Deva single-stage) with identical behavior.
- **Do It** owns: menu rendering and routing only — never SDLC logic, sessions, or checkpoints.
- **Config** (`guardrails.yaml`, `default-config.yaml`, `agent-commands.yaml`) remains the single source of policy; `guardrails.yaml` and `default-config.yaml` stay install-protected.

## The Deva Orchestration Kernel

Goal: shrink Deva to a thin kernel. Rationale: a large orchestrator concentrates risk and makes overlays harder. Approach: push each stage's preconditions and output rules down into the owning specialist, so Deva calls a uniform specialist contract and records the result. The kernel keeps only routing, session bookkeeping, checkpoint relay, and decomposition.

## Unified Routing

Today Do It routes stateless specialists directly and routes stateful selections through Deva single-stage, while Deva also runs the full pipeline. The target: one routing model so a stage reached via Do It (stateful), Deva single-stage, or the full pipeline executes through the same path and preconditions. Do It stays thin; the shared model lives behind Deva's kernel.

## Checkpoint Impacts

The checkpoint spine is unchanged (C0a…C10). What changes is uniformity:

- **Presentation:** every checkpoint renders with the same shape and a fixed registered-reply vocabulary (advance vs revise), so relayers (Do It, overlays) never have to special-case a checkpoint.
- **C8c / C8d:** human review, approval, and merge authority are preserved exactly. The reactive C8d integration trigger stays owner-exclusive to the integration publisher; the roadmap only standardizes how its checkpoint is presented and relayed.
- **Relay:** a returned checkpoint always ends the routing turn; no relayer may synthesize a decision reply.

## Replay-Safe Workflow State

Rationale: resume-after-interruption and single-stage re-runs must never double-write or corrupt a session. Approach: model session writes as idempotent records keyed by stage and attempt, so re-applying a stage reconciles rather than appends. This is the foundation step because every other change depends on safe resume.

## Specialist Handoffs

Rationale: handoffs re-transfer context and cost tokens/latency. Approach, once ownership is clean: pass each specialist only its declared inputs and let it read shared state through the session record rather than through re-narrated context, reducing both the number of handoffs and the payload per handoff.

## Acceptance Criteria

Inferred, testable criteria for "done":

1. Re-running any single stage twice produces an identical session record (idempotent; no duplicate activity entries).
2. A given stage behaves identically whether reached via Do It (stateful), Deva single-stage, or the full pipeline (same preconditions, same output, same checkpoint).
3. Deva contains no stage-specific implementation logic; removing any one specialist disables exactly one stage and nothing else.
4. Every checkpoint renders with the same shape and the same registered-reply vocabulary.
5. The branch model and C8c/C8d human authority are unchanged and still enforced (including by the optional Git hooks).
6. Measured handoff count and per-handoff context size for a representative story are lower than the current baseline.

## Risks and Mitigations

- **Behavior drift during migration** — mitigate by migrating one stage at a time behind unchanged external behavior, with `/diff-deva` reconciling each migrated run against the instruction-derived oracle.
- **Session-format breakage** — introduce replay-safe records behind current writers first, with a compatibility read path.
- **Overlay incompatibility** — keep the menu-assembly and config-overlay contracts stable; only internal ownership moves.

## Base Sources

- `.github/README.md` — "Future Work".
- `.github/docs/DESIGN-ROADMAP.md` — concise overview and delivery sequence.
- `.github/docs/DESIGN-DEVA.md` — current pipeline, stages, and checkpoints.
- `.github/docs/DESIGN-DO-IT.md` — current routing model.

<!-- ===== END SYNTHESIZED DOCUMENT ===== -->
