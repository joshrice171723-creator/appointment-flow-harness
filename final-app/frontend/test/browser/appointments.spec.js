const { test, expect } = require('@playwright/test');

test('staff calendar pages dates and keeps patient messaging in its own workspace', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Open front desk' }).click();
  await expect(page).toHaveURL(/front-desk/);
  const initialCalendar = page.waitForResponse((response) =>
    response.url().includes('/api/appointments?') && response.ok(),
  );
  await page.getByRole('link', { name: 'Appointments', exact: true }).click();
  const initialData = await (await initialCalendar).json();
  const date = page.getByLabel('Jump to date');
  await expect(date).not.toHaveValue('');
  // The current date can be Sunday; choose an actual source appointment in this week.
  const appointment = initialData.visits.find((visit) => visit.provider_name);
  expect(appointment).toBeTruthy();
  await date.fill(appointment.start_at.slice(0, 10));
  await expect(page.locator('tbody')).toContainText(appointment.provider_name);
  const before = await date.inputValue();
  const refreshed = page.waitForResponse((response) =>
    response.url().includes('/api/appointments?') && response.ok(),
  );
  await page.getByRole('button', { name: 'Next week' }).click();
  const data = await (await refreshed).json();
  expect(data.date).not.toBe(before);
  await expect(date).not.toHaveValue(before);
  await page.getByRole('button', { name: 'Previous week' }).click();
  await expect(date).toHaveValue(before);
  await expect(page.getByRole('link', { name: /message simulator|patient inbox/i })).toHaveCount(0);
  await expect(page.getByText('Unexpected end of JSON input')).toHaveCount(0);
});

test('a later decline stays in review rather than the confirmed count', async ({ page }) => {
  await page.route('**/api/appointments?*', async (route) => {
    const response = await route.fetch();
    const data = await response.json();
    const visit = {
      appointment_id: 900001,
      start_at: `${data.date}T12:00:00`,
      name: 'Confirmed fixture',
      status: 'scheduled',
      outcome: 'unknown',
      confirmed_at: '2026-11-05T16:00:00Z',
    };
    data.visits = [visit, {
      ...visit,
      appointment_id: 900002,
      name: 'Declined fixture',
      declined_reply: { body: 'NO' },
      reply: { case_id: 1, code: 'patient' },
    }];
    await route.fulfill({ response, json: data });
  });
  await page.goto('/');
  await page.getByRole('button', { name: 'Open front desk' }).click();
  await expect(page).toHaveURL(/front-desk/);
  await page.getByRole('link', { name: 'Appointments', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Confirmed 1', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Confirmed 1', exact: true }).click();
  await expect(page.locator('tbody')).toContainText('Confirmed fixture');
  await expect(page.locator('tbody')).not.toContainText('Declined fixture');
  await page.getByRole('button', { name: 'Replies to review 1', exact: true }).click();
  await expect(page.locator('tbody')).toContainText('Declined fixture');
  await expect(page.locator('tbody')).toContainText('Replied NO');
});
