# Reusable Multi-Pixel Capture Fixture

A single `test.extend` fixture captures every analytics and pixel beacon during a test run, letting individual tests assert against a shared `collected` list instead of each one reimplementing capture logic. It listens through `page.on('request')` and parses each request's `searchParams` and `postData()`.

Important: a capture helper must **observe** traffic, never block it. Use `page.on('request')` (or `page.route` combined with `route.continue()`). **Never** `page.route(...).abort()` — that blocks the very beacons you're trying to see. And make sure it captures pixels too, not just GA4.

## The fixture

```ts
// fixtures/analytics.ts
import { test as base, expect } from '@playwright/test';

export type Beacon = { destination: string; eventName: string; params: Record<string, string> };

const ENDPOINTS = [
  { match: '/g/collect',           destination: 'ga4',      event: (sp: URLSearchParams) => sp.get('en') },
  { match: 'facebook.com/tr',      destination: 'meta',     event: (sp: URLSearchParams) => sp.get('ev') },
  { match: 'analytics.tiktok.com', destination: 'tiktok',   event: (sp: URLSearchParams) => sp.get('event') },
  { match: 'px.ads.linkedin.com',  destination: 'linkedin', event: (sp: URLSearchParams) => sp.get('conversionId') },
];

export const test = base.extend<{ beacons: Beacon[] }>({
  beacons: async ({ page }, use) => {
    const collected: Beacon[] = [];

    page.on('request', request => {
      const url = request.url();
      const ep = ENDPOINTS.find(e => url.includes(e.match));
      if (!ep) return;

      const sp = new URL(url).searchParams;
      const params: Record<string, string> = {};
      for (const [k, v] of sp.entries()) params[k] = v;

      // Some pixels carry the payload in the POST body.
      const body = request.postData();
      if (body) {
        try { Object.assign(params, JSON.parse(body)); }
        catch { for (const [k, v] of new URLSearchParams(body)) params[k] = v; }
      }

      collected.push({ destination: ep.destination, eventName: ep.event(sp) ?? '', params });
    });

    await use(collected); // tests read this list after their actions
  },
});

export { expect };
```

## Using it in a test

```ts
import { test, expect } from '../fixtures/analytics';

test('add_to_cart hits GA4 and Meta', async ({ page, beacons }) => {
  await page.goto('/product/42');
  await page.getByRole('button', { name: 'Add to cart' }).click();
  await page.waitForLoadState('networkidle');

  const ga4 = beacons.find(b => b.destination === 'ga4' && b.eventName === 'add_to_cart');
  expect(ga4?.params['ep.currency']).toBe('USD');

  const meta = beacons.find(b => b.destination === 'meta' && b.eventName === 'AddToCart');
  expect(meta).toBeTruthy();
});
```

## Why a fixture instead of per-test capture

- Individual tests stay focused on assertions rather than plumbing.
- There's one place to update when marketing adds a new destination endpoint.
- The same `collected` list also feeds the CI regression gate (`ci-gating.md`): run the journeys, dump `beacons`, and diff against the tracking-plan baseline.
