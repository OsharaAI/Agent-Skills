---
name: exploratory-testing
description: >-
  Design and execute structured exploratory testing sessions. Covers Session-Based
  Test Management (SBTM), charter writing, heuristic-based exploration (HICCUPS,
  FEW HICCUPS), bug discovery patterns, note-taking templates, and conversion of
  findings to automated tests. Use when: "exploratory testing," "SBTM," "manual testing,"
  "bug hunting," "test charter," "heuristic testing."
  Not for: an AI browser agent autonomously exploring the app from a natural-language
  goal — use agentic-browser-testing. Not for: testing your product's own AI/LLM
  features — use ai-system-testing.
  Related: test-planning, ai-bug-triage, risk-based-testing, agentic-browser-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: strategy
---

<objective>
This skill turns exploratory testing into a repeatable discipline rather than ad-hoc clicking. Because exploration blends learning, designing checks, and running them in the same breath, a tester can pivot the moment the software reveals something unexpected. What follows gives that improvisation a backbone: frameworks that keep the work systematic, reproducible, and easy to write up afterward.
</objective>

---

## Quick Route

Match the situation in front of you to a charter shape, then jump to the matching reference section.

| Situation | Charter pattern | Open in references |
|-----------|-----------------|--------------------|
| **New feature** — learn it, find requirement gaps | "Explore [feature] with various roles/data to discover requirement gaps and unexpected behaviors" | Charter examples + session flow in `session-templates.md`; boundary/"what if" banks in `heuristics-and-automation.md` |
| **Regression** — a change just landed | "Explore [area] after [change] to discover regressions at integration points" | State-transition heuristics in `heuristics-and-automation.md` |
| **Bug investigation** — vague report ("sometimes slow") | "Explore [area] with [reported conditions] to discover exact reproduction steps" | Session flow + session-log template in `session-templates.md`; error-handling heuristics in `heuristics-and-automation.md` |

Complete time allocations for each row appear under **Session Planning by Context** further down.

---

## Discovery Questions

Gather context before you design a session. If `.agents/qa-project-context.md` exists, treat it as your starting point and skip whatever it already answers.

### Target Area

- What feature, module, or flow are you targeting?
- New territory (discovery mode) or something already shipped (regression mode)?
- What changed here most recently?
- Any known trouble spots or prior bug clusters? (`risk-based-testing` has the risk data.)

### Hunches Worth Chasing

- What is your gut telling you might be broken?
- Did the engineer flag anything as tricky or shaky?
- Where does the automated suite go quiet?
- Has this area generated user complaints before?

### Time and Scope

- How much session time do you have? (45-90 minutes tends to work best.)
- Wide survey across the area, or a focused deep dive into one corner?
- Which environments and datasets can you actually use?
- Any particular platforms, browsers, or devices in scope?

### Team Context

- Who built this feature? (Pairing with them while you explore is often very productive.)
- Does anyone on the team have deep domain knowledge here?
- Who needs to see the session report afterward?

---

## Core Principles

### 1. Structure With Room to Wander

This is not "poke around and see what happens." A charter sets the boundaries — target, resources, and the information you're after. Inside that frame, you're free to chase leads, dig into anomalies, and change course when the app surprises you. The charter is what makes it repeatable; the freedom is what makes it find bugs.

### 2. Write It Down While It's Happening

An observation you didn't capture is an observation you don't have. Take notes as you go, not from memory afterward. Log the action, what happened, and whatever question it raised. The session log stands in for a test script as the actual deliverable.

### 3. Heuristics Instead of Scripts

Think of heuristics as lenses, not checklists to clear. HICCUPS and its extended form, FEW HICCUPS (covered below), give you systematic angles for scrutinizing the software — they sharpen the questions you ask and surface things you'd otherwise walk past.

### 4. Keep Sessions Time-Boxed

Bug-finding returns diminish the longer you go. Past roughly 90 minutes, fatigue sets in and effectiveness drops. Cap sessions at 45-90 minutes and debrief right after. A handful of tight sessions beats one long, unfocused marathon.

### 5. A Bug Found Is Only Half the Job

The second half: ask whether an automated test could have caught this. If the answer is yes, go write it. Exploration exists partly to feed the automation pipeline, not just to produce a bug list.

---

## Session-Based Test Management (SBTM)

SBTM wraps exploratory testing in a management structure: the charter states intent, the session is the unit of work, and the debrief is where learning gets extracted.

> **Canonical references:**
> - SBTM PDF (Jon Bach / James Bach, satisfice.com) — https://www.satisfice.com/download/session-based-test-management
> - *Taking Testing Seriously: The Rapid Software Testing Approach* (Bach & Bolton, Wiley 2025) — current authoritative RST/SBTM book.
> - HTSM v6.3 (Bach, last updated Dec 2024) — emphasizes state-based testing and boundary heuristics. Pair with HICCUPS below.

### Charter Template

State the charter as a one-line mission, in this shape:

```
Explore [target]
  with [resources]
  to discover [information]
```

**Charter quality checklist:**
- The target is precise enough to steer exploration — "explore the app" doesn't count
- Resources call out concrete tools, data, or conditions to use
- The information goal describes what you want to learn, not a conclusion you're trying to confirm
- One session can realistically cover the charter within 45-90 minutes

`references/session-templates.md` has five fully worked charter examples spanning checkout, profile, search, data export, and multi-user collaboration.

### Session Setup, Flow, and Debrief

The complete session lifecycle — setup steps before you begin, the environment-prep checklist, minute-by-minute flow, what to do the moment something interesting shows up, and the structured debrief template — lives in `references/session-templates.md`. Open it at session start and leave it visible throughout.

Timing guardrails worth memorizing even without the reference open: orient and survey during the first 15 minutes, spend roughly 40 minutes exploring, then close out and debrief. Debrief every time, solo sessions included.

---

## Bug Discovery Heuristics

Heuristics are mental models for guiding exploration — lenses to look through, not lists to exhaust.

### HICCUPS

Seven oracles packed into one mnemonic. An oracle is simply a principle for recognizing when something's wrong.

| Letter | Oracle | What to Check | Example Questions |
|--------|--------|--------------|-------------------|
| **H** | History | Does current behavior match past behavior? | Did this work in the last release? Has the behavior changed subtly? |
| **I** | Image | Does it match the product's brand and quality bar? | Does this look polished? Does it feel consistent with the rest of the app? |
| **C** | Comparable | How do similar products handle this? | What does the competitor do here? What is the industry standard? |
| **C** | Claims | Does it match what was promised? | Does it match the spec? The marketing page? The tooltip text? |
| **U** | User expectations | Would a real user find this confusing or frustrating? | Would my mother understand this? Would a power user be annoyed by this? |
| **P** | Product | Is it consistent with other parts of the same product? | Does this error message match the style of other error messages? |
| **S** | Standards | Does it comply with applicable standards? | WCAG for accessibility, RFC for protocols, GDPR for data handling? |

### FEW HICCUPS (Extended)

Three more lenses layered onto the base set:

| Letter | Oracle | What to Check |
|--------|--------|--------------|
| **F** | Familiarity | Would a first-time user understand this without help? |
| **E** | Explainability | Can you explain the behavior to someone else? If not, it might be a bug. |
| **W** | World | Does it work in the real world? (different locales, time zones, network conditions, screen sizes) |

### Heuristic Test-Idea Banks

Detailed lists of concrete test ideas — boundary, state-transition, error-handling, "what if" — sit in `references/heuristics-and-automation.md`. Pull them up when you want specific prompts to work from:

- **Boundary heuristics** — numeric, string, time, and collection boundaries (zero/one/many, max±1, Unicode, DST, page-size edges).
- **State transition heuristics** — skipping steps, going backward, interrupting, repeating, concurrent transitions, post-error state.
- **Error handling heuristics** — network loss, malformed responses, rate limits, expired sessions, invalid uploads.
- **"What if" scenarios** — back button, duplicate tabs, ad blockers, pasted formatting, accessibility features, unfamiliar locales, hostile users.

---

## Note-Taking Template

Log observations in real time using a session log. The table format for the log, plus the tag set (BUG, QUESTION, IDEA, RISK, NOTE) for each observation, live in `references/session-templates.md`. Tag consistently as you go so the debrief can sort findings without a full re-read of the log.

---

## When to Explore vs. When to Automate

Not everything belongs in exploratory testing, and not everything belongs in automation. Use this framework to decide:

### Explore When:

- The feature is new and requirements are still evolving
- You are investigating a vague bug report ("sometimes it is slow")
- You want to assess the overall quality of an area (quality survey)
- The area is complex with many state combinations that are hard to script
- You need to evaluate subjective qualities (UX, intuitiveness, visual polish)
- You are trying to find bugs, not confirm behavior

### Automate When:

- The behavior is stable and well-defined
- The test needs to run on every commit/PR (regression)
- The scenario has a clear pass/fail criterion
- The test involves data combinations that are tedious to explore manually
- You need cross-browser or cross-device coverage at scale
- You found a bug through exploration and want to prevent regression

### The Exploration-to-Automation Pipeline

A reproducible bug found through exploration should graduate into an automated regression test — otherwise every future session wastes time re-verifying old bugs instead of covering new ground. See `references/heuristics-and-automation.md` for the pipeline diagram, the conversion steps, and a worked Playwright regression example (BUG-456 email validation).

When a smoke-style exploratory charter proves stable ("does the happy path still hold up at all"), promote it in two stages rather than jumping straight to a script: first, hand it to `agentic-browser-testing` as a natural-language goal so an agent confirms the flow's stability without any code; only once that stabilized flow has earned a maintained selector should it become a scripted `playwright-automation` test.

---

## Session Planning by Context

| Context | Focus | Charter Pattern | Time Split |
|---------|-------|----------------|-----------|
| **New feature** | Learning, requirement gaps, UX | "Explore [feature] with various roles/data to discover requirement gaps and unexpected behaviors" | 15 min orient + 40 min heuristics + 20 min boundaries/errors + 15 min document |
| **Regression** | Changes and their side effects | "Explore [area] after [change] to discover regressions at integration points" | 10 min review diff + 20 min changed area + 20 min integrations + 15 min smoke + 15 min document |
| **Bug investigation** | Reproducing and minimizing | "Explore [area] with [reported conditions] to discover exact reproduction steps" | 10 min read report + 15 min reproduce + 20 min minimize + 15 min related areas + 15 min document |

---

## Assisted Exploration (LLM as Companion, Not Replacement)

An LLM can sit in a session as oracle and idea generator while the critical thinking stays with you. This lines up with the testing-vs-checking distinction that Bach & Bolton draw in *Taking Testing Seriously* (Wiley 2025): the LLM is well-suited to *checking* — does this match a known reference? — but *testing*, the human judgment about what's worth exploring and what actually counts as a problem, has to remain yours. Used well, it widens your charter's coverage; used carelessly, it swaps your judgment for confident-sounding fabrication.

**How to use an LLM during a session:**

- **As an idea generator before the session.** Hand it the charter and ask for ten edge cases the heuristics might not surface. Pick a few worth trying and drop the rest — most will be generic or made up.
- **As an oracle for "is this actually correct?" mid-session.** When something looks off, have the agent pull up the relevant spec, API doc, or standard. Never take its answer at face value without checking the source it names.
- **As a fact-checker on findings, never as the report writer.** You write the bug report; let the LLM review it for clarity. Flip that order — LLM drafts, you edit — and you get template-shaped write-ups stripped of the specific details a human actually noticed.
- **For gap-spotting during debrief.** Ask it: "given these notes, what charter should come next?"

**The productivity-paradox warning:** AI assistance can make a tester's output *appear* faster while quietly eroding the critical thinking that made the work valuable in the first place. (Michael Bolton has made this point in DevelopSense talks and posts — treat it as a working principle rather than a citation.) If your debrief notes start reading like LLM output, the LLM has taken the wheel — stop and run the next session unassisted.

**What never to delegate to an LLM:**

- Choosing what to explore. The charter has to come from your own read on risk and stakeholder concerns.
- Deciding whether something is a bug. "The model says it looks fine" is not a debrief.
- Writing the testing narrative. The specific, situated detail is the entire point of exploratory testing — generic LLM prose is its opposite.

For testing AI features themselves (not just using AI to test), see `ai-system-testing`.

---

## Tester Roles in Modern Teams

Useful vocabulary for staffing conversations and self-positioning. Treat these as common industry archetypes, not a formal taxonomy:

- **Embedded testers** — testers woven into delivery teams end-to-end, part of the development conversation rather than a separate downstream gate. The dominant model on cross-functional teams today.
- **Specialist testers** — deep expertise in one domain (security, accessibility, performance), brought in across multiple teams as needed.
- **Coach testers** — senior testers who teach the craft — heuristics, charter writing, exploratory thinking — to developers and junior testers, and rarely run end-to-end tests themselves.

If your organization is shifting toward embedded testers, exploratory testing is among the highest-leverage skills to showcase — developers struggle to pick it up without coaching, and it's where a testing mindset is most visible.

For background on the testing-vs-checking distinction and AI's role, see "What Is Testing? A Conversation with Bach and Bolton" (DevelopSense, Feb 2026): https://developsense.com/blog/2026/02/what-is-testing-a-conversation-with-james-bach-and-michael-bolton

---

## Anti-Patterns

### Unchartered Exploration

Poking around with no charter. "I'll just click through and see what turns up" gives inconsistent results, can't be repeated, and resists any meaningful debrief. Write a charter every time, even a one-liner.

### Sessions That Run Too Long

Stretching exploration to three hours. Bug-finding effectiveness falls off sharply past 90 minutes — fatigue makes testers miss things and abandon promising leads. Split long testing efforts into several 60-90 minute sessions with breaks in between.

### Skipping Notes Mid-Session

Trusting memory to reconstruct the session afterward. By the end, half the observations have evaporated and the rest are fuzzy. Capture notes in real time with the template described above.

### Only Walking the Happy Path

Using exploratory time solely to confirm things work. That just duplicates what the automated suite already covers. Exploratory testing earns its keep by finding problems in the paths nobody scripted — lean on the heuristics to push into uncomfortable corners.

### Never Converting Findings to Automation

Rediscovering the same bug by hand release after release because no one wrote a regression test for it. Every reproducible bug from exploration should become an automated test — keep the exploration-to-automation pipeline actually running.

### Dismissing Exploration as "Not Real Testing"

Treating exploratory work as less rigorous than scripted testing. SBTM — with its charters, session logs, and debriefs — produces testing that's documented and accountable. The format differs from a test script, but the rigor matches it.

---

## Verification

Confirm the session left behind real, accountable artifacts — not just a vague sense that "it got tested." Check from smallest to largest:

- **Each charter is a genuine charter:** every session has a written `Explore [target] with [resources] to discover [information]` line, and the target is more specific than "the app." No charter line means unchartered exploration, not SBTM.
- **The session log has timestamps and tags:** open it and confirm each observation carries a time column and a tag (BUG, QUESTION, IDEA, RISK, NOTE). A wall of untimed, untagged prose can't be debriefed.
- **Every filed bug traces back to a charter and actually reproduces:** for each bug ID, walk its reproduction steps in a clean environment and confirm it still happens. If you can't reproduce it, it's a note, not a filed defect.
- **Converted regression tests genuinely run red-then-green:** for any exploratory finding turned into automation, run the new test against the buggy build (`npx playwright test path/to/spec` should fail) and against the fix (should pass). A test that's never been seen failing hasn't proven it guards the bug.
- **Coverage is reported honestly:** the debrief marks each charter area covered, partial, or unexplored. Watch for "100% covered" sitting above a list of unexplored areas — that's the gap to catch.

## Done When

- Session charters are written for each target area, each following the "Explore [target] with [resources] to discover [information]" pattern
- All planned sessions have been executed and debriefed using the debrief template, with each charter area marked covered, partial, or unexplored
- Every bug found during sessions is logged with a reference to the originating charter and reproduction steps
- Session logs exist with time-stamped observations tagged as BUG, QUESTION, IDEA, RISK, or NOTE
- A findings summary captures total session count, bugs filed (by severity), test ideas identified, and follow-up sessions scheduled or explicitly deferred

## Reference Files (in `references/`)

- **session-templates.md** — Charter examples, environment-prep checklist, session-flow timings, debrief template, and the note-taking session-log format.
- **heuristics-and-automation.md** — Boundary/state/error/"what if" heuristic test-idea banks, the exploration-to-automation pipeline diagram, and a worked Playwright regression example.

## Related Skills

- **agentic-browser-testing** -- The automated cousin: a browser agent explores the app from a natural-language goal with no script. Use it for unattended exploratory smoke; use exploratory-testing for human, charter-driven SBTM sessions and bug hunting.
- **playwright-automation** -- Where stabilized exploratory findings graduate into maintained, deterministic regression tests.
- **test-planning** -- Sprint test plans allocate time for exploratory sessions and reference charters.
- **risk-based-testing** -- Risk assessment identifies which areas deserve exploratory attention.
- **test-reliability** -- Flaky or unreliable areas identified through exploration feed into test reliability improvements.
- **qa-metrics** -- Track exploratory session counts, bug discovery rates, and charter coverage as QA metrics.
- **qa-project-context** -- The project context file identifies known risk areas and previous bug clusters that guide charter writing.
</content>
