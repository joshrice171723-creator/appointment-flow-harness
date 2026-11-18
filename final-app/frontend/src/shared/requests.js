const READ_NETWORK_ERROR = 'Could not reach Appointment Flow. Check that the app is running, then refresh.';
const INVALID_READ = 'Appointment Flow returned an invalid response. Refresh to try again.';
const UNCERTAIN_WRITE = 'The action may have been saved. Reload the details and check before trying again.';

const pagePayloadMatches = {
  '/workspaces': ({ clinics, staff }) => Array.isArray(clinics) && Array.isArray(staff),
  '/board': ({ clinic, staff, cases }) => Boolean(clinic && staff) && Array.isArray(cases),
  '/appointments': ({ clinic, date, week, today, visits }) =>
    Boolean(clinic && date && week && today) && Array.isArray(visits),
  '/work/:id': ({ case: followUp, clinic, staff }) => Boolean(followUp && clinic && staff),
  '/patient-details/:id': ({ person, clinic, details }) =>
    Boolean(person?.id && typeof person.name === 'string' && clinic) && Array.isArray(details),
  '/patient-details/:id/history': ({ rows, next_cursor }) =>
    Array.isArray(rows) && (next_cursor === null || typeof next_cursor === 'string'),
  '/operations': ({ rows, clinics }) => Array.isArray(rows) && Array.isArray(clinics),
  '/patient': ({ clinics, patients, messages, replies, key }, path) =>
    [clinics, messages, replies].every(Array.isArray) &&
    (Array.isArray(patients) || (patients === undefined && new URLSearchParams(path.split('?')[1]).get('include_patients') === '0')) &&
    typeof key === 'string' && key.length > 0,
};

export class RequestError extends Error {
  constructor(message, { rejected = false } = {}) {
    super(message);
    this.rejected = rejected;
  }
}

async function fetchResponse(path, options, networkError) {
  try {
    return await fetch('/api' + path, options);
  } catch (error) {
    if (!(error instanceof TypeError)) throw error;
    throw new RequestError(networkError);
  }
}

async function readPayload(response) {
  try {
    const payload = await response.json();
    return payload && typeof payload === 'object' && !Array.isArray(payload) ? payload : null;
  } catch (error) {
    if (error instanceof SyntaxError || error instanceof TypeError) return null;
    throw error;
  }
}

export async function loadJson(path, signal) {
  const response = await fetchResponse(path, { headers: { Accept: 'application/json' }, signal }, READ_NETWORK_ERROR);
  const payload = await readPayload(response);
  if (!response.ok) {
    throw new RequestError(
      payload?.error || `Appointment Flow could not load these details (HTTP ${response.status}).`,
    );
  }
  const endpoint = path.split("?")[0]
    .replace(/^\/(work|patient-details)\/\d+(?=\/|$)/, "/$1/:id");
  if (!payload || !pagePayloadMatches[endpoint]?.(payload, path)) {
    throw new RequestError(INVALID_READ);
  }
  return payload;
}

export async function postJson(path, fields) {
  const response = await fetchResponse(path, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content,
    },
    body: JSON.stringify(fields),
  }, UNCERTAIN_WRITE);
  const payload = await readPayload(response);

  // These Rails responses explicitly reject the action.
  if ((response.status === 409 || response.status === 422) && typeof payload?.error === 'string') {
    throw new RequestError(payload.error, { rejected: true });
  }
  const resultField = path === '/enter' ? 'path' : 'message';
  if (!response.ok || typeof payload?.[resultField] !== 'string' || !payload[resultField]) {
    throw new RequestError(UNCERTAIN_WRITE);
  }
  return payload;
}
