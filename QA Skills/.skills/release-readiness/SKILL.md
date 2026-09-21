---
name: release-readiness
description: >-
  Confirms a release is actually safe to ship by grounding the go/no-go call in
  evidence rather than gut feel. Bundles the go/no-go checklist, smoke-suite
  design, staged and canary rollout validation, rollback thresholds and
  procedures, and the post-deployment verification pass, so "ready" means
  measured rather than assumed.
  Use when: "release ready," "go/no-go," "smoke test," "release checklist,"
  "rollback plan," "staged rollout," "canary deploy."
  Skip this one for: the safe-release mechanics themselves (flags, canary, dark
  launch) as they are applied mid-rollout — see testing-in-production instead;
  always-on probes that keep running after the release ships — see
  synthetic-monitoring; and building new tests from production telemetry — see
  observability-driven-testing.
  See also: testing-in-production, qa-metrics, ci-cd-integration, ai-system-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: process
---

<objective>
"Looks fine to me" is how an untested rollback gets improvised live, usually right as the team is heading out for the weekend. This skill swaps that gut check for something you can actually point to: a go/no-go checklist backed by evidence, a smoke suite that finishes in under five minutes, a staged rollout gated on real metrics, rollback thresholds locked in before anyone deploys, and a verification pass once the release is live. Every section states a bar to clear, not a hope to have.
</objective>

---

## Before You Start: Discovery Questions

Look for `.agents/qa-project-context.md` first. If it's there, treat it as the source of truth and only ask about gaps it leaves open.

**Cadence and ownership:**
- How often does this team ship, and who actually signs off go/no-go? (Continuous, daily, or weekly delivery — and whether the call belongs to an engineering lead, a QA lead, or a release manager — determines how heavy the checklist needs to be.)
- Is there a fixed release-train schedule, or does shipping happen whenever it's ready?
- How many environments sit between local dev and production (staging, pre-prod, canary)?

**Where things stand today:**
- What does the existing go/no-go process actually look like — and is it written down anywhere?
- Has this team ever rolled back a release, and how long did it take? (This tells you whether "we have a rollback plan" is real or theoretical.)
- What caused the most recent release incident? Are there release-blocking bugs open right now?

**Platform capability:**
- Is rollback actually possible, and what's the time-to-rollback?
- Can releases go out staged or canaried?
- Are feature flags in use, and who manages them? (This decides whether the rollout is flag-driven or infrastructure-driven.)
- What alerting and monitoring exists? Can database migrations be reversed?

**People and comms:**
- Who covers on-call during and immediately after a release?
- How do stakeholders find out a release is happening — is there a dedicated channel?
- How do release notes get written?

---

## Core Principles

### 1. Evidence beats confidence
"I think it's fine" isn't a go/no-go signal. Evidence looks like: every CI pipeline green, smoke tests passing on staging, performance budgets met, zero open P0/P1s. No data to point to means you're not actually ready — you just feel ready.

### 2. Smoke tests are a last line of defense, not the whole defense
They exist to catch catastrophic breakage, nothing more subtle. If a smoke suite is the only thing standing between your code and production, the gap is upstream in your testing process, not in the smoke suite itself.

### 3. Rolling out in stages shrinks the blast radius
Push to every user at once and every user shares the risk of any bug. Stage it — canary, percentage-based, ring-based — and a bad release only touches 1% of users before anyone notices, instead of all of them.

### 4. Decide the rollback triggers before you ship, not during the fire
Waiting until something breaks to argue about whether it's "bad enough" to roll back burns exactly the minutes you don't have. Set the bar in advance, relative to baseline: "error rate crosses 2x baseline inside 15 minutes → we roll back, full stop." Anchor that trigger to your DORA targets: if a release's error rate would blow through your change-failure-rate target, or recovering from it would exceed your MTTR target, that's precisely the scenario the rollback rule is meant to catch.

### 5. Treat each release as a chance to get better at releasing
Post-deployment review isn't only bug-hunting. Note what ran smoothly, what dragged, what was nerve-wracking — and feed that back into the process.

---

## The Go/No-Go Checklist

Treat this list as a starting template, not a fixed script — adjust for your context. Every box you check needs backing evidence, not just a verbal "yep, checked." Save the completed checklist somewhere versioned and auditable — a `RELEASE-<version>.md` file, or a tracked ticket — so sign-off has a paper trail.

### Automated gates (non-negotiable)

- [ ] **Every CI pipeline is green** — unit, integration, E2E, type checks, linting
- [ ] **Smoke suite passes against staging** — the critical user journeys are verified there
- [ ] **Zero open P0/P1s tied to this release** — check the tracker, filtered by milestone or label
- [ ] **Performance budgets hold** — API latency and bundle size inside thresholds; Lighthouse CI for anything with a frontend (backend/API-only releases can skip Lighthouse — it measures page load, not service health)
- [ ] **Security scan is clean** — no high/critical findings from `npm audit`, Snyk, or Dependabot
- [ ] **API contract tests pass** — nothing public-facing has broken
- [ ] **Visual regression is clean** — no unplanned UI drift
- [ ] **Accessibility checks pass** — axe-core reports no new violations

### Manual gates (confirm before saying go)

- [ ] **Feature flag states reviewed** — write down which flags are on/off for this release and confirm the production state
- [ ] **Alerting is in place** — anything new shipping has matching alerts (errors, latency, business metrics)
- [ ] **Rollback plan exists and has been rehearsed** — a written procedure that's actually been run once on staging, not just drafted
- [ ] **Migrations verified** — forward migration tested; backward migration confirmed too, if the schema change is reversible at all
- [ ] **Third-party dependency changes checked** — new or bumped external packages reviewed for breaking changes
- [ ] **Release notes are ready** — changelog current, a stakeholder-readable summary written
- [ ] **On-call is a named person** — available, and briefed on what's actually shipping
- [ ] **Comms plan is set** — stakeholders know it's happening, support has been briefed
- [ ] **No collision with other teams' releases**
- [ ] **Deploy window makes sense** — not during peak traffic, not right before a weekend, unless continuous deployment makes that moot

### Risk read

- [ ] **Scope is categorized** — small (config tweak, copy change), medium (new feature, refactor), or large (architectural change, migration)
- [ ] **Blast radius is estimated** — if this goes wrong, what share of users notices?
- [ ] **Revert cost is known** — under 5 minutes to revert? Does reverting drag in a data migration?

---

## Designing the Smoke Suite

### Scope: critical paths only

Smoke tests exist to check whether the app is fundamentally broken — nothing more granular.

**A reasonable smoke suite runs 5-8 checks:**

1. **App is up** — homepage returns 200, loads, no console errors
2. **Login works** — valid credentials authenticate, session gets created
3. **The core loop functions** — whatever the product's primary value action is (create a document, submit a form, add to cart, finish checkout)
4. **Data actually comes back** — dashboards populate, search returns hits, product pages render
5. **Payments clear** (where relevant) — a test-credential payment flow completes
6. **APIs respond** — primary endpoints return well-formed responses
7. **Navigation holds up** — deep links, redirects, and menu paths all work
8. **Errors degrade gracefully** — a bad route shows a proper 404, not a crash

### What stays out

- Edge cases — that's regression testing's job
- Pixel-level polish — that's visual regression's job
- Performance thresholds — that's performance testing's job
- Exhaustive form validation — that's unit/integration testing's job

### Keeping it under 5 minutes

- Parallelize wherever the suite allows it
- Set up state via API calls, not the UI (create a test user through an API call, not the signup form)
- Trim non-essential assertions — check that elements exist rather than asserting exact copy
- Reuse a dedicated test account with data already seeded, instead of building it fresh each run
- Wait smart, not long — wait on elements, never `sleep(3000)` or `waitForTimeout`

### Different environments need different suites

**On staging:**
- Run the full 5-8 test suite
- Test payment providers can be used
- Feature flags can be set to their upcoming production configuration
- Migrations can be exercised

**On production:**
- Trim to 3-5 of the staging tests
- Use clearly-labeled synthetic accounts that won't pollute analytics
- Never route real money through it — sandbox mode only, or skip payment checks entirely
- Prioritize: app loads, login works, reads succeed, API responds

**Immediately post-deploy:**
- Fire within 60 seconds of deploy completing
- Same set as the production suite
- Any failure triggers an alert and starts the rollback evaluation

Staging never fully mirrors production — different data scale, different traffic shape, different third-party config, different infrastructure sizing. That gap is the whole reason production and post-deploy smoke checks exist on top of what staging already verified.

---

## Validating a Staged Rollout

### The typical ladder

The percentages below assume an infrastructure-level canary. A flag-based rollout follows the same shape but adds a 25% rung (details further down).

| Stage | Traffic % | Duration | Purpose |
|-------|-----------|----------|---------|
| Canary | 1% | 15-30 min | Catch outright crashes and obvious breakage |
| Early adopters | 10% | 1-2 hours | Check error rate, latency, and business metrics |
| Partial rollout | 25-50% | 2-4 hours | Confirm stability holds at scale |
| Full rollout | 100% | — | Watch for 24 hours after full deploy |

### The checks between each stage

Before letting a stage advance to the next, confirm **every one** of these:

**Errors:**
- 5xx rate no higher than baseline
- Exception count no higher than baseline
- No error types showing up that weren't there before

**Performance:**
- P50/P95 latency within an acceptable range of baseline (relative, not a fixed ceiling)
- Timeout rate hasn't climbed
- DB query times are steady

**Business signals:**
- Conversion rate isn't sliding
- Engagement (page views, actions taken) is steady
- Revenue or transaction volume looks normal, where applicable

**Infrastructure:**
- CPU/memory usage look normal
- Queue depth and message backlog aren't growing
- No disk pressure from new logging

### Automating the promotion decision

Write explicit rules for when a stage auto-promotes. Every gate should combine an error-rate ceiling, a latency ceiling stated **relative to baseline**, a minimum stability window, and — for the later stages — a business-metric guardrail. The full canary → 10% → 50% → 100% ruleset lives in `references/rollout-automation.md`.

### Rolling out via feature flags instead

An alternative to canarying at the infrastructure layer:

1. Ship the new code to 100% of instances with the flag OFF
2. Turn it on for internal users first (dogfood it)
3. Flip it on for 1% of users (the flag-based equivalent of canary)
4. Step it up: 10%, 25%, 50%, 100%
5. Delete the flag once it's been stable at full rollout for a week

**Why you'd want this:** rollback is instant (just flip the flag back), no infra changes needed, and you can target specific user segments.

**Why you might not:** it adds branching complexity to the code, stale flags pile up as debt, and it can't catch problems that live at the infrastructure layer.

#### Picking a flag platform

| Platform | Where it shines | Notes |
|----------|---------|-------|
| **LaunchDarkly** | Large-scale orgs; Guarded Rollouts (automated canary analysis, GA since May 2025); AI Configs for prompt/model rollouts; agent graphs | Bought Highlight.io in 2025, bundling in observability tied to flags |
| **Statsig** | Teams built around experimentation; Switchback experiments (Feb 2026) for marketplace-style two-sided systems; auto-tune | OpenAI acquired it in Sept 2025; still runs independently as of mid-2026, but factor acquisition/roadmap risk into a multi-year commitment |
| **GrowthBook** | OSS-first shops; stale-flag detection via code-reference scanning; SQL-based experimentation | A good fit when self-hosting and avoiding lock-in matter |
| **Unleash** | OSS, GitOps-style flag config, per-environment scoping | Apache 2 licensed; Enterprise tier adds SSO/audit |
| **Flagsmith** | Kill switches treated as first-class; canary alerting; has an OSS tier | Published "what is a kill switch" and "release testing" guides in 2026 |
| **Harness FME** (née Split) | Targeted rollouts wired into deploy pipelines; warehouse-native experimentation plus flag archiving (2026) | Renamed after the Harness acquisition |

Native canary analysis from the vendor (LaunchDarkly's Guarded Rollouts, Statsig's Auto-tune, Flagger) is now widely available — reach for it over a hand-rolled rollout-policy YAML if your platform supports it. Given how much churn this table already shows (Statsig into OpenAI, Split into Harness FME), favor OpenFeature-compatible SDKs — the CNCF spec that Harness FME and others are standardizing on — so the flag layer stays swappable later.

#### Rolling out AI/LLM-backed features

AI features don't follow the standard rollout pattern: prompt versions and model IDs vary independently of the code, and a kill switch stops being optional.

1. Pin both the prompt template version and the model ID somewhere versioned — an AI Configs platform, a custom dataset, or plain feature-flag JSON.
2. Roll the prompt/model pairing out behind a flag: internal users, then 1%, then 10%, and onward.
3. Track eval metrics per cohort — hallucination rate, jailbreak success rate, cost per request — not just the usual error rate.
4. Add a cost guardrail: a circuit breaker that fails the feature open (falls back gracefully) if per-request cost for a model spikes.
5. Build a kill switch: one flag that shuts off the AI path entirely and routes to a deterministic fallback or a "feature unavailable" state, and confirm it works in staging before it ever reaches prod.

For prompt-level eval design, see `ai-system-testing`; for canary metric design generally, see `testing-in-production`.

---

## Rollback: Criteria and Execution

### Triggers that fire automatically

Set these thresholds before the deploy happens — once one fires, the rollback starts without a debate. Every number here is relative to a measured baseline, never an absolute ceiling.

| Metric | Threshold | Action |
|--------|-----------|--------|
| Error rate (5xx) | >2x baseline for 5 min | Auto-rollback |
| P95 latency | >3x baseline for 5 min | Auto-rollback |
| Health check | 3 consecutive failures | Auto-rollback |
| Crash rate (mobile) | >0.5% | Auto-rollback |
| Error budget | >50% burned in 1 hour | Auto-rollback |

### Triggers that need a human

These call for judgment, but the guidelines should still be explicit:

- **Multiple customers report the same problem** — a critical issue surfacing repeatedly
- **Data looks wrong** — evidence of corruption or incorrect records
- **A security hole surfaces** — active exploitation, or a high-severity CVE
- **A monitoring gap is discovered** — you realize a critical metric for the new feature isn't observable
- **On-call says so** — the on-call engineer can always call a rollback, full stop

### How the rollback actually runs

**1. Decide — under 2 minutes**
- Automated trigger, or manual call?
- If manual: does it clear the bar? If yes, act — this isn't the moment to debate it.

**2. Execute — under 5 minutes**
- **Kill switch (fastest option, use it if you have it):** flip the dedicated kill switch for the affected capability. This is not the same as a full code rollback — it disables one feature without a redeploy. Test this switch in staging before every release; an untested kill switch isn't actually a kill switch.
- **Flag-based rollback:** turn off the flag guarding the new code path. Slower than a kill switch when both exist for the same feature (a rollout flag and a kill switch solve different problems).
- **Code rollback:** redeploy the prior artifact/image. Reach for this when the problem isn't cleanly contained behind a single flag.
- **Database rollback:** run the backward migration, if there is one. If the migration can't be reversed, skip this step and deal with the data separately.
- **Cache purge:** flush CDN and app-level caches if the old version would otherwise serve stale or wrong data.

**3. Verify — under 5 minutes**
- Run the production smoke suite
- Confirm error rate is back at baseline
- Confirm the rolled-back version is actually serving

**4. Communicate — under 10 minutes**
- Post to the release channel using the rollback skeleton below
- Update the status page if users were visibly affected
- Loop in support

**5. Investigate — next business day**
- Do the root-cause analysis
- Add a regression test that would have caught this
- Add whatever check was missing to the go/no-go checklist
- Plan the fix and the re-release

#### Rollback announcement skeleton

Post this to the release channel as part of step 4. Full release and rollback templates live in `references/communication-templates.md`.

```
Subject: [Rollback] v{version} — {date} {time}
Status: ROLLED BACK
Reason: {one line — e.g. error rate 4x baseline within 8 min}
Impact: {who was affected, for how long}
Current state: Running previous version v{prev_version}
Next steps:
- Root cause investigation: {owner}
- Fix ETA: {estimate or "investigating"}
```

### When the data can't just roll back

Options for a migration with no clean backward path:

- **Roll forward:** ship a fix on top of the current version instead of reverting
- **Dual-write:** write to both schemas during the migration window, so rollback simply stops writing to the new one
- **Shadow migration:** migrate in the background, validate it, then cut over — rollback just cancels the cutover
- **Point-in-time restore:** restore from backup as a last resort, accepting the data loss since that backup

---

## Verifying the Release Post-Deploy

### First 15 minutes

- [ ] Production smoke suite passes
- [ ] Error rate is at or under the pre-deploy baseline
- [ ] No unfamiliar exception types in the error tracker
- [ ] Health endpoints report healthy
- [ ] A couple of key pages spot-checked by hand

### 15 minutes to 2 hours

- [ ] Synthetic checks confirm every critical path still works
- [ ] Error rate trend is flat or falling, not climbing
- [ ] P50/P95 latency sits in the expected band
- [ ] Support ticket volume hasn't ticked up
- [ ] Business numbers (conversions, revenue, signups) look normal
- [ ] No sign of a memory leak or resource exhaustion trend

### 2 to 24 hours out

- [ ] Overnight batch jobs finished cleanly, if any run
- [ ] No timezone-dependent surprises as other regions come online
- [ ] Email/notification delivery is normal
- [ ] Third-party integrations are behaving
- [ ] No slow creeping performance decline

---

## Anti-Patterns to Watch For

### "It passed on staging"
Staging isn't production — the data volume, traffic shape, third-party config, and infra scale all differ. Passing there is necessary, but it's not proof you're ready.
**Fix:** Layer production smoke tests and a staged rollout on top of what staging already confirmed.

### Having no rollback plan
"We'll deal with it if it breaks" really means dealing with it under pressure, exhausted, while users complain — exactly the conditions that produce more mistakes.
**Fix:** Write the rollback procedure down. Rehearse it every quarter. Time the rehearsal. Make it a checklist that anyone can run, not something only one person remembers.

### Shipping Friday afternoon
Deploy at 4pm Friday, something breaks at 6pm, the team's already gone to dinner, and by Monday it's a full-blown mess.
**Fix:** Ship early in the week and early in the day, while the whole team is around to watch it. If Friday is unavoidable, deploy before noon and add extra monitoring.

### Skipping smoke tests because "CI is green"
CI runs against test data in a test environment. Smoke tests confirm the deployed build actually works against production config, production data, and production infrastructure — a different question entirely.
**Fix:** Smoke tests don't get skipped. If they're slow, speed them up. If they're flaky, fix them. Not optional.

### Batching months of work into one giant release
Six weeks of accumulated changes shipped at once means more failure surface, harder root-causing, higher risk, slower rollback, and a lot more stress.
**Fix:** Ship smaller and more often. If continuous deployment isn't feasible yet, aim for weekly or biweekly releases with changesets small enough to actually reason about.

### No one watches after deploy
The release goes out and the team moves straight to the next thing. An hour later users are hitting errors that nobody's tracking.
**Fix:** Put someone on dashboard duty for the first 30-60 minutes. Wire up alerts with sane thresholds. Run the post-deploy smoke suite.

### Refusing to roll back
"We're almost done fixing it forward" — meanwhile users sit broken for another 45 minutes while the fix gets debugged live.
**Fix:** Roll back, then investigate. A working old version beats a broken new one every time. Pride recovers; user trust takes longer.

### Flags that never get cleaned up
Feature flags are great for safe rollout and terrible when nobody ever removes them. A year in, there are 200 of them, nobody remembers which matter, and their interactions start causing bugs nobody can explain.
**Fix:** The 2026 approach is platform-native stale detection, not a calendar reminder. GrowthBook's stale-flag detection (via code references), LaunchDarkly's archive flow, and Flagsmith's flag-age telemetry all surface flags whose code paths have gone untouched for N weeks. Pair that with a quarterly pass: flags past the threshold get archived, or get a named owner and a documented reason to stay. Calendar reminders get ignored; code-reference scans don't.

### Trusting a canary alert that's actually unreliable
An auto-rollback wired to a metric that's noisy, slow to arrive, or only partially aggregated. It fires at the wrong moment (or fails to fire at the right one), and the team stops trusting it — so when a real incident hits, the alert gets ignored.
**Fix:** Treat the canary alert as a test with its own false-positive and false-negative rate, and actually measure both. Run it in shadow mode first — let it record what it would have decided without actually triggering a rollback — and compare its calls against reality for two weeks. Only promote it to live auto-rollback once the false-positive rate is acceptable. Reference: https://www.flagsmith.com/blog/when-canary-alerts-go-wrong

### Running standard A/B tests on two-sided systems
Marketplaces, ride-share, ad auctions — anywhere the treatment group's behavior leaks into the control group through shared state — break standard A/B testing. A 50/50 traffic split doesn't isolate anything when both sides are reacting to the same distorted market.
**Fix:** Switch to a switchback design instead — flip the entire system between control and treatment over short windows (minutes to hours). Statsig's Switchback experiments (Feb 2026) automate the common cases. Don't gate a release on a corrupted A/B result — rerun it with a design that actually fits. Reference: https://www.statsig.com/updates

---

## Post-Deploy Verification Commands

Run these right after the deploy finishes, cheapest check first. `references/rollout-automation.md` has the expanded error-tracker queries.

```bash
# Health endpoint returns healthy
curl -s https://your-app.com/health | jq .

# Response time + status in one shot
curl -o /dev/null -s -w "HTTP %{http_code} in %{time_total}s\n" https://your-app.com

# New errors since deploy (Sentry CLI) — should be empty
sentry-cli issues list --project your-project --query "firstSeen:>15m"

# Datadog: compare 5xx count for the service before vs after deploy — must not increase
```

Passing looks like: health reports `healthy`, status is `200` within your latency budget, the Sentry query comes back empty, and the post-deploy 5xx count doesn't exceed the pre-deploy baseline.

---

## Definition of Done

- Go/no-go checklist filled out with evidence per item, saved as a versioned artifact (`RELEASE-<version>.md` or a tracked ticket), and signed off by a named approver with a timestamp
- Smoke suite executed against the release candidate on staging with a clean pass (exit code 0)
- Rollback thresholds written down as specific, baseline-relative numbers, and the rollback procedure has actually been rehearsed on staging at least once
- Staged rollout plan set, with traffic percentages, per-stage promotion criteria, and guardrail metrics for each rung
- Post-deploy verification commands run clean (health 200, no new Sentry issues, 5xx count at or under baseline)

## Reference Files (in `references/`)

- **rollout-automation.md** — the baseline-relative canary → 10% → 50% → 100% promotion rules, plus the verification command snippets.
- **communication-templates.md** — pull this up when drafting a release or rollback announcement: ready-to-fill release and rollback templates.

## Related Skills

- `testing-in-production` — heavy overlap with progressive rollout. Go there for the safe-release *mechanics* (flags, canary, dark launch, guardrail metrics) used while shipping; this skill covers the go/no-go *decision* that gates whether shipping happens at all.
- `synthetic-monitoring` — continuous probes that run long after release. This skill's scope ends at the one-shot post-deploy verification window; synthetic-monitoring owns ongoing SLA checking.
- `qa-metrics` — where the DORA numbers (change failure rate, MTTR) and error/pass-rate data cited in go/no-go decisions and rollback thresholds actually come from.
- `ci-cd-integration` — builds the pipeline that has to be green before this skill's gates even apply.
- `ai-system-testing` — for AI/LLM feature releases: prompt-version eval tests and kill-switch design, referenced from the rollout section above.
- `compliance-testing` — EU AI Act, EAA, and GDPR requirements that can legally block a release ahead of the go/no-go call.
- `playwright-automation` — usually where smoke tests actually live in code; go there for test structure, come here for which journeys count as smoke-critical.
- `quality-postmortem` — when a release goes sideways, its postmortem is what feeds a missing check back into this checklist.
