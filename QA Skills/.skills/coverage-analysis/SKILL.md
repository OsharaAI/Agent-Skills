---
name: coverage-analysis
description: >-
  Measure and improve test coverage meaningfully. Covers Istanbul/V8/coverage.py
  configuration, coverage gap analysis by risk, coverage-as-ratchet in CI (never let
  it decrease), PR coverage diff checks, mutation testing for assertion quality, and
  distinguishing meaningful from vanity coverage. Use when: "code coverage," "coverage
  gap," "Istanbul," "coverage threshold," "coverage report," "branch coverage."
  Not for: writing the tests that raise coverage — use unit-testing; coverage as a
  tracked KPI trend over time — use qa-metrics.
  Related: unit-testing, ci-cd-integration, qa-metrics, ai-qa-review.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: metrics
---

<objective>
Hitting 90% line coverage with tests that never assert anything catches nothing —
executing a line only proves it ran, not that a future regression would trip an alarm.
This skill focuses on the metrics that actually matter (branch coverage, mutation
score, coverage on the riskiest paths), locks them into CI behind a one-way ratchet,
and points you at gaps ranked by risk rather than a single vanity percentage. The
failure mode it guards against: a shiny green coverage badge sitting on top of a test
suite that asserts nothing real, while the billing module limps along at 30%.
</objective>

## Quick Route

| Situation | Go to |
|-----------|-------|
| Pick and configure a coverage provider | Coverage Tools → `references/tool-config.md` |
| Decide where to write tests next | Gap Analysis |
| Stop coverage from regressing in CI | Coverage as CI Gate → Ratchet Pattern |
| Show per-PR coverage to reviewers | Coverage as CI Gate → PR Diff |
| Tests run code but don't assert | Mutation Testing |
| Decide what to exclude / what target to set | Meaningful vs Vanity Coverage |

---

## Discovery Questions

Look for `.agents/qa-project-context.md` first — reuse whatever it already answers instead of redoing the work. Otherwise, work through:

1. **Which test runner and coverage tool is already in place?** Look for a `coverage` block in `vitest.config.*`, `coverageProvider` in `jest.config.*`, a `.nycrc`, `c8` referenced in `package.json` scripts, or `[tool.coverage]` inside `pyproject.toml`. The runner dictates which package to install — a Vitest project needs `@vitest/coverage-v8`, never bare `c8` (details under Coverage Tools).
2. **Where does coverage stand today?** Execute the current coverage command and record the line, branch, and function numbers — this becomes the ratchet's starting floor.
3. **Does CI actually enforce coverage?** Search the GitHub Actions / GitLab CI config for `--coverage`, `coverageThreshold`, `fail_under`, or `--cov-fail-under`. Absent any of these, the coverage number is purely cosmetic.
4. **What target is set, and where did it come from?** A number handed down without justification ("leadership wants 80%") invites gaming the metric. A defensible target reflects the codebase's actual risk profile and maturity, not a nice round figure.

---

## Core Principles

**1. Coverage tells you what ran, not what was verified.** Executing a line says nothing about whether it's tested correctly — `expect(true).toBe(true)` runs the function body while asserting nothing about it. Coverage answers "did this code execute," never "would a test catch a bug here." That second question belongs to mutation testing.

**2. Branch coverage is the more honest metric.** A single-line ternary like `condition ? a : b` reads as fully covered by line coverage even when only one arm ever executes. Line-level numbers can't expose this. Gate on branches as well as lines:

```typescript
function discount(price: number, isPremium: boolean): number {
  return isPremium ? price * 0.8 : price;
}

// Line coverage: 100% (the statement executed). Branch coverage: 50% (only the true arm ran).
expect(discount(100, true)).toBe(80);

// Fix — exercise BOTH arms so branch coverage reaches 100%:
expect(discount(100, true)).toBe(80);
expect(discount(100, false)).toBe(100);
```

**3. The ratchet only moves up.** Whatever coverage is right now becomes the floor. Every subsequent PR has to clear it. This lets coverage climb naturally over time instead of forcing everyone to hit some target overnight.

**4. Rank gaps by risk, not by the headline number.** 85% isn't inherently "healthier" than 75% — what counts is whether the untested remainder touches payments, auth, or anything that corrupts data if it breaks. Prioritize accordingly.

**5. Hold new code to a stricter bar than legacy code.** Even a codebase sitting at 65% overall can require 90%+ coverage on newly written PR code. This arrests further decay without demanding a full legacy rewrite.

---

## Coverage Tools

Choose the provider based on **which test runner you're using first**, and only then by how well it aligns with your build pipeline.

| Runner / context | Install | Provider |
|---|---|---|
| **Vitest** | `@vitest/coverage-v8` (default) or `@vitest/coverage-istanbul` | `coverage.provider: 'v8'` / `'istanbul'` |
| **Jest** | bundled (`coverageProvider: 'v8'` or `'babel'`) | V8 or Istanbul/babel |
| **Non-Vitest Node** (`node:test`, plain mocha) | `c8` CLI | V8 via `c8 <command>` |
| **Legacy Istanbul CLI** | `nyc` | Istanbul instrumentation |
| **Python** | `pytest-cov` (wraps coverage.py) | coverage.py |

There are two underlying engines:

- **V8 coverage** — native to the V8 engine, so nothing gets instrumented ahead of time: quicker, no Babel step involved. In a Vitest project, install `@vitest/coverage-v8` — not `c8`, which is the standalone CLI meant for runners other than Vitest. For plain `node:test` or mocha, `c8` wraps that same V8 data as a command-line tool. This is the sensible default for new Node/Vitest work.
- **Istanbul** — instruments the source itself; costs more time but tracks more accurately through transpilation and bundling. Move to it (`@vitest/coverage-istanbul` or `nyc`) once V8 starts misattributing lines. **Tell-tale sign of bad V8 mapping:** uncovered markers land on blank lines, closing braces, or decorators, or an entire function you know is exercised shows up red — that's the source map losing track (frequently seen with particular TS bundler / SWC setups). That's your cue to switch providers.

> **Node baseline:** current majors are `c8` 11.x and `nyc` 18.x. c8 11 still works down to Node >=12; nyc 18 needs **Node 20 || >= 22**. Stuck on Node 18? Pin `nyc@^17` instead (c8 11 is fine there). New projects should just target Node 20+.

Full provider configuration — the Vitest `coverage` block, `.nycrc.json`, Jest's `coverageThreshold`, and `pyproject.toml` / `.coveragerc.toml` — plus install and run commands, lives in `references/tool-config.md`.

### Merging coverage across test types

Unit, integration, and E2E suites each cover only part of the codebase. Combine their results before judging gaps, or a line only exercised by an integration test will wrongly look untested:

- **Vitest** — configure multiple projects and let Vitest merge them, or merge the `coverage-final.json` outputs by hand.
- **nyc** — `nyc merge .nyc_output merged.json && nyc report -t merged` folds separate `.json` runs together.
- **coverage.py** — run each suite via `coverage run -p`, then `coverage combine`.

Always merge before applying the gate — never enforce a threshold against a single suite's coverage in isolation.

### Coverage Report Types

| Reporter | Output | Use Case |
|----------|--------|----------|
| `text` | Terminal table | Quick local check |
| `html` | Interactive HTML | Detailed local analysis, clicking through files |
| `lcov` | `lcov.info` file | SonarQube, Codecov, Coveralls integration |
| `json-summary` | `coverage-summary.json` | CI scripts, PR comments, dashboard metrics |
| `cobertura` | `cobertura-coverage.xml` | GitLab CI coverage visualization |

---

## Gap Analysis

A coverage report lists which lines and branches never executed — but not every gap deserves the same urgency. Rank by risk.

**Step 1: Produce the report.**

```bash
npm run test:coverage
# Open coverage/index.html in a browser
```

**Step 2: Rank files by how much is uncovered.** Parse `coverage-summary.json`, sort by `(total - covered)` descending, and focus on the worst 20 files. A short script that reads the summary JSON and prints file / line% / branch% / uncovered-count makes this a repeatable habit rather than a one-off.

**Step 3: Match each gap to a risk tier.**

| Gap Location | Risk Level | Action |
|-------------|-----------|--------|
| Payment processing | Critical | Write tests immediately |
| Auth/permissions | Critical | Write tests immediately |
| Data validation | High | Add to next sprint |
| Error handling paths | High | Add to next sprint |
| Utility functions | Medium | Cover when modifying |
| UI formatting | Low | Skip unless regression-prone |
| Generated code | None | Exclude from coverage |

Sort by branch coverage too, not lines alone — a file reporting 100% line / 50% branch coverage is hiding untested paths that a line-only ranking would mark "done."

---

## Coverage as CI Gate

### Threshold Configuration

Set one **global threshold** as the project-wide floor, then add **per-directory thresholds** that are tighter for high-stakes code (payments, auth) than for ordinary utilities. In Vitest, glob keys go under `thresholds` (e.g. `"src/payments/**": { lines: 95, branches: 90 }`); in Jest, path keys go under `coverageThreshold`. Both let you override per path.

The complete global, per-directory, and Jest per-file threshold examples are in `references/ci-gating.md`.

### Ratchet Pattern

Coverage should never drop. Capture the current level as a floor, and raise that floor whenever coverage improves. A ratchet script reads `coverage-summary.json`, compares each metric to a committed `.coverage-ratchet.json`, fails the build on any regression, and bumps the baseline up when things improve.

Commit `.coverage-ratchet.json` (for example, `{ "lines": 82, "branches": 78, ... }`). Run the ratchet script in CI right after tests finish. When a merge to main improves coverage, auto-commit the updated ratchet file.

The full `coverage-ratchet.ts` script is in `references/ci-gating.md`.

### PR Diff Coverage Gate

Hold new code in a PR to a higher bar (e.g. 90%) than the project's overall baseline. In CI, find changed files with `git diff --name-only origin/main...HEAD`, then look up their coverage in `coverage-summary.json`. Fail the pipeline if the changed files fall short of the threshold. This arrests decay without touching legacy code at all.

Post the diff for reviewers using `davelosert/vitest-coverage-report-action@v2` (which reads the JSON summary) or `marocchino/sticky-pull-request-comment@v2` combined with a script that narrows to changed files. The full PR workflow is in `references/ci-gating.md`.

**Hosted alternatives:** **Codecov**, **Coveralls**, and **Trunk Coverage** all provide differential PR coverage out of the box, complete with merge-blocking gates and inline annotations. Most teams are better off picking one of these than maintaining a homegrown diff script. For Codecov on GitHub: `codecov/codecov-action@v5` reads `lcov.info` and automatically posts a PR diff comment.

---

## Mutation Testing

Mutation testing checks *assertion quality*, not merely whether code ran. It introduces small changes to your source (flipping `>` to `>=`, deleting a statement) and checks whether any test notices. A mutant that survives means your tests wouldn't catch that bug in production. **Stryker JS v9.6+** paired with **Vitest 4.1+** keeps the cost low enough to run against PR-changed files; **mutmut 3.x** handles Python.

### Targeting

Running mutation testing across an entire codebase is costly — scope it **incrementally**. Stryker's `incremental: true` (backed by a JSON cache) combined with `--mutate` restricted to the git diff re-mutates only the files that changed; mutmut supports similar per-path scoping. Limit runs to:

- Pure business logic (validators, calculators, transformers)
- Critical paths (payment, auth, data integrity)
- Code with strong line coverage but questionable assertions (branch coverage above 90% yet few distinct assertion cases)

Leave UI rendering, glue code, and generated code out of scope.

The Stryker config (`stryker.config.json`, incremental mode, restricting runs to changed files) and the mutmut invocation are both in `references/mutation-testing.md`.

### Reading the score

An 80% mutation score means 80% of the deliberately injected bugs were caught. It's normal for this number to sit below your coverage percentage — plenty of mutants fall into branches the coverage report already flagged as untested. The signal worth acting on is **high coverage paired with a low mutation score**: the code runs, but nothing about the assertions actually constrains its behavior.

---

## Meaningful vs Vanity Coverage

### Why 100% Coverage Is Usually Wrong

Reaching 100% means testing every branch of every line — including things like:
- Error handling for states that can't actually occur
- Default arms of exhaustive switches
- Framework lifecycle hooks nothing calls directly
- Defensive guards against data that's already been validated upstream

Tests written purely to close that last gap tend to be shallow, brittle, and useless at catching real defects.

### Diminishing Returns

| Coverage Range | Value | Effort |
|---------------|-------|--------|
| 0% to 60% | High — main paths, obvious regressions | Low |
| 60% to 80% | Medium — error paths, edge cases | Medium |
| 80% to 90% | Lower — unusual combinations, defensive code | High |
| 90% to 100% | Minimal — unreachable code, framework internals | Very high |

Most projects should land in the **75–85%** sweet spot, with critical paths (payments, auth) pushed higher (**90%+**). Set the global threshold in that sweet spot and reserve 90%+ per-directory thresholds for payment/auth code.

### What NOT to Cover

Excluding these keeps the denominator honest instead of artificially inflated. Note the reasoning for each exclusion somewhere visible (a CONTRIBUTING doc or coverage note) so the exclude list can't be used to quietly bury real gaps later.

```typescript
// vitest.config.ts / jest.config.js — exclude patterns
exclude: [
  "**/*.d.ts",              // Type definitions
  "**/index.ts",            // Barrel exports (re-exports only)
  "**/*.stories.{ts,tsx}",  // Storybook stories
  "**/generated/**",        // Auto-generated code (GraphQL, Prisma)
  "**/migrations/**",       // Database migrations
  "**/__mocks__/**",        // Test mocks
  "**/types/**",            // Type-only modules
]
```

### Quality Indicators Beyond Percentage

| Indicator | What It Measures | How to Get It |
|-----------|-----------------|---------------|
| **Mutation score** | Would tests catch a real bug? | Stryker / mutmut |
| **Branch coverage** | Are all conditional paths tested? | V8/Istanbul with branch reporting |
| **Critical path coverage** | Are payment/auth/data flows fully covered? | Per-directory thresholds |
| **Defect escape rate** | Do production bugs occur in tested code? | Post-incident analysis |
| **Coverage delta** | Is coverage improving or declining? | Ratchet pattern tracking |

---

## Anti-Patterns

### 1. Treating coverage as proof of quality
"90% coverage means we're well tested" is a dangerous shortcut. Coverage only confirms code executed, not that its behavior was checked. **Fix:** pair the percentage with a mutation score for critical modules — a test carrying zero assertions should tank the mutation score even while sitting at 100% line coverage.

### 2. Excluding files to inflate numbers
Slipping hard-to-test files (error handlers, integration modules) into the exclude list buries exactly the gaps that matter most. **Fix:** only exclude code that's genuinely untestable — generated files, type-only definitions, barrel exports — and write down why for each one.

### 3. Writing trivial tests to hit targets
`it("should exist", () => expect(MyClass).toBeDefined())` adds a covered line but zero value. **Fix:** every test should verify behavior that would hurt users if it broke; mutation testing exposes these no-op tests for what they are.

### 4. Global threshold without per-module analysis
An 80% global threshold can pass comfortably even with payments sitting at 30%, so long as utility code drags the average up. **Fix:** set per-directory thresholds of 90%+ specifically for payment/auth code.

### 5. Coverage threshold set once, never adjusted
A team parked at 78% for six months isn't actually improving. **Fix:** let the ratchet push the floor upward automatically, and revisit it quarterly if it stalls.

### 6. Ignoring branch coverage
`const r = cond ? a : b` reports 100% line coverage even if one branch is never taken. **Fix:** always report and gate on `branches`, not just `lines`.

### 7. Coverage from E2E tests only
One E2E test can touch 60% of the codebase without exercising a single edge case — wide but shallow. **Fix:** track unit/integration coverage separately from E2E and gate on that total; treat E2E coverage as a bonus signal, never the gate itself.

---

## Verification

Confirm the gate would actually catch a regression — a build that stays green no matter what proves nothing.

1. **Threshold fires:** temporarily drop one committed metric below its current value (or delete a passing test), run `npm run test:coverage` (or `pytest --cov=src --cov-fail-under=80`), and check for a **non-zero exit code**. Revert afterward.
2. **Ratchet fires:** with `.coverage-ratchet.json` already committed, remove a test to force a regression, run the ratchet script, and confirm it prints `FAIL: ... coverage dropped` and exits with 1.
3. **Branch gate is live:** verify the report includes a `branches` column and that `branches` shows up in the threshold config, not only `lines`.
4. **PR diff renders:** open a draft PR that touches a single source file and confirm the coverage-diff comment appears with that file's actual numbers.

If step 1 returns exit code 0 after you deliberately dropped coverage, the gate isn't actually wired — fix it before calling this Done.

---

## Done When

- Coverage generation happens automatically on every CI push, with no manual step required.
- CI enforces the coverage threshold: the build exits non-zero whenever line **or branch** coverage drops below the defined minimum (confirmed via Verification step 1).
- The coverage report is uploaded as a CI artifact (HTML + `json-summary`), and each PR gets a coverage-delta comment.
- The coverage config includes an exclude list plus per-directory thresholds (90%+ for payments/auth), and a CONTRIBUTING/coverage doc explains the reasoning behind each exclusion.
- The ratchet is functioning: `.coverage-ratchet.json` is committed, the ratchet script runs as part of CI, and the build fails on any regression from the recorded baseline (confirmed via Verification step 2).

## Reference Files (in `references/`)

- **tool-config.md** — Full provider configs for Vitest (`@vitest/coverage-v8` / `-istanbul`), the c8 CLI for non-Vitest runners, nyc, Jest, and coverage.py, with install and run commands.
- **ci-gating.md** — PR coverage-diff workflow, global/per-directory/per-file thresholds, and the `coverage-ratchet.ts` script.
- **mutation-testing.md** — Stryker (`stryker.config.json`, incremental) and mutmut configuration for measuring assertion quality.

## Related Skills

- **unit-testing** — Writing the tests that raise coverage: mocking strategies, framework-specific config, and Vitest `coverage.changed` for changed-files-only coverage in CI. Go there to author tests; this skill measures and gates them.
- **ci-cd-integration** — Pipeline wiring for coverage gates, artifact storage, and PR comments.
- **qa-metrics** — Coverage as a tracked KPI trend over time alongside mutation score and defect escape rate. Go there for dashboards and trends; this skill is per-repo configuration and gating.
- **ai-qa-review** — AI-assisted identification of undertested paths and Vitest browser mode for component coverage parity.
