# Per-Framework Migration Detail

This file holds the full runnable before/after examples for each supported migration path. The reasoning behind the approach, the summary of key differences, and the migration checklists in short form all live in `SKILL.md` — what's here is the code.

## Selenium → Playwright

**What's different:**
- Selenium talks to the browser over the WebDriver protocol; Playwright talks over CDP and browser-specific protocols directly, which is part of why it's faster — it skips the HTTP-based WebDriver hop.
- Selenium needs an explicit wait almost everywhere; Playwright auto-waits on every action and assertion by default.
- Selenium locators are plain strings; Playwright locators are objects that support built-in filtering and chaining.

```python
# Selenium (Python)
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

driver.get("https://example.com/login")
wait = WebDriverWait(driver, 10)
email_input = wait.until(EC.visibility_of_element_located((By.ID, "email")))
email_input.send_keys("user@example.com")
driver.find_element(By.ID, "password").send_keys("pass123")
driver.find_element(By.CSS_SELECTOR, "button[type='submit']").click()
wait.until(EC.url_contains("/dashboard"))
```

```typescript
// Playwright (TypeScript)
await page.goto('https://example.com/login');
await page.getByLabel('Email').fill('user@example.com');
await page.getByLabel('Password').fill('pass123');
// 'Sign in' is the submit button's accessible name — replace it with the real
// label your app renders. The Selenium source only matched button[type=submit].
await page.getByRole('button', { name: 'Sign in' }).click();
await expect(page).toHaveURL(/dashboard/);
```

**Checklist for this path:**
- Strip out every explicit wait (`WebDriverWait`, `implicitly_wait`) — Playwright doesn't need them.
- Swap `find_element(By.ID/CSS/XPATH)` calls for `getByRole`, `getByLabel`, or `getByTestId`.
- Swap `send_keys` for `fill` (which clears the field first — usually the behavior you actually want).
- Swap `assert` statements for `expect`, which retries automatically.
- Replace WebDriver session handling with Playwright's `BrowserContext`, which is both lighter and faster.
- **Auth/session:** `driver.add_cookie(...)` won't carry over as-is. Capture the login once inside `globalSetup` and persist `storageState`, then reuse it per test instead of re-logging-in in every spec — see the storageState row in SKILL.md's troubleshooting table.

## Jest → Vitest

**Target version:** Vitest 4.x (currently 4.1.8). Vitest 4 was a significant jump — coverage and reporter APIs moved around a bit, though the `vitest/config` import path stayed put. If you're coming from Jest 28 or earlier, read https://vitest.dev/guide/migration before you start.

**What's different:**
- For most use cases Vitest is API-compatible with Jest, so a lot of tests need no changes at all.
- Where Jest uses `jest` for mocks, spies, and timers, Vitest uses `vi`.
- Vitest runs on Vite's transform pipeline (esbuild), which is noticeably faster.
- Vitest handles ESM natively — no transform step needed.
- Vitest 4 added `coverage.changed`, letting you scope coverage to changed files only — a nice CI win once you've migrated.

```typescript
// Jest
import { jest } from '@jest/globals';
jest.mock('./database');
jest.useFakeTimers();
const spy = jest.spyOn(service, 'fetch');
jest.advanceTimersByTime(1000);

// Vitest
import { vi } from 'vitest';
vi.mock('./database');
vi.useFakeTimers();
const spy = vi.spyOn(service, 'fetch');
vi.advanceTimersByTime(1000);
```

**Checklist for this path:**
- Swap `jest.` for `vi.` across mock/spy/timer calls.
- Turn `jest.config.js` into a Vite-based `vitest.config.ts`.
- Swap `@jest/globals` imports for imports from `vitest`.
- Drop the Babel/ts-jest transform config — Vitest uses esbuild out of the box. **One caveat:** if the project depends on custom Babel plugins (emotion, styled-components macros, decorators), you'll still need an esbuild/SWC equivalent or a Vite plugin — don't remove the transform blindly.
- `jest.fn()` becomes `vi.fn()`; the rest of the API is identical.
- `moduleNameMapper` in the Jest config becomes `resolve.alias` in the Vitest config.
- Expect a real speed win — 2-10x faster test runs is typical.
- **Incremental cutover (Vitest 4.1+):** tag migrated tests (`test('...', { tag: '@migrated' }, ...)`) and run the new suite with `vitest --tag @migrated` so it executes alongside the legacy run instead of requiring you to physically move files around. Drop the tag from a feature area once it reaches parity.

```typescript
// vitest.config.ts (replacing jest.config.js)
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,            // Optional: use describe/it/expect without imports
    environment: 'jsdom',     // Replaces jest-environment-jsdom
    setupFiles: ['./test/setup.ts'],
    coverage: {
      provider: 'v8',         // Replaces jest --coverage (istanbul)
      reporter: ['text', 'json', 'html'],
    },
  },
  resolve: {
    alias: {
      '@': '/src',            // Replaces moduleNameMapper
    },
  },
});
```

## Cypress → Playwright

**Target version:** Playwright ≥ 1.50 (currently 1.60.0, as of May 2026). You might be migrating off Cypress 13, 14, or 15 — 15.x is current and no longer supports Node 18. The translation tables below hold across all three majors, though Component Testing config keys differ between 13 and 15. For the mechanical first pass, reach for the official **cy2pw web converter** ([demo.playwright.dev/cy2pw](https://demo.playwright.dev/cy2pw/)) or the community CLI `npx @11joselu/cypress-to-playwright <dir>`, then hand-refine using this guide — see the tooling table in SKILL.md for guidance on trusting each one.

> **Skip this one:** `npx playwright migrate` isn't a real built-in Playwright CLI command — it will just fail at the terminal (verified June 2026). Use cy2pw or the community CLI above instead.

**What's different:**
- Cypress chains commands through a queue; Playwright uses async/await. This is the single biggest mental-model shift in this migration.
- Cypress executes inside the browser; Playwright sits outside and drives it — which changes how you reason about scope and context.
- `cy.intercept()` becomes `page.route()` — similar capability, different API shape.
- Cypress custom commands become Playwright fixtures.

> **Playwright 1.52 breaking changes** worth knowing before you touch any intercepts:
> - `page.route()` glob patterns no longer support `?` or `[]` — escape them or switch to a regex.
> - `route.continue()` ignores any Cookie header you pass in; it reads from the browser's cookie store instead. Set cookies with `browserContext.addCookies(...)`, **not** a header override.
> - macOS 13 is deprecated as a CI runner.
> Reference: https://playwright.dev/docs/release-notes#version-152

```typescript
// Cypress
cy.visit('/products');
cy.get('[data-testid="search"]').type('widget');
cy.intercept('GET', '/api/products*', { fixture: 'products.json' }).as('search');
cy.wait('@search');
cy.get('.product-card').should('have.length', 3);
cy.get('.product-card').first().find('.price').should('contain', '$29.99');
```

```typescript
// Playwright
await page.route('**/api/products*', route =>
  route.fulfill({ json: { items: [/*...*/] } }),
);
await page.goto('/products');
await page.getByTestId('search').fill('widget');
await expect(page.locator('.product-card')).toHaveCount(3);
await expect(page.locator('.product-card').first().locator('.price')).toContainText('$29.99');
```

**Checklist for this path:**
- Replace `cy.visit()` with `await page.goto()`.
- Replace `cy.get().type()` with `await locator.fill()` — fill clears first, which is almost always what you want.
- Replace `cy.intercept()` + `cy.wait()` with `page.route()` + `page.waitForResponse()`. When the assertion depends on a *real*, un-stubbed network call, pair the action with an explicit wait so you don't race the response:

```typescript
// Wait for the real /api/products response after typing, instead of cy.wait('@search')
const responsePromise = page.waitForResponse(/\/api\/products/);
await page.getByTestId('search').fill('widget');
const response = await responsePromise;
expect(response.status()).toBe(200);
```

- Replace `.should()` chains with `await expect()`, which retries automatically.
- Replace custom commands with fixtures — composable, typed, and they tear themselves down.
- Remove `cy.wrap()`/`cy.then()` patterns entirely; async/await replaces the whole command-queue idea.
- **Auth:** `cy.setCookie()` / `cy.session()` map onto `browserContext.addCookies()` and `storageState`. Capture the login once in `globalSetup` rather than re-implementing it in every spec.

## Mocha → Vitest

This is the easiest of the five paths — Mocha's API maps almost 1:1 onto Vitest's, and you pick up esbuild speed plus native TS support along the way.

**What's different:**
- `describe` / `it` / `before` / `after` / `beforeEach` / `afterEach` don't change at all.
- `chai` assertions (`expect(x).to.equal(y)`) become Vitest's `expect(x).toBe(y)` — same `expect` name, Jest-style matchers underneath. The mechanical swap is: `to.equal` → `toBe`, `to.deep.equal` → `toEqual`, `to.contain` → `toContain`.
- `sinon` spies/stubs become `vi.fn()` / `vi.spyOn()`.
- `mocharc` config becomes `vitest.config.ts`.

```typescript
// Mocha + Chai
import { expect } from 'chai';
describe('Calculator', () => {
  it('adds positive numbers', () => {
    expect(add(2, 3)).to.equal(5);
  });
});

// Vitest
import { describe, it, expect } from 'vitest';
describe('Calculator', () => {
  it('adds positive numbers', () => {
    expect(add(2, 3)).toBe(5);            // to.equal -> toBe
    expect(history()).toEqual([2, 3]);    // to.deep.equal -> toEqual
    expect(label()).toContain('sum');     // to.contain -> toContain
  });
});
```

**Checklist for this path:**
- Run a codemod or sed pass for the assertion-style swaps, and confirm the test count is unchanged before and after.
- Remove `mocha.opts` / `.mocharc.*` and replace with `vitest.config.ts`.
- Remove `ts-node` / `babel-register` setup — Vitest handles TypeScript natively via esbuild.
- Snapshot testing, in-source tests, and browser mode are Vitest-only features; consider adopting them once the migration itself is done.

## Protractor → Playwright

Protractor hit end-of-life in 2023, so treat this migration as urgent if it hasn't already happened. The Angular CLI no longer scaffolds Protractor at all — `ng e2e` now defaults to Cypress, Playwright, or WebdriverIO.

**What's different:**
- Protractor was purpose-built for AngularJS, with automatic `waitForAngular` support. Playwright has no Angular-specific handling — and doesn't need any with modern Angular.
- Protractor's `element(by.model())` and `element(by.binding())` have no direct Playwright equivalent; use `getByLabel`, `getByRole`, or `getByTestId` instead.
- Protractor's `browser.get()` becomes `page.goto()`.

```typescript
// Protractor
browser.get('/login');
element(by.model('username')).sendKeys('admin');
element(by.model('password')).sendKeys('secret');
element(by.css('button[type="submit"]')).click();
browser.wait(EC.urlContains('/dashboard'), 10000);
expect(element(by.binding('user.name')).getText()).toEqual('Admin');
```

```typescript
// Playwright
await page.goto('/login');
await page.getByLabel('Username').fill('admin');
await page.getByLabel('Password').fill('secret');
// Replace 'Sign in' with the submit button's real accessible name — the
// Protractor source only matched button[type=submit], which has no label.
await page.getByRole('button', { name: 'Sign in' }).click();
await expect(page).toHaveURL(/dashboard/);
await expect(page.getByText('Admin')).toBeVisible();
```

**Checklist for this path:**
- Remove every `browser.waitForAngular()` call — it's unnecessary with modern frameworks.
- Replace `element(by.model('x'))` with `page.getByLabel('X')`, mapping the model name to its field's label.
- Replace `element(by.binding('x'))` with `page.getByText()` or `page.getByTestId()`.
- Replace `browser.wait(EC.*)` with Playwright's auto-wait behavior or an `expect` assertion.
- Replace Jasmine assertions with Playwright's auto-retrying `expect`.
- Protractor's `onPrepare` becomes Playwright's `globalSetup` — a natural place to capture `storageState` so tests can skip the login flow.
</content>
