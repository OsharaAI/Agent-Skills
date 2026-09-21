# MSW Handlers for Stubbing External Dependencies

The strategy table for what to stub per dependency type, the pointer to contract testing, and
the underlying "stub at the HTTP boundary" principle all live in `SKILL.md`. What follows here
is the actual runnable MSW handler code and the server lifecycle setup. MinIO and its S3 client
configuration are documented separately, in `references/docker-compose.md`.

## Handlers for External APIs

Intercept calls at the HTTP boundary — the actual outbound URLs the system hits — rather than
mocking internal service classes. With MSW 2.x, that means importing `http` and `HttpResponse`
from `msw` and `setupServer` from `msw/node`. Each handler below reads the incoming request so
its response reflects the actual input instead of returning one fixed payload.

```typescript
// test/mocks/handlers.ts
import { http, HttpResponse } from "msw";

export const handlers = [
  // Stripe: create payment intent
  http.post("https://api.stripe.com/v1/payment_intents", async ({ request }) => {
    const body = await request.text();
    const params = new URLSearchParams(body);
    const amount = params.get("amount");

    return HttpResponse.json({
      id: "pi_test_" + Date.now(),
      amount: Number(amount),
      currency: params.get("currency") ?? "usd",
      status: "requires_payment_method",
      client_secret: "pi_test_secret_" + Date.now(),
    });
  }),

  // SendGrid: send email
  http.post("https://api.sendgrid.com/v3/mail/send", () => {
    return HttpResponse.json({ message: "success" }, { status: 202 });
  }),

  // Geocoding API
  http.get("https://maps.googleapis.com/maps/api/geocode/json", ({ request }) => {
    const url = new URL(request.url);
    const address = url.searchParams.get("address");

    return HttpResponse.json({
      results: [{
        formatted_address: address,
        geometry: { location: { lat: 40.7128, lng: -74.006 } },
      }],
      status: "OK",
    });
  }),
];
```

## Wiring Up the Server Lifecycle

```typescript
// test/mocks/setup.ts
import { setupServer } from "msw/node";
import { handlers } from "./handlers";

export const server = setupServer(...handlers);

// In vitest.setup.ts or jest.setup.ts:
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

With `onUnhandledRequest: "error"` set, any test that hits an API without a matching handler
fails immediately and visibly — nothing slips through as a silent real network call. Skip this
setting, and a missing stub quietly becomes a live outbound request, one that might pass today
in CI and flake without warning tomorrow.
