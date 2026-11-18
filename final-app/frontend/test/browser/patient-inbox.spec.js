const { test, expect } = require('@playwright/test');

async function stubSpanishEmail(page) {
  await page.route('**/api/patient?clinic=1&patient=103&include_patients=0', async (route) => {
    const response = await route.fetch();
    const data = await response.json();
    data.messages = [{
      token: 'spanish-email',
      clinic_id: 1,
      patient_id: 103,
      channel: 'Email',
      body: 'Responda SÍ para confirmar.',
      created_at: '2026-11-05T16:00:00Z',
    }];
    data.replies = [];
    await route.fulfill({ response, json: data });
  });
}

test('patient inbox keeps clinic selection, numeric patient order, and free-text replies', async ({ page }) => {
  await stubSpanishEmail(page);
  await page.goto('/');
  await page.getByRole('button', { name: 'Open patient workspace' }).click();
  await expect(page.getByRole('heading', { name: 'Patient inbox' })).toBeVisible();
  await page.getByLabel('Clinic', { exact: true }).selectOption('1');
  const patients = page.getByLabel('Patient', { exact: true });
  await expect(patients.locator('option[value="103"]')).toHaveCount(1);
  const ids = await patients.locator('option').evaluateAll((options) =>
    options.map((option) => Number(option.value)).filter(Boolean),
  );
  expect(ids).toEqual([...ids].sort((a, b) => a - b));
  await patients.selectOption('103');
  await page.getByRole('button', { name: 'Email', exact: true }).click();
  await expect(page.locator('.message-history')).toContainText('Responda SÍ');
  await page.getByLabel('Your reply').fill('Sí, pero llámame mañana.');
  await expect(page.getByLabel('Your reply')).toHaveValue('Sí, pero llámame mañana.');
  await expect(page.getByRole('button', { name: 'Send reply', exact: true })).toBeEnabled();
  // Do not submit: backend tests cover classification without modifying the reviewer's demo.
  await page.unrouteAll({ behavior: 'wait' });
});

test('changing patient clears the selected conversation and reply draft', async ({ page }) => {
  await stubSpanishEmail(page);
  await page.goto('/');
  await page.getByRole('button', { name: 'Open patient workspace' }).click();
  await expect(page.getByRole('heading', { name: 'Patient inbox' })).toBeVisible();
  await page.getByLabel('Clinic', { exact: true }).selectOption('1');
  const patients = page.getByLabel('Patient', { exact: true });
  await patients.selectOption('103');
  await page.getByRole('button', { name: 'Email', exact: true }).click();
  await page.getByLabel('Your reply').fill('A draft for this patient only');
  await patients.selectOption('');
  await expect(page.getByLabel('Your reply')).toHaveCount(0);
  await expect(page.locator('.message-history')).toHaveCount(0);
  await patients.selectOption('103');
  await expect(page.getByLabel('Your reply')).toHaveValue('');
  await expect(page.locator('.message-history')).toContainText('Responda SÍ');
  await page.unrouteAll({ behavior: 'wait' });
});

async function openSpanishInbox(page) {
  let inboxReads = 0;
  await page.route('**/api/patient?*', (route) => {
    const params = new URL(route.request().url()).searchParams;
    const patient = params.get('patient');
    return route.fulfill({
      json: {
        clinics: [{ id: 1, name: 'Austin' }],
        ...(params.get('include_patients') === '0' ? {} : {
          patients: [{ id: 103, clinic_id: 1, name: 'Patient 103' }],
        }),
        messages: patient === '103' ? [
          {
            token: 'spanish-email', clinic_id: 1, patient_id: 103, channel: 'Email',
            body: 'Responda SÍ para confirmar.', created_at: '2026-11-05T16:00:00Z',
          },
          {
            token: 'text-message', clinic_id: 1, patient_id: 103, channel: 'SMS',
            body: 'Reply YES to confirm.', created_at: '2026-11-05T16:00:00Z',
          },
        ] : [],
        replies: [],
        key: 'reply-fixture-' + ++inboxReads,
      },
    });
  });
  await page.goto('/patient');
  await page.getByLabel('Clinic', { exact: true }).selectOption('1');
  await page.getByLabel('Patient', { exact: true }).selectOption('103');
  await page.getByRole('button', { name: 'Email', exact: true }).click();
  await expect(page.getByLabel('Your reply')).toBeVisible();
}

test('a rejected reply retains the draft and identifies the form feedback', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await openSpanishInbox(page);
  await page.locator('body').evaluate((body) => { body.style.zoom = '125%'; });
  await page.route('**/api/patient/messages/spanish-email', (route) => route.fulfill({
    status: 409,
    json: { error: 'This message is no longer available.' },
  }));
  const reply = page.getByLabel('Your reply');
  await reply.fill('Please call me.');
  await reply.press('Tab');
  const send = page.getByRole('button', { name: 'Send reply' });
  await expect(send).toBeFocused();
  await expect(send).toBeInViewport();
  await send.press('Enter');
  const alert = page.getByRole('alert');
  await expect(alert).toHaveText('Action rejected. This message is no longer available.');
  await expect(alert).toBeFocused();
  await expect(alert).toBeInViewport();
  await alert.press('Tab');
  await expect(page.getByRole('button', { name: 'Reload details' })).toBeFocused();
  await expect(reply).toHaveValue('Please call me.');
  await expect(page.locator('form.patient-reply')).toHaveAccessibleDescription(
    'Action rejected. This message is no longer available.',
  );
});

test('an unacknowledged reply prompts a read before another submission', async ({ page }) => {
  await openSpanishInbox(page);
  const attempts = [];
  await page.route('**/api/patient/messages/spanish-email', (route) => {
    attempts.push(route.request().postDataJSON());
    if (attempts.length === 1) return route.abort();

    return route.fulfill({ json: { message: 'Reply recorded.' } });
  });
  const reply = page.getByLabel('Your reply');
  await reply.fill('Can I move my appointment?');
  const send = page.getByRole('button', { name: 'Send reply' });
  await send.click();
  await expect(page.getByRole('alert')).toContainText('The action may have been saved.');
  await expect(reply).toHaveValue('Can I move my appointment?');
  await expect(send).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Text messages' })).toBeDisabled();
  await page.getByRole('button', { name: 'Reload details' }).click();
  await expect(page.getByRole('status')).toContainText('Check whether the action appears');
  await expect(reply).toHaveValue('Can I move my appointment?');
  await expect(send).toBeEnabled();
  await expect(reply).not.toBeEditable();
  await expect(page.getByLabel('Patient', { exact: true })).toBeDisabled();
  await expect(page.getByLabel('Clinic', { exact: true })).toBeDisabled();
  expect(attempts).toHaveLength(1);

  await send.click();
  await expect(page.getByRole('status')).toHaveText('Reply recorded.');
  expect(attempts).toEqual([attempts[0], attempts[0]]);
  await expect(page.getByLabel('Patient', { exact: true })).toBeEnabled();
});

test('a saved reply stays saved when its refresh fails', async ({ page }) => {
  await openSpanishInbox(page);
  let attempts = 0;
  await page.route('**/api/patient/messages/spanish-email', async (route) => {
    attempts += 1;
    await page.route('**/api/patient?clinic=1&patient=103&include_patients=0', (read) =>
      read.fulfill({ status: 503, json: { error: 'Inbox unavailable.' } }), { times: 1 });
    await route.fulfill({ json: { message: 'Reply recorded.' } });
  });
  const reply = page.getByLabel('Your reply');
  await reply.fill('Yes');
  const send = page.getByRole('button', { name: 'Send reply' });
  await send.click();
  await expect(page.getByRole('alert')).toHaveText('Action saved, but the updated details could not be loaded.');
  await expect(reply).toHaveValue('');
  await expect(send).toBeDisabled();
  await page.getByRole('button', { name: 'Reload details' }).click();
  await expect(page.getByRole('status')).toHaveText('Reply recorded.');
  await expect(send).toBeEnabled();
  expect(attempts).toBe(1);
});

test('changing channels after a save cannot reuse the previous inbox request key', async ({ page }) => {
  await openSpanishInbox(page);
  let finishReload;
  const reload = new Promise((resolve) => { finishReload = resolve; });
  const submittedKeys = [];
  await page.route('**/api/patient/messages/spanish-email', async (route) => {
    submittedKeys.push(route.request().postDataJSON().key);
    await page.route('**/api/patient?clinic=1&patient=103&include_patients=0', async (read) => {
      await reload;
      await read.fallback();
    }, { times: 1 });
    await route.fulfill({ json: { message: 'Reply recorded.' } });
  });
  await page.getByLabel('Your reply').fill('Yes');
  const send = page.getByRole('button', { name: 'Send reply' });
  await send.click();
  await expect(page.getByRole('status')).toHaveText('Reply recorded.');
  await page.getByRole('button', { name: 'Text messages' }).click();
  await expect(page.locator('.message-history')).toContainText('Reply YES to confirm.');
  await expect(send).toBeDisabled();
  finishReload();
  await expect(send).toBeEnabled();
  await page.route('**/api/patient/messages/text-message', (route) => {
    submittedKeys.push(route.request().postDataJSON().key);
    return route.fulfill({ json: { message: 'Text reply recorded.' } });
  });
  await page.getByLabel('Your reply').fill('Please call me.');
  await send.click();
  await expect(page.getByRole('status')).toHaveText('Text reply recorded.');
  expect(submittedKeys).toHaveLength(2);
  expect(submittedKeys[1]).not.toBe(submittedKeys[0]);
});

test('the inbox ignores a slow response after the patient selection changes', async ({ page }) => {
  let finishFirst;
  const releaseFirst = new Promise((resolve) => { finishFirst = resolve; });
  const clinics = [{ id: 1, name: 'Austin' }];
  const patients = [103, 104].map((id) => ({ id, clinic_id: 1, name: 'Patient ' + id }));
  await page.route('**/api/patient?*', async (route) => {
    const patient = new URL(route.request().url()).searchParams.get('patient');
    if (patient === '103') await releaseFirst;
    const messages = patient ? [{
      token: patient,
      patient_id: Number(patient),
      clinic_id: 1,
      channel: 'SMS',
      body: 'Reminder for ' + patient,
      created_at: '2026-11-05T16:00:00Z',
    }] : [];
    await route.fulfill({ json: { clinics, patients, messages, replies: [], key: 'fixture' } });
  });
  await page.goto('/patient');
  await page.getByLabel('Clinic', { exact: true }).selectOption('1');
  const selectPatient = page.getByLabel('Patient', { exact: true });
  const first = page.waitForRequest('**/api/patient?clinic=1&patient=103&include_patients=0');
  await selectPatient.selectOption('103');
  await first;
  await expect(page.getByText('Loading messages…')).toBeVisible();
  await selectPatient.selectOption('104');
  await expect(page.locator('.message-history')).toContainText('Reminder for 104');
  await page.getByLabel('Your reply').fill('Draft for 104');
  finishFirst();
  await page.unrouteAll({ behavior: 'wait' });
  await expect(page.locator('.message-history')).not.toContainText('Reminder for 103');
  await expect(page.getByLabel('Your reply')).toHaveValue('Draft for 104');
});
