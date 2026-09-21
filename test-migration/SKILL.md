---
name: test-migration
description: >-
  Move an existing test suite onto a different framework step by step, keeping coverage intact along the way.
  Handles the Selenium→Playwright, Cypress→Playwright, Jest→Vitest, Mocha→Vitest, and Protractor→Playwright paths,
  including side-by-side CI execution, locator/assertion translation, and a coverage-parity tracking process.
  Use when: "migrate tests," "switch framework," "Selenium to Playwright," "Jest to Vitest," "framework migration."
  Not for: regenerating selectors in bulk after a UI refactor when the framework itself isn't changing — that's selector-drift-recovery.
  Not for: fixing a single flaky test at runtime — see test-reliability. Not for: modernizing patterns while staying on the same framework — see ai-qa-review.
  Related: playwright-automation, cypress-automation, unit-testing, ci-cd-integration, test-reliability.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: knowledge
---

<objective>
Coverage has a way of quietly evaporating during a framework switch: a suite of twenty old tests turns into fifteen new ones, a Selenium test that used to flake gets faithfully reproduced as a flaky Playwright test, and the old suite that was acting as a safety net gets retired a sprint too soon. The approach here is to migrate one piece at a time and keep both suites running in CI until the numbers prove the new suite has actually caught up — retiring the old framework has to be earned with evidence, never just declared.
</objective>

---

## Where to Start

| Moving from → to | Go to | Best first-pass tool |
|------------------------|---------|--------------------|
| Selenium → Playwright | Translation Patterns + `references/framework-guides.md` | hand-write; no codemod here is trustworthy |
| Cypress → Playwright | Translation Patterns + `references/framework-guides.md` | cy2pw web converter / community CLI (see tooling table) |
| Protractor → Playwright | `references/framework-guides.md` (urgent — EOL 2023) | hand-write; map `by.model`/`by.binding` |
| Jest → Vitest | `references/framework-guides.md` | `jest.`→`vi.` sed pass, then verify |
| Mocha → Vitest | `references/framework-guides.md` | chai-matcher codemod, then verify |
| Any path, 100+ tests | Migration Workflow + Parallel Running Strategy | always run both suites in CI in parallel |

---

## Questions to Ask Before Starting

Check `.agents/qa-project-context.md` first — if it's there, treat it as the source of truth and skip anything it already answers.

**Where things stand today:**
- Which framework is the source and which is the target? This decides which translation tables and guide section you need.
- How many tests exist, and how flaky or frequently skipped are they? A flaky test migrates into another flaky test unless you fix it first, and a skipped test may not be worth carrying over at all.
- Do you already have a coverage number? You'll need it as the baseline the new suite has to match.

**Supporting infrastructure:**
- What infrastructure sits underneath the tests — page objects, custom commands, fixtures, data factories? These have to move *before* the tests that depend on them.
- How does auth/session currently work? Login flows are the single most common place migrations silently break — see Failure Modes below.
- What does the CI pipeline look like, and can it run both frameworks side by side? Running them in parallel isn't optional.

**Constraints that shape the plan:**
- Is there a hard deadline? (Framework end-of-life, like Protractor, makes this urgent; otherwise it's just modernization.)
- Is there budget to run two suites in CI simultaneously for a while? Expect a temporary doubling of CI cost.
- How comfortable is the team with the target framework already? Any gap here determines whether you need a workshop or pairing plan.

---

## Guiding Principles

### 1. Go incrementally, not all at once

Rewriting the entire suite in one shot is the riskiest path available: it halts test development for weeks, dumps a huge batch of unproven tests into the pipeline all at once, and pulls the working safety net out before its replacement exists. Migrate test by test, module by module instead.

### 2. Keep both suites running until parity is proven

Both suites should run in CI until the new one covers at least as much as the old one did. Treat the old suite as your insurance policy — non-blocking, but still present — and don't retire it until the new suite has demonstrably caught real regressions across more than one sprint.

### 3. Front-load the highest-value tests

Tackle critical user journeys, chronically-failing tests (these gain the most from a better framework), and high-risk areas first. Low-value tests can wait until the end — and some of them may not be worth migrating at all, which is a legitimate, documentable call.

### 4. Use the migration as a chance to modernize, not just translate

Porting a poorly-written Selenium test into an equally poorly-written Playwright test wastes the opportunity in front of you. For every test, ask yourself how you'd write it if you were starting from scratch in the target framework — user-facing locators, auto-waiting, fixtures instead of ad-hoc setup. This matters even more when an AI codemod produced the first draft (see Anti-Patterns).

---

## The Six-Phase Playbook

A typical multi-sprint migration breaks into six phases. Use the checklists below as your working list; the heavier code samples live in the reference files.

**Phase 1 — Audit what you have (Week 1).** Count tests by category, note the skip/flake rate, record coverage if it's measured, capture runtime, and inventory page-object/utility files, custom plugins, and CI stages. Then sort every test into a bucket: *Critical* (revenue-impacting) → *High* (core journeys) → *Medium* (secondary flows) → *Low* (admin/edge cases) → *Skip* (disabled, duplicated, obsolete). This ordering drives every phase after it.

**Phase 2 — Stand up the target framework (Week 1-2).** Install it next to the existing one: write the config (`playwright.config.ts` / `vitest.config.ts`), give it its own test directory, wire up a non-blocking CI stage, prove the setup with one smoke test, match reporters to the current format, and share env vars/secrets across both.

**Phase 3 — Move the shared infrastructure first (Week 2-3).** Order matters here: base page object/test base → auth helpers → API client helpers → common page objects (nav/header/footer) → data factories → custom assertions → feature-specific page objects (paired with their tests). **This is also where you should capture `storageState`**, so every migrated test afterward can skip re-running the login flow.

**Phase 4 — Migrate tests in priority order (Week 3-8+).** For each test: read the original and figure out what it's *actually* checking → write the replacement from scratch using modern patterns rather than translating line by line → confirm it's green locally → confirm it's green in CI → mark the old one "migrated" instead of deleting it → once it's passed alongside the new one for a full sprint, delete it.

**Phase 5 — Run both suites in CI throughout.** Every pipeline run exercises both suites. Keep the legacy suite non-blocking (`continue-on-error: true`) until the new suite hits parity, then flip the blocking flag to the new suite and drop the old CI job. The complete GitHub Actions setup is in `references/parallel-ci.md`.

**Phase 6 — Retire the old framework (final phase).** Only once parity and stability are both proven: every critical/high test has moved over, the new suite has been green in CI for 2+ consecutive sprints, its flakiness is no worse than the old suite's, the coverage comparison shows nothing lost, and the team has been writing new tests exclusively in the new framework for 2+ sprints. At that point: remove the old dependencies from `package.json`, delete (don't just disable) the old test files, point CI at only the new suite, and update the documentation.

---

## Tooling for the First Pass

There's no magic AI button that does this for you. Choose an appropriate first-pass tool for your specific path, then hand-refine the output using `references/framework-guides.md`.

| Tool | Good for | Not reliable for |
|------|----------|-----------------|
| **cy2pw web converter** ([demo.playwright.dev/cy2pw](https://demo.playwright.dev/cy2pw/)) | Cypress→Playwright on straightforward specs; official, deterministic, browser-based | custom commands, POM conventions, fixture setup |
| **`@11joselu/cypress-to-playwright`** (community CLI, `npx @11joselu/cypress-to-playwright <dir>`) | a bulk first pass over a Cypress→Playwright directory | anything timing-sensitive — review every file it touches |
| **AI agents** (Claude Code, Cursor) | translating custom commands and fixtures — the parts converters can't handle | producing a finished test — treat its output as a first draft only |
| **Playwright 1.59+ agentic CLI** (`npx playwright trace`, `--debug=cli`, AI-optimized a11y snapshots) | triaging a failing test *after* it's already been migrated | performing the migration itself — these are debugging tools, not converters |

> **Skip this one:** `npx playwright migrate` doesn't exist as a built-in Playwright command; typing it just fails at the terminal (verified June 2026). Reach for cy2pw or the community CLI instead.

**Build a golden reference first.** Before turning any AI tool or codemod loose on the whole suite, hand-migrate one representative test from start to finish and commit it as the team's canonical example (e.g. `e2e/_golden/login.spec.ts`). Use it as the few-shot example you feed the AI, and point reviewers at it too. Every subsequent migration should be checked against this file — it's the single most effective way to keep both AI output and human review consistent.

---

## Pattern Translation Reference

### Mapping locators

| Old Pattern | New Pattern (Playwright) | Notes |
|-------------|--------------------------|-------|
| `By.id('submit-btn')` | `page.getByRole('button', { name: 'Submit' })` | Role-based is preferred |
| `By.css('.nav-item.active')` | `page.getByRole('link', { name: 'Dashboard' })` | Match on user-visible text |
| `By.xpath('//div[@class="modal"]')` | `page.getByRole('dialog')` | ARIA roles hold up better over time |
| `By.css('[data-testid="user-menu"]')` | `page.getByTestId('user-menu')` | Test IDs are a reasonable fallback |
| `cy.get('.product-card').first()` | `page.getByRole('article').first()` | Prefer semantic elements |
| `cy.contains('Add to cart')` | `page.getByRole('button', { name: 'Add to cart' })` | A specific role beats free text |
| `element(by.model('username'))` | `page.getByLabel('Username')` | Angular model binds to the field's label |

The role/label names in this table are illustrative — swap in whatever accessible name your app actually renders.

### Mapping wait strategies

| Old Pattern | New Pattern (Playwright) | Notes |
|-------------|--------------------------|-------|
| `Thread.sleep(3000)` | *(delete it)* | Playwright auto-waits |
| `WebDriverWait(driver, 10).until(visible)` | *(delete it)* | Actions auto-wait |
| `cy.wait(2000)` | *(delete it)* | Assertions auto-wait |
| `cy.wait('@apiCall')` | `page.waitForResponse(/\/api\/data/)` | An explicit network wait — start the promise before triggering the action |
| `browser.wait(EC.presenceOf(...))` | `await expect(locator).toBeVisible()` | A web-first assertion |
| `implicitlyWait(10, SECONDS)` | *(delete it — set this in config instead)* | Use `actionTimeout` |
| `FluentWait` with polling | `await expect(locator).toHaveText('Done')` | Web-first assertions already retry |

### Mapping assertions

| Old Pattern | New Pattern (Playwright) | Notes |
|-------------|--------------------------|-------|
| `assert element.is_displayed()` | `await expect(locator).toBeVisible()` | Retries automatically |
| `cy.get('.msg').should('have.text', 'Done')` | `await expect(locator).toHaveText('Done')` | Retries automatically |
| `expect(element.getText()).toBe('Done')` | `await expect(locator).toHaveText('Done')` | Retries automatically |
| `cy.url().should('include', '/dashboard')` | `await expect(page).toHaveURL(/dashboard/)` | Retries automatically |
| `assert len(elements) == 5` | `await expect(locator).toHaveCount(5)` | Retries automatically |

### Mapping config (Cypress → Playwright)

| Old (Cypress) | New (Playwright) |
|---------------|-------------------|
| `baseUrl` | `use.baseURL` |
| `defaultCommandTimeout: 10000` | `use.actionTimeout: 10000` |
| `pageLoadTimeout: 30000` | `use.navigationTimeout: 30000` |
| `retries: { runMode: 2 }` | `retries: 2` |
| `video: true` | `use.video: 'on'` |
| `screenshotOnRunFailure: true` | `use.screenshot: 'only-on-failure'` |

---

## Path-by-Path Notes

The full before/after code and per-path checklist for each route live in `references/framework-guides.md`. Here's the short version of what changes:

- **Selenium → Playwright:** drop every explicit wait (Playwright auto-waits), swap string-based locators for `getByRole`/`getByLabel`/`getByTestId`, and replace WebDriver sessions with `BrowserContext`. Capture `storageState` rather than rebuilding the login flow in each test.
- **Jest → Vitest** (target Vitest 4.x): largely API-compatible — swap `jest.` for `vi.`, turn `jest.config.js` into `vitest.config.ts`, and drop Babel/ts-jest transforms (unless you rely on custom Babel plugins like emotion/styled-components macros, in which case keep an esbuild/SWC equivalent). Expect runs to get 2-10x faster. Vitest 4.1's test `tags` support an incremental cutover.
- **Cypress → Playwright** (target PW ≥ 1.50): the core shift is moving from a command queue to async/await. `cy.intercept()`+`cy.wait()` becomes `page.route()`+`page.waitForResponse()`, and custom commands become fixtures. Watch out for the 1.52 changes to `page.route()` globs and the Cookie-header behavior (set cookies via `browserContext.addCookies()`, not a header override).
- **Mocha → Vitest:** nearly a 1:1 port. `describe`/`it`/hooks carry over unchanged; convert chai matchers (`to.equal`→`toBe`, `to.deep.equal`→`toEqual`, `to.contain`→`toContain`) and swap `sinon` for `vi.fn()`/`vi.spyOn()`.
- **Protractor → Playwright:** end-of-life since 2023, so treat this as urgent. Remove `waitForAngular`, map `by.model`/`by.binding` onto `getByLabel`/`getByText`/`getByTestId`, and replace `onPrepare` with `globalSetup`.

---

## Running Both Suites at Once

### Tracking coverage parity as you go

Keep a running spreadsheet comparing the old and new suites so nothing quietly falls through the cracks. This is also your objective evidence when it's time to decide on decommissioning.

```
Feature Area     | Old Suite Tests | New Suite Tests | Parity | Notes
Login/Auth       | 8               | 8               | 100%   | Complete
Dashboard        | 12              | 7               | 58%    | In progress
Search           | 6               | 0               | 0%     | Not started
Checkout         | 15              | 15              | 100%   | Complete
User Settings    | 4               | 4               | 100%   | Complete
Admin Panel      | 20              | 0               | 0%     | Low priority
---              | ---             | ---             | ---    |
Total            | 65              | 34              | 52%    | On track for Q2
```

### A sample cutover timeline

For a 200-test suite, a rough 10-sprint plan looks like: setup and infrastructure in Sprints 1-2, critical-path tests in Sprints 3-5 (roughly 50 tests), the bulk of the remaining tests in Sprints 6-8, and cleanup plus decommissioning in Sprints 9-10. The old suite starts out blocking and shifts to non-blocking as parity gets closer. From Sprint 3 onward, all new tests get written directly in the new framework.

### Deciding when to delete an old test

Don't delete an old test the moment its replacement exists — tag it "migrated" instead. Only delete it once the new version has run green in CI for 2+ weeks and someone has manually confirmed no unique assertions were lost in translation. If the old test ever catches something the new one misses, strengthen the new test before deleting anything.

---

## Pitfalls to Avoid

### Rewriting everything in one go

Freezing test development for three months to rewrite the entire suite at once. New tests can't ship during the freeze, coverage stalls, and the replacement suite sits untested in CI until it lands all together.

**Instead:** migrate incrementally with both suites running in parallel. One module per sprint. Both suites stay in CI the whole time. New tests go straight into the new framework from day one.

### Translating without modernizing

Porting Selenium tests into Playwright line by line, explicit waits, CSS selectors, fragile patterns and all. The framework changed but none of the underlying problems did.

**Instead:** rewrite each test with the target framework's idioms — `getByRole` instead of CSS selectors, no explicit waits, fixtures instead of `beforeEach` boilerplate. Treat the migration as a chance to make every test better.

### Treating an AI codemod's output as final

Cursor, Aider, Continue, Claude Code, and tools like cy2pw or the community converters all do mechanical translation reasonably well, but the quality is inconsistent — and the "translate instead of modernize" trap applies to their output even more than to human work.

**Instead:** run the tool on a single file first and diff it against the source. If it modernized well, batch the rest through it. If it just did a literal translation, write your own golden-reference file and feed that back as a few-shot example. After every batch, run it in parallel against the original suite — any divergence in results means the tool got something wrong, so investigate before promoting it further.

### Skipping the parallel run

Retiring the old suite before the new one has proven itself, and a regression slips through because the new suite was quietly missing a test the old one had.

**Instead:** keep both suites in CI for at least 2 sprints past the point where parity is reached. The old suite is cheap insurance. Only retire it once the new suite has caught real regressions on its own.

### Letting coverage shrink during the move

Twenty old tests quietly become fifteen new ones because "some were redundant" — without anyone actually verifying the deleted ones weren't covering something unique.

**Instead:** map every old test to its new counterpart explicitly in the coverage spreadsheet. If you deliberately decide not to migrate a test, write down why, and confirm its coverage exists somewhere else.

### Carrying flakiness over as-is

A test that flakes in Selenium will keep flaking in Playwright if the root cause is how the test itself is built — shared state, timing assumptions, non-deterministic data. A faithful translation just reproduces the same flakiness in a new syntax.

**Instead:** diagnose the flakiness before you migrate, fix the underlying cause, and write the new test with that fix already built in. Migration is the best possible moment to deal with flakiness, since you're rewriting the test anyway. For fixing a single flaky test at runtime rather than during a migration, see `test-reliability`.

### Skipping team training

Moving to Playwright when nobody on the team has used it before means the one or two people who know it end up writing everything, and everyone else can't maintain what gets shipped.

**Instead:** run a short (roughly 2-hour) workshop before starting. Pair a champion with a team member for the first ten migrated tests. Write down a team style guide for the new framework. Require at least two reviewers on every migrated test.

---

## Troubleshooting Table

| Symptom | Likely cause | Fix or check |
|---------|--------------|--------------|
| Migrated test logs in fresh each run / loses its session mid-test | No `storageState` — the login flow never got carried over | Capture `storageState` in `globalSetup` and reuse it per test. `cy.setCookie`/`driver.add_cookie` → `browserContext.addCookies()` |
| `npx playwright migrate` errors with "unknown command" | That CLI command doesn't exist | Use the cy2pw web converter or `@11joselu/cypress-to-playwright` instead |
| A migrated intercept never matches | The 1.52 glob change dropped support for `?`/`[]` | Escape those characters or rewrite the route as a regex |
| Cookies set via `route.continue()` are ignored | The Cookie header on `route.continue()` comes from the cookie store, not your override | Set cookies through `browserContext.addCookies()` |
| New test passes locally but flakes in CI | An old timing assumption got carried over literally | Swap `waitForTimeout`/explicit waits for web-first `expect(...)` assertions |
| Test count drops after running a codemod | The codemod silently skipped syntax it didn't support | Diff the per-feature-area test counts against the parity sheet before promoting the pass |

---

## How to Confirm It Worked

Verify from the smallest check up to the whole pipeline:

- **The migrated test actually passes:** `npx playwright test <migrated-file>` (or `npx vitest run <migrated-file>`) exits 0. A green run is the baseline, not proof you're done.
- **No tests quietly disappeared:** diff the new vs. old test count per feature area against the coverage spreadsheet, confirming the "New Suite Tests" column matches what actually ran (`npx playwright test --list | wc -l` per area).
- **Both suites are actually running in CI:** the parallel-run workflow shows the legacy job marked `continue-on-error: true` and the new job as blocking, both visible in the same pipeline run.
- **Nothing regressed:** the new suite stays green for 2+ consecutive sprint CI runs before you delete any old test.

---

## Definition of Done

- The migration scope is explicit: which tests move first (critical paths), which move last (low priority), and which are deliberately staying behind — each with a documented reason in the coverage spreadsheet.
- The coverage-parity spreadsheet shows 100% for every critical/high feature area, with no drop in test count versus the old suite's mapped tests.
- Both frameworks have run side by side in CI for at least 2 consecutive sprints, with the new suite green throughout.
- A retrospective document exists covering flakiness root causes found along the way, pattern improvements made, and any remaining gaps in team training.
- The old framework is completely gone: its dependencies removed from `package.json`, its test files deleted (not merely disabled), and CI updated to run only the new suite.

---

## Reference Files (in `references/`)

- **framework-guides.md** — complete before/after code plus a migration-notes checklist for each of the five supported paths: Selenium→Playwright, Jest→Vitest, Cypress→Playwright, Mocha→Vitest, Protractor→Playwright.
- **parallel-ci.md** — the GitHub Actions setup for running the old and new frameworks side by side in CI while the migration is in progress.

## Related Skills

- **playwright-automation** — idiomatic target-framework practices once a Selenium/Cypress/Protractor test has been translated; go here to polish the result.
- **cypress-automation** — for migrating *into* Cypress, or when you need deeper source-side Cypress detail.
- **unit-testing** — the fuller picture on Jest→Vitest patterns, mocks, and coverage configuration.
- **test-reliability** — for healing one flaky test at runtime; reach for it when a migration surfaces flakiness that needs triage rather than a rewrite.
- **selector-drift-recovery** — bulk selector regeneration after a UI refactor on the *same* framework, not a framework change.
- **ci-cd-integration** — the parallel-CI configuration details for running both suites during a migration.
- **qa-metrics** — for tracking migration progress over time: test-count parity, flakiness trends, coverage delta.
- **test-strategy** — migration decisions should line up with the broader multi-quarter test strategy.
</content>
