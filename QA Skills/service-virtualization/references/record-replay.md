# Record-replay — capture real traffic once, replay it deterministically

Record-replay works by capturing genuine API responses a single time and replaying them for every
subsequent test run. It's particularly useful when you're bootstrapping stubs for a newly
integrated third-party API, or when you want a fixed regression baseline for a multi-step
interaction.

**Which tool to use.** Reach for an established record-replay library instead of building your own
recorder: **Hoverfly** (capture → simulate → modify → synthesize modes; works as a language-agnostic
proxy), **Polly.JS** (browser and Node), or **VCR**-style cassettes (`vcrpy` in Python, `php-vcr`,
and similar in other ecosystems). MSW itself has no recording capability — pair it with Hoverfly's
capture mode, or produce the cassette format shown below by hand.

**Where it earns its keep:** bootstrapping a first set of stubs, and regression baselines for
response shapes that don't change often.

**Where it falls apart:** any API returning dynamic values (timestamps, UUIDs), stateful sequences
that depend on the outcome of earlier writes, and simply the passage of time — recordings go stale
within weeks. Always stamp a `recordedAt` field and fail the test once a recording is older than 30
days, forcing a fresh capture.

## A cassette format with a built-in expiry check

```typescript
// test/cassettes/checkout-flow.json shape
// { "recordedAt": "2026-05-20T10:00:00Z", "steps": [ {request, response}, ... ] }

import cassette from "./cassettes/checkout-flow.json";

const MAX_AGE_DAYS = 30;

export function assertFresh(recordedAt: string) {
  const ageDays = (Date.now() - new Date(recordedAt).getTime()) / 86_400_000;
  if (ageDays > MAX_AGE_DAYS) {
    throw new Error(
      `Cassette is ${Math.floor(ageDays)} days old (>${MAX_AGE_DAYS}). Re-record it.`
    );
  }
}
```

## Replaying a multi-step interaction

Feed the recorded steps back through MSW, in order, so the test drives the real client code through
the whole sequence (create order → add items → apply coupon → checkout). Running the freshness
check first means a stale cassette fails the test outright instead of quietly validating against an
API shape that no longer exists.

```typescript
import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import cassette from "./cassettes/checkout-flow.json";
import { assertFresh } from "./cassette-utils";

assertFresh(cassette.recordedAt); // fails the test if the recording is stale

let step = 0;
const server = setupServer(
  http.all("https://api.shop.example.com/*", () => {
    const recorded = cassette.steps[step++];
    return HttpResponse.json(recorded.response.body, { status: recorded.response.status });
  })
);

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterAll(() => server.close());

it("replays the recorded checkout flow", async () => {
  const order = await api.createOrder();          // step 0
  await api.addItem(order.id, "sku-1");           // step 1
  await api.applyCoupon(order.id, "SAVE10");      // step 2
  const receipt = await api.checkout(order.id);   // step 3
  expect(receipt.status).toBe("paid");
  expect(step).toBe(cassette.steps.length);       // every recorded step was consumed
});
```
</content>
