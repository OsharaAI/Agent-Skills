# Implementing Metrics — Phased Rollout

Resist standing up a full observability stack from day one. Earn each metric by
being able to name the action it triggers.

## Phase 1: Foundation (Week 1-2)

1. **Pick 3 metrics.** Begin with code coverage, flakiness rate, and defect escape
   rate — this trio delivers the most signal for the least setup effort.
2. **Automate collection.** Pull coverage from your test runner (Istanbul, c8,
   coverage.py), flakiness from CI run history, and defect escapes from tagged
   production bugs.
3. **Set initial targets.** Pull starting numbers from the company-stage table in
   SKILL.md, then adjust once you have 2-4 weeks of baseline data.
4. **Assign owners.** One engineer owns coverage, another owns flakiness, and the
   engineering manager owns defect escape rate.

## Phase 2: Visibility (Week 3-4)

1. **Stand up the engineering dashboard.** Grafana, Datadog, or even a shared
   Google Sheet all work — the tool matters far less than building the habit of
   checking it.
2. **Add CI annotations.** Surface coverage deltas and flakiness warnings directly
   in PR comments (most CI tools support this out of the box).
3. **Wire up alerts.** Flakiness above 5% triggers a Slack alert to the team;
   a coverage drop of more than 2% on a PR blocks the merge or flags it for review.
4. **Set a review cadence.** Cover metrics in the weekly team standup — 5 minutes
   is enough, it doesn't need to eat 30.

## Phase 3: Quality Gates (Month 2)

1. **Define release quality gates.** For example:
   - All P0 tests pass
   - Coverage has not decreased
   - No new P0/P1 bugs unresolved
   - Flakiness rate below threshold
   - E2E smoke suite green
2. **Enforce gates automatically.** Use CI pipeline stages, branch protection
   rules, or deployment gates to do this.
3. **Track how often gates pass.** If they're routinely overridden, that means
   either the gates are too strict or the team doesn't trust them — either way,
   adjust.

## Phase 4: Advanced Metrics (Month 3+)

1. **Layer in process metrics** — automation rate, test velocity, ROI.
2. **Build out the leadership dashboard** (see `references/dashboards.md`).
3. **Add trend-based alerting** — not just static thresholds, but flags like
   "coverage has declined for 3 consecutive sprints."
4. **Feed metrics into retros.** Let the data steer sprint retrospective
   discussions rather than relying on opinions.

## Data Sources and Integration

| Data source | Metrics it feeds | How to extract |
|---|---|---|
| CI system (GitHub Actions, GitLab CI) | Pass rate, duration, flakiness | API or built-in analytics |
| Coverage tool (Istanbul, c8, coverage.py) | Code coverage % | Coverage report JSON output |
| Issue tracker (Jira, Linear, GitHub Issues) | Defect escape rate, MTTR, severity distribution | API queries with label/tag filters |
| Test runner (Playwright, Jest, pytest) | Test count, skip count, duration per test | JUnit XML or JSON reporter output |
| Source control (Git) | Test creation velocity, churn | Git log analysis |

## Metric half-life

Once a quarter, go through every metric you track and ask: has this triggered an
action in the last 90 days? If a metric never actually moved a decision, retire it
— a dashboard nobody acts on is pure cost with no insight attached. A new metric
only earns a spot once you can name the action it's meant to trigger.
