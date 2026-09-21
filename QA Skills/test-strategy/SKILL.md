---
name: test-strategy
description: >-
  Builds a multi-quarter QA strategy document: scope definition, risk-based
  prioritization, test levels (unit/integration/E2E), pyramid diagnosis,
  entry/exit criteria, quality KPIs, tool-selection rationale, CI scaling
  levers, and a phased timeline. The output is meant to be used, not filed
  away — a document that shapes daily testing decisions rather than a
  compliance artifact. Use when: "test strategy," "QA strategy doc,"
  "testing approach," "QA roadmap," "multi-quarter QA direction." Not for: a
  single-sprint or single-release plan — use test-planning. Not for:
  identifying which areas carry the most risk — use risk-based-testing
  first.
  Related: risk-based-testing, qa-metrics, release-readiness, test-planning,
  test-reliability.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: strategy
---

<objective>
Produce a QA strategy fitted to the product's risk profile, the team's makeup, and its constraints — a document meant to steer real testing decisions day to day, not a compliance artifact that sits unread. Picture a team with 150 E2E tests running through a 52-minute pipeline: on the surface that reads as solid coverage. This skill's job is to see past that, diagnose the inverted pyramid underneath, prescribe how to rebalance it, and attach a measurable KPI to every piece of the strategy.
</objective>

---

## Questions to Ask Before Writing Anything

Gather context before drafting a single section. First check whether `.agents/qa-project-context.md` already exists — if so, treat it as the starting point and skip any question it already answers.

### About the Product and the Business
- What kind of product is this? (SaaS, e-commerce, API platform, mobile app, content site)
- Who uses it? (consumers, enterprise buyers, internal staff, developers)
- Which flows matter most to the business? (signup, checkout, payment, data export)
- How often does it ship? (continuous, weekly, bi-weekly, quarterly)
- Any compliance obligations in play? (SOC2, HIPAA, PCI-DSS, GDPR, EU AI Act)

### Where Testing Stands Today
- Which test levels exist right now, and how many tests sit at each one?
- What frameworks and tooling are already in use?
- Current code coverage — and is there a target?
- How long does a full CI run take, start to finish?
- What's the current flake rate?

### Pain Points and Goals
- What hurts most today? (regressions, slow feedback loops, flaky tests, coverage gaps)
- What broke across the last three releases, and what got past testing into production?
- What would "good enough" quality actually look like for this team?
- How much appetite is there to invest in test infrastructure?

### Team and Constraints
- Team size and makeup (developers, QA, SDETs, manual testers)
- How comfortable is the team with automation tooling?
- Any budget ceiling on tooling?
- Is there a deadline forcing this strategy's timeline?

---

> **Match the plan to team maturity** (record `team_maturity` in `.agents/qa-project-context.md`):
> - **startup** — Keep the pyramid minimal: unit tests plus a small set of critical E2E paths. Hold off on contract testing and formal metrics until CI is stable. Phase 1 should close out in under 4 weeks.
> - **growing** — Build the full pyramid with real coverage targets, flakiness thresholds, and CI gates. Layer in risk-based prioritization.
> - **established** — Go further: SLA-backed gates, coverage across multiple environments, advanced tooling (contract testing, chaos engineering, observability), and a formal review cadence.

---

## Principles That Drive the Strategy

1. **Prioritize by risk, not by exhaustiveness.** Code isn't uniformly important — a bug in the payment flow costs roughly 1000x what a tooltip typo costs. Effort should track business risk, not lines of code. The risk matrix is what tells you where to spend that effort; if one doesn't exist yet, run `risk-based-testing` first.

2. **The pyramid's shape is the metric to watch.** A healthy suite has lots of fast unit tests, a smaller layer of integration tests, and the fewest E2E tests of all. When that shape flips — the "ice cream cone" — feedback slows, upkeep balloons, and confidence in the suite drops even as test count rises. Figure out the current shape before recommending any fix.

3. **Push validation left.** The later a defect is caught, the more it costs to fix — often exponentially. Catch problems at the earliest layer that can catch them: static analysis before any test runs, unit before integration, contract checks before E2E. Design review, in particular, catches architectural problems no automated test ever will.

4. **No element of the strategy exists without a number attached.** Anything you can't measure, you can't tell whether you're improving. Coverage targets, flake thresholds, escape-rate goals, MTTR ceilings — every section should name a target number and how often it gets checked.

5. **Treat it as a living document.** Revisit it at least quarterly. It should carry a revision log, a named owner per section, and clear triggers for re-evaluation (a new product area, a team change, a major incident, a defect that escaped).

---

## Building the Strategy Document Section by Section

Work through each section below to assemble the final document. Match depth to actual complexity — a 5-person startup's strategy should run 5 pages, not 50. The finished document follows a fixed 13-section outline (Executive Summary through Revision History). The copy-paste markdown skeleton for that outline lives in `references/diagrams-and-worksheets.md`; four fully worked examples across different product types (SaaS, e-commerce, API-first, media) live in `references/strategy-templates.md`.

### 1. Scope & Objectives

Draw the boundaries first — vagueness here creates gaps and wasted work later.

- **In scope:** list every product area, service, and integration the strategy touches; both functional and non-functional test types; the platforms, browsers, and devices covered.
- **Out of scope:** call out explicitly what isn't covered and why — e.g., third-party services validated only at the contract level, or legacy systems on their way out.
- **Objectives:** 3-5 measurable goals, each with a deadline — for example, "Bring defect escape rate from 12% down to under 5% within two quarters," or "Reach 80% unit coverage on every service shipped after Q1 2026."

### 2. Test Levels & Types

For each level, define what it covers, who's responsible, and roughly how many tests should live there.

| Level | What It Validates | Owner | Framework | Target Count | Run Frequency |
|-------|-------------------|-------|-----------|-------------|---------------|
| **Unit** | Functions, business logic, edge cases | Developers | Vitest/Jest/pytest | 70-80% of all tests | Every commit |
| **Integration** | Service interactions, DB queries, API contracts | Developers + QA | Supertest/pytest + Testcontainers | 15-20% of all tests | Every PR |
| **E2E** | Critical user journeys through the full stack | QA/SDET | Playwright/Cypress | 5-10% of all tests | Pre-deploy + nightly |
| **API** | Contract compliance, schemas, error handling | Developers | Playwright APIRequestContext/Schemathesis | Per endpoint | Every PR |
| **Visual** | UI regression, layout shifts, responsive | QA | Playwright/Argos/Chromatic | Key pages | Nightly |
| **Performance** | Response times, throughput, resource usage | DevOps/QA | k6/Lighthouse | Critical paths | Weekly + pre-release |
| **Security** | OWASP Top 10, dep vulns, auth flows | Security/DevOps | OWASP ZAP/Snyk | Per release | Pre-release + scheduled |
| **Accessibility** | WCAG 2.2 AA, screen reader compat | QA/Frontend | axe-core | Key flows | Every PR |

Adapt this to the actual product — not every product warrants visual regression testing, but virtually every product warrants unit and integration coverage.

### 3. Test Pyramid Analysis

Start by diagnosing the shape you have; only then define the shape you want.

**The four shapes.** A test suite generally lands in one of four shapes: a healthy pyramid (unit-heavy, E2E-light), an ice cream cone (inverted — dominated by E2E), a diamond (integration-heavy), or an hourglass (unit- and E2E-heavy with a thin integration middle). Each carries its own trade-off between feedback speed and maintenance burden. The side-by-side ASCII diagrams live in `references/diagrams-and-worksheets.md`.

**Assess the current state.** Count the tests at each level, work out the percentage split, name the shape, and record CI duration, flake rate, and pass rate alongside it. The Current State Assessment Worksheet in the reference file has the fill-in-the-blanks version.

**Set the target state.** Pick target ratios (roughly 70-80% unit, 15-20% integration, 5-10% E2E), translate them into concrete test counts, and set target CI duration and flake rate too. See the Target State Worksheet for the template.

**If the shape is an ice cream cone or a diamond, work this plan:**
1. **Stop growing E2E** — no new E2E test gets added unless it covers a genuinely new critical path.
2. **Push existing E2E tests down a level** — find E2E tests that are really validating unit-level logic (e.g., a checkout test asserting tax math belongs on the tax function as a unit test) and rewrite them there.
3. **Bake unit-test requirements into the PR checklist** — any PR touching business logic must ship unit tests with it.
4. **Gate CI on the ratio** — fail the PR if the unit-to-E2E ratio drops below the agreed threshold.

Before you start trimming E2E tests, separate the ones that are genuinely flaky from the ones surfacing a real bug — quarantine the wrong one and a race condition slips straight into production. For the mechanics of flake triage and quarantine, see `test-reliability`.

**If the shape is an hourglass, work this plan instead:**
1. **Build out integration infrastructure** — DB fixtures, service stubs, contract tests.
2. **Map service boundaries** — every boundary needs integration coverage for both the happy path and error cases.
3. **Adopt contract testing** (Pact) for the communication between services.

### 4. Risk Assessment Matrix

Mapping features to risk levels is what actually determines how deeply each one gets tested. Score every feature on Impact (1 Negligible → 5 Catastrophic) times Likelihood (1 Rare → 5 Almost Certain); the resulting product (1-25) sorts into LOW/MED/HIGH/CRIT bands. The full 5x5 matrix, with every cell labeled, is in `references/diagrams-and-worksheets.md`.

| Risk Level | Testing Action | Automation | Monitoring |
|------------|---------------|------------|------------|
| **CRITICAL (15-25)** | Full automation + manual exploratory + load test | Mandatory, every commit | Real-time alerts, synthetic monitoring |
| **HIGH (10-14)** | Full automation + periodic manual review | Mandatory, every PR | Dashboard + daily checks |
| **MEDIUM (5-9)** | Automation for happy path + key error cases | Recommended | Weekly review |
| **LOW (1-4)** | Manual testing or skip | Optional | None required |

**Worked example:**

| Feature Area | Impact | Likelihood | Score | Testing Approach |
|-------------|--------|------------|-------|-----------------|
| Payment processing | 5 - Catastrophic | 3 - Possible | 15 - CRIT | Automated E2E + unit + contract + monitoring |
| User authentication | 5 - Catastrophic | 2 - Unlikely | 10 - HIGH | Automated E2E + security scan + unit |
| Product search | 3 - Moderate | 3 - Possible | 9 - MED | Unit + integration + happy-path E2E |
| Dashboard rendering | 2 - Minor | 3 - Possible | 6 - MED | Unit + visual regression |
| Email preferences | 1 - Negligible | 2 - Unlikely | 2 - LOW | Manual verification |

### 5. Environment Strategy

| Environment | Purpose | Test Types | Data | Deploy Trigger |
|------------|---------|------------|------|---------------|
| **Local** | Developer feedback | Unit, integration | Mocked/seeded | On save |
| **CI** | Automated validation | Unit, integration, lint, SAST | Ephemeral | On push/PR |
| **Staging** | Pre-production validation | E2E, visual, performance, security | Production-like (anonymized) | On merge to main |
| **Production** | Monitoring & smoke | Smoke tests, synthetic monitoring | Live | On deploy |

Spell out how each environment's test data is managed, whether it's ephemeral (preview deploys) or long-lived, who can access it, and how per-environment config is handled.

### 6. Tool Selection Rationale

Tools come after needs, not before. Once the needs are clear, score each candidate tool against weighted criteria.

| Criteria (weight) | Tool A | Tool B | Tool C |
|-------------------|--------|--------|--------|
| **Fits tech stack** (25%) | | | |
| **Team familiarity** (20%) | | | |
| **Community & docs** (15%) | | | |
| **CI integration** (15%) | | | |
| **Maintenance cost** (10%) | | | |
| **Speed of execution** (10%) | | | |
| **License cost** (5%) | | | |
| **Weighted total** | | | |

Rate each criterion 1-5, multiply by its weight, and sum for the weighted total. Beyond license fees, factor in **total cost of ownership**: time to get it running (CI config, first tests written, team trained), time to write tests (clock 5 real ones to get a sense of pace), time spent on maintenance (how often framework upgrades break existing tests), time spent debugging (clear error messages save a lot here), and infrastructure spend (browser farms, parallel runners).

**Typical stack starting points** — note in the doc why you kept these or diverged:

| Product Type | Unit | Integration | E2E | API | Visual |
|-------------|------|-------------|-----|-----|--------|
| React SaaS | Vitest | Testing Library + MSW | Playwright | Supertest | Playwright screenshots |
| Next.js | Vitest | Testing Library + MSW | Playwright | Supertest | Playwright screenshots |
| Python API | pytest | pytest + Testcontainers | pytest + requests | Schemathesis | N/A |
| Mobile (RN) | Jest | Testing Library + MSW | Detox / Maestro / Appium 3.x | Supertest | Appium screenshots |
| Vue SaaS | Vitest | Testing Library + MSW | Playwright | Supertest | Playwright screenshots |
| AI/LLM features | Vitest | DeepEval | Playwright + Promptfoo evals | Promptfoo / Ragas | N/A |

If the strategy covers AI/LLM features, add dedicated risk testing for hallucinations, bias, prompt injection, and privacy — see `ai-system-testing` and `compliance-testing` (EU AI Act).

**Frameworks worth knowing:**
- **CTAL-AT v2.0** (ISTQB, Advanced Agile Tester, 2026) — a brand-new Advanced-level certification requiring CTFL v4.0 as a prerequisite, not a revision of an older Advanced course; it takes the place of the now-retired Foundation-level CTFL-AT Agile extension (whose content has already folded into CTFL v4.0). Covers strategy and approach, whole-team practices, shift-left, end-to-end testing, test smells, and exploratory plus AI-assisted testing.
- **CT-GenAI v1.1** (ISTQB, released 2026-04-27) — treats LLM-powered test infrastructure as its own discipline and defines AI-specific risk classes: hallucinations, reasoning errors, bias, privacy, AI regulation.
- **CTFL v4.0** (ISTQB) — the baseline vocabulary; handy for getting teams from different testing backgrounds speaking the same language.
- **HTSM v6.3** (Bach) — the Heuristic Test Strategy Model; leans on state-based testing and boundary heuristics, a lighter-weight alternative to ISTQB's framing.
- **World Quality Report 2025-26** (Capgemini, 17th edition) — a useful benchmark: 43% of organizations are experimenting with GenAI in QA, 15% have it at scale. Handy for placing where your own team sits on that adoption curve.

### 7. CI Scaling Levers

As the suite and the team grow, CI wall-clock time is usually what breaks the strategy first. Reach for these levers before resorting to deleting tests:

- **Sharding** — spread the suite across N parallel runners (Playwright `--shard=1/4`, Jest `--shard`, pytest-xdist, Cypress parallelization). Speedup is roughly linear until fixed per-shard costs (install, build) start to dominate.
- **Test impact analysis** — run only the tests touched by a given diff instead of the whole suite on every PR, driven by a dependency graph (Nx affected, Vitest `--changed`, Bazel) or a coverage-to-file map. Still run the full suite on a nightly or merge gate so coverage doesn't quietly rot.
- **Caching** — cache dependencies, build artifacts, and browser binaries across runs.
- **Selective E2E on PR** — smoke-level E2E on PRs, full E2E on merge or nightly.

Measure whether these levers actually pay off rather than assuming they do. **Parallel efficiency** = summed test-run time divided by wall-clock time; aim for something close to the shard count (e.g., above 3x on 4 shards). A low number usually means fixed setup overhead or one long-pole test is eating the gains. Also track **CI-minutes-per-PR**, since parallelization can shrink wall-clock time while quietly inflating billed compute.

### 8. Entry/Exit Criteria

Spell out what has to be true before testing starts (entry) and before it's considered finished (exit), for each level.

**Unit** — Entry: code compiles, and the function has a documented input/output contract. Exit: every branch is covered, edge cases are tested, nothing is skipped, and coverage meets the target.

**Integration** — Entry: unit tests pass, dependent services are available or stubbed, test data is seeded. Exit: every service boundary is tested, error paths are validated, no flaky tests remain.

**E2E** — Entry: integration tests pass, staging is deployed, test accounts are provisioned. Exit: every critical journey passes, no open P0/P1 defects, performance is within SLA.

**Release** — Entry: every test level passes, no open CRITICAL/HIGH defects, release notes are drafted. Exit: smoke tests pass in production, monitoring shows nothing unusual across an agreed bake window (30 minutes is a reasonable starting point — tune it to your deploy cadence and alert latency), and the rollback plan has been verified.

### 9. Quality Gates & Definition of Done

Automated checkpoints that keep bad code from advancing.

**PR gate** (every PR): unit tests pass; integration tests pass; coverage doesn't drop (or meets the floor); no new lint errors; SAST scan clean (no new high/critical); bundle size within threshold; at least one reviewer approval.

**Merge gate** (merge to main): every PR-gate check passes; E2E smoke suite passes against the preview deployment; no merge conflicts; branch is current with main.

**Deploy gate** (before production): full E2E suite passes on staging; performance benchmarks in range; security scan clean; feature flags configured; rollback plan documented and tested.

**Nightly gate** (scheduled): full E2E including edge cases; visual regression; performance/load tests; accessibility scan; dependency vulnerability scan. QA lead reviews results the next morning.

Every gate needs a concrete pass/fail threshold enforced in CI — a gate someone can click past is documentation, not a gate.

### 10. Metrics & KPIs

| Metric | Definition | Target | Cadence |
|--------|-----------|--------|---------|
| **Code Coverage** | Lines/branches covered by unit + integration | >80% critical services, >60% overall | Per PR |
| **Test Pyramid Ratio** | Unit:Integration:E2E split | 70:20:10 (±10% tolerance) | Monthly |
| **Flakiness Rate** | % of runs with non-deterministic failures | <2% | Weekly |
| **Defect Escape Rate** | % of defects found in prod vs. total | <5% | Per release |
| **MTTR** | Detection to fix deployed | <4h P0, <24h P1 | Per incident |
| **CI Pipeline Duration** | Push to green/red signal | <15 min PR, <30 min full | Weekly |
| **CI Parallel Efficiency** | Summed test time ÷ wall-clock time | Approaching shard count (>3x on 4 shards) | Weekly |
| **CI-Minutes-per-PR** | Billed compute minutes per PR run | Flat or decreasing | Monthly |
| **Defect Density** | Defects per 1000 LOC | Decreasing trend | Monthly |
| **Automation Rate** | % of test cases automated | >80% for regression suite | Quarterly |
| **False Positive Rate** | % of failures that are not real bugs | <5% | Weekly |

**How to use these numbers:** watch the trend, not the raw figure — a team moving from 30% to 60% coverage is doing well even if 60% still sounds low. Anchor targets to where the team is starting from (jumping from 20% to 90% coverage in a single quarter isn't a plan, it's wishful thinking). Review the metrics with leadership every quarter and call out real progress. When something spikes — flakiness jumping suddenly, say — treat it as an infrastructure signal, not a team failing. Metrics should never become a stick. For full KPI definitions, DORA metrics, and dashboard setups, see `qa-metrics`.

### 11. Timeline & Milestones

Roll this out in phases — trying to do it all simultaneously guarantees nothing gets finished well.

**Phase 1 — Foundation (Weeks 1-4):** risk assessment across all product areas; CI pipeline gated on unit tests; baseline metrics captured (coverage, flakiness, pipeline time); unit tests written for the top 5 highest-risk areas; E2E framework chosen and configured. *Exit: CI runs unit tests on every PR, baseline metrics are documented.*

**Phase 2 — Coverage Expansion (Weeks 5-10):** integration tests across all service boundaries; E2E coverage for the top 10 critical journeys; visual regression on key pages; test data management in place; nightly runs active. *Exit: every critical path has E2E coverage, integration tests cover all APIs.*

**Phase 3 — Quality Gates (Weeks 11-14):** coverage gates on PRs (no regressions allowed); performance benchmarks wired into CI; security scanning live; monitoring dashboards up for every KPI. *Exit: all four gates (PR, merge, deploy, nightly) active and enforced.*

**Phase 4 — Optimization (Weeks 15-20):** flaky tests fixed or quarantined; CI scaling levers applied (sharding, caching, test impact analysis); synthetic monitoring live in production; first quarterly strategy review completed. *Exit: CI under 15 minutes, flakiness under 2%, first strategy revision published.*

**Ongoing:** quarterly strategy review and revision; monthly metrics review; continuous upkeep (refactoring, de-flaking, retiring dead tests).

---

## Anti-Patterns to Watch For

**Chasing 100% coverage.** Returns diminish sharply past 80% — that last 20% usually means testing trivial getters while integration gaps where real bugs hide go unaddressed. Set coverage targets per module based on risk, not a single blanket number.

**The ice cream cone (inverted pyramid).** Too much E2E relative to unit. Tell-tale signs: CI running 45+ minutes, tests breaking on every UI tweak, nobody trusting the suite's results. The fix is freezing E2E growth and pushing existing E2E tests down to lower levels.

**Treating the strategy as write-once.** A strategy written once and never revisited is worse than no strategy — it manufactures false confidence. Build in explicit review triggers: a quarterly calendar check, post-incident review, a new product area, a shift in team composition.

**Choosing tools before defining needs.** "We should use Playwright" is a tool decision dressed up as a plan. Start from what actually needs validating, then find tools that fit — the document should justify tool choices, never open with them.

**Skipping metrics means skipping accountability.** A strategy with no measurable targets is just a wish list. Every section should tie to a KPI; if a section can't be tied to a number, question whether it belongs at all.

**Keeping testing siloed.** A strategy that only lives on the QA wiki is invisible to developers. It needs to show up in PR templates, CI gates, and the Definition of Done — if developers don't encounter it daily, it effectively doesn't exist.

**Copying someone else's strategy wholesale.** Lifting another company's strategy verbatim ignores this team's risk profile, skill set, and constraints. Templates are a starting point — every section still needs tailoring.

**Automating everything on day one.** Manual exploratory testing carries real value, especially early on. Automate the regression suite and leave room for exploration to stay manual — the strategy should spell out what stays manual, and why.

---

## Verification

Before calling the document finished, check it against these criteria on the saved file:

```bash
DOC=docs/qa-strategy.md
# 1. All 13 numbered section headings present (Executive Summary → Revision History)
grep -cE '^### [0-9]+\.' "$DOC"          # expect 13
# 2. Every row in the Metrics & KPIs table has a non-empty Target cell
#    (no "| | " gaps in the target column) — visually scan the table block:
grep -nE '^\|' "$DOC" | grep -iE 'target|coverage|flak|mttr|escape'
# 3. A revision history and a named owner exist
grep -niE 'revision history|owner:' "$DOC"
```

Also check the pyramid math by hand — target unit% + integration% + E2E% should land near 100%. And if the document recommends sharding, make sure a parallel-efficiency or CI-minutes target shows up in the Metrics table; an optimization without a metric attached is just a guess.

---

## Done When

- [ ] A strategy document exists at an agreed path and `grep -cE '^### [0-9]+\.'` returns 13 (all sections Executive Summary → Revision History populated).
- [ ] Test pyramid target ratios are defined with concrete counts and a timeline to reach them; unit+integration+E2E percentages sum to ~100%.
- [ ] Entry and exit criteria are written for each level (unit, integration, E2E, release).
- [ ] Tool selection is documented with a scored, weighted rationale matrix — not just tool names.
- [ ] Quality gates are defined for all four stages (PR, merge, deploy, nightly), each with a concrete pass/fail threshold.
- [ ] Every Metrics & KPIs row has a non-empty Target and a tracking cadence.

## Related Skills

- **risk-based-testing** — run this one first; it's the deep dive on risk-assessment methodology and AI/LLM-specific failure classes, and this skill consumes its output matrix.
- **test-planning** — for a single sprint or release plan; test-strategy sits above it as the multi-quarter umbrella.
- **test-reliability** — covers flake root-cause triage, self-healing locators, and quarantine mechanics referenced in the pyramid-rebalance step.
- **qa-metrics** — full KPI definitions, DORA metrics, Test Impact Analysis, dashboards, trend analysis.
- **release-readiness** — go/no-go checklists, canary analysis, release confidence scoring.
- **ci-cd-integration** — pipeline configuration, gate implementation, and smart sharding setup.
- **shift-left-testing** — techniques for moving validation earlier in the process.
- **ai-system-testing** — brings in the eval-suite layer when the strategy covers AI/LLM features.
- **compliance-testing** — relevant when the strategy needs to serve a regulated audience (GDPR, EU AI Act, EAA, US state laws).

## Reference Files (in `references/`)

- **diagrams-and-worksheets.md** — pyramid shape diagrams, current/target state worksheets, the full 5x5 risk matrix, and the 13-section output skeleton.
- **strategy-templates.md** — four fully worked strategy documents (SaaS, e-commerce, API-first, media), plus a step-by-step pyramid analysis worksheet and a risk-matrix feature-inventory template.
</content>
