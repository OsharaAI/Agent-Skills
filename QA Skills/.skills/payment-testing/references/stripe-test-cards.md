# Stripe test cards and how to assert on their outcomes

Every card below only functions in test mode (keys `pk_test_…` / `sk_test_…`). Using a
real PAN in any mode breaches the Services Agreement — see the PCI note in `SKILL.md`.
Before relying on a specific number, double-check the current list at
https://docs.stripe.com/testing.

## The card catalogue

| PAN | Outcome | decline_code / failure_code | Use for |
|-----|---------|-----------------------------|---------|
| `4242424242424242` | Succeeds, no auth | — | Happy path Visa |
| `4000000000000002` | Declined at charge | `card_declined` (generic_decline) | Generic decline path |
| `4000000000009995` | Declined at charge | `insufficient_funds` | Insufficient-funds path |
| `4000000000009987` | Declined at charge | `lost_card` | Lost-card path |
| `4000000000000069` | Declined at charge | `expired_card` | Expired-card path |
| `4000000000000127` | Declined at charge | `incorrect_cvc` | Bad-CVC path |
| `4000000000003220` | 3DS **always** challenges | — | 3DS/SCA challenge flow |
| `4000002760003184` | 3DS required, succeeds after auth | — | SCA on first use |
| `4000000000000341` | **Attaches** to customer, **fails on later charge** | `card_declined` | Failed recurring renewal |

`4000000000000341` is the one people tend to overlook: any card that declines at
*attach* time can never be saved to a Customer object, so it can't be used to simulate
a renewal that fails *after* the card is already on file. This particular card attaches
without a hitch and only fails once a subscription invoice actually tries to charge
it — which is precisely the dunning scenario you want.

## Never reach for these

- `4111111111111111` — a generic Luhn-valid PAN left over from the Braintree/PayPal
  era. **It is not a Stripe test card**, and it won't reliably decline — don't use it
  here.
- Any real card number — including "just this once, just in CI."

## Playwright: check the right outcome for each card

The card field lives inside a cross-origin Stripe iframe, so use `frameLocator` — never
`page.locator` directly (see `playwright-3ds.md`). The helper below fills the Payment
Element and submits it.

```ts
import { test, expect, Page } from '@playwright/test';

// Stripe keys in the app under test must be pk_test_… — assert that in setup, never pk_live_.
async function fillCard(page: Page, pan: string) {
  const card = page.frameLocator('iframe[name^="__privateStripeFrame"]');
  await card.getByPlaceholder('Card number').fill(pan);
  await card.getByPlaceholder('MM / YY').fill('12 / 34');
  await card.getByPlaceholder('CVC').fill('123');
  await card.getByPlaceholder('ZIP').fill('42424');
  await page.getByRole('button', { name: /pay/i }).click();
}

test('successful Visa payment', async ({ page }) => {
  await page.goto('/checkout');
  await fillCard(page, '4242424242424242');
  await expect(page).toHaveURL(/\/success/);
  await expect(page.getByText(/payment succeeded/i)).toBeVisible();
});

test('card_declined surfaces a decline message', async ({ page }) => {
  await page.goto('/checkout');
  await fillCard(page, '4000000000000002');
  // generic_decline → "Your card was declined."
  await expect(page.getByText(/your card was declined/i)).toBeVisible();
  await expect(page).not.toHaveURL(/\/success/);
});

test('insufficient_funds surfaces the specific message', async ({ page }) => {
  await page.goto('/checkout');
  await fillCard(page, '4000000000009995');
  await expect(page.getByText(/insufficient funds/i)).toBeVisible();
});
```

For a more robust check than parsing UI copy, assert against the
`PaymentIntent.last_payment_error.decline_code` fetched server-side
(`paymentIntents.retrieve(id)` → `card_declined` / `insufficient_funds`) rather than
localized display text, which is more likely to change out from under you.
