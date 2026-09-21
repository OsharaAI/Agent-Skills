# Factory & Fixture Implementations

Working code for Fishery (TypeScript), FactoryBot (Ruby), Factory Boy (Python), and
Playwright fixtures. Referenced from `SKILL.md` under "Factory Patterns" and "Fixture
Strategies."

A factory is a function that returns test data with sensible defaults built in, so
individual tests only need to override the fields their scenario actually depends on.

## Fishery (TypeScript)

Fishery (2.4.0) is the go-to factory library for TypeScript codebases — it supports type
safety, traits, sequence counters, associations between factories, and transient params.

```bash
npm install --save-dev fishery @faker-js/faker
```

> **Faker v10 (currently v10.4.0) requires a reasonably modern Node.** It ships ESM-only,
> but still loads fine from CommonJS thanks to Node's `require(esm)` support on
> **Node 20.19+ / 22.13+ / 24+**. If you're stuck on an older Node version or a bundler
> without `require(esm)` support, pin `@faker-js/faker@^9` instead. On a supported Node
> version, `require('@faker-js/faker')` just works in v10 — nothing to migrate.

```typescript
// tests/factories/user.factory.ts
import { Factory } from 'fishery';
import { faker } from '@faker-js/faker';

interface User {
  id: string;
  email: string;
  name: string;
  role: 'admin' | 'member' | 'viewer';
  organizationId: string;
  createdAt: Date;
  isActive: boolean;
}

export const userFactory = Factory.define<User>(({ sequence, params }) => ({
  id: `user-${sequence}`,
  email: `user-${sequence}@test.example.com`,
  name: faker.person.fullName(),
  role: params.role ?? 'member',
  organizationId: params.organizationId ?? `org-${sequence}`,
  createdAt: new Date('2025-01-15T10:00:00Z'),
  isActive: true,
}));

// Named variants via params
const adminUser = userFactory.params({ role: 'admin' });
const orgMembers = userFactory.params({ organizationId: 'org-shared' });
```

### Calling it from a test

```typescript
import { userFactory } from '../factories/user.factory';

const user = userFactory.build();                                        // Reasonable defaults, no overrides
const admin = userFactory.build({ role: 'admin' });                      // Override one field
const users = userFactory.buildList(5);                                   // Build several at once
const orgMembers = userFactory.buildList(3, { organizationId: 'org-1' }); // Shared association value
```

### Wiring factories together

```typescript
// tests/factories/order.factory.ts
import { Factory } from 'fishery';
import { userFactory } from './user.factory';

interface Order {
  id: string;
  userId: string;
  items: Array<{ productId: string; quantity: number; unitPrice: number }>;
  totalCents: number;
  status: 'pending' | 'paid' | 'shipped' | 'delivered' | 'cancelled';
}

export const orderFactory = Factory.define<Order>(({ sequence }) => {
  const items = [{ productId: `prod-${sequence}`, quantity: 2, unitPrice: 1999 }];
  return {
    id: `order-${sequence}`,
    userId: userFactory.build().id,
    items,
    totalCents: items.reduce((sum, i) => sum + i.quantity * i.unitPrice, 0),
    status: 'pending',
  };
});
```

### Keeping IDs stable for snapshot assertions

Sequence-based IDs (`user-${sequence}`) are already stable run to run. If a field genuinely
needs to be a UUID and you're asserting against it (say, in a snapshot or golden-file
comparison), seed Faker beforehand so `faker.string.uuid()` produces the same value every
time:

```typescript
import { faker } from '@faker-js/faker';
faker.seed(42); // Locks in the UUID sequence for every run
const stableId = faker.string.uuid(); // Reproducible given the seed above
```

Avoid a raw `crypto.randomUUID()` anywhere a test asserts on the value — it's different on
every run and will break snapshots.

## FactoryBot (Ruby)

FactoryBot (6.6.0, from thoughtbot). The `Product` factory below demonstrates the
`out_of_stock` and `discounted` traits alongside a price field:

```ruby
# spec/factories/products.rb
FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "Product #{n}" }
    price { Faker::Commerce.price(range: 1.0..500.0) }
    category { Faker::Commerce.department }
    stock { 50 }
    trait :out_of_stock do stock { 0 } end
    trait :discounted do price { 9.99 } end
  end
end

# Usage: create(:product), create(:product, :out_of_stock), create(:product, :discounted)
```

A `User` factory that adds `:admin` / `:inactive` traits plus an association:

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user-#{n}@test.example.com" }
    name { Faker::Name.name }
    role { :member }
    organization
    trait :admin do role { :admin } end
    trait :inactive do is_active { false } end
  end
end

# Usage: create(:user), create(:user, :admin), create_list(:user, 3, :inactive)
```

## Factory Boy (Python)

factory-boy (3.3.3). Model variant flags with a `class Params` block plus `factory.Trait`:

```python
# tests/factories.py
import factory
from myapp.models import User

class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = User
    email = factory.Sequence(lambda n: f"user-{n}@test.example.com")
    username = factory.Sequence(lambda n: f"user{n}")
    name = factory.Faker("name")
    role = "member"
    is_active = True
    class Params:
        admin = factory.Trait(role="admin")
        inactive = factory.Trait(is_active=False)

# Usage: UserFactory(), UserFactory(admin=True), UserFactory.create_batch(3, inactive=True)
# Building a mix of active and inactive users:
active_users = UserFactory.create_batch(2)
inactive_users = UserFactory.create_batch(2, inactive=True)
```

## Fixture Strategies

### Static fixtures (JSON/YAML)

The right choice for API response mocks, config-driven test data, and golden-file
comparisons.

```typescript
// Loading a JSON fixture in a Playwright test
import productsResponse from '../fixtures/data/api-responses/products.json';

test('displays products from API', async ({ page }) => {
  await page.route('**/api/products*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(productsResponse) });
  });
  await page.goto('/products');
  await expect(page.getByText('Widget')).toBeVisible();
});
```

### Dynamic fixtures (Playwright)

Provision and tear down data per test using a Playwright fixture:

```typescript
// e2e/fixtures/data.fixture.ts
import { test as base, expect } from '@playwright/test';
import { userFactory } from '../factories/user.factory';

export const test = base.extend<{ testOrder: { id: string; userId: string } }>({
  testOrder: async ({ request }, use) => {
    // userId comes from the factory's sequence counter, not Date.now() (see Guiding Principle 4)
    const response = await request.post('/api/test/orders', {
      data: { userId: userFactory.build().id, items: [{ productId: 'prod-1', quantity: 1 }] },
    });
    expect(response.ok()).toBeTruthy();
    const order = await response.json();
    await use(order);
    await request.delete(`/api/test/orders/${order.id}`);
  },
});
```

### Composing fixtures out of smaller pieces

Combine factory-built payloads with Playwright's fixture mechanism to get setup and
teardown in one place:

```typescript
// e2e/fixtures/composed.fixture.ts
import { test as base } from '@playwright/test';
import { userFactory } from '../factories/user.factory';
import { orderFactory } from '../factories/order.factory';

export const test = base.extend<{ seedData: { user: { id: string }; orders: Array<{ id: string }> } }>({
  seedData: async ({ request }, use) => {
    const resp = await request.post('/api/test/seed', {
      data: { user: userFactory.build(), orders: orderFactory.buildList(3) },
    });
    const seedData = await resp.json();
    await use(seedData);
    await request.post('/api/test/cleanup', { data: { userId: seedData.user.id } });
  },
});
```

### Worker-scoped seeding (Playwright parallel workers)

A worker-scoped fixture seeds shared baseline data once per parallel worker, instead of
once per individual test — a middle ground between speed and isolation. Reach for this on
read-only data every test in a worker can safely share; anything mutable should stay
per-test.

```typescript
// e2e/fixtures/worker-seed.fixture.ts
import { test as base } from '@playwright/test';

export const test = base.extend<{}, { workerSeed: { orgId: string } }>({
  workerSeed: [async ({}, use, workerInfo) => {
    const orgId = `org-w${workerInfo.parallelIndex}`;
    // Baseline rows are scoped to this worker's own org, so workers never step on each other
    await seedOrg(orgId);
    await use({ orgId });
    await cleanupOrg(orgId);
  }, { scope: 'worker' }],
});
```
