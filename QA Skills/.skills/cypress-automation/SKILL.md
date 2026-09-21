---
name: cypress-automation
description: >-
  Build Cypress test suites in TypeScript: E2E tests, component tests, custom commands,
  cy.intercept network control, cy.session login, Cypress Cloud, and CI integration.
  Covers retry-ability, the command queue, cross-origin flows with cy.origin, and
  data-driven testing with fixtures.
  Use when: "write E2E test in Cypress," "Cypress page object / custom command," "cy.,"
  "cy.intercept," "Cypress component test," "Cypress Cloud," "cypress.config.ts."
  Not for: Playwright suites — use playwright-automation; flaky-test healing or quarantine —
  use test-reliability; bulk selector regeneration after a UI refactor — use selector-drift-recovery;
  Selenium-to-Cypress conversion — use test-migration.
  Related: playwright-automation, ci-cd-integration, visual-testing, unit-testing, test-reliability.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: automation
---

<objective>
This skill exists to stop a specific, recurring failure: teams write Cypress specs as though commands run synchronously — assigning `cy.get()` to a variable, sticking `await` in front of `cy.click()` — and then paper over the resulting flakiness with `cy.wait(3000)` instead of waiting on a real network signal. What follows is the mental model that avoids that trap (the command queue, built-in retry-ability), how to lay out a Cypress + TypeScript project, how to build typed custom commands, how to control the network with `cy.intercept`, how to test components in isolation, how to handle cross-origin auth with `cy.origin`, and how to wire the suite into CI and Cypress Cloud.
</objective>

## Where To Go For What

| Goal | Read |
|----------------|-------|
| Write an E2E spec that loads a page, intercepts a call, and asserts | Core Principles below, then `references/intercept-patterns.md` |
| Build a typed custom command or a `cy.session`-based login | Custom Commands below, then `references/config-and-commands.md` |
| Mount and exercise one component | Component Testing below, then `references/component-and-fixtures.md` |
| Set up `cypress.config.ts` and the folder layout | Project Structure below, then `references/config-and-commands.md` |
| Stub a response, spy on a request, simulate an outage, or poll | cy.intercept Patterns below, then `references/intercept-patterns.md` |
| Run headless in CI or parallelize with Cypress Cloud | CI Integration below, then `references/ci-recipes.md` |
| Deal with an SSO/OAuth redirect during login | Cross-Origin Flows below, then `references/intercept-patterns.md` |

---

## Questions To Settle Before Writing Anything

Look first for `.agents/qa-project-context.md` — if it's there, treat its answers as given and only ask about what it leaves open.

1. **Component tests, E2E, or both?** Component tests mount one piece of UI in isolation; E2E drives the whole app through a real browser. Most codebases want both, and component testing needs a mount adapter matched to the framework (React, Vue, Angular, Svelte).
2. **Is Cypress Cloud in play?** It buys parallel runs, flake detection, analytics, Test Replay, and the AI add-on. If the team already pays for it, wire up `projectId` and a record key; otherwise the suite runs fine locally or in plain CI without it.
3. **TypeScript?** Assume yes — it's native to Cypress and every example below uses it.
4. **Which framework/bundler pair?** React+Vite, Next.js+Webpack, Vue+Vite, Angular — this decides the `component.devServer` settings.
5. **Does login cross a domain?** SSO or an external OAuth provider means the login flow needs `cy.origin`; flag this early so the login command is built with it from the start.
6. **Greenfield or existing suite?** When migrating an existing suite, triage the flakiest or highest-value specs first rather than attempting a single big rewrite (hand that off to `test-migration` if it's a cross-framework port).

---

## Core Principles

### 1. A Command Is Queued, Not Run on the Spot

This is the concept everything else depends on. Calling `cy.get`, `cy.click`, `cy.type` doesn't execute anything immediately — it appends to an internal queue that Cypress drains serially and asynchronously. That means `async/await` around Cypress commands doesn't do what it looks like it does, and you can't capture a command's "return value" in a plain variable.

```typescript
// WRONG -- looks synchronous, isn't
const button = cy.get('[data-testid="submit"]'); // this is a Chainable, not a DOM node
button.click(); // "works" only because chaining happens to line up

// RIGHT -- chain instead, and drop into .then() when you actually need a value
cy.get('[data-testid="submit"]').click();

cy.get('[data-testid="price"]').invoke('text').then((text) => {
  const price = parseFloat(text.replace('$', ''));
  expect(price).to.be.greaterThan(0);
});
```

### 2. Built-in Retries Cover Queries and Assertions, Not Actions

Cypress keeps re-running **queries** (`cy.get`, `cy.find`, `cy.contains`) and **assertions** until they pass or the timeout expires. **Actions** (`cy.click`, `cy.type`, `cy.select`) get no such treatment — they fire once:

- `cy.get('.loading').should('not.exist')` polls until the spinner is gone
- `cy.get('.item').should('have.length', 5)` polls until there are 5 items
- `cy.click()` fires a single click; if the element isn't actionable yet, the test just fails

### 3. cy.intercept Owns the Network Layer

`cy.intercept` sits at the network boundary: it can stub a response, block until a request finishes, and inspect the body that went out. Getting comfortable with it is what separates a stable suite from a flaky one — always synchronize on a network alias or a DOM state, never on a hardcoded `cy.wait(ms)`.

### 4. Every Test Gets a Clean Slate

Cypress wipes cookies, localStorage, and sessionStorage between every `it()` by default, so no test should depend on another test having run first (or at all). Shared setup belongs in `beforeEach`, not in cross-test state.

### 5. Select Elements by Data Attribute, Not by Style

Prefer `data-testid`, `data-cy`, or `data-test` over class names or DOM structure — they survive CSS rewrites, renamed classes, and translated copy. Set the preferred attribute name once in `cypress.config.ts`.

---

## Project Structure & Configuration

A conventional layout separates `e2e/`, `component/`, `fixtures/`, and `support/` under `cypress/`, with a single `cypress.config.ts` at the repo root configuring both the E2E and component runners. The choices that matter most: read `baseUrl` from an environment variable rather than hardcoding it (CI needs a different host than local dev), set an explicit viewport, turn on `retries.runMode: 2` for CI runs, and pick the right framework/bundler pair for `component.devServer`. Component spec files live at `cypress/component/**/*.cy.tsx`.

Full directory tree, the complete config file, and the `tsconfig.json` additions are in `references/config-and-commands.md`.

---

## Custom Commands

Wrap repeated interactions in a small, typed API rather than repeating raw command chains everywhere. The usual set: a `login` command built on `cy.session` plus a direct API call (not driving the login form through the UI), a `getByTestId` shorthand, and assertion helpers such as `shouldShowToast`. Declare their types in `cypress/support/index.d.ts` — extend `Cypress.Chainable` with JSDoc `@example` blocks — so callers get autocomplete and the compiler catches misuse.

**A `cy.session` call is incomplete without `validate()`.** `cy.session` transparently caches cookies, localStorage, and sessionStorage, but it will keep handing back that cached session forever unless you give it a `validate()` callback to re-check it — skip that, and an expired or revoked token gets silently reused as if it still worked. Always supply a `validate()` that pings an authenticated endpoint, e.g. `cy.request('/api/me').its('status').should('eq', 200)`.

**Custom retryable lookups need `Cypress.Commands.addQuery()`, and its callback must be written as `function () {}`, never an arrow function.** Cypress relies on binding `this` inside that callback to enforce the command timeout; an arrow function has no own `this`, so retry-ability quietly breaks. (This rule flips for intercept handlers — `(req) => {}` is the right shape there, since they never touch `this`.)

Full command implementations, the `validate()` example, the `addQuery` pattern, and the TypeScript declaration block are all in `references/config-and-commands.md`.

---

## cy.intercept Patterns

The full toolkit for controlling network traffic in a test:

- **Stubbing** — hand back canned data via `{ statusCode, body }`, then block on it with `cy.wait('@alias')`.
- **Spying without stubbing** — `cy.intercept('POST', '/api/orders').as('createOrder')`, then inspect `interception.request.body` and `interception.response?.statusCode` after the wait resolves.
- **Conditional/polling responses** — use a `callCount` closure to flip a response from "still processing" to "done," simulating a polling endpoint. Here the handler should be an arrow function `(req) => { ... }`.
- **Simulated failures** — `{ statusCode: 500 }` for a server error, `{ forceNetworkError: true }` for a dropped connection, or `req.reply({ delay })` to simulate latency.
- **Rewriting a real response in flight** — `req.continue((res) => { ...; res.send(); })`.
- **Fixture-backed stubs** — `{ fixture: 'api-responses/checkout-success.json' }`.

One rule that trips people up constantly: the `cy.intercept` call has to be registered *before* whatever triggers the request, or the alias simply never matches anything.

Working code for every pattern above, plus the cross-origin recipe, is in `references/intercept-patterns.md`.

---

## Component Testing

A component test mounts one component directly in a real browser, skipping the rest of the application — quicker than a full E2E run, and closer to what the user actually sees than a pure unit test. Call `cy.mount(<Component .../>)`, pass `cy.stub()` or `cy.spy()` in for callback props, and assert with the same `cy.contains` / `cy.get` chains used elsewhere. `cy.visit` has no place in a component spec. Vue components mount with `cy.mount(Component, { props: { ... } })` instead.

A worked example — a full React `ProductCard` test suite — lives in `references/component-and-fixtures.md`.

---

## Data-Driven Testing with Fixtures

There are three tiers of test data, depending on its source:

- **Static fixtures** — `cy.fixture('users').as('users')` for JSON that barely changes; pull it back out via `this.users` inside a `beforeEach(function () { ... })` (note the non-arrow function, needed for `this` to resolve).
- **Dynamically generated data via `cy.task`** — register a Node-side task in `setupNodeEvents` for anything that has to happen outside the browser sandbox, like hitting an internal API or seeding a database. Because task bodies execute in the Node process, `fetch` inside one is Node's own global `fetch`, not a Cypress-provided API.
- **Per-environment configuration** — build a lookup table of environment-specific settings (e.g. `baseUrl`) inside `setupNodeEvents`, and pick an entry based on `--env ENVIRONMENT=...` at run time.

The fixture example, the `cy.task` seeding pattern, and the environment-config snippet are all in `references/component-and-fixtures.md`.

---

## Cross-Origin Flows

When a login flow legitimately redirects somewhere else — an SSO provider, an OAuth host, a separate auth subdomain — wrap whatever runs on that other origin in `cy.origin`. This is the modern replacement for the old workaround of flipping `chromeWebSecurity: false` or relying on `experimentalSessionAndOrigin`; don't reach for either of those to paper over a redirect. Keep this separate in your head from third-party payment iframes (Stripe, PayPal, etc.) — those get stubbed with `cy.intercept` from the outside; you never interact with their DOM directly.

The runnable `cy.origin` example is under "Cross-Origin Flows" in `references/intercept-patterns.md`.

---

## CI Integration

**Which action version to pin:** use `cypress-io/github-action@v7` (currently at 7.2.0, as of May 2026). It runs on Node 24 and is the actively maintained major version; drop to `@v6` only if your runner is stuck on Node 20 — that's the legacy branch, not a current alternative.

> **Cypress/Node compatibility today:** Cypress 15.x supports Node 20, 22, and 24 (Node 18 and 23 are no longer supported). Losing Node 20 support entirely is slated for a future Cypress 16 / action-v7.2 release tied to Node 20's EOL on 2026-04-30 — it hasn't happened in Cypress 15.

- **Running with Cypress Cloud:** configure `projectId`, invoke `npx cypress run --record --key $CYPRESS_RECORD_KEY`, and spread the run across a container matrix with `fail-fast: false` to get parallelization, flake detection, Test Replay, and analytics.
- **Running without Cloud:** `cypress-io/github-action@v7` handles `build`/`start`/`wait-on`, and you upload `cypress/screenshots` plus `cypress/videos` as artifacts whenever the job fails.

Both complete workflow files are in `references/ci-recipes.md`.

**On the Cypress AI add-on** (a paid Cloud feature, GA as of 2026): it bundles Auto Heal (selectors that repair themselves), AI-driven test generation, and AI-assisted bug triage. Two pieces worth flagging specifically now that they're GA: `cy.prompt`, which authors tests from plain English and self-heals at runtime, and **Cloud MCP** (GA May 2026, included free on every Cloud plan), an MCP server that streams recorded-run failures, stack traces, and Test Replay links straight to an AI assistant. This functionality overlaps with what `test-reliability` (selector healing), `ai-bug-triage` (clustering failures), and `ai-test-generation` (writing tests) already do — if the team is already paying for Cypress Cloud, it may well be cheaper to turn on the add-on than to build equivalent tooling, so raise that trade-off during framework selection.

---

## Anti-Patterns

### 1. Synchronizing with cy.wait(milliseconds)

```typescript
// BAD
cy.get('[data-testid="submit"]').click();
cy.wait(3000);

// GOOD -- synchronize on the network instead
cy.intercept('POST', '/api/submit').as('submit');
cy.get('[data-testid="submit"]').click();
cy.wait('@submit');
```

The only legitimate exception is testing a throttle or debounce delay on purpose. Everything else should wait on a network alias or a DOM assertion.

### 2. Branching Test Logic on Current DOM State

Don't inspect `$body.find(selector).length > 0` to decide what to do next. Make the state deterministic instead — stub whichever API call drives that conditional element.

### 3. Relying on CSS Selectors Instead of Data Attributes

`cy.get('.btn.btn-primary > span')` snaps the moment someone touches the CSS. Reach for `cy.getByTestId('submit')` or `cy.contains('button', 'Place Order')` instead.

### 4. Letting Tests Share State

A module-level `let orderId` written by one `it()` and read by another produces tests that only pass in a specific order and can't run in parallel. Have each test create its own data through `cy.request` or `cy.task` inside `beforeEach`.

### 5. Poking at Third-Party Iframes

Leave Stripe/PayPal iframes alone. Intercept the payment API call with `cy.intercept` and check your own app's response to it instead.

### 6. Skipping cy.session() for Login, or Skipping Its validate()

Logging in through the UI on every single test is both slow and brittle. Authenticate once via API using `cy.session` and let it cache the result — but always attach a `validate()` callback, or an expired token will get reused as if it were still good.

### 7. Writing addQuery's Callback as an Arrow Function

`addQuery('name', (arg) => { ... })` quietly loses its retry timeout, because Cypress needs a bindable `this` inside that function to apply it. Write it as `function (arg) { ... }` instead.

### 8. Letting the Whole Suite Run Serially in CI

Once a suite crosses roughly 5 minutes, split it up — via Cypress Cloud, the `cypress-split` plugin, or manual sharding across a CI matrix.

---

## Failure Modes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `element is detached from the DOM` | Held onto a yielded element across a re-render | Re-query inside `.should`/`.then` rather than reusing the stale reference |
| `cy.intercept` never matches / the wait on its alias hangs | Wrong HTTP method or URL glob, or the intercept was registered too late | Register the intercept before whatever triggers the request; double-check method and URL pattern |
| `cross origin` error mid-redirect | The flow jumps to a different domain | Wrap the other-origin steps in `cy.origin` rather than disabling `chromeWebSecurity` |
| Cached session behaves like a logged-out user | `cy.session` has no `validate()` and the token expired | Add a `validate()` callback that checks an authenticated endpoint |
| Custom query hangs / never times out | `addQuery` callback was written as an arrow function | Rewrite it as `function () {}` so `this` binds correctly |

---

## Verification

Before calling a Cypress task finished, confirm it actually runs:

- `npx cypress verify` — confirms the binary is installed and can run.
- `npx cypress run --spec "cypress/e2e/<file>.cy.ts"` — headless CI-mode run should exit 0.
- `npx cypress run --component --spec "cypress/component/<File>.cy.tsx"` — component specs should also exit 0.
- `npx tsc --noEmit` — the custom-command declarations in `index.d.ts` should type-check cleanly against the specs that use them.

---

## Done When

- `cypress.config.ts` reads `baseUrl` from an environment variable (no hardcoded `localhost` that would break CI), sets explicit `viewportWidth`/`viewportHeight`, and `npx cypress verify` passes.
- Custom commands live in `cypress/support/commands.ts` with matching declarations in `cypress/support/index.d.ts`, and `npx tsc --noEmit` exits 0.
- The `login` command is built on `cy.session` and includes a `validate()` callback.
- Nothing in the suite calls `cy.wait(<number>)` to synchronize (`grep -rn "cy.wait([0-9]" cypress/` turns up nothing beyond deliberate, documented throttle/debounce tests).
- Component specs live at `cypress/component/**/*.cy.tsx` and pass under `npx cypress run --component`.
- E2E specs pass in CI (`npx cypress run` exits 0), and failures produce either a recorded Cypress Cloud run (parallelized) or uploaded video/screenshot artifacts.

## Reference Files (in `references/`)

- **config-and-commands.md** — project directory tree, a complete `cypress.config.ts`, and custom commands (`cy.session` with `validate()`, the non-arrow `addQuery`) with their TypeScript declarations.
- **intercept-patterns.md** — every `cy.intercept` recipe (stub, spy, conditional/polling, error simulation, response rewriting, fixture-backed) plus the cross-origin flow.
- **component-and-fixtures.md** — a React component-test suite, plus data-driven testing (static fixtures, `cy.task` seeding, per-environment config).
- **ci-recipes.md** — GitHub Actions workflows on `@v7`, with and without Cypress Cloud, including parallelization and artifact upload.

## Related Skills

- **playwright-automation** — reach for this instead when the suite is Playwright rather than Cypress; same goals, different runner and API.
- **test-reliability** — for runtime flake healing, self-healing locators, and quarantining bad tests. This skill is about writing stable tests in the first place; that one repairs tests that are already failing.
- **selector-drift-recovery** — bulk-regenerates broken selectors after a UI refactor or redesign; this skill covers authoring, not mass repair.
- **test-migration** — for porting Selenium (or other) suites over to Cypress.
- **ci-cd-integration** — broader pipeline templates for GitHub Actions / GitLab CI, parallelization, and artifact handling.
- **visual-testing** — visual regression to pair with Cypress's functional coverage; Cypress itself has no pixel-diffing built in.
- **unit-testing** — Jest/Vitest for logic that doesn't need a browser; Cypress component tests fill the space between unit tests and full E2E.
- **test-data-management** — seeding, maintaining, and cleaning up the data Cypress tests consume.
- **qa-project-context** — the project context file recording framework choices, CI platform, and team conventions.
