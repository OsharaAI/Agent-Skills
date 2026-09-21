# Migration Testing — Code Reference

Working examples covering forward migrations, rollback, data preservation, drift detection, and schema snapshot comparison. The reasoning and ORM-specific notes live in `SKILL.md`; this file is just the runnable code.

## Validating the Forward Path

```typescript
// test/migrations/forward.test.ts
import { execSync } from 'child_process';
import { Pool } from 'pg';

// A Testcontainers-provided DATABASE_URL is the preferred setup (see performance-and-docker.md).
// The admin-Pool / CREATE DATABASE approach below is the fallback for a standing
// Postgres instance when Testcontainers isn't available; pick ONE approach per suite.

describe('Forward migrations', () => {
  let pool: Pool;

  beforeAll(async () => {
    // Create a fresh database for migration testing
    const adminPool = new Pool({ database: 'postgres' });
    await adminPool.query('DROP DATABASE IF EXISTS test_migrations');
    await adminPool.query('CREATE DATABASE test_migrations');
    await adminPool.end();

    pool = new Pool({ database: 'test_migrations' });
  });

  afterAll(async () => {
    await pool.end();
  });

  it('should apply all migrations from empty database', () => {
    // Run all migrations against empty database
    execSync('npx prisma migrate deploy', {
      env: { ...process.env, DATABASE_URL: 'postgresql://localhost/test_migrations' },
    });
  });

  it('should have correct schema after all migrations', async () => {
    // Verify expected tables exist
    const tables = await pool.query(`
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' ORDER BY table_name
    `);
    const tableNames = tables.rows.map((r) => r.table_name);
    expect(tableNames).toContain('users');
    expect(tableNames).toContain('orders');
    expect(tableNames).toContain('products');
  });

  it('should have correct columns on users table', async () => {
    const columns = await pool.query(`
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_name = 'users' ORDER BY ordinal_position
    `);
    const colMap = Object.fromEntries(
      columns.rows.map((r) => [r.column_name, r])
    );

    expect(colMap.id.data_type).toBe('uuid');
    expect(colMap.email.is_nullable).toBe('NO');
    expect(colMap.created_at.column_default).toContain('now()');
  });
});
```

## Testing Rollbacks

There's no `migrate down` or `migrate rollback` in Prisma. `prisma migrate resolve --rolled-back` is not a substitute — it exists to fix a migration whose `migrate deploy` run *failed partway*, and it errors out if you point it at a migration that applied without issue. The right test: apply the migration forward, capture the resulting state, run the hand-written `down.sql` directly through `psql`, confirm the reverted object is actually gone, then re-apply forward.

```typescript
import { execSync } from 'node:child_process';

describe('Migration rollback', () => {
  it('the down migration cleanly reverses the latest up', async () => {
    // Apply all migrations to a fresh DB
    execSync('npx prisma migrate deploy', { env: migrationEnv });

    // Capture pre-rollback state: the column the latest migration added exists
    const before = await pool.query(`
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'users' AND column_name = 'display_name'
    `);
    expect(before.rows).toHaveLength(1);

    // Get the latest applied migration name (Prisma stores in _prisma_migrations)
    const { rows } = await pool.query(
      `SELECT migration_name FROM _prisma_migrations
         WHERE finished_at IS NOT NULL
         ORDER BY finished_at DESC LIMIT 1`,
    );
    const latest = rows[0].migration_name;

    // Revert by applying the hand-written down.sql checked in alongside the
    // migration. Do NOT use `migrate resolve --rolled-back` here — that command
    // is only valid against a FAILED migration and throws on a clean one.
    execSync(`psql $DATABASE_URL -f prisma/migrations/${latest}/down.sql`, { env: migrationEnv });

    // Verify rollback succeeded: the column added by the up migration is gone
    const after = await pool.query(`
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'users' AND column_name = 'display_name'
    `);
    expect(after.rows).toHaveLength(0);
  });

  it('can re-apply after rollback (idempotent up)', async () => {
    // Mark the reverted migration as un-applied so deploy will re-run it, then re-apply
    execSync('npx prisma migrate reset --force --skip-seed', { env: migrationEnv });
    execSync('npx prisma migrate deploy', { env: migrationEnv });

    const after = await pool.query(`
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'users' AND column_name = 'display_name'
    `);
    expect(after.rows).toHaveLength(1);
  });
});
```

> **TypeORM and Sequelize** each ship a real revert command. Swap the `psql -f down.sql` line for `dataSource.undoLastMigration()` (TypeORM) or `npx sequelize-cli db:migrate:undo` (Sequelize) — the capture → revert → verify → re-apply structure stays the same.

## Confirming Data Survives a Migration

`prisma migrate deploy` doesn't support a `--to` target — every pending migration runs. To stop deliberately at N-1, point Prisma at a migrations directory holding only migrations up through N-1 (below, a `migrations-upto-n1` fixture directory), insert test data, then deploy the complete directory to trigger the migration actually under test.

```typescript
it('should preserve existing data when adding a column', async () => {
  // Setup: apply migrations up to N-1 by deploying a directory holding only those.
  // (Stage the dir in CI, or copy real migrations and drop the latest one.)
  execSync('npx prisma migrate deploy --schema=prisma/schema-upto-n1.prisma', { env: migrationEnv });

  // Insert data before the migration under test
  await pool.query(`INSERT INTO users (id, email) VALUES ($1, $2)`,
    ['550e8400-e29b-41d4-a716-446655440000', 'alice@example.com']);

  // Apply the migration under test (adds nullable 'display_name' column) — full dir
  execSync('npx prisma migrate deploy', { env: migrationEnv });

  // Verify existing data survived
  const result = await pool.query('SELECT email, display_name FROM users WHERE id = $1',
    ['550e8400-e29b-41d4-a716-446655440000']);
  expect(result.rows[0].email).toBe('alice@example.com');  // data survived
  // New nullable column carries its default (or null when no default)
  expect(result.rows[0].display_name).toBeNull();
});
```

Tools with genuine version targeting (Flyway's `migrate -target=`, Alembic's `upgrade <rev>`) should just use that flag rather than staging a directory this way.

## Detecting Migration Drift (shadow-DB check)

The most common real-world migration bug: the schema or the live database gets edited directly, without a corresponding migration, so the migration history checked into the repo no longer reproduces `schema.prisma` if replayed. `prisma migrate diff` combined with `--exit-code` returns non-zero the moment it detects that kind of drift — run it as a fast pre-flight step in CI, ahead of the more expensive tests.

```typescript
it('committed migrations reproduce schema.prisma exactly', () => {
  // Non-zero exit (and a thrown error) means the migrations and the schema disagree.
  execSync(
    'npx prisma migrate diff ' +
      '--from-migrations prisma/migrations ' +
      '--to-schema-datamodel prisma/schema.prisma ' +
      '--shadow-database-url "$SHADOW_DATABASE_URL" ' +
      '--exit-code',
    { env: migrationEnv },
  );
});
```

## Comparing Schema Snapshots

```typescript
// Diff the schema before and after a migration to catch unintended changes
import { execSync } from 'child_process';

function getSchemaSnapshot(dbUrl: string): string {
  return execSync(`pg_dump --schema-only --no-owner --no-privileges ${dbUrl}`, {
    encoding: 'utf-8',
  });
}

it('should only change the expected tables', () => {
  const before = getSchemaSnapshot(testDbUrl);
  execSync('npx prisma migrate deploy', { env: migrationEnv });
  const after = getSchemaSnapshot(testDbUrl);

  // Parse both schemas and compare table-by-table
  // Only 'orders' table should have changed
  const changedTables = diffSchemas(before, after);
  expect(changedTables).toEqual(['orders']);
});
```
