# Destructive Safety: Building In a Grace Period

Quarantine markers, CODEOWNERS-enforced sign-off, and the escaped-defect watch — the
full gating sequence lives in `SKILL.md` §7. Test files should never be `rm`'d directly,
and a cohort of flagged tests should never be removed in one PR.

## Step 1 — Quarantine instead of deleting

Mark the flagged tests as skipped (they stop executing but stay visible and instantly
restorable), or relocate them to a `quarantine/` directory that's still part of the repo.

```python
# pytest: skip with a reason tying back to the audit row
import pytest

@pytest.mark.skip(reason="curation-2026-Q2 redundant; audit row R-0142; restore: git revert <sha>")
def test_legacy_discount_rounding(): ...

# or xfail if it should fail until removed
@pytest.mark.xfail(reason="curation-2026-Q2 obsolete; feature removed")
def test_removed_feature(): ...
```

```ts
// Jest / Vitest
test.skip('legacy discount rounding [curation-2026-Q2, audit R-0142]', () => { /* ... */ })
```

Or move the file without removing it:

```bash
git mv tests/legacy/test_discount.py tests/quarantine/test_discount.py
```

## Step 2 — Require human sign-off via CODEOWNERS

A named approver must sign off on the quarantine/removal PR. Put the relevant test paths
under CODEOWNERS so this review is enforced automatically rather than relying on habit.

```
# .github/CODEOWNERS
/tests/                @qa-leads
/tests/quarantine/     @qa-leads @eng-managers
docs/test-curation-log.md  @qa-leads
```

The idea that "redundant tests don't need review" doesn't hold — redundancy was only a
hypothesis until the mutation check confirmed it, and even confirmed cases still need a
human to actually approve the removal.

## Step 3 — Run the observation window and watch for escaped defects

With the cohort quarantined (skipped), keep running the suite for a grace period —
**2 sprints / 2 releases by default** — while watching for defects slipping through.

Escaped-defect watch checklist:

- [ ] Cross-check production incidents from the window against what the quarantined
      tests used to cover (pull their coverage fingerprint from §1).
- [ ] Review new bug tickets: would any quarantined test have caught this?
- [ ] Review hotfix commits: did any of them touch lines that only a quarantined test
      used to cover?
- [ ] If the answer to any of the above is yes: the test was NOT redundant —
      **restore it** and update its audit row accordingly.

```bash
# restore in one step
git revert <quarantine-sha>          # if quarantined via a single PR
# or un-skip / git mv back from tests/quarantine/
```

## Step 4 — Delete in small batches, once the window closes clean

Only after the observation window ends with zero escaped defects should deletion happen
— and even then, in small batches rather than a single 600-file PR, with each batch's PR
linked to its corresponding audit rows (`audit-record.md`). Retain the quarantine commit
so every test stays restorable — git history is the last resort, not the actual plan.
