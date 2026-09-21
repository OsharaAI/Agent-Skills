# Session Templates

Charter examples, setup checklists, session-flow timings, a debrief template, and the note-taking session-log format for SBTM. Guiding principles and quality criteria live in `SKILL.md`.

## Charter Template

A charter is a single-sentence mission statement, shaped like this:

```
Explore [target]
  with [resources]
  to discover [information]
```

**Examples:**

```
Explore the checkout flow
  with multiple payment methods and expired cards
  to discover how the system handles payment failures and edge cases

Explore the user profile page
  with slow network conditions (Chrome DevTools throttling)
  to discover how the UI handles latency, timeouts, and partial loads

Explore the search functionality
  with special characters, Unicode, and SQL injection strings
  to discover input validation gaps and error handling behavior

Explore the data export feature
  with datasets of 0, 1, 1000, and 100000 records
  to discover performance boundaries and data integrity issues

Explore the multi-user collaboration flow
  with two browser sessions logged in as different users
  to discover race conditions, conflict resolution, and real-time sync behavior
```

## Session Setup

**Before the session:**

1. Read the charter and understand the target area
2. Prepare the environment (deploy the right version, seed test data, set up monitoring)
3. Prepare tools (browser DevTools open, screen recorder running if capturing evidence, note-taking template ready)
4. Set a timer for the session duration
5. Clear distractions (close Slack, mute notifications)

**Environment preparation checklist:**

```
[ ] Correct build/version deployed
[ ] Test data seeded (relevant states: empty, typical, large)
[ ] Test accounts ready (roles: admin, standard user, guest)
[ ] DevTools open: Console, Network, Performance tabs
[ ] Screen recorder running (optional but recommended)
[ ] Note-taking template open
[ ] Timer set: ___ minutes
```

## Running the Session

Let the charter guide where you explore. Draw on heuristics (see `references/heuristics-and-automation.md`) as thinking prompts along the way. When a lead pulls you slightly off the charter, follow it — just note that you deviated and why.

**Session flow:**

```
0:00 - 0:05   Orient: Navigate to the target area, understand the current state
0:05 - 0:15   Survey: Perform the happy path to establish baseline behavior
0:15 - 0:55   Explore: Apply heuristics, probe boundaries, follow anomalies
0:55 - 1:00   Wrap up: Review notes, capture final observations
1:00 - 1:15   Debrief: Summarize findings, identify follow-up actions
```

**When something interesting turns up:**

1. Stop and observe -- resist the urge to rush past the anomaly
2. Reproduce it -- can you trigger it again?
3. Vary the conditions -- does it still happen with different data, users, or browsers?
4. Document it -- screenshot, console log, network trace
5. Assess severity -- bug, design question, or just a test idea?
6. Decide: dig in now, or note it and keep exploring?

## Debrief

Run a structured debrief after every session, even when it's just self-reflection for a solo tester.

**Debrief template:**

```
Session Debrief
Charter: [charter text]
Tester: [name]
Duration: [planned] → [actual]
Date: [date]
Build: [version/commit]

Coverage:
  What percentage of the charter was covered? [%]
  What areas were explored that were NOT in the charter?
  What areas in the charter were NOT explored? Why?

Findings:
  Bugs: [count] (list with IDs if filed)
  Issues: [count] (not bugs, but concerns -- performance, UX, design questions)
  Test ideas: [count] (ideas for new automated tests)

Observations:
  What surprised you?
  What was harder than expected?
  What areas need deeper exploration in a follow-up session?

Follow-up Actions:
  [ ] File bug reports for findings
  [ ] Create automated tests for reproducible bugs
  [ ] Schedule follow-up session for unexplored areas
  [ ] Update risk assessment based on findings
```

## Note-Taking Template

Use this during the session to capture observations as they happen.

### Session Log Format

```
Session: [charter summary]
Date: [date]  |  Tester: [name]  |  Build: [version]  |  Duration: [minutes]

| Time  | Action / Input           | Observation                  | Bug? | Follow-up      |
|-------|--------------------------|------------------------------|------|----------------|
| 0:04  | Navigate to /dashboard   | Page loads in 0.9s           | No   |                |
| 0:07  | Create new project       | Happy path works             | No   |                |
| 0:09  | Enter name with 300 chars| Error: "Name too long" ✓     | No   |                |
| 0:12  | Enter name with only tabs| Accepted, project named blank| ?    | Whitespace-only |
|       |                          |                               |      | names should    |
|       |                          |                               |      | be rejected     |
| 0:16  | Rename via drag-drop UI  | Renamed but sort order breaks| No   | Cosmetic, low   |
|       |                          |                               |      | priority        |
| 0:20  | Submit form with no owner| No validation, project saved | YES  | BUG: required   |
|       |                          | with owner=null               |      | field not       |
|       |                          |                               |      | validated       |
| 0:25  | Kill connection mid-save | Spinner forever, no timeout  | YES  | BUG: no timeout |
|       |                          |                               |      | handling        |
```

### Tagging Observations

Apply these tags consistently so post-session analysis is easy:

- **BUG** -- Definite defect, file a report
- **QUESTION** -- Unclear whether this is intended behavior; ask product
- **IDEA** -- Test case idea for automation
- **RISK** -- Potential issue that needs investigation
- **NOTE** -- Interesting observation, not actionable yet
</content>
