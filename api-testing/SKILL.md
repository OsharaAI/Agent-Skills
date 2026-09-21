---
name: api-testing
description: >-
  Test REST and GraphQL APIs with Playwright APIRequestContext, Supertest, or standalone
  HTTP clients. Covers schema validation with Zod 4/AJV, auth flow testing, CRUD lifecycle
  tests, error and header validation, pagination, and performance assertions. Use when:
  "API test," "endpoint test," "REST test," "GraphQL test," "schema validation," "Postman replacement."
  Not for: consumer-driven contract verification (Pact, broker) — use contract-testing; browser UI flows — use playwright-automation.
  Related: contract-testing, test-data-management, ci-cd-integration, playwright-automation.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: automation
---

<objective>
Imagine an endpoint quietly starts returning a nullable field, or drops one altogether. A spot-check like `toHaveProperty` won't catch it, and the frontend breaks — in production. Treating the schema as a contract and testing against it is what surfaces that kind of drift in CI instead. This skill is about building REST and GraphQL API tests that verify response shape, status codes, headers, auth boundaries, and timing, run against a genuine test environment rather than a mock.
</objective>

## Discovery Questions

First check whether `.agents/qa-project-context.md` exists — if it does, rely on it and don't re-ask anything it already covers. Otherwise, work through:

1. **Is it REST, GraphQL, or a mix of both?** Plain REST suites rely on standard HTTP-level assertions. GraphQL calls for query/mutation builders, and it's worth adding an introspection-diff snapshot too.
2. **What's the auth mechanism?** JWT, API key, OAuth 2.0, session cookies — the fixture strategy differs for each.
3. **Is there an OpenAPI/Swagger spec?** If so, generate Zod schemas from it automatically (`orval`, `openapi-zod-client`) and think about spec-driven fuzzing via Schemathesis.

---

## Core Principles

1. **You're testing contracts, not implementation details.** Focus assertions on response shape, status codes, and headers rather than internal logic or database state.
2. **Schema checks stop drift before it reaches consumers.** When a schema test fails, that's a breaking change caught before the frontend discovers it the hard way.
3. **Auth deserves its own tests — tokens shouldn't just be hardcoded.** Cover login, refresh, expiry, and permission boundaries.
4. **Timing is a legitimate assertion.** Catching a performance regression in CI is far cheaper than dealing with it in production.

---

## Exploratory vs Automated: Tooling

Poking around an API manually (debugging, an OpenAPI playground) and running an automated test suite are two different jobs, and they call for different tools:

| Tool | Best for | Why |
|------|----------|-----|
| **Bruno** (v3.4+) | File-based collections, git-reviewable workflows, FOSS Postman replacement | Filesystem-first, no cloud sync required; gRPC + OAuth + GraphQL query builder |
| **Hurl** (8.x) | Plain-text HTTP testing, CI smoke checks | One file = many requests + assertions; runs anywhere curl runs; certificate + JSONPath (RFC 9535) queries |
| **Hoppscotch** | Web-based Postman-style exploration | Open source, runs in browser, good for quick checks |
| **Playwright `APIRequestContext`** | Automated tests in your test runner | This skill's focus — covered below |
| **Supertest** (Node) / **httpx** (Python) | In-process API tests against your own app | Fastest feedback when you control both sides |

For new projects, there's usually no reason to reach for Postman or Insomnia unless the team is already invested in them — file-based options like Bruno and Hurl review far better in pull requests and hold up when collections drift.

## Playwright API Testing

`APIRequestContext` lets you run API tests without spinning up a browser, while still sharing cookie/storage state with browser contexts when needed. Reach for it when you want:

- **Pure API tests** — issue `request.get/post/...` calls and assert on status, headers, and body.
- **Browser + API combined** — seed state through the API, confirm it shows up in the UI, then tear it down through the API again.
- **Pre-authenticated fixtures** — authenticate once inside a fixture, pass tests an already-logged-in `APIRequestContext`, and dispose of it during teardown. Tokens should never be hardcoded.

The `playwright.config.ts`, standalone tests, a combined browser+API example, and the authenticated fixture are all in `references/playwright-setup.md`.

---

## Schema Validation

Rather than spot-checking a handful of fields with `toHaveProperty`, validate the whole response shape against a schema. Two approaches cover most needs:

- **Zod 4** — define the schema, run `safeParse` on the response, and assert `result.success`. On failure, log `result.error.issues` for a precise diff. Stick to Zod 4's native string-format functions — `z.email()`, `z.uuid()`, `z.iso.datetime()` — since the older chained style (`z.string().email()`) is deprecated and headed for removal.
- **AJV with JSON Schema** — a good fit when a JSON Schema already exists (say, generated from an OpenAPI spec); compile and run it via `ajv` plus `ajv-formats`.

**Schema-as-contract:** point both the API implementation and its tests at one shared schema file. Any change to the response shape then fails consumer tests immediately. If you have an OpenAPI spec, generate that schema automatically (`orval` or `openapi-zod-client`). Spec-first teams should also consider running **Schemathesis** in CI to fuzz the live API against its spec, which surfaces undocumented shapes and edge-case 500s.

Full Zod 4, AJV, schema-as-contract, and Schemathesis examples live in `references/schema-validation.md`.

---

## Test Patterns

Every endpoint deserves a happy-path test plus a minimum of one error-path test. The recurring patterns to reach for:

- **CRUD lifecycle** — one `describe.serial` block that walks through create, read, update, delete, and then confirms the resulting 404, threading the resource id through each step.
- **Auth flows** — successful login, bad credentials (401), an expired token (401), token refresh, and a permission-boundary check (403). Give auth its own describe block.
- **Error responses** — 400 for malformed bodies, 422 with field-level validation detail, and 429 with a `retry-after` header for rate limiting. A suite that only exercises the happy path isn't finished.
- **Response headers** — check `content-type`, `cache-control`, and rate-limit headers unconditionally, never tucked behind a conditional that might not even execute. See the example below.
- **Pagination** — metadata on the first page, an empty result for an out-of-bounds page, and rejection of an invalid page size.
- **File upload/download** — a multipart upload test plus verification of the `content-disposition` header.
- **GraphQL** — build a small `gql` helper, then cover query, mutation, and invalid-query (errors array) cases, and add an introspection-diff snapshot to catch fields removed without notice.
- **Webhooks** — stand up a disposable HTTP server, register a webhook against it, fire the triggering event, and check delivery.

Full runnable code for every pattern above, plus the performance assertions, is in `references/test-patterns.md`.

### Response Headers

Headers are part of the contract too — cache directives, rate-limit data, content type, CORS policy. Pull them via `response.headers()`, index by lowercase name, and assert them directly rather than wrapping the check in an `if (rateLimited)` that might never trigger.

```typescript
test('GET /api/users sets expected response headers', async ({ request }) => {
  const response = await request.get('/api/users');
  const headers = response.headers();

  expect(headers).toBeDefined();
  expect(headers['content-type']).toContain('application/json');
  expect(headers['cache-control']).toBeDefined();   // "no-store" | "max-age=60" | ...
});
```

The rate-limit and `retry-after` variants are in `references/test-patterns.md` (Response Header Validation).

---

## Performance Assertions

Response time and payload size can be asserted just like anything else: check that a hot endpoint stays under a time budget (say, 500ms), that payload size doesn't exceed a ceiling, and that the API keeps returning non-5xx responses under a burst of concurrent load. See `references/test-patterns.md` (Performance Assertions) for the implementation.

---

## Anti-Patterns

### 1. Hardcoded auth tokens
Tokens expire, get rotated, and differ per environment. Acquire them dynamically through a login fixture instead.

### 2. Testing against production
API tests create, modify, and delete data — point them at a dedicated test environment or a local instance, never prod.

### 3. Not validating error responses
Suites that only cover the happy path miss the failure modes that show up most often in production. Cover 400, 401, 403, 404, and 500 for every endpoint.

### 4. Asserting headers only conditionally
Cache directives, rate-limit info, content type, and CORS policy all live in headers. Check them directly on every response where they apply — a test buried inside `if (rateLimited)` may simply never run, proving nothing.

### 5. No cleanup after test data creation
Resources created during a test but never deleted pile up and pollute the database. Rely on `afterEach`/`afterAll` hooks or fixture teardown to clean up.

### 6. Treating API tests as unit tests
API tests should verify the contract as a consumer would see it — don't mock out your own database. Mocking belongs to genuine external dependencies you don't control, like payment gateways or third-party SaaS.

### 7. Ignoring idempotency
PUT and DELETE are supposed to be idempotent — verify that calling either one twice yields the same outcome.

---

## Done When

- Every target endpoint has at least a happy-path test and at least one error-path test (4xx or 5xx response validated).
- Auth flow tested as its own describe block: successful login, invalid credentials, expired token, and permission boundary (403).
- Schema validation assertions on response shape using Zod 4 or AJV — not just `toHaveProperty` spot-checks.
- Header assertions exist for at least `content-type` and any cache/rate-limit headers the API sets, asserted unconditionally.
- Contract tests in place for any endpoint consumed by a different team or service (shared schema file; for consumer-driven verification use `contract-testing`).
- Genuine third-party calls (payment gateways, external SaaS) are mocked or virtualized; the API and its database run for real.
- CI job for the suite exits 0 (green) against the test environment.

## Reference Files (in `references/`)

- **playwright-setup.md** — `playwright.config.ts`, standalone API tests, combined browser+API tests, and the authenticated `APIRequestContext` fixture.
- **schema-validation.md** — Zod 4 and AJV/JSON-Schema response validation, the schema-as-contract pattern, and Schemathesis spec-driven fuzzing.
- **test-patterns.md** — Runnable CRUD lifecycle, auth flows, error responses, response headers, pagination, file upload/download, GraphQL (+ introspection diff), webhook, and performance tests.

## Related Skills

- **contract-testing** — Consumer-driven contract verification with Pact/broker; go there when a separate team consumes your API and you need guaranteed compatibility, not just a shared schema.
- **playwright-automation** — Browser-based E2E testing, Page Object Model, and combined browser + API patterns.
- **ci-cd-integration** — Running API test suites in CI pipelines, parallelization, and environment management.
- **test-strategy** — Deciding what to test at the API layer vs. unit vs. E2E.
