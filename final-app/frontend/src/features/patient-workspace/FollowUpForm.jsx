import React, { useState } from 'react';
import { formatWallTime } from '../../shared/format';
import { MAX_FOLLOW_UP_NOTE_LENGTH } from '../../shared/constants';

export function FollowUpForm({ issues, canSave, saving, feedbackId, save }) {
  const [outcome, setOutcome] = useState('');
  const [chosenIssueId, setIssueId] = useState(null);
  const issueId = chosenIssueId ?? (issues[0] ? String(issues[0].id) : '');
  const [note, setNote] = useState('');
  const [appointments, setAppointments] = useState([]);
  const selectedIssue = issues.find((issue) => String(issue.id) === issueId);
  const reviewingReply = Boolean(selectedIssue?.reply);
  const issueStillOpen = issues.some((issue) => String(issue.id) === issueId);
  const recordsScheduleChange = outcome === 'rescheduled' || outcome === 'canceled';

  if (!issues.length && !note && !outcome) return null;

  function saveFollowUp(event) {
    event.preventDefault();
    if (!issueStillOpen) return;
    save({ outcome, issue: issueId, note, ...(reviewingReply ? { appointment_ids: appointments } : {}) }, () => {
      setIssueId(null);
      setNote('');
      setOutcome('');
      setAppointments([]);
    });
  }

  return (
    <form onSubmit={saveFollowUp} aria-describedby={feedbackId}>
      <label htmlFor="follow-up-issue">Follow-up item</label>
      <select
        id="follow-up-issue"
        value={issueId}
        disabled={saving}
        onChange={(event) => { setIssueId(event.target.value); setOutcome(''); setAppointments([]); }}
      >
        {!issueStillOpen && <option value={issueId} disabled>Previously selected item is no longer open</option>}
        {issues.map((issue) => (
          <option key={issue.id} value={issue.id}>
            {issue.reply ? 'Reply: "' + issue.reply.body + '" · ' : ''}{issue.appointment_id ? '#' + issue.appointment_id + ' · ' : ''}{issue.reason}
          </option>
        ))}
      </select>
      {!issueStillOpen && <p className="notice" role="status">Choose an open follow-up item before saving.</p>}
      <label htmlFor="follow-up-result">Result</label>
      <select
        id="follow-up-result"
        required
        disabled={saving}
        value={outcome}
        onChange={(event) => {
          setIssueId(issueId);
          setOutcome(event.target.value);
        }}
      >
        <option disabled value="">Choose a result</option>
        {reviewingReply ? <>
          <option value="clarified">Applies to selected appointments</option>
          <option value="unclear">Still unclear (keep open)</option>
        </> : <>
        <option value="attempted">Contact attempted (keep open)</option>
        <option value="confirmed">Confirmed</option>
        <option value="rescheduled">Rescheduled</option>
        <option value="canceled">Canceled</option>
        </>}
      </select>
      {reviewingReply && <>
        <blockquote className="reply-review-text">{selectedIssue.reply.body}</blockquote>
        {outcome === 'clarified' && <fieldset>
          <legend>Which appointments does this reply concern?</legend>
          <p className="hint">Choose one or select both when the patient has clarified both.</p>
          {selectedIssue.candidate_appointments.map((appointment) => (
            <label className="reply-appointment-choice" key={appointment.id}>
              <input type="checkbox" disabled={saving} checked={appointments.includes(appointment.appointment_id)} onChange={(event) => {
                setIssueId(issueId);
                setAppointments(event.target.checked ? [...appointments, appointment.appointment_id] : appointments.filter((id) => id !== appointment.appointment_id));
              }} />
              Appointment #{appointment.appointment_id} · {formatWallTime(appointment.start_at)}
            </label>
          ))}
          <p className="hint">Clarification records which appointments the reply concerns. Record their outcomes separately.</p>
        </fieldset>}
      </>}
      {recordsScheduleChange && (
        <p className="hint">
          This stops reminders for this appointment.
        </p>
      )}
      <label htmlFor="follow-up-note">What happened?</label>
      <textarea
        id="follow-up-note"
        required
        readOnly={saving}
        minLength={3}
        maxLength={MAX_FOLLOW_UP_NOTE_LENGTH}
        value={note}
        onChange={(event) => {
          setIssueId(issueId);
          setNote(event.target.value);
        }}
      />
      <button className="primary wide" disabled={!canSave || !issueStillOpen || (reviewingReply && outcome === 'clarified' && !appointments.length)}>
        {saving ? 'Saving follow-up…' : 'Save follow-up'}
      </button>
    </form>
  );
}
