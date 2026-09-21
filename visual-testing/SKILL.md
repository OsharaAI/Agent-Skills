---
name: visual-testing
description: >-
  Set up and run visual regression testing across Playwright screenshots, Chromatic,
  Percy, and Argos CI, including how to manage baselines, tune diff thresholds, mask
  or freeze dynamic content, test multiple responsive viewports, and structure
  review/approval workflows.
  Use when: "visual test," "screenshot," "visual regression," "pixel diff," "snapshot diff,"
  "update baselines," "Chromatic," "percy snapshot," "argos screenshot."
  Not for: regenerating a large batch of baselines after a redesign breaks many tests at
  once — use selector-drift-recovery; multi-browser rendering matrices — use
  cross-browser-testing; general Playwright test structure — use playwright-automation.
  Related: playwright-automation, ci-cd-integration, cross-browser-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: automation
---

<objective>
Functional tests can pass while the UI is visibly broken: a button that renders at 2px tall still satisfies `toBeVisible()` and still responds to `click()`. Visual testing closes that gap by diffing fresh screenshots against approved baselines and surfacing pixel-level drift. This skill walks through Playwright's built-in `toHaveScreenshot`, the dedicated services (Chromatic, Percy, Argos CI), and the baseline-management practices that make either approach sustainable.
</objective>

## Where to Start

| If you're dealing with... | Go here |
|-----------|-------|
| Plain pixel diffs in CI with no need for a review SaaS | Playwright Visual Comparisons (below) |
| A repo that already has Storybook | Dedicated Tools → Chromatic, or the "Storybook without Chromatic" recipe |
| A need for a hosted review/approval UI plus AI-assisted diff triage | Dedicated Visual Testing Tools |
| Screenshots that flake because of timestamps, avatars, or ads | Masking & Freezing Dynamic Content |
| Baselines that are ballooning your git history | Baseline Management → Git LFS |

---

## Questions Worth Answering First

Look for `.agents/qa-project-context.md` before anything else — if it's there, defer to it and only chase down what it leaves unanswered.

### Which tooling fits
- **Built-in Playwright, or a dedicated service?** `toHaveScreenshot` costs nothing and keeps baselines in the repo (so git/LFS overhead is your problem). Chromatic, Percy, and Argos instead store artifacts off-repo and layer on review workflows, browser farms, historical tracking, and — as of late 2025 — AI-assisted diff triage. The right pick depends on team size, how much review tooling you need, and whether you'd rather artifacts live in your repo or theirs.
- **Is Storybook already in use?** If so, Chromatic fits naturally since every story doubles as a visual test — though you can also drive stories through Playwright for free (see recipes.md). Without Storybook, lean on built-in Playwright or Percy.
- **What CI platform, and what's the artifact budget?** Visual suites produce sizable screenshot and diff artifacts. In-repo baselines mean git bloat and LFS costs; hosted tools move that retention off-repo in exchange for a subscription. Verify CI has the storage and time headroom before scaling coverage up.

### How much to cover
- **Full-page captures, or component-level ones?** Full-page shots surface layout problems but react to any unrelated change nearby. Component screenshots are narrower in scope and much more stable.
- **Which surfaces actually need coverage?** Not every screen warrants it — prioritize user-facing flows, marketing pages, design-system components, and layouts with real complexity.
- **Which viewports matter?** Pick a desktop/tablet/mobile matrix driven by real analytics data rather than trying to cover every possible width.

### What moves between runs
- **What's non-deterministic?** Dates, timestamps, user-generated content, analytics identifiers, randomized content, ads, and avatars all need masking or freezing before capture.
- **Are there animations or transitions in play?** Left unhandled, they get captured mid-frame and generate false failures.
- **Do external resources vary?** Fonts, CDN-hosted images, and third-party embeds can render differently run to run.

---

## Principles to Work From

### 1. Visual coverage catches what behavioral assertions can't
A functional test checks behavior — "submitting the form shows a success message." A visual test checks appearance — "that message is green, sits in the right place, and doesn't overlap the form." Neither substitutes for the other; run both.

### 2. The real difficulty is baseline upkeep, not capture
Snapping a screenshot is trivial. What's hard is the ongoing work: refreshing baselines after intentional design changes, reviewing diffs, and getting a team to agree on approvals. Put effort into that review workflow from the start.

### 3. Non-deterministic content is your main source of noise
Anything that shifts between runs — timestamps, avatars, ads, random identifiers — produces pixel differences with no real regression behind them. Mask or freeze it aggressively; a suite where 1 in 10 failures is noise will be ignored within weeks. Hosted AI triage (Percy's Visual Review Agent, Chromatic's AI review) now filters a good chunk of this automatically, but it supplements masking/freezing rather than replacing it.

### 4. Thresholds get dialed in over time, not set once
There's no universal diff threshold — it depends on the component, the rendering engine, and what "visually different" means in context. Begin with zero tolerance, watch where false positives crop up, and loosen thresholds selectively per component, noting the reasoning each time.

### 5. A screenshot is evidence, not a verdict
The image itself is what proves a diff is real, so it needs to be stored, versioned, and easy to pull up during review. A failed test that only reports "visual diff detected" with no image attached is worthless — always publish expected/actual/diff images as CI artifacts.

---

## Playwright Visual Comparisons

`toHaveScreenshot` and `toMatchSnapshot`, both built into Playwright, give you visual regression coverage with no third-party service involved.

### A minimal screenshot comparison

```typescript
import { test, expect } from '@playwright/test';

test('dashboard matches baseline', async ({ page }) => {
  await page.goto('/dashboard');
  // Wait for data to load before capturing — never waitForTimeout
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
  await expect(page.getByTestId('chart-container')).toBeVisible();

  await expect(page).toHaveScreenshot('dashboard.png', { animations: 'disabled' });
});
```

The first execution establishes the baseline; every run after that compares against it and fails once the pixel difference crosses the configured threshold.

### Tuning the comparison

```typescript
await expect(page).toHaveScreenshot('dashboard.png', {
  maxDiffPixels: 100,          // Allow up to 100 pixels to differ
  // OR
  maxDiffPixelRatio: 0.01,     // Allow up to 1% of pixels to differ
  threshold: 0.2,              // Per-pixel color difference tolerance (0-1, YIQ space)
  animations: 'disabled',      // Freeze CSS animations and transitions
  caret: 'hide',               // Hide blinking cursor
  stylePath: './screenshot.css', // Inject a stylesheet at capture to hide dynamic chrome
  timeout: 15000,              // Wait up to 15s for a stable screenshot
});
```

`pixelmatch` (YIQ color space) is the comparator Playwright uses by default. The levers worth knowing are `comparator: 'pixelmatch'` alongside `threshold`/`maxDiffPixel*`; there's no stable perceptual-color mode key to reach for, so leave `mode:` alone — perceptual SSIM only exists as an internal, experimental underscore API, not something to depend on.

**Picking a threshold for the situation:**

| Option | Fits when |
|--------|----------|
| `maxDiffPixels: 0` | The component needs to be pixel-perfect (icons, logos, design-system atoms) |
| `maxDiffPixels: 50-100` | It's a full-page layout with minor antialiasing drift |
| `maxDiffPixelRatio: 0.01` | Full-page shots where the raw pixel count shifts with viewport size |
| `threshold: 0.2` | Cross-browser runs where color rendering isn't identical between engines |

### Visual settings in playwright.config.ts

```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  expect: {
    toHaveScreenshot: {
      comparator: 'pixelmatch',    // Default comparator (YIQ color space)
      maxDiffPixelRatio: 0.005,    // Global default: 0.5% tolerance
      animations: 'disabled',
      caret: 'hide',
    },
    toMatchSnapshot: {
      maxDiffPixelRatio: 0.005,
    },
  },
  projects: [
    {
      name: 'visual-desktop',
      use: { viewport: { width: 1280, height: 720 }, colorScheme: 'light' },
      testMatch: /.*visual.*\.spec\.ts/,
    },
    {
      name: 'visual-mobile',
      use: { viewport: { width: 375, height: 667 }, colorScheme: 'light', isMobile: true },
      testMatch: /.*visual.*\.spec\.ts/,
    },
  ],
});
```

### Masking & freezing dynamic content

Two tactics that complement each other: masking blanks out specific elements, while `stylePath`-driven freezing eliminates noise coming from time and animation.

```typescript
test('profile page visual test', async ({ page }) => {
  await page.goto('/profile');
  await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible();

  await expect(page).toHaveScreenshot('profile.png', {
    mask: [
      page.getByTestId('user-avatar'),       // User-specific image
      page.getByTestId('last-login-time'),    // Timestamp
      page.getByTestId('activity-feed'),      // Dynamic content
    ],
    maskColor: '#FF00FF',                      // Visible mask color for debugging
  });
});
```

When the target is cursors, animations, or bits of dynamic chrome, reach for `stylePath` (a stylesheet injected only at capture time) instead of per-element masks — it's declarative and keeps working even as the DOM changes. For timestamps and live data specifically, pin the clock via **`page.clock.setFixedTime`** (freezes it completely, which is what you want for deterministic screenshots; `page.clock.install` is the alternative when you need it to tick forward from a seed value) and pair that with `page.route` + `route.fulfill` to stub the API responses.

The full frozen-data recipe — clock plus route stubbing plus font-abort plus `getAnimations().finish()` — along with the `stylePath` example and component-state screenshots, all live in `references/recipes.md`.

### Refreshing baselines

```bash
# Update all baselines (when design intentionally changes)
npx playwright test --update-snapshots

# Update baselines for specific tests only
npx playwright test visual-dashboard --update-snapshots

# Review what changed before committing
git diff --stat                 # See which baseline files changed
npx playwright show-report      # Visually review expected/actual/diff for each
```

**The update sequence, in order:**

1. The design change gets implemented.
2. Visual tests are run and fail, showing the expected diffs.
3. Each diff gets reviewed in `show-report` — was this intentional?
4. If yes, baselines are refreshed with `npx playwright test --update-snapshots`.
5. The updated baseline images are committed with a message pointing to the design change.
6. PR reviewers confirm the new baseline images actually look right, rather than just glancing at the file diff.

### Testing components and responsive layouts

Prefer capturing the component itself (say, `getByRole('table')`) over the whole page — it's more focused and less prone to flaking. Drive each state — empty, error, normal — by stubbing the relevant API call per test. To cover multiple viewports, either loop over a `VISUAL_VIEWPORTS` array (mobile/tablet/desktop, each with its own `isMobile` flag) or set up a separate Playwright project per viewport. Both the component-state pattern and the responsive loop are written out in `references/recipes.md`.

---

## Dedicated Visual Testing Tools

These make sense once you want a hosted review/approval UI, a cross-browser rendering farm, historical trend tracking, or AI-assisted diff triage, and you're comfortable with artifacts living off-repo under a subscription.

| Tool | Fits best when | How it integrates | Standout feature |
|------|-----------|-------------|-------------|
| **Chromatic** | The project already uses Storybook | Every story becomes a visual test | Review/approval UI, cross-browser rendering, TurboSnap plus AI triage |
| **Percy** | No Storybook, but multi-browser coverage is needed | SDK integration, framework-agnostic | Multi-width captures, CSS overrides, an AI Visual Review Agent that filters out roughly 40% of false positives on its own, BrowserStack Test Observability |
| **Argos CI** | Open source is preferred and budget is tight | Playwright reporter | Self-hostable tier alongside a generous free cloud tier |

**Why AI triage matters heading into 2026:** Percy's Visual Review Agent and Chromatic's AI triage now auto-classify most diffs as either noise or genuine change, which is a real dent in review fatigue. It's the strongest argument for paying for a hosted tool instead of sticking with built-in baselines — though it lowers the need for masking and freezing dynamic content, it doesn't eliminate it.

> **Skip this one:** Lost Pixel's repo was archived (read-only) on 22 April 2026. Go with Argos, Chromatic, or Playwright's own `toHaveScreenshot` instead.

The Chromatic GitHub Action, Percy's `percySnapshot`, Argos's `argosScreenshot`, and the Storybook-without-Chromatic approach are all written out in `references/recipes.md`.

---

## Baseline Management

### Storing baselines in git, LFS, and per-platform tagging

Playwright keeps baselines next to the test files that produce them, and tags them per platform since rendering isn't identical across operating systems:

```
e2e/tests/visual/
  dashboard.visual.spec.ts
  dashboard.visual.spec.ts-snapshots/
    dashboard-chromium-linux.png     # Platform-specific baselines
    dashboard-chromium-darwin.png
    dashboard-firefox-linux.png
```

**What you gain:** version history alongside the code, visibility in PR review, offline availability. **What it costs:** the repo grows, and large PNGs weigh down git history over time.

**Git LFS** keeps that bloat in check; pair it with `snapshotPathTemplate` if you want to customize the directory layout:

```
# .gitattributes
*.png filter=lfs diff=lfs merge=lfs -text
```

```typescript
// playwright.config.ts
export default defineConfig({
  snapshotPathTemplate: '{testDir}/__snapshots__/{testFilePath}/{arg}-{projectName}{ext}',
});
```

Since baselines carry a platform tag, generate them inside the **exact Docker image CI runs against** so they line up with the CI rendering environment — a baseline captured on someone's laptop should never be committed. The Docker CI job (`mcr.microsoft.com/playwright:v1.60.0-noble`, kept in sync with your `@playwright/test` version) is in `references/recipes.md`.

### The review/approval loop

1. CI flags a visual diff and uploads the expected/actual/diff images as artifacts.
2. A PR reviewer inspects them in `show-report` or the hosted tool's UI.
3. If the change is intentional, baselines get refreshed (`--update-snapshots`) and re-committed.
4. If it's an unintentional regression, the code gets fixed and tests re-run.

---

## Pitfalls to Avoid

### 1. Capturing full pages with nothing masked
Screenshotting an entire page while leaving timestamps, avatars, and live data unmasked guarantees a diff every single run, and the team stops trusting the suite within weeks. Mask every dynamic region and freeze anything time-dependent, without exception.

### 2. Not uploading artifacts from CI
If a visual test fails and no screenshot artifacts were uploaded, there's nothing to inspect — just a forced local repro that might not even render the same way. Always publish the screenshots, diffs, and report as CI artifacts.

### 3. Rubber-stamping baseline updates
Running `--update-snapshots` and committing without actually reviewing what changed bakes real regressions straight into the baseline, where they become invisible going forward. Every baseline update deserves a look at the before/after images, not just a glance at the file diff.

### 4. Pointing visual tests at inherently unstable components
Components that are supposed to change — A/B test variants, personalized content, banners on rotation — will fail constantly for reasons that have nothing to do with regressions. Either exclude them from visual coverage or stub their content to something fixed.

### 5. Demanding pixel perfection on full-page shots
Setting `maxDiffPixels: 0` on a full page means ordinary sub-pixel rendering shifts from a browser, OS, or font update will fail the test. Save zero tolerance for small, critical components like logos and icons, and use something like `maxDiffPixelRatio: 0.005` for full pages.

### 6. Letting the rendering environment vary
Expecting baselines captured on assorted developer machines to match each other doesn't work — font rendering, antialiasing, and scaling all shift across platforms. Generate and run baselines inside one consistent CI Docker environment.

### 7. Ignoring animation state at capture time
If animations aren't disabled, transitions get captured mid-frame and produce diffs that look random. Use `animations: 'disabled'`, zero out durations through `stylePath`, or call `getAnimations().finish()` right before capturing.

---

## Confirming It Works

Before calling this done, verify baselines actually generate and the comparator runs, starting small:

```bash
npx playwright test --grep @visual          # baselines generate (first run) / compare (later)
npx playwright test --grep @visual --update-snapshots  # regenerate intentionally
npx playwright show-report                  # diff artifacts (expected/actual/diff) render
git check-attr filter -- "e2e/**/*.png"     # prints "filter: lfs" if LFS is wired
```

If the first run writes out `*-snapshots/*.png` cleanly and a second run then passes against those files, the pipeline is working end to end.

---

## Checklist Before Calling This Finished

- Baseline screenshots were captured inside a consistent CI Docker environment — not on someone's laptop — and are committed.
- `playwright.config.ts` has a global `maxDiffPixelRatio` set, and at least one icon/logo test overrides it down to `maxDiffPixels: 0`.
- All dynamic content (timestamps, avatars, live API data) is masked or frozen before capture, via `mask`, `stylePath`, or clock/route stubbing.
- The CI pipeline blocks merges once a visual diff exceeds the configured threshold.
- Baselines are tracked through Git LFS (`.gitattributes` includes `*.png filter=lfs`), or an off-repo hosted tool is used instead, so the repo doesn't bloat.
- A review workflow exists on paper: who reviews diffs, how baseline updates get triggered for intentional changes, and that PR reviewers actually sign off on the baseline images themselves.

## What's in `references/`

- **recipes.md** — covers frozen-data capture (clock plus route plus font-abort), `stylePath`-based masking, component-state screenshots, the responsive-viewport loop, the Chromatic/Percy/Argos snippets, running Storybook without Chromatic, and the Docker CI job.

## Skills Nearby

- **playwright-automation** — the underlying foundation for Playwright-based visual tests; its Page Object Model, fixtures, and test structure all apply here too.
- **ci-cd-integration** — for pipeline configuration: running visual tests, uploading artifacts, wiring up review workflows.
- **cross-browser-testing** — reach for this instead when the goal is a rendering matrix across browsers rather than diffing baselines for a single render; viewport and project config overlap between the two.
- **selector-drift-recovery** — use this instead when a redesign has broken many baselines at once and what's needed is bulk regeneration, not per-test visual diffing.
- **qa-project-context** — where the visually-critical pages and known dynamic content get documented.
