# Mailpit + Playwright recipes

Mailpit is the go-to local/self-hosted capture inbox: one Go binary (or the
`axllent/mailpit` Docker image), SMTP listening on `:1025`, with a web UI and REST API on
`:8025`. It's the actively maintained replacement for MailHog, which is now archived (see
the Avoid note in `SKILL.md`). The endpoints your tests will use:

- `GET /api/v1/messages` — list messages, newest first, with `?query=` for full-text
  search.
- `GET /api/v1/message/{ID}` — the full parsed message: `.Text`, `.HTML`, `.Subject`,
  `.From`, `.To`, headers.
- `DELETE /api/v1/messages` — purge everything (use it in global setup, but never rely on
  it as your only isolation mechanism).

Point your app's SMTP configuration at `localhost:1025` for the test environment. Example
docker-compose service:

```yaml
# docker-compose.test.yml
services:
  mailpit:
    image: axllent/mailpit:latest
    ports: ["1025:1025", "8025:8025"]
    environment:
      MP_SMTP_AUTH_ACCEPT_ANY: "true"
      MP_SMTP_AUTH_ALLOW_INSECURE: "true"
```

## Polling helper — no fixed sleep

Mail arrival happens asynchronously. Never write `page.waitForTimeout(5000)` and hope the
message landed by then — that pattern is responsible for most flaky email tests. Instead,
poll the list endpoint with `expect.poll` (or `.toPass`) until a message addressed to
*this specific test's* recipient shows up, then fetch its full body by ID. `expect.poll`
keeps retrying on an interval until its timeout, so quick delivery resolves right away and
slower delivery still eventually succeeds.

```ts
// helpers/mailpit.ts
import { APIRequestContext, expect, request } from '@playwright/test';

const BASE = process.env.MAILPIT_URL ?? 'http://localhost:8025';

type Summary = { ID: string; To: { Address: string }[]; Subject: string };
type Message = {
  ID: string; Subject: string; Text: string; HTML: string;
  From: { Address: string; Name: string };
  To: { Address: string }[];
};

/** Wait for the latest message sent to `recipient`, then return the parsed body. */
export async function waitForEmail(
  api: APIRequestContext,
  recipient: string,
  opts: { timeout?: number; intervals?: number[] } = {},
): Promise<Message> {
  let summary: Summary | undefined;

  await expect
    .poll(
      async () => {
        // Search by recipient so parallel tests never read each other's mail.
        const res = await api.get(
          `${BASE}/api/v1/messages?query=to:${encodeURIComponent(recipient)}`,
        );
        const { messages } = (await res.json()) as { messages: Summary[] };
        summary = messages.find((m) =>
          m.To.some((t) => t.Address.toLowerCase() === recipient.toLowerCase()),
        );
        return summary?.ID ?? null;
      },
      {
        message: `No email for ${recipient}`,
        timeout: opts.timeout ?? 30_000,
        intervals: opts.intervals ?? [500, 1_000, 2_000],
      },
    )
    .not.toBeNull();

  const res = await api.get(`${BASE}/api/v1/message/${summary!.ID}`);
  return (await res.json()) as Message;
}

/** Standalone request context if you are not inside a test with the `request` fixture. */
export async function mailpitContext(): Promise<APIRequestContext> {
  return request.newContext();
}
```

Note: what makes each test deterministic is the combination of the `query=to:` filter and
the follow-up `.find` against `To[].Address` — the code never just grabs `messages[0]`.

## Extracting an OTP and a magic link from the body

Pull data out with an anchored regex run against the email **body** (`message.Text` /
`message.HTML`) — not the live page's `innerText`. Always guard the match: letting a
`null` result flow through silently turns into `undefined`, and the eventual failure shows
up steps later with a confusing message instead of failing where the real problem is.

```ts
export function extractOtp(body: string): string {
  // Anchored 6-digit code. Prefer a label if your template has one.
  const m = body.match(/\b(\d{6})\b/);
  expect(m, 'No 6-digit OTP found in email body').not.toBeNull();
  return m![1];
}

export function extractLink(body: string, pattern = /https?:\/\/\S*(?:verify|confirm|reset|token=)\S*/i): string {
  const m = body.match(pattern);
  if (!m) throw new Error('No verification link found in email body');
  return m[0].replace(/[)>"'.]+$/, ''); // trim trailing punctuation/quotes
}
```

If your OTP might collide with other 6-digit numbers in the message (order numbers, years,
etc.), anchor on a label instead: `body.match(/code[:\s]+(\d{6})/i)`.

## Password-reset E2E (full flow)

Trigger the reset from the UI, capture the actual email, pull out the link, navigate to
it, set a new password, and confirm the new credentials work. Don't call the reset
endpoint directly or hardcode a token — doing so bypasses the exact integration (template
rendering, link generation, token signing) this test is meant to verify.

```ts
import { test, expect } from '@playwright/test';
import { waitForEmail, extractLink } from '../helpers/mailpit';

test('password reset end-to-end', async ({ page, request }) => {
  const email = `reset+${Date.now()}@example.test`; // unique per run

  // 1. Request reset on the UI.
  await page.goto('/forgot-password');
  await page.getByLabel('Email').fill(email);
  await page.getByRole('button', { name: 'Send reset link' }).click();
  await expect(page.getByText('Check your inbox')).toBeVisible();

  // 2. Capture the email and pull the reset link out of the body.
  const message = await waitForEmail(request, email);
  expect(message.Subject).toContain('Reset your password');
  const resetUrl = extractLink(message.HTML || message.Text, /https?:\/\/\S*reset\S*token=\S*/i);

  // 3. Visit the link, set a new password.
  await page.goto(resetUrl);
  await page.getByLabel('New password').fill('Sup3r-secret!');
  await page.getByLabel('Confirm password').fill('Sup3r-secret!');
  await page.getByRole('button', { name: 'Save' }).click();

  // 4. Confirm login works with the new password.
  await page.goto('/login');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill('Sup3r-secret!');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.getByRole('heading', { name: 'Welcome' })).toBeVisible();
});
```

## Signup / OTP / magic-link variations

- **Signup confirmation:** same shape — submit the signup form, `waitForEmail`, check
  `Subject`/`From`, `extractLink(body, /confirm/)`, `page.goto(confirmUrl)`, then confirm
  the account is now active.
- **OTP / MFA:** submit credentials, `waitForEmail`, `extractOtp(body)`, type the code into
  the page, and confirm you end up authenticated.
- **Magic-link login:** request the link, `waitForEmail`, `extractLink`,
  `page.goto(magicUrl)`, and confirm a session was established.

All four build on the same `waitForEmail` + `extractOtp` / `extractLink` pair. Each test
still needs a unique recipient address (see "Deterministic addresses" in `SKILL.md`).
</content>
