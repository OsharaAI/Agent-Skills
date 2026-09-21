# Testing other PSP sandboxes: Adyen, PayPal, Braintree

The trap to avoid: assuming a Stripe test card will work anywhere else. It won't. Every
PSP maintains its own sandbox cards and its own sandbox buyer accounts. Take the
*pattern* from your Stripe tests, not the literal card numbers — and always check each
PSP's current documented list before relying on a specific value.

## What carries over from Stripe, and what doesn't

| Concept | Stripe | General pattern (all PSPs) |
|---------|--------|----------------------------|
| Test mode isolation | `pk_test_`/`sk_test_` | Every PSP keeps sandbox/test credentials separate — never use live keys |
| Triggering a specific outcome | Specific PANs | Either PSP-specific sandbox PANs **or** "magic" amounts, depending on the PSP |
| Async confirmation | webhooks (`payment_intent.succeeded`) | webhooks / notifications — fulfillment should wait for the verified server event, never the redirect |
| No real cards | mandatory | mandatory everywhere — PCI scope applies regardless of PSP |
| Local event delivery | `stripe listen` | varies by PSP (Adyen CLI/dashboard replay; PayPal's webhook simulator) |

## Adyen

- Test cards are **not the same** as Stripe's — for example, `4212 3456 7891 0014`
  triggers the 3DS2 challenge flow. Pull the current list from Adyen's own docs.
- A large share of decline outcomes come from the **amount charged**, not the card:
  amounts ending in `.13` get refused, `.51` gets a referral. So the same card can
  either succeed or decline depending purely on the amount.
- Events arrive as Adyen **notifications** (its version of webhooks); check the HMAC
  signature — this is not the same verification as Stripe's.

## PayPal

- Log in and approve using **sandbox buyer accounts** (a sandbox personal account's
  email + password), not a card number — create these in the PayPal Developer
  Dashboard.
- If you're testing PayPal's card-based flow, choose a sandbox test card and place a
  rejection trigger inside the cardholder **name** field.
- Confirm the payment server-side via the Orders API or webhooks; don't rely solely on
  the client-side `onApprove` callback for fulfillment.

## Braintree (a PayPal company)

- The sandbox only accepts **specific Braintree test card numbers** — its own list, not
  Stripe's. Integrations typically go through **Drop-in UI** or **Hosted Fields**.
- Whether a transaction succeeds or declines is controlled by the **test amount**;
  card verification (Vault, recurring billing) is controlled by the **card number**.
- Braintree maintains its own 3DS test cards and flow, separate from Stripe's.

## The general rule

When you add support for a new PSP: track down that PSP's sandbox credentials, its
sandbox cards or buyer accounts, and how it delivers events/notifications. Carry over
the *structure* of your existing Stripe tests (happy path, decline, 3DS, webhook
reconciliation) and substitute that PSP's own sandbox values. Never reuse a Stripe PAN
or a live key from any PSP.
