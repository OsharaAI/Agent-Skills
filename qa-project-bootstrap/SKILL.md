---
name: qa-project-bootstrap
description: >-
  Onboard a new QA engineer to an existing codebase, or audit an existing test
  architecture. Produces a 30-day ramp plan: codebase orientation, framework
  walkthrough, test architecture audit, mentorship pairing, and first-test
  guidance. Use when: "QA onboarding," "new tester," "ramp up," "test architecture
  audit," "first 30 days," "QA mentorship," "joining QA team." Not for: setting up
  QA on a brand-new project from scratch — use `qa-start`.
  Related: qa-start, qa-project-context, shift-left-testing, ai-qa-review.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: process
---

<objective>
Hand a new QA engineer nothing but the README and tell them to "figure it out," and you'll lose two weeks to trial-and-error bad habits; leave an inherited test suite unaudited and it'll hide flaky tests and coverage gaps until they surface in production. This skill shortens the road to a first merged test and yields three concrete deliverables: a 30-day ramp plan, a five-dimension test architecture audit, and a framework walkthrough doc. Everything in it points at one metric — getting a real test merged to main and green in CI, quickly.

**Before starting:** Look for `.agents/qa-project-context.md` in the project root. When present, it already answers most discovery questions and supplies the technical context needed for onboarding. When absent, writing it is the first task on the list.
</objective>

## Quick Route

This skill covers three distinct jobs — figure out which one applies, jump straight to that section, and ignore the rest.

| Situation | Jump to | Output |
|-----------|---------|--------|
| Onboarding a **new person** to an existing team | First 30 Days Checklist → Mentorship Patterns | A 30-day ramp plan with owners and dates |
| Inherited an **existing suite** with no onboarding/docs | Test Architecture Audit (scope by `team_maturity`) | A 1-2 page findings doc, five dimensions |
| Need the **reference doc** for anyone writing tests | Framework Walkthrough Template | A project-specific walkthrough.md |

Full onboarding typically touches all three; a simple health check only needs the audit.

---

## Discovery Questions

### Who Is Being Onboarded?

1. **Is this a new QA engineer, or a developer who will contribute tests?** QA engineers need codebase orientation plus test strategy context; developers writing tests mainly need framework patterns and conventions. These are meaningfully different ramp-up paths.

2. **How experienced is this person with the test framework?** Brand new to Playwright/Cypress/pytest, experienced but unfamiliar with this codebase, or advanced and just needs local conventions? The answer sets how much of the framework walkthrough is actually needed.

3. **Are they the only QA person, or joining an established QA team?** A solo QA has to invent conventions from nothing. Someone joining a team instead learns existing patterns and works within norms that already exist.

### Project State

4. **Does a test framework already exist?** If so, assess its health. If not, picking one is the very first step (see the `test-strategy` skill).

5. **Is there a `.agents/qa-project-context.md` file in the project?** If not, writing one should be a top onboarding priority — it makes the new person document what they're learning, which pays off for the whole team.

6. **Is the local environment setup actually documented?** Can someone new stand up the full stack and run tests on day one? If it takes more than 2 hours, fix the setup process before bringing anyone on.

### Access and Tooling

7. **Are the necessary accounts and permissions already provisioned?** Repo access, CI dashboard, staging environment, test data accounts, bug tracker, team communication channels. Missing access on the first day wastes time and breeds frustration.

---

## Core Principles

### 1. Time to First Merged Test Is the Success Metric

The clearest signal that onboarding is working is how fast the new hire lands a real test on the main branch — not a tutorial exercise, not something that only runs locally, but a genuine test that executes in CI and checks real product behavior. Aim for the first two weeks.

### 2. Progressive Complexity

Ramp difficulty up gradually rather than all at once. Test one: a smoke test or a page-load check. Test two: interacting with a form. Test three: a multi-step user flow. By the third week, the new person should be handling tests for sprint stories directly. Dropping someone into a complex multi-service flow on day one just breeds anxiety and sloppy habits.

### 3. Document Tribal Knowledge

Any question a new person asks that documentation doesn't already answer is a sign tribal knowledge is leaking away. The onboarding process needs to capture those answers somewhere permanent — `.agents/qa-project-context.md`, the framework walkthrough doc, or inline code comments are all fair game. The new hire is actually the ideal author here, since they know firsthand what was missing.

### 4. Pair First, Solo Second

For the first three tests, pair the new person up — they drive, an experienced teammate navigates. Pairing passes along tacit knowledge (the *why* behind conventions, not merely the *how*) and builds confidence faster than documentation alone ever could.

### 5. Make the Easy Path the Right Path

When writing a test correctly takes more effort than writing it wrong, people default to the wrong way. Test utilities, fixtures, page objects, and data factories should be built so the recommended pattern is also the path of least resistance. If a newcomer has to fight the framework just to follow convention, that's a signal to fix the framework, not the person.

> **Calibrate to team maturity** (set via `team_maturity` in `.agents/qa-project-context.md`):
> - **startup** — Concentrate on days 1–10: get a single test framework working and one critical path under coverage. Hold off on process ceremony until there's a working baseline.
> - **growing** — Run the full 30-day plan: pick a framework, wire up CI, establish a coverage baseline, document team conventions.
> - **established** — The full 30-day plan, plus: audit the existing suite for anti-patterns, propose tooling upgrades, set a metrics baseline, and schedule recurring quality reviews.

---

## First 30 Days Checklist

### Week 1: Environment, Access, and Orientation

**Day 1-2: Setup**
- [ ] Repository cloned and building locally
- [ ] All environment variables configured (`.env.local`, test credentials)
- [ ] Application running locally (frontend + backend + database)
- [ ] Test suite runs locally and passes (or known failures are documented)
- [ ] IDE configured with recommended extensions (test runner plugin, linter, formatter)
- [ ] Access granted: CI dashboard, staging environment, bug tracker, team channels

**Day 3-4: Orientation**
- [ ] Read `.agents/qa-project-context.md` (or create it if it does not exist)
- [ ] Walk through the test directory structure with a team member
- [ ] Understand the test pyramid: how many unit, integration, and E2E tests exist
- [ ] Review the CI pipeline: what runs on PR, what runs nightly, what blocks merge
- [ ] Identify the top 5 critical user flows (these will be the first testing targets)
- [ ] Attend one Three Amigos or sprint planning session as an observer
- [ ] **Working with the team's AI assistants:** Figure out which coding agents the team relies on (Claude Code, Codex, Cursor, Gemini CLI, etc.), where each keeps its context (`.agents/qa-project-context.md`, `CLAUDE.md`, `AGENTS.md`), which prompts/skills count as house style, and which tasks the team deliberately keeps away from AI. Write this up as a short "AI assistants we use, what they're good at, what to never let them do" doc, due Day 4. Note also that if the team drives Playwright through an agent, there's now a dedicated `@playwright/cli` for agent-driven Playwright (daemon architecture, `playwright-cli` commands, token-efficient) — separate from the `npx playwright test` runner covered in the framework walkthrough.

**Day 5: First Small Win**
- [ ] Run a single test in debug/headed mode and understand what it does
- [ ] Modify one assertion in an existing test, verify it fails as expected, revert
- [ ] Read 3 existing tests and annotate what each section does (setup, action, assertion)

### Week 2: First Real Test

- [ ] Identify a simple, low-risk test to write (page loads, element visibility, basic navigation)
- [ ] Write the test using existing page objects and fixtures (pair with a team member)
- [ ] Run the test locally, ensure it passes reliably (3 consecutive runs)
- [ ] Open a PR, receive feedback, iterate
- [ ] Test passes in CI
- [ ] **First test merged**

### Week 3: Sprint Contribution

- [ ] Pick up a sprint story's QA work (with mentorship)
- [ ] Write tests covering the story's acceptance criteria
- [ ] Identify at least one edge case not covered by acceptance criteria
- [ ] Participate actively in Three Amigos or story refinement (ask questions)
- [ ] Review one existing PR for test quality (using the PR review checklist from `shift-left-testing`)

### Week 4: Independence Milestones

- [ ] Write and merge a multi-step E2E test without pairing
- [ ] Participate in bug triage and articulate testing gaps
- [ ] Contribute to `.agents/qa-project-context.md` with new learnings
- [ ] Present test results/findings at sprint review or team standup
- [ ] Self-assess: which test patterns feel comfortable? Which need more practice?

---

## Test Architecture Audit

Before writing new tests on an existing project, check the health of what's already there. The audit takes 2-4 hours and gives a clear read on the current state.

**Scope the audit to `team_maturity`** (from `.agents/qa-project-context.md`) — running the same audit regardless of maturity wastes a startup's time and shortchanges an established team:
- **startup** — Don't run the full audit. Just confirm one path has coverage and one framework runs, then put the time saved toward merging a first test.
- **growing** — Cover all five dimensions once to set a baseline; put off recurring reviews for later.
- **established** — Run the full five-dimension audit and schedule recurring quality reviews (monthly, say), tracking the findings doc over time.

### What to Assess

Five dimensions to assess, each backed by its own fill-in worksheet:

- **Coverage and Distribution** — test counts by layer, pyramid shape, code coverage and trend.
- **Reliability** — flaky test rate, top flakiest tests, quarantine count and age.
- **CI Health** — full suite and per-stage duration, parallelism, pass rate, retry rate.
- **Technical Debt** — skipped tests, `waitForTimeout`/`force: true` usage, hardcoded data, assertionless tests, deprecated APIs, stale AI-generated tests, stale feature flags.
- **Conventions** — page objects, fixtures, factories, naming, shared utilities, tagging.

See `references/audit-worksheets.md` for the copy-and-fill worksheets covering all five dimensions.

### Audit Output

Write up a short (1-2 page) findings document, sorted into these categories:

- **Strengths:** What already works well in the suite (worth preserving and learning from)
- **Gaps:** Coverage that's missing, critical paths that are undertested
- **Risks:** Flaky tests, aging quarantines, coverage trending down
- **Quick Wins:** Fixes doable in 1-2 sprints (flaky test fixes, filling in missing happy-path coverage)
- **Strategic Work:** Investments that take sustained effort (reworking the test architecture, adding an integration layer)

---

## Framework Walkthrough Template

Every project should have this document — it's the go-to reference for anyone writing tests. It breaks into six sections:

1. **Architecture Overview** — framework, language, where config lives, and an annotated directory tree.
2. **How to Run Tests** — the complete command set (full run, single file, grep filter, headed, debug, UI mode, per-browser, report).
3. **How to Write a New Test (Step by Step)** — the six-step locate/reuse/write/run/PR sequence and an Arrange-Act-Assert template.
4. **How to Debug Failures** — separate playbooks for local vs. CI failures and a decoder for common failure patterns.
5. **Common Patterns and Conventions** — project-specific examples covering auth fixtures, data factories, assertion specificity, selector priority.
6. **Where to Find Help** — a routing table for questions about patterns, failures, product behavior, and documentation.

`references/framework-walkthrough.md` has the full copy-and-adapt version, with all code blocks, directory trees, and command lists included.

---

## Codebase Orientation Guide

Cover these areas with the new person in one 60-90 minute session.

### Test Directory Structure Tour

Walk the real directory tree together and explain:
- The reasoning behind the organization (grouped by feature, not by type)
- Where each product area's page objects live
- Where the shared utilities sit and what each one does
- Where test data and fixtures are defined
- Where CI configuration lives

### Shared Utilities Inventory

| Utility | Location | Purpose | Example |
|---------|----------|---------|---------|
| Auth fixture | `fixtures/auth.fixture.ts` | Hands back authenticated sessions | `{ adminPage, userPage }` |
| Data factory | `helpers/factories.ts` | Generates test data through the API | `createTestUser({ role: 'editor' })` |
| API client | `helpers/api-client.ts` | Makes direct API calls for setup/teardown | `apiClient.delete('/users/' + id)` |
| Accessibility helper | `helpers/a11y.ts` | Wraps axe-core | `checkAccessibility(page, testInfo)` |
| Assertions | `helpers/assertions.ts` | Custom matcher library | `toHaveToast('Saved')` |

### Page Objects Walk-Through

Walk through the existing page objects and cover:
- The base page class and its contract (abstract `path`, `waitForReady`)
- How component objects compose into page objects
- The naming convention (file name mirrors the route: `checkout.page.ts` for `/checkout`)
- How to create a new page object (copy the simplest existing one and modify)

### CI Pipeline Walk-Through

Open up the CI config and trace through:
- What kicks off the pipeline (push, PR, schedule)
- Which stages run, and in what sequence
- Where the artifacts land (reports, traces, screenshots)
- How to locate and read a failed test in CI
- How to re-trigger a failed job

---

## Mentorship Patterns

### Pair on First 3 Tests

Have an experienced teammate sit alongside the new hire for their first three tests:

1. **Test 1: Navigator/Driver.** The experienced person walks through their approach and makes the key calls; the new person types and keeps asking "why?" Goal: grasp the workflow.
2. **Test 2: Co-pilots.** Both contribute equally, with the new person taking more of the decisions and the experienced person covering gaps. Goal: build confidence.
3. **Test 3: Observer.** The new person drives the whole thing; the experienced person only steps in when asked or when the approach is heading somewhere problematic. Goal: independence.

### Review All PRs for First 2 Weeks

For the first two weeks, give every PR from the new person a thorough, supportive review — not a rubber-stamp "LGTM," but specific feedback covering:
- Pattern adherence (correct use of page objects?)
- Selector strategy (stable locators?)
- Assertion quality (specific enough?)
- Test isolation (any shared-state risk?)
- Naming (does the test name actually describe the behavior?)

Once two weeks are up, drop back to the standard review depth.

### Testing Buddy System

Pair the new team member with a dedicated buddy they can bring any question to without hesitation. The buddy's job:
- Check in daily during week one ("what are you stuck on?")
- Stay available for unscheduled, ad-hoc questions
- Review every PR with educational, "why"-focused comments
- Walk the new person through team norms and unwritten rules

### Progressive Responsibility Ramp

```
Week 1-2:  Write tests for existing, well-understood features (smoke, basic flows)
Week 3-4:  Write tests for current sprint stories (with pairing available)
Week 5-6:  Write tests independently, review others' PRs
Week 7-8:  Contribute to test architecture (new fixtures, utilities, page objects)
Month 3+:  Lead test planning for a feature area, mentor the next new person
```

---

## Anti-Patterns

### Sink or Swim Onboarding

Handing someone repo access, pointing at the README, and leaving them to sort it out on their own. The result is weeks of wasted effort, bad habits picked up through trial and error, and a higher chance they leave early. Structured onboarding with pairing pays for itself within the first sprint.

### Tutorial-Only Onboarding

Burning two weeks on framework tutorials and toy exercises before ever touching the real codebase. Tutorials only teach syntax — not project conventions, domain knowledge, or how the team actually works. Cap tutorials at 1-2 hours and get to real tests fast.

### No Documentation, All Tribal Knowledge

If every question gets answered with "ask Sarah," the team has a bus factor of one, and onboarding lives or dies on Sarah's calendar. Write conventions down in `.agents/qa-project-context.md` and the framework walkthrough instead. Anything worth explaining out loud is worth writing down.

### Perfectionism Paralysis

Holding the new person's first test to a perfect standard. A first test only needs to work and follow the basics — quality improves naturally across review cycles. Blocking that first PR over style nits or advanced patterns kills confidence and delays the first real win.

### Ignoring the Onboarding Experience

Skipping feedback from the person who just went through onboarding. They're the one who lived it and knows exactly what was confusing, missing, or a waste of time. Run a 15-minute feedback conversation at the end of week 2 and again at week 4, and feed that back into the process for whoever's onboarded next.

### Copy-Paste Without Understanding

The new person clones an existing test, swaps out the locators and URL, and calls it finished — it works, but they don't actually understand why. Pairing and review should dig into the "why" behind each pattern; someone who can't explain why a fixture is built a certain way will misuse it the moment the context shifts.

---

## Verification

Confirm the deliverables actually hold up before calling onboarding done. Start with the cheapest check.

1. **The first merged test is stable, not a fluke.** Repeat it to rule out flakiness, then confirm CI is green.
   - `npx playwright test <new-test> --repeat-each=3` exits 0 (3 consecutive local passes)
   - The same test's CI check on the PR is green
2. **The audit doc is genuinely complete, not a stub.** Open the findings doc and check all five dimensions (coverage/distribution, reliability, CI health, technical debt, conventions) are filled in, with findings sorted into strengths / gaps / risks / quick wins / strategic work. A startup that deliberately skipped the audit (per `team_maturity`) should instead have that decision written down.
3. **The context file is populated, not just present.** `.agents/qa-project-context.md` exists and actually contains framework, critical paths, team structure, and risk areas — not a vague placeholder.

## Done When

- At least one real test is merged, passing in CI, and stable across 3 local repeats (`--repeat-each=3` exits 0) — this proves out the local and pipeline setup end-to-end.
- The test architecture audit doc exists, all five dimensions are filled in, and findings are sorted (strengths, gaps, risks, quick wins, strategic work) — or, for a startup-level `team_maturity`, the doc explicitly records the decision to skip it.
- Every Day-1/2 setup item in Week 1 has an assigned owner and a target date; anything blocking gets filed as a tracked ticket.
- `.agents/qa-project-context.md` exists and is filled in with framework, critical paths, team structure, and risk areas (not left as a placeholder).
- A test framework has been chosen with the reasoning recorded (alternatives considered, decision documented) — or marked N/A if an existing framework was simply inherited.

## Reference Files (in `references/`)

- **framework-walkthrough.md** — The complete framework walkthrough template: architecture overview, run commands, the new-test step-by-step and template, debug playbooks, conventions, and where to find help.
- **audit-worksheets.md** — Copy-and-fill worksheets for the test architecture audit (coverage, reliability, CI health, technical debt, conventions).

## Related Skills

- **qa-project-context** -- The project context file underpins everything else in onboarding. Create it if missing; keep it updated as onboarding proceeds.
- **playwright-automation** -- Framework-specific patterns, page object model, fixtures, and CI integration for projects built on Playwright.
- **shift-left-testing** -- Brings the new person up to speed on the team's shift-left practices: Three Amigos, PR review, Definition of Done.
- **test-strategy** -- Grasping the overall testing strategy gives the new person context for why the tests are structured the way they are.
- **test-reliability** -- Understanding flaky test patterns and quarantine management keeps the new person from introducing unreliable tests of their own.