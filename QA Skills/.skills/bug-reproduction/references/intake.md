# Extracting the implicit repro from a thin report

A report along the lines of *"Checkout is broken, order total is wrong sometimes"* carries
almost nothing you can actually reproduce from. Before writing any code — and **before
theorizing about a root cause** — pull out or ask for each dimension below. The instinct to
jump straight to "sounds like a float rounding bug, let me check the total calc" is exactly
the failure mode to resist until the bug can actually be reproduced. You can't fix what you
can't reproduce.

## The extraction checklist

These apply to *any* bug report. The starred ones are the load-bearing dimensions
specifically for a "wrong total" / data-correctness bug.

| Dimension | Why it changes reproducibility | Ask / extract |
|-----------|-------------------------------|---------------|
| **Exact steps to reproduce** | "Checkout is broken" is a symptom, not a path | The precise click-by-click path that triggered it |
| **Build / version / commit (git SHA)** | The bug may already be fixed, or only on one deploy | Exact build number or commit SHA they were on |
| **Environment** (browser, OS, device) | Locale/rendering/JS-engine differences | Browser + version, OS, mobile vs desktop |
| **Input data** ★ | A "wrong total" depends entirely on the inputs | Cart contents, quantities, the account/user, the discount/coupon, the exact fixture |
| **Expected vs actual** | "Wrong" is meaningless without the right number | What total did they expect, what did they see |
| **Frequency** ★ | "Sometimes" = intermittent — changes the whole strategy | Every time, or intermittent? How many of N attempts? |
| **Locale / timezone / currency** ★ | Rounding, tax, and formatting are locale-specific | Their locale, timezone, and currency |
| **Timestamp of occurrence** | Correlate with deploys, time-of-day bugs, batch jobs | When did it happen (with timezone) |
| **Logs / screenshots / network trace** | Turns hearsay into evidence | Console errors, the failing response body, a HAR |

★ = the dimensions that a thin "order total is wrong" report most commonly omits, and that
have the biggest influence on whether you can actually reproduce it.

## Why each load-bearing dimension matters for "wrong total"

- **Input data (cart / account / fixture):** total calculations are a pure function of their
  inputs. Two line items vs. three, a percentage discount vs. a flat one, a tax-exempt
  account versus not — any of these can flip a run between green and red. Without the exact
  cart, you're guessing.
- **Frequency:** "sometimes" is a strong signal of non-determinism — a race condition, an
  unseeded random discount, a time-of-day rule, or a flaky upstream price feed. That pushes
  you toward determinism work (freezing time, seeding the RNG, stubbing the network) rather
  than a simple linear repro.
- **Locale / timezone / currency:** totals involve rounding rules, tax tables, and currency
  minor-units that vary by locale. A "wrong" total in `de-DE` (comma decimals, 19% VAT) could
  be entirely correct in `en-US`. Always reproduce in *their* locale.
- **Build / commit:** if the user was on a build predating a fix, there's nothing left to
  reproduce. Pin down the SHA first.

## Turning answers into a repro spec

Once you've gathered these dimensions, write them down as a single reproducible spec before
touching any code:

```
Build:        2.5.1 (commit 3a9f2c1)
Environment:  Chrome 124 / macOS 14 / desktop
Locale:       de-DE, Europe/Berlin, EUR
Data:         account #4821 (tax-exempt=false), cart = [SKU-12 ×3], coupon SAVE10 (10%)
Steps:        1. log in as #4821  2. add SKU-12 ×3  3. apply SAVE10  4. open cart total
Expected:     €27.54
Actual:       €27.55  (off by one minor unit)
Frequency:    every time with this exact cart (deterministic)
```

If any row can't be filled in, that's your next question for the reporter — not a green
light to invent a root cause from imagination. Only once this spec reliably reproduces
should you move on to minimizing and isolating.
