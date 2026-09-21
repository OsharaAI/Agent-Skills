# Regression-Gating Tracking in CI

The gate walks through the user journeys, captures every beacon (using the fixture from `capture-fixture.md`), and compares what it captured against the tracking-plan baseline — **failing the build (non-zero exit)** the moment an event that used to fire stops firing, or a required param goes missing.

It belongs **pre-merge in PR CI**. It is not a manual GA4 DebugView check, not something that only runs against production traffic, and never a warning that still lets the build pass.

## Diffing against the baseline

The baseline is simply the set of events the tracking plan says each journey should produce. After capture, confirm every expected event showed up and satisfies its contract:

```ts
import { test, expect } from '../fixtures/analytics';
import { validateEvent } from '../tracking-plan/validate';
import plan from '../tracking-plan/tracking-plan.json';

const EXPECTED_ON_CHECKOUT = ['view_item', 'add_to_cart', 'begin_checkout', 'purchase'];

test('checkout journey emits every planned event with required params', async ({ page, beacons }) => {
  await runCheckoutJourney(page);
  await page.waitForLoadState('networkidle');

  for (const name of EXPECTED_ON_CHECKOUT) {
    const beacon = beacons.find(b => b.destination === 'ga4' && b.eventName === name);
    expect(beacon, `event "${name}" dropped — not captured during checkout`).toBeTruthy();

    const sp = new URLSearchParams(beacon!.params as Record<string, string>);
    const violations = validateEvent(plan, name, sp);
    expect(violations, `required params missing for "${name}": ${JSON.stringify(violations)}`).toEqual([]);
  }
});
```

A dropped event fails the `toBeTruthy()` check. A missing required param leaves `violations` non-empty, which fails too. Either way, Playwright exits non-zero and the job turns red.

## GitHub Actions workflow

```yaml
name: tracking-regression-gate
on: [pull_request]
jobs:
  tracking:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: npm ci
      - run: npx playwright install --with-deps chromium
      - name: Run tracking gate
        run: npx playwright test --project=tracking
        # non-zero exit on any dropped event / missing param fails the job
      - if: always()
        uses: actions/upload-artifact@v4
        with: { name: tracking-report, path: playwright-report/ }
```

## Putting failures in the job summary

Write out the missing/dropped findings to the step summary so the diff is visible without having to open the full report:

```ts
// in a custom reporter or afterAll
import fs from 'node:fs';
const summary = process.env.GITHUB_STEP_SUMMARY;
if (summary && violations.length) {
  fs.appendFileSync(summary, `## Tracking regressions\n` +
    violations.map(v => `- ${v.event}: ${v.problem} ${v.param ?? ''}`).join('\n') + '\n');
}
```

## What NOT to do

- **A manual GA4 DebugView check** — it's interactive rather than automated, so it never blocks a merge.
- **Production-only monitoring** — this only catches regressions after real users hit them; treat it as a complement (see `synthetic-monitoring`), never as the pre-merge gate itself.
- **Warn but pass** — a gate that can't fail is just decoration. The job needs to exit non-zero.

Confirm the gate actually works by deliberately breaking a tag (rename a param on a branch) and watching the build turn red.
