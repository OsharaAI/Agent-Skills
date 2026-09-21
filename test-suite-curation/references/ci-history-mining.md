# Mining CI History

How to turn a pile of test-result history into per-test pass/fail/flip statistics, and
how same-SHA divergence — the actual definition of flakiness — gets detected. The
dispositions these signals drive are documented in `SKILL.md` §4.

## Where the data comes from

- **Archived JUnit XML** — most CI systems emit a `junit.xml` per run; keep them around.
- **Datadog Test Optimization** — its Flaky Test Management API stores per-test history.
- **Trunk Flaky Tests** — does same-SHA flake detection natively; wants roughly 10+ runs per test before it's confident.
- **BuildPulse** — surfaces tests whose outcome varies on an identical SHA.
- **CircleCI test insights** — tracks per-test flakiness over time.

## Rolling JUnit XML up into per-test signals

```python
import glob, xml.etree.ElementTree as ET
from collections import defaultdict

runs = defaultdict(list)   # test_id -> [(sha, passed_bool), ...]

for path in glob.glob("ci-history/**/junit*.xml", recursive=True):
    sha = path.split("/")[1]               # however you encode commit SHA in the path
    for case in ET.parse(path).iter("testcase"):
        test_id = f"{case.get('classname')}::{case.get('name')}"
        failed = any(case.iter(tag) for tag in ("failure", "error"))
        runs[test_id].append((sha, not failed))

def pass_rate(history):
    return sum(p for _, p in history) / len(history)

def flip_rate(history):
    # fraction of consecutive runs that transitioned pass<->fail
    flips = sum(1 for (_, a), (_, b) in zip(history, history[1:]) if a != b)
    return flips / max(1, len(history) - 1)
```

## Tests that have never failed

```python
never_failed = [t for t, h in runs.items() if pass_rate(h) == 1.0]
```

Disposition: **look into it, don't delete it**. A 100% pass rate is usually a sign of
low-churn / low-risk / stable code — the test simply never gets a chance to fail because
nothing touching it ever changes. Cross-reference the file's churn
(`git log --oneline -- <file> | wc -l`) and its risk tier. If it's guarding a critical
path that just hasn't regressed recently, that's a keep, not a delete.

## Detecting flakiness the correct way: same-SHA divergence

The real definition of a flaky test is one with **different outcomes on the same SHA**
— a single failing run is NOT enough to call a test flaky.

```python
def same_sha_flaky(runs):
    flaky = []
    for test, history in runs.items():
        by_sha = defaultdict(set)
        for sha, passed in history:
            by_sha[sha].add(passed)
        # both True and False observed on at least one commit => flaky
        if any(len(outcomes) > 1 for outcomes in by_sha.values()):
            flaky.append(test)
    return flaky
```

Disposition: **quarantine it and fix the underlying flake — deleting it to quiet CI is
not an option**. Quarantine removes the noise right away while the root cause still gets
addressed (see `test-reliability`). Keep in mind a flaky test may be the only thing
covering a real path, so cutting it could mean losing that coverage entirely.

## Mining defect-detection history (feeds tiering)

Tests with an actual track record of catching bugs deserve a higher tier (`SKILL.md` §6).
Approximate that history this way: treat a test as a "defect catcher" if it **failed on
the commit right before one that closed a bug ticket**.

```python
# tests that failed on a SHA later linked to a fixed bug ticket
defect_catchers = {
    t for t, h in runs.items()
    if any(not passed and sha in bugfix_parent_shas for sha, passed in h)
}
```

`bugfix_parent_shas` should come from your issue tracker — commits referenced by closed
defect tickets, or a fallback like `git log --grep='fix' --grep='bug'`.

## Pulling data from platform APIs

```bash
# Datadog flaky tests (replace with your site/keys)
curl -s "https://api.datadoghq.com/api/v2/ci/test_management/flaky" \
  -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY"

# Trunk: flaky test list is available via the Trunk web app and API per repo.
```
