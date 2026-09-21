---
name: quality-postmortem
description: >-
  Runs blameless postmortems that convert escaped defects and test-suite health signals into
  concrete, systemic fixes. Bundles bug pattern classification, periodic test suite health
  checks, 5 Whys root-cause digging, structured improvement cycles, and ready-to-use
  postmortem/retro templates that carry built-in action item tracking.
  Use when: "QA retro," "escaped bugs," "postmortem," "quality incident," "defect analysis,"
  "improvement cycle."
  Not for: live release go/no-go decisions — use release-readiness. Not for ongoing metric
  dashboards — use qa-metrics. Not for reviewing existing test code quality — use ai-qa-review.
  Related: qa-metrics, test-reliability, test-strategy.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: process
---

<objective>
Turn escaped defects, test suite health signals, and gaps in the quality process into structured, blameless postmortems. A finished postmortem always yields 1-3 action items that are concrete and trackable -- never a vague pledge to "be more careful." The point is to fix the system, not to find someone to blame.
</objective>

---

## Where To Start

| Situation | Work through | Template to use |
|-------------|-------|----------|
| A single escaped bug needs dissecting | Bug Pattern Analysis | Escaped Bug Analysis (`references/templates.md`) |
| You've got 10+ escaped bugs and want the themes | Rolling Individual Bugs Up Into Patterns | — |
| A proactive, no-incident quarterly check | Test Suite Health Review | — |
| A live P0/P1 production incident | Postmortem Template for Quality Incidents | `references/templates.md` |
| A standing sprint/monthly review | Retro Meeting Template | `references/templates.md` |

---

## Questions To Settle First

Look for `.agents/qa-project-context.md` at the project root before anything else — it usually already has the quality goals, risk areas, and test suite details a postmortem needs. Skip whatever it already answers. For the rest, work through:

1. **Is there already a retro cadence?** Sprint-based, monthly, or purely incident-triggered? A steady cadence surfaces slow-building problems early; an incident-only cadence lets patterns build until they blow up.

2. **What kicked this off?** A production incident, a cluster of escaped bugs, a hunch that the suite isn't catching enough, or visible suite degradation? Whatever triggered it shapes where the analysis should focus.

3. **What evidence exists?** A bug tracker with severity and discovery-phase fields, CI pass-rate history, flaky-test reports, coverage trends? Without something to point to, a postmortem turns into an opinion swap.

4. **How did the last round of action items fare?** Shipped, still open, or quietly dropped? If the last batch never landed, the team has already concluded postmortems are theater — fix that follow-through problem before running this one.

5. **Who needs to be in the room?** The engineers who touched the affected area, the QA person who tested it (or didn't get the chance to), a product owner if users felt it, and an engineering manager if the fix needs to be structural. Cap it around 4-8 people so it stays a working session.

6. **What's currently worrying about the test suite?** Creeping flakiness, a slowing pipeline, coverage holes in high-risk code, a quarantine list that never shrinks? A health review is really a postmortem run before the incident happens, not after.

---

## Ground Rules

### 1. "Blameless" targets systems, not accountability

Blameless doesn't mean nobody answers for anything — it means the investigation stays pointed at systems, processes, and tooling instead of at a person's performance. "What allowed this defect to reach production?" is the right kind of question. "Why didn't the developer write a test?" cuts the analysis short. Push past it: maybe the test framework was painful to use, the PR checklist never asked for a test, no one paired to pass on the context, or deadline pressure made testing feel optional. Each of those has a systemic fix; "try harder next time" does not.

### 2. Chase the pattern, not the single fire

One escaped bug is just a story. Three in the same feature area inside two months is a signal. Roll incidents up and look for what repeats — the same root cause, the same team, the same missing test layer, the same pipeline stage. Patterns point to where to invest; one-off incidents only tell you where to firefight today.

### 3. Cap it at 1-3 action items, and make each one real

A real action item names a deliverable ("add integration tests for the coupon API"), an owner ("Alex"), a deadline ("end of sprint 14"), and how you'll know it's done ("PR merged, CI green"). "Improve testing" fails all four tests. "Write 5 integration tests covering payment-service edge cases by March 30" passes.

### 4. Nothing gets done that isn't tracked

An action item that lives only in meeting notes dies there. Put it in whatever tracker the team already uses — Jira, Linear, GitHub Issues — tagged consistently (`postmortem-action` or your team's equivalent), and check its status at the top of the next postmortem. When items keep stalling, the fix is either to shrink them (they're too big to fit a sprint) or to actually prioritize them (make them sprint commitments instead of backlog filler).

### 5. Watch two numbers, never just one

Shipping the action item isn't the finish line — check whether the underlying problem actually stopped happening. If the fix was "add integration tests to close a payment gap," the real test is whether another payment bug still got through. Track both:
- **Defect escape rate** — is the same category of bug still slipping past?
- **Action-item-closure rate** — how much of what got committed to actually shipped on time?

Closure rate climbing while escape rate also climbs means effort is going somewhere, just not the right somewhere. Closure rate staying low means the postmortem process itself isn't real. Most incident platforms in use today (incident.io, Rootly, FireHydrant) already log owner, due date, and completion status per action item — pull both numbers from there before standing up a separate dashboard.

### 6. Let AI sketch the timeline; a person owns the conclusion

Where AI SRE tooling is already part of the stack (Rootly AI SRE, incident.io's auto-drafted post-mortems), it's fine to let it assemble the incident timeline and surface candidate root causes from logs and traces. But the 5 Whys itself, the final root cause, and the action items need to come from a named **blameless RCA owner** — someone other than the incident commander who ran the response. AI is strong at spotting correlations in noisy data and weak at judging which one actually mattered. Treat its output as a first draft, never the verdict. A lighter model like Sonnet 4.6 is plenty for drafting the timeline; save heavier reasoning for causation that's genuinely murky.

---

## Bug Pattern Analysis

### Sorting an Escaped Defect

Once a bug has reached production, run it through three classification lenses to surface where prevention could have worked. The per-bug worksheet (Escaped Bug Analysis) is in `references/templates.md`.

#### Lens 1: What Kind of Root Cause

| Category | Description | Example |
|----------|-------------|---------|
| **Logic error** | Business logic incorrect or incomplete | Discount not applied for edge case currency |
| **Integration failure** | Two components do not communicate correctly | API returns different format than frontend expects |
| **Data issue** | Unexpected data shape, null values, encoding | User with emoji in name breaks CSV export |
| **Race condition** | Timing-dependent behavior | Two concurrent checkouts oversell last item |
| **Configuration** | Environment-specific settings wrong | Feature flag enabled in staging, disabled in prod |
| **Regression** | Previously working behavior broken | Refactor removed null check, old bug returns |
| **Missing requirement** | Behavior not specified, gap in product spec | No error handling for expired OAuth tokens |
| **Performance** | Functional but too slow under load | Search timeout with 100K+ records |

#### Lens 2: Which Test Layer Should Have Caught It

| Level | What it catches | If it escaped this level |
|-------|----------------|------------------------|
| **Unit** | Logic errors, edge cases, boundary conditions | Tests exist but missing edge case? Or no tests at all? |
| **Integration** | API contracts, data flow, service interactions | Integration tests exist? Do they cover error responses? |
| **E2E** | User journey failures, UI state management | Is this critical path covered? Was the specific scenario tested? |
| **Manual/Exploratory** | Visual issues, usability problems, unusual workflows | Was exploratory testing performed? Was the area in scope? |
| **Monitoring** | Performance degradation, error rate spikes | Are alerts configured? Are thresholds correct? |

#### Lens 3: What Could Have Prevented It

| Opportunity | Action | Example |
|-------------|--------|---------|
| **Add test** | Write a test at the appropriate level | Add unit test for currency rounding edge case |
| **Improve existing test** | Existing test was too narrow | Extend checkout E2E to include coupon + international currency |
| **Add quality gate** | CI check would have caught it | Add schema validation for API responses in CI |
| **Improve requirements** | Spec was ambiguous or incomplete | Add acceptance criteria for error states to story template |
| **Add monitoring** | Detect sooner even if not prevented | Add alert for error rate > 1% on payment endpoint |
| **Training/Process** | Knowledge gap or process gap | Run a session on defensive coding for nullable fields |

### Rolling Individual Bugs Up Into Patterns

Once you've classified 10 or more escaped bugs, step back and look at the shape of the whole set:

```
Escaped Bug Summary: [Q1 2026]
═══════════════════════════════

Total escaped bugs: 14

By root cause:
  Logic error:          5  (36%)  ← unit tests needed
  Integration failure:  4  (29%)  ← API contract tests needed
  Data issue:           3  (21%)  ← input validation gaps
  Configuration:        2  (14%)  ← env parity issues

By area:
  Checkout:             6  (43%)  ← highest risk, needs investment
  User management:      4  (29%)
  Reporting:            2  (14%)
  Settings:             2  (14%)

By should-catch level:
  Unit:                 5  (36%)  ← developers not testing edge cases
  Integration:          4  (29%)  ← missing integration test layer
  E2E:                  3  (21%)
  Monitoring:           2  (14%)

Top action themes:
  1. Add integration tests for checkout API (covers 4 of 14 bugs)
  2. Mandate unit tests for all calculation/validation logic (covers 5 of 14)
  3. Add currency and encoding edge cases to test data fixtures (covers 3 of 14)
```

A rollup like this shows exactly where the return on effort is highest: one systemic fix — integration tests for checkout, in this example — would have headed off 29% of everything that escaped. **When the same pattern shows up quarter after quarter, it belongs in the `test-strategy` doc, not buried in one sprint's action items** — elevate it so the strategy itself reflects where defects are actually getting through.

---

## Test Suite Health Review

Think of this as a postmortem you run on the suite itself before it fails you — quarterly, or sooner if warning signs show up.

### Tracking Flakiness Over Time

```
Flaky Test Trend Review
═══════════════════════

Current flaky rate: _____ % (target: <2%)
Trend (last 3 months):
  Month 1: _____ %
  Month 2: _____ %
  Month 3: _____ %
Direction: [ ] Improving  [ ] Stable  [ ] Worsening

Top 5 flakiest tests (by failure count):
  1. _____________________ — _____ failures — root cause: _____
  2. _____________________ — _____ failures — root cause: _____
  3. _____________________ — _____ failures — root cause: _____
  4. _____________________ — _____ failures — root cause: _____
  5. _____________________ — _____ failures — root cause: _____

Quarantine:
  Tests in quarantine:    _____ count
  Oldest quarantine:      _____ days (target: <14)
  Quarantine resolved this month: _____ count
```

### How Long the Suite Takes

Log the current full-run duration, how it's trended over the last three months, and the five slowest individual tests. If it's climbing, look for candidates to move to a nightly run, sequential stages that could run in parallel, slow fixture/data setup (an API call beats driving the UI), or oversized test files that should be split for better shard balance.

### Where Coverage Is Thin

Look at overall line/branch coverage, then zero in on critical paths that fall short of the bar (payments, auth, and data export should sit at 90%+), code that changed recently without matching test updates (cross-reference `git log --since="30 days ago"` against the coverage report), and any feature that shipped without E2E coverage at all.

### What's Sitting Skipped or Disabled

Go through every skipped/disabled test and sort by age and reason. Under a week old is probably still in progress. One to four weeks needs a ticket and a timeline attached. One to three months is overdue — fix it or delete it. Past three months, delete it; it isn't getting fixed. Resolve each one as: fix and re-enable, delete as obsolete, or move to quarantine with a linked ticket.

---

## Process Improvement Cycles

### Carving Out an Improvement Sprint

Set aside a fixed slice of every sprint — 10-15% of capacity — for quality work sourced from postmortem action items and health-review findings.

**Cycle:**

```
1. IDENTIFY    — Top 3 pain points from latest retro/postmortem
2. ROOT CAUSE  — 5 Whys analysis for the #1 pain point
3. PROPOSE     — Solution with effort estimate (S/M/L)
4. IMPLEMENT   — One improvement per sprint (start small)
5. MEASURE     — Did the metric improve? By how much?
6. ITERATE     — If not improved, dig deeper. If improved, tackle #2.
```

### Digging In With 5 Whys

5 Whys works by repeatedly asking "why" past the surface symptom until what's left is a process, system, or structural cause — not something one person did or didn't do. That discipline is the whole technique.

**Worked example: a payment bug got through to production**

```
Problem: Users were charged twice for a single purchase.

Why 1: The payment API was called twice on form submit.
Why 2: The submit button was not disabled after the first click.
Why 3: The frontend developer did not implement button disabling.
Why 4: The acceptance criteria did not mention double-submit prevention.
Why 5: The story refinement process does not include edge case review
       for payment-related stories.

Root cause: Process gap — payment stories are not reviewed for transaction
safety edge cases before development begins.

Action: Add a "Payment Safety Checklist" to the story template for any
story touching payment flows. Checklist includes: idempotency,
double-submit prevention, partial failure handling, timeout behavior.
Owner: [Product Manager] — Due: [Next sprint]
```

**Guardrails for the exercise:**
- Stop at whatever the team actually has the power to change — process, tool, or structure. Pushing on to "why is the budget limited?" has gone past useful.
- The chain doesn't have to be linear — a symptom can have several contributing causes running in parallel. Chase whichever branch matters most.
- Back every "why" with something you checked, not a guess. "The developer skipped tests" — did they? Look at the PR; maybe tests were there but too shallow.
- Landing on "human error" means you stopped one step too soon. People will always make mistakes; the job is to make the system catch or prevent them.

### Sizing Solutions by Effort

For each root cause, sketch 1-3 possible fixes at different effort levels. Here's how that looks for a recurring flaky-test issue:

```
Root Cause: E2E tests fail intermittently on async-loaded content

Solution A (Small — 1 day):
  Replace fixed waitForTimeout calls with explicit wait-for-condition
  assertions in the 5 flakiest specs.
  + Quick to implement, kills the most common flake source
  − Manual, one spec at a time; new flakes can creep back in

Solution B (Medium — 1 sprint):
  Solution A across the suite + add a flaky-test detector to CI that
  reruns failures once and tags any test that passes on retry.
  + Automated detection, surfaces flakes before they erode trust
  − Requires CI config change; reruns add pipeline time

Solution C (Large — 2 sprints):
  Solution B + auto-quarantine tagged tests and route them to an
  owner-assigned backlog with a 14-day fix-or-delete SLA.
  + Self-healing trust in the green build; flakes can't block releases silently
  − Needs quarantine infrastructure and ownership process buy-in

Recommendation: Start with A immediately, implement B this sprint,
plan C for next quarter as strategic work.
```

---

## Postmortem & Retro Templates

`references/templates.md` holds the two full-length, copy-paste-ready formats:

- **Postmortem Template for Quality Incidents** — for P0/P1 production bugs, data loss, security issues, or an outage traced to a code change. Covers summary, severity/impact, a UTC-timestamped timeline table, root cause, the 5 Whys, which tests existed versus which were missing, how it was detected, immediate/short-term/long-term action tables, and lessons learned.
- **Retro Meeting Template** — for the recurring sprint or monthly quality retro: a seven-part, 30-60 minute agenda (previous action items → data review → what went well → what needs work → root cause discussion → new action items → close) plus notes for whoever facilitates.

Both formats start the same way: reviewing what happened to the previous round's action items. That closed loop is what keeps anyone accountable — skip it and items just disappear.

---

## Anti-Patterns

### Making it about who, not what

Chasing down who made the mistake instead of what let the mistake reach production. Blame breeds fear, fear breeds concealment, and concealment breeds bigger incidents down the line. "Who wrote this bug?" teaches people to stay quiet. "What process gap let this through?" teaches people to fix the process.

### Talking without deciding anything

A meeting that leaves everyone with a better understanding but changes nothing. Without specific, assigned action items at the end, the same failure mode will resurface. Worse still, the team quietly reclassifies postmortems as venting sessions rather than tools that fix things.

### Committing to action items that never happen

Action items that land in a backlog and stay there, unprioritized. This is arguably worse than skipping action items entirely, since it manufactures a false sense that things are improving. Escalate anything still open after two sprints. When you audit why items die, it's usually one of these, not "we forgot":

- **Assigned to a team, not a person.** A group owner is nobody's owner. Fix: name one person with enough context to actually start.
- **No real deadline.** "Soon" doesn't count. Fix: attach a specific sprint or calendar date.
- **Too large to finish.** "Refactor the test framework" will never fit in a sprint. Fix: cut it into pieces that each fit one PR.
- **Never revisited.** Skip the check-in at the next retro and items disappear without anyone noticing. Fix: make the closed-loop review a standing first agenda item, every time.
- **No number attached.** If finishing the item doesn't move a metric you could name in advance, there's no way to know afterward whether it worked.

The counter-move: spend the first five minutes of every retro walking through the previous items, tagging each Done, In Progress (with a current ETA), or Dropped (with a reason).

### Only ever reacting to fires

Treating quality reviews as something that only happens after production breaks. Proactive checks — test suite health, coverage trends, the flaky test list — catch problems before they become incidents, so run them monthly on their own schedule. Incident postmortems are a supplement to that cadence, not a substitute for it.

### Stopping the root cause hunt too soon

"The developer skipped the test" describes a symptom, not a root cause. Keep pushing: was the framework painful? Was there no time? Was the requirement never written down? Was there no pairing or review to catch it? Landing on the individual shuts the door on any systemic fix.

### Writing action items with no teeth

Neither "improve test coverage" nor "be more careful with deployments" can be tracked, measured, or checked off with confidence. Contrast that with: "Add integration tests for payment webhook handling covering success, failure, and timeout paths. Owner: Alex. Due: Sprint 14. Verification: PR merged, 3 new integration tests green in CI."

### Retros run on vibes

Building a quality retro around gut feeling instead of evidence. "Feels like we've had more bugs lately" could be true, or it could just be recency bias. Pull the actual numbers: is the escaped-bug count really trending up, and where is it concentrated? Skip the data and the team ends up chasing whatever's loudest rather than whatever matters most.

---

## Verification

The deliverable is the written postmortem together with action items that are tracked to closure. Check the smallest, cheapest thing first:

```bash
# Every action item became a real, owned, dated ticket — not a doc bullet.
# (gh example; swap for `jira issue list` / Linear API as appropriate)
gh issue list --label postmortem-action --json number,title,assignees,milestone \
  | jq '[.[] | select(.assignees == [] or .milestone == null)]'
# Expect: []  (empty). Any item missing an owner or due milestone is not done.

# The escaped defect's timeline is reconstructable from evidence, not memory.
git log --since="<introduced-date>" --until="<detected-date>" --oneline -- <affected/path>
# Expect: the introducing commit is in this range and named in the postmortem.

# The fix/regression test the action item promised actually exists and passes.
git log --grep="<INCIDENT-ID>" --oneline      # the fix commit references the incident
<your test runner> <new regression test path> # exits 0
```

After that, read back through the postmortem itself and confirm two things: the 5 Whys lands on a process/tool/structure cause rather than "developer didn't write a test," and both the action-item-closure rate and the escaped-defect rate are written down — never just one of the two.

## Done When

- The escaped defect's timeline (introduced, released, detected, resolved) is reconstructed with evidence from commit history and the bug tracker, not recollection.
- The 5 Whys analysis is finished and terminates on a systemic cause (process, tool, or structure) — not "developer didn't write a test."
- The test gap is pinned to a specific coverage hole: a missing test type, an untested scenario, or an uncovered area.
- Action items have named owners and due dates and live in the team's work tracker under a postmortem tag.
- The findings went out to the team as a written summary, rather than staying inside QA or a private doc.
- Both the action-item-closure rate and the escaped-defect rate are tracked side by side; for incident postmortems, both should be pullable straight from the incident platform's native tracking.
- Where AI SRE tooling was used, its draft timeline and candidate root causes are logged as input, and a named blameless RCA owner (never the incident commander) signed off on the human-written 5 Whys and action items.

## Related Skills

- **qa-metrics** — Supplies the underlying numbers (defect escape rate, flakiness rate, coverage trends) that this skill analyzes and acts on. Reach for qa-metrics for the standing dashboard, this skill for the analysis session itself.
- **test-reliability** — Handles flaky test classification and quarantine management, which in turn feeds the test suite health review here.
- **test-strategy** — The document to update once a postmortem uncovers a systemic gap that keeps recurring quarter over quarter.
- **shift-left-testing** — Many action items that come out of a postmortem are really shift-left moves: testing earlier, tightening requirements, pairing dev with QA.
- **release-readiness** — Owns quality gates and release criteria, which should evolve based on what postmortems find; use it for live go/no-go calls, not for after-the-fact analysis.

## Reference Files (in `references/`)

- **templates.md** — The copy-paste-ready Postmortem Template for Quality Incidents, the Retro Meeting Template with facilitator notes, and the single-bug Escaped Bug Analysis worksheet.
