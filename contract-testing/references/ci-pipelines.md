# Contract Testing CI Pipelines — Code

The GitHub Actions workflows below cover both consumer and provider contract verification, plus the `can-i-deploy` deployment gate. `SKILL.md` explains the reasoning behind the workflow; this file is just the YAML and the raw commands.

## Consumer CI Pipeline

```yaml
# .github/workflows/consumer-contract.yml
name: Consumer Contract Tests
on: [push]

jobs:
  contract-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci

      - name: Run consumer contract tests
        run: npm run test:contract

      - name: Publish pacts to broker
        if: github.ref == 'refs/heads/main' || github.event_name == 'pull_request'
        env:
          PACT_BROKER_BASE_URL: ${{ secrets.PACT_BROKER_URL }}
          PACT_BROKER_TOKEN: ${{ secrets.PACT_BROKER_TOKEN }}
        run: |
          npx pact-broker publish ./pacts \
            --consumer-app-version="${{ github.sha }}" \
            --branch="${{ github.head_ref || github.ref_name }}"

      - name: Can I deploy?
        if: github.ref == 'refs/heads/main'
        env:
          PACT_BROKER_BASE_URL: ${{ secrets.PACT_BROKER_URL }}
          PACT_BROKER_TOKEN: ${{ secrets.PACT_BROKER_TOKEN }}
        run: |
          npx pact-broker can-i-deploy \
            --pacticipant="frontend-app" \
            --version="${{ github.sha }}" \
            --to-environment=production \
            --retry-while-unknown=6 \
            --retry-interval=10
```

`--retry-while-unknown` and `--retry-interval` keep the job polling the broker while its verdict is still "unknown." That's what covers the most common real failure: the consumer has just published a pact, but the provider hasn't finished verifying it yet — without these flags the gate would hard-fail on that timing race instead of waiting the verification out.

## Provider CI Pipeline

```yaml
# .github/workflows/provider-contract.yml
name: Provider Contract Verification
on:
  push:
  repository_dispatch:
    types: [pact-changed]  # Triggered by Pact Broker webhook

jobs:
  verify-contracts:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17-alpine
        env: { POSTGRES_DB: testdb, POSTGRES_USER: test, POSTGRES_PASSWORD: test }
        ports: ['5432:5432']
        options: >-
          --health-cmd="pg_isready -U test"
          --health-interval=5s
          --health-timeout=3s
          --health-retries=5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npm run db:migrate

      - name: Verify provider contracts
        env:
          TEST_DATABASE_URL: postgres://test:test@localhost:5432/testdb
          GIT_COMMIT: ${{ github.sha }}
          GIT_BRANCH: ${{ github.head_ref || github.ref_name }}
          PACT_BROKER_BASE_URL: ${{ secrets.PACT_BROKER_URL }}
          PACT_BROKER_TOKEN: ${{ secrets.PACT_BROKER_TOKEN }}
        run: npm run test:contract:provider

      - name: Can I deploy?
        if: github.ref == 'refs/heads/main'
        env:
          PACT_BROKER_BASE_URL: ${{ secrets.PACT_BROKER_URL }}
          PACT_BROKER_TOKEN: ${{ secrets.PACT_BROKER_TOKEN }}
        run: |
          npx pact-broker can-i-deploy \
            --pacticipant="user-service" \
            --version="${{ github.sha }}" \
            --to-environment=production \
            --retry-while-unknown=6 \
            --retry-interval=10
```

The gate sits on `main` on purpose, and it must never be bypassed there: `main` is the branch that reaches production. Skipping `can-i-deploy` on a feature branch is harmless, but skipping it on `main` means shipping a version the broker never confirmed was compatible — the exact production incident contract testing is meant to head off.

## can-i-deploy

`can-i-deploy` is what actually gates deployment. It queries the Pact Broker's matrix to determine whether a given version is safe to ship.

```bash
# Check if consumer can be deployed to production.
# --retry-while-unknown waits out the race where provider verification
# of the just-published pact hasn't landed yet.
npx pact-broker can-i-deploy \
  --pacticipant="frontend-app" \
  --version="abc123" \
  --to-environment=production \
  --retry-while-unknown=6 \
  --retry-interval=10

# Output:
# CONSUMER        | C.VERSION | PROVIDER     | P.VERSION | SUCCESS?
# frontend-app    | abc123    | user-service | def456    | true
# frontend-app    | abc123    | order-service| ghi789    | true
#
# All required verification results are published and successful.
# Computer says yes \o/

# Record deployment after successful deploy
npx pact-broker record-deployment \
  --pacticipant="frontend-app" \
  --version="abc123" \
  --environment=production
```

**Never deploy without a passing `can-i-deploy` result** — that check is the entire reason contract testing exists.
