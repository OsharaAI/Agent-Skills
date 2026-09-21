# Release & Rollback Announcement Templates

Ready-to-fill skeletons for announcing a release or a rollback. For guidance on *when* to send each one, and the reasoning behind a rollback call, see `SKILL.md` — this file only holds the templates themselves.

## Release Announcement

```
Subject: [Release] v{version} — {date}

Status: DEPLOYING / DEPLOYED / ROLLED BACK

Changes:
- {Summary of changes, 3-5 bullet points}

Risk Level: LOW / MEDIUM / HIGH
Rollback Plan: {Revert deploy / Disable feature flag / etc.}
On-Call: {Name, contact}

Monitoring Dashboard: {link}
Release Notes: {link}
```

## Rollback Announcement

```
Subject: [Rollback] v{version} — {date} {time}

Status: ROLLED BACK

Reason: {Brief description of the issue}
Impact: {Who was affected, for how long}
Current State: Running previous version v{prev_version}

Next Steps:
- Root cause investigation: {owner}
- Fix ETA: {estimate or "investigating"}
- Re-release plan: {TBD after investigation}
```
