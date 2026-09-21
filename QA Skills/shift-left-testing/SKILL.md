---
name: shift-left-testing
description: >-
  Bring quality work forward in the development lifecycle instead of saving it for
  the end. Covers dev/QA collaboration patterns, Three Amigos discussions, hands-on
  TDD coaching (Red-Green-Refactor), PR checklists focused on testability, and a
  Definition of Done anchored on real quality gates. Includes a maturity ladder a
  team can use to place itself and pick a concrete next step. Use when: "shift left,"
  "TDD," "dev-QA pairing," "definition of done," "testability," "quality culture,"
  "QA in sprint planning."
  Not for: authoring the unit tests themselves — see unit-testing; automated,
  at-scale PR test-quality review — see ai-qa-review; multi-quarter QA direction or
  roadmap planning — see test-strategy.
  Related: unit-testing, ai-qa-review, test-strategy.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: process
---

<objective>
Move quality checks as far upstream in the delivery pipeline as they'll go, back to where mistakes are still cheap to correct. A missing validation rule caught during refinement is a five-minute conversation; the same gap surviving to production turns into an incident, a hotfix, and a postmortem. This skill collects the practices, collaboration patterns, and cultural shifts that build quality into every stage of the work — from the very first story discussion through the PR merge — along with a maturity ladder for pinpointing your next concrete move.
</objective>

## Where to Start

| Your situation | Jump to |
|-----------|-------|
| QA never sees a feature until dev calls it "done" | Working Together → QA Joins Sprint Planning |
| You want a requirements conversation before coding starts | Working Together → Three Amigos |
| Trying to decide if this task deserves TDD | TDD in Practice → TDD or Test-After? |
| Reviewing a PR and want to judge test quality | PR Review Checklist |
| Reviewing a PR built by, or containing, AI-generated code | PR Review Checklist → AI-Generated or AI-Using Changes |
| Not sure where your team stands or what's next | Maturity Ladder |

---

## Questions to Ask First

Check for `.agents/qa-project-context.md` before doing anything else — when it exists, use it (it should cover team makeup, dev/QA workflow, sprint cadence, quality goals) and skip whatever ground it already covers.

### Mapping the Current Dev/QA Workflow

1. **When does QA first encounter a feature?** Once a PR is opened? After it hits staging? Only once something has already broken? The answer alone tells you how far downstream quality currently sits.

2. **Who's responsible for writing tests, and when?** Developers alone? QA alone, after dev declares the work finished? Both, but on disconnected timelines? You need a clear picture of today's ownership model before you can change it.

3. **How do requirements make their way to the team?** Written specs? A quick verbal handoff? A Figma mockup with no acceptance criteria at all? Vague requirements are the largest single source of defects that shifting left is meant to fix.

4. **Has TDD been attempted before?** Tried and dropped, or never tried at all? Knowing that history stops you from repeating a rollout that already failed once.

5. **What actually happens during PR review right now?** Who reviews? Does anyone actually assess testability, or is it strictly business logic? Are tests required to merge? PR review is typically the cheapest place to introduce a new quality check.

6. **Is there a Definition of Done, and is it actually followed?** Documented or just tribal knowledge? Does testing even appear in it? Genuinely enforced, or aspirational? The DoD is what separates "still in progress" from "actually done."

7. **How early does QA get involved in sprint planning?** Not at all? Brought in just for estimates? Actively helping shape the stories? This shows you how early in the cycle QA's thinking actually enters.

---

## Guiding Principles

### 1. Everyone Owns Quality

Quality isn't something QA does after developers hand off finished work — it's a thread running through the entire workflow: product frames testable acceptance criteria, developers write tests alongside their code, reviewers watch for testability, and QA handles strategy plus whatever automation lets slip through. Spread the ownership around, and whoever encounters a defect first is the one positioned to stop it.

### 2. Earlier Is Cheaper to Fix — as a Direction, Not a Formula

A validation gap caught in refinement costs about five minutes of conversation. The very same defect, left to reach production, costs an incident, a hotfix, a postmortem, and some measure of user trust. Cost genuinely does rise the further a bug travels — through refinement, design, development, QA, staging, and finally production — **but be skeptical of any specific multiplier attached to that curve.** The well-worn "1x becomes 100x" claim traces back to an undated IBM Systems Science Institute training slide with no published methodology behind it anywhere. Lean on the qualitative story above instead of a number nobody can actually source. The whole point of shifting left is intercepting defects in those cheap early stages — refinement through development — before QA, staging, or production ever see them.

### 3. QA Embeds Rather Than Gatekeeps

The old model puts QA at the very end of development as a gate, where code gets "thrown over the wall" for testing. Shifting left instead threads QA through the entire process: contributing during refinement, pairing on test design, reviewing PRs with testability in mind, and validating continuously along the way. Gates create bottlenecks and an adversarial dynamic. Embedding builds shared ownership and real collaboration instead.

### 4. Testability Is a Design-Time Concern

Code that's hard to test is usually also hard to maintain and debug, and tends to conceal bugs. Testability deserves the same design-stage attention normally reserved for performance, security, or usability. Asking "how will we verify this?" before writing any code tends to produce architecture that ends up cleaner and more modular.

### 5. Demonstrate Value Incrementally

Trying to roll out every shift-left practice simultaneously will overwhelm a team. Pick one to start — PR review checklists and Three Amigos tend to be the easiest on-ramps — show its payoff with concrete numbers (fewer bugs escaping, faster PR turnaround), and use that evidence to justify adopting the next one. Culture changes one visible win at a time.

---

## Working Together: Dev/QA Collaboration Patterns

### QA Joins Sprint Planning

**What this looks like:** QA engineers attend sprint planning and actively help shape the stories — raising edge cases, flagging missing acceptance criteria, and calling out risky areas before any code gets written.

**What QA actually does during planning:**

1. **Check each story's acceptance criteria for testability.** A criterion needs to be verifiable in principle — "user can sort the table" is testable; "the table feels user-friendly" is not.
2. **Surface edge cases and negative paths.** An empty dataset? Maximum-length input? Two users hitting the same record concurrently? A network drop mid-request?
3. **Flag integration risk.** Does the story touch a third-party API? Change a schema? Touch existing test fixtures?
4. **Estimate the QA effort.** Automation time, exploratory testing, environment setup — build this into sprint capacity instead of assuming it's free.
5. **Settle the test approach per story ahead of time.** Unit coverage for business rules, integration coverage for API changes, E2E coverage for user-facing flows.

**Template: questions QA brings to a story**

```
Story: [PROJ-2210] Add promo code to checkout
───────────────────────────────────────────────
QA questions before development starts:
1. What happens once a promo code has expired?
2. What if the promo code was already redeemed (single-use)?
3. Can more than one promo code stack on the same order?
4. What message does the shopper see for an invalid code?
5. Does the discount update live, or only after submit?
6. Is code validation rate-limited?

Test approach:
- Unit: promo validation rules, discount math, expiry check
- Integration: promo API endpoint, redemption state in the database
- E2E: apply promo during checkout, confirm discount on the receipt page
- Exploratory: currency rounding edge cases, maximum discount caps
```

### Three Amigos

A focused 15-to-30-minute conversation, held before any development begins, that brings three distinct viewpoints together.

**The three viewpoints:**
- **Product/Business:** What does the user actually need, and why?
- **Development:** How would we build it, and what technical constraints apply?
- **QA/Testing:** How would we confirm it works, and what might go wrong?

**An optional fourth voice (an AI participant):** a coding agent can generate edge cases and counter-scenarios directly from the acceptance criteria as the session unfolds. Treat its output as a checklist worth checking, not a decision on its own — the humans present still own the final criteria.

**Suggested 30-minute agenda:**

1. Product walks through the story (5 min) — user need, draft acceptance criteria
2. Dev asks clarifying questions (5 min) — feasibility, dependencies
3. QA asks testing questions (5 min) — edge cases, failure states, testability
4. The group surfaces gaps together (10 min) — add missing criteria, make hidden assumptions explicit
5. Close out (5 min) — updated story, documented risks, agreed test approach

**Worth running for:** stories rated Medium risk or above, anything touching payments, auth, or data integrity, ambiguous requirements, cross-team work.

**Safe to skip for:** bug fixes with a clear, known repro; copy-only or text-only changes; dependency bumps with no behavior change.

### Test-First Pairing Between QA and Dev

This isn't full TDD — it's collaborative test thinking applied ahead of implementation.

**The mechanics:**
1. Developer and QA sit together (in person or over a shared screen) for 20–30 minutes.
2. QA walks through the scenarios that need testing.
3. Developer sketches the test signatures — names, inputs, expected outputs — without implementing anything yet.
4. Together they bucket the tests into unit, integration, and E2E.
5. Developer then builds the feature against those agreed-upon tests as the target.

**What a session like this produces:** a set of agreed test signatures spanning unit, integration, and E2E, written before a line of implementation exists. See `references/tdd-examples.md` for the full promo-code pairing output.

### QA as PR Reviewer

QA reviews pull requests through a testability and test-quality lens, running alongside — never in place of — the standard code review.

**Rolling this out for the first time:**

1. **Start with one QA reviewer, limited to high-risk PRs.** Reviewing everything from day one is the fastest route to burning out that reviewer.
2. **Keep the review to 15 minutes.** QA is assessing test quality here, not re-litigating business logic the code review already covers.
3. **Use the checklist below.** It's designed to be objective, with no judgment calls needed.
4. **Frame feedback as a suggestion.** "Consider a test for the empty state" lands far better than "Missing tests."
5. **Track the catches.** Log every real gap the review finds, and share the tally with the team after a few weeks so the ROI is visible.

---

## TDD in Practice

### Red, Green, Refactor

TDD is a strict three-step loop, and each step carries its own purpose and its own exit condition.

```
┌──────────────────────────────────────────────────────┐
│  RED: Write a test that fails                        │
│  - The test spells out the behavior you want          │
│  - It has to fail — a passing test proves nothing yet │
│  - Keep it minimal: one behavior per test              │
│                                                      │
│  GREEN: Get the test passing                          │
│  - Write just enough code to satisfy the test          │
│  - No bonus features, no premature optimizing          │
│  - Ugly code is fine here                              │
│                                                      │
│  REFACTOR: Tidy up                                    │
│  - Reshape the code without changing behavior          │
│  - Every test must still pass afterward                │
│  - Cut duplication, rename things, simplify             │
└──────────────────────────────────────────────────────┘
```

**Worked example — a password strength checker:** begins with a single failing test, moves to the smallest amount of code that passes it, and ends with a refactor into a rules array that leaves behavior unchanged. See `references/tdd-examples.md` for the full walk-through.

### TDD or Test-After? A Decision Guide

TDD isn't always the right call. This table helps you decide.

| Situation | Pick | Rationale |
|----------|------|-----|
| Pure business logic (validators, calculators, transformers) | **TDD** | Inputs and outputs are clear, feedback is fast, tests double as documentation |
| Bug fix with a known repro | **TDD** | A failing test written first is proof the fix actually works |
| API endpoint with a settled contract | **TDD** | Request/response makes a natural boundary for a test |
| Exploratory UI prototyping | **Test-after** | The design is still moving; tests written early would be rewritten constantly |
| Third-party integration | **Test-after** | You need to learn how the API actually behaves before you can test against it |
| Complex data migration | **Test-after, with fixtures** | Build sample data first, then test the transformation against it |
| Performance tuning | **Test-after, with benchmarks** | You need a baseline before you can test an improvement |
| AI-generated implementation | **TDD (test first)** | LLMs readily produce code that merely looks correct; a failing test written first becomes the spec the agent has to satisfy — the single highest-leverage check on AI output |

### The Bug-Fix Litmus Test

Every bug fix ought to start with a failing test that reproduces the problem. That habit earns you three things:

1. **Proof you actually understand the bug.** If you can't get a test to fail on it, you haven't understood it yet.
2. **Proof the fix works.** That same test flips to green once the fix is in.
3. **A standing guard against regression.** The test remains in the suite from then on.

`references/tdd-examples.md` walks through a real example: a zero-decimal-currency rounding bug in JPY, resolved failing-test-first.

### Katas for Building TDD Muscle Memory

Short exercises (30–60 minutes) built to instill the rhythm of TDD:

| Kata | Difficulty | What it teaches |
|------|-----------|------------|
| FizzBuzz | Beginner | The basic Red-Green-Refactor loop |
| String Calculator | Beginner | Building complexity incrementally, edge cases |
| Roman Numerals | Intermediate | Spotting patterns, refactoring |
| Bowling Game | Intermediate | Managing state, handling complex rules |
| Gilded Rose | Advanced | Refactoring legacy code safely under a test harness |

**How to run it:** pair programming, 45 minutes, swap driver every 5 minutes. Reserve the last 15 minutes for a debrief: what was hard, what clicked, what would you change next time?

---

## PR Review Checklist: The QA Lens

Work through this checklist to judge a PR's test quality and testability. Not every item applies to every PR — apply judgment based on the size of the change.

### Are There Real Tests?

- [ ] **Tests exist for the change.** New feature → new tests. Bug fix → a regression test. Pure refactor → existing tests still pass (bonus points if they improve). A behavioral PR with zero tests needs an explicit reason.
- [ ] **Both the happy path and the edge cases are covered.** At a minimum: valid input, invalid input, empty/null input, boundary values. For anything user-facing: error states, loading states, empty states.
- [ ] **Tests read as specifications, not implementation notes.** `rejects an expired promo code with a clear error message` beats `test promo validator function line 42`.

### Is the Code Actually Testable?

- [ ] **Inputs and outputs are clear.** Pure functions are easy to test by nature; anything with side effects should isolate them (dependency injection, wrapper functions).
- [ ] **Dependencies can be swapped in.** Database clients, HTTP clients, clocks, random number generators — pass these in or inject them, don't import them directly inside business logic.
- [ ] **No hardcoded magic numbers or strings.** Constants get names and can be configured; a test should be able to override them without touching production code.

### Is the Test Quality There?

- [ ] **Selectors are stable.** E2E tests should reach for `data-testid`, `getByRole`, or `getByLabel` — not CSS classes or XPath. See the selector-stability scoring in `test-reliability`.
- [ ] **Assertions are specific.** `expect(result).toEqual({ status: 'expired', code: 'PROMO_EXPIRED' })` beats `expect(result).toBeTruthy()`.
- [ ] **Test data is deterministic.** No silent dependency on the current date, random values, or auto-incrementing IDs — use factories or fixtures instead.
- [ ] **Tests clean up after themselves.** Records they create get deleted; state they change gets restored. No leftover pollution for the next test.
- [ ] **Test names tell the story.** Someone unfamiliar with the code should be able to guess what's being tested from the name alone.
- [ ] **No tests that exist only to pad coverage.** A test with no meaningful assertion inflates the coverage number without adding any real safety.

### When the Change Involves AI

Add these checks whenever a PR contains AI-authored code or ships an AI-powered feature.

- [ ] **AI involvement is disclosed.** The PR description names the agent, the model, and what it actually generated, so reviewers know how hard to look.
- [ ] **A human sits on at least one side of the loop.** AI writing both the implementation and its own tests is a closed loop that proves nothing — either the tests or the implementation should be written or critically reviewed by a person (see the TDD decision guide above).
- [ ] **Prompt and model version are pinned, not hardcoded.** For features that call an LLM, the prompt version and model ID should live in a flag-based config store — LaunchDarkly AI Configs (GA 2025) or an equivalent — rather than as ad-hoc strings that drift over time. The PR should point at a config key, not paste the prompt inline.
- [ ] **A runtime kill switch exists.** Any AI-powered path ships behind a feature flag that can be switched off without a redeploy — pairing shift-left prevention with shift-right containment.
- [ ] **A prompt eval test exists.** At least one regression test exercises the prompt against representative inputs (see `ai-system-testing`).
- [ ] **No invented APIs.** The reviewer confirms every imported symbol actually exists — LLMs are prone to inventing plausible-looking APIs that don't.

---

## Definition of Done, With Quality Gates

The Definition of Done is the team's standing agreement on what "done" actually means, applying before any story can move to "Done" on the board.

### A DoD Built Around Real Gates

A solid DoD groups its checks into five categories: Code Complete, Tested, Quality Gates Pass, Documentation, and Deployment Ready. The Tested category asks for unit tests on business logic, integration tests for API/service changes, an E2E test for user-facing critical paths, coverage of edge cases and error states, and **manual exploratory testing for medium- or high-risk changes**. The Quality Gates category asks for a green CI run, no new lint or type errors, and **coverage that hasn't dropped below the existing baseline** — a baseline figure, not an arbitrary threshold. See `references/templates.md` for the full copy-paste checklist.

### Making the DoD Stick

A DoD only means something if it's genuinely enforced. Three ways to get there:

1. **Automate the gates in CI.** Tests pass, coverage doesn't regress, linting passes — none bypassable without an explicit override from a team lead.
2. **Bake it into the PR template.** Include the DoD as a checklist inside the PR template itself; reviewers confirm the boxes are actually checked.
3. **Enforce it at sprint review.** A story only gets accepted once the DoD is genuinely met. "It works, but the tests aren't written yet" doesn't count as done.

---

## Maturity Ladder

Figure out where your team sits today, and what the next concrete step should be.

### Level 1: Reactive

**What it looks like:**
- QA only tests once development calls itself finished
- Bugs surface in staging or production
- Automated test coverage is minimal or absent
- Requirements are vague; QA finds the gaps while testing
- "QA" is a separate block tacked onto the end of the sprint

**Next step:** Bring QA into sprint planning and have them ask clarifying questions on every story before development starts. Track: requirement gaps caught in planning versus caught in testing.

### Level 2: Gate

**What it looks like:**
- QA reviews PRs but isn't part of the design conversation
- Automated tests exist, but they're written after the feature is already built
- A Definition of Done exists on paper but its testing items get skipped
- QA functions as a checkpoint, not a collaborator
- Bugs surface late because testing happens after the fact; rework is routine

**Next step:** Run Three Amigos for high-risk stories — QA, dev, and product working through requirements, edge cases, and test approach before coding starts. Track: fewer bugs found during QA testing as upstream quality improves.

### Level 3: Embedded

**What it looks like:** QA takes part in sprint planning and story refinement. Developers write unit and integration tests as they build. PR review includes real testability checks. QA and dev pair on designing test cases. The DoD is enforced through automated gates.

**Next step:** Require a failing test before every bug fix, then extend test-first thinking to TDD for pure business logic. Track: regression rate trending toward zero.

### Level 4: Collaborative

**What it looks like:** Three Amigos is the default for medium- and high-risk stories. Developers practice TDD for business logic and bug fixes as a matter of course. QA's time goes to exploratory testing, strategy, and risk analysis. Quality metrics get tracked and discussed regularly. Ownership of quality is genuinely shared across roles.

**Next step:** Extend shift-left into architecture and design review — have QA review system design documents for testability before implementation starts. Track: defect escape rate holding consistently under 5%.

### Level 5: Preventive

**What it looks like:** Quality is woven into every stage of the work. Defect escape rate sits consistently under 3%. QA engineers spend their time on strategy, coaching, and systemic improvement. Production issues are rare, and each one triggers a root cause analysis. The team can't really picture working any other way.

**Staying here:** Quarterly maturity check-ins. New hires learn quality practices from their first week. Retrospectives include quality metrics as a matter of course.

### Score Yourself

Rate eight practices — QA in planning, Three Amigos, PR review, tests written during development, failing-test-first bug fixes, TDD for business logic, an enforced DoD, regular metrics review — on a Never/Sometimes/Usually/Always scale to place your team on the Level 1–5 ladder. The printable worksheet with scoring bands is in `references/templates.md`.

---

## Anti-Patterns to Watch For

### Using "Shift Left" to Justify Cutting QA

Rebranding "developers now write all the tests" as shift-left in order to cut QA headcount. Shifting left changes when quality happens — not who owns it. QA engineers bring a testing mindset, risk analysis, and exploratory testing skill most developers haven't developed. Cut QA and tell developers to "just test more," and the result is blind spots, not savings.

### Ceremony With No Substance

Running Three Amigos as a box-checking ritual where nobody actually pushes back on anything. If a session doesn't produce at least one changed acceptance criterion or one newly surfaced edge case, it wasn't a real conversation — it was theater. Track "gaps surfaced per Three Amigos session" as a metric to keep this honest.

### Forcing TDD Everywhere

Applying TDD to UI prototyping, exploratory spikes, or anything where the design is still in flux. TDD earns its keep when the target behavior is already clear. When the domain is still uncertain, spike first and build tests around whatever design emerges. Lean on the decision guide above.

### Quality Gates Imposed From Above

Rolling out strict gates — coverage thresholds, mandatory QA sign-off — without explaining the reasoning or involving the team in setting the numbers. Gates that feel imposed get slowed down and worked around. Gates the team helped design get defended by the team.

### Testing at the Wrong Level

Writing E2E tests to cover business logic that a unit test would validate faster and more reliably. Writing unit tests for user flows that really need E2E coverage. Shifting left isn't just "test sooner" — it's "test at the right layer, as early as that layer allows." A calculation bug calls for a unit test, not a browser test.

### Counting Activity Instead of Results

Tracking "how many Three Amigos sessions we ran" instead of "defects found in planning versus defects found in production." Activities are inputs; what matters is the outcome. Measure whether these practices are actually cutting escaped defects and rework, not just whether they're happening.

---

## Verification

Confirm the gates actually do something — a gate that never trips proves nothing:

1. **A no-test behavioral PR gets blocked.** Open a disposable PR that changes behavior without a test (or drops coverage under baseline) and confirm CI turns red and merge is disabled. If it merges anyway, the gate is for show.
2. **The DoD checklist shows up in the PR template.** Confirm it's actually present in `.github/pull_request_template.md` (or your platform's equivalent) so every reviewer sees it — `test -f .github/pull_request_template.md && grep -qi "unit test" .github/pull_request_template.md`.
3. **The AI kill switch actually works.** For any AI-powered path, flip its flag off in your flag platform and confirm the path goes dark with no redeploy required.

---

## Done When

- The Definition of Done includes test criteria (unit, integration, and E2E gates) and lives in the repo (for example, inside `.github/pull_request_template.md`)
- A PR review checklist with a test-coverage check is checked into the PR template and enforced by branch protection
- At least one Three Amigos session has run for an upcoming feature, its gaps are documented, and the ticket's acceptance criteria reflect them
- A first dev/QA pairing session has happened and its agreed test signatures are committed to the repo
- Pre-merge quality gates (tests pass, coverage doesn't regress, linting passes) are live in CI, and a no-test PR has been observed to fail (see Verification, step 1)
- Every risky or AI-powered code path has a feature flag with a verified disable toggle (see Verification, step 3), so prevention (shift-left) and containment (shift-right) ship as a pair

## Reference Files (in `references/`)

- **tdd-examples.md** — Runnable code for the dev/QA pairing test-first exercise, the Red-Green-Refactor password-validator walk-through, and the failing-test-first bug example.
- **templates.md** — The copy-paste Definition of Done with quality gates, plus the shift-left maturity self-assessment worksheet.

## Related Skills

- **unit-testing** — Deeper patterns for writing effective unit tests, the core artifact these shift-left practices produce.
- **ai-qa-review** — Automated PR review for test quality and testability, scaling up the review patterns covered here.
- **test-strategy** — The overall testing approach that these day-to-day shift-left practices implement.
- **qa-project-context** — Project-specific context that shapes which shift-left practice to introduce first.
- **quality-postmortem** — When shift-left fails and a defect escapes anyway, postmortems reveal which practice would have caught it.
- **qa-project-bootstrap** — New team members get introduced to the team's shift-left practices as part of onboarding.
