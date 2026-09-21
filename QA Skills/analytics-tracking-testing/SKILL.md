---
name: analytics-tracking-testing
description: >-
  Validate that analytics and marketing tracking fire CORRECTLY: GA4/GTM dataLayer events,
  Meta/TikTok/LinkedIn pixels, and ad-tech tags. Covers building a tracking plan as the
  contract, intercepting collect-endpoint beacons and dataLayer.push in Playwright, asserting
  event name + params + values + timing + de-duplication, Consent Mode v2 gating, CI regression
  gating, and news-media events (article-view, scroll-depth, paywall). Use when: "test analytics
  tracking," "GA4 event test," "verify the pixel fires," "dataLayer test," "tracking plan,"
  "Meta Pixel dedup," "scroll-depth tracking test," "gate tracking in CI."
  Not for: whether tracking is ALLOWED to fire under consent law (GDPR/CMP) — that is
  compliance-testing; this skill checks the data is CORRECT. SEO meta tags / structured data —
  out of scope.
  Related: compliance-testing, playwright-automation, api-testing, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "1.0"
  category: specialized
---

<objective>
A tracking setup can look healthy in GA4 DebugView and still be broken: an event stops firing after a refactor, the wrong currency ships, or a purchase gets counted twice. Neither `window.dataLayer` inspection nor a `toBeVisible()` check on a button proves anything real — the network beacon carrying the event might never leave the browser. The job here is to intercept the actual request (`google-analytics.com/g/collect`, `facebook.com/tr`, `analytics.tiktok.com`, `px.ads.linkedin.com`), pull the event name and parameters out of it, and check them against a tracking plan defined as a typed contract — and then wire that contract into CI so a silently dropped event breaks the build instead of slipping through.
</objective>

## Quick Route

| Situation | Go to |
|-----------|-------|
| Assert one GA4 event fired with correct params | [Intercepting GA4 beacons](#intercepting-ga4-beacons) |
| Treat the tracking plan as a validated contract | [The Tracking Plan Is the Contract](#the-tracking-plan-is-the-contract) |
| Verify dataLayer.push shape (not the beacon) | [Asserting dataLayer.push](#asserting-datalayerpush) |
| Pixel + server CAPI deduplication (event_id) | [Pixels and Server-Side Deduplication](#pixels-and-server-side-deduplication) |
| Events must/mustn't fire by consent state | [Consent Mode v2 Gating](#consent-mode-v2-gating) |
| Capture every pixel in one reusable fixture | `references/capture-fixture.md` |
| News-media: article-view, scroll-depth, paywall | [News-Media Events](#news-media-events) |
| Fail the build on a tracking regression | [Regression-Gating in CI](#regression-gating-in-ci) |
| Hundreds of events, many domains, small team | [Buy vs Build](#buy-vs-build) |

## Discovery Questions

Start by checking `.agents/qa-project-context.md` in the project root; skip whatever it already covers (stack, tag manager, consent platform, target environments).

- **What destinations are actually live?** GA4 (`/g/collect`), Meta Pixel (`facebook.com/tr`), TikTok (`analytics.tiktok.com`), LinkedIn (`px.ads.linkedin.com`), and any ad-tech tags — each speaks a different endpoint grammar, so whatever capture helper you build needs to know all of them.
- **Is it GTM, or a hardcoded gtag call?** With GTM, the real signal flows through `window.dataLayer.push` first and GTM turns that into the beacon afterward. That means you can — and often should — assert both layers: the push (the input contract) and the beacon (the output contract). They are separate tests, not interchangeable ones.
- **Does a tracking plan already exist?** If it doesn't, write one before doing anything else — it's the contract every other check depends on. Without it there's no objective definition of pass or fail.
- **What's the consent platform and its default state?** Consent Mode v2 determines which beacons are even legal to fire before the user consents. You'll need the CMP's accept/reject selectors to drive that part of the test.
- **Is there client + server (CAPI) dedup to worry about?** When a purchase fires both a client-side Pixel event and a server Conversions API call, they need matching `event_id` values or the conversion gets counted twice. That match — not "did `fbq` run" — is the thing worth testing.
- **Is this a news/publisher surface?** Article pages bring their own event set — article-view, scroll-depth thresholds (25/50/75/100), paywall-meter hits — that a typical e-commerce tracking plan won't include.

---

## Core Principles

1. **The beacon is the source of truth — not the DOM, not `dataLayer` alone.** A DOM update from a button click, or a `dataLayer.push` GTM quietly ignores, leaves nothing behind in GA4. The only evidence an event actually went out is the outbound request to the collect endpoint. Assert against that request's URL parameters. Reading `window.dataLayer` through `page.evaluate` only tells you a push occurred locally — not that anything reached the network.

2. **Treat the tracking plan as a typed contract, not documentation.** Every event the app is expected to fire should live in an external schema — JSON, YAML, or a TS interface — listing its required params and their types. Tests check captured events against that schema and report back `missing` fields and type `violations`. Hardcoding one expected value inline tells you nothing about the other params in the payload, and breaks the moment the plan changes.

3. **For purchases, deduplication is the property that actually matters.** Confirming `fbevents.js` loaded, or that `fbq('track','Purchase')` executed, says nothing about whether the conversion got double-counted. What matters: the client-side Pixel and the server-side CAPI call carry the *same* `event_id`/`eventID`, so Meta merges them into a single conversion.

4. **Consent state changes the output — test it as an input, not an afterthought.** The same page emits different beacons depending on consent: before consent, expect no beacon (or a cookieless ping at most); after acceptance, expect the full beacon. And the default for all four Consent Mode v2 signals must be `denied` — a `granted` default is both a compliance issue and something that would make your gating test meaningless.

5. **Trigger real actions, then wait on the network — never on a timer.** Scroll-depth tracking should be driven by genuine scroll actions (`mouse.wheel`, `scrollIntoView`, `evaluate(scrollTo)`), and the beacon should be awaited with `waitForRequest`, never `waitForTimeout`. A fixed sleep is both flaky and liable to hide exactly the kind of timing bug you're trying to catch.

6. **If a check can't fail the build, it isn't testing anything.** "Look at GA4 DebugView" or "keep an eye on production" will never stop a regression from merging. The contract has to run in CI and return a non-zero exit code the moment an event stops firing or loses a required param.

---

## Intercepting GA4 Beacons

GA4 (via gtag.js or GTM) reports every event as an HTTP request to `https://www.google-analytics.com/g/collect` (region variants such as `region1.google-analytics.com/g/collect` also show up). Everything you need — the event's identity and its data — lives in the URL query string, so the response body is irrelevant.

GA4's `/g/collect` URL grammar, param by param:

| Param | Meaning | Example |
|-------|---------|---------|
| `v=2` | Measurement Protocol version (always 2 for GA4) | `v=2` |
| `tid=G-XXXXXXX` | Measurement ID | `tid=G-ABC123` |
| `en=` | **Event name** | `en=add_to_cart` |
| `ep.<name>=` | Event parameter, **string** type | `ep.currency=USD` |
| `epn.<name>=` | Event parameter, **number** type | `epn.value=49.99` |
| `gcs=` / `gcd=` | Consent state (see the Consent Mode v2 section) | `gcs=G111` |

That string/number split matters in practice — GA4 auto-types params, so a `price` field lands as `epn.value` (number) while `currency` lands as `ep.currency` (string). Asserting `ep.value` when the real key is `epn.value` fails silently.

Capture the request with `page.waitForRequest` (for one expected event), `page.on('request', ...)` (to collect several), or `page.route` — inspect, then always continue, never `abort`. Pull params from `new URL(request.url()).searchParams`, and assert with `expect(...).toBe(...)` / `toEqual` / `toContain`.

Minimal pattern (a fuller version with a reusable helper is in `references/ga4-interception.md`):

```ts
test('add_to_cart fires with correct params', async ({ page }) => {
  await page.goto('/product/42');
  const [request] = await Promise.all([
    page.waitForRequest(r => r.url().includes('/g/collect') && r.url().includes('en=add_to_cart')),
    page.getByRole('button', { name: 'Add to cart' }).click(),
  ]);
  const params = new URL(request.url()).searchParams;
  expect(params.get('v')).toBe('2');
  expect(params.get('tid')).toContain('G-');
  expect(params.get('en')).toBe('add_to_cart');
  expect(params.get('ep.currency')).toBe('USD');
  expect(Number(params.get('epn.value'))).toBe(49.99);
});
```

Don't fall back on `page.evaluate(() => window.dataLayer)` as your only proof, on `toBeVisible()` for the button, or on `waitForTimeout()` to give the beacon "time to send." `references/ga4-interception.md` covers batched-event parsing (GA4 can pack several events into a single POST body) and region-endpoint variance.

---

## The Tracking Plan Is the Contract

The tracking plan is your source of truth: for every event, its name, its required params, and each param's type. Keep it in a versioned file — `tracking-plan.json`/`.yaml`, or a TS `interface`/`Zod` schema — that both the application code and the test suite import. Tests read the captured event and check it against this plan; they should not hardcode expected values inline.

Validation should produce a structured breakdown, not a plain pass/fail flag: enumerate every `missing` required param and every type `mismatch`/`violation`. Here's a sample plan entry with its validator:

```ts
// tracking-plan.json
{ "add_to_cart": { "required": { "currency": "string", "value": "number", "item_id": "string" } } }

function validateEvent(plan, eventName, params) {
  const spec = plan[eventName];
  const violations = [];
  for (const [name, type] of Object.entries(spec.required)) {
    const raw = params.get(`ep.${name}`) ?? params.get(`epn.${name}`);
    if (raw == null) { violations.push({ param: name, problem: 'missing' }); continue; }
    if (type === 'number' && Number.isNaN(Number(raw))) violations.push({ param: name, problem: 'type', expected: 'number' });
  }
  return violations; // empty array = event satisfies the contract
}
```

Then assert with `expect(validateEvent(plan, 'add_to_cart', params)).toEqual([])`. Checking only the event name while ignoring its params, or hardcoding expected values with no backing plan file, is exactly the shortcut this skill is meant to eliminate. `references/tracking-plan.md` covers the YAML variant, a Zod-typed plan, and a reusable `assertAgainstPlan` matcher.

---

## Asserting dataLayer.push

When what you actually want to check is the GTM **input** — "does the right object get pushed to `dataLayer` on page load?" — assert the push itself rather than the resulting GA4 beacon. This flips the usual direction: here the push *is* the thing under test.

Capture pushes by wrapping `window.dataLayer.push` inside `addInitScript`, installed *before navigation*, so every push from page load onward gets recorded, then pull the recorded array back with `page.evaluate`. Two things not to do: don't `page.route` to mock the dataLayer (that replaces the very thing you're testing), and don't check the GA4 network beacon instead (that's a different, downstream contract).

For ecommerce events, check the full nested shape rather than stopping at the event name — the `ecommerce.items` array and each item's `item_id`, `price`, and `currency`:

```ts
await page.addInitScript(() => {
  window.dataLayer = window.dataLayer || [];
  const orig = window.dataLayer.push.bind(window.dataLayer);
  window.__pushes = [];
  window.dataLayer.push = (...args) => { window.__pushes.push(...args); return orig(...args); };
});
await page.goto('/product/42');
const pushes = await page.evaluate(() => window.__pushes);
const viewItem = pushes.find(p => p.event === 'view_item');
expect(viewItem.ecommerce.items[0]).toMatchObject({ item_id: 'SKU-42', price: 49.99, currency: 'USD' });
```

`find`/`filter`/`some` over the recorded pushes will locate the event you're after. A complete helper is in `references/datalayer-capture.md`.

---

## Pixels and Server-Side Deduplication

Marketing pixels send their own separate beacons. Endpoints worth intercepting:

| Destination | Endpoint | Event param | Dedup key |
|-------------|----------|-------------|-----------|
| Meta Pixel | `facebook.com/tr` (also `/tr?`) | `ev=PageView`, `ev=Purchase` | `eid` / `event_id` |
| TikTok | `analytics.tiktok.com` | event in body/params | `event_id` |
| LinkedIn | `px.ads.linkedin.com` | conversion id | — |

For Meta, checking that `connect.facebook.net/en_US/fbevents.js` loaded, or that `fbq('track','Purchase')` was called, only tells you the library ran — it says nothing about correctness. The real correctness property for a Purchase event that fires both client-side (Pixel) and server-side (Conversions API / CAPI) is **deduplication**: both sides need to carry the *same* `event_id` so Meta collapses them into a single conversion instead of counting twice.

To test it: capture the browser's `facebook.com/tr` beacon for `ev=Purchase`, pull out its `event_id`, and check it matches the `event_id` your server sent to CAPI (from a captured/mocked server call, or a known fixture value). Skeleton:

```ts
const [pixel] = await Promise.all([
  page.waitForRequest(r => r.url().includes('facebook.com/tr') && r.url().includes('ev=Purchase')),
  completeCheckout(page),
]);
const clientEventId = new URL(pixel.url()).searchParams.get('eid'); // event_id on the wire
expect(clientEventId).toBe(serverCapiEventId); // deduplicates against the server CAPI event
```

`references/pixels-and-dedup.md` covers parsing TikTok/LinkedIn payloads and capturing the server-side CAPI call.

---

## Consent Mode v2 Gating

Consent Mode v2's four-signal model is now mandatory. Since the **June 15 2026** change, Google only honors the CMP-sent consent signal — so anything still built around the old two-signal model is out of date. Test both consent states.

The four signals, all of which must default to `denied`:

| Signal | Governs |
|--------|---------|
| `ad_storage` | Advertising cookies |
| `analytics_storage` | Analytics cookies |
| `ad_user_data` | Sending user data to Google for ads |
| `ad_personalization` | Personalized ads / remarketing |

A `granted` default is a bug on its own; leaving out `ad_user_data` and `ad_personalization` (the two signals v2 added) means you're still running the outdated two-signal model, which is also wrong.

**Before consent:** either no full beacon should fire, or only a *cookieless consent ping*. Seed the denied state with `addInitScript` (`gtag('consent', 'default', {...})`) before any page script runs, then check that no `/g/collect` request fires — or that the one request that does fire carries a denied consent state.

**After accept:** clicking the CMP's accept button should trigger the full beacon.

Consent state is encoded directly on the beacon URL:

- `gcs=` — covers `ad_storage` + `analytics_storage` only. `G100` means both denied, `G111` both granted, `G110`/`G101` partial. Before consent, expect `gcs=G100`.
- `gcd=` — encodes all four signals as a string starting with `11...`; present on every hit sent to Google.

Check the denied default and `gcs=`/`gcd=` on the pre-consent beacon, and the granted state afterward. A full test with `addInitScript`-based consent seeding and the CMP accept click is in `references/consent-mode.md`.

> Whether the law *permits* a given beacon under a specific consent state is `compliance-testing` territory. What this skill checks is that when a beacon does fire, its data and consent params are correct.

---

## News-Media Events

Publisher and news sites carry a tracking surface that generic e-commerce plans don't cover. Make sure all three are handled:

- **article_view** (or `article-view`) fired on article load — check that the beacon fires exactly once, carrying article metadata (id, section, author).
- **scroll-depth** thresholds at 25 / 50 / 75 / 100 percent — one event per bucket, triggered by *actual scrolling*.
- **paywall / meter** — a `paywall_hit` (or meter) event when the free-article allowance runs out.

Trigger scrolling with real actions — `mouse.wheel`, `element.scrollIntoView`, or `page.evaluate(() => window.scrollTo(...))` / `scrollBy` — and wait for the beacon (`waitForRequest`, or your captured-events list) rather than `waitForTimeout`. Sleeping through scroll interactions both introduces flakiness and hides threshold-timing bugs.

```ts
const buckets = [25, 50, 75, 100];
for (const pct of buckets) {
  const [req] = await Promise.all([
    page.waitForRequest(r => r.url().includes('/g/collect') && r.url().includes('en=scroll')),
    page.evaluate(p => window.scrollTo(0, document.body.scrollHeight * (p / 100)), pct),
  ]);
  expect(new URL(req.url()).searchParams.get('epn.percent_scrolled')).toBe(String(pct));
}
```

A fuller suite — article_view metadata, all four de-duplicated scroll buckets, and the paywall-meter event — is in `references/news-media.md`.

---

## Multi-Pixel Capture Fixture

Avoid reimplementing beacon capture in every test file. Instead, build one reusable Playwright fixture (`test.extend`) that listens via `page.on('request', ...)`, matches every destination endpoint (GA4 `/g/collect`, `facebook.com/tr`, `analytics.tiktok.com`, `px.ads.linkedin.com`), parses each request's `new URL(...).searchParams` and `postData()`, and pushes a normalized `{ destination, eventName, params }` record onto a shared `collected` array your tests assert against.

Key trap to avoid: a capture helper must **observe** traffic, not intercept it — use `page.on('request')` (or `page.route` followed by `route.continue()`), and never `page.route(...).abort()`, since that blocks the very beacons you're trying to see. It also needs to cover pixels, not just GA4. The complete fixture is in `references/capture-fixture.md`.

---

## Regression-Gating in CI

The gate compares captured events against the tracking-plan baseline and **fails the build** (non-zero exit) whenever an event that used to fire stops firing, or a required param disappears after a release. Set it up as a Playwright project that walks through the user journeys, captures every beacon through the fixture, and validates each against the plan. Any `missing` or dropped event makes an `expect` fail, which makes Playwright exit non-zero, which turns the CI job (GitHub Actions or otherwise) red.

Avoid a gate that amounts to "check GA4 DebugView manually," "only run this against production traffic," or "warn but let it pass anyway" — none of those actually block a regression. The baseline-diff run belongs in PR CI, before code merges. See `references/ci-gating.md` for the workflow YAML, the baseline-diff script, and how to surface missing-param failures in the job summary.

---

## Buy vs Build

DIY Playwright interception makes sense for a bounded set of events across a handful of critical journeys, gated pre-merge in CI. It stops scaling well once you're dealing with hundreds of events across many domains, a small team, and a need for *continuous production/drift monitoring* — catching a tag a marketer breaks in GTM at 2am, which a pre-merge gate will never see.

| Dimension | Build (Playwright) | Buy |
|-----------|-------------------|-----|
| Few events, key journeys, pre-merge gate | Best fit | Overkill |
| Hundreds of events, many domains | Maintenance crushes you | Buy |
| Continuous 24/7 production drift monitoring | Out of scope for CI | Buy |
| Small team, high coverage demand | Build cost too high | Buy |

Worth naming among the current paid options:

- **Trackingplan** — always-on/continuous monitoring of live traffic across web, mobile, and server-side; its strength is real-time drift detection rather than scheduled checks.
- **ObservePoint** — scheduled scans/audits of journeys against a tracking plan; a mature choice for periodic governance.

Don't lean on Segment Protocols as your *only* validation layer (it governs data moving through Segment, not arbitrary client beacons), and don't treat Google Tag Assistant as a CI gate — it's an interactive debugging tool, not an automated pass/fail mechanism. The decision comes down to scale, domain count, maintenance burden, and whether you need continuous monitoring — those are the axes where doing it yourself stops paying off.

---

## Anti-Patterns

### 1. Asserting `window.dataLayer` (or the DOM) instead of the beacon
`page.evaluate(() => window.dataLayer)` only proves a push happened, not that GA4 sent anything; `toBeVisible()` proves nothing about tracking at all. Intercept the `/g/collect` request and assert its `en=` and `ep.`/`epn.` params. (Exception: when the push itself IS the contract — see dataLayer.push — but don't then substitute the GA4 beacon for it.)

### 2. `waitForTimeout` to "wait for the event to fire"
A fixed sleep is flaky and masks timing bugs. Wait on the request instead: `page.waitForRequest(r => r.url().includes('/g/collect'))`.

### 3. Asserting only the event name
Name-only checks pass even when currency, value, and item_id are wrong. Validate every required param and its type against the tracking plan.

### 4. Hardcoding expected values inline with no plan file
Without a source of truth, nothing catches a param rename across the suite. Keep the plan external and validate against it.

### 5. Load/count checks for pixels (`fbevents.js` loaded, `fbq` ran)
Neither one proves the conversion is correct or deduplicated. For Purchase events, check that client and server `event_id` match.

### 6. Two-signal Consent Mode, or a `granted` default
Skipping `ad_user_data` and `ad_personalization` means you're stuck on the pre-2026 model. Default all four signals to `denied` and assert `gcs=`/`gcd=`.

### 7. `page.route(...).abort()` inside a capture helper
Aborting blocks the beacons you're trying to observe. Use `page.on('request')` (or `route.continue()`).

### 8. A "gate" that can't fail the build
GA4 DebugView, production-only monitoring, or warn-but-pass none of them stop a regression. Make CI exit non-zero on a dropped event or missing required param.

---

## Verification

Start with the smallest possible check — confirm the suite actually catches a regression rather than just trusting a green run:

- **One event, one beacon:** `npx playwright test -g add_to_cart` passes, and its trace (`--trace on`) shows the captured `/g/collect` request with `en=add_to_cart`. A green test with no matching request in the trace means the assertion is checking the wrong thing.
- **The gate can actually fail:** rename a required param on a branch (e.g. `value` → `amount`) and re-run the CI project — the build should exit non-zero with a `missing`/violation message. If it still passes, the gate isn't doing anything.
- **Consent default is denied:** with the denied seed applied and no accept click, every captured hit shows `gcs=G100` (or no full beacon at all); after accept, `gcs=G111`. Seeing `G111` before consent means the default is wrongly set to `granted`.
- **Dedup holds:** the client-side `eid` from `facebook.com/tr?ev=Purchase` matches the server CAPI `event_id` for the same order. If they differ, Meta will double-count that conversion.

## Done When

- Each tracked event has a test that intercepts the real collect-endpoint beacon (`/g/collect`, `facebook.com/tr`, etc.) and parses `en=`/`ev=` plus params from `searchParams`/`postData` — no DOM-only or dataLayer-only assertions.
- A versioned tracking plan file exists (JSON/YAML/TS) with required params and types; tests validate captured events against it and report `missing`/type violations, not just the event name.
- Purchase (or any client+server event) has a deduplication assertion: client beacon `event_id` equals the server CAPI `event_id`.
- A Consent Mode v2 test asserts all four signals default to `denied`, no full beacon fires before consent (or only a cookieless ping), the full beacon fires after accept, and `gcs=`/`gcd=` carry the expected consent state.
- A reusable capture fixture (`test.extend`) collects GA4 + Meta + TikTok + LinkedIn beacons; no test re-implements capture and no capture helper calls `route.abort()`.
- News-media surfaces (if present) cover article_view, scroll-depth at 25/50/75/100 driven by real scroll actions, and a paywall/meter event — all using `waitForRequest`, no `waitForTimeout`.
- A CI job runs the suite, diffs captured events against the tracking-plan baseline, and exits non-zero on a dropped event or missing required param — verified by a deliberately-broken tag turning the build red.

## Related Skills

- **compliance-testing** — Whether a beacon is *allowed* to fire under GDPR/CMP consent law, cookie-consent UI, and data-subject rights. This skill assumes the beacon is permitted and checks its data is correct; go there for the legality question.
- **playwright-automation** — Page Object Model, fixtures, config, and the general E2E patterns this skill builds its interception on.
- **api-testing** — Validating the server-side Conversions API / Measurement Protocol calls directly (request body, auth, response) when you need to assert the server half of deduplication.
- **qa-project-context** — Stack, tag manager, consent platform, and target environments that this skill's discovery questions read first.

## Reference Files (in `references/`)

- **ga4-interception.md** — Full GA4 `/g/collect` interception helper, batched-event POST-body parsing, region-endpoint handling.
- **tracking-plan.md** — JSON and YAML plan forms, a Zod-typed contract, and the reusable `assertAgainstPlan` matcher.
- **datalayer-capture.md** — `addInitScript` dataLayer.push wrapper and ecommerce `items[]` shape assertions.
- **pixels-and-dedup.md** — Meta/TikTok/LinkedIn payload parsing and client-vs-server CAPI `event_id` dedup capture.
- **consent-mode.md** — Consent Mode v2 default-denied seeding, CMP accept-click flow, and `gcs=`/`gcd=` assertions.
- **news-media.md** — article_view, de-duplicated 25/50/75/100 scroll buckets, and paywall-meter event tests.
- **capture-fixture.md** — The reusable multi-pixel `test.extend` capture fixture.
- **ci-gating.md** — GitHub Actions workflow, baseline-diff script, and surfacing missing-param failures.
