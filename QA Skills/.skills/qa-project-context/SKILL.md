---
name: qa-project-context
description: >-
  Create and fill .agents/qa-project-context.md with the project's tech stack, test
  frameworks, CI/CD pipeline, environments, quality goals, risk areas, team structure,
  and conventions. This is the one file every other QA skill reads first, so they skip
  redundant discovery and give context-aware advice.
  Use when: "set up QA context," "configure testing," "initialize project," first use of any QA skill.
  Not for: bootstrapping a brand-new project's QA end-to-end — use qa-start (which calls this skill as its first step).
  Related: qa-start, risk-based-testing, test-strategy, qa-metrics, playwright-automation.
license: Proprietary
metadata:
  author: osharaai
  version: "2.0"
  category: foundation
---

<objective>
This skill produces the one document every other QA skill relies on. Skip it, and each
skill has to re-ask "what framework? what CI? where do tests live?" from a blank slate,
which means shallower, more generic advice. The output is `.agents/qa-project-context.md`
at the project root, covering product, tech stack, test stack, CI/CD, environments,
quality goals, risk areas, team, and conventions — fully filled, with no
`[bracketed placeholders]` remaining.
</objective>

Other skills draw on specific sections of this file: `risk-based-testing` and
`test-strategy` pull from Risk Areas; `playwright-automation` and `test-reliability` pull
selector conventions from Conventions; `qa-metrics` pulls from Quality Goals; and every
automation skill leans on Tech Stack. Get those sections right and the whole library
benefits.

## Discovery Questions

Start by checking whether `.agents/qa-project-context.md` already exists. If it does,
read it and skip any section that's already filled in (no `[brackets]`). Next, scan the
repo for config files (see Codebase Detection) and present what you find for the user to
confirm, rather than asking blind. Work through the remaining questions **one section at
a time** — never dump them all at once.

### Product
- What's the product's name and its one-sentence description?
- What kind of product is it — SaaS, e-commerce, media, mobile app, internal tool? This shapes which flows matter most.
- What are the production, staging, and dev URLs?
- Name the 5–10 user journeys that matter most — the "if this breaks, someone gets paged at 2am" list. Every other skill uses this to prioritize coverage.

### Tech Stack
- What's the frontend framework/language? Backend framework, language, API style (REST, GraphQL, tRPC, gRPC)?
- Database, caching layer, ORM? Where's it hosted, what CDN, what monitoring?
- Is it a monorepo? If so, each app needs its own entry (see the Monorepo note) — sharding and detection work differently.

### Test Stack
- Any E2E tests currently? Which framework, where's the config, where do tests live? Same questions for unit, API, visual, and performance testing.
- If config files reveal a framework already, fill in Test Stack with its name, version, and path directly — don't re-ask.
- No test infrastructure at all is a legitimate answer — write "None selected yet" and note the recommended default (Core Principle 3).

### CI/CD
- Which platform? What triggers test runs (push, PR, nightly, manual)? Any sharding or parallelism?
- What has to pass before a deploy, and what gets archived (screenshots, reports, coverage)?

### Environments
- How many environments exist, and what are their URLs? How closely does staging mirror production — infra, data, third-party integrations?
- Does dev use mocked services or real APIs? Environment parity is a key driver of test reliability.

### Quality Goals
- Any current coverage targets? Acceptable flake rate? Time budget for the suite? Metrics already tracked, or ones they'd like?
- No targets set yet? Propose reasonable ones based on maturity (see the Quality Goals section below).

### Risk Areas
- Which areas cause the most incidents in production? Which integrations are least reliable (payments, email, other third parties)?
- Where does high churn meet low coverage? Score each with Impact × Likelihood (details under Risk Areas).

### Team
- QA headcount and specialties? What's the developer-to-QA ratio? What methodology do they follow (Scrum, Kanban, Shape Up)?
- At what point does QA get involved — shift-left at the spec stage, or only after development? This determines who owns automation.

### Conventions
- What naming pattern do test files follow? Co-located with source or kept separate? What's the branching model and PR gate?
- What's the E2E selector strategy? How is test data managed — factories, fixtures, a seeded DB, per-test API calls?

## Core Principles

1. **This file is the single source of truth for the whole skill library.** Every other
   skill reads `.agents/qa-project-context.md` before doing anything else. Copying its
   facts elsewhere just invites drift — keep the canonical stack, goals, and risk data
   here, and have other skills reference it rather than duplicate it.

2. **Record reality, not aspiration.** No E2E tests? Write "None selected yet" — not a
   wish list. Downstream skills branch on the truth: a genuinely missing framework
   triggers a setup recommendation, while a fictional one leads them to build on nothing.

3. **Detect first, ask only when detection comes up empty.** Read `package.json` and
   other config files before asking anything, then confirm what was found. Recommending
   specific tools is the job of specialized skills, not this one — except for the single
   carve-out where there's zero existing test infrastructure, in which case note
   **Playwright** for E2E and **Vitest** for unit as defaults in Test Stack, then route to
   `playwright-automation` / `unit-testing`. Outside that one case, this skill only
   records — it doesn't recommend.

4. **Never shortchange Risk Areas — it's the section with the most downstream value.**
   `risk-based-testing` and `test-strategy` both build directly on it. Push for at least
   3–4 impact/likelihood-scored entries, even if the user insists nothing's at risk.

## Codebase Detection

Before asking stack questions, scan for these files. Show the user what was detected and
confirm it; when a test config turns up, write that framework straight into Test Stack
instead of asking again.

| File | Indicates |
|------|-----------|
| `package.json` | Node.js project — check `dependencies` for the framework |
| `next.config.*` | Next.js |
| `nuxt.config.*` | Nuxt/Vue |
| `angular.json` | Angular |
| `astro.config.*` | Astro |
| `react-router.config.ts` | React Router 7 / Remix |
| `requirements.txt` / `pyproject.toml` | Python project |
| `go.mod` | Go project |
| `playwright.config.*` | Playwright is set up → populate Test Stack E2E |
| `cypress.config.*` | Cypress is set up → populate Test Stack E2E |
| `vitest.config.*` / `jest.config.*` | Unit test framework → populate Test Stack Unit |
| `.github/workflows/` | GitHub Actions CI |
| `.gitlab-ci.yml` | GitLab CI |
| `Jenkinsfile` | Jenkins |
| `docker-compose.*` | Docker-based environments |
| `wrangler.*` | Cloudflare Workers |
| `vercel.json` | Vercel hosting |
| `bun.lock` / `bun.lockb` | Bun runtime |
| `pnpm-workspace.yaml` / `turbo.json` / `nx.json` | Monorepo — handle per the Monorepo note |
| `src-tauri/tauri.conf.json` | Tauri desktop app |
| `.claude/` | Project uses Claude Code skills/agents |
| `.claude-plugin/plugin.json` | Project ships a Claude Code plugin |
| `AGENTS.md` | Codex / multi-agent workflow conventions |

## Workflow: Creating the Context File

1. **Look for an existing file.** Check the project root for `.agents/qa-project-context.md`.
2. **Not there?** Create `.agents/` if it doesn't exist, lay out the section skeleton, run
   through the Discovery Questions starting with Product, and write the file once it's
   filled in.
3. **There but incomplete:** read it, note which sections are done versus still bracketed,
   ask only about the unfilled ones, and update — leaving finished sections exactly as
   they were.
4. **There and complete:** recap the current context, ask what's changed since (new
   tooling, team shifts, new goals), and update only what changed.
5. **Once done:** confirm the file's path, run the Verification steps below, and point to
   the logical next skill based on what's in the file (no E2E → `playwright-automation`;
   no strategy → `test-strategy`; no unit tests → `unit-testing`).

Two fully filled-in example files (a SaaS product and a multi-site publisher), plus the
monorepo layout, live in `references/examples.md`. Here's a quick illustrative snippet:

```markdown
## Test Stack
### E2E / Integration
- **Framework:** Playwright 1.60
- **Config Location:** playwright.config.ts
- **Test Directory:** tests/e2e/
### Unit / Component
- **Framework:** None selected yet — Vitest recommended (see unit-testing)
```

## Section Guidance

Here's what a strong entry looks like in each section. The blank template itself lives at
`.agents/qa-project-context.md` in the qaskills repo.

**Product.** Key flows need to be concrete and testable — "Buyer searches products, adds
to cart, checks out with Stripe, receives confirmation email," not "user uses the app."
Every test skill prioritizes off this list, so aim for 5–10 entries.

**Tech Stack.** Log frontend, backend, database, and hosting as separate items. Only pin a
version when it actually changes how you'd test (App Router vs. Pages Router is a real
difference). Pull the version from `package.json` rather than copying whatever an example
happens to show.

**Test Stack.** For every tool, capture framework name plus version, config location, and
test directory. "None selected yet" plus the recommended default is a fine entry when
there's no infrastructure (per Principle 3).

**Monorepo.** Give each frontend app its own Tech Stack and Test Stack entry, but keep the
shared API/backend as a single entry. E2E sharding should happen **per app** — a change in
`apps/admin` shouldn't kick off `apps/storefront`'s E2E suite — and CI/CD should note which
path filters gate which app. Look for `turbo.json` / `pnpm-workspace.yaml` / `nx.json` as
the detection signal. Full example in `references/examples.md`.

**CI/CD.** Cover what downstream skills actually need to know: what blocks a deploy, how
quickly feedback arrives, and what evidence gets kept.

**Environments.** Call out where staging and production diverge — a different database
engine in staging, for instance, means a green staging run doesn't guarantee prod success.

**Quality Goals.** Keep these concrete and measurable. Starting points by maturity level:

| Maturity | Unit coverage | E2E | Flakiness | Suite duration |
|----------|--------------|-----|-----------|----------------|
| Early-stage startup | 60% on business logic | Top 5 critical flows | <2% | Unit <3 min, E2E <15 min |
| Growth-stage | 80% | All critical paths | <2% | Unit <3 min, E2E <15 min |
| Enterprise | 90%+ | Comprehensive + perf budgets | <1% | Unit <3 min, E2E <15 min |

State them as numbers — "80% line coverage measured by Istanbul," "flake rate <2% over a
rolling 30-day window," "full E2E under 15 min with 4 shards" — never "we want great
quality."

**Risk Areas.** Use a table with columns for Area, Risk Level, Business Impact, and Notes,
scored on **Impact × Likelihood**:

- **Critical (test first):** high impact + high likelihood (payment flow with known edge cases).
- **Important:** high impact + low likelihood (auth — catastrophic if broken, rarely changes).
- **Monitor:** low impact + high likelihood (notification formatting — breaks often, low severity).
- **Backlog:** low impact + low likelihood (admin settings — stable, rarely used).

Get at least 3 entries — nothing vague like "everything breaks."

**Team.** Log the real headcount and dev:QA ratio, since that's what determines the
ownership model:

| Dev:QA ratio | Ownership model |
|--------------|-----------------|
| Solo / zero QA (effectively infinite) | Devs own all tests. No manual regression suite; lean on low-barrier automation (Playwright + Vitest) and CI gates. QA "role" = strategy + critical-path E2E, done by the dev. |
| High (8:1+) | Developers write tests; QA focuses on strategy, critical-path automation, exploratory testing. |
| Balanced (4:1) | QA owns E2E, devs own unit, integration shared. |
| QA-heavy (<3:1) | Dedicated automation engineers, comprehensive regression suites, scheduled exploratory cadence. |

**Conventions.** Selector strategy matters most here, since `playwright-automation` and
`test-reliability` use it to generate matching selectors. Default to `data-testid` for
stability (e.g. `data-testid="invoice-create-button"`, kebab-case). If the team prefers
semantic/ARIA selectors for accessibility-aware testing, capture the exact patterns —
`role="button"`, `role="heading"`, `getByRole('link', { name: ... })` — along with the
tradeoff: ARIA roles double as accessibility assertions and hold up through markup
changes, but are more fragile than `data-testid` when copy or roles shift, so pin a
`name`/`level` to keep them unambiguous.

## Anti-Patterns

### 1. Asking all questions at once
Firing off 30 questions overwhelms people and produces shallow answers. Go section by
section, starting with Product.

### 2. Leaving `[brackets]` in the final file
When there's no answer, record the actual state ("None — no E2E framework selected yet"),
not a placeholder. Leftover placeholders quietly break every downstream skill that parses
this file.

### 3. Inventing information
Pull the stack from `package.json`, `requirements.txt`, or config files, then confirm with
the user before writing anything down. Never guess at a database or hosting provider.

### 4. Skipping Risk Areas
This is the single highest-value section for downstream skills. Push for at least 3–4
scored entries even when the user says everything's fine.

### 5. Recommending tools beyond the zero-infra default
This skill's job is recording current state — tool selection belongs to
`playwright-automation`, `unit-testing`, and other specialized skills. The one exception is
recommending the Playwright + Vitest default when there's no test infrastructure at all
(Principle 3).

## Verification

Confirm the file is complete, cheapest check first. Run this from the project root:

```bash
test -f .agents/qa-project-context.md \
  && ! grep -q '\[.*\]' .agents/qa-project-context.md \
  && echo "context complete: file exists, no placeholders"
```

An exit code of 0 with that message means the file's there and every
`[bracketed placeholder]` has been resolved. A non-zero exit means either the file is
missing or placeholders remain — resolve that before handing off to any other skill. Then
check that all nine section headers exist:

```bash
grep -c '^## ' .agents/qa-project-context.md   # expect >= 9
```

## Done When

- `.agents/qa-project-context.md` exists at the project root and `grep -q '\[.*\]'` returns
  non-zero (no bracketed placeholders remain).
- All nine sections are present: Product, Tech Stack, Test Stack, CI/CD, Environments,
  Quality Goals, Risk Areas, Team, Conventions.
- Product lists at least 5 specific, testable key user flows (no "user uses the app").
- Test Stack names the actual frameworks + versions + paths in use, or states "None selected yet"
  with the recommended default noted.
- Risk Areas table has at least 3 entries scored by impact and business impact.
- Quality Goals are concrete numbers (coverage %, flake %, durations) — not aspirational prose.
- Team section shows actual headcount and the dev:QA ratio (or "solo").

## Related Skills

- **qa-start** — bootstraps QA on a brand-new project end-to-end and calls this skill as its
  first step. Use qa-start when no QA exists yet; use this skill directly to (re)fill context.
- **risk-based-testing** — turns the Risk Areas section into a prioritized risk matrix. Run it
  after this skill when the question is "where do we focus testing?"
- **test-strategy** — consumes Risk Areas, Quality Goals, and Team to set multi-quarter direction.
- **qa-metrics** — tracks the Quality Goals defined here; both reference the same targets.
- **playwright-automation** / **unit-testing** — set up E2E / unit frameworks after the Test Stack
  section is filled; they read Conventions for selector and naming strategy.
- **ci-cd-integration** — wires the pipeline described in the CI/CD section.

## Reference Files (in `references/`)

- **examples.md** — two complete filled-in context files (SaaS and a multi-site publisher) plus
  the monorepo Tech/Test Stack layout.
</content>
