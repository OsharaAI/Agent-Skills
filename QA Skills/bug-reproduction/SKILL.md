---
name: bug-reproduction
description: >-
  Turn a vague bug report into a VERIFIED minimal reproduction and then a failing
  regression test, agent-driven end to end. Covers extracting the implicit repro from a
  thin report (env, build, steps, data), the reproduce-minimize-isolate-capture loop,
  git bisect to find the introducing commit, building a deterministic minimal repro
  (fixed seeds, frozen time, stubbed network), writing the failing regression test BEFORE
  the fix (red) and confirming the fix flips it green, and writing repro evidence back
  into the ticket. Distinguishes flaky-not-reproducible from environment-specific.
  Use when: "reproduce this bug," "minimal reproduction," "repro steps," "find the commit
  that broke it," "git bisect," "make the repro deterministic," "write a failing test for
  this bug," "regression test for a defect," "can't reproduce this bug."
  Not for: Classifying/deduplicating/severity-routing existing failures without
  reproducing them — that is ai-bug-triage. Generating tests from specs rather than from a
  defect — that is ai-test-generation.
  Related: ai-bug-triage, ai-test-generation, test-reliability, systematic-debugging, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "1.0"
  category: ai-qa
---

<objective>
An unreproduced bug cannot be fixed, and it cannot be proven fixed either. This skill takes
a thin, hand-wavy report ("order total is wrong sometimes") and pushes it through to a
VERIFIED minimal reproduction, a deterministic failing test authored BEFORE the fix exists,
a `git bisect` run that pins down the introducing commit, and a structured evidence block
recorded in the ticket. The underlying discipline: reproduce before you theorize, minimize
one variable at a time, pin time/seed/network so the failure is identical run after run,
insist the test is red before it's ever green, and confirm that reverting the fix makes it
red again.
</objective>

## Quick Route

| You have… | Go to |
|-----------|-------|
| A thin report and no idea how to trigger it | [Step 1: Extract the implicit repro](#step-1-extract-the-implicit-repro) |
| A messy 14-step repro to clean up | [Step 2: The reproduce-minimize-isolate-capture loop](#step-2-the-reproduceminimizeisolatecapture-loop) |
| "Worked last month, broken now" | [Step 3: Bisect to the introducing commit](#step-3-bisect-to-the-introducing-commit) |
| A repro that passes/fails inconsistently | [Step 4: Make the repro deterministic](#step-4-make-the-repro-deterministic) |
| A clean repro, no fix yet | [Step 5: Write the failing regression test (red) first](#step-5-write-the-failing-regression-test-red-first) |
| "The dev says it's fixed, test is green" | [Step 6: Verify the fix actually fixes it](#step-6-verify-the-fix-actually-fixes-it) |
| "It won't reproduce for me but does for the user" | [Step 7: Flaky vs environment vs not-reproducible](#step-7-flaky-vs-environment-vs-not-reproducible) |
| Repro + test done | [Step 8: Write the evidence back into the ticket](#step-8-write-the-evidence-back-into-the-ticket) |

## Discovery Questions

Start by checking `.agents/qa-project-context.md` at the project root — it holds the tech
stack, test runner, known-flaky areas, and environment matrix. Skip any question it already
answers, and if it doesn't exist, propose creating one via the `qa-project-context` skill.

- **What does the report say, word for word?** The thinner it is, the more work Step 1 has
  to do before you touch any code — a single sentence sets the whole intake agenda.
- **Does it already reproduce, and how reliably?** "Every time" sends you straight to
  minimizing; "sometimes" means determinism work comes first.
- **Was there a known-good version?** If yes, `git bisect` can name the introducing commit;
  if there's no known-good baseline, you're debugging forward instead.
- **What's the test runner and stack?** Vitest/Jest vs. Playwright determines which
  determinism API applies (`vi.setSystemTime` vs `page.clock`) and where the test lives.
- **Where does the non-determinism come from?** Clock, randomness, third-party calls,
  locale — anything on this list has to be pinned before the repro can be trusted.

---

## Core Principles

1. **Reproduce first, theorize second.** The tempting wrong move is reading a symptom and
   immediately guessing a cause ("sounds like float rounding, let me patch the total calc").
   Resist it. Get the repro failing on demand before forming any hypothesis — a fix you
   can't falsify against a reproduction is just a guess.

2. **A repro is a deterministic artifact, not an anecdote.** "It happens around midnight
   with some random code" is an anecdote, not evidence. Freeze the clock, seed the RNG, and
   stub the network so identical inputs produce an identical failure every time, on any
   machine. Without that, you can't bisect it, test it, or prove it's fixed.

3. **Shrink one variable at a time, and re-verify after each cut.** Minimizing a repro is a
   search process, not a rewrite. Drop one step, field, or dependency, rerun, and confirm
   the failure *still happens*. Cutting several things at once tells you nothing about which
   one actually mattered.

4. **Write the regression test red, before any fix exists.** The assertion should check the
   real expected value, fail on the first run (proof it actually targets this bug), and only
   then flip to green once the fix lands. A test written after the fix — or skipped/disabled
   — proves nothing at all.

5. **A green test isn't the finish line — reverting the fix to confirm red is.** Tests can
   pass for reasons unrelated to the bug. Pull the fix out temporarily and check the test
   fails again. Only a test that fails without the fix and passes with it actually guards
   against the defect.

---

## Step 1: Extract the implicit repro

"Checkout is broken, order total is wrong sometimes" describes a symptom, not a reproduction
path. Before writing a line of code, pull out (or ask for) every dimension that affects
reproducibility. Never invent repro steps from imagination, and never form a root-cause
theory yet — both come only after the bug actually reproduces.

For a "wrong total"-style data-correctness bug, the dimensions a thin report most commonly
leaves out — and that matter most — are:

- **Exact reproduction steps** — the literal click path, not a one-line summary.
- **Build / version / commit SHA** — the report might describe a build where this is
  already fixed.
- **Environment** — browser and version, OS, device.
- **Input data** — cart contents, quantities, account, coupon, the specific fixture. A total
  is a pure function of its inputs, so without them you're just guessing.
- **Expected vs. actual value** — the number they wanted and the number they got.
- **Frequency** — always, or intermittent? "Sometimes" is a signal of non-determinism.
- **Locale / timezone / currency** — rounding, tax rules, and formatting vary by locale; a
  total that's "wrong" in `de-DE` might be correct in `en-US`.
- **Timestamp of the occurrence**, plus any available logs, screenshots, or network traces.

Capture all of this as a single repro spec before writing any code. A blank field is your
next question for the reporter, not permission to start fixing or theorizing.

Full extraction checklist, the reasoning behind each load-bearing dimension for a "wrong
total" bug, and the repro-spec template live in `references/intake.md`.

---

## Step 2: The reproduce→minimize→isolate→capture loop

If you've got a confirmed but messy repro (say, 14 manual UI steps spanning 3 pages), don't
hand that straight to the developer, and don't try to rewrite it from scratch either. Run
this loop instead:

1. **REPRODUCE / confirm.** Establish a baseline first — run the whole thing and verify it
   actually fails. You can only shrink something that currently reproduces.
2. **MINIMIZE.** Cut exactly **one** step, field, or dependency, then rerun. Still fails?
   Keep the cut. Stops failing? That piece was load-bearing — put it back. Repeat one
   variable at a time until nothing left can be removed. Never start minimizing before
   confirming the baseline reproduces, and never skip re-checking after each cut.
3. **ISOLATE.** Push the failure down to the smallest layer that still shows it — from a
   three-page UI flow to a single page, then to a unit or API call if the root cause lives
   below the UI.
4. **CAPTURE.** Record the resulting minimal repro as evidence — the smallest steps or a
   single command, plus supporting logs/trace/screenshot. This is the artifact the developer
   and the regression test will both build on.

You're aiming for the smallest sequence that still reproduces the bug — not a cleaner
version of the original walkthrough.

---

## Step 3: Bisect to the introducing commit

The bug shows up on `HEAD` but a past release was fine, and you have a command that returns
non-zero when the bug is present. Let `git bisect run` binary-search history for you — don't
hand-check commits, and don't try to find it via `git revert`.

```sh
git bisect start
git bisect bad HEAD          # current commit has the bug   (alias: git bisect new)
git bisect good v2.4.0       # last clean release            (alias: git bisect old)
git bisect run npm test -- checkout-total.spec.ts   # ONE targeted test, never the full suite
# bisect prints "<sha> is the first bad commit"
git bisect reset             # ALWAYS clean up — restores the original HEAD
```

The exit-code contract behind `git bisect run`: **0 means good** (bug absent), **any
non-zero code from 1–124 means bad** (bug present), and **125 means skip** (untestable).
Your script needs to return 0 when things work and non-zero when the bug shows up — most
test runners already behave this way. Point it at **one specific test**, not the full suite
(`npm test:all`) — an unrelated failure on an old commit would falsely mark it bad and steer
the search into the wrong half of history.

`good`/`bad` implicitly assume a regression (fine in the past, broken now). `old`/`new` mean
the identical search but fit better when you're hunting any state change, not just a
regression.

The full walkthrough plus the skip/untestable wrapper script live in
`references/bisect.md`.

### Bisect skip and determinism (untestable or flaky commits)

Two problems can corrupt a naive bisect run, and treating any non-zero exit as "bad" walks
straight into both:

- **Old commits that won't build.** A build error exits 1, and bisect reads that as "bug
  present," incorrectly marking a perfectly clean commit as bad. The right answer: an
  unbuildable commit is **untestable**, so the wrapper needs to `exit 125` (skip) on build
  failure rather than call it bad.
- **Flaky network or timing failures.** An un-stubbed third-party call failing transiently
  also exits 1 and gets blamed unfairly. The fix is forcing determinism *during* the bisect
  run itself — stub the network, pin `TZ`, seed the RNG — so only the actual bug can cause a
  failure. If a commit's result changes between repeated runs, treat it as untestable (exit
  125), not bad.

Wrap the test command in a script that returns **0 for good, 1 for bad, 125 for skip** (the
valid "bad" range is 1–127, excluding 125), guards against build failure, stubs the network,
and retries once to catch flakiness before deciding. Then run
`git bisect run ./bisect-step.sh`. The complete wrapper script is in `references/bisect.md`.

---

## Step 4: Make the repro deterministic

Take a bug that "only happens around midnight, with a random discount code, through a
third-party pricing API" — that's three separate sources of non-determinism. Pin every one
of them so it **fails identically on every single run**: don't wait for midnight to arrive,
don't let it hit the real pricing API, and never mask timing problems with
`sleep`/`setTimeout`/`waitForTimeout`.

| Source | Vitest | Playwright |
|--------|--------|-----------|
| **Time** | `vi.useFakeTimers()` + `vi.setSystemTime(new Date('…'))` | `page.clock.install({ time })` + `page.clock.setFixedTime(…)` |
| **Randomness** | `faker.seed(1337)` (or stub `Math.random`) | seed the app's RNG via an init hook |
| **Network** | MSW `setupServer` + `http.get` → `HttpResponse.json` | `page.route(...)` → `route.fulfill(...)` |

Key points:
- **Vitest:** `vi.setSystemTime` does nothing until `vi.useFakeTimers()` has run first. Seed
  faker inside `beforeEach`. Set MSW's `onUnhandledRequest: 'error'` so any missed stub
  causes a loud failure rather than a silent live call.
- **Playwright:** `page.clock.install`/`setFixedTime` has to run **before** `page.goto`.
  `page.clock` is the officially supported API for this — use it rather than rolling your
  own `Date` override, and don't just extend the timeout to make things pass.
- Pin locale/timezone/currency (`TZ=UTC`, `LANG`) whenever the bug depends on locale.

**Avoid:** `jest.useFakeTimers('legacy')` (and the `timers: 'legacy'` config) — legacy fake
timers are deprecated and never mock `Date`/`Date.now`, so the clock keeps ticking for real
and your "frozen" repro drifts anyway. Modern timers have been the default since Jest 27 —
just call `jest.useFakeTimers()` + `jest.setSystemTime()`, or `vi.useFakeTimers()` in Vitest.
(Jest 30, 2025)

The full Vitest recipe (`vi.useFakeTimers` + `vi.setSystemTime` + `faker.seed` + MSW
`setupServer`), the Playwright recipe (`page.clock` + `page.route`), and a 10-run
determinism check are all in `references/determinism.md`.

---

## Step 5: Write the failing regression test (red) first

You now have a clean, deterministic repro, and the fix hasn't landed yet. This is the moment
to write the regression test — TDD applied to bugs:

1. Turn the minimal repro into a test that **asserts the real expected value** —
   `expect(total).toBe(2754)`. An assertion that's always true proves nothing.
2. Run it and make sure it **fails before the fix exists** — it has to be red first. If it
   isn't red, it isn't actually exercising the bug.
3. **Commit the test** (or stage it on the fix branch) so it guards the eventual fix in CI.
4. Once the developer's fix lands, rerun the same, unedited test — it should now **flip
   green**.

Target state: **red before the fix, green after it.**

Ways this gets defeated — none of which produce a test that genuinely fails until the bug is
actually fixed: writing the test only after the fix already merged; neutering a failing test
with pending markers, an always-true assertion, or a deleted assertion, just to keep CI
green; or building the fix first and bolting a test on afterward. Keep the assertion real
and let it go red.

The deterministic test bodies these assertions live inside are in
`references/determinism.md`.

---

## Step 6: Verify the fix actually fixes it

The developer's fix is pushed, and the regression test is now passing. **Green alone isn't
enough** — a test can pass for reasons that have nothing to do with the fix. Don't close the
ticket on green alone, and don't just take the developer's word for it. Run this validity
check:

1. **Temporarily revert the fix** (stash it, or comment out the fix line) and rerun the
   test. It should **fail again without the fix** — that's what proves the test actually
   exercises this specific bug, that it's passing *because* of the fix and not for some
   unrelated reason.
2. **Restore the fix** and confirm green comes back.
3. **Rerun several times** deterministically (`--repeat-each` or a loop) to make sure the
   green result is stable, not a one-off lucky pass.

The fix counts as verified only once the test is repeatably red-without-fix and
green-with-fix. This revert-to-verify step is the entire point of writing a regression test,
and it's the step most often skipped.

---

## Step 7: Flaky vs environment vs not-reproducible

You've spent two hours and it won't reproduce on your end, yet the user is clearly hitting
it. Don't jump to "cannot reproduce," don't assume it's flaky and quarantine it, and don't
conclude that failing to repro locally means it isn't real. These are three separate
diagnoses, each with its own tell:

| Diagnosis | Discriminating evidence | What you do |
|-----------|------------------------|-------------|
| **Flaky** | Same code, same env, **passes and fails on the same commit** — run `--repeat-each 50` (or rerun the same command many times) in *one* environment and watch it flip | Find the non-determinism (time/RNG/network/race), make it deterministic (Step 4) |
| **Environment-specific** | Reproduces only under a different config — **timezone, locale, viewport, OS, browser version, CI vs local** — and is stable within that config | Match the user's environment: reproduce *their* timezone/locale/OS/browser, then minimize |
| **Data-dependent** | Reproduces only with the user's specific account/input | Get and replicate their data/fixture; the bug rides on the input, not the platform |
| **Genuinely not reproducible** | None of the above reproduces after matching env + data + repeat runs | Document what you tried (envs, run counts, data) and the negative result — don't silently close |

What most people skip: **match the reported environment and data first**, replicating the
user's timezone, locale, OS, and browser version, then reproducing under those conditions
before drawing any conclusion. `--repeat-each` within the same environment isolates true
flakiness; a difference across environments points to environment-specificity; dependence on
particular input points to data-specificity.

---

## Step 8: Write the evidence back into the ticket

The reproduction is done and the regression test is committed. Now replace the vague
original report with a structured block instead of pasting the raw 14-step walkthrough or
writing "reproduced, closing." Include all seven elements:

1. **Minimal steps / repro command** — the smallest path, not the walkthrough.
2. **Environment + build/commit** — exact SHA and platform.
3. **Expected vs actual** — the concrete numbers.
4. **Introducing commit** — the offending commit from `git bisect`.
5. **Regression test** — link to the committed test file and path.
6. **Evidence** — logs, screenshot, trace, or artifact.
7. **Determinism notes** — seed, frozen time, and stubs so anyone can re-run identically.

A ready-to-copy Markdown template is in `references/ticket-writeback.md`.

---

## Anti-Patterns

### 1. Jumping to the fix before reproducing
Reading "total is wrong" and immediately patching the total calculation, or guessing "looks
like a rounding bug," before the failure can be triggered on demand. You cannot verify a fix
for something you never reproduced. Extract the repro first (Step 1).

### 2. Minimizing before confirming it reproduces
Stripping steps out of a repro you never confirmed actually fails. You end up "minimizing"
something that was never broken in the first place. Confirm the baseline fails, *then* cut.

### 3. Removing several variables at once
Cutting three steps in a single pass, so when the failure disappears you can't tell which
one mattered. Remove one thing at a time and rerun after each cut.

### 4. Bisecting the whole suite, or by hand
`git bisect run npm test:all` lets an unrelated failure mark commits bad; checking out
commits and testing them by hand is slow and error-prone. Point `git bisect run` at one
targeted test instead.

### 5. Exit 1 on build failure during bisect
Treating an unbuildable commit as "bug present" marks clean commits bad and derails the
search. Return **exit 125** (skip) for untestable commits, and save non-zero exits for the
real bug.

### 6. Live time, RNG, or network in the repro
Leaving `new Date()` and `Math.random` unmocked, hitting the real pricing API, or "waiting
for midnight" with a sleep call. This turns the repro into a coin flip. Freeze time, seed
the RNG, stub the network (Step 4).

### 7. Writing the test after the fix, or disabling it
Adding the regression test once the bug is already gone, or defusing a failing test with
pending markers, a tautological assertion, or a removed assertion just to keep CI green. A
test like that never actually proves it catches the bug. Write it red, before the fix.

### 8. Closing on green without revert-to-verify
"Test passes, close it." Tests can pass for the wrong reason. Revert the fix, confirm it
goes red again, then restore it and confirm green.

### 9. Closing as "cannot reproduce" on first failure to repro
Lumping flaky, environment-specific, and genuinely-not-reproducible into a single dismissal.
Match the user's environment and data, and use `--repeat-each`, before making that call
(Step 7).

---

## Failure Modes

| Symptom | Likely cause | Fix / check |
|---------|--------------|-------------|
| Bisect lands on an obviously unrelated commit | Full suite or flaky failures marking commits bad | Switch to one targeted test; wrap with exit-125 skip + network stub |
| Repro passes locally, fails in CI (or vice versa) | Environment-specific (TZ, locale, OS, browser) | Pin `TZ`/`LANG`; match the failing environment (Step 7) |
| Test is green but you're not sure it catches the bug | Never ran it red | Revert the fix and confirm it fails (Step 6) |
| `vi.setSystemTime` has no effect | Called before `vi.useFakeTimers()` | Call `useFakeTimers()` first |
| `page.clock` time not applied to app startup | `install`/`setFixedTime` ran after `page.goto` | Move clock setup before navigation |
| Repro flips pass/fail run to run | Live time/RNG/network not pinned | Apply Step 4; confirm with `--repeat-each 10` |

---

## Verification

- The repro command/test **fails on demand**: run it 10× (`--repeat-each 10` or a loop) and
  confirm it fails every time before the fix.
- `git bisect run …` terminates with "`<sha>` is the first bad commit" and `git bisect
  reset` leaves you on the original `HEAD`.
- With the fix reverted the regression test exits non-zero; with the fix applied it exits 0.
- The ticket block contains all seven write-back elements (Step 8) — grep it for the
  commit SHA, the test path, and the determinism notes.

---

## Done When

- A documented **minimal** reproduction exists — smallest steps or a single command — that
  fails on demand, verified failing across repeated runs.
- If the bug is a regression, `git bisect` has named the introducing commit SHA and it is
  recorded in the ticket.
- The repro is deterministic: time frozen, RNG seeded, network stubbed — proven by 10
  identical consecutive runs.
- A regression test is committed that was **red before the fix and green after**, and was
  confirmed to fail when the fix is reverted.
- The ticket carries the structured evidence block with all seven elements (minimal steps,
  environment/build, expected vs actual, introducing commit, regression-test link,
  evidence artifact, determinism notes); the original vague report is replaced, not left.
- If it did not reproduce, it is classified (flaky / environment-specific / data-dependent /
  not-reproducible) with the evidence that led there — never silently closed.

---

## Related Skills

- **`ai-bug-triage`** — Classify, deduplicate, and severity-route *existing* failures.
  Triage decides *whether and where* a failure matters; come here to actually *reproduce*
  one and write the failing test. Triage hands off; bug-reproduction picks up.
- **`ai-test-generation`** — Generate tests from specs/PRDs/stories. Use it when the source
  is a requirement; use this skill when the source is a *defect* and the test must first go
  red against the bug.
- **`test-reliability`** — Runtime self-healing and quarantine for a flaky test. When Step 7
  diagnoses true flakiness, go there to stabilize or quarantine; here you only diagnose.
- **`qa-project-context`** — Stack, test runner, environment matrix, and known-flaky areas
  that shape every step above. Check it first.
- **systematic-debugging** (`superpowers:systematic-debugging`) — The general root-cause
  debugging loop once you have a deterministic repro; this skill produces that repro and
  the failing test that guards the eventual fix.
