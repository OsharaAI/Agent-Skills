# Traces as Test Evidence — Code

The concrete OpenTelemetry test-runner wiring and the trace-based assertion patterns.
The reasoning behind treating traces as evidence — and when a span-level check is
worth writing — is in `SKILL.md`; this file is the implementation.

## Wiring OpenTelemetry into the test runner

Instrument the runner so the traces it produces correlate with the application's own
traces during the same run.

```typescript
// test-setup/tracing.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources'; // helper preferred over `new Resource(...)` on @opentelemetry/sdk-node >= 0.50
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'integration-tests',
    'test.suite': process.env.TEST_SUITE_NAME ?? 'unknown',
    'test.run_id': process.env.CI_RUN_ID ?? `local-${Date.now()}`,
  }),
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_ENDPOINT ?? 'http://localhost:4318/v1/traces',
  }),
});

export async function startTracing() {
  sdk.start();
}

// Flush and shut down from the runner's GLOBAL TEARDOWN hook, awaiting the promise
// so the exporter finishes flushing before the process exits.
export async function stopTracing() {
  await sdk.shutdown();
}
```

> **Don't wire the flush to `process.on('beforeExit', () => sdk.shutdown())`.**
> `beforeExit` never fires on an explicit `process.exit()`, an uncaught exception, or a
> SIGINT/SIGTERM — which cover most of the ways a test run actually ends — and because
> the promise isn't awaited, it can drop the final spans of the run. Hook
> `stopTracing()` into teardown instead:

```typescript
// playwright: global-teardown.ts (config.globalTeardown), or
// vitest: return the teardown from globalSetup
import { stopTracing } from './test-setup/tracing';
export default async function globalTeardown() {
  await stopTracing(); // awaited flush — no trailing spans dropped
}
```

### A faster, deterministic option: the in-memory exporter

For assertions scoped to a single service's own spans, you don't need a real
collector or a `waitForTrace` poll at all. Send spans to an in-process
`InMemorySpanExporter` through a `SimpleSpanProcessor`, run the code under test, then
read them back synchronously with `exporter.getFinishedSpans()` — no network round
trip, no async wait, no flakiness from a timeout. This covers the large majority of
cases (checking one service's own spans); reserve the collector + `waitForTrace`
approach below for traces that genuinely cross process boundaries.

## Building assertions on trace shape

Check span structure, attributes, and timing — go beyond just the HTTP response.

> **Force-sample your test traffic.** Head-based or probabilistic sampling can drop
> exactly the trace a test is trying to assert on — this is the number one reason
> these tests end up intermittently flaky. Run the workload under an always-on
> sampler (`OTEL_TRACES_SAMPLER=always_on`) or a per-request override so the trace
> you're asserting on is guaranteed to actually be recorded. Never rely on a
> probabilistically sampled trace for an assertion.

```typescript
import { expect } from '@playwright/test';
import { TraceCollector } from './trace-collector';

test('order creation produces correct trace structure', async ({ request }) => {
  const collector = new TraceCollector();
  const traceId = crypto.randomUUID().replace(/-/g, '');

  // Make request with trace context
  const response = await request.post('/api/orders', {
    data: { items: [{ sku: 'WIDGET-1', quantity: 2 }] },
    headers: { 'traceparent': `00-${traceId}-${crypto.randomUUID().replace(/-/g, '').slice(0, 16)}-01` },
  });
  expect(response.ok()).toBeTruthy();

  // Wait for trace to propagate (async collection)
  const trace = await collector.waitForTrace(traceId, { timeout: 10_000 });

  // Assert on trace structure
  const spans = trace.spans;

  // Verify the expected service calls happened
  const serviceNames = spans.map(s => s.resource['service.name']);
  expect(serviceNames).toContain('api-gateway');
  expect(serviceNames).toContain('order-service');
  expect(serviceNames).toContain('inventory-service');

  // Verify no unexpected errors in any span.
  // NOTE: the literal here is collector-dependent. The OTel status code is an enum;
  // in OTLP/JSON it serializes as the integer 2 (STATUS_CODE_ERROR) or the string
  // 'STATUS_CODE_ERROR' depending on your collector/exporter normalization — not a
  // bare 'ERROR'. Match what YOUR TraceCollector emits; do not copy 'ERROR' blindly.
  const errorSpans = spans.filter(s => s.status?.code === 'ERROR');
  expect(errorSpans).toHaveLength(0);

  // Verify latency requirements
  const rootSpan = spans.find(s => !s.parentSpanId);
  expect(rootSpan!.durationMs).toBeLessThan(500);

  // Verify correct database operations
  const dbSpans = spans.filter(s => s.attributes['db.system'] !== undefined);
  expect(dbSpans.some(s => s.attributes['db.operation'] === 'INSERT')).toBeTruthy();
  expect(dbSpans.some(s => s.attributes['db.statement']?.toString().includes('orders'))).toBeTruthy();
});
```

## Checking multi-service flow

For a microservices setup, confirm requests actually pass through the services you
expect, in the order you expect.

```typescript
// Trace structure assertion helper
interface ExpectedSpan {
  service: string;
  operation: string;
  attributes?: Record<string, string | number>;
  maxDuration?: number;
}

async function assertTraceStructure(
  traceId: string,
  expected: ExpectedSpan[],
  collector: TraceCollector,
): Promise<void> {
  const trace = await collector.waitForTrace(traceId, { timeout: 15_000 });

  for (const exp of expected) {
    const matching = trace.spans.find(
      s => s.resource['service.name'] === exp.service && s.name === exp.operation,
    );

    expect(matching, `Expected span: ${exp.service}/${exp.operation}`).toBeDefined();

    if (exp.attributes) {
      for (const [key, value] of Object.entries(exp.attributes)) {
        expect(matching!.attributes[key]).toBe(value);
      }
    }

    if (exp.maxDuration) {
      expect(matching!.durationMs).toBeLessThan(exp.maxDuration);
    }
  }
}

// Usage
test('checkout flow traverses expected services', async ({ request }) => {
  const traceId = generateTraceId();
  await request.post('/api/checkout', {
    headers: { traceparent: formatTraceparent(traceId) },
    data: { cartId: 'test-cart-123' },
  });

  await assertTraceStructure(traceId, [
    { service: 'api-gateway', operation: 'POST /api/checkout' },
    { service: 'cart-service', operation: 'getCart', maxDuration: 100 },
    { service: 'pricing-service', operation: 'calculateTotal', maxDuration: 200 },
    { service: 'payment-service', operation: 'processPayment', attributes: { 'payment.provider': 'stripe' } },
    { service: 'order-service', operation: 'createOrder' },
    { service: 'notification-service', operation: 'sendConfirmation' },
  ], collector);
});
```
