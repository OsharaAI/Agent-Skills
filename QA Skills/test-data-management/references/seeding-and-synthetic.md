# Seeding, Anonymization, and Synthetic Data

Working code for idempotent seeding, the anonymization pipeline, cleanup strategies, and
synthetic data generation. Referenced from `SKILL.md` under "Database Seeding," "Data
Anonymization," and "Synthetic Data."

## Making Seed Scripts Idempotent

A seed script needs to tolerate being run over and over without piling up duplicates. The
tool for that is an upsert (`INSERT ... ON CONFLICT ... DO UPDATE`) keyed on a stable
natural key rather than the primary key, so a repeat run updates the existing row instead
of inserting a second copy.

```sql
-- seeds/reference_data.sql -- countries and currencies (reference data)
INSERT INTO countries (code, name, currency) VALUES
  ('US', 'United States', 'USD'),
  ('GB', 'United Kingdom', 'GBP'),
  ('JP', 'Japan',         'JPY')
ON CONFLICT (code) DO UPDATE
  SET name     = EXCLUDED.name,
      currency = EXCLUDED.currency;
```

The `ON CONFLICT (code) DO UPDATE` clause matters because this kind of reference data
(country codes, currency lists) gets seeded into every environment and every CI run. Skip
it, and a second run either trips the unique constraint, or — if the script instead does a
`DELETE` followed by `INSERT` to "reset" the table — quietly breaks idempotency: the DELETE
severs foreign keys from any row created between runs and reassigns serial IDs, so anything
pointing at the old rows now points at the wrong record. Upserting leaves both IDs and
foreign keys untouched.

## Anonymizing Data with Faker.js

Production data needs to be anonymized before it's usable for realistic testing.

```typescript
// scripts/anonymize.ts
import { faker } from '@faker-js/faker';
faker.seed(42); // Locks output so it's reproducible across runs

function anonymizeUser(user: Record<string, unknown>, index: number) {
  return {
    ...user,
    email: `user-${index + 1}@test.example.com`,
    name: faker.person.fullName(),
    phone: faker.phone.number(),
    // faker.date.birthdate returns a Date object -- convert to ISO before writing to the DB
    dateOfBirth: faker.date.birthdate({ min: 18, max: 80, mode: 'age' }).toISOString(),
    ssn: `000-00-${String(index + 1).padStart(4, '0')}`,
  };
}
```

## Keeping Referential Integrity Intact While Anonymizing

Changing a user's email needs to propagate to every table that references it — orders,
comments, audit logs, and anything else. The anonymization pipeline should:

1. Build an in-memory map from original value to anonymized value, valid only for the
   duration of that run (never persisted).
2. Write **parent records first**, then walk child records using that same map, so foreign
   keys never point at a stale value.
3. Check referential integrity once anonymization finishes.
4. Run the whole thing inside a **single transaction**, so a failure partway through can't
   leave the data half-anonymized.

```typescript
// scripts/anonymize-pipeline.ts -- sketch
const lookup = new Map<string, string>(); // origEmail -> anonEmail, discarded after the run

await db.transaction(async (tx) => {
  // parents first: users
  for (const [i, u] of users.entries()) {
    const anon = anonymizeUser(u, i);
    lookup.set(u.email as string, anon.email as string);
    await tx.users.update(u.id, anon);
  }
  // children: rewrite the FK email column using the same lookup
  for (const o of orders) {
    await tx.orders.update(o.id, { customerEmail: lookup.get(o.customerEmail) });
  }
});
```

The lookup map only ever lives in memory for the duration of the run and is thrown away
afterward — do **not** persist a mapping that could be used to reverse the anonymization
back to real values (doing so would defeat GDPR's irreversibility requirement).

## Cleanup Strategies

**Transaction rollback (fastest):** wrap each test in its own transaction and roll it back
afterward. Works for unit and integration tests that talk to the database directly. Doesn't
work for E2E tests that go through the app over HTTP — the app's own connections commit
independently of anything the test rolls back.

```typescript
let tx: Transaction;
beforeEach(async () => { tx = await db.beginTransaction(); });
afterEach(async () => { await tx.rollback(); });
```

**Truncation (thorough):** wipe test tables clean between suites. `TRUNCATE TABLE ...
CASCADE` is the efficient way to do it.

**API-based cleanup (for E2E):** when a test can't reach the database directly, track
what it created via a fixture and delete everything in reverse creation order (children
before their parents):

```typescript
export const test = base.extend<{ cleanup: (id: string, type: string) => void }>({
  cleanup: async ({ request }, use) => {
    const toClean: Array<{ id: string; type: string }> = [];
    await use((id, type) => toClean.push({ id, type }));
    for (const r of toClean.reverse()) {
      await request.delete(`/api/test/${r.type}/${r.id}`);
    }
  },
});
```

## Generating Synthetic Data

### Covering edge cases

Factories should make edge-case data cheap to produce:

```typescript
// tests/factories/edge-cases.ts
export const edgeCaseStrings = [
  '',                               // Empty string
  '  leading and trailing  ',       // Whitespace padding
  'a'.repeat(10_000),               // Extremely long string
  '<script>alert("xss")</script>',  // XSS payload
  "Robert'); DROP TABLE users;--",  // SQL injection payload
  '\u0000\u0001\u0002',             // Null/control characters
  '‮override‬',           // RTL override character
];

export const edgeCaseDates = [
  new Date('1970-01-01T00:00:00Z'), // Unix epoch
  new Date('2038-01-19T03:14:07Z'), // 32-bit overflow boundary
  new Date('2024-02-29T00:00:00Z'), // Leap day
  new Date('2025-03-09T02:30:00-05:00'), // Mid-DST-transition timestamp
];
```

### Generating boundary values

```typescript
export function boundaryValues(min: number, max: number): number[] {
  return [min - 1, min, min + 1, Math.floor((min + max) / 2), max - 1, max, max + 1];
}

// Usage
test.each(boundaryValues(1, 100).map(v => [v]))(
  'validates quantity %i correctly',
  (quantity) => {
    const result = validateQuantity(quantity);
    if (quantity >= 1 && quantity <= 100) {
      expect(result.valid).toBe(true);
    } else {
      expect(result.valid).toBe(false);
    }
  }
);
```
