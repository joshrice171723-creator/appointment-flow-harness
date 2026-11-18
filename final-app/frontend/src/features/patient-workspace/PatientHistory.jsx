import React, { Fragment, useEffect, useRef, useState } from 'react';
import { confirmationLabel, formatInstant, formatWallTime } from '../../shared/format';
import { loadJson } from '../../shared/requests';

const activityFilters = { all: 'All activity', messages: 'Messages', replies: 'Replies', staff: 'Staff actions', verifications: 'Verifications' };
const appointmentFilters = { all: 'All appointments', upcoming: 'Upcoming', past: 'Past' };

export function HistoryResults({ personId, section, filter = 'all', appointmentId, messageId, refreshKey, initialRows, children }) {
  const params = new URLSearchParams({ section, filter });
  if (appointmentId) params.set('appointment_id', appointmentId);
  if (messageId) params.set('message_id', messageId);
  const url = personId ? '/patient-details/' + personId + '/history?' + params : null;
  const [result, setResult] = useState(null);
  const [retry, setRetry] = useState(0);
  const active = useRef(null);

  async function load(request, signal, cursor) {
    try {
      const payload = await loadJson(request + (cursor ? '&cursor=' + encodeURIComponent(cursor) : ''), signal);
      if (signal.aborted) return;
      setResult((current) => ({
        url: request,
        rows: cursor ? [...current.rows, ...payload.rows] : payload.rows,
        next: payload.next_cursor,
      }));
    } catch (error) {
      if (signal.aborted) return;
      setResult((current) => ({
        url: request,
        rows: cursor ? current.rows : [],
        next: cursor || null,
        error: error.message,
      }));
    }
  }

  useEffect(() => {
    if (!url) return;
    const controller = new AbortController();
    active.current = controller;
    setResult((current) => current?.url === url ? { ...current, loading: true } : null);
    load(url, controller.signal);
    return () => active.current?.abort();
  }, [url, refreshKey, retry]);

  if (!url) return children(initialRows || []);

  const current = result?.url === url ? result : null;

  function loadMore() {
    const controller = new AbortController();
    active.current?.abort();
    active.current = controller;
    setResult({ ...current, loading: true, error: null });
    load(url, controller.signal, current.next);
  }

  return (
    <>
      {current && children(current.rows)}
      {(!current || current.loading) && <p role="status">Loading records…</p>}
      {current?.error && (
        <div className="notice">
          <p role="alert">{current.error}</p>
          <button type="button" onClick={current.next ? loadMore : () => setRetry((value) => value + 1)}>Retry</button>
        </div>
      )}
      {current?.next && !current.error && (
        <button type="button" onClick={loadMore} disabled={current.loading}>Load more</button>
      )}
    </>
  );
}

export function HistoryFilters({ title, id, options, value, change }) {
  return (
    <label htmlFor={id}>
      {title}
      <select id={id} value={value} onChange={(event) => change(event.target.value)}>
        {Object.entries(options).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
      </select>
    </label>
  );
}

export function ActivityList({ rows, timezone, showAppointment, showMessage, messageId, legacy = false }) {
  return (
    <ol className="timeline workspace-activity-list">
      {rows.map((entry) => {
        const kind = entry.kind === 'attempted' ? 'Contact attempt' : entry.kind.replaceAll('_', ' ');
        const receipt = entry.entry_type === 'receipt';
        return (
          <li key={entry.entry_type + '-' + entry.id} data-kind={entry.kind}>
            <details open={(legacy || (receipt && entry.id === messageId)) || undefined}>
              <summary>
                <span className="activity-event">
                  <span className="activity-caption"><strong>{kind}</strong><span>{entry.actor || 'Appointment Flow'}</span></span>
                  <span className="activity-body">{entry.body || 'Unavailable in recorded history'}{entry.entry_type === 'verification' && entry.verified_value ? ' · ' + entry.verified_value : ''}</span>
                </span>
                <time dateTime={entry.created_at}>{formatInstant(entry.created_at, timezone)}</time>
              </summary>
              <div className="activity-expanded">
              <dl className="patient-workspace-evidence">
                <dt>Recorded by</dt><dd>{entry.actor || 'Appointment Flow'}</dd>
                <dt>Recorded at</dt><dd>{formatInstant(entry.created_at, timezone)} · {timezone}</dd>
              {(receipt || entry.message_id) && (
                <>
                  <dt>Message</dt>
                  <dd>{!receipt && showMessage ? (
                    <button type="button" onClick={() => showMessage(entry.message_id)}>Open message #{entry.message_id}</button>
                  ) : '#' + (receipt ? entry.id : entry.message_id)}</dd>
                  <dt>Channel</dt><dd>{entry.channel || 'Unavailable in recorded history'}</dd>
                  <dt>Destination used</dt><dd>{entry.destination || 'Unavailable in recorded history'}</dd>
                  <dt>Recipient recorded</dt>
                  <dd>{entry.recipient_name || (entry.recipient_id ? '#' + entry.recipient_id : 'Unavailable in recorded history')}</dd>
                  {entry.purposes && <><dt>Purpose</dt><dd>{entry.purposes}</dd></>}
                </>
              )}
              {entry.entry_type === 'verification' && (
                <>
                  <dt>PMS value at verification</dt><dd>{entry.pms_value || 'No value on file'}</dd>
                  <dt>Verified value</dt><dd>{entry.verified_value || 'Unavailable in recorded history'}</dd>
                  {entry.retired_at && <><dt>Superseded</dt><dd>{formatInstant(entry.retired_at, timezone)}</dd></>}
                </>
              )}
              </dl>
              {entry.kind === 'ambiguous_reply' && <p>Reply could not be matched to one appointment.</p>}
              <div className="activity-links">
              {entry.issue_id && <small>Follow-up item #{entry.issue_id}</small>}
              {showAppointment && entry.appointment_ids?.map((id) => (
                <button key={id} type="button" onClick={() => showAppointment(id)}>Appointment #{id}</button>
              ))}
              </div>
              </div>
            </details>
          </li>
        );
      })}
      {!rows.length && <li>No activity available.</li>}
    </ol>
  );
}

export function PatientActivity({ personId, refreshKey, history, timezone, showAppointment, messageId, showMessage, clearMessage }) {
  const [filter, setFilter] = useState('all');
  return (
    <section className="panel workspace-activity">
      <div className="section-heading">
      <div>
      <h2 id="activity" tabIndex={-1}>Activity log</h2>
      <p className="hint">Messages, replies, staff actions, and verifications.</p>
      </div>
      {messageId ? <button type="button" onClick={clearMessage}>Show all activity</button> : (
        personId && <HistoryFilters title="Show" id="patient-activity-filter" options={activityFilters} value={filter} change={setFilter} />
      )}
      </div>
      <HistoryResults personId={personId} section="activity" filter={messageId ? 'all' : filter} messageId={messageId} refreshKey={refreshKey} initialRows={history}>
        {(rows) => <ActivityList rows={rows} timezone={timezone} showAppointment={showAppointment} showMessage={showMessage} messageId={messageId} legacy={!personId} />}
      </HistoryResults>
    </section>
  );
}

function AppointmentEvidence({ appointment, personId, timezone, refreshKey, showMessage }) {
  return (
    <>
      <h4>Recorded appointment revisions</h4>
      <ul>
        {(appointment.revisions || []).map((revision) => (
          <li key={revision.id}>
            {formatWallTime(revision.start_at)} · {revision.current ? 'Current revision' : 'Earlier revision'}
            {revision.confirmed_at && ' · Confirmed ' + formatInstant(revision.confirmed_at, timezone)}
            {revision.confirmed_by && ' by ' + revision.confirmed_by}
          </li>
        ))}
        {!appointment.revisions?.length && <li>No tracked visit revisions.</li>}
      </ul>
      <h4>Linked follow-up</h4>
      <HistoryResults personId={personId} section="follow_up" appointmentId={appointment.appointment_id} refreshKey={refreshKey}>
        {(rows) => rows.length ? (
          <ul>{rows.map((row) => <li key={row.id}>{row.reason} · {row.resolved_at ? 'Resolved' : 'Open'}</li>)}</ul>
        ) : <p>No linked follow-up.</p>}
      </HistoryResults>
      <h4>Linked messages and activity</h4>
      <HistoryResults personId={personId} section="activity" appointmentId={appointment.appointment_id} refreshKey={refreshKey}>
        {(rows) => <ActivityList rows={rows} timezone={timezone} showMessage={showMessage} />}
      </HistoryResults>
    </>
  );
}

export function PatientAppointments({ personId, timezone, appointments, selectedId, selectAppointment, refreshKey, showMessage }) {
  const [filter, setFilter] = useState('all');
  const [expanded, setExpanded] = useState(null);
  const shown = selectedId ?? expanded;
  return (
    <section className="panel">
      <h2 id="appointments" tabIndex={-1}>Appointments</h2>
      <p className="hint">Times shown in {timezone}. Booking status comes from the PMS.</p>
      {selectedId ? <button type="button" onClick={() => { setExpanded(null); selectAppointment(null); }}>Show all appointments</button> : (
        <HistoryFilters title="Show" id="patient-appointment-filter" options={appointmentFilters} value={filter} change={setFilter} />
      )}
      <HistoryResults personId={personId} section="appointments" filter={selectedId ? 'all' : filter} appointmentId={selectedId} refreshKey={refreshKey} initialRows={appointments}>
        {(rows) => rows.length ? (
          <div className="table-wrap" role="region" aria-label="Patient appointments" tabIndex={0}>
            <table>
              <thead><tr><th scope="col">Appointment</th><th scope="col">Provider</th><th scope="col">PMS status</th><th scope="col">Confirmation or reply</th><th scope="col">Follow-up</th></tr></thead>
              <tbody>
                {rows.map((appointment) => {
                  const id = appointment.appointment_id;
                  return (
                    <Fragment key={id}>
                      <tr>
                        <th scope="row">
                          <button type="button" aria-expanded={shown === id} onClick={() => {
                            if (selectedId) selectAppointment(null);
                            setExpanded(shown === id ? null : id);
                          }}>#{id} · {formatWallTime(appointment.start_at)}</button>
                        </th>
                        <td>{appointment.provider_name || 'Unavailable'}</td>
                        <td>{appointment.status || 'Unavailable'}</td>
                        <td>{confirmationLabel(appointment, 'No confirmation recorded')}</td>
                        <td>{appointment.hold || (appointment.follow_up ? 'Open follow-up' : '—')}</td>
                      </tr>
                      {shown === id && <tr><td colSpan={5}><AppointmentEvidence appointment={appointment} personId={personId} timezone={timezone} refreshKey={refreshKey} showMessage={showMessage} /></td></tr>}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : <p>No appointments found.</p>}
      </HistoryResults>
    </section>
  );
}
