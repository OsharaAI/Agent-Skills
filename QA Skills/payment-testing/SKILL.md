---
name: payment-testing
description: >-
  Test payment and checkout flows end to end against PSP sandboxes — Stripe first, with
  the general pattern for Adyen/Braintree/PayPal. Covers Stripe test-mode card numbers and
  their decline codes, the 3DS/SCA challenge flow and its nested-iframe handling in
  Playwright, test clocks for subscription/billing-cycle simulation, webhook testing
  (stripe listen/trigger, signature verification, idempotency), failed/retried payments and
  refunds, and never using real cards. Use when: "test Stripe checkout," "payment test,"
  "3DS test," "test webhook signature," "test subscription renewal," "test clock,"
  "refund test," "decline card test," "checkout E2E."
  Not for: General API contract testing of non-payment endpoints — api-testing. PCI-DSS/regulatory
  compliance audit — compliance-testing.
  Related: api-testing, playwright-automation, compliance-testing, test-data-management, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "1.0"
  category: specialized
---

<objective>
Payment flows break in ways a generic E2E suite simply doesn't catch: a card input
sitting inside a cross-origin iframe that `page.locator` quietly never finds, an annual
renewal you'd otherwise have to wait a year to see, a webhook handler that looks fine
until Stripe retries and the order gets fulfilled twice, an order flipped to "paid" off
a redirect the browser could have forged. This skill is about testing payments against
the failure modes that actually happen — real PSP sandboxes, the documented test cards,
the nested 3DS challenge frame, server-side test clocks, signature-checked webhooks, and
fulfillment that only happens once. No real card number, ever. No live key, ever.
</objective>

## Find Your Scenario Fast

| What you're testing… | Jump to | Reference |
|-------------------|-------|-----------|
| Success / decline / insufficient-funds paths | [Test cards](#stripe-test-cards-and-outcomes) | `references/stripe-test-cards.md` |
| A 3DS/SCA modal challenge | [3DS challenge](#3ds--sca-the-nested-iframe-challenge) | `references/playwright-3ds.md` |
| A renewal that's months or years away | [Test clocks](#test-clocks-server-side-time-travel) | `references/webhooks-and-clocks.md` |
| Webhook delivery to localhost and signature checks | [Webhooks](#webhooks-local-delivery-signatures-idempotency) | `references/webhooks-and-clocks.md` |
| A failed renewal followed by a refund | [Failed payments](#failed-payments-dunning-and-refunds) | `references/webhooks-and-clocks.md` |
| Making fulfillment wait for a real, confirmed payment | [Reconciliation](#reconciliation-fulfill-on-the-webhook-not-the-redirect) | `references/webhooks-and-clocks.md` |
| Adyen / PayPal / Braintree sandboxes instead of Stripe | [Multi-PSP](#multi-psp-adyen-paypal-braintree) | `references/multi-psp.md` |

## Before You Start

Check `.agents/qa-project-context.md` first and don't re-ask anything it already covers
(PSP choice, stack, test framework, existing fixtures). Beyond that, pin down:

- **Which PSP is in use, and is it Stripe?** This skill defaults to Stripe. Other PSPs
  follow the same shape but ship their own sandbox cards/accounts — see
  [Multi-PSP](#multi-psp-adyen-paypal-braintree).
- **One-time charges, subscriptions, or both?** Subscriptions bring in test clocks,
  dunning, and the `invoice.*` event lifecycle; one-off payments don't need any of that.
- **Does SCA/3DS apply here?** Card flows in the EU/UK almost always trigger a challenge.
  If so, you need the nested-iframe handling, not ordinary locators.
- **Does fulfillment currently happen on the webhook, or on the redirect?** If it's
  triggered from `return_url`, that's exactly the bug to write a test for — fulfillment
  has to wait for a verified webhook instead.
- **Where do webhooks land during tests?** Locally via `stripe listen`, or against a
  deployed preview environment — the delivery mechanism differs.

## Non-Negotiables

1. **Real cards and live keys are off the table, full stop.** Any real PAN, in any
   environment, breaks Stripe's Services Agreement and pulls your codebase into PCI
   scope. The only acceptable setup is test mode (`pk_test_`/`sk_test_`) with the
   documented Stripe test cards. Masking or encrypting a real card number doesn't solve
   the problem — only removing it does.

2. **The server confirms money moved, not the client.** A redirect, an `onApprove`
   callback, or a `?status=success` query string can arrive early, get replayed, or be
   faked outright. Only fulfill an order after a signature-verified
   `payment_intent.succeeded` webhook, and double-check it with an API `retrieve` call.

3. **Signature verification happens before body parsing, not after.** If you parse the
   JSON body first, you've destroyed the raw bytes `constructEvent` needs to work. Give
   the webhook route the raw body; every other route can parse JSON as normal.

4. **Billing time lives on Stripe's servers, not yours.** Faking the clock inside your
   test process has zero effect on Stripe's billing engine. Test clocks are the only way
   to move billing time forward.

5. **Every webhook may arrive more than once.** Stripe's delivery model includes retries.
   Idempotency has to be keyed on `event.id` and stored durably — an in-memory set does
   not count as idempotency.

## Stripe Test Cards and Outcomes

Pick the card that reliably produces the outcome you're testing. The four that cover
most cases:

| PAN | Outcome | Code |
|-----|---------|------|
| `4242424242424242` | Succeeds | — |
| `4000000000000002` | Declined | `card_declined` (generic_decline) |
| `4000000000009995` | Declined | `insufficient_funds` |
| `4000000000003220` | 3DS always challenges | — |
| `4000000000000341` | Attaches, then fails on charge | `card_declined` |

Run the app under test on test keys (`pk_test_…`/`sk_test_…`) and check for that in your
test setup. **Avoid `4111111111111111`** — it's a generic Luhn-valid number from the
Braintree/PayPal era, not a Stripe test card, and it won't reliably decline.

Since the card field sits inside a cross-origin Stripe iframe, you have to fill it
through `frameLocator` — `page.locator` won't reach it. For a lightweight smoke test,
check the outcome against on-screen copy; for something more robust, check the
server-side `last_payment_error.decline_code` returned by `paymentIntents.retrieve`.
Complete Playwright tests for success / `card_declined` / `insufficient_funds` are in
`references/stripe-test-cards.md`.

## 3DS / SCA: The Nested-Iframe Challenge

This is the part that trips people up most. Stripe's 3DS challenge lives in **a frame
nested inside the Stripe modal frame** — one `frameLocator` alone can't reach it. You
need to chain `frameLocator` from the outer frame into the inner one, then click
**Complete authentication**.

Approaches that don't work, and why:

- `page.locator('#card')` — the field is cross-origin, so this locator matches nothing.
- `page.frames()[1]` — frame **position** shifts whenever Stripe adds or reorders
  frames. Never pick a frame by index.
- `await page.waitForTimeout(5000)` — a guess at how long the challenge takes. Wait for
  the element instead.

Here's the correct shape (the full test, including the failed-authentication variant,
is in `references/playwright-3ds.md`):

```ts
// 3DS-required card so the challenge always appears.
await card.getByPlaceholder('Card number').fill('4000000000003220');
await page.getByRole('button', { name: /pay/i }).click();

// Nested: outer Stripe challenge frame → inner ACS frame. One frameLocator is not enough.
const inner = page
  .frameLocator('iframe[name^="__privateStripeFrame"]')
  .frameLocator('iframe#challengeFrame, iframe[name="acsFrame"]');
await inner.getByRole('button', { name: /complete authentication|complete|authorize/i }).click();

await expect(page).toHaveURL(/\/success/);              // assert the succeeded state
await expect(page.getByText(/payment succeeded/i)).toBeVisible();
```

For a setup-intent / first-use SCA scenario, `4000002760003184` is the alternative card
— documentation and tooling treat it as the go-to when you need a 3DS card outside the
one-time-payment case.

## Test Clocks: Server-Side Time Travel

Testing a yearly renewal shouldn't mean waiting a year — Stripe's **test clocks**, a
server-side feature, solve that. Client-side fakes like `jest.useFakeTimers`, sinon, or
mocking `Date` have no effect on Stripe's billing engine.

A few rules that will bite you if you skip them:
- Create the clock at a `frozen_time`, and attach the customer **when you create them**
  — `test_clock: clock.id` can't be added to a customer that already exists.
- `testHelpers.testClocks.advance` only moves **forward** — there's no rewinding. Move
  at most two billing cycles forward per call.
- After advancing, poll until the clock reaches `ready`, then check the renewal invoice
  and any webhooks that fired.

```ts
const clock = await stripe.testHelpers.testClocks.create({
  frozen_time: Math.floor(Date.now() / 1000), name: 'annual-renewal',
});
const customer = await stripe.customers.create({ test_clock: clock.id /* … */ });
// …create subscription, then advance ~12 months forward:
await stripe.testHelpers.testClocks.advance(clock.id, { frozen_time: oneYearLater });
```

The full create/advance/assert sequence is in `references/webhooks-and-clocks.md`
(section 4).

## Webhooks: Local Delivery, Signatures, Idempotency

**Delivering events locally.** Skip ngrok, and don't poll the API for status changes.
`stripe listen` tunnels test events straight to localhost, and `stripe trigger` fires
them whenever you want:

```bash
stripe listen --forward-to localhost:3000/webhooks   # prints whsec_… ONCE at startup
stripe trigger payment_intent.succeeded
```

Take that `whsec_…` value and put it in `STRIPE_WEBHOOK_SECRET`. It's the **signing
secret** — a completely different value from `STRIPE_SECRET_KEY` (`sk_test_…`); don't
mix them up.

**Checking the signature.** Mount `express.raw` on the webhook route **ahead of** any
global `express.json()` middleware, so `constructEvent` receives the raw body it needs.
A forged or altered event must come back with **400**; never write your own `===`
string comparison for this.

```ts
app.post('/webhooks', express.raw({ type: 'application/json' }), (req, res) => {
  const sig = req.headers['stripe-signature'] as string;
  try {
    const event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET!);
    return handleEvent(event, res);
  } catch (err) {
    return res.status(400).send(`Webhook Error: ${(err as Error).message}`); // SignatureVerificationError
  }
});
app.use(express.json()); // everything else, after the webhook route
```

**Idempotency.** Because Stripe retries delivery, the same `event.id` can show up
twice. Idempotency keys on outbound API calls don't help with deduplicating inbound
webhooks. Store `event.id` under a **UNIQUE** constraint and bail out on conflict — an
in-memory set won't survive a restart and won't work across multiple instances anyway.
On a duplicate, the handler should still return **200** (so Stripe stops retrying),
while fulfillment itself runs exactly **once**.

```ts
const inserted = await db.query(
  `INSERT INTO processed_events (id) VALUES ($1) ON CONFLICT (id) DO NOTHING RETURNING id`, [event.id]);
if (inserted.rowCount === 0) return res.status(200).send('duplicate ignored');
```

`references/webhooks-and-clocks.md` (sections 2–3) has both the signature test (valid
accepted, forged rejected with 400) and the idempotency test (same event delivered
twice, fulfilled once).

## Failed Payments: Dunning and Refunds

To exercise a failed recurring charge end to end, subscribe using
`4000000000000341` (SDK alias `pm_card_chargeCustomerFail`) — it **attaches fine** to
the customer but **fails when charged later**, which is exactly what a renewal-failure
test needs. Cards that decline immediately at attach time can never be saved, so they
can't simulate a renewal that fails down the line.

Drive the whole lifecycle with a test clock:
1. Subscribe the customer (on a test clock) using the attach-then-fail card.
2. `advance` the clock past the renewal date so Stripe attempts the charge.
3. The charge fails, Stripe emits **`invoice.payment_failed`**, and the subscription
   flips to **`past_due`**. Check both.
4. Resolve it with **`refunds.create`** (which fires `charge.refunded`) — don't "solve"
   it by deleting the subscription instead.

The full driver is in `references/webhooks-and-clocks.md` (section 5).

## Reconciliation: Fulfill on the Webhook, Not the Redirect

Only flip an order to paid **after** a signature-verified `payment_intent.succeeded`
webhook, re-confirmed against the API — never off the `return_url` redirect, never off
a client-side success flag, and never by polling with a sleep loop.

```ts
if (event.type === 'payment_intent.succeeded') {
  const verified = await stripe.paymentIntents.retrieve(event.data.object.id);
  if (verified.status === 'succeeded' && verified.amount_received === expected) {
    await markOrderPaid(verified.metadata.orderId); // fulfillment happens HERE
  }
}
```

The reconciliation test should confirm the order stays `pending` right after the
redirect and only becomes `paid` once the verified webhook arrives —
`references/webhooks-and-clocks.md` (section 6) has the full test.

## Multi-PSP: Adyen, PayPal, Braintree

Stripe's test cards **won't work** on any other PSP. Each one has its own sandbox cards
and its own sandbox buyer accounts. Reuse the *shape* of your Stripe tests, but swap in
that PSP's own sandbox values — never reuse Stripe PANs or any live/production key.

- **Adyen** — has its own test cards (e.g. `4212345678910014` for 3DS2); a lot of its
  declines are driven by the **transaction amount** (`.13` gets refused, `.51` gets a
  referral) rather than by the card itself. Events show up as HMAC-signed
  notifications.
- **PayPal** — you log in with a **sandbox buyer account** (a sandbox personal
  email/password combo), not a card number. Confirm the payment server-side through the
  Orders API / webhooks — don't rely on the client-side `onApprove` callback alone.
- **Braintree** — has its own sandbox **test card** numbers, used through the Drop-in
  UI or Hosted Fields; the amount drives the transaction outcome, and the card number
  drives verification.

What holds true across all of them: separate test/sandbox credentials, never a real
card, and fulfillment gated on the verified server-side event or notification. Full
detail: `references/multi-psp.md`.

## Anti-Patterns

### 1. Defaulting to `4111111111111111`
That Luhn-valid number belongs to the Braintree/PayPal era, not Stripe. Use
`4242424242424242` for success, and the specific decline cards
(`4000000000000002`, `4000000000009995`) for failure paths.

### 2. Treating the card input like a normal form field
`page.locator('#card-number')` matches nothing because the field lives in a
cross-origin iframe. `frameLocator` is required.

### 3. Picking iframes by numeric index
`page.frames()[1]` breaks as soon as Stripe reorders frames. Match on a stable name
prefix (`iframe[name^="__privateStripeFrame"]`) and chain a second `frameLocator` for
the nested 3DS challenge.

### 4. Using `waitForTimeout` to wait out the challenge
Flaky when CI is slow, wasteful when CI is fast. Wait on the element
(`expect(...).toBeVisible()` or an auto-waiting locator action) instead of the clock.

### 5. Mocking time client-side for billing tests
`jest.useFakeTimers`, sinon, or mocking `Date` can't touch Stripe's server-side billing.
A test clock is the only path.

### 6. Reaching for ngrok or polling to receive local webhooks
`stripe listen --forward-to localhost:3000/webhooks` already tunnels events natively,
and `stripe trigger` fires them on demand — no public tunnel, no status polling needed.

### 7. Parsing the request body before verifying the signature
A global `express.json()` placed ahead of the webhook route wipes out the raw body
`constructEvent` needs, so verification can never succeed. `express.raw` has to be
mounted on the webhook route first.

### 8. Mixing up outbound idempotency keys with inbound webhook dedup, or using memory-only storage
Idempotency keys on outbound requests don't deduplicate inbound webhooks, and an
in-memory `Set` disappears on restart. Persist `event.id` behind a UNIQUE constraint.

### 9. Fulfilling based on the redirect or a client-side success flag
`return_url` can fire early, get replayed, or be forged. Fulfillment should wait for
the verified `payment_intent.succeeded` webhook.

### 10. "Resolving" a failed renewal by deleting the subscription
The correct fix is a refund through `refunds.create`, which keeps the dunning lifecycle
(`invoice.payment_failed` → `past_due`) intact and testable.

### 11. Justifying a real card "just for CI"
A hardcoded real PAN is a PCI/compliance problem no matter what environment it's in.
The actual fix is a test card in test mode, plus scrubbing the secret from the repo and
its git history and rotating any exposed key. Masking or encrypting it doesn't make it
okay.

## Verification

- `stripe listen --forward-to localhost:3000/webhooks` should print a `whsec_…` value
  and show events arriving when you run `stripe trigger payment_intent.succeeded`.
- Running the 3DS test with `4000000000003220` should reach the nested frame and click
  **Complete authentication** (the test should fail loudly, not silently, if that frame
  can't be found).
- Signature test: a tampered `Stripe-Signature` returns **400**; a header built with
  `generateTestHeaderString` returns **200**.
- Idempotency test: sending the same `event.id` twice results in exactly one
  fulfillment.
- `grep -rE 'pk_live|sk_live|4111111111111111'` across the test suite comes back empty.

## Done When

- The checkout suite covers success (`4242424242424242`), `card_declined`
  (`4000000000000002`), and `insufficient_funds` (`4000000000009995`), each checking
  the matching outcome, all running on `pk_test_`/`sk_test_` keys.
- A 3DS test fills `4000000000003220`, reaches the nested challenge frame through
  chained `frameLocator` calls, clicks **Complete authentication**, and checks for the
  succeeded state — no `frames()[index]`, no `waitForTimeout`.
- A subscription-renewal test uses a Stripe test clock
  (`testHelpers.testClocks.create` + `advance`, forward-only, customer attached at
  creation time) rather than any client-side time mock.
- Local webhooks arrive via `stripe listen --forward-to` / `stripe trigger`, and the
  `whsec_…` value is wired into `STRIPE_WEBHOOK_SECRET` (kept separate from
  `STRIPE_SECRET_KEY`).
- The webhook handler verifies the signature via `constructEvent` against the **raw**
  body before parsing, returns 400 for a forged event, and a test confirms it.
- Idempotency is enforced by persisting `event.id` under a UNIQUE constraint; a
  duplicate delivery returns 200 and results in exactly one fulfillment, proven by a
  test.
- A failed-renewal test drives `invoice.payment_failed` → `past_due` →
  `refunds.create` using a test clock and the attach-then-fail card
  `4000000000000341`.
- A reconciliation test confirms the order only becomes `paid` after the verified
  `payment_intent.succeeded` webhook (double-checked via `paymentIntents.retrieve`),
  never from the redirect.
- `grep -rE 'pk_live|sk_live|4111111111111111'` finds no live key and no banned PAN in
  the test suite. (A bare `[0-9]{16}` scan would flag every legitimate test card as a
  false positive — match on live-key prefixes and the specific banned `4111…` number,
  not on every 16-digit string.)

## Related Skills

- **api-testing** — general REST/GraphQL endpoint testing, schema validation, and auth
  flows for anything that isn't a PSP checkout or webhook. Use it when the target
  doesn't involve payments.
- **playwright-automation** — the Page Object Model, fixtures, and general browser E2E
  mechanics the 3DS flow here is built on top of.
- **compliance-testing** — PCI-DSS, GDPR, and other regulatory audit work. This skill
  keeps you *out* of PCI scope by relying on test cards; go there for a formal
  compliance audit.
- **test-data-management** — seeding customers, subscriptions, and fixtures, and
  managing the test-clock-bound customers this skill creates.
- **qa-project-context** — the universal starting point for PSP, stack, and fixture
  conventions that every question above should defer to.

## Reference Files (in `references/`)

- **stripe-test-cards.md** — the full test-card catalogue with decline codes plus the
  Playwright success/decline/insufficient-funds tests.
- **playwright-3ds.md** — nested-iframe 3DS challenge handling, both the complete and
  fail variants, plus selector notes.
- **webhooks-and-clocks.md** — `stripe listen`/`trigger`, raw-body signature
  verification, idempotency keyed on `event.id`, test clocks, dunning with refunds, and
  reconciliation.
- **multi-psp.md** — Adyen, PayPal, and Braintree sandbox patterns and how they differ
  from Stripe.
