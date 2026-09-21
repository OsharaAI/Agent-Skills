# Failure Injection — Runnable Code

This file holds the actual implementations — commands, configs, and test code — for injecting each class of failure. For the decision tables covering which failure maps to which tool and use case, see `SKILL.md`.

## Network failures

```bash
# Add latency to all egress on eth0 (200ms ± 50ms here simulates a distant region;
# use 500ms to mirror Starter Experiment 1's "slow database").
tc qdisc add dev eth0 root netem delay 200ms 50ms distribution normal

# Add 5% packet loss
tc qdisc add dev eth0 root netem loss 5%

# Remove the injected fault
tc qdisc del dev eth0 root
```

```yaml
# toxiproxy configuration for database latency.
# `latency` and `jitter` are milliseconds. 500/100 here matches Starter
# Experiment 1 ("add 500ms latency"); use 200/50 to mirror a distant region.
- name: postgres-latency
  listen: 0.0.0.0:15432
  upstream: postgres:5432
  toxics:
    - name: latency
      type: latency
      attributes:
        latency: 500
        jitter: 100
```

## Service failures

```bash
# Kill a Kubernetes pod
kubectl delete pod order-service-abc123 --grace-period=0

# Stress CPU on a specific container (via Chaos Mesh)
# chaos-mesh-cpu-stress.yaml
```

```yaml
# LitmusChaos 3.29.x: pod-delete experiment.
# engineState: active is REQUIRED to start — without it the engine is created
# but never runs. annotationCheck: 'false' targets pods by label, not annotation.
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: order-service-chaos
spec:
  engineState: active
  annotationCheck: 'false'
  appinfo:
    appns: production
    applabel: app=order-service
  chaosServiceAccount: litmus-admin
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: '60'
            - name: CHAOS_INTERVAL
              value: '30'
            - name: FORCE
              value: 'false'
```

## Infrastructure failures

```bash
# Fill disk to trigger disk-full handling
fallocate -l 10G /tmp/fill-disk.dat

# Stress 4 CPU cores for 60 seconds
stress-ng --cpu 4 --timeout 60s

# Consume 2GB of memory
stress-ng --vm 1 --vm-bytes 2G --timeout 60s

# Cleanup
rm /tmp/fill-disk.dat
```

## Dependency failures

```typescript
// Toxiproxy programmatic control for integration tests.
// Named import — toxiproxy-node-client (v4.x) has no default export.
import { Toxiproxy } from 'toxiproxy-node-client';

const toxiproxy = new Toxiproxy('http://localhost:8474');

test('application handles Redis unavailability gracefully', async () => {
  const proxy = await toxiproxy.get('redis');

  // Disable Redis
  await proxy.disable();

  try {
    const response = await fetch('http://localhost:3000/api/products');
    // Should still work, but slower (cache miss, hits database)
    expect(response.ok).toBe(true);
    const data = await response.json();
    expect(data.products.length).toBeGreaterThan(0);

    // Verify degraded performance is within acceptable range
    const latency = parseInt(response.headers.get('x-response-time') ?? '0');
    expect(latency).toBeLessThan(5000); // 5 seconds max without cache
  } finally {
    // Always re-enable
    await proxy.enable();
  }
});
```

## Automated abort / steady-state gating

An abort condition that only lives in a document is a policy, not a safeguard, until some tool actually enforces it. Making the check machine-readable means a flapping experiment shuts itself down with nobody at the keyboard — which is what converts "chaos without monitoring" and "no rollback plan" from things a team merely tries to remember into something the infrastructure guarantees.

```json
// AWS FIS experiment template: a CloudWatch alarm auto-stops the experiment
// the moment error rate breaches threshold. No human in the loop.
"stopConditions": [
  {
    "source": "aws:cloudwatch:alarm",
    "value": "arn:aws:cloudwatch:us-east-1:123456789012:alarm:HighErrorRate"
  }
]
```

The same idea shows up elsewhere:
- **Gremlin** — Health Checks attached to a scenario auto-halt and roll back when
  a monitored metric (a CloudWatch/Datadog/Prometheus check) goes unhealthy.
- **LitmusChaos** — probes (`httpProbe`, `promProbe`, `cmdProbe`) with
  `mode: Continuous` fail the experiment and stop chaos when an SLO breaks.
- **Litmus MCP Server** (Oct 2025) — lets an AI assistant such as Claude list,
  run, and stop experiments against ChaosCenter via natural language; useful for
  driving the abort ("stop the network latency experiment") conversationally.

## Continuous chaos in CI (GameDay-as-code)

Schedule a low-blast-radius experiment to run on a recurring basis during a quiet traffic window, so any regression shows up in CI rather than during peak hours. The probe described above is what makes it reasonably safe to run this unattended.

```yaml
# GitHub Actions: nightly Litmus pod-delete during the 03:00 UTC traffic trough.
on:
  schedule:
    - cron: '0 3 * * *'   # off-peak only; never gate a release on this job
jobs:
  chaos:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: kubectl apply -f chaos/order-service-chaos.yaml   # engineState: active
      - run: kubectl wait --for=condition=complete chaosengine/order-service-chaos --timeout=180s
```
</content>
