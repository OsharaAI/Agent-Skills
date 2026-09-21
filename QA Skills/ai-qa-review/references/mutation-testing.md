# Mutation Testing — the objective backstop for qualitative smells

Coverage only tells you that a line *executed*. Mutation testing tells you whether your tests would actually *notice a bug* in that line. The runner seeds small faults ("mutants") into the code — flipping a `>` to `>=`, forcing a `null` return, deleting a statement — then reruns the suite against each one. If the suite still passes, that mutant "survived": nothing was asserting against that behavior. The mutation score is simply killed / total.

This turns two of the SKILL's more subjective smells into something measurable:

- **Closed AI loop** (tests that just mirror the implementation). Tests that merely echo what the agent produced rarely kill mutants — they check the value that came out, not the contract that should hold. AI-authored tests scoring low are a direct signal of this.
- **Weak / redundant assertions** (`toBeTruthy`, duplicated checks). Wherever mutants survive, that's exactly where the assertions fail to pin behavior down.

## Tools (verified current, mid-2026)

| Stack | Runner | Command |
|-------|--------|---------|
| JS / TS | StrykerJS (supports Jest, Vitest, Mocha) | `npx stryker run` |
| Java | PIT (pitest) | `mvn org.pitest:pitest-maven:mutationCoverage` |
| Rust | cargo-mutants | `cargo mutants` |
| Python | mutmut | `mutmut run` |

## Thresholds (2026 guidance)

- AI-generated tests coming in **under 60%** mutation score indicate tests that aren't independent of the implementation — treat this as the Closed-AI-loop / weak-assertion smell and insist on human-authored boundary tests before trusting the suite.
- For hand-tuned production code: aim for 70% on critical paths, 50% as a general standard, 30% for experimental code. Anything above 80% is a strong signal of solid test quality.

## Minimal StrykerJS config

```jsonc
// stryker.config.json
{
  "testRunner": "vitest",
  "coverageAnalysis": "perTest",
  "mutate": ["src/**/*.ts", "!src/**/*.test.ts"],
  "thresholds": { "high": 80, "low": 60, "break": 60 }
}
```

Setting `"break": 60` fails CI below that threshold — wire it in as a quality gate alongside the test runner, much the way ESLint enforces static rules. Scope it to changed files during PR review (`--mutate "$(git diff --name-only main...HEAD | grep '\.ts$' | tr '\n' ',')"`), reserving a full-suite mutation run — which is slow — for scheduled audits only.

Surviving mutants can also feed a test-generation loop of their own: hand them back to the agent and ask it to write whatever assertion would kill each one.
</content>
