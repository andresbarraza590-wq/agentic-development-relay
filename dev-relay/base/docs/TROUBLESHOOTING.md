<!-- ===================================================================== -->
<!-- SYNTHESIZED DOCUMENT (inferred, NOT from screenshots)                 -->
<!--                                                                       -->
<!-- TROUBLESHOOTING.md was never captured. base/README.md confirms it      -->
<!-- exists and enumerates its symptoms: "missing MCP registration, stale   -->
<!-- setup validation, Dev Assistant hanging after handoff, hidden nested    -->
<!-- subagent prompts, querying a run's raw session logs, and optionally     -->
<!-- auto-approving Copilot's file edits under .github/." The Quick Start    -->
<!-- also links the anchor                                                   -->
<!-- #why-does-the-agent-still-prompt-to-edit-github-files-as-outside-your-  -->
<!-- workspace-even-with-auto-approve-set, which is reproduced verbatim as a  -->
<!-- heading so that link resolves. Each section's remedy is reconstructed    -->
<!-- from base/README.md, do-it.agent.md, and DEBUGGING.md; wording is       -->
<!-- INFERRED, not the original. Replace with the real file if it surfaces.  -->
<!-- ===================================================================== -->

# Troubleshooting

Symptom-driven diagnosis and recovery. For conceptual background, see [Questions and Answers](QNA.md); for tracing a run in detail, see [Debugging Agent Runs](DEBUGGING.md).

## Missing MCP registration

**Symptom:** a stage that needs Jira (or an enrichment source) fails, or validation reports an MCP server as not registered.

**Fix:** register the server in VS Code Copilot using the setup guides linked in the README's [Configure the Required MCP Integrations](../README.md#configure-the-required-mcp-integrations) section (Jira MCP is required and blocking; <INTERNAL_KNOWLEDGE_ASSISTANT>, Confluence, and Stack Overflow are optional). After registering, run **Do It → Validate my environment** on its own while the chat is idle so the one-time interactive authorization can complete, then retry the work.

## Stale setup validation

**Symptom:** Deva redirects you to environment validation, or a run blocks on a setup precondition even though you validated earlier.

**Fix:** the PASS cache is reused only while current; it goes stale when the environment or configuration changes. Run **Do It → Validate my environment** again to re-materialize the configuration snapshot and refresh the cache. Validation is global (not per-story), so you only need to do this once per environment change.

## Dev Assistant hanging after a handoff

**Symptom:** after Deva hands off to a specialist, the chat appears to stop with no visible output.

**Fix:** this is almost always a hidden nested subagent prompt waiting for input (see the next section) — the handoff did not fail, it is blocked on a confirmation you cannot see. Recover the hidden session before assuming the run died. If there is genuinely no pending session, re-send your last message so the root agent (Deva) picks the pipeline back up with full context.

## Hidden nested subagent prompts

**Symptom:** the chat shows only `1 session needs input` and stalls, and tool confirmations never appear.

**Fix:** a nested subagent has an open prompt (often an MCP tool confirmation) that is not surfaced in the main view. Open the command palette and run **`Chat: Show Sessions`** to reveal the nested session, answer its prompt, and the run continues. To reduce how often this happens, select the custom agent from the Chat agent/mode picker rather than typing `@deva`/`@do-it` into the default Agent chat, which can add an unintended nested handoff and hide MCP tool confirmations.

## Querying a run's raw session logs

**Symptom:** you need to know exactly what happened in a run — which agents ran, who handed off to whom, which tools were called, timings, and where it failed.

**Fix:** the Dev Assistant writes a per-Jira activity log at `.github/logs/<JIRA-KEY>/activity.log` and a live/archived `session.md`. To reconstruct a readable, application-level trace from Copilot's raw debug logs, use `render-agent-trace.ps1` directly, or the read-only `/debug-sessions` prompt for one finished session and `/debug-logs` for a whole story's run woven together. See [Debugging Agent Runs](DEBUGGING.md).

## Why does the agent still prompt to edit .github files as outside your workspace even with auto-approve set?

**Symptom:** even with auto-approve configured, Copilot prompts **Allow Once** on every session and activity write under `.github/`.

**Cause:** this happens when the workspace was opened through a mapped drive (for example, `I:`) rather than by its physical path. VS Code then treats the framework's runtime files as edits *outside* your workspace, so auto-approve does not apply to them.

**Fix:** open the workspace by its **physical path** rather than the mapped `I:` drive. Close the mapped-drive window and reopen the folder at its real location (for example, `C:\Users\<you>\<WORKSPACE_PROJECTS_DIR>\<workspace-name>`), then start Copilot Chat in agent mode again.

**Optional (security trade-off):** you can auto-approve Copilot's file edits under `.github/`. This removes the per-write prompt but broadens what the agent can change without confirmation. Read the caveats first and enable it only if your team accepts that trade-off; prefer the physical-path fix above, which does not weaken approval scope.

## Base Sources

- `.github/README.md` — Quick Start, Configure the Required MCP Integrations, Troubleshooting, Debugging Agent Runs.
- `.github/agents/do-it.agent.md` — the `Chat: Show Sessions` recovery note.
- `.github/docs/DEBUGGING.md` — tracing a run from raw logs.

<!-- ===== END SYNTHESIZED DOCUMENT ===== -->
