---
name: ai-test-generation
description: >-
  Use AI to write NEW test code from specs, PRDs, user stories, code diffs, bug
  reports, or OpenAPI specs. Staged pipeline: requirements extraction → risk
  analysis → coverage matrix → scenario generation → oracle design → test code →
  human review, with guardrails against hallucinated APIs and weak assertions.
  Use when: "generate tests from spec," "tests from PRD," "tests from user story,"
  "auto-generate test cases," "AI write tests for me."
  Not for: testing AI/LLM features in your product — use ai-system-testing.
  Not for: auditing a pre-existing test suite you did not just generate — use
  ai-qa-review (Step 7 here only reviews tests THIS pipeline produced).
  Related: playwright-automation, unit-testing, api-testing, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: ai-qa
---

<objective>
Left unchecked, an LLM will happily churn out dozens of plausible-sounding tests that assert nothing meaningful, point at endpoints that were never built, and repeat each other under different names. This skill counters that by forcing the model through a staged pipeline — producing assumptions, a coverage matrix, and explicit oracle definitions as structured intermediates BEFORE a single line of test code is written. The result is traceable back to real requirements and grounded in the actual codebase, rather than being ad-hoc noise.

**Before starting:** Look for `.agents/qa-project-context.md` at the project root. When present, it supplies the tech stack, test frameworks, naming conventions, selector strategy, and known risk areas — context that meaningfully raises the quality of what gets generated.
</objective>

## Quick Route

One pipeline serves every input type; what changes is only what Step 1 focuses on extracting. Find the matching row below, then run Steps 2 through 7 exactly as written.

| Input type | Step 1 extracts | Watch for |
|------------|-----------------|-----------|
| PRD / feature spec | Entities, business rules, acceptance criteria, NFRs, stated assumptions | Requirements hiding inside vague language like "seamless" or "fast" |
| User story + AC | Each AC → ≥1 happy + ≥1 negative scenario | A single AC line that actually bundles multiple behaviors |
| Code diff (`git diff main...HEAD`) | New/changed code paths, modified conditionals, removed behavior | Keep the regression scope to changed paths — not the entire module |
| Bug report | Repro steps, expected vs actual, environment | Write a test that asserts what's *expected* — it should fail today and pass once fixed |
| OpenAPI / GraphQL SDL | Endpoints, schemas, required fields, enums, auth | Don't stop at 200s — cover validation, auth failures, and edges per endpoint |

For Playwright work, there's also an agent-integration mode to pick — see Discovery Q2.

## Discovery Questions

Check `.agents/qa-project-context.md` first; anything it already answers can be skipped. Otherwise clarify:

1. **Where is the input coming from?** A PRD/spec, a user story with acceptance criteria, a code diff, a bug report, or an API schema — this drives which Step 1 emphasis from the Quick Route applies. If it's actually an LLM/AI feature spec, stop here: route to `ai-system-testing` for eval datasets instead of Playwright specs.

2. **Which test framework is the target, and — for Playwright — which agent integration mode?**
   - **E2E:** Playwright (preferred), Cypress. **Unit:** Jest, Vitest, pytest. **API:** Playwright `APIRequestContext`, Supertest, requests.
   - **Playwright CLI + agents** (the recommended path for Claude Code / Codex / Cursor): running `npx playwright init-agents --loop=claude` scaffolds planner/generator/healer agents as markdown into `.claude/agents/`. These are interactive dev-time tools whose output is ordinary Playwright tests that run unmodified in CI — token-efficient and native to the agent's own loop.
   - **Playwright MCP** (`npx @playwright/mcp@latest`): more overhead, but the right choice when the agent needs to actively drive a live browser across an extended interactive session.
   - **Neither** — write tests by hand, using AI only as a scratch-pad aid.

3. **What context does the project already provide?** Existing test patterns, Page Objects/helpers, data factories/fixtures, CI constraints such as timeouts and parallelism. The richer this is, the less cleanup work follows.

4. **What review workflow applies?** Options: run the full pipeline through to human review then merge (the default); stop at scenarios and let a human write the code; or generate code and have a human refine it iteratively.

5. **Is domain knowledge required?** Regulated-industry compliance (healthcare, finance), domain invariants (money never goes negative, appointments can't overlap), or risk areas flagged by past incidents.

## Core Principles

1. **The pipeline comes before code.** Test code must never be generated before what to test, why, and how to verify it are established. The seven steps exist specifically to block premature generation aimed at the wrong targets.

2. **The structured intermediates ARE the deliverable.** The assumptions doc, the coverage matrix, and the oracle definitions carry more lasting value than the test code itself — they're what's reviewable, traceable, and reusable.

3. **Keep "what" separate from "how."** Deciding what to test (scenario generation) and deciding how to verify it (oracle design) are different cognitive tasks. Collapse them together and you get scenarios shaped by what's convenient to assert, with verification bolted on afterward.

4. **AI drafts, a human reviews.** AI-generated tests should never ship without a human review pass. AI is an accelerant, not a substitute for judgment.

5. **More context yields better output.** Give the LLM your conventions, existing patterns, selector strategy, and data setup approach. More context in, less cleanup out.

6. **Optimize for quality, not volume.** Every test carries an ongoing maintenance cost. Concentrate effort on critical paths, complex logic, and known risk areas rather than chasing a high test count.

## The Pipeline

**This order is mandatory — agents MUST follow it:**

```
Step 1: Extract   → Requirements, entities, business rules from input
Step 2: Analyze   → Risks, invariants, edge cases, ambiguities
Step 3: Map       → Coverage matrix (requirement → scenario → priority)
Step 4: Generate  → Candidate scenarios (happy + boundary + negative + security + a11y)
Step 5: Design    → Assertions and oracles SEPARATELY from scenarios
Step 6: Code      → Test code (only after all above exist)
Step 7: Review    → Human review with traceability back to source
```

Every step has a full prompt template (extraction, risk analysis, scenario, oracle, code) in `references/prompt-patterns.md`. What follows here is the expected shape of each step's output.

### Step 1: Extract Requirements and Entities

Break the input down into: **Entities** (roles/states/attributes), **Business Rules** (numbered), **Explicit Requirements** (`[REQ-N]`, stated directly in the source), and **Implicit Requirements** (`[IMP-N]`, inferred by you — flag each one for human confirmation). Keeping explicit and inferred requirements clearly separated is what stops assumptions from later being tested as if they were spec.

### Step 2: Risk Analysis and Invariants

Work out what can break, what must never stop being true, and where the source material is simply silent.

- **Risks** — a table of `Risk | Likelihood | Impact | Source Requirement` (e.g., a race condition on stock decrement, an email arriving more than 30s late).
- **Invariants** (conditions that must ALWAYS hold) — e.g., `stock >= 0`, `order total = sum(items) + tax + shipping`, `user sees only their own orders`.
- **Ambiguities** (questions requiring a human answer) — e.g., "Does free shipping apply before or after discount codes?" State these outright rather than quietly guessing.
- **Edge cases surfaced by the risks** — e.g., two users racing to buy the last unit, a payment that succeeds while the email service is down.

### Step 3: Coverage Matrix

This is the single most important artifact in the whole pipeline — it's what catches both gaps and duplicates. Every requirement maps to one or more scenarios, each tagged with category, priority, and oracle type:

| Requirement | Scenario | Category | Priority | Oracle Type |
|-------------|----------|----------|----------|-------------|
| REQ-1 | Add single item to empty cart | Happy path | P0 | State: cart count = 1 |
| REQ-1 | Add out-of-stock item | Negative | P0 | UI: error message, cart unchanged |
| REQ-2 | Complete checkout with valid card | Happy path | P0 | State: order created, stock decremented |
| REQ-2 | Two users checkout last item | Race condition | P1 | One succeeds, one gets stock error |
| INV-1 | Stock never goes negative | Invariant | P0 | Data: stock >= 0 after any operation |

Once it's built, check: does every requirement have at least one happy-path and one negative scenario; does every invariant have a direct test; does every risk from Step 2 map to a scenario; and are there no two rows testing the same thing?

### Step 4: Generate Candidate Scenarios

Expand every matrix row into a complete Given/When/Then scenario, including explicit test-data requirements (e.g., `Given: user with 99 items in cart (max 100); When: adds one more; Then: count = 100`). Make sure these categories are all systematically covered:

| Category | Description |
|----------|-------------|
| Happy path | The user does exactly what the feature is designed for |
| Boundary | Edge of valid input ranges — use the BOUNDARIES framework (`references/prompt-patterns.md`) |
| Negative | Invalid inputs, unauthorized actions |
| Security | Auth bypass, injection, privilege escalation |
| Accessibility | Screen reader, keyboard-only, contrast |
| State transition | Valid and invalid moves between states |
| Concurrency | Two users acting simultaneously |

### Step 5: Design Assertions and Oracles

**This must stay a distinct step from Step 4.** Scenarios describe what happens; oracles describe how you'd prove it happened. For every scenario, spell out oracles across each category — a single assertion is almost never enough to actually prove a behavior:

| Oracle category | Asserts | Example |
|-----------------|---------|---------|
| UI state | Visible text / element state | `cart badge toHaveText('1')` |
| Data | Persisted state via API/DB | `GET /api/cart` returns 1 item, correct total |
| Negative | What should NOT happen | no error toast; no navigation away |
| Side effect | Async/external outcomes | analytics `add_to_cart` fired; email in inbox < 30s |

**Rules for oracle quality:** assert the business outcome, not an implementation detail; reach for the most specific assertion available (`toHaveText('$29.99')` beats `toBeTruthy()`); always include a negative assertion somewhere; check data integrity, not merely what's on screen; and don't skip accessibility (focus management, live-region announcements).

### Step 6: Generate Test Code

**Do not start this until Steps 1-5 have been reviewed artifacts.** From here, code is a largely mechanical translation of scenarios plus oracles into the target framework's syntax, carrying traceability comments back to the requirement and scenario:

```typescript
/**
 * Scenario: SC-001 — Add single item to empty cart
 * Requirement: REQ-1 (User can add items to cart)
 * Priority: P0
 */
test('add single item to empty cart', async ({ page, testProduct }) => {
  await page.goto(`/products/${testProduct.id}`);                       // Given
  await page.getByRole('button', { name: 'Add to cart' }).click();      // When
  await expect(page.getByTestId('cart-badge')).toHaveText('1');         // Then
  await expect(page.getByTestId('error-toast')).not.toBeVisible();      // Negative oracle
});
```

**Rules for code generation:** follow whatever conventions `qa-project-context.md` defines; reuse the Page Objects, fixtures, and data factories that already exist rather than inventing new ones; keep traceability comments in place (`Scenario: SC-XXX`, `Requirement: REQ-XX`); stick to the project's chosen selector strategy; and push setup/teardown into fixtures instead of writing it inline.

### Step 7: Human Review

This step is mandatory, not optional. It reviews **only the tests this pipeline itself just produced** — before they get merged. (For auditing a pre-existing suite you didn't just generate, that's `ai-qa-review`'s job instead.) Every generated test should pass this checklist:

- [ ] **Traces to requirement:** you can follow test → scenario → coverage row → requirement.
- [ ] **Tests behavior, not implementation:** would survive a harmless refactor.
- [ ] **Correct abstraction level:** the right test type — unit vs. integration vs. E2E.
- [ ] **Test naming and readability:** the name states the behavior; intent is clear without reading the body.
- [ ] **Test isolation / no shared state:** creates and cleans up its own data, has no ordering dependency on other tests, and passes alone or in any order.
- [ ] **Realistic test data:** plausible and varied, using `example.com`.
- [ ] **Meaningful assertions:** matches the oracle definition; specific rather than `toBeTruthy()`.
- [ ] **Matches project conventions:** naming, structure, selector strategy.
- [ ] **No flakiness risks:** no hardcoded timeouts, race conditions, or order dependence.
- [ ] **Edge cases included:** more than just the happy path.
- [ ] **Assumptions validated:** Step-2 ambiguities got resolved before any coding happened.

**Possible outcomes per test:** **KEEP** (merge as-is) · **MODIFY** (fix the listed issues, then merge) · **REJECT** (wrong requirement, wrong abstraction, hallucinated API) · **DEFER** (blocked pending an ambiguity being resolved).

## Guardrails

These are hard rules that agents MUST follow.

- **No code before coverage exists.** Test code must never appear before Steps 1-3 (requirements, risk analysis with documented assumptions, coverage matrix) are done. If an agent jumps straight to code: STOP and go back.
- **Assert the outcome, never the implementation.** Prefer `expect(screen.getByRole('progressbar')).toBeVisible()` over `expect(component.state.isLoading).toBe(true)`, and `expect(page.getByTestId('cart-badge')).toHaveText('1')` over `expect(store.dispatch).toHaveBeenCalledWith(...)`.
- **Scenarios (Step 4) always come before oracles (Step 5).** A scenario is WHAT happens; an oracle is HOW you verify it. Blend them and scenarios drift toward whatever's easiest to assert.
- **Always surface the intermediates** — the assumptions document, unresolved ambiguities, oracle candidates, and the traceability chain — even if only in abbreviated form.

**Flag these on sight:**
- **Hallucinated APIs** — endpoints, selectors, methods, or imports that don't actually exist in the codebase. Confirm mechanically (see Verification) before handing off for human review.
- **Duplicate scenarios** — the same behavior tested with trivially different data. Consolidate or parametrize instead.
- **Low-value assertions** — things like `expect(response).toBeTruthy()` or `expect(page).toHaveURL(/.*/)`.
- **Missing negative cases** — if every scenario is a happy path, the coverage matrix isn't finished.
- **Unrealistic test data** — placeholders like `test@test.com`, `John Doe`, `password123`. Use varied, plausible data on `example.com` instead.

## Model selection per step

Match model cost to step difficulty rather than defaulting to one model everywhere. Mechanical work — Step 1 extraction and the Step 3 coverage-matrix bookkeeping — is well within reach of a cheap model like **Haiku 4.5** or **Sonnet 4.6**. Reserve **Opus 4.8** for oracle design (Step 5) and code generation (Step 6), where a wrong inference is costly and hallucination risk is highest; bring in **Fable 5** only for the genuinely hard reasoning cases — subtle invariants, regulated-domain logic. Running your strongest model on every step wastes budget; running your cheapest model on Step 6 produces fabricated APIs.

## Verification

Turn the "hallucinated APIs" warning into an actual mechanical check. Run this after Step 6, before handing off to a human:

1. **Resolve imports and types.** TypeScript: `npx tsc --noEmit` catches fabricated imports and wrong signatures. Python: `python -m pyflakes <files>` or `ruff check`.
2. **Grep generated selectors and endpoints against the real codebase.** Confirm every `getByTestId('...')` id and every API path referenced by the tests genuinely exists in source:
   ```bash
   grep -roE "getByTestId\('([^']+)'\)" generated/ | sed -E "s/.*'([^']+)'.*/\1/" | sort -u \
     | while read id; do grep -rq "$id" src/ || echo "MISSING testid: $id"; done
   ```
3. **Run the suite once.** Tests referencing routes or selectors that don't exist will fail immediately — quarantine those rather than spending review time on dead code.

Treat any `MISSING` line or `tsc` error as a hallucination that must be fixed before a human's review time gets spent on it.

## Anti-Patterns

1. **Jumping straight to code.** The most common failure mode: an agent receives a PRD and immediately starts writing tests. Skip the coverage matrix and you'll miss scenarios while duplicating others — the whole pipeline exists to prevent exactly this.
2. **Asserting implementation instead of behavior.** `expect(component.state.isLoading).toBe(true)` breaks the moment anything gets refactored. Assert `expect(screen.getByRole('progressbar')).toBeVisible()` instead — what the user actually sees.
3. **Blending scenarios and assertions together.** Treating "test this thing and check this value" as a single step. Keep *what to test* and *how to verify it* as separate decisions.
4. **Leaving project context out of the prompt.** Without existing conventions and patterns, output stays generic. This is precisely the gap `qa-project-context.md` closes.
5. **Over-generating.** Left alone, AI will happily produce 50 tests for a trivial function, and each one becomes ongoing maintenance burden. Let the coverage matrix set the boundary on how much gets generated.
6. **Merging what you don't understand.** If you can't explain what a generated test does or why, don't merge it — a test you don't understand is a test you won't be able to debug later.
7. **Skipping the review step.** Step 7 isn't optional. AI-generated tests routinely contain hallucinated APIs, wrong selectors, incorrect business logic, and flakiness that only a human catches.
8. **Not closing the feedback loop.** When AI-written tests catch real bugs, note down which prompt patterns worked; when they produce false positives, note what went wrong. Over time this becomes a project-specific playbook of what actually works.

## Done When

- All seven artifacts exist: requirements document, risk & invariants, coverage matrix, scenario set, oracle definitions, test code, and review notes carrying a KEEP/MODIFY/REJECT/DEFER decision per test.
- The coverage matrix was produced and reviewed before any test code file was written.
- Verification passed: `tsc --noEmit` (or the language equivalent) exits 0, and the selector/endpoint grep reports zero `MISSING` lines.
- Every generated test has a recorded human review decision — no test is marked KEEP without one.
- The suite's CI job exits 0 (green).
- Reproducibility metadata is recorded: the exact model ID (e.g., `claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`), the input source hash, and the version of any skill / CLI / MCP server that was invoked.

## Related Skills

- **qa-project-context** — Sets up the context file that dramatically improves AI test generation quality. Configure this first.
- **playwright-automation** — Deeper Playwright patterns (POM, fixtures, CI), plus the Test Agents (`init-agents --loop=claude`, scaffolded into `.claude/agents/`) and `@playwright/mcp` modes selected in Discovery Q2. Generated tests live inside this framework.
- **unit-testing** — Jest, Vitest, pytest patterns for unit-level generated tests.
- **api-testing** — Endpoint test patterns for tests generated from OpenAPI specs.
- **test-strategy** — Decide *what* to test and at which level, before generation starts.
- **test-reliability** — Keep generated tests reliable: flake classification, healing, video receipts.
- **ai-system-testing** — For an LLM feature spec as input, generate eval datasets here (Promptfoo, DeepEval, Ragas, Braintrust) instead of Playwright specs.
- **ai-qa-review** — Audits a *pre-existing* suite you didn't just generate (test smells, testability). Step 7 in this skill only ever reviews this pipeline's own output.
- **ai-bug-triage** — Route bugs found by generated tests through the triage pipeline for classification and reporting.

## Reference Files (in `references/`)

- **prompt-patterns.md** — The full prompt library mapped to the seven steps: extraction, risk analysis, scenario generation, oracle design, and code generation prompts, plus the BOUNDARIES edge-case framework used in Step 4.
</content>
