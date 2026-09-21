# Quality Postmortem Templates

The two longer, ready-to-copy formats live here: the incident postmortem for P0/P1
events, and the recurring quality retro. Everything else — escaped-bug classification,
5 Whys, effort-estimate solutions — is short enough to stay inline in SKILL.md. These
two aren't, so they get their own file.

---

## Postmortem Template for Quality Incidents

Reach for this when something significant breaks: a P0/P1 production bug, data loss, a
security issue, or an extended outage traced to a code change. Populate every field from
evidence — commit history, deploy logs, the bug tracker — never from memory.

```markdown
# Quality Incident Postmortem: [INCIDENT-ID]

## Summary
[One paragraph: what happened, who was affected, how it was resolved]

## Severity and Impact
- **Severity:** [P0 / P1 / P2]
- **Users affected:** [count or percentage]
- **Duration:** [from detection to resolution]
- **Business impact:** [revenue, reputation, compliance]

## Timeline (all times in UTC)
| Time | Event |
|------|-------|
| HH:MM | [Code change deployed / feature flag enabled] |
| HH:MM | [First user report / monitoring alert] |
| HH:MM | [Incident acknowledged by on-call] |
| HH:MM | [Root cause identified] |
| HH:MM | [Fix deployed / rollback completed] |
| HH:MM | [Incident resolved, monitoring confirms recovery] |

## Root Cause
[Technical description of what went wrong]

## 5 Whys
1. Why did [symptom]? Because [cause 1].
2. Why [cause 1]? Because [cause 2].
3. Why [cause 2]? Because [cause 3].
4. Why [cause 3]? Because [cause 4].
5. Why [cause 4]? Because [root cause].

## What Tests Existed
- [List relevant existing tests and why they did not catch this]

## What Tests Were Missing
- [Specific test scenarios that would have prevented this]

## Detection
- **How was it detected?** [User report / monitoring / internal testing]
- **Could it have been detected earlier?** [Yes/No — how?]
- **Time from deploy to detection:** [duration]

## Prevention Measures

### Immediate (this sprint)
| Action | Owner | Due | Status |
|--------|-------|-----|--------|
| [Write regression test for this specific scenario] | [name] | [date] | [ ] |
| [Add monitoring alert for this error pattern] | [name] | [date] | [ ] |

### Short-term (next 2 sprints)
| Action | Owner | Due | Status |
|--------|-------|-----|--------|
| [Add integration tests for related edge cases] | [name] | [date] | [ ] |
| [Update deployment checklist] | [name] | [date] | [ ] |

### Long-term (this quarter)
| Action | Owner | Due | Status |
|--------|-------|-----|--------|
| [Improve test coverage for entire area] | [name] | [date] | [ ] |
| [Process change to prevent similar gaps] | [name] | [date] | [ ] |

## Lessons Learned
- [What went well in detection and response]
- [What could have been better]
- [What systemic issue does this reveal]
```

If AI SRE tooling produced the initial timeline (Rootly AI SRE, incident.io's
auto-drafted post-mortems), treat that draft as raw input and have the blameless RCA
owner — never the incident commander — write the actual 5 Whys and sign off on the
resulting action items.

---

## Retro Meeting Template

This is the format for the standing quality retrospective, distinct from an
incident-specific postmortem. Run it per-sprint or monthly.

### Agenda (30-60 minutes)

```
Quality Retro: Sprint [N] / [Month Year]
═════════════════════════════════════════

1. Previous Action Items Review (5 min)
   - Review status of action items from last retro
   - Mark completed, carry forward incomplete, escalate blocked

2. Data Review (10 min)
   Present metrics since last retro:
   - Escaped bug count and classification
   - Flaky test rate trend
   - CI pass rate trend
   - Coverage change
   - Test suite duration change
   - Quarantine inventory

3. What Went Well (5 min)
   - Quality wins: bugs caught early, smooth releases, good test coverage
   - Process improvements that paid off

4. What Needs Improvement (10 min)
   - Quality pain points: escaped bugs, flaky tests, slow pipeline, gaps
   - Process friction: review bottlenecks, unclear ownership, tooling issues

5. Root Cause Discussion (10-15 min)
   - Pick the top 1-2 issues from "Needs Improvement"
   - Run 5 Whys or group brainstorming
   - Identify systemic causes

6. Action Items (5-10 min)
   - Define 1-3 specific, assigned, time-bound action items
   - Each item: what, who, when, how to verify
   - Add to team's work tracker with "retro-action" tag

7. Close (2 min)
   - Confirm next retro date
   - Thank participants
```

### Facilitator Notes

- **Have the data ready before the meeting starts.** Don't burn meeting time pulling up
  dashboards live — get metrics into a shared doc beforehand.
- **Hold the timebox.** Left unchecked, quality retros will eat whatever time is
  available. 30 minutes covers a sprint retro; reserve 60 for monthly or
  incident-triggered sessions.
- **Pass facilitation around.** Rotating who runs it — across QA, developers, and tech
  leads — brings in different angles each time.
- **Send a recap inside 24 hours.** Post a summary with the action items to the team
  channel, linked to the actual tracker tickets. That's what tells people the retro
  produced real work, not just conversation.
- **Open the NEXT retro by reviewing these items.** That review is the accountability
  mechanism itself. If items routinely go unfinished, cut how many you commit to or
  shrink their scope.

---

## Escaped Bug Analysis Template

For working through one escaped defect at a time, before there's enough volume to roll
up. Once 10 or more are analyzed, aggregate them using the pattern described in
SKILL.md.

```
Escaped Bug Analysis: [BUG-ID] [Title]
═══════════════════════════════════════

Timeline:
  Introduced:    [commit/PR/date]
  Released:      [release version/date]
  Detected:      [date, by whom — user report, monitoring, internal]
  Resolved:      [date]
  Time to detect: [hours/days]
  Time to fix:    [hours]

Classification:
  Root cause:         [logic error / integration / data / race condition / ...]
  Should-catch level: [unit / integration / E2E / monitoring]
  Prevention:         [add test / improve test / add gate / improve spec / ...]

Existing Coverage:
  Were there tests for this area?    [yes / no / partial]
  If yes, why did they miss it?      [edge case not covered / wrong assertion / ...]
  If no, why not?                    [area not identified as risky / time pressure / ...]

Impact:
  Users affected:    [count or estimate]
  Revenue impact:    [none / minor / significant / critical]
  Brand impact:      [none / minor / significant / critical]

Action Items:
  1. [Action] — Owner: [name] — Due: [date]
  2. [Action] — Owner: [name] — Due: [date]
```
