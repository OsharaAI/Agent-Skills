# Toxiproxy — injecting network faults on purpose

Toxiproxy (`ghcr.io/shopify/toxiproxy:2.12.0`) installs itself as a TCP proxy sitting between your
application and a dependency, and lets you dial in latency, cap bandwidth, or force connection
resets on demand. Point the app at the **proxy** port rather than the real service so the link can
be degraded at runtime whenever a test needs it.

For larger-scale resilience work — fault-injection campaigns, game days, blast-radius limits —
that belongs in `chaos-engineering`; this file only covers making a single dependency misbehave
inside one test.

## Compose port layout

```yaml
# In docker-compose.test.yml
toxiproxy:
  image: ghcr.io/shopify/toxiproxy:2.12.0
  ports:
    - "8474:8474"   # Toxiproxy admin API
    - "15432:15432" # Proxied PostgreSQL (app connects HERE, not to 5432)
    - "16379:16379" # Proxied Redis      (app connects HERE, not to 6379)
```

The proxy's `listen` address is whichever published port is shown above (e.g. `0.0.0.0:15432`),
while `upstream` is the **actual** service's host:port as seen from inside the Toxiproxy container.
Under docker-compose that's simply the service name plus its internal port (`postgres:5432`).
Under Testcontainers, the upstream instead has to be the container's dynamically mapped host:port
— read via `getHost()`/`getMappedPort()` and passed into `createProxy`. Don't assume a fixed
5432/6379 upstream if Testcontainers is what's provisioning the dependency.

## Helper functions — every response gets checked

Nothing here swallows a failed call silently. A helper that ignores a failed proxy-creation request
is worse than having no helper at all, because the test would go green even though no toxic was
ever actually applied.

```typescript
// test/helpers/toxiproxy.ts
const TOXIPROXY_API = "http://localhost:8474";

async function post(path: string, body: unknown) {
  const res = await fetch(`${TOXIPROXY_API}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Toxiproxy ${path} failed: ${res.status} ${await res.text()}`);
  return res;
}

// listen = the published proxy port (e.g. "0.0.0.0:15432")
// upstream = the REAL service host:port (compose: "postgres:5432"; Testcontainers: mapped host:port)
export async function createProxy(name: string, listen: string, upstream: string) {
  await post("/proxies", { name, listen, upstream, enabled: true });
}

export async function addLatency(proxyName: string, latencyMs: number) {
  await post(`/proxies/${proxyName}/toxics`, {
    name: "latency",
    type: "latency",
    attributes: { latency: latencyMs, jitter: Math.floor(latencyMs * 0.1) },
  });
}

export async function severeConnection(proxyName: string) {
  await post(`/proxies/${proxyName}/toxics`, {
    name: "reset_peer",
    type: "reset_peer",
    attributes: { timeout: 0 },
  });
}

export async function removeToxics(proxyName: string) {
  const res = await fetch(`${TOXIPROXY_API}/proxies/${proxyName}/toxics`);
  if (!res.ok) throw new Error(`Toxiproxy list toxics failed: ${res.status}`);
  const toxics = (await res.json()) as Array<{ name: string }>;
  for (const toxic of toxics) {
    const del = await fetch(`${TOXIPROXY_API}/proxies/${proxyName}/toxics/${toxic.name}`, {
      method: "DELETE",
    });
    if (!del.ok) throw new Error(`Toxiproxy delete toxic ${toxic.name} failed: ${del.status}`);
  }
}
```

## Putting it to use in a test

```typescript
beforeAll(async () => {
  // upstream points at the real Postgres reachable from the Toxiproxy container
  await createProxy("postgres", "0.0.0.0:15432", "postgres:5432");
});

afterEach(() => removeToxics("postgres")); // always clean up — toxics leak across tests otherwise

it("handles a slow database within the timeout budget", async () => {
  await addLatency("postgres", 500);
  await expect(queryWithTimeout(300)).rejects.toThrow(/timeout/i);
});

it("reconnects after the connection is severed", async () => {
  await severeConnection("postgres");
  await removeToxics("postgres"); // restore the link
  await expect(retryUntilConnected()).resolves.toBe(true);
});
```
</content>
