# cy.intercept Recipes

Runnable patterns for controlling the network layer with `cy.intercept`: stubbing, spying, conditional/polling responses, simulated failures, rewriting live responses, and fixture-backed stubs. The reasoning for choosing stub vs. spy lives in `SKILL.md`.

## Stubbing a Response

```typescript
cy.intercept('GET', '/api/products', {
  statusCode: 200,
  body: { products: [{ id: '7', name: 'Desk Lamp', price: 34.5 }] },
}).as('getProducts');

cy.visit('/products');
cy.wait('@getProducts');
cy.getByTestId('product-card').should('have.length', 1);
```

## Spying Without Stubbing

```typescript
cy.intercept('POST', '/api/orders').as('createOrder');

cy.getByTestId('place-order').click();
cy.wait('@createOrder').then((interception) => {
  expect(interception.request.body).to.have.property('items');
  expect(interception.request.body.items).to.have.length(3);
  expect(interception.response?.statusCode).to.eq(201);
});
```

## Conditional / Polling Responses

```typescript
let callCount = 0;
cy.intercept('GET', '/api/status', (req) => {
  callCount += 1;
  if (callCount <= 2) {
    req.reply({ statusCode: 202, body: { status: 'processing' } });
  } else {
    req.reply({ statusCode: 200, body: { status: 'complete', url: '/download/report.pdf' } });
  }
}).as('pollStatus');

cy.visit('/jobs/456');
// The app keeps polling until the status flips; wait on the alias once per poll,
// then assert the UI has caught up.
cy.wait('@pollStatus');
cy.wait('@pollStatus');
cy.wait('@pollStatus');
cy.contains('Report ready').should('be.visible');
```

## Simulating Network Failures

```typescript
// A server-side failure
cy.intercept('POST', '/api/checkout', { statusCode: 500, body: { error: 'Internal Server Error' } }).as('checkoutFail');

// A dropped connection, then verify the app's error state
cy.intercept('POST', '/api/checkout', { forceNetworkError: true }).as('networkError');

cy.getByTestId('place-order').click();
cy.wait('@networkError');
cy.contains('Something went wrong. Please try again.').should('be.visible');

// An artificially slow response
cy.intercept('GET', '/api/dashboard', (req) => {
  req.reply({
    delay: 5000,
    statusCode: 200,
    body: { widgets: [] },
  });
}).as('slowDashboard');
```

## Rewriting a Live Response

```typescript
cy.intercept('GET', '/api/feature-flags', (req) => {
  req.continue((res) => {
    res.body.flags['new-checkout'] = true;
    res.send();
  });
}).as('featureFlags');
```

## Fixture-Backed Responses

```typescript
// Serves cypress/fixtures/api-responses/checkout-success.json
cy.intercept('POST', '/api/checkout', { fixture: 'api-responses/checkout-success.json' }).as('checkout');
```

## Cross-Origin Flows via cy.origin

When a flow legitimately hands off to a different domain (SSO, an OAuth provider, an auth host separate from the main app), wrap the steps that run there in `cy.origin`. This is the replacement for the older `chromeWebSecurity: false` / `experimentalSessionAndOrigin` escape hatches — don't disable web security just to push through a redirect.

```typescript
cy.visit('/login');
cy.contains('button', 'Sign in with SSO').click();

cy.origin('https://auth.example.com', () => {
  cy.get('#username').type('person@example.com');
  cy.get('#password').type('hunter2-placeholder', { log: false });
  cy.contains('button', 'Continue').click();
});

// back on the app's own origin
cy.url().should('include', '/dashboard');
```

Keep this distinct from third-party payment iframes (Stripe, PayPal, and similar): those are stubbed from the outside with `cy.intercept` and never entered directly. `cy.origin` is for redirects to domains your flow legitimately controls or trusts, not for embedded third-party iframes.
