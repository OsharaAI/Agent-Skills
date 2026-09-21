---
name: test-planning
description: >-
  Produces a concrete test plan scoped to a single sprint or a single release.
  Walks through decomposing features into testable scenarios, tracing
  requirements to the tests that cover them, estimating effort per test type,
  building a risk × effort prioritization matrix, assigning people to work, and
  laying out a schedule that has buffer built into it. Use when: "sprint test
  plan," "release test plan," "what to test this sprint," "test estimation,"
  "coverage mapping." Skip this one for multi-quarter strategy work (go to
  `test-strategy`), for ranking areas by risk on their own (go to
  `risk-based-testing`), or for making the actual go/no-go call (go to
  `release-readiness`).
  Related: test-strategy, risk-based-testing, release-readiness.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: strategy
---

<objective>
This skill turns a sprint or a release into an actionable test plan — a single document that pins down what gets tested, how thoroughly, who is responsible, and by when. It is meant to stay alive throughout the sprint, not get written once and filed away. Any plan that books every available hour to planned work is already broken, because the first bug found blows the schedule; buffer and prioritization are what let a plan absorb reality instead of breaking against it.
</objective>

## Quick Route

| Situation | Go to |
|-----------|-------|
| Planning one sprint | Work through Steps 1-6 below, then fill in the 1-page sprint template from `references/plan-documents.md` |
| Planning a release | Pull the release template from `references/plan-documents.md`; note that the actual go/no-go call lives in `release-readiness`, not here |
| Tracking a plan that's already running, or closing the loop afterward | Use the daily-status and retrospective formats in `references/tracking-formats.md` |
| Figuring out what to drop when demand outstrips capacity | Apply the Step 4 prioritization matrix |

---

## Discovery Questions

Gather this context before drafting anything. If `.agents/qa-project-context.md` already exists, treat it as your starting point and only ask what it doesn't already answer.

### Scope

- What's actually in scope — a sprint, a release, a hotfix, a single feature?
- For each feature: is it new, changed, or untouched this cycle?
- Which of these features is shipping for the very first time?
- Any infrastructure or dependency shifts involved — schema migrations, an API version bump, swapping a third-party provider?
- Is there a PRD, requirements doc, or set of user stories this plan needs to map onto?

### Time and Resources

- How much testing time is actually available (days, hours)?
- Who can actually do the testing — SDETs, manual testers, developers pulled in?
- Anything shared that could become a bottleneck — staging environments, test accounts, specific devices?
- Is the ship date fixed, or is there room to slip it?

### Risk Context

- Which parts of the system saw the most change this cycle?
- What broke last time — last sprint, last release?
- Any areas known to be fragile, or carrying tech debt that raises the odds of a problem?
- The methodology for scoring and ranking risk lives in `risk-based-testing` — lean on it here rather than reinventing it.

### Existing Coverage

- What automated coverage already touches the in-scope features?
- Where does the automated suite's pass rate currently sit?
- Are there known holes in automation that manual testing has to fill?
- How recently was exploratory testing last run against these features?

---

## Core Principles

### 1. Traceability comes first — every requirement needs a test

If a plan can't be traced back to requirements, it's really just a guess dressed up as a plan. Each user story, acceptance criterion, and requirement needs at least one test case pointing at it. Wherever that mapping is missing, you've found an untested requirement — which is the riskiest kind of gap there is.

### 2. The window is fixed — plan to fit it, not the other way around

Left unconstrained, testing will always grow to consume however much time exists. Give each activity a hard time box and hold it there. When the available window can't fit everything, let the prioritization matrix decide the cuts — not instinct.

### 3. Depth should follow risk, not be uniform

Treating a payment-flow rewrite the same as a tooltip label change wastes effort in the wrong place. The risk × effort matrix should drive how much depth each feature gets — full regression for some, a quick smoke test for others, and nothing at all for low-risk, unchanged areas.

### 4. Always hold back a buffer

A plan that commits 100% of the available time to planned work is guaranteed to break the moment a bug turns up. Cap planned work at 70-80% of the window and set the remaining 20-30% aside, explicitly, for verifying fixes, re-testing, and whatever unplanned investigation comes up. If that reserve isn't written into the plan as its own line, it doesn't functionally exist.

### 5. The plan exists to be seen, not filed

Engineers need visibility into what will be tested so they can write code that's actually testable. Product managers need coverage visibility to decide whether a release is ready to go. Put the plan somewhere the whole team can see it, not in a drawer.

### 6. Entry and exit criteria carry the most weight

The part of a plan people actually come back to is its gate, so state it plainly instead of burying it in prose: **entry** means code-complete on staging, the existing suite is green, and test data is seeded; **exit** means every HIGH-risk area has been covered, there are no open P0/P1 issues, and the coverage matrix has zero unexplained GAP rows. Nearly everything else in the plan is just supporting detail for these two checkpoints.

---

## Workflow

Each of the six steps below pairs with a fill-in-the-blank scaffold. This section holds the reasoning for why and how; the actual copy-paste artifacts — decomposition template, coverage matrix, estimation worksheet, prioritization grid, allocation table, schedule — all live in `references/workflow-templates.md`.

### Step 1: Break features into testable pieces

Decompose every in-scope feature into testable units — a testable unit being a specific, verifiable behavior with a clean pass/fail result. Check each feature against every one of these categories so nothing slips through:

- **Happy path** — the flow when everything goes right.
- **Validation** — empty required fields, malformed input, boundary values.
- **Error conditions** — a 5xx from the server, a timed-out request, input the system should reject.
- **Edge cases** — unicode text, oversized payloads, formats the system doesn't support.
- **Concurrency / race conditions** — simultaneous edits to the same record, double-submits, retrying after a timeout. This is the category that hides the ugliest data-corruption bugs, and it's also the one people forget most often.
- **Integration points** — how the feature behaves at each boundary it crosses.

The full decomposition template, plus a worked "User Profile Edit" example that touches all six categories, is in `references/workflow-templates.md`.

> **Cross-checking an agent's decomposition.** If an agent is doing the decomposition, immediately have it check its own scenario list against the Step 2 coverage matrix. Any requirement with nothing mapped to it, or any category above with zero entries, is a gap the agent should flag before estimation starts — catch the blind spot here, not later when CI does.

### Step 2: Trace requirements to tests

Build a traceability matrix linking every requirement to the test case(s) that verify it. The template for this lives in `references/workflow-templates.md`.

Rules to enforce on the matrix:
- Nothing gets left off — every requirement should appear (aim for full, 100% mapping)
- A "GAP" entry forces an explicit choice: write the missing test, accept the risk, or defer it
- Automated entries carry a test ID tied to a real file/function, not a description
- Manual entries point at the actual test case doc or exploratory charter

### Step 3: Estimate the effort

Estimate each test type's effort from historical data where you have it. Without history, start from the reference numbers below and adjust after the first sprint's actuals come in.

**Reference estimates (per test case):**

| Test Type | Write Time | Execute Time | Maintenance (per quarter) |
|-----------|-----------|-------------|--------------------------|
| Unit test | 0.5 hr | < 1 sec | 5 min |
| Integration test | 1 hr | 5-30 sec | 15 min |
| E2E test (Playwright/Cypress) | 2-3 hours | 30s-2 min | 30 min |
| Manual test case (write) | 0.25 hr | 5-15 min per execution | 10 min |
| Exploratory session (charter) | 15 min | 1.5 hrs per session | N/A |
| Accessibility review (manual) | 0.5-1 hr per area | included in write | 15 min |
| Visual regression test | 30-60 min | 10-30 sec | 20 min (baseline updates) |
| Performance test (k6 script) | 2-4 hours | 5-30 min per run | 30 min |
| Prompt regression / LLM eval | 30-60 min per case | 30 sec - 2 min (with API cost) | 20 min |
| Setup & test data (per feature) | 0.5-2 hrs | one-time | re-seed per env |

Write Time covers authoring only. The "Setup & test data" row is the one planners leave off most often, yet environment work, fixtures, and mock configuration typically eat 20-40% of total effort — give it a real line up front instead of discovering the cost mid-sprint.

> **The trade-off with AI-authored tests.** Letting an agent write tests can cut *Write Time* by roughly 40-60% — but budget an equally-sized *Review Time* line for each case. Bolton's "AI productivity paradox" (2026) describes exactly this: the time saved vanishes once an agent's plausible-looking-but-broken tests pass a light review and then fail in CI. `ai-test-generation` Step 7 has the review checklist; `ai-qa-review` has the smell taxonomy.

> **Make room for a test-smells pass.** ISTQB's CTAL-AT v2.0 (May 2026) treats test smells as something planning should account for. A recurring 30-minute "test-smells review" each sprint, run against the taxonomy in `ai-qa-review`, is cheap insurance against maintenance debt piling up unnoticed.

Roll the per-case numbers up using the sprint estimation worksheet in `references/workflow-templates.md` until you have a capacity-utilization figure — you're aiming for 70-80%, with 20-30% held back as buffer.

### Step 4: Build the risk × effort prioritization matrix

Estimated effort will usually exceed what capacity allows — when it does, use the risk × effort matrix to decide what falls away. The full grid is in `references/workflow-templates.md`.

Plot each test case using its risk score (from `risk-based-testing`) against its Step 3 effort estimate, then spend capacity in this order: **DO FIRST → DO SECOND → DO THIRD → DEFER → SKIP**.

**Tie-break rule:** inside the HIGH-risk row, cheap beats expensive — a HIGH-risk/low-effort test (DO FIRST) always ranks above a HIGH-risk/high-effort test (DO THIRD), since it buys the most risk reduction per hour spent. Push medium-risk items to DEFER before touching any HIGH-risk coverage; low-risk items are the ones that get deferred or dropped outright. The buffer itself is never fair game for fitting in more planned work.

### Step 5: Allocate people to the work

Match testers to tasks based on skill and who has time.

**Guidelines for allocation:**
- Route automated test authoring to SDETs or developers already comfortable with the framework
- Give exploratory testing to whoever knows the feature best — frequently the developer or PM, not necessarily QA
- New features benefit from a tester who didn't build them — fresh eyes catch more
- Never let critical-path testing depend on one person; make sure a second person could pick it up
- Cap everyone's load at 70-80% utilization, never 100% — the remainder is their personal buffer
- Split the buffer across people rather than pooling it under one tester — give every assignee their own buffer line, so one person's blocker doesn't eat into everyone else's slack

The allocation table format is in `references/workflow-templates.md`.

### Step 6: Lay out the schedule with buffer included

Place testing activities across the sprint timeline — don't let them pile up in the final two days. The 2-week schedule template is in `references/workflow-templates.md`.

**Scheduling rules that matter most:**
- Start testing as soon as a feature is code-complete, not once the sprint is winding down
- Set up environments and test data on Day 1 — not Day 3
- Verify bugs continuously as they're fixed, rather than batching verification
- Reserve the final day for confirming what's already done, not starting new work

---

## Plan Documents

The complete, ready-to-use documents are in `references/plan-documents.md`:

- **Sprint Test Plan (1-Page)** — scope table, coverage summary, effort budget, entry/exit criteria, and plan-level risks. A sprint plan should never exceed one page.
- **Release Test Plan** — rolls up the underlying sprint plans and layers on release-level concerns (full regression, cross-browser pass, perf benchmark, security scan, smoke test) plus go/no-go criteria. The go/no-go decision itself is `release-readiness`'s job, not this document's.
- **Feature Coverage Matrix** — a per-feature scenario list, each with priority, test type, location, and current status.
- **Test Estimation Worksheet** — covers new-test development, running the existing suite, manual testing, and a summary showing the delta against available capacity.

---

## Tracking Progress During the Sprint

A plan nobody revisits after Day 1 is dead weight. Check it daily while the sprint runs, and roll the outcomes into how you plan the next one.

- **Daily test status** — what got done, what's blocked, bugs found, what's planned for tomorrow, coverage percentage so far, and how much buffer has been used. Format is in `references/tracking-formats.md`.
- **Sprint retrospective inputs** — estimation accuracy broken down by test type, how coverage tracked against plan, bug counts by severity, and takeaways. Format is in `references/tracking-formats.md`; carry these numbers forward into the next sprint's estimates.

---

## Anti-Patterns

### Skipping risk assessment before planning

Giving every feature the same depth of testing burns effort on low-risk corners while under-covering the parts that matter most. Run the Step 4 prioritization matrix before committing effort anywhere — the full methodology for scoring risk lives in `risk-based-testing`.

### Leaving no room for bugs to surface

Booking every available hour to planned activities means there's nothing left when bugs actually show up. Hold back 20-30% as buffer, and track how much of it gets used, every day.

### Pushing all testing to the sprint's final days

Cramming everything into the last two days rushes coverage and surfaces bugs too late to act on. Start as soon as a feature is ready, and test continuously rather than in one end-of-sprint batch.

### Writing the plan as a compliance exercise

A thirty-page document that gets filed away helps no one. A sprint plan belongs on one page, gets checked daily, and changes as the sprint unfolds — a plan that never changes is a plan nobody's using.

### Guessing at estimates with no track record

Effort numbers invented from nothing tend to be wrong. Log actual time spent, split out by test type, and use that history to sharpen future estimates — reliability usually shows up after 2-3 sprints of doing this.

### Forgetting environment and data setup

Setting up environments, building test data, and configuring mocks can eat 20-40% of total testing effort. Keep the "Setup & test data" row from Step 3 in every estimate, or the plan will consistently run long.

### Leaving critical-path coverage to one person

If only one tester can cover the critical path, that person is a single point of failure. Make sure at least two people are capable of covering it.

---

## Verification

Before calling the plan finished, check it against these: every ticket ID that's in scope on the sprint board shows up in the Scope table; the coverage matrix has no unexplained GAP rows (each one carries an accept-risk or defer note); allocated capacity adds up to 70-80% with a clearly named buffer line; and the entry/exit criteria are actually filled in, not left as placeholders. Any failure on this list means the plan isn't ready yet.

## Done When

- [ ] The sprint or release test plan document exists (whichever template applies), with scope table, coverage summary, effort budget, and entry/exit criteria fully filled in — nothing left as a placeholder
- [ ] Every in-scope feature has been broken into specific scenarios with clear pass/fail criteria, spanning happy path, validation, error, edge, and concurrency categories
- [ ] The requirements-to-test coverage matrix is complete, with every GAP entry carrying an accept-risk or defer note
- [ ] Every scenario has an estimate and a spot on the risk × effort matrix, with anything deferred explicitly called out
- [ ] Capacity allocation sits at 70-80%, with 20-30% buffer reserved as its own named line
- [ ] Test data needs, environment details, and who's assigned to what are all written into the plan

## Reference Files (in `references/`)

- **workflow-templates.md** — The fill-in scaffolds behind each of the six workflow steps: decomposition template plus worked example, coverage matrix, sprint estimation worksheet, risk × effort grid, allocation table, and the 2-week schedule.
- **plan-documents.md** — The finished, copy-paste documents: 1-page sprint test plan, release test plan, feature coverage matrix, and estimation worksheet.
- **tracking-formats.md** — The daily test status format and the sprint retrospective inputs format, including per-test-type variance.

## Related Skills

- **test-strategy** — The larger QA strategy that individual test plans carry out; strategy sets the approach, plans execute it sprint by sprint.
- **risk-based-testing** — The deeper risk-assessment methodology feeding the Step 4 prioritization matrix.
- **release-readiness** — Owns the go/no-go decision that a release test plan's exit criteria ultimately feed; this skill assembles the plan, that one makes the ship call.
- **qa-metrics** — Metrics such as defect escape rate and estimation accuracy that sharpen future test plans.
- **exploratory-testing** — Covers the structured exploratory sessions referenced in this plan's manual testing sections.
- **qa-project-context** — Supplies the baseline answers to the discovery questions above.
