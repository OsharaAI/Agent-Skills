# Device Farm Integration

Capability objects and CI matrix config for cloud device farms. Build-vs-buy reasoning and the tiering strategy itself live in `SKILL.md`.

## BrowserStack App Automate

```typescript
// browserstack.config.ts
export const bsCapabilities = {
  'bstack:options': {
    userName: process.env.BROWSERSTACK_USERNAME,
    accessKey: process.env.BROWSERSTACK_ACCESS_KEY,
    projectName: 'MyApp Mobile Tests',
    buildName: `build-${process.env.CI_BUILD_NUMBER}`,
    sessionName: 'Login Flow',
    debug: true,
    networkLogs: true,
    appiumVersion: '3.x', // pin to a current 3.x stable the farm advertises
  },
  platformName: 'Android',
  'appium:deviceName': 'Samsung Galaxy S24',
  'appium:platformVersion': '14.0',
  'appium:app': process.env.BROWSERSTACK_APP_URL, // app_url returned by the upload below
};
```

Upload the binary first, then feed the `app_url` it returns (`bs://...`) into `BROWSERSTACK_APP_URL`:

```bash
curl -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -X POST "https://api-cloud.browserstack.com/app-automate/upload" \
  -F "file=@./build/app-debug.apk"
# → { "app_url": "bs://<hashed-id>" }   # export as BROWSERSTACK_APP_URL
```

## Sauce Labs

```typescript
export const sauceCapabilities = {
  platformName: 'iOS',
  'appium:deviceName': 'iPhone 15 Pro',
  'appium:platformVersion': '17',
  'appium:app': 'storage:filename=MyApp.ipa',
  'sauce:options': {
    name: 'Login Flow',
    build: `build-${process.env.CI_BUILD_NUMBER}`,
    appiumVersion: '3.x', // pin to a current 3.x stable Sauce advertises
  },
};
```

## Device Matrix Strategy

```yaml
# GitHub Actions matrix for device farm
strategy:
  fail-fast: false
  matrix:
    include:
      # P0: Top devices from analytics
      - platform: android
        device: Samsung Galaxy S24
        os_version: "14"
      - platform: ios
        device: iPhone 15 Pro
        os_version: "17"
      # P1: Previous generation
      - platform: android
        device: Google Pixel 8
        os_version: "14"
      - platform: ios
        device: iPhone 14
        os_version: "16"
      # P2: Oldest supported
      - platform: android
        device: Samsung Galaxy A54
        os_version: "13"
      - platform: ios
        device: iPhone SE 3rd Gen
        os_version: "16"
```

Derive the matrix from real usage analytics rather than guesswork. A common split: 60% of test runs on P0 devices, 30% on P1, and the remaining 10% on P2.
</content>
