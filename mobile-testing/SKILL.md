---
name: mobile-testing
description: >-
  Test native, React Native, hybrid, and Flutter mobile apps with Appium 3.x, Detox,
  Maestro, and Patrol. Covers device farm setup (BrowserStack, Sauce Labs), gesture
  simulation, deep link and cold-start testing, push notifications, biometric (Face ID)
  auth, offline/poor-network simulation, and iOS/Android permission dialog handling.
  Use when: "mobile test," "Appium," "Detox," "Maestro," "Patrol," "Flutter test,"
  "iOS test," "Android test," "device farm," "deep link," "biometric," "Face ID,"
  "permission dialog," "React Native test."
  Not for: device/browser matrix strategy in the abstract — use cross-browser-testing;
  app startup/memory/battery profiling depth — use performance-testing; mobile screenshot
  diffing — use visual-testing.
  Related: ci-cd-integration, cross-browser-testing, performance-testing, test-data-management, test-reliability.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: automation
---

<objective>
Picture a login spec that sails through on the iOS simulator and then stalls indefinitely on a physical handset, because a location-permission prompt nobody accounted for is sitting over the UI. That is exactly the class of failure this skill exists to head off. It hands you a working test suite spanning native, React Native, hybrid, and Flutter targets — matching each app type to the right tooling, splitting real hardware from emulated devices where it matters, and giving first-class treatment to the things browser-based test frameworks simply cannot reach: deep links, push delivery, biometric prompts, connectivity loss, and permission dialogs.
</objective>

---

## Quick Route

| Situation | Go to |
| --- | --- |
| Picking a framework for an app type | [Framework Decision](#framework-decision) |
| Native/hybrid Appium setup + selectors + gestures | [Appium 3.x](#appium-3x) → `references/appium-patterns.md` |
| React Native suite | [Detox](#detox-for-react-native) → `references/detox-and-maestro.md` |
| Low-friction cross-platform YAML | [Maestro](#maestro-cross-platform-yaml) → `references/detox-and-maestro.md` |
| Cloud device matrix (P0/P1/P2) | [Device Farm](#device-farm-integration) → `references/device-farm.md` |
| Deep links, push, biometrics, offline, permissions | [Mobile-Specific Patterns](#mobile-specific-testing-patterns) → `references/mobile-patterns.md` |

---

## Discovery Questions

First check whether `.agents/qa-project-context.md` exists at the project root — if so, pull answers from it and only ask what it leaves open.

1. **App type:** Native iOS/Android, React Native, Flutter, or a hybrid shell (Cordova/Capacitor)? This drives the framework pick — see [Framework Decision](#framework-decision).
2. **Real hardware or simulated devices?** Physical devices belong in release validation and performance checks; emulators/simulators are for fast local iteration. Most teams end up needing both.
3. **Which device farm?** BrowserStack App Automate, Sauce Labs, AWS Device Farm, or something self-hosted? Budget and how well it plugs into CI usually decide this.
4. **OS version floor:** What's the minimum supported iOS/Android version? Pull real usage analytics before locking the matrix — don't default to whatever hardware just shipped.
5. **CI setup today:** Do mobile tests currently run on developer machines, CI-hosted emulators, or a cloud farm?
6. **Build distribution:** TestFlight, Firebase App Distribution, or raw APK/IPA handoff? This shapes how the binary reaches the farm.

---

## Core Principles

1. **Reserve real hardware for release gates; use emulators for everyday speed.** Simulated devices can't reproduce real touch latency, GPS drift, camera behavior, or actual push-notification timing and battery draw. Keep emulators for dev loops and PR gating; save physical device farms for nightly/release runs.

2. **Gestures don't transfer across frameworks.** Appium's W3C Actions API, Detox's device-level calls, and each platform's native gesture recognizer all implement swipe/pinch/long-press differently. Never assume a gesture snippet written for one framework works in another.

3. **Deep links and push are mobile-only territory.** No web testing tool can exercise them. Build dedicated coverage for both rather than treating them as edge cases.

4. **Permission prompts will break naive assumptions.** iOS and Android runtime permissions work differently from each other. Without explicit handling for camera, location, contacts, and notifications, a test just hangs on a dialog it has no way to dismiss.

5. **Connectivity state is a bigger deal on mobile than on web.** Real users bounce between WiFi, cellular tiers, and dead zones constantly. Cover degraded and zero connectivity, not only the happy-path WiFi case.

6. **Guard anything OS-specific.** A shell invocation, selector, or device call available on Android may simply not exist on iOS, or vice versa. Check `platformName` before firing platform-only commands, otherwise the test quietly fails on the other OS without telling you why.

---

## Framework Decision

| App type | Primary choice | Why |
| --- | --- | --- |
| Native iOS/Android, hybrid | **Appium 3.x** | Driver-based, mature ecosystem, deepest native + gesture coverage |
| React Native | **Detox** | Gray-box, synchronizes with the RN bridge, fastest feedback, least flake |
| Cross-platform, mixed-skill team | **Maestro** | Declarative YAML, native AI commands, lowest authoring friction |
| Flutter | **Patrol 4.x** | Flutter-native integration testing; 4.0 added web support (via Playwright) and richer native interaction APIs |

---

## Appium 3.x

Appium 3.x is the current stable line as of 2026, and it keeps the plugin/driver split that 2.0 introduced — the server itself stays thin, and platform automation lives in the drivers. Moving off 2.x is mostly a Node upgrade plus dependency housekeeping; most of your capability config carries forward unchanged, but the 3.x line did retire a batch of long-deprecated commands and reworked plugin/driver wiring, so skim the 3.x migration notes for anything you rely on that got removed.

**Selector priority:** Accessibility ID > platform-specific selector (iOS class chain / Android UIAutomator) > XPath (last resort — slow, brittle).

**Guard anything platform-only.** Check `platformName` before running a platform-restricted shell command, selector strategy, or device API:

```typescript
if (driver.capabilities.platformName === 'Android') {
  // UIAutomator selectors, `mobile: shell` network toggles
} else {
  // iOS class chain / predicate selectors, `mobile: alert`, device-farm network profiles
}
```

`references/appium-patterns.md` covers install/driver setup, W3C Android/iOS capability objects, the four ways to locate elements, and the complete gesture toolkit (scroll, swipe, pinch, long-press, double-tap).

---

## Detox for React Native

Detox takes a gray-box approach: it hooks into the React Native bridge and waits out in-flight animations, network calls, and timers before it acts, which removes the bulk of timing-related flake you'd otherwise fight.

> Supported RN range is 0.77–0.84, New Architecture included. Default to `by.id`/`by.text` matchers; only fall back to `by.type()` when you need to loosen an overly strict class-based assertion.

**Ordering rule for biometrics:** call `device.setBiometricEnrollment(true)` *before* `device.matchBiometric()`. Skip the enrollment step and the match call silently does nothing — the auth flow never progresses.

**Push is effectively iOS-only through `sendUserNotification`.** Detox's Android push support is limited and doesn't behave the same way — for Android, route push through FCM plus the notification shade (the Appium-based approach) rather than expecting feature parity.

`references/detox-and-maestro.md` has the full `.detoxrc.js` setup, sample login-flow specs, the device API surface (biometrics, shake, orientation, location, deep links, notifications), and CI build/test invocations.

---

## Maestro (Cross-Platform YAML)

Maestro CLI 2.5.x (April 2026) offers the least setup overhead for cross-platform mobile e2e work — flows are plain declarative YAML, commands like `assertVisible: 'login button'` work via native AI assistance with no selectors required, and the same flow runs against simulators, physical devices, or Maestro Cloud. It's a strong fit for teams that don't want to carry Appium's Java/JS toolchain or Detox's RN-only scope.

```bash
# macOS (preferred — lower friction, brew-managed):
brew tap mobile-dev-inc/tap && brew install mobile-dev-inc/tap/maestro
# Or the cross-platform curl one-liner:
curl -Ls "https://get.maestro.mobile.dev" | bash
```

Reach for Maestro when: the suite spans platforms, the team has mixed skill levels, or fast iteration matters most. Skip it when: you need deep native gesture/biometric coverage (Appium or Detox handle that better) or fine-grained programmatic control.

`references/detox-and-maestro.md` walks through an annotated login-flow YAML that injects a password via `${MAESTRO_TEST_PASSWORD}`.

---

## Device Farm Integration

Build the device matrix off analytics, not off whatever device just launched. A common tiering split: 60% of runs on P0 devices, 30% on P1, 10% on P2. Builds get uploaded to the farm ahead of time and referenced from capabilities (`app` URL or `storage:filename`).

`references/device-farm.md` has the BrowserStack and Sauce Labs capability blocks, the authenticated upload `curl` call, and a GitHub Actions matrix spanning P0/P1/P2 across both platforms.

---

## Mobile-Specific Testing Patterns

Web frameworks have no way to reach these scenarios — treat every one of them as a first-class test, not an afterthought.

- **Deep links** — cold start (kill the app, then deep-link into it), authenticated redirect flows, and in-app navigation while running.
- **Push notifications** — Detox's `sendUserNotification` covers iOS; Android goes through Appium plus FCM test endpoints or the notification shade.
- **Offline / degraded network** — platform-guarded: Android's `mobile: shell` airplane-mode toggle, device-farm network profiles, and notes on iOS conditioner / Detox proxy approaches.
- **Permission dialogs** — Android's `autoGrantPermissions`, plus explicit `mobile: alert` (`action: accept`/`dismiss`) and `-ios predicate string` handling on iOS.
- **Biometrics** — Detox's `setBiometricEnrollment(true)` followed by `matchBiometric()` (enrollment always comes first).
- **App lifecycle** — backgrounding/foregrounding, cold starts, and fresh installs versus resumed sessions.

`references/mobile-patterns.md` has the runnable code, including the platform-guarded airplane-mode snippet and the iOS/Android permission-handling split.

---

## Anti-Patterns

**Relying on emulators for everything.** They don't reproduce touch latency, camera quirks, GPS drift, or push timing. Keep them for dev velocity and run release suites on real devices through a farm.

**Baking device names into tests.** `await driver.$('Samsung Galaxy S24 - Home')` breaks the moment the device pool changes. Stick to accessibility IDs and platform-neutral selectors.

**Firing platform-only commands with no guard.** `cmd connectivity airplane-mode` only exists on newer Android builds and nowhere on iOS; running it unguarded just fails quietly on the other OS. Check `platformName` first (see [Appium 3.x](#appium-3x)).

**Assuming permissions are already granted.** Tests built on that assumption break on fresh installs or when you're specifically testing a denial path. Handle each platform's permission model explicitly.

**Calling `matchBiometric()` without enrolling first.** No prior `setBiometricEnrollment(true)` means the match call is a no-op — auth never completes, and the test times out stuck on the login screen.

**Only ever testing portrait.** Plenty of apps break in landscape, especially on tablets. Cover both orientations for critical flows.

**Skipping offline scenarios entirely.** Real users drop connectivity all the time. Either demonstrate the app mishandles it (and fix it) or verify it degrades gracefully.

**Falling back to `sleep()` for synchronization.** Detox already auto-waits; Appium gives you implicit/explicit waits. Sleep-based timing is both slower and flakier than either.

**Overlooking binary size and cold-start time.** A 200MB app with a 6-second launch is a genuine UX problem. Add non-functional checks for both. (For deeper startup/memory/battery analysis, hand off to `performance-testing`.)

---

## Verification

Run the smallest applicable check for the framework(s) in play — each command should exit 0 and produce the output shown before you consider the suite finished.

```bash
# Appium: drivers installed and server reachable
appium driver list --installed        # lists uiautomator2 and/or xcuitest
appium --version                       # prints the 3.x version

# Detox: one config builds and a smoke spec passes
detox test --configuration ios.sim.debug --headless   # green run on the iOS simulator

# Maestro: a single flow runs end-to-end
maestro test flows/login.yaml          # prints "Flow Passed"
```

---

## Done When

- Device matrix defined and committed (e.g. `device-matrix.md` or a CI matrix block): real devices + emulators per platform, tiered P0/P1/P2 from analytics.
- Test suite runs against both iOS and Android from a single CI configuration (matrix strategy or paired jobs).
- A gesture test (swipe/scroll/long-press) and a deep-link cold-start test (terminate → deep-link → assert target screen) exist as committed test files — list their paths.
- Push notification coverage is either a committed test file path OR a tracked deferral ticket ID (e.g. "JIRA-1234: deferred until FCM test endpoint available") — not a bare code comment.
- `appium driver list --installed` / `detox test --configuration ios.sim.debug` / `maestro test flows/login.yaml` (whichever applies) exits 0 locally.
- CI runs tests on at least one emulator per platform (iOS simulator + Android emulator) on every PR, with real-device-farm runs gated to nightly or release branches.

## Reference Files (in `references/`)

- **appium-patterns.md** — Appium 3.x install, W3C capabilities, element-location strategies, gesture simulation, and the platform-guard pattern.
- **detox-and-maestro.md** — Detox `.detoxrc.js` config, test patterns, device APIs (biometric ordering, push iOS-only note), CI commands; plus Maestro install (brew + curl) and YAML flow.
- **device-farm.md** — BrowserStack and Sauce Labs capabilities, authenticated app-upload curl, and the GitHub Actions P0/P1/P2 device matrix.
- **mobile-patterns.md** — Runnable code for deep links, push, platform-guarded network simulation, iOS/Android permission dialogs, and app lifecycle.

## Related Skills

- **ci-cd-integration** — Pipeline configuration for mobile test execution, artifact management, device-farm CI connectors.
- **cross-browser-testing** — Device-matrix design borrows the browser-matrix methodology; go there for matrix strategy in the abstract, here for the mobile execution.
- **performance-testing** — Mobile non-functional depth: app startup time, memory usage, battery drain.
- **visual-testing** — Screenshot/pixel-diff regression, including mobile viewport captures.
- **test-data-management** — Seed data strategies for mobile apps; backend state setup via API.
- **test-reliability** — Runtime flaky-test healing for mobile timing, device state, and network conditions.
</content>
