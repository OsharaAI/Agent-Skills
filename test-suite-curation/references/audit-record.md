# The Audit Record

The per-test log of "what we deleted and why" — the artifact that makes a removal
defensible to a future engineer or an auditor. It is always one row per deleted test,
never a bare count. The decision rules that feed this record live in `SKILL.md` §8.

## Column schema

| Column | What it holds |
|--------|---------------|
| `row_id` | a stable id, referenced from the quarantine skip reason (e.g. `R-0142`) |
| `test_id` | the removed test's full path/name |
| `category` | `redundant` / `obsolete` / `low-value` |
| `reason` | the specific justification — never just the word "redundant" |
| `superseded_by` | the surviving test id that now covers/replaces it (required when `category` is `redundant`) |
| `coverage_delta` | lines/branches no longer covered after the removal (before vs. after); ideally 0 net loss |
| `mutation_check` | for `redundant` rows: does the survivor kill the same mutant set? (`yes` + the run id) |
| `quarantined_at` | the SHA/date the test entered quarantine |
| `window_closed` | the date the observation window ended with no escaped defect |
| `approver` | the human who signed off (typically a CODEOWNERS reviewer) |
| `approval_sha` | the PR/commit SHA that carried out the deletion |
| `restore` | the one-line command plus quarantine location needed to bring it back |

## Worked example row

```
row_id:          R-0142
test_id:         tests/legacy/test_discount.py::test_legacy_discount_rounding
category:        redundant
reason:          subsumed by test_discount_v2; identical line+branch coverage AND survivor
                 kills the same mutant set (no unique fault detection)
superseded_by:   tests/pricing/test_discount.py::test_discount_v2
coverage_delta:  0 lines / 0 branches lost (survivor covers superset)
mutation_check:  yes — mutmut run 2026-05-12, kills(B) ⊆ kills(A)
quarantined_at:  9a1c3f7  2026-05-14
window_closed:   2026-06-09  (2 sprints, no escaped defect)
approver:        r.oyelaran (QA lead, CODEOWNERS /tests/)
approval_sha:    e72b04d
restore:         git revert e72b04d  (or un-skip in tests/quarantine/test_discount.py)
```

## Store it committed, not as a side note

The log belongs in version control, right alongside the deletions it documents, so it
persists indefinitely. A CSV works well for tooling; a Markdown table reads better for
humans:

```
docs/test-curation-log.md     # committed; reviewed via CODEOWNERS
```

If you can't fill in every field, you can't defend the deletion yet — a `redundant` row
with a blank `superseded_by`, `coverage_delta`, or `mutation_check` means the test stays
put until those gaps are closed.
