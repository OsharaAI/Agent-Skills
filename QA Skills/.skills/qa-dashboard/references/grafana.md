# Grafana reference

Covers the CI-to-InfluxDB push script, the panel queries, and a provisioned alert rule for the
">2pp pass-rate drop" alert required by the SKILL's Done When section.

## Data pipeline: from CI into Grafana

```
CI Pipeline Run
  ├── Test results (JUnit XML)
  ├── Coverage report (JSON)
  └── Timing data (JSON)
        │  Parser script (post-test CI step)
        ▼
  Time-series DB (InfluxDB / Prometheus pushgateway)
        ▼
  Grafana queries + panels
```

## Pushing test metrics into InfluxDB

Pay attention to the try/flush guard here: since this script runs under `if: always()` in CI, skipping a
flush inside the `catch` block means any exception mid-loop would discard every point `writePoint` had
already buffered before `close()` runs. The pattern is flush first, then re-throw, so the CI step still
reports the failure.

```typescript
// scripts/push-test-metrics.ts
import { InfluxDB, Point } from "@influxdata/influxdb-client";

interface TestResult {
  name: string;
  suite: string;
  status: "passed" | "failed" | "skipped";
  duration: number;
  retries: number;
}

async function pushMetrics(results: TestResult[], runId: string, branch: string) {
  const client = new InfluxDB({
    url: process.env.INFLUXDB_URL!,
    token: process.env.INFLUXDB_TOKEN!,
  });
  const writeApi = client.getWriteApi("qa", "test-results", "ms");

  try {
    for (const result of results) {
      const point = new Point("test_execution")
        .tag("suite", result.suite)
        .tag("test_name", result.name)
        .tag("status", result.status)
        .tag("branch", branch)
        .tag("run_id", runId)
        .floatField("duration_ms", result.duration)
        .intField("retries", result.retries)
        .intField("passed", result.status === "passed" ? 1 : 0)
        .intField("failed", result.status === "failed" ? 1 : 0);
      writeApi.writePoint(point);
    }

    const total = results.length;
    const passed = results.filter((r) => r.status === "passed").length;
    const failed = results.filter((r) => r.status === "failed").length;
    const avgDuration = results.reduce((sum, r) => sum + r.duration, 0) / total;

    const summary = new Point("test_run_summary")
      .tag("branch", branch)
      .tag("run_id", runId)
      .intField("total", total)
      .intField("passed", passed)
      .intField("failed", failed)
      .floatField("pass_rate", (passed / total) * 100)
      .floatField("avg_duration_ms", avgDuration);
    writeApi.writePoint(summary);
  } catch (err) {
    await writeApi.flush();   // don't lose buffered points on a mid-loop throw
    throw err;
  } finally {
    await writeApi.close();
  }
}
```

```yaml
# GitHub Actions: push metrics after tests
- name: Push test metrics to Grafana
  if: always()
  env:
    INFLUXDB_URL: ${{ secrets.INFLUXDB_URL }}
    INFLUXDB_TOKEN: ${{ secrets.INFLUXDB_TOKEN }}
  run: |
    npx tsx scripts/push-test-metrics.ts \
      --results-file test-results/results.json \
      --run-id "${{ github.run_id }}" \
      --branch "${{ github.head_ref || github.ref_name }}"
```

## Recommended panels (InfluxQL)

**Panel 1 — Pass Rate Trend (time series).** This also serves as the "is main ready to release?" signal,
turning green once it's above 99%.

```sql
SELECT mean("pass_rate") FROM "test_run_summary"
WHERE "branch" = 'main' GROUP BY time(1d)
-- Visualization: Time series, thresholds at 95% (yellow) and 99% (green)
```

**Panel 2 — Release Readiness (stat / gauge).** This is the composite "can we ship?" panel — it reduces
the latest main-branch pass rate down to one number, colored according to the release gate:

```sql
SELECT last("pass_rate") FROM "test_run_summary" WHERE "branch" = 'main'
-- Visualization: Stat panel. Thresholds: red < 95, yellow 95–99, green >= 99
-- Pair with a coverage stat (>= 80) for a two-tile "ready to release" row.
```

**Panel 3 — Flakiness Top 10 (table).**

```sql
SELECT "test_name", count("retries") AS retry_count FROM "test_execution"
WHERE "retries" > 0 AND time > now() - 14d
GROUP BY "test_name" ORDER BY retry_count DESC LIMIT 10
-- Visualization: Table with sortable columns
```

Beyond these, consider: **Test Duration Distribution** (a histogram bucketed at 1s/5s/10s/30s/60s),
**Coverage Trend** (branch coverage plotted as a line over time), and **CI Duration Trend** (with a
target line drawn at 600s).

## Alerting — the provisioned ">2pp pass-rate drop in a day" rule

On Grafana 11 and later, alert rules provision as YAML placed under `provisioning/alerting/`. This
particular rule fires whenever main's pass rate today sits more than 2 percentage points under
yesterday's, routing the result to Slack through a contact point — it's the literal implementation of
the Done When requirement, "pass rate drops by more than 2pp in a single day."

```yaml
# provisioning/alerting/pass-rate-drop.yaml
apiVersion: 1
groups:
  - orgId: 1
    name: qa-regressions
    folder: QA
    interval: 1h
    rules:
      - title: Main pass rate dropped >2pp in a day
        condition: drop
        data:
          - refId: today
            relativeTimeRange: { from: 86400, to: 0 }      # last 1d
            datasourceUid: influxdb
            model:
              query: SELECT mean("pass_rate") FROM "test_run_summary" WHERE "branch" = 'main'
          - refId: yesterday
            relativeTimeRange: { from: 172800, to: 86400 }  # the day before
            datasourceUid: influxdb
            model:
              query: SELECT mean("pass_rate") FROM "test_run_summary" WHERE "branch" = 'main'
          - refId: drop
            datasourceUid: __expr__
            model:
              type: math
              expression: $yesterday - $today > 2    # >2 percentage-point drop
        for: 0m
        labels: { severity: warning }
        annotations:
          summary: "main pass rate fell >2pp vs yesterday — investigate before merging"
```

```yaml
# provisioning/alerting/contactpoints.yaml — route the alert to Slack
apiVersion: 1
contactPoints:
  - orgId: 1
    name: qa-slack
    receivers:
      - uid: qa-slack-webhook
        type: slack
        settings:
          url: ${SLACK_WEBHOOK_URL}      # incoming-webhook URL
          title: "{{ .CommonAnnotations.summary }}"
```

A few more alerts worth setting up the same way: pass rate falling below 95% over a 10-minute window,
CI duration exceeding 15 minutes, and coverage dropping by more than 2% within a week — all of these can
route through the same `qa-slack` contact point.
