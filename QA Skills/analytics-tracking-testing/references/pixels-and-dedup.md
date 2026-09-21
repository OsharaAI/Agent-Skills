# Pixels and Client-vs-Server Deduplication

Marketing pixels each send beacons to their own endpoints. Match on host/path and read the event out of `searchParams` or `postData()`.

| Destination | Endpoint | Event field | Dedup key |
|-------------|----------|-------------|-----------|
| Meta Pixel | `facebook.com/tr` (also `/tr?`) | `ev=PageView`, `ev=Purchase` | `eid` (carries `event_id`) |
| TikTok | `analytics.tiktok.com` | event in params or POST body | `event_id` |
| LinkedIn | `px.ads.linkedin.com` | conversion id in path/params | — |

## Why load/count checks aren't enough

Confirming `connect.facebook.net/en_US/fbevents.js` loaded only proves the library was present. Confirming `fbq('track','Purchase')` ran only proves the call happened. Neither tells you the data is correct, and neither one catches the real risk for a dual-fired Purchase event: **double-counting**. The Pixel fires on the client, and the server fires its own Conversions API (CAPI) call. Unless both share an `event_id`, Meta records two separate conversions.

## Meta PageView + Purchase, with a dedup check

```ts
import { test, expect } from '@playwright/test';

test('Purchase pixel de-duplicates against server CAPI', async ({ page }) => {
  // PageView on load
  const [pageView] = await Promise.all([
    page.waitForRequest(r => r.url().includes('facebook.com/tr') && r.url().includes('ev=PageView')),
    page.goto('/'),
  ]);
  expect(new URL(pageView.url()).searchParams.get('ev')).toBe('PageView');

  // Purchase on checkout completion
  const [pixel] = await Promise.all([
    page.waitForRequest(r => r.url().includes('facebook.com/tr') && r.url().includes('ev=Purchase')),
    completeCheckout(page),
  ]);
  const clientEventId = new URL(pixel.url()).searchParams.get('eid'); // event_id on the wire

  // serverCapiEventId: captured from the mocked server CAPI call, or a known fixture value
  expect(clientEventId, 'client and server event_id must match to deduplicate').toBe(serverCapiEventId);
});
```

`fbq('track', 'Purchase', {...}, { eventID })` places the dedup key onto the beacon as `eid`. Your server's CAPI payload has to send that same value back in its `event_id` field.

## Capturing the server-side CAPI event_id

If the server's CAPI call is reachable from the test environment, intercept it directly (it hits `graph.facebook.com/.../events`), or read back the `event_id` your checkout backend logged for that order. In an isolated test, you can generate the `event_id` inside a fixture and confirm both sides consume the same value.

## TikTok / LinkedIn parsing

```ts
function parseTikTok(request) {
  const url = new URL(request.url());           // analytics.tiktok.com
  const body = request.postData();
  return { params: url.searchParams, body: body ? JSON.parse(body) : null };
}
// LinkedIn: px.ads.linkedin.com/collect — conversion id in the query string.
```
