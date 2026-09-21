# Tracking & Retrospective Formats

Ready-to-use formats for keeping tabs on a plan while the sprint is underway, and for looping the results back into how the next one gets planned. `SKILL.md` covers how often to use these; this file just holds the formats themselves, verbatim.

## Daily Test Status Format

```
Test Status - [Date]

Completed today:
  ✓ E2E: checkout happy path (TC-201)
  ✓ Unit: discount stacking (TC-305, TC-306)

Blocked:
  ✗ Integration: payment API -- staging env down since 2pm
    Action: DevOps notified, ETA unknown

Found today:
  BUG-789: Discount applies twice on retry (P1, assigned to Dev)
  BUG-790: Avatar upload spinner never stops on timeout (P2, backlog)

Tomorrow:
  - E2E: checkout error paths (TC-202, TC-203)
  - Exploratory: payment flow edge cases (1h session)

Coverage: 14/22 scenarios complete (64%)
Blockers: 1 (staging environment)
Buffer consumed: 2h of 8h (25%)
```

## Sprint Retrospective Inputs

Once the sprint wraps, carry these data points forward into future planning:

```
Estimation accuracy: Estimated 40h | Actual 46h | Variance +15%
  Cause: Bug verification took 6h more than buffered

Actual vs estimated by test type (feeds Step 3 calibration):
  Unit:        est  4h | actual  4h | +0%   (estimate good)
  E2E:         est 12h | actual 14h | +17%  (page objects slower than assumed)
  Exploratory: est  6h | actual  6h | +0%
  Setup/data:  est  2h | actual  6h | +200% (was under-budgeted — raise next sprint)

Coverage: Planned 22 scenarios | Tested 20 | Skipped 2 (low risk, time pressure)
  Gap: accessibility review deferred

Bugs: Total 7 | P0: 0 | P1: 2 | P2: 3 | P3: 2 | Escaped: 0

Lessons:
  - Buffer was too low for this complexity (increase to 30%)
  - Setup/data was the worst miss — give it a real line next sprint
  - E2E write time runs high with page objects; bump to 3h/test
  - Start testing Day 2 instead of Day 3
```
