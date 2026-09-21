# Fingerprinting Coverage Per Test

How to capture per-test (dynamic) coverage contexts and turn a `.coverage` SQLite
database into per-test line/branch fingerprints. The decision rules built on top of this
data live in `SKILL.md` §1.

## Capturing per-test contexts (pytest / coverage.py)

```bash
# --cov-context=test tags every measured line with the test that ran it.
# --cov-branch records branch arcs so if/else on one line are distinct.
pytest --cov=src --cov-branch --cov-context=test
```

The equivalent, if you'd rather set it in `.coveragerc` than pass flags:

```ini
[run]
branch = true
dynamic_context = test_function
```

Under the hood, coverage.py calls `switch_context()` around each test (pytest-cov wires
this up automatically). The results are written into the `.coverage` SQLite database.

## Reading contexts back out of the .coverage database

coverage.py ships a stable Python API — use it instead of querying raw SQL directly, so
you're not exposed to schema changes. That said, the underlying tables are `context`,
`file`, `line_bits`, and `arc`.

```python
import coverage

cov = coverage.Coverage(data_file=".coverage")
cov.load()
data = cov.get_data()

# Per-test line sets: {test_context: {(file, line), ...}}
line_sets = {}
branch_sets = {}
for ctx in data.measured_contexts():
    if not ctx:                      # "" is the no-context bucket; skip it
        continue
    data.set_query_context(ctx)
    lset, bset = set(), set()
    for f in data.measured_files():
        for line in (data.lines(f) or []):
            lset.add((f, line))
        for arc in (data.arcs(f) or []):     # arcs present only with --cov-branch
            bset.add((f, arc))
    line_sets[ctx] = lset
    branch_sets[ctx] = bset
```

A raw-SQL fallback, for when you have the `.coverage` file but not coverage.py itself
installed:

```sql
-- contexts table maps context_id -> test name
SELECT context, c.id FROM context c;
-- line_bits maps (file_id, context_id) -> bitmap of covered lines
SELECT f.path, lb.context_id, lb.numbits
FROM line_bits lb JOIN file f ON f.id = lb.file_id;
```

## Computing uniquely-covered lines and subsumption

```python
from collections import Counter

# How many tests cover each (file, line)?
line_owner_count = Counter()
for lset in line_sets.values():
    for key in lset:
        line_owner_count[key] += 1

# Lines covered by exactly one test -> that test is load-bearing; protect it.
uniquely_covered = {
    test: {key for key in lset if line_owner_count[key] == 1}
    for test, lset in line_sets.items()
}

# Subsumption CANDIDATES: A's covered set ⊇ B's covered set.
# This is a candidate only — confirm with mutation testing (SKILL.md §2) before deletion.
def subsumption_candidates(line_sets):
    items = list(line_sets.items())
    out = []
    for a, sa in items:
        for b, sb in items:
            if a != b and sb and sb <= sa:
                out.append((a, b))   # A subsumes B's coverage
    return out
```

A non-empty `uniquely_covered[test]` means removing `test` drops coverage outright — it
should never be a delete candidate. Every pair produced by `subsumption_candidates`
needs to be fed into the mutation-confirmation step before anything is proposed.

## The JS / Vitest + Istanbul equivalent

Istanbul has no built-in equivalent of coverage.py's dynamic contexts. Two workarounds:

1. **Per-test coverage via the runner itself** — run each test file in isolation with
   `vitest run --coverage --coverage.reporter=json` and index the resulting
   `coverage-final.json` by test file. This is coarser than true per-test data but is
   good enough for clustering purposes.
2. **`@vitest/coverage-istanbul` with `coverage.all: true`**, combined with a custom
   reporter that snapshots and resets `globalThis.__coverage__` between tests
   (`beforeEach`/`afterEach`) to approximate genuine per-test contexts.

```ts
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: 'istanbul',
      reporter: ['json'],          // coverage-final.json has per-file statement/branch maps
      all: true,
      branches: true,
    },
  },
})
```

From `coverage-final.json`'s `statementMap` and `branchMap`, build the same
`(file, statement)` and `(file, branch)` sets per test, then reuse the
uniquely-covered and subsumption logic shown above unchanged.
