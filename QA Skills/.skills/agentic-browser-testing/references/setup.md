# Agentic Browser Test Setup

Concrete configuration for running a goal-driven browser agent on Playwright MCP, including the
determinism harness that SKILL.md points to.

## 1. Install and register Playwright MCP

Playwright MCP works off the accessibility tree by default: every interaction returns a
structured `browser_snapshot` of roles, refs, and accessible names (roughly 200-400 tokens)
rather than a screenshot. Pixels are not the default input to the model.

```jsonc
// .mcp.json (Claude Code) — register the server, headless, deterministic
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": [
        "@playwright/mcp@latest",
        "--headless",
        "--isolated",                 // fresh profile each run, no leaked state
        "--viewport-size=1280,720"    // pin viewport so the a11y tree is stable
      ]
    }
  }
}
```

Core tools the agent has available — all ref/snapshot based, none of them coordinate-driven:

| Tool | Purpose |
|------|---------|
| `browser_navigate` | Go to the seeded entry URL |
| `browser_snapshot` | Capture the accessibility tree (role / ref / accessible name) |
| `browser_click` | Click an element by its `ref` from the latest snapshot |
| `browser_type` | Type into a field by `ref` |
| `browser_wait_for` | Wait for text to appear/disappear (NOT a fixed sleep) |

`browser_take_screenshot` exists too, but strictly for human-readable evidence and debugging —
never wire it into an assertion.

## 2. The goal prompt (this is the whole point — no script involved)

The agent is given a plain-language goal plus an **explicit success assertion**, then finds and
clicks its own way through via `browser_snapshot`. Nowhere in this does `page.goto`,
`page.locator`, or `data-testid` hunting appear.

```text
GOAL: Complete a guest checkout for one in-stock item and reach the order
      confirmation page.

START: navigate to {{SEEDED_URL}}/products/seed-sku-001  (seeded, in stock)

RULES:
- Read the accessibility snapshot to find controls; act by ref.
- Bounded to {{MAX_STEPS}} steps. If you cannot progress, FAIL — do not loop.
- Do NOT invent data; use the seeded fixture values only.

SUCCESS (all must hold — assert against the final browser_snapshot, not a screenshot):
- URL matches /order/confirmation/.+
- Snapshot contains text "Order confirmed" AND an order number matching /#\d{6,}/
NEGATIVE (forbidden state — fail fast if seen):
- Still on a URL matching /checkout|/cart  → FAIL
- Snapshot contains role="alert" with "payment failed" → FAIL

OUTPUT: a single JSON object {"passed": true|false, "evidence": "...", "steps": N}
```

That negative check is what keeps the agent honest instead of letting it self-report "looks
fine" while genuinely stuck.

## 3. Determinism harness

Everything the model or the app could vary needs to be pinned down:

```jsonc
// agent-run.config.json
{
  "model": "claude-haiku-4-5-20251001",  // PINNED id, not "latest"
  "temperature": 0,                        // no creative exploration in CI
  "maxSteps": 18,                          // step budget — hard cap, fail past it
  "maxTokens": 120000,                     // token budget guardrail
  "seed": "checkout-seed-001",             // seeded fixture / DB reset key
  "promptCache": true                      // cache the static goal + tool defs
}
```

Ranked by impact:

1. **temperature 0 + a pinned model id** — same inputs give the same trajectory every time; never
   use `latest`.
2. **Seeded data plus a DB reset** before each run — this removes the app itself as a variable.
3. **A bounded step budget** — controls both cost and non-determinism; a run that overruns it is
   a failure, never a candidate for retry.
4. **An explicit pass/fail assertion** — a genuine true/false oracle rather than "no error."
5. **Snapshot-based assertions** — check the accessibility tree, never pixels.

Avoid: raising temperature in hopes of "smarter" exploration, `retry-until-pass` loops,
`waitForTimeout` sleeps, or diffing screenshots. Each of these hides flakiness instead of
resolving it.

## 4. Cost and latency controls

Expect agent runs to cost 2-5x more time and money than an equivalent script. Manage that without
cutting coverage:

| Lever | How |
|-------|-----|
| Step budget | Keep `maxSteps` low and enforced; each step is an LLM round-trip and the dominant cost |
| Model tiering | Haiku 4.5 / Sonnet 4.6 for cheap navigation steps; save Opus 4.8 for flows that are genuinely ambiguous |
| Prompt caching | Cache the static system prompt, tool schemas, and goal text — they don't change run to run |
| Scope | One narrow goal per run, starting from a **seeded entry point** deep-linked past login rather than replaying it |
| Snapshot over screenshot | An a11y snapshot costs ~200-400 tokens against thousands for a screenshot — default to it |

Avoid the instinct to reach for "a bigger model on every step," "more max steps," or
"screenshot every step" — none of those buy reliability, they just spend more.
</content>
