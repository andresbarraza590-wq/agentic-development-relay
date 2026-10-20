# 🤖 AI Agent Pipeline — Team Demo

> **One command. Fourteen agents. Full development cycle.**

> **Note:** This demo is aligned to the current `agents/` and `skills/` in this repo.
>
> **Strong recommendation:** Update this file whenever `agents/` or `skills/` are changed to keep the demo accurate.

---

## Table of Contents

- [The Problem](#the-problem)
- [The Solution: Agent Pipeline](#the-solution-agent-pipeline)
- [The Agents (1 Orchestrator + 13 Specialists)](#the-agents-1-orchestrator--13-specialists)
- [Live Demo Flow](#live-demo-flow)
  - [Step 0a — Setup Validation](#step-0a--setup-validation)
  - [Step 1 — Trigger + Story Intake](#step-1--trigger--story-intake)
  - [Step 2 — Branch Setup](#step-2--branch-setup)
  - [Step 3 — Implement on Story Branch](#step-3--implement-on-story-branch)
  - [Step 4/5 — QA, Tests, and AC Check](#step-45--qa-tests-and-ac-check)
  - [Step 6/7 — Push + Regression Gate](#step-67--push--regression-gate)
  - [Step 8/9/10 — Prepare Review Delivery, Refresh, and Wrap-Up](#step-8910--prepare-review-delivery-refresh-and-wrap-up)
- [Branching Strategy](#branching-strategy)
- [Human Checkpoints](#human-checkpoints-)
- [What's in the Source Repo](#whats-in-the-source-repo)
- [Quick Start (2 minutes)](#quick-start-2-minutes)
- [Key Takeaways](#key-takeaways)

---

## The Problem

- **Vague stories** — half the sprint goes to figuring out what to build, not building it
- **Giant PRs** — nobody reads them properly; bugs ship, merges explode
- **Tests as an afterthought** — coverage gaps surface in Prod, not in review
- **Tribal knowledge** — one person holds the context; everyone else guesses

---

## The Solution: Agent Pipeline

In VS Code Copilot Chat, select **Deva** in the agent/mode picker, then enter **`work on PROJ-1234`**. A team of specialized subagents takes it from there — setup validation, architecture bootstrap, Jira intake, branch setup, implementation, review, testing, acceptance verification, publishing, regression, direct or stacked review delivery, conditional stacked integration, and wrap-up docs — pausing only when a decision needs a human.

```text
Select Deva in the picker ──→ enter: work on PROJ-1234

📦 Setup cache is checked; do-it option 1 owns validation (one-time)
🏛️  Architecture Bootstrapper grounds the codebase        (skippable)
📋 Story Analyst reads Jira via MCP and asks questions     (interactive)
🔴 Branch plan: create and push branches / change branch plan
🌿 Branch Manager creates feature/story branches          (authorized)
🖥️ Implementation Partner writes code on story branch     (automatic)
🔍 QA + 🧪 Tester run one at a time; share C4             (automatic)
✅ Acceptance Checker validates AC alignment              (automatic)
📤 Branch Publisher verifies and pushes story branch      (automatic)
🔁 Regression Runner collects the regression result       (interactive)
✂️  Review delivery selects direct or stacked mode         (automatic)
👥 C8c records human review and delivery landing           (interactive)
🔗 C8d validates final integration for stacked mode        (conditional)
📄 Post-Action report generated                            (automatic)
```

**Your job is to decide at 🔴 checkpoints. The agents do the rest.**

> **Under the hood:** Agents are Markdown files in `agents/`. After Copilot prerequisites are configured and the framework is installed under `.github/`, VS Code discovers them without a custom agent plugin or manual agent registration.
> Each agent's YAML frontmatter locks down exactly what it can do: read, edit, execute, or call external APIs.
> The entry-point agents — `deva` and the optional `do-it` router — are available in the Chat agent/mode picker; the specialists run silently as subagents.
> Runs on both runtimes: the installer mirrors these same agents and skills into a Claude Code layout (`.claude/` plus a root `CLAUDE.md`) from one source, so nothing is authored twice.

---

## The Agents (1 Orchestrator + 13 Specialists)

| Agent | What it does | Can it edit files? | Normally uses Jira? | Can it run commands? |
| --- | --- | :---: | :---: | :---: |
| 📦 **Dev Assistant** | Pipeline engine — chains all other agents in order; selected by you in the Chat agent/mode picker or routed through Do It | ✅ | ✅ | ✅ |
| 🧰 **Setup Validator** | Standalone preflight — materializes runtime configuration and validates MCP connectivity, auth readiness, and git hygiene; Deva verifies its cache at Step 0a | ❌ | ✅ | ✅ |
| 🏛️ **Architecture Bootstrapper** | Step 0b — deep-scans every confirmed repository before publishing a first architecture baseline; checks coverage and drift and may propose a consent-gated refresh when metadata exists | ✅ | ❌ | ✅ |
| 📋 **Story Analyst** | Reads the Jira ticket, interviews you to fill gaps, produces a structured task brief | ❌ | ✅ | ❌ † |
| 🖥️ **Implementation Partner** | Writes the code for each subtask | ✅ | ❌ | ✅ |
| 🔍 **QA** | Reviews written code for bugs, edge cases, and security issues — read-only so it can never accidentally change anything | ❌ | ❌ | ❌ |
| 🧪 **Tester** | Generates unit tests targeting ≥80% coverage | ✅ | ❌ | ✅ |
| ✅ **Acceptance Checker** | Reads the original Jira AC, checks the code satisfies every criterion, flags scope creep | ❌ | ✅ | ❌ |
| 🌿 **Branch Manager** | Creates `feature/<user>/<PARENT-JIRA>` and canonical `feature/<user>/story/<PARENT-JIRA>` — owns the git commands | ❌ | ❌ | ✅ |
| 📤 **Branch Publisher** | Verifies the local suite is green, then pushes the story branch | ❌ | ❌ | ✅ |
| 🔁 **Regression Runner** | Collects one explicit developer regression result; Deva owns repair, QA/test, republish, and retry rounds | ❌ | ❌ | ✅ |
| ✂️ **Subbranch Extractor** | Prepares direct review for one slice or stacked review subbranches for multiple slices, and re-extracts after feedback | ✅ | ❌ | ✅ |
| 🔗 **Integration Publisher** | Reactively creates or reconciles the final stacked feature-to-`develop` draft PR | ✅ | ❌ | ✅ |
| 📄 **Documenter** | Generates the Confluence-ready story wrap-up / Post-Action report | ✅ | ❌ | ❌ |

> File-edit and command capabilities reflect VS Code tool restrictions. Jira values describe normal role usage: Jira MCP tools may remain granted in frontmatter to keep integrations warm, while each agent's operating contract controls whether it may call them.
>
> † Story Analyst stays read-only in practice; its one command capability is a consent-gated, read-only <BASE_ENGINEERING_ECOSYSTEM> documentation lookup, not general command execution.

---

## Live Demo Flow

### Step 0a — Setup Validation

```text
📦 Deva checks .github/cache/sessions/setup-validation.md
  - Current PASS cache: reuse it; no authorization or validation checks rerun
  - Cache absent: redirect to do-it option 1 and stop
🔴 CHECKPOINT C0a: Run or skip architecture bootstrap?
  - End turn; architecture cannot start until the developer answers C0a
  - Developer replies exactly: run architecture / skip architecture / stop architecture
  - A parent agent cannot print that reply or synthesize it during a handoff
  - Architecture Bootstrapper re-checks the decision-bearing C0a session entry before any skill call
🔴 CHECKPOINT C0b: start intake / stop intake
```

### Step 1 — Trigger + Story Intake

> Select **Deva** in the Chat agent/mode picker, then enter `work on PROJ-1234`.

Story Analyst reads Jira and asks targeted questions:

```text
📋 I've read PROJ-1234: Config Cache Refresh Logic

❓ A few questions before I start:
  1. 📁 Which repos does this touch?
  2. 🔗 Any existing libraries to leverage?
  3. 🎯 What does "done well" look like?
  4. ⚠️ Any gotchas?
```

🔴 CHECKPOINT C1a: confirm intake / revise intake

Story Analyst returns consolidated understanding.

You explicitly authorize Jira enrichment, and Story Analyst writes the agreed context while preserving the original description.

🔴 CHECKPOINT C1b: confirm understanding / revise understanding

### Step 2 — Branch Setup

```text
Deva presents the exact base, feature/story branches, and remote pushes.
🔴 BRANCH AUTHORIZATION: create and push branches / change branch plan

After authorization, Branch Manager creates:
  feature/<user>/<PARENT-JIRA>
  feature/<user>/story/<PARENT-JIRA>
🔴 CHECKPOINT C2 after branch creation: start implementation / revise branch setup
```

### Step 3 — Implement on Story Branch

```text
🖥️ Implementation Partner works only on feature/<user>/story/<PARENT-JIRA>

First loads architecture context (.github/artifacts/architecture-metadata.json),
  treating it as read-only and reporting architecture-significant deltas to
  Dev Assistant for a developer-consented architecture-stage refresh.

💡 Plan:
  - Celery task + API integration
  - DB persistence + S3 backup
  - Version validation logic
  - EventBridge Terraform

  (For large stories: Dev Assistant can approve a multi-stream plan
   and invoke each Implementer stream one at a time — all commits still
   land on the story branch. Physical overlap requires isolated workspaces
   and fenced handoffs.)
```

🔴 CHECKPOINT C3: run quality checks / continue implementation

### Step 4/5 — QA, Tests, and AC Check

```text
🔍 QA + 🧪 Tester run one at a time on story branch; both feed C4
🔴 CHECKPOINT C4: start acceptance / apply quality fixes

✅ Acceptance Checker returns AC status table
  Met / Partially Met / Not Met / Deviated
🔴 CHECKPOINT C5: publish story / defer acceptance gaps / fix acceptance gaps
```

### Step 6/7 — Push + Regression Gate

```text
📤 Push feature/<user>/story/<PARENT-JIRA>
🔴 CHECKPOINT C6: start regression / stop regression

🔁 Developer runs regression and reports pass/fail
🔴 CHECKPOINT C7: regression passed / regression failed
```

### Step 8/9/10 — Prepare Review Delivery, Refresh, and Wrap-Up

```text
✂️ Step 8a: propose acceptance-mapped review slices and delivery mode
🔴 CHECKPOINT C8a: prepare review delivery / revise split plan

✂️ Step 8b: prepare the approved direct or stacked manifest
  → one slice: feature/user/PROJ-1234 → develop
  → multiple: feature/user/story/PROJ-1234-PR1 → feature/user/PROJ-1234
  → multiple: feature/user/story/PROJ-1234-PR2 → feature/user/story/PROJ-1234-PR1
🔴 CHECKPOINT C8b: open draft pull requests / revise draft pull requests
  → open only the approved head/base pairs
  → cumulative tip tree must equal the canonical story tree
  → resume after approval reconciles publish only; never repeat plan or extraction

👥 Step 8c: humans review the direct PR or stacked draft PRs
🔴 CHECKPOINT C8c: review complete / review changes requested
  → changes-requested is durable and resumes the correction path after interruption
  → review incremental slices root-to-tip
  → collapse approved PRs tip-to-root; recheck/reapprove every changed parent
  → prove PR1/story tree equality and merge PR1 to feature

🔗 Step 8d: stacked-only reactive integration publication
  → automatically create or reconcile the final feature-to-develop draft PR
  → ordinary C8d feedback repairs story first, refreshes validation, then projects that exact delta additively into feature and refreshes the same PR
  → final-integration feedback stays in Step 8d; delivery mode/count/ownership/topology changes restart Step 8 authorization
  → humans retain conflict decisions, review, approval, checks disposition, and merge
🔴 CHECKPOINT C8d: integration complete / integration changes requested / restart review preparation from integration

👥 Step 9: reviewer feedback loop
  - require pending C8c with durable review-changes-requested evidence
  - fix on story branch first
  - refresh stale QA, tests, acceptance, publication, and regression evidence
  - direct: apply only the story correction delta to feature and verify canonical projection
  - stacked: recycle the affected suffix additively
  - same-count stacked plan change: preserve the unaffected prefix and create a revisioned replacement suffix
  - delivery-mode or slice-count change: mutate nothing and restart Stage 8 review preparation
🔴 CHECKPOINT C9: accept revised delivery / revise delivery / restart review preparation
  → return to C8c for another human review outcome

📄 Step 10: auto-generated Post-Action report at
  .github/artifacts/sessions/PROJ-1234/report.cb30f6d2-1b91-45d3-8ed4-29c8cb75e622-docs-documenter-default-1.md
  → session stages report reference + readiness before C10; missing report blocks archive
🔴 CHECKPOINT C10: archive session / revise report
```

---

## Branching Strategy

```text
develop
  └─ feature/user/PROJ-1234              ← feature branch
      └─ feature/user/story/PROJ-1234          ← canonical story branch
          │       │
          │       └─ (Step 8b: extract topical slices into a stack)
          │
          └─ feature/user/story/PROJ-1234-PR1   → PR1 → feature branch
              └─ feature/user/story/PROJ-1234-PR2 → PR2 → PR1
                  └─ feature/user/story/PROJ-1234-PR3 → PR3 → PR2
```

- **All code commits to the story branch initially** — subbranches are created only after local and environment regression testing passes
- Each topical slice (celery, terraform, validation) becomes its own subbranch, kept to ~100-300 lines per PR
- Subbranches form a stacked chain of draft PRs — PR1 targets the feature branch and each dependent targets its immediate parent
- Review runs root-to-tip; merge authorization and collapse run tip-to-root, with current checks and aggregate approval after every child changes its parent
- PR1 must equal the canonical story tree before it lands in the feature branch
- After stacked C8c, Step 8d automatically creates or reconciles the separate feature-to-`develop` draft PR; C8d retains human approval and merge authority

---

## Human Checkpoints (🔴)

The pipeline pauses at explicit gates so the developer stays in control:

| Checkpoint | When | Exact reply choices |
| --- | --- | --- |
| C0a | After setup validation | `run architecture` / `skip architecture` / `stop architecture` |
| C0b | After the architecture result | `start intake` / `stop intake` |
| C1a | During intake | `confirm intake` / `revise intake` |
| C1b | After authorized Jira enrichment | `confirm understanding` / `revise understanding` |
| C2 | After branch setup | `start implementation` / `revise branch setup` |
| C3 | After implementation | `run quality checks` / `continue implementation` |
| C4 | After QA + Tests | `start acceptance` / `apply quality fixes` |
| C5 | After AC check | `publish story` / `defer acceptance gaps` / `fix acceptance gaps` |
| C6 | After push | `start regression` / `stop regression` |
| C7 | After regression | `regression passed` / `regression failed` |
| C8a | After regression pass | `prepare review delivery` / `revise split plan` |
| C8b | After review-delivery preparation | `open draft pull requests` / `revise draft pull requests` |
| C8c | During human PR review | `review complete` / `review changes requested` |
| C8d | During final stacked integration review | `integration complete` / `integration changes requested` / `restart review preparation from integration` |
| C9 | During reviewer feedback loop | `accept revised delivery` / `revise delivery` / `restart review preparation` |
| C10 | After report generation | `archive session` / `revise report` |

Every Jira-keyed specialist re-checks its registry dependencies and decision-bearing upstream checkpoint entries before stage work. If a parent agent tries to jump directly to the next specialist, that specialist returns the pending checkpoint instead of reading inputs, invoking skills, editing files, running commands, or mutating remote state. Keyless standalone runs keep their separate explicit-input safeguards.

**You stay in control. The agents accelerate the work.**

**Key insight:** Regression failures are fixed on the story branch (source of truth), then QA/tests/regression loops re-run before subbranch extraction.

**Resumable:** progress is saved after each approved checkpoint to `.github/cache/sessions/<JIRA-KEY>/session.md`, which tracks each pipeline stage's status and staleness. Come back later and the Dev Assistant offers to resume from your last checkpoint (or start fresh); on completion the file is archived to `.github/artifacts/sessions/<JIRA-KEY>/session.md` for audit and reuse, not wiped. Because progress is tracked per stage, you can also run a single stage on its own — for example, `run qa on [JIRA-KEY]` — and a later full run will skip it while it stays fresh. Separately, the Dev Assistant appends a timestamped activity log to `.github/logs/<JIRA-KEY>/activity.log` with verbosity set by `pipeline.log_level`; like the archived session file, it is kept for post-mortem. Single-stage runs are recorded there too — including one routed through **Do It** from the Chat agent/mode picker (tagged `mode=single`).

---

## What's in the Source Repo

The deployable framework source is organized under `base/`. Installation copies this tree into a target's `.github/` directory, where VS Code discovers the agent and skill definitions automatically:

```text
ingress_ai_agents/
└─ base/
    ├─ agents/                        ← agents
    │   ├─ deva.agent.md                ← user-facing; select Deva in the agent/mode picker
    │   ├─ setup-validator.agent.md
    │   ├─ architecture-bootstrapper.agent.md
    │   ├─ story-analyst.agent.md
    │   ├─ implementation-partner.agent.md
    │   ├─ qa.agent.md
    │   ├─ tester.agent.md
    │   ├─ acceptance-checker.agent.md
    │   └─ ... (7 more)
    ├─ skills/                        ← 21 base skills; overlays may add more
    │   ├─ configuration-resolution/SKILL.md
    │   ├─ jira-analysis/SKILL.md
    │   ├─ codebase-discovery/SKILL.md
    │   ├─ parallel-build-dispatch/SKILL.md
    │   ├─ pr-scoping/SKILL.md
    │   ├─ subbranch-extraction/SKILL.md
    │   ├─ documentation-generation/SKILL.md
    │   └─ ... (14 more)
    ├─ prompts/                        # Slash-command prompts (.prompt.md)
    ├─ scripts/                        # Runtime dependencies, resolver, tests, tracer, and Git hooks
    │   ├─ requirements.txt
    │   ├─ configuration/resolve-config.py
    │   └─ configuration/test-resolve-config.py
    ├─ docs/                          # Framework docs, metric templates, and guides
    │   ├─ AGENT-GUIDE.md               # Full documentation guide
    │   ├─ AGENT-METRICS.md             # Metrics framework
    │   └─ DEMO.md                      # Team demo walkthrough
    ├─ cache/                         # Session/runtime cache artifacts
    ├─ copilot-instructions.md        # Workspace-level instruction set
    ├─ config/                        # Policy-related YAML files
    │   ├─ agent-commands.yaml          # Build/test/lint/coverage command manifest
    │   ├─ default-config.yaml          # Org-wide configuration baseline
    │   └─ guardrails.yaml              # Governance rules and quality thresholds
    └─ README.md                      # Framework README
```

After installation, the contents of `base/` appear at the corresponding `.github/` paths, such as `.github/agents/` and `.github/skills/`.

---

## Quick Start (2 minutes)

1. Clone the repo, run the framework installer, and open VS Code.
2. Make sure Copilot agent mode is enabled.
3. Select **Do It** in the Chat agent/mode picker, enter `show the menu`, and choose option **1 — Validate my environment** to materialize the canonical runtime configuration snapshot and create the setup cache.
4. Open the Chat agent/mode picker and confirm that **Deva** appears.
5. Select **Deva** in the picker and start the workflow with **`work on [YOUR-JIRA-KEY]`**.
6. Answer checkpoint questions and review each generated change; Deva coordinates commits, story-branch publishing, and conditional direct or stacked draft PR delivery through the owning stages.

> After installation and the one-time environment validation, VS Code auto-discovers the agents and skills from this repository layout.
> Skills also appear as `/` slash commands, so typing `/` shows what is available.

---

## Key Takeaways

| Before | After |
| --- | --- |
| Jira stories are interpreted manually | Story Analyst reads the ticket and asks the right follow-up questions |
| One large story becomes one large PR | Orchestrator breaks the work into small, reviewable subtasks |
| Tests are added late, or not at all | Tester generates tests alongside the code, targeting ≥80% coverage |
| QA happens only after a PR is opened | QA runs during development, before the PR becomes a surprise |
| An interrupted story means re-doing work from scratch | Dev Assistant resumes the end-to-end flow from your last approved checkpoint; specialists still run standalone as fresh, cold-start tasks |
| Critical context lives in senior developers' heads | Team workflow lives in `agents/` and `skills/`, version-controlled with the repo |
| New developers need weeks or months to learn the process | A new developer can clone the repo, select Deva, and enter `work on [JIRA]` |
