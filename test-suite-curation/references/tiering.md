# Tiering: Smoke, Core, and Extended

How to encode suite tiers as markers driven by risk and defect-detection history rather
than by raw speed. The decision rules behind this live in `SKILL.md` §6.

## Evidence used for tier selection, in priority order

1. **Business risk / critical-path membership** — sourced from the risk map
   (`risk-based-testing`). Anything touching revenue, auth, data integrity, or a top
   user journey belongs in smoke/core no matter its runtime.
2. **A track record of catching real defects** — tests in the `defect_catchers` set
   from `ci-history-mining.md` earn a high tier on that history alone.
3. **Runtime / duration** — only ever a *tiebreaker*. Among tests that are equally
   risky, the faster one wins a smoke slot. This should never be the primary axis, never
   determine smoke by picking the first N tests in a file, and never be decided by
   random sampling.

| Tier | Purpose | What belongs here |
|------|---------|--------------------|
| smoke | runs on every push, a few minutes | top-risk paths plus proven defect-catchers; fast enough to gate every commit |
| core | per-PR / merge gate | all critical and high-risk coverage |
| extended | full / nightly / slow / pre-release | everything else — exhaustive, long-running, edge-case coverage |

## Encoding tiers as markers, not by relocating files

```python
import pytest

@pytest.mark.smoke
def test_checkout_completes_payment(): ...

@pytest.mark.extended
def test_checkout_handles_47_currency_edge_cases(): ...
```

```ini
# pytest.ini / pyproject.toml
[pytest]
markers =
    smoke: critical-path + proven defect-catcher; gates every push
    core: critical + high-risk coverage; PR/merge gate
    extended: full/nightly/slow/edge-case suite
```

```bash
pytest -m smoke            # select a tier without moving any files
pytest -m "core or smoke"  # the PR gate
pytest -m extended         # nightly
```

The JS/Vitest equivalent: tag tests with `test.concurrent`/custom tags or a filename
suffix (`*.smoke.test.ts`), then select via `vitest --project smoke` or a
`testNamePattern`. In JUnit, use `@Tag("smoke")` with `-Dgroups=smoke`.

## Turning the evidence into a tier assignment

```python
def assign_tier(test, risk_tier, defect_catchers, runtime_s):
    if risk_tier == "critical" or test in defect_catchers:
        # fast enough to gate every push? -> smoke, else core
        return "smoke" if runtime_s < 2.0 else "core"
    if risk_tier == "high":
        return "core"
    return "extended"
```

Runtime only breaks a tie *within* a given risk class — it should never pull a low-risk
test up into smoke, nor push a critical-path test out of it.
