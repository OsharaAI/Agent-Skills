# Testcontainers — disposable real services for integration tests

`@testcontainers/postgresql` 11.x and its companion packages boot genuinely real services inside
Docker. Containers come up right before the test suite runs and get removed once it finishes.
Because mapped ports are **assigned randomly**, always fetch them through `getMappedPort()` /
`getConnectionUri()` rather than assuming `5432`/`6379`. (This randomness is exactly why the
Testcontainers port model can't be mixed with the docker-compose port model described in
`references/ci.md` — a suite needs to commit to one or the other.)

> **Keep image tags from going stale.** The versions pinned below are deliberately specific so
> runs stay reproducible, but that also means they age silently. `elasticsearch:8.12.0` is already
> noticeably behind the Elastic 9.x line (GA'd in 2026); revisit it — along with `postgres:17-alpine`
> and `redis:8-alpine` — on a regular cadence and re-pin to something current.

```bash
npm i -D testcontainers @testcontainers/postgresql @testcontainers/redis
```

```typescript
// test/helpers/containers.ts
import { PostgreSqlContainer, StartedPostgreSqlContainer } from "@testcontainers/postgresql";
import { RedisContainer, StartedRedisContainer } from "@testcontainers/redis";
import { GenericContainer, StartedTestContainer, Wait } from "testcontainers";

let postgres: StartedPostgreSqlContainer;
let redis: StartedRedisContainer;
let elasticsearch: StartedTestContainer;

export async function startContainers() {
  // Start all containers in parallel — sequential startup is the #1 cause of slow suites
  [postgres, redis, elasticsearch] = await Promise.all([
    new PostgreSqlContainer("postgres:17-alpine")
      .withDatabase("testdb")
      .withUsername("test")
      .withPassword("test")
      .start(),

    new RedisContainer("redis:8-alpine").start(),

    new GenericContainer("elasticsearch:8.12.0") // bump to a 9.x tag periodically
      .withEnvironment({
        "discovery.type": "single-node",
        "xpack.security.enabled": "false",
      })
      .withExposedPorts(9200)
      .withWaitStrategy(Wait.forHttp("/", 9200).forStatusCode(200))
      .start(),
  ]);

  return {
    databaseUrl: postgres.getConnectionUri(),
    redisUrl: `redis://${redis.getHost()}:${redis.getMappedPort(6379)}`,
    elasticsearchUrl: `http://${elasticsearch.getHost()}:${elasticsearch.getMappedPort(9200)}`,
  };
}

export async function stopContainers() {
  await Promise.all([postgres?.stop(), redis?.stop(), elasticsearch?.stop()]);
}
```

## Hooking it into Vitest

A `globalSetup` file is the natural place for this: call `startContainers()` from `setup()` and
`stopContainers()` from `teardown()`, exporting the returned URLs into `process.env` so ordinary
test code just reads `process.env.DATABASE_URL` and friends. Give the suite enough headroom for
containers to actually come up:

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    globalSetup: ["./test/global-setup.ts"],
    testTimeout: 30_000, // container startup can be slow on cold CI runners
  },
});
```

```typescript
// test/global-setup.ts
import { startContainers, stopContainers } from "./helpers/containers";

export async function setup() {
  const urls = await startContainers();
  process.env.DATABASE_URL = urls.databaseUrl;
  process.env.REDIS_URL = urls.redisUrl;
  process.env.ELASTICSEARCH_URL = urls.elasticsearchUrl;
}

export async function teardown() {
  await stopContainers();
}
```
</content>
