---
name: qa-do
description: >-
  Routing skill of last resort. Takes a plain-language QA situation and names the
  right 1-2 skills to use and in what order. Use ONLY when the request does not
  match any other skill's trigger phrases. Use when: "which skill should I use,"
  "where do I start," "I'm not sure what to test," "/qa-do," or any vague QA
  situation that doesn't map to one skill. Not for: bootstrapping a brand-new
  project with no QA — use qa-start. Not for: capturing project setup/context —
  use qa-project-context. If the request clearly matches another skill, invoke
  that skill directly instead of routing through here.
  Related: qa-start, qa-project-context, test-strategy.
license: Proprietary
compatibility: Cross-tool. Tested with Claude Code, Codex, Cursor, Gemini CLI. Reads the project root; no network access required.
metadata:
  author: osharaai
  version: "2.0"
  category: foundation
  argument-hint: "plain-language QA situation (e.g. 'our checkout flow is slow and tests are flaky')"
---

<objective>
Nearly every QA scenario falls into a pattern that's already been mapped out. Give this
skill a plain-language account of your goal or your problem, and it will match that
account to a pattern and name the one or two skills to use, in sequence. Its job is
diagnosis and routing, not restating the content of the skills it sends you to. When
called with arguments, treat the situation as `$ARGUMENTS`; otherwise, ask the user for a
sentence or two describing what's going on.
</objective>

## Core Principles

1. **Prefer precision over proximity.** Landing on a broad skill "in the neighborhood" is
   worse than landing directly on a narrow, exact-fit one. "Reproduce this bug" belongs
   with `bug-reproduction`, not the wider `ai-bug-triage`; "test our Stripe checkout" belongs
   with `payment-testing`, not generic `api-testing`. When it's unclear, favor whichever
   skill's trigger phrases match the actual artifact named in the request.

2. **Cap it at two skills, always ordered — never a stack.** Never hand back more than two.
   A second skill is only justified when the first one leaves an obvious gap uncovered
   (diagnose → measure, risk → checklist). When a single skill fully covers it, answer
   "Direct" and stop there. Needing three or more is itself a signal the situation is
   ambiguous — resolve that with a clarifying question rather than piling on skills.

3. **Treat the table as ground truth — and watch for drift.** This routing table is
   especially vulnerable to going out of date, because any new skill dropped into `skills/`
   creates a row that might not exist yet here. Whenever a skill is added or removed,
   regenerate both this table and the Skill Categories reference from `skills/`. If a
   request has nothing to match, don't force a bad direct hit — fall back to whichever
   Quick Reference category is closest.

## How to Use

Give a sentence or two on what you're doing or what's going wrong. In response, the router
names **the recommended skill(s) (1-2, in order)** with **a one-line explanation per
skill** of what role it plays. For instance: "Our E2E tests keep failing in CI but pass
locally" resolves to `test-reliability` first (to diagnose flaky or environment-sensitive
tests), followed by `ci-cd-integration` (to bring the pipeline environment in line with
local behavior).

## Common Situations and Their Skills

| Situation | Recommended Skills | Order |
|-----------|-------------------|-------|
| New project, no tests at all | `qa-start` (or `qa-project-context` → `test-strategy`) | Bootstrap the whole QA setup |
| Onboard a QA engineer to an existing codebase | `qa-project-bootstrap` | Direct — 30-day ramp + architecture audit |
| "Tests keep breaking in CI" | `test-reliability` → `ci-cd-integration` | Reliability first, then pipeline |
| "A UI refactor/redesign broke many selectors" | `selector-drift-recovery` | Direct — bulk regen, not per-test healing |
| "What should we test before this release?" | `risk-based-testing` → `release-readiness` | Risk first, then checklist |
| "We need Playwright tests" | `playwright-automation` | Direct |
| "We need Cypress tests" | `cypress-automation` | Direct |
| "Let an agent explore the app and assert outcomes" | `agentic-browser-testing` | Direct — goal-driven, no script |
| "Write tests from this PRD/spec/story" | `ai-test-generation` | Direct |
| "Reproduce this vague bug / turn this report into a failing test" | `bug-reproduction` | Direct — verified minimal repro + regression test |
| "Review my tests / find test smells" | `ai-qa-review` | Direct |
| "Our test suite is slow and flaky" | `test-reliability` → `qa-metrics` | Diagnose first, measure second |
| "Our suite is bloated / too many redundant tests" | `test-suite-curation` | Direct — audit + prune with evidence |
| "Manage / author manual test cases (TestRail, Xray, Zephyr, Qase)" | `test-case-management` | Direct |
| "Set up test reporting" | `qa-dashboard` → `ci-cd-integration` | Dashboard design, then CI wiring |
| "Test our API" | `api-testing` | Direct |
| "Write unit tests / add a mock / coverage threshold" | `unit-testing` | Direct |
| "Test our database / migration / data integrity" | `database-testing` | Direct |
| "Set up consumer-driven contract tests (Pact)" | `contract-testing` | Direct |
| "Where are our coverage gaps?" | `coverage-analysis` | Direct |
| "Do a structured exploratory / charter-based testing session" | `exploratory-testing` | Direct |
| "Check accessibility compliance" | `accessibility-testing` | Direct |
| "Test our payment / Stripe checkout / 3DS / subscription billing" | `payment-testing` | Direct |
| "Test the signup confirmation / password reset / OTP email flow" | `email-testing` | Direct |
| "Verify analytics / GA4 / pixel / dataLayer events fire correctly" | `analytics-tracking-testing` | Direct |
| "We got a bug in prod, understand why" | `bug-reproduction` → `quality-postmortem` | Reproduce first, then retro |
| "Classify / triage a batch of CI failures" | `ai-bug-triage` | Direct — batch failure clustering |
| "We're migrating from Selenium/Cypress" | `test-migration` | Direct |
| "Performance is degrading" | `performance-testing` → `observability-driven-testing` | Measure first, then trace |
| "Set up test data" | `test-data-management` | Direct |
| "Set up / containerize a test environment or staging" | `test-environments` | Direct |
| "Add tests to CI" | `ci-cd-integration` | Direct |
| "Visual changes breaking tests" | `visual-testing` → `test-reliability` | Baseline first, then stabilize |
| "We have no idea what quality looks like" | `qa-metrics` → `qa-dashboard` | Define KPIs, then surface them |
| "Third-party API is unreliable in tests" | `service-virtualization` | Direct |
| "Need to test on multiple browsers" | `cross-browser-testing` | Direct |
| "Need to test on real iOS/Android devices (Appium/Detox/Maestro)" | `mobile-testing` | Direct |
| "Security audit coming up" | `security-testing` | Direct |
| "Tests depend on each other and break in random order" | `test-data-management` → `test-reliability` | Fix data isolation first |
| "Roll out a feature safely (flags, canary) during release" | `testing-in-production` | Direct |
| "Schedule probes / SLA checks that run after release" | `synthetic-monitoring` | Direct |
| "Our QA is only catching bugs after dev, too late" | `shift-left-testing` → `test-planning` | Process change first, then plan |
| "We're building an AI/LLM feature and need to test it" | `ai-system-testing` | Direct |
| "Make this test report sound human / less AI-y" | `qa-report-humanizer` | Direct |
| "Make sure this is GDPR/EAA/AI Act compliant" | `compliance-testing` | Direct |
| "Run chaos / failure injection on staging" | `chaos-engineering` | Direct |

## When the Situation is Ambiguous

When a description could plausibly map to three or more skills at once, ask one
clarifying question to narrow things down. Once it's answered, the routing collapses
back to 1-2 skills.

- "Are you fixing something broken, or building new coverage from scratch?"
- "Is this a process problem (how the team works) or a tooling problem (what's running)?"
- "Is the priority speed of delivery, or confidence in correctness?"
- "Are you the only QA, or is this a team-wide change?"

### Disambiguation pairs (four overlaps worth resolving explicitly, not guessing at)

- **`test-reliability` vs `selector-drift-recovery`** — a single flaky test that needs
  runtime healing → `test-reliability`; a batch of selectors broken by an intentional UI
  refactor → `selector-drift-recovery`.
- **`cross-browser-testing` vs `mobile-testing`** — browser/CSS-engine differences →
  `cross-browser-testing`; real-device work with Appium/Detox/Maestro, gestures, or deep
  links → `mobile-testing`.
- **`ai-bug-triage` vs `bug-reproduction`** — clustering/deduping a batch of CI failures →
  `ai-bug-triage`; chasing down and understanding one specific bug → `bug-reproduction`.
- **`qa-start` vs `qa-project-bootstrap`** — a brand-new project with no QA in place yet →
  `qa-start`; bringing a QA engineer onto an existing codebase → `qa-project-bootstrap`.

## Skill Categories Quick Reference

Whenever skills change, regenerate this list from the `category:` field found in every
`skills/*/SKILL.md`.

| Category | Skills |
|----------|--------|
| **Foundation** | qa-project-context, qa-start, qa-do |
| **Strategy** | test-strategy, test-planning, risk-based-testing, exploratory-testing |
| **Automation** | playwright-automation, cypress-automation, api-testing, unit-testing, mobile-testing, visual-testing, performance-testing, cross-browser-testing, database-testing, security-testing, selector-drift-recovery |
| **Specialized** | accessibility-testing, payment-testing, email-testing, analytics-tracking-testing |
| **AI-QA** | ai-test-generation, ai-bug-triage, bug-reproduction, test-reliability, ai-qa-review, agentic-browser-testing |
| **Infrastructure** | ci-cd-integration, test-environments, test-data-management, contract-testing, service-virtualization |
| **Metrics** | qa-metrics, qa-dashboard, coverage-analysis |
| **Process** | shift-left-testing, qa-project-bootstrap, release-readiness, quality-postmortem, compliance-testing, qa-report-humanizer, test-case-management, test-suite-curation |
| **Production** | testing-in-production, synthetic-monitoring, observability-driven-testing |
| **Knowledge** | ai-system-testing, chaos-engineering, test-migration |

## Anti-Patterns

- **Sending a request to a broad skill when a precise one is available.** E.g., "Reproduce
  this bug" landing on `ai-bug-triage` (batch classification) instead of `bug-reproduction`
  (a single verified repro). Fix: match the specific artifact named in the request to the
  skill that actually names it.
- **Piling three or more skills onto one situation.** That's a symptom of ambiguity, not
  diligence. Fix: ask one clarifying question first, then narrow to 1-2.
- **Relying on an outdated table.** A skill added recently but missing its row will get
  silently routed to a weaker neighbor instead. Fix: regenerate the table from `skills/`
  (see Core Principle 3), and fall back to the nearest Quick Reference category rather than
  forcing an inaccurate match.
- **Absorbing a request that a named sibling already owns.** "Set up QA on a new project"
  belongs to `qa-start`; "capture project context" belongs to `qa-project-context`. qa-do
  only kicks in as a last resort.

## Related Skills

- **qa-start** — the sibling this one gets confused with most often. Reach for it (instead
  of qa-do) when standing up QA on a brand-new project with none in place; it chains
  context → strategy → planning.
- **qa-project-context** — captures project setup ahead of using most other skills, since
  every skill checks for it first. Route requests here rather than reimplementing that step.
- **test-strategy** — the fit when the ask is "we need a QA strategy" broadly, rather than
  a specific problem needing a route.
