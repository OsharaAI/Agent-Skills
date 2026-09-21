---
name: ai-bug-triage
description: >-
  Hybrid fingerprint + LLM pipeline for bug classification, deduplication, and ticket
  generation. Normalizes CI logs, creates stable fingerprints, clusters near-duplicates,
  then uses LLM for severity classification and ticket writing. Includes bug reporting
  templates and severity/priority matrix. Use when: "bug triage," "classify bugs,"
  "failure analysis," "auto-classify," "CI failures," "bug report," "defect template."
  Not for: runtime self-healing of one flaky locator — use test-reliability. Not for:
  designing new tests from production telemetry — use observability-driven-testing.
  Related: qa-metrics, qa-dashboard, ci-cd-integration, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: ai-qa
---

<objective>
This skill combines two approaches for bug classification, deduplication, and ticket generation: deterministic fingerprinting to catch duplicates (a task LLMs handle poorly), and an LLM layer for explanation, severity judgment, and ticket authoring (tasks LLMs are well-suited for).

**Key reframe:** LLMs excel at explaining and routing failures, not at deduplicating them. The goal for an agent is to architect this pipeline rather than substitute itself for it.
</objective>

---

## Discovery Questions

Before anything else, check `.agents/qa-project-context.md` — it typically already documents the tech stack, component ownership, and known-flaky areas, all of which sharpen classification. Skip any question already answered there, and confirm the rest:

1. **Where do failures originate?**
   - CI pipeline logs (GitHub Actions, GitLab CI, Jenkins, CircleCI)
   - Test framework output (Playwright, Jest, pytest, Vitest)
   - Production error monitoring (Sentry, Datadog, Bugsnag)
   - Manual bug reports from QA or users

2. **Where do tickets need to land?**
   - Jira, Linear, GitHub Issues, Azure DevOps, Shortcut
   - Which fields are mandatory? (component, severity, priority, labels)
   - What workflow governs them? (triage board, auto-assignment rules)

3. **How wide is the deduplication window?**
   - Within one test run? A sprint? A release? All history?
   - Is fingerprinting already in place, and if so, what's the current duplicate rate?

4. **What level of human approval is required?**
   - Tickets auto-created, reviewed afterward?
   - Tickets only suggested, approved before creation?
   - Duplicates auto-closed? (risky — require sign-off)

5. **What historical inputs are available?**
   - Prior bug reports with resolution outcomes?
   - A history of flaky tests or recurring environment problems?
   - A component-to-owner mapping?

---

## Core Principles

1. **Deterministic work comes first, LLM work second.** Deduplication and clustering need reliable, repeatable fingerprinting. Reserve the LLM for judgment calls: assessing severity, forming root-cause hypotheses, and drafting readable tickets.

2. **Normalize before you compare anything.** Raw CI logs are cluttered with timestamps, ports, PIDs, and random suffixes that make two occurrences of the same failure look unrelated. Scrub this noise out ahead of fingerprinting.

3. **Anchor fingerprints to what doesn't change.** Exception type, the top stack frames, the test name, the error message template, and the URL pattern are all stable signals. Timestamps, request IDs, and transient port numbers are not — exclude them.

4. **Nothing destructive happens without a human.** Auto-closing a "duplicate" ticket or auto-merging reports needs sign-off. A wrongly merged duplicate costs more time than triaging it by hand would have.

5. **The point of classifying is to route correctly.** The label itself isn't the deliverable — it's the decision that follows: which team owns it, how urgent it is, what SLA applies.

6. **Watch triage accuracy over time.** Compare auto-classification outcomes against human judgment regularly. If agreement drops under 85%, the pipeline needs retuning.

---

## The Pipeline

```
CI Log / Error Report
  │
  ▼
Step 1: NORMALIZE
  Strip timestamps, process IDs, ports, random suffixes, ANSI codes
  │
  ▼
Step 2: EXTRACT STABLE ANCHORS
  Exception type, top N stack frames, test name, error message template, URL pattern
  │
  ▼
Step 3: HASH CANONICAL FORM
  Deterministic fingerprint from ordered anchors
  │
  ▼
Step 4: CLUSTER NEAR-DUPLICATES
  Similarity scoring for non-identical but related failures
  │
  ▼
Step 5: LLM CLASSIFY
  Severity, component, suspected root cause, failure category
  │
  ▼
Step 6: LLM GENERATE TICKET
  Title, description, repro steps, evidence, suggested assignee
  │
  ▼
Step 7: HUMAN APPROVAL
  Review before create/close/merge
```

### Step 1: Normalize

The goal is to remove whatever noise makes an identical failure look like a new one.

**Normalization rules (apply in order):**

```
1. Strip ANSI color codes:        \x1b\[[0-9;]*m → ""
2. Strip timestamps:              \d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}[.\d]*Z? → "<TIMESTAMP>"
3. Strip UUIDs:                   [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} → "<UUID>"
4. Strip process IDs:             pid[=: ]\d+ → "pid=<PID>"
5. Strip port numbers:            :\d{4,5}(?=[\s/,)\]]|$) → ":<PORT>"
6. Strip temp file paths:         /tmp/[^\s]+ → "<TMPPATH>"
7. Strip memory addresses:        0x[0-9a-f]{8,16} → "<ADDR>"
8. Strip random suffixes:         [-_][a-z0-9]{6,8}(?=\.) → "<RAND>"
9. Strip request IDs:             (?:request[_-]?id|trace[_-]?id|correlation[_-]?id)[=: ]["']?[a-zA-Z0-9-]+ → "<REQ_ID>"
10. Collapse whitespace:          \s+ → " "
```

**Example:**

```
Before: 2025-03-22T14:32:01.456Z [pid=42891] Error: Connection refused at 127.0.0.1:54321
        request_id=abc-123-def-456
After:  <TIMESTAMP> [pid=<PID>] Error: Connection refused at 127.0.0.1:<PORT>
        <REQ_ID>
```

Note that rule 5 only strips the port, leaving the literal address `127.0.0.1` in place. That works fine when failures always originate from the same host, but if your runners bind to different hosts (say, `127.0.0.1` on one and `0.0.0.0` on another), the same underlying failure will fingerprint differently. Add a bind-address normalization rule if your environments are heterogeneous in this way.

### Step 2: Extract Stable Anchors

Once the log is normalized, pull out the elements that identify a failure independent of environment or timing.

**Anchor types (in priority order):**

| Anchor | Example | Stability |
|--------|---------|-----------|
| Exception type | `TypeError`, `AssertionError`, `HTTP 500` | Very high |
| Error message template | `Cannot read property 'X' of undefined` | High |
| Top 3 stack frames | `at processOrder (order.ts:142)` | High |
| Test name | `checkout.spec.ts > completes payment` | Very high |
| URL pattern | `POST /api/orders` | High |
| HTTP status code | `500`, `429`, `503` | Very high |
| Exit code | `exit code 1`, `SIGKILL` | High |
| Assertion diff | `Expected: 200, Received: 500` | Medium |

**Extraction rules:**
- Retain function names, but drop line numbers since they shift with every edit
- Retain URL paths, but strip query strings and any ID segments embedded in the path (`/api/orders/<ID>`)
- Retain the shape of error messages while swapping dynamic values for placeholders
- Leave the test file path and test name untouched

### Step 3: Hash Canonical Form

Build a deterministic fingerprint out of the anchors you extracted.

**Algorithm:**

```
1. Sort anchors alphabetically by type
2. Concatenate: exception_type + "|" + message_template + "|" + top_frames + "|" + test_name
3. SHA-256 hash the concatenated string
4. Take first 16 hex characters as fingerprint
```

**Fingerprint properties:**
- The same underlying failure always yields the same fingerprint (deterministic)
- Distinct failures yield distinct fingerprints (collision-resistant)
- Trivial formatting changes in the log don't shift the fingerprint (stable)
- Short enough to double as a Jira label or GitHub tag

**Example:**

```
Anchors:
  exception_type: "TypeError"
  message_template: "Cannot read property 'vendorId' of undefined"
  top_frames: "processOrder|groupByVendor|checkout"
  test_name: "checkout.spec.ts > multi-vendor checkout"

Canonical: "TypeError|Cannot read property 'vendorId' of undefined|processOrder|groupByVendor|checkout|checkout.spec.ts > multi-vendor checkout"
Fingerprint: a3f8b2c1e9d04567
```

### Step 4: Cluster Near-Duplicates

Exact fingerprint matches only catch identical failures. Similarity scoring is what catches related failures that manifest slightly differently despite sharing a root cause.

**Similarity dimensions:**

| Dimension | Weight | Match Criteria |
|-----------|--------|---------------|
| Exception type | 0.30 | Exact match |
| Error message | 0.25 | Levenshtein distance < 20% of message length |
| Stack frames | 0.25 | Jaccard similarity of top 5 frames > 0.6 |
| Component/file | 0.10 | Same directory or module |
| Test name | 0.10 | Same describe block or test file |

**Clustering threshold:** a similarity score above 0.75 flags the pair as a likely duplicate and prompts a merge suggestion.

**Send to human review whenever:**
- The score falls between 0.60 and 0.75 (too close to call)
- It's the first time this fingerprint has appeared (nothing to compare against)
- The failure comes from a component already known to be intermittent

### Step 5: LLM Classify

With fingerprinting and clustering done, hand the failure to the LLM for classification. Feed it the exception, message, top 5 stack frames, test name, and CI context, and request five outputs:

1. **Failure category** — `test bug | application bug | environment issue | flaky test | build failure`
2. **Severity** — `critical | major | minor | trivial` (see the severity matrix below)
3. **Component** — inferred from stack trace and file paths
4. **Suspected root cause** — 1-2 sentence hypothesis
5. **Confidence** — `high | medium | low`; on low confidence, the LLM should say what additional data would raise it

Anything classified with low confidence goes to a human rather than triggering automatic action. The full prompt text lives in `references/pipeline-prompts-and-integration.md`, and `references/classification-taxonomy.md` holds the bug-category, severity, and component-mapping definitions that prompt should reference.

**Failure categories (see references/ci-failure-analysis.md for detail):**

| Category | Description | Typical Action |
|----------|-------------|---------------|
| Application bug | The app is broken | File bug ticket, assign to owning team |
| Test bug | The test is wrong | Fix the test, no app change needed |
| Environment issue | CI infra / network / service down | Retry, notify infra team |
| Flaky test | Intermittent, non-deterministic | Quarantine, investigate root cause |
| Build failure | Compilation, dependency, config | Fix build, usually blocking |

### Step 6: LLM Generate Ticket

Once a classification exists, have the LLM turn it into a ticket a human would actually want to read. Give it the classification, the normalized error, a log excerpt, and any related cluster fingerprints, and have it produce:

- **Title** — concise, searchable, includes component name (under 80 chars)
- **Description** — what happened, in plain language (never raw logs)
- **Steps to reproduce** — derived from the test name and log context
- **Evidence** — relevant log lines, assertion diffs, screenshots if available
- **Suggested labels** — `[component, severity, failure-category, fingerprint]`
- **Suggested assignee** — based on component ownership, if known

The fingerprint needs to appear on the ticket itself (as a label and as a Fingerprint field) so future runs can match against it. See `references/pipeline-prompts-and-integration.md` for the full prompt and the bug report template.

### Step 7: Human Approval

**Nothing gets actioned automatically.** The pipeline's job is to recommend; a person makes the call.

**Approval decisions:**
- **Create ticket** — New failure, clear root cause, assign to team
- **Merge into existing** — Duplicate of known issue, add evidence to existing ticket
- **Quarantine test** — Flaky test, not an app bug, quarantine and schedule investigation
- **Retry and monitor** — Environment issue, retry CI, alert if persists
- **Dismiss** — Known issue already fixed in pending deploy, or test bug with obvious fix

---

## Severity/Priority Matrix

Severity captures how bad the impact is. Priority captures how soon it needs fixing. Treat these as two independent axes, not one.

### Severity Definitions

| Severity | Definition | Examples |
|----------|-----------|---------|
| **Critical** | System unusable, data loss, security breach, no workaround | Payment processing fails, user data exposed, app crashes on launch |
| **Major** | Core feature broken, degraded experience, workaround exists | Search returns wrong results, checkout requires page reload, form data lost on back-button |
| **Minor** | Non-core feature affected, cosmetic with functional impact | Sorting does not persist, tooltip clipped on mobile, secondary action fails |
| **Trivial** | Cosmetic only, no functional impact | Typo in label, 1px alignment, inconsistent capitalization |

### Priority Definitions

| Priority | Definition | SLA (example) |
|----------|-----------|---------------|
| **P0** | Fix immediately, blocks release or production | Same day |
| **P1** | Fix this sprint, significant user impact | This sprint |
| **P2** | Fix next sprint, moderate impact | Next sprint |
| **P3** | Fix when convenient, low impact | Backlog |

### Severity x Priority Decision Guide

| | Critical | Major | Minor | Trivial |
|---|---------|-------|-------|---------|
| **Affects all users** | P0 | P0 | P1 | P2 |
| **Affects segment (>10%)** | P0 | P1 | P2 | P3 |
| **Affects few users (<10%)** | P1 | P1 | P2 | P3 |
| **Edge case only** | P1 | P2 | P3 | P3 |

---

## Bug Report Template

The same template applies whether the ticket was auto-generated or written by a person. It starts with the defect heading and severity/priority/component/environment/fingerprint/reporter metadata, then continues into Description, Steps to Reproduce, Expected/Actual Behavior, Evidence, Frequency, Suggested Root Cause, and Related Issues. The full copy-paste Markdown version is in `references/pipeline-prompts-and-integration.md`.

---

## Deduplication Patterns

| Pattern | Detection | Action |
|---------|-----------|--------|
| **Exact duplicate** | Same fingerprint | Merge into existing ticket, add evidence |
| **Near-duplicate** | Same cluster (similarity > 0.75) | Link tickets, suggest merge for human review |
| **Same root cause, different symptom** | Same exception type + overlapping frames in different tests | Create parent ticket linking symptom tickets |
| **Regression of fixed bug** | Fingerprint matches closed ticket | Reopen ticket, flag as regression, increase priority |
| **Flaky recurrence** | Same fingerprint intermittently across CI runs | Tag as flaky, quarantine if rate > 10% |

---

## CI Failure Analysis

Full patterns live in `references/ci-failure-analysis.md`. The short version: a consistent failure points to a test bug or app bug; an intermittent one points to a flaky test or an environment problem; several failures hitting at once suggest environment or a shared component; and anything failing before tests even run is a build failure.

---

## Integration Patterns

Whatever tracker you use, the pipeline's output stays the same shape — Step 6 produces a title, description, labels, severity, and component that map onto any tracker's fields. See `references/pipeline-prompts-and-integration.md` for the `gh issue create` / fingerprint-dedup commands, a GitHub Actions "triage on failure" workflow, and notes on wiring up Jira, Linear, or Azure DevOps via their REST/GraphQL APIs.

### Buy vs Build

Before you build the full pipeline yourself, check whether a hosted platform already does most of it. Several vendors now ship AI-driven test triage that overlaps heavily with Steps 4 through 6.

| Platform | Covers | Notes |
|----------|--------|-------|
| **Trunk Flaky Tests** | Fingerprinting, clustering, severity routing, native PR comments + webhooks | Dedicated Agents feature for triage; documented Quarantining workflow — the closest off-the-shelf analog to this skill's pipeline |
| **CloudBees Smart Tests** | Fingerprinting, ML-based prioritization, Test Impact Analysis | Formerly **Launchable** — agents searching old docs may find the old name |
| **Datadog Test Optimization** | Flaky Test Management (Auto Retries, Early Flake Detection, Failed Test Replay), Test Impact Analysis | Bits AI Dev Agent now auto-generates fix PRs and Flaky Test Policies auto-quarantine-then-disable after 30 days; pairs with Datadog APM if you're already on Datadog |
| **Sealights** | Quality intelligence and test-impact gating | Enterprise; strongest in regulated industries |

Reach for the in-skill pipeline when you need on-prem or air-gapped deployment, your tracker integration is unusual, or you need an explicit AI-prompt audit trail for compliance purposes. Outside those cases, buying tends to beat rebuilding fingerprinting and clustering from scratch.

### Model selection cost note

Sonnet 4.6 or Haiku 4.5 is enough for the classification step (Step 5) — cheap and plenty capable. Reserve Opus 4.8 for cases where the cluster is genuinely novel, the failure is ambiguous, or the root-cause guess comes back low-confidence. Running every triage through Opus is wasted spend.

---

## Anti-Patterns

### 1. Using LLM for Deduplication

LLMs aren't deterministic — run the same comparison twice and you may get two different similarity scores. Deduplication needs deterministic fingerprinting; save the LLM for explaining and classifying.

### 2. Auto-Closing Without Review

Closing a ticket as "duplicate" purely off a fingerprint match risks merging two genuinely distinct issues. Close/merge actions always need a human to confirm first.

### 3. Over-Classifying Severity

When everything gets labeled "critical," the label stops meaning anything. Stick to the severity matrix — a cosmetic typo stays trivial no matter how much it bothers someone.

### 4. Ignoring Environment Failures

Don't lump every failure under "app bug" when a chunk of them are really CI infrastructure problems (Docker OOM, network timeout, disk full). Environment issues need their own category because they need different fixes.

### 5. No Feedback Loop

Standing up the pipeline once and never checking its accuracy afterward is a mistake. Keep tracking auto-classification accuracy, the false-duplicate rate, and how developers rate ticket quality.

### 6. Raw Logs in Tickets

Don't dump 500 lines of raw CI output into a ticket. Normalize it, pull out the relevant lines, and present just the 5-10 that actually matter.

### 7. Fingerprinting Without Normalization

Hashing raw log lines gives you an unstable fingerprint — the same failure produces a different hash on every run, and dedup never triggers. Normalization (Step 1) is not optional: always normalize before hashing, never fingerprint the raw log.

### 8. No Component Ownership Mapping

A classification that doesn't route anywhere is wasted effort. Keep a component-to-team mapping current so classified bugs actually reach the people who own them.

---

## Verification

The fingerprinter is the piece everything else depends on — validate it before trusting any deduplication results. Run the 5 stability assertions from `references/ci-failure-analysis.md` against your implementation:

1. Same error, **different timestamps** → same fingerprint.
2. Same error, **different PIDs and ports** → same fingerprint.
3. Same error, **different line numbers** (code edited) → same fingerprint.
4. **Different errors** (e.g. `TypeError` vs `RangeError`) → different fingerprints.
5. Same exception type, **different message property** (`'name'` vs `'email'`) → different fingerprints.

Tests 1 through 3 should all collapse to a single hash; tests 4 and 5 should each produce a distinct one. If they don't, normalization (Step 1) is either letting noise leak into the hash or stripping out something that should have stayed stable — resolve that before touching the clustering weights. Those weights (0.30 / 0.25 / 0.25 / 0.10 / 0.10) must sum to 1.00.

---

## Done When

- Every failure in `failures.json` has non-null `severity`, `component`, and `category` fields.
- The 5 fingerprint stability assertions above pass (tests 1-3 same hash, tests 4-5 distinct).
- Duplicates are merged or linked, each pointing to the canonical ticket's fingerprint label.
- Every P0/P1 ticket has an assignee set.
- Auto-classification accuracy is measured and recorded (target > 85%; see `qa-metrics`).

---

## Related Skills

- **`qa-metrics`** — Track triage accuracy, duplicate rates, mean time to classification, and defect escape rates.
- **`ci-cd-integration`** — Pipeline configuration for running triage on test failures, parallel execution, and reporting.
- **`test-reliability`** — Runtime per-test healing and quarantine for a single flaky locator. Triage classifies failures; test-reliability fixes one test live.
- **`observability-driven-testing`** — Goes the other direction: turns production telemetry into new test designs. Use it when prod errors should spawn tests, not tickets.
- **`qa-project-context`** — Project context that improves classification accuracy: component map, known issues, ownership.
- **`ai-test-generation`** — Generate regression tests from triaged bug reports.

---

## Reference Files (in `references/`)

- **pipeline-prompts-and-integration.md** — LLM classification + ticket-generation prompts (Steps 5-6), the full bug report Markdown template, and tracker integration code (GitHub Issues, CI workflow, Jira/Linear notes).
- **classification-taxonomy.md** — Bug categories, severity definitions, component mapping rules, and root cause categories.
- **ci-failure-analysis.md** — CI log parsing patterns, failure category decision tree, fingerprinting algorithm detail.
