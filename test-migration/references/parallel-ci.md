# Running Old and New Suites Side by Side in CI

The complete CI setup for exercising the legacy and target frameworks together during a migration. The reasoning for it — when the old suite should block vs. not, and what a sample cutover timeline looks like — lives in `SKILL.md`; this file is just the configuration.

## GitHub Actions: two suites, one pipeline

The legacy suite stays in the pipeline, but marked non-blocking (`continue-on-error: true`), so its failures are informational while the new suite builds up a track record. Once the new suite hits parity, turn `continue-on-error` off for it, and drop the old job entirely once you decommission.

```yaml
# GitHub Actions: parallel suite execution
jobs:
  old-suite:
    name: "E2E Tests (Cypress) [Legacy]"
    runs-on: ubuntu-latest
    # Non-blocking during migration — failures are informational
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx cypress run

  new-suite:
    name: "E2E Tests (Playwright) [Migration]"
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npx playwright test
```
</content>
