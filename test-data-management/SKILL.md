---
name: test-data-management
description: >-
  Build and maintain test data through factory patterns, fixture strategies,
  PII anonymization, and synthetic data generation. Supports Fishery
  (TypeScript), FactoryBot (Ruby), and Factory Boy (Python), along with
  database seeding, teardown/cleanup approaches, and GDPR-aligned handling
  of sensitive records. Use when: "test data," "fixtures," "factories,"
  "seed data," "synthetic data," "test database," "data anonymization."
  Not for: migration/integrity testing of the DB itself — use database-testing;
  environment provisioning and database branching strategy — use test-environments.
  Related: test-environments, database-testing, api-testing, unit-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: infrastructure
---

<objective>
Build, maintain, and tear down test data so that it stays deterministic, isolated, realistic, and safe. A test suite is only as trustworthy as the data underneath it: shared mutable state produces flaky results, hardcoded placeholder values produce unrealistic ones, and unmasked production records turn "just testing" into a compliance incident. This skill covers factories, fixtures, idempotent seed scripts, anonymization pipelines, and cleanup patterns designed to hold up under parallel test execution.
</objective>

---

## Where to Look First

| If you need to... | Go here |
|-----------|-------|
| Spin up fresh entity data with per-test overrides | Factory Patterns → `references/factories.md` |
| Stub an API response or compare against a golden file | Fixture Strategies → `references/factories.md` |
| Move production-shaped data into a non-prod environment | Data Anonymization |
| Load a test DB / reference tables idempotently | Database Seeding → `references/seeding-and-synthetic.md` |
| Tear things down after tests / isolate parallel runs | Cleanup Strategies → `references/seeding-and-synthetic.md` |
| Produce edge cases and boundary values | Synthetic Data → `references/seeding-and-synthetic.md` |

---

## Questions Worth Asking First

Before settling on a test-data strategy, figure out what's already in place. If `.agents/qa-project-context.md` exists, treat it as ground truth and skip whatever it already answers.

### How data is handled today
- Where does test data come from right now — hand-built, scripted, copied from prod, or nonexistent?
- Do tests share records, or does each test build its own?
- What tears data down afterward — truncation, rollback, a human, or nothing?
- If seed scripts exist, can they safely be re-run?

### Privacy and regulatory exposure
- Does the product touch PII (names, emails, addresses, phone numbers, government IDs)?
- Are GDPR, HIPAA, PCI-DSS, or similar obligations in play?
- Does any non-prod environment ever see real production data?

### Scale and shape of the data
- Roughly how big are test datasets — tens of rows, thousands, millions?
- How tangled are the relationships — flat CRUD, deep hierarchies, polymorphic associations?
- Do multiple services need to agree on the same data (microservice data coupling)?

---

## Guiding Principles

### 1. Give every test its own data
A test that depends on data left behind by another test is a liability: change the shared row anywhere and something else breaks. The fix is for each test to create exactly what it needs, assert against that, and remove it afterward — this is also what makes parallel execution and order-independence possible.

### 2. Reach for factories before static fixtures on anything dynamic
Static JSON/YAML fixtures make sense for reference data that never changes — country lists, currency codes. For anything with a lifecycle that tests create and mutate — users, orders, products — prefer factory functions: sensible defaults out of the box, with room for each test to override the fields it cares about.

### 3. Never let raw production data into test environments
Production is the most realistic data source there is, and also the most sensitive. Copying it anywhere non-prod without anonymizing it first is a hard no — swap PII for synthetic stand-ins while keeping the underlying distributions and relationships intact.

### 4. Determinism is what makes a test reproducible
A test should produce the same outcome no matter when or where it runs. That rules out unseeded `Math.random()`, `Date.now()`, and relying on auto-increment IDs inside assertions. Reach for seeded random generation (`faker.seed(n)`), fixed timestamps, factory sequence counters, and — when you truly must assert on a UUID — a seeded `faker.string.uuid()` so the value doesn't drift between runs.

### 5. Build only as much data as the test actually exercises
Give each test the minimum it needs. A search test doesn't need a fully fleshed-out user with billing history, saved payment methods, and past orders attached. Padding out test data past what's needed buries the test's actual intent and adds upkeep cost for no benefit.

---

## Factory Patterns

A factory is a function that hands back test data with reasonable defaults, letting each test override only the fields relevant to its scenario. The defaults across ecosystems: **Fishery** (2.4.0) for TypeScript, **FactoryBot** (6.6.0) for Ruby, and **factory-boy** (3.3.3) for Python — all commonly paired with **faker** (v10.4.0) to generate realistic-looking field values.

Full working examples — Fishery with associations and deterministic UUIDs, FactoryBot's `User` and `Product` factories with `out_of_stock`/`discounted` traits, Factory Boy's `class Params` + `Trait` approach, and Playwright fixture wiring — live in `references/factories.md`. The common shape across all of them:

- **Defaults, then overrides** — `Factory.define` sets up reasonable defaults; a test overrides just the field it cares about, e.g. `userFactory.build({ role: 'admin' })`.
- **Sequence generators for fields that must be unique** — `sequence` in Fishery, `sequence(:email)` in FactoryBot, `factory.Sequence` in Factory Boy. Never hardcode an ID or email address.
- **Traits for named variants** — give recurring states a name (`:admin`, `:inactive`, `out_of_stock`, `discounted`) rather than maintaining a separate fixture file per combination.
- **Associations for related records** — one factory can build another (an order factory builds its user), so referential structure comes for free instead of being wired by hand.

### Choosing Factories vs. Static Fixtures

| Situation | Factory | Static fixture |
|----------|-----------|----------------|
| Entity data the test creates or mutates | Yes | No |
| Reference data (countries, currencies, config) | No | Yes |
| Many variations needed per test | Yes | No — leads to file sprawl |
| Complex relationships between records | Yes, via associations | No — painful to keep in sync |
| Mocked API responses | No | Yes — JSON fixtures |
| Snapshot / golden-file comparisons | No | Yes |

**Rule of thumb:** if the data gets created, changed, or deleted during the test, it belongs in a factory. If it's read-only reference material, a fixture file is the right call.

---

## Fixture Strategies

Three shapes of fixture, all detailed with code in `references/factories.md`:

- **Static fixtures (JSON/YAML)** — the right tool for API response mocks (`page.route` + `route.fulfill`), config data, and golden-file diffs.
- **Dynamic fixtures (Playwright)** — `test.extend` provisions data via the API before the test runs and tears it down after `await use(...)`. This is the standard per-test setup/teardown pattern.
- **Composed fixtures** — layer factory-built data (`userFactory.build()`, `orderFactory.buildList(3)`) inside one `test.extend` block that handles both seeding and cleanup together.

---

## Data Anonymization

Anonymize production-derived data before it touches a non-prod environment — never use it raw.

### How to mask each PII category

| Field | Approach | Example |
|-----------|---------------------|---------|
| Email | Faker-generated address, domain pattern preserved | `jane.doe@acme.com` -> `user-7291@test.example.com` |
| Full name | Faker-generated name | `Jane Doe` -> `Alice Johnson` |
| Phone number | Faker-generated, original format kept | `+1-555-123-4567` -> `+1-555-987-6543` |
| Address | Faker-generated, country/region kept | `123 Main St, NYC` -> `456 Oak Ave, NYC` |
| SSN / national ID | Fixed test pattern | `123-45-6789` -> `000-00-0001` |
| Credit card | Known test card numbers | `4111-...` -> `4242-4242-4242-4242` |
| Date of birth | Shifted by a constant offset | `1990-03-15` -> `1987-07-22` |

The full anonymization pipeline — seeded Faker for reproducibility, an in-memory lookup table, a parents-before-children write order, and a wrapping transaction — is written out in `references/seeding-and-synthetic.md` under "Anonymization with Faker.js" and "Referential Integrity During Anonymization." The key constraint: rewriting a user's email has to cascade to every table that references it (orders, comments, audit logs). Process parent rows first, dependent rows second, reusing the same lookup table, all inside a single transaction.

### GDPR checklist

- [ ] No real PII exists in any non-production environment
- [ ] Anonymization is irreversible (no lookup table mapping back to originals is stored)
- [ ] Anonymization preserves data distributions (age ranges, geographic spread) for realistic testing
- [ ] Anonymized data cannot be re-identified through combination of quasi-identifiers
- [ ] Data retention policies apply to test environments (auto-delete after N days)
- [ ] The anonymization pipeline runs automatically, not manually (eliminates human error)

---

## Database Seeding

### Making seed scripts safe to re-run

A seed script has to tolerate being run more than once without creating duplicates. Use an upsert — `INSERT ... ON CONFLICT (natural_key) DO UPDATE SET ...` — keyed on a stable business/natural key rather than the primary key. A "reset" pattern of `DELETE` followed by `INSERT` looks similar but is **not** idempotent: it strips foreign keys and reassigns serial IDs on every run. The full `INSERT ... ON CONFLICT (code) DO UPDATE` example for countries/currencies, plus the reasoning, is under "Idempotent Seed Scripts" in `references/seeding-and-synthetic.md`.

### Database branching as a DBaaS feature

When your production database sits on **Neon**, **Supabase**, or **PlanetScale**, branching can hand each PR its own isolated database instead of reseeding from zero — though the providers don't behave identically regarding data:

- **Neon Branching** — copy-on-write Postgres branches created in seconds, **including data** — well suited to ephemeral preview environments and probably the closest thing to "a real DB copy per PR."
- **Supabase Branching** — `supabase branches create pr-123` clones the schema and, optionally from a backup, the data too; the preview environment then points at that branch's URL.
- **PlanetScale Branching** — MySQL branches come **schema-only by default, with no data**, so seeding the branch is still your job. Note that PlanetScale discontinued its free Hobby tier in April 2024; MySQL now starts around $39/mo, Postgres around $5/mo.

Pair this with the Preview Environments pattern documented in `test-environments`.

> **Steer clear of: Snaplet (hosted)** — the hosted product shut down 31 Aug 2024, with the team
> moving to Supabase. `@snaplet/seed` continues as `supabase-community/seed`, a
> community-maintained fork (last meaningful release v0.98.0, July 2024, no active feature
> development since). For new work, favor the DB-branching providers above combined with
> factory-generated seed data.

### Choosing a data scope: per-test, per-suite, per-worker, or global

| Approach | Best for | Upside | Downside |
|----------|------------|------|------|
| Per-test setup/teardown | Tests that mutate data | Fully isolated, safe under parallelism | More setup code, slower |
| Per-suite seed | Read-only reference data | Simple, fast | Tests can't modify it |
| Per-worker seed | Playwright's parallel workers | Good speed/isolation tradeoff | Needs worker-scoped fixtures |
| Global seed | One-time environment bootstrap | Runs once, establishes a baseline | Must be idempotent; shared-state risk |

For the worker-scoped fixture implementation (`test.extend` with `{ scope: 'worker' }`) that drives per-worker seeding, see "Worker-Scoped Seeding" in `references/factories.md`.

### Tearing data back down

| Approach | Best for | Relative speed |
|----------|------------|-------|
| **Transaction rollback** | Unit/integration tests with a direct DB connection | Fastest |
| **Truncation** (`TRUNCATE ... CASCADE`) | Resetting tables between suites | Medium |
| **API-based cleanup** | E2E tests without direct DB access | Slowest |

Transaction rollback doesn't work for E2E tests — the application under test opens its own database connections, so a transaction held on the test side can't undo writes the app already committed. Use API-based cleanup instead, deleting in the reverse of creation order. Working code for all three approaches is in `references/seeding-and-synthetic.md` under "Cleanup Strategies."

---

## Synthetic Data Generation

Factories should make it trivial to cover edge cases and boundary conditions without writing them out by hand for every test. The reusable arrays and helper functions — `edgeCaseStrings` (empty, whitespace-padded, extremely long, XSS payload, SQL-injection payload, null/control characters, RTL override), `edgeCaseDates`, and a `boundaryValues(min, max)` helper feeding a `test.each` loop — are documented under "Synthetic Data Generation" in `references/seeding-and-synthetic.md`.

---

## Patterns to Avoid

### Shared, mutable test data
Several tests reading and writing the same underlying rows. Test A creates a user; Test B mutates it; Test C asserts against the original state and fails for reasons that have nothing to do with what it's testing. The remedy: every test builds its own data through a factory.

### Skipping anonymization on production data
Pulling the production database into staging in the name of "realistic testing" without masking it first. That's a GDPR violation, a bigger blast radius if the less-hardened environment is breached, and an open compliance liability. Always anonymize before use — or better yet, generate synthetic data that mirrors production's statistical shape.

### Data that isn't deterministic
Calling `Math.random()` or `Date.now()` when generating test data, with no seed applied. The result: a test that passes Monday and fails Tuesday because the randomly generated name happened to blow past a field length limit. Seed the Faker instance and freeze timestamps instead.

### No teardown at all
Data gets created and simply left behind. Eventually the test database bloats enough to hurt performance, or leftover rows start producing false positives elsewhere. Every piece of data created needs a matching cleanup step.

### Fixture sprawl
A dedicated JSON file for every possible test variation — `user-admin.json`, `user-inactive.json`, `user-admin-inactive.json`, and so on. A factory with traits replaces all of that. Reserve fixture files for static reference data and mocked API responses.

### Building more data than the test needs
Constructing a fully populated user object with thirty fields when the test only checks `role`. It obscures what the test is actually verifying and makes it brittle to unrelated schema changes. Factories with good defaults fix this — override only what matters.

### Hardcoded identifiers
Writing `userId: '1'` directly into a test. This ties the test to a specific database state, and breaks under parallel execution (ID collisions) or against a database that already has rows in it. Use factory sequence values or seeded UUIDs instead (see Guiding Principle 4).

---

## Verification

Confirm the data layer is deterministic, isolated, and clean of PII — cheapest checks first:

1. **Seeds are idempotent** — run the seed twice in a row and diff row counts: `psql -c "SELECT count(*) FROM countries" && <seed> && psql -c "SELECT count(*) FROM countries"` should report the same number both times and exit 0. A rising count means an `ON CONFLICT` clause is missing somewhere.
2. **No hidden shared state** — run the suite with parallelism enabled *and* in randomized order: `npx playwright test --workers=4` (or `pytest -n auto -p randomly`) should stay green. A failure that only shows up under this condition points to test ordering or shared-data coupling.
3. **Runs are reproducible** — execute the same data-generating test twice with `faker.seed(n)` set; the names, IDs, and UUIDs produced should match run to run. If they don't, look for an unseeded Faker call or a leaked `Date.now()`/`crypto.randomUUID()`.
4. **No real PII slipped in** — `grep -rE '@(gmail|outlook|yahoo)\.com|[0-9]{3}-[0-9]{2}-[0-9]{4}' tests/ fixtures/` should come back empty (that pattern catches real-looking emails and SSNs). Any hit marks a gap in the anonymization pipeline.
5. **Cleanup restores baseline** — snapshot row counts before running the suite and again after: the test database should match the original baseline with nothing orphaned.

---

## Definition of Done

- Every entity type the suite touches has a backing factory or fixture — no inline, hand-built object literals scattered through the tests for shared entities (grep the test directory to confirm none remain).
- Test data stays isolated per test — the suite passes with parallelism turned on (`--workers=N` / `pytest -n auto`) **and** with test order randomized (`--shuffle` / `-p randomly`), which rules out shared mutable state or ordering dependencies.
- Seed scripts are idempotent — running one twice in a row leaves the row count unchanged and exits 0, and CI runs it without any manual step.
- No real PII appears in test fixtures — everything sensitive is anonymized or fully synthetic (a grep for real domains / realistic SSNs turns up nothing).
- Cleanup is verified — row counts in the test database return to baseline once the suite finishes, with no orphaned rows accumulating run over run.

---

## Reference Files (in `references/`)

- **factories.md** — Complete Fishery examples (associations, deterministic UUIDs), FactoryBot's `User`/`Product` traits, Factory Boy's `Params`/`Trait` pattern, static/dynamic/composed Playwright fixtures, and the worker-scoped seeding fixture.
- **seeding-and-synthetic.md** — The idempotent `ON CONFLICT` seed script, the Faker.js anonymization and referential-integrity pipeline, all three cleanup strategies (rollback / truncate / API), and the synthetic edge-case and boundary-value generators.

## Related Skills

- **unit-testing** — the primary consumer of factory-generated data; this skill supplies the data layer beneath it.
- **api-testing** — draws on both factories (request bodies) and fixtures (mocked responses).
- **playwright-automation** — E2E tests need data seeded through the API or fixtures before browser interaction begins.
- **test-reliability** — deterministic test data removes one of the biggest sources of flaky tests.
- **test-environments** — owns environment provisioning and database-branching strategy (Neon, Supabase, PlanetScale) for preview environments; this skill owns what fills them.
- **database-testing** — covers migration testing, data-integrity assertions, and Testcontainers for the database layer itself; go there to test the database, come here to populate it.
- **ci-cd-integration** — seeding and cleanup steps need to be wired into the CI pipeline's stages.
