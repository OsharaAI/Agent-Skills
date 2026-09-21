# Capturing `dataLayer.push`

When what's really under test is the GTM **input** — "what object gets pushed to `window.dataLayer`?" — assert the push itself rather than the resulting GA4 beacon. Wrap `dataLayer.push` using `addInitScript` *before navigation* so pushes that happen during page load get recorded too.

Avoid:
- Using `page.route` to mock the dataLayer — that would replace the thing you're supposed to be testing.
- Reading the GA4 `/g/collect` beacon instead — that's the output side, a different contract entirely.

## Wrapping push before navigation

```ts
import { test, expect } from '@playwright/test';

test('view_item pushes the ecommerce shape', async ({ page }) => {
  await page.addInitScript(() => {
    window.dataLayer = window.dataLayer || [];
    const orig = window.dataLayer.push.bind(window.dataLayer);
    (window as any).__pushes = [];
    window.dataLayer.push = (...args: any[]) => {
      (window as any).__pushes.push(...args);
      return orig(...args);
    };
  });

  await page.goto('/product/42'); // page-load pushes are now captured

  const pushes = await page.evaluate(() => (window as any).__pushes);
  const viewItem = pushes.find((p: any) => p.event === 'view_item');
  expect(viewItem, 'view_item was never pushed').toBeTruthy();
  expect(viewItem.ecommerce.items[0]).toMatchObject({
    item_id: 'SKU-42',
    price: 49.99,
    currency: 'USD',
  });
});
```

## Checking the nested ecommerce shape

GA4 ecommerce pushes nest products under `ecommerce.items` (an array). Check the array's shape rather than stopping at the event name:

```ts
const items = viewItem.ecommerce.items;
expect(items).toHaveLength(1);
expect(items.every((i: any) => typeof i.item_id === 'string')).toBe(true);
expect(items.every((i: any) => typeof i.price === 'number')).toBe(true);
expect(items[0].currency).toBe('USD');
```

`find` / `filter` / `some` over the recorded `__pushes` array will locate or count whichever event you care about — `find` when you expect a single push, `filter(...).length` to confirm a push happened exactly once and wasn't duplicated.

## Checking both layers together

For a complete input-to-output check, capture the dataLayer push (as above) alongside the resulting GA4 beacon (`ga4-interception.md`) in the same test, then confirm the beacon's `ep.`/`epn.` params match what was pushed. This catches GTM tag misconfigurations that quietly drop or rename a param somewhere between the push and the beacon.
