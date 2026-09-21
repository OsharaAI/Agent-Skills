---
name: service-virtualization
description: >-
  Playbook for deciding how to isolate each external dependency a test suite touches — in-process
  mocks, HTTP-level stubs (MSW, WireMock), record-replay fixtures, fault injection (Toxiproxy), or
  short-lived real services (Testcontainers) — and for making sure no live call can slip through
  CI unnoticed.
  Use when: "mock service," "stub API," "fake service," "WireMock," "MSW," "Toxiproxy,"
  "test isolation," "dependency management," "stub an external API in CI."
  Not for: consumer-driven contract verification (Pact, broker) — use contract-testing; standing
  up a full Docker Compose env or seed data — use test-environments; broad resilience/game-day
  fault campaigns — use chaos-engineering.
  Related: contract-testing, test-environments, api-testing, test-data-management, chaos-engineering.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: infrastructure
---

<objective>
Stub Stripe underneath the SDK and your suite will stay green right up until Stripe tweaks a field
in a live response and production starts throwing 500s — because nothing tied that stub to a real
contract. This skill helps you pick the right isolation approach for each dependency (in-process
mock, HTTP stub, record-replay, fault injection, or a disposable real instance), pushes stubbing
down to the HTTP boundary so an SDK bump can't silently break your tests, and makes CI fail loudly
the moment a real network call slips past your stubs.
</objective>

## Where to Start

| Situation | Go to |
|-----------|-------|
| Node/browser test hitting an external HTTP API | MSW → `references/msw.md` |
| Polyglot CI, complex matching, or you need a standalone stub server | WireMock → `references/wiremock.md` |
| Dependency is a DB / cache / queue | Testcontainers → `references/testcontainers.md` |
| Testing timeouts, latency, connection resets | Toxiproxy → `references/toxiproxy.md` |
| Bootstrapping stubs from a real API, or a multi-step baseline | Record-replay → `references/record-replay.md` |
| Wiring any of these into GitHub Actions | `references/ci.md` |
| Not sure which to reach for | see the decision tree below |

---

## Questions Worth Asking First

Check `.agents/qa-project-context.md` before anything else — if it's there, follow its existing
mocking conventions and treat anything it already answers as settled. Otherwise, work through:

- **How many external dependencies exist, and which ones actually hurt in tests?** Anything
  rate-limited, slow, flaky, or billed per call is a prime virtualization target — payments, email,
  auth providers, and third-party data feeds usually top the list.
- **Which test level are you isolating for?** Unit tests want the fastest possible in-process
  mocks; integration tests want HTTP-level fidelity; end-to-end wants something close to
  production. The level you're at determines the strategy, not personal preference.
- **Does the vendor ship a real sandbox?** Stripe's test mode, Twilio's test credentials, and
  similar official modes beat anything you'd build yourself — reach for them first when available.
- **Is there a contract backing this dependency?** If so, contract tests will keep your stubs
  honest — hand off to `contract-testing`. If not, understand you're mocking something you don't
  own, which is a real risk (see Guiding Principle 3 below).
- **Is Docker available in CI?** Without it you're limited to MSW's in-process interception; with
  it, WireMock, Testcontainers, and Toxiproxy all become options.

---

## Guiding Principles

**1. Let the confidence you need set the isolation level.** Unit tests are allowed to mock
aggressively since they're exercising internal logic. Integration tests need stubs that behave
realistically because they're proving out boundaries. End-to-end tests should run against
whatever is closest to production while still being reliable enough to run repeatedly.

**2. When a real dependency is cheap, fast, and reliable, use it instead of faking it.** A
throwaway PostgreSQL container is more trustworthy than any hand-built fake, and it costs almost
nothing to spin up — default to it. Save fakes for dependencies that are genuinely slow,
unreliable, or expensive to call.

**3. Don't mock what you don't own unless a contract is watching it — and prefer the vendor's own
sandbox first.** Stub Stripe's shape today and let Stripe change it tomorrow, and your tests will
keep passing while production breaks. Preference order: the provider's official test mode or
sandbox (Stripe test mode, Twilio test creds) first, then an HTTP stub backed by a contract test
that catches drift, and only as a last resort a bare stub with nothing validating it. See
`contract-testing`.

**4. A stub that never fails is only half a stub.** If every response is a 200, your error-handling
code never actually runs during tests. Every stub needs failure variants too — 429s, 500s,
timeouts, malformed payloads.

**5. Put one abstraction layer between your tests and whichever tool you're using.** Wrap MSW
handlers, WireMock mappings, and Testcontainers bootstrapping behind a shared interface so a future
tool swap doesn't force a rewrite of every test.

---

## Choosing a Strategy

### How the isolation options compare

| Strategy | Speed | Fidelity | Complexity | Best for |
|----------|-------|----------|------------|----------|
| **In-process mock** | Fastest | Lowest | Trivial | Unit tests, isolating internal modules |
| **HTTP stub (MSW)** | Fast | Medium | Low | Frontend/Node tests hitting external APIs |
| **HTTP stub (WireMock)** | Fast | Medium-High | Medium | Language-agnostic, complex matching rules |
| **Record-replay** | Fast after first run | High initially, decays | Medium | Bootstrapping stubs from real APIs quickly |
| **Service fake** | Medium | High | High | Stateful dependencies (in-memory DB, fake auth) |
| **Ephemeral real (Testcontainers)** | Slower | Highest | Medium | Databases, message queues, caches |
| **Shared real service** | Slow | Production-level | Low (to set up) | Staging validation, final pre-deploy check |

### A tree to walk through when undecided

```
Is the dependency internal to your codebase?
├─ Yes → In-process mock (vi.mock / jest.mock / monkeypatch)
└─ No → Is it a database, cache, or message queue?
         ├─ Yes → Testcontainers (ephemeral real instance)
         └─ No → Is it a third-party HTTP API?
                  ├─ Yes → Does the provider offer a test/sandbox mode?
                  │        ├─ Yes → Use sandbox in staging, MSW/WireMock in CI
                  │        └─ No → MSW or WireMock + contract test for drift detection
                  └─ No → Is it an internal microservice?
                           ├─ Yes → Contract test (Pact) + stub for consumer tests
                           └─ No → Evaluate case by case
```

---

## The Toolset

Default to **MSW** for in-process Node/browser tests, reach for **WireMock** when you need
cross-language coverage or a standalone stub process, use **Prism** when the OpenAPI spec is
itself the source of truth, and keep **Mockoon** around for exploratory mocking during
development. The detailed setup for each lives under `references/` — what follows is the summary.

### MSW (Mock Service Worker)

MSW 2.x intercepts traffic at the network layer — a Service Worker in browsers, request
interception in Node — making it the natural default for JS/TS codebases. Stub the HTTP boundary
itself (`POST /v1/payment_intents`) rather than an SDK method, so the test doesn't care which SDK
version is installed.

The key enforcement lever this skill relies on is `setupServer(...).listen({ onUnhandledRequest })`.
Flip it to `"error"` in CI so any request that escapes your handlers fails the build; leave it at
`"warn"` locally so you're not blocked mid-iteration.

`references/msw.md` covers centralized stateful handlers (payments), a Vitest setup that switches
`onUnhandledRequest` based on CI vs. local, per-test timeout/retry overrides, and a full stateful
auth lifecycle — create, verify, refresh, and **revoke through `http.delete`** — keyed off a
`Bearer` token.

### WireMock

A language-agnostic HTTP stub server (currently stable at **3.13.2** — 4.0 is still beta as of
mid-2026, so stick with the 3.x line for CI). It can run standalone or as a container, and it
shines in polyglot setups or wherever matching logic gets complicated.

Lean on **priority-based mappings** to model error scenarios: give a `priority: 1` mapping that
only matches when a test opts in via an `X-Test-Scenario: rate-limit` header, returning 429 — it
shadows the default happy-path mapping without affecting anything that doesn't ask for it.
WireMock's admin API also lets you create stubs programmatically (`POST /__admin/mappings`),
verify calls (`POST /__admin/requests/count`), and reset state (`POST /__admin/mappings/reset`).

`references/wiremock.md` has the Docker setup, a response-templated paginated mapping, the JSON
for a priority-based error mapping, and how to wire in drift detection against `contract-testing`
(replaying a Pact or checking the stub against an OpenAPI spec via Prism).

### The rest of the HTTP mock landscape

| Tool | Strengths | When to use |
|------|-----------|-------------|
| **Mockoon** | Desktop UI + CLI; OpenAPI import; rule-based responses; lightweight | Dev-time mocking and quick CLI mocks in CI |
| **Hoverfly** | Capture-replay (record real traffic, replay deterministically); capture/simulate/modify/synthesize modes | Migrating from a real dependency to a mock — record once, replay forever |
| **Prism** | OpenAPI-driven mock server (Stoplight); validates requests + generates responses from spec | OpenAPI-first projects with a published spec |
| **MockServer** | Java-based; rich expectation matching; multi-protocol | JVM teams already on MockServer |

### Testcontainers

Boots **actual** services in Docker for integration tests — containers come up before the suite
runs and get torn down afterward. `@testcontainers/postgresql` 11.x and its siblings cover the
common cases. Mapped ports are **random by design**, so always fetch them through
`getMappedPort()` / `getConnectionUri()` rather than hardcoding `5432`/`6379`.

`references/testcontainers.md` walks through starting PostgreSQL, Redis, and Elasticsearch in
parallel with wait strategies, wiring a Vitest `globalSetup` (`process.env.DATABASE_URL`,
`testTimeout: 30_000`), and a reminder to periodically refresh pinned image tags — `elasticsearch:8.12.0`
is already trailing the Elastic 9.x line.

### Toxiproxy (fault injection)

`ghcr.io/shopify/toxiproxy:2.12.0` inserts itself as a TCP proxy between your app and a dependency,
letting you dial in latency, throttle bandwidth, or force connection resets. Your app connects to
the **proxy** port, never the real one directly. Clear toxics in `afterEach` without fail — they
otherwise bleed into the next test.

`references/toxiproxy.md` covers the compose port mapping, wiring `createProxy(name, listen,
upstream)` (including how compose's `15432`/`16379` proxy ports map back to the real upstream),
helper functions that check `response.ok` on every call, and a worked example combining latency
injection with a connection reset. For campaign-scale resilience testing, that's `chaos-engineering`
territory instead.

---

## Record-Replay

Record-replay captures live API responses once, then replays them deterministically on future
runs — handy both for bootstrapping stubs quickly and for pinning down a regression baseline
across a multi-step interaction. Reach for an established library — **Hoverfly**, **Polly.JS**, or
**VCR**-style cassettes — rather than writing your own recorder.

It falls apart on dynamic fields (timestamps, UUIDs), on stateful multi-step sequences, and simply
with age — recordings drift out of date within a matter of weeks. Always stamp a `recordedAt`
value and **fail any test whose recording has passed 30 days**, forcing it to be re-captured.

`references/record-replay.md` covers the cassette format, an `assertFresh()` helper enforcing the
30-day cutoff, and a replay harness driving a multi-step flow (create order → add items → apply
coupon → checkout).

---

## Wiring This Into CI

MSW requires no supporting infrastructure at all — it intercepts in-process, so CI behaves exactly
like a local run; the one CI-specific rule is setting `onUnhandledRequest: error` (quoted `"error"`
in JS) so any call that escapes the stubs hard-fails the job. WireMock and Testcontainers, by
contrast, both need Docker.

Two **mutually exclusive port models** show up here, and mixing them in one suite causes confusion:
docker-compose publishes **fixed** ports (so a hardcoded `DATABASE_URL=...localhost:5432...` just
works), while Testcontainers hands out **random** ports that must be read via `getMappedPort()` and
injected into `process.env`. Commit to one model per suite.

`references/ci.md` has the MSW step, a docker-compose GitHub Actions job (`up -d --wait
--wait-timeout 120`, with `if: always()` teardown), and a table matching CI constraints to tools.

---

## Common Mistakes

### 1. Mocking absolutely everything
When every dependency is faked, the suite only proves the mocks behave as configured — not that
the real system works. Reserve real instances (via Testcontainers) for databases and caches; stub
only the external HTTP calls.

### 2. Letting mock responses diverge between tests
One test returns `{ id: "pi_123" }` for Stripe, another returns `{ paymentIntentId: "pi_123" }` —
now two tests disagree about what reality looks like. Keep handlers centralized and reuse a single
response shape everywhere (see the shared shape in `references/msw.md`).

### 3. Letting stubs go stale as the real API evolves
The mapping still says Stripe returns `{ amount: 1000 }`, but the live API has since added
`{ amount: 1000, currency: "usd" }`. Tests stay green, production doesn't. Contract tests exist
precisely to catch this — see `contract-testing` and the drift-detection notes in
`references/wiremock.md`.

### 4. Stubbing at the wrong altitude
Mocking `stripe.paymentIntents.create` ties the test to a particular SDK version. Stub the
underlying HTTP call (`POST /v1/payment_intents`) instead, so the test keeps working regardless of
HTTP client or SDK changes.

### 5. Skipping failure scenarios
A stub that only ever returns 200 never touches retry logic, timeout handling, backoff, or error
parsing. Pair every stub with at least one failure variant.

### 6. Reusing one long-lived shared mock server
A single WireMock instance shared across CI jobs invites coupling and leftover state from one run
bleeding into the next. Give every test run its own isolated stub server.

### 7. Record-replay with no expiration check
A cassette recorded six months ago describes an API that has likely moved on. Stamp `recordedAt`
and fail tests once a recording passes 30 days, forcing a fresh capture (see
`references/record-replay.md`).

---

## Confirming It Actually Worked

Work from the smallest, cheapest check up to the broadest:

```bash
# 1. MSW: any unhandled request must hard-fail the suite in CI
CI=1 npm run test:integration            # onUnhandledRequest:"error" → exit 0 means nothing escaped

# 2. WireMock/Testcontainers: confirm containers are reachable, then teardown leaves nothing
docker compose -f docker-compose.test.yml up -d --wait --wait-timeout 120 && echo OK
docker compose -f docker-compose.test.yml down -v

# 3. Grep CI logs for outbound calls to the real provider's host (should print nothing)
grep -iE "api\.stripe\.com|api\.twilio\.com" ci-run.log && echo "LEAK" || echo "clean"
```

A clean run with `CI=1` and `onUnhandledRequest:"error"`, paired with an empty grep against the
real host, is your proof that nothing bypassed virtualization.

---

## Exit Criteria

- Every external dependency has a documented isolation decision (MSW/WireMock stub, Testcontainers,
  or vendor sandbox mode).
- Each critical dependency's stub includes at least one failure path — a 4xx/5xx, a timeout, or a
  rate limit.
- Stub definitions and mapping files live in version control next to the tests that use them.
- CI runs green with `onUnhandledRequest: "error"` (or WireMock's equivalent), and grepping CI logs
  for the real provider's host comes back empty.
- Any record-replay baseline carries a `recordedAt` stamp and a 30-day freshness check that fails
  the test once it's stale.

## Reference Files (in `references/`)

- **msw.md** — centralized stateful handlers, a Vitest setup with the CI/local `onUnhandledRequest`
  switch, per-test timeout/retry overrides, and the full create/verify/refresh/revoke auth flow.
- **wiremock.md** — Docker setup, response-templated and paginated mappings, the priority-based
  error mapping, the admin API, and the contract-drift seam (Pact/Prism).
- **testcontainers.md** — parallel PostgreSQL/Redis/Elasticsearch startup, `globalSetup` wiring,
  and the image-tag refresh note.
- **toxiproxy.md** — compose ports, `createProxy` upstream wiring, helpers with `response.ok`
  checks, and a latency + reset usage example.
- **record-replay.md** — tooling choices, the cassette format, the 30-day `assertFresh` check, and
  a multi-step replay harness.
- **ci.md** — MSW (zero-infra), the docker-compose GitHub Actions job, the two port models, and the
  tool-by-constraint table.

## Related Skills

- **contract-testing** — Consumer-driven contract verification with Pact/broker; go there to prove
  a stub matches a real provider, not just to detect drift against a shared schema.
- **test-environments** — Full Docker Compose env strategy, preview environments, and seed data; go
  there for standing up the environment, not for isolating a single dependency.
- **chaos-engineering** — Broad fault-injection campaigns, game days, and blast-radius limits; go
  there when resilience itself is the goal rather than making one dependency misbehave in a test.
- **api-testing** — REST/GraphQL testing patterns, schema validation, and auth flow testing.
- **test-data-management** — Factory patterns and data seeding for stub state setup.
