---
name: accessibility-testing
description: >-
  Validate WCAG 2.2 AA conformance using axe-core paired with Playwright, run keyboard-only
  navigation audits, exercise screen readers, verify ARIA patterns, and map findings to legal
  obligations (ADA, EAA, Section 508). Because scanners alone surface only a fraction of real
  problems, this skill combines automated checks with hands-on manual verification. Use when:
  "accessibility," "a11y," "WCAG," "screen reader," "axe," "keyboard navigation," "ARIA," "ADA
  compliance."
  Not for: cookie-consent/GDPR compliance — use compliance-testing; pixel-diff visual
  regression — use visual-testing.
  Related: playwright-automation, compliance-testing, visual-testing, ci-cd-integration.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: specialized
---

<objective>
The goal is a product that someone navigating entirely by keyboard, or relying on a screen
reader, can actually operate — backed by tests that run automatically in CI. Passing
`toBeVisible()` says nothing about whether a control is keyboard-reachable, and a clean axe scan
says nothing about whether a screen-reader user can actually complete a task. Automated scanners
surface only 30-40% of real accessibility problems; the remainder requires the keyboard, screen
reader, and ARIA-state checks this skill also covers.
</objective>

## Questions to Resolve First

Look for `.agents/qa-project-context.md` before asking anything — treat whatever it already
answers as settled and build from there.

**Scope and legal obligations** (this determines the bar you're testing against)
- Which WCAG conformance level applies — A, AA, or AAA? AA is the level most legal frameworks default to.
- Which regulations are in play — ADA, EAA/EN 301 549, Section 508, AODA? Each one implies a specific WCAG level.
- Does a VPAT or public accessibility statement need upkeep, or are there contractual accessibility clauses from enterprise or government customers?

**Baseline** (auditing from scratch vs. guarding against new regressions are different jobs)
- Was there a prior audit? What did it find, and how much of that is still open?
- Does the design system already bake in accessible components and guidance?

**Existing tooling** (shapes what can run unattended vs. what still needs a human)
- Is automated a11y testing wired into CI already?
- Which screen readers does the team actually validate against — VoiceOver, NVDA, JAWS, TalkBack?

## Guiding Principles

1. **Automation tops out around 30-40% coverage.** axe-core is good at flagging missing alt
   text, insufficient contrast, unlabeled fields, and malformed ARIA — but it has no way to judge
   whether alt text actually describes the image, whether tab order makes sense, or whether a
   bespoke widget can be operated at all. A green axe run is a floor, not proof of conformance.
   Notably, axe has **zero automated coverage** for some WCAG 2.2 success criteria (2.4.11
   focus-not-obscured, 2.5.7 dragging movements, and only partial coverage of 2.5.8 target-size),
   so passing axe never equals passing 2.2 AA.

2. **Default to native HTML; reach for ARIA only when nothing else fits.** Elements like
   `<button>`, `<nav>`, `<input>`, and `<dialog>` come with keyboard handling, semantics, and
   screen-reader support already built in. Recreate a button with `<div role="button">` and now
   you owe it `tabindex`, manual Enter/Space handling, visible focus styling, and correct ARIA
   state — none of which a real `<button>` requires you to think about. ARIA is a fallback, not a
   first choice.

3. **Fix things in order of user impact: keyboard first, then screen reader, then automated
   sweep.** A keyboard-inaccessible feature is completely unreachable for some users — that's the
   worst outcome. A screen reader announcing the wrong thing is confusing but often still
   navigable. Automated tooling picks up whatever mechanical issues remain. Triage by damage,
   not by what's easiest to check.

4. **Treat accessibility like a standing quality bar, not a one-time feature.** Test it on every
   PR and every new component, the same way you'd treat performance or security regressions.
   Accessibility debt that accumulates into the component library becomes 10-100x more expensive
   to unwind later.

5. **Actual assistive technology, not just DevTools, is the final check.** Browser accessibility
   panels and axe extensions are useful during development, but they don't substitute for testing
   with VoiceOver (macOS/iOS), NVDA (Windows), and TalkBack (Android) — each interprets the page
   differently. Save hands-on AT passes for the complex, custom-built widgets.

## Automated Scanning: axe-core + Playwright

Bring in `@axe-core/playwright` on the 4.11.x line (it follows axe-core's own major.minor
versioning). Wrap the call in a shared `checkAccessibility(page, testInfo, options)` utility that
restricts scanning to the WCAG tag set `['wcag2a', 'wcag2aa', 'wcag22aa']`, attaches the raw
results JSON to the test run as an audit record, and fails via `violations.toHaveLength(0)`. Run
it against every important page — and against interactive states like an open modal or an
expanded menu, not only the initial page load.

Only suppress a rule when there's a documented reason (a linked ticket or an inline comment), and
scope third-party widgets you don't control out with `exclude` rather than turning the rule off
globally.

The install command, the RGAA tagging gotcha, the complete helper implementation, page-loop and
interactive-state test examples, suppression patterns, and CI wiring are all in
`references/recipes.md`.

## The Manual Checklist

Think of automated scanning as the baseline, not the finish line. The checks below need either a
human tester or a keyboard-driven Playwright spec (examples in `references/recipes.md`).

### Auditing keyboard-only navigation

- [ ] **Tab order follows reading order** — left-to-right, top-to-bottom for LTR layouts, with no unexpected focus jumps.
- [ ] **Every interactive element is reachable** using Tab and Shift+Tab alone.
- [ ] **Focus is always visibly indicated.** Never strip `outline: none` without providing a replacement.
- [ ] **The skip link functions** — the very first Tab reveals "Skip to main content," and Enter jumps focus into `<main>`.
- [ ] **Enter triggers** buttons and links; **Space** triggers buttons and toggles checkboxes.
- [ ] **Escape dismisses** modals, dropdowns, and tooltips, returning focus to whatever opened them.
- [ ] **Arrow keys move focus** inside tabs, menus, radio groups, and tree widgets.
- [ ] **No unintended keyboard traps** exist (a modal deliberately trapping focus until dismissed is fine and expected).
- [ ] **Custom controls work mouse-free** — sliders, date pickers, drag-and-drop.

### Verifying with screen readers

| Screen Reader | OS | Browser | Free? |
|--------------|-----|---------|-------|
| VoiceOver | macOS/iOS | Safari | Yes (Cmd+F5) |
| NVDA | Windows | Firefox/Chrome | Yes |
| JAWS | Windows | Chrome/Edge | No |
| TalkBack | Android | Chrome | Yes |

- [ ] Navigating to a page announces its title.
- [ ] Heading levels form a coherent outline (h1 → h2 → h3, nothing skipped).
- [ ] Images carry meaningful alt text, or `alt=""` when purely decorative.
- [ ] Focusing a form field announces its associated label.
- [ ] Required fields are announced as such; validation errors are tied to the relevant field.
- [ ] Dynamic content (toasts, loading indicators) is announced through live regions.
- [ ] Interactive elements describe their purpose (never just "click here").

### Contrast and other visual checks

- [ ] Body text meets **4.5:1** contrast minimum (WCAG AA); large text (18pt+, or 14pt+ bold) meets **3:1**.
- [ ] UI components and graphical elements meet **3:1** contrast against neighboring colors.
- [ ] Color is never the only signal conveying information — pair it with icons, patterns, or text.

### Making forms and errors accessible

- [ ] Every field has a real `<label>` connected via `for`/`id` — a placeholder doesn't count as a label.
- [ ] Required status is shown both visually and programmatically (`required` / `aria-required`).
- [ ] Errors connect to their input with `aria-describedby` and announce via `role="alert"`.
- [ ] A failed submission moves focus to the first invalid field.
- [ ] Related inputs are grouped under `<fieldset>` with a `<legend>`.

## WCAG 2.2 at a Glance

### Level A — non-negotiable

| Criterion | What it means | Common failure |
|-----------|--------------|---------------|
| 1.1.1 Non-text Content | Images have alt text | `<img>` without `alt` |
| 1.3.1 Info and Relationships | Structure via HTML semantics | `<div>` styled as a heading |
| 2.1.1 Keyboard | All functionality via keyboard | Custom widget responds only to mouse |
| 2.4.1 Bypass Blocks | Skip navigation link | No skip link |
| 3.1.1 Language of Page | `<html lang="en">` set | Missing `lang` |
| 3.3.1 Error Identification | Errors described in text | Error shown only by red border |
| 4.1.2 Name, Role, Value | Custom controls expose name/role | `<div onclick>` with no role |

### Level AA — the usual legal floor

| Criterion | What it means | Common failure |
|-----------|--------------|---------------|
| 1.4.3 Contrast (Minimum) | 4.5:1 normal, 3:1 large | Light gray on white |
| 1.4.4 Resize Text | Scales to 200% without loss | Fixed-height containers clip text |
| 1.4.11 Non-text Contrast | UI components 3:1 | Low-contrast input borders |
| 2.4.7 Focus Visible | Keyboard focus visible | `outline: none` with no replacement |
| 2.5.8 Target Size | Touch targets 24×24px min | Tiny icon buttons |
| 3.3.2 Labels or Instructions | Inputs have labels | Placeholder as the only label |
| 3.3.8 Accessible Auth | No cognitive function test | CAPTCHA with no alternative |

### Level AAA — aspirational

| Criterion | What it means |
|-----------|--------------|
| 1.4.6 Contrast (Enhanced) | 7:1 normal text, 4.5:1 large |
| 2.4.9 Link Purpose (Link Only) | Link text alone describes destination |
| 3.1.5 Reading Level | Lower-secondary education level |

## Patterns Worth Testing Directly

Assert against the accessible tree — roles, names, ARIA state — rather than CSS, so tests survive
a restyle. The patterns that need dedicated, runnable coverage:

- **Forms** — the error is wired to the field via `aria-describedby`, `aria-invalid='true'` is set, and focus lands on the first invalid field.
- **Modal/dialog** — `aria-modal='true'`, `aria-labelledby` present, focus trapped inside, Escape restores prior focus.
- **Interactive states** — an open dropdown (`role="menu"` or `role="listbox"` plus `aria-expanded`), a loading skeleton (`aria-busy='true'` mid-fetch), a toast (`aria-live='polite'`). Each of these only shows its real ARIA once triggered, so click into the state and assert against that — a default-load snapshot won't exercise any of it.
- **Data tables** — proper `columnheader` roles, with `aria-sort` reflecting whichever column is active.
- **Landmarks** — a single `main`, plus `banner`, `navigation`, and `contentinfo` all present.

Full runnable tests for each of these patterns are in `references/patterns.md`.

## Snapshotting the Accessible Tree

`toMatchAriaSnapshot()` in Playwright captures the accessibility tree as YAML for comparison —
it's an efficient way to catch a case where a purely visual change quietly broke the underlying
semantics (a heading turned into plain text, a styled `<div>` masquerading as a button). Because
it checks structure and accessible names rather than pixels, it complements `visual-testing`
rather than replacing it. Keep the scope narrow — a whole-page snapshot over anything async or
reorderable will be flaky. Example snapshots for navigation and forms are in
`references/patterns.md`.

## Mapping Requirements to the Law

| Law / Standard | Region | WCAG level required | Enforcement |
|---------------|--------|-------------------|------------|
| **ADA** | USA | AA (court precedent) | Lawsuits (private right of action) |
| **Section 508** | USA (federal) | WCAG 2.0 AA | Federal procurement requirement |
| **EAA** | EU | EN 301 549 (WCAG 2.1 AA) | **In force since 28 June 2025.** Member states actively enforcing; private cause of action varies (DE, FR, IE most active). EN 301 549 expected to align with WCAG 2.2 next revision. |
| **AODA** | Ontario, Canada | WCAG 2.0 AA | Fines up to $100K/day |
| **EN 301 549** | EU | WCAG 2.1 AA | Public procurement requirement |
| **Equality Act 2010** | UK | WCAG 2.1 AA (guidance) | Lawsuits |
| **ISO/IEC 40500:2025** | International | Equivalent to WCAG 2.2 (Oct 2023) | Useful for procurement/RFP language; freely available from ISO |

**Bottom line:** for any product serving US or EU users, **treat WCAG 2.2 AA as the bar for new
work** — the EAA is already enforced, EN 301 549 is on track to reference 2.2, and ISO/IEC
40500:2025 (September 2025) has already codified 2.2 internationally. Where 2.2 isn't yet
reachable, 2.1 AA is the fallback minimum.

**On WCAG 3:** the W3C's March 2026 working draft renamed "Outcomes" to "Requirements" and
dropped the binary pass/fail model in favor of roughly 174 requirements. It's still a working
draft — Candidate Recommendation isn't expected until Q4 2027, with a final Recommendation not
before 2028. Build against WCAG 2.2 now; keep an eye on WCAG 3 without testing against it yet.

**What to keep as evidence:** per-page automated scan output, dated manual checklists with the
tester's name, screen-reader findings with AT version numbers, an accessibility statement, a VPAT
for enterprise deals, and a documented remediation plan for anything still open. The full
legal/VPAT/consent mapping lives in `compliance-testing`.

## Common Mistakes

### Treating a clean scan as proof of accessibility
Running axe, seeing zero violations, and calling it done. Automated tooling misses roughly
60-70% of real-world issues and doesn't cover several WCAG 2.2 criteria at all. **Fix:** always
pair the axe run with the keyboard and screen-reader checklist, and require both to pass before
release, not just the scan.

### Piling on unnecessary ARIA
Slapping `role`, `aria-label`, and `aria-describedby` onto elements that already have native
semantics, which causes screen readers to announce things twice. **Fix:** strip the redundant
ARIA and lean on the native element instead — a `<button>` never needs `role="button"`.

### Leaving keyboard users behind
Building interactions that only work with a mouse or touch — dropdowns that need a click,
drag-and-drop with no keyboard path, tooltips that only appear on hover. **Fix:** every
mouse-driven interaction needs a keyboard equivalent, verified with a `keyboard.spec.ts` test
(see `references/recipes.md`).

### Bolting accessibility on at the end
Deferring a11y work until the product feels "done," at which point inaccessible patterns are
already baked into the shared component library — and 10-100x costlier to fix. **Fix:** require
an axe check in the Definition of Done so every new component is checked before it merges.

### Deprioritizing accessibility because no one's complained
Assuming silence means there's no problem — users who can't use a product because of a barrier
usually just leave rather than filing a complaint, and web-accessibility lawsuit volume in the US
has risen every year since 2018. **Fix:** treat open a11y issues as release blockers with the
same severity rules as functional bugs, and surface them in release-readiness reviews.

### Only checking the default view
Scanning just the initial page load and missing modals, expanded menus, error states, and loading
skeletons — all of which carry ARIA that only appears once triggered. **Fix:** drive each
interactive state during the test (click to expand, trigger the fetch) and re-scan the resulting
DOM.

## When Things Go Wrong

| Symptom | Likely cause | Fix or check |
|---------|-------------|-------------|
| axe finds 0 violations but the page is unusable by keyboard | Automated scans don't test operability or focus order | Run the keyboard audit; add a `keyboard.spec.ts` |
| `toMatchAriaSnapshot` is flaky | Dynamic content or list reordering inside the snapshot scope | Scope to a stable container; use a partial snapshot |
| Contrast rule passes but text over a gradient/overlay/image is unreadable | axe can't compute contrast against non-solid backgrounds | Check those cases manually or with a contrast picker |
| Passing axe but failing a WCAG 2.2 AA audit | axe ships no rule for 2.4.11 / 2.5.7 and only partial 2.5.8 | Manually verify focus-not-obscured, dragging alternatives, and target size |

## Confirming the Tests Actually Test Something

A suite that passes only because it never touched real content (wrong URL, an error page getting
scanned, a snapshot assertion that never runs) is more dangerous than having no tests at all.
Verify the harness is doing real work:

1. **Make sure axe is examining live content.** Temporarily strip a `<label>` from a page you
   know should trigger a violation, then run:
   ```bash
   npx playwright test e2e/tests/a11y/pages.spec.ts
   ```
   The test must fail and name the specific rule. If a page with a deliberately planted defect
   still passes, AxeBuilder is likely scanning the wrong DOM — a redirect, a blank page, or a bad
   selector — and that needs fixing before any green run can be trusted.
2. **Make sure the keyboard specs hit the real app.** Run
   `npx playwright test e2e/tests/a11y/keyboard.spec.ts` and inspect the trace for the skip-link
   test — the first Tab press should land on the skip link itself, not on nothing. A test that
   passes because the page never actually loaded is a silent false positive.
3. **Make sure CI actually enforces the gate.** Push a branch with one deliberately serious
   violation — the `a11y` job should exit non-zero and fail the check. Revert once confirmed.
4. **Spot-check a snapshot's stability.** Run `toMatchAriaSnapshot` once with
   `--update-snapshots`, then run it again unmodified — it must pass cleanly the second time. If
   it flakes, the scope is too wide and includes async or reordering content; narrow it to a
   stable container.

## Definition of Done

- axe-core is wired into the E2E suite and runs automatically across every key user-facing page named in the test strategy.
- CI reports zero critical/serious axe violations and blocks the merge whenever a new one appears (workflow in `references/recipes.md`).
- Every interactive flow — forms, modals, dropdowns, nav menus — has been walked through with keyboard-only navigation.
- Interactive-state ARIA has been verified for at least one dropdown/menu (`aria-expanded` + role), one loading region (`aria-busy`), and one live region (`aria-live`).
- The full brand color palette has been checked against WCAG AA contrast thresholds (4.5:1 normal text, 3:1 large text and UI components).
- Manual screen-reader test notes exist for complex custom widgets (date pickers, data tables, drag-and-drop), naming the screen reader and version used.

## Adjacent Skills

- **playwright-automation** — supplies the test runner underlying both the axe scans and the keyboard/ARIA snapshot tests; this skill layers accessibility-specific patterns on top of it.
- **compliance-testing** — covers legal/regulatory territory this skill doesn't: cookie consent (GDPR/CMP), VPAT generation, EAA/Section 508 reporting. Use it for consent banners and formal compliance paperwork; stay here for WCAG conformance itself.
- **visual-testing** — handles pixel-diff screenshot regression. Reach for it for rendering changes; use this skill's ARIA snapshots for semantic-tree regressions and its contrast checks for a11y-specific color thresholds.
- **ci-cd-integration** — wires a11y tests into CI and enforces merge blocking on violations.
- **risk-based-testing** — helps decide which pages and components to audit first.
