# Cross-Browser Testing Patterns — Code

Runnable examples for writing a single test that runs across many browsers, branching on `browserName` only where behavior truly diverges, comparing screenshots visually, and validating progressive enhancement. `SKILL.md` covers the rules for *when* each pattern applies.

## Same Test, Multiple Browsers

The default approach: write it once, let project configuration handle the rest.

```typescript
// This test runs on every configured browser project automatically
test('user can complete checkout', async ({ page }) => {
  await page.goto('/cart');
  await page.getByRole('button', { name: 'Checkout' }).click();
  await page.getByLabel('Card number').fill('4242424242424242');
  await page.getByLabel('Expiry').fill('12/28');
  await page.getByLabel('CVC').fill('123');
  await page.getByRole('button', { name: 'Pay' }).click();
  await expect(page.getByRole('heading', { name: 'Order confirmed' })).toBeVisible();
});
```

## Browser-Specific Test Logic

Branch on `browserName` only where the underlying behavior genuinely differs.

```typescript
test('file upload works', async ({ page, browserName }) => {
  await page.goto('/upload');
  const fileInput = page.locator('input[type="file"]');

  // WebKit does not support directory upload
  if (browserName === 'webkit') {
    await fileInput.setInputFiles('/path/to/file.pdf');
  } else {
    await fileInput.setInputFiles(['/path/to/file1.pdf', '/path/to/file2.pdf']);
  }

  await expect(page.getByText('Upload complete')).toBeVisible();
});
```

**Rule:** keep browser-specific branches rare in your test suite. A large number of them is usually a sign the application itself has compatibility bugs that need fixing.

## Visual Cross-Browser Comparison

Lean on Playwright's built-in screenshot comparison to catch rendering drift.

```typescript
test('homepage renders correctly', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveScreenshot('homepage.png', {
    maxDiffPixelRatio: 0.01, // Allow 1% pixel difference
  });
  // Each browser project generates its own baseline:
  // homepage-chromium.png, homepage-webkit.png, homepage-firefox.png
});
```

## Progressive Enhancement Validation

Intercept and abort any request where `resourceType === 'script'` so the page effectively runs without JavaScript, then confirm the native HTML form still submits correctly. This route-interception technique only works under Chromium, so gate it behind `browserName === 'chromium'`.

```typescript
test('form works without JavaScript', async ({ page, browserName }) => {
  // Disable JavaScript to test progressive enhancement
  // Note: only works with Chromium
  if (browserName === 'chromium') {
    await page.context().route('**/*', (route) => {
      if (route.request().resourceType() === 'script') {
        return route.abort();
      }
      return route.continue();
    });
  }

  await page.goto('/contact');
  // Core form submission should work via native HTML form action
  await page.getByLabel('Message').fill('Hello');
  await page.getByRole('button', { name: 'Send' }).click();
  // Even without JS, the form should submit and show confirmation
  await expect(page).toHaveURL(/.*thank-you/);
});
```
</content>
