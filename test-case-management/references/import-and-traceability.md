# CSV Import, Organization, Traceability, Automation Graduation

## TestRail CSV import — column-to-field mapping

A CSV imports cleanly into TestRail when its header row maps onto TestRail's importer fields —
that's what lets the import wizard auto-match columns and skip manual remapping. Don't emit
free-form prose, a single `Description` column mixing steps and expected results together, or
JSON when what was asked for is CSV.

Key importer fields and the columns that map to them:

| TestRail field | CSV header to use |
|----------------|-------------------|
| Title | `Title` |
| Section / folder placement | `Section` or `Section Hierarchy` (e.g. `Authentication > Password Reset`) |
| Separated steps | `Steps (Separated)` (one row per step, or `\n`-joined) |
| Per-step expected | `Expected Result` |
| Preconditions | `Preconditions` |
| Priority | `Priority` |
| Type | `Type` |
| References | `References` |

For separated steps, TestRail's importer either reads several rows sharing the same `Title`
(each row representing one step plus its expected result), or a single row whose steps are
newline-delimited and mapped in the wizard to the "Steps (Separated)" template field.

Here's an example CSV covering three cases under a "Password Reset" section:

```csv
Title,Section Hierarchy,Priority,Type,Preconditions,Steps (Separated),Expected Result
Password reset — valid email sends a link,Authentication > Password Reset,High,Functional,"A user account exists for reset@example.com","Open /forgot-password and enter reset@example.com, then click Send reset link","A confirmation reads ""Check your email""; a reset email arrives within 2 minutes"
Password reset — unknown email shows neutral message,Authentication > Password Reset,Medium,Functional,"No account exists for ghost@example.com","Open /forgot-password and enter ghost@example.com, then click Send reset link","The same neutral confirmation is shown; no email is sent (no user enumeration)"
Password reset — expired link is rejected,Authentication > Password Reset,High,Negative,"A reset link older than its 60-minute TTL exists","Open the expired reset link and submit a new password","An error reads ""This reset link has expired""; the password is unchanged"
```

In the import wizard, map the columns to TestRail fields and pick the "Test Case (Steps)"
template so `Steps (Separated)` and `Expected Result` populate the separated-step grid. Quote
any cell that contains commas, and double up `"` to escape literal quotes.

---

## Suite & section organization

TestRail offers two repository modes — choose one deliberately:

| Mode | When | Trade-off |
|------|------|-----------|
| **Single Repository (single suite)** | Most teams; one navigable tree of sections | Simplest; everything in one suite, organized by sections/subsections |
| **Single Repository + baselines** | Need branching/baselines per release | Adds baseline overhead |
| **Multiple Test Suites** | Genuinely separate products or platforms maintained by different teams | More navigation friction; harder cross-suite reporting |

For a **web + mobile** product, the typical right call is **single repository, with top-level
sections per platform** (`Web`, `Mobile (iOS)`, `Mobile (Android)`, plus `Shared / API`), and
feature sections nested underneath those. Only split into multiple suites when web and mobile
belong to separate QA teams working on separate release cadences.

Rules of thumb:
- Use **sections and subsections** to build hierarchy — never one suite (or one folder) per
  case.
- Keep the hierarchy **shallow**: aim for 3–4 levels (`Platform > Feature > Sub-feature > cases`).
  Avoid nesting 7+ levels deep — it kills navigation and breaks run filters.
- Don't dump every case into the root section, and don't create a folder for a single case.
- **Don't duplicate the same case across suites** — keep one source of truth and reference
  shared steps instead; duplicates drift out of sync over time.

The same pattern carries over to Xray (Test Repository folders), Zephyr Scale (folders), and
Qase (suites): shallow, feature-aligned, with platform at the top when multiple platforms exist.

---

## Traceability: requirements → tests → coverage

Traceability exists to surface **uncovered requirements** — stories with no tests — not to
maintain a spreadsheet that slowly rots. Lean on the tool's native requirement→test link.

### Xray on Jira

Xray represents coverage through a **"tests" issue link** running from a Test issue to the
requirement (a Story/Requirement Jira issue). The steps:

1. From each Test, add a **"tests" link** pointing to the Story's Jira issue key (or mark the
   story as a "requirement" and link it from its Test Coverage panel).
2. Read coverage off the story's **Test Coverage panel** on the Jira issue, and across the
   whole project via the **Traceability Report** (an Xray report listing requirements as rows,
   with linked tests and their latest status as columns).
3. Filter the **Requirement Coverage / Traceability Report** down to requirements with **0
   linked tests** — those are the uncovered stories. That filtered list is the actual
   deliverable; don't stop at "every test links to something."

Don't link tests to **Test Executions** as a substitute for requirement coverage — executions
record that a run happened, not which requirement is covered. And don't propose a
hand-maintained spreadsheet as the sole mechanism; it can't reliably answer "which stories have
no tests."

The other tools offer equivalents: Zephyr Scale links test cases to Jira issues and provides a
**Traceability** view; Qase links cases to requirements through its Jira/Requirements
integration; TestRail relies on the `refs`/`References` field plus its Jira integration's
coverage view.

---

## When a manual case should graduate to automation

With automation capacity limited, prioritize by **ROI**, not by sheer volume. Default heuristic
for triaging a manual backlog (say, 400 cases sitting in Zephyr Scale):

**Automate first** when ALL of these trend high:
- **Run frequency** — runs every release / every regression / in smoke. Higher frequency means
  the manual per-run cost keeps recurring, so automation pays for itself fast.
- **Stability** — the feature and its UI are stable / low-churn / deterministic. Stable cases
  carry low maintenance cost once automated.
- **Regression / smoke value** — the case guards a genuinely critical path (login, checkout,
  payments) that can't be allowed to silently break.

Score each case roughly as `value = run_frequency × regression_importance ÷ (automation_cost ×
expected_maintenance)`, and automate from the top of that ranked list down.

**Keep manual** when any of these hold:
- **Exploratory / one-off** cases, or ones that run rarely (once a quarter or less) —
  automation cost never pays back.
- **High-churn UI** still in flux — automating now just buys ongoing maintenance; wait until it
  settles down.
- **Flaky / non-deterministic** behavior — automating flakiness just relocates the flake into
  CI; fix the underlying determinism first.
- Cases that need **human judgment** (visual aesthetics, UX feel, content tone).

Two anti-patterns to reject outright: "automate everything," and "automate the flaky,
frequently changing UI first." Both spend capacity on the worst-ROI candidates. The right
sequence: stable, high-frequency regression/smoke cases first; flaky/high-churn/exploratory
ones last, if ever.
</content>
