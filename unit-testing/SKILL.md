---
name: unit-testing
description: >-
  Guidance for writing solid unit tests across Jest, Vitest, and pytest: the
  stub/spy/mock/fake test-doubles taxonomy, the Arrange-Act-Assert shape, setting up
  and gating on coverage thresholds in CI, snapshot tests, fake timers, and mutation
  testing via Stryker/mutmut.
  Use when: "unit test," "Jest," "Vitest," "pytest," "mock," "coverage threshold,"
  "test doubles," "mutation testing," "fake timers," "snapshot test."
  Not for: reading coverage output or hunting down coverage gaps (that's
  coverage-analysis); having an AI author the test code itself (ai-test-generation);
  auditing pre-existing tests for smell/quality issues (ai-qa-review); assertions on
  browser or component rendering (cypress-automation or visual-testing).
  Related: coverage-analysis, ci-cd-integration, ai-test-generation, shift-left-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: automation
---

<objective>
The point of a unit test is to fail the moment the code is wrong and stay green the
moment it's right — nothing softer than that. A suite that mocks out every collaborator
can stay green even while the integration between those collaborators is broken; the
doubles taxonomy in this skill exists to head that off. Likewise, a single mistyped
config key — `coverageThresholds` instead of `coverageThreshold` — lets code sitting at
40% coverage ship through a pipeline that reports green, because Jest silently ignores
the plural key. The config guidance and Verification steps below exist to make sure the
gate is actually armed. This skill spans Jest, Vitest, and pytest, covering test
doubles, coverage gating, snapshots, fake timers, and mutation testing as a check on
whether coverage is actually meaningful.
</objective>

---

## Before You Start: Discovery

Look for `.agents/qa-project-context.md` first. If it's there, treat it as already
answering these questions and only chase down what it leaves open.

1. **Which runner?** Jest, Vitest, or pytest — read `package.json` or `pyproject.toml`
   to find out. The answer decides which config keys and mocking APIs apply.
2. **Is coverage tooling already wired up?** Look for `jest.config.*`, `vitest.config.*`,
   `.nycrc`, or a `[tool.coverage]` block. This tells you whether you're introducing the
   gate from scratch or just adjusting an existing one.
3. **How is mocking done here?** Manual mocks, auto-mocking, or dependency injection —
   check for `__mocks__/` folders or DI containers, since that shapes which doubles fit
   naturally into the codebase.
4. **Where do tests live?** Co-located next to source (`*.test.ts`) or gathered in a
   `__tests__`/`tests/` tree? Match the existing convention rather than starting a third
   pattern.

---

## Principles That Don't Change By Framework

**1. Assert on behavior, never on internals.** A test should care about *what* the code
produces, not *how* it gets there — so refactoring the internals shouldn't break it.

```typescript
// Bad — implementation detail        // Good — observable behavior
expect(svc._cache.size).toBe(3);      expect(svc.getUser("abc")).toEqual({ id: "abc", name: "Alice" });
```

**2. Keep tests fast, isolated, and deterministic.** That means no network, disk, or
database calls, no state shared between tests, and no unguarded `Date.now()` or
`Math.random()` — pin those down with fake timers and fixed seeds.

**3. Shape each test as Arrange-Act-Assert.** One consistent structure, every time.

```typescript
it("should apply discount for orders over $100", () => {
  // Arrange
  const order = createOrder({ subtotal: 150 });
  const svc = new DiscountService(0.1);
  // Act
  const result = svc.apply(order);
  // Assert
  expect(result.total).toBe(135);
});
```

**4. A test should verify one concept.** It's fine to have several `expect` calls, as
long as they're all checking the same underlying idea.

**5. Name tests by what they prove.** Favor `"should [behavior] when [condition]"` over
something opaque like `"test calculateTotal"`.

---

## What To Reach For, Per Framework

Complete setup/teardown, mocking, spying, timer, in-source, and monorepo examples for
each runner are kept in `references/patterns.md`, organized by framework. What follows
here is the current state of each ecosystem and what to default to; pull the actual code
from the reference file.

### Jest

The current release line is **Jest 30.x** (30.4.2, May 2026), which brought
`--collect-tests`, support for `jest.config.mts`, Temporal-aware fake timers, and
`clearMocksOnScope`. If the code you're testing touches the Temporal API or does
timezone math, the Temporal-aware fake timers in Jest 30 eliminate a category of
fragile setup code.

Default toolkit: `jest.mock()` for boundaries between modules (pair with
`jest.requireActual` when you only want to override part of a module), `jest.spyOn()`
when you want to keep the real method but observe calls to it, `jest.Mocked<T>` for
typed mocks, and `jest.useFakeTimers()` for anything time-based. Full examples:
`references/patterns.md` § Jest.

### Vitest

Vitest mirrors Jest's API but is built for Vite. The stable line is **Vitest 4.1.x**
(June 2026), with **5.0.0-beta** already out (beta.3, May 2026). Version 4 introduced
`coverage.changed` (coverage scoped to changed files only), `mockThrow`/`mockThrowOnce`,
and a browser mode that's now stable. Note that the Vitest 5 beta **drops the
`sequential` option** and needs **Node 22 / Vite 6.4** — hold off adopting it until it's
out of beta. Mocking uses `vi.mock`/`vi.spyOn`; the two features that set Vitest apart
are **in-source testing** (`import.meta.vitest`) and **browser mode** for testing
components as rendered. Full examples: `references/patterns.md` § Vitest.

### pytest

Build tests around fixtures and `conftest.py` (use `yield` inside a fixture for
teardown), reach for `@pytest.mark.parametrize` when a test is really the same check run
over several inputs, and use `monkeypatch` to substitute environment variables or
attributes. Fixtures beat `setUp`/`tearDown` methods here because they compose and stay
isolated per test. Full examples: `references/patterns.md` § pytest.

### Bun / Deno

`bun test` (Jest-compatible out of the box, no config needed) and `deno test`
(native TypeScript with permission flags) are perfectly reasonable choices when the
project's runtime is already Bun or Deno. For Node projects, though, Vitest or Jest
still win on plugin ecosystem depth.

---

## Choosing a Test Double

Reach for the least powerful double that gets the job done — in practice that's usually
a stub.

| Double | What it does | When to use |
|--------|-------------|-------------|
| **Stub** | Returns canned data, no verification | Control a dependency's return value |
| **Spy** | Wraps real impl, records calls | Verify calls without changing behavior |
| **Mock** | Replaces impl + records calls | Control return AND verify interaction |
| **Fake** | Simplified working impl (in-memory DB) | Complex stateful dependencies |

**Rule of thumb:** lean on stubs over mocks, save fakes for dependencies that carry
state, and never let a unit test hit a real external API. The only things worth mocking
are the **external boundaries** — network, filesystem, database, time. Everything else —
the fast, deterministic collaborators internal to your code — should run for real, or
you end up with a suite that's green while the wiring between pieces is actually broken.
All four doubles shown in code: `references/patterns.md` § Test doubles.

---

## Coverage

### Wiring up the config

**Jest** — the correct key is **`coverageThreshold`**, singular. Writing the plural
`coverageThresholds` is **not a mistake Jest will catch** — it's simply not a recognized
key, so Jest ignores it, the gate never actually enforces anything, and CI happily stays
green with 30% coverage. This is, by far, the most common config bug in this area.

```javascript
// jest.config.js
module.exports = {
  coverageProvider: "v8",
  collectCoverageFrom: ["src/**/*.ts", "!src/**/*.{d,test,stories}.ts", "!src/**/index.ts"],
  coverageThreshold: { global: { branches: 80, functions: 80, lines: 80, statements: 80 } },
};
```

**Vitest** — configure `test.coverage.thresholds` inside `vitest.config.ts` with
`provider: "v8"` (see `references/patterns.md` § Vitest for the complete block).

**pytest:**

```toml
# pyproject.toml
[tool.coverage.run]
source = ["src"]
omit = ["src/**/test_*.py", "src/**/conftest.py"]
[tool.coverage.report]
fail_under = 80
show_missing = true
exclude_lines = ["pragma: no cover", "if TYPE_CHECKING:"]
```

### Which coverage metric to gate on

| Type | Measures | Blind spots |
|------|----------|-------------|
| **Branch** | Every if/else path taken? | Misses value combinations |
| **Line** | Each line executed? | Misses untested branches in one line |
| **Statement** | Each statement executed? | Similar to line |
| **Function** | Each function called? | Nothing about correctness |

**In order of how much they tell you:** Branch > Line > Statement > Function. Treat
**80% line coverage as a floor to enforce**, not a target to chase for its own sake, and
weight branch coverage more heavily than the rest. Spend coverage effort on business
logic, data transformations, error handling, and edge cases — and don't bother covering
generated code, type-only definitions, barrel exports, trivial getters, or framework
scaffolding.

> Deciding *which* uncovered lines actually matter, and doing that gap analysis, belongs
> to `coverage-analysis` — not here.

### Making CI actually enforce it

Jest and Vitest already exit with a non-zero code when a threshold fails, so that exit
code itself is the enforcement mechanism. pytest, on the other hand, needs to be told
explicitly:

```yaml
- run: pytest --cov=src --cov-fail-under=80
```

---

## Mutation Testing

Coverage only tells you which lines *executed*. Mutation testing asks a sharper
question: would the suite actually *notice* a bug? It does this by making tiny changes
to the source (flipping `>` to `>=`, `true` to `false`, and so on) and re-running the
suite against each mutated version. If the suite still passes despite the mutation, that
mutant **survived** — meaning your tests ran that line of logic but never actually
asserted anything about it.

### Stryker (JS/TS)

```bash
npm i -D @stryker-mutator/core @stryker-mutator/jest-runner  # or vitest-runner
```

```javascript
// stryker.config.json  (Stryker's documented default; .mjs/.mts also load)
{
  "testRunner": "jest",
  "coverageAnalysis": "perTest",
  "mutate": ["src/**/*.ts", "!src/**/*.test.ts"],
  "thresholds": { "high": 80, "low": 60, "break": 50 },
  "reporters": ["html", "clear-text", "progress"]
}
```

Out of the box, Stryker defaults to `{ high: 80, low: 60, break: null }`, and a `break`
of `null` means nothing ever fails the build on score alone. Give `break` a real number
(50, for instance) if you want a weak score to fail CI. Kick it off with
`npx stryker run`.

### mutmut (Python) — mutmut 3.x

mutmut 3 replaced its old CLI entirely. Paths to mutate now live in a `[mutmut]` config
block rather than a flag; run the tool, then walk through survivors in its TUI:

```ini
# setup.cfg  (or a [tool.mutmut] table in pyproject.toml)
[mutmut]
paths_to_mutate=src/
```

```bash
pip install mutmut          # 3.5.x
mutmut run                  # paths come from config, not a flag
mutmut browse               # interactive TUI: inspect and retest survivors
mutmut apply <mutant_id>    # write a survivor to disk to see what it changed
```

> **Don't use:** `mutmut run --paths-to-mutate=src/`, `mutmut results`, or
> `mutmut show 42` — those belonged to mutmut <3. The `--paths-to-mutate` flag no longer
> exists (paths now live in the `[mutmut]` config block), and `results`/`show` were
> replaced by `browse`/`apply` (confirmed against mutmut 3.5.x, June 2026). Running the
> old commands against a current install just errors out.

### Reading the score

| Score | Meaning |
|-------|---------|
| 90%+ | Strong — catching most logic changes |
| 70–89% | Decent — review survivors in critical paths |
| <70% | Tests execute code but do not verify behavior |

Point mutation testing at **critical business logic** rather than the whole codebase —
it's slow. And don't chase equivalent mutants: those are mutations that produce
logically identical behavior, so no test could ever distinguish them regardless of how
good the suite is.

---

## Snapshot Testing

**Reach for it when:** you're checking UI component render output, serialized data
structures, or CLI output — cases where the exact shape of the output matters but
asserting it field-by-field would be tedious.

**Skip it when:** the output changes often (leads to snapshot fatigue and reviewers
rubber-stamping diffs), the snapshot is large (nobody actually reviews it), it captures
implementation details like CSS classes or internal IDs, or a single targeted assertion
would tell you what you actually need to know.

Favor **inline** snapshots when the output is short (under 20 lines), and use
**property matchers** (`expect.any(String)`) for fields that legitimately vary, like ids
and timestamps. Always run CI with the `--ci` flag so that an unrecognized snapshot
**fails the build** instead of quietly being written to disk and committed. Code:
`references/patterns.md` § Snapshot testing.

---

## Watch Out For These

**Reaching into private methods to test them** — test through the public API instead.
If a private method truly needs dedicated tests, that's a signal to pull it out into its
own module with a public interface.

**Mocking every single collaborator** — only the external boundaries (network,
filesystem, DB, time) deserve a mock. If everything is mocked, the suite stays green
even when the actual wiring between pieces is broken.

**Writing `coverageThresholds` instead of `coverageThreshold`** — Jest silently ignores
the plural, so the gate never triggers and CI passes at any coverage level whatsoever.
The correct key is singular. See the Coverage section above.

**Faking every timer without thinking about it** — calling `jest.useFakeTimers()` or
`vi.useFakeTimers()` with no allowlist can deadlock code that's waiting on a genuine
microtask. Only fake the specific timers the test actually needs, via `doNotFake` /
`toFake`. See `references/patterns.md` § Jest timers.

**Dropping `await` in an async test** — a missing `await` means the assertion inside
never actually runs, and the test passes without checking anything. Guard against this
with `expect.assertions(n)` / `expect.hasAssertions()` on async tests.

**Leaning on snapshots when a simple assertion would do** — write
`expect(x).toBe("active")` for a known specific value, and save snapshots for
genuinely structured output that's impractical to assert field-by-field.

**Vague test names** — swap something like `"works"` for
`"should return empty array when no items match the filter"`.

**Letting state leak between tests** — initialize fresh state in `beforeEach` instead of
at module scope:

```typescript
// Bad: shared mutation               // Good: fresh per test
const items = [];                     let items: string[];
it("A", () => items.push("a"));       beforeEach(() => { items = []; });
it("B", () => {                       it("A", () => { items.push("a"); expect(items).toHaveLength(1); });
  items.push("b");                    it("B", () => { items.push("b"); expect(items).toHaveLength(1); });
  expect(items).toHaveLength(1); // FAILS
});
```

---

## Verification

Before calling this done, confirm both that the suite actually runs and that the
coverage gate genuinely fails under-covered code — this is precisely what a
`coverageThreshold` typo would silently defeat.

1. **The suite runs and passes:** `npx jest` (or `vitest run`, `pytest -q`) should exit
   with code `0`.
2. **The gate has teeth.** Run coverage and check that it exits non-zero once you're
   below the threshold:
   ```bash
   npx jest --coverage --ci          # Jest/Vitest exit !=0 below coverageThreshold
   vitest run --coverage             # same for Vitest
   pytest --cov=src --cov-fail-under=80   # pytest exits !=0 below the floor
   ```
   Temporarily crank a threshold above what's currently covered (say, 99) and confirm
   the command now fails. An exit code of `0` there means your threshold key is
   misspelled — most likely the plural `coverageThresholds`.
3. **CI mode protects snapshots:** because the run uses `--ci`, an unrecognized
   snapshot fails the build instead of being written automatically. After a CI-mode
   run, `git status` should show no new `*.snap` files.

---

## Definition of Done

- Coverage thresholds are configured — `coverageThreshold` (singular) in
  `jest.config.*`, `coverage.thresholds` in `vitest.config.*`, or `fail_under` in
  `pyproject.toml` — AND confirmed (via Verification step 2) to exit non-zero below
  threshold
- Every test file lives in the one location the project has standardized on
  (co-located, or a `__tests__`/`tests/` tree) — `git ls-files` turns up no stray test
  paths elsewhere
- Only external boundaries (HTTP, DB, time) are mocked; internal collaborators are not —
  a `grep` of test files finds no real network/DB clients being constructed
- Nothing in the suite reaches outside the process — it still passes with the network
  disabled and no test database running
- CI invokes the test command with `--ci` (Jest/Vitest) so an unrecognized snapshot
  fails the build rather than getting auto-written

## Reference Files (in `references/`)

- **patterns.md** — the runnable examples behind every framework mentioned above: Jest
  setup/teardown, module/spy/timer mocks, async guards; Vitest config, in-source tests,
  concurrency, browser mode; pytest fixtures/parametrize/monkeypatch; Bun/Deno; the four
  test doubles; snapshot file/inline/property-matcher examples.

## Related Skills

- **coverage-analysis** — for reading coverage reports, spotting the gaps that matter,
  and treating mutation score as a first-class signal. Use it to interpret coverage;
  stay in this skill to configure and enforce it.
- **ci-cd-integration** — pipeline test stages, parallelization, caching, and
  deployment gating.
- **ai-test-generation** — for when an AI is writing the test code itself from a
  spec/PRD; this skill covers writing and structuring tests by hand.
- **ai-qa-review** — for auditing existing tests for hallucinated APIs, fabricated
  imports, and closed-loop tests.
- **shift-left-testing** — pre-commit hooks, IDE integration, and TDD workflow built
  around these tests.
