---
name: ai-qa-review
description: >-
  Review EXISTING test code for quality, smells, and testability issues. Detects
  test smells across six dimensions — readability, reliability, diagnostic value,
  design, AI-generated, and coverage — analyzes testability of application code,
  and backs the qualitative smells with mutation testing.
  Use when: "review my tests," "test quality audit," "test smells," "testability
  analysis," "are these tests any good." Not for: generating new tests — use
  `ai-test-generation`. Not for: testing AI features in your product — use
  `ai-system-testing`.
  Related: unit-testing, shift-left-testing, coverage-analysis, ai-test-generation.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: ai-qa
---

<objective>
A QA-oriented code review discipline for spotting test smells, judging how testable application code really is, and surfacing coverage gaps. An assertion of `toBe(true)` and a suite sitting at 95% coverage that only ever exercises the happy path can both look perfectly healthy while hiding real bugs. This skill's job is to name the smell precisely, point at the offending line, and turn a vague "looks fine" into a hard mutation-score gate.

**Before starting:** Look for `.agents/qa-project-context.md` at the project root first. When present, it carries the team's test-framework conventions, naming patterns, and quality bar, and should shape how feedback is calibrated.
</objective>

---

## Quick Route

There are three distinct ways into this skill. Find your row, then jump straight to the section it points to.

| Situation | Path | Jump to |
|-----------|------|---------|
| PR with changed test files | Execute the changed files, score them, hold the diff up against the PR checklist | **Verification** → **PR Review Checklist** |
| Whole suite needs a health pass | Measure it, sample it, surface the 3-5 systemic smells, propose lint/mutation gates | **Batch Audit Process** |
| Application code, "why is this hard to test?" | Call out DI / side-effect / pure-function / interface issues with concrete before/after examples | **Testability Analysis** |

Regardless of entry point, all three paths draw from the same six smell buckets and the same Verification commands.

---

## Discovery Questions

Start by checking `.agents/qa-project-context.md` for answers — skip anything it already covers.

1. **Review scope:** Is this a review of test code quality, of application code testability, or both? The answer determines which Quick Route path applies.
2. **Framework conventions:** Which test framework is in play — Jest, Vitest, Playwright, pytest? `describe/it` nesting, fixture handling, and assertion style all vary, and so do the Verification commands.
3. **PR review or batch audit?** A PR review scores only the files that changed. A batch audit sweeps the whole suite looking for systemic issues.
4. **Existing quality standards:** Has the team written down its own test conventions anywhere — `.eslintrc` test rules, a `CONTRIBUTING.md` section, a style guide?
5. **Known pain points:** Any recurring flakiness, slow runs, or confusing failures? These should steer which smells get attention first.

---

## Core Principles

1. **Test code deserves the same bar as production code.** Readability, maintainability, single responsibility all apply. Tests that are hard to read are tests nobody trusts.

2. **Judge what's asserted, not merely what's executed.** A line running doesn't mean a wrong result would be noticed. A suite full of `toBeTruthy` calls at 95% coverage catches next to nothing. Mutation score (see **Verification**) is the metric that fills that gap.

3. **Testability review heads off test debt before it accumulates.** Catching design flaws in application code early avoids the awkward test workarounds those flaws otherwise force. Code that resists testing usually resists maintenance too.

4. **Turn repeated feedback into tooling.** If review comments keep repeating, that's a sign of missing automation — codify the pattern as a lint rule, a custom ESLint plugin, or a shared fixture instead of typing it again.

5. **A smell is a symptom, not a sentence.** It flags a possible problem; whether it's actually harmful depends on context. A long test covering a genuinely complex workflow can be entirely appropriate, and a mock-heavy test at a system boundary can be the right call.

6. **Only give feedback that can be acted on.** Every comment needs to state what's wrong, why it matters, and how to fix it. "This test is bad" fails that bar. "This test uses sleep-based waiting, which causes flakiness — swap in an explicit wait condition" clears it.

---

## Test Smell Buckets

There are six dimensions. Every smell belongs to one and maps to a specific review action. The complete SMELL/FIX code samples for the whole catalog live in `references/smell-examples.md` — keep the inline pointers to it visible, since that before/after code is where the real value is.

### Readability Smells

Issues that make a test hard to parse at a glance.

#### Obscure Setup

**What it looks like:** Thirty-plus lines building objects, most of it irrelevant, burying the actual point of the test. The reader can't tell which fields the assertion even cares about.

**Fix:** Pull construction out into factories. Only data that matters to the test should appear in its body — e.g. `buildOrder({ items: [buildItem({ weight: 2.5, quantity: 2 })] })` rather than assembling entire user/product/order graphs inline.

**Review action:** Ask for factory extraction.

#### Mystery Guest

**What it looks like:** `loadFixture('report.json')` — the test leans on external data invisible to the reader, who now has to go open another file just to follow the assertion.

**Fix:** Either bring the relevant data inline, or give fixtures names descriptive enough that the test reads clearly on its own.

**Review action:** Ask for inlined data or better-named fixtures.

#### Duplicate Assertions

**What it looks like:** Several tests all check the same underlying behavior at different levels of precision (`toBe('Alice')`, `toHaveProperty('name')`, `toBeDefined()`) — three tests for one behavior.

**Review action:** Ask for consolidation, keeping only the sharpest assertion. Redundant tests add upkeep cost without adding confidence.

---

### Reliability Smells

Issues that make tests fail intermittently or only in certain environments.

#### Sleep-Based Waiting

**What it looks like:** `setTimeout`, `sleep()`, `waitForTimeout()` standing in for real synchronization. See `references/smell-examples.md` for the SMELL/FIX pair (swapping `waitForTimeout` for an explicit `toBeVisible` wait).

**Review action:** Reject outright. There's no acceptable use of sleep-based waiting — require an explicit wait condition instead.

#### Order Dependency

**What it looks like:** Tests that pass as a group but fail alone or in a different sequence. See `references/smell-examples.md` for the SMELL/FIX pair (each test building its own preconditions).

**Review action:** Ask for data isolation — every test should set up whatever state it needs itself.

#### External Service Coupling

**What it looks like:** Tests hitting real external systems — payment gateways, email providers, other third-party APIs. See `references/smell-examples.md` for the SMELL/FIX pair (mocking at the service boundary).

**Review action:** Ask for a mock or fake at that boundary. Genuine external calls belong in integration or contract tests, not unit tests.

---

### Diagnostic Smells

Issues that make a failing test hard to interpret and debug.

#### Weak Assertion Messages

**What it looks like:** A failure that tells you nothing about what was expected or why. See `references/smell-examples.md` for the SMELL/FIX pair (trading `toBe(true)` for a specific assertion such as `expect(result.errors).toEqual([])` that surfaces the actual offending value).

**Review action:** Ask for sharper, more diagnostic assertions — the failure message alone should explain the problem, without needing to open the test source.

#### Multiple Failure Causes Per Test

**What it looks like:** One test quietly covering several independent behaviors, so a failure doesn't tell you which one broke. See `references/smell-examples.md` for the SMELL/FIX pair (breaking a lifecycle test into one test per behavior).

**Review action:** Ask for the test to be split. Each test should have exactly one reason to fail.

---

### Design Smells

Issues in how tests are architected that raise long-term maintenance cost.

#### Conditional Test Logic

**What it looks like:** `if/else`, `switch`, ternaries, or `for` loops living inside a test body. Branching in a test is itself unverified — there's no way to know which branches actually executed. See `references/smell-examples.md` for the SMELL/FIX pair (turning a branching loop into `it.each`).

**Review action:** Ask for parameterized tests (`it.each` / `test.each`). Conditional logic inside tests obscures which cases genuinely get checked.

#### Giant Fixtures

**What it looks like:** A `beforeEach` or fixture standing up 20+ objects for every single test, when any given test only touches 2-3 of them. See `references/smell-examples.md` for the SMELL/FIX pair (replacing a monolithic `beforeEach` with per-test inline setup).

**Review action:** Ask for inline setup. Shared setup belongs in factories, not one large `beforeEach`.

#### Over-Mocking

**What it looks like:** Everything gets mocked, including simple value objects and pure functions. See `references/smell-examples.md` for the SMELL/FIX pair (dropping a mock of the very function under test).

**Review action:** Ask for the unnecessary mocks to be removed. Mock at the boundaries, not the internals.

---

### AI-Generated Test Smells

When a coding agent (Claude Code, Codex, Cursor, Copilot) authored the tests, the same taxonomy applies, but a handful of failure modes show up often enough to warrant a dedicated pass.

| Smell | Detection |
|-------|-----------|
| **Hallucinated locator** | Run the test against a real page once. If the locator never matches anything, the model invented a `data-testid` that isn't there. |
| **Fabricated import** | Statically verify every imported symbol actually exists in its file or package. Models will invent plausible-sounding APIs (`@testing-library/something-that-doesnt-exist`). |
| **Generic test data** | `example.com`, `test@test.com`, `Lorem ipsum`, `John Doe` — filler the agent reached for because no project-specific factory existed. Swap in the project's real data factory. |
| **Closed AI loop** | The same agent, same session, wrote both the implementation and its tests. The tests end up describing what got produced rather than constraining it. Pair the agent's tests with at least one human-authored boundary test, or apply TDD (test-first) per `shift-left-testing`. A low mutation score (see **Verification**) is the telltale sign. |
| **Project-convention drift** | Page Object structure, fixture style, naming, or assertion patterns that don't match the rest of the suite. AI-generated code rarely lands on local conventions unprompted. |

For first-time test generation guidance and its Step-7 review checklist, cross-link `ai-test-generation`. For evaluating AI-system *behavior* itself (the prompt equivalent of ESLint), wire each tool's CLI runner — `promptfoo eval`, `deepeval test run` (Apache 2.0), Ragas `ragas evaluate` / experiments (Apache 2.0) — in as a quality gate alongside your normal test runner.

> **Promptfoo ownership note:** Promptfoo was acquired by OpenAI (announced 9 Mar 2026). The core remains MIT-licensed, open source, and model-agnostic; red-team capabilities are being absorbed into OpenAI Frontier. `promptfoo eval` remains the right quality-gate command — just expect OpenAI as the vendor going forward.

### Coverage Smells

Issues that leave real gaps in what's actually verified.

#### Happy Path Only

**What it looks like:** Every test hands in valid input and expects success — no error paths anywhere. See `references/smell-examples.md` for the SMELL/FIX pair (adding zero, max, negative, and boundary cases to a discount calculator).

**Review action:** Ask for the missing scenarios. Apply the BOUNDARY framework: Boundary values, Null/empty, Duplicates, Ordering, Range limits.

#### Missing Boundary Cases

**What it looks like:** Tests cover "typical" values like 5 items but skip 0, 1, max, and max+1. Use `it.each` to name the boundaries explicitly: empty collection, single item, exact page size, one over, large set.

**Review action:** Ask for boundary tests. Every numeric parameter, string length, and collection size has edges worth testing.

#### Missing Error/Negative Cases

**What it looks like:** Nothing verifies what happens when things go wrong — network failure, bad input, denied permissions, concurrent modification.

**Review action:** For every happy-path test, ask: "what's the matching failure mode?" and request a test for it.

---

## Testability Analysis

When reviewing application code, judge whether its structure supports testing at all. Each of these has a corresponding hard-to-test vs. testable before/after in `references/testability-refactors.md`.

### Dependency Injection

Flag classes that construct their own dependencies inline (`new PostgresDatabase()`, `new StripeClient()` inside a method). Push for constructor injection so tests can drop in mocks or fakes. See `references/testability-refactors.md`.

### Side Effect Isolation

Flag functions that tangle pure calculation together with I/O (email, logging, analytics). Pull the calculation out as a pure function and have the side-effectful orchestrator call it. See the `calcTotal` before/after in `references/testability-refactors.md`.

### Pure Function Extraction

Watch for validation, transformation, and business rules buried in request handlers. Logic sitting inline in `app.post('/api/orders', ...)` can't be unit-tested without standing up an HTTP server — pull it out as a standalone function. See the `shippingFor` before/after in `references/testability-refactors.md`.

### Interface Segregation

Flag classes that depend on sweeping interfaces (the entire `PrismaClient`) while touching only 2-3 methods. Suggest narrowing to an interface with just the methods actually used, so test doubles become trivial to write. See `references/testability-refactors.md`.

---

## Review Workflow

### PR Review Checklist

Work through each test file in a PR systematically:

```markdown
## Test Quality Review

### Readability
- [ ] Can I understand what each test verifies in under 10 seconds?
- [ ] Is setup minimal and test-relevant?
- [ ] Are test names descriptive: "should [behavior] when [condition]"?

### Reliability
- [ ] No sleep/waitForTimeout/setTimeout for synchronization?
- [ ] No shared mutable state between tests?
- [ ] No dependency on test execution order?
- [ ] No calls to real external services?

### Diagnostic Value
- [ ] Will failures produce messages that identify the problem?
- [ ] Does each test have one reason to fail?
- [ ] Are assertions specific (not toBeTruthy/toBeDefined)?

### Design
- [ ] No conditional logic (if/else/switch/for) in test bodies?
- [ ] Fixtures/setup proportional to what each test needs?
- [ ] Mocking limited to external boundaries?
- [ ] Parameterized tests (it.each) used for data-driven scenarios?

### AI-Generated (if applicable)
- [ ] Locators verified against a real page (no hallucinated data-testid)?
- [ ] Imports resolve (no fabricated APIs)?
- [ ] Project data factory used, not test@test.com / John Doe?

### Coverage
- [ ] Happy path AND error/negative paths tested?
- [ ] Boundary values tested (0, 1, max, max+1)?
- [ ] Edge cases: empty, null, duplicate, concurrent?
```

### Batch Audit Process

For auditing an entire test suite:

1. **Quantify:** Tally tests by type (unit/integration/E2E), framework, and directory.
2. **Sample:** Review 10-20% of files, weighted toward the largest and most recently touched.
3. **Pattern:** Pull out the 3-5 smells that show up most often across the sample.
4. **Prioritize:** Order by impact: reliability smells > diagnostic smells > design smells > readability smells.
5. **Automate:** For each recurring smell, decide whether an ESLint rule or mutation-score gate could catch it going forward.
6. **Report:** Write up findings (one row per file reviewed), including concrete examples, suggested fixes, severity (high/medium/low), and rough effort estimates.

---

## Prompt Templates

Three prompt patterns to drive AI-assisted review:

1. **Review test quality:** "Check this test file for readability, reliability, diagnostic, design, AI-generated, and coverage smells. For each issue: name the smell, cite the line, explain why it matters, and provide a fix."

2. **Identify coverage gaps:** "Given this application code and its existing tests, identify missing scenarios across happy path, error handling, boundaries, edge cases, concurrency, and security. Prioritize as P0/P1/P2."

3. **Testability improvements:** "Review this application code for hard-coded dependencies, mixed side effects, extractable pure functions, and overly broad interfaces. Show current vs. refactored code."

---

## Anti-Patterns

1. **Judging test code only by production-code standards.** Test code carries extra quality dimensions — reliability, diagnostics, coverage — that ordinary production-code linters never check. Apply the six smell buckets, not just generic "clean code" thinking.

2. **Flagging every smell with no regard for context.** A 50-line test for a genuinely complex state machine isn't obscure setup — that's necessary complexity. Weigh each smell against the behavior actually under test.

3. **Reaching for mocks everywhere.** Over-mocking is itself a smell. Don't suggest mocking pure functions, value objects, or fast in-process collaborators. Reserve mocks for real boundaries: network, database, filesystem, clock.

4. **Chasing coverage percentage instead of coverage quality.** 95% line coverage made up entirely of happy-path tests is worse than 75% that includes error paths and boundaries. Judge what's asserted, not just what ran — and back that judgment with a mutation score.

5. **Reviewing without ever running anything.** Static reading alone misses runtime problems. Run the suite (see **Verification**), rerun it to check for flakiness, and note execution time. A suite that passes but takes 20 minutes has a performance smell of its own.

6. **Treating review as a one-off.** Test quality erodes over time. Set up a recurring review cadence or automated gates (a lint rule, a mutation threshold) that catch regressions on their own.

---

## Verification

Run these before writing a single comment — they're the runtime checks this skill expects, spelled out concretely. Scope to the PR's changed test files for a PR review; run the whole suite for a batch audit.

1. **Run the suite once.** Confirm it's green before reviewing anything — never review red or skipped tests as though they pass.
   - Vitest: `npx vitest run <files>` · Jest: `npx jest <files>` · Playwright: `npx playwright test <files>` · pytest: `pytest <files>`
2. **Run it again to expose flakiness.** A test passing once and failing the next run is a reliability smell, not bad luck.
   - Vitest: `npx vitest run --retry=0 <files>` looped, or `for i in 1 2 3; do npx vitest run <files> || break; done`
   - Jest: `npx jest <files> && npx jest <files> && npx jest <files>` (or `jest-circus` repeat)
   - Playwright: `npx playwright test --repeat-each=3 <files>`
   - pytest: `pytest --count=3 <files>` (pytest-repeat) or `pytest -p no:randomly` vs random order to catch order dependency
3. **Capture per-test timing.** A suite that takes 20 minutes has a performance smell.
   - Vitest: `--reporter=verbose` (prints per-test duration) · Jest: `--verbose` · Playwright: `--reporter=list` · pytest: `--durations=10`
4. **Mutation score — the objective backstop.** For the qualitative smells that resist eyeballing at scale (Closed AI loop, weak assertions), run a mutation runner and check the resulting score. AI-generated tests scoring under roughly 60% aren't actually constraining the implementation. Full tooling, thresholds, and configuration live in `references/mutation-testing.md`.
   - JS/TS: `npx stryker run` · Java: PIT `mvn ... mutationCoverage` · Rust: `cargo mutants` · Python: `mutmut run`

Steps 1-3 together with the mutation score form the evidence behind every "reliability"/"diagnostic" finding that goes into the report.

---

## Done When

- A findings artifact exists with one row per reviewed file, each carrying a severity rating (high/medium/low). (file exists, row count == files reviewed)
- Every applicable smell dimension is addressed: readability, reliability, diagnostic, design, AI-generated, coverage. (six headings present in the report; "N/A" allowed, blank not)
- Every high-severity finding includes an actionable remediation (what + why + fix), not just a description of the problem.
- Verification actually ran: the suite passed at least 3 consecutive times (no flaky failures), per-test timing was captured, and for AI-generated suites a mutation score was recorded.
- At least one recurring smell has been turned into an automated gate — an ESLint rule, a CI check, a committed mutation-score threshold — or the report explicitly says none was warranted.

---

## Reference Files (in `references/`)

- **smell-examples.md** — Full SMELL/FIX code for every catalogued smell across reliability, diagnostic, design, and coverage dimensions.
- **testability-refactors.md** — Hard-to-test vs. testable before/after for all four testability subsections: dependency injection, side effect isolation, pure function extraction, interface segregation.
- **mutation-testing.md** — Tooling (Stryker/PIT/cargo-mutants/mutmut), thresholds, Stryker config, and the AI-loop / weak-assertion gate.

---

## Related Skills

- **unit-testing** — Framework-specific patterns (Jest, Vitest, pytest) that inform what "good" looks like for each framework.
- **shift-left-testing** — Pre-commit hooks and IDE integration that catch test smells before review.
- **coverage-analysis** — Interpreting coverage reports to find meaningful gaps, not just percentage targets.
- **ai-test-generation** — Generated tests need review too. Apply these smell checks to AI-generated test code.
- **test-reliability** — Reliability smells (sleep-based waits, order dependency) overlap with flaky test patterns.
</content>
