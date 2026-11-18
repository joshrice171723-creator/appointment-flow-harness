import React, { useRef, useState } from 'react';
import { flushSync } from 'react-dom';
import { path, states } from '../../shared/constants';
import { formatInstant, formatWallTime } from '../../shared/format';
import { Frame, IssuePill, ResolutionSummary } from '../../shared/ui';
import { usePage } from '../../shared/usePage';
import { FollowUpForm } from './FollowUpForm';
import { PatientDetails } from './PatientDetails';
import { HistoryResults, PatientActivity, PatientAppointments } from './PatientHistory';

function FollowUpItem({ item, showAppointment, timezone }) {
  return (
    <div className="issue">
      <div>
        {!item.resolved_at && <IssuePill code={item.code} appointmentAt={item.start_at_utc} />}
        <p><strong>{item.reason}</strong></p>
        {item.reply && <>
          <blockquote className="reply-review-text">{item.reply.body}</blockquote>
          <small>Received {formatInstant(item.reply.created_at, timezone)}</small>
          <p>Possible appointments</p>
          <ul>{item.candidate_appointments.map((appointment) => (
            <li key={appointment.id}>#{appointment.appointment_id} · {formatWallTime(appointment.start_at)}</li>
          ))}</ul>
        </>}
        {item.appointment_id && (
          showAppointment ? (
            <button type="button" onClick={() => showAppointment(item.appointment_id)}>Appointment #{item.appointment_id}</button>
          ) : <small>Appointment #{item.appointment_id}</small>
        )}
        {item.start_at && <small>{formatWallTime(item.start_at)} · {timezone}</small>}
        {item.resolved_at && (
          <details>
            <summary>Resolved · {formatInstant(item.resolved_at, timezone)}</summary>
            {item.resolution ? (
              <p>{item.resolution.actor} · {formatInstant(item.resolution.created_at, timezone)} · {item.resolution.body}</p>
            ) : <p>Resolution details unavailable in recorded history.</p>}
          </details>
        )}
      </div>
    </div>
  );
}

function FollowUp({ followUp, issues, staff, personId, page, submit, timezone, showAppointment }) {
  const [showHistory, setShowHistory] = useState(false);
  const editor = useRef(null);
  const active = followUp && followUp.state !== 'resolved';
  const assigned = staff?.id && followUp?.owner_id === staff.id;
  const openIssues = issues.filter((item) => !item.resolved_at);
  const target = followUp ? '/work/' + followUp.id : null;

  function saveFollowUp(fields, clearDraft) {
    submit(target, { ...fields, version: followUp.version }, () => {
      clearDraft();
      editor.current?.close();
    });
  }

  return (
    <section className="panel workspace-follow-up">
      <div className="section-heading">
        <h2 id="follow-up" tabIndex={-1}>{followUp?.state === 'resolved' ? 'Follow-up history' : 'Follow-up items'}</h2>
        {active && assigned && openIssues.length > 0 && (
          <button className="primary" onClick={() => editor.current.showModal()}>Record follow-up</button>
        )}
      </div>
      {!followUp && <p>No follow-up recorded.</p>}
      {active && !assigned && <p>Assign this work to yourself to record appointment follow-up.</p>}
      <div className="workspace-issues">
      {followUp && !openIssues.length && <p>No open follow-up items.</p>}
      {openIssues.map((item) => <FollowUpItem key={item.id} item={item} showAppointment={showAppointment} timezone={timezone} />)}
      </div>
      <dialog ref={editor} className="workspace-record" aria-labelledby="record-follow-up-title">
      <div className="section-heading">
        <h2 id="record-follow-up-title">Record follow-up</h2>
        <button type="button" onClick={() => editor.current.close()}>Close</button>
      </div>
      <p className="hint">Record the result for an appointment. Patient corrections are under Patient details.</p>
      {(page.feedbackId || page.readError) && (
        <div className="notice" id="follow-up-feedback">
          <p role="alert">{page.submission.message || page.readError || 'Review the latest details before saving again.'}</p>
          <button type="button" onClick={page.reviewLatest} disabled={page.loading || page.busy}>Reload details</button>
        </div>
      )}
      {followUp && (
        <FollowUpForm
          key={followUp.id}
          issues={active && assigned ? openIssues : []}
          canSave={page.canSubmit && active && assigned}
          saving={page.busy}
          feedbackId={page.feedbackId || page.readError ? 'follow-up-feedback' : undefined}
          save={saveFollowUp}
        />
      )}
      </dialog>
      {followUp && (personId || issues.some((item) => item.resolved_at)) && (
        <details className="patient-workspace-history" onToggle={(event) => setShowHistory(event.currentTarget.open)}>
          <summary>Resolved follow-up records</summary>
          {showHistory && <FollowUpHistory personId={personId} page={page} issues={issues} showAppointment={showAppointment} timezone={timezone} />}
        </details>
      )}
    </section>
  );
}

function FollowUpHistory({ personId, page, issues, showAppointment, timezone }) {
  return (
    <HistoryResults personId={personId} section="follow_up" filter="resolved" refreshKey={page.data} initialRows={issues.filter((item) => item.resolved_at)}>
      {(rows) => rows.length ? rows.map((item) => (
        <FollowUpItem key={item.id} item={item} showAppointment={showAppointment} timezone={timezone} />
      )) : <p>No follow-up records.</p>}
    </HistoryResults>
  );
}

export default function PatientWorkspace() {
  const page = usePage(path, { autoRefresh: true });
  const [section, setSection] = useState('follow-up');
  const [selectedAppointment, selectAppointment] = useState(null);
  const [selectedMessage, selectMessage] = useState(null);
  const caseEntry = path.startsWith('/work/');
  const {
    case: followUp, person, clinic, staff, guardian, guardian_review_required: guardianReviewRequired,
    details = [], visits = [], issues = [], history = [], hold, next_appointment: nextAppointment,
  } = page.data || {};
  const personId = person?.id;

  function showAppointment(id) {
    flushSync(() => {
      setSection('appointments');
      selectAppointment(id);
    });
    const heading = document.getElementById('appointments');
    heading?.focus();
    heading?.scrollIntoView({ block: 'start' });
  }

  function showMessage(id) {
    flushSync(() => {
      setSection('activity');
      selectMessage(id);
    });
    const heading = document.getElementById('activity');
    heading?.focus();
    heading?.scrollIntoView({ block: 'start' });
  }

  function showDetails() {
    const field = document.querySelector('.patient-detail-field[data-conflict]');
    const target = field?.querySelector('button') || document.getElementById('patient-details');
    if (field) target?.click();
    else target?.focus();
  }

  const appointmentLink = personId ? showAppointment : undefined;
  const verification = personId && (
    <PatientDetails person={person} details={details} guardian={guardian} guardianReviewRequired={guardianReviewRequired} timezone={clinic.timezone} page={page} submit={page.submit} />
  );
  const followUpSection = page.data && (
    <FollowUp followUp={followUp} issues={issues} staff={staff} personId={personId} page={page} submit={page.submit} timezone={clinic.timezone} showAppointment={appointmentLink} />
  );

  return (
    <Frame
      area="patient-workspace"
      title={person?.name || (caseEntry ? 'Follow-up details' : 'Patient details')}
      eyebrow={clinic?.name}
      subtitle={followUp && ((person ? 'Patient follow-up' : 'Patient details are restricted') + ' · ' + states[followUp.state])}
      page={page}
      clinic={clinic}
      headingAction={followUp && (
        <div className="owner-panel">
          {followUp.state === 'resolved' ? <ResolutionSummary resolution={followUp.resolution} timezone={clinic.timezone} /> : (
            <>
              <span className="hint">Assigned to</span>
              <strong>{followUp.owner || 'Unassigned'}</strong>
              {staff?.id && followUp.owner_id !== staff.id && (
                <button className="primary" disabled={!page.canSubmit} onClick={() => page.submit('/work/' + followUp.id, { outcome: 'claim', version: followUp.version })}>
                  {page.busy ? 'Assigning…' : 'Assign to me'}
                </button>
              )}
              {staff?.id && followUp.owner_id === staff.id && <span className="hint">You are responsible for this work</span>}
            </>
          )}
        </div>
      )}
    >
      {clinic && <a className="back" href={'/front-desk?clinic=' + clinic.id}>← Patient flow / {clinic.name}</a>}
      {personId && (
        <>
          <div className="patient-workspace-summary">
            <div>
              <strong>Next scheduled appointment</strong>
              {nextAppointment ? (
                <p>
                  {formatWallTime(nextAppointment.start_at)} · #{nextAppointment.appointment_id}
                  {' '}<button type="button" onClick={() => showAppointment(nextAppointment.appointment_id)}>View appointment</button>
                </p>
              ) : <p>No upcoming appointment recorded.</p>}
              {nextAppointment && person.allowed_channels && (
                <p>Reminder channels for this appointment: {person.allowed_channels.join(', ') || 'None available'}</p>
              )}
            </div>
            {hold && <div className="notice"><p>{hold}</p><button type="button" onClick={showDetails}>Review patient details</button></div>}
          </div>
        </>
      )}
      <div className={personId ? "workspace-layout" : undefined}>
        {personId && <aside className="workspace-patient-card" aria-label="Patient details">{verification}</aside>}
        <div className="workspace-content">
      <nav className="patient-workspace-nav" aria-label="Patient workspace">
        {Object.entries({ 'follow-up': 'Follow-up', ...(personId ? { appointments: 'Appointments' } : {}), activity: 'Activity log' }).map(([id, label]) => (
          <button key={id} type="button" aria-pressed={section === id} aria-controls={'workspace-' + id} onClick={() => setSection(id)}>
            {label}{id === 'follow-up' && <span className="count">{issues.filter((item) => !item.resolved_at).length}</span>}
          </button>
        ))}
      </nav>
      <div id="workspace-follow-up" hidden={section !== 'follow-up'}>{followUpSection}</div>
      <div id="workspace-appointments" hidden={section !== 'appointments'}>
      {personId && (
        <PatientAppointments personId={personId} timezone={clinic.timezone} appointments={visits} selectedId={selectedAppointment} selectAppointment={selectAppointment} refreshKey={page.data} showMessage={showMessage} />
      )}
      </div>
      <div id="workspace-activity" hidden={section !== 'activity'}>
      {(personId || history.length > 0) && (
        <PatientActivity personId={personId} refreshKey={page.data} history={history} timezone={clinic.timezone} showAppointment={appointmentLink} messageId={selectedMessage} showMessage={showMessage} clearMessage={() => selectMessage(null)} />
      )}
      </div>
        </div>
      </div>
    </Frame>
  );
}
