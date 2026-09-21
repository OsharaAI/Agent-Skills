# GitHub Actions Templates

Ready-to-copy workflow files — drop them into `.github/workflows/` and adjust environment variables and secrets to match your project.

These pin to the action majors current as of June 2026 (`checkout@v6`, `setup-node@v6`, `cache@v5`, `upload-artifact@v7`, `download-artifact@v7`, `dorny/test-reporter@v3`, `dorny/paths-filter@v3`, `marocchino/sticky-pull-request-comment@v3`, `slackapi/slack-github-action@v2`). Let Dependabot keep first-party actions current; for third-party actions, pin to a commit SHA with a version comment instead.

---

## 1. Unit Test Workflow

Gives fast feedback on every push by running lint, type-check, and unit tests with coverage.

```yaml
# .github/workflows/unit-tests.yml
name: Unit Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

concurrency:
  group: unit-${{ github.ref }}
  cancel-in-progress: true

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-node@v6
        with:
          node-version: 22
          cache: npm

      - run: npm ci

      - name: Lint
        run: npm run lint

      - name: Type-check
        run: npm run type-check

      - name: Run unit tests with coverage
        run: npm test -- --ci --coverage --reporters=default --reporters=jest-junit
        env:
          JEST_JUNIT_OUTPUT_DIR: test-results

      - name: Upload coverage report
        uses: actions/upload-artifact@v7
        if: ${{ !cancelled() }}
        with:
          name: coverage-report
          path: coverage/
          retention-days: 7

      - name: Upload test results
        uses: actions/upload-artifact@v7
        if: ${{ !cancelled() }}
        with:
          name: unit-test-results
          path: test-results/
          retention-days: 7
```

---

## 2. Playwright E2E Workflow

Splits Playwright tests across multiple runners via sharding, caches browsers so they aren't reinstalled every run, and stitches the per-shard reports into one combined HTML report.

```yaml
# .github/workflows/e2e-tests.yml
name: E2E Tests

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: e2e-${{ github.ref }}
  cancel-in-progress: true

jobs:
  e2e:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    strategy:
      fail-fast: false
      matrix:
        shard: [1, 2, 3, 4]

    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-node@v6
        with:
          node-version: 22
          cache: npm

      - run: npm ci

      # Caching avoids a 200MB+ browser download whenever the cache is warm
      - name: Cache Playwright browsers
        id: playwright-cache
        uses: actions/cache@v5
        with:
          path: ~/.cache/ms-playwright
          key: playwright-${{ runner.os }}-${{ hashFiles('package-lock.json') }}

      - name: Install Playwright browsers
        if: steps.playwright-cache.outputs.cache-hit != 'true'
        run: npx playwright install --with-deps chromium

      # OS-level dependencies aren't part of the cached path, so install them regardless
      - name: Install Playwright OS dependencies
        if: steps.playwright-cache.outputs.cache-hit == 'true'
        run: npx playwright install-deps chromium

      - name: Build application
        run: npm run build

      # Launch the app in the background; wait-on blocks until it's reachable
      - name: Start application
        run: npm start &
        env:
          NODE_ENV: test

      - name: Wait for application
        run: npx wait-on http://localhost:3000 --timeout 60000

      - name: Run Playwright tests (shard ${{ matrix.shard }}/4)
        run: npx playwright test --shard=${{ matrix.shard }}/4
        env:
          BASE_URL: http://localhost:3000
          TEST_USER_EMAIL: ${{ secrets.TEST_USER_EMAIL }}
          TEST_USER_PASSWORD: ${{ secrets.TEST_USER_PASSWORD }}

      # Keep results even when the run fails — that's when you need them most
      - name: Upload test results
        uses: actions/upload-artifact@v7
        if: ${{ !cancelled() }}
        with:
          name: test-results-shard-${{ matrix.shard }}
          path: |
            test-results/
            playwright-report/
          retention-days: 7

      # Traces are large, so only keep them when something actually failed
      - name: Upload traces on failure
        uses: actions/upload-artifact@v7
        if: failure()
        with:
          name: traces-shard-${{ matrix.shard }}
          path: test-results/**/trace.zip
          retention-days: 7

  # Combines every shard's report into a single browsable HTML report
  merge-reports:
    needs: e2e
    if: ${{ !cancelled() }}
    runs-on: ubuntu-latest
    timeout-minutes: 5

    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-node@v6
        with:
          node-version: 22
          cache: npm

      - run: npm ci

      - name: Download all shard results
        uses: actions/download-artifact@v7
        with:
          pattern: test-results-shard-*
          path: all-results

      - name: Merge into single HTML report
        run: npx playwright merge-reports --reporter=html all-results

      - name: Upload merged report
        uses: actions/upload-artifact@v7
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 14
```

---

## 3. Full CI Pipeline

A multi-job pipeline with real dependencies between stages: lint and unit tests run first, E2E follows, then deploy. Concurrency groups cancel stale in-flight runs automatically.

```yaml
# .github/workflows/ci.yml
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # --- Stage 1: Validate ---
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npm run lint
      - run: npm run type-check

  # --- Stage 2: Unit Tests ---
  unit-tests:
    needs: lint
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npm test -- --ci --coverage
      - uses: actions/upload-artifact@v7
        if: ${{ !cancelled() }}
        with:
          name: coverage
          path: coverage/
          retention-days: 7

  # --- Stage 3: E2E Tests ---
  e2e:
    needs: unit-tests
    runs-on: ubuntu-latest
    timeout-minutes: 30
    strategy:
      fail-fast: false
      matrix:
        shard: [1, 2, 3]
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with: { node-version: 22, cache: npm }
      - run: npm ci

      - name: Cache Playwright browsers
        id: pw-cache
        uses: actions/cache@v5
        with:
          path: ~/.cache/ms-playwright
          key: pw-${{ runner.os }}-${{ hashFiles('package-lock.json') }}

      - name: Install Playwright
        if: steps.pw-cache.outputs.cache-hit != 'true'
        run: npx playwright install --with-deps chromium

      - name: Install Playwright OS deps
        if: steps.pw-cache.outputs.cache-hit == 'true'
        run: npx playwright install-deps chromium

      - run: npm run build

      - name: Start app
        run: npm start &
        env: { NODE_ENV: test }

      - run: npx wait-on http://localhost:3000 --timeout 60000

      - run: npx playwright test --shard=${{ matrix.shard }}/3
        env:
          BASE_URL: http://localhost:3000

      - uses: actions/upload-artifact@v7
        if: ${{ !cancelled() }}
        with:
          name: e2e-results-${{ matrix.shard }}
          path: |
            test-results/
            playwright-report/
          retention-days: 7

  # --- Stage 4: Deploy (main only) ---
  deploy:
    needs: [unit-tests, e2e]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    # OIDC keyless auth means there's no long-lived DEPLOY_TOKEN to store or rotate
    permissions:
      id-token: write
      contents: read
    # Blocks a second deploy from starting while one is already in flight
    concurrency:
      group: deploy-production
      cancel-in-progress: false
    environment: production
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npm run build
      # Trades the GitHub OIDC JWT for short-lived STS credentials
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: arn:aws:iam::123456789012:role/gha-deploy
          aws-region: eu-central-1
      - name: Deploy to production
        run: npm run deploy   # uses short-lived creds from the step above
```

---

## 4. Nightly Full Suite

Runs the entire test suite every night across all browsers, plus a dependency security scan (`npm audit`) and an accessibility audit (`@axe-core/playwright`), and pings Slack when something fails.

```yaml
# .github/workflows/nightly.yml
name: Nightly Full Suite

on:
  schedule:
    - cron: '0 2 * * *'   # 2am UTC daily
  # Manual trigger, useful when debugging a nightly failure
  workflow_dispatch:

jobs:
  full-suite:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    strategy:
      fail-fast: false
      matrix:
        # Cross-browser coverage happens nightly rather than on every PR
        project: [chromium, firefox, webkit]

    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-node@v6
        with: { node-version: 22, cache: npm }

      - run: npm ci

      - name: Install all Playwright browsers
        run: npx playwright install --with-deps

      - run: npm run build

      - name: Start application
        run: npm start &
        env: { NODE_ENV: test }

      - run: npx wait-on http://localhost:3000 --timeout 60000

      # Includes the visual and performance specs, not just functional E2E
      - name: Run full test suite (${{ matrix.project }})
        run: npx playwright test --project=${{ matrix.project }}
        env:
          BASE_URL: http://localhost:3000
          TEST_USER_EMAIL: ${{ secrets.TEST_USER_EMAIL }}
          TEST_USER_PASSWORD: ${{ secrets.TEST_USER_PASSWORD }}

      - name: Upload results
        uses: actions/upload-artifact@v7
        if: ${{ !cancelled() }}
        with:
          name: nightly-${{ matrix.project }}
          path: |
            test-results/
            playwright-report/
          retention-days: 14

  # Runs only nightly, since these scans are too slow/noisy for every PR
  security-and-a11y:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with: { node-version: 22, cache: npm }
      - run: npm ci

      # High/critical advisories fail the job; lower severities are reported only
      - name: Dependency security scan
        run: npm audit --audit-level=high

      - name: Install Playwright (chromium only)
        run: npx playwright install --with-deps chromium
      - run: npm run build
      - name: Start application
        run: npm start &
        env: { NODE_ENV: test }
      - run: npx wait-on http://localhost:3000 --timeout 60000

      # Executes specs tagged @a11y, which assert via @axe-core/playwright's AxeBuilder
      - name: Accessibility audit
        run: npx playwright test --grep @a11y
        env: { BASE_URL: http://localhost:3000 }

  # Alerts the team so a nightly failure doesn't sit unnoticed until morning
  notify:
    needs: [full-suite, security-and-a11y]
    if: failure()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Send Slack notification
        uses: slackapi/slack-github-action@v2
        with:
          webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
          webhook-type: incoming-webhook
          payload: |
            {
              "text": "Nightly test suite failed",
              "blocks": [
                {
                  "type": "header",
                  "text": { "type": "plain_text", "text": "Nightly Tests Failed" }
                },
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Repository:* ${{ github.repository }}\n*Run:* <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View logs>\n*Triggered by:* ${{ github.event_name }}"
                  }
                }
              ]
            }
```

---

## 5. PR Quality Gate

Triggered on pull requests: posts results as a PR comment and blocks merge on failure. Bundles lint, unit tests, and a lightweight E2E smoke pass into one job.

```yaml
# .github/workflows/pr-quality-gate.yml
name: PR Quality Gate

on:
  pull_request:
    branches: [main]

concurrency:
  group: pr-gate-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  checks: write
  pull-requests: write
  contents: read

jobs:
  quality-gate:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-node@v6
        with: { node-version: 22, cache: npm }

      - run: npm ci

      - name: Lint and type-check
        run: |
          npm run lint
          npm run type-check

      # jest.config's coverageThreshold already enforces the floor, so this step
      # exits 1 on its own when coverage drops — no bash-side scraping required.
      # The json-summary reporter writes coverage/coverage-summary.json for the comment step below.
      - name: Run unit tests
        run: npm test -- --ci --coverage --reporters=default --reporters=jest-junit
        env:
          JEST_JUNIT_OUTPUT_DIR: test-results
          JEST_JUNIT_OUTPUT_NAME: junit.xml

      # Surfaces results as a check run directly on the PR.
      # Swap reporter: java-junit if the JUnit file comes from Playwright instead of Jest.
      - name: Publish test results
        uses: dorny/test-reporter@v3
        if: ${{ !cancelled() }}
        with:
          name: Unit Test Results
          path: test-results/junit.xml
          reporter: jest-junit
          fail-on-error: true

      # Builds a sticky PR comment showing coverage (replaced on each new push).
      # Reads the json-summary file directly since no `coverage-summary` CLI exists.
      - name: Generate coverage summary
        if: ${{ !cancelled() }}
        run: |
          PCT=$(jq '.total.lines.pct' coverage/coverage-summary.json)
          {
            echo "## Test Coverage"
            echo ""
            echo "Line coverage: **${PCT}%**"
            echo ""
            echo "_Updated by CI on $(date -u +'%Y-%m-%d %H:%M UTC')_"
          } > coverage-comment.md

      - name: Comment coverage on PR
        uses: marocchino/sticky-pull-request-comment@v3
        if: ${{ !cancelled() }}
        with:
          header: test-coverage
          path: coverage-comment.md

      - name: Upload coverage artifact
        uses: actions/upload-artifact@v7
        if: ${{ !cancelled() }}
        with:
          name: pr-coverage
          path: coverage/
          retention-days: 7
```

---

## 6. Conditional Execution

Skips E2E entirely when a PR touches neither frontend code nor the Playwright config, saving CI minutes on backend-only changes.

```yaml
- name: Detect changed files
  id: changes
  uses: dorny/paths-filter@v3
  with:
    filters: |
      frontend:
        - 'src/**'
        - 'e2e/**'
      backend:
        - 'api/**'
        - 'lib/**'
      config:
        - 'package.json'
        - 'playwright.config.ts'

- name: Run E2E tests
  if: steps.changes.outputs.frontend == 'true' || steps.changes.outputs.config == 'true'
  run: npx playwright test

- name: Run API tests
  if: steps.changes.outputs.backend == 'true' || steps.changes.outputs.config == 'true'
  run: npm run test:api
```

---

## 7. Reproduce CI Locally

For a test that only fails in CI, rebuild the same environment locally using the **identical** Playwright image tag the pipeline runs — resist the temptation to leave a stale tag pinned. Keep it aligned with your installed `@playwright/test` version.

```bash
# Match the version you run in CI; v1.60.0 shown as the current release
docker run --rm -v "$(pwd)":/work -w /work \
  mcr.microsoft.com/playwright:v1.60.0-noble \
  npx playwright test --project=chromium
```

---

## Usage Notes

### Adapting These to Your Project

1. **Swap `npm test`** for whatever your real test command is (`npx jest`, `npx vitest`, etc.)
2. **Swap `npm start`** for however your app actually boots (`npm run dev`, `npx serve dist`, etc.)
3. **Configure secrets** under GitHub repo Settings > Secrets and variables > Actions
4. **Tune shard counts** to your suite's size — aim for roughly 3-5 minutes of work per shard.
5. **Tune `timeout-minutes`** to your suite's real duration plus about a 50% safety margin.

### Guidance on Shard Counts

| Suite Size | Recommended Shards | Expected Duration |
|------------|-------------------|-------------------|
| < 50 tests | 1-2 | 2-5 min |
| 50-200 tests | 3-4 | 4-8 min |
| 200-500 tests | 4-6 | 5-10 min |
| 500+ tests | 6-10 | 5-10 min |

### npm Scripts These Workflows Expect

These workflows assume the following scripts already exist in `package.json`:

```json
{
  "scripts": {
    "lint": "eslint .",
    "type-check": "tsc --noEmit",
    "test": "jest",
    "build": "next build",
    "start": "next start",
    "deploy": "your-deploy-command"
  }
}
```

### Packages These Workflows Expect

```bash
# For unit test reporting
npm install -D jest-junit

# For E2E tests
npm install -D @playwright/test

# For the nightly accessibility audit (@a11y specs)
npm install -D @axe-core/playwright

# For waiting on the app to start in CI
npm install -D wait-on
```

### Coverage Configuration

Put the coverage floor in the runner's own config so the test command fails on its own below that floor, and emit `json-summary` so the PR-comment step has `coverage/coverage-summary.json` to read. In `jest.config.js`:

```javascript
module.exports = {
  coverageReporters: ['text', 'json-summary', 'lcov'],
  coverageThreshold: { global: { lines: 80, statements: 80, branches: 70 } },
};
```

No dedicated `coverage-summary` CLI exists; nyc/c8 users can substitute `nyc report --reporter=text-summary` (the standalone `istanbul` CLI is deprecated).
