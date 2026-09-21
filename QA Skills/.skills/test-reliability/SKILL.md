---
name: test-reliability
description: >-
  A runtime, per-test healing toolkit backed by evidence: multi-attribute
  selector healing, environment-aware diagnosis, flake classification,
  quarantine handling, and confidence-scored auto-repair. It extends past
  plain locator fallback chains into action-level healing, data healing, and
  repair workflows you can actually inspect.
  Use when: "flaky test," "test stability," "self-healing locator," "broken
  locator recovery," "unreliable test," "quarantine flaky test."
  Not for: bulk regenerating selectors after a planned UI refactor — use
  selector-drift-recovery instead (this skill heals ONE test at runtime, while
  that one rewrites many tests offline). Not for: classifying or clustering CI
  failures into bug reports — use ai-bug-triage for that.
  Related: playwright-automation, selector-drift-recovery, ci-cd-integration, qa-metrics, ai-bug-triage.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: ai-qa
---

<objective>
Keep retrying a flaky test and it will eventually fail 3-for-3 during the release you cared about most; auto-repair it silently and it may end up asserting against a completely different element than before. This skill is about building a suite the team can actually rely on: locators that resist churn, flakes sorted by what's really causing them, healing that knows the difference between an environment hiccup and a real bug, data healing, and a repair pipeline where every automated change comes with a confidence score and a paper trail a human can check.
</objective>

## Quick Navigation

| Situation | Go to |
|-----------|-------|
| A test flakes in CI and you don't know why yet | Sorting Flakes by Root Cause → decision tree |
| A locator broke and you need a sturdier replacement | Building Sturdier Locators |
| An action fails and you suspect a slow backend rather than a UI bug | Accounting for the Environment |
| Mid-test 401/404/429s traced back to stale data | Healing Stale Test Data |
| You want auto-repair, but gated behind human review | Observable Repair Workflow |
| You need to isolate a flaky test without blocking CI | Handling Quarantine |
| You want a step-by-step walkthrough for one flaky test | `references/flaky-test-runbook.md` |

## Questions Worth Asking Up Front

Look in `.agents/qa-project-context.md` before anything else — it usually already documents known flaky spots, the team's selector strategy, and the CI environment. Skip whatever it already answers.

- **What's the current flaky-test rate?** Pull CI failure numbers from the last 30 days. Under 2% is fine, 2-5% deserves attention, and past 5% is actively costing you team trust.
- **Where does the pain actually live?** Is it locators breaking, timing, test data, or the environment? If you can't tell yet, instrument first — see the classification section below.
- **What selector strategy is already in place?** Consistent `data-testid` usage, a mix of CSS and role-based locators, or no real strategy at all? This tells you where the stability-score baseline sits.
- **How are flaky tests handled today?** Retried and hoped for the best, skipped and forgotten, or run through an actual process? This determines how much new process is worth adding.
- **What does the CI environment look like?** Same machine every run, or different runners with varying resources? This shapes whether you're diagnosing the test or the infrastructure.
- **How is test data managed?** A shared database, per-test fixtures, factory-seeded data, or external services? This determines whether data healing is even applicable.

## Guiding Principles

1. **Prevention beats cure, every time.** A resilient test up front costs roughly 1x. Debugging a flaky one afterward costs about 10x. Losing the team's trust in the suite costs 100x.

2. **Nothing heals silently.** Every automated repair needs to leave a trail: what broke, what was attempted, what actually worked, and how confident the system was. A fix nobody can see is just as damaging to trust as an unexplained failure.

3. **Diagnose before you touch anything.** A timing bug and a data-dependency bug need entirely different treatments. Guessing wrong wastes time and can actively make the test worse.

4. **A flaky test is a bug, full stop.** It's not something to shrug off. Either the test itself is buggy (fix the test), the app has a real defect (fix the app), or the environment is the problem (fix the environment).

5. **Reliability is a number, not a vibe.** Track flaky rate, mean time to heal, how long tests sit in quarantine, and selector stability. Things that get measured are the things that get fixed.

6. **Self-healing has levels — climb them in order.** Level 1 is resilient locators, Level 2 adds fallback strategies, Level 3 brings in environment-aware healing, and Level 4 is confidence-scored auto-repair. Don't reach for Level 4 before Level 1 is solid.

## Building Sturdier Locators

### Multi-Attribute Selectors Instead of Fallback Chains

Relying on one locator strategy means one point of failure. Rather than chaining fallbacks, a multi-attribute selector checks several signals at once for the same lookup — that combination itself is what makes it resilient.

**The core idea:** don't do "try A, then B, then C." Do "find the element that matches A and B and C, but tolerate one of those signals being missing."

```typescript
// Multi-attribute locator: tries combinations from most specific to least
const submitBtn = await multiAttributeLocator(page, {
  testId: 'checkout-submit',              // most stable signal
  role: 'button',                          // semantic signal
  name: /place order/i,                    // accessible name
  nearText: 'Order Summary',              // visual context
});
// Internally: tries testId+role+name first, then testId alone, then role+name,
// then text, then nearText+role. Returns first visible match.
// Unlike fallback chains, it combines signals for higher confidence.
```

### Finding Elements via DOM Neighborhood

Sometimes a broken locator just means the element's attributes changed, not that it's gone. Its surrounding markup can still point you to it:

1. **Container, then tag and type:** locate the wrapping element by testId, then search inside it by tag and type.
2. **Adjacent label text:** find the sibling label, then grab the input or button next to it.
3. **Nearby visible text:** find text close to where the target should be, then look for the right element type in that same parent.

Treat these as candidate repairs to be scored by the confidence system further down — they are not something you'd want firing automatically at runtime as a blind fallback.

### Scoring Selectors for Stability

Give every selector a score from 0 to 5 so you know what to refactor first.

| Score | Strategy | Survives |
|-------|----------|----------|
| 5 | `getByTestId('submit-order')` | CSS, text, and structural changes |
| 4 | `getByRole('button', { name: 'Submit' })` | CSS and structural changes |
| 3 | `getByLabel('Email')` | CSS changes; breaks on label rewording |
| 2 | `getByText('Submit Order')` | Breaks on any copy change |
| 1 | `locator('.btn-primary.submit')` | Breaks on CSS or structural change |
| 0 | `locator('//div[3]/button[1]')` | Breaks on any DOM change |

**Aim for a suite-wide average of 3.5 or higher.** Audit this monthly, and fix score-0 and score-1 selectors first. Write one score per locator out to `selector-stability.md` (or a CI step) and report the suite average, so the 3.5 target is something you can point to, not just claim.

## Sorting Flakes by Root Cause

Every flaky test traces back to one of a handful of root causes, and getting the category right is what determines the correct fix.

### The Root-Cause Categories

| Category | Signal | Root Cause | Fix Direction |
|----------|--------|------------|---------------|
| **Timing** | Timeout errors, passes on retry, worse in CI | Race condition, animation, async operation | Wait for condition, not time |
| **Data dependency** | Fails with other tests, passes alone | Shared state, missing cleanup | Isolate per-test, fixture cleanup |
| **Environment** | Fails on specific runner, correlates with load | Resource contention, network latency | Mock externals, increase resources |
| **Order dependency** | Fails with --shard or fullyParallel | Depends on another test's side effect | Self-contained setup |
| **Time sensitivity** | Fails at specific times (midnight, month-end) | Uses real clock, date boundary | Mock clock, relative comparisons |
| **Visual rendering** | Screenshot diff flickers, subpixel differences | Font rendering, antialiasing, animation frame | Increase threshold, mask dynamic regions |
| **External service** | Correlates with third-party status | Real HTTP calls in tests | Mock external APIs |

### A Decision Tree to Classify Fast

```
Test is flaky
│
├── Does it pass when run alone?
│   ├── YES → ORDER DEPENDENCY or DATA DEPENDENCY
│   │   ├── Does another test create/modify data it needs? → ORDER DEPENDENCY
│   │   └── Does it share a database/file/cache? → DATA DEPENDENCY
│   │
│   └── NO → Not order/data dependent. Continue below.
│
├── Does it fail more often in CI than locally?
│   ├── YES → TIMING or ENVIRONMENT
│   │   ├── Timeout errors? → TIMING (CI is slower)
│   │   ├── Connection errors? → ENVIRONMENT (network latency / service)
│   │   └── Resource errors (OOM, disk)? → ENVIRONMENT (resource contention)
│   │
│   └── NO → Same rate locally and CI. Continue below.
│
├── Does it fail at specific times?
│   ├── YES → TIME SENSITIVITY
│   │   ├── Near midnight? → Date boundary issue
│   │   ├── Near month/year end? → Calendar calculation
│   │   └── Specific hour? → Timezone issue
│   │
│   └── NO → Continue below.
│
├── Does it involve screenshots or visual comparison?
│   ├── YES → VISUAL RENDERING
│   │
│   └── NO → Continue below.
│
├── Does it call external HTTP APIs?
│   ├── YES → EXTERNAL SERVICE
│   │
│   └── NO → TIMING (most likely — default classification)
│       └── Investigate: what async operation is not being awaited?
```

Full code-level fixes for each of these categories live in `references/flaky-test-runbook.md` (Step 4).

## Accounting for the Environment

Not every failing test points to a test problem — sometimes the environment itself is at fault. This section is about telling the two apart and adapting accordingly.

### Slow Backend or Genuine UI Failure?

Before blaming the test when an action fails, check whether the backend is actually healthy:

1. **Action fails** → hit `/api/health`.
2. **Backend unhealthy (5xx or timeout)** → retry with exponential backoff and diagnose it as `backend_down`. This isn't a UI bug.
3. **Backend healthy (2xx)** → this is a genuine UI/test failure. Don't retry it.

Return a structured diagnosis: `{ success: boolean; diagnosis: 'backend_down' | 'ui_failure' | 'backend_slow_recovered' }`. This feeds directly into flake classification — a backend issue is an environment issue, not a test bug.

### Spotting Resource Contention

Before you write off a CI failure as a real bug, rule out resource contention first:

- **Browser health:** load `about:blank`. Taking more than 2s (baseline under 500ms) means the runner is overloaded.
- **API health:** hit `/api/health`. Taking more than 5s (baseline under 1s) means the backend is under load.
- **Diagnosis:** if either check comes back slow, classify the failure as an environment issue and annotate it accordingly. Don't let resource-contention failures count toward your flaky-rate metric.

## Healing Stale Test Data

Test data has a way of expiring, getting cleaned up, or simply going invalid. Data healing is about catching that and regenerating what's needed.

### Recognizable Failure Patterns

| Pattern | Signal | Fix |
|---------|--------|-----|
| Expired auth token | 401 response during test | Regenerate token in fixture |
| Deleted test record | 404 when accessing seeded data | Re-seed before test |
| Uniqueness violation | 409 or constraint error | Generate unique identifiers per run |
| Stale cache | Wrong data returned | Clear cache in setup |
| Exceeded quota | 429 or rate limit error | Reset quotas or use dedicated test account |

### A Fixture That Heals Itself

Build fixtures that check whether their data is still good and regenerate it when it isn't.

```typescript
// Pattern: verify → heal → use → cleanup
testUser: async ({ request }, use, testInfo) => {
  // 1. Try to find existing test user by deterministic email
  // 2. Verify auth token is still valid (GET /api/me)
  // 3. If token expired → refresh it (POST /refresh-token), mark as healed
  // 4. If user missing → create new one, mark as healed
  // 5. If healed → annotate testInfo for observability
  // 6. use(user) → run the test
  // 7. Cleanup: delete test user (guaranteed by fixture, even on failure)
}
```

**A few rules worth keeping:**
- Bake `testInfo.testId` into emails or identifiers so each test gets a unique record.
- When healing kicks in, record it via `testInfo.annotations` so it's visible later.
- Clean up inside the fixture's post-use block, not in `afterEach` — fixtures guarantee that cleanup runs even after a failure.

## Observable Repair Workflow

**The non-negotiable rule:** healing has to be visible and reviewable. Every repair moves through this pipeline:

```
Failure Detected
  │
  ▼
Candidate Repair Generated
  │
  ▼
Confidence Score Computed (0.0 - 1.0)
  │
  ▼
Evidence Diff Produced (what changed, what was tried)
  │
  ▼
Approval Policy Applied
  │ ├── Score >= 0.9   → Auto-apply, log for batch review
  │ ├── Score 0.7-0.89 → Apply in quarantine, flag for individual review
  │ ├── Score 0.5-0.69 → Do NOT apply, open PR with evidence for review
  │ └── Score < 0.5    → Discard, manual investigation required
  │
  ▼
Intent Fidelity Check (does repaired test still test the same thing?)
  │
  ▼
Rollback if intent fidelity drops
```

### Confidence Scoring

Score each candidate repair across six weighted dimensions that sum to a value between 0.0 and 1.0:

| Dimension | Weight | Scoring |
|-----------|--------|---------|
| Match specificity | 0.30 | testId=1.0, role=0.9, text=0.7, context=0.5, CSS=0.3 |
| Element visible | 0.15 | 1.0 if visible, 0.0 if not |
| Same parent container | 0.15 | 1.0 if same container, 0.0 if different |
| Same element type | 0.15 | 1.0 if same tag+role, 0.0 if different |
| Text similarity | 0.15 | 0.0-1.0 (Levenshtein ratio of accessible name) |
| Attribute overlap | 0.10 | 0.0-1.0 (Jaccard of shared attributes) |

**Score thresholds** (half-open bands — a score of exactly 0.9 falls into the auto-apply tier only):
- **>= 0.9** — Auto-apply, log for batch review.
- **0.7-0.89** — Apply in quarantine, flag for individual review.
- **0.5-0.69** — Do not apply; open a PR with evidence for review.
- **< 0.5** — Discard, manual investigation required.

The same four bands show up three times: in the approval-policy diagram above, in the thresholds just listed, and again in the runbook's Score Interpretation section (`references/flaky-test-runbook.md`). If you ever adjust the thresholds, update all three together.

### What Counts as Evidence

A repair record should capture: the test file, the test name, the failure type, the original locator, each candidate replacement (with its confidence score, a string describing the evidence, and whether intent was preserved), which candidate got chosen, a timestamp, which approval path it took, what would trigger a rollback, **and a `screencast.webm` recording of the run** (Playwright 1.59+'s `page.screencast` with `showActions` annotations — think of it as the video receipt for an agentic fix). Skip the screencast and a Level-3/4 healed test is asking a reviewer to just trust a JSON blob; include it and both the diff and the actual runtime behavior are inspectable.

### Buy vs. Build

Reach for a vendor to cover Levels 3-4 when you don't want to be the one owning a confidence-scored healer. Build it yourself when you need on-prem or air-gapped deployment, a clear audit trail of AI prompts, or quarantine logic that your issue tracker simply can't represent. Once a hosted tool is already fingerprinting, clustering, and auto-quarantining for you, building your own stops paying off.

- For **Selenium / Selenide / Robot Framework** suites, **Healenium** is still the go-to dedicated self-healing layer (now available on AWS Marketplace).
- For **agent-driven self-healing in Playwright**, **Playwright MCP** is the standard route — it gives an agent live browser control to hunt down replacement locators when CLI-plus-skills isn't enough on its own.
- Hosted platforms offering this workflow out of the box: **Trunk Flaky Tests** (auto-quarantine plus AI failure clustering; its 2026 Quarantined Tests API returns the live quarantine list programmatically — the same hygiene this skill has you build by hand), **CloudBees Smart Tests** (formerly Launchable — an agent digging through old docs might still surface the old name), and **Datadog Test Optimization** (renamed from "Datadog Test Visibility" back in December 2024). All three combine fingerprinting, clustering, and auto-quarantine — covering roughly what Levels 3-4 do here.

### Verifying Intent Fidelity

Once a repair is applied, confirm the test is still exercising the same user intent it always was:

- **Element type changed** (e.g. `button` → `a`) — intent was NOT preserved; roll it back.
- **ARIA role changed** (e.g. `button` → `link`) — intent was NOT preserved; roll it back.
- **Form action changed** (points at a different endpoint) — intent was NOT preserved; roll it back.
- **Same tag, role, and form action** — intent preserved; keep the repair.

Any repair that changes WHAT the test verifies, rather than just HOW it locates elements, needs to be rolled back.

## Handling Quarantine

Quarantine lets a flaky test keep running without being able to block CI. The full config and CI wiring are in `references/flaky-test-runbook.md` (Step 6) — here's the short version:

```typescript
// Tag the flaky test
test('intermittent WebSocket reconnect', {
  tag: ['@quarantine'],
  annotation: {
    type: 'quarantine',
    description: 'Flaky since 2026-03-15. Race condition in WebSocket handler. Ticket: BUG-1234.',
  },
}, async ({ page }) => { /* ... */ });
```

```typescript
// playwright.config.ts — separate projects
projects: [
  { name: 'stable', testMatch: /.*\.spec\.ts/, grep: /^(?!.*@quarantine)/ },  // exclude quarantine
  { name: 'quarantine', grep: /@quarantine/, retries: 3 },
],
```

In CI, run `--project=stable` as a blocking step, and run `--project=quarantine` with `continue-on-error: true` so quarantined tests never hold up the pipeline.

### The Lifecycle of a Quarantined Test

```
1. DETECT    — Test identified as flaky (CI reporter or manual triage)
2. TAG       — Add @quarantine annotation with ticket link and date
3. ISOLATE   — Quarantine project runs separately, does not block
4. DIAGNOSE  — Follow the flaky test runbook (references/flaky-test-runbook.md)
5. FIX       — Apply the fix pattern for the classified category
6. VERIFY    — Run 50x with --repeat-each, zero failures required
7. RELEASE   — Remove @quarantine tag, add annotation documenting the fix
```

### Keeping Quarantine Clean

- **14 days is the ceiling.** Past that, either fix it or delete it — quarantine that never ends is just rot with a label on it.
- **No entry without a ticket link.** Anonymous quarantines aren't allowed.
- **Review it weekly.** Check the quarantine list every sprint and escalate anything getting old.
- **Watch the size.** Once more than 5% of the suite is quarantined, that's a systemic problem needing a process fix, not more individual test fixes.

## Patterns to Avoid

### 1. Swapping Selectors Silently
Replacing a broken selector with zero logging, review, or confidence scoring. The "fixed" test might now be checking a completely different element. **Every repair needs to leave evidence behind.**

### 2. Treating Retries as a Fix
A retry is a detection mechanism, not a cure. A test that only passes on its second or third attempt will eventually fail all three during the release that matters most.

### 3. Permanently Disabling Flaky Tests
`test.skip('flaky, will fix later')` — "later" is a myth. Either quarantine it with a tracked ticket, or delete it outright. A skipped test with no ticket attached is just dead code.

### 4. Applying One Fix to Every Flake
Timing problems and data-dependency problems need completely different solutions. Slapping `waitForTimeout(5000)` onto a data-dependency issue just makes the test slower without making it any less flaky.

### 5. Reaching for waitForTimeout

```typescript
// NEVER the right fix
await page.waitForTimeout(5000);

// Wait for the actual condition
await expect(page.getByRole('table')).toBeVisible();
await page.waitForResponse(resp => resp.url().includes('/api/data') && resp.status() === 200);
```

### 6. Healing With No Observability
Auto-repair that produces no logs, no evidence, and no confidence score. You can't improve what you can't measure, and you can't trust what you can't review.

### 7. Building Healing Infrastructure Too Early
Standing up a whole self-healing framework before you've even adopted basic resilient-locator habits. Start with multi-attribute selectors and real wait conditions. Only add healing infrastructure once the data shows you where breakage is actually concentrated.

### 8. Letting Quarantine Run Indefinitely
Tests that sit in quarantine for months. Quarantine is meant to be temporary, not a permanent home — enforce the 14-day cap.

## Common Failure Modes

| Symptom | Likely cause | Fix or check |
|---------|--------------|--------------|
| Backend health check itself flaps → false `backend_down` diagnosis | Health endpoint is itself flaky/slow | Track the health endpoint's own p99 separately; don't gate diagnosis on a single probe |
| Artifact storage balloons after enabling repair video | `page.screencast` recording on every run, not just repairs | Record only on the repair path, not the happy path |
| Auto-repair accuracy drops below 80% | Confidence threshold too low, or intent-fidelity check skipped | Raise the auto-apply floor; never skip the intent check |
| Quarantine project blocks the pipeline | Missing `continue-on-error` on the quarantine CI step | Add it; the quarantine project must never block merges |

## Verifying Your Work

- Reproduce the flake first: `npx playwright test <spec> --repeat-each=20 --workers=4 --trace=on` — it needs to fail at least once before you trust a fix for it.
- After fixing, prove it's stable: `npx playwright test <spec> --repeat-each=50 --workers=4` — require 50/50 passes, including under CI conditions.
- Check that quarantine routing works: `npx playwright test --project=stable` should exclude `@quarantine` tests, and `--project=quarantine` should run only them.
- Confirm the selector audit actually emits numbers: the stability report should list a per-locator score and a suite average.

## Definition of Done

- Every flaky test has been identified and sorted into a root-cause category (timing, data dependency, environment, etc.).
- Every flaky test is either quarantined or fixed — none are silently left on retry without a documented plan and a ticket.
- `selector-stability.md` (or the CI report) lists a per-locator stability score and a suite average of 3.5 or higher.
- The flaky-test-rate metric (percentage of tests passing only on retry) is published to the CI dashboard where the team can see it.
- Every quarantine entry carries a ticket reference and an expiry date no more than 14 days out.

## Related Skills

- **selector-drift-recovery** — for bulk-regenerating many selectors offline after a planned UI refactor; this skill instead heals one test at a time, at runtime.
- **playwright-automation** — the underlying Playwright setup, Page Object Model, fixtures, and CI integration these patterns build on top of.
- **ci-cd-integration** — pipeline configuration, parallel execution, and the quarantine job wiring referenced above.
- **qa-metrics** — for tracking flaky rate, mean-time-to-heal, quarantine size, and selector stability over time.
- **ai-bug-triage** — hand off to this when flake investigation turns up a genuine app bug that needs to be classified and reported.
