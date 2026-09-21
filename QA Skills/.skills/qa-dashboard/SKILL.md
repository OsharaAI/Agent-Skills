---
name: qa-dashboard
description: >-
  Build and visualize QA dashboards and reports with Allure Report, Grafana, and
  ReportPortal. Covers test execution visualization, stakeholder-facing quality
  reports, trend/flakiness panels, release-readiness gates, alerting, and CI
  integration for automated report generation.
  Use when: "test dashboard," "Allure," "test report," "quality dashboard,"
  "Grafana," "ReportPortal," "test results visualization."
  Not for: defining which KPIs to measure or how to interpret them — use qa-metrics
  (this skill builds the panels; qa-metrics decides what they should show).
  Related: qa-metrics, ci-cd-integration, ai-bug-triage.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: metrics
---

<objective>
The goal is dashboards that push people toward action, not dashboards that merely display
numbers. What this guards against: a wall of panels announcing "5 failures" with nothing
linking to those failures, no stated target, and no trend line — essentially a notification
wearing a tool's clothing, which stops getting opened by the third week. This skill covers
audience-specific QA reporting: polished HTML reports via Allure, live trend panels with
regression alerting through Grafana/InfluxDB, self-hosted AI-assisted aggregation via
ReportPortal, and stakeholder summaries generated automatically. Each panel should tie back
to a real question someone asks, and every red indicator should drill straight down to the
failing test.
</objective>

## Quick Route

| Situation | Go to |
|-----------|-------|
| Already on Grafana for infra metrics | **Grafana Dashboards** — add test metrics alongside prod |
| Test runner has a hosted dashboard (Cypress/Playwright) | **SaaS-Native Dashboards** — least plumbing |
| Need rich HTML report, no infra to run | **Allure Report** — generate in CI, publish artifact |
| Need self-hosted aggregation across frameworks + AI triage | **ReportPortal** |
| Need a single view across multiple runners | **Grafana** or **Allure** (cross-runner aggregation) |
| Need a weekly summary / release verdict for stakeholders | **Stakeholder Reports** |

---

## Discovery Questions

Look at `.agents/qa-project-context.md` first — when it's present, use what's there and don't re-ask anything it already answers. Otherwise work through:

1. **What's currently used for test reporting?** Plain console output, JUnit XML, HTML reports, or an existing dedicated platform? This pins down the starting point and how much integration work remains.
2. **Who is the dashboard for?** Developers want failure detail and traces; QA leads want trend lines and flakiness data; leadership wants a confidence read and defect rates. Each of these audiences needs its own view — not a shared one.
3. **What decision is this dashboard supposed to inform?** Is this build releasable? Which tests need attention? Is quality trending up sprint over sprint? A dashboard with no decision behind it just becomes shelfware.
4. **Where do the test results actually get stored?** GitHub Actions artifacts, S3, a database? Wherever results live constrains which dashboarding tool is realistic.
5. **Which CI platform is in play?** GitHub Actions, GitLab CI, Jenkins — the artifact and reporting integrations differ across each.

---

## Core Principles

**1. A dashboard should answer a question, not just print a number.** Every panel needs to correspond to something someone would actually ask. "What's the flakiness rate?" qualifies. "Total test count" is trivia.

**2. Different audiences want different views.** Someone debugging a CI failure needs stack traces, screenshots, traces — a VP just wants a yes/no on release readiness. Don't try to serve both from the same screen.

**3. CI moves in real time; leadership moves in trends.** A CI dashboard should refresh on every pipeline run, while a leadership-facing one should roll up weekly or per sprint. Mixing those cadences confuses everyone looking at either.

**4. Every red indicator needs a next click.** A failing test, a flaky test, a coverage gap — each should be a link, not just a label. A panel that reports "5 failures" with nowhere to go is a notification, not a dashboard.

**5. Report generation should be automatic.** Anything that depends on someone running a script, copying numbers, or building slides by hand will quietly die the first time the sprint gets busy. Wire report generation into CI.

---

## Allure Report

Allure turns test results into polished HTML reports, with history, categories, and retry tracking built in, and it plugs into Playwright, Jest, Vitest, pytest, and most other frameworks.

**Allure 2 vs Allure 3.** These are two distinct paths that are easy to conflate, since the framework adapters (`allure-playwright`, `allure-vitest`, `allure-jest`) all still emit the same Allure 2 result files — what differs is the reader that turns those results into a report:

- **Allure 2 path** — `allure-commandline` (2.42.1, Jun 2026). Running `brew install allure` gets you **this**, not v3. Its commands are `allure generate` / `allure open` / `allure serve`, and categories come from a `categories.json` file dropped into `allure-results/`. It's stable and effectively frozen now — dependency bumps only.
- **Allure 3 path** — the `allure` npm package plus `allurerc.mjs` (3.9.0, May 2026). A full TypeScript rewrite bringing plugins, a single config file, live `allure watch`, project-wide quality gates, multi-environment reports, and **Allure Service** for server-side history. Its commands are `npx allure run` / `npx allure generate` / `npx allure watch`, and categories live inside `allurerc.mjs` instead — the dropped-in `categories.json` file belongs to v2.

New projects should default to Allure 3. That said, if you're only using `brew install allure` and `allure generate`, you're on the **v2** path — which is still fully supported, just be clear on which one you've got.

A minimal Playwright wiring: register the adapter with `reporter: ["allure-playwright", { outputFolder, environmentInfo }]` so every run writes its results into `allure-results/` along with the captured environment:

```typescript
// playwright.config.ts
reporter: [
  ["list"],
  ["allure-playwright", {
    outputFolder: "allure-results",
    environmentInfo: {
      Environment: process.env.TEST_ENV ?? "local",
      BaseURL: process.env.BASE_URL ?? "http://localhost:3000",
    },
  }],
],
```

Attach per-test metadata (`allure.severity` / `feature` / `story` / `tag`) so results group sensibly, define failure
`categories` so product bugs are separated from infra breakage, and make sure `history/` carries over across CI
runs — otherwise there's no trend data at all. **An Allure report without history is just a single snapshot: no
trend line, no way to spot intermittent failures.** `references/allure.md` has the complete Playwright/Vitest
configs, the v2 `categories.json`, the v3 `allurerc.mjs` plus the `allure run` runnable path, and the GitHub
Actions steps for preserving history.

---

## Grafana Dashboards

Grafana provides live dashboards plus alerting, and it's the natural choice when infra metrics already live there and test metrics should sit alongside them.

**Data pipeline:** a CI step that runs after tests parses the results (JUnit XML, coverage JSON, timing data) and writes points into a time-series database — InfluxDB or a Prometheus pushgateway — which Grafana then queries. The push script emits two measurements: `test_execution` (one point per individual test, tagged with `suite`/`test_name`/`status`/`branch`/`run_id`) and `test_run_summary` (one point per overall run, carrying `pass_rate`, `total`, `failed`, `avg_duration_ms`). Every point should carry `branch` and `run_id` tags so panels can be filtered down to `main` or traced back to a specific run.

Because the script executes under `if: always()`, the write loop needs a try/flush/close wrapper — without it, a mid-loop exception discards every point that had been buffered. `references/grafana.md` contains the full `push-test-metrics.ts` script (flush guard included) and the corresponding GitHub Actions step.

### Recommended panels

| Panel | Question | Query shape |
|-------|----------|-------------|
| **Pass Rate Trend** (time series) | Is quality improving? | `SELECT mean("pass_rate") FROM "test_run_summary" WHERE "branch"='main' GROUP BY time(1d)`, thresholds at 95% (yellow) / 99% (green) |
| **Release Readiness** (stat) | Is main ready to release? | `SELECT last("pass_rate") FROM "test_run_summary" WHERE "branch"='main'`, red <95 / yellow 95–99 / green ≥99 — pair with a coverage stat ≥80 |
| **Flakiness Top 10** (table) | Which tests waste the most time? | `SELECT "test_name", count("retries") AS retry_count FROM "test_execution" WHERE "retries">0 AND time>now()-14d GROUP BY "test_name" ORDER BY retry_count DESC LIMIT 10` |
| **CI Duration Trend** | Is the pipeline getting slower? | `avg_duration_ms` over time with a target line at 600s |

The complete set of queries, along with Coverage Trend and Duration Distribution panels, is in `references/grafana.md`.

### Alerting

Alert rules provision as YAML under `provisioning/alerting/` (this needs Grafana 11+). The one that the Done
When section requires — **the main branch's pass rate falling more than 2 percentage points in a single
day** — is built from two queries (mean `pass_rate` over the trailing `1d` versus the day prior) feeding into
a math expression, `$yesterday - $today > 2`, and routed out through a Slack contact point (an incoming-webhook
URL). The fully provisioned rule and contact point live in `references/grafana.md`. Worth alerting on as well:
pass rate under 95% over a 10-minute window, CI duration exceeding 15 minutes, and coverage dropping more than
2% within a week. **Dashboards support investigation; alerts handle detection** — a dashboard nobody looks at
won't catch anything.

---

## ReportPortal

A self-hosted reporting platform offering ML-driven failure analysis, aggregation across frameworks, and live dashboards.

```bash
# Pin to a tagged release (current 26.0.x line: 26.0.3). The `master` branch may not
# match the supported 26.x line.
curl -LO https://raw.githubusercontent.com/reportportal/reportportal/26.0.3/docker-compose.yml
docker compose up -d
# Access at http://localhost:8080 (default: superadmin/erebus)
# ML auto-analysis lives in the `service-auto-analyzer` container — confirm it is running.
```

Starting with 26.0.3, ReportPortal can also ingest **agentic** test results — launches are tagged with an
`AGENTIC` vs `AUTOMATION` execution-type badge — which matters if any part of the suite runs through Claude
Code or a similar agent.

### Playwright integration

```typescript
// playwright.config.ts
reporter: [
  ["list"],
  ["@reportportal/agent-js-playwright", {
    apiKey: process.env.RP_API_KEY,
    endpoint: process.env.RP_ENDPOINT ?? "http://localhost:8080/api/v1",
    project: "my-project",
    launch: `E2E Tests - ${process.env.CI ? "CI" : "local"}`,
    attributes: [
      { key: "branch", value: process.env.GITHUB_HEAD_REF ?? "local" },
      { key: "build", value: process.env.GITHUB_RUN_ID ?? "dev" },
    ],
  }],
],
```

Install with `npm i -D @reportportal/agent-js-playwright`.

| Feature | What it does |
|---------|--------------|
| **Auto-analysis** | ML failure classification: product bug, test bug, system issue, or to-investigate |
| **Defect type mapping** | Custom defect categories with sub-types for your project |
| **Flaky test detection** | Tests that flip pass/fail across launches |
| **Merge launches** | Combine sharded CI runs into one unified view |
| **Quality gates** | Pass/fail criteria per launch (max failures, min pass rate) |
| **Comparison** | Side-by-side of two launches to spot regressions |

After a run finishes, quality gate status can be queried at `GET /api/v1/$PROJECT/launch/$LAUNCH_ID/quality-gate` —
use that as a CI gate and fail the pipeline whenever the status isn't `PASSED`.

### Allure TestOps (managed alternative)

For teams that would rather not self-host, **Allure TestOps** (26.2.x line, 2026) offers the SaaS route:
Allure 3 quality gates, named environments, global attachments, and Allure 3-style flaky detection (a test
gets flagged once it shows 3 or more status transitions across its last 10 runs). Its **MCP server is in
public beta (26.1.1)**, which lets AI agents query launches and quality gates directly — useful when the QA
workflow runs through Claude Code or Cursor.

---

## SaaS-Native Test Dashboards

When a test runner ships its own first-class hosted dashboard, favor it over Allure/Grafana for that runner's native data — it means less plumbing, longer retention, and PR comments out of the box. Bring in Allure/Grafana only when aggregation across multiple runners is actually needed.

| Platform | Test runner | Native data + PR comments |
|----------|-------------|---------------------------|
| **Cypress Cloud** | Cypress | Test replay, parallelization, flake detection; AI add-on (Auto Heal, Bug Triage) |
| **Currents.dev** | Cypress, Playwright | OSS-friendly Cypress Cloud alternative; lower price point |
| **Playwright HTML + `--reporter=blob`** | Playwright | Free, self-hosted; combine shards with `merge-reports` |
| **Datadog Test Optimization** | Any (CI-side) | Flaky Test Management (now with Bits AI auto-fix), TIA, native APM |
| **Allure TestOps** | Any | Allure 3 quality gates, named environments, MCP server beta |

**Combining sharded Playwright runs, for free, natively.** Each shard emits a blob report, and those get merged into a single HTML report afterward — the zero-cost way to combine sharded CI runs:

```bash
# each shard: npx playwright test --reporter=blob   (uploads blob-report/ as an artifact)
npx playwright merge-reports --reporter html ./blob-reports
```

Reach for Allure or Grafana when a single cross-runner dashboard is genuinely needed, or when a SaaS tool's pricing or data-residency terms don't work. Short of that, the SaaS-native dashboard is typically the cheapest route to PR-level signal.

---

## Stakeholder Reports

**Weekly QA Summary** — set this up as a scheduled CI job rather than a manual task. It should carry the pass rate and its trend, new versus fixed failures, the top 5 flaky tests, the coverage delta, and average CI duration. Bucket overall health as STABLE (>= 98%), NEEDS ATTENTION (>= 95%), or CRITICAL (< 95%), and push it to Slack automatically.

**Release Quality Report** — produced ahead of each release, gated on: E2E pass rate >= 99%, unit pass rate at 100%, branch coverage >= 80%, no critical bugs, at most 2 major bugs, and the Core Web Vitals budget. The output is a READY / NOT READY verdict along with a pass/fail breakdown per gate.

For the performance gate, the current (2026) Core Web Vitals "good" thresholds are: **LCP under 2500ms, INP under 200ms, CLS under 0.1.** Gate on INP rather than FID — INP took over as the Core Web Vital from FID on 2024-03-12, and FID was retired completely on 2024-09-09.

---

## Recommended Dashboard Panels

A practical baseline that covers the questions teams most often ask.

| Panel | Question It Answers | Data Source | Audience |
|-------|-------------------|-------------|----------|
| **Pass/Fail Trend** | Is quality improving or degrading? | CI test results over time | Everyone |
| **Flakiness Top 10** | Which tests waste the most time? | Tests with retries in last 14 days | Developers, QA |
| **Coverage Heatmap** | Where are we blind? | Coverage by module/directory | Developers |
| **Defect Escape Trend** | Are bugs reaching production? | Incidents tagged as test escapes | QA leads, Leadership |
| **CI Duration** | Is the pipeline getting slower? | Pipeline duration over time | DevOps, Developers |
| **Test Velocity** | Tests proportional to features? | New tests added per sprint | QA leads |
| **Failure Categories** | Product bugs or test infra? | Categorized failure reasons | QA leads |
| **Release Readiness** | Can we ship? | Composite score from all gates | Leadership |

---

## Anti-Patterns

**A 30-panel dashboard.** Nobody reads it. Start small — 5 or 6 panels answering the most pressing questions — and only add more once someone asks a question the existing set can't answer.

**Metrics with no frame of reference.** "Pass rate: 97%" is meaningless on its own; it needs a target ("99%") and a comparison point ("98.5% last week") to actually be useful.

**Hand-run report generation.** Anything that requires someone to SSH in, run queries by hand, and paste results into slides will stop happening around week 3. Push it into CI instead.

**One dashboard serving both developers and leadership.** Developers want failure details, stack traces, repro steps; leadership just wants a single traffic-light signal. These need to be separate views.

**Treating test counts as a progress metric.** "200 new tests added" tells you nothing about quality on its own. Critical-path coverage, defect escape rate, and mean time to detect regressions are the more meaningful numbers.

**Skipping alerts on regressions.** A dashboard nobody actively checks accomplishes nothing. Set alerts for pass-rate drops, coverage decreases, and CI-duration increases — dashboards handle investigation, alerts handle detection.

**Running Allure without history.** A one-off Allure report is just a snapshot: no trend, no way to catch intermittent failures, no sense of improvement over time. Always keep `history/` across CI runs, or lean on Allure 3 / Allure Service for server-side history instead.

**Blending the Allure 2 and 3 code paths.** Talking about v3 in your docs while actually running `brew install allure` + `allure generate` + a dropped-in `categories.json` puts you on v2 with v2-style categories. Commit to one path and use its commands consistently, start to finish.

---

## Verification

Confirm the report or dashboard actually renders before marking this done. Start with the smallest checks:

```bash
# Allure: a report builds and the trend widget shows >1 run (history preserved)
npx allure generate allure-results --clean -o allure-report && npx allure open allure-report
#   -> Overview page loads; the "Trend" widget shows more than one run.

# Grafana push: the summary point landed in InfluxDB
influx query 'from(bucket:"test-results") |> range(start:-1d) |> filter(fn:(r)=> r._measurement=="test_run_summary")'
#   -> returns at least one row with a pass_rate field for branch=main.

# Grafana alert: the provisioned rule loaded
curl -s http://localhost:3000/api/v1/provisioning/alert-rules -u admin:admin | jq '.[].title'
#   -> includes "Main pass rate dropped >2pp in a day".
```

---

## Done When

- The dashboard lives at a known location that returns HTTP 200 for the team — a CI artifact URL, a Grafana URL, or a hosted SaaS link — with no local setup or manual report run needed to view it.
- Test execution trends (pass rate, failure count, duration) show at least 2 weeks of historical data.
- The flakiness panel is set up and shows the top flaky tests with retry counts over a rolling 14-day window.
- Some stakeholder report is generating automatically — **either** a weekly summary carrying a STABLE/NEEDS ATTENTION/CRITICAL label, **or** a per-release quality report with a READY/NOT READY verdict and per-gate breakdown (either one, or both, satisfies this).
- An alert is wired up and routed (to Slack or similar) that triggers whenever the main branch's pass rate falls by more than 2 percentage points within a single day.

## Related Skills

- **qa-metrics** — Covers defining quality KPIs, measurement frameworks, and how to interpret metrics. Use it to decide *what* gets measured; this skill is for *visualizing* it.
- **ci-cd-integration** — Pipeline setup for automated report generation and artifact management.
- **ai-bug-triage** — AI-driven failure classification that feeds the dashboard's failure categories.

## Reference Files (in `references/`)

- **allure.md** — the complete Playwright/Vitest adapter configs, per-test metadata, the v2 `categories.json`, the v3 `allurerc.mjs` plus `allure run` runnable path, and the CI history-preservation workflow.
- **grafana.md** — the `push-test-metrics.ts` script (flush guard included), the full set of panel queries, and the provisioned ">2pp pass-rate drop" alert rule plus its Slack contact point.
