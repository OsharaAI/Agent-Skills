# Hosted inboxes: Mailosaur, MailSlurp, Ethereal

Reach for one of these once local Mailpit stops being sufficient — because you need a
**genuinely deliverable, external address** (staging, a third-party ESP, real DNS),
isolation that holds up under heavy parallelism, or actual SPF/DKIM/DMARC alignment
results. Keep every API key in a secret / env var (`MAILOSAUR_API_KEY`,
`MAILSLURP_API_KEY`) — never hardcode it inline.

## Mailosaur — real addresses, auto-waiting `messages.get`

Every Mailosaur server exposes a domain like `<serverId>.mailosaur.net`, and any address
under it is captured automatically. `messages.get(serverId, { sentTo })` **auto-waits**
(around 10s by default, adjustable via `timeout`) for a matching message to appear — so
there's no need for your own sleep, and no need to reach for `messages.list(` plus a
hand-rolled poll loop. Filter by `sentTo` to keep parallel runs deterministic.

```ts
// helpers/mailosaur.ts
import MailosaurClient from 'mailosaur';

const mailosaur = new MailosaurClient(process.env.MAILOSAUR_API_KEY!);
const serverId = process.env.MAILOSAUR_SERVER_ID!;
const serverDomain = `${serverId}.mailosaur.net`;

/** A unique, real, deliverable address for this test. */
export function testAddress(tag = ''): string {
  return `${tag || 'user'}.${Date.now()}.${Math.random().toString(36).slice(2, 8)}@${serverDomain}`;
}

export async function getEmail(sentTo: string, timeout = 30_000) {
  // Auto-waits for a matching message; throws on timeout.
  return mailosaur.messages.get(serverId, { sentTo }, { timeout });
}
```

```ts
// tests/welcome.mailosaur.spec.ts
import { test, expect } from '@playwright/test';
import { getEmail, testAddress } from '../helpers/mailosaur';

test('staging welcome email — subject, from, link domain', async ({ page }) => {
  const email = testAddress('signup');
  await page.goto('https://staging.example.com/signup');
  await page.getByLabel('Email').fill(email);
  await page.getByRole('button', { name: 'Create account' }).click();

  const message = await getEmail(email);

  // Assert content, not just existence.
  expect(message.subject).toBe('Welcome to Example');
  expect(message.from?.[0].email).toBe('hello@example.com');

  const links = message.html?.links ?? [];
  expect(links.length).toBeGreaterThan(0);
  expect(links.every((l) => new URL(l.href!).hostname.endsWith('staging.example.com'))).toBe(true);

  // OTP / codes are exposed in the structured `codes` array too:
  // const otp = message.html?.codes?.[0]?.value;
});
```

Mailosaur also exposes structured `message.html.links`, `message.html.codes`, and
attachment metadata directly — favor these over scraping the raw body with regex whenever
they're available.

## MailSlurp — per-test throwaway inbox

MailSlurp is API-first: spin up a fresh inbox for each test, send/receive through it, then
wait. `createInbox()` returns a unique `emailAddress` plus an `id`; `waitForLatestEmail
(inbox.id, timeoutMs)` blocks until a message shows up — no fixed delay, no IMAP library
involved. Giving every test its own inbox (rather than sharing one) is what actually buys
you parallel isolation.

```ts
// helpers/mailslurp.ts
import { MailSlurp } from 'mailslurp-client';

export const mailslurp = new MailSlurp({ apiKey: process.env.MAILSLURP_API_KEY! });

// In a test (Playwright fixture or beforeEach):
//   const inbox = await mailslurp.createInbox();
//   ... use inbox.emailAddress in the signup form ...
//   const email = await mailslurp.waitForLatestEmail(inbox.id, 60_000);
```

```ts
// tests/otp.mailslurp.spec.ts
import { test, expect } from '@playwright/test';
import { mailslurp } from '../helpers/mailslurp';

test('login OTP via per-test inbox', async ({ page }) => {
  const inbox = await mailslurp.createInbox(); // unique throwaway inbox

  await page.goto('/login');
  await page.getByLabel('Email').fill(inbox.emailAddress);
  await page.getByRole('button', { name: 'Send code' }).click();

  // Blocks until an email lands in THIS inbox; 60s timeout, no sleep.
  const email = await mailslurp.waitForLatestEmail(inbox.id, 60_000);

  const otp = email.body?.match(/\b(\d{6})\b/)?.[1];
  expect(otp, 'no OTP in email').toBeTruthy();

  await page.getByLabel('Verification code').fill(otp!);
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page).toHaveURL(/\/app/);
});
```

Skip `imap-simple` / `node-imap` / `imapflow` against a real mailbox for this kind of
test — MailSlurp's `waitForLatestEmail` already handles the polling and gives you parallel
isolation for free.

## Ethereal — throwaway local preview (NOT for CI assertions)

Ethereal is a fake SMTP service meant purely for **eyeballing** what an email looks like
during local development, with no service setup required. It captures the message and
hands you a preview URL — it **delivers nothing**, so there's no real inbox to assert
against in CI. Reserve it strictly for previewing a template.

```ts
// scripts/preview-welcome.ts  — run locally, opens a preview URL
import nodemailer from 'nodemailer';

const account = await nodemailer.createTestAccount(); // throwaway Ethereal account
const transporter = nodemailer.createTransport({
  host: account.smtp.host,
  port: account.smtp.port,
  secure: account.smtp.secure,
  auth: { user: account.user, pass: account.pass },
});

const info = await transporter.sendMail({
  from: '"Example" <hello@example.test>',
  to: 'preview@example.test',
  subject: 'Welcome to Example',
  html: '<h1>Welcome!</h1><p>Confirm your account.</p>',
});

// Open this in a browser to preview the rendered message:
console.log('Preview URL:', nodemailer.getTestMessageUrl(info));
```

For anything asserted in CI, use Mailpit locally or Mailosaur/MailSlurp for real
addresses — Ethereal should never be part of that path.
</content>
