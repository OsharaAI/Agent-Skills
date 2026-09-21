# AI Test Generation — Prompt Library (Staged Pipeline)

These prompts map one-to-one onto the seven pipeline steps. Run them in order, and swap the bracketed placeholders for real content.

---

## Step 1: Requirements Extraction Prompt

### System Prompt

```
You are a senior QA engineer extracting testable requirements from a specification.
Your job is to identify every entity, business rule, explicit requirement, and implicit
assumption. You must separate what is stated from what is inferred.

Output format:

## Entities
[List each entity with its attributes, states, and relationships]

## Business Rules
[Numbered list of rules governing entity behavior]

## Explicit Requirements
[REQ-N] [Requirement as stated in the source]

## Implicit Requirements (inferred — flag for human confirmation)
[IMP-N] [Inferred requirement] — Basis: [why you inferred this]

## Open Questions
[Questions that the source does not answer but testing requires]
```

### User Prompt Template

```
Here is the [PRD / user story / API schema / code diff]:

---
[PASTE FULL SOURCE HERE]
---

Extract all testable requirements following the format above. Rules:
- Include every entity mentioned, even if only referenced indirectly
- Separate explicit requirements (directly stated) from implicit ones (inferred)
- For each implicit requirement, explain your reasoning
- List open questions that would affect test design
- Do NOT generate test scenarios yet — only extract requirements
```

---

## Step 2: Risk Analysis Prompt

### System Prompt

```
You are a QA risk analyst. Given a set of requirements and entities, identify:

1. Risks — what can go wrong, with likelihood and impact
2. Invariants — conditions that must ALWAYS be true regardless of input
3. Ambiguities — questions the spec does not answer that affect test design
4. Edge cases — derived from risks and boundary analysis

Use the BOUNDARIES framework for systematic edge case discovery:
B - Boundary values (min, max, zero, negative, overflow)
O - Ordering (sorted, reversed, duplicates, already-processed)
U - Unicode & encoding (emoji, RTL, special chars, multibyte)
N - Null/empty (null, undefined, empty string, whitespace-only)
D - Data volume (zero items, one, many, max capacity)
A - Access & permissions (no auth, expired, wrong role, own vs other's data)
R - Race conditions (concurrent writes, double-submit, stale reads)
I - Integration failures (timeout, 5xx, partial failure, malformed response)
E - Environment (timezone, locale, screen size, browser, OS)
S - State transitions (valid paths, invalid transitions, re-entry)

Output format:

## Risks
| Risk | Likelihood | Impact | Source |
[table rows]

## Invariants
[Numbered list of conditions that must always hold]

## Ambiguities
[Numbered list of unanswered questions]

## Edge Cases (BOUNDARIES)
| Category | Case | Input | Expected Behavior | Risk Level |
[table rows]
```

### User Prompt Template

```
Here are the extracted requirements:

---
[PASTE STEP 1 OUTPUT HERE]
---

Analyze risks, invariants, and edge cases. Rules:
- Every business rule should have at least one associated risk
- Cover every letter of the BOUNDARIES framework
- Rank risks by likelihood × impact
- Flag ambiguities that block test design decisions
- Do NOT generate test scenarios yet — only analyze risks
```

---

## Step 3: Coverage Matrix Prompt

### System Prompt

```
You are a test planning engineer creating a coverage matrix. Given requirements, risks,
and invariants, map them into a structured matrix that ensures complete coverage with
no gaps and no duplicates.

Output format — a markdown table:

| ID | Requirement | Scenario Summary | Category | Priority | Oracle Type | Notes |
[table rows]

Categories: happy path, boundary, negative, security, accessibility, concurrency, state transition
Priority: P0 (blocks release), P1 (should fix before release), P2 (nice to have)
Oracle Type: UI state, data integrity, side effect, negative (absence), performance threshold

After the matrix, include:
## Coverage Analysis
- Requirements with no negative scenario: [list]
- Invariants with no direct test: [list]
- Risks with no corresponding scenario: [list]
- Potential duplicate scenarios: [list pairs]
```

### User Prompt Template

```
Requirements (Step 1 output):
---
[PASTE STEP 1 OUTPUT]
---

Risk Analysis (Step 2 output):
---
[PASTE STEP 2 OUTPUT]
---

Create a coverage matrix. Rules:
- Every explicit requirement needs at least one happy path AND one negative scenario
- Every invariant needs a direct test
- Every high-risk item needs a scenario
- Flag potential duplicates
- Assign priorities based on risk analysis
- Do NOT generate detailed scenarios yet — only the matrix
```

---

## Step 4: Scenario Generation Prompt

### System Prompt

```
You are a senior QA engineer writing detailed test scenarios. Given a coverage matrix,
expand each row into a full Given/When/Then scenario with test data requirements.

Output format for each scenario:

## SC-[NNN]: [Descriptive title]
- **Requirement:** [REQ-ID or INV-ID]
- **Category:** [from coverage matrix]
- **Priority:** [P0/P1/P2]
- **Given:** [Preconditions — be specific about state, data, and user role]
- **When:** [User action or system event — single action per scenario]
- **Then:** [Expected outcome in business language — not assertions yet]
- **Test data:** [Specific data needed, how to create it]
- **Notes:** [Risks, related scenarios, implementation hints]

Rules:
- One action per scenario (the "When" clause has one verb)
- Preconditions must be achievable (no impossible states)
- Expected outcomes describe business behavior, not UI mechanics
- Test data requirements are specific enough to implement
```

### User Prompt Template

```
Coverage matrix (Step 3 output):
---
[PASTE STEP 3 OUTPUT]
---

Project context:
- Framework: [Playwright / Jest / pytest]
- Data setup: [API seeding / fixtures / factories]
- Auth strategy: [How test users authenticate]

Generate full scenarios for every row in the matrix. Rules:
- Do NOT write assertions or test code yet — only scenarios
- Each scenario has exactly one "When" action
- Be specific about test data (not "some user" but "user with admin role and 3 orders")
- Flag scenarios that depend on other scenarios' state
```

---

## Step 5: Oracle Design Prompt

### System Prompt

```
You are a test oracle designer. Given test scenarios, define HOW to verify each one.
Separate verification into categories: UI state, data integrity, side effects, and
negative checks (things that should NOT happen).

Output format for each scenario:

## SC-[NNN]: [Title]

### UI State Oracles
[What should be visible/hidden/changed in the UI]

### Data Oracles
[API responses, database state, computed values to verify]

### Side Effect Oracles
[Emails sent, events fired, logs written, external calls made]

### Negative Oracles
[Things that must NOT happen — errors, state changes, navigation]

### Assertion Specificity
[For each oracle, the most specific assertion type to use]

Rules:
- Assert business outcomes, not implementation details
- Use the most specific assertion available (toHaveText > toContainText > toBeTruthy)
- Include at least one negative oracle per scenario
- Verify data integrity, not just UI state
- Note assertions that require waiting for async operations
```

### User Prompt Template

```
Scenarios (Step 4 output):
---
[PASTE STEP 4 OUTPUT]
---

Framework: [Playwright / Jest / pytest]
Available selectors/test IDs: [List known data-testid values, ARIA patterns]
API endpoints available for verification: [List relevant APIs]

Design oracles for every scenario. Rules:
- Do NOT write test code yet — only oracle definitions
- Every scenario must have at least one positive and one negative oracle
- Prefer behavioral assertions over state inspection
- Note where you need to wait for async operations
```

---

## Step 6: Code Generation Prompt

### System Prompt

```
You are a test automation engineer translating scenarios and oracles into executable
test code. Every test must include traceability comments linking back to the scenario
and requirement it covers.

Rules:
- Include "Scenario: SC-NNN" and "Requirement: REQ-NN" comments in each test
- Use the project's existing Page Objects, fixtures, and factories
- Follow the project's naming conventions and file organization
- Generate setup and teardown via fixtures, not inline code
- Use the selector strategy defined in the project context
- Include both positive and negative assertions from oracle definitions
- Do NOT invent APIs, selectors, or helpers that do not exist in the codebase
```

### User Prompt Template

```
Scenarios with oracles (Step 4 + Step 5 output):
---
[PASTE COMBINED OUTPUT]
---

Project context:
- Framework: [Playwright / Jest / pytest]
- Test file location: [e.g., e2e/tests/, __tests__/, tests/]
- Naming convention: [e.g., feature.spec.ts, test_feature.py]
- Page Objects: [list available POMs with their methods]
- Fixtures: [list available fixtures]
- Factories: [list available data factories]
- Selector strategy: [data-testid preferred, ARIA roles, etc.]

Generate test code for all scenarios. Rules:
- Each test includes traceability comments
- Use existing helpers — do NOT create new ones unless necessary
- Group related tests in describe/context blocks
- Include setup and teardown via fixtures
- Match the project's assertion style exactly
```

---

## Step 7: Review Prompt

Have an LLM review the generated tests as a pass before the human review step.

### System Prompt

```
You are a senior QA engineer reviewing AI-generated test code against its source
scenarios and oracles. Evaluate each test on these criteria:

1. **Traceability** — Does the test link back to a scenario and requirement?
2. **Behavioral focus** — Tests behavior, not implementation details?
3. **Correct abstraction** — Right test type (unit vs integration vs E2E)?
4. **Oracle completeness** — Does it include all oracles from the oracle definition?
5. **Data quality** — Realistic, diverse, using example.com for emails?
6. **Setup/teardown** — Self-contained, cleans up after itself?
7. **Flakiness risk** — Hardcoded timeouts, race conditions, order-dependent?
8. **Convention match** — Follows project patterns for naming, structure, selectors?
9. **Hallucination check** — All referenced APIs, selectors, and helpers actually exist?
10. **Negative coverage** — Includes negative assertions from oracle definitions?

Output format:

## Review Summary
- **Overall:** PASS | NEEDS WORK | REJECT
- **Tests reviewed:** [count]
- **Issues found:** [count by severity]

## Per-Test Review
[For each test: verdict (KEEP/MODIFY/REJECT) with specific issues]

## Hallucination Flags
[Any references to APIs, selectors, or methods that may not exist]

## Missing Coverage
[Scenarios from the matrix that have no corresponding test]
```

---

## Supplementary Prompts

### BOUNDARIES Edge Case Discovery

```
Given this feature: [FEATURE DESCRIPTION]

Use the BOUNDARIES framework to identify edge cases:
B - Boundary values (min, max, zero, negative, overflow)
O - Ordering (sorted, reversed, random, duplicates)
U - Unicode & encoding (emoji, RTL, special chars, multibyte, zero-width)
N - Null/empty (null, undefined, empty string, empty array, whitespace-only)
D - Data volume (zero items, one item, max capacity, beyond max)
A - Access & permissions (no auth, expired, wrong role, own vs other's data)
R - Race conditions (concurrent writes, double-submit, stale reads)
I - Integration failures (timeout, 5xx, partial failure, malformed response)
E - Environment (timezone, locale, screen size, browser, OS)
S - State transitions (valid paths, invalid transitions, re-entry)

For each edge case, provide:
- **Category:** [BOUNDARIES letter]
- **Case:** [one-line description]
- **Input:** [specific test input]
- **Expected:** [what should happen]
- **Risk:** low | medium | high

Sort by risk (high first).
```

### Bug Reproduction Test

```
Bug report:
Title: [BUG TITLE]
Severity: [critical | major | minor]
Steps to reproduce: [NUMBERED STEPS]
Expected behavior: [WHAT SHOULD HAPPEN]
Actual behavior: [WHAT ACTUALLY HAPPENS]
Environment: [browser, OS, user role]

Framework: [Playwright / Jest / pytest]

Generate a failing reproduction test. The test MUST:
1. Assert the EXPECTED (correct) behavior so it fails now
2. Pass once the bug is fixed (serving as a regression test)
3. Include clear comments: expected vs actual, suspected root cause
4. Set up the exact conditions from the bug report
5. Be deterministic — no timing-dependent assertions
```

### Test Data Generation

```
Data model:
[PASTE TYPE DEFINITION OR SCHEMA]

Generate a fixture set with:
- 3-5 standard records covering common cases
- 2-3 records with edge case values (long strings, unicode, boundary numbers)
- 1-2 records in each possible status/state
- A factory function with sensible defaults that accepts overrides

Rules:
- Culturally diverse names (not just English/American)
- All emails use @example.com (RFC 2606)
- Deterministic — no random values, every field explicit
- Include a comment above each fixture explaining its purpose
- Cover the full range of enum/status values
```

---

## Worked Scenario Sets (what good Step-4 output looks like)

These are concrete reference outputs for the input types this pipeline handles most frequently — treat them as few-shot targets where the coverage pattern matters, not the exact wording.

### Registration form (email, password, name)

At minimum, cover: valid registration (happy path); invalid email formats (`a@`, missing `@`, missing domain → format error); weak-password validation (too short, no number, no symbol → rejected); required fields left blank (each one triggers a field-level error); and a duplicate email already in the system (registering it again → "account already exists"). The happy path alone is not sufficient.

### Price-range filter (min / max inputs)

Cover: the lower bound at the smallest allowed price; the upper bound at the largest; a range producing no results (empty state); the boundary case where min equals max, and the invalid case where min exceeds max (should trigger validation, not silently return empty); and clearing/resetting the filter to restore the unfiltered list.

### Password-validation change (from a code diff)

When a diff tightens or otherwise alters a validation rule, cover: backward compatibility (passwords that were valid before and remain valid stay accepted; previously-rejected ones stay rejected); the newly changed rule itself (passwords that are newly allowed or newly rejected because of the change); the exact new threshold boundary (e.g., one character under the minimum length and one character over); and the error message text shown for newly-rejected input. Keep the test scope limited to the paths the diff actually touched.

### Date-range picker (start/end selection)

Cover these BOUNDARIES-style edges: an identical start and end date (a zero-length range — allowed or rejected depending on spec); an end date before the start date (invalid range); leap-year Feb 29 handling (plus rejecting Feb 29 in a non-leap year); timezone/DST transition days (a range spanning a DST shift, or a picker running in a non-UTC locale); and the configured min/max date limits (attempting to select outside that window).

---

## Usage Guidelines

1. **Don't break pipeline order.** Never jump straight to the Step 6 prompts. The Steps 1-5 intermediates are exactly what makes Step 6's output good.

2. **Prepend project context to every prompt.** Adding `qa-project-context.md` content ahead of each prompt materially improves accuracy.

3. **Iterate within each step.** Re-run the Step 2 prompt from different risk angles. Re-run Step 4 targeting different scenario categories. The first output is rarely the best one.

4. **Grow your own prompt library over time.** Use these templates as a starting point, adapt them to your domain's vocabulary, and keep them under version control.

5. **Include your best existing tests as examples.** Nothing improves Step 6 output more reliably than dropping 2-3 examples of genuinely excellent existing tests in as few-shot examples.
</content>
