# Graduation to Scripted Tests + CI Gating

How to turn a stabilized agent run into a durable scripted Playwright test, and how to gate a
merge on an agent's goal outcome. Referenced from SKILL.md.

## Graduation: agent run → scripted `tests/*.spec.ts`

Once a goal has been green for roughly two weeks and the underlying flow has settled, stop paying
the per-run agent cost. Promotion happens through **Playwright Test Agents** (planner / generator
/ healer), available from Playwright **v1.56.0** onward, which run over MCP and integrate with
Claude Code.

```bash
npm i -D @playwright/test@latest        # v1.56+ for Test Agents
npx playwright init-agents --loop=claude # generates planner/generator/healer definitions
```

The pipeline works like this:

1. **Seed test** — write `tests/seed.spec.ts` to bootstrap a ready `page` (global setup,
   fixtures, login). Both the planner and generator build on it.
2. **Planner** — walks the now-stable flow and writes a readable Markdown plan to
   `specs/<flow>.md` (e.g. `specs/checkout.md`).
3. **Generator** — reads that plan, opens the live app, checks locators against the real DOM,
   and produces `tests/<flow>.spec.ts` using **role-based locators** (`getByRole`, `getByLabel`,
   `getByText`) with genuine assertions.
4. **Healer** — when a generated test later fails, replays it, locates the equivalent element,
   swaps in a stable locator, and reruns.

```ts
// tests/checkout.spec.ts  — generated from specs/checkout.md
// Role-based locators, NOT xpath, NOT data-testid-only, NOT recorded clicks.
import { test, expect } from '../fixtures';

test('guest checkout reaches confirmation', async ({ page }) => {
  await page.goto('/products/seed-sku-001');
  await page.getByRole('button', { name: 'Add to cart' }).click();
  await page.getByRole('link', { name: 'Checkout' }).click();
  await page.getByLabel('Email').fill('seed@example.test');
  await page.getByRole('button', { name: 'Place order' }).click();
  await expect(page).toHaveURL(/\/order\/confirmation\//);
  await expect(page.getByText('Order confirmed')).toBeVisible();
});
```

From here the generated test runs on every PR in milliseconds at zero LLM cost. Keep the original
agent goal around only for occasional exploratory smoke checks — the scripted test is now the
regression guard.

Don't: leave it running as an agent indefinitely, record clicks into the suite, or hand-write
`page.locator('xpath=...')`. Durable, role-based locators are the entire point of graduating.

## CI gating: a failed goal has to block the merge

The agent run needs to exit **non-zero** on failure and produce a **machine-readable** verdict.
CI reads a boolean — nobody is reading prose, and nothing is grepping an explanation.

```yaml
# .github/workflows/agentic-smoke.yml
name: agentic-smoke
on: pull_request
jobs:
  smoke:
    runs-on: ubuntu-latest
    timeout-minutes: 10            # hard timeout cap on the whole job
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: npm ci
      - name: Seed ephemeral state
        run: npm run db:reset && npm run seed:checkout   # fresh, seeded, isolated
      - name: Run agent goal
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: node scripts/run-agent-goal.mjs --config agent-run.config.json
        # script enforces maxSteps/timeout and writes result.json {"passed":bool}
      - name: Gate the merge on the boolean verdict
        run: |
          test "$(jq -r .passed result.json)" = "true" || exit 1
```

The runner script (`run-agent-goal.mjs`) needs to:

- Enforce the **step budget** and a wall-clock **timeout** internally, aborting once either is
  exceeded.
- Write a structured `result.json` shaped like `{ "passed": true|false, "evidence": "...",
  "steps": N }`.
- Call `process.exit(passed ? 0 : 1)` so a failed goal actually fails the job.

Patterns that quietly defeat the gate:

- `continue-on-error: true` / `allow_failure: true` — the merge goes through even on red.
- Forcing exit 0 regardless of outcome, or handing back prose for a human to interpret.
- Reusing shared, long-lived state instead of fresh, seeded fixtures per run.

## Canvas / vision fallback (a scoped last resort)

A `<canvas>`-based app (chart editor, WebGL surface, Figma-style tool) has no accessibility tree
at all, so `browser_snapshot` comes back with nothing actionable — it will not "just work" against
raw canvas.

The preferred fix is to **instrument the canvas**: add ARIA roles, accessible names, or an
offscreen DOM mirror so the snapshot-driven model can operate it like anything else. That keeps
the rest of the suite snapshot-first.

If you genuinely can't modify the app, there's an escape hatch — but scope it to that one flow:

```jsonc
// scoped MCP config for the canvas suite ONLY
{ "args": ["@playwright/mcp@latest", "--headless", "--caps=vision"] }
```

`--caps=vision` unlocks `browser_mouse_click_xy { x, y }` using viewport-relative coordinates.
Treat it as a documented, narrowly-scoped last resort for just the canvas region — don't flip the
whole suite over to coordinates, don't disable the accessibility tree globally, and don't give up
on agentic testing wholesale; contain the pixel interaction to the single element that actually
needs it.
</content>
