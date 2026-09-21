---
name: testing-in-production
description: >-
  Covers how to validate safety WHILE a release is actively rolling out: feature
  flags, progressive rollouts, canary analysis, guardrail metrics, production
  smoke tests, and synthetic users — the connective tissue between QA and SRE
  work. Use when: "feature flag testing," "canary deploy," "progressive
  rollout," "guardrail metrics," "dark launch," "safe rollout." Not for:
  scheduled probes that run continuously after release — use
  `synthetic-monitoring`. Not for: designing tests from prod telemetry — use
  `observability-driven-testing`.
  Related: release-readiness, synthetic-monitoring, observability-driven-testing, qa-metrics.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: production
---

<objective>
There is exactly one environment that behaves like production: production. Staging is always an approximation — it can't reproduce real traffic volume, real data shapes, or the quirks of live third-party integrations. This skill is about validating quality directly against that live environment without gambling with it: keep the blast radius small, wire up automatic rollback, watch guardrail metrics, and run smoke tests that surface problems before your users do. What it's guarding against is the classic failure mode — a release pushed to every user at once, with no flag to flip off, no baseline to compare against, and no rollback path anyone has actually tried.
</objective>

## Where to Start

| Situation | Go to |
|-----------|-------|
| Shipping a feature behind a flag | Feature Flag Testing |
| Ramping traffic 1% → 100% with gates | Progressive Rollout + `references/rollout-policy.md` |
| Need post-deploy checks on every release | Production Smoke Tests + `references/patterns.md` |
| Deciding what numbers gate the rollout | Guardrail Metrics |
| New code path with no user-visible change yet | Dark Launches |
| Proving the rollback actually works | Verification |

---

## Questions to Ask First

Look for `.agents/qa-project-context.md` before asking anything below — if it's there, treat it as authoritative and only ask about what it doesn't already cover.

**Feature-flag tooling:**
- Is there a feature flag platform in use? (LaunchDarkly, Statsig — now part of OpenAI, GrowthBook, Unleash, Flagsmith, Harness FME — formerly Split, custom-built, or none at all)
- Where do flags live and get managed — a dashboard, a config file, environment variables?
- Can targeting be scoped to individual users, percentages, or named segments?
- How many flags are currently live, and is anything cleaning up the stale ones?

**Rollout mechanics:**
- Is there a way to ship to only part of the traffic — canary infra, weighted routing, flags?
- How long does a full deploy take, and how long does undoing one take?
- Are deploys blue-green, rolling, or something else?
- Can traffic be split by region, cohort, or raw percentage?

**Observability maturity:**
- What's actually instrumented — APM, logs, error tracking, custom metrics?
- Are there live dashboards for errors, latency, and the metrics the business cares about?
- Do alerts exist, and are their thresholds sane?
- Is there a way to watch canary and baseline metrics side by side, live?

**Access and safety controls:**
- Who can touch production, and does that require approval?
- Are dedicated test accounts available in the live environment?
- Can actions be taken in production without touching real user data?
- Is there an incident-response process if something breaks?

---

## Principles This Skill Runs On

### 1. Production is the environment that actually matters for final validation

No amount of staging fidelity captures production's real data volume, real traffic shape, real third-party behavior, or real users. Running tests there isn't recklessness — it's just being honest about where the truth lives. The real question is never "should we," it's "how do we do this without breaking things."

### 2. Shrink the blast radius before you touch anything

Before running a production test, answer: if this fails, how many people feel it? That number should be as close to zero as you can make it. This is the entire point of feature flags, canary releases, and traffic splitting — they turn "100% of users" into "1% of users, or fewer."

### 3. Never test without a rollback that's already been proven to work

Identify the rollback mechanism before the test starts, and make sure it's both fast and actually tested. Flipping a flag off is a solid rollback plan. Rolling back to the prior deploy is acceptable too. "We'll deal with it if it breaks" is not a plan at all. An untested rollback is just a guess dressed up as a plan — the [Verification](#verification) section covers how to actually prove one works.

### 4. No monitoring means no production testing

Without real-time visibility into error rates, latency, and the metrics the business tracks, you have no way to know a test caused a problem. Monitoring isn't optional tooling here — it's the thing that makes production testing safe at all. Close any observability gaps before you add more production tests.

### 5. Nothing you do in production should leave a mess

A production test should never mutate real user records, fire real notifications, touch real payment rails, or leave behind side effects someone has to clean up by hand. This means synthetic accounts, dedicated test flags, and isolated resources aren't optional extras — they're the baseline requirement.

---

## Feature Flag Testing

Of all the production-testing mechanisms, flags are the safest: they separate the act of deploying code from the act of releasing it to users, and they roll back instantly.

### Cover both the ON state and the OFF state

Every flagged feature needs coverage in both positions. The OFF path is not just a fallback — **it's your rollback path**, so it has to work perfectly. Drive both states with `setFeatureFlag(name, true|false, { userId: TEST_USER_ID })`. The complete ON/OFF test pair lives in `references/patterns.md`.

### Validate the whole lifecycle, not just on/off

A flag moves through several distinct states over its life, and each transition deserves its own validation pass, not just a final on/off check.

```
Flag lifecycle:
  Created → Targeting internal users → Canary (1%) → Partial (10-50%) → Full (100%) → Cleanup (removed)

Test at each stage:
  - Internal: Feature works for internal accounts, hidden from external
  - Canary: Metrics are comparable between flag-on and flag-off cohorts
  - Partial: No performance degradation at scale
  - Full: All user segments work correctly
  - Cleanup: Code with flag removed behaves identically to flag-on
```

### Don't let flags outlive their usefulness

An old flag sitting in the codebase is quiet technical debt. Set up a **weekly CI job** that asks the flag provider which flags are **at 100% rollout and older than 14 days** — those are ripe for cleanup: strip the branching logic and keep only the path that's actually enabled. Deleting the flag but leaving the dead branch behind is only half the job.

### Test the flag combinations that could actually collide

Interacting flags need combination coverage, but that doesn't mean exhaustively testing all 2^N possibilities. Narrow it to flags touching the **same user flow** — for example `new-checkout`, `express-pay`, and `discount-engine-v2` all sit on the checkout path. From there, a handful of representative combinations is enough: fully new, a realistic mix, and fully legacy. The looping test pattern for this lives in `references/patterns.md`.

---

## Progressive Rollout

> **Check for a built-in canary analysis feature before building your own.** Your platform may already do this: **LaunchDarkly Guarded Rollouts** (progressive rollouts with automatic, metric-driven rollback, running on a frequentist sequential-testing model since early 2026), **Statsig Auto-tune**, **Argo Rollouts AnalysisRun**, **Flagger**, **Harness Continuous Verification**. Reaching for one of these beats maintaining your own analysis loop, since it already understands your metrics and rollback wiring.
>
> **Rolling out AI features is a distinct pattern** — the flag's value becomes a model variant plus a prompt, wrapped in cost guardrails and a kill switch. The documented route for this is **LaunchDarkly AI Configs / AgentControl** (AI Configs was folded into the AgentControl branding in May 2026). Full detail on that pattern lives under `release-readiness`.

### Ramping from 1% to 100% in stages

Rather than one big-bang release, move traffic through stages with explicit criteria required to advance past each one.

| Stage | Traffic | Hold Time | Key Checks |
|-------|---------|-----------|------------|
| Canary | 1% | 15-30 min | Error rate, crash rate, exceptions |
| Early adopters | 10% | 1-2 hours | Latency P95, conversion rate |
| Partial | 50% | 2-4 hours | All guardrails, business metrics |
| Full | 100% | 24 hours monitoring | Long-tail issues, batch job compatibility |

### Let promotion and rollback happen automatically

Advancement between stages should hinge on conditions a machine can check — a `hold_duration` combined with metric thresholds like `error_rate_5xx < 0.5%`, `latency_p95 < 500ms`, `crash_rate == 0`. On the other side, rollback should fire the moment a guardrail is breached, **without waiting on a human**: `error_rate_5xx > 2x_baseline for 5m`, `latency_p99 > 3x_baseline for 5m`, `crash_rate > 0.1% for 2m` — each of these paging on-call. Don't rely solely on raw multiplier thresholds; also gate on **error-budget burn rate**, which catches the slow burns that eventually blow through an SLO even while looking fine moment-to-moment. The complete promotion YAML, rollback trigger set, and SLO-gate config are in `references/rollout-policy.md`.

### Don't trust a fired rollback until you've confirmed it worked

A rollback triggering and an incident actually being resolved are two different things. Once rollback fires, hold off on calling it "recovered" until each of these has been checked:

1. **Re-run the health-check smoke test** against production (`GET /api/health` returns `healthy` and the previous `version`).
2. **Confirm the flag or deploy state actually reverted** — query the flag platform or check which build is serving traffic; never just assume it worked.
3. **Confirm guardrail metrics are back to baseline** — error rate, P99 latency, and crash rate all within their pre-deploy windows.
4. **Confirm on-call was actually notified** (Slack/PagerDuty), so someone owns the incident.

The rollback is only verified once all four checks pass. The [Verification](#verification) section below covers the staging dry-run used to prove this whole chain before it's ever relied on in production.

---

## Production Smoke Tests

### Checks that run right after every deploy

These should fire as their own **pipeline stage** immediately post-deploy — not just live in pre-deploy CI. Their job is confirming core functionality actually works against real production configuration, data, and infrastructure: hit `/api/health`, walk through auth with synthetic credentials, load core data, and run a search. Set `retries: 1` plus a `timeout` so one flaky run doesn't block the whole pipeline. The complete `production-smoke.spec.ts` suite is in `references/patterns.md`.

### Keep test accounts obviously fake

A production test account should never be mistaken for a real one: use a reserved email pattern (`smoke-test+{env}@yourcompany.com`), set an `is_synthetic = true` flag on the record, and exclude these accounts from analytics, billing, and email campaigns. Provision them through the admin API rather than the UI, and favor short-lived OIDC / workload-identity tokens over passwords that live forever. Full conventions are in `references/patterns.md`.

### Reads only — writes need guaranteed cleanup

Smoke tests against production should be read-only wherever possible. Where a write is genuinely unavoidable, its cleanup belongs in **fixture teardown**, so it fires regardless of whether the test passes or fails.

One trap to avoid: calling `test.afterEach()` from inside a `test()` body. Playwright only registers hooks at describe/file scope, so a hook added mid-test never gets scheduled — it just throws `test.afterEach() can only be called in a describe block`, and the data it was supposed to clean up leaks. The fix is an auto-cleanup fixture that tracks created resource IDs and deletes them during teardown (or, for a quick one-off script, a `try/finally` block). The full fixture-based create-verify-cleanup pattern is in `references/patterns.md`.

---

## Guardrail Metrics

### What to keep an eye on mid-rollout

| Category | Metric | Comparison Method | Alert Threshold |
|----------|--------|-------------------|-----------------|
| Errors | HTTP 5xx rate | vs. pre-deploy baseline | >2x baseline for 5 min |
| Errors | Unhandled exception count | vs. pre-deploy baseline | Any new exception type |
| Latency | P50 response time | vs. pre-deploy baseline | >1.5x baseline |
| Latency | P95 response time | vs. pre-deploy baseline | >2x baseline |
| Latency | P99 response time | vs. pre-deploy baseline | >3x baseline |
| Business | Conversion rate | vs. 7-day average | Drop >5% |
| Business | Revenue per session | vs. 7-day average | Drop >10% |
| Client | Crash rate (mobile) | vs. previous release | >0.1% increase |
| Client | JavaScript error rate | vs. pre-deploy baseline | >2x baseline |
| Infra | CPU utilization | absolute | >80% sustained |
| Infra | Memory utilization | absolute | >85% sustained |

### What to compare against

A canary's metrics are most meaningful next to a control group still on the old version — not just against historical numbers in isolation.

```
Comparison approaches (best to worst):
  1. Canary vs. control: split traffic, compare groups in real time (best)
  2. Before/after: compare post-deploy metrics to pre-deploy window (good)
  3. Historical: compare to same time last week (acceptable for trends)
  4. Absolute thresholds: fixed thresholds regardless of baseline (fragile)
```

### Don't trust conclusions before you have enough data

Business metrics like conversion and revenue are noisy at low volume. Hold off on conclusions until the sample size is actually large enough to mean something.

```
Minimum sample sizes for rollout decisions:
  - Error rate: 1,000 requests (errors are rare events, need volume)
  - Latency: 500 requests (more stable, converges faster)
  - Conversion rate: 5,000 sessions (business metrics have high variance)
  - Crash rate: 10,000 app launches (crashes are rare events)

Rule of thumb: if you don't have enough traffic at 1% to reach
significance in 30 minutes, increase to 5% or extend the hold window.
```

---

## Dark Launches

A dark launch puts new code live in production while keeping it invisible to users — real traffic exercises the new path, but nobody sees a difference.

### Shadowing live traffic

Send a copy of each incoming request to the new service alongside the real one, and compare the two responses — but only the real service's response ever reaches the user.

```
Request flow:
  User → Load Balancer → Production Service (returns response to user)
                       ↘ Shadow Service (processes request, logs result, discards)

What to compare:
  - Response status codes: shadow should match production
  - Response body: diff for semantic equivalence (ignore timestamps, IDs)
  - Latency: shadow should not be significantly slower
  - Error rate: shadow should not produce more errors
```

### Running old and new side by side

When migrating something substantial — a database, an algorithm, an entire service — run both implementations in production at once. The old path is what users actually get; the new one executes asynchronously alongside it, logs any discrepancies, and throws away its own output. Watch how the match rate trends over time, aiming for 99%+ before cutting over for real.

```
Shadow launch timeline:
  Week 1: Deploy shadow, start comparing, expect <50% match
  Week 2: Fix mismatches, match rate should climb to 90%+
  Week 3: Match rate stable at 99%+, handle remaining edge cases
  Week 4: Cut over: shadow becomes primary, old becomes shadow
  Week 5: Remove old path after 1 week of stability
```

---

## Anti-Patterns

### Production testing with nothing watching
No dashboards, no alerts, no visibility — running tests this way means the first sign of trouble is a user complaint, not your own instrumentation.
**Fix:** Treat monitoring as a hard prerequisite, not an add-on. Before any production test runs, confirm error rates, latency, and the relevant business metrics are all visible in real time, and that alerts already exist.

### Skipping the rollback plan
"We'll just push a fix if it breaks" isn't a rollback plan — it's a promise made under pressure, when fixes are slower, riskier, and more likely to introduce a second bug on top of the first.
**Fix:** Every production test or rollout needs a documented rollback path that executes in under 5 minutes — disabling a flag, redeploying the previous build, or rerouting traffic — plus a verification step confirming the system actually came back healthy (see [Verification](#verification)).

### Tests that leave real damage behind
A test that creates a real order, sends a real email, or edits real user data isn't really a test — it's a self-inflicted incident.
**Fix:** Rely on synthetic accounts clearly marked as test data, run payments and email through sandbox modes, and put any cleanup in fixture teardown so it always executes. If a test genuinely can't be made non-destructive, it shouldn't run in production at all.

### Cleanup that skips itself on failure
Put a cleanup step after an assertion, and the moment that assertion fails, the cleanup never runs — leaking precisely the data it existed to remove. Calling `test.afterEach()` from inside a `test()` body falls into this same hole: it either throws or silently does nothing.
**Fix:** Put teardown in an auto-cleanup fixture, or a `finally` block, so it executes whether the test passes or fails. Details in `references/patterns.md`.

### Using production to paper over a broken staging environment
Production testing is meant to supplement pre-production testing, not stand in for it. If staging is broken and "testing in production" is really just working around that, the actual fix is repairing staging.
**Fix:** Keep pre-production genuinely functional. Reserve production testing for the things only production can tell you — real traffic, real data at scale, real third-party behavior.

### Canary rollouts with nothing to compare against
Shipping to 1% of traffic without comparing its metrics to a control group defeats the purpose — it's just a slower rollout, not a safer one, since nothing is actually being detected.
**Fix:** Always benchmark canary metrics against a baseline, whether that's a side-by-side dashboard or an automated canary-analysis tool (Kayenta, Argo Rollouts analysis).

### Flags that never get removed
A flag that's fully rolled out but never cleaned up just sits there. Do that for a year and you end up with hundreds of flags, unknown interactions between them, and branching logic nobody remembers the reason for.
**Fix:** Give every flag an expiration date the moment it's created. Once it's fully rolled out and has held stable for 2 weeks, remove both the flag and its dead code branch. Track flag age and alert when one overstays its expiration.

---

## Verification

An untriggered rollback is just a theory — prove the path actually fires **before** it's ever relied on for real. Work up from the smallest check:

1. **Trip a guardrail in staging.** Force a failure — push `error_rate_5xx` past `2x_baseline`, or fail the health check 3 times in a row — on a staged rollout wired to the same `automatic_rollback` policy the real one uses. Verify the rollback action fires inside its `for:` window.
2. **Check the reverted state.** Re-run the health-check smoke test and assert `status === 'healthy'` with the **previous** `version` string. Query the flag platform or deploy system directly to see which build is actually serving traffic — never assume.
3. **Check that metrics actually recovered.** Error rate, P99 latency, and crash rate should all sit back inside their pre-deploy windows.
4. **Check that the notification actually fired.** The rollback alert should have reached the on-call channel (Slack/PagerDuty).
5. **Check that smoke tests are actually wired into the pipeline.** Run the deploy job against staging and confirm the post-deploy smoke stage runs and gates promotion — `npx playwright test production-smoke.spec.ts` should exit 0.

If steps 1 through 4 can't be shown working in staging, treat the rollback as unverified — the rollout isn't ready.

> **Shortcut for agents:** LaunchDarkly, GrowthBook, Unleash, Flagsmith, Statsig, and Harness FME all have vendor MCP servers, so an AI agent can flip flags and pull rollout metrics directly during these checks instead of clicking through a dashboard.

---

## Done When

- The flag rollout plan spells out explicit percentage steps (1% → 10% → 50% → 100%) and names the guardrail metrics for each stage.
- Canary analysis has automated pass/fail criteria configured, so neither promotion nor rollback depends on someone eyeballing metrics.
- Production smoke tests run as their own pipeline stage on every deploy — not only in pre-deploy CI — and that stage exits 0 against real production.
- Rollback triggers are defined, written down, and proven via the [Verification](#verification) staging dry-run — guardrail tripped, rollback fired, reverted state and recovered metrics all confirmed — before the rollout ever touches production for real.
- The production test-data approach is documented: synthetic users or anonymized real ones, and exactly how they stay out of analytics and billing.

## Reference Files (in `references/`)

- **rollout-policy.md** — the full promotion-criteria YAML, automatic-rollback trigger definitions, and the error-budget / SLO-gate config.
- **patterns.md** — flag ON/OFF and combination tests, the `production-smoke.spec.ts` suite, synthetic-account conventions, and the fixture-based non-destructive create-verify-cleanup pattern.

## Related Skills

- **release-readiness** — Owns the go/no-go call for the release as a whole; production testing is just the post-deploy verification piece inside it. Check there for the release checklist rather than rollout mechanics.
- **synthetic-monitoring** — Covers scheduled probes that keep running *after* the rollout is finished. That's where ongoing SLA validation lives, not in-flight rollout safety.
- **observability-driven-testing** — Takes prod traces and logs as *input* for designing new tests. Go there when telemetry is what's telling you what to test next, not when the goal is shipping safely right now.
- **qa-metrics** — Where guardrail metrics and rollout criteria ultimately roll up into dashboards and KPIs.
- **ci-cd-integration** — Handles wiring the smoke-test stage and rollout gates into the actual pipeline.
- **test-environments** — Covers the pre-production environments that production testing complements — and never replaces.
