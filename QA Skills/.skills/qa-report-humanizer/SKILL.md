---
name: qa-report-humanizer
description: >-
  Remove AI-generated patterns from QA reports, bug reports, test summaries,
  status updates, and quality communications. Detects and rewrites robotic
  test-result language, template-sounding status updates, inflated severity
  descriptions, and generic stakeholder reports — without inventing facts.
  Makes QA writing sound like a real engineer wrote it.
  Use when: "humanize report," "rewrite QA summary," "fix test report,"
  "make this sound human," "clean up status update."
  Not for: general prose, blog, or marketing-copy cleanup — use the global
  humanizer skill. Not for: classifying or routing CI failures — use ai-bug-triage.
  Related: ai-bug-triage, qa-metrics, qa-dashboard, quality-postmortem.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: process
---

<objective>
A clean-sounding QA report that says nothing is worse than an awkward one that names the
actual break. "A critical defect was identified in the authentication module" is
grammatically fine and informationally empty. This skill takes QA reports, bug reports,
test summaries, and status updates and turns them into something an engineer can actually
act on — while guaranteeing that no number, error, or severity gets invented along the way.
</objective>

## Discovery Questions

Start with `.agents/qa-project-context.md` — it already encodes the team's tone, tracker,
and severity conventions, so skip whatever it answers. Beyond that, only ask what would
actually change the output:

- **Who's the audience — engineer, exec, or customer?** An engineer needs the failing
  selector and repro steps; an exec needs a ship/no-ship call and the open blockers; a
  customer needs impact and a timeline. Each audience changes both tone and what gets cut.
- **Which channel — Slack, a PR comment, or a formal report?** Slack wants 2-3 lines plus a
  link, a PR comment wants the specific code/selector fix, a report wants real structure.
  Let the channel dictate length and formatting.
- **Do the numbers and severities need to survive untouched?** A source that says "9 failed"
  and "P1" keeps those exact values in the rewrite. Missing a figure? Flag the gap rather
  than filling it in (see Core Principle 5).

## Core Principles

1. **Specificity wins over thoroughness.** "Login fails when the email has a plus sign"
   does more work than "Various authentication edge cases were identified" — the first is
   fixable, the second teaches nothing. Always name the behavior, the trigger, and the scope.

2. **Describe the event, not its category.** "Authentication module" is a bucket you throw
   things into; "login with plus-sign emails" is an actual bug. Category language lets a
   writer sound thorough while dodging the specifics they don't actually have. Swap every
   category for the concrete thing it's standing in for.

3. **A report that hides what broke or what to do has failed.** Write for whoever has to
   fix this at 4pm on a Friday: lead with what's broken or at risk, then the action item.
   Cut anything nobody's going to read.

4. **Keep every fact, strip every adjective.** Rewriting changes the prose, not the
   underlying data — no number, error string, severity, bug description, or test result is
   allowed to move. The only things fair game for deletion are filler, hedging, and
   repeated synonyms — never information.

5. **Don't fabricate the specifics you were asked to supply.** The instruction "make it
   specific" can tempt a model into inventing a percentage, an incident count, or a repro
   that was never actually observed. Resist it. When the source is vague and no number can
   be verified, the honest move is to say so ("user impact not measured") rather than write
   "8% of users." A made-up metric is a worse outcome than an admittedly vague one.

## QA-specific AI patterns to detect and fix

Each pattern below gets a bad draft, a rewrite, and the reasoning. The worst offender —
the template opener — gets the full treatment; the others are shown more compactly.

### 1. The template opener (the worst offender)

Bad:
> Test execution was completed successfully for Sprint 47. A total of 342 test cases were executed across 5 test suites, achieving a 97.4% pass rate. The following sections provide detailed results.

Better:
> Sprint 47: 342 tests run, 9 failed. 6 of the failures are in checkout (payment form validation). The other 3 are flaky timing issues we've seen before.

Why: the first buries the actual signal under throat-clearing preamble; the second delivers
what happened and where to look in a single line.

### 2. Inflated severity language

Bad: "A critical defect was identified in the authentication module that could potentially impact the user experience across multiple touchpoints."
Better: "Login breaks if your email has a `+` in it. We've checked analytics — about 8% of our users have plus-sign emails. Needs a fix before release."

Why: "critical defect in the authentication module" names a category; "login breaks if your email has a plus sign" names something fixable. (That 8% figure comes straight from the source's own analytics — never add a number the source didn't already supply.)

### 3. The pass-rate obsession

Bad: "The overall pass rate increased from 94.2% to 97.1%, demonstrating significant improvement and showcasing the team's commitment to quality."
Better: "Pass rate went from 94% to 97%. Most of that was fixing the 3 flaky Playwright tests that kept timing out on the dashboard load. Real bugs found: 2 (both in the new export feature)."

Why: a pass rate without context is a vanity metric. State what actually changed instead.

### 4. Generic risk language

Bad: "Several high-risk areas have been identified that require careful monitoring. The team recommends continued vigilance and proactive testing."
Better: "The payment flow has no E2E coverage for 3D Secure cards. We've had two production incidents from this in the past 6 months. I'd prioritize this over the admin panel work."

Why: phrases like "high-risk areas" and "continued vigilance" carry no content. Name the actual area, the actual risk, and the action to take.

### 5. Synonym cycling for test results

Bad: "The authentication tests passed successfully. The login verification suite completed without issues. The credential validation checks returned positive results. The sign-in workflow tests executed as expected."
Better: "All auth tests passed (login, registration, password reset, SSO)."

Why: saying "auth tests passed" four different ways is three times too many restatements. Give one outcome exactly one verb.

### 6. The "despite challenges" closer

Bad: "Despite several challenges encountered during the testing phase, the team successfully completed all planned test activities. Moving forward, the focus will be on continuous improvement."
Better: "We didn't get to the mobile browser tests this sprint — ran out of time after the checkout regression. Carrying those to next sprint. Everything else is done."

Why: state the gap, the reason for it, and the carry-forward plan — and lose the "despite challenges" framing entirely.

### 7. Vague stakeholder updates

Bad: "Quality metrics continue to trend positively. The team is aligned on priorities and committed to delivering a high-quality release."
Better: "The release looks fine. 4 bugs open, all P2 or lower. The login plus-sign bug (P1) was fixed yesterday. Smoke tests pass on staging."

Why: the reader is trying to make a ship/no-ship call, so lead with that decision and the open blockers.

### 8. PR review comments that say nothing

Bad: "Great work on this implementation! I noticed a few potential areas for improvement that might enhance the overall test coverage and robustness."
Better: "This test only checks the happy path. What happens when the API returns a 429? And the selector `.btn-submit` will break if anyone changes the CSS class — use `getByRole('button', { name: 'Submit' })` instead."

Why: call out the missing scenario and the brittle line, then give the concrete fix.
`getByRole` is Playwright's recommended user-facing locator — favor it over CSS-class selectors.

### 9. Bug report padding (with repro and evidence)

Bad: "While conducting comprehensive regression testing of the user management module, a significant defect was discovered that impacts the core functionality of the system."
Better:
> Deleting a user doesn't revoke their API tokens — they can still call the API after deletion.
> Repro: create a user, mint a token, `DELETE /api/users/{id}`, then `GET /api/me` with that token.
> Returns `200 OK` with the user's data instead of `401 Unauthorized`. Found in the user-management API.

Why: open with the broken behavior itself, then a two-line repro plus the real error/status
code so whoever picks it up can reproduce it in seconds. Cut the passive "was discovered"
and the testing-session preamble.

### 10. The rule-of-three summary

Bad: "This sprint we improved quality, velocity, and confidence. The team demonstrated strong collaboration, technical excellence, and customer focus."
Better: "This sprint we fixed the checkout flakiness (was failing 12% of the time, now <1%) and added E2E coverage for the new export feature."

Why: a tricolon of generic virtues is about the loudest AI tell a sprint summary can have. Swap it for the two things that actually happened.

## How to rewrite

1. **Delete the opening paragraph.** Intros are almost always throat-clearing — cut everything before the first fact that matters.
2. **Put what matters first.** What broke, what's at risk, what someone should do about it — in that order, up top.
3. **Trade categories for specifics.** "Authentication module" becomes "login with plus-sign emails." "Performance degradation" becomes "dashboard takes 8s to load (was 2)." "Several edge cases" becomes "empty cart, expired coupon, currency mismatch."
4. **Strip the filler.** Every phrase listed in `references/filler-blocklist.md` goes — "It is worth noting that," "Moving forward," "Despite challenges," "The team is committed to," "Stakeholders can feel confident," and the rest of the list.
5. **Add value, not invention.** What's the next action? What's the downside of not taking it? How sure are you — and it's fine to admit "I'm not sure this is stable yet"? Where the source lacks a number to back a claim, say the number's missing rather than inventing one.
6. **Say it out loud first.** Anything you wouldn't actually say in standup needs another pass.

## Format-specific guidance

| Format | Lead with | Skip | Also include |
|---|---|---|---|
| **Test execution summary** | Failure count, where they are, whether they're new | Total counts, pass % (unless asked) | What's not covered yet, what to watch |
| **Bug report** | What breaks, how to reproduce it, who's affected | "while performing comprehensive testing…" | Actual error message, status code, screenshot, or console output |
| **Sprint update (stakeholders)** | Release readiness (yes/no/conditional), open blockers | Methodology, process, team-morale lines | What you'd want to know if you were deciding whether to ship |
| **Slack message** | The result in 2-3 lines + a link | Greetings, "I wanted to share…" | — |
| **Postmortem** | What broke, when, how long, who was affected | "This postmortem aims to provide…" | An honest account of what you missed and why |

Example for Slack — Bad: "Hello team, I wanted to share the results of our latest test execution…"
Better: "E2E run passed. 2 flaky failures (both dashboard timeout, known issue). Full report: [link]"

## Anti-Patterns

- **Manufacturing the specifics you were asked to add.** Turning a vague draft into a precise-sounding one by inventing a percentage, an incident count, or a repro that was never in the source. This violates the fact-preservation guarantee — flag the missing detail instead of filling it in.
- **Opening with "Test execution was completed successfully" when things failed.** An opener that contradicts the body. Lead with the failures instead.
- **Reaching for "potential impact" instead of the real one.** State the actual impact if you know it; say it's unmeasured if you don't. "Potential" is a hedge that avoids committing to either.
- **Writing "the team is aligned," ever.** It's a pure AI tell that conveys nothing.
- **Stretching 3 bullets into 12 by rewording the same point.** Synonym cycling — one outcome deserves one statement, not several.
- **Ending on empty optimism.** "Moving forward, the focus will be on continuous improvement" adds nothing — cut it.
- **Hiding behind passive voice to avoid naming what broke.** "An issue was identified" leaves out the subject. State what broke and where.
- **Opening a bug report with the testing session instead of the bug.** Skip "while conducting regression testing of the module" — start with the broken behavior itself.

## Verification

Core Principle 4's fact-preservation promise is the claim that actually matters here, so
confirm it mechanically, starting with the smallest check:

1. **Numbers and severities didn't drift.** Pull every figure out of both the input and the
   output and diff the two sets. Everything in the output set needs to already exist in the
   input set — anything extra is a fabricated fact:
   ```bash
   grep -oE '[0-9]+(\.[0-9]+)?%?|P[0-3]|[0-9]{3}' input.md  | sort -u > /tmp/in.txt
   grep -oE '[0-9]+(\.[0-9]+)?%?|P[0-3]|[0-9]{3}' output.md | sort -u > /tmp/out.txt
   comm -13 /tmp/in.txt /tmp/out.txt   # must be empty (allow only obvious rounding, e.g. 97.4 -> 97)
   ```
2. **Zero hits against the filler blocklist.** Pull the "Grep-ready regex" line out of
   `references/filler-blocklist.md`, drop it into `BLOCKLIST`, and grep the output with it:
   ```bash
   BLOCKLIST='it('\''?s)? worth noting|moving forward|in conclusion|despite (several )?challenges|the team is (committed|aligned)|stakeholders can feel confident'
   grep -iE "$BLOCKLIST" output.md   # expect no output; extend BLOCKLIST with the full regex from the reference
   ```
   A hit means an AI tell survived — rewrite that line.
3. **A second pass for cleanliness.** Feed the output through the global `humanizer` (or
   `avoid-ai-writing`) skill in detect mode; it should come back clean of em-dash overuse,
   tricolons, and vague attribution. Anything QA-specific it catches that this skill missed
   should also get fixed here.

## Done When

- Every number, severity, error string, and bug description in the output traces back to the input (the `comm -13` diff from Verification step 1 comes back empty, rounding aside).
- The output returns zero matches against the filler blocklist regex (Verification step 2).
- Synonym cycling is gone: each distinct test outcome appears once, never as a "passed / completed without issues / returned positive results" chain.
- The output clears the global humanizer/avoid-ai-writing pass without flags (Verification step 3).
- What ships is the rewritten version, with the original draft archived or discarded rather than delivered alongside it.

## Related Skills

- **`ai-bug-triage`** — Owns bug-report templates and the severity/priority matrix. Triage determines *what* a bug is and how it's classified; this skill takes an already-classified report and fixes its prose.
- **`qa-metrics`** — Covers what's actually worth tracking. Reach for it when a report needs real metrics; this skill then makes sure those metrics carry context instead of reading as vanity numbers.
- **`qa-dashboard`** — Handles dashboard setup and stakeholder report layout; this skill humanizes the narrative sitting alongside the dashboard.
- **`quality-postmortem`** — Owns postmortem structure and root-cause analysis. Build the postmortem there, then humanize its writeup here.

## External Skills

These sit in the global Claude skill set, not in this repo's `skills/` directory:

- **`humanizer`** / **`avoid-ai-writing`** — General-purpose engines for stripping AI-sounding
  prose. When a task calls for both, run the global skill first for language-level cleanup
  (em-dash overuse, tricolons, vague attribution), then this skill for QA-specific structure
  and fact preservation. If you have access to an engineer's actual standup/Slack voice, feed
  a sample into the global humanizer's voice mode so the result sounds like that person rather
  than a generic "human" register.

## Reference Files (in `references/`)

- **filler-blocklist.md** — The copy-paste list of banned filler phrases, the grep-ready
  regex Verification relies on, the synonym-cycling tells, and the passive-voice dodges that
  hide who broke what.
