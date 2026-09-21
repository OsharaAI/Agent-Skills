# Confirming Redundancy With Mutation Testing

How to prove that one test genuinely absorbs another's fault-detection ability.
Coverage equality is only ever a candidate signal; the mutation kill-set comparison is
the actual proof. The decision rules this supports live in `SKILL.md` §2.

## Why mutation testing is the right tool here

A mutant is a small, deliberately injected fault — flipping `>` to `>=`, swapping `+`
for `-`, deleting a call. A test **kills** a mutant if it fails against the mutated
code. When survivor A kills every mutant that candidate B kills, A has genuinely
absorbed B's fault-detection and B is a real deletion candidate. If B kills even a
single mutant that A misses, B is catching a category of fault A can't — **keep B**,
even if their line coverage was identical.

## Tool choice by stack (current as of mid-2026)

| Stack | Tool | Notes |
|-------|------|-------|
| Python | **mutmut 3.6.0+** | AST-based, fast; needs fork support (WSL on Windows). Default choice. |
| Python | **cosmic-ray** | More configurable, slower to set up; reach for it when you need build-tool integration. |
| JS/TS | **StrykerJS 9.x** (`@stryker-mutator/core`) | `coverageAnalysis: perTest` + `incremental`. |
| Java/JVM | **PIT (pitest)** | Mature; slower than mutmut but the standard on the JVM. |
| Rust | **cargo-mutants** | Native Rust mutation testing. |

## Scope the run to just the suspect lines

Don't mutate the entire codebase to compare two tests — narrow the run to the lines the
candidate pair actually covers, which you already know from the coverage fingerprint.

```bash
# mutmut: limit to the file(s) the suspect pair covers
mutmut run --paths-to-mutate src/pricing.py
mutmut results        # list surviving/killed mutants
```

```jsonc
// stryker.config.json — scope mutate globs to the covered files
{
  "$schema": "./node_modules/@stryker-mutator/core/schema/stryker-schema.json",
  "testRunner": "vitest",
  "coverageAnalysis": "perTest",
  "mutate": ["src/pricing.ts"],
  "thresholds": { "high": 80, "low": 60, "break": 0 }
}
```

## Comparing kill-sets

Run mutation testing once across the full suite and check, per mutant, which test
killed it (StrykerJS reports the killing test directly in its JSON output; with mutmut,
run the suite filtered to A, then to B, and diff the surviving mutants between runs).

```
kills(A) = {mutants test A kills}
kills(B) = {mutants test B kills}

if kills(B) ⊆ kills(A):   A subsumes B's fault detection -> B is a delete candidate
if kills(B) ⊄ kills(A):   B kills a mutant A misses        -> KEEP B (different oracle)
```

Even once `kills(B) ⊆ kills(A)` holds, B still has to go through quarantine and sign-off
(`SKILL.md` §7) before it's actually removed — the mutation check authorizes proposing
the deletion, not carrying it out.

## The tricky case: never-failed plus identical coverage

When a test has never failed in CI *and* shares identical coverage with another (the
"two green signals" anti-pattern in `SKILL.md`, eval tsc-009), those two signals
together are still not proof enough. Run the mutation check and ask directly: does the
*other* test kill what this one kills? A test can carry a distinct assertion, input,
edge case, or oracle that makes it irreplaceable even with a spotless CI history and
matching coverage. A perfect pass record often just means the underlying code is
low-risk and stable — not that the test is disposable. Quarantine only becomes an option
once the mutation check has actually confirmed subsumption.
