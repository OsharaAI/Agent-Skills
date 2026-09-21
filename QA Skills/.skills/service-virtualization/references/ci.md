# Wiring service virtualization into GitHub Actions

## MSW needs nothing extra

Because MSW intercepts in-process, there's no infrastructure to stand up for it — no Docker, no
ports to open, no health checks to wait on. The only thing that changes between local and CI is
that `onUnhandledRequest` must be `"error"` in CI (see `references/msw.md`), so a real call that
slips past the stubs kills the run instead of passing quietly.

```yaml
- name: Run tests with MSW stubs
  run: npm run test:integration   # onUnhandledRequest:"error" in CI; "warn" locally
```

## Running WireMock and Testcontainers in CI

Two **port models** exist here and they don't mix within a single suite:

- **The docker-compose model** publishes **fixed** ports (`5432`, `8080`), which is what lets a
  test hardcode a connection string like
  `DATABASE_URL=postgres://test:test@localhost:5432/testdb`.
- **The Testcontainers model** hands out **random** ports instead, discovered at runtime through
  `getMappedPort()` and exported into `process.env` by global setup (see
  `references/testcontainers.md`).

The example below follows the docker-compose (fixed-port) approach. Don't combine its hardcoded
`localhost:5432` with a Testcontainers-based helper in the same suite — they're built on
conflicting assumptions about where ports live.

```yaml
# GitHub Actions — docker-compose (fixed-port) model
- name: Start test infrastructure
  run: docker compose -f docker-compose.test.yml up -d --wait --wait-timeout 120

- name: Run integration tests
  env:
    WIREMOCK_URL: http://localhost:8080
    DATABASE_URL: postgres://test:test@localhost:5432/testdb
  run: npm run test:integration

- name: Teardown
  if: always()   # tear down even when tests fail
  run: docker compose -f docker-compose.test.yml down -v
```

`--wait --wait-timeout 120` holds the job until every compose service reports healthy (which
requires a `healthcheck:` block in the compose file). `if: always()` makes sure teardown still runs
after a failed step, so nothing lingers between jobs.

## Matching a CI constraint to a tool

| Constraint | Recommended tool |
|-----------|-----------------|
| No Docker in CI runners | MSW (in-process) |
| Multi-language services | WireMock (language-agnostic) |
| Need real database behavior | Testcontainers or GitHub Actions services |
| Testing network failures | Toxiproxy + real/containerized services |
| Browser-based API mocking | MSW (browser mode with Service Worker) |
</content>
