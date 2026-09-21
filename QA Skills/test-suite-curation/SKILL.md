---
name: test-suite-curation
description: >-
  Evidence-driven audit and pruning/restructuring of an entire regression test
  suite: per-test coverage fingerprinting, AST-based near-duplicate clustering,
  mining CI history for never-failing and flaky tests, decision rules for
  pruning (redundant/obsolete/low-value/keep), risk- and defect-history-driven
  tiering into smoke/core/extended, and a defensible "what we deleted and why"
  record. Because removal can't be safely undone by accident, a quarantine
  period and human sign-off are required before anything is deleted. Use when: "audit the test suite," "prune redundant tests,"
  "find duplicate tests," "which tests can we delete," "restructure into smoke/core/extended,"
  "is this test pulling its weight," "shrink the regression suite."
  Not for: Judging whether an individual test is WELL-WRITTEN (smells, assertions) — that
  is ai-qa-review. Healing one flaky test at runtime — that is test-reliability. Bulk
  selector regeneration after a UI refactor — that is selector-drift-recovery.
  Related: ai-qa-review, coverage-analysis, test-reliability, risk-based-testing, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "1.0"
  category: process
---

<objective>
Test A and Test B execute the identical set of lines. A busy engineer, seeing the overlap, deletes B — and a few weeks later a bug reaches production because B was the only one of the pair that actually verified the rounding logic. Two tests running the same code is not the same as two tests being interchangeable. This skill treats the whole regression suite as a single corpus to be analyzed at once — the kind of cross-suite redundancy check nobody performs manually — prunes it using proof rather than gut feel, and treats every deletion as an action that must be reversible in practice, backed by a quarantine window, a named human approver, and a record that would hold up under audit.
</objective>

## Quick Route

| You want to... | Go to |
|----------------|-------|
| See exactly which lines/branches belong to which test | [Fingerprinting Coverage Per Test](#1-fingerprinting-coverage-per-test) |
| Understand why "identical coverage" isn't grounds for deletion | [The Coverage-Equality Trap](#2-the-coverage-equality-trap-the-rule-that-carries-the-skill) |
| Find copy-pasted, near-identical tests | [Clustering Near-Duplicate Tests](#3-clustering-near-duplicate-tests) |
| Identify tests that never fail, or fail inconsistently | [Mining CI History](#4-mining-ci-history-for-signal) |
| Sort flagged tests into redundant / obsolete / low-value / keep | [Deciding What to Do With Each Flagged Test](#5-deciding-what-to-do-with-each-flagged-test) |
| Reorganize a flat suite into smoke/core/extended | [Tiering Into Smoke, Core, and Extended](#6-tiering-into-smoke-core-and-extended) |
| Delete flagged tests without losing anything | [Destructive Safety](#7-destructive-safety-building-in-a-grace-period) |
| Write up the "what we deleted and why" log | [Keeping an Audit Record](#8-keeping-an-audit-record) |

## Discovery Questions

Start by checking `.agents/qa-project-context.md` at the project root, and don't re-ask anything it already covers. Beyond that, establish:

- **What's the language and test runner?** pytest+coverage.py, Jest/Vitest+Istanbul, Go, JUnit — each stack has a different way to capture per-test context, and a different mutation-testing tool.
- **Does CI test-result history exist, and how far back does it go?** Without stored JUnit/Datadog/Trunk history, never-failing and flaky-test signals are simply unavailable — you're limited to coverage and clustering evidence.
- **How big is the suite, and what's its current runtime?** This determines the tiering target (a smoke suite under, say, five minutes) and whether a single run can capture per-test coverage or the run needs sharding.
- **Is there a business risk map or a list of critical paths?** Both tiering and the "keep" disposition hinge on this. If it doesn't exist yet, run `risk-based-testing` before continuing.
- **Who has authority to approve deletions, and is a CODEOWNERS file in place?** Because deletion is irreversible in effect, you need a named approver identified before this skill removes a single test.
- **How long should quarantined tests sit before permanent removal?** This is the observation window — default to 2 sprints / 2 releases if the team has no existing convention.

---

## Core Principles

1. **Matching coverage isn't the same as matching value.** Two tests can execute the exact same lines while checking entirely different things — different assertions, different inputs, different edge cases. Coverage tells you which code *ran*; it says nothing about what was *verified*. The only real evidence that one test makes another unnecessary is that it catches the same faults — which requires mutation testing, not a coverage comparison.

2. **What an agent brings is corpus-wide analysis, not authority to delete.** Fingerprinting thousands of tests, clustering near-duplicates, and cross-referencing years of CI history is work that would take a human days or weeks — an agent does it in minutes. That's the whole point of using one here. But the output is a *proposal*; approval stays with a person. Scale in analysis should never translate into scale in unreviewed deletion.

3. **Treat deletion as irreversible unless you've built in a way back.** Pointing at git history is not a recovery plan. The safe order is: quarantine (skip/xfail, or relocate to a deprecated suite), let it sit through an observation window, watch for defects slipping through, and only then delete with sign-off. The grace period — not the commit log — is what actually protects you.

4. **Not every flagged test deserves the same fate.** Redundant, obsolete, and low-value describe three distinct situations that call for three distinct actions. Funnel them all into one "delete" bucket and you'll end up cutting real coverage along with the noise.

5. **Back every decision with recorded evidence, not instinct.** Each test you remove needs its own documented row — category, the test replacing it, the coverage impact, who signed off, and how to bring it back. If any of that can't be filled in, the test isn't ready to be deleted.

---

## 1. Fingerprinting Coverage Per Test

A single merged `--cov` run only gives you per-*file* percentages — it can't tell you which *test* touched which line, so it's useless for spotting overlap between tests. What you actually need is **per-test (dynamic) coverage contexts**.

**pytest / coverage.py** — capture which test hit which line using dynamic contexts, with branch tracking enabled:

```bash
pytest --cov=src --cov-branch --cov-context=test
```

The `--cov-context=test` flag has coverage.py invoke `switch_context()` around each individual test, so every measured line gets tagged with the test that executed it. Pairing it with `--cov-branch` matters because otherwise a test that takes the `if` branch and one that takes the `else` branch on the same line would look identical — with it, they're correctly distinguished. All of this lands in the `.coverage` SQLite file, in its `context` and `line_bits`/`arc` tables.

From there, pull the per-test contexts out of the `.coverage` database and construct, for each test, the exact set of `(file, line)` and `(file, branch-arc)` pairs it touches. Two derived facts matter most:

- **Lines only one test reaches.** If exactly one test covers a line, losing that test means losing that coverage — full stop. These tests are earning their keep and should be protected from removal.
- **Subsumption.** When test A's coverage set is a strict superset of test B's, that's a *lead worth investigating* for redundancy — not proof of it (see §2).

The SQL for extracting contexts from `.coverage`, the Python for building per-test line/branch sets and computing the unique-coverage and subsumption relationships, and the JS/Vitest+Istanbul equivalent using `--coverage` are all in `references/coverage-fingerprinting.md`.

What **not** to do: don't rank tests by how many lines their file contains, and don't delete a test just because its standalone coverage percentage looks low — a single-line test might be the only thing standing guard over a critical branch.

---

## 2. The Coverage-Equality Trap (the rule that carries the skill)

This is the rule the rest of the skill hinges on. Per-test data showing **Test A and Test B cover exactly the same lines** tempts an obvious-seeming conclusion: "they're redundant, cut one." That conclusion is unsafe, for this reason:

> **Identical coverage says nothing about identical assertions, inputs, or oracles.** Two tests can walk through the exact same lines while one checks the HTTP status code and the other checks the response body — or while they're driven by completely different edge-case inputs. Same lines executed, different values asserted; same lines executed, different state verified. Coverage is a record of what ran, not of what was actually checked.

To determine whether B is *genuinely* made redundant by A — whether A's fault-detection truly covers everything B's does — run **mutation testing**:

- Python: **mutmut** (3.6.0+) or **cosmic-ray**. JS/TS: **StrykerJS** (9.x). Java/JVM: **PIT**. Rust: **cargo-mutants**.
- Mutation testing seeds deliberate faults ("mutants") into the code under test. A test "kills" a mutant when the mutated code makes it fail. If A kills everything B kills, A has genuinely absorbed B's fault-detection and B becomes a legitimate deletion candidate. If B kills even one mutant A doesn't, B is catching something A can't — **keep B**, coverage overlap notwithstanding.

**The rule in practice:** identical coverage earns *candidate* status only → mutation testing confirms or denies it → deletion is proposed only after confirmation. If assertions diverge and mutation results diverge, **both tests stay**. `references/mutation-confirmation.md` has the mutmut/Stryker configuration for scoping a mutation run to just the suspect lines, plus how to compare kill-sets.

---

## 3. Clustering Near-Duplicate Tests

The goal here is spotting copy-pasted tests without sweeping in every test that happens to share a file. **Filename grouping tells you nothing about actual similarity** — don't use it as a clustering signal. Instead, combine two signals that each carry real evidence:

1. **AST (abstract syntax tree) similarity.** Parse each test into an AST, strip out identifier names and literal values, and compare what's left structurally. A similarity metric over tokens or trees works best — Jaccard similarity over normalized token shingles, cosine similarity over AST n-grams, or tree edit distance. Comparing at the AST level filters out formatting noise and variable-renaming that would defeat plain string diffing. Line numbers should never factor into the similarity score.

2. **Coverage-profile signature.** Section 1 already gives each test a covered-line/branch set — treat that as its **execution profile**. Tests whose execution profiles line up closely *and* whose ASTs line up closely are strong candidates for being near-duplicates; either signal by itself is too weak to act on.

Group tests using a **tunable similarity threshold** — agglomerative/hierarchical clustering cut at a configurable distance, starting around 0.85 and adjusted based on how many false positives you can tolerate. The output of this step is clusters for review, never a deletion list.

**Every cluster goes to a human, no exceptions.** Don't auto-remove a whole cluster — copy-pasted tests frequently diverge in exactly the one assertion that matters. For each cluster, present its members, their pairwise similarity score, and their coverage-profile overlap, and let a person decide what (if anything) should be merged.

`references/clustering.md` covers the AST normalization approach, the shingle/Jaccard and tree-edit similarity implementations, and the agglomerative clustering code with its tunable threshold.

---

## 4. Mining CI History for Signal

Pull apart your stored **test-result history** — archived JUnit XML, or a service that already tracks this for you, such as **Datadog Test Optimization**, **Trunk Flaky Tests**, **BuildPulse**, or **CircleCI test insights**. For every test, compute a pass rate, a fail rate, and a **flip rate** (how often adjacent runs swap between pass and fail). Two distinct patterns emerge here, with two very different implications:

**Tests that have never failed** (100% pass rate across the whole window). It's tempting to delete anything that's never once failed — resist that. **A perfect pass record doesn't make a test worthless.** More often it means the test guards **stable, low-churn, low-risk code** — the kind nobody touches, so nothing ever trips the test. That's an absence of *recent defect-detection evidence*, not an absence of value. The right move is to **investigate rather than delete**: look at the churn and risk profile of the code being tested. If it's a critical path that just hasn't regressed lately, leave the test alone.

**Tests that fail inconsistently.** A single failed run does **not** make a test flaky — the actual definition is **producing different outcomes on the identical commit SHA**. Detect this by grouping test runs by commit and looking for tests that both passed and failed on the same commit (Trunk and BuildPulse support this natively). It's tempting to just delete flaky tests to quiet CI down — don't. A flaky test could be your only coverage for a real code path. The right move is to **quarantine the test and fix the underlying flake, not delete it for convenience**. Quarantining silences the noise immediately while the actual root cause gets addressed separately (see `test-reliability` for healing a single flaky test at runtime).

The JUnit-XML aggregation script, the same-SHA flake-detection query, and sample Datadog/Trunk API calls are all in `references/ci-history-mining.md`.

---

## 5. Deciding What to Do With Each Flagged Test

Resist the urge to delete anything that merely "looks redundant." These are three genuinely different states, and each one calls for a **different response**:

| Category | What defines it | What to do |
|----------|------------------|------------|
| **Redundant** | Covered by another test's coverage AND that survivor kills the same mutant set (§2) | **Merge or delete — only once the mutation-kill check has confirmed the subsumption**; route through quarantine first |
| **Obsolete** | Tests a feature that's been removed, dead code, or a path that no longer exists | **Delete outright** — but confirm the target genuinely no longer exists before removing it |
| **Low-value** | Has never failed AND is trivial (a getter, a no-op, an assertion that checks nothing meaningful) | **Quarantine and send to review** — low value still isn't zero value; get confirmation before removing |
| **Keep** | Covers something no other test does, has a track record of catching defects, or protects a high-risk path | **Keep, unconditionally** — regardless of any coverage overlap it shows |

The core discipline is matching action to category: `redundant → merge/delete-after-mutation-check`, `obsolete → delete`, `low-value → quarantine/review`, `keep → keep`. Treating every flagged test the same way is exactly how real coverage gets lost. Note that both `redundant` and `low-value` route through quarantine — neither goes straight to `rm`.

---

## 6. Tiering Into Smoke, Core, and Extended

Splitting a flat suite into tiers is not the same exercise as sorting by runtime. **Smoke isn't "the first N tests in the file," it isn't a random sample, and speed alone must never be the tiering criterion.** Two kinds of evidence should drive tiering:

1. **Business risk and critical-path coverage** — sourced from the risk map (`risk-based-testing`). Tests touching revenue, authentication, data integrity, or the major user journeys belong in smoke/core regardless of how long they take.
2. **A track record of catching defects** — tests that have demonstrably caught real bugs (found by mining CI history plus linked bug tickets for failures that preceded a fix). A test with that history earns a high tier on merit alone.

| Tier | Purpose | What lands here |
|------|---------|------------------|
| **Smoke** | Fast, runs on every push, a few minutes total, critical paths only | Highest-risk paths plus proven defect-catchers, fast enough to gate every commit |
| **Core** | Gates PRs / merges | Everything critical and high-risk, a broader set than smoke |
| **Extended** | Full runs, nightly, slower, pre-release | Everything else — exhaustive coverage, long-running cases, edge cases |

**Runtime is a valid input — but only as a tiebreaker, never the primary criterion.** Duration only decides between tests that are otherwise equally risky; among equally-risky candidates, favor the quicker one for smoke. Encode the tier as a **marker or tag** rather than moving files around — `@pytest.mark.smoke` / `@pytest.mark.extended`, a Jest/Vitest tag, or a JUnit category — so that something like `pytest -m smoke` can select a tier in place. The marker scheme and the defect-detection-history query are both detailed in `references/tiering.md`.

---

## 7. Destructive Safety: Building In a Grace Period

If asked to remove 600 tests, the naive approach is a single PR that `rm`s all 600 files. **Don't do that — never remove an entire cohort in one PR, and don't `rm` test files at all.** Because deletion is destructive, gate it behind this sequence:

1. **Quarantine before anything is deleted — never delete directly.** Mark flagged tests as skipped (`@pytest.mark.skip(reason="curation-2026-Q2, see audit row")`, `xfail`, or Jest's `.skip`), or relocate them into a `quarantine/`/`deprecated/` directory that still lives in the repository. They stop executing but remain visible and trivially restorable.
2. **Get human sign-off — no exceptions.** A named approver — enforced via **CODEOWNERS** on the test directories, or an explicit reviewer on the PR — has to approve. "It's redundant, so it doesn't need review" is not a valid shortcut: redundancy was only a *hypothesis* until §2's mutation check confirmed it.
3. **Set an observation window.** Keep the cohort quarantined and run the suite for a **grace period** — **2 sprints / 2 releases** by default — while **watching for defects that escape**: check production incidents and bug tickets to see whether anything the quarantined tests would have caught actually happened. An escaped defect during that window means the test wasn't redundant after all — restore it.
4. **Only then, delete — and do it in small batches**, each batch tied back to its audit-record row (§8).
5. **Preserve a path back.** Log the quarantine location and commit so any deleted test can be **restored in a single step**. Git history is the fallback of last resort, not the actual recovery plan.

`references/destructive-safety.md` covers the quarantine markers in detail, a sample CODEOWNERS entry for test paths, and the full escaped-defect watch checklist.

---

## 8. Keeping an Audit Record

The artifact that makes every removal defensible — to a future engineer, or to an auditor — is **not a tally of how many tests got deleted**. It's a **per-test log, one row per deleted test**, each carrying its own real justification. "We removed 600 redundant tests" by itself proves nothing and satisfies no audit.

Each row needs:

- **Test id / path** — which test was removed.
- **Category and reason** — redundant / obsolete / low-value, along with the specific justification (e.g. "subsumed; survivor kills identical mutant set").
- **Superseded by** — for a redundant removal, the id of the surviving test that now covers what this one did.
- **Coverage delta** — which lines/branches, if any, are no longer covered post-removal (before/after); ideally this is zero, as proven in §1.
- **Approval** — who approved it, the PR/commit **SHA**, and the sign-off **date**.
- **Restore path** — the quarantine location and the one-line command needed to bring it back.

Commit this as a versioned CSV or Markdown table (e.g. `docs/test-curation-log.md`) so the record travels alongside the deletions. `references/audit-record.md` has the complete column schema and a fully worked example row.

---

## Anti-Patterns

### 1. "Coverage matches, so delete one"
The costliest mistake in this whole skill. Matching line coverage only proves the lines *executed* — it says nothing about whether the assertions match. Always confirm subsumption with mutation testing (§2) before proposing removal.

### 2. Treating two green signals as sufficient on their own
A test with 18 months of unbroken passes AND identical coverage to another test *looks* like an obviously safe delete. It isn't — **neither signal alone is sufficient, and together they still aren't proof**. A test that's **never failed usually means the code is stable, not that the test is worthless** — low churn and low risk, not redundancy. It might still hold a **unique oracle** — a distinct assertion, input, or edge case that no other test checks. The question to ask is: does the *other* test actually kill/catch/assert what this one does? Only once mutation testing answers that should you move to quarantine and observation, then deletion. Neither the never-failed signal nor the coverage-match signal is sufficient by itself (see §2 and §7).

### 3. A single merged coverage run without per-test context
Running `--cov=src` with no context setting only produces per-file percentages and can't reveal per-test overlap at all. Use `--cov-context=test` and read contexts back out of the `.coverage` database per test.

### 4. Clustering near-duplicates by filename
Being in the same file proves nothing about similarity. Cluster instead on AST similarity plus coverage-profile signature at a tunable threshold (§3), and always route the resulting clusters to a human — never delete a cluster automatically.

### 5. Deleting tests just because they're never-failing or flaky
Never-failing calls for investigation (it usually points to low-churn code), not deletion. Flaky calls for quarantine-and-fix, not deletion for CI hygiene. Remember: flakiness means divergent outcomes on the same commit SHA, not a single bad run.

### 6. Applying one disposition to every flagged test
Redundant, obsolete, and low-value each require a different action (§5). Treating them as one "delete" bucket erases real coverage along with the noise.

### 7. Tiering purely by speed (or by file order)
Smoke status comes from risk plus a defect-detection track record — not from being the fastest tests, and not from being first in the file. Runtime is only ever a tiebreaker (§6).

### 8. One giant deletion PR
Removing 600 test files in a single PR, with no quarantine, no sign-off, and no observation window, is the failure mode this whole skill exists to prevent. Always go quarantine → sign-off → observation → small-batch deletion (§7).

### 9. "It's already in git history, just delete it"
Git history isn't a monitoring system — nobody is actively watching for the specific defect a deleted test would have caught. The actual safety net is the quarantine grace period combined with active escaped-defect monitoring.

---

## Verification

Before anyone deletes anything, confirm the audit actually holds up — cheapest checks first:

- **Per-test contexts were actually captured, not a flat summary.** `sqlite3 .coverage "SELECT COUNT(*) FROM context WHERE context != '';"` should return a count close to your total test count, not 0 or 1. Zero means `--cov-context=test` never ran.
- **No deletion is resting on coverage equality alone.** Every `redundant` row in the audit log has its `mutation_check` column filled in (`yes` plus a run id). `grep -c 'redundant' docs/test-curation-log.md` should equal the number of rows with a non-blank `mutation_check`.
- **Quarantine landed in the repo before any removal did.** `git log --diff-filter=D --name-only -- tests/ | grep test_` shows no deleted test files in the quarantine PR; flagged tests are skipped/xfail or sitting under `tests/quarantine/`, and still collectible (`pytest --collect-only -m skip` or equivalent lists them).
- **Tiers actually select the right tests.** `pytest -m smoke --collect-only` returns only the risk/defect-catcher cohort and stays under the smoke time budget; `pytest -m "smoke or core or extended" --collect-only` accounts for every single test (nothing untagged).
- **The audit record has no gaps.** No `redundant` row has a blank `superseded_by`, `coverage_delta`, or `mutation_check`; every removal claiming zero net coverage loss shows `coverage_delta` as `0 lines / 0 branches`.

---

## Done When

- A per-test coverage fingerprint exists for the whole suite (via `--cov-context=test`/`--cov-branch`, or the Istanbul per-test equivalent), with uniquely-covered lines computed per test.
- Every "redundant" candidate has an attached mutation-testing result proving the survivor kills the same mutant set — nothing was proposed for deletion on coverage equality alone.
- Near-duplicate clusters came from AST plus coverage-profile similarity at a stated threshold and were routed to human review — no cluster was auto-deleted.
- CI history was mined for never-failing tests (disposition: investigate) and same-SHA flaky tests (disposition: quarantine/fix) — neither group was deleted based on those signals alone.
- Every flagged test carries exactly one label — redundant, obsolete, low-value, or keep — with the matching disposition applied.
- Tiers (smoke/core/extended) are assigned via markers/tags built on risk and defect-detection history; a command like `pytest -m smoke` correctly selects a tier.
- No test was removed without: serving its full quarantine period, a named approver / CODEOWNERS sign-off on record, and a completed observation window with no escaped defect.
- A committed, per-test audit record exists with one row per deletion, covering category, superseded-by, coverage delta, approver/SHA/date, and restore path.

---

## Related Skills

- **ai-qa-review** — Assesses whether a single test is *well-constructed* (smells, weak assertions, testability). This skill answers whether a test should *exist at all*; ai-qa-review answers whether an existing one is good. Run it on the survivors once curation is done.
- **coverage-analysis** — Owns coverage thresholds, gap analysis, and project-level mutation-testing setup. This skill consumes per-test coverage data to make redundancy calls; go to coverage-analysis for ratchets and CI gating.
- **test-reliability** — Handles runtime self-healing and quarantine for a *single* flaky test as it happens. This skill *discovers* the flaky cohort across CI history; test-reliability *repairs* them individually.
- **risk-based-testing** — Builds the risk matrix that this skill's "keep" disposition and its tiering both depend on. Run it first if no risk map already exists.
- **qa-project-context** — The shared dependency underneath everything here: stack, runner, risk map, and ownership.

## Reference Files (in `references/`)

- **coverage-fingerprinting.md** — Queries against `.coverage`'s SQLite context tables, building per-test line/branch sets, computing unique-coverage and subsumption, and the JS/Istanbul equivalent.
- **mutation-confirmation.md** — mutmut/cosmic-ray/StrykerJS configuration scoped to suspect lines, plus the kill-set comparison that confirms subsumption.
- **clustering.md** — AST normalization, Jaccard/cosine/tree-edit similarity, and agglomerative clustering with a tunable threshold.
- **ci-history-mining.md** — JUnit-XML aggregation, the same-SHA flake-detection query, and Datadog/Trunk API examples.
- **tiering.md** — The marker/tag scheme for smoke/core/extended plus the defect-detection-history query.
- **destructive-safety.md** — Quarantine markers, CODEOWNERS for test paths, and the escaped-defect watch checklist.
- **audit-record.md** — The full column schema for the deletion log plus a worked example row.
