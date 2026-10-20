# Debugging Agent and Pipeline Runs

The framework provides seven debugging tools. The first three form the read-only foundation for completed-run analysis:

- `render-agent-trace.ps1` is the deterministic extractor for one Copilot chat session. It converts a current transcript or legacy debug-log session into a redacted trace and makes no model calls.
- `/debug-sessions` invokes the tracer and interprets one Copilot chat session: agent handoffs, tool requests and executions, confirmations, timings, MCP lifecycle, and runtime failures.
- `/debug-logs` investigates a Jira-keyed Deva run: it uses the tracer for each relevant Copilot session, then weaves that runtime evidence together with the pipeline event history and latest durable state.

The two slash commands are after-the-fact model interpreters; the script is their deterministic extraction substrate and can also be run directly. All three are read-only. Never run either prompt inside the live pipeline it is analyzing.

A fourth tool, `/dry-run-deva`, is the forward-looking counterpart: instead of interpreting a run that already happened, it **sequentially interprets** the authoritative pipeline instructions for a Jira key without mutating anything. It starts at Stage 0 and reads each stage's Deva section, referenced agents and skills, and operational inputs only when that stage is reached, emitting an instruction-level trace of every rule evaluated, decision taken, and side effect a real run would perform. Use it to debug the pipeline logic itself when there is no run to analyze yet. Like the other three, it is non-mutating — its only write is its own trace log — and it never runs inside a live pipeline.

A fifth tool, `/diff-deva`, closes the loop between the other two: it puts a simulation and a real run side by side and reconciles them. It generates a decision-matched, sequential dry-run oracle from the authoritative runtime instructions, aligns it with a real run's `activity.log` onto one common event algebra, and reports the earliest *unexplained* divergence — classifying every difference as a real bug, a model misprediction, an explained decision, or uncovered ground. Use it to answer "did this run follow its governing instructions, and if not, whose fault is it?" It refuses when the two runs' resolved config fingerprints can't be matched (a genuine framework-version or schema difference refuses too, while a field that is merely unavailable on one side only warns). Retrospective mode writes or reuses its validated oracle cache, and an optional report may also be written. Under *design authority* the same tool instead measures a dry-run or a real run against the `DESIGN-DEVA.md` design document, classifying each divergence as implementation-drift or design-staleness.

A sixth tool, `/plot-deva`, asks the quantitative question the others leave open: *where does the time go?* It reads the same append-only, ISO-8601 UTC `activity.log` timestamps and renders them as self-contained HTML charts with inline SVG — with a Jira key, the story's latest completed run as a per-segment duration histogram and cumulative-elapsed curve; without one, a box-and-whisker ("candlestick") per stage or checkpoint across every completed run, exposing which segments are slow on average and which runs inflate the tails. Passing the `ai` argument (`/plot-deva ai`) reruns that aggregate after a contextual review that sets aside only explicitly evidenced human-pause or interrupted-session samples, disclosing every exclusion and its raw duration below the chart while leaving the logs untouched. Like the others it is read-only and never runs inside a live pipeline; its only write is the chart artifact under `.github/artifacts/plots/`.

A seventh tool, `/measure-deva`, measures Copilot activity inside one exact Deva interval. It resolves stage, checkpoint, milestone, or run boundaries from `activity.log`, correlates the Copilot sessions in that half-open time window, and reports elapsed time, turns, compactions, and indexed text volume. Exact input/output tokens are reported only from cloud `assistant.usage` events; when cloud session sync is unavailable, it reports `UNAVAILABLE` for tokens and keeps the local metrics clearly labeled as activity proxies. It is read-only and never estimates tokens from character counts.

- [Choose the right debugging tool](#choose-the-right-debugging-tool)
- [What the tracer does](#what-the-tracer-does)
- [Run the script directly](#run-the-script-directly)
- [Command options](#command-options)
- [Use the `/debug-sessions` prompt](#use-the-debug-sessions-prompt)
- [Use the `/debug-logs` prompt](#use-the-debug-logs-prompt)
- [Use the `/dry-run-deva` prompt](#use-the-dry-run-deva-prompt)
- [Use the `/diff-deva` prompt](#use-the-diff-deva-prompt)
- [Use the `/plot-deva` prompt](#use-the-plot-deva-prompt)
- [Use the `/measure-deva` prompt](#use-the-measure-deva-prompt)
- [Understand the three pipeline sources](#understand-the-three-pipeline-sources)
- [Interpret a unified pipeline timeline](#interpret-a-unified-pipeline-timeline)
- [Diagnose a stalled tool or hidden confirmation](#diagnose-a-stalled-tool-or-hidden-confirmation)
- [How agent relationships are reconstructed](#how-agent-relationships-are-reconstructed)

## Choose the right debugging tool

| Question or available identifier | Tool | Scope |
| --- | --- | --- |
| I need a deterministic trace without model interpretation | `render-agent-trace.ps1` | One Copilot session; current transcript or legacy debug-log format |
| What happened in this chat session? | `/debug-sessions <sessionId>` | One Copilot session |
| Why did one agent or tool run twice? | `/debug-sessions <sessionId>` | One Copilot session |
| Why did a requested tool never start? | `/debug-sessions <sessionId>` | Request, confirmation, execution, and MCP lifecycle |
| What happened across the complete Jira story run? | `/debug-logs <JIRA-KEY>` | Pipeline events, state, and all correlated Copilot sessions |
| Why is a stage still `in_progress`? | `/debug-logs <JIRA-KEY>` | Stage event history plus runtime handoff/tool evidence |
| Did the pipeline state disagree with what the chat reported? | `/debug-logs <JIRA-KEY>` | `activity.log` versus `session.md` versus Copilot logs |
| I have only `latest`, a session ID, or a log path | Either command | Session scope first; `/debug-logs` adds any Jira keys found |
| What would Deva do, and why, without running it? | `/dry-run-deva <JIRA-KEY>` | A non-mutating instruction-level simulation of the full pipeline |
| Why did the logic branch or checkpoint behave that way? | `/dry-run-deva <JIRA-KEY>` | Rule-by-rule trace of stages, decisions, and suppressed side effects |
| Did this run follow the current authoritative instructions? | `/diff-deva <JIRA-KEY>` | A run vs. a sequential decision-matched oracle from HEAD; earliest unexplained divergence |
| Is this drift a real bug, a bad simulation, or a design violation? | `/diff-deva <JIRA-KEY>` | Every difference classified with an evidence triplet |
| Did this run or dry-run match the `DESIGN-DEVA.md` design document? | `/diff-deva --mode design-retrospective` or `--mode design-conformance` | A run or dry-run vs. a design spine; each divergence classified as implementation-drift or design-staleness |
| Which stages or checkpoints cost the most time? | `/plot-deva [JIRA-KEY]` | Per-segment duration and cumulative timing for one story, or aggregated across every run |
| Which run inflated a stage's timing tail? | `/plot-deva` | Box-and-whisker per stage/checkpoint across every completed run envelope |
| Is a slow segment real work or a human pause between sessions? | `/plot-deva ai` | The cross-run aggregate with only evidenced human-pause or interrupted-session samples set aside, every exclusion disclosed |
| How much Copilot activity occurred between two Deva boundaries? | `/measure-deva <JIRA-KEY> <start> <end>` | Exact cloud tokens when available; otherwise local turns, elapsed time, compactions, and indexed text proxies |

Use `/debug-sessions` when the chat session is the unit of investigation. Use `/debug-logs` when the Jira story is the unit of investigation or when a run crossed several chats. Use `/dry-run-deva` when you want to trace the pipeline logic itself without producing a real run to analyze. Use `/diff-deva` when you have both an instruction-derived oracle and a run and want to know whether they agree. Use `/plot-deva` when you want to see where a run — or every run — spends its minutes. Add the `ai` argument (`/plot-deva ai`) when you want that cross-run aggregate with evidenced human-pause outliers set aside and every exclusion disclosed. Use `/measure-deva` when you want activity or token evidence bounded by two events in one run rather than whole-run timing.

## What the tracer does

`scripts/logs/render-agent-trace.ps1` turns a current Copilot transcript or legacy `debug-logs` session into an application-level trace of one Copilot chat session: the handoff chain between agents, tool execution starts and completions, timings, and errors.

Two properties make it trustworthy:

- **Deterministic** — it makes no model calls, so the same logs always produce the same trace.
- **Faithful** — it reports only what the log contains, nothing inferred by an LLM.

You can run the script yourself for the raw trace, or let the read-only `/debug-sessions` prompt run it and interpret the result for you.

## Run the script directly

The tracer requires PowerShell 7 or later. First locate your session-log root. Current-format sessions are stored in the `transcripts/` folder under `GitHub.copilot-chat` (flat `.jsonl` files — one per session). Legacy-format sessions are stored in `debug-logs/` instead (one subdirectory per session). The script auto-detects the format; do not infer the format from a hard-coded VS Code version boundary. Then render a trace:

```powershell
$script = ".github/scripts/logs/render-agent-trace.ps1"

# Current format (transcripts/ — flat .jsonl files, one per session)
$root   = "<...>/GitHub.copilot-chat/transcripts"

# Legacy format (debug-logs/ — one subdirectory per session)
# $root = "<...>/GitHub.copilot-chat/debug-logs"

# Render the newest session as markdown (handoff diagram + timeline)
pwsh -NoProfile -File $script -DebugLogsRoot $root -Latest -Format markdown

# Render a specific session and save it into the logs traces folder
# Current format: pass the .jsonl file path; legacy: pass the session directory
pwsh -NoProfile -File $script -SessionPath "$root/<sessionId>.jsonl" -Format markdown -OutDir ".github/logs/traces"

# Browse available sessions (newest first)
pwsh -NoProfile -File $script -DebugLogsRoot $root -List
```

A typical workflow is: `-List` to find the session, then `-SessionPath` (or `-Latest`) to render it, adding `-OutDir` when you want to keep the trace.

## Command options

| Option | Effect |
| -------- | -------- |
| `-SessionPath <path>` | A current transcript `.jsonl` file or a legacy `debug-logs/<sessionId>` directory. |
| `-SessionId <id>` | Select a transcript or legacy session directory by ID under `-DebugLogsRoot`. |
| `-DebugLogsRoot <dir>` | The session-log root; use with `-Latest`, `-List`, or `-SessionId`. |
| `-AgentsDir <path[]>` | Override the agent-definition lookup directories; defaults to `.github/agents` and `.claude/agents` when present. |
| `-Latest` | Pick the most recently modified session under `-DebugLogsRoot`, skipping ghost/stub sessions that were opened but never prompted. |
| `-Format text\|markdown\|mermaid\|json` | Output shape (default `text`). |
| `-OutFile <path>` / `-OutDir <dir>` | Write to a file, or auto-name `trace-<session>.<ext>` in a directory. |
| `-Full` | Render untruncated, redacted message and handoff-description text; tool-argument summaries remain bounded and redaction always remains active. |
| `-ShowLlm` | Add per-request model round-trips (model, tokens, latency). Applies only when legacy `debug-logs` contain `llm_request` telemetry; current flat transcripts do not expose equivalent events. |
| `-List` | List sessions under `-DebugLogsRoot` and exit (the `Ghost` column flags stub sessions that were opened but never prompted). |

## Use the `/debug-sessions` prompt

For interpretation rather than a raw dump, open a new chat and run the `/debug-sessions` prompt. It runs the script for you, explains the trace in plain language, and answers follow-up questions. For example:

- `/debug-sessions latest` — walk me through the last run`
- `/debug-sessions <sessionId>` — why did qa run twice?`

Ask it to "save under logs" to persist the markdown trace to `.github/logs/traces/`.

## Use the `/debug-logs` prompt

Run `/debug-logs` in a new chat after a Deva run has finished or stalled. A Jira key is the normal input:

- `/debug-logs PROJ-1234` — show the complete run timeline`
- `/debug-logs PROJ-1234` — why is intake still in progress?`
- `/debug-logs PROJ-1234` — correlate the Jira MCP failure with the pipeline state`

You can also provide a session ID, a debug-log path, or `latest`. Without a Jira key, `/debug-logs` starts from the session trace, identifies Jira keys mentioned by the runtime evidence, and adds any matching pipeline sources it can verify.

The prompt produces one time-sequential view instead of three disconnected summaries. It uses `activity.log` as the chronology, attaches Copilot handoffs and tool calls by time window and agent, and overlays the final stage/checkpoint/artifact state from `session.md`. It must label inferred correlations rather than presenting them as exact joins.

`/debug-logs` degrades gracefully when a source is missing:

- A keyless or stateless run normally has only Copilot debug logs; the prompt falls back to a `/debug-sessions`-style view.
- A resumed story can have one pipeline history spanning several Copilot sessions; the prompt attaches every matching session.
- A discarded live session can retain `activity.log` without `session.md`; the prompt shows the event history without claiming an end-state snapshot.
- Missing or expired Copilot logs leave pipeline history and state available, but infra-level handoffs and tool timing may remain unknown.

## Use the `/dry-run-deva` prompt

Run `/dry-run-deva` in a new chat when you want to see what Deva *would* do — and why — without producing a real run. It is a thin, sequential interpreter of the current framework: it starts at Stage 0, reads that stage's configuration and applicable Deva instructions, follows only their agent and skill references, simulates their operations without mutation, and stops at the checkpoint before discovering the next stage. Reactive stages are event-selected rather than polled, so an unselected alternative produces no trace records merely to explain why it did not run. The interpreter continues the authoritative selected path through Stage 10:

- `/dry-run-deva PROJ-1234` — trace the whole pipeline, stopping at each checkpoint like a real run

Resolve each checkpoint with one registered reply on a later top-level developer turn. To trace an alternate branch, choose its registered revision reply when that gate is presented.

It never preloads later stage narratives or operational inputs and contains no parallel stage specification that can override the reached instructions. It writes a single instruction-level trace to `.github/logs/<JIRA-KEY>/dry-run-<timestamp>.trace.log` — a syslog-style record of every rule evaluated (`EVAL`), input read (`READ`), branch taken (`DECISION`), suppressed side effect (`WOULD-MUTATE`), simulated handoff (`HANDOFF`), and gate reached (`CHECKPOINT`). That trace file is its only write and doubles as its resume state, so the target's real `session.md`, `activity.log`, and Git state are never created or changed. Each record is written through to the log before its matching narration appears in chat, so you can tail the file while the dry-run is active, and a cancelled or interrupted run always leaves a valid, auditable prefix on disk. Only a prefix ending at a pending checkpoint resumes in that file; a stop anywhere else leaves the prefix for inspection and the next invocation starts a fresh trace. If the log cannot be written the command fails closed rather than continuing in chat only. Use it to debug pipeline logic, checkpoint flow, and specialist handoffs before or without a live run; use `/debug-logs` once a real run exists to analyze, and `/diff-deva` to reconcile that run against this instruction-derived simulation.

## Use the `/diff-deva` prompt

Run `/diff-deva` in a new chat when you have both a dry-run oracle and a real run and want to know whether they agree. It reconciles two instruction-level pictures of the pipeline — a sequential *oracle* and an *observation* of what a run did — onto one common event algebra, then finds and classifies where they diverge. It reconciles under one of two *authorities*: **instruction authority**, where the yardstick is the authoritative runtime instructions at HEAD, and **design authority**, where the yardstick is the `DESIGN-DEVA.md` design document. It has five modes:

- `/diff-deva PROJ-1234` — *retrospective* (default): generate a dry-run oracle from HEAD, replay the real run's approved decisions into it, and reconcile it against that run's `activity.log`
- `/diff-deva --mode two-trace --oracle <trace> --real <activity.log>` — compare two specific traces
- `/diff-deva --mode conformance --oracle <trace>` — check that a dry-run sequentially followed the authoritative runtime instructions, with no real run
- `/diff-deva --mode design-conformance --oracle <trace>` — check that a dry-run matches the `DESIGN-DEVA.md` design document, with no real run
- `/diff-deva --mode design-retrospective --oracle <design-spine-trace> --real <activity.log>` — reconcile a real run against a design spine interpreted from `DESIGN-DEVA.md`

Two switches refine every mode: `--scope flow` (default, the checkpoint/stage/handoff/decision spine) or `--scope full` (also side effects), and `--feedback on` (default; also flags model mispredictions and design violations) or `--feedback off`.

The deterministic mechanics — parsing both trace formats, the comparability gate, normalization, and per-stage alignment — live in `.github/scripts/diagnostics/diff-deva.py`; `.github/scripts/diagnostics/retrospective-diff-deva.py` extracts the observed decision vector, validates a generated decision-matched oracle, caches it under `.github/cache/diagnostics/diff-deva/oracles/` by framework version, config fingerprint, and decision vector, then invokes that core (instruction authority only — the design spine is never cached). The prompt classifies each divergence and writes the report. **The comparability gate is two-tier:** the resolved config fingerprint is decisive — if it can't be established on either side or the two differ, the command refuses and stops, because a run whose config can't be matched is out of scope by design; the framework version and session schema are advisory — a genuine difference still refuses, but a field that is merely unavailable on one side (the common case for a real `activity.log`, which carries no version and often no schema) only records a warning and lets the comparison proceed. **Under design authority the fingerprint gate relaxes to advisory**, because a design spine has no resolved-config fingerprint; a present-on-both mismatch still refuses. Every divergence it surfaces is classified — under instruction authority as one of **real-bug**, **model-misprediction**, **design-violation**, **explained-decision**, or **no-oracle-coverage**; under design authority as **implementation-drift**, **design-staleness**, **explained-decision**, or **no-oracle-coverage** — and the headline is the *first fault*, the earliest divergence that is a genuine fault rather than an explained decision or a coverage gap. It never mutates pipeline state; retrospective mode writes or reuses the validated oracle cache, and an optional report may also be written.

## Use the `/plot-deva` prompt

Run `/plot-deva` in a new chat after runs have finished to see **where the time went**. Because every `activity.log` line is ISO-8601 UTC, the gaps between stage entries and checkpoint approvals are exact minutes; the command renders those minutes as self-contained HTML charts with inline SVG that you can open offline. Whether you pass a Jira key chooses the mode:

- `/plot-deva PROJ-1234` — profile one story's latest completed run: a duration histogram (minutes per segment) beside a cumulative curve (elapsed minutes to each segment)
- `/plot-deva` — aggregate every completed run envelope under the logs dir into one box-and-whisker per segment (whisker low/high = min/max, box = mean ± stddev, centre line = mean, dashed tick = median), so the slowest stages and the runs that inflate a tail stand out
- `/plot-deva ai` — the same cross-run aggregate after a contextual AI review that sets aside only explicitly evidenced human-pause or interrupted-session samples, each with a timestamped reason; every exclusion and its raw duration stay visible below the chart, and the raw logs are never changed

These options refine both modes: `--by stage` (default) buckets by pipeline stage and `--by checkpoint` buckets by gate (`C0a`, `C0b`, `C1a`, …); `--out <path>` overrides the artifact path and `--json` also prints the computed statistics to stdout. `--keep <count>` retains the newest charts in the default chart family (default 10), while `--keep 0` disables pruning; explicit `--out` skips rotation. The deterministic mechanics — reading the logs, computing per-segment durations, and rendering stdlib-only HTML with inline SVG and no matplotlib, network, or external assets — live in `.github/scripts/diagnostics/plot-deva.py`, so a chart is reproducible rather than eyeballed. The `ai` mode is backed by `--curated` plus one `--exclude STORY[#RUN]:SEGMENT=EVIDENCE` per set-aside sample; the run suffix is required only when the unsuffixed story/segment would match multiple runs. Each exclusion is auditable, and an unmatched, ambiguous, duplicate, or reasonless exclusion hard-fails rather than silently reshaping the chart. It never runs inside a live pipeline. With default output it writes the current chart and may prune older artifacts in that same chart family. It never runs inside a live pipeline. With only a handful of runs the aggregate `n` is small — read a wide box as low-confidence rather than a firm signal.

## Use the `/measure-deva` prompt

Run `/measure-deva` in a new chat after the measured interval has ended. Give it a Jira key and two boundaries:

- `/measure-deva PROJ-1234 C4 C5` — measure from C4 approval to C5 approval
- `/measure-deva PROJ-1234 stage:implement stage:qa` — measure between stage-enter events
- `/measure-deva PROJ-1234 checkpoint:C8a:approved checkpoint:C8b:milestone` — use explicit checkpoint event types
- Add `--session <id>` when you know the exact Copilot session; repeat it when the interval crossed chats.

The command resolves exact timestamps from the Jira-keyed `activity.log`, then queries only corroborated Copilot sessions in that half-open interval. Cloud history with `assistant.usage` events provides exact input and output tokens by model. Local history provides turns, elapsed time, compaction count, and indexed character volume only; assistant text may be truncated, and none of those values is converted into a token estimate. A bare checkpoint means its canonical `event=approved` timestamp because `activity.log` has no canonical checkpoint-pending event. Missing, duplicated, or ambiguous boundaries block rather than being guessed.

## Understand the three pipeline sources

Each source answers a different question:

| Source | What it proves | Scope | Canonical location |
| --- | --- | --- | --- |
| `activity.log` | Which pipeline event occurred and when | Jira key | `<pipeline.log_dir>/<JIRA-KEY>/activity.log` |
| `session.md` | Latest observed stage, checkpoint, artifact, and decision state | Jira key | Live under `<pipeline.session_dir>/<JIRA-KEY>/session.md`, then archived under `<pipeline.archive_dir>/<JIRA-KEY>/session.md` |
| Copilot runtime evidence | Which agent, tool request, execution, confirmation, and MCP lifecycle event occurred inside a chat | Session ID | Transcript/legacy logs rendered by `render-agent-trace.ps1`; persisted confirmation state read from `chatSessions/<sessionId>.jsonl` by the prompts |

The tracer owns deterministic transcript extraction. `/debug-sessions` adds targeted persisted confirmation and permission evidence when a request never reached execution; `/debug-logs` applies that same session-level check before correlating the result onto the Jira-keyed pipeline timeline.

Read the configured pipeline paths from `.github/config/guardrails.yaml`; do not guess a fallback path when configuration is unreadable.

`activity.log` is the timeline spine because it is append-only and timestamped. `session.md` is a mutable snapshot, not a chronological log. Copilot logs explain the runtime activity between pipeline events. None substitutes for another:

- A stage can be `in_progress` in `session.md` while the transcript reveals a requested tool that never started.
- A subagent can return successfully in the Copilot trace while a missing approval event leaves the pipeline checkpoint pending.
- A complete stage row without the corresponding activity and checkpoint evidence is a state-integrity concern, not proof of success.

Pipeline Session is the sole managed writer of `activity.log` and `session.md`. Both debugging prompts are read-only consumers and must never repair, normalize, or overwrite source evidence.

## Interpret a unified pipeline timeline

`/debug-logs` returns one time-sorted table with the sources interleaved:

| time (UTC) | source | scope | actor / agent | event / tool | detail | outcome |
| --- | --- | --- | --- | --- | --- | --- |
| `<time>` | `activity` | `PROJ-1234` | `Stage:intake` | `enter` | Story Analyst handoff began | observed |
| `<time>` | `infra` | `<sessionId>` | `story-analyst` | Jira tool requested | confirmation pending | no execution start |
| `<time>` | `state` | `PROJ-1234` | `intake` | stage snapshot | `in_progress`, C1a pending | observed |

Correlating Jira-keyed pipeline files with session-keyed Copilot logs has no universal shared identifier. The prompt joins them using:

1. overlapping timestamps,
2. Jira-key mentions,
3. matching stage and subagent names,
4. managed handoff identities when present.

The output must state which sources were present, which were missing, and which joins were inferred. It closes with the latest `session.md` end-state and key artifacts, but does not treat that snapshot as proof of the event sequence.

Before trusting the timeline, `/debug-logs` also checks integrity that is observable in the current bytes: each activity event begins on a new line and no later event appears after missing run-opening history. Fused lines and malformed current structure are reported directly. Historical truncation, lost-prefix, or whole-file replacement is reported only when a named prior-byte authority proves it; without that evidence, historical append integrity is `unverified`, not defective. The read-only prompt does not repair any source.

## Diagnose a stalled tool or hidden confirmation

The tracer shows tools that reached `tool.execution_start`. A stalled run can stop one phase earlier, after the model requested a tool but before VS Code started it. Use `/debug-sessions` for one chat session or `/debug-logs` when you also need the Jira-keyed `activity.log` and `session.md`.

Check the tool lifecycle in order:

| Phase | Source | Interpretation when absent |
| --- | --- | --- |
| Requested | transcript `assistant.message.data.toolRequests` | The model never requested the tool. |
| Confirmed | persisted `chatSessions/<sessionId>.jsonl` | The request may be waiting on or may have lost a tool confirmation. |
| Started | transcript `tool.execution_start` | VS Code did not schedule the requested tool; investigate approval, permissions, cancellation, or nested-agent scope. |
| Completed | transcript `tool.execution_complete` | The tool started but did not return before the trace ended. |

For an MCP call, also inspect the corresponding timestamped VS Code output file under `logs/<window-start>/window*/mcpServer.*<server-id>*.log`. `Discovered N tools` means the server registered its tools; it does not mean a method ran or that a nested confirmation was accepted. A successful foreground control call that returns real data, followed by a nested request with no `tool.execution_start`, points to the VS Code confirmation/scheduling or active-agent lifecycle rather than the MCP endpoint.

Apply this to every configured MCP family, including Jira, <INTERNAL_KNOWLEDGE_ASSISTANT>, Confluence, and Stack Overflow. Resolve the configured key from the active user/workspace `mcp.json`, then compare it with the persisted invocation's source metadata and the transcript's actual runtime tool name. These strings can differ, so do not derive one mechanically from another. Use the resolved identity to find the correct `mcpServer.*.log` output channel. Treat a startup metadata warning as benign only when that same server successfully falls back and discovers tools; treat a real method result as authentication evidence.

Verify the real root agent from persisted chat state and `runSubagent` events. Do not infer it from user text such as `@deva`; in affected recent VS Code versions, that text can remain in the default Agent chat and create an extra nested handoff. For hidden pending confirmations, expand the subagent card and choose **Open Subagent**, or run **Chat: Show Sessions**.

## How agent relationships are reconstructed

The tracer rebuilds the agent hierarchy from `runSubagent` calls, so it labels subagent handoffs such as `agent → do-it → qa`. Treat the first `@agent` or `/command` as a presentation hint, not definitive root-agent evidence: verify the persisted request's agent identity when root selection matters. Note that per-turn agent switches within a single chat are **not** separately labeled.
