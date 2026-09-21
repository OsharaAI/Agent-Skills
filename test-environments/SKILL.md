---
name: test-environments
description: >-
  Plans out how testing environments should work across dev, CI, preview, staging, and
  production — covering Docker Compose test infrastructure, multi-stage Dockerfiles, the
  seed-data lifecycle, per-PR preview environments, production parity, and stubbing external
  dependencies at the HTTP boundary.
  Use when: "set up test environment," "docker-compose for tests," "per-PR preview environment,"
  "staging parity," "spin up test infra," "environment tiers."
  Not for: deciding mock vs. stub vs. fake per dependency (use service-virtualization); factory
  and fixture data patterns (use test-data-management); pipeline/Actions config (use
  ci-cd-integration).
  Related: test-data-management, ci-cd-integration, contract-testing, service-virtualization.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: infrastructure
---

<objective>
A test suite that passes against SQLite can still explode the moment it meets production
Postgres. A single shared staging box turns into a bottleneck — one bad deploy and the whole
team is stuck waiting. A Stripe call nobody stubbed turns into random CI flakiness. This skill
exists to head off exactly those failure modes: it lays out environment tiers that copy
production faithfully wherever it counts, gives each PR its own isolated environment, and
pushes external-dependency stubs out to the HTTP boundary. What comes out of it: a
`docker compose up` stack that actually works for local dev and CI, a checklist for auditing
parity, and a stubbing approach chosen per dependency type.
</objective>

## Discovery Questions

Before asking anything, look for `.agents/qa-project-context.md`. If it's there, pull answers
from it and only ask about what it doesn't already cover. Otherwise, work through:

1. **What environments already exist?** Local dev, CI, staging, preview, production — inventory what's there before deciding what's missing.
2. **Does the app run in containers already?** Look for a `Dockerfile`, `docker-compose.yml`, or `compose.yaml`. If one exists, compose and multi-stage targets are mostly already solved; if not, that's the first thing to build.
3. **Where does test data come from?** Hand-written SQL, migrations, factory libraries, or copies of production? The answer determines whether seeding is a small addition or needs to be rebuilt from scratch.
4. **How far has staging drifted from production?** Same database engine, queue, cache, auth provider, orchestration approach? Every difference is a category of bug staging simply cannot surface.
5. **What third-party APIs does the system depend on, and are any of them stubbed outside production?** Real calls to unstubbed third parties are the single biggest cause of CI flake.

---

## Core Principles

**1. Wherever bugs actually hide, staging needs to match production.** Testing against SQLite
when production runs PostgreSQL tells you nothing about how the app behaves in prod. The
database engine and its version, the queue, the cache, and the auth provider all need to line
up — these are exactly the components where environment-specific bugs originate.

**2. Short-lived environments beat ones that stick around.** A staging environment shared by
everyone becomes a chokepoint — one team member's broken deploy locks out the rest. Spinning up
a fresh, isolated environment per PR lets testing happen in parallel; save staging for the final
check before release.

**3. Seed data should be generated, not copied from production.** Snapshots of production data
bring PII along with them, plus stale references and state you can't reproduce reliably.
Generate seed data from factories instead, producing small, consistent, valid datasets.
(Factory patterns are covered in `test-data-management`.)

**4. Stub third parties at the network edge, not somewhere inside your code.** External APIs are
flaky, rate-limited, and cost money to call repeatedly. Intercept them at the HTTP layer using
something like MSW or WireMock — mocking your own internal service classes instead just hides
bugs in how your services actually integrate.

**5. Treat environment configuration as source code.** Anything that differs between
environments — URLs, feature flags, credentials, resource limits — belongs in version control
and should go through review. Setup steps that can't be reconstructed from the repo shouldn't
exist.

---

## Environment Strategy

### Environment Tiers

| Environment | Purpose | Data | External Deps | Lifecycle |
|-------------|---------|------|---------------|-----------|
| **Local dev** | Quick inner-loop iteration | Minimal seeded fixtures | Stubbed (MSW/WireMock) | Managed by each developer |
| **CI** | Automated checks | Ephemeral, seeded per run | Stubbed or containerized | Spun up and torn down per pipeline run |
| **Preview** | Per-PR review and E2E testing | Generated from factories | Stubbed or sandboxed | Spun up when PR opens, torn down when it closes |
| **Staging** | Validation before release | Anonymized, production-like | Real integrations (sandbox accounts) | Long-lived, reset on a schedule |
| **Production** | Serves real users | Real | Real | Always on |

### Getting Local Dev Running Fast

The goal here is quick feedback with nothing shared between developers. Getting the whole stack
running locally should take under two minutes:

```bash
docker compose -f docker-compose.test.yml up -d
npm run db:seed
npm run dev
```

Let Docker Compose handle infrastructure — database, cache, queue — but keep the application
itself running natively so reloads stay fast. Third-party APIs get intercepted by MSW handlers
that load automatically in dev mode.

### Continuous Integration

CI environments are entirely containerized, built fresh for every run, and discarded afterward.
The YAML below is only the **`services:`** portion of a job definition — it needs to live under
`jobs.<id>.services`, next to `runs-on` and `steps`; pasted on its own, it won't parse as a
workflow file.

```yaml
# .github/workflows/test.yml — fragment: nest under jobs.test.services
services:
  postgres:
    image: postgres:18-alpine
    env:
      POSTGRES_DB: testdb
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    ports: ['5432:5432']
    options: >-
      --health-cmd="pg_isready -U test"
      --health-interval=5s
      --health-timeout=3s
      --health-retries=5
  redis:
    image: redis:8-alpine
    ports: ['6379:6379']
    options: >-
      --health-cmd="redis-cli ping"
      --health-interval=5s
      --health-timeout=3s
      --health-retries=5
```

### Compose or Testcontainers?

Both approaches give tests real backing infrastructure; the choice comes down to who should own
the container lifecycle:

- **Docker Compose** — you declare the stack, bring it up before the test run (`docker compose
  up --wait`), and tear it down afterward, typically from a `trap`-guarded script. This fits
  local dev, a CI stack shared across the run, and E2E suites where many tests reuse the same
  services.
- **Testcontainers** (available for Node, JVM, Python, Go) — containers are started directly
  from test code and torn down automatically per test or per suite, without any compose file or
  trap script to maintain. This fits integration tests wanting their own private,
  programmatically-controlled infrastructure — e.g., a fresh Postgres instance per test class.
  As of 2026 this is the standard choice for infrastructure owned by the test itself, and it
  beats hand-rolled compose-plus-trap setups in most cases.

Use Compose when the stack is shared across people and many tests; reach for Testcontainers when
each test or suite should get its own throwaway copy.

### Per-PR Preview Environments

Give every pull request its own environment so reviewers can click through and exercise the
actual change without stepping on other PRs in flight.

Hosting choices as of 2026, matched to your stack:

- **Vercel** preview deployments — a natural fit for Next.js, static, or serverless apps; each PR gets a URL automatically.
- **Cloudflare Pages** previews — git-integrated with a generous free tier.
- **Render** or **Railway** preview environments — cover the full stack, databases included.
- **Northflank**, **Qovery**, **Bunnyshell**, **Uffizzi** — Kubernetes-backed ephemeral-environment
  platforms for when a preview needs the entire stack, not just a frontend.

Pair each preview's lifecycle with a **database branch** (the model used by Neon, Supabase, and
similar PlanetScale-style tools): open a branch when the PR opens, drop it when the PR closes.
That gets every preview a cheap, instant, isolated copy of the database instead of sharing one
staging DB across PRs. (More on this in `test-data-management`.)

To keep local dev in step with CI:

- **Devcontainers** (`.devcontainer/devcontainer.json`) — works across VS Code, Codespaces, and
  JetBrains; the go-to for giving every developer an identical Docker-backed environment.
- **Tilt** (`Tiltfile`) — built for Kubernetes-first local development, with hot reload and
  orchestration across multiple services. Reach for this when staging itself runs on K8s.

Hooking E2E tests up to a generated preview URL takes only a few lines:

```yaml
- name: Run E2E against preview
  env:
    BASE_URL: ${{ steps.deploy.outputs.preview-url }}
  run: npx playwright test --project=chromium
```

A self-hosted Docker preview, namespaced per PR and torn down automatically on close, looks like
this:

```yaml
- name: Deploy preview
  run: |
    NAMESPACE="pr-${{ github.event.number }}"
    docker compose -f docker-compose.preview.yml -p "$NAMESPACE" up -d
    echo "preview-url=https://${NAMESPACE}.preview.example.com" >> "$GITHUB_OUTPUT"

- name: Teardown preview
  if: github.event.action == 'closed'
  run: |
    NAMESPACE="pr-${{ github.event.number }}"
    docker compose -p "$NAMESPACE" down -v
```

### Staging

Staging stays up long-term and should mirror production's infrastructure. Reset it on a
schedule — weekly, or on demand — to keep it from drifting:

```bash
#!/bin/bash
# scripts/reset-staging.sh
set -euo pipefail

echo "Resetting staging database..."
psql "$STAGING_DATABASE_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

echo "Running migrations..."   # migrations MUST recreate extensions + grants (see caveat below)
npm run db:migrate -- --env staging

echo "Seeding anonymized data..."
npm run db:seed -- --env staging --dataset production-anonymized

echo "Verifying staging health..."
curl -sf https://staging.example.com/health || exit 1
echo "Staging reset complete."
```

**Watch out:** running `DROP SCHEMA public CASCADE` wipes out the schema's default privileges
along with any installed extensions (`uuid-ossp`, `pgcrypto`, and so on). Your migration
pipeline needs to put those back (`CREATE EXTENSION IF NOT EXISTS …`, re-granting defaults), or
the migration step will fail. A plain `CREATE SCHEMA public` does not restore the grants that
were there before — don't assume it does.

---

## Setting Up Docker Compose for Tests

A solid `docker-compose.test.yml` brings up the whole stack — app, Postgres, Redis, a seed
container that runs once, and Mailpit — for integration and E2E testing. Two things are easy to
get wrong:

- **`depends_on` needs a health check to actually gate startup.** Leave out `healthcheck` and
  `condition: service_healthy`, and `depends_on` only confirms the container *started* — not
  that the service inside is ready to accept connections. Tests end up racing the database and
  failing with connection errors.
- **The seed step should be a one-shot container, not a persistent service.** Give it
  `depends_on: condition: service_completed_successfully` so the app only starts once seeding
  *exits successfully*. Modeling seeding as a long-running service instead creates a race where
  the app can boot before seeding finishes.

See `references/docker-compose.md` for the full `docker-compose.test.yml`, the `trap`-guarded
integration test runner, the multi-stage Dockerfile (including the `production` target), and
the MinIO block.

### Multi-Stage Dockerfile

A single `base` layer installs dependencies once, and `development`, `test`, and `seed` all
build on it; a lean `production` stage then installs only production dependencies (`npm ci
--omit=dev`), pulling its build artifacts from the `test` stage. This separation keeps
test-only dependencies and source out of the image that ships, while each environment still
gets its own entrypoint. In `base`, use `npm ci --include=dev` — that's the current flag;
`--production=false` is the old `--omit`/`--include` syntax. The complete Dockerfile lives in
`references/docker-compose.md`.

---

## External Dependency Management

### Stubbing Strategy by Dependency Type

| Dependency Type | Local/CI Approach | Staging Approach |
|----------------|-------------------|------------------|
| Payment (Stripe) | MSW handler returns mock responses | Stripe test mode using `sk_test_` keys |
| Email (SendGrid) | **Mailpit** captures outgoing SMTP (web UI at :8025, SMTP at :1025) | SendGrid sandbox mode |
| Auth (Auth0) | Local JWT issuer signing with test keys | Auth0 dev tenant |
| Storage (S3) | MinIO container (S3-compatible) | Dedicated test bucket with a lifecycle policy |
| Search (Elasticsearch) | Testcontainers-managed Elasticsearch | Dedicated test index with a reset script |
| SMS (Twilio) | MSW handler | Twilio test credentials |

**Skip MailHog** — it hasn't been maintained since its last release in 2020. Mailpit
(`axllent/mailpit`) is a drop-in replacement on the same ports (1025 for SMTP, 8025 for the UI).

### Using MSW for HTTP-Level Stubs

Intercept external API calls at the HTTP boundary with MSW 2.x — import `http` and
`HttpResponse` from `msw`, and `setupServer` from `msw/node`, wiring the lifecycle through
`beforeAll`/`afterEach`/`afterAll`. Configure `onUnhandledRequest: "error"` so any call that
isn't mocked fails the test explicitly instead of quietly reaching the real network. The
Stripe, SendGrid, and geocoding handlers, plus the full server lifecycle, are in
`references/stubbing.md`.

### Substituting MinIO for S3

Run S3-compatible storage in a container rather than calling real AWS from local or CI tests.
Point the AWS SDK's `S3Client` at it using `endpoint`, credentials from environment variables,
and `forcePathStyle: true` (MinIO requires this). The compose service definition and client
setup are both in `references/docker-compose.md`.

### Keeping Stubs Honest with Contract Tests

Stubs can drift out of sync with what the real API actually does. Back every stub with a
contract test confirming it still matches the real API's shape — see `contract-testing` for
how.

---

## Checklist: Auditing Environment Parity

Work through this whenever you're setting up or reviewing a non-production environment.

| Dimension | Ask | Warning Sign |
|-----------|----------|----------|
| **Database engine** | Same engine and version as production? | SQLite in test, PostgreSQL in prod |
| **Database schema** | Same migration pipeline used to build it? | Schema changed by hand in staging |
| **Data shape** | Does seed data cover every entity state? | Only happy-path records, nothing edge-case |
| **Infrastructure** | Same container orchestration approach? | Docker Compose in CI, Kubernetes in prod |
| **Network** | Same service topology internally? | Monolith in test, microservices in prod |
| **Config** | Are env vars documented and version-controlled? | Undocumented vars, manual setup steps |
| **Auth** | Same provider and flow as production? | Auth bypassed in test via hardcoded tokens |
| **Feature flags** | Same evaluation engine? | Hardcoded flags in test vs. LaunchDarkly in prod |
| **TLS/HTTPS** | Same certificate handling? | HTTP in staging, HTTPS in prod |
| **Timeouts/Limits** | Same rate limits, connection pools, timeouts? | Unlimited timeouts in test masking perf problems |

Factory-based approaches to seed data are covered in `test-data-management`.

---

## Anti-Patterns to Avoid

**Relying on one shared staging environment as your only test environment.** A single bad
deploy from one person locks out everyone else. Give each PR its own ephemeral environment for
isolated testing, and reserve staging for the last check before release.

**Seeding tests from copies of the production database.** This carries PII risk, produces state
you can't reproduce, and drags down test speed with oversized datasets. Generate small,
deterministic seed data from factories instead.

**Branching application code based on the environment.** Something like `if
(process.env.NODE_ENV === "test") { skipAuth(); }` means the real auth flow is never actually
tested. Swap implementations through dependency injection or configuration, not conditionals
scattered through the code.

**Setting up environments by hand.** A setup process that requires a 15-step wiki page will be
stale within a week. Everything should be scriptable down to `docker compose up -d && npm run
db:seed`.

**Stubbing internal code instead of external calls.** The stub boundary belongs at the edge
where your system talks to the outside world. Mocking your own internal modules instead just
conceals bugs in how your services actually work together.

**Skipping health checks in Docker Compose.** A `depends_on` without a health check only
confirms the container started, not that the service is ready — tests end up racing the
database and hitting connection errors.

**Letting preview environments live indefinitely.** Previews still running after their PR
merges waste resources and accumulate stale state. Wire up automatic teardown on close
(`if: github.event.action == 'closed'`).

---

## Verifying the Setup

Check these against whatever you build, starting with the cheapest check:

1. **The compose file parses.** `docker compose -f docker-compose.test.yml config -q` should
   exit 0 — this catches YAML and schema mistakes before any image gets pulled.
2. **The stack comes up and stays healthy.** `docker compose -f docker-compose.test.yml up -d
   --wait --wait-timeout 60` should exit 0; a nonzero exit means some health check never turned
   green.
3. **The database is actually reachable.** `docker compose exec postgres pg_isready -U test -d
   testdb` should report `accepting connections`.
4. **The Dockerfile's production target builds cleanly.** `docker build --target production -t
   app:prod .` should succeed, and `docker run --rm app:prod npm ls --omit=dev --depth=0`
   should show zero dev dependencies.
5. **Stubs fail loudly when bypassed.** Run the suite with `onUnhandledRequest: "error"` set —
   any real outbound call should error the test rather than pass silently.

---

## Definition of Done

- Every tier (dev, CI, preview, staging, production) is documented with its characteristics and how to access it.
- `docker compose -f docker-compose.test.yml config -q` exits 0, and `docker compose up -d --wait` brings every service to a healthy state (exit 0).
- The multi-stage Dockerfile's `production` target builds with `--omit=dev`, so the shipped image carries no dev dependencies.
- Seed scripts are idempotent — running them twice exits 0 with no duplicate-key errors — and live in the repository.
- External dependencies are stubbed at the HTTP boundary with `onUnhandledRequest: "error"` set, and no real third-party credentials appear outside production.
- Gaps in environment parity (e.g. SQLite in CI vs. PostgreSQL in prod) are written down, with either a mitigation in place or a tracked issue.
- Preview environments spin up automatically for PRs and tear down automatically on close (`if: github.event.action == 'closed'`).

---

## What's in `references/`

- **docker-compose.md** — the complete `docker-compose.test.yml` (Postgres 18, Redis 8, a one-shot seed container, Mailpit), the `trap`-guarded integration test runner, the multi-stage Dockerfile (base/development/test/seed/production), and the MinIO service plus S3 client configuration.
- **stubbing.md** — MSW 2.x handlers for Stripe, SendGrid, and geocoding, along with the `setupServer` lifecycle configured with `onUnhandledRequest: "error"`.

---

## Related Skills

- **service-virtualization** — helps decide mock vs. stub vs. fake vs. real per dependency, and covers WireMock/MSW in more depth. Use it to *choose* the stubbing approach; this skill handles wiring that choice into the environment.
- **test-data-management** — factory patterns, synthetic data generation, database seeding, and DB branching (Neon/Supabase/PlanetScale) for giving each PR its own database copy.
- **ci-cd-integration** — pipeline configuration, GitHub Actions services, artifact handling, sharding, and self-hosted runners. Covers the workflow surrounding this skill's environments; this skill defines the services that workflow runs against.
- **contract-testing** — consumer-driven contracts that confirm your stubs actually match real APIs.
