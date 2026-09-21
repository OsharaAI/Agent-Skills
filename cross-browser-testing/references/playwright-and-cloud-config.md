# Playwright and Cloud Platform Configuration — Code

The runnable setup for Playwright's built-in engines, branded channels, and the two cloud grids (BrowserStack, Sauce Labs). `SKILL.md` explains *when* to reach for each option; this file is the actual implementation.

## Playwright Built-in Browsers

Playwright bundles three engines out of the box, so basic cross-browser coverage needs nothing beyond a config file — no cloud platform required.

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  projects: [
    // P0: Desktop
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },

    // P0: Mobile
    { name: 'mobile-chrome', use: { ...devices['Pixel 7'] } },
    { name: 'mobile-safari', use: { ...devices['iPhone 15'] } },

    // P1: Desktop
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    // One Edge project only — drive installed Edge via the channel option.
    // The `channel: 'msedge'` snippet further down is the SAME idea, not an
    // additional project; do not declare two projects both named `edge`.
    { name: 'edge', use: { channel: 'msedge' } },

    // P2: Tablets
    { name: 'ipad', use: { ...devices['iPad Pro 11'] } },

    // Optional: real-Chrome rendering parity via the new Chromium headless mode (Playwright 1.49+)
    // Closer to production Chrome (extensions, codecs, fingerprinting) than headless-shell.
    { name: 'chromium-new-headless', use: { ...devices['Desktop Chrome'], channel: 'chromium' } },
  ],
});
```

## Browser Channels

Instead of its bundled engines, Playwright can also drive browsers already installed on the machine.
The snippets below are illustrative alternatives to the `edge` project shown above, not extra
projects to add on top — settle on a single declaration per branded browser so no two projects
end up sharing the name `edge`.

```typescript
// Use installed Chrome instead of bundled Chromium
{ name: 'chrome', use: { channel: 'chrome' } },

// Use installed Edge (same channel as the `edge` project above — declare it once)
{ name: 'edge', use: { channel: 'msedge' } },

// WebKit is always Playwright's bundled version (no channel option)
// Firefox is always Playwright's bundled version
```

## Running Specific Projects

```bash
# Run only Safari tests
npx playwright test --project=webkit

# Run only mobile tests
npx playwright test --project=mobile-chrome --project=mobile-safari

# Run P0 browsers in CI, all browsers nightly
npx playwright test --project=chromium --project=webkit --project=mobile-chrome --project=mobile-safari
```

## BrowserStack

BrowserStack's current recommendation is the `npx browserstack-node-sdk playwright test` runner
paired with a `browserstack.yml` capabilities file, plus a `client.playwrightVersion` capability
(used alongside `browserstack.playwrightVersion`) so the client side and the grid side of the
socket connection stay aligned. The raw `wsEndpoint`/CDP config shown below is still a valid direct
connection — reach for the SDK path when setting things up fresh. Either way, pin the version to
whatever `npx playwright --version` reports for `package.json`.

```typescript
// browserstack.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  use: {
    connectOptions: {
      wsEndpoint: `wss://cdp.browserstack.com/playwright?caps=${encodeURIComponent(JSON.stringify({
        browser: 'chrome',
        browser_version: 'latest',
        os: 'Windows',
        os_version: '11',
        'browserstack.username': process.env.BROWSERSTACK_USERNAME,
        'browserstack.accessKey': process.env.BROWSERSTACK_ACCESS_KEY,
        // Pin BOTH to your installed Playwright (e.g. 1.60.x) to avoid client/server socket mismatch.
        'browserstack.playwrightVersion': '1.60.0', // keep aligned with package.json
        'client.playwrightVersion': '1.60.0',       // SDK-recommended; mirrors the above
        build: `cross-browser-${process.env.CI_BUILD_NUMBER}`,
        name: 'Cross-browser test suite',
      }))}`,
    },
  },
});
```

## Sauce Labs

```typescript
// sauce.config.ts
export default defineConfig({
  use: {
    connectOptions: {
      wsEndpoint: `wss://ondemand.saucelabs.com/playwright?sauce:options=${encodeURIComponent(JSON.stringify({
        username: process.env.SAUCE_USERNAME,
        accessKey: process.env.SAUCE_ACCESS_KEY,
        browserName: 'chromium',
        browserVersion: 'latest',
        platformName: 'Windows 11',
        'sauce:build': `build-${process.env.CI_BUILD_NUMBER}`,
      }))}`,
    },
  },
});
```

## CI Matrix with Cloud Platforms

```yaml
# GitHub Actions: parallel cross-browser on BrowserStack
cross-browser:
  runs-on: ubuntu-latest
  strategy:
    fail-fast: false
    matrix:
      include:
        - browser: chrome
          os: Windows
          os_version: "11"
        - browser: safari
          os: OS X
          os_version: Sonoma
        - browser: firefox
          os: Windows
          os_version: "11"
        - browser: edge
          os: Windows
          os_version: "11"
  steps:
    - uses: actions/checkout@v4
    - run: npm ci
    - run: npx playwright test
      env:
        BROWSER: ${{ matrix.browser }}
        BROWSERSTACK_USERNAME: ${{ secrets.BROWSERSTACK_USERNAME }}
        BROWSERSTACK_ACCESS_KEY: ${{ secrets.BROWSERSTACK_ACCESS_KEY }}
```
</content>
