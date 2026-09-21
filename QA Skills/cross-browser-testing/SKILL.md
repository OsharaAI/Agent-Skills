---
name: cross-browser-testing
description: >-
  Design analytics-driven browser test matrices and execute cross-browser tests.
  Covers BrowserStack/Sauce Labs configuration, Playwright browser channels, common
  cross-browser CSS/JS divergences, a known-issues documentation log, and progressive
  enhancement validation.
  Use when: "cross-browser," "browser matrix," "BrowserStack," "Safari issues,"
  "browser compatibility," "Edge," "works in Chrome but not Safari."
  Not for: pixel-level baseline strategy and threshold tuning — use visual-testing;
  device-farm testing of native/hybrid apps — use mobile-testing.
  Related: visual-testing, playwright-automation, ci-cd-integration, mobile-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: specialized
---

<objective>
Shipping a product that only ever ran through Chrome is a trap: markup that looks fine under Chromium can collapse in WebKit, a clipboard call that behaves in Chrome can quietly do nothing in Firefox, and a cookie-partitioning flow can hold up everywhere except the one engine a chunk of your users actually run. This skill helps you build a browser matrix grounded in real traffic data, wire up a Playwright or cloud-grid config to exercise it, and keep a committed record of known engine divergences — with every entry backed by a test that checks the outcome a user experiences, never the underlying CSS.
</objective>

## Quick Route

| Situation | Go to |
|-----------|-------|
| Need to decide *which* browsers to test | Browser Matrix Design |
| Already on Playwright, just add browsers | Playwright Browser Configuration → `references/playwright-and-cloud-config.md` |
| Need real Safari/Windows/older OS, not engines | Cloud Platform Setup |
| One browser misbehaves; want a test for it | Common Cross-Browser Issues + `browserName` branch in `references/testing-patterns.md` |
| Need to record a divergence so it is not re-debugged | Known-Issues Log |
| Pixel diffs / baseline thresholds | use `visual-testing` |

## Discovery Questions

Check `.agents/qa-project-context.md` first — reuse whatever it already answers instead of re-asking. Otherwise work through:

1. **Which browsers does your traffic actually show?** Pull real browser/OS breakdowns from analytics rather than guessing. Spending effort on a browser nobody opens is wasted work; skipping one that carries 15% of sessions is a real gap.
2. **Is mobile in scope alongside desktop?** iOS Safari and Android Chrome do not render like their desktop namesakes — list them as their own matrix rows rather than folding them into the desktop entries.
3. **Local engines or a cloud grid?** Playwright's bundled engines only get you Chromium, Firefox, and WebKit — not the actual shipped Chrome or Safari. BrowserStack, Sauce Labs, and LambdaTest give you the real, branded browser/OS combinations.
4. **What counts as passing — graceful degradation, or pixel-identical output?** Progressive enhancement tolerates visible differences as long as the experience holds up; a pixel-perfect bar does not. This choice sets your pass/fail line.
5. **Is Playwright already wired up?** If so, cross-browser support is mostly a config addition rather than tooling adoption.

---

## Core Principles

1. **Let traffic drive the matrix.** Invest according to real usage. A browser sitting at 0.3% of sessions doesn't warrant the same coverage as one carrying 40%. Re-pull the numbers every quarter since share moves.

2. **Aim for progressive enhancement, not pixel parity.** Perfectly identical rendering across every browser is neither realistic nor the goal. Decide up front what "working" means — core tasks complete, content stays reachable, the layout remains usable — and treat cosmetic drift in shadows, gradients, or animation timing as acceptable.

3. **Prioritize Safari and Firefox — they expose the real gaps.** A Chrome-only pass mostly finds Chrome-only bugs. WebKit (Safari) and Gecko (Firefox) diverge from Chromium the most, so give them the bulk of your attention.

4. **Assert on functionality, not engine internals.** A cross-browser test should confirm a user can finish their task, not that a given CSS property computed identically. Leave pixel-level comparison to dedicated visual-diff tooling.

5. **Don't confuse an engine with a shipped browser.** Playwright's WebKit build is not Safari, and its Chromium build is not Chrome — same rendering engine, different product (fonts, codecs, enterprise policy, and release cadence all diverge). Describe results as "WebKit coverage" unless you actually ran the real, branded Safari on a cloud grid.

6. **Write the test once, run it everywhere.** Author the logic a single time and execute it across every browser configuration — never fork the same test per browser.

---

## Browser Matrix Design

### Analytics-Based Methodology

```
Step 1: Export browser/OS data from analytics (last 90 days)
Step 2: Rank by session share
Step 3: Group into tiers
Step 4: Assign test coverage per tier
Step 5: Review quarterly
```

### Tier System

| Tier | Criteria | Coverage | When to run |
|------|----------|----------|-------------|
| **P0** | >10% traffic share | Full test suite | Every PR, every deploy |
| **P1** | 3-10% traffic share | Smoke + critical paths | Nightly, pre-release |
| **P2** | 1-3% traffic share | Smoke tests only | Weekly, pre-release |
| **Skip** | <1% traffic share | Not tested | Manual spot-check if reported |

### Example Matrix (derived from analytics)

```markdown
## Browser Matrix — Q1 2026 (next-review: 2026-04-01)

| Browser | Version | Platform | Traffic % | Tier | Notes |
|---------|---------|----------|-----------|------|-------|
| Chrome | Latest | Windows | 34% | P0 | |
| Chrome | Latest | macOS | 12% | P0 | |
| Safari | Latest | macOS | 11% | P0 | WebKit-specific issues |
| Chrome | Latest | Android | 15% | P0 | Mobile viewport |
| Safari | Latest | iOS | 14% | P0 | Mobile Safari quirks |
| Firefox | Latest | Windows | 5% | P1 | Gecko rendering |
| Edge | Latest | Windows | 4% | P1 | Chromium-based but different UA/policy |
| Samsung Internet | Latest | Android | 3% | P1 | Chromium fork, lagging engine |
| Firefox | Latest | macOS | 1.5% | P2 | |
| Chrome | N-1 | Windows | 1.2% | P2 | Previous major version |
```

### Version Coverage Strategy

- **Latest:** Always test current stable release.
- **Latest - 1:** Test previous major version only for P0 browsers where analytics show >1% on older versions.
- **Extended Support Release (ESR):** Test Firefox ESR only if enterprise users are a significant segment.
- **Do not test:** Beta/Canary/Nightly releases unless you are a browser vendor or building browser-facing tools.

---

## Playwright Browser Configuration

Playwright bundles three engines — Chromium, Firefox, WebKit — so basic engine-level coverage needs no external cloud service. Remember this is engine coverage, not brand coverage: the bundled WebKit is not Safari and the bundled Chromium is not Chrome (see Core Principle 5). Set up one project per matrix row, wire mobile devices through `devices[...]`, and reach real, locally installed branded browsers using the `channel` option.

Full `playwright.config.ts` project examples, branded-channel snippets, and the `--project` invocations live in `references/playwright-and-cloud-config.md`.

**When channels earn their keep:** reach for a channel when you specifically need real branded behavior the bundled engine can't give you — installed Chrome (`channel: 'chrome'`) or Edge (`channel: 'msedge'`) for extension support, enterprise policy, or codec handling. WebKit and Firefox have no channel equivalent — they're always the bundled engine. Also note: the config's `edge` project and the `msedge` channel snippet illustrate the same technique two ways, not two separate projects to combine — a working config declares exactly one `edge` project.

**`page.screencast()` (Playwright 1.59+, current in 1.60)** records an annotated video of a run and is handy when a matrix failure needs a human to review it across engines. When you (or an agent) need to step through a failure interactively instead, reach for `--ui` (UI mode) or `--debug` (Inspector); `PWDEBUG=1` and `--headed` cover the remaining real entry points. There is no `--debug=cli` flag.

---

## Cloud Platform Setup

Cloud grids (BrowserStack, Sauce Labs) hand you real branded browser/OS combinations that Playwright reaches over a CDP or Playwright WebSocket endpoint. Supply credentials and capabilities as environment variables, and keep the grid's `playwrightVersion` capability matched to the Playwright version pinned in `package.json` (currently 1.60.x) — a mismatch between client and server versions surfaces as socket errors.

**BrowserStack's current recommendation** is the `npx browserstack-node-sdk` runner combined with a `client.playwrightVersion` capability (used alongside `browserstack.playwrightVersion`) so the client and the grid stay version-locked. The raw `wsEndpoint`/CDP approach shown below still works for direct connections, but the SDK path is the one to reach for on a new setup.

The BrowserStack config (including the `client.playwrightVersion` capability), the Sauce Labs config, and a GitHub Actions matrix that spreads runs across cloud browsers are all in `references/playwright-and-cloud-config.md`.

---

## Common Cross-Browser Issues

The recurring divergences you'll actually hit, along with how to detect and address them. `references/common-browser-issues.md` holds the concrete CSS fixes and Playwright tests for: partitioned cookies / CHIPS inside iframes, `<input type="date">`, the Clipboard API, `scroll-behavior`, `backdrop-filter`, the `<dialog>` element, View Transitions, and Web Animations timing.

### Modern Cross-Browser Gotchas (2026)

Most of the old Safari-lags-behind list has closed out (flexbox `gap`, `:has()`, and same-document View Transitions are all Baseline now). What's still genuinely divergent:

- **Partitioned cookies / partitioned storage:** Chrome's CHIPS (the `Partitioned` attribute), Safari's ITP, and Firefox's State Partitioning all treat embedded third-party contexts differently. Test third-party cookie behavior *inside an iframe, per engine* — don't settle for "the browser supports cookies" as a signal. A runnable per-engine iframe test is in `references/common-browser-issues.md`.
- **`:has()` selector performance:** Support has been universal since 2023, but a page leaning heavily on `:has()` can see very different style-recalculation costs by engine. Keep it on the watch list — profile if a page feels sluggish in one engine, and run it through `visual-testing` if you suspect regressions.
- **View Transitions API:** Same-document transitions reached Baseline (Chrome 111, Safari 18, Firefox 144 — October 2025), so they no longer count as a divergence. The real gap now is **cross-document** transitions: supported from Chrome 126+ and Safari 18.2+, still behind a flag in Firefox. Treat cross-document transitions as progressive enhancement and confirm the fallback (no transition) still works.
- **WebDriver BiDi:** Fully production-ready in Selenium 4, only partially there in Playwright. It's the direction cross-runner projects are converging on — worth watching, not yet a hard requirement.

---

## Known-Issues Log

When a real divergence can't be fixed in the app right away, write it down in a committed file (`docs/browser-issues.md`) instead of letting the same debugging happen again later. This table is exactly what the `Done When` checklist looks for, and every row's test must check the **outcome the user sees, not a CSS property**:

```markdown
| Affected browser | Repro | Workaround / fallback / ticket | Test asserts (user outcome, not CSS) |
|------------------|-------|--------------------------------|--------------------------------------|
| Safari (WebKit) ≤17 | scroll-behavior: smooth is partial | rely on anchor nav; no JS scroll dependency | anchor link puts heading in viewport (`toBeInViewport`) |
| Firefox ≤102 | backdrop-filter unsupported | -webkit- prefix + rgba background fallback | overlay readable; modal content visible |
| Firefox (current) | cross-document View Transitions flagged off | progressive enhancement; instant nav fallback | navigation completes; target page heading visible |
```

Keep the table to one row per divergence. A row missing both a fallback and a ticket is really just an undocumented bug wearing a disguise.

---

## Testing Patterns

The four patterns worth knowing, and the rules governing each:

- **Same test, multiple browsers** — the default approach. Author the test once and let project configuration fan it out across browsers. Never fork identical test logic per browser.
- **Browser-specific test logic** — only branch on `browserName` when the behavior *actually* differs (the WebKit date-input fallback and the Chromium-only clipboard permission grant are legitimate examples). **Rule of thumb:** keep this to a minimum — a proliferation of browser branches usually points to compatibility bugs in the app that deserve a real fix, not a workaround in the test.
- **Visual cross-browser comparison** — `toHaveScreenshot` with a `maxDiffPixelRatio` tolerance, with each browser project maintaining its own baseline image (`homepage-chromium.png`, `homepage-webkit.png`, and so on). Threshold strategy and baseline lifecycle belong to `visual-testing`.
- **Progressive enhancement validation** — intercept and abort script requests (Chromium-only) and confirm the core experience still functions via plain HTML.

Runnable code for all four lives in `references/testing-patterns.md`.

---

## Anti-Patterns

**Only ever testing Chrome.** Chrome may lead on desktop share, but it shares an engine with Edge, Opera, and Brave. Safari (WebKit) and Firefox (Gecko) are where the real cross-browser bugs hide — a Chrome-only pass is false confidence.

**Calling WebKit/Chromium results "Safari"/"Chrome."** The bundled engine shares rendering behavior with the branded browser, not the actual shipped product. Labeling WebKit results as Safari coverage hides codec, font, and policy issues that only the genuine browser reveals.

**Treating every browser as equally important.** A browser sitting at 1% of traffic doesn't merit the same investment as one at 30%. Let the tier system decide where effort goes.

**Copy-pasting tests per browser.** Write the logic once and run it via project configuration. Seeing both a `checkout.chrome.spec.ts` and a `checkout.safari.spec.ts` with the same body is a sign something's structured wrong.

**`browserName` checks scattered everywhere.** Heavy branching by browser in tests is usually a symptom of a compatibility bug the app should fix, not something to route around in test code.

**Zero-tolerance pixel assertions.** Anti-aliasing, sub-pixel rounding, and font rendering vary across browsers and OSes. Give visual comparisons room with `maxDiffPixelRatio` or `maxDiffPixels`.

**Leaving mobile out of the matrix.** Mobile Chrome and mobile Safari behave nothing like their desktop siblings — viewport handling, touch input, and CSS support all diverge. Give them their own matrix rows.

**Letting the matrix go stale.** Browser share shifts over time; a matrix built on two-year-old numbers is no longer accurate. Revisit analytics every quarter and push the `next-review` date forward.

**Recording a divergence with no fallback and no ticket.** That's not documentation — it's an unfixed bug dressed up as a known issue.

---

## Failure Modes

| Symptom | Likely cause | Fix or check |
|---------|--------------|--------------|
| Cloud tests fail with a socket/handshake error | Grid Playwright version ≠ local | Set `playwrightVersion`/`client.playwrightVersion` to match `npx playwright --version`; use the `browserstack-node-sdk` runner |
| Clipboard test passes in Chromium, fails in Firefox/WebKit | `grantPermissions` only works in Chromium | Assert UI feedback (`Copied!`), not the clipboard API; gate `grantPermissions` on `browserName === 'chromium'` |
| Progressive-enhancement test errors in Firefox/WebKit | Script-abort route interception is Chromium-only | Gate the route on `browserName === 'chromium'`; skip the JS-disabled assertion elsewhere |
| WebKit project "passes" but real users on Safari report breakage | WebKit engine ≠ shipped Safari | Add a real-Safari row on a cloud grid for the affected flow |
| Visual baseline diff explodes for one browser only | Single baseline shared across browsers | Generate per-project baselines; each browser keeps its own `*-<project>.png` |
| `:has()`-heavy page janky in one engine only | Style-recalc cost differs by engine | Profile in that engine; reduce `:has()` scope; visual-regress in `visual-testing` |

---

## Done When

- Browser matrix defined using real analytics data (last 90 days), with tier assignments (P0/P1/P2) documented and justified by traffic share, committed to a file carrying a dated `next-review` field.
- Playwright project config (or BrowserStack/Sauce Labs config) reflects the matrix and runs P0 browsers on every PR; cloud configs pin `playwrightVersion` to match `package.json`.
- `docs/browser-issues.md` exists with one row per known divergence: affected browser, repro, workaround/fallback or linked ticket, and the test that asserts the user outcome (not the CSS).
- Common-divergence checklist (partitioned cookies, date inputs, clipboard, scroll behavior, backdrop-filter, `<dialog>`, View Transitions) has a test or a known-issues row for each item relevant to P0/P1 browsers.
- A tracked issue exists for the next quarterly matrix review (or the matrix file's `next-review` date is in the future), so the refresh is not lost.

## Related Skills

- **visual-testing** — Owns pixel-level baseline strategy, threshold tables, and `toHaveScreenshot` config. Go there for *how tolerant* a screenshot diff should be; this skill only decides *which browsers* get a baseline.
- **playwright-automation** — Core Playwright patterns, fixtures, and CI configuration that cross-browser testing builds on.
- **ci-cd-integration** — Pipeline configuration for parallel browser-matrix execution and artifact collection.
- **mobile-testing** — Device-farm and native/hybrid app testing (Appium/Detox); go there when the target is an app, not a browser viewport.
- **accessibility-testing** — Cross-browser accessibility differences (screen-reader behavior, ARIA support) that overlap with this matrix.

## Reference Files (in `references/`)

- **playwright-and-cloud-config.md** — `playwright.config.ts` project list, branded channels, `--project` run commands, and BrowserStack (SDK + `client.playwrightVersion`)/Sauce Labs/CI matrix configs.
- **common-browser-issues.md** — Per-engine partitioned-cookie iframe test, date-input WebKit fallback, clipboard, scroll behavior, backdrop-filter, `<dialog>`, View Transitions, and Web Animations.
- **testing-patterns.md** — Same-test-multiple-browsers, `browserName` branching, visual comparison, and progressive-enhancement code.
</content>
