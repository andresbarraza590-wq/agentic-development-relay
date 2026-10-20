# Agent Guide: Understanding and Creating AI Coding Agents

<!-- ===================================================================== -->
<!-- SYNTHESIZED SECTION (inferred, NOT from screenshots): replaces the     -->
<!-- folded top of AGENT-GUIDE.md (original lines ~2-133). The capture shows -->
<!-- only line 1 (the title); the editor folded ~2-133 in all 12 of this     -->
<!-- file's screenshots, so the real introduction/overview was never shown.  -->
<!-- The overview below is reconstructed from base/README.md (which calls     -->
<!-- this the "Primary reference for agent and skill design, orchestration    -->
<!-- flow, and customization patterns"), DESIGN-DEVA.md, DESIGN-DO-IT.md, and -->
<!-- the agents/skills/prompts themselves. Wording is INFERRED and is NOT the -->
<!-- original text. Re-capture lines 1-137 (fold expanded) to replace it.     -->
<!-- ===================================================================== -->

## Overview

This guide is the primary reference for designing agents and skills, understanding the orchestration flow, and customizing the framework. Start here to understand setup, invocation patterns, and the end-to-end workflow checkpoints, then use the step-by-step setup below to build your own agent.

The framework is built from four kinds of building block:

- **Agents** (`.github/agents/*.agent.md`) — role-scoped specialists with YAML frontmatter controlling discovery, tool permissions, and subagent access. Two are entry points (`deva`, `do-it`); the rest are specialists that own one pipeline stage each.
- **Skills** (`.github/base/skills/*/SKILL.md`) — reusable procedures an agent invokes. A skill always runs under the model of the agent that invoked it; a `model:` line in a `SKILL.md` is ignored.
- **Prompts** (`.github/base/prompts/*.prompt.md`) — standalone slash commands (for example `/dry-run-deva`, `/diff-deva`, `/debug-logs`) for diagnostics and maintenance, invoked directly rather than through the menu.
- **Configuration** (`.github/config/*.yaml`) — policy: `guardrails.yaml` and `default-config.yaml` are install-protected; `agent-commands.yaml` (and overlay `team-config.yaml`) are overlay-customizable.

## The Orchestration Model

Deva is the orchestrator: it runs the end-to-end Software Development Life Cycle (SDLC) from a Jira story, routing through staged specialists and pausing at human checkpoints. **Do It** is the thin guided front door — it renders one fixed menu and routes to a single specialist (stateless) or to Deva (stateful); it owns no SDLC logic. See [Design of Deva](DESIGN-DEVA.md) and [Design of Do It](DESIGN-DO-IT.md) for the authoritative designs.

Each specialist owns exactly one stage: `setup-validator` (environment), `architecture-bootstrapper` (architecture context), `story-analyst` (Jira → brief), `branch-manager` (branches), `implementation-partner` (code), `qa` (review), `tester` (tests), `acceptance-checker` (AC + scope), `branch-publisher` (push), `regression-runner` (regression loop), `subbranch-extractor` (review delivery), `integration-publisher` (final stacked PR, reactive/internal), and `documenter` (wrap-up report).

## Invocation Patterns

- **Full pipeline:** select **Deva** in the Chat agent/mode picker and enter `work on <JIRA-KEY>`.
- **Guided menu:** select **Do It** and enter `show the menu`, then pick a row (add a Jira key to run it stateful, omit it to run stateless).
- **Diagnostics / maintenance:** run a slash-command prompt directly.

Select the custom agent from the picker rather than typing `@deva`/`@do-it` into the default Agent chat, which can add an unintended nested handoff and hide MCP tool confirmations.

## Workflow Checkpoints

A full run advances through a fixed checkpoint spine — setup (C0a), architecture (C0b), intake (C1a), refine (C1b), branch (C2), implement (C3), QA and test (C4), acceptance (C5), push (C6), regression (C7), split (C8a/C8b), review (C8c), integration (C8d), re-extraction (C9), and documentation/archive (C10). Each checkpoint pauses for a human decision; an agent never answers its own checkpoint. The branch model is `develop` → `feature/<user>/<PARENT-JIRA>` → `feature/<user>/story/<PARENT-JIRA>`, and humans retain review, approval, and merge authority at C8c/C8d.

<!-- ===== END SYNTHESIZED SECTION ===== -->

## Step-by-step Setup Guide

### Step 1: Create the Agent Files

Agents live in [agents/](../agents/) as `.agent.md` files. Each file includes YAML frontmatter that controls discovery, tool permissions, and subagent orchestration:

**[agents/my-agent.agent.md](../agents/)**

```markdown
---
description: "Use when... [trigger phrases for auto-discovery]"
tools: [read, edit, search, execute]     # What this agent can access
user-invocable: true                     # Show in @ picker (false = subagent only)
agents: [sub-agent-1, sub-agent-2]       # Allowed subagents (omit = all)
---

# My Agent

You are a specialist at [task]. Your job is to [purpose].

## Approach
1. [Step one]
2. [Step two]

## Constraints
- DO NOT [restriction]
```

**Key frontmatter fields:**

| Field | Purpose |
| ------- | -------- |
| `description` | **Required.** Tells VS Code when this agent should be discovered or suggested. Add clear trigger phrases. |
| `tools` | Defines which tools the agent is allowed to use (for example: `read`, `edit`, `search`, `execute`, `agent`, `web`, `todo`, MCP servers, and <BASE_ENGINEERING_ECOSYSTEM> tools). |
| `user-invocable` | Controls visibility in the Chat agent/mode picker: `true` shows it to users, `false` keeps it subagent-only. |
| `agents` | Controls subagent access: list allowed subagents explicitly; omit to allow all; use `[]` to allow none. |
| `model` | Optional model override for this agent (for example, `"Claude Sonnet 4"`). |

For portable Copilot and Claude generation, keep `description`, `model`, and
`argument-hint` values on one line, and declare `tools` inline or as a YAML
list. Do not use `>` or `|` block scalars for these fields; Claude mirror
generation rejects those forms.

### Step 2: Create Reusable Skills

Each skill lives in its own folder under [skills/{name}/](../skills/) and includes a `SKILL.md` file. VS Code uses the `description` field to auto-discover skills and load them on demand:

**Hypothetical example: [skills/write-tests/SKILL.md](../skills/)**

```markdown
---
name: write-tests
description: 'Write unit tests using pytest. Use when generating tests, verifying coverage targets, or creating test fixtures.'
---

# Write Unit Tests

## When to Use
- After implementing new functionality
- When QA flags missing coverage

## Procedure
1. Identify the module under test
2. Create a test file in `test/` mirroring the source path
3. Use pytest fixtures for setup/teardown
4. Cover happy path, edge cases, and error cases
5. Use `unittest.mock` for external dependencies
6. Run `pytest <test_file>` to verify tests pass
```

**Key points:**

- Set `name` to exactly match the skill folder name.
- Use `description` to help agents discover when to load the skill; include clear trigger keywords.
- Skills are also available as `/` slash commands in chat (for example, the installed `/test-generation` skill).
- Treat each skill's [SKILL.md](../skills/) as the source of truth for its workflow contract. Prefer supporting material in `references/` or `scripts/` when that keeps the authoritative contract coherent; do not split a skill merely to satisfy a generic line-count target.

**Skill folder structure:**

The hypothetical `write-tests` skill would use this structure:

```text
skills/write-tests/
├── SKILL.md          # Required: skill definition, usage guidance, and frontmatter
├── scripts/          # Optional: helper scripts the skill can run or reference
├── references/       # Optional: supporting docs loaded only when needed
└── assets/           # Optional: reusable templates, examples, or boilerplate files
```

### Step 3: Use Agents in VS Code

After the framework installer places the source artifacts in `.github/`, VS Code automatically discovers agents and skills. Before the first Deva run, select **Do It** in the Chat agent/mode picker and use option 1 to validate the environment and create the setup cache.

**Invoking agents:**

- Open the Chat agent/mode picker.
- Select an agent (for example, **Deva**) before entering your request.
- Example: select **Deva**, then enter `work on PROJ-1234`.
- Not sure which agent to use? Select **Do It**, then enter `show the menu`; it routes you to the right agent.

> **Affected recent VS Code versions, including 1.133:** do not type `@deva` or `@do-it` into the default Agent chat. That text may not switch the root agent and can create an extra subagent layer that hides MCP tool confirmations.

**Invoking skills:**

- Type `/` in chat to open available skills as slash commands.
- Example: `/test-generation` or `/code-review`
- Agents can also auto-load skills when a skill `description` matches your task.

**How auto-discovery works:**

- VS Code reads the `description` field in `.agent.md` and `SKILL.md` frontmatter files.
- When you submit a prompt, VS Code matches it to the most relevant agent or skill description.
- Subagents with `user-invocable: false` stay hidden from the picker, but other agents can still invoke them.

**Tool isolation:**

Each agent is limited to the tools listed in its `tools:` frontmatter. This keeps responsibilities clear and prevents unintended actions.

| Agent | Tools | Why |
| ------- | ------- | ----- |
| deva | read, edit, search, execute, agent, todo, Jira MCP | Recommended entry point and end-to-end orchestrator engine; needs broad access to coordinate the full workflow. |
| do-it | agent | Thin front-door router; only presents a menu and hands off to the right agent. |
| implementation-partner | read, edit, search, execute | Implements code changes and runs local validation commands. |
| qa | read, search | Review-only role focused on findings; does not modify code. |
| story-analyst | read, search, web, execute, Jira MCP | Collects context from Jira and repositories, then prepares implementation-ready inputs; `execute` is limited to read-only <BASE_ENGINEERING_ECOSYSTEM> lookups. |
| tester | read, edit, search, execute | Creates and updates tests, then runs test commands to verify results. |

### Step 4: Add Context Files (Optional)

For complex projects, include always-on instructions and architecture documentation:

**[copilot-instructions.md](../copilot-instructions.md)** — automatically loaded into every agent session:

```markdown
# Project Instructions

## Project Overview
- Language: Python 3.11
- Framework: Flask / FastAPI
- Testing: pytest
- Infrastructure: Terraform + AWS

## Conventions
- All source code lives in `src/`
- Tests mirror source structure in `test/`
- Use type hints on all function signatures
- Docstrings follow Google style
```

**`instructions/*.instructions.md`** (optional, developer-authored — not installed by the framework) — file-specific instructions loaded based on the `applyTo` pattern:

```markdown
---
applyTo: "**/*.tf"
---
Follow existing Terraform module patterns in the project.
Use variables for all configurable values with descriptions.
```

### Step 5: Test and Iterate

1. Ask the agent to complete a specific task (for example, "Add a health check endpoint").
2. Review the result against your team standards for quality, style, and scope.
3. If the output misses a convention, update your instructions to make that requirement explicit.
4. Commit the instruction updates and share them with your team.

---

## Agentic AI Instruction Structure

```text
.github/
├── copilot-instructions.md          # Global rules loaded in every session
├── docs/
│   ├── AGENT-GUIDE.md                # Team onboarding and workflow guide
│   └── AGENT-METRICS.md              # How to measure agent effectiveness
│
├── agents/                          # Orchestrators and specialist subagents
│   ├── deva.agent.md   # Recommended entry point
│   ├── do-it.agent.md               # Guided front door: menu that routes to the right agent
│   ├── story-analyst.agent.md       # Jira/context analysis
│   ├── implementation-partner.agent.md # Code implementation
│   ├── qa.agent.md                   # Quality and risk review
│   ├── tester.agent.md               # Test creation and execution
│   ├── acceptance-checker.agent.md   # Acceptance criteria and scope checks
│   ├── setup-validator.agent.md      # Standalone readiness validator; Deva verifies its cache at Step 0a
│   ├── architecture-bootstrapper.agent.md # Architecture bootstrap (Step 0b)
│   ├── branch-manager.agent.md       # Creates feature/story branches (Step 2)
│   ├── branch-publisher.agent.md     # Pushes the story branch (Step 6)
│   ├── regression-runner.agent.md    # Developer regression loop (Step 7)
│   ├── subbranch-extractor.agent.md  # Review subbranches + draft PRs (Steps 8-9)
│   ├── integration-publisher.agent.md # Final stacked integration PR (Step 8d)
│   └── documenter.agent.md           # Story wrap-up doc (Step 10)
│
├── skills/                          # Reusable task playbooks
│   ├── jira-analysis/SKILL.md
│   ├── codebase-discovery/SKILL.md
│   ├── code-implementation/SKILL.md
│   ├── test-generation/SKILL.md
│   └── ... (more skill folders)
│
└── instructions/                    # Optional file-pattern-specific rules
    └── terraform.instructions.md
```

Cloning this repository provides the framework source. After the installer places the selected layers under the target `.github/` directory, VS Code automatically discovers those effective agents and skills.

The installer also generates a mirrored Claude Code layout — `CLAUDE.md` at the workspace root plus `.claude/agents/` and `.claude/skills/` — from these same `.github/` assets, so the framework runs on both Copilot and Claude Code. `.github/` stays the single source of truth; the `.claude/` files are generated, not hand-edited.

---

## Agentic AI Operating Model

The default SDLC workflow uses a **pipeline of specialized agents**, each mapped to a role in a development team. Every agent has a clear responsibility, and work moves between agents through structured handoffs.

### How to Start: Just Say "Work on [JIRA-KEY]"

You do not need to call each agent manually. Select **Deva** in the VS Code Copilot Chat agent/mode picker, then enter `work on [JIRA-KEY]`; it runs the full pipeline end-to-end.

The Dev Assistant invokes the required subagents automatically. Those subagents are hidden from the picker (`user-invocable: false`), so you do not call them directly.

```text
You: "Work on PROJ-1234"

Agent: 🔍 Checks the validated setup cache, then offers the optional architecture bootstrap (Steps 0a-0b).
Agent: 📥 Runs intake and confirms scope (Step 1), then creates feature/story branches after approval (Step 2).
Agent: 🛠️ Implements on the story branch (Step 3), then runs logically independent QA and test handoffs one at a time before AC validation (Steps 4-5).
Agent: 🚀 Publishes the green story branch and collects developer regression results (Steps 6-7); Deva coordinates any repair rounds.
Agent: 🎭 Prepares direct or stacked review delivery, records C8c human review, runs stacked-only C8d integration, re-extracts C8c feedback when needed, and then writes the parent-story report (Steps 8-10).
```

In short, you provide confirmations at checkpoints, and the agent handles the remaining workflow steps.

### Agent Roster

| Agent | Primary responsibility | When it runs |
| --- | --- | --- |
| **[Dev Assistant](../agents/deva.agent.md)** | Recommended entry point and pipeline engine; orchestrates the full workflow end-to-end | Select Deva in the agent/mode picker, then enter `work on [JIRA]` |
| **[Setup Validator](../agents/setup-validator.agent.md)** | Materializes the canonical runtime configuration snapshot, validates environment prerequisites, and blocks early on setup issues | Run directly through `do-it` option 1; Deva Step 0a only verifies its workspace artifacts |
| **[Architecture Bootstrapper](../agents/architecture-bootstrapper.agent.md)** | Bootstraps machine-readable architecture metadata and companion docs when absent; smart drift scan (may propose a consent-gated refresh) when present | Auto-invoked in Step 0b (skippable) |
| **[Story Analyst](../agents/story-analyst.agent.md)** | Reads Jira and produces implementation-ready context | Auto-invoked in Step 1 |
| **[Implementation Partner](../agents/implementation-partner.agent.md)** | Implements scoped code changes | Auto-invoked in Step 3; approved multi-stream plans execute one managed handoff at a time under the current file-backed session |
| **[Acceptance Checker](../agents/acceptance-checker.agent.md)** | Checks acceptance criteria coverage and flags scope drift | Auto-invoked in Step 5 |
| **[QA](../agents/qa.agent.md)** | Reviews for defects, resilience, error handling, and security risks | Auto-invoked in Step 4; logically independent from Tester but currently serialized |
| **[Tester](../agents/tester.agent.md)** | Creates tests and drives coverage for changed code | Auto-invoked in Step 4; logically independent from QA but currently serialized |
| **[Branch Manager](../agents/branch-manager.agent.md)** | Creates the feature and story branches (owns the git commands) | Auto-invoked in Step 2 |
| **[Branch Publisher](../agents/branch-publisher.agent.md)** | Verifies the local suite is green, then pushes the story branch | Auto-invoked in Step 6 |
| **[Regression Runner](../agents/regression-runner.agent.md)** | Collects one explicit developer regression result; Deva owns repair and retry rounds | Auto-invoked in Step 7 |
| **[Subbranch Extractor](../agents/subbranch-extractor.agent.md)** | Prepares direct review for one slice or stacked review subbranches for multiple slices, and re-extracts after reviewer feedback | Auto-invoked in Steps 8-9 |
| **[Integration Publisher](../agents/integration-publisher.agent.md)** | Creates or reconciles the final stacked feature-to-`develop` draft PR | Reactively invoked in Step 8d after stacked C8c |
| **[Documenter](../agents/documenter.agent.md)** | Generates the Confluence-ready story wrap-up / Post-Action report | Auto-invoked in Step 10 |

### Starting and Resuming Work

There are two ways to run agents, with one simple rule:

- **The full end-to-end flow always goes through the Dev Assistant engine.** It is the only *stateful* agent: it saves progress after each approved checkpoint and, when you come back to a story, offers to **resume** from where you left off or **start over**. Select **Deva** in the agent/mode picker to **begin or continue** a story's end-to-end pipeline.
- **Every independently invocable specialist run is a cold start.** Architecture Bootstrapper, Story Analyst, Branch Manager, Implementation Partner, QA, Tester, Acceptance Checker, Branch Publisher, Regression Runner, Subbranch Extractor, Documenter, and Setup Validator keep no pipeline memory. Request an available one-off task through **Do It** or ask Dev Assistant to route it; do not try to launch a hidden specialist by name. Integration Publisher is reactive and Deva-only, so it has no standalone Do It route. Specialists never resume or persist pipeline state.
- **Run a single pipeline stage on demand.** You can ask the Dev Assistant (directly or through **Do It**) to run just one stage of an in-progress story — for example, "run qa on PROJ-1234" or "just the acceptance check for PROJ-1234." When a Jira key is present, the assistant checks that stage's prerequisites, runs only that stage, and records the result in the session — and in the activity log (as `mode=single`) — so a later full run skips it while it stays fresh (and re-runs it if upstream work changed). Without a Jira key, the same request routes to the matching specialist as a stateless task with no Deva story session, checkpoint, or activity record; the specialist may still perform its declared file, output, cache, or explicitly authorized external effects.

In short: **Dev Assistant = the resumable end-to-end flow; individual specialists = fresh, standalone tasks.** (Setup Validator keeps a workspace-scoped configuration snapshot and small pass/fail cache, but neither is resumable per-story pipeline state.)

### Shared Skills Library

Skills are reusable playbooks that different agents use to perform specific tasks consistently. The base framework supplies 21 skills in the skills/ folder; overlays may add to the effective installed set.

| Skill | Main purpose | Primarily used by |
| --- | --- | --- |
| [Jira Analysis](../skills/jira-analysis/SKILL.md) | Extract and structure Jira ticket details | Story Analyst, Acceptance Checker |
| [Story Refinement](../skills/story-refinement/SKILL.md) | Score story readiness and drive AC/scope/dependency improvements before implementation | Story Analyst (Step 1b) |
| [Codebase Discovery](../skills/codebase-discovery/SKILL.md) | Map repository structure, conventions, and patterns | Story Analyst, Implementation Partner |
| [Architecture Diagram](../skills/architecture-diagram/SKILL.md) | Create, refresh, and validate machine-readable architecture metadata (boundaries, data-flow directions, public-API flows) | Architecture Bootstrapper |
| [Prompt Structuring](../skills/prompt-structuring/SKILL.md) | Convert requirements into implementation-ready prompts | Story Analyst |
| [Progress Tracking](../skills/progress-tracking/SKILL.md) | Track subtasks and completion against plan | Dev Assistant, Acceptance Checker |
| [Pipeline Session](../skills/pipeline-session/SKILL.md) | Read and write the per-story session file — per-stage status, staleness, and preconditions — plus the per-story activity log at `.github/logs/<JIRA-KEY>/activity.log` | Dev Assistant |
| [Configuration Resolution](../skills/configuration-resolution/SKILL.md) | Materialize, verify, and read the canonical workspace configuration snapshot | Setup Validator, Dev Assistant, operational consumers |
| [Parallel Build Dispatch](../skills/parallel-build-dispatch/SKILL.md) | Coordinate approved serialized multi-stream implementation plans; physical overlap requires isolated workspaces and fenced handoffs | Dev Assistant (Step 3) |
| [PR Scoping](../skills/pr-scoping/SKILL.md) | Measure and validate focused, size-bounded linear review slices before approval | Subbranch Extractor (Step 8 plan) |
| [Subbranch Extraction](../skills/subbranch-extraction/SKILL.md) | Prepare direct feature review for one slice or parent-Jira ordinal stacked review branches for multiple slices | Subbranch Extractor (Steps 8-9) |
| [Integration Publication](../skills/integration-publication/SKILL.md) | Create or reconcile the final stacked feature-to-`develop` draft PR | Integration Publisher (Step 8d) |
| [Code Implementation](../skills/code-implementation/SKILL.md) | Implement production-ready code changes | Implementation Partner |
| [Error Handling](../skills/error-handling/SKILL.md) | Apply consistent and user-friendly error-handling patterns | Implementation Partner, QA |
| [Code Review](../skills/code-review/SKILL.md) | Review for defects, robustness, and security risks | QA |
| [Acceptance Criteria Validation](../skills/acceptance-criteria-validation/SKILL.md) | Check implementation against acceptance criteria | Acceptance Checker |
| [Security Basics](../skills/security-basics/SKILL.md) | Identify common security issues during review | QA |
| [Test Generation](../skills/test-generation/SKILL.md) | Generate unit tests across key code paths | Tester |
| [Mocking Patterns](../skills/mocking-patterns/SKILL.md) | Isolate dependencies using reliable mock patterns | Tester |
| [Code Coverage](../skills/code-coverage/SKILL.md) | Measure and improve test coverage | Tester |
| [Documentation Generation](../skills/documentation-generation/SKILL.md) | Produce the final story Post-Action report | Documenter (Step 10) |

## Sample Agentic AI End-to-end Workflow

The Dev Assistant executes Steps 1-10 on one story branch, preceded by the Step 0a setup gate and the optional Step 0b architecture stage. **All implementation lands on the story branch first.** At the end (Step 8), one slice uses direct review from the story branch; multiple slices use stacked review subbranches. Each decision gate is a **human review checkpoint (🔴)** where the agent proposes and the developer decides.

### Branching Strategy

This pipeline starts with the story branch. Stacked delivery creates review subbranches at the end; direct delivery creates none.

```text
develop
└── feature/<user>/<PARENT-JIRA>              ← feature branch
    └── feature/<user>/story/<PARENT-JIRA>        ← canonical story branch
        └── feature/<user>/story/<PARENT-JIRA>-PR1    ← PR1 → feature branch
            └── feature/<user>/story/<PARENT-JIRA>-PR2  ← PR2 → PR1
                └── feature/<user>/story/<PARENT-JIRA>-PR3 ← PR3 → PR2
```

**Rules:**

1. Use `feature/<user>/<PARENT-JIRA>` as the feature branch created from `develop` or approved as the existing feature base.
2. Use `feature/<user>/story/<PARENT-JIRA>` as the **canonical story branch**. All implementation and accepted corrections land there first.
3. Create subbranches **only at Step 8**, after regression is acknowledged. The `subbranch-extraction` skill splits the completed story branch into review-focused slices.
4. Open subbranch PRs as one linear **stack**: PR1 targets the feature branch; every dependent PR targets its immediate parent. Never target `develop` from a review PR.
5. Review incremental slices from PR1 toward the tip. After feedback is resolved, merge from the tip toward PR1. Each child closes and obtains current aggregate approval before merging that parent.
6. Require PR1's tracked tree to equal the canonical story tree before PR1 merges into the feature branch. Use merge commits; never squash, rebase-merge, force-push, or rewrite the published stack.
7. After PR1 lands and C8c is approved, reactive Step 8d creates or reconciles the separate feature-to-`develop` draft PR; humans validate, approve, and merge it at C8d.

---

### The Pipeline

The Dev Assistant executes these stages in sequence. Each `🔴 CHECKPOINT` is a decision gate for the developer. Reply with one exact, meaningful phrase shown by Deva; checkpoint ids never appear in the required reply. Advancing phrases approve the gate, while revision phrases keep it pending and route the named correction or stop path. Generic `yes`, `no`, `continue`, `approved`, and old `approve Cx` messages are not valid new decisions. If Deva is running below another agent, that parent must relay the checkpoint and stop. A reply printed by an assistant, a synthetic user message created during a handoff, or an autonomous-run request is never a developer decision. For defense in depth, every Jira-keyed specialist independently checks its registered upstream stages and decision-bearing checkpoint entries before doing any work; a direct parent dispatch therefore stops at the same pending gate.

Checkpoint naming convention:

- use `C`-prefixed identifiers (for example, `C1a`, `C3`, `C8b`) to match
  deva and checkpoint-ledger output.

#### Session Persistence & Resume

The Dev Assistant saves progress after each **approved** checkpoint to `.github/cache/sessions/<JIRA-KEY>/session.md`, so an interrupted story can be picked up where you left off instead of restarting.

- **Same live session:** if the assistant is already running your story, it just continues — no prompt.
- **Cold start:** if you return later and an in-progress session exists, it asks "Resume from `<checkpoint>`, or start fresh?" and re-verifies your branch/setup before continuing.
- **Only approved work is saved** — rejected work is never persisted as resumable.
- **Per-stage tracking:** the session records each pipeline stage's status (not started, in progress, complete, or stale) and the source it was produced from, so the assistant can skip stages that are already complete and fresh, and automatically re-run any stage made stale by later changes. This is what lets you run a single stage on its own and still have a later full run reuse the work. The `pipeline-session` skill is the sole managed-state writer and pipeline mutation API for this file; read-only diagnostics may inspect it. The stage list lives in `.github/config/guardrails.yaml` under `pipeline.stages`.
- **Activity log:** alongside the session file, the Dev Assistant appends a human-readable activity stream to `.github/logs/<JIRA-KEY>/activity.log` — a timestamped record of stage entries, checkpoint approvals/rejections, skips, re-runs, and blocks. It covers full runs and single-stage runs alike, including a stage routed through **Do It** from the Chat agent/mode picker (recorded as `mode=single`). Only the Dev Assistant writes it — the Do It router never does — and its verbosity is set by `pipeline.log_level` in `.github/config/guardrails.yaml`. Like archived sessions, an activity log is retained for `pipeline.archive_retention_days`; it becomes prunable only when its latest parseable event timestamp is older than that TTL.
- **Archive on completion:** on a full run the completed session file is moved to `.github/artifacts/sessions/<JIRA-KEY>/session.md` after the Step 10 report; a re-run rotates the prior copy to `session.<timestamp>.md`. Archived sessions and activity logs share the retention TTL (`pipeline.archive_retention_days`): age-known artifacts older than it are prunable, while newer or age-unknown artifacts are never wiped. The archive step also appends a one-line entry to the **reuse index** at `.github/logs/index.md` (key, date, tags, one-line summary, link) so completed stories are discoverable at a glance — this is what the intake prior-art lookup scans first. Prior art is **consent-gated**: the Story Analyst finds related past stories, summarizes them, and asks for your approval during intake (C1a); only what you approve flows into the work, and the build/QA/test agents reuse just that approved set — they never pull in prior work on their own.
- The **Dev Assistant** owns session status display, every session write, and the resume decision. The **Do It** router only selects and hands off to the destination agent.

#### Step 0a — Verify Setup and Choose Architecture

The Dev Assistant verifies the setup-validation cache and the canonical resolved-configuration snapshot. It does not repeat environment validation or configuration materialization. Setup Validator itself also returns a current PASS cache verbatim without rerunning authorization or other checks. If either Deva check fails, it stops and directs the developer to Do It option 1, **Validate my environment**. When both pass, Deva surfaces C0a and ends the turn; it does not start architecture yet.

> 🔴 **CHECKPOINT C0a** — Setup validation passed. Reply `run architecture`, `skip architecture`, or `stop architecture`.

#### Step 0b — Establish Architecture Context (Optional)

When selected at C0a, the Architecture Bootstrapper creates missing architecture context or performs a read-only drift assessment of existing context. A first bootstrap inventories every confirmed repository, invokes the deep architecture-discovery profile for each one, and publishes the metadata and VCS baseline only after all repository coverage records are complete. Existing metadata without that coverage evidence triggers a consent-gated deep baseline refresh; verified metadata refreshes only when configured drift thresholds are met and the developer consents. Before any Jira-keyed architecture work, the bootstrapper independently calls the registry-backed architecture precondition check; otherwise it returns the pending checkpoint without reading architecture metadata or invoking the architecture skill. The same entry defense applies at every later specialist stage. Skipping bootstrap execution is recorded as the proposed architecture result, but it does not skip C0b.

> 🔴 **CHECKPOINT C0b** — Architecture context is ready, pre-existing, or intentionally skipped. Reply `start intake` or `stop intake`. This checkpoint is always surfaced.

#### Step 1 — Read Jira + Discover Context (Story Analyst)

The Dev Assistant invokes the Story Analyst, which reads the live Jira ticket via MCP (summary, description, AC, comments, linked issues) and scans your workspace for relevant repos and patterns. It then asks targeted questions:

- 📁 Which repos and files does this touch?
- 🔗 Any existing libraries to leverage?
- 🌿 Base branch — develop, or an existing feature branch?
- ⚠️ Gotchas the ticket doesn't mention?

> 🔴 **CHECKPOINT C1a** — After answering the questions, reply `confirm intake` or `revise intake`.

The Story Analyst then presents its consolidated understanding of the objective, scope, repositories, key files, Acceptance Criteria (AC), out-of-scope boundaries, and base branch.

After you explicitly authorize the Jira mutation, the Story Analyst enriches the live Jira description with `## Context`, `## Understanding`, `## Scope`, `## Agreements`, and `## Prompt-Ready Actions for Implementation Partner` sections (the original description is preserved verbatim under `## Original Description`).

> 🔴 **CHECKPOINT C1b** — Reply `confirm understanding` or `revise understanding`.

#### Step 2 — Set Up Branches (developer-authorized)

Based on your base-branch choice in Step 1:

Deva first presents the exact base branch, feature branch, story branch, and remote pushes. Reply `create and push branches` to authorize that unchanged plan or `change branch plan` to revise it. Branch Manager performs no branch mutation before that later authorization.

- **Base = `develop`:** After authorization, Branch Manager creates `feature/<user>/<PARENT-JIRA>` off `develop`, pushes it, then creates and pushes `feature/<user>/story/<PARENT-JIRA>` from the feature branch.
- **Base = existing feature branch:** After authorization, Branch Manager updates `develop`, merges it into the approved feature branch without rewriting published history, pushes the updated feature branch, then creates and pushes the canonical namespaced story branch. A missing branch, merge conflict, or rejected push blocks the stage without a workaround.

> 🔴 **CHECKPOINT C2** — After the branches are ready, reply `start implementation` or `revise branch setup`.

#### Step 3 — Implement on the Story Branch (Implementation Partner)

**All implementation lands on the story branch.** No subbranches yet.

For most stories, a single Implementation Partner works linearly. For large stories (3+ repos with no shared files, Acceptance Criteria mapping to clearly independent components, more than one sprint of solo work, or developer request), the Dev Assistant may approve a disjoint multi-stream plan. Under the current file-backed session, it invokes those Implementation Partner streams one at a time on `feature/<user>/story/<PARENT-JIRA>`. Physical overlap remains disabled until isolated workspaces, a serialized commit critical section, and fenced managed handoffs are enforceable.

Commits may interleave topics — that's fine. Step 8 separates them by extraction mode and approved plan, not by commit order.

> 🔴 **CHECKPOINT C3** — Reply `run quality checks` or `continue implementation`.

#### Step 4 — QA + Tests on the Story Branch (serialized shared gate)

QA and Tester are logically independent, but the current controller invokes them one at a time on the **full story branch** (not per-area, not per-commit). Both results feed the shared C4 gate:

- **QA:** bugs, null handling, error cases, security
- **Tester:** unit tests meeting the configured overall coverage target (80% by default) and business-logic target (90% by default)

The Dev Assistant presents both results together, followed by the recommended fix list.

> 🔴 **CHECKPOINT C4** — Reply `start acceptance` or `apply quality fixes`.

#### Step 5 — Acceptance Check (Acceptance Checker)

The Acceptance Checker audits the full story branch against the Jira's acceptance criteria and flags scope creep. Each AC is marked ✅ Met / ⚠️ Partially Met / ❌ Not Met / 🔲 Deviated.

> 🔴 **CHECKPOINT C5** — Reply `publish story`, `defer acceptance gaps`, or `fix acceptance gaps` as applicable.

#### Step 6 — Push the Story Branch (automatic on approval)

**Precondition:** the local automated suite is green (run the `test` command from `.github/config/agent-commands.yaml`; a concrete passing command is required, and an absent, empty, or `skip` test value is a blocker the developer must resolve).

```bash
git push -u origin feature/<user>/story/<PARENT-JIRA>
```

No subbranches, no PRs yet — they come at Step 8.

> 🔴 **CHECKPOINT C6** — Reply `start regression` or `stop regression`.

#### Step 7 — Developer Regression Loop

The developer runs regression and reports pass/fail. If it fails, fixes land on the story branch, then QA/test updates can be re-run as needed.

> 🔴 **CHECKPOINT C7** — Reply `regression passed` or `regression failed`.

#### Step 8 — Review Delivery + Draft PRs (subbranch-extraction skill)

Now that the story branch is functionally complete and regression-acknowledged, the Dev Assistant partitions its diff into review slices via the **`subbranch-extraction` skill**:

- One slice selects direct mode: integrate the complete story additively into feature, create no review branch, and prepare the feature-to-`develop` draft PR
- Multiple slices select stacked mode: use contiguous `feature/<user>/story/<PARENT-JIRA>-PR<N>` branches built cumulatively in dependency order
- Review slices create neither Jira subtasks nor descriptive slugs
- Initial extraction returns a prepared manifest without opening PRs
- After C8b authorization, direct mode opens one feature-to-`develop` draft PR; stacked mode opens the authorized linear stack
- The manifest proves complete one-slice ownership and mode-specific feature/story or cumulative-tip/story tracked-tree equivalence
- If interrupted after C8b authorization, resume uses the persisted manifest and side-effect ledger to reconcile `publish` mode only; it does not repeat planning, extraction, C8a, or the C8b prompt
- The story branch is read-only — never modified or rebased

> 🔴 **CHECKPOINT C8a** — Reply `prepare review delivery` or `revise split plan`.
> 🔴 **CHECKPOINT C8b** — Reply `open draft pull requests` or `revise draft pull requests`.

#### Step 8c — Human Review

After draft delivery opens, direct mode reviews and merges its feature-to-`develop` PR at C8c. Stacked mode reviews root-to-tip, collapses tip-to-root, and lands PR1 into feature at C8c. Reactive Step 8d then automatically creates or reconciles the final feature-to-`develop` draft PR.

When changes are requested, the pipeline records that C8c revision choice durably before collecting feedback; an interruption resumes the selected correction path. The fix lands on the story branch, stale QA/test/acceptance/publication/regression evidence is refreshed, and only then does the pipeline enter reactive Step 9. Direct re-extraction is blocked without that C8c evidence.

> 🔴 **CHECKPOINT C8c** — Reply `review complete` or `review changes requested`.

For stacked delivery only, C8c approval triggers Integration Publisher. It publishes the final draft PR without approving or merging it.

> 🔴 **CHECKPOINT C8d** — Reply `integration complete`, `integration changes requested`, or `restart review preparation from integration`.

Ordinary C8d feedback remains in Step 8d: repair the canonical story first, refresh stale validation, then let Integration Publisher project exactly that correction additively into feature, push it, and refresh the same integration PR. It never enters Step 9. Feedback that changes delivery mode, slice count, accepted ownership, or topology returns to Step 8 for fresh C8a/C8b authorization.

#### Step 9 — Reviewer Feedback Re-Extraction Loop

If a reviewer flags an issue, the fix lands on the **story branch first**. Direct mode projects only that story delta additively to feature and verifies no canonical story change was lost, preserving any `develop` synchronization already present. Stacked mode recycles the affected branch and dependents when ownership/topology is unchanged, or creates an authorized same-count replacement suffix when the plan changes. A mode/count change returns to Stage 8 through `restart review preparation`. After C9 accepts revised delivery, the pipeline returns to C8c for another human review outcome.

> 🔴 **CHECKPOINT C9** — Reply `accept revised delivery`, `revise delivery`, or `restart review preparation` when the delivery mode or slice count changed.

#### Step 10 — Post-Action Report (Documenter)

The Dev Assistant invokes **Documenter** once. Documenter runs the `documentation-generation` skill and returns its canonical payload unchanged, generating a single Confluence-ready Markdown file at:

```text
.github/artifacts/sessions/[PARENT-JIRA]/report.[REPORT-IDENTITY].md
```

The report covers Jira intake answers, implementation summary, QA findings, test coverage, the AC validation table, regression results, and mode-specific review delivery. Direct mode records feature/story equivalence, any required canonical story-projection proof, and C8c feature-to-`develop` integration. Stacked mode records the subbranch manifest and PR links, root-to-tip review, the tip-to-root merge chain, PR1/story equivalence, PR1-to-feature landing, and C8d feature-to-`develop` integration. Re-runs of the pipeline regenerate the file from scratch.

Before C10 is shown, the live session stores the report path and a short readiness summary as a pending candidate, not a duplicate of the report body. C10 accepts that persisted candidate; it cannot complete and the session cannot archive unless the reference remains present and the report remains readable.

> 🔴 **CHECKPOINT C10** — Reply `archive session` or `revise report`.

---

### Putting It All Together

```text
Select Deva in the agent/mode picker, then enter: work on [JIRA]
                │
                ▼

┌─────────────────────────────┐   🔴 Q&A → confirm understanding
│ 1. Story Analyst            │   🔴 confirm story branch
│ 2. Branches                 │   🔴 confirm implementation
│ 3. Implementation Partner(s)│   🔴 confirm fixes
│ 4. QA + Tester              │   🔴 confirm AC
│ 5. Acceptance Checker       │   🔴 push approved
│ 6. Push                     │   🔴 pass / fail
│ 7. Developer regression     │   🔴 split plan + authorize draft PRs
│ 8. Subbranch split          │   🔴 complete / changes requested
│ 8c. Direct/stacked review   │   🔴 complete / changes requested (stacked only)
│ 8d. Stacked integration     │   ♻ changes return to human review
│ 9. Re-extraction loop       │   📄 immutable report under .github/artifacts/sessions/[JIRA]/
│ 10. Post-Action MD          │
└─────────────────────────────┘
                │
                ▼
        Reviewer feedback?  →  Fix on story branch  →  recycle/replace Step 9  →  C8c
```

### Git Commit History (What It Looks Like)

```text
feature/<user>/<PARENT-JIRA>
│
├── feature/<user>/story/<PARENT-JIRA>          canonical story branch
│   ├── [PARENT-JIRA]: scaffold widget service
│   ├── [PARENT-JIRA]: add GQL schema
│   ├── [PARENT-JIRA]: add REST view + serializer
│   ├── [PARENT-JIRA]: address QA findings
│   └── [PARENT-JIRA]: add unit tests
│
    (Step 8 carves these into a stack of subbranches)
│
└── feature/<user>/story/<PARENT-JIRA>-PR1          → PR1 → feature branch
    └── feature/<user>/story/<PARENT-JIRA>-PR2  → PR2 → PR1
        └── feature/<user>/story/<PARENT-JIRA>-PR3 ← PR3 → PR2
```

---

### Tips for Daily Use

1. **You do not need the full pipeline for every task.** For small fixes, select **Do It** and use the corresponding menu route, or use `/` to run a skill directly.

2. **Agents and skills load automatically from the repository layout.** You do not need to paste instructions into chat. VS Code reads each `description` frontmatter and selects the best match for your request.

3. **Subagents are orchestrated automatically.** When you run Deva from the agent/mode picker, it calls Implementation Partner, invokes the logically independent QA and Tester handoffs one at a time, then calls Acceptance Checker.

4. **Use agents during PR review as well.** Select **Do It** in the Chat agent/mode picker and route the pasted diff to QA or Acceptance Checker; those specialists remain hidden from direct invocation.

5. **Keep improving agent definitions.** If an agent repeatedly misses something, update the relevant [.agent.md](../agents/) or [SKILL.md](../skills/) file. Treat these files as maintainable code.

6. **Use this guide for onboarding.** Share it with new team members so they can quickly learn team conventions, patterns, and quality expectations.

7. **Always verify agent output.** Every 🔴 checkpoint is intentional. The agent assists, but you remain responsible for final decisions and code quality.

8. **Make small, frequent commits.** Keep each commit focused on one logical change and use a Jira-prefixed message for clear, traceable history.

9. **Keep the story branch tightly scoped.** Aim to reach Step 7 (regression) within hours to a few days. If progress stalls, split the work into separate Jira stories before Step 3.

---

## Quick Reference Summary

| If you want to... | Go to / use... |
| --- | --- |
| Set global project guidance for all agent runs | [copilot-instructions.md](../copilot-instructions.md) |
| Define how a specific task should be done | [skills/{name}/SKILL.md](../skills/) |
| Turn a Jira ticket into implementation-ready context | Story Analyst subagent (Step 1) |
| Run the full workflow end-to-end | Select Deva in the agent/mode picker; enter `work on [JIRA]` |
| Implement a focused coding change | Implementation Partner subagent (Step 3) |
| Confirm acceptance criteria are satisfied | Acceptance Checker subagent (Step 5) |
| Review code for bugs, resilience, and security | QA subagent (Step 4) |
| Create unit tests and improve coverage | Tester subagent (Step 4) |
| Verify regression status before split | Step 7 developer regression |
| Split a completed story into review-sized PRs | subbranch-extraction skill (Step 8) |
| Generate a Confluence-ready delivery report | documentation-generation skill (Step 10) |
| Share team-standard agent behavior | Commit [agents/](../agents/) and [skills/](../skills/) to the repository |
| Improve results over time | Iterate on agent and skill files based on review feedback and metrics |
