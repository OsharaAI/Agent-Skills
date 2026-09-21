# Running Cypress in CI

Two complete GitHub Actions workflows — one recording to Cypress Cloud, one standalone. The reasoning for choosing between them, and the action-version pinning rationale, lives in `SKILL.md`.

**Which action version to use:** pin to `cypress-io/github-action@v7` (currently 7.2.0, as of May 2026); it runs on Node 24 and has dropped the older Node 20 code path. Fall back to `@v6` only when the runner itself is still on Node 20 — that's the maintained-for-legacy branch, not today's recommended default.

## Recording to Cypress Cloud

Set `projectId` inside `cypress.config.ts`, then run `npx cypress run --record --key $CYPRESS_RECORD_KEY`. Cloud handles parallelization, flake detection, test replay, and reporting.

```yaml
# GitHub Actions -- parallel run recorded to Cloud
jobs:
  cypress:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        containers: [1, 2, 3, 4]
    steps:
      - uses: actions/checkout@v4
      - uses: cypress-io/github-action@v7
        with:
          record: true
          parallel: true
          group: 'E2E Tests'
        env:
          CYPRESS_RECORD_KEY: ${{ secrets.CYPRESS_RECORD_KEY }}
```

## Standalone, No Cloud

```yaml
# GitHub Actions -- no Cloud dependency
steps:
  - uses: actions/checkout@v4
  - uses: cypress-io/github-action@v7
    with:
      build: npm run build
      start: npm run start
      wait-on: 'http://localhost:3000'
      browser: chrome
  - uses: actions/upload-artifact@v4
    if: failure()
    with:
      name: cypress-artifacts
      path: |
        cypress/screenshots
        cypress/videos
```
