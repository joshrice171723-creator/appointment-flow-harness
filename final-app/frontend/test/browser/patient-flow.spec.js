const { test, expect } = require('@playwright/test');

test('all queues paginate independently and summary selection toggles the grid', async ({ page }) => {
  const cases = ['attention', 'progress', 'resolved'].flatMap((state, group) =>
    Array.from({ length: 25 }, (_, index) => ({
      id: group * 25 + index + 1, patient_id: group * 25 + index + 1,
      name: `${state} patient ${index + 1}`, state, visits: 1,
      reason: 'Patient requested a call.', first_visit: '2026-11-12T10:00:00',
      resolution: state === 'resolved' ? { kind: 'confirmed', actor: 'Front desk' } : undefined,
    })),
  );
  await page.route('**/api/board?*', (route) => route.fulfill({ json: {
    clinic: { id: 1, name: 'Austin', timezone: 'America/Chicago' },
    staff: { id: 1, name: 'Front desk' }, cases,
  } }));
  await page.goto('/front-desk?clinic=1');
  const attention = page.locator('.column.attention');
  const progress = page.locator('.column.progress');
  await expect(attention.locator('.work-card')).toHaveCount(10);
  await expect(progress.locator('.work-card')).toHaveCount(10);
  await attention.getByRole('button', { name: 'Next' }).click();
  await expect(attention.getByRole('status')).toHaveText('11–20 of 25');
  await expect(progress.getByRole('status')).toHaveText('1–10 of 25');
  await attention.getByLabel('Per page').selectOption('20');
  await expect(attention.locator('.work-card')).toHaveCount(20);
  await expect(attention.getByRole('status')).toHaveText('1–20 of 25');
  await attention.getByRole('button', { name: 'Next' }).click();
  await expect(attention.locator('.work-card')).toHaveCount(5);
  await expect(attention.getByRole('button', { name: 'Next' })).toBeDisabled();

  const summary = page.locator('.work-metrics').getByRole('button', { name: /Needs attention/ });
  await summary.click();
  await expect(page.locator('.column')).toHaveCount(1);
  expect(await attention.locator('.queue-cards').evaluate((element) =>
    getComputedStyle(element).gridTemplateColumns.split(' ').length)).toBeGreaterThan(1);
  await summary.click();
  await expect(page.locator('.column')).toHaveCount(2);

  await page.getByRole('button', { name: 'Resolved', exact: true }).click();
  const resolved = page.locator('.column.resolved');
  await expect(resolved.locator('.work-card')).toHaveCount(10);
  await resolved.getByRole('button', { name: 'Next' }).click();
  await expect(resolved.getByRole('status')).toHaveText('11–20 of 25');
  await resolved.getByLabel('Per page').selectOption('30');
  await expect(resolved.locator('.work-card')).toHaveCount(25);
  await expect(resolved.getByRole('button', { name: 'Next' })).toBeDisabled();

  await page.getByRole('button', { name: 'Active work', exact: true }).click();
  await page.getByLabel('Find a patient').fill('no matching patient');
  await expect(attention.getByRole('status')).toHaveText('0 of 0');
  await expect(progress.getByRole('status')).toHaveText('0 of 0');
  await expect(attention.getByRole('button', { name: 'Next' })).toBeDisabled();
  expect((await attention.locator('.queue-cards').boundingBox()).height).toBeGreaterThan(1000);
  expect((await progress.locator('.queue-cards').boundingBox()).height).toBeGreaterThan(1000);
});

test('active work filters reasons and counts down unanswered appointments', async ({ page }) => {
  await page.clock.install({ time: new Date('2030-01-10T12:00:00Z') });
  await page.route('**/api/board?*', async (route) => {
    const response = await route.fetch();
    const data = await response.json();
    const base = { state: 'attention', visits: 1, reason: 'Follow up', owner: null };
    data.cases = [
      { ...base, id: 901, name: 'Later unanswered', no_response: true, no_response_start_at: '2030-01-11T12:00:00Z' },
      { ...base, id: 902, name: 'Patient concern', reply_review: true },
      { ...base, id: 903, name: 'Blocked contact', reminders_blocked: true },
      { ...base, id: 904, name: 'Sooner unanswered', no_response: true, no_response_start_at: '2030-01-11T00:00:00Z' },
    ];
    await route.fulfill({ response, json: data });
  });
  await page.goto('/');
  await page.getByRole('button', { name: 'Open front desk' }).click();
  const type = page.getByLabel('Follow-up type', { exact: true });
  await type.selectOption('reply_review');
  await expect(page.locator('.work-card')).toHaveCount(1);
  await expect(page.locator('.work-card')).toContainText('Patient concern');
  await type.selectOption('reminders_blocked');
  await expect(page.locator('.work-card')).toHaveCount(1);
  await expect(page.locator('.work-card')).toContainText('Blocked contact');
  await type.selectOption('no_response');
  await expect(page.locator('.work-card h3')).toHaveText(['Sooner unanswered', 'Later unanswered']);
  await expect(page.locator('.work-card').first()).toContainText('No reply · appointment in 12 hrs');
  await page.clock.fastForward(60 * 60 * 1000);
  await expect(page.locator('.work-card').first()).toContainText('No reply · appointment in 11 hrs');
  await type.selectOption('all');
  await expect(page.locator('.work-card')).toHaveCount(4);
  await page.unrouteAll({ behavior: 'wait' });
});
