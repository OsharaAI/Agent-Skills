---
name: ci-cd-integration
description: >-
  Build CI/CD pipelines that execute test suites reliably. Covers GitHub Actions and
  GitLab CI templates, sharding and parallel execution, artifact handling, quarantining
  flaky tests, publishing test results, coverage-based quality gates, OIDC keyless
  deployment, and ready-to-use workflows for Playwright, Jest, and multi-stage
  pipelines.
  Use when: "CI/CD," "GitHub Actions," "pipeline," "test in CI," "GitLab CI,"
  "continuous integration," "test automation pipeline," "shard tests in CI."
  Not for: per-test flaky healing at runtime — use test-reliability; go/no-go release
  decisions and smoke-test checklists — use release-readiness; test-result dashboards
  and trend reporting — use qa-metrics.
  Related: playwright-automation, qa-metrics, test-reliability, coverage-analysis, release-readiness.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: infrastructure
---

<objective>
Two failure modes plague CI pipelines built without deliberate design: a fully serial 20-minute suite on every push, which grinds developer velocity to a halt, and a "green" pipeline that silently retries flaky specs until they pass, which buries a real race condition instead of surfacing it. This skill exists to build pipelines that avoid both: they route the correct test subset to the correct trigger, spread execution across parallel runners, keep traces and reports as durable evidence, quarantine unreliable tests rather than papering over them, and block merges using actual coverage numbers rather than a felt sense of "probably fine." Reach for this skill when the concern is *running* tests inside a pipeline — not authoring the tests themselves.
</objective>

## Questions to Settle First

Look for `.agents/qa-project-context.md` before anything else — if it's there, treat it as already-answered ground truth (particularly `team_maturity` and any CI conventions already in place) and don't re-ask. Otherwise work through:

1. **CI platform in use.** GitHub Actions, GitLab CI, CircleCI, or Jenkins? Ready-made templates in this skill cover GitHub Actions and GitLab CI only.
2. **Which test categories need to run.** Unit, integration, E2E, visual regression, performance — each carries its own resource footprint and expected runtime.
3. **Current total CI runtime.** Past the 10-minute mark, parallelism and sharding stop being optional nice-to-haves.
4. **Push frequency across the team.** Teams pushing often need aggressive cancel-in-progress concurrency and heavier caching.
5. **Trigger-to-suite mapping.** Not every push warrants a full E2E run — decide which trigger fires which suite before touching any YAML.

### Match pipeline complexity to team maturity

Record `team_maturity` in `.agents/qa-project-context.md`, then pick the pipeline shape that fits:

- **startup** — a single combined job: lint, unit tests, one E2E smoke test on PR. Speed of feedback wins over exhaustiveness.
- **growing** — unit, integration, and E2E split into their own jobs, with parallelization, artifact uploads, published results, and flaky-test quarantine.
- **established** — the full matrix: sharded E2E runs, staged multi-environment promotion, performance and security scanning, deploy gates, SLA-driven pipelines.

---

## Guiding Principles

1. **Match test scope to feedback speed.** Every push gets unit tests (under 2 minutes). Every PR gets E2E (under 10 minutes). The full suite runs on merge and nightly. Treat the trigger-to-suite table below as a binding contract, not a suggestion.
2. **Default to parallel execution.** Sharding turns a 20-minute serial run into a 5-minute run across 4 workers — the extra runner cost is almost always worth paying.
3. **Treat artifacts as your evidence trail.** Every run should upload traces, screenshots, coverage data, and HTML reports. Skip this and a CI failure becomes an unreproducible mystery that only resolves with "well, it works on my machine."
4. **Quarantine flaky tests instead of masking them with retries.** A `retries: 3` setting makes the report look green while the underlying race condition keeps shipping. Move flaky specs to a non-blocking job, track them explicitly, and fix the root cause.
5. **Tighten gates as code moves toward production.** PR-stage gates should be cheap and fast; deploy-stage gates should be comprehensive.
6. **Let the test runner own its own thresholds.** Coverage enforcement belongs in the runner's own `coverageThreshold`/`thresholds` config, which exits non-zero on failure. Parsing coverage percentages out of stdout with regex breaks the moment the runner's output format changes.

---

## How the Pipeline Is Structured

```
Push to branch:   lint+types (30s) → unit (1-2m)
PR opened:        + integration (2-3m) → E2E sharded (5-8m) → merge report
Merge to main:    full E2E ∥ visual ∥ perf budget → deploy (OIDC)
Nightly (cron):   full suite + npm audit + axe a11y + flaky quarantine
```

### Trigger-to-suite mapping

| Trigger | Tests | Max duration |
|---------|-------|---------------|
| Push to branch | lint, type-check, unit | 2 min |
| PR opened/updated | + integration, E2E smoke | 10 min |
| Merge to main | + full E2E, visual, perf budget | 15 min |
| Nightly schedule | full suite, security, a11y, flaky quarantine | 30 min |
| Release tag | full suite, smoke against staging | 20 min |

---

## Building on GitHub Actions

Ready-to-paste workflow files (unit tests, sharded Playwright E2E, the complete pipeline, nightly runs, PR gating) live in `references/github-actions-templates.md`.

### Action version guidance (as of June 2026)

Pin to the current major version and let Dependabot handle bumps. Anything in the `actions/*` family now runs on the Node 24 runner — Node 20 is deprecated on GitHub-hosted runners.

| Action | Current major | Notes |
|--------|----------------|-------|
| `actions/checkout` | `@v6` | |
| `actions/setup-node` | `@v6` | Auto-caching only kicks in from v5+ when `packageManager` is set; be explicit with `cache: npm` |
| `actions/cache` | `@v5` | Runs on the new cache service v2 backend |
| `actions/upload-artifact` | `@v7` | Supports unzipped uploads via `archive: false` |
| `actions/download-artifact` | `@v7` | Keep its major version matched to upload-artifact |
| `dorny/test-reporter` | `@v3` | Requires the Node 24 runner; the reporter's keys are unchanged |
| `dorny/paths-filter` | `@v3` | |
| `marocchino/sticky-pull-request-comment` | `@v3` | |
| `slackapi/slack-github-action` | `@v2` | Floating major; read the notification note below before jumping to v3 |

If the pipeline is supply-chain sensitive, pin third-party actions (dorny, marocchino, slackapi, knapsack) to a full commit SHA with a version comment instead of a tag, and let Dependabot bump the SHA: `uses: dorny/test-reporter@<40-char-sha> # v3.0.0`. First-party `actions/*` carry less risk, so tags remain fine there.

### Concepts worth knowing

**Concurrency groups** stop wasted runs from piling up when a branch receives several pushes in quick succession:

```yaml
concurrency:
  group: tests-${{ github.ref }}
  cancel-in-progress: true
```

**Sharding via matrix strategy** spreads tests across runners:

```yaml
strategy:
  fail-fast: false
  matrix:
    shard: [1, 2, 3, 4]
steps:
  - run: npx playwright test --shard=${{ matrix.shard }}/4
```

**Caching** avoids re-downloading browsers on every run:

```yaml
- uses: actions/setup-node@v6
  with: { node-version: 22, cache: npm }

- name: Cache Playwright browsers
  id: playwright-cache
  uses: actions/cache@v5
  with:
    path: ~/.cache/ms-playwright
    key: playwright-${{ runner.os }}-${{ hashFiles('package-lock.json') }}

- name: Install Playwright browsers
  if: steps.playwright-cache.outputs.cache-hit != 'true'
  run: npx playwright install --with-deps chromium
```

For **uploading artifacts** and **stitching sharded reports** back into a single HTML report, see the E2E workflow in `references/github-actions-templates.md`. The merge step pulls files with `actions/download-artifact@v7` using `pattern: test-results-*`, then runs `npx playwright merge-reports --reporter=html`.

### Scaling sharding beyond a handful of workers

Once you're running more than 10-15 shards, naïve hash-based splitting starts leaving some shards idle while others lag. Reach for a timing-aware balancer instead:

- **`knapsack-pro`** — splits by historical duration; supports Playwright, Jest, Cypress, and RSpec.
- **CloudBees Smart Tests** (previously **Launchable**) — combines ML-based prioritization with Test Impact Analysis, running only tests likely affected by the diff.
- **Datadog Test Optimization** — pairs TIA with flake management and duration-based shard balancing.
- **Trunk Flaky Tests** — quarantine plus retry-budget management, aware of flake history.

Before paying for a balancer: Playwright's built-in `--shard` flag already splits by file and factors in duration from previous runs. To inspect the timing data it's using, or feed in your own, dump it directly: `npx playwright test --reporter=json | jq '[.suites[].specs[] | {file: .file, duration: .tests[].results[].duration}]'`. Jest users can get similar visibility from `jest-slow-test-reporter`, which surfaces the slowest specs so they can be split or fixed.

Running self-hosted runners on Kubernetes? Use **Actions Runner Controller** (`arc-runner-set` / `gha-runner-scale-set`), installed via Helm, which auto-scales runner pods per workflow — it supersedes the now-deprecated `runner-deployment` CRD.

### Enforcing required checks

Under Settings → Branches → Branch protection rules, turn on "Require status checks to pass before merging," list `lint`, `unit-tests`, and `e2e` (every shard) as required, and enable "Require branches to be up to date."

---

## Building on GitLab CI

The complete pipeline lives in `references/gitlab-ci-template.md`. Highlights:

- Stage order: `[validate, test, e2e, deploy]`. Use `node:22-alpine` for lint/unit stages and `mcr.microsoft.com/playwright:v1.60.0-noble` for E2E — keep that image pinned to whatever minor version of `@playwright/test` you actually have installed.
- Parallel sharding: setting `parallel: 4` exposes `CI_NODE_INDEX`/`CI_NODE_TOTAL`, consumed via `npx playwright test --shard=$CI_NODE_INDEX/$CI_NODE_TOTAL`.
- Coverage reporting: emit a `cobertura` coverage artifact plus a `junit` report — GitLab reads both the percentage and test outcomes from these. The older `coverage:` stdout-regex approach is a fallback of last resort and breaks across Jest versions; prefer the cobertura report.

---

## Patterns Worth Knowing

### Posting test results to the PR

```yaml
- name: Publish test results
  uses: dorny/test-reporter@v3
  if: ${{ !cancelled() }}
  with:
    name: Test Results
    path: test-results/junit.xml
    reporter: jest-junit  # use java-junit for a Playwright JUnit report
```

The sticky coverage comment pattern (`marocchino/sticky-pull-request-comment@v3`) is shown in full under the PR Quality Gate section of `references/github-actions-templates.md`.

### Running tests conditionally

Don't test what didn't change. `dorny/paths-filter@v3` produces outputs you can gate later steps on — see the Conditional execution section of `references/github-actions-templates.md`.

### Isolating flaky tests

Route flaky tests into a separate, non-blocking job so they still execute in CI without holding up merges:

```yaml
e2e-stable:        # required for merge
  steps:
    - run: npx playwright test --grep-invert @flaky

e2e-quarantine:    # non-blocking
  continue-on-error: true
  steps:
    - run: npx playwright test --grep @flaky
    - if: failure()
      run: echo "::warning::Quarantined tests failed. Review and fix or remove."
```

Mark the flaky test itself so the grep pattern can find it:

```typescript
test('sometimes fails due to race condition @flaky', async ({ page }) => {
  // runs in CI but doesn't block merges
});
```

After ten straight green runs in quarantine, drop the `@flaky` tag. Runtime self-healing for a single flaky test (selector recovery, adaptive retries) belongs to `test-reliability`, not here.

### Layered caching

| Layer | Path | Cache key |
|-------|------|-----------|
| Node modules | (handled by `setup-node` `cache: npm`) | automatic |
| Playwright browsers | `~/.cache/ms-playwright` | `pw-{os}-{hash(package-lock.json)}` |
| Build cache (Next.js) | `.next/cache` | `nextjs-{os}-{hash(lockfile)}-{hash(src)}` |
| Test fixtures | `e2e/fixtures/.cache` | `test-data-{hash(seed.sql)}` |

`actions/cache@v5` covers layers 2 through 4; add `restore-keys` to the build-cache layer so partial matches still help.

### Deploying without long-lived secrets

Skip storing a permanent `DEPLOY_TOKEN`. GitHub Actions OIDC lets you assume a cloud role and get short-lived credentials instead — nothing static sits around waiting to leak or need rotation:

```yaml
deploy:
  permissions:
    id-token: write   # request the OIDC JWT
    contents: read
  steps:
    - uses: aws-actions/configure-aws-credentials@v6
      with:
        role-to-assume: arn:aws:iam::123456789012:role/gha-deploy
        aws-region: eu-central-1
    - run: ./deploy.sh production   # uses short-lived STS creds, no static secret
```

Scope the IAM role's trust policy to your specific repo and branch via the `sub` claim. GCP (`google-github-actions/auth`) and Azure (`azure/login`) offer equivalent OIDC support.

### Failure notifications to Slack/Teams

`slackapi/slack-github-action@v2`, using `webhook-type: incoming-webhook`, gated with `if: failure() && github.ref == 'refs/heads/main'` so only main-branch breakage triggers a ping. If considering `@v3`, check its docs first — it changed how payloads from workflow-trigger webhooks are handled (no longer auto-flattened/stringified). A full example sits in the Nightly Full Suite section of `references/github-actions-templates.md`.

---

## Gate Definitions

| Gate | When | Required checks | Blocking? |
|------|------|-------------------|-----------|
| **PR Gate** | PR opened/updated | lint, type-check, unit, coverage threshold | Yes |
| **Merge Gate** | Before merge to main | + E2E smoke suite | Yes |
| **Deploy Gate** | Before production deploy | + full E2E, visual, perf budget | Yes |
| **Nightly Gate** | Scheduled 2am daily | full suite, npm audit, axe a11y | Alert only |

### PR Gate — target under 3 minutes

Put the coverage floor in the runner's own config, not a bash script. For Jest (`jest.config.js`) or Vitest (`coverage.thresholds` in `vitest.config.ts`):

```javascript
coverageThreshold: { global: { lines: 80, statements: 80, branches: 70 } }
```

With that in place, `jest --coverage` exits non-zero on a drop, failing the job without any extra scripting. If you need to surface the number in CI output, have Jest write a `json-summary` and read that file — there's no dedicated `coverage-summary` CLI:

```yaml
- run: npm test -- --ci --coverage   # exits 1 if below coverageThreshold
- name: Print coverage (optional)
  run: |
    PCT=$(jq '.total.lines.pct' coverage/coverage-summary.json)
    echo "Line coverage: ${PCT}%"
```

(The `json-summary` reporter writes to `coverage/coverage-summary.json`. nyc/c8 projects can use `nyc report --reporter=text-summary` instead. Avoid the deprecated standalone `istanbul` CLI — don't run `istanbul report`.)

### Merge Gate — target under 10 minutes

Everything in the PR Gate plus E2E smoke tests. Add these as required status checks in branch protection.

### Deploy Gate — target under 15 minutes

Requires `[unit-tests, e2e-tests, visual-tests]` to pass, then a performance budget check (`npx lhci autorun` / `lhci assert --config=lighthouserc.json`) before the OIDC deploy step described above.

### Nightly Gate — up to 30 minutes

Runs the full E2E suite across all browsers plus a security scan, an accessibility audit, and flaky quarantine. These need to be actual jobs, not just aspirational prose:

```yaml
- run: npm audit --audit-level=high   # fails on high/critical advisories
- run: npx playwright test --grep @a11y   # specs that call @axe-core/playwright
```

The `@a11y`-tagged specs lean on `@axe-core/playwright`:

```typescript
import AxeBuilder from '@axe-core/playwright';
test('home page has no a11y violations @a11y', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
```

Route the results to Slack rather than making them a blocking check.

---

## Common Mistakes

### 1. Full suite on every commit
Running a 20-minute test suite on every single push kills velocity. Stick to the trigger-to-suite map — fast checks on push, thorough checks on PR and merge.

### 2. Skipping artifact storage
No traces, screenshots, or logs means every CI failure turns into a wasted afternoon of "let me try to reproduce this locally." Upload artifacts using `if: ${{ !cancelled() }}`.

### 3. Retrying flaky tests without a tracking mechanism
`retries: 3` makes flaky tests invisible instead of fixed — green report, live race condition. Quarantine them, track them, and actually fix the cause.

### 4. Failures that only happen in CI, with no local repro path
When a test fails only in CI, write down why (timezone difference, missing env var, screen resolution mismatch) and provide a script that reproduces the CI environment locally using the **exact same** Playwright image CI uses — don't let it drift to a stale pinned image. See the Local repro section of `references/github-actions-templates.md`.

### 5. Jobs implicitly sharing state
A job reading files a sibling job produced, without going through artifacts or `needs`. Every job starts from a clean slate — pass data explicitly with `upload-artifact`/`download-artifact`.

### 6. Missing concurrency controls
Without a concurrency group, multiple runs on the same branch burn runner minutes for no reason. Always set `cancel-in-progress: true` on a concurrency group.

### 7. Secrets committed directly into workflow YAML
Tokens, passwords, and keys never belong in plaintext YAML. Use repo secrets (`${{ secrets.X }}`) or GitLab CI/CD variables, and favor OIDC keyless auth over any long-lived deploy token.

### 8. No job-level timeouts
A hung test can occupy a runner indefinitely. Set `timeout-minutes` per job and configure `actionTimeout`/`navigationTimeout` in the Playwright config.

---

## Confirming It Actually Works

Validate the pipeline before trusting it — start with the cheapest check and work up:

1. **Lint the workflow YAML** — `actionlint .github/workflows/*.yml` catches broken expressions, bad `needs` references, and shell-quoting mistakes before they surface at runtime. Pair it with `yamllint .github/workflows/` for indentation issues, and run actionlint itself as a CI job.
2. **Test a job locally** — `act -j unit-tests` runs the job in a local container, letting you iterate without pushing.
3. **Verify required checks show up** — push to a scratch branch, open a draft PR, and confirm the expected checks (`lint`, `unit-tests`, `e2e`) appear, and that dropping coverage below the threshold actually fails the gate.
4. **Check artifacts land correctly** — pull the run's artifacts from the Actions UI (or `gh run download <id>`) and confirm `playwright-report/` and trace files are present.

---

## Definition of Done

- A documented trigger map exists: push runs only lint+unit; the PR workflow gates E2E behind `if: github.event_name == 'pull_request'` — verified in the actual YAML, not just assumed to exist.
- `actionlint .github/workflows/*.yml` exits 0.
- A non-blocking quarantine job runs `--grep @flaky` with `continue-on-error: true`, while the stable job runs `--grep-invert @flaky` and appears in required checks.
- Test artifacts (reports, screenshots, traces) upload under `if: ${{ !cancelled() }}` with an explicit `retention-days`/`expire_in` set.
- Concurrency groups with `cancel-in-progress: true` exist on PR/test workflows.
- Coverage enforcement happens via the runner's own `coverageThreshold`/`thresholds` (non-zero exit below the floor) — no scraping via a `coverage-summary` CLI.
- `lint`, `unit-tests`, and `e2e` are all listed as required status checks in branch protection.
- No long-lived deploy token appears in YAML — deployment relies on OIDC (`id-token: write` plus a cloud role) or, failing that, a secrets-manager reference.

---

## Adjacent Skills

- **playwright-automation** — where the E2E tests, Page Object Model, and `playwright.config.ts` (whose sharding/timeout settings this pipeline drives) actually get written.
- **test-reliability** — runtime healing for a single flaky test (selector recovery, retry policy); go there to *fix* a flaky test, come here to *quarantine* it in CI.
- **qa-metrics** — turns the JUnit/coverage artifacts this pipeline generates into dashboards and flakiness trends over time.
- **release-readiness** — owns the human go/no-go call and release checklist that consumes these gate results; this skill builds the gates, that skill decides based on them.
- **coverage-analysis** — identifies coverage gaps and sets the threshold value that this skill's PR gate enforces.

## Reference Files (in `references/`)

- **github-actions-templates.md** — ready-to-copy workflows: unit tests, sharded Playwright E2E with report merging, the full pipeline, nightly runs (Slack + audit + axe), and PR quality-gate workflows, plus conditional-execution and local-repro snippets.
- **gitlab-ci-template.md** — a complete `.gitlab-ci.yml` featuring parallel sharding, cobertura coverage, and JUnit MR reporting.
