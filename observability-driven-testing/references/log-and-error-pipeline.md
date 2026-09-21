# Log-Informed Test Design & Error-to-Test Pipeline — Code

The runnable pieces for turning production errors into tests. `SKILL.md` covers the
reasoning — how to categorize errors, the prioritization matrix, the pipeline steps —
this file just holds the code that implements it.

## Scanning production error logs for test gaps

Every unhandled production error is effectively a missing test. This script formalizes
that mapping.

```typescript
// Script: analyze-production-errors.ts
// Run weekly to identify test gaps from production error data

interface ProductionError {
  message: string;
  stack: string;
  count: number;
  firstSeen: string;
  lastSeen: string;
  endpoint: string;
  userId?: string;
}

interface TestGap {
  error: ProductionError;
  coveredByTest: boolean;
  suggestedTestType: 'unit' | 'integration' | 'e2e';
  priority: 'critical' | 'high' | 'medium' | 'low';
}

function analyzeTestGaps(
  errors: ProductionError[],
  testCoverage: Map<string, string[]>, // endpoint -> test file paths
): TestGap[] {
  return errors.map(error => {
    const testsForEndpoint = testCoverage.get(error.endpoint) ?? [];
    const coveredByTest = testsForEndpoint.length > 0;

    // Prioritize by frequency and recency
    const daysSinceLastSeen = daysBetween(new Date(error.lastSeen), new Date());
    const priority = error.count > 100 && daysSinceLastSeen < 7 ? 'critical'
      : error.count > 50 ? 'high'
      : error.count > 10 ? 'medium'
      : 'low';

    // Suggest test type based on error characteristics
    const suggestedTestType = error.stack.includes('TypeError') ? 'unit'
      : error.stack.includes('timeout') || error.stack.includes('ECONNREFUSED') ? 'integration'
      : 'e2e';

    return { error, coveredByTest, suggestedTestType, priority };
  });
}
```

## A production error turned into a test, end to end

Below is what a test looks like when it's built directly from a real production
incident, with the origin documented right in the test file so nobody wonders why it
exists.

```typescript
// Test created from production error: Sentry issue PROJ-4521
// Error: "Cannot read properties of null (reading 'address')"
// Context: POST /api/orders when user has no shipping address saved
// Frequency: 47 occurrences in last 7 days

describe('order creation with missing shipping address', () => {
  // This test was created because production error PROJ-4521 showed that
  // users without a saved shipping address triggered a null reference error
  // in the order validation pipeline.

  it('returns 400 with clear error message when shipping address is null', async () => {
    const user = await createTestUser({ address: null });
    const response = await api.post('/api/orders', {
      userId: user.id,
      items: [{ sku: 'WIDGET-1', quantity: 1 }],
    });

    // 400 (malformed request) or 422 (well-formed but semantically invalid) are both
    // defensible for a missing-required-field case — pick the one your API contract uses
    // and assert it explicitly. Here the contract returns 400.
    expect([400, 422]).toContain(response.status);
    expect(response.body.error).toBe('MISSING_SHIPPING_ADDRESS');
    expect(response.body.message).toContain('shipping address is required');
  });

  it('prompts user to add address when attempting checkout without one', async ({ page }) => {
    await loginAs(page, { address: null });
    await page.goto('/checkout');
    await expect(page.getByText('Please add a shipping address')).toBeVisible();
    await expect(page.getByRole('link', { name: 'Add address' })).toBeVisible();
  });
});
```
