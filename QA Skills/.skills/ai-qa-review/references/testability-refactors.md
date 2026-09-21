# Testability Refactors

Concrete before/after code for the testability issues raised under "Testability Analysis" in `SKILL.md`. The what-to-flag guidance lives in the SKILL; the actual refactor code lives here.

## Dependency Injection

Flag classes that construct their own dependencies directly (`new PostgresDatabase()`, `new StripeClient()` inside a method). Push for constructor injection so tests can drop in mocks or fakes instead.

```typescript
// HARD TO TEST                          // TESTABLE
class OrderService {                     class OrderService {
  async create(data: OrderInput) {         constructor(
    const db = new PostgresDB();             private readonly db: Database,
    const email = new SendGrid();            private readonly email: EmailClient,
  }                                        ) {}
}                                        }
```

## Side Effect Isolation

Flag functions that blend pure calculation with I/O (email, logging, analytics). Pull the calculation out as a pure function, then have the side-effectful orchestrator call it. The pure half becomes trivial to unit test.

```typescript
// HARD TO TEST: calculation and side effects fused
async function checkout(cart: Cart, userId: string) {
  let total = 0;
  for (const item of cart.items) total += item.price * item.qty;
  if (cart.coupon) total *= 1 - cart.coupon.rate;
  await db.orders.insert({ userId, total });        // I/O
  await email.send(userId, `You paid ${total}`);    // I/O
  return total;
}

// TESTABLE: pure calculation extracted
function calcTotal(cart: Cart): number {
  const subtotal = cart.items.reduce((s, i) => s + i.price * i.qty, 0);
  return cart.coupon ? subtotal * (1 - cart.coupon.rate) : subtotal;
}

async function checkout(cart: Cart, userId: string) {
  const total = calcTotal(cart);                    // unit-test this directly
  await db.orders.insert({ userId, total });
  await email.send(userId, `You paid ${total}`);
  return total;
}
```

`calcTotal` now tests with plain inputs and outputs — no DB, no email, no boundary values buried behind I/O.

## Pure Function Extraction

Watch for validation, transformation, and business rules hiding inside request handlers. Logic inline in `app.post('/api/orders', ...)` can't be unit-tested without spinning up an HTTP server. Pull it out as a standalone function instead.

```typescript
// HARD TO TEST: rule logic trapped inside the route handler
app.post('/api/orders', async (req, res) => {
  if (!req.body.items?.length) return res.status(400).json({ error: 'empty' });
  const weight = req.body.items.reduce((w, i) => w + i.weight * i.qty, 0);
  const shipping = weight > 20 ? 15 : weight > 5 ? 8 : 4;   // business rule
  res.json({ shipping });
});

// TESTABLE: rule is a pure function, handler is a thin adapter
export function shippingFor(items: Item[]): number {
  const weight = items.reduce((w, i) => w + i.weight * i.qty, 0);
  return weight > 20 ? 15 : weight > 5 ? 8 : 4;
}

app.post('/api/orders', async (req, res) => {
  if (!req.body.items?.length) return res.status(400).json({ error: 'empty' });
  res.json({ shipping: shippingFor(req.body.items) });
});
```

`shippingFor` can now be driven with `it.each` across the 5/20 boundaries directly — no Express, no supertest needed.

## Interface Segregation

Flag classes depending on sweeping interfaces (all of `PrismaClient`) when only 2-3 methods actually get used. Define a narrow interface exposing only what's needed, so test doubles become easy to write.

```typescript
// HARD TO TEST: must mock all of PrismaClient to fake one query
class UserLookup {
  constructor(private prisma: PrismaClient) {}
  byEmail(email: string) { return this.prisma.user.findUnique({ where: { email } }); }
}

// TESTABLE: narrow port, one-line fake
interface UserReader {
  findUnique(args: { where: { email: string } }): Promise<User | null>;
}
class UserLookup {
  constructor(private users: UserReader) {}
  byEmail(email: string) { return this.users.findUnique({ where: { email } }); }
}
// test: new UserLookup({ findUnique: async () => ({ id: '1', email }) })
```
</content>
