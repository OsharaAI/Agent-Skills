---
name: observability-driven-testing
description: >-
  Use production telemetry as INPUT to design new tests. Covers OpenTelemetry
  integration with tests, trace-based assertions, log-informed test creation,
  production-error analysis for coverage gaps, and telemetry-driven test
  prioritization. Use when: "trace-based testing," "design tests from logs,"
  "OpenTelemetry assertions," "production errors point to test gaps,"
  "telemetry-driven testing." Not for: safe rollout techniques (flags, canary)
  during release — use testing-in-production. Not for: scheduled post-deploy
  probes — use synthetic-monitoring. Not for: triaging CI failures — use
  ai-bug-triage.
  Related: testing-in-production, synthetic-monitoring, qa-metrics, ai-bug-triage.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: production
---

<objective>
Nothing tells you where your test suite is thin better than production itself: every
error log, every slow span, every latency spike is a hint about a gap you haven't
closed. This skill wires that feedback back into test design, and treats the shape of
a trace as something you can assert on, not just read after the fact. A request that
quietly reaches the database on a path that was supposed to be cache-only will still
return `200 OK` — an HTTP-only check waves it through, while a trace-based assertion
catches it. What comes out the other end: instrumented test runners, assertions built
on trace structure, and a repeatable pipeline from production error to regression test.
</objective>

## Where to Start

| If you need to... | Go to |
|-----------|-------|
| Make test runs emit traces tied to the app under test | OTel test-runner setup (`references/trace-assertions.md`) |
| Check which services fired, whether any span errored, or how long things took | Traces as Test Evidence |
| Convert a Sentry/Datadog error into an actual test | Production Error to Test Pipeline |
| Figure out which endpoint most needs a test next | Telemetry-Driven Test Prioritization |
| Debug a trace assertion that's flaky or a span that never shows up | Failure Modes |

---

## Questions to Ask First

Check `.agents/qa-project-context.md` before anything else — if it's there, treat it as ground truth and skip whatever it already answers.

**What's the observability stack?**
- Which APM/tracing product is running (Datadog, New Relic, Honeycomb, Splunk Observability/SignalFx, ServiceNow Cloud Observability — formerly Lightstep, Dash0, Jaeger, Grafana Tempo, or plain OpenTelemetry)? This decides both how you pull traces and the query language the diagnosis steps below assume.
- Is OpenTelemetry wired into the app, and for which services specifically? Anything un-instrumented is effectively invisible to trace-based testing.
- What's handling logs (ELK, Loki, CloudWatch, Datadog Logs)? This is where you'll correlate logs to a trace ID.
- Structured logs, or freeform text? Structured logs translate directly into test-gap data; freeform text needs a fingerprinting pass first.

**How mature is the tracing setup?**
- Do traces cross service boundaries, or stop at one service? Without cross-service traces you're limited to single-span assertions.
- What's the sampling rate — full capture, 10%, head-based, tail-based? Probabilistic sampling can silently drop the exact trace a test depends on, so test traffic needs to be force-sampled (details under Failure Modes).
- Can you query traces by error status, by latency, or by custom attribute?
- Are traces, logs, and metrics correlated with each other? That correlation is what makes exemplars — jumping from a metric straight to a representative trace ID — actually usable for prioritization.

**How solid is production error tracking?**
- What tool captures errors (Sentry, SmartBear Insight Hub — formerly Bugsnag, Rollbar, Datadog Error Tracking, LaunchDarkly Observability, formerly Highlight.io)?
- Who triages production errors, and how — automated, manual, or not at all?
- Is there any established habit of converting a production error into a test case?
- What's the most recent production error that a test really should have already caught?

**What can the test infrastructure itself do?**
- Can your tests emit their own telemetry (traces, custom metrics, structured logs)?
- Is test telemetry ever correlated back to application telemetry?
- Do you have any mapping from tests to the code they cover? You'll need this to build the error-rate-to-coverage matrix further down.

---

## The Underlying Principles

### 1. Let production tell you what to test next
The highest-value tests are the ones that stop a real incident from repeating — not hypothetical edge cases you dreamed up at a whiteboard. Treat the production error log as a pre-sorted backlog: it's already ranked by what actually happened to real users.

### 2. A trace is evidence, not just diagnostics
Knowing "the API returned 200" only proves the endpoint responded. Knowing "the request hit the cache, never touched the database, and finished in under 50ms" proves the system did the right thing end to end. Trace-based checks add depth to a test without adding brittleness.

### 3. An observability blind spot is a testing blind spot
If a code path has no traces, no logs, and no metrics, it's unverifiable — you can't test it in advance and you can't diagnose it during an incident. Test coverage and observability coverage are really the same map viewed from two angles.

### 4. Don't let the loop stay open
The cycle needs to complete: an error surfaces, gets analyzed, becomes a test, ships, and the recurrence stops. Teams that catch production errors but don't consistently turn them into tests will keep re-catching the same category of bug forever.

---

## Traces as Test Evidence

> **Pin `@opentelemetry/semantic-conventions` to a single exact version and treat any bump to it as a breaking change.** Attribute names in trace assertions are just strings, and those strings shift between releases — silently breaking your assertions. v1.41.0 (April 2026) alone introduced GenAI breaking changes, split out a `process.executable` entity, and demoted `graphql.document` from Recommended to Opt-In. Pin the exact version and upgrade only on purpose:
>
> ```json
> // package.json — exact pin, no caret
> "@opentelemetry/semantic-conventions": "1.41.1"
> ```
> ```bash
> npm install --save-exact @opentelemetry/semantic-conventions@1.41.1
> ```
>
> **Avoid adding new OpenTracing shims.** OpenTracing compatibility was deprecated by the OTel spec in March 2026 (removal no sooner than March 2027) — write new instrumentation against native OTel APIs and OTLP instead.

The full implementation for the three patterns below lives in `references/trace-assertions.md`:

- **Instrument the test runner itself** — wire tracing into the runner (`test-setup/tracing.ts`) so a test run's spans link up with the application's own traces through `service.name`, `test.suite`, and `test.run_id` resource attributes. Do the flush in the runner's **global teardown** with an awaited `sdk.shutdown()` call — not a `process.on('beforeExit')` handler, which will drop the last spans.
- **Build assertions on trace shape** — check which services were hit, that no span carries an ERROR status, how long the root span took, and what database calls happened, rather than relying solely on HTTP status. When you only need to check spans from a single process, skip the network entirely: use an **`InMemorySpanExporter` with a `SimpleSpanProcessor`** and call `getFinishedSpans()` synchronously — there's no `waitForTrace` polling and no timeout-induced flake. Save the real collector + `waitForTrace` approach for traces that actually span multiple processes.
- **Validate multi-service flow** — an `assertTraceStructure` helper that confirms a request touched the right services in the right order, with per-span attribute checks and a `maxDuration` ceiling.

If you'd rather express trace assertions declaratively (YAML/UI rather than hand-written span queries), the open-source **Tracetest** project (`kubeshop/tracetest`) still exists, but its most recent public OSS release is v1.7.1 (Oct 2024) and activity has slowed — check its maintenance status before betting on it. Its commercial Cloud product was discontinued in October 2024, so don't attempt to set that up.

---

## Turning Logs Into Test Design

### Mine production error logs for missing tests

Production errors are your best signal for where to write tests next — every uncaught one represents a gap. `references/log-and-error-pipeline.md` has the `analyze-production-errors.ts` script, which maps each error to existing test coverage, ranks it by frequency and recency, and recommends which layer (unit/integration/e2e) the new test belongs in.

### Sort errors into covered vs. uncovered

```
1. Pull production errors from whatever tracker you use (Sentry, Insight Hub, etc.)
   - Filter: last 30 days, occurrence count > 5 (skip one-offs)
   - Group by: error message fingerprint

2. For each error group, ask:
   a. Would an existing test catch this?
      → Yes: something's wrong with that test (not running, or has a hole) — dig in
      → No: this is a genuine test gap — write one

   b. What layer does the test belong at?
      → TypeError / null reference → unit test
      → Timeout / connection error → integration test with fault injection
      → UI rendering breakage → E2E test
      → Data inconsistency → contract test or database test

3. Result: a ranked list of tests to write, ordered by
   error frequency × user impact × recency
```

### Rank by how often it happens and how much it matters

Use a 2×2 of frequency against impact: P0 is high-frequency and high-impact (drop everything), P1 is low-frequency but high-impact (next sprint), P2 is high-frequency but low-impact (this sprint), and P3 is low on both axes (backlog it). High impact reads as payment/auth breakage, data loss, or a crash; low impact reads as a UI glitch or something slow-but-working.

---

## Telemetry-Driven Test Prioritization

### Rank endpoints by an error-weighted gap score

Test effort should scale with actual traffic and actual failure — not guesswork. **The formula below is the one this whole skill relies on:**

```
Gap Score = (error_rate × requests_per_day) / max(test_count, 1)
```

It's error-weighted — it ranks an endpoint by the raw volume of failing requests, discounted by how much test coverage already protects it. (Want a volume-weighted view instead — one that surfaces high-traffic endpoints that are otherwise healthy? Multiply by `(1 + error_rate)` instead of `error_rate`. That's a different question, and the labels below don't apply to it.)

### Example: mapping error rate and coverage to a gap score

```
Endpoint           | Requests/day | Error Rate | Test Count | Gap Score
POST /api/orders   | 50,000       | 0.3%       | 2          | 75   CRITICAL
PUT  /api/profile  | 5,000        | 1.2%       | 1          | 60   CRITICAL
DELETE /api/items  | 2,000        | 0.8%       | 0          | 16   HIGH
POST /api/auth     | 80,000       | 0.1%       | 8          | 10   OK
GET  /api/search   | 200,000      | 0.05%      | 15         | 6.7  OK

Gap Score = (error_rate × requests_per_day) / max(test_count, 1)
Labels: CRITICAL ≥ 50, HIGH 12–49, OK < 12.

Action: write tests for anything HIGH or above, starting with the highest score.
```

Each label above falls directly out of the formula plus the stated cutoffs — apply the same formula and you'll land on the same matrix. Feel free to choose your own thresholds, but write them down explicitly rather than hand-labeling rows.

**Exemplars are what closes the loop from metric to trace to test.** Once an endpoint shows up as high-error in this matrix, OTel exemplars let you jump directly from that error-rate metric to one representative failing trace ID — then walk that trace (see below) to build the test, instead of manually searching for a matching one.

### Trace the hottest paths

Find the code paths that see the most production traffic and make sure their test coverage matches.

```
1. Pull the top 20 endpoints by request volume from APM data
2. For each, trace the request through every service it touches
3. Map each service-level span to what test coverage exists
4. Flag hot paths where coverage is zero or thin

Output:
  /api/checkout → cart-service → pricing-service → payment-service
  Coverage: cart-service (82%) → pricing-service (45%) → payment-service (91%)
  Gap: pricing-service's discount calculation sits at 45% coverage on a critical path
  Action: add discount edge-case tests in pricing-service
```

> **Combine endpoint-level traffic data with continuous profiling** to catch CPU and allocation hotspots *inside* an endpoint, not just at its boundary. The OTel **profiling signal** hit public alpha on 2026-03-26 (OTLP path `/v1development/profiles`), targeting GA around Q3 2026 — don't treat it as production-ready yet. For now, reach for **Pyroscope**, **Parca**, **Polar Signals**, or **Datadog Profiling**. If you need zero-instrumentation (eBPF-based) profiling: Polar Signals, Parca, or Grafana **Beyla**.

> **Zero-instrumentation observability** — when rolling out the OTel SDK isn't realistic yet, eBPF-based tools can capture HTTP/gRPC traces straight from kernel syscalls without touching application code: **Beyla** (Grafana), **Cilium Tetragon**, **Pixie**, **Coroot**. Good fit for legacy or polyglot services where SDK adoption would take quarters.

> **OTel Weaver** turns semantic-convention YAML into type-safe instrumentation code, which keeps trace assertions from drifting out of sync with sem-conv releases. Worth it if you maintain custom conventions or have been bitten by attribute drift before.

---

## Production Error to Test Pipeline

This is the core workflow of the whole skill — converting a production error into a test that stops it from recurring.

```
1. ERROR DETECTED
   Source: Sentry, Datadog, CloudWatch, or any error tracker
   Capture: error message, stack trace, request context, trace ID, user impact

2. REPRODUCE
   - Pull the trace from your observability platform (use an exemplar → trace ID if you have one)
   - Pin down the exact request parameters and state that caused it
   - Reproduce it locally or in staging with matching input
   - Can't reproduce it? Add targeted logging and wait for it to happen again

3. WRITE TEST
   - Pick the right layer (unit for logic bugs, integration for cross-service issues)
   - The test must fail before the fix lands (red-green check)
   - Reference the originating production error in the test name or a comment

4. FIX AND DEPLOY
   - Fix the underlying bug; confirm the new test passes with the fix in place
   - Ship the fix and the test together

5. VERIFY IT'S GONE
   - Watch for the same error in production post-deploy
   - Confirm the count drops to zero
   - Still happening? The fix was incomplete — go back to step 2
```

`references/log-and-error-pipeline.md` walks through a complete example built from Sentry issue PROJ-4521 (a null shipping address causing a null-reference error), asserting either `400` or `422` at the API layer (whichever matches your contract) plus checking the E2E checkout prompt. The test name and an accompanying comment record the source error, how often it happened, and the context — follow that same convention for any test born from a production signal.

### Keep the team's feedback loop running

- **Weekly 30-minute error review:** pull the top 10 newest errors by frequency from the tracker. For each one: assign someone, write a test, or explicitly mark it known/acceptable. The failure mode to avoid is an error tracker with thousands of unread, unresolved entries.
- **Gate incident closure on it:** every postmortem should answer "what test would have caught this?" before the incident is closed — either the test gets written, or the gap is written down explicitly. Make this a checklist item, not a good intention.

---

## Diagnosis Workflows

### Walk a failing request through its full trace

When something fails — in a test or in production — use the trace to reconstruct exactly what happened.

```
1. Get the trace ID (from test output, the error tracker, or a user report)

2. Open it in your APM tool
   - Jaeger: /trace/{traceId}
   - Datadog: /apm/traces?traceId={traceId}
   - Honeycomb: query by trace.trace_id

3. Walk the span tree
   - Root span: what did the user actually request?
   - Child spans: which services got called?
   - Error spans: where did it actually break? (the first span showing an error)
   - Slow spans: where did the time go?

4. Cross-reference with logs
   - Filter logs to this trace ID to see every log line for the request
   - Look for warnings/errors that show up right before the failure

5. Nail down the root cause
   - Is it your code, a dependency, or infrastructure?
   - One-off/transient, or a persistent bug?
```

### Match a failing test against production telemetry

When a test fails, check your observability platform: (1) search production errors from the last 7 days for a matching message; (2) search traces on the same HTTP route for ERROR status. If you find a match, the bug is real and affecting real users — fix it now. No match means it's likely a test-only issue, or a bug that hasn't shown up in production yet. This is how you turn a vague "probably flaky" into either "confirmed, this hits production" or "confirmed, this is test-only."

---

## Anti-Patterns

### 1. Sitting on production signals
500 unresolved errors piling up that nobody looks at, while the suite stays green and the team assumes everything's fine. **Fix:** run the weekly error review described above — top 10, each one owned, tested, or explicitly accepted.

### 2. Only testing what's easy to see
Checking HTTP status and latency while data consistency, background job completion, and cache coherence go unchecked. **Fix:** instrument background jobs, cache operations, and async workflows with spans, and assert against them. Anything running in production should be producing telemetry.

### 3. Production and test teams never talking
SRE handles the incidents, QA writes the tests, and the two never systematically connect — so the same bug class keeps coming back. **Fix:** stand up the production-error-to-test pipeline and the incident-close gate described above.

### 4. Piling on instrumentation nobody reads
Emitting thousands of metrics and logs that nobody ever looks at — all cost, no payoff. **Fix:** name three specific questions you want telemetry to answer, build dashboards for exactly those, and only add more instrumentation when a new question shows up.

### 5. Treating traces as debug-only, never as assertions
Pulling up traces only after something breaks, instead of using trace shape as a proactive check. **Fix:** put trace-based assertions into integration tests — right services called, efficient queries, expected cache hits. These catch regressions that HTTP-only checks miss entirely.

### 6. Asserting on a trace that might get sampled away
Probabilistic/head-based sampling can drop the exact trace your assertion depends on, causing intermittent failures with no real cause. **Fix:** force-sample test traffic (`OTEL_TRACES_SAMPLER=always_on`, or an override for that specific request) so the trace you're asserting on is guaranteed to exist.

---

## Failure Modes

| Symptom | Likely cause | Fix or check |
|---------|--------------|--------------|
| `waitForTrace` times out, span never shows up | Sampling dropped it, or the exporter hadn't flushed before the assertion ran | Set `OTEL_TRACES_SAMPLER=always_on` for the test run; flush via an awaited `sdk.shutdown()` in global teardown |
| Last test's spans go missing | Shutdown was wired to `process.on('beforeExit')`, which doesn't fire on process exit/signal | Move the shutdown call into the runner's global teardown hook; `await sdk.shutdown()` |
| App's spans aren't part of the test's trace | The app isn't propagating the `traceparent` header | Verify the app reads/forwards the W3C `traceparent` header and that the OTel propagator is set up |
| Assertion on `db.system`/`graphql.document`/GenAI attributes breaks suddenly | A sem-conv version bump renamed or relocated the attribute | Pin `@opentelemetry/semantic-conventions` to an exact version; diff release notes; update assertions on purpose |
| No spans reaching the collector in CI | `OTEL_EXPORTER_ENDPOINT` isn't reachable from the CI network | Point it at the collector address inside CI; smoke-test with the Verification step below |
| `status?.code === 'ERROR'` never matches even though real errors exist | Your collector serializes status as `2` or `'STATUS_CODE_ERROR'`, not the literal string `'ERROR'` | Match whatever your specific collector actually emits (see the note in `references/trace-assertions.md`) |

---

## Verification

Confirm the whole telemetry pipeline actually works before trusting any assertion built on it — smallest check first:

```bash
# 1. Start a local collector, point the runner at it, run one instrumented test.
OTEL_EXPORTER_ENDPOINT=http://localhost:4318/v1/traces \
OTEL_TRACES_SAMPLER=always_on \
  npx playwright test --grep @trace

# 2. Confirm a span with service.name=integration-tests arrived at the collector
#    (check the collector's debug/logging exporter output, or query your APM).
```

Next, in code, confirm a **known** trace ID actually resolves before leaning on any structural assertion: `await collector.waitForTrace(traceId, { timeout: 10_000 })` should return spans — if it times out, chase down sampling, flushing, or propagation issues (see Failure Modes) before writing more assertions on top. For span checks scoped to one process, the `InMemorySpanExporter` route skips the collector entirely and returns synchronously.

## Done When

- Every one of the top-20-by-traffic endpoints (from the hot-path exercise) resolves to at least one span in a sampled trace — no high-traffic endpoint is a black box.
- At least one key user journey has trace-based assertions checking service calls and span attributes, not just HTTP status, and they pass with `OTEL_TRACES_SAMPLER=always_on`.
- Tests exist for the known failure modes surfaced by the production error analysis.
- You've computed the error-rate/Gap-Score matrix and it's produced at least one ranked list of untested code paths.
- `@opentelemetry/semantic-conventions` is exact-pinned in `package.json` (no caret).
- A post-deploy review (checklist item or postmortem entry) documents that observability signals were checked before calling the release stable.

## Reference Files (in `references/`)

- **trace-assertions.md** — OTel test-runner setup (correct global-teardown flush plus the in-memory exporter alternative), force-sampling guidance, trace-based assertions, and the distributed `assertTraceStructure` helper.
- **log-and-error-pipeline.md** — the `analyze-production-errors.ts` test-gap script and a full worked example of a production-error-to-test conversion (the 400-or-422 assertion).

## Related Skills

- **testing-in-production** — covers safe rollout mechanics (flags, canary, guardrail metrics) *during* a release; this skill instead consumes the telemetry those releases generate as input for designing tests *afterward*.
- **synthetic-monitoring** — scheduled probes that run *after* a release and generate their own telemetry, which then feeds back into the analysis here.
- **qa-metrics** — turns the numbers this skill produces (error rates, latency, Gap Score) into dashboards and KPIs; this skill generates the raw signal, qa-metrics rolls it up.
- **ai-bug-triage** — for when the input is a pile of CI/production failures that need classifying and routing first; use it to feed the error-categorization step here, then come back to write the tests.
