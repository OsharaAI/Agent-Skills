# Automated bisect to find the introducing commit

Say a bug is present on `HEAD` but was absent in last month's release, and you have a
command that exits **non-zero when the bug is present**. `git bisect run` will binary-search
through history and invoke that command at every step. Let it drive the search — don't check
out commits by hand.

## The exit-code contract

`git bisect run <cmd>` reads the command's exit code at each commit as follows:

| Exit code | Meaning | bisect verdict |
|-----------|---------|----------------|
| `0` | bug absent | **good** (or `old`) |
| `1`–`124`, `126`, `127` | bug present | **bad** (or `new`) |
| `125` | commit is **untestable** — skip it | `git bisect skip` |
| any | — | a non-zero exit other than 125 marks the commit bad |

Your repro command therefore needs to return **0 when the feature works correctly** and
**non-zero when the bug shows up**. Most test runners already behave this way — a failing
test naturally exits 1.

## Happy path

```sh
git bisect start
git bisect bad HEAD                 # current commit has the bug  (a.k.a. `git bisect new`)
git bisect good v2.4.0             # last month's release was clean (a.k.a. `git bisect old`)
git bisect run npm test -- checkout-total.spec.ts   # ONE targeted test, not the whole suite
# ... bisect prints "<sha> is the first bad commit" ...
git bisect reset                    # ALWAYS clean up — restores HEAD and ends the session
```

A note on terminology: the classic `good`/`bad` pair assumes you're chasing down a commit
that introduced a *regression* (fine in the past, broken now). The `old`/`new` aliases run
the identical binary search but read more naturally when hunting any transition, not
strictly a break — `git bisect start --term-old fixed --term-new broken` even lets you
rename the terms entirely.

**Run one targeted command, never the full suite.** `git bisect run npm test` (running
everything) is slow and fragile — an unrelated test failing at an old commit will falsely
mark it bad and steer the search down the wrong path. Point bisect at just the single test
that captures this specific bug.

## Skip untestable commits and ignore flaky failures (exit 125)

Two failure modes can corrupt a naive bisect run:

1. **Old commits that won't build.** A compile error makes the test runner exit 1, which
   bisect misreads as "bug present," incorrectly marking a clean-but-unbuildable commit as
   bad.
2. **Flaky network or timing failures.** A one-off failure (say, an un-stubbed third-party
   call) also exits 1 and gets wrongly blamed on the code.

The remedy is a **wrapper script** that separates "I can't judge this commit" (exit 125,
skip) from "the bug is genuinely here" (exit 1, bad), while also forcing determinism during
the run. Invoke it with `git bisect run ./bisect-step.sh`:

```sh
#!/usr/bin/env bash
# bisect-step.sh — exit 0 = good, 1 = bad (bug present), 125 = skip (untestable).
set -u

# Force determinism so a flaky network or clock can't mark a commit bad.
export TZ=UTC
export PRICING_API_URL="http://localhost:4000"   # local stub server, never the live API
export FAKER_SEED=1337

# 1. If the commit doesn't build, it's UNTESTABLE — skip, don't blame it.
if ! npm ci --silent && npm run build --silent; then
  echo "build failed → untestable, skipping this commit"
  exit 125
fi

# 2. Run the ONE targeted test. Retry once to absorb a single flaky blip; if it flips
#    between pass and fail in the SAME commit, treat the commit as untestable (skip),
#    not as bad — a flaky result is not evidence the bug was introduced here.
npm test -- checkout-total.spec.ts && first=0 || first=1
npm test -- checkout-total.spec.ts && second=0 || second=1

if [ "$first" -ne "$second" ]; then
  echo "result not reproducible at this commit (flaky) → skip"
  exit 125
fi

# Stable result: 0 = bug absent (good), 1 = bug present (bad).
exit "$first"
```

Wire it up:

```sh
git bisect start
git bisect bad HEAD
git bisect good v2.4.0
git bisect run ./bisect-step.sh
git bisect reset
```

Why this matters: treating any failure as "bad" — the naive default — silently mislabels
unbuildable or flaky commits, and the binary search converges on the wrong one. The exit-125
skip path combined with stubbing the network during the bisect run is what makes the final
answer trustworthy.

If an entire stretch of history is known to be unbuildable, exclude it up front instead of
letting bisect discover it commit by commit:

```sh
git bisect skip v2.4.1..v2.4.5     # exclude a known-broken range before running
```

## After bisect

`git bisect run` finishes by printing `<sha> is the first bad commit`, and `git show <sha>`
shows you the diff. That SHA is the **introducing commit** — record it verbatim for the
ticket write-back. Finish with `git bisect reset` to return the working tree to the original
`HEAD`.
