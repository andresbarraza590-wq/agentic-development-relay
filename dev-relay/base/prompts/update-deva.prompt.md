---
description: "Propagate completed framework changes through documentation, versions, and release notes, then commit and push each applicable repository without creating a pull request."
model: Claude Sonnet 4.8 (copilot)
tools: [read, edit, runCommands]
user-invocable: true
argument-hint: "optional: a summary of the completed change(s) to propagate"
---
<!-- ===================================================================== -->
<!-- SYNTHESIZED PROMPT (inferred, NOT from screenshots)                   -->
<!-- update-deva.prompt.md was never captured. Reconstructed from             -->
<!-- base/README.md Appendix B ("Propagates completed framework changes       -->
<!-- through documentation, versions, and release notes, then commits and     -->
<!-- pushes each applicable repository without creating a pull request") and   -->
<!-- Appendix E (per-layer semantic versioning rules). Wording is INFERRED.    -->
<!-- This prompt MUTATES (commits/pushes); review its actions before running.  -->
<!-- Replace with the real prompt if it surfaces.                              -->
<!-- ===================================================================== -->

# /update-deva — Documentation, Version, Release, Commit, and Push Maintenance

You propagate an **already-completed** framework change through its paperwork and publish it. You do not design or implement the change — you make the rest of the repository consistent with it and push.

## Procedure

1. **Identify the completed change(s)** from the working tree / recent commits (or the supplied summary). Confirm the change is complete before propagating.
2. **Documentation** — update every doc affected by the change so docs match behavior (README, DESIGN-* docs, AGENT-GUIDE, appendices, and any references).
3. **Versions** — advance the affected layer's version by exactly one level per [Appendix E](../README.md#appendix-e-release-versioning): patch for a small backward-compatible fix, minor for a larger backward-compatible change (reset patch), major for a breaking change (reset minor and patch). Keep the repository `README.md` and `base/README.md` `Version:` lines matching each other for the base layer; overlay layers version independently.
4. **Release notes** — record the change in the applicable release notes / overlay NOTE file.
5. **Commit and push** — commit the propagated changes and push **each applicable repository**. Do **not** open a pull request; `/update-deva` publishes maintenance directly.

## Constraints

- Respects the hard Git rules: never push directly to `develop`/`master`/`main`/`release/*`, never force-push, squash, or rebase-merge (the optional Git hooks enforce this deterministically).
- Advance each layer's version by exactly one level; never skip or jump levels.
- This prompt mutates repositories — surface what it will change and let the developer confirm before committing and pushing.
