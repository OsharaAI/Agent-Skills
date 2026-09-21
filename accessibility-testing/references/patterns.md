# Runnable Tests for Common Accessible Patterns

These are ready-to-use Playwright tests for the UI patterns that come up most often. The
reasoning, checklists, and pitfalls to avoid live in `SKILL.md` — this file is just the code.
Every test below checks the accessible tree (role, name, ARIA state) instead of CSS or raw DOM
structure, so a styling refactor won't break them.

## Forms That Report Errors Accessibly

```typescript
test('form displays accessible error messages', async ({ page }) => {
  await page.goto('/contact');
  await page.getByRole('button', { name: 'Send message' }).click();

  const emailInput = page.getByLabel('Email address');
  const emailError = page.getByText('Email is required');
  await expect(emailError).toBeVisible();

  // Verify aria-describedby links input to error
  const errorId = await emailError.getAttribute('id');
  expect(await emailInput.getAttribute('aria-describedby')).toContain(errorId);
  await expect(emailInput).toHaveAttribute('aria-invalid', 'true');
  await expect(emailInput).toBeFocused();
});
```

What this expects in the markup: `<label for="email">Email</label>` alongside `<input id="email"
aria-required="true" aria-invalid="true" aria-describedby="email-error">`, with `<p
id="email-error" role="alert">Email is required</p>` as the associated error.

## Dialogs That Follow the ARIA Modal Pattern

```typescript
test('dialog follows ARIA dialog pattern', async ({ page }) => {
  await page.goto('/dashboard');
  const trigger = page.getByRole('button', { name: 'Delete project' });
  await trigger.click();

  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog).toHaveAttribute('aria-labelledby');
  await expect(dialog).toHaveAttribute('aria-modal', 'true');
  await expect(dialog.locator(':focus')).toBeVisible(); // Focus inside dialog

  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await expect(trigger).toBeFocused(); // Focus returns to trigger
});
```

## The Three Most-Missed States: Open Dropdowns, aria-busy, Live Regions

In practice, these are the states teams forget to test — the ARIA only appears once the state is
triggered, so a default page-load snapshot never touches them. The trick is to click into the
state first, then assert.

```typescript
// Opened dropdown / menu — assert the ARIA of the open state, not just that it opened
test('dropdown menu is accessible when open', async ({ page }) => {
  await page.goto('/dashboard');
  const trigger = page.getByRole('button', { name: 'Account' });
  await expect(trigger).toHaveAttribute('aria-expanded', 'false');

  await trigger.click(); // click to trigger state change
  await expect(trigger).toHaveAttribute('aria-expanded', 'true');

  // A combobox-style listbox uses role="listbox"; a button menu uses role="menu"
  const menu = page.getByRole('menu'); // or getByRole('listbox') for a select-style widget
  await expect(menu).toBeVisible();
  await expect(menu.getByRole('menuitem')).toHaveCount(3);

  await page.keyboard.press('Escape');
  await expect(menu).toBeHidden();
  await expect(trigger).toHaveAttribute('aria-expanded', 'false');
  await expect(trigger).toBeFocused();
});
```

```typescript
// Loading skeleton announces busy state via aria-busy
test('loading skeleton sets aria-busy while fetching', async ({ page }) => {
  await page.goto('/reports');
  const region = page.getByRole('region', { name: 'Report data' });

  await page.getByRole('button', { name: 'Run report' }).click(); // triggers fetch
  await expect(region).toHaveAttribute('aria-busy', 'true'); // skeleton is announced as busy

  await expect(region).toHaveAttribute('aria-busy', 'false'); // resolves when data lands
  await expect(region.getByRole('table')).toBeVisible();
});
```

```typescript
// Toast / status message announced via a polite live region
test('toast notifications are announced', async ({ page }) => {
  await page.goto('/settings');
  const toastRegion = page.locator("[aria-live='polite']");
  await expect(toastRegion).toBeAttached();

  await page.getByRole('button', { name: 'Save changes' }).click();
  await expect(toastRegion.getByText('Settings saved')).toBeVisible();
});
```

## Data Tables With Sortable Columns

```typescript
test('table has proper headers and sort state', async ({ page }) => {
  await page.goto('/users');
  const table = page.getByRole('table', { name: 'User accounts' });
  await expect(table.getByRole('columnheader')).toHaveCount(5);

  const nameHeader = page.getByRole('columnheader', { name: 'Name' });
  await nameHeader.click();
  await expect(nameHeader).toHaveAttribute('aria-sort', 'ascending');
});
```

## Landmark Regions

```typescript
test('page has required landmarks', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByRole('banner')).toBeVisible();       // <header>
  await expect(page.getByRole('navigation')).toBeVisible();    // <nav>
  await expect(page.getByRole('main')).toBeVisible();          // <main>
  await expect(page.getByRole('main')).toHaveCount(1);         // Exactly one <main>
  await expect(page.getByRole('contentinfo')).toBeVisible();   // <footer>
});
```

## Snapshotting the Accessibility Tree (Playwright)

`toMatchAriaSnapshot()` captures the accessible tree as YAML and compares it against a stored
expectation. It's the tool of choice for catching a regression where something looks fine
visually but the underlying semantics quietly broke — a `<div>` dressed up to look like a button,
or a heading demoted to plain text. It checks structure and accessible names, never pixel output.

```typescript
test('navigation has correct accessible structure', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByRole('navigation', { name: 'Main' })).toMatchAriaSnapshot(`
    - navigation "Main":
      - link "Dashboard"
      - link "Projects"
      - link "Settings"
      - link "Help"
  `);
});

test('form has correct accessible structure', async ({ page }) => {
  await page.goto('/settings');
  await expect(page.getByRole('form', { name: 'Profile settings' })).toMatchAriaSnapshot(`
    - form "Profile settings":
      - textbox "Display name"
      - textbox "Email address"
      - combobox "Time zone"
      - checkbox "Email notifications"
      - button "Save changes"
  `);
});
```

Keep in mind that ARIA snapshots care about ordering and will capture whatever dynamic content is
present at the time. If a list can reorder or content loads asynchronously, the snapshot will be
flaky — narrow the scope to a stable container, or assert a partial snapshot instead of the whole
dynamic region.
