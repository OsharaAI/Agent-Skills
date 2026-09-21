# Risk-Based Testing — Worked Examples

Four scored examples showing the full path from a risk score to the coverage it
prescribes. Each one follows the same shape: the risk profile (Impact,
Probability, composite score, and zone), the failure modes surfaced in Phase 3,
and the coverage the Phase-5 by-zone table calls for.

---

## Example 1: E-commerce Checkout

**Risk profile:** Impact 5, Probability 4 → Score 20 (CRITICAL)

**Failure modes surfaced:**
- Payment goes through but no order gets created (a race condition)
- Stacked discounts compute the wrong total
- Inventory oversells under concurrent load
- The shipping calculator quotes the wrong rate for international addresses
- Tax comes out wrong in certain jurisdictions

**Coverage this calls for:**
- Unit tests: every discount combination, jurisdiction-specific tax rules, inventory decrement logic
- Integration tests: payment gateway communication (success, failure, timeout, duplicate calls), the order-creation pipeline, inventory reservation under concurrent access
- E2E tests: full checkout as guest and as logged-in user, checkout with a discount applied, checkout with international shipping, retrying checkout after a failed payment
- Load tests: 100 simultaneous checkout attempts on a last-unit-in-stock item
- Monitoring: real-time order completion rate, payment-to-order reconciliation every 5 minutes, revenue anomaly detection

---

## Example 2: Content Delivery (Media Platform)

**Risk profile:** Impact 4, Probability 3 → Score 12 (HIGH)

**Failure modes surfaced:**
- A CDN cache miss overloads the origin server
- Video transcoding fails silently for certain codecs
- Thumbnail generation times out and leaves a blank image behind
- The recommendation engine returns stale or empty results

**Coverage this calls for:**
- Unit tests: input validation on the transcoding pipeline, the recommendation scoring algorithm
- Integration tests: CDN purge/refresh flow, transcoding job queue processing, thumbnail generation across every supported format
- E2E tests: content upload through to playback, content discovery through to a recommendation click
- Monitoring: CDN hit ratio, transcoding failure rate, p99 thumbnail generation latency

---

## Example 3: Third-Party API Integration

**Risk profile:** Impact 4, Probability 4 → Score 16 (CRITICAL)

**Failure modes surfaced:**
- Rate limit gets exceeded during peak traffic
- The API's response schema changes without warning, breaking deserialization
- A timeout on the API cascades into a failure across a synchronous call chain
- The API returns HTTP 200 with an error body instead of a proper error status

**Coverage this calls for:**
- Unit tests: the response parser against every known shape including malformed ones, rate-limit backoff calculation, circuit breaker state transitions
- Integration tests: contract tests validating the response schema against what's expected, timeout handling, retry behavior, circuit breaker activation
- E2E tests: the user experience when the API is slow but functional, and when the API is fully down (does the fallback actually work?)
- Monitoring: API response time at p50/p95/p99, error rate, proximity to the rate limit, circuit breaker state

---

## Example 4: Authentication Flows

**Risk profile:** Impact 5, Probability 2 → Score 10 (HIGH)

**Failure modes surfaced:**
- A session token isn't invalidated after a password change
- A race condition in the OAuth callback opens the door to account takeover
- An API endpoint skips the MFA check, allowing a bypass
- Login endpoint has no rate limiting, leaving it open to brute force

**Coverage this calls for:**
- Unit tests: token generation and validation, password hashing, MFA code verification, rate-limit counter logic
- Integration tests: the full auth flow (register, login, logout, password reset), session invalidation on credential change, OAuth across every supported provider, MFA enrollment and verification
- E2E tests: login (valid credentials, invalid credentials, locked account), password reset flow, MFA flow
- Security tests: simulated brute force (confirming rate limiting kicks in), session fixation, reusing a token after logout
- Monitoring: spikes in failed login rate, unusual session patterns, MFA bypass attempts
</content>
