# Allure reference

Complete adapter configurations, the v3 runnable path, how to preserve CI history, and failure categories.

## Allure 2 vs Allure 3 — picking a path

The **framework adapters** — `allure-playwright`, `allure-vitest`, `allure-jest` — all still write Allure 2
result files into `allure-results/`. What actually differs between the two versions is the **reader/CLI**
that converts those results into an HTML report:

- **Allure 2 path** — `allure-commandline` (2.42.1, Jun 2026), which is what `brew install allure` gives you.
  It reads `allure-results/categories.json` and uses `allure generate` / `allure open` / `allure serve`.
  The feature set here is stable and essentially frozen, seeing mostly dependency bumps at this point.
- **Allure 3 path** — the `allure` npm package paired with `allurerc.mjs` (3.9.0, May 2026). This is a full
  TypeScript rewrite: a plugin system, one consolidated config file, live `allure watch`, project-wide
  quality gates, multi-environment reports, and **Allure Service**, which handles cloud history and
  replaces the artifact-shuffling approach described below. Categories now live in the `allurerc.mjs`
  plugin config — the separate `categories.json` file is strictly an Allure 2 idea.

Default to Allure 3 for new work. The commands under "Allure 3 runnable path" further down are the v3
counterparts to the v2 `allure generate` command referenced in the SKILL file.

## Allure with Playwright

```bash
npm i -D allure-playwright
```

```typescript
// playwright.config.ts
import { defineConfig } from "@playwright/test";

export default defineConfig({
  reporter: [
    ["list"],
    ["allure-playwright", {
      outputFolder: "allure-results",
      detail: true,
      suiteTitle: true,
      environmentInfo: {
        Browser: "Chromium",
        Environment: process.env.TEST_ENV ?? "local",
        BaseURL: process.env.BASE_URL ?? "http://localhost:3000",
      },
    }],
  ],
});
```

**Attaching metadata to tests** — severity, feature, story, and tag values feed Allure's grouping logic and the "Behaviors" view:

```typescript
import { test, expect } from "@playwright/test";
import { allure } from "allure-playwright";

test.describe("Checkout Flow", () => {
  test("should complete purchase with valid card", async ({ page }) => {
    await allure.severity("critical");
    await allure.feature("Checkout");
    await allure.story("Payment Processing");
    await allure.tag("smoke");

    await allure.attachment("Test Config", JSON.stringify({
      paymentProvider: "stripe-test",
      currency: "USD",
    }), "application/json");

    await page.goto("/checkout");
    await page.fill('[data-testid="card-number"]', "4242424242424242");
    await page.fill('[data-testid="card-expiry"]', "12/28");
    await page.fill('[data-testid="card-cvc"]', "123");
    await page.click('[data-testid="pay-button"]');

    await expect(page.locator('[data-testid="confirmation"]')).toBeVisible();
  });
});
```

## Allure with Jest/Vitest

```bash
# Jest
npm i -D jest-allure2-reporter allure-jest
# Vitest
npm i -D allure-vitest
```

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    reporters: [
      "default",
      ["allure-vitest/reporter", {
        resultsDir: "allure-results",
        environmentInfo: { Node: process.version, OS: process.platform },
      }],
    ],
    setupFiles: ["allure-vitest/setup"],
  },
});
```

## Allure 2 path — generating a report (runnable)

```bash
# Install Allure 2 CLI
brew install allure  # macOS — this installs Allure 2 (allure-commandline 2.42.1)
# or: npm i -D allure-commandline

# Generate HTML report from results
npx allure generate allure-results --clean -o allure-report

# Open the generated report
npx allure open allure-report

# Generate + serve in one step (handy for CI artifact viewing)
npx allure serve allure-results
```

## Allure 3 path — runnable

Allure 3 comes as the `allure` npm package and is configured through an `allurerc.mjs` file placed next to
your test config. This is the v3 counterpart to `allure generate`, and it's what "use Allure 3 for new
projects" actually looks like once written in code:

```bash
npm i -D allure
```

```javascript
// allurerc.mjs
import { defineConfig } from "allure";

export default defineConfig({
  name: "E2E Report",
  output: "allure-report",
  plugins: {
    awesome: {
      options: {
        // v3 reads categories here — NOT from a dropped-in categories.json
        categories: [
          { name: "Product Bugs", matchedStatuses: ["failed"], messageRegex: ".*Expected.*but received.*" },
          { name: "Test Infrastructure", matchedStatuses: ["broken"], messageRegex: ".*(ECONNREFUSED|timeout|navigation).*" },
        ],
      },
    },
  },
});
```

```bash
# Build the report from allure-results (v3 equivalent of `allure generate`)
npx allure run -- npx playwright test     # run tests + build report
npx allure generate allure-results        # build report from existing results
npx allure watch                          # real-time report that updates as tests run
```

## History and trends (Allure 2 — carrying history/ between CI runs)

Trend tracking in Allure 2 only works if the `allure-report/history` directory is carried forward between
runs. (Allure 3 / Allure Service handles this server-side instead; what follows is the no-cost Allure 2
approach.)

```yaml
# GitHub Actions
- name: Download previous Allure history
  uses: actions/download-artifact@v4
  with:
    name: allure-history
    path: allure-history
  continue-on-error: true  # First run has no history

- name: Run tests
  run: npx playwright test

- name: Copy history to results
  run: |
    mkdir -p allure-results/history
    cp -r allure-history/history/* allure-results/history/ 2>/dev/null || true

- name: Generate Allure report
  run: npx allure generate allure-results --clean -o allure-report

- name: Upload Allure report
  uses: actions/upload-artifact@v4
  with:
    name: allure-report
    path: allure-report/
    retention-days: 30

- name: Upload Allure history
  uses: actions/upload-artifact@v4
  with:
    name: allure-history
    path: allure-report/history/
    retention-days: 90
```

## Custom categories (Allure 2 — `allure-results/categories.json`)

This file goes into `allure-results/` before running `allure generate`, and it groups failures by type
rather than leaving them as a flat list. **This applies to Allure 2 only** — in Allure 3 the equivalent
configuration lives inside `allurerc.mjs` (see the v3 path above).

```json
// allure-results/categories.json
[
  { "name": "Product Bugs", "matchedStatuses": ["failed"], "messageRegex": ".*Expected.*but received.*" },
  { "name": "Test Infrastructure", "matchedStatuses": ["broken"], "messageRegex": ".*(ECONNREFUSED|timeout|navigation).*" },
  { "name": "Flaky Tests", "matchedStatuses": ["failed"], "messageRegex": ".*(intermittent|race condition|retry).*" },
  { "name": "Missing Test Data", "matchedStatuses": ["broken"], "messageRegex": ".*(seed|fixture|not found in database).*" }
]
```
