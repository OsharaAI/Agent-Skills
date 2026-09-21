---
name: chaos-engineering
description: >-
  Validate system resilience through controlled fault injection. Covers hypothesis-driven
  chaos experiments, failure injection types (network, service, infrastructure, dependency),
  LitmusChaos/Chaos Mesh/AWS FIS/Gremlin/toxiproxy tooling, automated abort gating, game day
  planning, and progressive chaos adoption. Use when: "chaos engineering," "fault injection,"
  "resilience test," "game day," "failure recovery," "system reliability," "blast radius."
  Not for: safe rollout flags/canary/dark launch during a release — use testing-in-production;
  designing new tests from production telemetry — use observability-driven-testing.
  Related: testing-in-production, observability-driven-testing, performance-testing, release-readiness, test-environments.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: knowledge
---

<objective>
Chaos engineering builds confidence in a system's ability to survive turbulent conditions by deliberately experimenting on it. It is not random destruction: every experiment starts from a hypothesis and runs under control, surfacing weaknesses before they become outages. A retry mechanism that looks fine in a demo can silently double-charge customers the moment the payment API times out — you only find that out by injecting the timeout and watching what happens.
</objective>

## Quick Route

| Situation | Go to |
|-----------|-------|
| First experiment ever, team is new | Starting Small → First Three Experiments |
| Designing one experiment | Chaos Experiment Workflow (5 steps) |
| Picking a tool for your environment | Tools → Choosing a tool decision tree |
| Running a team session | Game Day Planning |
| Need runnable injection commands/configs | `references/fault-injection.md` |
| Want the abort to fire without a human | `references/fault-injection.md` → Automated abort |

---

## Discovery Questions

Check `.agents/qa-project-context.md` first. If it exists, treat it as prior answers and skip any question it already covers.

**Environment and readiness:**
- Where will chaos experiments run — pre-production only, production with approval, or never production?
- How mature is the team's monitoring? Can problems be detected as they happen?
- Has the team rehearsed incident response, and is a runbook in place?
- Does chaos engineering have executive sponsorship? (Especially important once production is in scope.)

**Architecture:**
- What does the architecture look like — monolith, microservices, serverless, or a mix?
- Which dependencies are critical (database, cache, message queue, third-party APIs)?
- Are there single points of failure, such as one database or one region with no redundancy?
- What redundancy and failover mechanisms are already in place?

**Current resilience practices:**
- Do services expose health checks, and what do those checks actually verify?
- Is there circuit-breaking, retry logic, or timeout configuration anywhere in the stack?
- When a dependency goes down, does the system degrade gracefully, fail hard, or is that untested?
- Has the team already been surprised by an outage, and what broke?

**Team and culture:**
- Is the team at ease with intentionally breaking things? (Some nervousness is expected and worth addressing directly.)
- Who will champion the practice and own it going forward?
- How aggressive should the rollout be — cautious and incremental, or willing to move fast?

---

## Core Principles

### 1. Hypothesis-driven: define expected behavior before injecting

Every chaos experiment begins with a stated hypothesis in the form "We believe that if [failure X occurs], the system will [respond with behavior Y]." Skip the hypothesis and you're no longer experimenting, just breaking things. A solid hypothesis names the concrete steady-state metrics — error rate, latency, throughput — and the range each is allowed to move within.

Example: "We believe that if the primary database becomes unavailable, the application will serve cached data for reads and queue writes for up to 5 minutes without user-visible errors. Blast radius: staging, one service. Steady-state baseline: error rate <0.1%, P95 latency <300ms."

### 2. Start small: one service, controlled blast radius

Don't open with "take down production." A better first move is adding 200ms of latency to one non-critical service in staging. Widen the scope only as tooling and confidence grow.

### 3. Monitoring is a prerequisite

Without real-time visibility into problems, injecting failures is reckless, not scientific — it's an outage you scheduled yourself. Confirm dashboards, alerts, and on-call coverage are functioning before any experiment runs.

### 4. Game days build muscle memory

Automated chaos pipelines are useful, but scheduled game days — where the whole team runs experiments together and practices responding — train the human reflexes that actually matter during a real incident.

---

## Chaos Experiment Workflow

Every experiment goes through the same five stages.

### Step 1: Define steady state hypothesis

Pin down what "normal" looks like in measurable terms, then state what you expect to happen when the failure hits.

```
Experiment: Database failover
Steady state:
  - Error rate: < 0.1%
  - P95 latency: < 300ms
  - Successful orders per minute: > 50

Hypothesis: When the primary database fails over to the replica,
  - Error rate will spike to < 2% for < 30 seconds
  - P95 latency will increase to < 1s for < 60 seconds
  - No orders will be permanently lost
  - The application will recover without manual intervention
```

### Step 2: Introduce the variable

Trigger the failure deliberately, with a bounded scope and a fixed duration.

```
Injection:
  Target: primary database (PostgreSQL)
  Method: block TCP port 5432 on the primary instance
  Scope: single database instance
  Duration: 60 seconds
  Blast radius: staging environment only (first run)

  Abort conditions:
    - Error rate > 10% for > 2 minutes
    - Any data corruption detected
    - Manual abort by experiment owner
```

### Step 3: Observe

While the experiment runs, watch every relevant metric live, with each dashboard assigned to a specific person.

```
Observation assignments:
  - Engineer A: application error rate and latency dashboard
  - Engineer B: database metrics (connections, replication lag, failover status)
  - Engineer C: application logs (search for database connection errors)
  - Engineer D: business metrics (order count, payment processing)
```

### Step 4: Analyze recovery and data integrity

Once it's over, compare what actually happened to what the hypothesis predicted.

```
Analysis checklist:
  - Did the system behave as hypothesized? (Y/N, with details)
  - How long was the impact? (Expected vs. actual duration)
  - Were any errors visible to users?
  - Was any data lost or corrupted?
  - Did monitoring and alerting detect the problem correctly?
  - How long before alerts fired?
  - What was the recovery time?
```

### Step 5: Fix and iterate

Write up what was found, close the resilience gaps, and put a re-run on the calendar to confirm the fix.

```
Findings document:
  Experiment: Database failover (2026-03-20)
  Hypothesis: Confirmed / Partially confirmed / Disproved
  Recovery time: 45s (expected vs actual: expected <10s, actual 45s)
  Data integrity: no rows lost; 3 writes returned 500 instead of queueing

  Findings:
    - Connection pool did not detect stale connections for 45 seconds (expected: <10s)
    - Retry logic worked correctly for read operations
    - Write operations returned 500 errors for 38 seconds (expected: queued)

  Action items (every one has an owner and a due date — no item is deferred):
    - [ ] Configure connection pool health checks — assigned to @maria, due 2026-03-31
    - [ ] Implement write queue with 5-minute buffer — assigned to @dan, due 2026-04-02
    - [ ] Re-run experiment after fixes deployed (re-run scheduled 2026-04-03);
          specific metrics to check on re-run: stale-connection detection <10s,
          zero write 500s, error rate <2%
```

---

## Failure Injection Types

### Network failures

| Failure | Tool | Use Case |
|---------|------|----------|
| Latency injection | tc, toxiproxy, Gremlin | Simulate slow network, distant regions |
| Packet loss | tc netem, Chaos Mesh | Simulate unreliable network |
| DNS failure | iptables, CoreDNS manipulation | Simulate DNS outage |
| Network partition | iptables, Chaos Mesh | Simulate split-brain scenarios |
| Bandwidth restriction | tc, toxiproxy | Simulate congested network |

For runnable `tc netem` latency/packet-loss commands and the toxiproxy latency config, see `references/fault-injection.md`.

### Service failures

| Failure | Method | Use Case |
|---------|--------|----------|
| Service crash | Kill process, pod delete | Simulate unexpected crash |
| Service slowdown | CPU stress, thread pool exhaustion | Simulate overloaded service |
| Error injection | Return 500/503, throw exceptions | Simulate application errors |
| Memory pressure | stress-ng, Chaos Mesh | Simulate memory leaks |

For the `kubectl delete pod` command and the LitmusChaos pod-delete ChaosEngine manifest, see `references/fault-injection.md`.

### Infrastructure failures

| Failure | Method | Use Case |
|---------|--------|----------|
| Disk full | fallocate, dd | Simulate disk exhaustion |
| CPU exhaustion | stress-ng | Simulate CPU saturation |
| Memory exhaustion | stress-ng | Simulate OOM conditions |
| Clock skew | chrony manipulation, timedatectl | Simulate time drift |

For the `fallocate` disk-fill and `stress-ng` CPU/memory commands, see `references/fault-injection.md`.

### Dependency failures

| Failure | Method | Use Case |
|---------|--------|----------|
| API down | toxiproxy, mock server | Simulate third-party outage |
| Database unavailable | block port, kill process | Simulate database outage |
| Cache unavailable | block Redis port | Simulate cache miss storm |
| Message queue full | fill queue, block consumers | Simulate backpressure |

For the programmatic toxiproxy integration test that disables Redis and checks for graceful degradation, see `references/fault-injection.md`.

---

## Tools

| Tool | Type | Best For |
|------|------|----------|
| LitmusChaos (3.29.x) | Kubernetes-native, CNCF | K8s environments, CI/CD integration; ChaosCenter UI; Workflows for GameDay-as-code; MCP Server (Oct 2025) drives experiments from an AI assistant |
| Chaos Mesh (2.8.x) | Kubernetes-native, CNCF | K8s with fine-grained control; eBPF chaos via `bpfki` runtime for kernel-precision faults |
| AWS FIS | Managed AWS service | Cloud-chaos for AWS workloads (EC2, ECS, RDS, EKS); CloudWatch-alarm stop-conditions for auto-abort — primary cloud-native option |
| Gremlin | Managed platform | Teams wanting guided experiments + compliance reporting; Health Checks halt-and-rollback on SLO breach |
| Steadybit | Managed platform | Reliability hub spanning Kubernetes + cloud + on-prem; direct alternative to Gremlin |
| kube-monkey | Open source | Lightweight K8s alternative when Litmus/Chaos Mesh feel heavy |
| Pumba | Open source | Docker-only chaos (containers, networks); pre-K8s and edge |
| toxiproxy | Network proxy, open source | Network fault injection in integration tests |
| tc (traffic control) | Linux kernel | Network latency and packet loss |
| stress-ng | Linux utility | CPU, memory, disk stress testing |
| k6 (+ xk6-disruptor) | Load testing tool | Combined load + chaos scenarios |

**Avoid: Chaos Monkey (Netflix) for new projects — low activity, Spinnaker-only path (as of mid-2026).** The project still runs and hasn't been archived, but it's limited to instance termination and demands a Spinnaker pipeline. For new work, pick Chaos Mesh, LitmusChaos, or AWS FIS instead. (Don't mix this up with SimianArmy, the older repo, which was archived back in 2021.)

### Choosing a tool

```
Decision tree:
  Running on Kubernetes?
    → Cloud-managed AWS workloads: AWS FIS (cloud-native, IAM-integrated)
    → On K8s with sidecar tolerance: Chaos Mesh (eBPF, fine-grained)
    → On K8s wanting workflows + UI: LitmusChaos (ChaosCenter, Workflows)
    → On K8s lightweight: kube-monkey

  Running on plain VMs / Docker?
    → Docker only: Pumba
    → Linux: tc + stress-ng (manual)

  Need network fault injection in integration tests?
    → toxiproxy (lightweight, programmatic API)

  Need to combine load testing with chaos?
    → k6 with xk6-disruptor extension

  Need managed platform with UI and compliance?
    → Gremlin or Steadybit (both commercial)
```

### GameDay-as-code

Rather than one-off events, the 2026 pattern treats chaos runs as scheduled CI jobs: Litmus Workflows, the Steadybit reliability hub, and Gremlin Scenarios each let you express a chaos run as YAML and fire it from CI on a cron schedule. This doesn't replace the human element covered in Game Day Planning below — it just removes the excuse of never finding time to schedule one. A concrete example (a nightly pod-delete job gated to an off-peak window, plus automated abort/stop-condition patterns) lives in `references/fault-injection.md`.

In October 2025, LitmusChaos added an MCP Server that wires an AI assistant like Claude straight into ChaosCenter — so experiments can be listed, run, and stopped in plain language ("run pod-delete on the frontend pods," "stop the network latency experiment") instead of hand-authored YAML. Worth knowing about if your ops workflow already runs through an AI agent.

---

## Game Day Planning

A game day is a scheduled block of time where the team runs chaos experiments together, exercises incident response, and comes away more confident in the system's resilience.

### Preparation checklist

```
2 weeks before:
  - [ ] Define 2-3 experiments to run (don't overload the schedule)
  - [ ] Write hypotheses for each experiment
  - [ ] Get approval from engineering leadership and affected teams
  - [ ] Notify support team and stakeholders
  - [ ] Verify monitoring and alerting are working
  - [ ] Identify rollback procedures for each experiment
  - [ ] Schedule 3-4 hour block (experiments + analysis + retro)

1 day before:
  - [ ] Confirm all participants and their roles
  - [ ] Test that fault injection tools work in the target environment
  - [ ] Verify rollback procedures work (dry run)
  - [ ] Prepare dashboards and observation assignments
  - [ ] Brief the on-call team
  - [ ] Confirm abort criteria for each experiment
```

### Communication and roles

Three windows of communication matter: before (schedule, scope, who has abort authority), during (a status update every 15 minutes in a dedicated channel), and after (a written summary within 24 hours covering findings and action items).

Each experiment needs assigned roles: an **experiment owner** who runs it and makes the call to abort, **observers** watching application metrics, infrastructure metrics, logs, and user experience respectively, and a **scribe** capturing the timeline and key decisions as they happen.

### Post-game retrospective

Per experiment, ask: was the hypothesis confirmed, what surprised the team, and what action items came out of it? At the process level, ask whether monitoring caught the problem, whether alerts actually fired, and whether the team was comfortable with how big the blast radius was. Wrap up by assigning owners and due dates to every action item, and pick a date for the next game day.

---

## Starting Small: First Three Experiments

Teams new to this should begin with these three experiments, run in a pre-production environment.

### Experiment 1: Slow database

**Why first:** slow databases are the most common source of user-facing sluggishness, and this experiment is simple to set up and simple to reverse.

```
Hypothesis: When database latency increases by 500ms, the application
will remain functional with response times under 3 seconds.

Injection: Add 500ms latency to the database connection using toxiproxy.
Duration: 5 minutes.
Environment: staging.

What to observe:
  - Application response times (should increase by ~500ms, not 10x)
  - Connection pool behavior (should not exhaust connections)
  - Timeout handling (requests should not hang indefinitely)
  - Circuit breaker activation (if implemented)
  - Cache effectiveness (cached reads should be unaffected)
```

### Experiment 2: Third-party API returns 500s

**Why second:** external dependencies fail all the time in the real world, yet how the application copes with those failures often goes untested.

```
Hypothesis: When the payment provider returns 500 errors, the
application will show a user-friendly error message and allow
retry without duplicate charges.

Injection: Configure mock/proxy to return 500 for payment API calls.
Duration: 10 minutes.
Environment: staging.

What to observe:
  - Error message quality (user-friendly, not stack traces)
  - Retry behavior (does the application retry? How many times?)
  - Idempotency (retries don't create duplicate transactions)
  - Fallback (is there an alternative payment path?)
  - Monitoring (does the payment failure show up in alerts?)
```

### Experiment 3: Cache unavailable

**Why third:** losing the cache can trigger a "thundering herd," where traffic slams straight into the database all at once and cascades into further failures.

```
Hypothesis: When Redis becomes unavailable, the application will fall
back to direct database queries with degraded but functional performance.

Injection: Block Redis port using toxiproxy or iptables.
Duration: 5 minutes.
Environment: staging.

What to observe:
  - Database query volume (should increase but not overwhelm)
  - Response times (should increase but remain under 5 seconds)
  - Error rate (cache miss should not cause errors)
  - Connection pool (database connections should not exhaust)
  - Recovery (when cache returns, does the application resume normal behavior?)
```

---

## Anti-Patterns

### Chaos without monitoring

Breaking things without any way to observe the fallout isn't chaos engineering — it's just sabotage with extra steps, and you'll only learn something went wrong once a customer complains.

**Fix:** Before running anything, confirm you can watch error rates, latency, throughput, and dependency health as they happen. If you can't, fix monitoring before you touch fault injection. Better still, wire the monitor directly into the experiment so it aborts itself on a threshold breach — AWS FIS CloudWatch stop-conditions, Gremlin Health Checks, or a Litmus `promProbe` set to `mode: Continuous` (details in `references/fault-injection.md`).

### Starting too big

Don't open with "kill the production database." Jumping to high-impact experiments before the team has any reps with low-impact ones just generates anxiety — and sometimes a real outage.

**Fix:** Stay in staging first. Target non-critical services first. Favor reversible faults like latency over anything destructive like data corruption. Build confidence step by step, and only move to production once several staging runs have gone well.

### No rollback plan

"It's only a 60-second experiment, we don't need a rollback plan" — right up until the injection tool itself crashes and the fault never clears, turning what should've been a 5-minute `tc` latency test into a 2-hour outage.

**Fix:** Every experiment needs a documented rollback that can be executed in under 30 seconds. Test that rollback before the experiment starts, and keep a second person on standby to abort if the owner can't. Where possible, lean on a tool-enforced stop-condition rather than a human's finger on the switch (see Automated abort in `references/fault-injection.md`), and choose injections that self-terminate on a timeout (`stress-ng --timeout`, Litmus `TOTAL_CHAOS_DURATION`) so the fault clears even if no one's watching.

### Chaos in production without approval

Running production experiments without documented sign-off from engineering leadership and the teams affected is a fast way to burn trust — and careers.

**Fix:** Before touching production, get explicit written approval from engineering leadership; notify affected teams and brief both on-call and support; publish the scope, duration, and abort criteria with a named abort authority; and keep the blast radius as narrow as it can possibly be. Prove it out in staging first — skipping any of these steps is what turns a controlled experiment into a real incident.

### Running chaos experiments during incidents

Injecting new failures into a system that's already struggling only muddies diagnosis and drags the outage out longer.

**Fix:** If the system isn't in a steady state, cancel or delay the experiment. Check for open incidents before starting one, and if an unrelated incident breaks out mid-experiment, abort immediately.

### No follow-through on findings

The experiment shows the circuit breaker doesn't actually work. The team says "huh, interesting" and moves on. Nothing gets fixed. The next real outage hits the exact same failure mode.

**Fix:** Turn every finding into a ticket with an owner and a due date, and schedule a re-run to confirm the fix landed. Track this backlog alongside real production incident action items — don't let it live somewhere separate and forgotten.

---

## Verification

Before trusting any live experiment, prove the safety net actually works — an abort path you've never triggered is just a guess, not a control. Check from smallest to largest:

1. **Inject and reverse in staging.** Run the lowest-blast-radius injection (e.g. `tc qdisc add dev eth0 root netem delay 200ms`) against one staging service, confirm it shows up on the steady-state dashboard, then run the documented rollback (`tc qdisc del dev eth0 root`) and confirm metrics return to baseline. Time the rollback — it must complete inside its stated window (under 30s).
2. **Trip the automated abort.** Push the monitored metric past its threshold (force error rate over the stop-condition) on an experiment wired to AWS FIS CloudWatch stop-conditions, a Gremlin Health Check, or a Litmus `promProbe` in `mode: Continuous`. Confirm it halts on its own with zero human intervention. If it doesn't fire, treat the abort as unverified (see `references/fault-injection.md`).
3. **Confirm the self-clearing timeout.** Kick off a bounded injection (`stress-ng --cpu 4 --timeout 60s`, or Litmus `TOTAL_CHAOS_DURATION: '60'`) and step away. Confirm the fault clears on its own at the deadline even with nobody aborting it.
4. **Confirm the findings loop closes.** After a staging run, verify a findings doc exists with baseline-vs-actual numbers and that every gap became a tracked ticket with an owner — the write-up is the deliverable, not the injection itself.

If any of steps 1–3 can't be demonstrated in staging, the experiment isn't ready to move toward production.

---

## Done When

- Every experiment has a written hypothesis ("We believe that if [failure X], the system will [expected behavior Y]") recorded before any fault is injected
- Blast radius is explicitly bounded — target scope, duration, and abort conditions are written in the experiment record, and no experiment runs in production before at least one passing run of the same experiment in staging
- A steady-state snapshot (dashboard link or the actual baseline metric values) is attached to each experiment record, captured immediately before injection
- A findings doc exists per experiment with baseline-vs-actual numbers, recovery time, and an explicit data-integrity check (lost/corrupted: yes/no)
- Each weakness found has a tracked ticket with a named owner, a due date, and a scheduled re-run of the same experiment to verify the fix

## Reference Files (in `references/`)

- **fault-injection.md** — Runnable commands, configs, and test code for injecting each failure class: `tc netem` and toxiproxy network faults, `kubectl`/LitmusChaos service faults (ChaosEngine with `engineState: active`), `fallocate`/`stress-ng` infrastructure faults, the programmatic toxiproxy dependency-failure test, plus automated abort / stop-condition examples (AWS FIS, Gremlin, Litmus probes, Litmus MCP) and a cron-gated continuous-chaos CI job.

## Related Skills

- **testing-in-production** — for safe-rollout mechanics *during* a release (feature flags, canary, dark launch). Chaos engineering deliberately breaks things to find weaknesses; testing-in-production controls exposure so a breakage stays contained. Go there for the rollout, here for the fault injection.
- **observability-driven-testing** — when production telemetry (traces, logs, error patterns) is the *input* that tells you which tests or experiments to design. It feeds the hypothesis; chaos engineering then proves or disproves it. Observability is also a hard prerequisite for safe chaos.
- **performance-testing** — load testing complements chaos; combine load + fault for realistic failure scenarios (see k6 + xk6-disruptor).
- **release-readiness** — chaos experiment results feed into go/no-go release confidence assessments.
- **test-environments** — pre-production environments are the safe starting point for chaos experiments.
- **qa-metrics** — chaos experiment results (recovery time, error impact) are quality metrics worth tracking.
</content>
