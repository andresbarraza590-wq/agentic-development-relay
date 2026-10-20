<!-- ===================================================================== -->
<!-- SYNTHESIZED DOCUMENT (inferred, NOT from screenshots)                 -->
<!--                                                                       -->
<!-- DESIGN-DO-IT.md was never captured in any reconstruction screenshot.  -->
<!-- base/README.md confirms it exists ("Design of Do It — Authoritative   -->
<!-- design for guided routing, menu behavior, and stateful versus         -->
<!-- stateless execution"). This document is reconstructed from authoritative-->
<!-- sources that WERE captured: do-it.agent.md (the agent's own contract,  -->
<!-- menu, and routing rules), DESIGN-DEVA.md (the pipeline and stages),    -->
<!-- and base/README.md. It aims to match the real design's substance, but  -->
<!-- its wording and structure are inferred and are NOT the original text.  -->
<!-- Replace this file with the real one if a screenshot/source surfaces.   -->
<!-- ===================================================================== -->

# Design of Do It

## Table of Contents

- [What Do It Is](#what-do-it-is)
- [Design Goals](#design-goals)
- [The Menu](#the-menu)
- [Stateful versus Stateless Routing](#stateful-versus-stateless-routing)
- [Routing Rules](#routing-rules)
- [The Four Output Shapes](#the-four-output-shapes)
- [Relationship to Deva](#relationship-to-deva)
- [Overlays and the Menu](#overlays-and-the-menu)
- [Standalone Prompts Are Not Menu Rows](#standalone-prompts-are-not-menu-rows)
- [Base Sources](#base-sources)

## What Do It Is

**Do It** is the friendly front door to the framework. It exists for two situations: a developer who is unsure which agent to use, and a developer who wants a small, focused task without running the full pipeline. Do It renders one fixed, ordered menu of the installed agents, takes the developer's choice, posts one short line, and hands off to the chosen agent. It performs no Software Development Life Cycle (SDLC) work itself and owns no checkpoints, sessions, preconditions, or continuity.

Do It is deliberately *thin*. Every piece of pipeline logic — session writes, precondition checks, staleness decisions, discards, and checkpoint handling — belongs to **Deva** (see [Design of Deva](DESIGN-DEVA.md)). Do It only displays the menu and routes.

## Design Goals

- **One fixed menu, rendered verbatim.** The menu is a single flat, numbered table rendered exactly as written in the Do It agent body — never reordered, grouped, categorized, summarized, or reconstructed from memory. There are no "full pipeline / single stage / specialist" buckets; there is one flat list.
- **Thin routing, no SDLC ownership.** Do It never advances the pipeline, answers a checkpoint, or chains destinations. One developer selection causes exactly one handoff.
- **Predictable output.** Do It's visible output is always exactly one of four shapes (see [The Four Output Shapes](#the-four-output-shapes)).
- **No surprise state.** Running a specialist without a Jira key must never create pipeline state; running one with a Jira key routes through Deva so it is precondition-checked and recorded.

## The Menu

Do It renders one row per developer-selectable agent installed in `.github/agents/` (except Do It itself), in fixed order: base rows first, then team/workspace overlay rows, then personal overlay rows. Internal-only reactive agents (for example, Integration Publisher) are invoked exclusively by Deva and receive no menu row.

| # | You want to... | Routes to | Stage |
| --- | --- | --- | --- |
| 0 | Build a feature from a Jira story (full pipeline) | `deva` | full pipeline |
| 1 | Validate my environment | `setup-validator` | setup |
| 2 | Bootstrap or check architecture context | `architecture-bootstrapper` | architecture |
| 3 | Analyze a Jira ticket only | `story-analyst` | intake (or refine) |
| 4 | Create the feature and story branches | `branch-manager` | branch |
| 5 | Implement a specific change | `implementation-partner` | implement |
| 6 | Review code for bugs and risks | `qa` | qa |
| 7 | Add or repair tests | `tester` | tests |
| 8 | Check acceptance criteria and scope | `acceptance-checker` | acceptance |
| 9 | Verify and push the story branch | `branch-publisher` | push |
| 10 | Run the developer regression loop | `regression-runner` | regression |
| 11 | Prepare review delivery (or refresh it after feedback) | `subbranch-extractor` | split (or reextract) |
| 12 | Generate the story wrap-up doc | `documenter` | docs |

The developer picks a row by number, optionally with a Jira key (for example, `5` or `5 PROJ-1234`).

## Stateful versus Stateless Routing

The presence or absence of a Jira key decides whether a selection is recorded on a story's session:

- **Stateful** — a Jira key is given. The row runs as a single pipeline stage recorded on that story's Deva session, precondition-checked, and checkpointed. Do It routes it through Deva in single-stage mode.
- **Stateless** — no Jira key. The row's agent runs directly, with no Deva story session, checkpoint, or activity record. A stateless specialist may still edit files, write its declared output, cache workspace setup, or perform explicitly authorized external mutations; its own standalone contract governs those effects.

Two rows are special:

- **Row 0** always needs a Jira key and always runs the full pipeline (always stateful).
- **Row 1 (`setup-validator`)** always runs stateless and ignores any Jira key — environment validation is global, not tied to a story, and its PASS result is cached globally.

## Routing Rules

- **Row 0 — always stateful.** Hand off to `deva` for the full pipeline. If no Jira key was given, ask for it in one line, then hand off. Never inspect setup readiness or chain `setup-validator` first — Deva owns the cache precondition and redirects to Row 1 when needed.
- **Any other row, no Jira key — stateless.** Hand off directly to that row's agent; the specialist's standalone contract governs its effects.
- **A base specialist row (2–12), with a Jira key — stateful.** Hand off to Deva in single-stage mode for that row's stage.
- **Row 3 maps to two stages.** Default to `intake`; choose `refine` only when the developer signals the story is already intaken and needs re-confirmation / re-enrichment. If unclear, ask exactly one question and pass exactly one stage to Deva.
- **Row 11 maps to two stages.** Default to `split`; choose `reextract` only when the developer signals a post-review change to an approved delivery. If unclear, ask exactly one question. Do not inspect or infer C8c state in Do It — Deva and the specialist enforce the registry trigger.
- **Row 1** always routes once to `setup-validator`, stateless, ignoring any key; a reusable PASS cache is returned without rerunning checks.

## The Four Output Shapes

Do It's entire visible output is always exactly one of these — never combined, never with extra commentary:

1. **Menu render** — on invocation before a row is picked: render the menu table in full, every row in order, then ask the developer to pick a row on one line.
2. **One-line handoff** — once a row is picked (or named in the invocation): post exactly one short line naming the destination agent and whether the run is stateless or stateful, then hand off with the `agent` tool.
3. **One clarification** — when one routing fact is ambiguous (for example, Row 3 intake-vs-refine or Row 11 split-vs-reextract): ask exactly one concise question and stop.
4. **Relayed checkpoint / question / blocker** — after a handoff returns: surface only the returned text, prefixed with the destination agent's name, and stop. A checkpoint is pending developer input — Do It never answers it, emits a registered decision reply, or invokes another destination.

## Relationship to Deva

Do It and Deva are complementary entry points. Deva is the orchestrator that owns the full pipeline and all session state; Do It is a stateless router in front of the same agent roster. When a selection must be stateful, Do It hands it to Deva (single-stage or full pipeline) rather than running the stage itself, so the one source of pipeline truth stays with Deva. After a handoff to Deva, every later developer message for that story is passed back to Deva with full context; Do It never advances the pipeline or answers a checkpoint on its own.

## Overlays and the Menu

The menu is assembled from the agents actually installed in `.github/agents/`, so team, workspace, and personal overlays extend it by adding agents — base rows first, then overlay rows in tier order. The runtime always renders the table exactly as written in the Do It agent body; overlays change the roster, not the rendering rules.

## Standalone Prompts Are Not Menu Rows

Diagnostic and maintenance capabilities are standalone slash-command prompts, not menu rows: `/debug-sessions` (one finished session's trace), `/debug-logs` (a whole story's run woven together), `/plot-deva` (timing charts), `/diff-deva`, `/dry-run-deva`, `/measure-deva`, `/update-deva`, `/audit-deva`, and `/audit-artifacts`. Do It points developers at these but does not list them as rows.

## Base Sources

- `.github/agents/do-it.agent.md` — the Do It agent contract, menu, and routing rules (authoritative).
- `.github/docs/DESIGN-DEVA.md` — the pipeline, stages, and checkpoints Do It routes into.
- `.github/README.md` — Quick Start entry points and the stateful/stateless distinction.

<!-- ===== END SYNTHESIZED DOCUMENT ===== -->
