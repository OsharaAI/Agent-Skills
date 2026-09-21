---
name: playwright-automation
description: >-
  Write production-grade Playwright tests in TypeScript: Page Object Model,
  fixtures, auto-waiting, user-facing locators, parallel execution, CI
  integration, sharding, and 2025-2026 feature awareness. Includes an explicit
  "do not" list for AI agents.
  Use when: "Playwright," "write E2E test," "page object," "new Playwright suite,"
  "Playwright config."
  Not for: fixing one flaky test at runtime — use test-reliability. Not for: bulk
  regenerating selectors after a UI refactor — use selector-drift-recovery. Not for:
  visual baseline creation/management — use visual-testing. Not for: deep WCAG/axe
  audits — use accessibility-testing.
  Related: visual-testing, ci-cd-integration, api-testing, test-reliability, selector-drift-recovery, accessibility-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: automation
---

<objective>
This skill captures how a seasoned engineer builds Playwright suites in TypeScript that stay green after a refactor instead of rotting into flaky noise. The problem it heads off: agents left to their own devices gravitate toward three habits that guarantee brittle tests — sprinkling in `waitForTimeout`, reaching for CSS selectors by default, and calling the deprecated `page.click()`-style APIs. What follows instead is a discipline built on auto-waiting, locators tied to what a user actually sees, and fixture-driven setup.
</objective>

## Questions to Resolve First

Look for `.agents/qa-project-context.md` before asking anything — reuse whatever it already answers, and only prompt for the gaps:

1. **Language: TypeScript or JavaScript?** Push toward TypeScript; it surfaces locator and assertion mistakes at compile time, and all examples below assume it's in use.
2. **Browser targets?** Chromium is enough for local iteration; layer in Firefox and WebKit for CI runs. Note that mobile viewports are handled as separate Playwright *projects* (a different device descriptor), not as separate spec files.
3. **Greenfield or migration?** If moving off Cypress or Selenium, tackle the flakiest existing tests first rather than attempting a single big-bang rewrite — this changes how you sequence the work.
4. **One site or several?** Multi-site setups call for shared fixtures plus per-site configuration objects — details in `references/multi-site-architecture.md`.

---

## Guiding Principles

1. **Locators should mirror the user's view of the page.** Preference order: `getByRole`, then `getByLabel`, then `getByTestId`, with raw CSS only as a last resort. The locator should describe what's visible on screen, not the DOM's internal shape. Full decision tree in `references/selector-strategies.md`.
2. **Lean on auto-waiting; `waitForTimeout` is off the table.** Playwright actions and its web-first assertions already retry until conditions are met. Reaching for a fixed timeout is a signal that the locator or assertion needs improving, not that a delay is needed.
3. **Keep tests isolated.** Every test runs against its own fresh `BrowserContext`; no test should assume state left behind by another test or rely on run order.
4. **Default to parallel; serialize only when unavoidable.** Turn on `fullyParallel: true` and reach for `test.describe.serial` only for the rare flow that truly cannot be split apart.
5. **Prefer fixtures over lifecycle hooks for setup.** Fixtures compose cleanly, carry type information, and clean up automatically — use them instead of `beforeEach`/`afterEach` for anything beyond trivial setup. See `references/fixtures-and-projects.md`.

> **Scale the approach to team maturity** (recorded as `team_maturity` in `.agents/qa-project-context.md`):
> - **startup** — Chromium only, a handful (5–10) of critical-path tests, a plain CI run per PR. Hold off on sharding and visual baselines until the suite has proven stable.
> - **growing** — Chromium plus Firefox, a proper Page Object Model, parallel execution, CI sharding, and HTML reports saved as artifacts.
> - **established** — the full browser matrix, dedicated auth fixtures, an API mocking layer, a visual regression baseline, trace capture on failure, and ongoing flakiness tracking.

---

## Project Structure

```
project-root/
├── playwright.config.ts
├── e2e/
│   ├── fixtures/              # base.fixture.ts, auth.fixture.ts, data.fixture.ts
│   ├── pages/                 # Page objects by feature
│   │   ├── base.page.ts
│   │   ├── dashboard.page.ts
│   │   └── components/        # Reusable component objects (data-table, modal)
│   ├── tests/                 # Test files by feature (auth/, dashboard/, settings/)
│   ├── helpers/               # test-data.ts, api-client.ts
│   └── global-setup.ts
├── .auth/                     # Git-ignored storageState files
└── test-results/              # Git-ignored artifacts
```

### playwright.config.ts

```typescript
import { defineConfig, devices } from '@playwright/test';

const isCI = !!process.env.CI;
const baseURL = process.env.BASE_URL ?? 'http://localhost:3000';

export default defineConfig({
  testDir: './e2e/tests',
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 2 : 0,
  workers: isCI ? '50%' : undefined,
  reporter: isCI
    ? [['blob'], ['github'], ['json', { outputFile: 'test-results/results.json' }]]
    : [['html', { open: 'on-failure' }]],
  use: {
    baseURL,
    trace: isCI ? 'on-first-retry' : 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: isCI ? 'on-first-retry' : 'off',
    navigationTimeout: 30_000,
    // Avoid a global actionTimeout — it can mask a genuinely slow auto-waited
    // action. Set per-action only where a known-slow widget needs it.
  },
  projects: [
    { name: 'setup', testMatch: /global-setup\.ts/, teardown: 'teardown' },
    { name: 'teardown', testMatch: /global-teardown\.ts/ },
    { name: 'chromium', use: { ...devices['Desktop Chrome'], storageState: '.auth/user.json' }, dependencies: ['setup'] },
    { name: 'firefox', use: { ...devices['Desktop Firefox'], storageState: '.auth/user.json' }, dependencies: ['setup'] },
    { name: 'webkit', use: { ...devices['Desktop Safari'], storageState: '.auth/user.json' }, dependencies: ['setup'] },
  ],
  webServer: isCI ? undefined : {
    command: 'npm run dev', url: baseURL, reuseExistingServer: !isCI, timeout: 120_000,
  },
});
```

Note the `blob` reporter in CI — that's the piece that lets sharded runs later be merged back together (see the sharding section below). The `setup` project is responsible for writing `storageState` a single time, and the browser projects declare a dependency on it before they run.

### Global setup (storageState)

```typescript
import { test as setup, expect } from '@playwright/test';

setup('authenticate as default user', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
  await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/.*dashboard/);
  await page.context().storageState({ path: '.auth/user.json' });
});
```

That's the essence of the `setup`-project pattern: a dedicated setup project (or, alternatively, a `globalSetup` file) performs the UI login exactly once, and each browser project then replays the resulting cookies/localStorage by pointing `storageState` at the saved file in config. Multi-role scenarios (admin, standard user, guest) and token-based seeding are covered in `references/auth-patterns.md`.

---

## Page Object Model

```typescript
import { type Page, type Locator, expect } from '@playwright/test';

export abstract class BasePage {
  constructor(protected readonly page: Page) {}
  abstract readonly path: string;
  async goto(): Promise<void> {
    await this.page.goto(this.path);
    await this.page.waitForLoadState('domcontentloaded');
  }
}
```

**Component objects** model reusable pieces of UI — a modal, a table, a nav bar. Construct them around a root `Locator` rather than a whole `Page`:

```typescript
export class DataTable {
  readonly rows: Locator;
  constructor(private readonly root: Locator) {
    this.rows = root.getByRole('row');
  }
  getRowByText(text: string | RegExp): Locator {
    return this.rows.filter({ hasText: text });
  }
}
```

**Favor composition over deep inheritance.** A page object owns instances of its components rather than sitting at the bottom of a five-level class hierarchy:

```typescript
export class UsersPage extends BasePage {
  readonly path = '/admin/users';
  readonly table: DataTable;
  constructor(page: Page) {
    super(page);
    this.table = new DataTable(page.getByRole('table', { name: 'Users' }));
  }
}
```

**Wire page objects in through fixtures** rather than instantiating them directly inside test files:

```typescript
export const test = base.extend<{ usersPage: UsersPage }>({
  usersPage: async ({ page }, use) => { await use(new UsersPage(page)); },
});
export { expect } from '@playwright/test';
```

A page object's job is to hand back state — locators, values — never to assert on its own. Keeping assertions in the test file means a failure's stack trace points to the scenario that broke, not to some method buried in a page object.

---

## Patterns Worth Reusing

### Grouping form steps with test.step

Group related actions inside `test.step()` blocks so the trace viewer's timeline reads like a narrative instead of a flat list of clicks:

```typescript
test('submits a multi-step form', async ({ page }) => {
  await page.goto('/onboarding');
  await test.step('fill personal info', async () => {
    await page.getByLabel('First name').fill('Jane');
    await page.getByRole('button', { name: 'Next' }).click();
  });
  await test.step('submit', async () => {
    await page.getByRole('button', { name: 'Complete setup' }).click();
  });
  await expect(page).toHaveURL('/dashboard');
});
```

### Intercepting network calls

```typescript
// Fake out a response entirely
await page.route('**/api/products*', async (route) => {
  await route.fulfill({ json: { items: [{ id: 'sku-9', name: 'Gadget', price: 44.5 }] } });
});

// Fetch the real response, then tweak it
await page.route('**/api/feature-flags', async (route) => {
  const response = await route.fetch();
  const body = await response.json();
  body.flags['new-checkout'] = true;
  await route.fulfill({ response, json: body });
});

// Force an error path
await page.route('**/api/products*', (route) => route.fulfill({ status: 500 }));

// WebSocket interception (v1.48+)
await page.routeWebSocket('**/ws/notifications', (ws) => {
  ws.onMessage(() => ws.send(JSON.stringify({ type: 'alert', title: 'Deployed' })));
});
```

HAR replay and conditional routing live in `references/network-and-mocking.md`.

### A fixture for authenticated API calls

When a test needs to seed data or check backend state directly — bypassing the UI — give it a pre-authenticated `APIRequestContext` through a fixture. Pull the token from the fixture's setup, never inline it as a literal:

```typescript
import { test, request, type APIRequestContext } from '@playwright/test';

// test.extend adds an `api` fixture to the base test object.
export const apiTest = test.extend<{ api: APIRequestContext }>({
  api: async ({ baseURL }, use) => {
    const ctx = await request.newContext({
      baseURL,
      extraHTTPHeaders: { Authorization: `Bearer ${process.env.API_TOKEN!}` },
    });
    await use(ctx);
    await ctx.dispose();
  },
});
```

### Marking and annotating tests

```typescript
test('checkout @smoke', async ({ page }) => { /* npx playwright test --grep @smoke */ });
test.slow();                                    // Triples timeout
test.skip(({ browserName }) => browserName === 'webkit', 'WebKit bug');
test.fixme('known issue tracked in JIRA-1234', async ({ page }) => { /* ... */ });
```

---

## Writing Assertions

Reach for web-first assertions by default — they keep retrying until either the condition becomes true or the timeout elapses:

```typescript
await expect(page.getByRole('alert')).toBeVisible();
await expect(page.getByRole('heading')).toHaveText('Dashboard');
await expect(page).toHaveURL('/dashboard');
await expect(page.getByRole('button', { name: 'Save' })).toBeEnabled();
await expect(page.getByRole('listitem')).toHaveCount(5);
await expect(page.getByRole('listitem')).toHaveText(['Apple', 'Banana', 'Cherry']);
```

**Soft assertions** let a test keep going after a failure and report everything that broke, rather than stopping at the first miss:

```typescript
await expect.soft(page.getByLabel('Name')).toHaveValue('Sam Rivera');
await expect.soft(page.getByLabel('Email')).toHaveValue('sam@example.com');
```

**ARIA snapshots** capture the shape of the accessibility tree, which is useful for catching semantic regressions:

```typescript
await expect(page.getByRole('navigation', { name: 'Main' })).toMatchAriaSnapshot(`
  - navigation "Main":
    - link "Home"
    - link "Products"
`);
```

### Visual checks (a quick inline option; the full workflow lives elsewhere)

`toHaveScreenshot`, built into Playwright, retries automatically and generates a baseline image the first time it runs. Mask any regions that change dynamically, and never pair it with a preceding `waitForTimeout`:

```typescript
await expect(page.getByTestId('product-card')).toHaveScreenshot('product-card.png', {
  mask: [page.getByTestId('price')],
});
```

Baseline lifecycle management, threshold tuning (`maxDiffPixelRatio`, `maskColor`, `stylePath`), and review workflows belong to the `visual-testing` skill — that's the right home for anything beyond this one-liner.

### A quick axe scan (deep audits belong elsewhere)

The ARIA snapshot above only verifies structure — it doesn't check WCAG compliance. For rule-based scanning, pull in `@axe-core/playwright`:

```typescript
import AxeBuilder from '@axe-core/playwright';

test('dashboard has no a11y violations', async ({ page }) => {
  await page.goto('/dashboard');
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
```

For anything involving WCAG conformance levels, rule tuning, or fixing violations, defer to `accessibility-testing`.

---

## Running in Parallel and in CI

### Splitting the suite into shards

Distribute tests across CI matrix jobs, then stitch the resulting shard reports back into a single HTML report. This only pays off once a suite reaches `growing` maturity or beyond — a `startup`-sized suite of 5–10 tests gains nothing from sharding.

```yaml
strategy:
  fail-fast: false
  matrix:
    shard: [1, 2, 3, 4]
steps:
  - run: npx playwright test --shard=${{ matrix.shard }}/4
```

Every shard uploads its own `blob-report/` directory, and a closing job runs `npx playwright merge-reports --reporter=html ./all-blob-reports` to combine them. That `blob` reporter setting from the config earlier is exactly what makes the merge possible — running `--shard` without it just leaves you with several disconnected HTML reports. The complete GitHub Actions workflow, including blob upload/download steps and artifact handling, is in `references/ci-recipes.md`.

### Tools for tracking down failures

- **Trace viewer** — `npx playwright show-trace test-results/.../trace.zip` gives a full timeline: actions taken, network activity, DOM snapshots, console output.
- **UI mode** — `npx playwright test --ui` for live, step-through, time-travel debugging.
- **`--debug` flag** — `npx playwright test my-test.spec.ts --debug` runs headed and pauses before each action.
- **VS Code extension** (`ms-playwright.playwright`) — run and debug tests from the gutter, pick locators visually, and use watch mode.
- **`page.pause()`** — drops into the Inspector mid-run. This is a local-only debugging aid; never leave it committed.

Flaky-test triage and artifact analysis techniques are detailed in `references/debugging-and-triage.md`.

---

## Staying Current (2025-2026)

As of this writing, **Playwright 1.60.0** (May 2026) is current — keep the version pinned identically in `package.json` and in whatever Docker image CI uses. Notable additions from recent releases:

| Version | Feature | What it does |
|---------|---------|-------------|
| v1.45 | Clock API | `page.clock.install()` / `fastForward()` — control time without monkey-patching `Date` |
| v1.45 | `--fail-on-flaky-tests` | Fail the CI run if any test needed a retry to pass |
| v1.46 | `--only-changed` | Run only tests affected by changed files (git-diff aware) |
| v1.46 | ARIA snapshots | `toMatchAriaSnapshot()` for accessibility-tree assertions |
| v1.48 | `routeWebSocket` | First-class WebSocket interception (replaces CDP hacks) |
| v1.55 | Test Migrator | Automated Cypress→/Selenium→Playwright via `npx playwright migrate` |
| v1.56 | Test Agents | `npx playwright init-agents --loop=claude\|vscode\|opencode` — planner/generator/healer agents inside the coding agent's loop |
| v1.57 | Chrome for Testing default | Headed uses `chrome`, headless uses `chrome-headless-shell` instead of bundled Chromium. Caveat: a high-memory regression was reported (microsoft/playwright #38489) — pin a known-good image tag for CI. |
| v1.57 | `toHaveScreenshot` options | `maskColor`, `stylePath`, `pathTemplate` for masking color, custom stylesheet, and output path control |
| v1.59 | Screencast API | `page.screencast.start()` / `.stop()` for mid-test video with start/stop control — an alternative to `recordVideo`, not a replacement. Adds action annotations, chapter markers, custom HTML overlays, and `screencast.showOverlays()` / `hideOverlays()`. Useful for agent self-verification: a coding agent can hand off a reviewable video receipt. |
| v1.59 | `--debug=cli` | Pause-and-attach so an agent can step through a test |
| v1.60 | `locator.drop()` | Simulate an external file/clipboard drag-and-drop onto an element |
| v1.60 | `tracing.startHar()` | HAR recording as a first-class tracing API |

### Letting AI help author tests: Test Agents vs MCP

There are two distinct integration routes, and the right one depends on whether the agent operates *inside* the editor's own loop or needs to *control* a live browser from outside it.

**Route A — Test Agents**, via `npx playwright init-agents --loop=claude`, scaffolds planner, generator, and healer agents that the coding agent pulls in during its own loop. This is the lighter-weight option — no MCP server, no cross-process JSON traffic — and fits the "have Claude/VS Code/opencode write my Playwright tests" use case well.

**Route B — `@playwright/mcp`** stands up an MCP server that exposes browser actions to any MCP-capable agent. It costs more overhead (a process boundary, JSON marshalling both ways), but it's the correct choice when the agent needs to interactively drive a real, live browser rather than author tests offline. Configure it via `{ "mcpServers": { "playwright": { "command": "npx", "args": ["@playwright/mcp@latest"] } } }` in `.mcp.json`.

Repairing a failing test at runtime belongs to `test-reliability`; generating an initial suite from a PRD or spec belongs to `ai-test-generation`.

---

## Mistakes That Rot a Suite Over Time

These are design-level traps, not one-off bugs — they compound quietly. The full catalog of runtime "never do X" rules with BAD/GOOD code pairs lives in `references/anti-patterns.md`; load it whenever you're actually writing test bodies.

### 1. One page object to rule them all
Consolidating the whole application into a single class eventually produces an unmanageable multi-thousand-line file that every test imports and nobody can safely touch. Break it apart by page or feature, and build up complex pages from composed component objects.

### 2. Letting page objects make assertions
If a page object method calls `expect` internally, the assertion is hidden from the test that triggered it — a failure's stack trace then points into the page object rather than at the scenario that actually broke. Page objects should hand back locators or values; the test itself should be the one asserting.

### 3. Coupling assertions to implementation details
Tests that key off CSS class names, DOM nesting depth, or internal element IDs will break on any refactor, even one that changes nothing a user would notice. Assert against what's user-visible instead: text content, ARIA roles, URLs.

### 4. Fixtures that secretly depend on execution order
A fixture that touches shared module-level state, or silently assumes some other test ran beforehand, will fail as soon as tests run in parallel or in isolation. Every fixture needs to be self-sufficient.

### 5. Reaching for `data-testid` when `getByRole` already works
Tagging buttons and headings that already carry an accessible name with test ids throws away a free, low-cost accessibility signal. Save `getByTestId` for elements that genuinely lack a stable role or label.

Of all of these, the most costly mistake at *runtime* is synchronizing with a fixed `waitForTimeout` instead of trusting an auto-waiting locator:

```typescript
// BAD — needlessly slow on fast machines, still flaky on slow ones, and hides what's really being waited on
await page.waitForTimeout(2000);
await page.click('#submit');

// GOOD — the locator's action waits for actionability on its own
await page.getByRole('button', { name: 'Submit' }).click();
```

Nine further code-level offenders — CSS selectors instead of roles, legacy `page.*` calls instead of locators, `force: true`, shared mutable state, re-logging-in per test instead of reusing storageState, unguarded `locator.all()`, `allTextContents()` in place of `toHaveText()`, calling out to real third-party services, and committed `test.only` — are cataloged in `references/anti-patterns.md`.

---

## Checking Your Work

Run these checks against whatever you generated, cheapest first:

```bash
npx playwright test --list                 # tests are discovered and parse
grep -rn 'waitForTimeout\|page.pause' e2e/  # must print nothing
npx tsc --noEmit                            # locator/assertion types compile
```

To turn these prose-level bans into an enforced lint failure in CI, enable `eslint-plugin-playwright`'s `no-wait-for-timeout`, `no-force-option`, `no-element-handle`, and `no-page-pause` rules.

---

## Signs the Work Is Done

- `playwright.config.ts` is in place with `projects` covering at minimum Chromium (add Firefox and WebKit once targeting CI), and `forbidOnly: !!process.env.CI` is set.
- Page objects live under `e2e/pages/` (or an equivalent folder), components are composed from a root `Locator`, and no POM method calls `expect`.
- `grep -rn 'waitForTimeout' e2e/` comes back empty, and `no-wait-for-timeout` is turned on in `eslint-plugin-playwright`.
- Locators are consistently `getByRole` / `getByLabel` / `getByTestId` — `grep -rn 'page.locator(\|xpath=\|css=' e2e/` finds nothing (aside from a few justified, commented exceptions).
- The suite runs in CI on every PR; once the team is at `growing` maturity or beyond, it shards across matrix jobs, uses the `blob` reporter with a `merge-reports` step, and uploads the resulting HTML report as an artifact when a run fails.

## Where to Go for Adjacent Concerns

- **visual-testing** covers screenshot baseline lifecycle, threshold tuning, and review/approval flow — anything beyond a single inline `toHaveScreenshot` call belongs there.
- **accessibility-testing** owns WCAG conformance levels, axe rule tuning, and remediation guidance; what's shown here is just a minimal scan.
- **api-testing** handles backend API validation, schema/contract testing, and the broader `APIRequestContext` toolkit.
- **ci-cd-integration** is where pipeline configuration, parallelization strategy, and reporting beyond what Playwright provides natively live.
- **test-reliability** deals with healing a single flaky test at runtime — quarantining it, tuning retry strategy.
- **selector-drift-recovery** handles bulk, offline regeneration of selectors after a UI refactor invalidates many tests at once.

### What's in `references/`

| File | Purpose |
|------|---------|
| `anti-patterns.md` | BAD vs GOOD code pairs for every code-level mistake |
| `fixtures-and-projects.md` | Auth fixtures, data fixtures, multi-env projects, composition |
| `selector-strategies.md` | Locator decision tree, `getByRole` examples, stability scoring |
| `auth-patterns.md` | storageState, multi-role, token seeding, session expiry |
| `multi-site-architecture.md` | Shared fixtures, per-site config, monorepo patterns |
| `network-and-mocking.md` | `page.route`, `route.fetch`, HAR, WebSocket, conditional routing |
| `debugging-and-triage.md` | Trace viewer, flaky-test triage, retries, artifacts |
| `ci-recipes.md` | Reporters, sharding + merge, `--only-changed`, browser caching, Docker |
