# AI-Assisted Test Metrics

> Manual reporting template and future automation design. The current Tester and Deva contracts do not update this file automatically.

> **AI-generated test files** are counted by scanning all test files for the tag
> `ai-generated: <JIRA-KEY> / tester-agent / <YYYY-MM-DD>` in the
> language-native comment syntax (for example, `#` for Python/HCL or `//` for
> Java). Stateless runs use `KEYLESS` in place of `<JIRA-KEY>`. A
> project-approved wrapper or annotation may accompany this canonical text but
> does not replace it.
> The tag supports a two-way file inventory only: tagged AI-generated baseline
> files versus untagged test files. It does not count test cases or determine
> final authorship after review.
> For period metrics, classify each new test using the canonical three-way
> categories in `AGENT-METRICS.md`: tagged with no substantive human rewrite is
> `AI-authored`; tagged and materially edited by a human is `AI-assisted`; and
> written without an AI-generated baseline is `Human-authored`. Record the
> review evidence used for that classification. Use total test files minus tagged
> files only for the separate untagged-file count, not as the Human-authored
> metric.

## Summary

| Metric | Value |
| -------- | ------- |
| Total test files in suite | n/a (not backfilled) |
| AI-generated tagged test files | n/a (not backfilled) |
| Untagged test files in suite | n/a (not backfilled) |
| Total new tests created (period) | n/a (not backfilled) |
| AI-authored new tests (period) | n/a (not backfilled) |
| AI-assisted new tests (period) | n/a (not backfilled) |
| Human-authored new tests (period) | n/a (not backfilled) |
| % AI Test Creation (AI-authored / total new tests) | n/a (not backfilled) |
| AI-assisted test % (AI-assisted / total new tests) | n/a (not backfilled) |
| Human-authored test % (human-authored / total new tests) | n/a (not backfilled) |
| First-run pass rate | — |
| Stories processed through pipeline | 0 |
| Total human corrections (revert/amend) | 0 |
| Total human escalations | 0 |

## Per-Story Breakdown

<!--
Record a section manually per story using this template:

### JIRA-KEY — Story Title (YYYY-MM-DD)
| Approved Work Unit | Delivery ID | Branch | Prod Lines | Test Lines | Tests | Passing | Coverage | AI Authored | AI Assisted | Human Authored | % AI Test Creation | AI-Assisted Test % | Human-Authored Test % | Categories | Human Fixes | Data Confidence |
| ------------------ | ----------- | ------ | ---------- | ---------- | ----- | ------- | -------- | ----------- | ----------- | -------------- | ------------------ | ------------------ | --------------------- | ---------- | ----------- | --------------- |
| implementation-stream-1 | PR1 | feature/<user>/story/<PARENT-JIRA>-PR1 | N | N | N | N% | N | N | N% | N% | N% | happy:N, edge:N, error:N | N | exact |

Allowed values for Data Confidence: exact, estimated.

Percentage formulas use `total_new_tests` as the denominator. When it is zero, record all three origin percentages as `n/a` and exclude that record from percentage averages.

Future session log design: .github/artifacts/sessions/<JIRA-KEY>/<JIRA-KEY>-YYYYMMDD.jsonl
Writer: pipeline-session only, using metric events returned by agents through Deva.
Retention: pipeline.archive_retention_days.
-->

_No stories processed through the pipeline yet._
