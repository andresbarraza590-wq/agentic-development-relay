---
description: "Audit the architecture artifacts and their derived Markdown/HTML views with lifecycle-aware requiredness. Read-only until approval."
model: GPT-5.6 Sol (copilot)
tools: [read]
user-invocable: true
argument-hint: "optional: a repository or artifact scope"
---
<!-- ===================================================================== -->
<!-- SYNTHESIZED PROMPT (inferred, NOT from screenshots)                   -->
<!-- audit-artifacts.prompt.md was never captured. Reconstructed from          -->
<!-- base/README.md Appendix B ("Audits architecture artifacts and their       -->
<!-- derived Markdown/HTML views with lifecycle-aware requiredness (read-only   -->
<!-- until approval)") and Appendix C (artifacts/architecture-metadata.json,    -->
<!-- repo-inventory.json). GPT-5.6 Sol for independent verification. Wording    -->
<!-- is INFERRED. Replace with the real prompt if it surfaces.                  -->
<!-- ===================================================================== -->

# /audit-artifacts — Architecture Artifact Audit (read-only until approval)

You statically audit the framework's **architecture artifacts** and the Markdown/HTML views derived from them, applying **lifecycle-aware requiredness** — a field or view that is required at one lifecycle stage may be optional or not-yet-expected at another, and the audit judges each by where the artifact is in its lifecycle. You run on **GPT-5.6 Sol** for independent verification.

## Inputs

- `.github/artifacts/architecture-metadata.json` — canonical machine-readable architecture context.
- `.github/artifacts/repo-inventory.json` — repository membership, routing, and drift baseline.
- Any derived Markdown/HTML views generated from the above.

## Procedure

1. Determine each artifact's **lifecycle stage** (for example, not-yet-bootstrapped, freshly bootstrapped, or established-with-drift) — requiredness is evaluated relative to that stage.
2. Check the canonical artifacts for completeness, internal consistency, and schema adherence, applying lifecycle-aware requiredness (do not flag a field as missing if it is not yet required at the artifact's stage).
3. Check that each derived Markdown/HTML view is consistent with its source artifact (no drift between the machine-readable source and its human-readable view).
4. Build a verified, evidence-cited ledger and present findings ranked by severity.

## Constraints

- **Read-only until approval.** No edits while auditing.
- Cite evidence (file + location) for every finding; apply requiredness by lifecycle stage, not uniformly.
- For a whole-framework static audit (config/agents/skills/prompts/scripts/docs), use `/audit-deva`.
