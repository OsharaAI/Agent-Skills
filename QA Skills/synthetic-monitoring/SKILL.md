---
name: synthetic-monitoring
description: >-
  Always-on scheduled checks that keep probing production long after a
  release ships. Covers how to design probes for the journeys that matter
  most, wire probe results into an alerting pipeline, validate SLAs, run
  probes from multiple regions, and where QA responsibilities hand off to
  SRE. Use when someone mentions "synthetic
  monitoring," "uptime testing," "scheduled probes," "SLA validation,"
  "availability monitoring," or "post-deploy checks." Not for: safe-release
  techniques applied during a rollout — see testing-in-production instead.
  Not for: building new tests from production telemetry — see
  observability-driven-testing instead. Not for: a single post-deploy smoke
  gate tied to one release — see release-readiness instead.
  Related: testing-in-production, release-readiness, performance-testing, qa-metrics.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: production
---

<objective>
Synthetic monitoring is the practice of firing the same scripted checks at your live production system on a fixed, never-ending cadence, rather than only right after a release. It's the thing that catches an outage, a slowdown, or a broken flow before a customer has to email support about it — including the 3 AM window when the app has no real traffic at all. Relying on status codes alone won't get you there: a login page that returns a cheerful 200 while every authentication attempt quietly fails will sail past a naive uptime check, and only gets caught once a probe verifies that the dashboard actually renders afterward. This skill covers building those probes, wiring them into alerting, holding them to an SLA, distributing them across regions, and writing runbooks so a middle-of-the-night page doesn't turn into a guessing game.
</objective>

## Where To Go

| If you're trying to... | Go to |
|-----------|-------|
| Choose a platform (Checkly, Datadog, Grafana, CloudWatch…) | Platform Options |
| Write a probe (login, API health, search) | Probe Design → `references/probe-implementations.md` |
| Figure out why probes stay green while users complain | Failure Modes |
| Quiet down noisy alerts (or stop missing real ones) | Alerting Integration |
| Work out a downtime budget for an SLA | SLA Validation |
| Handle a 3 AM probe failure with no idea where to start | runbook template in `references/platforms-and-ci.md` |

---

## Before You Start: Discovery

Look at `.agents/qa-project-context.md` before asking anything below — if it's already answered there, skip re-asking. Each answer shapes which probes get written, where alerts route, and how the SLA math shakes out.

**Which journeys actually matter** (this determines the probe list):
- Identify the 5-10 journeys whose breakage would hurt most — login, search, checkout, signup, or whatever counts as the core workflow. Each becomes a probe.
- Which of those directly cost revenue or customers if they break? Those earn the tightest schedule and the authority to wake someone up.
- What fails silently — sync jobs, webhooks, background processing? These need probes even more than visible features, precisely because no user will ever file a report about them.
- Are there existing documented SLOs/SLAs for uptime and latency? If so, they directly set your downtime budget and alert thresholds.

**What's already watching** (this determines where the real gaps sit):
- What monitoring already exists — uptime pings, APM, error tracking, dashboards? Build on top of it rather than duplicating it, and look for what's uncovered.
- Where's the gap between what's monitored and what a user actually experiences? That gap is exactly where a new probe earns its keep.
- How are outages discovered today — an alert, a support ticket, a tweet? If the honest answer is "a customer complained," shrinking that detection time is job one.
- Trace back through the most recent real outage: how long passed between it starting and someone noticing? That's the number your probes have to beat.

**Infrastructure shape** (this determines region count and what gets asserted):
- One region, or several? Serving from multiple regions means probing needs to match that spread.
- Is a CDN or edge/caching layer sitting in front of the origin? If it is, a probe can stay green while the origin burns — header assertions are what catch that.
- Do third-party dependencies (payments, auth, email) publish their own status pages? Those belong in your runbooks.
- Where do alerts need to land — PagerDuty, OpsGenie, Slack, email? This drives the routing config.

**Data safety** (this determines how probes are allowed to touch production):
- Are dedicated synthetic accounts already set up in prod? Without them, every probe run contaminates real data and skews real analytics.
- Can those accounts be scrubbed out of analytics, billing, and marketing sends? If not, probe traffic silently distorts any downstream number that touches them.
- Is there a programmatic way to create and tear down test data? That's what determines whether "create, verify, delete" probes are realistic for you.

---

## Principles Worth Internalizing

### 1. It's watching even when nobody else is
Real-user monitoring (RUM) reports what already happened to actual visitors; synthetic monitoring tells you what's happening right now, whether or not anyone's around. The 3 AM scenario is the whole point of this skill — with zero real users to notice something's broken, a probe is the only thing standing watch. Think of the two as complementary: synthetic walks a fixed set of known paths on a predictable schedule, while RUM catches the unpredictable things real users actually do.

### 2. A probe should be small enough to trust
Once a "probe" takes two minutes and clicks through fifteen pages, it's no longer a probe — it's an E2E suite that happens to run against prod. Cap each one at a 30-second wall-clock budget, scope it to a single critical path, and set retries to zero — a flaky probe is worse than a flaky test, because it pages an actual human. A slow probe that "still passes" is masking a degradation your users are already living with.

### 3. One blip is noise; a pattern is a signal
Networks hiccup and DNS resolvers have off days — a single failed run tells you almost nothing on its own. The signal worth acting on is two consecutive failures, and ideally failures surfacing from more than one region simultaneously, which rules out a local fluke. Build thresholds around consecutive failures plus multi-region confirmation, or the team will — rightly — learn to ignore the pager.

### 4. Leave production data exactly as you found it
A probe running every few minutes, all day every day, means even a trivial side effect — one stray row, one incremented counter — compounds quickly. Every probe needs to be non-destructive, clean up immediately after itself, and stay excluded from analytics, billing, and (easy to forget) your own SLO/error-budget math. Skip this and your probes end up grading their own homework.

### 5. Check that the job got done, not that the server answered
A 200 from `/login` proves nothing if authentication is silently failing underneath it. A 200 from `/search` proves nothing if the result set comes back empty. Build every assertion around the outcome the user was actually after — did data load, did auth succeed, did results show up — instead of settling for "the page didn't 500."

---

## Designing Probes

Base probe design on the journeys users actually take, not on the health of isolated infrastructure components. Nobody using your product cares if the load balancer says it's healthy — they care whether they can log in and finish their work.

| Probe | What it confirms | How often | Timeout |
|-------|-------------------|-----------|---------|
| Homepage load | DNS, CDN, server, basic rendering | 1 min | 10s |
| Login flow | Auth service, session handling | 5 min | 15s |
| Core workflow | The main value-delivering action (e.g., creating a document, running a report) | 5 min | 20s |
| API health | Backend services, DB connectivity | 1 min | 5s |
| Search | Index health, query handling, result rendering | 5 min | 15s |
| Checkout (where relevant) | Payment integration (sandbox), cart, order creation | 10 min | 25s |
| Third-party integrations | OAuth, outbound email, file storage | 10 min | 15s |

### What the actual probe code looks like

Three patterns handle nearly every case: a browser-driven login flow (Playwright), an API health check (status plus auth plus a latency ceiling), and a search probe (submit a query, then check the results themselves rather than trusting the status code). Each one should stay confined to a single path, use a tight timeout, and skip retries entirely. Complete, runnable versions of the login, API-health, and search probes — along with the environment-aware config that lets identical code target either staging or production — are in `references/probe-implementations.md`.

### Keeping probes harmless

```
Fine to do:
  - Anything read-only: GETs, page loads, searches
  - Sandboxed transactions: test-mode payments, email sent only to internal addresses
  - Create, verify, delete: spin up a draft, confirm it, remove it right away
  - Tag-and-exclude: mark synthetic actions so downstream systems ignore them

Avoid:
  - Anything that creates a real order, ticket, or user-visible record
  - Anything that fires a real notification — email, SMS, push
  - Touching shared config, permissions, or settings
  - Anything that can't be cleaned up automatically afterward
```

### What a synthetic account needs

```
Requirements:
  - Obviously synthetic at a glance: email contains "synthetic" or "monitor"
  - Flagged in the DB (is_synthetic = true)
  - Kept out of analytics, billing, marketing sends, and support queues
  - Kept out of RUM and out of SLO/error-budget math — it isn't real traffic
  - Seeded with stable data the probe can depend on run after run
  - Credentials pulled from a secrets manager (process.env), rotated quarterly
  - One account per concurrently-running probe, to avoid two probes fighting over state
```

---

## Choosing a Platform

| Platform | What it's good at | Best fit |
|----------|-----------|----------|
| Checkly | Playwright-native, code-first, Git-integrated; **Rocky**, its AI agent (GA 2026), now runs automated root-cause analysis across Playwright/API/Multistep/TCP/DNS/ICMP checks; scriptable via CLI from any AI agent; ships an MCP server | Teams that already write Playwright E2E tests |
| Datadog Synthetic | Tight APM integration, both browser and API checks | Teams already living in Datadog |
| Grafana Synthetic Monitoring | Open source, plugs into existing Grafana dashboards; pairs with k6 2.x — pin a version channel (v1.x/v2.x) if you want reproducible runs | Teams standardized on the Grafana stack |
| AWS CloudWatch Synthetics | Ready-made blueprints (heartbeat, API, broken-link, visual diff); canaries in Python or Node/Puppeteer | Teams already on AWS |
| New Relic Synthetics | Fits into a broader full-stack observability setup | Teams on New Relic |
| Better Stack | Lightweight uptime checks plus status pages and on-call, out of the box | SMBs wanting something fast to stand up |
| Uptime Kuma | Open-source, self-hosted, minimal footprint | Self-hosting is a requirement and needs are modest |
| Roll-your-own (Playwright / k6 / Puppeteer + cron) | Total control, zero vendor lock-in | Tight budgets or unusual requirements |

> Probe code typically gets written in Playwright (TS/JS), Puppeteer, k6 (JS — k6 2.0, shipped May 2026, added AI-assisted authoring and a cleaner Assertions API and is now a solid first-class option for synthetic checks), or Python (CloudWatch Synthetics, Checkly). Pick whichever your team already maintains comfortably. One thing worth avoiding: don't stand up something new on Pingdom — it's a legacy uptime tool at this point. Favor the code-first options (Checkly, Grafana, a custom Playwright setup) that keep probes living in version control alongside the app.

### Running it yourself vs. letting a vendor run it

Self-managed route: a GitHub Actions `schedule` cron firing every 5 minutes runs the Playwright probes, prod credentials arrive as secrets, and results get posted to a monitoring webhook. Vendor-managed route: Checkly, being Playwright-native, runs the same kind of check from multiple locations on a fixed cadence without you having to own the scheduler. Either way, write probes to be environment-aware — the same probe code should work against staging or production just by swapping the base URL and thresholds. The GitHub Actions workflow, the Checkly config, the alert-routing rules, and the runbook template all live in `references/platforms-and-ci.md`.

---

## Wiring Up Alerts

Not every failed probe run is an incident — the goal is a rule set that filters noise without missing a real outage.

```
Rules:
  - One failure: just log it (probably a transient network blip)
  - 2 failures in a row, same region: warning (might be something)
  - 2 failures in a row, 2+ regions: page on-call (this is a confirmed outage)
  - Latency over 2x baseline for 10 minutes: warning (degradation)
  - Latency over 3x baseline for 5 minutes: page on-call (severe degradation)
  - Any timeout, 3 in a row: page on-call (service isn't responding)
```

**How it routes.** Failures on revenue-critical probes (login, checkout, api-health) page on-call through PagerDuty and post to a Slack incidents channel, on a short repeat interval; warnings from secondary probes route instead to a Slack monitoring channel; info-level events use a much longer repeat interval. None of this fires unless each probe result carries `severity` and `probe` labels — the complete `alerting-rules.yaml` and the tagging step are in `references/platforms-and-ci.md`.

**Don't let planned maintenance page anyone.** A maintenance window should mute synthetic paging entirely (probes failing during it is expected) and should be excluded from error-budget math — otherwise scheduled work looks like a reliability problem and pages someone for nothing.

**What a good alert message includes** — enough that whoever picks it up can start investigating without having to ask questions first:

```
Alert template:
  Title: [SYNTHETIC] {probe_name} failing from {region}
  Severity: {critical|warning|info}
  Consecutive failures: {count}
  Last success: {timestamp}
  Error: {error_message}
  Duration: {last_response_time_ms}ms (threshold: {threshold}ms)
  Dashboard: {link_to_dashboard}
  Runbook: {link_to_runbook}
  Regions affected: {list_of_failing_regions}
```

`{link_to_runbook}` should point to a compact, six-line runbook per probe covering: what it checks, what to look at first, how to reproduce it manually, when to escalate, where the dashboard lives, and who owns it. The template is in `references/platforms-and-ci.md`.

---

## Holding Probes to an SLA

### Working out availability

```
Availability = (total_minutes - downtime_minutes) / total_minutes × 100

Where:
  - total_minutes = minutes in the calendar month (43,200 for a 30-day month)
  - downtime_minutes = minutes during which a synthetic probe detected a failure

Common tiers (monthly downtime budget, on a 43,200-minute month):
  99.0%  = 432 min   = 7h 12min     (a basic web app)
  99.9%  = 43.2 min  = 43min 12s    (a typical business application)
  99.95% = 21.6 min  = 21min 36s    (a critical SaaS product)
  99.99% = 4.32 min  = 4min 19s     (infrastructure or platform-level services)
```

> These tiers are common reference points, not a menu you pick from by label. The right target comes from analyzing actual user impact, not from a tier's name. Current SRE thinking (see Google's SRE Workbook and OpenSLO) favors explicit SLOs paired with error-budget policies over named tiers: define what a user-visible failure looks like concretely, size the budget to how much impact is tolerable, and let the number emerge from that. References: https://sre.google/workbook/ ; https://openslo.com/

### Look at percentiles, not the average

Averages smooth over exactly the experiences you should care about — track percentiles instead.

```
Example SLA response-time targets:
  Homepage load:  P50 < 1s,    P95 < 3s,   P99 < 5s
  API response:   P50 < 200ms, P95 < 500ms, P99 < 1s
  Search results: P50 < 500ms, P95 < 2s,   P99 < 4s
  Login flow:     P50 < 2s,    P95 < 5s,   P99 < 8s
```

### Tying it to an error budget

An error budget is what converts an SLA number into an actual engineering decision.

```
Example:
  SLO: 99.9% availability over a 43,200-minute month
  Budget: 0.1% of total time = 43.2 minutes/month

  Spent so far this month: 12 minutes (28%)
  Left: 31.2 minutes (72%)

What to do based on what's left:
  >50% remaining: business as usual, ship normally
  25-50% remaining: get cautious, review what changed recently
  <25% remaining: pause non-critical deploys, prioritize reliability work
  Fully spent: treat it like an incident — every deploy gets extra scrutiny
```

Exclude downtime from your own maintenance windows from this calculation, or planned work will masquerade as a reliability problem.

---

## Probing From More Than One Place

Run checks from the regions your actual users occupy — a service that's fine from us-east-1 but broken from ap-southeast-1 is, functionally, down for everyone in APAC.

```
Picking regions:
  - At least 3 for anything global
  - Always cover: nearest to primary infrastructure, largest user population, farthest from primary
  - US-primary example: us-east-1, eu-west-1, ap-southeast-1
  - EU-primary example: eu-west-1, us-east-1, ap-northeast-1
```

Track latency per region instead of as a single blended number — a global average will hide a struggling region.

```
Example regional latency view:
  Region       | P50    | P95    | Status
  us-east-1    | 120ms  | 340ms  | healthy
  eu-west-1    | 280ms  | 620ms  | healthy
  ap-southeast | 450ms  | 1200ms | warning (P95 over threshold)

Worth alerting on:
  - Any region whose P95 crosses its own threshold
  - A 5x+ latency gap between regions (points to a CDN or routing problem)
  - A previously-healthy region settling into consistent degradation
```

**Checking the CDN layer.** Have probes inspect response headers (`x-cache`, `cf-cache-status`) looking for a `HIT`, and confirm the `server` header matches the provider you expect. This surfaces CDN misconfiguration — and catches an origin failure hiding behind a stale cached response — before users experience it as a slow, uncached page.

---

## Common Mistakes

### Building probes that are really mini E2E suites
A "probe" clicking through ten pages, filling five forms, and checking twenty elements has stopped being a probe — it's an E2E test that happens to run against prod. When it fails, distinguishing a real outage from probe flakiness becomes guesswork. **Instead:** one critical path per probe, under 30 seconds, under 5 assertions, so a failure tells you immediately what's actually broken.

### Paging on every single failed run
Occasional failures from network blips, DNS hiccups, and general cloud flakiness are just background noise of running anything at scale. Alert on every single one and the team learns to tune out alerts altogether. **Instead:** require 2-3 consecutive failures plus confirmation from 2+ regions before paging anyone. Escalate in steps — first failure logs, second warns, third pages.

### Letting probes share an account
Two probes on a shared account collide — one changes a setting, the next fails because it assumed the default was still intact. **Instead:** give each concurrently-running probe its own dedicated, flagged, synthetic account, excluded from analytics and billing.

### Only checking that the page loads
A probe that stops at "page returned 200" misses anything broken beneath a spinner or a stuck loading state. A login screen returning 200 without actually authenticating anyone is still broken. **Instead:** assert on something meaningful — data actually loading, auth actually succeeding, the core action actually completing, search actually returning results. One probe checking "did the user get what they came for" beats ten that only look for a 2xx.

### Shipping probes with no runbook behind them
The alert fires at 3 AM. On-call sees "Login probe failing" and has nothing further to go on — not what it checks, not where to start looking, not how to tell a real outage apart from a probe hiccup. **Instead:** attach a runbook to every probe (what it tests, what to check first — third-party status, recent deploys, telemetry — how to reproduce it manually, when to escalate, and a dashboard link). Template's in `references/platforms-and-ci.md`.

**Worth watching (2026): agents doing first-pass triage.** Tools like Checkly's Rocky (GA 2026, automated root-cause analysis spanning check types) and Honeycomb's Canvas Skills (Agent Observability, shipped May 2026 — the open-source `honeycombio/agent-skill` repo includes a honeycomb-investigator and an instrumentation-advisor for Claude Code and Cursor) can read probe context, the linked runbook, and telemetry, then automatically post a candidate diagnosis into chat. That's useful as a first pass that trims MTTR on routine failures — but it doesn't substitute for human judgment on anything genuinely novel.

---

## Failure Modes

| Symptom | Likely cause | What to do |
|---------|--------------|--------------|
| Probe stays green, users report an outage | Probe only checks for HTTP 200, not the actual outcome | Add assertions on content/state — a dashboard heading, a result count, `body.status` |
| Alerts fire and resolve repeatedly (flapping) | No consecutive-failure or multi-region gate | Require 2+ consecutive failures plus 2+ regions before paging |
| Passes locally, fails in a specific CI run or region | A regional outage, or CDN routing gone wrong | Compare results across regions; check the latency-gap and `x-cache` assertions |
| Probe fails but there's no real outage | Synthetic account has drifted state (shared account) | Give each concurrent probe its own isolated, reset/seeded account |
| Origin is actually down but the probe is green | CDN is serving a stale cached response | Assert on `cf-cache-status` / the origin `server` header, not just a 200 |
| Error budget draining with no incident to show for it | Maintenance windows are being counted as downtime | Mute synthetic paging during maintenance; exclude that window from the budget math |
| On-call gets paged but can't do anything with it | Runbook link is missing or empty | Fill in the six-line runbook; check that `{link_to_runbook}` actually resolves |
| Reliability numbers look suspiciously perfect | Synthetic traffic is being counted as real in SLO/RUM | Filter `is_synthetic` traffic out of RUM, billing, and error-budget pipelines |

---

## Confirming It Actually Works

Verify starting from the smallest check and working outward — don't just trust that the setup is correct.

1. **Run probes against staging.** `npx playwright test probes/ --reporter=list` against staging, confirming every probe completes within its declared timeout (none exceeding the 30s ceiling).
2. **Prove a failure actually pages someone.** Point a probe at a deliberately broken URL (a `503`, or a bad path), let it fail through the configured consecutive-failure count, and confirm the page reaches on-call within your SLA's detection-time target — and that it clears once the URL is fixed again.
3. **Prove the assertions aren't just checking status.** Temporarily break whatever's being asserted on (rename a heading on staging, for instance) and confirm the probe actually fails. If it stays green, the assertion is checking the wrong thing.
4. **Confirm synthetic traffic is filtered out.** Query analytics/RUM/billing for `is_synthetic` traffic and verify none of it is leaking through.

---

## Definition of Done

- Every critical journey surfaced during discovery has a probe — not just a homepage ping or a lone health endpoint — and each one asserts on the actual outcome, not a bare 2xx.
- Every probe finishes under 30 seconds wall-clock, with `retries: 0`.
- Alerting config enforces both a ≥2 consecutive-failure rule and a multi-region confirmation rule, with every probe result tagged `severity` + `probe` so routing actually matches.
- The SLA dashboard shows live availability and error-budget burn, and synthetic traffic is filtered out of RUM, billing, and error-budget pipelines.
- A deliberately-failing test probe reaches on-call within the SLA's detection-time target — verified once, not assumed to work.
- Every probe links to a non-empty runbook covering first checks, manual reproduction, and escalation.
- There's an actual recurring review mechanism for monitoring health (a scheduled job or a standing calendar item) — not just a plan to check on it eventually.

## Reference Files (in `references/`)

- **probe-implementations.md** — Working login-flow, API-health, and search probe code, plus the environment-aware probe config.
- **platforms-and-ci.md** — The GitHub Actions scheduling workflow, the Checkly config, alert-routing rules with the tagging step, and the per-probe runbook template.

## Related Skills

- **testing-in-production** — covers safe-release *techniques* (flags, canaries, guardrail metrics) used *during* a rollout; this skill is the schedule-driven check that keeps running continuously *after*.
- **release-readiness** — owns the one-time post-deploy smoke gate tied to a specific release; come here instead for the continuous version that outlives any single release.
- **observability-driven-testing** — takes production telemetry (including signals these probes generate) as *input* for designing new tests; this skill *generates* the probes and the telemetry in the first place.
- **performance-testing** — load tests measure capacity under deliberate load; synthetic probes track how production performance *trends* in the gaps between those load tests.
- **qa-metrics** — the availability, latency-percentile, and error-budget numbers probes produce feed directly into the quality dashboards defined there.
- **ci-cd-integration** — see that skill for wiring synthetic probes into a pipeline as a post-deploy verification stage.
