---
name: database-testing
description: >-
  Confirms database integrity, exercises migrations in both the forward and backward
  direction, checks schema constraints hold, keeps seed data under control, flags
  migration drift, and surfaces query-performance regressions. Spans PostgreSQL, MySQL,
  and MongoDB, across Prisma, TypeORM, Drizzle, and SQLAlchemy, with Testcontainers-based
  test databases.
  Use when: "database test," "migration test," "migration rollback," "rollback test,"
  "data integrity," "SQL test," "schema validation," "seed data," "query performance,"
  "Testcontainers."
  Not for: large-scale synthetic data generation or masking — that's test-data-management;
  Docker/IaC provisioning of test environments — that's test-environments; SQL injection — that's security-testing.
  Related: test-data-management, test-environments, security-testing, ci-cd-integration.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: specialized
---

<objective>
Green checkmarks lie in two specific ways: `prisma migrate deploy` can complete successfully while quietly wiping out a column's contents, and an `EXPLAIN` check that's structurally incapable of failing will happily approve a query that just lost its index. Neither mistake shows up until production. This skill builds the tests that would have caught them — migrations verified in both directions, constraints proven to reject bad rows, seed data that never varies between runs, drift checks, and query-plan assertions that are demonstrably capable of turning red.

**Before starting:** look for `.agents/qa-project-context.md` — it should already record the database engine, ORM, migration tooling, and environment setup that everything below depends on.
</objective>

---

## Discovery Questions

Start with `.agents/qa-project-context.md`; anything it already answers, skip. Otherwise work through:

1. **Which database?** PostgreSQL, MySQL, SQLite, MongoDB, something mixed? Constraint syntax, available migration tools, and how you'd profile performance all diverge by engine.
2. **Which ORM or query layer?** Prisma, TypeORM, Drizzle, Sequelize, SQLAlchemy, Django ORM, hand-written SQL — this decides both the migration tooling and the shape of the tests.
3. **Which migration runner?** Prisma Migrate, TypeORM migrations, Flyway, Liquibase, Alembic, knex, something custom — this is what determines how forward/backward testing actually works.
4. **How is test-database state handled?** A fresh DB per test, transaction rollback, Testcontainers, or a shared instance that gets cleaned up afterward? This trades off speed against reliability.
5. **What seed data already exists?** Look for factories, fixtures, or scripts — `prisma/seed.ts`, a `seeds/` folder, `fixtures/`, established factory conventions.
6. **Is there any performance baseline already?** Existing benchmarks, slow-query logs, monitoring dashboards worth building on.

---

## Core Principles

1. **Every migration needs both directions tested.** A migration you can't reverse is a migration you can't safely deploy — if rollback breaks, a bad release becomes unrecoverable. Exercise the actual `down` mechanism (Prisma's hand-maintained `down.sql`, or whatever native revert command the ORM ships), never a status flag pretending to be a rollback.

2. **Constraints are your database-level safety net.** `NOT NULL`, `UNIQUE`, `FOREIGN KEY`, `CHECK` — these stop garbage data regardless of what the application layer does or forgets to do. Verify each one is actually present and actually rejects the bad input with the expected error.

3. **Seed data has to be boring and repeatable.** Same inputs, same outputs, every single run. Fixed IDs, fixed timestamps, factories instead of randomness — unseeded `faker.random()`, bare `uuid()`, and `now()` inside seed data all produce tests that pass sometimes and fail other times for no reason.

4. **Don't let tests share database state.** Order-dependence is how flaky suites are born. Reach for transaction rollback, a dedicated database per test, or rigorous cleanup.

5. **Exercise real migrations, not the ORM's auto-sync.** `prisma db push` and `typeorm synchronize: true` bypass the exact path production deploys will take. Run the actual migration files.

6. **An assertion incapable of failing tells you nothing.** Before trusting a green EXPLAIN check, deliberately break the thing it's supposed to catch (drop the index) and confirm it goes red. Details under Verification.

---

## Migration Testing

Runnable examples for everything in this section live in `references/migration-tests.md`.

### Validating the Forward Path

Start from an empty database, run every migration via `prisma migrate deploy`, then query `information_schema` to confirm the tables and columns that should exist do, with correct types, nullability, and defaults. A Testcontainers-supplied `DATABASE_URL` is the preferred setup; falling back to an admin `Pool` running `CREATE DATABASE` against a long-lived Postgres instance is acceptable when Testcontainers isn't an option — but commit to one approach per suite rather than mixing them.

### Testing Rollbacks

Prisma simply doesn't have a `migrate down` or `migrate rollback` command. Don't reach for `prisma migrate resolve --rolled-back` as a substitute — that command exists to fix a migration whose `migrate deploy` run *failed midway*, and it throws an error if you point it at something that applied cleanly. The correct test shape: apply the migration, snapshot the resulting state, execute the hand-authored `down.sql` for that migration directly through `psql -f down.sql`, confirm the reverted object no longer exists, then reapply forward. This means every migration directory needs its own `down.sql` checked in.

TypeORM and Sequelize don't have this problem — both ship a real revert command (`dataSource.undoLastMigration()` for TypeORM, `sequelize-cli db:migrate:undo` for Sequelize). Drop either in wherever the `psql -f down.sql` step would go; the surrounding capture → revert → verify → reapply structure doesn't change.

Drizzle sits in an awkward spot: Drizzle Kit's v1 line was still in beta as of mid-2026 (`drizzle-kit@1.0.0-beta.22` at last check, no GA release yet — pin to `0.44.x` if you'd rather stay on stable). The workflow is `drizzle-kit generate` followed by `drizzle-kit migrate`, and you should pin an exact version in CI since the v1 betas have been reworking the `casing` API and dropped Postgres's RQB v1 `._query`, with more churn likely before GA. Drizzle also has no down-migration generator at all, so — same as Prisma — you write and check in your own inverse SQL by hand.

### Confirming Data Survives a Migration

To verify that adding a column doesn't destroy existing rows: bring the schema up to migration N-1, insert some rows, apply migration N, and check the rows are still there (with the new nullable column populated by its default, or null). Watch out — `prisma migrate deploy` has no concept of a `--to` target; it always runs every pending migration. The workaround for stopping at N-1 is to point Prisma at a migrations folder that's been staged (in CI) to contain only the first N-1 migrations, verify, then swap in the complete directory and deploy again. Tools that do support real version targeting — Flyway's `-target=`, Alembic's `upgrade <rev>` — should just use that flag directly instead of this workaround.

### Catching Migration Drift

The single most common real-world migration bug: someone modifies the database or the schema file directly, and now the checked-in migration history no longer produces `schema.prisma` if replayed from scratch. `prisma migrate diff --from-migrations … --to-schema-datamodel … --exit-code` exits non-zero the moment it detects that gap — treat it as a cheap pre-flight check that runs in CI before any of the heavier tests. Full example in `references/migration-tests.md`.

### Comparing Schema Snapshots

Take a `pg_dump --schema-only` dump immediately before and after running the migration, then diff them table-by-table to confirm only the tables you meant to touch actually changed. See `references/migration-tests.md` for the code.

### Notes for Other ORMs

**TypeORM:** configure the `DataSource` with `migrationsRun: false`, then drive `dataSource.runMigrations()` and `dataSource.undoLastMigration()` explicitly from within tests. The pattern is the same one used elsewhere: apply everything, check the schema, revert the last migration, check the schema reverted correctly.

**Alembic (Python):** run `alembic upgrade head` starting from an empty database, `alembic downgrade base` to confirm a full rollback works, and an upgrade → downgrade → upgrade cycle to make sure the schema comes back consistent. Provision the test database through a fixture so each run starts clean.

---

## Data Integrity Testing

Runnable constraint and referential-integrity examples are in `references/integrity-and-seed.md`.

### Testing Constraints

Every constraint needs a test proving it actually rejects the input it's supposed to: `NOT NULL` should reject a missing required column, `UNIQUE` a duplicate value, `FOREIGN KEY` a dangling reference, `CHECK` an out-of-range value, and `ON DELETE CASCADE` should remove the dependent rows it's meant to. Match against the actual database error text (`/null value in column/`, `/unique constraint/i`, and so on) at the `pool.query` layer — checking at the ORM or application-validation layer instead can hide the fact that the database-level constraint was never created.

### Referential Integrity and a Data-Quality Pass

Anti-join queries (`LEFT JOIN … WHERE parent.id IS NULL`) catch orphaned rows pointing at parents that no longer exist. Beyond that, run an audit for the gap between what integrity you *intended* to enforce and what's *actually* enforced: comparing `COUNT(*)` against `COUNT(DISTINCT col)` surfaces a column that behaves as unique in practice but has no actual constraint backing it up; `COUNT(*) FILTER (WHERE col IS NULL)` surfaces one that's effectively always populated but isn't declared `NOT NULL`. Examples in `references/integrity-and-seed.md`.

### Validating Data Types

Worth checking explicitly: monetary amounts keep exact precision (no floating-point drift), `VARCHAR` columns reject overflow with a `value too long` error, and timestamps normalize to UTC regardless of the offset they came in with — insert a value with a `+02:00` offset, read it back, and confirm the output is UTC ISO format.

---

## Seed Data Management

Runnable factory, seed-script, and isolation code lives in `references/integrity-and-seed.md`.

### The Factory Pattern (TypeScript)

Build test records through a `buildUser(overrides)` factory that increments an internal counter to produce stable, predictable IDs and emails, and always uses a fixed timestamp (`new Date('2026-01-01T00:00:00Z')` — never a bare `new Date()`). Pair it with a `createUser(pool, overrides)` helper that inserts the record and hands it back. Full code in `references/integrity-and-seed.md`.

### Writing a Prisma Seed Script

Build the script around `upsert` with fixed IDs so running it twice produces identical results, and branch behavior on `process.env.SEED_ENV`: `test` stays minimal (a couple of users), `staging` produces realistic volume (50+ users), `demo` is hand-curated. Both `staging` and `demo` build on top of what `test` seeds. See `references/integrity-and-seed.md`.

### Isolating Tests via Transaction Rollback

Wrapping each test in `BEGIN` / `ROLLBACK` keeps inserted rows from ever surviving between tests. A single shared client at module scope is fine as long as the suite runs serially (`jest --runInBand`); once test files run in parallel within a worker, give each suite its own client or fall back to savepoints. Details in `references/integrity-and-seed.md`.

---

## Query Performance Testing

Runnable EXPLAIN ANALYZE and index-check examples are in `references/performance-and-docker.md`.

### Reading EXPLAIN ANALYZE Output

Run `EXPLAIN (ANALYZE, FORMAT JSON)` against the queries that matter, pull `plan.Plan['Node Type']` from the result, and check it matches `/Index/` rather than showing up as `Seq Scan`, plus confirm `plan['Execution Time']` stays under whatever threshold you've set. See `references/performance-and-docker.md`.

### Confirming Indexes Exist

Query `pg_indexes` directly and check that the columns your lookups and range scans depend on — think `users.email`, `orders.user_id`, `orders.created_at` — actually have indexes backing them. See `references/performance-and-docker.md`.

### Catching Slow Queries

Load in a realistic row count (10K+), time execution with `performance.now()`, and confirm the queries that matter most — dashboard aggregations with joins, `GROUP BY`, `ORDER BY` — stay under a defined ceiling (100ms is a reasonable starting point).

**For MongoDB:** call `collection.find(...).explain('executionStats')` and confirm `stage` is anything other than `COLLSCAN`, check that `totalDocsExamined` stays close to `nReturned`, and confirm compound indexes exist via `collection.indexes()`.

---

## Docker-Based Test Databases

**The 2026 default is Testcontainers.** `@testcontainers/postgresql` at 11.14+ (as of May 2026) is the path of least friction — it manages container lifecycle in code, cleans up automatically, and runs test files in parallel on distinct ports without you writing any of that logic. It also removes the need for a docker-compose file and manual port-conflict handling. The `PostgreSqlContainer` setup is documented in `references/performance-and-docker.md`.

**A hand-written compose file is still a legitimate option.** Set up `docker-compose.test.yml` with `postgres:18-alpine`, back storage with `tmpfs` for speed, and add a `pg_isready` healthcheck. Bind to a non-default port (5433, say) to avoid clashing with a locally running Postgres. Keep the major version aligned with production — Postgres 18 (18.4 as of May 2026) is current, so move off 17 unless production is deliberately pinned there.

Wire these together as `package.json` scripts: `test:db:up` brings up compose, `test:db:migrate` runs `prisma migrate deploy`, `test:db:seed` runs `prisma db seed`, `test:db` chains all of that plus `jest`, and `test:db:down` tears down with `compose down -v`.

---

## Anti-Patterns

### 1. Running tests against a copy of production
Production data carries PII, isn't deterministic, and shifts underneath you over time. Reach for factories and seed scripts producing synthetic data instead.

### 2. Letting tests share database state
One test inserts a user, a later test assumes that user is already there, CI happens to reorder them, and now the second test fails for reasons that have nothing to do with the code under test. Transaction rollback or guaranteed per-test cleanup avoids this entirely.

### 3. Skipping rollback tests because "we never roll back"
That assumption survives right up until the first migration that breaks production and needs a real rollback. Test the `down` path regardless. If the tooling genuinely has no revert mechanism, write that down as a known risk rather than quietly skipping the test.

### 4. Treating `migrate resolve --rolled-back` as a rollback tool
It isn't one — it only repairs a migration that *failed partway through*, throws on anything that applied cleanly, and never actually reverts schema changes. Use the real mechanism instead: `down.sql` for Prisma, `undoLastMigration()` for TypeORM.

### 5. Relying on ORM schema-sync instead of migrations
`prisma db push`, `typeorm synchronize: true`, and Django's `migrate --run-syncdb` all bypass the migration path that production actually goes through. Tests need to exercise the same mechanism production uses, full stop.

### 6. Only exercising the happy path
A query returning rows when there's data to return is the trivial case. Also cover empty result sets, nulls sitting in optional columns, results at the upper size limit, and queries run against data that shouldn't match anything.

### 7. Writing a performance check that structurally cannot fail
An EXPLAIN assertion that passes regardless of whether the index exists is worse than no test — it creates false confidence. Confirm it actually goes red when you drop the index (Verification section below walks through this).

### 8. Letting seed data be random
Calling `faker.random()` without seeding it, or using `uuid()` / `now()` in seed data, guarantees a different dataset every run and non-deterministic test outcomes. Pin things down instead: `faker.seed(42)`, hard-coded IDs, `new Date('2026-01-01T00:00:00Z')`.

---

## Verification

Confirm the suite genuinely catches regressions, working from the cheapest check up:

1. **Clean-state green run:** `npm run test:db` exits 0 against a freshly provisioned Testcontainers database.
2. **The EXPLAIN check has real teeth:** in a throwaway database, run `DROP INDEX users_email_idx`, re-run the performance test and confirm it now **fails** (the planner should fall back to `Seq Scan`), then put the index back and confirm the test goes green again. If the test stays green even with the index missing, it's broken and needs fixing before you trust it. Details in `references/performance-and-docker.md`.
3. **Drift detection actually triggers:** `prisma migrate diff --from-migrations prisma/migrations --to-schema-datamodel prisma/schema.prisma --exit-code` should return 0 against an untouched repo; hand-edit `schema.prisma` afterward and confirm the same command now returns non-zero.

---

## Done When

- A single test file covers both directions of the newest migration: the forward test starts from an empty database and checks the resulting schema through `information_schema`; the rollback test runs `down.sql`, confirms the reverted object is gone, then re-applies forward — and both pass in CI.
- A constraints test file demonstrates a rejection, with the matching DB error message, for each of NOT NULL, UNIQUE, FOREIGN KEY, and CHECK — verified at the `pool.query` level.
- A data-preservation test inserts rows ahead of the migration under test and confirms they're intact afterward (without faking a `--to` flag that doesn't exist).
- A migration-drift check (`prisma migrate diff … --exit-code`) is wired into CI and returns 0 against a clean checkout.
- Seed data is idempotent — built on `upsert` with fixed IDs — and switches its output based on `SEED_ENV`; running it twice back-to-back leaves identical state.
- An EXPLAIN test checks `Node Type` against `/Index/` and `Execution Time` against a threshold, and has been proven to fail once the relevant index is dropped.
- The `test:db` CI job passes cleanly against a Testcontainers-provisioned database.

## Reference Files (in `references/`)

- **migration-tests.md** — forward-migration validation, `down.sql`-based rollback, data-preservation checks, drift detection via `migrate diff`, and schema snapshot diffing.
- **integrity-and-seed.md** — constraint and referential-integrity tests, the intended-vs-enforced data-quality audit, the factory pattern, the `SEED_ENV`-driven seed script, and transaction-rollback isolation helpers.
- **performance-and-docker.md** — EXPLAIN ANALYZE plan assertions, index-existence checks, the dropped-index teeth test, and Testcontainers setup.

## Related Skills

- **test-data-management** — synthetic data generation and masking at scale, for non-production environments generally. This skill covers in-test factories and seed scripts; that one covers large realistic datasets and PII masking.
- **test-environments** — Docker/IaC provisioning of test databases and environment parity more broadly. This skill uses Testcontainers *within* a test suite; test-environments owns the standing infrastructure around it.
- **security-testing** — SQL injection, database-level access control, encryption verification. This skill is about correctness and integrity, not adversarial input.
- **ci-cd-integration** — running migration and database test jobs as part of CI pipelines, including provisioning test databases in GitHub Actions.
- **performance-testing** — load testing database performance, connection-pool sizing, and query optimization under concurrent load; that's out of scope here.
