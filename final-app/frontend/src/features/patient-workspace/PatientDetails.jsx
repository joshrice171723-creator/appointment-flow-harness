import React, { useRef, useState } from 'react';
import { formatInstant } from '../../shared/format';
import { ActivityList, HistoryResults } from './PatientHistory';

const inputTypes = { birthdate: 'date', wireless_phone: 'tel', email: 'email' };

function PatientDetailEditor({ detail, personId, originatingPatientId, timezone, page, submit }) {
  const [draft, setDraft] = useState(null);
  const dialog = useRef(null);
  const [showHistory, setShowHistory] = useState(false);
  const storedValue = detail.conflict ? detail.pms_value : detail.verified_value ?? detail.pms_value;
  const value = draft ?? (detail.conflict ? '' : storedValue ?? '');
  const inputId = `verified-${personId}-${detail.field}`;

  function verifyDetail(event) {
    event.preventDefault();
    submit(`/patient-details/${personId}`, {
      field: detail.field,
      verified_value: value,
      token: detail.token,
      ...(originatingPatientId ? { originating_patient_id: originatingPatientId } : {}),
    }, () => {
      setDraft(null);
      dialog.current.close();
    });
  }

  return (
    <div className="patient-detail-field" data-conflict={detail.conflict ? true : undefined}>
      <div className="patient-detail-row">
        <span className="patient-detail-label">{detail.label}</span>
        <strong>{storedValue || (detail.field === 'preferred_language' ? 'English assumed' : 'No value on file')}</strong>
        <span className={'pill ' + (detail.conflict ? 'urgent' : detail.verified_at ? 'positive' : 'neutral')}>
          {detail.conflict ? 'Review required' : detail.verified_at ? 'Verified' : 'Not verified'}
        </span>
        <button type="button" className="detail-edit-icon" title={'Edit ' + detail.label.toLowerCase() + ' and view history'} aria-label={'Edit ' + detail.label.toLowerCase() + ' and view history'} onClick={() => {
          setShowHistory(true);
          dialog.current.showModal();
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="m15 5 4 4M4 20l4-1L20 7a2.8 2.8 0 0 0-4-4L4 15l-1 6 5-2" />
          </svg>
        </button>
      </div>
      <dialog ref={dialog} className="workspace-record patient-detail-dialog" aria-labelledby={inputId + '-title'} onClose={() => setShowHistory(false)}>
        <div className="section-heading">
          <h2 id={inputId + '-title'}>{detail.label}</h2>
          <button type="button" onClick={() => dialog.current.close()}>Close</button>
        </div>
        <p className="hint">Verify details in Appointment Flow. The PMS remains read-only.</p>
        <form onSubmit={verifyDetail} aria-describedby={page.feedbackId || page.readError ? inputId + '-feedback' : undefined}>
          {(page.feedbackId || page.readError) && (
            <div className="notice" id={inputId + '-feedback'}>
              <p role="alert">{page.submission.message || page.readError || 'Review the latest details before saving again.'}</p>
              <button type="button" onClick={page.reviewLatest} disabled={page.loading || page.busy}>Reload details</button>
            </div>
          )}
          <dl>
            <dt>Practice management system (PMS)</dt>
            <dd>{detail.pms_value || 'No value on file'}</dd>
            <dt>Verified in Appointment Flow</dt>
            <dd>
              {detail.verified_value || 'No local correction'}
              {detail.matches_pms && <small>Matches the PMS value</small>}
              {detail.verified_at && (
                <small>{detail.verified_by} · {formatInstant(detail.verified_at, timezone)}</small>
              )}
            </dd>
          </dl>
          {detail.conflict && (
            <p className="notice" id={inputId + '-help'}>
              The PMS value changed after verification. Automated reminders are on hold. Enter the value you have verified.
            </p>
          )}
          <label htmlFor={inputId}>Verified {detail.label.toLowerCase()}</label>
          <input
            id={inputId}
            type={inputTypes[detail.field] || 'text'}
            maxLength={254}
            value={value}
            onChange={(event) => setDraft(event.target.value)}
            aria-describedby={detail.conflict ? inputId + '-help' : undefined}
            required
            readOnly={page.busy}
          />
          <button className="primary" disabled={page.busy || page.canSubmit === false}>
            Verify and save {detail.label.toLowerCase()}
          </button>
        </form>
        <section className="patient-verification-history">
          <h3>Verification history</h3>
          {showHistory && (
            <HistoryResults personId={originatingPatientId || personId} section="activity" filter="verifications" refreshKey={page.data}>
              {(rows) => {
                const matching = rows.filter((entry) => entry.patient_id === personId && entry.field === detail.field);
                return matching.length ? <ActivityList rows={matching} timezone={timezone} /> : <p className="hint">No verifications for this field in the loaded records.</p>;
              }}
            </HistoryResults>
          )}
        </section>
      </dialog>
    </div>
  );
}

export function PatientDetails({ person, details, guardian, guardianReviewRequired, timezone, page, submit }) {
  const contact = person.contact;

  function fieldsFor(personId, fields, originatingPatientId) {
    return fields.map((detail) => (
      <PatientDetailEditor
        key={`${personId}-${detail.field}`}
        detail={detail}
        personId={personId}
        originatingPatientId={originatingPatientId}
        timezone={timezone}
        page={page}
        submit={submit}
      />
    ));
  }

  return (
    <section className="panel contact">
      <h2 id="patient-details" tabIndex={-1}>Patient details</h2>
      <p><strong>{person.name}</strong></p>
      {contact && (
        <dl>
          <dt>Contact on file</dt>
          <dd>{contact.name || person.name}</dd>
        </dl>
      )}
      {fieldsFor(person.id, details)}
      {guardian && (
        <div className="patient-workspace-adult">
          <h3>Authorized adult · {guardian.name}</h3>
          {fieldsFor(guardian.id, guardian.details, person.id)}
        </div>
      )}
      {guardianReviewRequired && <p className="notice">Review the PMS guarantor link and contact authorization.</p>}
    </section>
  );
}
