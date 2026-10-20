# Agent Metrics Checklist

Use this as a lightweight checklist to track execution throughout the agent workflow.

## 1. Per PR Checklist

Story and run context:

- [ ] Jira key captured
- [ ] PR labeled `ai-assisted`
- [ ] Agent flow used (picker-selected Deva → subagents)

Tier 1 PR metrics:

- [ ] PR cycle time recorded (opened → merged)
- [ ] First-review turnaround recorded
- [ ] Review rounds counted
- [ ] PR size recorded as non-test additions + deletions after excluding repository-recognized test paths
- [ ] Test-line churn recorded separately
- [ ] Delivery identity and lineage recorded (`delivery_id`, `delivery_mode`, `branch_name`, `parent_branch`): feature branch for direct mode or `PR<N>` for stacked mode
- [ ] Production lines vs test lines recorded per delivery slice
- [ ] Coverage delta captured
- [ ] Defect escape linked if any post-merge issue appears

Tier 2 agent metrics:

- [ ] Agent invocations per PR captured
- [ ] Agent acceptance rate noted (kept vs reverted)
- [ ] QA escaped-defect rate or golden-set precision/recall noted
- [ ] New test-case origin distribution noted (AI-authored, AI-assisted, human-authored)
- [ ] Test origin split captured (`ai_authored_tests`, `ai_assisted_tests`, `human_authored_tests`)
- [ ] `% AI Test Creation` calculated as `(ai_authored_tests / total_new_tests) * 100`; record `n/a` when `total_new_tests = 0` and exclude that record from percentage averages
- [ ] `AI-assisted test %` calculated as `(ai_assisted_tests / total_new_tests) * 100` with the same zero-test `n/a` and average-exclusion rule
- [ ] `Human-authored test %` calculated as `(human_authored_tests / total_new_tests) * 100` with the same zero-test `n/a` and average-exclusion rule
- [ ] Rework after agent measured
- [ ] Story-scoped metrics recorded manually when the team uses the optional templates

Outcome snapshot:

- [ ] AC status recorded (Met / Partially Met / Not Met / Deviated)
- [ ] Final decision captured (merged / follow-up required)
- [ ] Historical confidence tagged (`exact` or `estimated`) when backfilling metrics

## 2. Weekly Checklist

- [ ] Aggregate all ai-assisted PRs for the week
- [ ] Compare against baseline/manual values
- [ ] Publish review friction trend
- [ ] Publish reviewer effort trend
- [ ] Publish convergence speed trend
- [ ] Publish aggregate prod vs test line trend by delivery slice
- [ ] Publish `% AI Test Creation` trend
- [ ] Publish `AI-assisted test %` trend
- [ ] Publish `Human-authored test %` trend
- [ ] Identify top 3 recurring review comment categories
- [ ] Identify top 3 recurring QA finding categories
- [ ] Record one tuning action per recurring issue

## 3. Sprint Checklist

- [ ] Summarize stories completed as a team or sprint aggregate
- [ ] Summarize first-round approval rate
- [ ] Summarize average review rounds
- [ ] Summarize defect escape rate
- [ ] Summarize average `% AI Test Creation`
- [ ] Summarize average `AI-assisted test %`
- [ ] Summarize average `Human-authored test %`
- [ ] Summarize stories with explicit branch-level delivery metrics
- [ ] Confirm quality gates are met:
  - [ ] Code accuracy >= 80%
  - [ ] QA precision >= 0.70
  - [ ] QA recall >= 0.90
  - [ ] Test first-pass rate >= 85%
  - [ ] AC agreement >= 85%
  - [ ] Review rounds <= 1.5 average
  - [ ] Average iterations per approved work unit <= 2.5
  - [ ] PR cycle time reduction >= 30% versus baseline
  - [ ] Defect escape rate has not increased versus baseline
  - [ ] Rework rate <= 20%
- [ ] Decide keep/tune/switch strategy for model + prompts
- [ ] Log approved improvement actions for next sprint

## 4. Quick Data Sources

- Project-native SCM API, such as GitHub or Bitbucket: PR timestamps, review states, review comments, diff stats
- Jira: story status, sprint assignment, throughput
- CI coverage reports: coverage delta and trend
- Future session telemetry (not currently implemented): per-agent events and iteration counts

## 5. Notes Template

Use this template to keep weekly and sprint notes concise, consistent, and easy to compare.

```text
Period:
Total ai-assisted PRs:
Avg PR cycle time:
Avg review rounds:
Avg reviewer effort:
Avg prod lines/delivery slice:
Avg test lines/delivery slice:
Avg % AI Test Creation:
Avg AI-assisted test %:
Avg Human-authored test %:
Top comment categories:
Top QA categories:
Coverage trend:
AC agreement trend:
Decisions:
Action owners:
```
