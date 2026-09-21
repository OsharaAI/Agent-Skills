# GA4 `/g/collect` Beacon Interception

GA4 (via gtag.js or GTM) sends each event as a request to `https://www.google-analytics.com/g/collect`. Region variants exist too (`region1.google-analytics.com/g/collect`, `analytics.google.com/g/collect`), so match on the `/g/collect` path rather than the full hostname. Everything about the event's identity lives in the URL query string.

## URL grammar

| Param | Meaning |
|-------|---------|
| `v=2` | Measurement Protocol version (always 2 for GA4 web) |
| `tid=G-XXXXXXX` | Measurement ID |
| `en=` | Event name (`en=add_to_cart`) |
| `ep.<name>=` | Event parameter, string type (`ep.currency=USD`) |
| `epn.<name>=` | Event parameter, number type (`epn.value=49.99`) |
| `gcs=` / `gcd=` | Consent state |
| `dl=` / `dt=` | Document location / title |

## Single-event interception

```ts
import { test, expect } from '@playwright/test';

test('add_to_cart fires with correct params', async ({ page }) => {
  await page.goto('/product/42');

  const [request] = await Promise.all([
    page.waitForRequest(r =>
      r.url().includes('/g/collect') && r.url().includes('en=add_to_cart')),
    page.getByRole('button', { name: 'Add to cart' }).click(),
  ]);

  const params = new URL(request.url()).searchParams;
  expect(params.get('v')).toBe('2');
  expect(params.get('tid')).toContain('G-');
  expect(params.get('en')).toBe('add_to_cart');
  expect(params.get('ep.currency')).toBe('USD');     // string param
  expect(Number(params.get('epn.value'))).toBe(49.99); // number param
  expect(params.get('ep.item_id')).toBe('SKU-42');
});
```

## Collecting many events on a page

Listen with `page.on('request')` and push each parsed event onto an array. Keep in mind GA4 can bundle multiple events into a single POST: additional events show up in the request's `postData()` as newline-separated, `&`-joined param strings, each carrying its own `en=`.

```ts
type GA4Event = { name: string; params: Record<string, string> };

function parseGA4(request): GA4Event[] {
  const events: GA4Event[] = [];
  const base = new URL(request.url()).searchParams;

  const collect = (sp: URLSearchParams) => {
    const name = sp.get('en');
    if (!name) return;
    const params: Record<string, string> = {};
    for (const [k, v] of sp.entries()) if (k.startsWith('ep.') || k.startsWith('epn.')) params[k] = v;
    events.push({ name, params });
  };

  collect(base);
  // Batched events live in the POST body, one event per line.
  const body = request.postData();
  if (body) for (const line of body.split('\n')) {
    if (line.trim()) collect(new URLSearchParams(line));
  }
  return events;
}

function attachGA4Collector(page) {
  const collected: GA4Event[] = [];
  page.on('request', r => { if (r.url().includes('/g/collect')) collected.push(...parseGA4(r)); });
  return collected;
}
```

## Why the alternatives fall short

- `page.evaluate(() => window.dataLayer)` — shows that a push happened, not that GA4 actually emitted a hit; GTM might still drop or transform it.
- `toBeVisible()` on the clicked element — has nothing to do with whether a beacon actually left the browser.
- `waitForTimeout(2000)` — flaky; use `waitForRequest` on `/g/collect` instead.

## `page.route` when you need to inspect AND let it through

```ts
await page.route('**/g/collect*', async route => {
  const params = new URL(route.request().url()).searchParams;
  // record params here…
  await route.continue(); // never route.abort() — that kills the beacon
});
```
