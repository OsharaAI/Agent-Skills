---
name: risk-based-testing
description: >-
  Build a scored risk matrix or heatmap that ranks what could break by business
  impact multiplied by likelihood, drill into failure-mode analysis for the
  highest-scoring items, and align test coverage to each risk tier. Covers
  stakeholder interview techniques and an ongoing reassessment cadence. Run this
  before test-strategy or test-planning. Trigger phrases: "risk
  assessment," "risk matrix," "risk heatmap," "what could break," "critical paths,"
  "failure modes," "where to focus testing."
  Skip this for multi-quarter QA direction — that's test-strategy. Skip this for
  a single sprint or release test plan — that's test-planning. Skip this for
  hands-on, session-based bug hunting — that's exploratory-testing.
  See also: test-strategy, test-planning, release-readiness, qa-metrics.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: strategy
---

<objective>
Spreading test effort evenly across every feature is a losing trade: pushing a settings page to 90% coverage draws attention away from checkout, where a defect actually costs money. This skill exists to surface risk deliberately, turn it into a number (impact multiplied by likelihood), translate that number into how much testing each area deserves, and keep the whole picture honest as the product keeps changing underneath it. The output is a scored risk matrix that feeds directly into `test-strategy` and `test-planning`.
</objective>

## Quick Route

| Situation | Start at |
|-----------|----------|
| Greenfield product, no risk model exists yet | Phase 1 (Identification) → work through all 6 phases |
| Reassessing right after an incident | Phase 6 (Reassessment triggers), then re-score the affected items back in Phase 2 |
| A new AI/LLM feature needs assessment | Phase 3 (AI/LLM failure classes), then score each class in Phase 2 |
| Refreshing an existing matrix mid-sprint | Phases 4–5 (Heatmap + Coverage alignment) for the changed features only |
| Checking whether an old heatmap still holds up | Phase 6 signals + the "Risk Theater" anti-pattern |

---

## Questions to Ask Before Scoring Anything

Check for `.agents/qa-project-context.md` first. If it already exists, treat it as your starting point and don't re-ask what it already answers. For everything else, pull answers from engineering, product, and operations.

### Where the revenue lives
- Which flows generate revenue directly — checkout, subscriptions, billing, plan upgrades?
- How much does each of those flows cost per hour of downtime?
- Are any of them time-boxed — flash sales, market-hours trading windows, payroll cutoffs?
- Do any carry contractual SLAs with financial penalties attached?

### What's broken recently
- Across the last three releases, what failed, and what made it to production?
- What actually caused each failure — a code bug, a bad config push, a third-party outage, a data migration gone wrong?
- How big was each incident's blast radius — users affected, revenue lost, reputational damage?
- Were there close calls caught late in the cycle that almost got through?

### Where the codebase is fragile
- Which areas of the code churn the most? High churn tends to track with high risk.
- Where is coverage weakest today?
- Where does the business logic get tangled — the most branching, the most conditionals?
- Is there code whose original authors have since left the team?

### What you depend on externally
- Which outside services does the product rely on — payment processors, identity providers, CDNs, third-party APIs?
- How reliable has each one actually been, historically?
- Does the product degrade gracefully when one of them goes down, or does it just break?
- Are there single points of failure with nothing behind them?

### Compliance and sensitive data
- What regulations are in play — GDPR, PCI-DSS, HIPAA, SOC2, SOX, the EU AI Act?
- What's the most sensitive data in the system — PII, financial records, health data, credentials?
- What's the legal fallout if a breach or a compliance failure happens?
- Do any audits require specific documented testing evidence?

---

## Core Principles

1. **Features aren't interchangeable.** A checkout bug that blocks purchases sits in a different universe from a crooked icon on a settings screen. Treating them the same wastes effort on the low-stakes area while the high-stakes one stays under-tested.
2. **Risk is impact times probability, not a hunch.** Score how bad a failure would be, score how likely it is, independently and on a consistent scale, then multiply the two together. That product is the risk score — not a feeling about which features seem important.
3. **A risk model has to keep moving.** Build it once and let it sit, and it becomes a source of false confidence. The product changes, dependencies change, the team changes, and incidents happen — the model needs to track all of that. Bake reassessment into your regular cadence rather than treating it as optional.
4. **A near-miss is still evidence.** Catching a catastrophic bug in staging isn't a win to celebrate — it's proof the model missed how risky that area actually is. Log near-misses with the same seriousness as production incidents.
5. **Let risk decide coverage, not the reverse.** Don't open with "80% coverage everywhere" as the goal. Open with "where would a failure actually hurt," and let that answer set the coverage target per module.

---

## Workflow

```
1. Identify → 2. Classify → 3. Analyze → 4. Heatmap → 5. Coverage → 6. Reassess → (repeat)
                                 ↑
                       score ≥ 10 only; skip to 4 if nothing clears the threshold
```

### Phase 1: Find the Risks

Cast a wide net and list everything that could plausibly go wrong. Good sources:

- **Talk to people.** Product managers see the business-critical flows. Engineers see the fragile code. Support hears the recurring complaints.
- **Read the incident history.** What failed before tends to predict what fails next — go back through the last 6–12 months of post-mortems.
- **Map the dependencies.** Every external service, database, message queue, and third-party API is a risk vector waiting to be listed.
- **Look at churn.** Code that changes often tends to break more often too. Use the ranked churn command from Phase 6 to find these areas; save `git log --stat <file>` for inspecting one specific suspect commit-by-commit, not for building the ranking.
- **Look at the architecture.** Shared databases, single points of failure, synchronous call chains, and tightly coupled modules are all things that widen blast radius.

**HTSM v6.3** (Bach's Heuristic Test Strategy Model) is a useful lens for this phase — its state-based and boundary heuristics catch risks that a plain feature list won't. Download: https://www.satisfice.com/download/heuristic-test-strategy-model

You should come out of this phase with a raw list: each item names something that could fail and describes what happens if it does.

### Phase 2: Score Each Risk

Every item gets scored on two independent axes.

**Impact — how bad is it if this happens:**

| Score | Level | What it means | Sample cases |
|-------|-------|-----------|----------|
| 5 | Catastrophic | Money is lost, data is breached, legal exposure, user safety at stake | Payments stop processing; PII gets exposed |
| 4 | Major | A large user segment is hit, an SLA is broken, a major feature stops working | Login fails for a segment of users; data gets corrupted |
| 3 | Moderate | A workflow is disrupted but a workaround exists | Search returns bad results; exports fail |
| 2 | Minor | Cosmetic or a small UX papercut | Misaligned element; a slow but non-critical page |
| 1 | Negligible | No user-facing impact, internal only | Wrong tooltip text in an admin panel; a log formatting glitch |

**Probability — how likely is it to happen:**

| Score | Level | What it means | What points to it |
|-------|-------|-----------|-----------|
| 5 | Frequent | Expect it in most releases | Heavy churn, no tests, tangled logic |
| 4 | Likely | Probably surfaces within a quarter | Recent changes, patchy coverage, known tech debt |
| 3 | Possible | It's happened before and could again | Moderate complexity, partial coverage |
| 2 | Unlikely | Possible but not expected | Stable, well-covered, simple |
| 1 | Rare | Needs unusual circumstances to trigger | Thoroughly tested, rarely touched, simple |

Multiply the two scores to get the composite. That composite drives priority — impact alone doesn't. For example, high code churn pushes probability up regardless of how bad the impact is: a merely Moderate-impact feature (3) under heavy churn scores a Probability of 5, giving a **risk score of 15 — landing in the CRITICAL zone** even though the impact alone looked unremarkable.

### Phase 3: Break Down How Each Top Item Fails

Every item scoring 10 or above gets a full failure-mode writeup:

```
Feature/Component: [name]
Risk Score: [impact × probability]

Failure Mode 1: [what specifically can fail]
  Trigger:            [what causes this failure]
  Blast Radius:       [users affected, systems affected, data affected]
  Detection Method:   [how would we know -- monitoring, user report, test]
  Current Mitigation: [existing tests, monitoring, feature flags, fallbacks]
  Gap:                [what is missing from current mitigation]

Failure Mode 2: ...
```

**Worked example — checkout on an e-commerce site (Risk Score 20 = Impact 5 × Probability 4):**

```
Failure Mode 1: Payment succeeds, but no order record gets created
  Trigger:            A race between the payment callback and the order-creation write
  Blast Radius:       Affects individual users; money is charged with no order confirmation to show for it
  Detection Method:   Hourly payment reconciliation job, or a user complaint
  Current Mitigation: Idempotency key on the payment call, retry logic on the order write
  Gap:                No automated test exercises the race itself; reconciliation only runs hourly

Failure Mode 2: A discount code applies the wrong amount
  Trigger:            A percentage discount stacked on an item that's already discounted
  Blast Radius:       Every user with stacked discounts; direct revenue leakage
  Detection Method:   Margin-monitoring alert (fires past a 5% deviation)
  Current Mitigation: Unit tests cover single, non-stacked discounts
  Gap:                Nothing tests stacked discounts or rounding edge cases

Failure Mode 3: Inventory isn't reserved during checkout
  Trigger:            Two customers buying the last unit of stock at the same time
  Blast Radius:       Overselling, fulfillment failures, damaged customer trust
  Detection Method:   Fulfillment staff notice it while packing orders
  Current Mitigation: A database-level stock check runs at order creation
  Gap:                No load test simulates concurrent purchases of a last-stock item
```

#### AI/LLM failure classes

For AI/LLM-powered features, run each of these CT-GenAI classes through the same Impact/Probability scoring as any other risk item. What mitigates them isn't a single manual test pass — it's a standing, automated **eval suite**.

> **AI/LLM-specific failure classes** (per ISTQB CT-GenAI v1.1, effective 27 April 2026):
> - **Hallucination / reasoning error** — Impact ranges moderate to major; Probability runs high unless there's explicit prompt-eval coverage. Catch it with golden-dataset evals and fact-check assertions (see `ai-system-testing`).
> - **Bias** — Catastrophic impact in regulated domains like finance, healthcare, and hiring. Probability depends on the dataset. Catch it with counterfactual evals and demographic-parity checks.
> - **Prompt injection / jailbreak** — Major impact (data exfiltration, prompt extraction). Probability is high for anything customer-facing. Catch it with Garak, PyRIT, or Promptfoo redteam runs.
> - **Privacy leak** — Catastrophic under GDPR/CCPA/the EU AI Act. Probability depends on the dataset. Catch it by scanning training data and prompts for PII.
> - **AI Act / regulatory non-compliance** — Catastrophic impact (fines, outright bans). High probability for anything facing EU users. See `compliance-testing`.
>
> Tooling note as of mid-2026: PyRIT's home is now **microsoft/PyRIT** — the old Azure-hosted repo was archived in March 2026, so don't point new redteam work at that legacy path. Promptfoo was acquired by OpenAI in March 2026 but is still MIT-licensed. Garak hasn't changed.

**Reference frameworks:** **CT-GenAI v1.1** (ISTQB, effective 27 April 2026) is the source for the AI/LLM classes above. **WQR 2025-26** (Capgemini, 17th edition, Nov 2025) supplies the adoption-stage framing useful for planning AI risk work.

### Phase 4: Plot the Heatmap

Lay every scored item out on a 5×5 grid so priorities are visible at a glance and coverage decisions have a clear basis.

```
                    PROBABILITY
                    Rare(1)   Unlikely(2)  Possible(3)  Likely(4)   Frequent(5)
                   +----------+-----------+-----------+----------+-----------+
  Catastrophic(5)  |  5  MED  | 10  HIGH  | 15  CRIT  | 20 CRIT  | 25  CRIT  |
                   +----------+-----------+-----------+----------+-----------+
  Major(4)         |  4  LOW  |  8  MED   | 12  HIGH  | 16 CRIT  | 20  CRIT  |
I                  +----------+-----------+-----------+----------+-----------+
M  Moderate(3)     |  3  LOW  |  6  MED   |  9  MED   | 12 HIGH  | 15  CRIT  |
P                  +----------+-----------+-----------+----------+-----------+
A  Minor(2)        |  2  LOW  |  4  LOW   |  6  MED   |  8 MED   | 10  HIGH  |
C                  +----------+-----------+-----------+----------+-----------+
T  Negligible(1)   |  1  LOW  |  2  LOW   |  3  LOW   |  4 LOW   |  5  MED   |
                   +----------+-----------+-----------+----------+-----------+
```

**What each zone means for testing:**

| Zone | Score Range | Color | Testing Action |
|------|------------|-------|---------------|
| CRITICAL | 15-25 | Red | Full automation, live production monitoring, load testing, and manual exploratory passes |
| HIGH | 10-14 | Orange | Full automation plus periodic manual review |
| MEDIUM | 5-9 | Yellow | Automate the happy path and the key error cases |
| LOW | 1-4 | Green | Manual check at release time, or skip it altogether |

A populated example, showing roughly where named risks land:

```
                    Rare(1)   Unlikely(2)  Possible(3)  Likely(4)   Frequent(5)
  Catastrophic(5)             Auth bypass   Payments fail  Checkout crash
  Major(4)                                  Data export    Search broken  User upload
  Moderate(3)                  Report fmt    Email deliver  Profile edit
  Minor(2)         Footer link Tooltip text  Theme switch
  Negligible(1)    Admin label
```

### Phase 5: Match Coverage to the Heatmap

Every zone comes with a specific testing recipe — density should follow risk directly.

| Risk Zone | Unit Tests | Integration Tests | E2E Tests | Manual Testing | Monitoring |
|-----------|-----------|------------------|-----------|---------------|-----------|
| CRITICAL (15-25) | 90%+ branch coverage | Every service boundary | Full journey plus error paths | Exploratory testing every release | Real-time alerts, synthetic checks |
| HIGH (10-14) | 80%+ branch coverage | Key interactions | Happy path + top 3 error paths | Spot-checked | Dashboard, reviewed daily |
| MEDIUM (5-9) | 70%+ branch coverage | Happy path only | Happy path only | On major changes only | Reviewed weekly |
| LOW (1-4) | Basic happy path | Not required | Not required | On initial build only | Not required |

#### Gap Analysis Worksheet

Use this to line up what coverage exists against what the risk zone demands:

```
Feature: [name]
Risk Zone: [CRITICAL / HIGH / MEDIUM / LOW]      Risk Score: [number]

Required Coverage:
  Unit:        [target %]     Current: [actual %]     Gap: [delta]
  Integration: [required?]    Current: [exists? y/n]  Gap: [missing scenarios]
  E2E:         [required?]    Current: [exists? y/n]  Gap: [missing flows]
  Monitoring:  [required?]    Current: [exists? y/n]  Gap: [missing alerts]

Priority: [P0 / P1 / P2 / P3]
Estimated Effort: [hours / story points]
Owner: [name]                Target Sprint: [sprint number]
```

A churn spike is often what forces this worksheet open: say a module changed 47 times over 3 months (pushing Probability to 5), and it's sitting at only 40% branch coverage with no integration tests — that combination pushes it up a zone (MEDIUM to HIGH, for instance), and the new coverage bar is justified by the churn data, not chosen arbitrarily.

Four fully worked, fully scored examples (checkout, a media platform, a third-party API, and auth) live in `references/examples.md`, tracing the path from risk score all the way to the coverage that gets prescribed.

### Phase 6: Keep Watching and Reassess

A risk model isn't a deliverable you file away — it needs to stay part of the team's rhythm.

**When to reassess:**
- Within 48 hours of any production incident: re-score whatever was affected, check dependency health, and rerun the Phase-5 gap analysis to surface any coverage hole the incident just exposed
- Whenever a new feature area gets introduced
- Whenever a critical dependency changes (an API version bump, a provider swap)
- Whenever the team's composition shifts significantly
- At minimum, once a quarter, whether or not something triggered it

**Signals worth tracking continuously:**
- **Churn by module** (ranked by frequency):
  ```bash
  git log --since="3 months ago" --name-only --format= | grep -v '^$' | sort | uniq -c | sort -rn | head -20
  ```
- **Where defects cluster:** which modules keep generating bugs? Track this through issue labels.
- **How often near-misses happen:** how frequently does staging or QA catch something that would otherwise have reached production?
- **Health of dependencies:** keep an eye on the status pages and uptime of critical third-party services.
- **Coverage direction:** is coverage in the high-risk areas trending up or down?

---

## Anti-Patterns

### Flat coverage across the board
Setting one coverage number and applying it everywhere regardless of risk. A 90% bar on a settings page pulls resources away from payments or auth, where they'd actually matter. Let the risk model decide the allocation instead.

### Scoring once and walking away
Building the matrix during planning and then never touching it again. The product, the team, and the dependencies keep moving, so a six-month-old model goes stale the moment any of those shift — and it stops reflecting reality well before anyone notices. Put reassessment on the calendar and actually run it.

### Writing off near-misses
Treating a bug caught in staging as nothing but good news. If manual testing was the only thing standing between that bug and production, the automated safety net has a hole in it. Log the near-miss and update the model to reflect what it revealed.

### Risk theater
Filling in matrices and drawing heatmaps without ever changing where testing effort actually goes. A heatmap that isn't reflected in coverage was a wasted exercise — check the alignment every quarter. Bolton's "Quality Engineering Is Not Testing" (2026-04-20) calls out exactly this pattern — producing a heatmap and declaring quality engineering "done." Reference: https://developsense.com/blog/2026/04/quality-engineering-is-not-testing

### Over-indexing on old incidents
Weighting past failures too heavily while ignoring new risk vectors. A module that broke two years ago and has since been rewritten might not deserve its old risk score anymore, while a brand-new third-party integration carries risk nobody's assessed yet.

### Mixing up severity and priority
Severity measures how bad a failure would be; priority measures how urgently it needs testing. A catastrophic-but-vanishingly-rare failure (the data center gets destroyed) can rank below a moderate-but-frequent one (search is occasionally wrong) — use the composite score to decide, not impact alone.

---

## Verification

Confirm the matrix is real and the coverage actually matches it — check the cheapest things first:

- **The artifact exists and is checked in:** `git ls-files | grep -E 'risk-matrix|qa-project-context'` should return a file. A draft sitting only on someone's laptop doesn't count as a risk model.
- **Nothing in scope is unscored:** grep the artifact for rows missing an impact or probability number. A named feature with no score attached is a gap, not evidence of low risk.
- **The top-scoring items have full failure-mode writeups:** anything scoring 10 or above needs all five fields present — Trigger, Blast Radius, Detection Method, Current Mitigation, Gap. A blank Gap line means the analysis wasn't actually done.
- **Coverage actually matches the heatmap:** for every CRITICAL or HIGH feature, verify the Phase-5 prescribed coverage genuinely exists — run the suite and check the per-module numbers against the target. A CRITICAL label next to 40% branch coverage and no E2E tests is Risk Theater.
- **The churn signal is fresh:** rerun the Phase-6 churn command. Any module in the top 10 that isn't scored at Probability 4 or higher signals a model that's drifted out of sync with reality.

## Done When

- A scored risk matrix exists as a tracked artifact (either the risk section of `.agents/qa-project-context.md` or a committed `risk-matrix.md`), and every in-scope feature has both an impact score (1-5) and a probability score (1-5)
- Each feature's composite score places it in a named zone — CRITICAL, HIGH, MEDIUM, or LOW — with a testing action assigned to match
- Every feature scoring 10 or higher has a completed failure-mode analysis documenting trigger, blast radius, detection method, current mitigation, and gap
- Coverage requirements per zone have been checked against current coverage, and each identified gap carries a Priority (P0-P3), an Owner, and a Target Sprint
- Reassessment triggers and cadence are written into the same artifact (quarterly at minimum, plus within 48 hours of any production incident)

## Reference Files (in `references/`)

- **examples.md** — Four fully-scored worked examples (checkout, media platform, third-party API, auth) tracing risk profile → failure modes → prescribed coverage.

## Related Skills

- **test-strategy** — The multi-quarter QA direction this matrix feeds into; risk assessment is one input among several to that broader strategy.
- **test-planning** — Sprint- and release-level planning draws on risk priorities to decide what gets tested this iteration.
- **release-readiness** — Go/no-go calls reference the heatmap to confirm the critical areas are actually covered.
- **qa-metrics** — Defect escape rate and defect clustering data flow back in to keep the risk model current.
- **ai-system-testing** — Builds the eval suites that mitigate the AI/LLM failure classes described in Phase 3.
- **qa-project-context** — Holds the critical flows, fragile areas, and dependencies this skill draws on, and is where the resulting risk matrix gets written back.
</content>
