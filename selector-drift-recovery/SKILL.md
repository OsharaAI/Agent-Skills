---
name: selector-drift-recovery
description: >-
  Regenerate large batches of test locators that broke because a UI refactor or
  redesign reshaped the DOM, rather than because the product itself broke.
  Compares an aria-snapshot of the old DOM against the new one to isolate the
  drift, remaps each stale locator using a role-first strategy scoped to the
  right region, checks the rebuilt suite against the new build, and delivers
  one PR bundling every per-file selector fix with its own evidence. Built for
  Playwright >= 1.50 (trace viewer's DOM-snapshot panel, getByRole filtering,
  ariaSnapshot). Use when: "UI refactor broke tests," "redesign broke tests,"
  "bulk update selectors," "regenerate selectors after refactor," "selector
  drift," "fix N broken tests after redesign." Not for: healing a single flaky
  test at runtime — use test-reliability. Not for: authoring a fresh test suite
  — use playwright-automation. Not for: porting tests across frameworks
  (Selenium to Playwright) — use test-migration.
  Related: test-reliability, playwright-automation, test-migration, ci-cd-integration, visual-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: automation
---

<objective>
Twenty-three tests start throwing `TimeoutError: locator.* exceeded` right after a redesign lands — nothing about the product broke, only the DOM underneath it. This skill exists to close that gap in one pass: it lines up the pre- and post-refactor DOM, regenerates every broken locator against the new markup using role-first rules, re-runs the suite to confirm the fixes hold, and packages the result as a single PR carrying a confidence score and a screenshot for every change. It fires off an event — a merged refactor — not a single flake, and what it hands back is a PR for a human to approve, never a silent runtime patch.

Think of it as the offline, batch sibling of `test-reliability`: both lean on the same multi-attribute-locator and confidence-scoring machinery, but they point in opposite directions. `test-reliability` patches one selector live, behind a guarded threshold, while a test is running. `selector-drift-recovery` rebuilds many selectors at once, offline, against the finished new DOM, and rolls them into a reviewable PR. Mid-way through that second kind of workflow inside `test-reliability` already? Switch over here.
</objective>

## Quick Route

| Situation | Go to |
|---|---|
| Just one test is broken, no refactor involved | Stop — that's `test-reliability`'s job |
| A refactor changed behavior/flows, not only structure | Stop — rebuild from the spec with `playwright-automation` |
| Switching test frameworks (Selenium → Playwright) | Stop — that's `test-migration`, not drift recovery |
| Nowhere to find the pre-refactor DOM | Capture one first (Phase 1), or narrow scope — without it you're really just rewriting tests |
| 200+ selectors broken across many files | Split into one PR per page/directory, then start Phase 1 |
| Old and new DOM in hand, ready to map | Jump to Phase 1 → 6 |

---

## Before You Dive In

First check whether `.agents/qa-project-context.md` exists — if it does, treat it as already-answered ground truth (framework, selector conventions, known-fragile spots) and skip whatever it covers. Otherwise, work through:

1. **What caused the drift?** A refactor still in flight (Storybook already shows the new DOM), a redesign already merged to main, a dependency bump, or a CSS/Tailwind migration? This determines whether you're getting ahead of it or reacting to red CI.
2. **How wide is the damage?** One component, one page, or the whole product? Narrow damage: limit recovery to the test files touching that component. Product-wide: block out half a day to a full day and expect some tests will need rewriting rather than re-pointing.
3. **What kind of locators does the suite already use?** Mostly `data-testid`, and the refactor kept those ids stable? Recovery is close to mechanical. Mostly CSS classes or XPath? Expect 30–60% of them to need an entirely different *approach*, not just a swapped-in locator.
4. **Do you actually have a working baseline to compare against?** You need the pre-refactor DOM from *somewhere* — an old CI trace artifact, a live staging build still on the prior version, a Storybook story, or the components' git history. No reference point at all means this is effectively a rewrite, not a recovery.
5. **Inline locators, or hidden behind a Page Object?** The JSON reporter's `error.location` reports the line that *failed* — for an inline locator that's the locator itself, but for a POM-wrapped one it's the helper method, not the test. Sort this out before trusting the line numbers the extraction step gives you (more in Failure Modes).
6. **Who signs off on the PR?** Every confidence-scored change still needs a human to bless it. Settle in advance whether that's the original test author, whoever drove the refactor, or QA leadership.

---

## Ground Rules

1. **This is triggered by an event, never by a single failure.** Kick it off when a refactor is imminent or has just landed — not the moment one test flakes. One flaky test belongs to `test-reliability`; ten-plus breaking from the same refactor belong here.

2. **Everything hinges on one old/new DOM pair.** Capture both sides as **aria snapshots** (`await page.locator('body').ariaSnapshot()`) rather than raw HTML: a role-tree diff surfaces exactly the structural change role-first recovery cares about, and it ignores the noise — renamed classes, extra wrapper divs — that would swamp a raw-HTML diff. No snapshot pair yet? Get one before anything else.

3. **Default to role-first locators, no exceptions.** Whatever the old test used, the replacement should try `getByRole` plus an accessible name first, `getByLabel` for form inputs second, and `getByTestId` third if the refactor happens to have added one. Treat the recovery PR as an opportunity to raise the suite's average stability score (same 0–5 rubric used by `test-reliability`, below).

4. **Resolve ambiguity with region scoping, not position.** Two buttons both named "Submit"? Narrow with `getByRole('region', { name }).getByRole('button', …)` or a `.filter({ hasText })`, not layout math. (See the callout below on why positional selectors are off the table.) A locator only earns a 3 once scoping has actually reduced it to a single match.

5. **Ship one PR, organized by file, evidence attached per change.** No reviewer can meaningfully evaluate 47 scattered selector edits across 30 separate commits. Consolidate into one PR, group the diff by test file, and attach a confidence score plus a DOM screenshot to every individual change.

6. **Green suite before merge; dead tests get removed, not patched.** A "fixed" selector that still doesn't run has accomplished nothing — the job isn't done until CI is green, not merely until a diff exists. And if the refactor deleted a feature outright, delete its tests too; don't manufacture selectors for elements that no longer exist.

> **Skip these:** Playwright's positional selectors — `:near()`, `:right-of()`, `:left-of()`, `:above()`, `:below()` — are deprecated and slated for possible removal, because a one-pixel layout nudge changes what they match (per the 2026 Playwright docs). They also run counter to the role-first approach this skill is built on. Reach for region scoping or `getByRole().filter()` instead.

---

## Workflow

Six gated phases — each has a checkpoint you confirm before moving to the next.

### Phase 1 — Capture the pre-refactor DOM

Get a snapshot, in its old state, of every page or component the failing tests exercise. **In order of preference:**

1. **The most recent green CI trace.** Teams commonly keep traces on failure (`trace: 'on-first-retry'`); pull the last passing run's artifact instead, open it with `npx playwright show-trace traces/checkout.zip`, click through actions, and read the **DOM snapshot panel** for each one. (There's no "Copy HTML at this step" menu anymore — read the panel directly, or script a dump with `page.content()` / `ariaSnapshot()` as shown below.)
2. **Storybook checked out at the pre-refactor commit.** `git checkout <PRE_REFACTOR_SHA>`, boot Storybook, and dump each story with a small `page.content()` / `ariaSnapshot()` script.
3. **A staging environment still running the old build.** Walk the same flows there and snapshot them.
4. **The component's git history.** Works, but it's the slowest path — you're rendering things in isolation.

Save output as `.drift-recovery/old/<page-or-component>.aria.yml` (plus `.html` if raw markup matters too) for each unit.

**Checkpoint:** you can point to a saved snapshot file — not a recollection — that answers "what did this page look like the last time these tests passed?"

### Phase 2 — Capture the post-refactor DOM

Repeat the capture against the new build — a preview deploy (Vercel/Netlify) is ideal, or a local dev server or the PR branch running in CI. Let hydration finish first (`await page.waitForLoadState('networkidle')`); snapshotting too early on an SSR page gets you the pre-hydration tree and you'll lose anything client-rendered.

Save output as `.drift-recovery/new/<page-or-component>.aria.yml`, mirroring the old set.

**Checkpoint:** every old snapshot has a corresponding new one. If a route now 404s, that flow was removed — queue its tests for deletion in Phase 6.

### Phase 3 — Isolate the broken locators and figure out what they were for

Run each test file against the new build with the JSON reporter, then parse the output. For every failure, record: **file, line, the original locator string, whether it's a timeout or an assertion failure, and what the locator was trying to do.** Group by test file.

- **Classify the error type first.** A drift-caused failure looks like `TimeoutError: locator.* exceeded`. That's different from an assertion mismatch (`expect(...).toBe`) — don't try to re-select a locator that actually resolved fine and just failed a value check.
- **Intent has to be inferred — the reporter won't hand it to you.** Look at the surrounding test: what does it do with the locator, what does it check afterward? Capture a short phrase for that ("submit the order," "read the order total"). Candidate generation in the next phase depends on this string, so treat it as required data, not a nice-to-have note.
- **The same goes for the page route.** Also absent from the reporter. Tie each locator back to the snapshot file it should resolve against (one of the `.drift-recovery/new/*.aria.yml` files) so Phase 4 loads the correct new DOM.

You end up with a table like:

| Test file | Line | Old locator | Error type | Page route | Inferred intent |
|---|---|---|---|---|---|
| `tests/checkout.spec.ts` | 42 | `getByTestId('submit-btn')` | timeout | `/checkout` | Submit the order |
| `tests/checkout.spec.ts` | 87 | `locator('.summary > h2')` | timeout | `/checkout` | Read the order total |

`references/recovery-scripts.md` has `identify-drift.ts`, which builds exactly this table — with intent and route already filled in, not left as placeholders.

**Checkpoint:** every broken locator has both an inferred intent and a page route attached. Can't infer one? Ask the author or dig up the original PR — guessing isn't acceptable here.

### Phase 4 — Propose replacements

For each row, build candidate locators against the **new** snapshot and score them 0–5 (the same rubric `test-reliability` uses). Ladder, strongest option first:

1. **A fresh `data-testid`** the refactor introduced — the strongest signal the refactor authors gave you. Score 5.
2. **`getByRole` plus an accessible name, unique on the page.** Score 4.
3. **`getByLabel` for a form field**, whenever the target is an input with a real label. Score 4 (prefer this over a bare role match when the field wouldn't otherwise have a name).
4. **Role plus name, scoped to a region until it's unique.** If role+name alone matches more than one element, wrap it — `getByRole('region', { name }).getByRole(role, { name })` or `.filter({ hasText })` — and verify the scoped version matches exactly one. It only earns a 3 **once scoping has actually made it unique.**
5. **Text content alone** (`getByText`). Score 2 — breaks the moment copy changes.
6. **A CSS class tied to the structure that just changed.** Score 1 — very likely to break again immediately.
7. **Nothing safe to offer.** Score 0 — kick it to a human.

| Score | Strategy | Auto-apply? |
|---|---|---|
| 5 | Fresh `data-testid` | yes |
| 4 | `getByRole` + accessible name (or `getByLabel`), unique | yes |
| 3 | `getByRole` + name, region-scoped down to one match | yes |
| 2 | Text-only match | no |
| 1 | CSS class on changed markup | no |
| 0 | Nothing safe found | no — flag for a human |

**A 3 is only valid once scoping has already resolved it to one element.** A candidate that still matches more than one (`count > 1`, "still needs scoping") is not a 3 — it's incomplete work, and must never be auto-applied.

Write results to `.drift-recovery/candidates.json`: `{ file, line, oldLocator, selector, score, rationale, screenshotPath }` per row. `generate-candidates.ts` in `references/recovery-scripts.md` implements this.

**Checkpoint:** every row either has a candidate scored 3 or higher (confirmed unique) or is explicitly flagged for a human. Nothing scored 0, 1, or 2 gets auto-applied.

### Phase 5 — Apply, run, adjust

1. Write the score-≥3 replacements to a feature branch, editing by `(file, line)` — never a blanket string replace. The reporter's locator string is a *rendered* form (e.g. `locator('.summary > h2')`) that frequently doesn't match the literal source text, a plain `String.replace` only touches the first hit, and it'll collide whenever two lines share an identical locator. Target the exact line, and mark `applied: true` only for candidates you actually wrote in.
2. Re-run the **entire affected suite**, not just what was previously red — a new locator can accidentally match something else and take down a test that used to pass.
3. For each test: **green** → keep the change. **red** → back out that single line and route the test to human review.
4. Print a summary: however many were auto-recovered, however many were flagged.

**Checkpoint:** recovered tests pass. Flagged tests are clearly labeled as such, never quietly folded in with the rest.

### Phase 6 — Open the PR

The PR itself is the output of this skill. **Title:** `chore(tests): selector recovery after <refactor description>`. **Body**, built from `candidates.json` filtered to `applied` rows:

```markdown
## Trigger
<Link to the refactor PR / describe the redesign>

## Summary
- N test files updated   - M selectors changed
- K tests deleted (feature removed)   - L tests flagged for manual review

## Per-file changes
<For each file: a table of line, old, new, score, screenshot URL>

## Flagged for review
<Tests where no candidate scored >= 3, with the inferred intent>

## How to review
- Check each screenshot: does `new` point at the element `old` pointed at?
- For score-3 candidates, verify the region scope is meaningful in the new design.
- For flagged tests, decide: rewrite, delete, or accept a manual selector update.
```

Embed screenshots using your CI's artifact-URL scheme. `references/recovery-scripts.md` has both `apply-recovery.ts` (line-anchored edits) and `build-pr-body.ts`.

**Checkpoint:** the PR is small enough to review in one sitting. If not, split it by area — one PR per page, component, or test directory.

---

## What Not To Do

1. **Auto-apply anything scored 0, 1, or 2.** A 2 just means "we found *an* element that matched." That's a bet, not a fix, and it's the most common reason a suite's average stability score falls *after* a recovery pass. Only 3-and-up gets auto-applied.

2. **Call an unresolved multi-match a "3."** If `getByRole(...)` still matches more than one element, it isn't a 3 until region scoping brings it down to exactly one. Mislabeling it and auto-applying ships a locator pointed at the wrong element.

3. **Skip the screenshots.** Even a 4 can point at the wrong element if the page has two regions sharing a role and name. The per-change screenshot is the only thing that catches that kind of semantic drift — the numeric score alone won't.

4. **Do a content-wide string replace instead of editing by line.** `content.replace(oldLocator, …)` only hits the first occurrence, breaks on duplicate locators, and fails silently whenever the reporter's rendered string doesn't match the source verbatim. Always edit the specific `(file, line)`.

5. **Trust extracted line numbers blindly for POM-wrapped locators.** The JSON reporter's `error.location` reports the failing line, which for a Page Object is the helper method, not the test itself. Pull the real locator from the trace action or grep the POM source before applying anything.

6. **Regenerate selectors for features that no longer exist.** If the refactor removed a flow, its tests should be deleted, not patched. Catch deleted routes during Phase 2 and prune accordingly.

7. **Let CI auto-merge the recovery PR.** The whole point of the PR is a human reviewing the evidence per change. Auto-merging on green defeats that — a suite can pass while a selector quietly points at the wrong-but-present element. Require an actual reviewer.

8. **Treat this as a fire to put out immediately.** A red suite feels urgent, but a *correct* fix matters more than a fast one. Rushing tends to produce score-2 replacements that erode the suite over time.

---

## Failure Modes

| Symptom | Likely cause | Fix or check |
|---|---|---|
| `identify-drift.ts` reports 0 failures despite a red CI run | The suite crashed before writing the JSON report, or the wrong file got parsed | `jq '.stats' .drift-recovery/results.json`; confirm `--reporter=json` was actually redirected to that file |
| The extracted line lands in a POM file instead of the test | The locator is wrapped inside a Page Object | Pull the locator from the trace action, or grep the POM source for the rendered string |
| `generate-candidates.ts` sees `undefined` for intent or route | Phase 3's output is missing those fields | Fill them in during Phase 3 — the reporter never provides them, and the generator can't invent them |
| The new-DOM snapshot is missing elements rendered client-side | Snapshot was taken before hydration finished | Add `await page.waitForLoadState('networkidle')` before calling `ariaSnapshot()` |
| Average stability score fell after recovery | A score-2 or CSS-based candidate got auto-applied | Roll back any `candidates.json` entries under score 3 — only role/label/testid picks should ship (see the scorer below) |

---

## Verification

Run these against the recovery branch before opening the PR, cheapest check first:

```bash
# 1. No applied candidate falls under the stability floor (a machine-checkable stand-in for "score went up")
node references/score-candidates.mjs .drift-recovery/candidates.json
# prints average score + count of applied rows with score < 3 — that count MUST be 0

# 2. The recovered suite is green against the new build
PLAYWRIGHT_TEST_BASE_URL=$PREVIEW_URL npx playwright test --reporter=json \
  | jq '.stats.unexpected'        # must be 0 (flagged tests excluded via grep/skip)

# 3. The PR exists with the evidence body
gh pr view --json title,body -q '.title'   # contains "selector recovery"
```

`references/score-candidates.mjs` reads `candidates.json` and prints the average applied score alongside the count of `applied && score < 3` rows — any nonzero count means a low-confidence pick slipped through. Step 1 passing plus step 2 returning `0` together confirm the recovery actually worked.

---

## Done When

- Every test in scope is either passing on the new build, flagged for human review with a stated reason, or deleted because its feature is gone.
- `references/score-candidates.mjs candidates.json` reports **0** applied candidates scoring under 3.
- The PR is open (`gh pr view` succeeds), with a confidence score and screenshot for every change, grouped by file.
- `npx playwright test --reporter=json | jq '.stats.unexpected'` returns `0` on the recovery branch.
- `.agents/qa-project-context.md` gets a short note describing the refactor and any new test patterns it introduced.

## Reference Files (in `references/`)

- **recovery-scripts.md** — the complete, runnable playbook: aria-snapshot capture, `identify-drift.ts` (fills in intent + route), `generate-candidates.ts` (region-scoping ladder, genuine score-3 logic), line-anchored `apply-recovery.ts`, and `build-pr-body.ts`. Includes the Cypress-adaptation note.
- **score-candidates.mjs** — small stability scorer; prints the average applied score and how many applied rows fall under score 3. Used by both Verification and Done When.

## Related Skills

- **test-reliability** — runtime, single-test healing. Use it for one flaky test, not a mass update driven by a refactor. Shares the 0–5 stability rubric with this skill.
- **playwright-automation** — writing new tests from scratch. Reach for it when the refactor removed enough functionality that tests need rewriting, not just re-pointing.
- **test-migration** — moving between frameworks (Selenium → Playwright). That's a re-recording exercise, not selector drift, even though both touch a lot of tests at once.
- **visual-testing** — running this on every PR would have caught the redesign's visual diff before merge. Recovery is the fallback for when that coverage isn't in place.
- **ci-cd-integration** — wires the recovery PR's validation step into your CI pipeline.
