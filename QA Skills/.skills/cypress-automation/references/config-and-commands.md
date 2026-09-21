# Config, Project Layout, and Custom Commands

The concrete scaffolding for a Cypress + TypeScript project. Concepts, principles, and the reasoning behind these choices live in `SKILL.md`; this file is the implementation reference.

## Project Layout

```
project-root/
├── cypress.config.ts
├── cypress/
│   ├── e2e/                    # E2E specs, grouped by feature
│   ├── component/              # Component specs (*.cy.tsx)
│   ├── fixtures/                # Static JSON test data, including api-responses/
│   ├── support/
│   │   ├── commands.ts         # Custom commands
│   │   ├── e2e.ts              # E2E support file
│   │   ├── component.ts        # Component support file
│   │   └── index.d.ts          # TypeScript declarations for custom commands
│   └── downloads/               # Git-ignored
├── cypress.env.json             # Git-ignored, per-environment variables
└── tsconfig.json
```

## cypress.config.ts

```typescript
import { defineConfig } from 'cypress';

export default defineConfig({
  projectId: process.env.CYPRESS_PROJECT_ID, // Needed for Cypress Cloud

  e2e: {
    baseUrl: process.env.CYPRESS_BASE_URL ?? 'http://localhost:3000',
    specPattern: 'cypress/e2e/**/*.cy.ts',
    supportFile: 'cypress/support/e2e.ts',
    viewportWidth: 1280,
    viewportHeight: 720,
    defaultCommandTimeout: 10000,
    requestTimeout: 15000,
    responseTimeout: 30000,
    video: false,                    // Turn on for CI if you want recordings
    screenshotOnRunFailure: true,
    retries: {
      runMode: 2,                    // Retries when run via `cypress run` (CI)
      openMode: 0,                   // No retries in the interactive runner
    },
    // experimentalRunAllSpecs is unnecessary now -- it stabilized in Cypress 14,
    // and "Run all specs" is simply the default behavior in 15.x.
    setupNodeEvents(on, config) {
      // Register task plugins, code coverage hooks, etc. here
      return config;
    },
  },

  component: {
    devServer: {
      framework: 'react',           // 'react' | 'vue' | 'angular' | 'svelte'
      bundler: 'vite',              // 'vite' | 'webpack'
    },
    specPattern: 'cypress/component/**/*.cy.tsx',
    supportFile: 'cypress/support/component.ts',
  },
});
```

Add `"types": ["cypress"]` under `compilerOptions` in `tsconfig.json`, and make sure `"cypress/**/*.ts"` is listed in `include`.

## Custom Commands

A custom command hides a repeated interaction behind a small, typed API. Always type them so callers get autocomplete and a compile error if they misuse them.

### Defining Commands

```typescript
// cypress/support/commands.ts

// Login -- authenticate via API rather than driving the login UI on every test
Cypress.Commands.add('login', (email: string, password: string) => {
  cy.session(
    [email, password],
    () => {
      cy.request({
        method: 'POST',
        url: '/api/auth/login',
        body: { email, password },
      }).then((response) => {
        expect(response.status).to.eq(200);
        window.localStorage.setItem('auth_token', response.body.token);
      });
    },
    {
      // Re-checks the cached session before Cypress reuses it. Skip validate()
      // and a stale/expired token gets silently reused as though it still worked.
      validate() {
        cy.request('/api/me').its('status').should('eq', 200);
      },
    },
  );
});

// A shorthand selector by data attribute
Cypress.Commands.add('getByTestId', (testId: string) => {
  return cy.get(`[data-testid="${testId}"]`);
});

// Asserts a toast notification shows and then clears
Cypress.Commands.add('shouldShowToast', (message: string) => {
  cy.get('[role="alert"]')
    .should('be.visible')
    .and('contain.text', message);
  cy.get('[role="alert"]').should('not.exist');
});
```

### TypeScript Declarations

```typescript
// cypress/support/index.d.ts

declare namespace Cypress {
  interface Chainable {
    /**
     * Authenticate via the API and cache the resulting session.
     * @example cy.login('person@example.com', 'hunter2-placeholder')
     */
    login(email: string, password: string): Chainable<void>;

    /**
     * Select an element by its data-testid attribute.
     * @example cy.getByTestId('submit-button').click()
     */
    getByTestId(testId: string): Chainable<JQuery<HTMLElement>>;

    /**
     * Assert that a toast notification appears with the given message.
     * @example cy.shouldShowToast('Profile updated')
     */
    shouldShowToast(message: string): Chainable<void>;
  }
}
```

### Retryable Custom Queries

For element lookups that should retry the way built-in queries do, use `Cypress.Commands.addQuery()` instead of `Cypress.Commands.add()`. The callback passed to `addQuery` **must** be written as a non-arrow `function () {}` — Cypress relies on binding `this` inside it to apply the command timeout, and an arrow function has no `this` of its own, which silently kills retry-ability.

```typescript
// cypress/support/commands.ts
Cypress.Commands.addQuery('getByTestId', function (testId: string) {
  const getFn = cy.now('get', `[data-testid="${testId}"]`);
  return (subject) => getFn(subject);
});
```

This is the reverse of the rule for `cy.intercept` handlers, where an arrow function `(req) => { ... }` is perfectly fine — intercept handlers never depend on `this`.
