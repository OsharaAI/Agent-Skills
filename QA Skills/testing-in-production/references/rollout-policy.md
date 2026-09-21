# Rollout Policy and Rollback Config

The full policy YAML behind progressive rollouts — machine-checkable promotion criteria
and automatic-rollback triggers. `SKILL.md` holds the reasoning, the canary-stage table,
and the guardrail-metric table; this file is just the policy itself. Treat these as
vendor-neutral shapes to adapt into Argo Rollouts `AnalysisTemplate`, Flagger
`MetricTemplate`, or whatever guarded-rollout config your flag platform provides.

## Criteria for automated promotion

Stage advancement should hinge on conditions a machine can evaluate. A human can still
override, but that should be the exception rather than the rule.

```yaml
# rollout-policy.yaml
canary_to_10_percent:
  hold_duration: 30m
  conditions:
    - metric: error_rate_5xx
      comparison: less_than
      threshold: 0.5%
      window: 15m
    - metric: latency_p95
      comparison: less_than
      threshold: 500ms
      window: 15m
    - metric: crash_rate
      comparison: equals
      threshold: 0
      window: 15m

10_percent_to_50_percent:
  hold_duration: 2h
  conditions:
    - metric: error_rate_5xx
      comparison: less_than
      threshold: 0.5%
      window: 1h
    - metric: latency_p95
      comparison: less_than
      threshold: 500ms
      window: 1h
    - metric: conversion_rate
      comparison: within_percentage
      baseline: pre_deploy_average
      tolerance: 5%
      window: 1h

50_percent_to_100_percent:
  hold_duration: 4h
  conditions:
    - metric: error_rate_5xx
      comparison: less_than
      threshold: 0.3%
      window: 2h
    - metric: all_guardrails
      comparison: passing
      window: 2h
    - metric: customer_reported_issues
      comparison: equals
      threshold: 0
```

## Triggers for automatic rollback

A guardrail breach should trigger rollback on its own — no human approval sits in the
critical path.

```yaml
automatic_rollback:
  - condition: error_rate_5xx > 2x_baseline
    for: 5m
    action: rollback_to_previous
    notify: [oncall-slack, pagerduty]

  - condition: latency_p99 > 3x_baseline
    for: 5m
    action: rollback_to_previous
    notify: [oncall-slack]

  - condition: crash_rate > 0.1%   # mobile: calibrate to user-perceived crash rate
    for: 2m                          # (Play Console Vitals, App Store Connect Crashes,
    action: rollback_to_previous     # iOS Hang Rate / ANR rate) — not raw exception counts
    notify: [oncall-slack, pagerduty, engineering-leads]

  - condition: health_check_failures > 3_consecutive
    action: rollback_immediately
    notify: [oncall-slack, pagerduty]
```

## Error-budget and SLO gates

Simple `2x_baseline` thresholds are good at catching sudden cliffs but blind to slow
burns that still eventually blow through the SLO. That's why promotion and rollback
should also gate on **error-budget burn rate**, not multiplier thresholds alone — this is
the piece that ties the rollout back to standard SRE practice. Use multi-window,
multi-burn-rate alerting: a short window (5m) picks up sharp regressions, a longer one
(1h) picks up a slow, sustained drain. If the canary cohort is burning through budget
faster than the fleet's allowable rate for that window, halt promotion or roll back — even
if the raw error rate still looks fine on its own.

```yaml
slo_gate:
  - condition: budget_burn_rate_5m > 14.4   # ~2% of 30d budget in 1h
    action: rollback_to_previous
    notify: [oncall-slack, pagerduty]
  - condition: budget_burn_rate_1h > 6       # sustained drain
    action: halt_promotion
    notify: [oncall-slack]
```

Base these on the same SLO definitions the service already publishes elsewhere, so the
rollout gate and the on-call alert are never working from a different idea of "healthy."
