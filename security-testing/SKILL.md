---
name: security-testing
description: >-
  Exercises an application's defenses against the OWASP Top 10 (2025) using automated CI
  tooling — OWASP ZAP for DAST, OSV-Scanner/SBOM/provenance for dependency and supply-chain
  scanning, Semgrep for SAST, JWT/OAuth/RBAC auth-and-session checks, and Playwright patterns
  covering XSS, CSRF, SQLi, and SSRF.
  Use when: "security test," "OWASP," "vulnerability," "ZAP," "XSS," "SSRF," "dependency scan,"
  "auth testing," "OWASP LLM Top 10." This skill sticks to automated scanning and negative-path
  tests wired into CI — it is not a manual penetration-testing engagement.
  Not for: mapping security controls to regulations (SOC 2, HIPAA, PCI, GDPR) — use compliance-testing;
  pipeline stage wiring and deploy gating mechanics — use ci-cd-integration; purely functional API auth/input
  tests with no attacker model — see api-testing; testing your product's own LLM features or defending the
  agent itself (prompt-injection detector, indirect injection, jailbreak red-teaming) — use ai-system-testing.
  Related: ci-cd-integration, compliance-testing, api-testing, shift-left-testing, ai-system-testing.
license: Proprietary
metadata:
  author: osharaai
  version: "2.1"
  category: specialized
---

<objective>
A login flow can pass every happy-path check while a serious hole ships right alongside it: an
expired JWT still opens an admin panel, an IDOR lets User A pull up User B's order history, or a
webhook field successfully reaches `169.254.169.254`. This skill exists to make the negative
paths — broken access control, injection, SSRF, auth bypass, supply-chain drift — mandatory gates
in CI on every pull request, spreading coverage across DAST, SCA, SAST, and hand-written Playwright
tests so no single tool's blind spot is the thing that ships. The result is a set of runnable tests
mapped to the OWASP Top 10 (2025), plus the CI gates that break the build the moment a category
regresses.
</objective>

## Before You Start: Discovery

Check for `.agents/qa-project-context.md` first. If it exists, treat auth mechanism, compliance needs, and infrastructure as already answered there — don't re-ask. Otherwise, work through:

1. **What's the threat model?** Has anyone mapped the assets worth protecting, likely attackers, and where they'd get in? If not, run a lightweight threat-modeling pass before writing a single test — it tells you which OWASP categories deserve the most attention.
2. **How does auth work here?** Session cookies, JWT, OAuth 2.0/OIDC, API keys, MFA — each mechanism opens its own set of negative-path tests (algorithm confusion, session fixation, tampered state).
3. **Any compliance obligations?** SOC 2, HIPAA, PCI DSS, GDPR each mandate specific controls; mapping those belongs to `compliance-testing`. This skill only verifies the controls actually behave as intended.
4. **What's already scanning?** Look for OSV-Scanner, Snyk, Dependabot, Semgrep, or ZAP already wired into CI before bolting on duplicates.
5. **What protocols are exposed?** REST, GraphQL, gRPC each carry their own injection and authorization risk shapes.
6. **Where does this deploy?** Cloud (AWS/GCP/Azure), containers, serverless — cloud metadata endpoints are a favorite SSRF target, and misconfiguration is literally A02.

---

## Guiding Principles

1. **Security testing runs continuously, not once a quarter.** Every PR triggers the scans; nothing waits for a periodic pentest. A flaw caught on the PR that introduced it is a few minutes of fix time; the same flaw found in production is an incident.

2. **The OWASP Top 10 sets a floor, not a ceiling.** It's the common, high-impact vulnerability classes — but domain-specific risk (healthcare records, financial transactions, multi-tenant boundaries) demands its own analysis beyond the checklist.

3. **Layer your tools — none of them sees everything.** ZAP won't catch a logic bug in your auth flow; SCA doesn't look at your own code; Semgrep can't see what happens at runtime. Stack DAST + SCA + SAST + auth tests + secret scanning so a gap in one layer is covered by another — a regression then has to slip past all of them at once. SCA specifically earns its place because most shipped code is third-party: known CVEs in dependencies are the cheapest attack surface available, so scan every build.

4. **Push checks as early as they'll go.** SAST and secret scanning belong at commit time, dependency/supply-chain checks at PR time, DAST against staging, and custom auth tests on every run. This is the shift-left approach detailed in `shift-left-testing`.

5. **Write tests that think like an attacker, not a user.** A passing happy-path login test tells you nothing about whether logout actually kills the session, an expired token gets rejected, privilege escalation fails, or a malformed payload fails closed. The negative-path assertion *is* the test.

---

## OWASP Top 10 (2025): What to Cover

The finalized 2025 list (owasp.org/Top10/2025/) reshuffles the ordering and adds two new categories relative to 2021:

- **A03 Software Supply Chain Failures** replaces "Vulnerable and Outdated Components" and widens the scope to provenance, build-pipeline trust, and SBOM.
- **A10 Mishandling of Exceptional Conditions** is entirely new. SSRF no longer gets its own category — its tests now live under A01 (access control) and A06 (insecure design).
- **A02 Security Misconfiguration** climbed from A05.
- **A07 Authentication Failures** dropped "Identification and" from its name.
- **A09 Security Logging and Alerting Failures** was renamed from "Logging and Monitoring."

Runnable test code for every category lives in `references/owasp-tests.md`.

### A01: Broken Access Control

Still the top spot — this is what happens when users can act beyond their intended permissions. SSRF now falls under this category whenever a server gets tricked into reaching internal resources on an attacker's behalf.

**Test for:** IDOR (swap in another user's resource ID and see if it resolves), missing function-level checks (hit an admin route as a plain user), path traversal (`../../etc/passwd`), CORS misconfiguration, and SSRF (user-supplied URLs reaching internal hosts, cloud-metadata endpoints, or `file://`).

### A02: Security Misconfiguration

Leftover defaults, unneeded features, chatty error pages. Moved up from A05 — and still one of the easiest ways in.

**Test for:** stack traces suppressed in production, default credentials rotated, extraneous HTTP methods (TRACE, etc.) disabled, directory listings off, admin panels not internet-reachable, cloud storage buckets not public.

### A03: Software Supply Chain Failures

New for 2025. This goes past "are my dependencies current" and into provenance and build-pipeline integrity across the whole chain.

**Test for:** a committed lockfile that CI actually installs from (`npm ci`, never `npm install`); an SBOM generated and archived as a build artifact (Syft or `anchore/sbom-action`); provenance attestation on build outputs (SLSA v1.0 L2/3, signed with `cosign` or `actions/attest-build-provenance`); dependency review gating every PR; CI secrets withheld from forked-repo runs; self-hosted runners kept isolated from untrusted PR code.

The full dependency-review / SBOM / provenance workflow, plus the lockfile-drift check, is in `references/owasp-tests.md`.

### A04: Cryptographic Failures

Sensitive data exposed because encryption is weak, missing, or misapplied.

**Test for:** TLS version, cipher suite, and HSTS configuration; password hashing via bcrypt/argon2 (never MD5/SHA1); no sensitive values leaking into URLs, logs, or error output; cookies flagged `Secure`, `HttpOnly`, `SameSite`; the standard security headers present (HSTS, `X-Content-Type-Options: nosniff`, `X-Frame-Options`).

### A05: Injection

Untrusted input reaching an interpreter unsanitized.

**Test for:** SQL injection through parameters, form fields, or headers; XSS in its reflected, stored, and DOM-based forms; CSRF on any state-changing operation; command injection via filenames, search terms, or webhook URLs.

### A06: Insecure Design

Architectural gaps that code-level patches alone can't fix — this includes SSRF at the design level (a URL-accepting feature with no allow-list), rate-limit-free credential stuffing, and business-logic abuse.

**Test for:** rate limiting on auth endpoints (send 15 concurrent login attempts and expect at least one `429` among the responses); business-logic exploitation (negative order quantities, stacked coupons); lockout after repeated failed attempts; allow-list enforcement anywhere a feature fetches a user-supplied URL.

### A07: Authentication Failures

Weak or broken login flows, exposure to credential stuffing. Covers session rotation after login, rejection of expired/`alg:none` JWTs, the RBAC role matrix, and OAuth state-parameter tampering. Full patterns in `references/auth-tests.md`.

### A08: Software or Data Integrity Failures

Unsigned update paths, unsafe deserialization, an untrusted CI/CD pipeline.

**Test for:** Subresource Integrity (SRI) applied to CDN-hosted scripts; a Content-Security-Policy header present and clear of `'unsafe-inline'` / `'unsafe-eval'`.

### A09: Security Logging and Alerting Failures

Logging alone isn't enough — this category also covers the absence of alerts on what gets logged. The 2025 rename underscores that a log with no alert is just after-the-fact evidence, not detection.

**Test for:** failed logins both logged and alerting past a threshold; admin actions audit-logged and alerting on off-hours activity; logs scrubbed of secrets and PII; the alerting pipeline itself under monitoring.

### A10: Mishandling of Exceptional Conditions

New for 2025 — the recognition that error handling itself is an attack surface: fail-open defaults, exceptions that leak internals, race conditions inside error paths, and security checks getting skipped whenever something goes wrong.

**Test for:** error responses free of stack traces, framework names, or DB schema hints; authorization failing closed by default; timeouts and partial failures never bypassing authorization; resource cleanup guaranteed on every failure path; fuzzing every endpoint to confirm responses stay inside the documented error contract.

---

## OWASP LLM Top 10 (2025)

Apps that embed an LLM — chatbot, RAG pipeline, agent, copilot — fail in ways the classic Top 10 above doesn't capture. That territory belongs to the OWASP Gen AI Security Project's own list (genai.owasp.org/llm-top-10/). What follows is the CI-gate-level view: one line of "what to test" per category. For deep behavioral coverage of LLM01 and LLM02 — indirect injection via tool/RAG data, the defend-the-tester technique, jailbreak red-teaming, the runnable injection detector — that work belongs to `ai-system-testing`; this skill doesn't duplicate it.

| ID | Category | What to test |
|----|----------|--------------|
| **LLM01** | Prompt Injection | Both direct and indirect injection (instructions smuggled in retrieved docs, tool output, or file content) overriding system intent. → Deep coverage lives in `ai-system-testing`. |
| **LLM02** | Sensitive Information Disclosure | Crafted prompts extracting PII, secrets, other tenants' data, or training data from the model. → Deep coverage (detector, scoped tests) lives in `ai-system-testing`. |
| **LLM03** | Supply Chain | Provenance across models, adapters, datasets, and plugins; pinned and verified weights; a poisoned third-party model or LoRA. |
| **LLM04** | Data and Model Poisoning | Integrity of training, fine-tune, and RAG-ingest data; backdoors or bias smuggled in through tainted sources. |
| **LLM05** | Improper Output Handling | Generated text reaching a downstream interpreter unsanitized — XSS, SSRF, SQLi, or command injection sourced from LLM output. |
| **LLM06** | Excessive Agency | An agent holding more tools, permissions, or autonomy than its task needs — able to delete, pay, or send email with no human checkpoint. |
| **LLM07** | System Prompt Leakage | The system prompt extractable, and worse, depended on to hold secrets or enforce authorization that should live server-side. |
| **LLM08** | Vector and Embedding Weaknesses | RAG retrieval crossing tenant or permission boundaries; embedding inversion; poisoned vectors returned as context. |
| **LLM09** | Misinformation | Confidently fabricated output — invented facts, fake citations or URLs, unsafe code — accepted as trustworthy. |
| **LLM10** | Unbounded Consumption | Missing token, rate, or cost ceilings enabling resource exhaustion, denial-of-wallet, or model extraction via sheer query volume. |

LLM05 is where this reconnects with the classic list: treat any LLM output as untrusted input and rerun the A05 injection checks against whatever it produces.

---

## Automating the Scans

A full pipeline stacks DAST, dependency/supply-chain scanning, SAST, and secret scanning together. Configs and CI workflow definitions live in `references/scanning-and-ci.md`.

- **OWASP ZAP (DAST):** run a baseline scan against staging on every PR, and `zap-api-scan.py` against API surfaces. Current is ZAP 2.17.0, with weekly Docker tags following `w2026-MM-DD`. The **ZAP MCP Server (April 2026)** lets coding agents drive spider/active-scan/alert-analysis directly — handy for "scan the diff" workflows.
- **Dependency / supply-chain:** treat **OSV-Scanner as the default gate** — it's multi-language and exits non-zero on any detected vuln. Layer in SBOM generation (Syft) plus provenance (`cosign` / `attest-build-provenance`) to cover A03. `npm audit --audit-level=high` is a noisy, semver-only spot-check — not a gate, since it misses non-strict-semver versions and doesn't reliably exit non-zero.
- **SAST:** **the SAST gate is Semgrep's `p/owasp-top-ten` ruleset.** `eslint-plugin-security` is a weak secondary at best (see below) — treat it as a lint-time nudge, never as coverage.
- **Secret scanning:** TruffleHog with `--only-verified` in CI, `git-secrets` at pre-commit.

**Don't lean on `eslint-plugin-security` as your SAST gate.** As of mid-2026 it's still around 13 rules with essentially no growth since 2020, and benchmark data puts its miss rate near 90% of detectable vulnerabilities. Version 4.0.0 is compatible with flat config, so it will run — but only underneath Semgrep, never as a replacement for it.

**ESLint 10 (Feb 2026) dropped `.eslintrc` support entirely** — flat config (`eslint.config.js`) is now the only option. Any `.eslintrc.*` security setup is inert on ESLint 10; it's only relevant to repos still pinned to ESLint 8. Both config blocks are in `references/scanning-and-ci.md`.

---

## Auth Testing Patterns

Covers session handling, JWT edge cases (expiry, `alg: none` confusion, wrong-key signatures), and the RBAC test matrix. Full implementations are in `references/auth-tests.md`. Don't skip session rotation after login (session-fixation defense) or OAuth state-parameter tampering.

---

## Wiring This Into CI

Five layers make up a complete security pipeline, one CI step apiece:

1. **Secret scanning** — TruffleHog, `--only-verified`
2. **Dependency check** — OSV-Scanner, failing on any vuln; SBOM + provenance covering A03
3. **SAST** — Semgrep `p/owasp-top-ten` as the actual gate; ESLint security plugins as a weak secondary
4. **DAST** — ZAP baseline scan against the staging URL
5. **Custom auth tests** — `npx playwright test --project=security`

**Making security a merge gate:** OSV-Scanner's non-zero exit on any vulnerability gates the merge directly. Gating on `npm audit` instead means parsing `npm audit --json` yourself and calling `exit 1` when high/critical counts exceed zero — `npm audit` won't reliably do that on its own. A runnable version of this gate is in `references/scanning-and-ci.md`.

---

## Anti-Patterns to Avoid

**Only testing security right before a release.** Findings that surface late cost more to fix. Scan every PR — not once a quarter.

**Trusting one tool to cover everything.** ZAP misses logic bugs in auth; SCA doesn't see your own code; ESLint misses runtime behavior. Stack multiple tools instead.

**Counting a nearly-abandoned linter as real SAST coverage.** `eslint-plugin-security` alone catches almost nothing (~13 rules, detection frozen around 2020). Gate on Semgrep's `p/owasp-top-ten`; keep the linter around only as a nudge.

**Letting dependency warnings pile up.** "We'll fix it later" turns into a backlog of known CVEs. Fail the build on high/critical findings via OSV-Scanner.

**Only exercising the happy path in auth tests.** Login succeeding proves little on its own — check whether logout actually invalidates the session, whether an expired token still grants access, whether privilege escalation is blocked.

**Putting real secrets in test files.** A test holding live credentials is itself a vulnerability. Pull from env vars and CI secrets instead.

**Skipping SSRF checks.** Any feature that accepts a URL — webhooks, image uploads, imports — is a potential SSRF vector. Test it against internal addresses and cloud-metadata endpoints.

**Asserting a single status code where several are legitimate.** SSRF, CSRF, and exceptional-condition tests often have more than one acceptable response code. Use `expect([400, 403, 422]).toContain(response.status())` — `toBeOneOf` isn't a built-in matcher and will throw at runtime.

**Treating the example payloads as exhaustive.** The XSS/SQLi payloads shown in the reference files are illustrative, not a complete list. Lean on ZAP's maintained payload database for real breadth.

---

## Verifying the Suite Actually Works

A security suite that passes vacuously — wrong URL, an assertion that never runs — is worse than having no suite at all. Confirm the checks actually fire:

1. **Run one negative-path test against a target you know is vulnerable, and confirm it fails.** OWASP Juice Shop works well for this:
   ```bash
   docker run --rm -p 3000:3000 bkimminich/juice-shop
   BASE_URL=http://localhost:3000 npx playwright test --project=security
   ```
   You should see the IDOR / injection / missing-header tests fail here. If they all pass against Juice Shop, your assertions aren't actually reaching the app — fix the selectors or URLs before trusting a green run against your own staging.
2. **Confirm the matcher pattern is followed throughout.** `grep -r "toBeOneOf" tests/` should return nothing at all — every multi-status assertion should use `expect([...]).toContain(...)`.
3. **Confirm the dependency gate actually fails.** Introduce a known-vulnerable dependency, run the OSV-Scanner step, and check that the job exits non-zero — then remove the planted dependency.

---

## Definition of Done

- A committed `owasp-coverage.md` (or an equivalent CI assertion) maps every OWASP 2025 category to at least one tagged test, or documents it as a mitigated/accepted risk with justification — nothing goes silently uncovered.
- OSV-Scanner (or an equivalent) runs in CI and exits non-zero on high/critical vulnerabilities, confirmed via the planted-vuln check above.
- Semgrep's `p/owasp-top-ten` runs in CI with zero unresolved findings on main (ESLint security plugins may run alongside as a non-gating secondary signal).
- The ZAP baseline scan runs against staging and its report uploads as a CI artifact every run (`if: always()`).
- The security Playwright project (`--project=security`) passes against staging AND fails when pointed at OWASP Juice Shop, proving the assertions actually fire.
- Each auth/session edge case has its own passing test: CSRF rejection, expired-token rejection, `alg:none` rejection, session invalidation on logout, RBAC role-escalation prevention.
- No real secrets turn up in test files (clean `grep` / TruffleHog run).

## Related Skills

- **ci-cd-integration** — the pipeline wiring and deploy-gating mechanics; go there for *how* these steps run, come here for *what* they check.
- **compliance-testing** — maps security controls to regulatory frameworks (SOC 2, HIPAA, PCI, GDPR); this skill proves the controls function, that one proves you've picked the right controls.
- **ai-system-testing** — owns your product's own LLM features: the deep OWASP LLM Top 10 work, indirect prompt injection, the injection detector, sensitive-info-disclosure tests, jailbreak red-teaming. This skill just names the LLM categories for CI gating; that one defends the agent itself.
- **api-testing** — functional REST/GraphQL auth, input, and rate-limit tests with no attacker model involved; go there when nothing is actually being simulated as an attack.
- **shift-left-testing** — the dev-QA workflow, TDD practice, and definition-of-done that the shift-left principle here builds on.
- **test-environments** — secure configuration of test environments, secret handling, network isolation.
- **database-testing** — data integrity and access control enforced at the database layer.

## Reference Files (in `references/`)

- **owasp-tests.md** — runnable Playwright test code for OWASP A01–A10 (IDOR, SSRF, injection, crypto, security headers, rate limiting, supply-chain SBOM/provenance, exceptional conditions), plus the note on the acceptable-status-set matcher pattern.
- **scanning-and-ci.md** — ZAP, OSV-Scanner/Snyk, Semgrep plus ESLint flat-config SAST, secret scanning, and the full five-layer CI pipeline including the runnable dependency gate.
- **auth-tests.md** — session, JWT (`alg:none`, expiry), and RBAC matrix test code for A07.
