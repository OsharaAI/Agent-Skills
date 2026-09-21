---
name: compliance-testing
description: >-
  Validate regulatory compliance across GDPR/CMP consent flows, Google Consent Mode
  v2, Global Privacy Control (GPC), CCPA/US state opt-out mechanisms, EU AI Act
  Article 50 transparency, Better Ads Standards, and cookie-inventory audits. Includes
  automated testing of consent flows, blocking of third-party scripts prior to
  consent, and detection of cookie drift.
  Use when: "GDPR test," "compliance," "CMP test," "cookie consent," "consent mode,"
  "CCPA," "GPC," "AI Act," "Better Ads," "privacy banner."
  Not for: WCAG/axe-core test authoring — use accessibility-testing. Not for: OWASP/vuln
  scanning — use security-testing. Not for: evaluating your LLM feature's quality or
  safety — use ai-system-testing.
  Related: accessibility-testing, security-testing, ai-system-testing, ci-cd-integration.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: process
---

<objective>
Compliance work has no partial-credit tier: an analytics cookie that fires a split second before consent, or a "Reject all" control disguised as a barely-visible grey link, is still a violation no matter how well everything else in the flow was built. Manual reviews run on a quarterly cadence simply cannot keep pace with a regression a developer introduces on an ordinary Tuesday. The purpose of this skill is to automate the technical side of that verification — consent state, script blocking, cookie attributes, GPC signals, Consent Mode v2, AI Act disclosures — so that any drift in configuration breaks the CI build well before it ever surfaces as a regulator's complaint.
</objective>

## Questions to Ask First

Before asking anything, check whether `.agents/qa-project-context.md` already exists at the project root — it should already document the applicable regulations, CMP details, ad networks, and geographic scope, so there's no need to re-ask what it already covers. If the file is missing, suggest generating one with the `qa-project-context` skill.

### Which regulations are in scope
- **Which privacy/platform regulations govern this product?** This one answer shapes the entire test matrix.
  - **EU:** GDPR, the ePrivacy Directive (cookies), the Digital Services Act (DSA, in force since 17 Feb 2024), and the EU AI Act (prohibitions and AI-literacy obligations have been live since 2 Feb 2025; GPAI duties and penalties since 2 Aug 2025; Article 50 transparency lands 2 Aug 2026 — high-risk obligations, however, have been pushed back, as detailed further down).
  - **US:** CCPA/CPRA, plus comprehensive privacy statutes now in effect across roughly 20 states (Texas TDPSA, Indiana CDPA effective 1 Jan 2026, Delaware DPDPA, Nebraska NDPA, Minnesota CDPA, Rhode Island DTPPA, among others). Most of these mandate honoring Global Privacy Control (`Sec-GPC: 1`).
  - **UK:** UK GDPR/DPA, PECR (cookie rules), the Online Safety Act 2023, and the Data Use and Access Act (DUAA).
  - **Elsewhere:** Brazil's LGPD, Canada's PIPEDA, South Africa's POPIA.
- **What's the legal basis for processing data?** Consent (opt-in), legitimate interest, or contractual necessity — this determines whether explicit consent must precede any processing whatsoever.
- **Is there a DPO or legal team in the loop?** Legal interpretation is their responsibility; this skill's role is narrowly to confirm the technical build matches what they've decided.

### How consent is managed
- **Which CMP is deployed?** OneTrust, Cookiebot, Didomi, Usercentrics, Iubenda, Sourcepoint, Axeptio, or a homegrown solution? Whatever the answer, it determines the consent storage format, the available API surface, and the integration approach. **Any ad serving in the EEA or UK requires a Google-certified CMP running Consent Mode v2** — running an uncertified CMP means Google ad serving gets blocked entirely. **Starting 28 Feb 2026, new TC strings must comply with TCF v2.3**, or Google's demand side will treat that traffic as unconsented and downgrade it to Limited Ads.
- **What consent categories has the site defined?** Typically: Strictly Necessary (always on), Analytics/Performance, Functional/Preferences, and Marketing/Targeting.
- **How does consent state propagate to third-party scripts?** Through IAB TCF v2 (`__tcfapi`), a custom data layer, or a direct call to the CMP's API?

### Advertising and accessibility considerations
- **Which ad formats and networks are in play?** Google Ads, Meta, programmatic buys; display, video, interstitial placements. The Coalition for Better Ads decides which formats trigger Chrome's ad-filtering engine.
- **Are there accessibility obligations to satisfy (ADA, EAA, Section 508)?** These are genuine compliance requirements, but the test-writing itself belongs to `accessibility-testing` — here we only outline the legal landscape (see the table further down).

## Core Principles

### 1. "Mostly compliant" isn't a real category
A cookie set before consent is a violation, no exceptions. A banner that can't be dismissed without hitting "accept" is a violation, no exceptions. The standard is exact compliance, not "close enough."

### 2. Automate what's technical; put legal review on a recurring schedule
Automatable territory: cookies firing pre-consent, scripts loading without consent, banner mechanics, cookie attribute correctness, consent persistence, GPC handling, Consent Mode signaling. What still needs a human touch: the actual *wording* of the privacy policy and documentation of cross-border transfers. A passing automated suite is never a substitute for legal sign-off on language.

### 3. Bugs hide in the "unhappy" consent states
Most violations cluster around "no interaction yet," "rejected," and "withdrawn" — rarely around "accepted everything." A suite that only exercises the fully-accepted path tells you almost nothing useful.

### 4. Verify behavior, not the CMP's self-reported state
CMPs, like any software, ship with bugs — their UI proves nothing on its own. Confirm the real outcome instead: did the cookie actually get set, did the script actually load, did the GPC opt-out actually take effect. Treat the CMP as just an implementation detail behind the behavior under test.

### 5. Layer the checks and drive them from data
Verify compliance across multiple layers simultaneously — CMP configuration, network traffic, cookie state, client-side signals. Base the suite on a typed inventory and a domain list, so adding a category or adjusting a threshold is a data edit, not a rewrite. Regulations change often enough that keeping the suite current needs to stay cheap.

## Testing GDPR / CMP Flows with Playwright

Consent-flow compliance breaks down into a set of checks that fail independently of one another. Runnable implementations for each live in `references/gdpr-cmp-tests.md`.

- **Banner mechanics and dark-pattern detection** — the banner must show on first visit; accept and reject controls need equal visual weight (reject can't be relegated to a tiny afterthought link); a privacy-policy link must be present.
- **Cookie state across the before/after boundary** — the single most important check: no non-essential cookies before consent, analytics cookies appearing only once consent is granted, and nothing non-essential surviving a rejection. Keep the `isStrictlyNecessary`/`isAnalyticsCookie` classifiers in sync with the inventory.
- **Persistence and withdrawal** — consent state has to survive page navigation, and users need a way to withdraw consent from privacy settings, with the withdrawal actually clearing the affected cookies.
- **Blocking third-party scripts pre-consent** — tracking scripts (`google-analytics.com`, `googletagmanager.com`, `facebook.net`, `analytics.tiktok.com`, `bat.bing.com`, etc.) must stay dormant until consent is given, then load once it is. This is arguably the highest-stakes check of the set — monitor it via `page.on('request')`.
- **Global Privacy Control (`Sec-GPC: 1`)** — CCPA/CPRA and most active US state laws require this signal to be honored. With the header set, confirm `navigator.globalPrivacyControl === true` (the genuine browser-level signal) and that marketing cookies are absent. **Never** assert an invented global like `window.__cmp.gpcStatus` — it doesn't exist; `__cmp` is a relic of legacy TCF v1, whereas TCF v2 exposes `__tcfapi`.
- **TCF v2 consent state** — every TCF-certified CMP exposes `window.__tcfapi('getTCData', 2, cb)`. Pull purpose and vendor consent directly through that call rather than reverse-engineering private CMP internals; the same response also returns `tcfPolicyVersion`, which doubles as a freshness check for TCF v2.3.
- **Google Consent Mode v2** — mandatory since March 2024 for Google ads served in the EEA/UK. `ad_storage`, `analytics_storage`, `ad_user_data`, and `ad_personalization` must all default to `denied`, flipping to `granted` only after an `update` signal fires post-acceptance. The interception logic assumes gtag's `arguments`-array call shape — see the reference for the object-form fallback.

## EU AI Act Compliance

The Act's rollout happens in phases, and the 2026 timeline has shifted from what was originally scheduled. **The Digital Omnibus (proposed Nov 2025, provisional agreement reached 7 May 2026) delayed the high-risk obligations** — don't build tests against the old 2 Aug 2026 high-risk deadline.

| Obligation | Applies | What to test |
|------------|---------|---------------|
| Prohibitions + AI literacy | 2 Feb 2025 (live) | No Article 5 prohibited practices (social scoring, real-time public biometric ID, manipulative AI). Document which AI features are in scope; gate any prohibited libraries. |
| GPAI obligations + penalties | 2 Aug 2025 (live) | Model cards, training-data summaries, and copyright-policy/disclosure pages must exist. |
| **Article 50 transparency** | **2 Aug 2026** | AI-generated content must be labeled; deepfakes disclosed; users told they're interacting with AI. Test that the disclosure label/watermark actually appears. **This date has not moved.** |
| Machine-readable marking grace period | 2 Dec 2026 | Systems already live before 2 Aug 2026 get until this date to add watermarking/marking (the Omnibus compressed this grace window from six months to three). |
| High-risk (Annex III, use-case) | **2 Dec 2027** | Risk management, data governance, human oversight, transparency UI. **Delayed from the original 2 Aug 2026** by the Omnibus. |
| High-risk (Annex I, product-regulated) | **2 Aug 2028** | Same obligations, embedded within regulated products. **Delayed from 2 Aug 2027.** |

Build the Article 50 disclosure test now, and postpone the high-risk UI tests until the Annex III obligations actually take effect. `references/eu-ai-act-tests.md` contains the Article 50 transparency-disclosure test alongside the Article 5 prohibited-practice gate (biometric library detection). LLM-specific evaluation — hallucination, jailbreak resistance, prompt injection — belongs instead in the `ai-system-testing` skill.

## Better Ads Standards

The Coalition for Better Ads maintains the list of ad formats that trigger Chrome's built-in ad filtering against non-compliant sites.

| Format | Desktop | Mobile | How to test |
|--------|---------|--------|--------------|
| Pop-up ads | Yes | Yes | Look for a modal/overlay appearing within 5s of load without a user action triggering it |
| Auto-playing video with sound | Yes | Yes | Check the live `video.autoplay` / `video.muted` properties, not the HTML attributes |
| Prestitial countdown ads | Yes | Yes | Look for a countdown timer that blocks the content |
| Large sticky ads (>30% viewport) | Yes | Yes | Compare the sticky element's dimensions against the viewport |
| Ad density >30% | No | Yes | Compute total ad area relative to content area |
| Flashing animated ads | No | Yes | Track animation frame rate for more than 3 flashes/second |

For the muted-video check, always read the **live DOM property** (`el.muted`) instead of `getAttribute('muted')`. Player scripts routinely set `video.muted = true` in JavaScript without ever touching the content attribute — an attribute-only check will wrongly flag muted ads as having sound, and will also miss ads that unmute themselves partway through.

**Note that the CBA added two new desktop and two new mobile ad formats on 14 Jan 2025, and Chrome won't start assessing those combined formats before 14 May 2026.** Recheck against the current Better Ads Standards page before that date arrives. `references/better-ads-tests.md` contains the implementations for the auto-playing-video and mobile-ad-density checks.

## Cookie Compliance

Treat a typed cookie inventory as the source of truth, then verify real-world cookies against it along three dimensions:

- **The inventory itself** — a `CookieDefinition[]` recording name, category, purpose, maximum expiry, and required `Secure` / `HttpOnly` / `SameSite` attributes.
- **Attribute checks** — every observed cookie must match its definition's flags and stay within its declared expiry. Normalize a missing `SameSite` value to `None` before comparing, since Playwright sometimes omits or varies it when the server never explicitly set it — skip that normalization and the check either fails spuriously or silently passes when it shouldn't.
- **Drift detection** — any cookie appearing that isn't in the inventory should fail the suite outright (`throw`, not a warning), which keeps the inventory current as new scripts get added.

Full implementations of the typed inventory and both checks live in `references/cookie-compliance.md`.

## Accessibility Compliance — the legal landscape only

Accessibility carries real legal weight across many jurisdictions, but actual test implementation (axe-core, keyboard navigation, screen reader checks) belongs to `accessibility-testing`. This table exists purely to map out the underlying obligations.

| Region | Law | Standard | Enforcement |
|--------|-----|----------|--------------|
| EU | European Accessibility Act (EAA) | EN 301 549 / WCAG 2.1 AA | In force since 28 June 2025; member-state penalties active. WCAG 2.2 alignment expected in the next EN 301 549 revision. |
| USA | ADA | WCAG 2.1 AA (court precedent) | Private lawsuits |
| USA (federal) | Section 508 | WCAG 2.0 AA | Federal procurement requirement |
| Canada (Ontario) | AODA | WCAG 2.0 AA | Fines up to $100K/day |
| UK | Equality Act 2010 | WCAG 2.1 AA (guidance) | Lawsuits |

## Running Compliance Checks on a Schedule

Run the compliance suite on a weekly cadence — not solely at PR time — so configuration drift gets caught as soon as it happens, and retain results as long-lived CI artifacts to back up an audit trail. `references/ci-automation.md` has the scheduled GitHub Actions workflow, set up with 90-day artifact retention.

## Common Mistakes

### Only testing the fully-accepted state
Running the compliance suite solely against the "accepted everything" path. Violations live in the "no interaction" and "rejected" states — cover every state: no interaction, accepted, rejected, partially accepted, and withdrawn.

### Asserting a global that doesn't exist
Checking `window.__cmp.gpcStatus` or some similarly fabricated property to "prove" a GPC opt-out worked. That global simply isn't real. Instead assert `navigator.globalPrivacyControl === true` and confirm marketing cookies are gone; read genuine consent state through `__tcfapi`.

### Checking only the HTML attribute for muted video
Treating `getAttribute('muted') === null` as evidence a video has sound. The content attribute is frequently absent on videos muted purely via JavaScript. Read the live `el.muted` / `el.autoplay` properties instead.

### A cookie inventory nobody maintains
An inventory that drifts out of sync with reality is worse than having none. Add the drift-detection test that `throw`s on any unrecognized cookie, which keeps the inventory honest without manual effort.

### Trusting the CMP's own UI
Exercising only the CMP's interface and treating that as proof of compliance. CMPs have bugs like anything else. Verify the real outcome — cookies actually set, scripts actually loaded, data actually transmitted.

### Relying solely on quarterly manual audits
A once-a-quarter manual check leaves a wide window open — a developer could add a pre-consent analytics script and it might go unnoticed for three months. Automated tests catch it on the very next CI run.

### Treating every region the same
A single global consent model won't hold up: GDPR demands opt-in, CCPA allows opt-out via GPC. Serving both regions means testing both experiences separately.

### Freezing the suite once it's built
Regulations keep shifting — the ePrivacy Regulation, TCF version bumps, AI Act phase-ins, updated CBA standards. Revisit the suite every quarter rather than assuming it stays accurate indefinitely.

## Confirming the Suite Actually Works

Start with the smallest possible check before trusting anything larger:

```bash
npx playwright test --project=chromium --grep @compliance
```

A healthy run shows the unhappy-path tests doing the real gating: "no non-essential cookies before consent" and "no tracking scripts load before consent" need to **pass on a fresh context** (`storageState: undefined`). To confirm the suite would actually catch a real violation, temporarily point it at a page that loads GA before consent is given — the script-blocking test needs to go red in that case. A suite that stays green against a known-bad page isn't testing anything. Then confirm the GPC test correctly reads `navigator.globalPrivacyControl === true` once `Sec-GPC: 1` is set, and that the Consent Mode default-state test reports `denied` across all four signals.

## Definition of Done

- Applicable regulations have been identified for the product and its audience (GDPR, ePrivacy, DSA, EU AI Act, the relevant subset of US state laws, UK OSA/DUAA) and recorded in `.agents/qa-project-context.md`.
- The consent flow is tested at every entry point — first visit, accept, reject, withdrawal, cross-navigation persistence — each as its own distinct passing test.
- Global Privacy Control is honored: with `Sec-GPC: 1` set, `navigator.globalPrivacyControl === true` and marketing cookies are absent.
- Google Consent Mode v2 is verified: default `denied` across `ad_storage` / `analytics_storage` / `ad_user_data` / `ad_personalization`, switching to `granted` via `update` after acceptance (only relevant for sites serving Google ads in the EEA/UK).
- EU AI Act applicability has been assessed: the prohibited-practice gate, GPAI documentation review (where relevant), and the Article 50 transparency disclosure test for any AI-generated content.
- The cookie audit is complete: every cookie is categorized in the typed inventory, and the drift-detection test passes with zero unrecognized cookies.
- No undeclared tracking domains or cookies fire beyond what the privacy policy discloses (this is the automatable half of the check — reviewing the legal language itself is a separate manual sign-off).
- The compliance suite runs green in the weekly CI job, with results retained as artifacts for 90 days.

## Related Skills

- **accessibility-testing** — where the actual WCAG/axe-core/keyboard/screen-reader tests get written. This skill only sketches the accessibility legal landscape; it writes no a11y assertions itself.
- **security-testing** — handles security compliance (OWASP Top 10:2025, dependency and supply-chain scanning), which complements privacy compliance under a different threat model and toolset.
- **ai-system-testing** — owns the eval layer for AI features (hallucination, jailbreak resistance, prompt injection). This skill limits itself to testing the Article 50 *disclosure*, not whether the AI itself behaves correctly.
- **ci-cd-integration** — where the pipeline configuration lives for the scheduled weekly audit and the compliance quality gates.
- **release-readiness** — a failing compliance gate (pre-consent tracking, a missing AI Act disclosure) should block a release; wire this suite's output into that go/no-go checklist.

## Reference Files (in `references/`)

- **gdpr-cmp-tests.md** — Playwright implementations for banners/dark patterns, cookie state before/after consent, persistence and withdrawal, third-party script blocking, Global Privacy Control (`navigator.globalPrivacyControl`), TCF v2 `__tcfapi` consent reads plus a v2.3 version guard, and Google Consent Mode v2.
- **eu-ai-act-tests.md** — the Article 50 transparency-disclosure test and the Article 5 prohibited-practice gate (biometric library detection), with notes on the Omnibus timeline shift.
- **better-ads-tests.md** — Coalition for Better Ads checks: live-property detection of auto-playing unmuted video and mobile ad-density measurement.
- **cookie-compliance.md** — the typed cookie inventory, attribute validation (including SameSite normalization), and inventory drift detection.
- **ci-automation.md** — the scheduled weekly compliance-audit GitHub Actions workflow with 90-day artifact retention.
