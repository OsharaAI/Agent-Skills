# Diagrams, Worksheets & Output Skeleton

This file is the template library that backs the test-strategy skill — ASCII diagrams and blank worksheets meant to be copied straight into the strategy document and filled in. The reasoning behind each one, and how to use it, is explained in `SKILL.md`; keeping the templates here is what lets that file stay lean.

## The Four Test Pyramid Shapes

What a test suite's shape looks like, and what each shape tells you.

```
HEALTHY PYRAMID         ICE CREAM CONE         DIAMOND              HOURGLASS

    /  E2E  \           +-----------+                                 /  E2E  \
   /  ~5-10% \          | E2E ~60%  |            / Int \             / ~30%    \
  /           \         |           |           / ~50%  \           +----------+
 / Integration \        +-----------+          /         \          | Int ~10% |
/   ~15-20%     \       | Int ~20%  |         +-----------+         +----------+
+---------------+       +-----------+         | Unit ~30% |        /  Unit     \
|   Unit ~70%   |       | Unit ~20% |         +-----------+       /   ~60%      \
+---------------+       +-----------+                             +--------------+

Fast feedback,          Slow, brittle,        Heavy on mocks,      Missing middle
high confidence,        expensive to run,     integration gaps      layer, gaps in
cheap to maintain       hard to maintain      still possible        service boundaries
```

## Worksheet: Where the Suite Stands Today

Pull these numbers from the codebase and fill them in:

```
Current Test Distribution:
  Unit tests:        _____ count  →  _____ %
  Integration tests: _____ count  →  _____ %
  E2E tests:         _____ count  →  _____ %
  Manual test cases:  _____ count  (not in pyramid, but track)

Current Shape: [ ] Pyramid  [ ] Ice Cream Cone  [ ] Diamond  [ ] Hourglass  [ ] No Shape

CI Pipeline Duration: _____ minutes
Flaky Test Rate:      _____ %
Test Suite Pass Rate: _____ %
```

## Worksheet: Where It Should End Up

Set the target ratios and the timeline for reaching them:

```
Target Test Distribution:
  Unit:        70-80%  → target count: _____
  Integration: 15-20%  → target count: _____
  E2E:          5-10%  → target count: _____

Target CI Duration: < _____ minutes
Target Flaky Rate:  < _____ %
```

## The 5x5 Risk Matrix

Multiply Impact by Likelihood to get the score, then use the resulting label (LOW/MED/HIGH/CRIT) to look up the matching testing action in the Risk-to-Testing Action Map in `SKILL.md`.

```
LIKELIHOOD →     Rare      Unlikely    Possible    Likely    Almost Certain
IMPACT ↓          1           2           3          4            5

Catastrophic (5)  5-MED      10-HIGH    15-CRIT    20-CRIT      25-CRIT
Major (4)         4-LOW       8-MED     12-HIGH    16-CRIT      20-CRIT
Moderate (3)      3-LOW       6-MED      9-MED     12-HIGH      15-CRIT
Minor (2)         2-LOW       4-LOW      6-MED      8-MED       10-HIGH
Negligible (1)    1-LOW       2-LOW      3-LOW      4-LOW        5-MED
```

## The Output Skeleton

Every finished strategy document should follow this same section structure:

```markdown
# QA Strategy: [Product Name]
## Version [X.Y] | Last Updated: [Date] | Owner: [Name]

### 1. Executive Summary (1 paragraph)
### 2. Scope & Objectives
### 3. Test Levels & Types (table)
### 4. Test Pyramid Analysis (current → target)
### 5. Risk Assessment (matrix + feature mapping)
### 6. Environment Strategy (table)
### 7. Tool Selection (decisions + rationale)
### 8. Entry/Exit Criteria (per level)
### 9. Quality Gates (per stage)
### 10. Metrics & KPIs (table with targets)
### 11. Timeline & Milestones (phased)
### 12. Risks to the Strategy Itself
### 13. Revision History
```
