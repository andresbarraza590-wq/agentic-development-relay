<!-- ===================================================================== -->
<!-- SYNTHESIZED DOCUMENT (inferred, NOT from screenshots)                 -->
<!--                                                                       -->
<!-- QNA.md was never captured. base/README.md confirms it exists and names  -->
<!-- its topics: "conceptual guidance about supported knowledge integrations,-->
<!-- how pipeline stages use those sources, MCP authorization reuse, and the -->
<!-- rationale for parent-targeted stacked pull requests." Each Q&A below is  -->
<!-- reconstructed from those named topics plus base/README.md and           -->
<!-- DESIGN-DEVA.md. Wording is INFERRED, not the original. Replace with the  -->
<!-- real file if it surfaces.                                               -->
<!-- ===================================================================== -->

# Questions and Answers

Conceptual guidance about the framework's knowledge integrations, how the pipeline uses them, MCP authorization, and the stacked pull-request model. For symptom-driven fixes, see [Troubleshooting](TROUBLESHOOTING.md).

## Knowledge Integrations

### Which knowledge sources does Deva support?

- **Jira MCP** — required and blocking for ticket-driven workflows. Deva reads the story, acceptance criteria, and linked context from Jira.
- **<INTERNAL_KNOWLEDGE_ASSISTANT> MCP** — strongly recommended, non-blocking. Enriches work with <ORG_NAME> internal documents (including Confluence Wiki). When it cannot connect, Deva reports degraded mode and continues without internal-document enrichment.
- **<INTERNAL_MCP_PLATFORM> Confluence MCP** and **<INTERNAL_MCP_PLATFORM> Stack Overflow MCP** — optional enrichment sources.
- **<BASE_ENGINEERING_ECOSYSTEM>** — compatibility is mandatory, local installation is optional. <BASE_ENGINEERING_ECOSYSTEM> documentation searches and <BASE_ENGINEERING_ECOSYSTEM>-owned tools are skipped or reported as degraded when <BASE_ENGINEERING_ECOSYSTEM> is not installed, without blocking the workflow.

### What is "degraded mode"?

When an optional, non-blocking source (<INTERNAL_KNOWLEDGE_ASSISTANT>, Confluence, Stack Overflow, or <BASE_ENGINEERING_ECOSYSTEM>) is unavailable, Deva does not stop. It records that enrichment from that source was unavailable and proceeds with what it has. Only the required Jira MCP blocks ticket-driven work.

## How Pipeline Stages Use These Sources

- **Story intake / refinement (Stages 1a/1b)** read Jira (required) and enrich from <INTERNAL_KNOWLEDGE_ASSISTANT> / Confluence / <BASE_ENGINEERING_ECOSYSTEM> when available, to turn a ticket into an implementation brief and acceptance criteria.
- **Architecture bootstrap (Stage 0b)** traces the confirmed repositories to build architecture context; internal-document sources enrich but do not gate it.
- **Build, QA, and test (Stages 3–4)** draw on architecture context and, where helpful, Stack Overflow / internal docs for patterns.
- **Acceptance (Stage 5)** checks the implementation against the Jira-derived acceptance criteria and scope.

The required/optional split is deliberate: a developer can install, validate, and run the framework with only Jira connected; everything else improves quality without being a prerequisite.

## MCP Authorization Reuse

### Why does the guide say to run environment validation on its own first?

MCP servers often require a one-time interactive authorization in VS Code. Running **Validate my environment** (Do It Row 1) on its own, while the chat is idle, lets that one-time authorization complete before feature work begins — so it does not interrupt a pipeline run mid-stage.

### Why do agents keep already-authorized MCP servers in their `tools` list if they do not call them?

So VS Code keeps those already-authorized MCP servers running across handoffs. A router like Do It lists the MCP servers only to preserve the live, authorized session for the destination agent that actually uses them — the router itself never probes or calls them. This reuse avoids re-authorizing on every handoff.

### Is the validation result per-story?

No. Environment validation is global, not tied to a story, so its PASS result is cached globally and Row 1 ignores any Jira key.

## Stacked Pull Requests

### Why target the parent branch instead of `develop` for each PR in a stack?

The branch hierarchy is `develop` → `feature/<user>/<PARENT-JIRA>` → `feature/<user>/story/<PARENT-JIRA>`. When a story is delivered in multiple slices, each slice PR targets the **previous slice's branch** (a contiguous linear stack of `feature/<user>/story/<PARENT-JIRA>-PR<N>` branches), not `develop`. Parent-targeting keeps each PR's diff limited to just that slice's change, so reviewers see small, reviewable increments instead of one large cumulative diff. The stack is reviewed PR1 toward the tip and collapsed tip toward PR1, with current checks and approval at each changed parent.

### When is a single PR used instead of a stack?

When the story is one slice. A single slice integrates the complete canonical story additively into the feature branch and opens one feature-to-`develop` draft PR. No slice Jira subtasks or descriptive slugs are created in either case.

### Who holds merge authority?

Humans. After draft review delivery opens, Deva pauses. Requested changes land on the canonical story branch first, then propagate additively. C8d retains human review, approval, and merge authority. Deva never pushes directly to `develop`, force-pushes, squashes, or rebase-merges.

## Base Sources

- `.github/README.md` — Environment Setup, Operational Notes, Appendix A/D.
- `.github/docs/DESIGN-DEVA.md` — stage-by-stage source usage and the branch model.
- `.github/docs/TROUBLESHOOTING.md` — symptom-driven recovery.

<!-- ===== END SYNTHESIZED DOCUMENT ===== -->
