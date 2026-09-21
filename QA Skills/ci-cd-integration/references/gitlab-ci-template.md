# GitLab CI Template

A complete `.gitlab-ci.yml` covering lint, unit tests, sharded E2E, and deploy. Image tags reflect mid-2026 (`node:22-alpine`, `mcr.microsoft.com/playwright:v1.60.0-noble`) — keep the Playwright image pinned to whatever `@playwright/test` minor version you actually have installed.

```yaml
# .gitlab-ci.yml
stages: [validate, test, e2e, deploy]

variables:
  NODE_ENV: test
  npm_config_cache: '$CI_PROJECT_DIR/.npm'

cache:
  key: ${CI_COMMIT_REF_SLUG}
  paths: [.npm/, node_modules/]

lint:
  stage: validate
  image: node:22-alpine
  script: [npm ci --prefer-offline, npm run lint, npm run type-check]

unit-tests:
  stage: test
  image: node:22-alpine
  script: [npm ci --prefer-offline, 'npm run test:ci -- --coverage']
  artifacts:
    when: always
    paths: [coverage/]
    reports:
      junit: junit.xml
      # GitLab reads both the percentage and per-line data from this cobertura report.
      coverage_report: { coverage_format: cobertura, path: coverage/cobertura-coverage.xml }

e2e-tests:
  stage: e2e
  image: mcr.microsoft.com/playwright:v1.60.0-noble
  parallel: 4  # GitLab auto-exposes CI_NODE_INDEX and CI_NODE_TOTAL for this
  script:
    - npm ci --prefer-offline
    - npm run build
    - npm start &
    - npx wait-on http://localhost:3000 --timeout 60000
    - npx playwright test --shard=$CI_NODE_INDEX/$CI_NODE_TOTAL
  artifacts:
    when: always
    paths: [test-results/, playwright-report/]
    expire_in: 7 days
    reports:
      junit: test-results/junit.xml  # parsed by GitLab and surfaced in the MR UI
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy-staging:
  stage: deploy
  script: [./deploy.sh staging]
  rules: [{ if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH' }]
  needs: [unit-tests, e2e-tests]
```

## Reporting coverage

The cobertura `coverage_report` artifact above is the preferred path — GitLab pulls both the overall percentage and per-line coverage from it and renders it directly in the MR diff. Get Jest to produce it with `jest --coverage --coverageReporters=cobertura` (or set `coverageReporters` inside `jest.config.js`).

The older stdout-regex approach should be treated as a last-resort fallback: it's brittle across changes to Jest's text-table formatting and becomes unnecessary once cobertura reporting is wired up. Reach for it only if a cobertura report genuinely isn't available:

```yaml
# Legacy fallback only — drop this once coverage_report (cobertura) is wired up.
coverage: '/All files[^|]*\|[^|]*\s+([\d\.]+)/'
```
