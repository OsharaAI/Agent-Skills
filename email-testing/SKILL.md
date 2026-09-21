---
name: email-testing
description: >-
  End-to-end testing of email-dependent flows — signup confirmation, password reset,
  magic-link login, OTP/MFA codes, and notification emails. Covers the capture-inbox
  decision tree (Mailpit, Mailosaur, MailSlurp, Ethereal), Playwright polling without
  fixed sleeps, regex extraction of links/OTPs from the email body, deterministic
  per-test addresses (plus-addressing, per-inbox), subject/from/header/link assertions,
  and SPF/DKIM/DMARC deliverability checks as a separate suite.
  Use when: "test the signup confirmation email," "password reset email test,"
  "magic-link login test," "capture OTP from email," "Mailpit," "Mailosaur," "MailSlurp,"
  "email arrives flaky in CI," "assert email subject/from/links."
  Not for: Sending transactional email from your app code, or API-only contract tests of
  an email provider — those are api-testing / app concerns. Email HTML rendering across
  clients (Outlook/Gmail dark mode) is out of scope (note it as a gap; use visual-testing
  or Litmus).
  Related: playwright-automation, api-testing, test-data-management, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "1.0"
  category: specialized
---

<objective>
Anything that depends on an email link or code can pass a test for the wrong reason. A
"sign up, then hit the confirm endpoint" test proves the endpoint works, not that the
system actually generated, addressed, templated, and delivered a linkable email. This
skill's approach is to capture the genuine message, wait for it with a poll instead of a
guessed sleep, pull the OTP or link out of the body with an anchored regex, and drive the
rest of the flow from there — so a broken template, a bad token signature, or mail sent
to the wrong recipient shows up as a failing test. Deliverability checks (SPF/DKIM/DMARC)
live in their own non-blocking suite, kept apart so a DNS misconfiguration never takes
down the functional gate.
</objective>

---

## Quick Route

| Situation | Go to |
|-----------|-------|
| Pick a capture tool | "Capture-inbox decision tree" below |
| Poll an inbox without a sleep | `references/mailpit-playwright.md` (polling helper) |
| Pull an OTP / link out of the body | `references/mailpit-playwright.md` (extraction) |
| Full password-reset / signup / magic-link E2E | `references/mailpit-playwright.md` |
| Real addresses on staging | `references/hosted-inboxes.md` (Mailosaur) |
| Per-test throwaway inbox | `references/hosted-inboxes.md` (MailSlurp) |
| Just preview a template locally | `references/hosted-inboxes.md` (Ethereal) |
| Flag SPF/DKIM/DMARC problems | `references/deliverability.md` |
| Tests pass locally, "no email yet" in CI | "Flaky email in CI" below |

---

## Discovery Questions

Look for `.agents/qa-project-context.md` first. If it already answers one of these, don't
re-ask it.

- **Where does the mail need to land?** If local capture (Mailpit) is enough, most
  functional flows are covered at no cost. If you need a *genuinely deliverable, external*
  address — staging, a third-party ESP, real DNS — you need a hosted inbox (Mailosaur /
  MailSlurp). This one question drives most of the tool choice.
- **How much does the suite run in parallel?** Under heavy parallelism, "read the newest
  email" stops meaning anything specific — you need per-test unique addresses or per-test
  inboxes instead of a shared mailbox.
- **Which flows are involved?** Signup confirmation, password reset, magic-link login,
  OTP/MFA, notifications — the shape is always capture → extract → complete, but what gets
  extracted differs (a link vs. a 6-digit code).
- **Does deliverability matter here?** Whether mail actually lands in the inbox and passes
  SPF/DKIM/DMARC is a separate, non-blocking concern — not something the OTP/reset test
  itself should check. Settle this up front.
- **Dev-time preview or CI assertion?** Eyeballing a template while developing calls for
  Ethereal; asserting behavior in CI calls for Mailpit/Mailosaur/MailSlurp. Keep these
  separate.

---

## Core Principles

1. **Capture the real email — don't route around it.** Hitting the reset endpoint directly,
   or hardcoding a token, bypasses exactly what the test is supposed to prove: templating,
   recipient resolution, link generation, token signing. Trigger it from the UI and read
   the actual inbox.

2. **Poll instead of sleeping.** Mail delivery is async, so a fixed `waitForTimeout` is
   either too short (flaky) or too long (wastes CI minutes) — this is the leading cause of
   flaky email tests. Use `expect.poll` / `.toPass` against `/api/v1/messages`, or rely on a
   built-in waiter (`messages.get`, `waitForLatestEmail`) that already polls internally.

3. **Give every test its own recipient.** If two parallel tests both go looking for "the
   latest signup email," they'll grab each other's message. Make each test's address
   unique — via plus-addressing or a dedicated inbox — and **filter reads by that
   recipient**. Wiping the inbox between tests does not solve this under parallelism.

4. **Pull data out of the body with a guarded, anchored regex.** Extract the OTP or link
   from `message.Text` / `message.HTML`, never from the rendered page. Match with something
   like `\d{6}`, and always check the match isn't null — a missing code should throw, not
   silently become `undefined`.

5. **Check content, not just presence.** "Something arrived" is a thin assertion. Verify
   `subject`, `from`, and that any links point at the expected domain — otherwise
   wrong-template and wrong-link bugs slip through.

6. **Keep deliverability in its own lane.** SPF/DKIM/DMARC results come from a real
   receiving server authenticating your domain, never from text in the body — and this
   suite must not gate the functional tests.

---

## Capture-inbox decision tree

Start with whichever tool is cheapest and still receives your mail. **Mailpit** is the
default for local and CI functional testing; reach past it only when you actually need a
real address or stronger parallel isolation.

| Tool | Hosting / cost | Address type | Use when |
|------|----------------|--------------|----------|
| **Mailpit** | Self-host, single binary or docker, **free / open source** | Any local SMTP recipient | Default. Local + GitHub Actions functional tests, tight budget. REST API at `:8025` (`/api/v1/messages`). |
| **Mailosaur** | Hosted (API key), paid | **Real** `*.mailosaur.net` addresses | Staging/prod-like flows needing a real deliverable address; auto-waiting `messages.get(serverId, { sentTo })`; structured links/codes; real SPF/DKIM/DMARC. |
| **MailSlurp** | Hosted (API key), paid | Real, per-inbox | Per-test throwaway inboxes via `createInbox()` + `waitForLatestEmail`; strong parallel isolation. |
| **Ethereal** | Hosted throwaway, free | Captures, **delivers nothing** | Local-dev template **preview** only (`createTestAccount` + `getTestMessageUrl`). NOT for CI assertions. |

For a budget-conscious signup-flow suite running locally and in GitHub Actions, reach for
**Mailpit** — a single binary or docker image with a free, open-source REST API on `:8025`.
When a suite later needs a real, externally-deliverable address, graduate it to
**Mailosaur** or **MailSlurp**. Resist the shortcut of "just check the database instead" —
a database row only proves a write happened, not that mail was actually sent, addressed,
and clickable.

**Skip MailHog** — it's been archived and unmaintained since 2020; Mailpit is its
drop-in replacement (same ports, compatible API), confirmed current as of mid-2026. Also
avoid smtp4dev and Papercut for new suites — Mailpit's search and API are better suited to
automated assertions.

See `references/mailpit-playwright.md` for the docker-compose file, the polling helper, and
the extraction utilities; see `references/hosted-inboxes.md` for Mailosaur, MailSlurp, and
Ethereal.

---

## Polling an inbox (Mailpit)

Query the list endpoint with Playwright's `request` fixture, locate the message addressed
to *this test's* recipient, and then fetch its full body by ID. Wrap the search in
`expect.poll` with a `timeout` and `intervals` so it keeps retrying until a match shows up
— fast delivery resolves immediately, slow delivery still eventually passes.

```ts
// `request` is the Playwright APIRequestContext fixture; plain fetch() works too.
await expect.poll(async () => {
  const res = await request.get(`http://localhost:8025/api/v1/messages?query=to:${encodeURIComponent(to)}`);
  const { messages } = await res.json();
  return messages.find((m) => m.To.some((t) => t.Address === to))?.ID ?? null;
}, { timeout: 30_000, intervals: [500, 1_000, 2_000] }).not.toBeNull();
// then: request.get(`http://localhost:8025/api/v1/message/${id}`) → { Text, HTML, Subject, From, To }
```

Combining the `query=to:` filter with the `.find` on the recipient is what keeps parallel
runs deterministic. Grabbing `messages[0]` / `messages.at(-1)` (whatever's newest) with no
recipient filter defeats that. The full helper lives in
`references/mailpit-playwright.md`.

---

## Extracting OTPs and links

Match against the **email body**, anchored, and guard against a null result:

```ts
const otp = body.match(/\b(\d{6})\b/)?.[1];
expect(otp, 'no OTP in email body').toBeTruthy();   // throw / fail if null

const link = body.match(/https?:\/\/\S*(?:verify|confirm|reset|token=)\S*/i)?.[0];
if (!link) throw new Error('no verification link in email body');
```

Don't slice by position (`body.split(' ')[3]`, `substring(0, 6)`, `indexOf('code')`) —
those snap the moment a template wording changes. Don't read the live page's `innerText`
when the data actually lives in the email body. If a 6-digit code might collide with some
other number in the message, anchor on a label instead: `body.match(/code[:\s]+(\d{6})/i)`.
Hosted providers often expose structured `message.html.links` / `message.html.codes` —
prefer those over raw regex when they're available. See
`references/mailpit-playwright.md`.

---

## Deterministic addresses (parallel isolation)

The classic parallel-flake scenario: two signups fire at once, both tests poll for "the
latest signup email," and they end up reading each other's message. In order of
preference, fix it with:

- **A unique address per test** — plus-addressing / sub-addressing, e.g.
  `user+${randomUUID()}@example.com` or `signup.${Date.now()}@...`. Most mail providers
  route `user+anything@` back to `user@`, so a single real mailbox can generate unlimited
  distinct recipients.
- **Filtering every read by recipient** — `sentTo` on Mailosaur, or a `query=to:` search
  plus `.find` on Mailpit. Never grab the newest message overall.
- **A dedicated inbox per test** — MailSlurp's `createInbox()` hands each test its own
  inbox; Mailosaur gives each test a unique address on your server's domain.

Purging the inbox between tests is **not** enough once tests run concurrently — two tests
firing at the same moment still collide. The real fix is a unique address combined with a
recipient filter. See `references/hosted-inboxes.md`.

---

## Asserting subject / from / headers / links

Once the message is captured, check its content:

- `expect(message.subject).toBe('Welcome to Example')` — catches a wrong template.
- `expect(message.from?.[0].email).toBe('hello@example.com')` — catches a misconfigured
  sender / reply-to.
- Headers such as `List-Unsubscribe` or custom `X-` headers, when your product sets them.
- Links resolve to the expected domain:
  `expect(links.every((l) => new URL(l.href).hostname.endsWith('staging.example.com'))).toBe(true)`.

A Mailosaur example that checks `subject`, `from`, and link domain together is in
`references/hosted-inboxes.md`.

---

## Deliverability: SPF / DKIM / DMARC

Run this as its **own non-blocking suite**, apart from functional flow tests. SPF, DKIM,
and DMARC `pass`/`fail` results (and alignment) come from a real receiving server
authenticating your sending domain — they are **not** substrings you'll find in the body,
so never reach for `body.includes('spf')` or `body.match(/dkim/)`. Also keep in mind that
**Mailpit doesn't check SPF/DKIM/DMARC alignment at all** — it only runs basic
SpamAssassin-style content scoring, since nothing traveled over real DNS. Getting real
alignment results requires an actual hosted send-and-receive path (a **Mailosaur**
deliverability report, or a one-off run through mail-tester.com). Tag this suite
`@deliverability`, run it as a non-required CI job (`continue-on-error`), and never fold a
deliverability assertion into the OTP / reset flow test. See `references/deliverability.md`.

---

## Flaky email in CI

The symptom: it passes on your machine, then CI complains the email "hasn't arrived yet."
Check for all four root causes below — bumping the sleep duration is not a diagnosis:

1. **A fixed sleep in place of polling.** `waitForTimeout` or any arbitrary delay is
   racing the email's arrival. Swap it for `expect.poll` / `.toPass` / a built-in `waitFor`.
2. **Too short a timeout.** Mail delivery in CI tends to be slower than local. Once you're
   polling, lengthen the poll `timeout` (say, 30–60s) rather than reaching for a longer
   blind sleep.
3. **Missing recipient filter.** Reading whatever message is newest overall can surface
   another test's mail under parallel execution. Filter by `sentTo` / `to:` and give each
   test a unique address.
4. **Leftover messages from an earlier run.** A stale matching email can satisfy the
   assertion before the new one even arrives. Clear the inbox during global setup, and/or
   make each run's address unique so old mail can't match.

Re-running the whole job, quarantining the test, or setting a blanket 30s sleep all mask
the symptom while leaving the underlying race intact.

---

## Anti-Patterns

### 1. Fixed sleep before reading the inbox
`page.waitForTimeout(5000)` / `setTimeout` / `sleep()` then read. Too short flakes, too long
wastes minutes. Poll with `expect.poll` against `/api/v1/messages` (or a built-in waiter).

### 2. Recommending a dead capture tool
MailHog is archived (2020). Papercut / smtp4dev are weaker for automation. Use Mailpit.

### 3. Checking the database instead of the email
A DB row proves the write happened, not that the email was sent, addressed, and linkable.
Read the actual captured message.

### 4. Shortcutting past the email
Calling the reset endpoint directly or hardcoding a token skips templating, link
generation, and token signing. Capture the email, extract the link, `page.goto` it.

### 5. Brittle index-based extraction
`body.split(' ')[3]`, `substring(0, 6)`, `indexOf('code')`. Use an anchored `\d{6}` regex
with a null guard. And extract from the email body, not the live page's `innerText`.

### 6. Newest-message-overall with no recipient filter
`messages[0]` / `messages.at(-1)` collide under parallelism. Filter by recipient and use a
unique per-test address; "delete all messages between tests" alone does not fix it.

### 7. Asserting only that an email exists
No `subject` / `from` / link checks misses wrong-template and wrong-link bugs. Assert
content.

### 8. Regexing SPF/DKIM/DMARC out of the body, or trusting Mailpit for it
Auth results come from a real receiving server, not body text; Mailpit only does spam
scoring. Use Mailosaur's deliverability report, in a separate non-blocking suite.

### 9. IMAP libraries against a real mailbox
`imap-simple` / `node-imap` / `imapflow` reinvent polling and lose isolation. Use
MailSlurp `createInbox` + `waitForLatestEmail`, one inbox per test.

### 10. Ethereal in CI, or a paid service for a local preview
Ethereal delivers nothing — it's preview-only (`createTestAccount` + `getTestMessageUrl`).
Don't assert on it in CI; equally, don't spin up a paid hosted service just to eyeball a
template locally.

---

## Verification

Confirm the suite genuinely captures and asserts, cheapest check first:

- **Capture is reachable:** `curl -s localhost:8025/api/v1/messages | jq '.total'` returns
  a number (Mailpit is up and its API answers). For a hosted inbox, a one-line
  `messages.get` / `createInbox` smoke script should complete without an auth error.
- **No blind sleeps remain:** `grep -rE 'waitForTimeout|sleep\(|setTimeout' tests/` over the
  email specs comes back empty.
- **The flow is real, not just green:** run the signup/reset spec, then temporarily break
  the template subject and confirm the test now fails — if it still passes, content isn't
  actually being asserted.
- **Determinism survives concurrency:** run the email specs with `--workers=4
  --repeat-each=3`; a clean run confirms the per-recipient filter holds under parallelism.
- **Deliverability stays isolated:** `--grep @deliverability` selects only the
  authentication suite, and its CI job is marked `continue-on-error` / non-required.

## Done When

- The capture tool was chosen using the decision tree and is recorded in
  `.agents/qa-project-context.md` (Mailpit for local/CI, a hosted inbox only where a real
  address is needed).
- No email test contains `waitForTimeout` / `sleep` / `setTimeout` before reading the
  inbox — `grep -rE 'waitForTimeout|sleep\(|setTimeout' tests/` over the email specs is
  clean; arrival is awaited via `expect.poll` / `.toPass` / a built-in waiter.
- Each email test uses a unique recipient (plus-address or per-test inbox) and filters
  reads by that recipient — no `messages[0]` / `messages.at(-1)` without a filter.
- OTP/link extraction uses an anchored regex (`\d{6}`, `https?://...`) with a null guard
  that fails the test on no match.
- At least the signup-confirmation (or reset / magic-link) flow has a green E2E test that
  captures the real email and completes the flow through `page.goto(link)`.
- Content assertions on `subject`, `from`, and link domain exist — not just existence.
- Deliverability (SPF/DKIM/DMARC) tests, if in scope, live in a separate `@deliverability`
  suite that is non-blocking in CI.

---

## Related Skills

- **playwright-automation** — the browser-driving half of every email flow: forms,
  navigation, fixtures, and the poll helpers. This skill adds the inbox side.
- **api-testing** — go there to test the email provider's API directly or to test that your
  app *sends* mail; this skill is about *receiving and asserting* in an E2E flow.
- **test-data-management** — generating unique per-test addresses, factories, and seeded
  users that feed the recipient strategy here.
- **qa-project-context** — records the chosen capture tool, SMTP target, and credentials so
  every email test shares one configuration.

---

## Reference Files (in `references/`)

- **mailpit-playwright.md** — docker-compose, the `expect.poll` Mailpit helper, OTP/link
  extraction utilities, and full password-reset / signup / OTP / magic-link E2E tests.
- **hosted-inboxes.md** — Mailosaur (`messages.get` auto-wait, real addresses, structured
  links/codes), MailSlurp (`createInbox` + `waitForLatestEmail`, per-test inbox), and
  Ethereal (local preview via `createTestAccount` + `getTestMessageUrl`).
- **deliverability.md** — SPF/DKIM/DMARC as a separate non-blocking suite, why body-regex
  and Mailpit don't validate auth, and the Mailosaur deliverability assertion.
</content>
