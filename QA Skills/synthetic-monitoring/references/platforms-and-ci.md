# Platforms and CI Scheduling

Configuration for scheduling synthetic probe runs. Platform comparisons and guidance on choosing between them live in `SKILL.md`.

## Custom implementation: Playwright + GitHub Actions

```yaml
# .github/workflows/synthetic-monitoring.yml
name: Synthetic Monitoring
on:
  schedule:
    - cron: '*/5 * * * *'  # Every 5 minutes
  workflow_dispatch: {}

jobs:
  synthetic-probes:
    runs-on: ubuntu-latest
    timeout-minutes: 3
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22 # current LTS as of May 2026 — bump as Node LTS rolls forward
      - run: npm ci
      - run: npx playwright install chromium --with-deps

      - name: Run synthetic probes
        env:
          PRODUCTION_URL: ${{ secrets.PRODUCTION_URL }}
          SYNTHETIC_USER_EMAIL: ${{ secrets.SYNTHETIC_USER_EMAIL }}
          SYNTHETIC_USER_PASSWORD: ${{ secrets.SYNTHETIC_USER_PASSWORD }}
          SYNTHETIC_API_KEY: ${{ secrets.SYNTHETIC_API_KEY }}
        run: npx playwright test probes/ --reporter=json --reporter=list

      - name: Report results to monitoring
        if: always()
        run: |
          node scripts/report-synthetic-results.js \
            --results=test-results/results.json \
            --webhook=${{ secrets.MONITORING_WEBHOOK }}
```

## Checkly-based implementation

```typescript
// checkly.config.ts
import { defineConfig } from 'checkly';

export default defineConfig({
  projectName: 'Production Monitoring',
  logicalId: 'prod-monitoring',
  checks: {
    frequency: 5,          // Every 5 minutes
    locations: ['us-east-1', 'eu-west-1', 'ap-southeast-1'],
    // Use the latest stable Checkly runtime — see https://www.checklyhq.com/docs/runtimes/
    // (e.g. 'next' for the rolling stable; pin a dated runtime for reproducibility)
    runtimeId: '2025.04',
    browserChecks: {
      testMatch: 'probes/**/*.check.ts',
    },
  },
  cli: {
    runLocation: 'us-east-1',
  },
});
```

## Alert routing configuration

```yaml
# alerting-rules.yaml
routes:
  - match:
      severity: critical
      probe: [login, checkout, api-health]
    receivers: [pagerduty-oncall, slack-incidents]
    repeat_interval: 5m

  - match:
      severity: warning
      probe: [search, third-party]
    receivers: [slack-monitoring]
    repeat_interval: 30m

  - match:
      severity: info
    receivers: [slack-monitoring]
    repeat_interval: 4h
```

These routes only match once a probe result is tagged with `severity` and `probe` labels. Set those labels when results get reported (e.g. in `report-synthetic-results.js`): map the probe's file name to `probe`, and derive `severity` from the consecutive-failure count (1 → info, 2 → warning, 2+ across regions → critical) before the payload is posted to the alert webhook. Skip that tagging step and none of the routes above will ever trigger.

## Probe runbook template

Every probe needs a linked runbook — that's the `{link_to_runbook}` field in the alert template — kept to six lines per probe. Here's what that looks like for the payment-integration probe:

```markdown
# Runbook: checkout / payment-integration probe
- What the probe tests: sandbox checkout — cart → Stripe test card → order confirmation page.
- First check: status.stripe.com; then recent deploys to checkout-service (last 60 min); then payment error rate in APM.
- Manual verification (reproduce): log in as synthetic@example.com, add item, pay with test card 4242…, confirm order page.
- Escalate: page #payments-oncall (PagerDuty) if Stripe is green AND a recent deploy correlates.
- Dashboard: https://grafana.example.com/d/checkout-synthetic
- Runbook owner: payments team — review quarterly.
```

Order the "first checks" line by likelihood — third-party status first, then recent deploys, then app telemetry — so the on-call engineer can start investigating from that line alone.
