function formatDate(date, zone) {
  try {
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      timeZone: zone,
    }).format(date);
  } catch (error) {
    if (!(error instanceof RangeError)) throw error;
    return 'Unavailable';
  }
}

export function confirmationLabel(visit, emptyLabel) {
  if (visit.reply) {
    return visit.declined_reply ? 'Replied NO · Follow-up needed' : 'Reply needs review';
  }
  if (visit.confirmed_at) return 'Confirmed';
  if (visit.declined_reply) return 'Replied NO';
  if (visit.patient_reply) return 'Reply recorded';
  return emptyLabel;
}

export function formatWallTime(value) {
  return value ? formatDate(new Date(value.slice(0, 19) + 'Z'), 'UTC') : '—';
}

export function formatInstant(value, zone = 'UTC') {
  return value ? formatDate(new Date(value), zone) : '—';
}

export function moveDate(day, offset) {
  const date = new Date(day + 'T00:00:00Z');
  date.setUTCDate(date.getUTCDate() + offset);
  return date.toISOString().slice(0, 10);
}

export function calendarLabel(day) {
  return new Intl.DateTimeFormat('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(day + 'T00:00:00Z'));
}

export function monthName(month, short = false) {
  return new Intl.DateTimeFormat('en-US', {
    month: short ? 'short' : 'long',
    year: short ? undefined : 'numeric',
    timeZone: 'UTC',
  }).format(new Date(month + '-01T00:00:00Z'));
}

export function percentage(count, total) {
  return total ? ((100 * count) / total).toFixed(1) + '%' : '—';
}
