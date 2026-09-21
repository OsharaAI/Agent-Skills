# Full Docker Compose Setup for Tests

The reasoning behind these choices — environment tiers, and the Compose-vs-Testcontainers
comparison — lives in `SKILL.md`. What's here is purely the runnable artifacts: the
`docker-compose.test.yml` itself, the integration test runner, the multi-stage Dockerfile
(production target included), and the MinIO configuration.

## `docker-compose.test.yml`

This compose file brings up the entire stack needed for integration and E2E testing. Two
things worth noting: it uses `mailpit` rather than MailHog (which hasn't shipped a release
since 2020), and the `seed` service relies on `condition: service_completed_successfully` so
the app waits until seeding actually *finishes* before starting.

```yaml
# docker-compose.test.yml
name: app-test

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: test  # Multi-stage: use the test stage
    ports:
      - "3000:3000"
    environment:
      NODE_ENV: test
      DATABASE_URL: postgres://test:test@postgres:5432/testdb
      REDIS_URL: redis://redis:6379
      STRIPE_API_KEY: sk_test_fake  # Test-mode key, never real
      EMAIL_PROVIDER: stub          # Internal stub, no real emails
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      seed:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 5s
      timeout: 3s
      retries: 10

  postgres:
    image: postgres:18-alpine
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    volumes:
      - postgres-test-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test -d testdb"]
      interval: 3s
      timeout: 2s
      retries: 10

  redis:
    image: redis:8-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 3s
      timeout: 2s
      retries: 10

  seed:
    build:
      context: .
      dockerfile: Dockerfile
      target: seed
    environment:
      DATABASE_URL: postgres://test:test@postgres:5432/testdb
    depends_on:
      postgres:
        condition: service_healthy
    command: ["npm", "run", "db:seed"]

  mailpit:
    image: axllent/mailpit:latest
    ports:
      - "8025:8025"   # Web UI for inspecting sent emails
      - "1025:1025"   # SMTP

volumes:
  postgres-test-data:
```

## Running the Integration Suite Against Compose

This runner uses `trap` to guarantee teardown regardless of how the run ends — success,
failure, or a Ctrl-C — so a crashed test suite never leaves containers or volumes hanging
around.

```bash
#!/bin/bash
# scripts/test-integration.sh
set -euo pipefail

COMPOSE_FILE="docker-compose.test.yml"

cleanup() {
  echo "Tearing down test environment..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
}
trap cleanup EXIT

echo "Starting test infrastructure..."
docker compose -f "$COMPOSE_FILE" up -d --wait --wait-timeout 60

echo "Running integration tests..."
DATABASE_URL="postgres://test:test@localhost:5432/testdb" \
REDIS_URL="redis://localhost:6379" \
  npx vitest run --project=integration

echo "Tests complete."
```

## Multi-Stage Dockerfile

Dependencies get installed exactly once, in a `base` layer that `development`, `test`, and
`seed` all build from; `production` is a separate, minimal runtime stage that leaves dev
dependencies out entirely. `base` uses `npm ci --include=dev` — the current flag;
`--production=false` is the deprecated `--omit`/`--include` syntax. When `SKILL.md` refers to
"the dev-deps-excluded image," this `production` stage is what it means.

```dockerfile
# Dockerfile
FROM node:24-alpine AS base
WORKDIR /app
COPY package*.json ./
RUN npm ci --include=dev

FROM base AS development
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]

FROM base AS test
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "start"]

FROM base AS seed
COPY prisma/ ./prisma/
COPY scripts/seed.ts ./scripts/
COPY tsconfig.json ./
CMD ["npx", "tsx", "scripts/seed.ts"]

# Slim runtime: production deps only, build artifacts copied from `test`.
FROM node:24-alpine AS production
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=test /app/dist ./dist
EXPOSE 3000
CMD ["npm", "start"]
```

## MinIO in Place of S3

A containerized, S3-compatible object store means local and CI tests never need to touch a
real AWS bucket.

```yaml
# In docker-compose.test.yml
minio:
  image: minio/minio:latest
  ports:
    - "9000:9000"
    - "9001:9001"  # Console
  environment:
    MINIO_ROOT_USER: minioadmin
    MINIO_ROOT_PASSWORD: minioadmin
  command: server /data --console-address ":9001"
  healthcheck:
    test: ["CMD", "mc", "ready", "local"]
    interval: 5s
    timeout: 3s
    retries: 5
```

```typescript
// Configure S3 client to point at MinIO in tests
import { S3Client } from "@aws-sdk/client-s3";

const s3 = new S3Client({
  endpoint: process.env.S3_ENDPOINT ?? "http://localhost:9000",
  region: "us-east-1",
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY ?? "minioadmin",
    secretAccessKey: process.env.S3_SECRET_KEY ?? "minioadmin",
  },
  forcePathStyle: true, // Required for MinIO
});
```
