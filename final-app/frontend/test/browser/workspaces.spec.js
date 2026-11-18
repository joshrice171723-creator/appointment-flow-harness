const { test, expect } = require('@playwright/test');

test('empty and unrecognized API responses show a readable error', async ({ page }) => {
  const responses = ['', '{}'];
  await page.route('**/api/workspaces', (route) => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: responses.shift(),
  }));
  await page.goto('/');
  const invalidResponse = 'Appointment Flow returned an invalid response. Refresh to try again.';
  await expect(page.getByRole('alert')).toHaveText(invalidResponse);
  const reload = page.waitForResponse('**/api/workspaces');
  await page.getByRole('button', { name: 'Reload details' }).click();
  await reload;
  await expect(page.getByRole('alert')).toHaveText(invalidResponse);
  await expect(page.getByText('Unexpected end of JSON input')).toHaveCount(0);
});
