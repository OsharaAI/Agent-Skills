# Rollout Automation & Verification Commands

The rules for auto-promoting a staged rollout, plus the commands for checking a deploy right after it lands. The reasoning behind these (what to watch between stages, the post-deploy verification timeline) lives in `SKILL.md` — this file is the reference sheet.

## Auto-Promotion Rules

Set explicit criteria for when a rollout stage advances automatically. Every threshold should be expressed **relative to this service's measured baseline**, never as a fixed number — a flat 500ms ceiling is wrong for most APIs and practically begs to be copy-pasted somewhere it doesn't fit. Capture the baseline (trailing 7-day P95, current 5xx rate, whatever applies) before the rollout begins, and compare against that.

```
Promote from canary (1%) to 10% when:
  - 5xx error rate <= baseline + small margin (e.g. not above 1.2x baseline) for 15 minutes
  - P95 latency within tolerance of baseline (e.g. not above 1.2x baseline)
  - No new exception types
  - Zero crash reports

Promote from 10% to 50% when:
  - 5xx error rate at or below baseline for 1 hour
  - P95 latency within tolerance of baseline
  - Conversion rate within 5% of baseline
  - No customer-reported issues

Promote from 50% to 100% when:
  - 5xx error rate at or below baseline for 2 hours
  - All business metrics within expected range
  - No rollback signals from any monitoring system
```

These promotion ceilings mirror the rollback triggers in `SKILL.md` in reverse (>2x baseline error rate, >3x baseline P95 there): promote while safely under baseline, roll back once you're well past it.

## Verification Commands

Fast checks to run as soon as a deploy finishes:

```bash
# Check application health
curl -s https://your-app.com/health | jq .

# Check response time
curl -o /dev/null -s -w "HTTP %{http_code} in %{time_total}s\n" https://your-app.com

# Check for new errors in the last 15 minutes (Sentry CLI example)
sentry-cli issues list --project your-project --query "firstSeen:>15m"

# Compare error counts (Datadog example)
# Before deploy: note the 5xx count
# After deploy: check if 5xx count increased
```
