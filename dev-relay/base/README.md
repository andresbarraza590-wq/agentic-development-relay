# Agentic AI Instruction Framework

Configure and validate your environment, then run Deva through a guided menu or the end-to-end development pipeline.

Quick link: [<INTERNAL_QUICK_LINK>](https://<INTERNAL_QUICK_LINK>)

Version: 2.3.0

[Release policy](#appendix-e-release-versioning)

## Table of Contents

- [About Deva](#about-deva)
- [Environment Setup](#environment-setup)
- [Install Framework Runtime Dependencies](#install-framework-runtime-dependencies)
- [Configure the Required MCP Integrations](#configure-the-required-mcp-integrations)
- [Enable Nested Agent Support in VS Code](#enable-nested-agent-support-in-vs-code)
- [Configure AI Co-Author Tagging in VS Code](#configure-ai-co-author-tagging-in-vs-code)
- [Configure Optional Integrations](#configure-optional-integrations)
- [Optional: Configure IntelliJ](#optional-configure-intellij)
- [Quick Start: Validate, Bootstrap, and Run](#quick-start-validate-bootstrap-and-run)
- [Installed File Layout](#installed-file-layout)
- [Recommended Reading](#recommended-reading)
- [Future Work](#future-work)
- [Metrics and Reporting](#metrics-and-reporting)
- [Operational Notes](#operational-notes)
- [Questions and Answers](#questions-and-answers)
- [Troubleshooting](#troubleshooting)
- [Debugging Agent Runs](#debugging-agent-runs)
- [Appendix A: Claude Code Mirror](#appendix-a-claude-code-mirror)
- [Appendix B: Runtime Model Assignments](#appendix-b-runtime-model-assignments)
- [Appendix C: Installed Directory Structure](#appendix-c-installed-directory-structure)
- [Appendix D: Optional Git Hook Enforcement](#appendix-d-optional-git-hook-enforcement)
- [Appendix E: Release Versioning](#appendix-e-release-versioning)
- [Appendix F: Operational Reference](#appendix-f-operational-reference)

## About Deva

The Agentic AI Instruction Framework provides reusable agents, skills, and instructions that teams and individuals can extend without changing the base framework. It builds on established instruction ecosystems, most notably <BASE_ENGINEERING_ECOSYSTEM> (the <ORG_NAME> Engineer), instead of replacing them.

We call the framework Dev Assistant, or **Deva** — pronounced "dee-vah," like "diva." Deva orchestrates the development workflow from Jira analysis through implementation, review delivery, integration, final documentation, and archival.

Deva is currently VS Code-first and uses Copilot Nested Agents. The installer also generates a Claude Code mirror; see [Appendix A: Claude Code Mirror](#appendix-a-claude-code-mirror).

![Deva — the Agentic AI Instruction Framework](images/deva.png)

## Environment Setup

Complete the three required VS Code sections below before your first Deva run. Optional integrations can be added later and do not block the core workflow.

**<BASE_ENGINEERING_ECOSYSTEM> compatibility is mandatory; local <BASE_ENGINEERING_ECOSYSTEM> installation is optional.** Agents and overlays must preserve <BASE_ENGINEERING_ECOSYSTEM> conventions and gracefully handle unavailable <BASE_ENGINEERING_ECOSYSTEM> capabilities. A developer without <BASE_ENGINEERING_ECOSYSTEM> installed can install, validate, and run the framework; <BASE_ENGINEERING_ECOSYSTEM> documentation searches and <BASE_ENGINEERING_ECOSYSTEM>-owned tools, prompts, and configuration are skipped or reported as degraded without blocking the SDLC workflow.

### Install Framework Runtime Dependencies

The configuration resolver requires the Python packages declared by the installed framework. From the workspace root, run:

```powershell
python -m venv .venv
& .\.venv\Scripts\Activate.ps1
python -m pip install -r .github/scripts/requirements.txt
```

Setup validation blocks with these commands when the dependency is unavailable. It does not install packages automatically or fall back to model-performed YAML parsing.

### Configure the Required MCP Integrations

Install and configure the Jira and <INTERNAL_KNOWLEDGE_ASSISTANT> MCP servers in VS Code Copilot:

- **Jira MCP:** [<INTERNAL_MCP_PLATFORM> Jira MCP server setup guide](<JIRA_MCP_SETUP_GUIDE_URL>). Jira connectivity is required and blocking for ticket-driven workflows.
- **<INTERNAL_KNOWLEDGE_ASSISTANT> MCP:** [<INTERNAL_KNOWLEDGE_ASSISTANT> MCP server setup guide (supports Confluence Wiki)](<KNOWLEDGE_ASSISTANT_MCP_SETUP_GUIDE_URL>). <INTERNAL_KNOWLEDGE_ASSISTANT> is strongly recommended for <ORG_NAME> internal-document enrichment. It is non-blocking: when it cannot connect, Deva reports degraded mode and continues without internal-document enrichment. See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

### Enable Nested Agent Support in VS Code

To use the nested agent `.md` files in this project, enable the **Use Nested Agents** and **Allow Invocation from Subagents** settings in VS Code:

1. Open VS Code Settings by pressing **`Ctrl + ,`**
2. In the search bar, type **`useNestedAgents`**
3. Check the box to enable the **Use Nested Agents** setting
4. In the search bar, type **`subagent`**
5. Check the box to enable the **Allow Invocation from Subagents** setting
6. Restart or reload VS Code if prompted

### Configure AI Co-Author Tagging in VS Code

Enable AI co-author trailers so generated commits are properly attributed.

1. Open Settings (`Ctrl + ,`)
2. Search for **AI Co-Author**
3. Set to **all**

Optional JSON path:

1. Open Command Palette (`Ctrl + Shift + P`)
2. Select **Open User Settings (JSON)**
3. Add:

```json
"git.addAICoAuthor": "all"
```

Workspace enforcement at `.vscode/settings.json`:

```json
{
  "git.addAICoAuthor": "all"
}
```

### Configure Optional Integrations

These integrations can enrich Deva but are not required for the core workflow:

- **Optional:** [<INTERNAL_MCP_PLATFORM> Confluence MCP server setup guide](<CONFLUENCE_MCP_SETUP_GUIDE_URL>).
- **Optional:** [<INTERNAL_MCP_PLATFORM> Stack Overflow MCP server setup guide](<STACKOVERFLOW_MCP_SETUP_GUIDE_URL>).

### Optional: Configure IntelliJ

If your team also uses IntelliJ, configure Copilot and co-author tagging as a compatibility setup.

1. Install and enable the **GitHub Copilot** plugin
2. In IntelliJ settings, enable native co-author trailer support if available
3. If native support is unavailable, use a repository fallback:
   - a git commit template (`.gitmessage`) with `Co-Authored-By` trailer guidance, or
   - a `.githooks/commit-msg` hook that appends the trailer

## Quick Start: Validate, Bootstrap, and Run

After completing the required [Environment Setup](#environment-setup):

1. Open the workspace in VS Code and start Copilot Chat in agent mode. Open it by the workspace's **physical path** rather than the mapped `I:` drive — otherwise VS Code treats framework runtime files as edits outside your workspace and prompts **Allow Once** on every session and activity write ([details](docs/TROUBLESHOOTING.md#why-does-the-agent-still-prompt-to-edit-github-files-as-outside-your-workspace-even-with-auto-approve-set)). If <BASE_ENGINEERING_ECOSYSTEM> is installed, initialize it first:

   ```bat
   REM Run sage only when <BASE_ENGINEERING_ECOSYSTEM> is installed
   sage
   cd /d "C:\Users\%USERNAME%\<WORKSPACE_PROJECTS_DIR>\<workspace-name>"
   code .
   ```

2. In the Chat agent/mode picker, select **Do It**, enter `show the menu`, and choose option 1, **Validate my environment**. A current PASS cache is returned without rerunning validation. When the cache is missing or stale, or revalidation is explicitly requested, this materializes the canonical runtime configuration snapshot before checking the environment. Run validation on its own before feature work so one-time MCP authorization can complete while the chat is idle.

3. Once validation passes, select **Do It** again, enter `show the menu`, and choose option 2, **Bootstrap or check architecture context**. The first run inventories every confirmed repository, deeply traces its architecture-relevant surfaces, records per-repository coverage, and generates the context files only after that baseline is complete. Later runs check coverage and meaningful drift and may propose a refresh.

4. Start work through either entry point:
   - **Full pipeline:** select **Deva** in the Chat agent/mode picker, then enter `work on <JIRA-KEY>` — for example, `work on PROJ-1234` — to orchestrate the complete workflow.
   - **Guided menu:** select **Do It** in the picker, then enter `show the menu` to choose a full pipeline, one pipeline stage, implementation, tests, review, ticket analysis, or environment validation.

5. Answer the prompts, review plans and checkpoints, and approve execution when ready.

You are ready when environment validation passes, architecture context is present, and Deva accepts your Jira key or Do It selection without a setup blocker.

> **Keeping this framework current:** if you installed through the optional `deva` command, run `deva update` to refresh the framework, then reinstall into your workspace with `deva --workspace <name> --backup --skip-overlay`. If you install by calling `install.bat` directly, keep using that command — both paths are supported.

New to the framework internals? Read [Design of Deva](docs/DESIGN-DEVA.md) for the end-to-end pipeline and [Design of Do It](docs/DESIGN-DO-IT.md) for guided routing and stateful versus stateless runs. For runtime model assignments, see [Appendix B: Runtime Model Assignments](#appendix-b-runtime-model-assignments).

> **Affected recent VS Code versions, including 1.133:** select the custom agent in the Chat agent/mode picker. Typing `@deva` or `@do-it` into the default Agent chat may not switch the root agent; it can add an unintended nested handoff and hide Model Context Protocol (MCP) tool confirmations. The legacy agent names `da`, `pc`, `ko`, `kickoff`, `development-assistant`, and `pipeline-controller` are no longer supported.

## Installed File Layout

Most users do not need to inspect the generated file layout. For the complete technical reference, see [Appendix C: Installed Directory Structure](#appendix-c-installed-directory-structure).

## Recommended Reading

Read these in order:

1. **[Design of Deva](docs/DESIGN-DEVA.md)** — Authoritative end-to-end design for the Deva pipeline, stage ownership, checkpoints, and orchestration lifecycle.
2. **[Design of Do It](docs/DESIGN-DO-IT.md)** — Authoritative design for guided routing, menu behavior, and stateful versus stateless execution.
3. **[Agent Guide](docs/AGENT-GUIDE.md)** — Primary reference for agent and skill design, orchestration flow, and customization patterns. Start here to understand setup, invocation patterns, and end-to-end workflow checkpoints.
4. **[Agent Metrics](docs/AGENT-METRICS.md)** — Measurement framework for tracking agent effectiveness across PR quality, cycle time, and delivery outcomes (PR outcomes, QA signals, tester outputs, and AC validation results). Revisit it during retrospectives to identify which agents or prompts need tuning for the next sprint.
5. **[Metrics Checklist](docs/AGENT-METRICS-CHECKLIST.md)** — Operational checklist for PR, weekly, and sprint reporting. Apply it as the standard format for PR-level, weekly, and sprint reporting.
6. **[Demo Presentation](docs/DEMO.md)** — Walkthrough deck for team demos, including narrative flow, live demo sequence, and key talking points.

## Future Work

The planned target design for Deva and Do It preserves the staged-checkpoint approach while planning clearer ownership boundaries, a smaller Deva orchestration kernel, unified Do It routing, consistent checkpoint presentation, replay-safe workflow state, and more efficient specialist handoffs:

- **[Deva and Do It Roadmap](docs/DESIGN-ROADMAP.md)** — Concise target-design overview, checkpoint journey, priorities, and delivery sequence.
- **[Deva and Do It Roadmap Details](docs/DESIGN-ROADMAP-DETAILS.md)** — Original expanded design with detailed rationale, ownership boundaries, checkpoint impacts, and acceptance criteria.

These documents describe future direction rather than current runtime behavior. For the implemented architecture narrative, see [Design of Deva](docs/DESIGN-DEVA.md) and [Design of Do It](docs/DESIGN-DO-IT.md); runtime behavior remains governed by the resolved configuration and reached agent, skill, and prompt instructions.

## Metrics and Reporting

The metrics documents are manual reporting templates and future automation designs. The current agent pipeline does not write repository JSONL telemetry or update metrics files automatically.

Teams can record outcomes manually in:

- [Agent Metrics Rollup](docs/AGENT-METRICS-ROLLUP.md) (story, repository, aggregate, and interaction metrics)
- [Agent Test Metrics](docs/AGENT-TEST-METRICS.md) (test origin and correction summaries)

## Operational Notes

- A successful full pipeline run writes a Confluence-ready immutable Post-Action report to `.github/artifacts/sessions/<JIRA-KEY>/report.<REPORT-IDENTITY>.md`.
- Branches use the canonical hierarchy `develop` → `feature/<user>/<PARENT-JIRA>` → `feature/<user>/story/<PARENT-JIRA>`. All implementation and fixes land on the story branch first.
- Step 8 routes by slice count. One slice integrates the complete canonical story additively into feature and opens one feature-to-`develop` draft PR. Multiple slices use contiguous `feature/<user>/story/<PARENT-JIRA>-PR<N>` branches in one linear stack; no slice Jira subtasks or descriptive slugs are created.
- For a stack, review PR1 toward the tip and collapse tip toward PR1 with current checks and approval at each changed parent. After matching the story tree and landing in feature at C8c, reactive Step 8d automatically creates or reconciles the final feature-to-`develop` draft PR. C8d retains human review, approval, and merge authority. Never push directly to `develop`, force-push, squash, or rebase-merge.

For session storage, retention, report regeneration, customization, and enforcement details, see [Appendix F: Operational Reference](#appendix-f-operational-reference).

## Questions and Answers

See **[Questions and Answers](docs/QNA.md)** for conceptual guidance about supported knowledge integrations, how pipeline stages use those sources, MCP authorization reuse, and the rationale for parent-targeted stacked pull requests.

## Troubleshooting

See **[Troubleshooting](docs/TROUBLESHOOTING.md)** for symptom-driven diagnosis and recovery — missing MCP registration, stale setup validation, Dev Assistant hanging after handoff, hidden nested subagent prompts, querying a run's raw session logs, and optionally auto-approving Copilot's file edits under `.github/` (a security trade-off — read the caveats before enabling it).

## Debugging Agent Runs

Need to know exactly what happened in a run — which agents ran, who handed off to whom, which tools were called, how long each step took, and where it failed? See **[Debugging Agent Runs](docs/DEBUGGING.md)**. It reconstructs a faithful, application-level trace from Copilot's raw debug logs, which you can generate with `render-agent-trace.ps1` directly or through the read-only `/debug-sessions` prompt.

## Appendix A: Claude Code Mirror

The installer also mirrors the framework into the [Claude Code](https://docs.claude.com/claude-code) layout, so the same agents, skills, and instructions run on both runtimes. Alongside `.github/`, each install generates:

- `CLAUDE.md` at the workspace root — from `copilot-instructions.md`.
- `.claude/agents/*.md` — each Copilot agent transformed into a Claude Code subagent (frontmatter translated to `name`/`description`/`tools`/`model`; body preserved). Claude-family model assignments map to Claude Code aliases; provider-specific assignments without a Claude alias omit `model` and inherit the selected Claude Code model. Supported native tool restrictions are mapped so read-only agents stay read-only; unsupported MCP or unknown tokens are omitted without broadening the mapped restrictions, and a list containing only unsupported tokens becomes an explicit empty tool list.
- `.claude/skills/` — copied as-is (`SKILL.md` is compatible across both runtimes).
- `.claude/commands/*.md` — each Copilot prompt (`prompts/*.prompt.md`) transformed into a Claude Code slash command (frontmatter translated to `description`/`argument-hint`/`allowed-tools`/`model` when a Claude alias exists, the Copilot-only `agent` dropped; prompts without frontmatter keep just their body).
- Governance YAML (`config/guardrails.yaml`, `config/default-config.yaml`, `config/agent-commands.yaml`) — copied for self-containment. `guardrails.yaml` and `default-config.yaml` are **install-protected**: they always come from the base, and no overlay tier (workspace, repo, or local) can override them in `.github/config/` or in this `.claude/` mirror. Only `agent-commands.yaml` and `team-config.yaml` are overlay-customizable.

`.github/` remains the single source of truth. The `.claude/` layout and `CLAUDE.md` are generated at install time — do not edit them by hand. Edit the base assets and re-run the installer.

## Appendix B: Runtime Model Assignments

Each agent or slash-command prompt declares an explicit Copilot `model:` in its frontmatter so its Copilot runtime tier is intentional rather than inherited. Agents and prompts are assigned by tier so each one's model matches its reasoning needs: Opus 4.8 for correctness-critical orchestration, code generation, and review; Sonnet 4.8 for balanced drafting, validation, and bookkeeping; Haiku 4.8 for mechanical routing and deterministic checks; and GPT-5.6 Sol for the independent static audits. The Claude Code mirror maps Claude-family assignments to native aliases; a provider-specific assignment without a Claude alias, such as GPT-5.6 Sol, inherits the selected Claude Code model. Four Copilot assignments are used across agents and prompts:

- **Opus 4.8** — heavy reasoning and code generation, where depth and correctness matter most (`deva`, `implementation-partner`, `qa`, `architecture-bootstrapper`, and the `/dry-run-deva` / `/diff-deva` prompts).
- **Sonnet 4.8** — balanced drafting, validation, and bookkeeping (`story-analyst`, `acceptance-checker`, `tester`, `subbranch-extractor`, `integration-publisher`, `documenter`, and the `/update-deva` / `/debug-logs` / `/debug-sessions` / `/plot-deva` prompts).
- **Haiku 4.8** — mechanical routing and deterministic checks (`do-it`, `setup-validator`, `branch-manager`, `branch-publisher`, `regression-runner`, and the `/measure-deva` prompt).
- **GPT-5.6 Sol** — comprehensive static auditing of the framework or a workspace's architecture artifact set.

| Agent or prompt | Model | Rationale |
| --- | --- | --- |
| `implementation-partner` | Opus 4.8 | Writes, edits, and runs code. |
| `qa` | Opus 4.8 | Hunts bugs, edge cases, and quality flaws. |
| `tester` | Sonnet 4.8 | Designs exhaustive test coverage. |
| `architecture-bootstrapper` | Opus 4.8 | Bootstraps architecture context via a one-time deep trace across every confirmed repository. |
| `deva` | Opus 4.8 | Orchestrates the SDLC, including stage routing, checkpoints, session bookkeeping, and high-risk decomposition decisions. |
| `story-analyst` | Sonnet 4.8 | Reads Jira and interviews the developer to produce instructions. |
| `acceptance-checker` | Sonnet 4.8 | Validates scope and acceptance criteria. |
| `setup-validator` | Haiku 4.8 | Runs environment and health checks. |
| `branch-manager` | Haiku 4.8 | Creates the feature and story branches. |
| `branch-publisher` | Haiku 4.8 | Verifies the suite is green and pushes the story branch. |
| `regression-runner` | Haiku 4.8 | Requests and records the developer's explicit regression result. |
| `subbranch-extractor` | Sonnet 4.8 | Prepares direct or stacked review delivery and opens authorized draft PRs. |
| `integration-publisher` | Sonnet 4.8 | Creates or reconciles the final stacked feature-to-`develop` draft PR after C8c. |
| `documenter` | Sonnet 4.8 | Generates the story wrap-up / Post-Action report. |
| `do-it` | Haiku 4.8 | Presents the menu and routes to the right agent. |
| `/debug-logs` (prompt) | Sonnet 4.8 | Correlates `activity.log`, `session.md`, and debug logs into one time-sequential run timeline (read-only). |
| `/debug-sessions` (prompt) | Sonnet 4.8 | Renders and interprets a single finished session's debug-log trace (read-only). |
| `/dry-run-deva` (prompt) | Opus 4.8 | Sequentially interprets the authoritative pipeline instructions from Stage 0 through Stage 10 without mutating anything, discovering each stage's agents, skills, and inputs only when reached (writes only its own trace log). |
| `/diff-deva` (prompt) | Opus 4.8 | Reconciles a run against a sequential oracle derived from the current authoritative instructions (or compares two traces, checks trace conformance, or — under design authority — checks a dry-run or a real run against the `DESIGN-DEVA.md` design document), surfacing the earliest unexplained divergence and classifying every difference (pipeline-state read-only; retrospective mode writes/reuses a validated oracle cache). |
| `/plot-deva` (prompt) | Sonnet 4.8 | Charts where a run spends its minutes — per-stage/checkpoint duration and cumulative time for one story's latest completed run, or a box-and-whisker across every completed run; `ai` mode additionally sets aside evidenced human-pause samples and discloses each exclusion (writes self-contained HTML with inline SVG and, on default output, rotates that chart family with `--keep`). |
| `/measure-deva` (prompt) | Haiku 4.8 | Measures Copilot activity between two Deva boundaries; reports exact tokens only from cloud usage events and otherwise reports clearly labeled local activity proxies (read-only). |
| `/update-deva` (prompt) | Sonnet 4.8 | Propagates completed framework changes through documentation, versions, and release notes, then commits and pushes each applicable repository without creating a pull request. |
| `/audit-deva` (prompt) | GPT-5.6 Sol | Completes the full layered static audit, builds a verified ledger, and presents findings (read-only until approval). |
| `/audit-artifacts` (prompt) | GPT-5.6 Sol | Audits architecture artifacts and their derived Markdown/HTML views with lifecycle-aware requiredness (read-only until approval). |

**Skills do not carry a functional model.** A `model:` line in a `SKILL.md` is ignored by the runtime — a skill always executes under the model of the agent that invoked it. Only agents (and slash-command prompts) can set their own model. Overlays follow the same convention for any agents and prompts they add.

## Appendix C: Installed Directory Structure

The installer generates the following framework layout under `.github/`. This reference is intended for maintainers and users who need to inspect or customize framework internals.

```text
.github/
├── agents/                          # agent definitions (.agent.md)
│   ├── deva.agent.md                # Recommended entry point (select Deva in the agent/mode picker)
│   ├── do-it.agent.md               # Guided menu entry point (select Do It in the agent/mode picker)
│   ├── setup-validator.agent.md     # Subagent — environment validation gate
│   ├── architecture-bootstrapper.agent.md # Subagent — architecture bootstrap (Step 0b)
│   ├── implementation-partner.agent.md      # Subagent — writes code
│   ├── story-analyst.agent.md       # Subagent — Jira → instructions
│   ├── acceptance-checker.agent.md  # Subagent — AC + scope validation
│   ├── qa.agent.md                  # Subagent — quality review
│   ├── tester.agent.md              # Subagent — test generation
│   ├── branch-manager.agent.md      # Subagent — creates feature/story branches (git)
│   ├── branch-publisher.agent.md    # Subagent — pushes the story branch
│   ├── regression-runner.agent.md   # Subagent — developer regression loop
│   ├── subbranch-extractor.agent.md # Subagent — review subbranches + draft PRs
│   ├── integration-publisher.agent.md       # Subagent — final stacked integration PR
│   └── documenter.agent.md          # Subagent — story wrap-up doc
├── skills/                          # 21 reusable skills (SKILL.md)
│   ├── acceptance-criteria-validation/
│   ├── architecture-diagram/
│   ├── code-coverage/
│   ├── code-implementation/
│   ├── code-review/
│   ├── codebase-discovery/
│   ├── configuration-resolution/
│   ├── documentation-generation/
│   ├── error-handling/
│   ├── integration-publication/
│   ├── jira-analysis/
│   ├── mocking-patterns/
│   ├── parallel-build-dispatch/
│   ├── pipeline-session/
│   ├── pr-scoping/
│   ├── progress-tracking/
│   ├── prompt-structuring/
│   ├── security-basics/
│   ├── story-refinement/
│   ├── subbranch-extraction/
│   └── test-generation/
├── prompts/                         # Slash-command prompts (.prompt.md)
│   ├── audit-artifacts.prompt.md    # Standalone — architecture artifact audit (/audit-artifacts)
│   ├── audit-deva.prompt.md         # Standalone — static framework audit (/audit-deva)
│   ├── debug-logs.prompt.md         # Standalone — unified multi-source run timeline (/debug-logs)
│   ├── debug-sessions.prompt.md     # Standalone — single-session trace analyst (/debug-sessions)
│   ├── dry-run-deva.prompt.md       # Standalone — sequential, non-mutating instruction interpreter (/dry-run-deva)
│   ├── diff-deva.prompt.md          # Standalone — reconcile a run vs. an instruction-derived oracle or the DESIGN-DEVA.md design (/diff-deva)
│   ├── plot-deva.prompt.md          # Standalone — chart timing as self-contained HTML with inline SVG (/plot-deva)
│   ├── measure-deva.prompt.md       # Standalone — measure Copilot activity between Deva boundaries (/measure-deva)
│   └── update-deva.prompt.md        # Standalone — documentation, version, release, commit, and push maintenance (/update-deva)
├── scripts/                         # Deterministic utilities — configuration resolver, log tracer, and Git hooks
│   ├── requirements.txt             # Framework Python runtime dependencies
│   ├── configuration/resolve-config.py        # Configuration materialize/verify/read executable
│   ├── configuration/test-resolve-config.py   # Configuration resolver unit tests
│   ├── diagnostics/diff-deva.py     # /diff-deva reconciler core — parse, comparability gate, normalize, align
│   ├── diagnostics/retrospective-diff-deva.py # Decision extraction, oracle validation/cache, retrospective reconciliation
│   ├── diagnostics/test-diff-deva.py          # Reconciler core unit tests
│   ├── diagnostics/test-retrospective-diff-deva.py # Retrospective wrapper unit tests
│   ├── diagnostics/plot-deva.py     # /plot-deva timing plotter core — render HTML with inline SVG
│   ├── diagnostics/test-plot-deva.py          # Timing plotter core unit tests
│   ├── diagnostics/run-with-timeout.py        # Bounded external-check watchdog — process-group timeout with JSON outcome
│   ├── diagnostics/test-run-with-timeout.py   # Timeout watchdog unit tests
│   ├── skills/test-checkpoint-decisions.py    # Semantic checkpoint decision regression tests
│   ├── logs/render-agent-trace.ps1
│   └── githooks/
├── docs/                            # Framework docs, metric templates, and guides
│   ├── DESIGN-DEVA.md               # Authoritative Deva pipeline design
│   ├── DESIGN-DO-IT.md              # Authoritative Do It routing design
│   ├── DESIGN-ROADMAP.md            # Target-design overview and delivery sequence
│   ├── DESIGN-ROADMAP-DETAILS.md    # Expanded target-design rationale
│   ├── AGENT-GUIDE.md               # Team onboarding and workflow guide
│   ├── AGENT-METRICS.md             # Metrics framework
│   ├── DEBUGGING.md                 # How to trace and debug an agent run
│   ├── DEMO.md                      # Team demo walkthrough
│   ├── QNA.md                       # Conceptual framework questions and answers
│   ├── TROUBLESHOOTING.md           # Solutions to common issues
│   └── (AGENT-METRICS-CHECKLIST.md, AGENT-METRICS-ROLLUP.md, AGENT-TEST-METRICS.md — metrics templates)
├── images/                          # README image assets (PNG)
├── artifacts/                       # Durable framework artifacts; local-only and gitignored
│   ├── architecture-metadata.json   # Canonical machine-readable architecture context
│   ├── repo-inventory.json          # Repository membership, routing, and drift baseline manifest
│   └── sessions/                    # Archived session.md and immutable report.<REPORT-IDENTITY>.md per Jira key
├── cache/                           # Resolved configuration, reusable diagnostics, and live sessions; sessions archive on completion
│   ├── config/resolved-config.json  # Runtime-owned, validated default/team configuration snapshot
│   ├── diagnostics/diff-deva/oracles/ # Validated decision-matched oracle cache
│   └── sessions/                    # Setup report and live per-Jira session.md files
├── logs/                            # Per-Jira activity log (activity.log) and reuse index; written by the Dev Assistant; kept for post-mortem
├── config/                          # Policy-related YAML files
│   ├── agent-commands.yaml          # Build/test/lint/coverage command manifest
│   ├── default-config.yaml          # Org-wide configuration baseline
│   └── guardrails.yaml              # Governance rules and quality thresholds
├── copilot-infra-nutshell.md        # <ORG_NAME> infrastructure orientation (linked from copilot-instructions.md)
├── copilot-instructions.md          # Workspace-level instruction set
└── README.md                        # Framework README
```

## Appendix D: Optional Git Hook Enforcement

The framework ships optional Git hooks in `.github/scripts/githooks/` that enforce the hard Git rules deterministically, so they hold even if an agent ignores its prose. After a per-repo install, activate them from the repository root:

```bash
bash .github/scripts/githooks/install-hooks.sh
```

The installer requires a Unix-compatible shell. On Windows, run it from Git Bash, WSL, or another environment that provides `bash` and standard POSIX utilities.

This copies the active, extensionless hooks into Git's private `.git/framework-hooks/` directory, sets `core.hooksPath` to that directory, and enables:

- **pre-push** — installed from `pre-push.sh`; blocks direct pushes to `develop`/`master`/`main`/`release/*` and non-fast-forward (force) pushes.
- **pre-commit** — installed from `pre-commit.sh`; rejects staged secrets/credentials and files larger than 5 MiB (5,242,880 bytes).
- **post-commit** — installed from `post-commit.sh`; appends a local JSON audit line inside `.git` (never dirties the working tree).

> Agent-lifecycle hooks (PreToolUse/PostToolUse) are intentionally not shipped: they are a Claude Code feature and are not supported by the VS Code Copilot agent runtime today.

## Appendix E: Release Versioning

Versions are scoped to individual framework layers, not to the assembled installation:

- The `Version:` lines in the repository `README.md` and `base/README.md` identify the base framework release and must match each other.
- `overlays/workspace/NOTE-OVERLAY.md` identifies the workspace overlay release.
- Each `overlays/repo/<name>/NOTE-REPO.md` identifies that repository overlay's release.
- Each `overlays/local/<name>/NOTE-LOCAL.md` identifies that local overlay's release.

The base framework, workspace overlay, and each repository and local overlay maintain independent release cadences. Their version numbers do not need to match the base or one another. Compare a version only with earlier releases of the same layer; a numerically higher version in one layer does not mean the complete installation is newer than another installation.

Every layer uses `<major>.<minor>.<patch>` versioning and advances its own version by exactly one level according to the impact of that layer's changes:

- **Patch** for a small, backward-compatible fix, such as `2.1.3` to `2.1.4`.
- **Minor** for a larger, backward-compatible change, resetting the patch to zero, such as `2.1.4` to `2.2.0`.
- **Major** for a breaking or foundational change, resetting the minor and patch to zero, such as `2.2.0` to `3.0.0`.

## Appendix F: Operational Reference

### Reports and Session Artifacts

- After draft review delivery opens, Deva pauses for humans. Requested changes land on the canonical story branch first, then propagate additively to feature in direct mode or through the affected stack suffix.
- Direct `review complete` at C8c includes the feature-to-`develop` merge. Stacked C8c includes stack collapse and PR1-to-feature landing, then triggers Stage 8d; only C8d `integration complete` establishes the final stacked merge before Deva generates the report.
- After the C10 `archive session` decision, the completed full-run session is archived beside the report as `.github/artifacts/sessions/<JIRA-KEY>/session.md`. Single-stage runs leave their live session at `.github/cache/sessions/<JIRA-KEY>/session.md` for later continuation.
- Reports and archived sessions are local, gitignored runtime artifacts for retrospectives, audits, troubleshooting, and implementation traceability. The activity log remains at `.github/logs/<JIRA-KEY>/activity.log`; archive and log retention follow `pipeline.archive_retention_days`.

### Customization and Enforcement

- Teams and individuals may customize the shipped **[Copilot Instructions](copilot-instructions.md)** through a workspace, repository, or local overlay. When the scaffold has not been populated, the architecture bootstrap fills its project-context sections from verified source evidence.
- Repositories may optionally enforce hard Git rules with the hooks described in [Appendix D: Optional Git Hook Enforcement](#appendix-d-optional-git-hook-enforcement).
