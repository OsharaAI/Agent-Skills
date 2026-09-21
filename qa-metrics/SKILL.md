---
name: qa-metrics
description: >-
  Covers defining, tracking, and acting on QA metrics — test coverage percentage,
  flakiness rate, defect escape rate, MTTR, test execution time trends, automation ROI,
  quality gates, and test-suite SLAs. Provides the formulas behind each metric, sensible
  targets by company stage, and what to do when a metric turns red.
  Use when: "QA metrics," "test metrics," "quality KPIs," "test health," "flakiness rate,"
  "defect escape rate."
  Not for: building the dashboard UI (Allure/Grafana), which belongs to qa-dashboard; or
  measuring coverage gaps and mutation score, which belongs to coverage-analysis.
  Related skills: qa-dashboard, coverage-analysis, ci-cd-integration, release-readiness, quality-postmortem.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: metrics
---

<objective>
Imagine a suite of 4,000 tests, 800 of them disabled and 200 flaky — it reads fine on a slide but misrepresents reality once it ships. This skill lays out the metrics that genuinely influence behavior: each comes with a formula, a target, a responsible owner, and a specific response for when it turns red, turning the dashboard into a feedback loop rather than window dressing.
</objective>

## Quick Route

| Your situation | Metric to reach for | Section / reference |
|---|---|---|
| Starting from zero, unsure where to begin | code coverage, flakiness, defect escape | Core Principles + `references/rollout.md` |
| Bugs still escaping despite strong coverage | defect escape rate + mutation score | Coverage Metrics, Defect Metrics |
| Flaky tests, developers tuning out CI | flakiness rate, pass rate | Test Health Metrics |
| Pipeline is slow, feedback arrives late | suite duration, parallelism efficiency | Execution Metrics |
| Need to justify spend on automation | automation ROI | Process Metrics |
| Choosing targets appropriate to our stage | company-stage table | Setting Realistic Targets |
| Leadership wants both delivery and quality | DORA + escape rate | Engineering Quality Metrics (DORA) |
| Need the dashboard view itself | (go to `qa-dashboard`) | — |

---

## Discovery Questions

First check whether `.agents/qa-project-context.md` exists — if so, treat it as your baseline and don't re-ask what it already covers. Otherwise, work through:

### Current State
- What metrics are you tracking today? (Even "we glance at CI pass rate sometimes" counts.)
- Where does your test data live? (CI system, coverage reports, bug tracker, spreadsheets, nowhere)
- Do you have any dashboards already? Who looks at them, and how often?
- What tooling runs your CI pipeline? (GitHub Actions, GitLab CI, Jenkins, CircleCI)

### Stakeholders
- Who are the stakeholders for quality metrics? (engineering, product, leadership, customers)
- What does each care about? Engineers want flakiness; leadership wants escape trends; product wants release confidence.
- Who will own each metric? If nobody owns it, nobody acts on it.

### Quality Problems
- What quality problems need visibility? (regressions, slow pipelines, flaky tests, coverage gaps, incidents)
- What broke in production recently? Would a metric have caught it earlier?
- What decisions are you making without data today?

### Goals
- What does "healthy test suite" mean for your team?
- Any compliance or contractual quality requirements? (SLAs, SOC2, ISO)
- Quick wins vs. full observability — what is the appetite for metrics infrastructure?

---

## Core Principles

### 1. A Metric Without a Response Plan Is Just Decoration
Every metric needs three things defined up front: the threshold that triggers action, what that action is, and who's responsible for taking it. Example: once flakiness passes 5%, the on-call engineer picks the three flakiest tests and digs into them that same week — no ambiguity about what happens next.

### 2. Track Leading and Lagging Metrics, But Act on the Leading Ones
Defect escape rate and MTTR are **lagging** — by the time you see them, users have already felt the pain. Flakiness, coverage delta, and skipped-test count are **leading** — they warn you before an escape happens. Leadership uses lagging metrics to gauge overall direction; engineers should focus their day-to-day attention on the leading ones, since those are still changeable.

### 3. Look at the Trend, Not the Snapshot
One number in isolation tells you almost nothing. "Coverage is 72%" is meaningless on its own, but "coverage moved from 68% to 72% over three sprints" tells a real story. Chart metrics as time series and judge them by direction of travel rather than where they sit right now.

### 4. Every Metric Wants a Target and an Owner
Targets are what make a metric something you can act on; owners are what make it someone's job. Skip either one and the metric fades into noise. Derive targets from your team's maturity level (see the targets table) and hand ownership to whoever can actually influence the number.

### 5. Don't Waste Effort Chasing Vanity Metrics
"4,000 tests" sounds great until you learn 800 are disabled and 200 are flaky. What counts is tests that actually run, pass consistently, and catch genuine bugs. Work backward from the real goal — whether users hit bugs that damage the business. Defect escape rate ties directly to that outcome; raw lines of test code do not tie to anything.

---

## Essential QA Metrics

For every metric below you get: what it means, how to calculate it, a suggested target, why it's worth tracking, and what to do once it goes red.

### Test Coverage Metrics
*How much of our system is verified by automated tests?* (leading)

#### Code Coverage Percentage
The share of code that automated tests actually exercise (measured at the line, branch, or statement level).

```
Line coverage   = (lines executed by tests / total executable lines) × 100
Branch coverage = (branches executed by tests / total branches) × 100
```

**Targets:** Line: 70-85% for app code. Branch: 60-75%. Critical paths (payments, auth): 90%+.

**Why it matters:** Coverage surfaces the blind spots — untested code is exactly where bugs go unnoticed.

**When it goes red:** If coverage drops on a PR, block the merge or flag it. If a critical module is under-covered, open targeted tickets. If coverage plateaus, check whether that's dead code or actually untested logic.

**Warning:** Coverage tells you what ran, not whether the assertions were any good. Pair it with mutation testing (StrykerJS v9.6+, mutmut) to get a truer signal. Stryker's Vitest runner tends to track recent Vitest releases, so verify the runner's peer-dependency before locking in a Vitest version. Set `incremental: true` in monorepo CI to keep mutation runs affordable. For a deeper dive into coverage and mutation analysis, see `coverage-analysis`.

#### Requirement Coverage Percentage
```
Requirement coverage = (features with at least one test / total features) × 100
```
**Targets:** 100% for P0/P1 features, 80%+ for P2.

**Why it matters:** It's possible for a feature to have no tests at all even when the code around it is well-covered. Tag tests (`@feature:checkout`, `@story:PROJ-1234`) so you can trace coverage back to features.

#### Risk Coverage Percentage
```
Risk coverage = (high-risk areas with automated tests / total high-risk areas) × 100
```
**Targets:** 95%+ for high-risk areas. Keep a risk register and check it against per-module coverage data.

---

### Test Health Metrics
*Can we trust our test suite?* (leading)

#### Flakiness Rate
The share of test runs that give inconsistent results with no underlying code change.

```
Flakiness rate = (test runs with flaky results / total test runs) × 100
```

**Targets:** Acceptable: <2%. Warning: 2-5%. Critical: >5%.

**Why it matters:** Trust erodes fast once tests are flaky. The moment developers start assuming "it's probably just flaky," they stop actually reading results — flakiness is arguably the biggest single threat to a suite's credibility.

**When it goes red:** Quarantine the offending tests right away. Each week, dig into the three flakiest — a small handful of tests usually accounts for most of the noise. Typical root causes include timing or race conditions, shared state, external dependencies, and order-dependent tests. Anything still flaky after 30+ days should be rewritten or removed.

**Detection:** Buildkite Test Analytics, **Datadog Test Optimization** (the successor to Datadog CI Visibility — includes Flaky Test Management, Auto Test Retries, Early Flake Detection, Failed Test Replay, and Test Impact Analysis, with a Bits AI Dev Agent that can open PRs to fix flaky tests on its own), Trunk Flaky Tests, or simply a script that diffs results across multiple runs of the same commit.

#### Pass Rate Trend (7-Day Rolling)
```
Pass rate = (green CI runs / total CI runs) × 100  [rolling 7 days]
```
**Targets:** Healthy: >95%. Warning: 90-95%. Broken: <90%.

Averaging over a rolling 7 days irons out day-to-day noise so the underlying trend shows through. A build that's red more often than not means the team has stopped trusting the pipeline.

#### Disabled and Skipped Test Count
Total tests marked `skip`, `disabled`, `pending`, `xit`, `xdescribe` or equivalent.

**Target:** Push this toward zero over time. Anything skipped for more than 2 sprints should be fixed or removed. Add a CI check that fails the build once skipped tests exceed 5% of the total.

**Why it matters:** Skipped tests hide coverage gaps that dashboards don't surface. A suite with 500 passing tests and 150 skipped ones is actually missing `150 / (500 + 150) = 23%` of its coverage — a number most dashboards won't show you.

#### Test Suite Duration
Wall-clock time from suite start to completion.

**Targets:** Unit: <5 min. Integration: <10 min. E2E: <15 min. Full pipeline: <30 min (the per-stage numbers are the actual budget — the 30-minute figure is just their sum, not a looser separate ceiling).

**Why it matters:** Slow-running tests kill the feedback loop. If results take 45 minutes, the developer has already moved on to something else mentally.

**When it goes red:** Profile which tests are slowest (often the slowest 10% eat up half the total runtime). Add more parallelism. Push slow tests to run post-merge instead of pre-merge. Look for wasteful setup/teardown. Track duration over time and alert on sudden jumps (a >20% increase within a week).

---

### Defect Metrics
*Are we catching bugs before users do?* (lagging)

#### Defect Escape Rate
Of all the defects found, the proportion that were caught only after reaching production.

```
Defect escape rate = (defects found in production / total defects found) × 100
```

**Targets:** Excellent: <5%. Acceptable: 5-10%. Needs work: 10-20%. Critical: >20%.

**Worked example:** Say a release turns up 15 defects total and 2 surface in production → `2 / 15 × 100 = 13.3%` escape rate, putting it in the "needs work" bucket.

**Why it matters:** Arguably the most important quality metric there is — it tells you directly whether your testing is catching bugs before customers do.

**When it goes red:** Sort escaped defects by the layer that should have caught them (unit, integration, E2E, or code review), and write a retrospective test for each one. Watch for escapes clustering around particular areas — those deserve extra investment.

**How to track:** Label production bugs (`escaped-defect`) and, at sprint retros, tally escaped defects against those caught pre-release.

#### Mean Time To Resolution (MTTR)
```
MTTR = sum(resolution_time for each defect) / number of defects
```
**Targets:** P0: <4 hours. P1: <24 hours. P2: <1 sprint. P3: <2 sprints.

A high MTTR usually points to process friction — slow reviews, unclear ownership, cumbersome deploys — more often than genuine technical difficulty. Split the timeline into phases (triage, assign, fix, deploy) to isolate where things stall. (Note this is QA's *defect* resolution time, not the same thing as the DORA recovery metric further down.)

#### Defect Density
```
Defect density = defects found / KLOC  (or per feature shipped)
```
**Targets:** Establish your own baseline; the wider industry runs 1-10 defects per KLOC. A module running 5x denser than others is a candidate for refactoring or better test coverage.

#### Severity Distribution
A healthy mix looks like: P0 <5%, P1 10-15%, P2 40-50%, P3 30-40%. Chart it as a stacked bar over time — a heavy skew toward P0/P1 signals that testing is missing the critical issues.

---

### Execution Metrics
*Is our CI pipeline fast, reliable, and cost-effective?* (leading)

#### CI Pipeline Duration
Wall-clock time, broken down per stage. **Targets:** Lint: <2 min. Unit: <5 min. Integration: <10 min. E2E: <15 min. Full: <30 min (this is the stage totals added up, matched against the suite-duration budget).

**When it goes red:** Tackle whichever stage is slowest first. Separate fast checks that run on every push from slower ones reserved for PR merge. Profile how much time goes to setup versus actual execution. Look for stages running sequentially that could run in parallel.

#### CI Cost Per Run
```
CI cost per run = (compute minutes × cost per minute) + fixed costs
```
For example, 50 builds a day at $0.50 apiece works out to $750/month. Bring this down by caching dependencies, using spot instances, right-sizing runners, and skipping suites that nothing has touched.

#### Parallelism Efficiency
```
Parallelism efficiency = (total sequential time / (wall-clock time × workers)) × 100
```
**Target:** >80%. For instance, if 4 workers finish in 3, 3, 3, and 12 minutes, the wall-clock time is 12 and the sequential total is 21, giving efficiency = `21 / (12 × 4) = 44%` — well below target since three workers sat idle for 9 minutes each. Address this by splitting work based on estimated duration rather than file count, breaking apart slow test files, and using dynamic splitting tools (Playwright sharding, Jest `--shard`).

---

### Process Metrics
*Is our QA process improving over time?* (mix of leading and lagging)

#### Automation Rate
```
Automation rate = (automated test cases / total test cases) × 100
```
**Targets:** Regression: 90%+. Smoke: 100%. Exploratory: 0% (by definition). Overall: 70-85%.

Manual testing simply doesn't scale, whereas automation pays off repeatedly — write a test once and it runs thousands of times after. Prioritize automating whatever scenarios run most often.

#### Test Creation Velocity
The count of net-new automated tests added each sprint (excluding refactors of existing ones).

**Target:** Aim for at least 3-5 automated tests per shipped user story. A sprint that ships 20 features with zero new tests is a sign the coverage gap is widening.

#### Automation ROI
```
Manual cost     = (manual time per cycle × cycles per year) × hourly rate
Automation cost = (write time + annual maintenance) × hourly rate
ROI             = (manual cost - automation cost) / automation cost × 100
```
**Example:** Manual regression testing costs 8 hrs/release × 26 releases × $75/hr = $15,600/yr. Automating it costs 120 hrs to build plus 40 hrs/yr of upkeep at $75/hr — $12,000 in year one, then $3,000/yr afterward. That gives a year-1 ROI of `(15,600 - 12,000) / 12,000 = 30%` and a year-2 ROI of `(15,600 - 3,000) / 3,000 = 420%`. Use numbers like these to make the case to stakeholders.

---

### Engineering Quality Metrics (DORA)

DORA metrics have become the common language of leadership delivery dashboards. They complement defect escape rate: DORA covers delivery throughput while QA metrics cover delivery quality.

| Metric | What it measures | Benchmark (top-15%) |
|--------|------------------|---|
| **Lead Time for Changes** | Commit → production | < 1 day |
| **Deployment Frequency** | How often you ship | Multiple per day |
| **Failed Deployment Recovery Time** (formerly MTTR) | Time to restore service after a *change-induced* failure | < 1 hour |
| **Change Failure Rate** | % of deploys that cause incidents | ~5% (older "high performer" bar was <15%) |
| **Rework Rate** | % of deploys that are unplanned fixes for a prior bad deploy | Low and falling |

The 2025 DORA report made **Rework Rate** an official fifth metric and reorganized the set into groups: the first three metrics above now sit under *throughput* (recovery time moved there since high-performing teams just ship a fix rather than treat it separately), while Change Failure Rate and Rework Rate form *instability*. **Reliability** — availability, latency, and error budget relative to your SLOs — is tracked as its own separate dimension, and it's where QA's escape-rate framing overlaps with SRE, since error rate and availability are effectively the user-facing symptoms of escaped defects. The 2025 report also dropped the old Elite/High/Medium/Low tier labels in favor of percentile distributions across seven team archetypes, so treat the benchmark column as a percentile, not a fixed tier you belong to. The rename to **Failed Deployment Recovery Time** (introduced in the 2023/2024 reports) exists to separate change-induced failures from external outages; it remains a delivery metric, separate from the QA defect MTTR discussed earlier.

Source: https://dora.dev/research/. Tools that pull DORA metrics from Git/CI data include Sleuth, Faros, LinearB, Jellyfish, and Swarmia.

### Test Impact Analysis (TIA) as a Lever

TIA uses coverage data to decide which tests need to run based on what code actually changed — trading test breadth for lower CI cost. Two things worth tracking:

- **% of tests skipped per PR via TIA** — a higher number means cheaper CI; if this rises without coverage dropping, TIA is doing its job.
- **Escaped defects traced to skipped tests** — your safety net. Any non-zero count means the TIA selection needs narrowing, or the always-run set needs widening.

Hosted options: Datadog Test Optimization (TIA), CloudBees Smart Tests, NCrunch (in-IDE). Or build it yourself from coverage data plus a git diff. See `coverage-analysis`.

---

## Setting Realistic Targets

Match your targets to your team's actual maturity level — going after enterprise-grade numbers at a seed-stage startup just wastes effort.

| Metric | Startup (seed-Series A) | Growth (Series B-C) | Enterprise (public/large) |
|---|---|---|---|
| Unit test coverage | 60% | 75% | 85% |
| Branch coverage | 45% | 60% | 75% |
| E2E coverage (critical paths) | Top 5 flows | Top 15 flows | All P0/P1 flows |
| Flakiness rate | <5% | <3% | <1% |
| Pass rate (7-day) | >90% | >95% | >98% |
| Defect escape rate | <20% | <10% | <5% |
| MTTR (P0) | <8 hours | <4 hours | <2 hours |
| CI pipeline duration | <20 min | <15 min | <10 min |
| Automation rate | 50% | 75% | 90% |
| Metrics tracked | 3-5 core | 8-10 with dashboards | Full suite with alerting |

**Progression path:**
1. Begin with just 3 metrics: code coverage, flakiness rate, defect escape rate.
2. Bring in execution metrics once CI cost or speed starts to hurt.
3. Bring in process metrics once the team passes 5 engineers.
4. Adopt the full suite once quality becomes a product differentiator or a compliance obligation.

The full week-by-week rollout plan, the three dashboard layouts, and the data-source extraction table live in `references/rollout.md` and `references/dashboards.md`.

---

## Anti-Patterns

- **Treating coverage as proof of quality.** Coverage tells you what ran, not what was verified. Pair it with mutation testing to get the real picture.
- **Presenting metrics with no context.** "Coverage is 74%" means nothing without a target (80%), a trend (up from 69%), and a breakdown (92% on critical paths, 40% on admin). Always show target, trend, and distribution together.
- **Gaming the numbers.** Writing throwaway tests purely to inflate coverage. Counter this by pairing coverage with defect escape rate — high coverage alongside escaping defects means the tests aren't actually testing anything meaningful.
- **Tracking too many metrics.** Track 25 and you'll act on none of them. Begin with 3, and only add another once you can name the specific action it will trigger.
- **Measuring without following through.** A Grafana dashboard nobody ever opens is worthless. Retire any metric that hasn't triggered an action in the last quarter (see the metric half-life practice in `references/rollout.md`).
- **Comparing metrics across teams.** Coverage numbers from a payments service and an admin tool aren't comparable to each other. Track each one's improvement over time instead of ranking teams against one another.

---

## Verification

The goal is a functioning feedback loop, so confirm the data actually flows before calling this done:

1. **Coverage output is machine-readable.** Run your coverage tool and check that it writes JSON or LCOV (`coverage/coverage-final.json`, `lcov.info`) rather than just an HTML report meant for human eyes.
2. **CI history can be queried.** Call your CI provider's API for the last 7 days of results and verify you can derive pass rate and flakiness from the response.
3. **Escape labels are in place.** Query the issue tracker for the `escaped-defect` label (or your team's equivalent) and confirm the tagging convention is actually being followed.
4. **A gate genuinely blocks merges.** Open a throwaway PR that lowers coverage or adds a `.skip`, and verify CI actually fails it — a gate that never fires isn't proving anything.

---

## Done When

- Key metrics have explicit formulas defined: coverage % (line and branch), flakiness rate, defect escape rate, and MTTR by severity.
- Baselines exist for each metric, drawn from at least 2 weeks of collected data, with targets assigned from the company-stage table.
- Collection is fully automated through CI integrations — coverage from the test runner, flakiness from CI run history, defects from issue-tracker labels — with no manual steps involved.
- CI enforces quality gates that block merges or deployments when flakiness crosses threshold, coverage drops, or critical tests fail (confirmed via a failing throwaway PR).
- Each metric has a named owner, and there's a metrics block built into the recurring retro template (or a standing calendar invite) — an artifact you can point to, not just a stated intention.

## Reference Files (in `references/`)

- **dashboards.md** — engineering (daily), leadership (monthly), and sprint-health dashboard layouts, along with the example weighting for the release-confidence score.
- **rollout.md** — the four-phase, week-by-week implementation plan, the data-source extraction table, and the metric half-life retirement practice.

## Related Skills

- **qa-dashboard** — builds the actual Allure/Grafana/SaaS dashboard UI that surfaces these metrics; that's where the rendering happens, this skill covers what to measure.
- **coverage-analysis** — goes deep on coverage gaps and mutation score; feeds the assertion-quality dimension into this skill's coverage metric.
- **ci-cd-integration** — sets up the CI pipelines that generate the raw data behind these metrics, including Test Impact Analysis as a cost-saving lever.
- **release-readiness** — pulls in quality gates plus DORA Change Failure Rate / Failed Deployment Recovery Time to make go/no-go calls.
- **test-reliability** — handles runtime per-test healing for the flaky tests flagged by the flakiness rate here.
- **quality-postmortem** — pairs action-item-closure-rate with escape rate as its postmortem-side metric.
- **qa-project-context** — supplies targets and baselines that feed into metrics tracking.
