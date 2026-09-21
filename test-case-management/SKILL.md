---
name: test-case-management
description: >-
  Write and maintain MANUAL and hybrid test cases and suites across TestRail, Xray (Jira),
  Zephyr Scale, and Qase. Covers what a test case is built from (title, preconditions, steps,
  expected results, test data), how to structure suites and sections, generating batches of
  cases from stories and acceptance criteria, catching ambiguous steps through linting,
  producing each tool's CSV/API import-export payloads, tracing requirements to tests and
  surfacing coverage gaps, keeping reviews rigorous, and judging when a manual case is ready
  to become an automated one.
  Use when: "write a test case," "manual test case," "TestRail case," "Xray test," "Zephyr
  Scale case," "Qase case," "import CSV into TestRail," "lint these steps," "traceability
  report," "should this be automated."
  Not for: producing automated TEST CODE itself — that's ai-test-generation. Deciding
  sprint-level WHAT to test — that's test-planning.
  Related: ai-test-generation, test-planning, exploratory-testing, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "1.0"
  category: process
---

<objective>
Imagine a test step that just says "test the login," with an expected result of "verify it
works." It'll pass a review, but it doesn't actually prove anything: give it to two different
testers and each will interpret it differently, and afterward neither can say with confidence
whether it truly passed. Preventing that outcome is the whole point of this skill. It pushes you
toward cases that leave nothing to chance — discrete steps, exactly one checkable result per
step, concrete data — organized into suites people can actually find their way around, written
in the exact payload shape each destination tool demands. From a distance TestRail, Xray Cloud,
Zephyr Scale, and Qase look interchangeable, but their authentication schemes, endpoints, and
step-field naming conventions differ in ways agents constantly confuse. Get any of that wrong
and you'll get a 401 or a 400 back instead of a created case.
</objective>

## Where to Start

| You're trying to... | Go to |
|---|---|
| Turn a single AC into one well-formed case | [Anatomy of a Manual Case](#anatomy-of-a-manual-case) |
| Generate many cases at once from a story | [Bulk Case Generation](#bulk-case-generation) + the relevant tool section |
| Check whether a set of steps is actually verifiable | [Linting Ambiguous Steps](#linting-ambiguous-steps) + `references/linting.md` |
| Build a create-case payload for a specific tool | [Per-Tool API Payloads](#per-tool-api-payloads) + `references/tool-apis.md` |
| Produce a CSV TestRail will actually import | `references/import-and-traceability.md` (CSV section) |
| Decide how suites/sections should be laid out | `references/import-and-traceability.md` (organization section) |
| Find requirements with no linked tests | [Requirement Traceability](#requirement-traceability) + `references/import-and-traceability.md` |
| Decide if a case is ready for automation | [Graduating to Automation](#graduating-to-automation) |

## Before You Start: What to Ask

Start by checking `.agents/qa-project-context.md` at the project root — it may already cover
the tool, project keys, and house conventions, and if so there's no need to ask again. If that
file is missing, note that the `qa-project-context` skill can generate one. For anything it
doesn't already answer, ask directly:

- **Which of the four tools is this for — TestRail, Xray, Zephyr Scale, or Qase?** Auth model,
  endpoint shapes, and even what the steps field is called all vary by tool. Get this wrong and
  the payload comes back as a 401 or 400.
- **For TestRail: a single shared repository, or several suites?** This determines whether
  cases live under sections in one suite or get spread across suites — it affects every
  `section_id` you produce and the organizational plan as a whole.
- **For Xray/Zephyr: Jira Cloud, or Server/Data Center?** Base paths and auth mechanisms differ
  between the two. This skill assumes Cloud; Server requires an entirely different set of
  endpoints.
- **Where are the cases coming from — acceptance criteria, a story, or a loose feature
  description?** This drives both how many cases you end up with and how you split rules into
  cases.
- **Is requirement traceability needed here?** If it is, gather the relevant Jira/requirement
  keys upfront so links get built alongside the cases rather than bolted on afterward.

---

## Guiding Rules

1. **An expected result only holds up if a stranger could judge it.** If a second person — or
   a machine — would need to guess at pass/fail, the result has failed its purpose. Words like
   "works," "looks right," "is fine," or "wait a bit" don't meet that bar. Use a concrete value,
   a named element with its expected state, an exact message, a status code, a count, or a
   bounded time window instead.

2. **One check per step.** Stacking three assertions into a single step means a failure tells
   you nothing about which of the three actually broke, or which needs a rerun.

3. **Split along business rules, not convenience.** A story like "valid code lowers the total /
   expired code errors out / used code gets rejected" is really three cases, each independently
   pass/fail-able — never one case padded with three paragraphs of stapled-together expected
   results.

4. **Every tool's API is its own contract.** TestRail's `custom_steps_separated`, Qase's
   `Token` header, Xray's two-step GraphQL authentication, and Zephyr's standalone `teststeps`
   call don't substitute for each other. Only pull syntax from the section for the tool you're
   actually targeting.

5. **Traceability exists to surface gaps.** The real deliverable is a list — pulled from a
   native coverage report — of requirements with zero linked tests, not a spreadsheet that goes
   stale, and not the empty claim that "every test links to something."

6. **Automate for payoff, not for volume.** Capacity is limited, so stable, frequently-run
   regression/smoke cases go first, while exploratory, one-off, and high-churn/flaky cases stay
   manual. Chasing "automate everything" wastes that limited capacity on cases least worth the
   investment.

---

## Anatomy of a Manual Case

Five ingredients make a case well-formed; leave out any one and reproducibility breaks.

| Ingredient | Contains | What breaks without it |
|---|---|---|
| **Title** | Feature, scenario, and outcome in one line | Hard to search or dedupe |
| **Preconditions** | Assumed state (account exists, on page X, flag enabled) | Tester improvises setup; flaky runs |
| **Steps** | One discrete action each | Not reproducible |
| **Expected Results** | One observable outcome per step | Can't be verified |
| **Test Data** | The literal values used (codes, emails, counts, timings) | Can't be repeated |

**Poorly formed** (a single vague step, an expected result that can't be checked, nothing said
about setup or data):

```
Title: Login test
Steps: Test the login.
Expected: Verify it works.
```

**Well formed** — derived from the AC "after 5 wrong-password attempts, the account locks for
15 minutes":

```
Title: Login — account locks for 15 minutes after 5 failed attempts
Preconditions: A registered account exists for user@example.com. The user is logged out
               on the /login page. Lockout policy: 5 attempts, 15-minute lockout.
Test Data: email user@example.com, wrong password "WrongPass!", correct password "Passw0rd!"
Steps (one assertion per step / single expected result each):
  1. Action:   Submit the login form with user@example.com and "WrongPass!".
     Expected: Error "Invalid email or password." shows; the failed-attempt count is now 1.
  2. Action:   Repeat the wrong-password submit until 5 failed attempts total.
     Expected: On the 5th failure the account is locked; message reads
               "Account locked. Try again in 15 minutes."
  3. Action:   Immediately submit with the CORRECT password "Passw0rd!".
     Expected: Login is still blocked; the same lockout message is shown (lockout overrides
               valid credentials).
  4. Action:   Wait 15 minutes, then submit with the correct password.
     Expected: Login succeeds and the dashboard loads.
```

Why this version works: the setup is explicit, the data is concrete (5 attempts, a 15-minute
window), each step performs one action, and each result can be verified without interpretation.

---

## Bulk Case Generation

Starting from a story or a set of acceptance criteria, break it into one case per rule first,
then generate the tool-specific payload for each. Using a discount-code story as the worked
example (valid code lowers the total / expired code errors / already-redeemed code is
rejected), it splits into **three** cases:

1. A valid code is applied → the total drops (happy path).
2. An expired code is applied → an inline error appears, total is unchanged.
3. An already-used code is applied → it's rejected, total is unchanged.

If the team also wants edge coverage, layer in the negatives the story implies but doesn't
state outright (an empty code field, a malformed code) — but every case still needs discrete
steps with exactly one expected result each; never collapse all three rules into a single case.
Choosing *which* stories belong in a given sprint's scope is a `test-planning` concern, not
something answered here.

---

## Linting Ambiguous Steps

When you're asked to "lint" a suite, your job is to FLAG the steps that aren't deterministic
and rewrite them — not to nod along and pronounce them fine. Rubber-stamping ("yep, everything
checks out") is exactly the failure mode this section is meant to prevent.

A step fails the lint whenever its expected result can't be verified with certainty. Watch for:

- **Vague actions** — "click around," "test the X," "play with it" → replace with the exact
  element and the exact action.
- **Vague data** — "some data," "a value," "stuff" → substitute concrete test data.
- **Unverifiable expectations** — "everything works," "it looks right," "is fine," "no
  problems" → replace with the specific observable outcome.
- **Open-ended waits** — "wait a bit," "after a while" → give it a bound ("within 10 s" or
  "until the spinner disappears and a row appears").
- **More than one assertion per step** → break it into separate steps, one assertion each.

Take the classic four-step offender ("app opens / everything works / it looks right / the
report is ready") as an example — all four are ambiguous, and all four need flagging and
rewriting with real selectors, real values, and bounded conditions. "No issues found" is never
a valid verdict for a suite like this one. `references/linting.md` holds the complete checklist,
the full worked rewrite of those four steps, and the expected table format for lint output.

---

## Per-Tool API Payloads

These four APIs are easy to cross-wire. What follows is just the summary — full curl commands
and GraphQL bodies live in `references/tool-apis.md`:

| Tool | Auth | Create endpoint | Steps field |
|------|------|-----------------|-------------|
| **TestRail** | Basic `email:api_key` | `POST add_case/{section_id}` | `custom_steps_separated` array of `{content, expected}` |
| **Xray Cloud** | `POST /api/v2/authenticate` → Bearer token | GraphQL `createTest` at `/api/v2/graphql` | `steps[] {action, result}`; Gherkin → `testType: Cucumber` + `gherkin` |
| **Zephyr Scale Cloud** | `Authorization: Bearer <JWT>` | `POST /v2/testcases` then `POST /v2/testcases/{key}/teststeps` | separate `teststeps` call, `inline {description, expectedResult, testData}` |
| **Qase** | header `Token: <key>` | `POST /v1/case/{CODE}/bulk` | `steps[] {action, expected_result, data}` |

Traps worth respecting here too, which the reference doc covers in more depth:

- **TestRail** — separated steps belong in `custom_steps_separated`, not the plain-text
  `custom_steps` blob. The endpoint is `add_case/{section_id}` — `add_test` is something
  different (a run instance). The base URL is `{instance}/index.php?/api/v2`. Don't reach for
  a Qase-shaped `POST /case`.
- **Xray Cloud** — authenticate first through `/api/v2/authenticate` (client_id/client_secret
  yields a bearer token good for 24h), then favor **GraphQL** `createTest` over REST helpers.
  Gherkin scenarios import as a **Cucumber** test type, never Generic. Avoid the deprecated
  `/rest/raven/1.0/...` Cloud path, Server-style REST, and Jira username/password basic auth.
- **Zephyr Scale Cloud** — the base URL is `api.zephyrscale.smartbear.com/v2`, and auth is JWT
  Bearer. Steps go through a SEPARATE `/testcases/{key}/teststeps` call — never embedded as
  text in the create body. Don't emit `/v1/`, the wrong host, or Qase's `Token` header here.
- **Qase** — the auth header is `Token: <key>`, not `Authorization: Bearer`. Prefer
  `POST /case/{CODE}/bulk` with a `cases` array over N separate single-case POSTs. Keep
  TestRail's `add_case` / `custom_steps_separated` out of this one.

The TestRail CSV importer expects a header row that maps to its own field names — `Title`,
`Section Hierarchy`, `Steps (Separated)`, `Expected Result`, `Priority`, `Type`,
`Preconditions` — spelled out in `references/import-and-traceability.md`. Always produce an
actual CSV with a header row; never fall back to free-form prose, a single Description column,
or JSON when CSV is what was requested.

---

## Suite and Section Structure

Organize using **sections and subsections**, kept **shallow** — the target is 3 to 4 levels
deep. For a product spanning web and mobile, default to **single-repository mode** with
top-level sections per platform (`Web`, `Mobile (iOS)`, `Mobile (Android)`, `Shared / API`) and
feature sections nested beneath them. Only reach for **multiple suites** when different
platforms are genuinely owned by separate teams with separate release cadences.

Avoid: a folder per individual case, nesting 7+ levels deep, dumping every case into the root
section, and copying the same case into more than one suite (keep one source of truth
instead). The full single-repository-vs-multiple-suites tradeoff, plus the complete
organizational rules, is in `references/import-and-traceability.md`.

---

## Requirement Traceability

The goal is a coverage report that surfaces **which stories have zero tests** — the actual gaps
— not a reassuring confirmation that testing happened somewhere.

**On Xray/Jira**: attach the native **"tests" issue link** from each Test to the requirement's
Jira issue key — never to a Test Execution, which only records that a run occurred, not that
coverage exists. Check per-story coverage in the Story's Test Coverage panel; check it
project-wide via the **Traceability Report / Requirement Coverage report**. Then filter that
report down to requirements with **zero linked tests** — that filtered list is the actual
deliverable. A manually maintained spreadsheet is not an acceptable stand-in for this mechanism,
and uncovered requirements must never be silently dropped from the report. Zephyr Scale, Qase,
and TestRail each offer their own version of this (issue links plus a coverage/traceability
view), documented in `references/import-and-traceability.md`.

---

## Graduating to Automation

Rank manual cases by expected return: `value ≈ run_frequency × regression_importance ÷
(automation_cost × expected_maintenance)`. When facing a capacity constraint (say, a 400-case
backlog in Zephyr Scale):

- **Automate these first** — cases that run often (every release, every regression pass, in
  smoke), cover stable/low-churn/deterministic areas, and protect a genuinely critical path.
- **Leave these manual** — exploratory or one-off cases, cases that run rarely, UI that's still
  churning heavily, anything flaky or non-deterministic, and cases requiring human judgment.

Two anti-patterns to reject outright: "automate everything," and "automate the flaky,
fast-changing UI first." Both drain scarce capacity into the candidates with the worst payoff.
The full decision rule lives in `references/import-and-traceability.md`. Once a case has
actually graduated, producing the automated test code itself belongs to `ai-test-generation`
or a framework-specific skill (`playwright-automation`, `api-testing`) — that work sits outside
this skill's scope.

---

## Keeping Reviews Rigorous

- A reviewable case fits on one screen: the title states the outcome, preconditions are
  present, steps are discrete, every expected result is observable, and test data is concrete.
- Run the lint checklist against a new case before merging it; reject anything with a
  non-deterministic expected result.
- Link the requirement at case-creation time — not as a cleanup pass done later.
- Tag suites by smoke/regression/platform so runs can be filtered; a 400-case repository with
  no tags becomes unusable once it's time to decide what to run for a release.

---

## Common Mistakes to Avoid

### 1. A single vague step with a "verify it works" expected result
"Test the login → verify it works" can't actually be run by anyone. Break it into discrete
steps, give each an observable expected result, and spell out preconditions and concrete data.

### 2. Rubber-stamping a suite that was supposed to be linted
Declaring steps "fine," or lightly rewording them while "everything works" and "wait a bit"
survive untouched, is exactly the failure linting is meant to catch. Every non-verifiable
expected result needs to be flagged and rewritten.

### 3. Mixing up the four tools' APIs
Sending Bearer auth to Qase (it wants `Token`), putting `add_case`/`custom_steps_separated` on
a Qase or Zephyr call, hitting `/rest/raven/1.0/` on Xray Cloud, hitting `/v1/` on Zephyr Scale
Cloud, or embedding steps as a text blob in Zephyr's create body — each one produces either a
4xx or a silently wrong field. Pull syntax only from that tool's own section.

### 4. Folding a multi-rule story into a single case
Combining "valid / expired / already-used" into one case produces one pass/fail verdict that
hides which rule actually broke. One case per rule, always.

### 5. Treating CSV as prose or a single Description column
A TestRail import lacking a header row mapped to importer fields forces manual remapping after
the fact. Supply `Title`, `Section Hierarchy`, `Steps (Separated)`, `Expected Result`, and so on.

### 6. Deep nesting and one folder per case
Trees 7+ levels deep, or a folder for every individual case, make the repository unusable to
navigate. Stick to 3–4 shallow section levels, with platform at the top for web+mobile products.

### 7. Traceability kept as a manual spreadsheet
A hand-maintained sheet can't reliably answer "which stories have no tests." Rely on the tool's
native requirement→test link plus its coverage/Traceability report, and surface the gaps.

### 8. Automating everything, or automating the flaky cases first
Automating one-off exploratory cases, or a high-churn/flaky UI, before anything else burns
capacity for a negative return. Stable, high-frequency regression/smoke cases come first.

---

## How to Verify Your Output

Before handing anything off, confirm it actually works — start with the cheapest checks:

- **Lint your own output.** Search the generated cases for the banned phrases:
  `grep -niE "verify it works|looks right|is fine|wait a bit|no problems|everything works" cases.*`
  — this should return nothing. Any match is a non-deterministic expected result you still need
  to fix.
- **TestRail CSV.** Open the file and check that the header row includes `Title`,
  `Section Hierarchy`, `Steps (Separated)`, `Expected Result` — `head -1 cases.csv` should show
  those column names, not a lone `Description`. Dry-run it through the import wizard; correct
  headers auto-match with no manual remapping required.
- **API payload, before it actually POSTs.** Validate the JSON (`jq . payload.json` should exit
  0), and cross-check the auth header and endpoint against the row for that tool in
  [Per-Tool API Payloads](#per-tool-api-payloads) — Qase needs `Token:` not
  `Authorization: Bearer`, TestRail needs `add_case/{section_id}` not `add_test`. A `201` (or
  test id in the response, or a `200` with a new case `key` for Zephyr) confirms creation
  worked; a `401` points to the wrong auth scheme, a `400` points to the wrong step field.
- **Traceability.** Pull the tool's coverage/Traceability report and confirm it lists
  requirements with 0 linked tests — an empty "uncovered" column means the links took; a
  populated one is your remaining gap list.

---

## Definition of Done

- Every generated case has a title, preconditions, discrete steps, one observable expected
  result per step, and concrete test data — with no "verify it works" / "looks right" / "wait a
  bit" style expected results anywhere.
- A multi-rule story was split into one case per rule, not merged into a single case.
- Any API payload uses the right tool's auth scheme, endpoint, and step-field name (TestRail:
  `custom_steps_separated` + `add_case/{section_id}`; Xray: two-step auth then GraphQL
  `createTest`, Cucumber for Gherkin; Zephyr: `/v2` Bearer plus a separate `/teststeps` call;
  Qase: `Token` header plus `/case/{CODE}/bulk`).
- Any TestRail CSV has a header row that maps to importer fields (`Title`,
  `Section Hierarchy`, `Steps (Separated)`, `Expected Result`).
- A linted suite comes back with every ambiguous step flagged and rewritten — "no issues found"
  is never the answer when smells are actually present.
- Traceability relies on the tool's native requirement→test link plus a coverage report listing
  the uncovered requirements.
- Automation graduation output is ROI-ordered (stable, high-frequency, regression/smoke cases
  first) and explicitly names what's staying manual.

---

## Related Skills

- **ai-test-generation** — hand off here once a manual case has graduated, to turn it into
  actual automated TEST CODE; this skill's scope ends at the manual/hybrid case and its import
  payload.
- **test-planning** — go here for sprint/release-level decisions about WHAT to test; this skill
  authors the cases once that scope has already been decided.
- **exploratory-testing** — where one-off/charter-based cases originate that are meant to stay
  manual; feeds into the automation-graduation call made here.
- **qa-project-context** — the shared dependency every path through this skill reads first, for
  the tool, project keys, and house conventions, before any payload gets generated.

---

## Reference Files (in `references/`)

- **tool-apis.md** — complete TestRail / Xray Cloud / Zephyr Scale / Qase create-case payloads
  (curl + GraphQL), their auth flows, and the tool-by-tool traps to avoid cross-wiring.
- **linting.md** — the full ambiguous-step lint checklist, the worked rewrite of the four
  classic bad steps, and the expected lint-output table format.
- **import-and-traceability.md** — TestRail CSV column-to-field mapping with a 3-case example,
  the suite/section organization rules, requirement traceability plus coverage-gap reporting,
  and the automation-graduation decision rule.
