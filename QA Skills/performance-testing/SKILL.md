---
name: performance-testing
description: >-
  Test application performance with k6 load/stress/soak/spike scripts and k6 scenarios,
  Lighthouse CI for Web Vitals, and performance budgets as CI gates. Covers load profiles,
  custom metrics, bottleneck identification, and Core Web Vitals (LCP, INP, CLS).
  Use when: "performance test," "load test," "stress test," "soak test," "spike test,"
  "k6," "k6 scenarios," "Lighthouse," "Web Vitals," "Core Web Vitals," "performance budget."
  Not for: scheduled production probes — use synthetic-monitoring; pixel-diff regressions —
  use visual-testing; designing tests from prod telemetry — use observability-driven-testing.
  Related: ci-cd-integration, qa-metrics, release-readiness.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: automation
---

<objective>
Performance work should be judged by numbers wired into the build pipeline, not by a
gut feeling that things seem snappy. This skill spans two territories: **load testing**,
which asks whether the backend holds up under traffic, and **web performance**, which
asks whether the page feels fast once it reaches a real browser. Writing down "LCP came
in at 3.2s" is just an observation; failing the pipeline at 2.5s turns that observation
into an enforceable standard.
</objective>

## Quick Route

| You need to... | Go to |
|----------------|-------|
| Test backend capacity / throughput / latency under traffic | **k6 Load Testing** → `references/recipes.md` |
| Pick a load shape (constant / ramp / spike / soak) | **Load Profiles** table |
| Measure frontend speed for real users (LCP, INP, CLS) | **Web Performance** + **Core Web Vitals** |
| Gate page perf in CI | **Lighthouse CI** (gate TBT, not INP — see below) |
| A budget is breached and you must find why | **Bottleneck Identification** |
| Migrate an existing suite from k6 v1 → v2 | **k6 v2 Migration** callout |

## Discovery Questions

Look for `.agents/qa-project-context.md` before asking anything below — if answers already
live there, reuse them instead of re-asking.

### Scope of measurement
- **Is the concern user-facing speed or server capacity?** Web performance tracks what a visitor experiences (Core Web Vitals, load time); load testing tracks what the infrastructure can sustain (RPS, latency as concurrency rises). Most real projects need coverage on both fronts.
- **Which journeys actually matter for performance?** Load-testing every route is wasted effort — narrow in on flows that see heavy traffic, drive revenue, or have tight latency requirements.
- **Do performance budgets already exist?** If targets are already set, use them. If not, this skill is how you derive them — but a baseline measurement comes first, before any number gets written down as a target.

### Where things stand today
- **What does the current baseline look like?** Setting a target before you've measured anything is guessing. Measure, then decide.
- **What has performance broken in the past?** Pages that drove users away, endpoints that timed out under load, queries that stalled the database — these are your starting map of where to look.
- **Is there existing observability?** APM tooling (Datadog, New Relic), real-user monitoring, or synthetic checks all supply field data useful for shaping a realistic test.

### Environment constraints
- **Which environment will absorb the load?** Staging or a purpose-built load environment — never production without sign-off from operations.
- **What does real traffic look like?** Flat and steady, daily peaks, seasonal surges (think Black Friday), or bursty and event-driven — the answer determines which load profile applies.
- **Anything in the path that will skew results?** Rate limiters, WAF rules, and auto-scalers all distort what a load test reports, and the test design needs to account for them.

## Core Principles

### 1. Profile before you touch anything
Gut instinct about what's slow is frequently wrong, and engineers waste time optimizing code that was never the bottleneck. Measure first, pinpoint the actual culprit, and only then start optimizing. A verified 50ms improvement in the true bottleneck outperforms a guessed 500ms improvement somewhere irrelevant.

### 2. A budget nobody enforces isn't a budget
Write a target in a wiki page and it will be ignored within a sprint or two. Turn budgets into k6 thresholds and Lighthouse assertions inside the pipeline, so a regression breaks the build automatically rather than surfacing in a quarterly retro.

### 3. Modeling real traffic beats chasing the breaking point
Pushing 10x traffic through a stress test reveals where things snap. Running at roughly 1.5x expected volume tells you whether users tomorrow will have a decent experience. Both tests earn their keep, but the realistic one runs far more often and catches regressions sooner.

### 4. Users feel Core Web Vitals, not server logs
Latency and throughput numbers matter on the backend, but the browser is where users actually perceive speed. LCP, INP, and CLS capture that perception directly. An API that responds instantly but renders a sluggish page is still, from the user's chair, slow.

### 5. Treat performance as a first-class feature
It won't maintain itself. It needs its own test infrastructure, budgets, and ongoing monitoring — the same rigor applied to functional correctness. A performance regression deserves the same urgency as a broken feature.

## k6 Load Testing

k6 is an open-source, JavaScript/TypeScript-scripted load testing tool that runs from the
command line and slots into CI pipelines. **Current stable release: k6 v2.0.0** (shipped
final in 2026-05). v2 introduced breaking changes relative to v1 — covered in the
migration notes below.

Three pieces make up a load test: a **load profile** (the `stages`/`scenarios` shape),
**checks** (assertions run per request), and **thresholds** (the pass/fail budget that
controls the exit code). Pull the base URL from `__ENV` so one script runs unmodified
against local, staging, and CI targets.

Full working examples — the complete basic load test, custom metrics, and scenario
setups — live in `references/recipes.md`. Here's a minimal threshold block on its own:

```javascript
export const options = {
  stages: [
    { duration: '1m', target: 20 },
    { duration: '3m', target: 20 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],
  },
};
```

### Load Profiles

| Profile | Question | Shape | Duration |
|---------|----------|-------|----------|
| **Constant** | Can the system handle normal traffic? | `vus: 50, duration: '10m'` | 10 min |
| **Ramp-up (stress)** | At what point does it degrade? | 50 → 100 → 200 → 400 → 800 → 0 | 12 min |
| **Spike** | Does it recover from a sudden surge? | 50 → spike 500 → sustain → drop 50 → recover | 6 min |
| **Soak** | Does it leak resources over time? | Ramp to 100, sustain 4h, ramp down | 4+ hours |

A spike test only counts as finished once "does it recover?" is turned into a real
**assertion**, not left as a code comment. Tag the window right after the spike (say,
`phase:recovery`) and attach a threshold scoped to it, so the run fails outright if p95
stays elevated. The recovery-detection pattern is in `references/recipes.md`.

### Custom Metrics and Scenarios

k6 ships four metric kinds: `Counter` (running total), `Rate` (share of true/non-zero
values, between 0 and 1), `Trend` (a distribution — p50/p95/p99), and `Gauge` (the most
recent value observed). Attach `{ tags: { name: 'endpoint' } }` to requests so metrics
can be sliced by endpoint, scenario, or flow.

**Scenarios** let several user flows run at once, each with its own executor and its own
scoped thresholds (e.g. `'http_req_duration{scenario:checkout}': ['p(95)<500']`). They're
the tool for modeling a realistic traffic mix — say, browsing plus checkout plus
API-heavy calls, all concurrently. Complete examples of both custom metrics and
scenarios are in `references/recipes.md`.

### k6 CI Integration

Install k6 through the official **`grafana/setup-k6-action@v1`** rather than assembling
a manual apt/gpg-keyserver sequence (fragile, decays over time, and pins nothing). A
breached threshold makes k6 exit non-zero on its own, so the CI job fails without any
extra glue code. The complete GitHub Actions pipeline (checkout → set up k6 → run →
upload artifact) is in `references/recipes.md`.

> **k6 v1 → v2 migration (v2.0.0 final, 2026-05):**
> - `k6/experimental/websockets` → `k6/websockets` (drop the `experimental/` prefix; stable now)
> - `k6/experimental/redis` → **`k6/x/redis`** — NOT removed. The import auto-resolves the
>   `xk6-redis` extension (auto-extension-resolution is on by default; JS usage unchanged).
>   Do not hand-roll a Redis client.
> - `externally-controlled` executor removed
> - `options.ext.loadimpact` removed → use `options.cloud` (Grafana Cloud k6, formerly k6 Cloud / Load Impact)
> - CLI: `--no-summary` → **`--summary-mode=disabled`**; `--upload-only` → `k6 cloud upload script.js`;
>   `k6 login`/`pause`/`resume`/`scale`/`status` removed (use `k6 cloud login`, etc.); positional `k6 cloud script.js` removed
> - Exit code **97** is new: a non-threshold cloud-side abort. Wire it into CI handling.
> Reference: https://grafana.com/docs/k6/latest/get-started/migrating-to-v2/

## Web Performance

### Lighthouse CI

Lighthouse CI (`@lhci/cli`) drives automated Google Lighthouse audits and enforces
budgets through `lighthouserc.js` assertion rules. Currently: `@lhci/cli` 0.15.x running
on the Lighthouse 12.6 engine. The project sits in maintenance mode (its last release was
roughly a year back) and hasn't yet picked up Lighthouse 13 (which needs Node 22.19+);
it's still the standard way to gate Lighthouse in CI, but keep an eye on upstream before
betting a brand-new project on it.

A complete `lighthouserc.js` (with LCP/CLS/TBT/perf-score assertions) plus the `lhci
autorun` CI step both live in `references/recipes.md`.

### INP only exists in the field — gate TBT in the lab instead

This is the point people get wrong most often in web performance work, so it's worth
being exact about it:

- **INP (Interaction to Next Paint) can only be measured in the field.** A Lighthouse lab
  run loads a page without any user interacting with it, so there's **nothing for it to
  score for INP**. Putting `interaction-to-next-paint` in a standard `lhci autorun`
  assertion gates a value Lighthouse never actually produces.
- **In lab conditions, gate Total Blocking Time (TBT) instead**, as a stand-in: assert
  `'total-blocking-time': ['error', { maxNumericValue: 200 }]`. TBT tracks with INP
  reasonably well but isn't the same thing — a page can post 0ms TBT and still fail INP
  in the field.
- **Pull actual INP numbers from the field** — Chrome UX Report (CrUX) or your RUM
  platform. That's the figure real users experience, and the one search ranking cares
  about.
- **If you genuinely need to measure scripted-interaction latency**, reach for
  Lighthouse's user-flow / timespan mode with scripted clicks, or `k6/browser` paired
  with a `PerformanceObserver` watching `event` entries. Either way, that's a scripted
  lab approximation — not field INP.

> **FID is retired:** it was deprecated and dropped from `web-vitals` v5+; INP took its
> place as a Core Web Vital in March 2024. Don't assert on FID in anything new.

### Measuring CWV in Playwright

To get a per-page lab reading inside an existing Playwright suite, call `page.evaluate`
with a `PerformanceObserver` to grab LCP and CLS (both observe reliably at page load),
then assert against your thresholds. The full test is in `references/recipes.md`. For
capturing CWV under simulated load, see the `k6/browser` recipe in that same file.

## Core Web Vitals

The three metrics Google relies on to describe how fast a page feels to users.

| Metric | Measures | Good | Needs Improvement | Poor |
|--------|----------|------|-------------------|------|
| **LCP** (Largest Contentful Paint) | Loading — when the largest element renders | ≤ 2.5s | 2.5s–4.0s | > 4.0s |
| **INP** (Interaction to Next Paint) | Responsiveness — interaction → next paint (field-only) | ≤ 200ms | 200ms–500ms | > 500ms |
| **CLS** (Cumulative Layout Shift) | Visual stability — unexpected layout movement | ≤ 0.1 | 0.1–0.25 | > 0.25 |

**Typical fixes:**
- **LCP** — a slow origin server (add caching/CDN, or SSR/SSG the LCP content), render-blocking CSS/JS (defer non-critical scripts, inline critical CSS), a slow-loading image (switch to WebP/AVIF, `preload` the LCP image).
- **INP** — long-running JS tasks (`scheduler.yield()`, `requestIdleCallback`), expensive event handlers (debounce/throttle, offload to Web Workers), layout thrashing (batch DOM reads and writes via `requestAnimationFrame`).
- **CLS** — always set `width`/`height` on images, reserve space for content injected later (`aspect-ratio`/`min-height`), use `font-display: swap` alongside `size-adjust`, and give ads/embeds fixed-size containers.

### Field vs. Lab Data

| | Lab Data | Field Data |
|---|----------|-----------|
| **Source** | Lighthouse, WebPageTest, Playwright, k6/browser | Chrome UX Report (CrUX), RUM tools |
| **Environment** | Simulated, controlled | Real users, real devices, real networks |
| **Use for** | Debugging, CI gates, pre-deployment | Understanding actual user experience |
| **Limitation** | No real-world variance; no field INP | Cannot reproduce specific conditions |

Lab data belongs in CI gates and debugging sessions; field data tells you what's
actually happening to real visitors. A page scoring a perfect 100 in Lighthouse while
CrUX data looks bad has a genuine problem on its hands — and remember, INP will only
ever show up in that field column.

## Bottleneck Identification

When a budget gets breached, work through this order — resist the urge to guess or to
start optimizing before you've profiled:

1. **Find the slow endpoint first.** Per-endpoint `Trend` metrics from k6 surface p50/p95/p99 for each API. Whichever is slowest is where you start.
2. **Check the database.** Look for missing indexes (`EXPLAIN`), N+1 query patterns (fix with JOIN/batching), lock contention on write-heavy tables (restructure transactions), and unbounded result sets (add pagination).
3. **Check CDN/caching behavior.** Confirm `cache-control` is set correctly on static assets (`public, max-age=31536000, immutable`) and look at the `x-cache: HIT` ratio.
4. **Check third-party scripts.** Re-run Lighthouse with `blockedUrlPatterns` covering analytics/chat/tracking tags, then diff the scores with and without them to see their real cost.
5. **Cross-reference server-side metrics.** Client-side timing alone won't reveal the cause — pull CPU, memory, disk I/O, connection-pool saturation, and query execution time from the same window as the test.

## Anti-Patterns

### 1. Load testing production without a heads-up
An uncoordinated load test can trip auto-scaling (costly), get rate-limited (the test just fails), fire alerts (paging people for nothing), or cause a real outage. Always loop in operations first, and aim tests at staging or a dedicated load environment.

### 2. Load scenarios disconnected from reality
Simulating 10,000 concurrent users on a product with 500 daily actives, or flat uniform traffic when real usage spikes hard at certain hours. Build the model from analytics data; without that, start around 2x estimated peak and scale from there.

### 3. Watching only the client side
Reading nothing but k6's response times while the server quietly sits at 95% CPU, the connection pool runs dry, or memory leaks climb. Always cross-check load results against server-side metrics.

### 4. Only testing performance right before a release
A once-a-quarter pre-release load test lets regressions pile up for months with no way to trace which change caused what. Run performance tests in CI on every merge to main, with budgets that catch regressions the moment they land.

### 5. Skipping budgets entirely
Saying "LCP is 3.2s" tells you nothing actionable; saying "LCP must stay under 2.5s" is an enforceable rule. Set budgets, encode them as k6 thresholds and Lighthouse assertions, and treat any violation as a bug.

### 6. Trying to assert INP inside standard Lighthouse CI
A standard `lhci autorun` lab run has no user interaction, so it can never produce a real INP score. Gating on `interaction-to-next-paint` there checks a number Lighthouse never actually measured. Gate `total-blocking-time` in the lab instead, and pull true INP from CrUX/RUM.

### 7. Optimizing before profiling
Burning days shaving time off a function responsible for 2% of total response time. Profile first, locate the real bottleneck, then optimize it — a 200ms slow query will always matter more than a 5ms JS function.

### 8. Load testing against a near-empty database
Running load tests with 100 rows seeded when production holds 10 million. Query behavior changes dramatically at real scale. Seed the load environment with anonymized, production-scale data before testing.

## Verification

Confirm the artifacts actually behave as intended before calling the work finished:

- **k6 script:** `k6 run --summary-mode=disabled load-tests/api-load.js` should exit **0**,
  with the final summary showing every `thresholds` line green (`✓`). Any red threshold
  line means a budget was breached and the exit code will be non-zero.
- **Spike recovery:** run the spike script and check that the `{phase:recovery}`
  threshold shows up in the summary and passes — that's the proof recovery is being
  asserted, not merely noted in a comment.
- **Lighthouse CI:** `lhci autorun` should exit **0** with every `['error', ...]`
  assertion passing; a breached LCP/CLS/TBT assertion causes a non-zero exit.

## Done When

- k6 scripts cover the target load profiles: baseline (constant), stress (ramp to breaking point), and soak (sustained), each with `__ENV`-driven base URL.
- Spike test asserts recovery via a threshold scoped to the post-spike window (e.g. `http_req_duration{phase:recovery}`), not just a `// recovery` comment.
- Performance budgets encoded as k6 thresholds (e.g. `p(95)<500`, `http_req_failed rate<0.01`) that fail the CI job when exceeded.
- Lighthouse CI `lighthouserc.js` gates merges on `largest-contentful-paint`, `cumulative-layout-shift`, and `total-blocking-time` (the lab proxy for INP) as `['error', ...]` assertions; real INP tracked from CrUX/RUM, not asserted in lab.
- Core Web Vitals baselines documented for each key page (home, checkout, dashboard) with Good/Needs Improvement/Poor classification.
- Test results include p95 and p99 latency, error rate, and throughput per scenario, stored as CI artifacts.

## Reference Files (in `references/`)

- **recipes.md** — runnable artifacts: basic k6 load test, spike-with-recovery detection, custom metrics, scenarios, k6 CI workflow (`grafana/setup-k6-action`), `lighthouserc.js`, the `k6/browser` CWV-under-load example, and the Playwright LCP/CLS test.

## Related Skills

- **ci-cd-integration** — pipeline wiring for k6 and Lighthouse CI, scheduling nightly runs, gating deployments on budgets.
- **qa-metrics** — LCP/INP/CLS and p95 latency as part of the broader QA metrics dashboard.
- **release-readiness** — performance benchmarks in the go/no-go checklist.
- **synthetic-monitoring** — scheduled production CWV/uptime probes *after* release; this skill is pre-release lab gating.
- **observability-driven-testing** — when prod telemetry is the *input* to designing new perf tests.
- **qa-project-context** — captures performance budgets, traffic patterns, and critical flows to test.
