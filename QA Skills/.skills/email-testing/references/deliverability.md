# Deliverability: SPF / DKIM / DMARC — a separate, non-blocking suite

Deliverability answers "will this actually reach the inbox," which is a different question
from "does the flow work." It belongs in its **own suite**, one that does not block the
functional OTP / reset / signup tests. A functional test should still pass even with a
broken DMARC alignment, because the user-facing flow works fine against the capture inbox
either way; merging the two concerns means every flow test goes red over a DNS issue and
buries the signal you actually care about.

## The conceptual trap to avoid

SPF, DKIM, and DMARC outcomes are produced by the **receiving mail server authenticating
the sending domain** — they don't exist as text you can find inside the email body. Don't
write `body.includes('spf')` or `body.match(/dkim/)`. And don't assume Mailpit checks any
of this: it only runs a SpamAssassin-style content score on the captured message. It does
**not** perform real SPF/DKIM/DMARC alignment, since nothing was ever routed through real
DNS.

Getting a genuine alignment result requires an actual **send-and-receive over real DNS**
— a hosted service that truly receives the mail:

| Need | Tool |
|------|------|
| Real SPF/DKIM/DMARC `pass`/`fail` + alignment per message | **Mailosaur** — `message.metadata` / deliverability report exposes auth results |
| One-off score with raw SPF/DKIM/DMARC breakdown | **mail-tester.com** (send to its address, fetch the report) |
| Spam-content score only (no auth) | Mailpit's built-in SpamAssassin score — content heuristics, NOT auth |

## Mailosaur deliverability assertion (separate spec)

```ts
// tests/deliverability/auth.spec.ts  — runs in its own non-blocking job
import { test, expect } from '@playwright/test';
import MailosaurClient from 'mailosaur';

const mailosaur = new MailosaurClient(process.env.MAILOSAUR_API_KEY!);
const serverId = process.env.MAILOSAUR_SERVER_ID!;

test('notification email passes SPF, DKIM, DMARC @deliverability', async () => {
  const sentTo = `deliverability.${Date.now()}@${serverId}.mailosaur.net`;
  await triggerNotificationEmail(sentTo); // your app's send path, over real SMTP

  const message = await mailosaur.messages.get(serverId, { sentTo }, { timeout: 60_000 });

  // Mailosaur returns structured authentication / deliverability results.
  const auth = message.metadata?.ehlo; // plus spam/deliverability report fields
  const report = await mailosaur.analysis?.deliverability?.(message.id!);

  expect(report?.spf?.result, 'SPF').toBe('pass');
  expect(report?.dkim?.[0]?.result, 'DKIM').toBe('pass');
  expect(report?.dmarc?.result, 'DMARC alignment').toBe('pass');
});
```

Exact field names shift between Mailosaur SDK versions, so check the current
deliverability-report docs before relying on one — the underlying point is that you always
read structured **SPF / DKIM / DMARC** `pass`/`fail` + alignment results from the service
itself, never from parsing body text.

## Wiring it as non-blocking

- Tag these tests `@deliverability` and put them in a separate Playwright project or CI
  job (`--grep @deliverability`).
- Mark the job `continue-on-error: true` (GitHub Actions) or make it a non-required check,
  so a deliverability regression raises a warning/alert instead of blocking the release.
- Run it on a schedule (nightly), in addition to whenever send-path code changes —
  deliverability can drift purely from DNS/ESP changes made outside your repo.

Rendering the email's HTML consistently across clients (Outlook, Gmail, Apple Mail dark
mode) is yet another separate concern and is out of scope here — reach for Litmus / Email
on Acid or the `visual-testing` skill instead.
</content>
