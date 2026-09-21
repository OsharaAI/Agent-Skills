# Handling the 3DS / SCA challenge in Playwright (nested iframes)

This is the single trickiest part of payment E2E testing. Stripe's 3DS challenge lives
in **a frame nested inside the Stripe modal frame** — a single `frameLocator` cannot
reach it. You need to chain nested `frameLocator` calls and click the "Complete
authentication" button inside the innermost one.

## Why the obvious approaches don't work

- `page.locator('#card')` — the card input sits in a **cross-origin iframe**. The
  locator quietly matches nothing, and the test either hangs or times out with a
  confusing error.
- `page.frames()[1]` — fragile by nature. The frame's position shifts the instant
  Stripe adds, removes, or reorders frames (loading spinners, hCaptcha, analytics
  frames, etc.). Never select a frame by its numeric index.
- `await page.waitForTimeout(5000)` — a guess at how long the challenge will take.
  Flaky when CI is under load, wasted time when it isn't. Wait on the actual element.
- Selenium-style `switch_to.frame` — wrong toolkit entirely; this is Playwright.

## The pattern that actually works

Use a card that always requires 3DS (`4000000000003220`) so the challenge is
guaranteed to appear. Chain `frameLocator` calls from the outer modal frame into the
inner challenge frame, then click **Complete authentication**.

```ts
import { test, expect } from '@playwright/test';

test('3DS challenge completes and payment succeeds', async ({ page }) => {
  await page.goto('/checkout');

  // 1. Fill the Payment Element (itself a cross-origin frame).
  const card = page.frameLocator('iframe[name^="__privateStripeFrame"]');
  await card.getByPlaceholder('Card number').fill('4000000000003220');
  await card.getByPlaceholder('MM / YY').fill('12 / 34');
  await card.getByPlaceholder('CVC').fill('123');
  await page.getByRole('button', { name: /pay/i }).click();

  // 2. The challenge is NESTED: outer Stripe challenge frame → inner ACS frame.
  //    A single frameLocator is insufficient — chain two.
  const challengeOuter = page.frameLocator('iframe[name^="__privateStripeFrame"]');
  const challengeInner = challengeOuter.frameLocator('iframe#challengeFrame, iframe[name="acsFrame"]');

  // 3. Click "Complete authentication" inside the nested challenge frame.
  await challengeInner
    .getByRole('button', { name: /complete authentication|complete|authorize/i })
    .click();

  // 4. Assert success — never trust a redirect alone; assert the success state.
  await expect(page).toHaveURL(/\/success/);
  await expect(page.getByText(/payment succeeded/i)).toBeVisible();
});

test('3DS challenge can be failed', async ({ page }) => {
  await page.goto('/checkout');
  const card = page.frameLocator('iframe[name^="__privateStripeFrame"]');
  await card.getByPlaceholder('Card number').fill('4000000000003220');
  await card.getByPlaceholder('MM / YY').fill('12 / 34');
  await card.getByPlaceholder('CVC').fill('123');
  await page.getByRole('button', { name: /pay/i }).click();

  const inner = page
    .frameLocator('iframe[name^="__privateStripeFrame"]')
    .frameLocator('iframe#challengeFrame, iframe[name="acsFrame"]');
  await inner.getByRole('button', { name: /fail authentication/i }).click();
  await expect(page.getByText(/authentication failed|could not be authenticated/i)).toBeVisible();
});
```

## Notes on selectors

- Stripe's frame names carry the prefix `__privateStripeFrame…` followed by a numeric
  suffix that changes on every render — match on the **prefix** with `[name^="…"]`
  rather than the full name.
- The inner challenge frame's id or name varies between Stripe versions
  (`challengeFrame`, `acsFrame`). Match both with a comma-separated selector and use a
  button-name regex, so a version bump doesn't silently break the test.
- Playwright already auto-waits on `frameLocator` actions, so `waitForTimeout` is
  unnecessary. If you need to explicitly wait for the modal, use
  `await expect(challengeInner.getByRole('button', { name: /complete/i })).toBeVisible()`
  — which waits on the element itself.
- This frame structure reflects current Playwright guidance as of mid-2026; picking a
  frame by index is explicitly discouraged.
