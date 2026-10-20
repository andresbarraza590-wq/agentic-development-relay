# Agent Metrics Rollup

> Manual reporting template and future automation design. The current pipeline does not update this file or write repository JSONL telemetry.

## Proposed Aggregation

<!-- AUTO-GENERATED:START -->
No automated aggregation is implemented.
<!-- AUTO-GENERATED:END -->

## Historical Backfill (Manual/Assumed)

## Per-Story Summary

| Story | Repo | Delivery Slices | Prod Lines | Test Lines | Tests Passing | % AI Test Creation | AI-Assisted Test % | Human-Authored Test % | Back/Forth | Human Corrections | Revert | Amend | Accept | Escalations | Data Confidence | Last Updated |
| ----- | ---- | --------------- | ---------- | ---------- | ------------- | ------------------ | ------------------ | --------------------- | --------- | ----------------- | ------ | ----- | ------ | ----------- | --------------- | ------------ |

## Per-Repo Summary

| Repo | Stories | Delivery Slices | Prod Lines | Test Lines | Tests Passing | Avg % AI Test Creation | Avg AI-Assisted Test % | Avg Human-Authored Test % | Back/Forth | Human Corrections | Escalations | Last Updated |
| ---- | ------- | --------------- | ---------- | ---------- | ------------- | ---------------------- | ---------------------- | ------------------------- | --------- | ----------------- | ----------- | ------------ |

## Aggregate Summary

| Stories | Delivery Slices | Repos Touched | Prod Lines | Test Lines | Tests Passing | Avg % AI Test Creation | Avg AI-Assisted Test % | Avg Human-Authored Test % | Back/Forth | Human Corrections | Escalations | Last Updated |
| ------- | --------------- | ------------- | ---------- | ---------- | ------------- | ---------------------- | ---------------------- | ------------------------- | --------- | ----------------- | ----------- | ------------ |

## Notes

- `% AI Test Creation` formula: `(ai_authored_tests / total_new_tests) * 100`.
- `AI-assisted test %` formula: `(ai_assisted_tests / total_new_tests) * 100`.
- `Human-authored test %` formula: `(human_authored_tests / total_new_tests) * 100`.
- Count one delivery slice for direct mode using `feature/<user>/<PARENT-JIRA>` and one per stacked parent-story ordinal branch `feature/<user>/story/<PARENT-JIRA>-PR<N>`; never use Jira-subtask/ST identities.
- If `total_new_tests = 0`, record all three percentages as `n/a` and exclude that record from percentage averages.
- Use `Data Confidence = estimated` for historical backfill rows without explicit test-origin markers.
- A future implementation may use JSONL session logs plus committed test metric files as its aggregation source.
- Proposed interaction metrics include `session_end`, `human_correction`, and `human_escalation` events.
- Do not include employee names, SIDs, email addresses, or other engineer identifiers in this committed rollup.
