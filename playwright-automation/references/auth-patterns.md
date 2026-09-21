# Handling Authentication

A survey of the ways to authenticate in a Playwright E2E suite — from a single shared login, through multi-role setups, token seeding, and keeping sessions alive across a long run.

---

## What storageState Gives You

`storageState` is Playwright's mechanism for snapshotting a browser context's cookies and localStorage into a JSON file. Any later test can load that file and start out already logged in, skipping the login UI entirely.

```
1. Global setup: log in through the UI, then save storageState to .auth/user.json
2. Test projects: load .auth/user.json so tests begin already authenticated
3. Each test: runs in a fresh BrowserContext seeded with those saved cookies/localStorage
```

Make sure `.auth/` is listed in `.gitignore`.

---

## The Simplest Case: One Shared Login

One user, logged in once, shared by every test in the suite.

```typescript
// e2e/global-setup.ts
import { test as setup, expect } from '@playwright/test';

setup('authenticate as default user', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
  await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/dashboard/);

  // Save the authenticated state
  await page.context().storageState({ path: '.auth/user.json' });
});
```

```typescript
// playwright.config.ts
export default defineConfig({
  projects: [
    {
      name: 'setup',
      testMatch: /global-setup\.ts/,
    },
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: '.auth/user.json',
      },
      dependencies: ['setup'],
    },
  ],
});
```

---

## Handling Multiple Roles

Needed once your application shows different UI to admins, regular users, and guests.

### One Setup File Per Role

```typescript
// e2e/auth/admin.setup.ts
import { test as setup, expect } from '@playwright/test';

setup('authenticate as admin', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill(process.env.ADMIN_EMAIL!);
  await page.getByLabel('Password').fill(process.env.ADMIN_PASSWORD!);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/admin/);
  await page.context().storageState({ path: '.auth/admin.json' });
});

// e2e/auth/user.setup.ts
import { test as setup, expect } from '@playwright/test';

setup('authenticate as user', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill(process.env.USER_EMAIL!);
  await page.getByLabel('Password').fill(process.env.USER_PASSWORD!);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/dashboard/);
  await page.context().storageState({ path: '.auth/user.json' });
});
```

### Wiring Roles Into Projects

```typescript
// playwright.config.ts
export default defineConfig({
  projects: [
    // Setup projects -- run first, no dependencies
    {
      name: 'admin-setup',
      testMatch: /admin\.setup\.ts/,
    },
    {
      name: 'user-setup',
      testMatch: /user\.setup\.ts/,
    },

    // Admin tests
    {
      name: 'admin-chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: '.auth/admin.json',
      },
      dependencies: ['admin-setup'],
      testMatch: /.*\.admin\.spec\.ts/,
    },

    // Regular user tests
    {
      name: 'user-chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: '.auth/user.json',
      },
      dependencies: ['user-setup'],
      testMatch: /.*\.user\.spec\.ts/,
    },

    // Guest/anonymous tests (no storageState)
    {
      name: 'guest-chromium',
      use: { ...devices['Desktop Chrome'] },
      testMatch: /.*\.guest\.spec\.ts/,
    },
  ],
});
```

### A Naming Scheme for Spec Files

```
e2e/tests/
├── auth/
│   ├── login.guest.spec.ts         # Runs without auth
│   └── password-reset.guest.spec.ts
├── dashboard/
│   ├── overview.user.spec.ts       # Runs as regular user
│   └── admin-panel.admin.spec.ts   # Runs as admin
├── settings/
│   ├── profile.user.spec.ts
│   └── team-management.admin.spec.ts
```

---

## Switching Roles Mid-Test

Occasionally one test needs to span roles — an admin creates something, and a regular user should then see it.

```typescript
import { test, expect } from '@playwright/test';

test('admin-created announcement visible to users', async ({ browser }) => {
  // Context acting as admin
  const adminCtx = await browser.newContext({ storageState: '.auth/admin.json' });
  const adminPage = await adminCtx.newPage();
  await adminPage.goto('/admin/announcements');
  await adminPage.getByRole('button', { name: 'New announcement' }).click();
  await adminPage.getByLabel('Title').fill('Planned downtime Friday');
  await adminPage.getByRole('button', { name: 'Publish' }).click();
  await expect(adminPage.getByRole('alert')).toContainText('Published');
  await adminCtx.close();

  // Context acting as a regular user
  const userCtx = await browser.newContext({ storageState: '.auth/user.json' });
  const userPage = await userCtx.newPage();
  await userPage.goto('/dashboard');
  await expect(userPage.getByText('Planned downtime Friday')).toBeVisible();
  await userCtx.close();
});
```

---

## Seeding Tokens Through the API

Apps built on JWTs or API tokens let you bypass the login UI entirely — just set the token where the app expects it.

### Injecting a Token Directly

```typescript
// e2e/fixtures/auth.fixture.ts
import { test as base, type BrowserContext } from '@playwright/test';

export const test = base.extend<{ authenticatedContext: BrowserContext }>({
  authenticatedContext: async ({ browser, request }, use) => {
    // Get a token from the auth API
    const resp = await request.post('/api/auth/token', {
      data: {
        email: process.env.TEST_USER_EMAIL,
        password: process.env.TEST_USER_PASSWORD,
      },
    });
    const { accessToken, refreshToken } = await resp.json();

    // Create context with the token set in localStorage
    const ctx = await browser.newContext({
      storageState: {
        cookies: [],
        origins: [
          {
            origin: process.env.BASE_URL ?? 'http://localhost:3000',
            localStorage: [
              { name: 'accessToken', value: accessToken },
              { name: 'refreshToken', value: refreshToken },
            ],
          },
        ],
      },
    });

    await use(ctx);
    await ctx.close();
  },
});
```

### Seeding a Token via Cookie

```typescript
export const test = base.extend<{}, { authCookies: string }>({
  authCookies: [async ({ browser }, use) => {
    const ctx = await browser.newContext();

    // Get auth cookie from API
    const resp = await ctx.request.post('/api/auth/login', {
      data: { email: 'test@example.com', password: 'password' },
    });
    const setCookie = resp.headers()['set-cookie'];

    // Save the state
    const path = `.auth/cookies-${test.info().parallelIndex}.json`;
    await ctx.storageState({ path });
    await ctx.close();
    await use(path);
  }, { scope: 'worker' }],
});
```

---

## Giving Each Worker Its Own Auth File

Running tests in parallel means each worker process needs a distinct auth state file, or they'll clobber one another.

```typescript
export const test = base.extend<{}, { workerAuth: string }>({
  workerAuth: [async ({ browser }, use, workerInfo) => {
    // A distinct path per worker index
    const authFile = `.auth/worker-${workerInfo.workerIndex}.json`;

    const ctx = await browser.newContext();
    const page = await ctx.newPage();

    await page.goto('/login');
    await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
    await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('**/dashboard');

    await ctx.storageState({ path: authFile });
    await ctx.close();

    await use(authFile);
  }, { scope: 'worker' }],
});
```

---

## Dealing With Sessions That Expire

On a long-running suite, a saved session can go stale before the run finishes.

### A Fixture That Re-Authenticates on Demand

```typescript
export const test = base.extend<{ authedPage: Page }>({
  authedPage: async ({ browser }, use) => {
    const ctx = await browser.newContext({ storageState: '.auth/user.json' });
    const page = await ctx.newPage();

    // Confirm the session is still good before the test proceeds
    const resp = await page.request.get('/api/auth/me');

    if (resp.status() === 401) {
      // Log back in
      await page.goto('/login');
      await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
      await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
      await page.getByRole('button', { name: 'Sign in' }).click();
      await page.waitForURL('**/dashboard');
      // Persist the refreshed state so later tests benefit too
      await ctx.storageState({ path: '.auth/user.json' });
    }

    await use(page);
    await ctx.close();
  },
});
```

### Refreshing Tokens Automatically via Route Interception

```typescript
test('handles token refresh transparently', async ({ page }) => {
  let refreshCount = 0;

  // Catch any 401 and attempt a token refresh before giving up
  await page.route('**/api/**', async (route) => {
    const response = await route.fetch();

    if (response.status() === 401 && refreshCount === 0) {
      refreshCount++;
      // Get a fresh token
      const refreshResp = await page.request.post('/api/auth/refresh');
      if (refreshResp.ok()) {
        // Replay the original request with the refreshed token
        const retryResponse = await route.fetch();
        await route.fulfill({ response: retryResponse });
        return;
      }
    }

    await route.fulfill({ response });
  });

  await page.goto('/dashboard');
  await expect(page.getByRole('heading')).toHaveText('Dashboard');
});
```

---

## Testing Around OAuth / SSO

### Option 1: Skip OAuth Entirely (the preferred route)

Since most OAuth flows hand control to a third-party UI you don't own, it's better to hit a test-only API endpoint that issues a session token directly.

```typescript
setup('authenticate via API', async ({ request }) => {
  // The test environment exposes a backdoor login endpoint just for this
  const resp = await request.post('/api/test/auth', {
    data: { userId: 'qa-fixture-user', role: 'user' },
  });

  // That response sets a session cookie
  const storageState = {
    cookies: resp.headers()['set-cookie']
      ? [/* parse set-cookie header */]
      : [],
    origins: [],
  };

  await fs.writeFile('.auth/user.json', JSON.stringify(storageState));
});
```

### Option 2: Fake the OAuth Callback

```typescript
test('OAuth login flow', async ({ page }) => {
  // Intercept the authorize redirect and simulate a successful callback
  await page.route('**/oauth/authorize*', async (route) => {
    const url = new URL(route.request().url());
    const redirectUri = url.searchParams.get('redirect_uri')!;
    const state = url.searchParams.get('state')!;

    // Send the app a fake authorization code
    await route.fulfill({
      status: 302,
      headers: {
        Location: `${redirectUri}?code=mock_auth_code&state=${state}`,
      },
    });
  });

  // Fake the token-exchange step too
  await page.route('**/oauth/token', async (route) => {
    await route.fulfill({
      json: {
        access_token: 'mock_access_token',
        token_type: 'bearer',
        expires_in: 3600,
      },
    });
  });

  await page.goto('/login');
  await page.getByRole('button', { name: 'Sign in with Google' }).click();
  await expect(page).toHaveURL(/dashboard/);
});
```

---

## Quick Reference

| Scenario | Pattern | Where to look |
|---|---|---|
| Single user, all tests | Global setup + storageState in config | Top of this file |
| Multiple roles | Separate setup files + role-based projects | Handling Multiple Roles |
| Cross-role verification | Multiple browser contexts in one test | Switching Roles Mid-Test |
| API-based apps (JWT) | Token seeding via API, skip login UI | Seeding Tokens Through the API |
| Parallel workers | Per-worker auth file paths | Giving Each Worker Its Own Auth File |
| Long suites | Session validity check + re-auth fixture | Dealing With Sessions That Expire |
| OAuth/SSO | Mock the OAuth flow or use API backdoor | Testing Around OAuth / SSO |
