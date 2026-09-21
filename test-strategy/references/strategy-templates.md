# Test Strategy Templates

A set of ready-to-adapt strategy documents, one per product type. Each is filled with realistic, concrete values instead of blank placeholders, so you can see what a genuinely strong strategy document looks like before adjusting it to your own context.

---

## 1. SaaS Product Strategy Template

```markdown
# QA Strategy: Boardline (B2B Project Management SaaS)
## Version 1.0 | Last Updated: 2026-03-15 | Owner: Priya Nair, QA Lead

### Executive Summary
Boardline serves 2,400 B2B customers managing $180M+ in projects annually. Testing effort is
concentrated on payment and billing flows, workspace collaboration (real-time sync), and data
integrity for project/task CRUD operations. The target is a defect escape rate under 5% with CI
feedback under 12 minutes. This strategy moves the current ice-cream-cone suite toward a healthy
pyramid shape over two quarters.

### Scope & Objectives
**In scope:** Web app (React/Next.js), REST API (Node.js), WebSocket real-time engine,
Stripe billing integration, SSO/SAML auth, PostgreSQL data layer, S3 file attachments.
**Out of scope:** Mobile app (its own strategy), marketing site, Salesforce integration
(owned by RevOps, contract-tested only).

**Objectives:**
1. Bring defect escape rate down from 11% to under 5% by end of Q3 2026
2. Move the test pyramid from 25/15/60 (unit/integration/E2E) to 70/20/10 by end of Q4 2026
3. Cut CI pipeline time from 38 minutes to under 12 minutes by end of Q3 2026
4. Reach 85% unit coverage on billing and auth services by end of Q2 2026

### Test Levels

| Level | Framework | Current Count | Target Count | Run Time |
|-------|-----------|--------------|-------------|----------|
| Unit | Vitest | 312 | 1,400 | <2 min |
| Integration | Vitest + Supertest + Testcontainers | 187 | 400 | <5 min |
| E2E | Playwright | 743 | 200 (critical paths only) | <8 min (parallelized) |
| API Contract | Pact | 0 | 85 (per endpoint) | <1 min |
| Visual | Playwright screenshots | 0 | 30 (key pages) | nightly |
| Performance | k6 | 3 scripts | 12 scripts | weekly |
| Security | Snyk + OWASP ZAP | dependency scan only | full DAST | pre-release |
| Accessibility | axe-core | 0 | 15 (all user-facing pages) | per PR |

### Risk Assessment

| Feature | Impact | Likelihood | Score | Approach |
|---------|--------|------------|-------|----------|
| Stripe billing & invoicing | 5 | 3 | 15-CRIT | Unit + contract + E2E + synthetic monitoring |
| SSO/SAML authentication | 5 | 2 | 10-HIGH | Unit + integration + E2E for login flows |
| Real-time task sync (WebSocket) | 4 | 4 | 16-CRIT | Unit + integration + E2E multi-tab |
| Task CRUD operations | 3 | 3 | 9-MED | Unit + integration, E2E for create/complete |
| File attachment upload/download | 3 | 2 | 6-MED | Unit + integration with S3 mock |
| Dashboard charts & reporting | 2 | 3 | 6-MED | Unit for calculations, visual regression |
| User profile & preferences | 1 | 2 | 2-LOW | Manual verification during release |
| Notification preferences | 1 | 1 | 1-LOW | Manual only |

### Quality Gates

**PR Gate (required, <12 min):**
- Vitest unit + integration: all pass
- Coverage: no decrease (enforced via codecov)
- ESLint + Prettier: no errors
- axe-core a11y: no new violations
- Bundle size: <5% increase warning, >10% blocks merge

**Merge to main:**
- PR gate passes
- Playwright smoke suite (12 critical paths): all pass against preview deploy
- Pact contract verification: all consumer/provider contracts verified

**Deploy to production:**
- Full Playwright suite passes on staging
- k6 performance baseline: p95 < 800ms for API, p95 < 2s for page load
- ZAP security scan: no new high/critical findings
- Feature flags verified in staging

**Nightly:**
- Full Playwright suite including edge cases
- Visual regression comparison
- k6 load test (100 concurrent users, 10 min)
- Dependency vulnerability scan

### Metrics

| Metric | Current | Q2 Target | Q4 Target |
|--------|---------|-----------|-----------|
| Unit coverage (billing) | 34% | 85% | 90% |
| Unit coverage (overall) | 28% | 55% | 70% |
| Pyramid ratio (U/I/E) | 25/15/60 | 50/20/30 | 70/20/10 |
| Flakiness rate | 8.2% | <4% | <2% |
| CI duration (PR) | 38 min | 15 min | 12 min |
| Defect escape rate | 11% | 7% | 5% |
| MTTR (P0) | 6 hours | 4 hours | 2 hours |

### Timeline

**Phase 1 (Weeks 1-4): Foundation**
- Audit all 743 existing E2E tests, tagging each by risk level and what it actually verifies
- Write unit tests for the billing service (target: 85% coverage)
- Stand up Pact for API contract testing between frontend and backend
- Stand up a baseline metrics dashboard (Grafana)

**Phase 2 (Weeks 5-10): Pyramid Correction**
- Break down 400+ E2E tests into their unit/integration equivalents
- Retire redundant E2E tests (expected drop: 743 → ~200)
- Add integration tests for every API endpoint via Supertest
- Parallelize the remaining E2E tests (target: 8 minutes total)

**Phase 3 (Weeks 11-14): Gates & Monitoring**
- Turn on all four quality gates (PR, merge, deploy, nightly)
- Stand up synthetic monitoring for checkout and login flows
- Add visual regression coverage for dashboard and settings pages
- Run the first security audit with ZAP

**Phase 4 (Weeks 15-20): Optimization**
- Roll out test impact analysis (only run tests affected by each PR)
- Quarantine and fix flaky tests (target: <2%)
- Add load-testing scenarios for WebSocket connections
- Run the first quarterly strategy review and publish v1.1
```

---

## 2. E-Commerce Strategy Template

```markdown
# QA Strategy: GreenBasket (D2C Grocery E-Commerce)
## Version 1.0 | Last Updated: 2026-03-10 | Owner: Daniel Osei, Head of QA

### Executive Summary
GreenBasket processes 45,000 orders/week at an AOV of $67. Downtime during peak hours (5-8 PM)
costs roughly $12,000/hour in lost revenue, so this strategy puts the checkout funnel, inventory
sync, and delivery scheduling above everything else. PCI-DSS compliance is non-negotiable for
payment processing. Mobile web makes up 72% of traffic and gets test coverage sized accordingly.

### Scope & Objectives
**In scope:** Storefront (Next.js), checkout flow, Stripe/Apple Pay/Google Pay payments,
inventory management API, delivery scheduling engine, search (Algolia), CMS-driven content pages.
**Out of scope:** Warehouse management system (third-party, contract-tested), driver app (owned by a separate team).

**Objectives:**
1. Drive payment-related defects escaping to production to zero (currently 2-3 per quarter)
2. Cover every payment method and device size in the checkout funnel's E2E tests
3. Validate inventory sync accuracy to 99.9% via automated reconciliation tests
4. Confirm page load time: LCP under 2.5s on a 4G connection for product and category pages

### Risk Assessment

| Feature | Impact | Likelihood | Score | Approach |
|---------|--------|------------|-------|----------|
| Checkout + payment processing | 5 | 3 | 15-CRIT | Full stack: unit + integration + E2E + synthetic + PCI scan |
| Inventory sync (real-time stock) | 5 | 4 | 20-CRIT | Integration tests + reconciliation job + alerting |
| Delivery slot scheduling | 4 | 3 | 12-HIGH | Unit (slot algorithm) + integration (capacity) + E2E |
| Product search & filtering | 3 | 2 | 6-MED | Unit + Algolia contract test |
| User accounts & order history | 3 | 2 | 6-MED | Unit + integration |
| Promo codes & discounts | 4 | 3 | 12-HIGH | Unit (calculation engine) + E2E (apply at checkout) |
| CMS content pages | 1 | 2 | 2-LOW | Visual regression only |
| Email notifications | 2 | 2 | 4-LOW | Integration test for trigger, manual for content |

### Test Levels

| Level | Count | Focus Areas |
|-------|-------|-------------|
| Unit (Vitest) | 890 | Price calculations, discount logic, slot availability algorithm, inventory thresholds |
| Integration (Supertest) | 210 | Stripe webhooks, Algolia sync, inventory API, delivery capacity |
| E2E (Playwright) | 85 | Checkout (6 payment methods x 3 viewports), search-to-cart, delivery booking |
| Performance (k6) | 8 | Product page load, checkout throughput, inventory API under load |
| Security (ZAP + Snyk) | Per release | PCI-DSS compliance, XSS in search, CSRF on checkout |
| Visual (Playwright) | 25 | Product cards, cart, checkout steps, order confirmation |
| Mobile-specific | 40 (E2E) | Touch interactions, viewport-specific layouts, Apple Pay/Google Pay |

### Quality Gates

**PR Gate:** Unit + integration pass, coverage no decrease, Lighthouse CI (LCP < 2.5s).
**Deploy Gate:** Full E2E on staging including all payment methods in Stripe test mode,
  performance benchmarks pass, PCI scan clean.
**Post-Deploy:** Synthetic monitoring places a test order every 5 minutes, alerts on failure.

### Key Metric Targets

| Metric | Target |
|--------|--------|
| Payment defect escapes | 0 per quarter |
| Checkout E2E pass rate | >99.5% |
| Inventory sync accuracy | >99.9% |
| Mobile LCP (4G) | <2.5s |
| CI pipeline (PR) | <10 min |
| Flakiness rate | <1.5% |
```

---

## 3. API-First Product Strategy Template

```markdown
# QA Strategy: StreamForge (Developer API Platform)
## Version 1.0 | Last Updated: 2026-03-12 | Owner: Elena Voss, Staff Engineer

### Executive Summary
StreamForge's data-transformation APIs serve 340 enterprise customers pushing 18M API calls/day.
The users are developers, so API reliability and backward compatibility aren't nice-to-haves —
they're existential. A breaking change or unplanned downtime is a direct SLA violation with
financial penalties attached. This strategy leans hard on contract testing, backward-compatibility
validation, and load performance. There's no UI testing here — the dashboard is a separate
product with its own strategy document.

### Scope & Objectives
**In scope:** REST API (Go), GraphQL API (Go), webhook delivery system, rate limiting,
authentication (API keys + OAuth2), SDK generation (TypeScript, Python, Java), API documentation accuracy.
**Out of scope:** Admin dashboard (separate strategy), billing system (Stripe-managed).

**Objectives:**
1. Ship zero breaking changes without a major version bump (currently 1-2 slip through per quarter)
2. Keep API p99 latency under 200ms across all endpoints under normal load
3. Validate webhook delivery success rate above 99.5%
4. Get contract tests and OpenAPI spec validation onto 100% of public endpoints

### Test Levels

| Level | Framework | Count | Focus |
|-------|-----------|-------|-------|
| Unit (Go test) | stdlib + testify | 2,100 | Transform logic, validation, error handling, edge cases |
| Integration | testcontainers-go | 380 | Database queries, Redis caching, queue processing |
| Contract | Schemathesis + custom | 165 | OpenAPI spec compliance, backward compatibility |
| SDK | Jest/pytest/JUnit per SDK | 90 per SDK | Generated SDK correctness against live API |
| Load | k6 | 12 scenarios | Throughput, latency percentiles, rate limiting behavior |
| Security | gosec + ZAP | Per release | Auth bypass, injection, rate limit circumvention |

### Backward Compatibility Validation
Every PR triggers:
1. An OpenAPI spec diff — any removed field or changed type on an existing field blocks the merge
2. Contract tests running the existing consumer-driven contracts against the new code
3. SDK regeneration plus the SDK test suite (this is what catches serialization/deserialization breaks)
4. An integration test run against a previous-version API client (n-1 compatibility)

### Performance Testing Protocol
- **Baseline:** 1,000 req/s sustained for 10 minutes, p99 < 200ms
- **Stress:** Ramp to 5,000 req/s, measure degradation curve
- **Spike:** 0 to 3,000 req/s in 10 seconds, recovery within 30 seconds
- **Soak:** 500 req/s for 4 hours, memory/connection leak detection
- Runs weekly, before every release, and after any infrastructure change

### Key Metric Targets

| Metric | Target |
|--------|--------|
| Breaking changes escaped | 0 per quarter |
| API p99 latency | <200ms |
| Contract test coverage | 100% of public endpoints |
| Webhook success rate | >99.5% |
| Unit coverage | >85% |
| CI pipeline (PR) | <8 min |
```

---

## 4. Media/Content Site Strategy Template

```markdown
# QA Strategy: Waveform (Media Streaming & Editorial Platform)
## Version 1.0 | Last Updated: 2026-03-08 | Owner: Noah Kim, QA Manager

### Executive Summary
Waveform reaches 890,000 MAU across video and editorial content, with revenue split between ad
impressions (60%) and subscriptions (40%). The testing priorities follow the money and the risk:
content delivery reliability, video player behavior across devices, ad rendering accuracy, and
Core Web Vitals for SEO. Because the site is content-heavy with a comparatively thin application
layer, visual regression and performance testing carry more weight here than they typically would
in a SaaS product.

### Scope & Objectives
**In scope:** Public site (Next.js SSR/ISR), video player (custom + HLS.js), ad integration
(Google Ad Manager), subscription/paywall logic, CMS content rendering, search, personalization engine.
**Out of scope:** CMS authoring interface (vendor-managed), CDN infrastructure (owned by DevOps).

**Objectives:**
1. Push Core Web Vitals pass rate above 95% across all template types (currently 78%)
2. Keep video player error rate under 0.1% across supported browsers/devices
3. Raise ad viewability score above 70% (IAB standard, currently 62%)
4. Eliminate paywall bypass defects entirely (subscription content reachable without auth)

### Risk Assessment

| Feature | Impact | Likelihood | Score | Approach |
|---------|--------|------------|-------|----------|
| Video player (playback, quality switching) | 5 | 3 | 15-CRIT | Unit + cross-browser E2E + real device lab |
| Paywall / subscription gate | 5 | 2 | 10-HIGH | Unit + integration + E2E + security audit |
| Ad rendering & viewability | 4 | 4 | 16-CRIT | Integration + visual + ad verification tool |
| Content rendering (articles, galleries) | 3 | 2 | 6-MED | Visual regression + CMS contract tests |
| Search & personalization | 2 | 3 | 6-MED | Unit + integration |
| Newsletter signup | 1 | 1 | 1-LOW | Manual only |

### Test Levels

| Level | Count | Focus |
|-------|-------|-------|
| Unit (Vitest) | 420 | Paywall logic, ad placement algorithm, personalization scoring, video state machine |
| Integration | 95 | CMS API contract, ad server integration, search index sync |
| E2E (Playwright) | 65 | Video playback (5 browsers), paywall enforcement, content rendering |
| Visual (Playwright + Argos) | 120 | All content templates, responsive breakpoints, dark mode, ad slots |
| Performance (Lighthouse CI + k6) | 15 | LCP/CLS/INP for all templates, video start time, TTFB |
| Cross-browser | Matrix | Chrome, Safari, Firefox, Edge, Samsung Internet, iOS Safari |
| Accessibility (axe-core) | All templates | WCAG 2.2 AA for all content pages |

### Performance Strategy
For a content site, Core Web Vitals are make-or-break. Lighthouse CI runs on every PR against:
- Homepage
- Article page (text-heavy)
- Article page (video embed)
- Category/listing page
- Search results page

**Thresholds (block merge if exceeded):**
- LCP: >2.5s
- CLS: >0.1
- INP: >200ms
- Total bundle size increase: >10KB without justification

### Key Metric Targets

| Metric | Target |
|--------|--------|
| Core Web Vitals pass rate | >95% |
| Video player error rate | <0.1% |
| Visual regression false positive rate | <3% |
| Ad viewability score | >70% |
| Cross-browser E2E pass rate | >99% |
| Paywall bypass defects | 0 |
```

---

## Test Pyramid Analysis Worksheet

A step-by-step worksheet for sizing up your current suite's shape and planning the correction.

### Step 1: Count What Exists Today

```
Source command examples:
  Unit:        npx vitest --reporter=json 2>/dev/null | jq '.numTotalTests'
  Integration: find . -path "*/integration/*.test.*" | wc -l
  E2E:         find . -path "*/e2e/*.spec.*" | wc -l

Results:
  Unit tests:          _______ count
  Integration tests:   _______ count
  E2E tests:           _______ count
  Total:               _______ count
```

### Step 2: Work Out the Ratios

```
  Unit %:         (unit count / total) x 100        = _______ %
  Integration %:  (integration count / total) x 100 = _______ %
  E2E %:          (E2E count / total) x 100         = _______ %
```

### Step 3: Name the Current Shape

```
  [ ] Healthy Pyramid    — Unit 60-80%, Integration 15-25%, E2E 5-15%
  [ ] Ice Cream Cone     — E2E > Unit (inverted, most common anti-pattern)
  [ ] Diamond            — Integration > Unit and Integration > E2E (heavy mocking)
  [ ] Hourglass          — Unit high, Integration low, E2E high (missing middle)
  [ ] Trophy             — Integration-heavy (Kent C. Dodds style, valid for some apps)
  [ ] No Shape           — Tests exist but with no intentional distribution
```

### Step 4: Set the Target Ratios

```
  Target unit %:         _______ %  → need _______ more/fewer unit tests
  Target integration %:  _______ %  → need _______ more/fewer integration tests
  Target E2E %:          _______ %  → need _______ more/fewer E2E tests
```

### Step 5: Turn Gaps Into Action Items

For every gap identified above, list a concrete next step:

| Gap | Action | Owner | Due Date | Effort |
|-----|--------|-------|----------|--------|
| Unit tests too low | Add unit tests for [service] business logic | | | |
| E2E tests too high | Decompose E2E tests for [feature] into unit tests | | | |
| Integration tests missing | Add API contract tests for [service] boundaries | | | |
| Flaky E2E tests | Quarantine and rewrite top 10 flakiest tests | | | |

### Step 6: Track the Trend Month Over Month

```
Month:    | Unit % | Int %  | E2E %  | Shape          | CI Time  | Flaky %
----------|--------|--------|--------|----------------|----------|--------
Baseline  |        |        |        |                |          |
Month 1   |        |        |        |                |          |
Month 2   |        |        |        |                |          |
Month 3   |        |        |        |                |          |
Month 4   |        |        |        |                |          |
Month 5   |        |        |        |                |          |
Month 6   |        |        |        |                |          |
```

---

## Risk Assessment Matrix Template

### The Full 5x5 Matrix With Example Entries

```
                    Rare (1)        Unlikely (2)     Possible (3)     Likely (4)       Almost Certain (5)
                  ┌───────────────┬───────────────┬───────────────┬───────────────┬───────────────┐
Catastrophic (5)  │  5 - MEDIUM   │ 10 - HIGH     │ 15 - CRITICAL │ 20 - CRITICAL │ 25 - CRITICAL │
(data loss,       │               │ Auth bypass   │ Payment       │               │               │
 financial loss,  │               │               │ processing    │               │               │
 compliance)      │               │               │ errors        │               │               │
                  ├───────────────┼───────────────┼───────────────┼───────────────┼───────────────┤
Major (4)         │  4 - LOW      │  8 - MEDIUM   │ 12 - HIGH     │ 16 - CRITICAL │ 20 - CRITICAL │
(feature broken,  │               │               │ Real-time     │ Search returns│               │
 significant UX   │               │               │ sync failures │ wrong results │               │
 degradation)     │               │               │               │               │               │
                  ├───────────────┼───────────────┼───────────────┼───────────────┼───────────────┤
Moderate (3)      │  3 - LOW      │  6 - MEDIUM   │  9 - MEDIUM   │ 12 - HIGH     │ 15 - CRITICAL │
(partial feature  │               │ File upload   │ Dashboard     │ Form          │               │
 failure, UX      │               │ edge case     │ chart errors  │ validation    │               │
 issue)           │               │               │               │ gaps          │               │
                  ├───────────────┼───────────────┼───────────────┼───────────────┼───────────────┤
Minor (2)         │  2 - LOW      │  4 - LOW      │  6 - MEDIUM   │  8 - MEDIUM   │ 10 - HIGH     │
(cosmetic,        │               │               │ Tooltip       │ CSS layout    │ Typos in      │
 minor UX)        │               │               │ positioning   │ shifts        │ dynamic       │
                  │               │               │               │               │ content       │
                  ├───────────────┼───────────────┼───────────────┼───────────────┼───────────────┤
Negligible (1)    │  1 - LOW      │  2 - LOW      │  3 - LOW      │  4 - LOW      │  5 - MEDIUM   │
(no user impact,  │ Legacy page   │ Admin-only    │               │ Console       │               │
 internal only)   │ styling       │ label         │               │ warnings      │               │
                  └───────────────┴───────────────┴───────────────┴───────────────┴───────────────┘
```

### Filling In the Matrix, Step by Step

1. **Inventory the feature areas** across the product (15-30 entries is a reasonable range).
2. **Score Impact (1-5)** by asking what happens if this specific feature breaks in production:
   - 5: Revenue loss, data loss, compliance violation, security breach
   - 4: Major feature unusable, significant user frustration, support flood
   - 3: Feature partially broken, workaround exists, moderate user impact
   - 2: Cosmetic issue, minor inconvenience, few users affected
   - 1: No user-facing impact, internal tooling, already deprecated
3. **Score Likelihood (1-5)** based on code complexity, how often it changes, and its bug history:
   - 5: Changes every sprint, complex logic, history of bugs
   - 4: Changes frequently, moderate complexity, occasional bugs
   - 3: Changes occasionally, some complexity
   - 2: Stable code, simple logic, rarely changes
   - 1: Static, trivial, or mature and battle-tested
4. **Multiply Impact by Likelihood** to get the risk score.
5. **Map the score to a testing approach** using the Risk-to-Testing Action Map in the main `SKILL.md`.

### Feature Inventory Template

| # | Feature Area | Impact (1-5) | Likelihood (1-5) | Risk Score | Risk Level | Testing Approach | Owner |
|---|-------------|-------------|-------------------|------------|------------|-----------------|-------|
| 1 | | | | | | | |
| 2 | | | | | | | |
| 3 | | | | | | | |
| 4 | | | | | | | |
| 5 | | | | | | | |
| 6 | | | | | | | |
| 7 | | | | | | | |
| 8 | | | | | | | |
| 9 | | | | | | | |
| 10 | | | | | | | |

Sort by Risk Score, highest first — whatever lands at the top gets automated testing before anything else.
</content>
