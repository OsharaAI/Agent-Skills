---
name: agentic-browser-testing
description: >-
  Goal-driven E2E testing: instead of a fixed script, a browser agent (Playwright MCP or
  computer-use) receives a plain-language objective, navigates the app on its own via the
  accessibility tree, and checks the result against an oracle you supply. Covers how to pick
  intent-driven testing over scripted testing, the levers needed to keep an agent run
  deterministic (a pinned model, temperature 0, seeded fixtures, a capped step count, an
  explicit success check, evidence based on snapshots rather than pixels), keeping cost and
  latency under control, the accessibility-tree-first interaction pattern, gating CI on the
  outcome, and turning a run that's proven stable into a scripted Playwright test. Use when:
  "agentic browser test," "goal-driven browser test," "let an agent explore the app,"
  "natural-language E2E," "browser agent smoke test," "Playwright MCP test."
  Not for: Writing/maintaining deterministic scripted Playwright tests — that is
  playwright-automation. Testing your product's OWN LLM features — that is ai-system-testing.
  Related: playwright-automation, ai-system-testing, exploratory-testing, test-reliability, qa-project-context.
license: Proprietary
metadata:
  author: osharaai
  version: "1.0"
  category: ai-qa
---

<objective>
Every hand-authored Playwright test is one relocated button or one renamed CSS class away from
breaking, and keeping that test alive against a dashboard that reshapes itself weekly is a
never-ending chore. This skill sets up the alternative: a browser agent that works from intent.
Hand it a plain-language goal, and it finds its own path through the interface by reading the
accessibility tree (Playwright MCP's `browser_snapshot`), then checks what happened against an
oracle that you — not the model — define. The specific trap it's built to avoid is the one that
destroys confidence in agents fastest: a run that reports "success" while it's actually still
sitting on the login page, because nothing ever forced it to prove where it landed. What comes
out the other end is a deterministic, CI-gated agent run, with a defined path for turning it into
a permanent scripted test once the underlying flow stops changing.
</objective>

## Fast Lookup

| Situation | Go to |
|-----------|-------|
| Stand up a goal-driven run from scratch | Discovery + `references/setup.md` |
| Decide agentic vs scripted for a given flow | Fit: Intent-Driven vs Scripted |
| Agent passes one run, fails the next | Determinism |
| "How does it click without screenshots?" | Interaction Model |
| Runs are slow / burning tokens | Cost and Latency |
| Agent reports false success | Success Assertion (the Oracle) |
| Flow is stable — make it permanent | Graduation → `references/graduation-and-ci.md` |
| Block a merge on the goal | CI Gating → `references/graduation-and-ci.md` |
| Canvas / no accessibility tree | Canvas Fallback → `references/graduation-and-ci.md` |

## Questions to Settle Before Starting

Look at `.agents/qa-project-context.md` in the repo root before anything else, and treat whatever
it already answers (stack, environments, seed/reset tooling, model access) as decided.

1. **What flow is this, and how often does its UI shift?** Fast-moving or experimental surfaces
   favor an intent-driven agent; a stable, heavily-trafficked path like login favors a script.
   This one question sets the whole strategy.
2. **Does seeded fixture data exist with a dependable reset step?** Without seeded data and a
   reset between runs, you cannot get determinism — close that gap before anything else.
3. **Can the agent skip authentication via a deep link to a seeded starting state?** Re-running
   login every single pass wastes the most time; a seeded entry URL shrinks the goal and the step
   count.
4. **What proves success, unambiguously?** Look for something concrete — exact account text, a
   `/dashboard` URL, an order number — paired with something that must be absent. "No error
   appeared" is not an oracle.
5. **Is the target rendered via canvas or WebGL?** No accessibility tree means snapshot-driven
   interaction is off the table; you'll need vision-based fallback or ARIA instrumentation on the
   canvas.
6. **Which model, and what's the spending ceiling?** Pick a specific model id and a step cap
   before you start. Route routine steps to cheaper models (Haiku 4.5 / Sonnet 4.6), and reserve
   Opus 4.8 for flows that are genuinely open-ended.

---

## Guiding Principles

1. **Only bring in intent-driven testing where UI churn earns its cost.** Because the agent reads
   a goal and finds its own route through the accessibility tree, a moved button or a renamed
   class doesn't break it the way a hardcoded selector would. That resilience costs 2-5x the time
   and money of a script, so spend it where the UI is genuinely volatile or hard to target — not
   on paths that barely change.

2. **An agent run only counts as trustworthy once it's deterministic.** The same goal run against
   the same seeded app must produce the same verdict every time — which means temperature 0, a
   pinned model id, seeded and reset data, a hard step ceiling, and an explicit pass/fail check.
   Drop any one of these and what you have is randomness dressed up as a test.

3. **The model never decides pass/fail — that judgment stays in your harness.** Never accept a
   self-graded "looks good" from the agent. Success must be a checkable assertion against the
   final `browser_snapshot`: specific expected text, a URL match, and confirmation that a
   forbidden state is absent — verdict computed by your harness, never by the model.

4. **Default to the accessibility tree; pixels are the exception, not the rule.** A
   `browser_snapshot` gives you roles, refs, and accessible names in roughly 200-400 tokens, and
   it's cheap and deterministic. Screenshots, coordinate-based clicking, vision models, and OCR
   only belong in canvas-only situations — never as your starting point.

5. **The finish line is graduation, not an agent that runs forever.** Once a flow proves stable,
   convert its run into a durable `tests/*.spec.ts` file built on role-based locators. A goal
   that's stayed green for two weeks should become a fast, zero-cost regression test — keep the
   agent for exploration, not for indefinitely babysitting something that's already settled down.

---

## Choosing Between Intent-Driven and Scripted

Decide per-flow, not for the whole project. If you need a risk map first, run
`risk-based-testing` — the table below is the routing logic once you have one.

| Flow characteristic | Use | Why |
|---------------------|-----|-----|
| Stable, high-frequency critical path (login, payment) | **Scripted + pinned** (`playwright-automation`) | Runs every PR; needs to be fast, free, and deterministic. Re-exploring it buys nothing. |
| Fast-changing / experimental UI (a dashboard that churns weekly, a redesign in flight) | **Agentic / intent-driven** | Selectors would keep breaking; a goal rides out layout churn. |
| Flow you can't reliably target with a selector | **Agentic** | The agent locates the control by role/name rather than you reverse-engineering a selector. |
| Exploratory smoke / "is the happy path still alive" | **Agentic** | A single NL goal covers a lot of ground with nothing to maintain. |
| Anything in CI that must never falsely pass | Scripted, OR agentic **with a hard oracle** | Non-determinism is a false-pass risk that has to be actively capped. |

**Bottom line:** stable, critical paths stay on pinned scripted tests; point intent-driven agents
at UI that's still in flux and at exploratory smoke checks. Don't move everything to the agent —
it's slower, costlier, and non-deterministic by nature, and that tradeoff isn't worth it
everywhere.

---

## How the Interaction Actually Works (accessibility-tree-first)

Playwright MCP isn't computer-use with screenshots and pixel coordinates — it's built around the
accessibility tree:

1. `browser_navigate` loads the seeded entry URL.
2. `browser_snapshot` returns the **accessibility tree**: every interactive element as a `role`,
   a stable `ref`, and an `accessible name` sourced from ARIA/labels — roughly 200-400 tokens.
3. The agent picks an element by its `ref` and fires `browser_click` or `browser_type`.
4. `browser_wait_for` waits for specific text to appear or vanish — never a fixed sleep.
5. Once the DOM has updated, the agent takes a fresh `browser_snapshot` and asserts against it.

Why avoid screenshots: a snapshot costs far fewer tokens than an image, matches deterministically
against text refs instead of fuzzy pixels, and needs no vision model or OCR pass. Making
screenshots the primary input just makes everything slower, pricier, and flakier.
`browser_take_screenshot` is there purely for human-readable evidence — never feed it into an
assertion.

The full MCP registration, tool reference, and goal prompt template live in
`references/setup.md`.

---

## Determinism: Earning a Place in CI

If the same run passes once and fails the next time with nothing in the app having changed, it
isn't a test yet — and the fix is never "just retry it" or cranking up temperature to make the
agent "smarter." Pin down every variable instead:

| Lever | Setting |
|-------|---------|
| Model | **Pinned model id** (e.g. `claude-haiku-4-5-20251001`), never `latest` |
| Sampling | **temperature 0** — no creative wandering in CI |
| Data | **Seeded fixture + reset/seed the database** before every run |
| Scope | **Bounded step budget** (`maxSteps`), e.g. 18 — exceeding it FAILS, never auto-retries |
| Oracle | **Explicit pass/fail verdict** asserted against the snapshot |
| Evidence | Assert on the **accessibility tree**, never a screenshot diff |

Avoid: temperatures like `0.7` or `1` in the name of "better" exploration, retry-until-it-passes
loops, `waitForTimeout` sleeps, and pixel-by-pixel screenshot comparison. All of these mask
flakiness rather than remove it. The full harness config lives in `references/setup.md`.

---

## The Oracle: Where Agents Quietly Fail

Watch this failure mode above all others: an agent claims success while it's actually stuck on
the login page, because "the page loaded," "no error appeared," or "it looks fine" was accepted
as proof — with the model grading its own work. The fix is a mandatory, harness-checked oracle.

For a goal like *"sign in as an existing user and confirm the dashboard shows the right account
name"*:

```text
SUCCESS (all must hold — assert against the final browser_snapshot):
  - URL matches /dashboard
  - Snapshot contains the specific expected account name text, e.g. "Acme Corp — Jane R."
NEGATIVE / forbidden state (fail fast if any is true):
  - Still on a URL matching /login  → FAIL
  - Snapshot contains role="alert" with "invalid credentials"  → FAIL
VERDICT: harness emits {"passed": true|false}; the LLM does not decide.
```

The positive checks (specific account name plus `/dashboard` URL) confirm where the agent
actually ended up; the **negative check** — verifying it isn't still on the login screen — is
what stops false passes. "No error," "didn't crash," "screenshot looks right," and "just trust
the agent" are never acceptable success criteria.

---

## Managing Cost and Latency

Agent runs will run 2-5x slower and pricier than the scripted equivalent, because every step is
an LLM round-trip and that dominates the cost. Cut spend by narrowing scope, not by throwing more
model at it:

- **Step budget** — enforce a low `maxSteps`; fewer round-trips means less drift.
- **Model tiering** — send cheap navigation steps to Haiku 4.5 / Sonnet 4.6, and hold Opus 4.8
  back for genuinely ambiguous exploration. Don't run the biggest model on every step.
- **Prompt caching** — cache the static system prompt, tool schemas, and goal text since they're
  identical run to run.
- **Seeded entry points** — scope each run to a single narrow goal, deep-linked past login rather
  than re-driving it each time.
- **Snapshots over screenshots** — an accessibility snapshot costs ~200-400 tokens versus
  thousands for a full-page screenshot. Default to the snapshot.

Push back on: "just use a bigger model / Opus 4.8 for every step," "raise the step limit,"
"screenshot every step," or running with no budget cap whatsoever. Details in
`references/setup.md`.

---

## Graduating a Run and Gating CI On It

Once a goal stabilizes, turn it into a durable scripted test and make merges depend on its
verdict. Full detail lives in `references/graduation-and-ci.md`; the short version:

- **Graduate** with **Playwright Test Agents** (planner / generator / healer, shipped since
  Playwright **v1.56.0**): `npx playwright init-agents --loop=claude`. The **planner** writes a
  Markdown test plan to `specs/<flow>.md`; the **generator** turns that plan into
  `tests/<flow>.spec.ts` using **role-based locators** (`getByRole`, `getByLabel`, `getByText`)
  verified against the live DOM; the **healer** repairs locators that break later. This is the
  intended promotion path — not "leave it running as an agent forever," not recorded clicks, not
  `page.locator('xpath=...')`, and not relying solely on data-testid.
- **Gate CI** so a failed goal exits **non-zero** and produces a **machine-readable** verdict
  (`{"passed": true|false}` written to `result.json`); a GitHub Actions job reads that boolean and
  calls `exit 1` when it's false. Keep state seeded and ephemeral, reset every run, and enforce
  both a step budget and a timeout. Never use `continue-on-error: true`, never force a zero exit
  code regardless of outcome, and never leave the verdict as prose for a person to interpret.
- **Canvas with no accessibility tree:** instrumenting the canvas with ARIA is the preferred fix;
  only as a scoped last resort should you flip on `--caps=vision` to unlock
  `browser_mouse_click_xy`, and only for that one flow. `browser_snapshot` simply returns nothing
  useful on raw canvas — that's not a reason to make coordinate clicking your default or to
  abandon agentic testing altogether.

---

## Converting a Brittle Script Into a Goal (with honest caveats)

Turning an 80-line script that re-types login credentials and walks through 6 hardcoded steps
into one natural-language **goal** with an **explicit success assertion** is a real win for a
flow that keeps shifting — but be honest about the tradeoffs:

- **Non-determinism / false-pass risk** — the run can pass when it shouldn't; that's exactly why
  the hard oracle and negative check are mandatory, never optional.
- **Cost/latency** — plan on 2-5x slower runs; keep that bounded with a step budget and a seeded
  entry point.
- **Not everything should move** — stable paths stay scripted, and this goal should be planned
  from the outset to graduate back into a scripted test once it settles.

Don't oversell it: it's **not** "strictly better with zero downsides," you should **not**
"migrate everything" to it, and you should never loosen the assertions just to make it pass.

---

## Common Mistakes

### 1. Defaulting to a scripted test out of habit
The words "browser test" tend to trigger a codegen reflex — `page.goto`, `page.locator`,
`await expect(page...)`, digging for a `data-testid`. That's the wrong instinct here: a
goal-driven agent starts from plain-language intent and finds its own way via
`browser_snapshot`, with no selectors pre-written anywhere.

### 2. Overcorrecting into "the agent replaces everything"
Enthusiasm can swing too far the other way. The agent is inherently 2-5x slower and not
deterministic out of the box. Critical, stable paths like login should stay scripted and
version-pinned — intent-driven testing earns its keep specifically on UI that keeps moving.
Neither "always use the agent" nor "agents replace scripted tests entirely" should become policy.

### 3. Masking flakiness with retries or a hotter temperature
Retrying until it passes, or nudging temperature up hoping for "smarter" exploration, both add
noise rather than remove it. The real remedy is temperature 0, a pinned model id, seeded data, a
capped step budget, and a verdict that's checked explicitly.

### 4. Confusing this with screenshot-and-coordinate computer-use
Playwright MCP defaults to the accessibility tree, not vision. Falling back to screenshots, OCR,
or `mouse_click_xy` as a default choice is slower, pricier, and less reliable — pixel-based
interaction is reserved strictly for canvas situations.

### 5. Letting "nothing broke" count as success
If "the page loaded," "no error showed up," or "it looks fine" is treated as sufficient — and the
model is left to grade itself — you get exactly the failure mode this skill guards against: a
run that reports success while sitting on the login page. Insist on specific expected text, a URL
match, and a negative check for a forbidden state, all evaluated outside the model.

### 6. Chasing speed with a bigger model or a looser step cap
Counterintuitively, running Opus 4.8 on every single step or raising `maxSteps` makes runs slower
and pricier without making them any more reliable. Reliability comes from smaller models where
possible, tight budgets, caching, and a narrower scope — not a bigger hammer.

### 7. Never graduating a stable run
Leaving an agent to babysit a flow that's been green for two weeks, rather than converting it
into `tests/*.spec.ts` via Playwright Test Agents, wastes the whole point of graduation. Recorded
clicks and xpath locators are not acceptable substitutes for that promotion step.

### 8. Letting CI trust a prose summary
If the pipeline accepts a written explanation instead of a boolean, or sets
`continue-on-error: true`, a genuinely failing goal can merge anyway. The job must exit non-zero
on failure and hand CI a verdict it can parse.

---

## Definition of Done

- The goal is written as plain-language intent — no `page.locator`, `page.goto`, or
  `data-testid` embedded in it — and includes a seeded START URL.
- Success is defined explicitly: matching text, a URL check, and a forbidden-state negative
  check, all evaluated against `browser_snapshot` rather than a screenshot.
- The run configuration pins a model id, sets `temperature: 0`, defines a `maxSteps` ceiling, and
  fixes a seed — with no `waitForTimeout` sleeps and no retry-until-pass logic.
- Interaction stays snapshot-first throughout: `browser_navigate`, `browser_snapshot`,
  `browser_click`, `browser_type`, `browser_wait_for` — screenshots appear only as supporting
  evidence, never as the assertion source.
- The runner writes `result.json` as `{"passed": true|false}` and exits non-zero on failure; CI
  gates the merge on that boolean, with no `continue-on-error` and no forced zero exit.
- CI resets and seeds state fresh for every run, and enforces both a step ceiling and a timeout.
- There's a documented trigger for graduation (for instance: "two weeks green → run
  `init-agents`, generate `tests/<flow>.spec.ts` with `getByRole` locators").
- Any canvas/WebGL target either gets ARIA instrumentation or a narrowly scoped
  `--caps=vision` + `browser_mouse_click_xy` fallback limited to that one flow.

---

## Related Skills

- **playwright-automation** — Writing and maintaining deterministic scripted Playwright tests
  and Page Objects. Go there to author the durable test; this skill graduates an agent run into one.
- **ai-system-testing** — Testing your product's OWN LLM/AI features (prompt regression, model
  output quality). This skill tests any app *using* an agent; it does not test your AI feature.
- **exploratory-testing** — Human SBTM exploration and bug hunting. The agentic smoke goal is
  the automated cousin; use exploratory-testing for charter-driven manual sessions.
- **test-reliability** — Self-healing locators and quarantine for *scripted* flaky tests at
  runtime. Complements the determinism levers here once a test has graduated.
- **qa-project-context** — The universal dependency; supplies stack, environments, seed/reset
  tooling, and model access that every question above depends on.

## Reference Files (in `references/`)

- **setup.md** — Playwright MCP registration (`.mcp.json`), the snapshot tool table, the
  natural-language goal prompt with success/negative assertions, the determinism harness
  config (pinned model, temperature 0, maxSteps, seed, prompt cache), and cost/latency levers.
- **graduation-and-ci.md** — Playwright Test Agents promotion pipeline (planner → `specs/*.md`,
  generator → `tests/*.spec.ts` with role-based locators, healer), the GitHub Actions gating
  workflow with a machine-readable boolean verdict, and the canvas `--caps=vision` fallback.
</content>
