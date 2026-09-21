# Visual Testing Recipes

Working Playwright examples for the patterns referenced from SKILL.md. Everything below
assumes `@playwright/test` 1.60 or newer.

## Making dynamic content deterministic before capture

The recipe: freeze the clock, stub the API response, and block font requests, so the
resulting render is identical byte-for-byte on every run. `page.clock.setFixedTime` holds
time completely still, which is what you want for screenshots; reach for `page.clock.install`
only if the page genuinely needs to observe the clock advancing from a starting point.

```typescript
test('dashboard with frozen data', async ({ page }) => {
  // Pin time dead-still — eliminates timestamp differences. setFixedTime does not tick.
  await page.clock.setFixedTime(new Date('2026-01-15T10:00:00Z'));

  // Stub API to return deterministic data
  await page.route('**/api/dashboard', async (route) => {
    await route.fulfill({
      json: {
        stats: { users: 1234, revenue: 56789 },
        chart: [10, 20, 30, 40, 50],
      },
    });
  });

  // Disable font loading to prevent FOUT (Flash of Unstyled Text)
  await page.route('**/*.woff2', (route) => route.abort());

  await page.goto('/dashboard');
  await expect(page.getByTestId('chart-container')).toBeVisible();

  // Force any in-flight animations to their end frame
  await page.evaluate(() => {
    document.getAnimations().forEach((a) => a.finish());
  });

  await expect(page).toHaveScreenshot('dashboard-frozen.png', {
    animations: 'disabled',
  });
});
```

## Using stylePath to hide dynamic regions (a cleaner alternative to mask)

`stylePath` loads a stylesheet that only applies at capture time. It's a declarative way to
hide cursors, animations, and other dynamic chrome without building per-element `mask:[]`
arrays — since 1.60 it's the preferred fix for animation and cursor noise specifically.
Fall back to `mask:[]` only for a specific element the stylesheet approach can't reach.

```typescript
// screenshot.css
// * { caret-color: transparent !important; }
// .live-clock, .activity-feed { visibility: hidden !important; }
// *, *::before, *::after { animation: none !important; transition: none !important; }

await expect(page).toHaveScreenshot('profile.png', {
  stylePath: './screenshot.css',
});
```

## Screenshotting a component across its different states

Target the component rather than the whole page, and stub the API to force each state.

```typescript
test('data table renders with normal data', async ({ page }) => {
  await page.goto('/admin/users');
  await expect(page.getByRole('table')).toBeVisible();
  const table = page.getByRole('table', { name: 'Users' });
  await expect(table).toHaveScreenshot('users-table.png');
});

test('empty state renders correctly', async ({ page }) => {
  await page.route('**/api/users', (route) => route.fulfill({ json: { users: [] } }));
  await page.goto('/admin/users');
  const emptyState = page.getByTestId('empty-state');
  await expect(emptyState).toHaveScreenshot('users-empty-state.png');
});

test('error state renders correctly', async ({ page }) => {
  await page.route('**/api/users', (route) => route.fulfill({ status: 500 }));
  await page.goto('/admin/users');
  const errorState = page.getByTestId('error-state');
  await expect(errorState).toHaveScreenshot('users-error-state.png');
});
```

## Testing responsively across viewports

Focus on the breakpoints where the layout actually changes rather than trying to cover
every conceivable width, and base the matrix on real analytics data.

```typescript
const VISUAL_VIEWPORTS = [
  { name: 'mobile', width: 375, height: 667, isMobile: true },
  { name: 'tablet', width: 768, height: 1024, isMobile: false },
  { name: 'desktop', width: 1280, height: 720, isMobile: false },
] as const;

for (const vp of VISUAL_VIEWPORTS) {
  test.describe(`Visual @ ${vp.name}`, () => {
    test.use({ viewport: { width: vp.width, height: vp.height }, isMobile: vp.isMobile });

    test('homepage layout', async ({ page }) => {
      await page.goto('/');
      await expect(page.getByRole('main')).toBeVisible();
      await expect(page).toHaveScreenshot(`homepage-${vp.name}.png`, {
        fullPage: true,
        animations: 'disabled',
      });
    });
  });
}
```

Alternatively, set up one Playwright project per viewport in `playwright.config.ts` (see
the "Visual settings in playwright.config.ts" section of SKILL.md) and let the test runner
fan the suite out across them.

## Snippets for the dedicated tools

### Chromatic (for Storybook)

```yaml
# GitHub Actions
- uses: chromaui/action@latest
  with:
    projectToken: ${{ secrets.CHROMATIC_PROJECT_TOKEN }}
    exitZeroOnChanges: true    # Changes go to review, not CI failure
    onlyChanged: true          # TurboSnap: only test stories affected by code changes
```

The flow: code gets pushed, CI captures the screenshots, reviewers approve or reject them in
the Chromatic UI, and the PR merges once approved.

### Testing Storybook stories without Chromatic

Chromatic isn't a requirement for visual-testing Storybook stories. `@playwright/test` can
point directly at the story iframe and capture it the same way it would any other page —
baselines stay in-repo and there's no SaaS bill:

```typescript
test('Button/Primary story', async ({ page }) => {
  await page.goto('/iframe.html?id=button--primary&viewMode=story');
  await expect(page.getByRole('button')).toBeVisible();
  await expect(page).toHaveScreenshot('button-primary.png');
});
```

For full coverage without writing a test per story, the Storybook test-runner can also
walk every story automatically.

### Percy (framework-agnostic)

```typescript
import { percySnapshot } from '@percy/playwright';

test('checkout page visual', async ({ page }) => {
  await page.goto('/checkout');
  await percySnapshot(page, 'Checkout Page', {
    widths: [375, 768, 1280],
    percyCSS: `.ad-banner { display: none !important; }`,
  });
});
// CI: npx percy exec -- npx playwright test --grep @visual
```

### Argos CI (the open-source option)

```typescript
import { argosScreenshot } from '@argos-ci/playwright';

test('pricing page visual', async ({ page }) => {
  await page.goto('/pricing');
  // Confirm preset names against argos-ci.com/docs/viewports before pinning them.
  await argosScreenshot(page, 'pricing-page', { viewports: ['iphone-x', 'macbook-16'] });
});
```

## Keeping per-platform baselines consistent in CI

Rendering isn't identical across operating systems, which is why Playwright tags baselines
like `*-chromium-linux.png`. Generating them inside the same Docker image CI uses keeps
them matched.

```yaml
jobs:
  visual-tests:
    runs-on: ubuntu-latest
    container:
      image: mcr.microsoft.com/playwright:v1.60.0-noble # match @playwright/test in package.json
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx playwright test --grep @visual
```
