# Mutation Testing

Configuration for Stryker (JS/TS) and mutmut (Python). Strategy for what to target and how to interpret the resulting score both live in `SKILL.md` — this file covers setup only.

## Stryker (JS/TS)

```json
// stryker.config.json
{
  "$schema": "./node_modules/@stryker-mutator/core/schema/stryker-schema.json",
  "testRunner": "vitest",
  "coverageAnalysis": "perTest",
  "incremental": true,
  "incrementalFile": ".stryker-tmp/incremental.json",
  "mutate": ["src/**/*.ts"],
  "thresholds": { "high": 80, "low": 60, "break": 50 }
}
```

Scope runs to PR-changed files with `--mutate '$(git diff --name-only origin/main...HEAD | grep "src/.*\.ts")'`. Combine `incremental: true` with its JSON cache so subsequent runs re-mutate only what actually changed.

## mutmut (Python)

```bash
mutmut run --paths-to-mutate=src/
mutmut results
```

mutmut 3.x is a ground-up rewrite and remains actively maintained (still current in 2026); pin it with `pip install mutmut==3.*`.
