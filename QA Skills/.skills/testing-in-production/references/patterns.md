# Code Patterns for Testing in Production

Working code for the feature-flag, smoke-test, and non-destructive-cleanup patterns this
skill relies on. `SKILL.md` carries the reasoning, tables, and anti-patterns — this file
is just the implementations.

## Feature flags: covering both ON and OFF

Every flagged feature needs a test in each state. The OFF path doubles as the rollback
path, so it has to hold up perfectly.

```typescript
// Test the feature-on experience
test('new checkout flow renders when flag is enabled', async ({ page }) => {
  await setFeatureFlag('new-checkout', true, { userId: TEST_USER_ID });
  await page.goto('/checkout');
  await expect(page.getByRole('heading', { name: 'Express Checkout' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Pay with saved card' })).toBeEnabled();
});

// Test the feature-off fallback (this is the rollback path)
test('legacy checkout flow renders when flag is disabled', async ({ page }) => {
  await setFeatureFlag('new-checkout', false, { userId: TEST_USER_ID });
  await page.goto('/checkout');
  await expect(page.getByRole('heading', { name: 'Checkout' })).toBeVisible();
  await expect(page.getByRole('form', { name: 'Payment details' })).toBeVisible();
});
```

## Feature flags: testing combinations that matter

When flags interact, test the combinations that could actually cause problems rather
than every one of the 2^N possibilities — focus on flags touching the same user flow.

```typescript
// Identify interacting flags by feature area
const checkoutFlags = ['new-checkout', 'express-pay', 'discount-engine-v2'];

// Test the critical combinations, not all 2^N
const criticalCombinations = [
  { 'new-checkout': true, 'express-pay': true, 'discount-engine-v2': true },   // all new
  { 'new-checkout': true, 'express-pay': false, 'discount-engine-v2': true },  // mixed
  { 'new-checkout': false, 'express-pay': false, 'discount-engine-v2': false }, // all legacy
];

for (const combo of criticalCombinations) {
  test(`checkout with flags: ${JSON.stringify(combo)}`, async ({ page }) => {
    for (const [flag, value] of Object.entries(combo)) {
      await setFeatureFlag(flag, value, { userId: TEST_USER_ID });
    }
    await page.goto('/checkout');
    // Assert checkout completes without errors
    await page.getByRole('button', { name: /place order/i }).click();
    await expect(page.getByText(/order confirmed/i)).toBeVisible();
  });
}
```

## Production smoke tests

Executed right after every deploy, these confirm the application's core functionality
actually holds up against real production configuration, data, and infrastructure.

```typescript
// production-smoke.spec.ts
import { test, expect } from '@playwright/test';

const PROD_URL = process.env.PRODUCTION_URL!;
const SMOKE_USER = process.env.SMOKE_TEST_EMAIL!;
const SMOKE_PASS = process.env.SMOKE_TEST_PASSWORD!;

test.describe('Production Smoke', () => {
  test.describe.configure({ retries: 1, timeout: 30_000 });

  test('application loads and responds', async ({ request }) => {
    const health = await request.get(`${PROD_URL}/api/health`);
    expect(health.ok()).toBeTruthy();
    const body = await health.json();
    expect(body.status).toBe('healthy');
    expect(body.version).toBeDefined();
  });

  test('authentication flow works', async ({ page }) => {
    await page.goto(`${PROD_URL}/login`);
    await page.getByLabel('Email').fill(SMOKE_USER);
    await page.getByLabel('Password').fill(SMOKE_PASS);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page).toHaveURL(/dashboard/);
    await expect(page.getByRole('heading', { name: /dashboard/i })).toBeVisible();
  });

  test('core data loads correctly', async ({ page }) => {
    // Assumes auth state from storageState
    await page.goto(`${PROD_URL}/dashboard`);
    await expect(page.getByRole('table')).toBeVisible();
    await expect(page.getByRole('row')).not.toHaveCount(0);
  });

  test('search returns results', async ({ page }) => {
    await page.goto(`${PROD_URL}/search`);
    await page.getByRole('searchbox').fill('test query');
    await page.getByRole('button', { name: 'Search' }).click();
    await expect(page.getByRole('listitem')).not.toHaveCount(0);
  });
});
```

## Non-destructive create-verify-cleanup (fixture-based)

Smoke tests against production should read rather than write. Where a write can't be
avoided, its cleanup needs to be **guaranteed** — living in fixture teardown, which runs
regardless of whether the test passed or failed.

One thing to avoid: calling `test.afterEach()` from inside a `test()` body. Playwright
only registers hooks at describe/file scope, so a hook added mid-test never actually gets
scheduled for that test — Playwright throws `test.afterEach() can only be called in a
describe block` instead. The outcome is leaked data, which is exactly what this pattern
exists to prevent.

The idiomatic 2026 approach is an auto-fixture that hands back a tracked-resource
recorder and deletes everything it recorded during teardown:

```typescript
// fixtures/draft.fixture.ts — auto-cleanup that ALWAYS runs (pass or fail)
import { test as base, expect } from '@playwright/test';

type DraftTracker = { track: (id: string) => void };

export const test = base.extend<{ drafts: DraftTracker }>({
  drafts: async ({ request }, use) => {
    const created: string[] = [];
    await use({ track: (id) => created.push(id) });

    // Teardown: runs after the test regardless of outcome
    for (const id of created) {
      await request.delete(`${process.env.PRODUCTION_URL}/api/documents/${id}`, {
        headers: { Authorization: `Bearer ${process.env.SMOKE_TEST_TOKEN}` },
      });
    }
  },
});
export { expect };
```

```typescript
// document-smoke.spec.ts
import { test, expect } from './fixtures/draft.fixture';

test('can create and delete a draft', async ({ page, drafts }) => {
  await page.goto(`${process.env.PRODUCTION_URL}/documents`);
  await page.getByRole('button', { name: 'New document' }).click();
  await page.getByLabel('Title').fill('[SMOKE TEST] Auto-cleanup');
  await page.getByRole('button', { name: 'Save draft' }).click();

  const docId = page.url().split('/').pop()!;
  drafts.track(docId);   // registered for teardown BEFORE the assertion can fail

  await expect(page.getByText('[SMOKE TEST] Auto-cleanup')).toBeVisible();
});
```

When a fixture isn't an option — say, a single throwaway script — wrapping the body in
`try/finally` and deleting inside `finally` gives the same guarantee, just with more
boilerplate.

## Synthetic user accounts

A production test account should always be obviously distinct from a real one.

```
Synthetic account conventions:
  - Email pattern: smoke-test+{env}@yourcompany.com
  - Display name: "[SYNTHETIC] Smoke Test User"
  - Flag: is_synthetic = true in user record
  - Excluded from: analytics, billing, email campaigns, support queues
  - Data isolation: test data uses reserved ID ranges or namespaces

Account management:
  - Create accounts via admin API, not through the UI
  - Prefer short-lived OIDC-issued tokens / workload identity over rotating passwords
    (GitHub Actions OIDC -> cloud, AWS IAM Roles Anywhere, SPIFFE/SPIRE for mTLS)
  - If long-lived credentials are unavoidable, rotate quarterly and store in a
    secrets manager (Vault, AWS Secrets Manager, GCP Secret Manager)
  - Never reuse synthetic accounts across different test suites
```
