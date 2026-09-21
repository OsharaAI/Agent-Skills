# Component Mounts and Data-Driven Fixtures

Runnable code for mounting a component in isolation and for the three tiers of data-driven testing (static fixtures, `cy.task` seeding, per-environment config). Discussion of when component tests are the right tool lives in `SKILL.md`.

## Component Testing

Mounting a component directly, rather than through the full app, gives you a faster feedback loop than E2E and more real-browser fidelity than a plain unit test.

### React Component Test

```tsx
// cypress/component/ProductCard.cy.tsx
import { ProductCard } from '../../src/components/ProductCard';

describe('ProductCard', () => {
  const product = { id: '42', name: 'Desk Lamp', price: 34.5, image: '/desk-lamp.png' };

  it('renders product information', () => {
    cy.mount(<ProductCard product={product} onAddToCart={cy.stub()} />);

    cy.contains('Desk Lamp').should('be.visible');
    cy.contains('$34.50').should('be.visible');
    cy.get('img').should('have.attr', 'src', '/desk-lamp.png');
  });

  it('calls onAddToCart with the product id on click', () => {
    const onAddToCart = cy.stub().as('addToCart');
    cy.mount(<ProductCard product={product} onAddToCart={onAddToCart} />);

    cy.contains('button', 'Add to Cart').click();
    cy.get('@addToCart').should('have.been.calledOnceWith', '42');
  });

  it('renders the out-of-stock state', () => {
    cy.mount(<ProductCard product={{ ...product, inStock: false }} onAddToCart={cy.stub()} />);

    cy.contains('button', 'Add to Cart').should('be.disabled');
    cy.contains('Out of Stock').should('be.visible');
  });
});
```

Vue components follow the same shape but mount via `cy.mount(Component, { props: { ... } })`, and use `cy.spy()` where you'd assert on an emitted event.

## Data-Driven Testing with Fixtures

### Static Fixture Data

```typescript
// Reads cypress/fixtures/users.json
describe('Role-based access', () => {
  beforeEach(function () {
    cy.fixture('users').as('users');
  });

  it('shows the admin panel to an admin user', function () {
    const admin = this.users.find((u: { role: string }) => u.role === 'admin');
    cy.login(admin.email, admin.password);
    cy.visit('/admin');
    cy.getByTestId('admin-panel').should('be.visible');
  });
});
```

### Dynamic Test Data via cy.task

Reach for `cy.task` whenever setup needs to happen in Node rather than the browser — hitting an internal API, seeding a database, and so on. The task body executes in the Node process, so the `fetch` call below is Node's built-in global `fetch` (present from Node 18 onward, well within Cypress 15's Node 20+ floor) — it is not a Cypress command:

```typescript
// cypress.config.ts -- register the task inside setupNodeEvents
on('task', {
  async seedTestUser(role: string) {
    const response = await fetch(`${config.env.API_URL}/test/seed-user`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ role }),
    });
    return response.json();
  },
});

// In the spec:
beforeEach(() => {
  cy.task('seedTestUser', 'editor').then((user) => {
    cy.login(user.email, user.password);
  });
});
```

### Environment-Specific Configuration

```typescript
// Invoke with: npx cypress run --env ENVIRONMENT=staging
setupNodeEvents(on, config) {
  const envConfig = { local: { baseUrl: 'http://localhost:3000' }, staging: { baseUrl: 'https://staging.example.com' } };
  return { ...config, ...envConfig[config.env.ENVIRONMENT || 'local'] };
}
```
