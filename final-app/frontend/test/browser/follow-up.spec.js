const { test, expect } = require('@playwright/test');

test('board opens the patient workspace and sends follow-up actions to the case', async ({ page }) => {
  const staff = { id: 1, name: 'Front desk' };
  const clinic = { id: 1, name: 'Austin', timezone: 'America/Chicago' };
  const followUp = { id: 901, patient_id: 77, state: 'attention', name: 'Demo Patient 77', version: 1 };
  const issues = [
    { id: 1, appointment_id: 100, reason: 'First open item' },
    { id: 2, appointment_id: 200, reason: 'Second open item' },
  ];
  await page.route('**/api/board?*', (route) => route.fulfill({ json: { clinic, staff, cases: [followUp] } }));
  await page.route('**/api/patient-details/77', (route) => route.fulfill({
    json: { case: followUp, clinic, staff, person: { id: 77, name: followUp.name }, details: [], issues },
  }));
  await page.route('**/api/patient-details/77/history?*', (route) => route.fulfill({ json: { rows: [], next_cursor: null } }));
  await page.route('**/api/work/901', (route) => {
    if (route.request().postDataJSON().outcome === 'claim') {
      Object.assign(followUp, { state: 'progress', owner_id: staff.id, version: 2 });
    }
    return route.fulfill({ json: { message: 'Follow-up saved.' } });
  });

  await page.goto('/front-desk?clinic=1');
  await page.getByRole('link', { name: /Demo Patient 77/ }).click();
  await expect(page).toHaveURL(/\/patient-details\/77$/);
  await expect(page.getByText('First open item', { exact: true })).toBeVisible();
  await expect(page.getByText('Second open item', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Assign to me' }).click();
  await page.getByRole('button', { name: 'Record follow-up', exact: true }).click();
  await page.getByLabel('Follow-up item').selectOption('2');
  await page.getByLabel('Result').selectOption('attempted');
  await page.getByLabel('What happened?').fill('Left a voicemail.');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(page.getByRole('complementary', { name: 'Patient details' })).toBeVisible();
  await page.getByRole('button', { name: 'Activity log', exact: true }).click();
  await page.getByRole('button', { name: /^Follow-up/ }).click();
  await page.getByRole('button', { name: 'Record follow-up', exact: true }).click();
  await expect(page.getByLabel('What happened?')).toHaveValue('Left a voicemail.');
  const save = page.waitForRequest((request) => request.url().endsWith('/api/work/901') && request.method() === 'POST');
  await page.getByRole('button', { name: 'Save follow-up' }).click();
  expect((await save).postDataJSON()).toEqual({ outcome: 'attempted', issue: '2', note: 'Left a voicemail.', version: 2 });
});

test('resolved follow-ups keep their outcome and readable activity history', async ({ page }) => {
  const resolution = { kind: 'confirmed', actor: 'Front desk', reason: 'Patient confirmed by phone.' };
  const followUp = { id: 901, patient_id: 77, state: 'resolved', name: 'Resolved fixture', owner: 'Front desk', visits: 1, resolution };
  await page.route('**/api/board?*', async (route) => {
    const response = await route.fetch();
    const data = await response.json();
    data.cases = [followUp];
    await route.fulfill({ response, json: data });
  });
  await page.route('**/api/patient-details/77', (route) => route.fulfill({
    json: {
      case: followUp,
      person: { id: 77, name: followUp.name },
      details: [],
      clinic: { id: 1, name: 'Austin', timezone: 'America/Chicago' },
      staff: { name: 'Front desk' },
    },
  }));
  await page.route('**/api/patient-details/77/history?*', (route) => route.fulfill({
    json: {
      next_cursor: null,
      rows: new URL(route.request().url()).searchParams.get('section') === 'activity' ? [{
        id: 1,
        entry_type: 'event',
        kind: 'confirmed',
        actor: resolution.actor,
        body: resolution.reason,
        created_at: '2026-11-05T16:00:00Z',
      }] : [],
    },
  }));
  await page.goto('/');
  await page.getByRole('button', { name: 'Open front desk' }).click();
  await page.getByRole('button', { name: 'Resolved', exact: true }).click();
  const card = page.locator('.work-card').first();
  await expect(card).toBeVisible();
  await expect(card.locator('.pill')).toHaveText(/Confirmed|Canceled|Rescheduled|Closed/);
  await expect(card).not.toContainText('Unassigned');
  await card.click();
  await page.getByRole('button', { name: 'Activity log', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Activity log', exact: true })).toBeVisible();
  await expect(page.locator('.timeline li').first()).toBeVisible();
  await page.unrouteAll({ behavior: 'wait' });
});

test('background refresh never retargets a follow-up draft to another appointment', async ({ page }) => {
  await page.clock.install();
  const firstIssue = { id: 1, appointment_id: 100, reason: 'First open item' };
  const secondIssue = { id: 2, appointment_id: 200, reason: 'Second open item' };
  let issues = [firstIssue, secondIssue];
  await page.route('**/api/work/901', (route) => route.fulfill({
    json: {
      case: { id: 901, state: 'progress', owner_id: 1, version: issues.length },
      clinic: { id: 1, name: 'Austin', timezone: 'America/Chicago' },
      staff: { id: 1, name: 'Front desk' },
      issues,
    },
  }));
  await page.goto('/work/901');
  await page.getByRole('button', { name: 'Record follow-up', exact: true }).click();
  await page.getByLabel('Result').selectOption('attempted');
  await page.getByLabel('Follow-up item').selectOption('1');
  await page.getByLabel('What happened?').fill('Left a voicemail for the first appointment.');
  issues = [secondIssue];
  await page.clock.fastForward(5 * 60 * 1000);
  await expect(page.getByText('Choose an open follow-up item before saving.')).toBeVisible();
  await expect(page.getByLabel('What happened?')).toHaveValue('Left a voicemail for the first appointment.');
  await expect(page.getByRole('button', { name: 'Save follow-up' })).toBeDisabled();
});

test('a background read cannot replace the follow-up while its save is pending', async ({ page }) => {
  await page.clock.install();
  let finishBackgroundRead;
  let acknowledgeSave;
  const backgroundRead = new Promise((resolve) => { finishBackgroundRead = resolve; });
  const pendingSave = new Promise((resolve) => { acknowledgeSave = resolve; });
  let reads = 0;
  const issue = { id: 1, appointment_id: 100, reason: 'Open item' };
  await page.route('**/api/work/901', async (route) => {
    if (route.request().method() === 'POST') {
      await pendingSave;
      return route.fulfill({ json: { message: 'Contact attempt recorded.' } });
    }
    const read = ++reads;
    if (read === 2) await backgroundRead;
    return route.fulfill({
      json: {
        case: { id: 901, state: 'progress', owner_id: 1, version: read },
        clinic: { id: 1, name: 'Austin', timezone: 'America/Chicago' },
        staff: { id: 1, name: 'Front desk' },
        issues: read === 2 ? [] : [issue],
        history: read === 3 ? [{
          id: 1, entry_type: 'event', kind: 'attempted', actor: 'Front desk',
          body: 'Left a voicemail.', created_at: '2026-11-05T16:00:00Z',
        }] : [],
      },
    });
  });
  await page.goto('/work/901');
  await page.getByRole('button', { name: 'Record follow-up', exact: true }).click();
  await page.getByLabel('Result').selectOption('attempted');
  const note = page.getByLabel('What happened?');
  await note.fill('Left a voicemail.');
  const background = page.waitForRequest('**/api/work/901');
  await page.clock.fastForward(5 * 60 * 1000);
  await background;
  const save = page.waitForRequest((request) =>
    request.url().endsWith('/api/work/901') && request.method() === 'POST');
  await page.getByRole('button', { name: 'Save follow-up' }).click();
  expect((await save).postDataJSON()).toEqual({
    outcome: 'attempted', issue: '1', version: 1, note: 'Left a voicemail.',
  });
  finishBackgroundRead();
  await expect(note).toHaveValue('Left a voicemail.');
  await expect(note).not.toBeEditable();
  acknowledgeSave();
  await expect(page.getByRole('status')).toHaveText('Contact attempt recorded.');
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await page.getByRole('button', { name: 'Activity log', exact: true }).click();
  await expect(page.locator('.timeline')).toContainText('Left a voicemail.');
  await page.getByRole('button', { name: /^Follow-up/ }).click();
  await page.getByRole('button', { name: 'Record follow-up', exact: true }).click();
  await expect(note).toHaveValue('');
  await page.unrouteAll({ behavior: 'wait' });
});

test('both patient workspace links show the same history and verify an adult in place', async ({ page }) => {
  let acknowledge;
  const pendingSave = new Promise((resolve) => { acknowledge = resolve; });
  const detail = {
    field: 'email', label: 'Email', pms_value: 'adult@example.test', token: 'adult-email-version',
  };
  const workspace = {
    case: { id: 901, owner_id: 1, state: 'progress' },
    person: { id: 77, name: 'Demo Patient 77' },
    guardian: { id: 88, name: 'Demo Patient 88', details: [detail] },
    clinic: { id: 1, name: 'Austin', timezone: 'America/Chicago' },
    staff: { id: 1, name: 'Front desk' },
    next_appointment: { appointment_id: 700, start_at: '2026-11-12T16:00:00' },
    details: [],
  };
  await page.route('**/api/work/901', (route) => route.fulfill({ json: workspace }));
  await page.route('**/api/patient-details/77', (route) => route.fulfill({ json: workspace }));
  await page.route('**/api/patient-details/77/history?*', (route) => {
    const section = new URL(route.request().url()).searchParams.get('section');
    const rows = {
      appointments: [workspace.next_appointment],
      activity: [{ id: 17, entry_type: 'receipt', actor: 'SMS', kind: 'sent', body: 'Appointment reminder', created_at: '2026-11-05T16:00:00Z', destination: '+15550000000', appointment_ids: [700] }],
    };
    return route.fulfill({ json: { rows: rows[section] || [], next_cursor: null } });
  });
  await page.route('**/api/patient-details/88', async (route) => {
    await pendingSave;
    await route.fulfill({ json: { message: 'Patient detail verified in Appointment Flow.' } });
  });

  await page.goto('/patient-details/77');
  await expect(page.getByRole('heading', { name: 'Demo Patient 77' })).toBeVisible();
  await page.goto('/work/901');
  await expect(page.getByRole('heading', { name: 'Demo Patient 77' })).toBeVisible();

  await expect(page.getByRole('complementary', { name: 'Patient details' })).toBeVisible();
  await page.getByRole('button', { name: 'Edit email and view history' }).click();
  const field = page.getByLabel('Verified email', { exact: true });
  await field.fill('updated@example.test');
  const save = page.waitForRequest((request) => request.url().endsWith('/api/patient-details/88') && request.method() === 'POST');
  await page.getByRole('button', { name: 'Verify and save email' }).click();
  expect((await save).postDataJSON()).toEqual({
    field: 'email', verified_value: 'updated@example.test', token: 'adult-email-version', originating_patient_id: 77,
  });
  await expect(field).not.toBeEditable();
  acknowledge();
  await expect(page.getByRole('dialog')).not.toBeVisible();

  await page.getByRole('button', { name: 'Appointments', exact: true }).click();
  await page.getByRole('button', { name: /#700/ }).first().click();
  await expect(page.getByRole('heading', { name: 'Appointments', exact: true })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Linked messages and activity' })).toBeVisible();
  const appointments = page.getByRole('region', { name: 'Patient appointments' });
  await appointments.getByText('sent', { exact: true }).click();
  await expect(appointments.getByText('+15550000000', { exact: true })).toBeVisible();
});
