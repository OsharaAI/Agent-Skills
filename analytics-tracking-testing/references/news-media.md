# News-Media Events

Publisher pages have a tracking surface that generic e-commerce plans don't account for: article view, scroll depth, and the paywall meter. Every interaction should be driven by real actions with the beacon awaited directly — never `waitForTimeout`.

## article_view on load

```ts
import { test, expect } from '@playwright/test';

test('article_view fires once with metadata', async ({ page }) => {
  const [request] = await Promise.all([
    page.waitForRequest(r => r.url().includes('/g/collect') && r.url().includes('en=article_view')),
    page.goto('/news/2026/election-results'),
  ]);
  const params = new URL(request.url()).searchParams;
  expect(params.get('en')).toBe('article_view');
  expect(params.get('ep.article_id')).toBeTruthy();
  expect(params.get('ep.section')).toBe('politics');
  expect(params.get('ep.author')).toBeTruthy();
});
```

## Scroll depth at 25 / 50 / 75 / 100

Trigger real scrolling (`page.evaluate(scrollTo)`, `mouse.wheel`, or `scrollIntoView`) and wait for each bucket's beacon. Confirm each threshold fires exactly once — firing the same threshold twice is a common bug here.

```ts
test('scroll_depth fires once per threshold', async ({ page }) => {
  await page.goto('/news/2026/election-results');

  const fired: string[] = [];
  page.on('request', r => {
    if (r.url().includes('/g/collect') && r.url().includes('en=scroll')) {
      fired.push(new URL(r.url()).searchParams.get('epn.percent_scrolled') ?? '');
    }
  });

  for (const pct of [25, 50, 75, 100]) {
    await Promise.all([
      page.waitForRequest(r => r.url().includes('en=scroll') && r.url().includes(`percent_scrolled=${pct}`)),
      page.evaluate(p => window.scrollTo(0, document.body.scrollHeight * (p / 100)), pct),
    ]);
  }

  expect(fired.sort()).toEqual(['100', '25', '50', '75']); // each exactly once, no dupes
});
```

Other scroll drivers, useful if `scrollTo` doesn't trip the listener:

```ts
await page.mouse.wheel(0, 2000);                              // wheel events
await page.locator('#article-footer').scrollIntoViewIfNeeded(); // scroll an element into view
await page.evaluate(() => window.scrollBy(0, 1000));          // incremental
```

## Paywall / meter event

Once the free-article meter runs out, a `paywall_hit` (or `meter`) event should fire. Seed the meter's count past its limit (via cookie or localStorage) so the next article trips the wall, then check for the event.

```ts
test('paywall_hit fires when the meter is exhausted', async ({ page, context }) => {
  await context.addCookies([{ name: 'meter_count', value: '5', domain: 'localhost', path: '/' }]); // limit is 5

  const [request] = await Promise.all([
    page.waitForRequest(r => r.url().includes('/g/collect') && r.url().includes('en=paywall_hit')),
    page.goto('/news/2026/premium-analysis'),
  ]);
  const params = new URL(request.url()).searchParams;
  expect(params.get('en')).toBe('paywall_hit');
  expect(params.get('ep.wall_type')).toBe('metered');
  await expect(page.getByTestId('paywall-overlay')).toBeVisible();
});
```

Cover all three surfaces (article_view, the four scroll buckets, and the paywall) — checking only `article_view` while skipping scroll depth and the paywall is the most common gap this tracking surface ships with.
