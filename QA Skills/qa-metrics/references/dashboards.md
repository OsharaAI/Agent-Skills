# QA Metrics Dashboards

Different audiences need different cuts of the same underlying data. Design each
view around who's looking at it, not around what the data warehouse happens to store.

## Engineering Dashboard (Daily View)

Sits wherever engineers already spend their time — CI, Slack, or the team wiki.

**Include:**
- CI pass rate (today and 7-day trend)
- Top 5 flaky tests with failure count
- Test suite duration by stage (unit, integration, E2E)
- Coverage delta on latest PR (increased/decreased)
- Skipped test count
- Number of quarantined tests awaiting fix

**Exclude:** Business-level metrics, ROI calculations, historical trend analysis beyond 30 days.

**Refresh cadence:** Real-time or per-build.

Most of what's here is leading indicators — signals that predict an escape before it
happens, which is exactly why engineers need to see them daily.

## Leadership Dashboard (Monthly View)

Answers a single question: is quality trending up, holding steady, or slipping?

**Include:**
- Defect escape rate trend (3-6 month view)
- MTTR by severity (monthly average)
- Quality gate pass rate (% of releases that passed all quality gates)
- Automation ROI (cumulative savings)
- Severity distribution trend
- Release confidence score (composite metric, see below)
- DORA metrics, if leadership also wants delivery throughput alongside quality (see SKILL.md)

**Exclude:** Individual test names, CI runner details, code-level coverage numbers.

**Refresh cadence:** Monthly or per-release.

This is mostly lagging territory — the impact is already known one way or the other
by the time you see it, which fits a monthly leadership review.

### Release confidence score (example weighting, not a standard)

```
Release confidence = (0.3 × pass_rate) + (0.3 × (100 - defect_escape_rate))
                   + (0.2 × coverage_score) + (0.2 × (100 - flakiness_rate))
```

Each input is normalized to a 0-100 scale (`coverage_score` is your coverage
percentage, capped at 100). Treat this as a starting composite rather than a
canonical formula — pass rate and flakiness tend to move together, so this
particular weighting double-counts test health to some extent. Adjust the weights
to reflect what actually matters to your team, and read the resulting number as a
trend line rather than a grade. Whatever weighting you settle on, write it down so
the score stays comparable from month to month.

## Sprint Health Dashboard (Per-Sprint View)

Feeds sprint retrospectives and planning sessions.

**Include:**
- Tests added vs. features shipped (ratio)
- Bugs found in sprint vs. bugs escaped to production
- Flakiness rate change during the sprint
- Coverage change during the sprint
- Test debt items created vs. resolved

**Refresh cadence:** Updated at sprint boundaries.

Plug this directly into the retro template so the numbers drive the conversation
instead of everyone arguing from opinion.
