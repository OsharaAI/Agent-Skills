---
name: contract-testing
description: >-
  Implement consumer-driven contract testing with Pact-JS (v16). Covers consumer test
  writing, broker-driven provider verification, Pact Broker setup, can-i-deploy as a
  deployment gate, webhook-triggered verification, pending pacts, and schema-first vs
  consumer-first approaches (OpenAPI/Ajv, Schemathesis).
  Use when: "contract test," "Pact," "consumer-driven," "API contract," "provider
  verification," "can-i-deploy."
  Not for: stubbing or mocking a dependency to isolate a test — use service-virtualization;
  general REST/GraphQL endpoint assertions against your own API — use api-testing.
  Related: api-testing, service-virtualization, ci-cd-integration, test-environments.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: infrastructure
---

<objective>
Imagine a provider quietly renames a field in its response payload. Each side's own unit
suite stays green, and nobody notices the mismatch until the consumer's frontend breaks in
production. Contract testing is what stops that from happening: it moves the failure into
CI, where the consumer states precisely what it expects, the provider proves it can produce
it, and `can-i-deploy` refuses to let a deploy through until the broker has confirmed both
sides agree. Applying this skill yields Pact consumer tests, a broker-backed provider
verification job, and the deploy gate that links the two — enough for services to ship on
independent schedules without ever needing a shared integration environment.
</objective>

## Discovery Questions

Look for `.agents/qa-project-context.md` first. If it's there, treat it as already answered and don't re-ask what it covers. Otherwise work through:

1. **Architecture:** Is this microservices, a monolith with separate consumers (mobile/SPA), or a BFF pattern? Independent deploy cadence is where contract testing pays off most.
2. **Contract ownership:** Consumer-driven (consumers state what they need) or provider-driven (the provider hands down a spec)? Consumer-driven tends to serve most teams better.
3. **Versioning scheme:** URL-based (`/v1/`, `/v2/`), header-based, or nothing formal? Contracts need to account for however version negotiation actually works.
4. **Scale of the pairing problem:** How many consumer-provider relationships exist? Pick the highest-traffic or flakiest integration first — don't attempt full coverage on day one.
5. **Existing specs:** Does an OpenAPI/Swagger document already exist? If so, a schema-first contract (or Schemathesis) may be the faster starting point.
6. **Transport:** HTTP request/response, or async messaging? The HTTP examples in this skill cover the former; queue/topic integrations (Kafka, SNS/SQS) call for Pact message contracts instead — see Pact-JS Setup.

## Core Principles

**1. Consumers state their needs; providers prove they can meet them.** A consumer test says, in effect, "calling `GET /users/123` should return `{ id, name, email }`." The provider then runs that same test against its actual implementation — if it can't satisfy it, the build fails before anything ships.

**2. Truth lives in the broker, nowhere else.** Not a wiki page, not a Slack thread, not "deploy it and watch what happens." Pacts and their verification outcomes are stored in the Pact Broker, and provider verification must pull from it (`pactBrokerUrl` + `consumerVersionSelectors`) rather than from local pact files, since only the broker knows which consumer versions are actually deployed.

**3. Contracts substitute for shared environments, not for integration tests.** Multi-step workflow testing still needs real integration tests. What contract testing removes is the need to stand up consumer and provider together just to check that the interface lines up.

**4. A violated contract must fail the build.** A contract check that merely logs a warning and lets the pipeline proceed is worthless — contracts only matter as hard deployment gates.

**5. Contracts check shape, not behavior.** The consumer side confirms response structure and status codes; the provider side confirms it can produce them. Actual business logic stays in unit and integration tests.

## Pact-JS Setup

Add `@pact-foundation/pact` as a dev dependency to both the consumer and the provider codebases. Two halves make up the workflow:

- **Consumer test:** states what the consumer expects back from the provider (request plus expected response shape). Running it emits `pacts/<consumer>-<provider>.json`, the actual contract artifact. Reach for `Matchers` (`Matchers.like`, `Matchers.eachLike`, `Matchers.integer`, `Matchers.string`, `Matchers.regex`) so the contract checks types and formats instead of locking in brittle literal values.
- **Provider verification:** replays the consumer's pact against the provider's **real** implementation (never a mock), using `stateHandlers` to prepare whatever data each `given(...)` clause requires, then reports the outcome back to the broker.

> **Pact-JS v16 (current as of June 2026) renamed `PactV4` to `Pact` and `MatchersV3` to `Matchers`.** Those older names are gone as of v16, so update imports if you're working from an older blog post or example — the underlying behavior hasn't changed.

The same `Pact` class also handles **message pacts** for event-driven systems (Kafka, SNS/SQS, RabbitMQ): the consumer describes the message shape it expects, and the provider verifies what its producer actually emits.

`references/pact-js-setup.md` has the install commands, a consumer test walking through a single user, a 404, and a paginated list, the broker-driven provider verification spec (state handlers, pending pacts included), the Pact Broker Docker Compose file, and a pointer to message contracts.

## Pact Broker

The Pact Broker is the central registry: pact files land there, and so do the results of provider verification. It's what makes `can-i-deploy` possible. Run it locally via Docker Compose on top of Postgres, and have consumer CI publish pacts to it tagged with commit SHA and branch.

**Every credential must come from the environment** — the Postgres password, the broker's DB URL, the basic-auth password. Any of these hardcoded into the compose file is a secret leaked into version control. Also pin the broker image to a specific released tag rather than `:latest`.

The Docker Compose file and the `pact-broker publish` invocation are in `references/pact-js-setup.md`.

## Consumer-Driven Workflow

The full lifecycle looks like this:

```
1. Consumer writes contract test
   └── Generates pact JSON file

2. Consumer CI publishes pact to broker
   └── Broker stores pact tagged with consumer version + branch

3. Broker webhook triggers provider verification
   └── Provider CI pulls latest pact, runs verification

4. Provider publishes verification result to broker
   └── Broker records: "provider v2.3.1 satisfies consumer v1.5.0"

5. Before deploy: can-i-deploy check
   └── "Can consumer v1.5.0 be deployed? Yes, provider v2.3.1 is in production and verified."
```

Each pipeline — consumer and provider — runs its own contract tests, reports to the broker, and blocks deployment behind `can-i-deploy`. The provider pipeline additionally watches for a `repository_dispatch` event, so a freshly published pact kicks off verification without anyone triggering it by hand.

The consumer CI workflow, the provider CI workflow (Postgres service plus migrations included), and the standalone `can-i-deploy` / `record-deployment` invocations are documented in `references/ci-pipelines.md`.

### Pact Broker Webhooks

Set up a webhook on the Pact Broker so that a newly published pact fires a `repository_dispatch` and kicks off provider verification automatically. Concretely, the webhook issues a `POST` to `https://api.github.com/repos/myorg/user-service/dispatches` with event type `pact-changed`, and the provider pipeline listens for that exact trigger (see the `repository_dispatch` block in `references/ci-pipelines.md`).

### Pending Pacts (Incremental Adoption)

Turning on `enablePending: true` (together with `includeWipPactsSince`) in the provider's `Verifier` lets a brand-new consumer interaction show up without instantly breaking the provider's build — it gets surfaced as a report but doesn't fail the build until the consumer explicitly marks it as expected. This is the go-to safety net for rolling contracts out gradually rather than all at once.

## Schema-First vs Consumer-First

### Consumer-First (Pact)

Here the consumers dictate what they actually need, and the contract grows out of genuine usage rather than upfront design.

**Fits well when:** different clients have genuinely different needs (a mobile app may need far fewer fields than the web client), the API evolves organically, or the ecosystem is made up of many microservices.

### Schema-First (OpenAPI + Validation)

Here the provider ships an OpenAPI spec first, and consumers check their own usage against it.

**Fits well when:** the API is public-facing with many consumers, it was designed up front before any code was written, or the organization has strong governance over API design.

> Note that OpenAPI 3.0 isn't plain JSON Schema — it uses things like `nullable: true` that a vanilla Ajv instance (which defaults to the 2020-12 draft) will mis-validate. Point Ajv at the OpenAPI dialect and pair it with `ajv-formats`, or reach for a validator built specifically for OpenAPI. The Ajv configuration and a helper that validates a response against the spec live in `references/schema-first.md`.

### Hybrid Approach

Treat OpenAPI as the design document and Pact as the thing that actually enforces it.

1. The provider team leads the design of the API, expressed as an OpenAPI spec.
2. Baseline Pact consumer tests are generated straight from that spec.
3. Individual consumers layer on additional interactions beyond that baseline.
4. The provider verifies against the Pact contracts, which end up being a subset of the full OpenAPI surface.

### Bi-Directional Contracts (PactFlow / SmartBear)

PactFlow, a SmartBear product, offers a bi-directional model that avoids coupling consumer pacts directly to provider verification runs: the provider hands over an OpenAPI spec, the consumer hands over a pact, and PactFlow determines compatibility between the two without the provider ever running a pact verifier. This is a paid feature outside Pact OSS, and it's worth reaching for when:

- The provider team either can't or won't wire a Pact verifier into their pipeline.
- An OpenAPI spec is already the provider's canonical source of truth.
- You want some level of contract coverage without binding the two repos together tightly.

The catch: bi-directional checks are less precise than a full pact verification run — they confirm overlap between spec and contract rather than exact runtime behavior. Treat it as a stepping stone toward full verification once both teams are on board.

### Schemathesis (Property-Based, Spec-Driven)

If a project is OpenAPI-first, **Schemathesis (v4.x)** can run property-based tests straight from the spec against a live API — throwing large volumes of both valid and invalid requests at it and checking that responses stay conformant. It surfaces a different category of bug than Pact does (encoding issues, odd edge-case payloads, status codes drifting). The two complement each other well: Pact handles consumer-driven *interactions*, Schemathesis handles spec-driven *coverage*. For CI, favor the `schemathesis/action@v3` Action over a bare shell command.

> **Don't use `schemathesis run --base-url ... --hypothesis-deadline=2000` — that's Schemathesis ≤ v3 syntax, and it's been dead since v4.0 (2025-06).** v4 dropped `--hypothesis-deadline` altogether and renamed `--base-url` to `--url`, plus the schema itself is now a positional argument. The current invocation looks like: `schemathesis run ./openapi.yaml --url <base> --checks all`. Details in `references/schema-first.md`.

## can-i-deploy

`can-i-deploy` is the deployment gate itself. It queries the Pact Broker's compatibility matrix to answer one question: given everything the broker currently knows, is this specific version safe to put into the target environment? Once a deploy succeeds, follow up with `record-deployment` to keep that matrix accurate.

Always include `--retry-while-unknown <n> --retry-interval <s>`. This handles the single most frequent real-world failure mode: the consumer just published a pact moments ago and the provider hasn't finished verifying it — without the retry flags, the gate fails outright on that race instead of waiting for the result to show up.

**Do not deploy without a passing `can-i-deploy` result, and never bypass it on `main`.** Since `main` is what ends up in production, skipping the gate there means shipping a version the broker never confirmed as compatible — precisely the failure mode contract testing exists to prevent.

The `can-i-deploy` and `record-deployment` invocations, annotated with sample output and the retry flags, are in `references/ci-pipelines.md`.

## Anti-Patterns

**Letting business logic creep into contracts.** Contracts should stay narrow: status codes, whether fields are present, their types, their formats. Business rules belong elsewhere, in unit and integration tests.

**Writing contracts without any consumer input.** A provider team that defines contracts unilaterally ends up testing its own assumptions about what consumers need, not what they actually use. Genuine consumer-driven contracts catch the integration failures that matter.

**Glossing over provider states.** A consumer expecting `given("user 123 exists")`, verified against an empty database, produces a meaningless pass. Provider state handlers need to actually construct the scenario the consumer assumed.

**Verifying against local pact files in production pipelines.** `pactUrls` verification only sees whatever pact happens to be on disk, not what's actually running. Pull from the broker instead, via `pactBrokerUrl` + `consumerVersionSelectors`, so verification reflects live consumer versions.

**Publishing pacts from a developer's laptop.** Pacts should only be published from CI, tied to a known commit SHA and branch. Local publishes create versions nobody can trace, and they pollute the broker.

**Brushing off a failing `can-i-deploy`.** A "no" means either fix the violation or go negotiate the change with the consumer team — deploying regardless breaks production.

**Cramming every endpoint into one giant pact.** Focus first on the critical integration points, and grow the contract incrementally (leaning on pending pacts) as real failures justify expansion. A pact with 500 interactions in it is nobody's idea of maintainable.

**Letting stale pacts pile up.** Configure the broker to purge pact versions older than 90 days that aren't deployed anywhere. Leftover stale pacts slow down verification and muddy the compatibility matrix.

## Verification

Confirm things work, starting from the smallest check and working outward:

1. **The consumer test actually produces a pact.** Run `npm run test:contract` and check that `pacts/<consumer>-<provider>.json` exists and contains the interactions you wrote. No file means no contract exists yet.
2. **Provider verification passes for real.** Run `npm run test:contract:provider` against a live test database — every interaction from the consumer side needs to verify against the running provider itself, not a stand-in mock.
3. **The broker round-trips correctly.** Publish with `pact-broker publish ./pacts --consumer-app-version=$GIT_COMMIT --branch=$GIT_BRANCH` and check the broker UI shows both the pact and its recorded verification result.
4. **The deployment gate actually gates.** Run `pact-broker can-i-deploy --pacticipant=<name> --version=<sha> --to-environment=production --dry-run` and confirm you get back a firm yes or no — not "unknown" — for a version known to be good.

## Done When

- Consumer pact tests run in CI, producing and publishing a `pacts/*.json` file on every run, tagged with commit SHA and branch.
- Provider verification runs in CI both on provider code changes and whenever a new pact is published (triggered via the Pact Broker's `repository_dispatch` webhook), always pulling pacts from the broker rather than local files.
- `can-i-deploy`, invoked with `--retry-while-unknown`, gates deployment on `main` in both the consumer and provider pipelines, and fails the job outright on a broken contract.
- Some form of `CONTRACTS.md` (or an equivalent `CODEOWNERS` entry) names an owner or reviewer for each consumer-provider interaction.
- At least one breaking-change scenario has actually been exercised end-to-end and shown to be caught by `can-i-deploy` before it could reach production.

## Reference Files (in `references/`)

- **pact-js-setup.md** — Install commands, a consumer pact test (single user, 404 case, pagination), broker-driven provider verification with state handlers and pending pacts, a message-contract pointer, and the Pact Broker Docker Compose plus publish command.
- **ci-pipelines.md** — Consumer and provider GitHub Actions workflows, along with the standalone `can-i-deploy` (retry flags included) and `record-deployment` commands.
- **schema-first.md** — The OpenAPI-against-Ajv response validation helper (with the 3.0 dialect caveat spelled out) plus the Schemathesis v4 command and Action.

## Related Skills

- **api-testing** — For asserting your own REST/GraphQL endpoints (shape, status, auth, headers). Use that skill for general endpoint testing; come back here once a separate team consumes your API and needs guaranteed compatibility rather than just a shared schema.
- **service-virtualization** — For stubbing or mocking a dependency to isolate a test. Use that skill to swap in a fake service; use this one to prove two real services actually agree on their interface — contracts verify compatibility, virtualization only simulates it.
- **ci-cd-integration** — Covers the pipeline mechanics: running these contract jobs as gates, managing secrets, parallelizing jobs. Go there for the plumbing that this skill's deployment gate plugs into.
- **test-environments** — Covers environment strategy: where contract verification should run and how the broker gets provisioned across staging and production.
