const { test, expect } = require('@playwright/test');

test('leadership reports supplied statuses without invented attendance fields', async ({ page }) => {
  await page.goto('/');
  const report = page.waitForResponse((response) =>
    response.url().includes('/api/operations?month=') && response.ok(),
  );
  await page.getByRole('button', { name: 'Open Apex leadership' }).click();
  await report;
  await expect(page.getByRole('region', { name: 'Austin outcomes' }).getByText('Completed visits', { exact: true })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Phoenix outcomes' }).getByText('Completed visits', { exact: true })).toBeVisible();
  await expect(page.getByText('On-time arrivals', { exact: true })).toHaveCount(0);
  await expect(page.getByText('No-show rate', { exact: true })).toHaveCount(0);
  await page.getByText('How rates are calculated', { exact: true }).click();
  await expect(page.getByText(/broken means rescheduled/)).toBeVisible();
});

test('changing the outcome month keeps open follow-up details visible', async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto('/');
  const initialReport = page.waitForResponse((result) =>
    result.url().includes('/api/operations?month=') && result.ok(),
  );
  await page.getByRole('button', { name: 'Open Apex leadership' }).click();
  await initialReport;
  const monthPicker = page.getByLabel('Outcome month');
  await expect(monthPicker).toBeVisible();
  const currentMonth = await monthPicker.inputValue();
  const previousMonth = await monthPicker.locator('option').evaluateAll(
    (options, current) => options.find((option) => option.value < current)?.value,
    currentMonth,
  );
  expect(previousMonth).toBeTruthy();

  const details = page.getByText('Contact and follow-up', { exact: true });
  await details.focus();
  await page.keyboard.press('Enter');
  const counts = page.getByRole('region', { name: 'Contact and follow-up counts' });
  await expect(counts).toBeVisible();

  const response = page.waitForResponse((result) =>
    result.url().includes('/api/operations?month=' + previousMonth) && result.ok(),
  );
  await monthPicker.selectOption(previousMonth);
  const report = await (await response).json();
  for (const clinic of report.clinics) {
    const row = report.rows.find((item) => item.outcome_month === previousMonth && item.clinic_id === clinic.id);
    await expect(page.getByRole('region', { name: clinic.name + ' outcomes' }))
      .toContainText(`${(row?.total || 0).toLocaleString()} recorded visits`);
  }
  await expect(counts).toBeVisible();
});
