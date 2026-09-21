---
name: qa-start
description: >-
  A guided, three-stage launcher for standing up QA where nothing exists yet. It
  runs qa-project-context, then test-strategy, then test-planning back to back as
  one flow, and hands off to automation once the foundation is in place. Trigger it
  for requests like "set up QA on a new project," "QA from scratch," or "no QA
  exists yet," or when the user types "/qa-start" directly. Skip it when someone is
  onboarding onto a team that already has a test suite — that's qa-project-bootstrap
  — or when the right skill isn't obvious yet, which is what qa-do is for.
  Related: qa-project-context, test-strategy, test-planning, qa-project-bootstrap, qa-do.
license: Proprietary
compatibility: Cross-tool. Tested with Claude Code, Codex, Cursor, Gemini CLI. Reads/writes the user's project root; no network access required.
metadata:
  author: osharaai
  version: "2.0"
  category: foundation
  argument-hint: "optional path to existing repo (e.g. './apps/web') if running from a monorepo root"
---

<objective>
`qa-start` is an orchestrator, not a source of QA advice in its own right. Its entire job is sequencing: it fires `qa-project-context`, then `test-strategy`, then `test-planning`, in that fixed order, so nobody starts writing test cases before anyone has agreed on what's worth testing and why. Finish the run and you'll have three concrete artifacts on disk — a context file, a strategy doc, and a first-cut test plan — which together form a working QA foundation.
</objective>

## Is This the Right Skill?

Use `qa-start` any time "where do we even begin with QA?" has no good answer because there's no foundation to point to:

- A greenfield project that has never had test infrastructure.
- An existing, possibly old, codebase where **QA was simply never set up** — this is still `qa-start`'s territory, not `qa-project-bootstrap`'s. That other skill assumes tests are *already there*; this one assumes they aren't.
- A project where QA used to exist but rotted away — deleted tests, no more strategy, coverage at zero. Treat it as a rebuild from the ground up.

The dividing line: if a QA engineer is stepping onto a team that has a working test suite already, that's `qa-project-bootstrap`'s job, not this skill's.

## Where to Jump In

You don't have to start at the beginning if part of the foundation is already built. Skip ahead based on what already exists:

| What you already have | Where to resume |
|-----------------------|------------------|
| Nothing — no context file, no strategy, no plan | Begin at Stage 1 |
| A populated `.agents/qa-project-context.md` | Jump straight to `test-strategy` (Stage 2) |
| Both the context file and a strategy doc | Jump straight to `test-planning` (Stage 3) |
| All three artifacts already exist | See "Once the Foundation Is Set" below |
| A QA engineer joining a team that already tests things | Wrong skill — go to `qa-project-bootstrap` |

## Stage 1 — Establish Project Context

Powered by: `qa-project-context`

This stage produces `.agents/qa-project-context.md` at the repo root — a running record of tech stack, testing frameworks in use, the CI/CD setup, available environments, coverage targets, known risk areas, and how the team is organized. Everything downstream reads from this file instead of re-asking you.

Run `qa-project-context` and answer its discovery prompts as they come; it also inspects the repository directly where it can, and writes the results to the file for you.

You're done with this stage once every section of `.agents/qa-project-context.md` is filled in — it becomes the reference point every later step builds on.

## Stage 2 — Settle on a Test Strategy

Powered by: `test-strategy`

This stage turns context into direction: it decides the shape of your test pyramid (how much weight goes to unit versus integration versus end-to-end coverage for your particular product), sets entry/exit criteria, picks tooling, defines which environments need coverage, and establishes the quality gates that guard CI and releases.

Run it once Stage 1's file exists — it pulls answers from that file automatically instead of repeating questions you've already answered.

Consider this stage complete when you have a strategy document (commonly named something like `strategy.md`) that justifies its pyramid shape, explains its tool choices, spells out CI/release gates, and lists entry/exit criteria per test type. A tight, decisive one-pager is worth more here than an exhaustive template nobody reads.

## Stage 3 — Draft the Initial Test Plan

Powered by: `test-planning`

This stage converts the strategy into something actionable for the upcoming sprint or release: features get mapped to concrete test cases, effort gets estimated, and calls get made about what's covered now versus pushed to later.

Run it after Stage 2 finishes. It draws on both the Stage 2 strategy and the Stage 1 context, and will ask you for the relevant feature list or sprint scope.

The stage is complete once you have a plan document (e.g. `plan.md`) that maps features to test cases, ranks coverage priorities, carries effort estimates, and states its scope boundaries clearly. This is the artifact the team actually works from day to day.

## Once the Foundation Is Set

With context, strategy, and an initial plan in hand, the foundation is complete — but this launcher stops here on purpose. Where you go next depends on your stack:

- **Writing real tests:** reach for `playwright-automation` or `cypress-automation` to automate your riskiest flows first.
- **Wiring up CI:** bring in `ci-cd-integration` so the suite runs automatically on every pull request.
- **Measuring health over time:** once tests are running, `qa-metrics` defines what "healthy" looks like and how to track it.

## Telling qa-start, qa-project-bootstrap, and qa-do Apart

This trio gets confused constantly, so here's the distinction in one spot:

- **`qa-start`** is for building QA from **zero** — brand-new projects, or ones where QA was lost and needs rebuilding. It runs context → strategy → first plan and its output is the *foundation itself*.
- **`qa-project-bootstrap`** is a roughly month-long onboarding path for a QA engineer **joining a team that already has a test suite**. It covers team workflow, a ramp-up schedule, and an audit of tests that already exist. It's meant to run *on top of* an existing foundation, not to create one.
- **`qa-do`** is the fallback router for "I'm not sure which skill applies." Skip it if you already know QA doesn't exist yet — go straight to `qa-start` instead.

Rule of thumb: no QA in place, regardless of how old the codebase is, always means `qa-start` — never `qa-project-bootstrap`.

## Making It a Manual-Only Command

Nothing stops you from re-running this launcher on demand from the Claude Code `/skills` menu.

If you'd rather it never fire automatically, add `disable-model-invocation: true` to the frontmatter, or flip the equivalent `skillOverrides` setting in `.claude/settings.local.json`.

> Heads up: some Claude Code builds have a bug where `disable-model-invocation: true` also blocks the manual slash command from working (tracked as anthropics/claude-code#26251). If you need `/qa-start` to still work by hand, use the `skillOverrides` value `user-invocable-only` instead of the frontmatter flag.

## See Also

- **qa-project-context** — Stage 1; writes tech stack, setup, and quality-goal details into `.agents/qa-project-context.md`.
- **test-strategy** — Stage 2; settles the testing approach, pyramid shape, tooling, and quality gates.
- **test-planning** — Stage 3; turns the strategy into a first plan mapping features to test cases.
- **qa-project-bootstrap** — the right call instead when a QA engineer is ramping onto a team whose tests already exist; this skill builds the foundation, that one onboards someone onto an existing one.
- **qa-do** — fallback router for when no skill obviously fits; unnecessary if you already know there's no QA yet.
- **playwright-automation / cypress-automation** — your next stop after the plan, for automating tests against the highest-risk flows first.
