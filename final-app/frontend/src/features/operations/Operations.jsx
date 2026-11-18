import React, { useEffect, useId, useState } from 'react';
import ClinicComparison from './ClinicComparison';
import { usePage } from '../../shared/usePage';
import { Frame } from '../../shared/ui';
import { monthName, percentage } from '../../shared/format';

const outcomeLabels = [
  ['completed', 'Completed visits'],
  ['rescheduled', 'Rescheduled'],
  ['canceled', 'Canceled'],
  ['unknown', 'Unknown result'],
];

const contactHoldLabels = {
  missing_age: 'Missing birthdate',
  conflicting_details: 'Conflicting PMS and local details',
  missing_phone: 'Missing phone with no usable email',
  invalid_phone: 'Invalid phone with no usable email',
  authorized_adult: 'Missing authorization for an adult contact',
  language: 'Language needs review',
  permission: 'No permitted reminder channel',
  opt_out: 'SMS opt-out with no permitted email',
  appointment_time: 'Appointment time needs review',
  patient_mapping: 'Patient mapping needs review',
  no_contact: 'No usable contact details',
  other: 'Other contact hold',
};

const followUpGroups = [
  ['Contact records and reminder recipients', 'Counts visits with missing or invalid details in the practice management system, and visits whose reminders went to an authorized adult. Contact details reflect what is on file now.', [
    ['missing_birthdate', 'Visits with no birthdate on file'],
    ['missing_phone', 'Visits with no phone number on file'],
    ['invalid_phone', 'Visits with an invalid phone number on file'],
    ['guardian_visits', 'Visits with a reminder sent to an authorized adult'],
  ]],
  ['Patient replies', 'Counts NO and YES-like replies sent to the front desk. The YES-like count includes replies asking for a call that were routed to staff.', [
    ['decline_replies', 'NO replies sent to front desk'],
    ['affirmative_review', 'YES-like replies sent to front desk'],
  ]],
  ['Front-desk issues', 'Counts issue records by their latest state and reason. A visit can have multiple issues. Reopening changes an existing record.', [
    ['total', 'Issue records'],
    ['resolved', 'Currently resolved'],
    ['open', 'Currently open'],
    ['contact', 'Contact or permission holds'],
    ['no_response', 'No reply before appointment'],
    ['delivery', 'Delivery failures'],
    ['patient', 'Patient replies needing review'],
    ['ambiguous_reply', 'Replies needing an appointment match'],
    ['other', 'Other issues'],
  ]],
];

function CountTooltip({ group, description }) {
  const tooltipId = useId();
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    function dismissOnEscape(event) {
      if (event.key === 'Escape') setDismissed(true);
    }
    window.addEventListener('keydown', dismissOnEscape);
    return () => window.removeEventListener('keydown', dismissOnEscape);
  }, []);

  return (
    <span className="count-tooltip" onMouseEnter={() => setDismissed(false)}>
      <button type="button" aria-label={`About ${group}`} aria-describedby={tooltipId}
        onFocus={() => setDismissed(false)}>
        <span aria-hidden="true">i</span>
      </button>
      <span id={tooltipId} role="tooltip" hidden={dismissed}>{description}</span>
    </span>
  );
}

export default function Operations() {
  const [selectedMonth, setSelectedMonth] = useState('');
  const page = usePage('/operations?month=' + (selectedMonth || 'current'), { autoRefresh: true });
  const report = page.data || page.lastLoadedData;
  const rows = report?.rows || [];
  const months = [...new Set(rows.map((row) => row.outcome_month))];
  const activityMonth = report?.activity_month;
  const month = selectedMonth || (months.includes(activityMonth) ? activityMonth : months[0] || '');
  const periods = [...months].sort((first, second) => second.localeCompare(first));
  const clinics = report?.clinics || [];
  const reminderClinics = clinics.filter((clinic) => clinic.messaging_available);
  const detailReady = Boolean(page.data) && (selectedMonth || month === activityMonth);
  const fallbackMonth = !selectedMonth && page.data && month !== activityMonth ? month : '';
  const detailPending = !detailReady && (page.loading || Boolean(fallbackMonth));
  const detailClinics = report ? reminderClinics : [
    { id: 'pending', name: detailPending ? 'Loading clinics…' : 'Clinic unavailable' },
  ];

  useEffect(() => {
    if (fallbackMonth) setSelectedMonth(fallbackMonth);
  }, [fallbackMonth]);
  const monthRows = rows.filter((row) => row.outcome_month === month);
  const contactHolds = monthRows.flatMap((row) =>
    Object.entries(row.contact_holds || {}).map(([reason, counts]) => ({ clinic: row.clinic, reason, counts })),
  );
  return (
    <Frame
      title="Appointment outcomes"
      eyebrow={report?.workspace}
      page={page}
      area="ops"
      renderBeforeLoad
      headingAction={
        months.length > 0 && (
          <div className="period-picker">
            <label htmlFor="month">Outcome month</label>
            <select
              id="month"
              value={month}
              onChange={(event) => setSelectedMonth(event.target.value)}
            >
              {months.map((value) => (
                <option key={value} value={value}>
                  {monthName(value)}
                  {value === activityMonth ? ' so far' : ''}
                </option>
              ))}
            </select>
          </div>
        )
      }
    >
      {month && (
        <section className="outcomes-overview" aria-labelledby="outcomes-period">
          <div className="outcomes-overview-heading">
            <h2 id="outcomes-period">{monthName(month)}{month === activityMonth ? ' so far' : ''}</h2>
          </div>
          <div className="clinic-outcomes">
            {clinics.map((clinic) => {
              const row = monthRows.find((item) => item.clinic_id === clinic.id);
              const recordedVisits = row?.total || 0;
              const outcomes = outcomeLabels.map(([status, label]) => ({ status, label, count: row?.[status] || 0 }));
              return (
                <section key={clinic.id} aria-label={clinic.name + ' outcomes'}>
                  <div className="outcomes-overview-heading">
                    <h3>{clinic.name}</h3>
                    <p>{recordedVisits.toLocaleString()} recorded visits</p>
                  </div>
                  {recordedVisits > 0 ? (
                    <div className="outcome-distribution" aria-hidden="true">
                      {outcomes.map(({ status, count }) => count > 0 && (
                        <span key={status} data-outcome={status} style={{ flexGrow: count }} />
                      ))}
                    </div>
                  ) : <p>No recorded visits for this month.</p>}
                  <dl className="outcome-totals">
                    {outcomes.map(({ status, label, count }) => (
                      <div key={status}>
                        <dt><span className="outcome-key" data-outcome={status} aria-hidden="true" />{label}</dt>
                        <dd>{count.toLocaleString()} <small>{recordedVisits > 0 && percentage(count, recordedVisits)}</small></dd>
                      </div>
                    ))}
                  </dl>
                </section>
              );
            })}
          </div>
        </section>
      )}
      {report && <ClinicComparison clinics={clinics} rows={rows} periods={periods} month={month} activityMonth={activityMonth} />}
      {detailPending && <p className="sr-only" role="status">Loading month details…</p>}
      <details className="panel operations-detail">
        <summary>Contact holds</summary>
        <p>Each hold appears in its current state. A verification conflict stays open until it clears or the appointment leaves outreach.</p>
        <div className="table-wrap" role="region" aria-label="Contact holds by reason" aria-busy={detailPending} tabIndex={0}>
          <table>
            <thead>
              <tr>
                <th scope="col">Clinic</th>
                <th scope="col">Reason</th>
                <th scope="col">Still open</th>
                <th scope="col">Appointment outcome recorded</th>
                <th scope="col">Resolved another way</th>
              </tr>
            </thead>
            <tbody>
              {(!detailReady || !contactHolds.length) && (
                <tr><td colSpan={5}>{detailPending ? 'Loading contact holds…' : detailReady ? 'No contact holds for this month.' : 'Contact holds unavailable.'}</td></tr>
              )}
              {detailReady && contactHolds.map(({ clinic, reason, counts }) => (
                <tr key={clinic + reason}>
                  <td>{clinic}</td>
                  <th scope="row">{contactHoldLabels[reason] || contactHoldLabels.other}</th>
                  <td>{counts.open}</td>
                  <td>{counts.appointment_outcome}</td>
                  <td>{counts.otherwise_resolved}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
      <details className="panel operations-detail">
        <summary>Contact and follow-up</summary>
        <p>Counts cover clinics with reminders configured and include upcoming visits in the selected appointment month.</p>
        {detailClinics.length === 0 ? <p>No clinics have reminders configured.</p> : (
          <div className="table-wrap follow-up-counts" role="region" aria-label="Contact and follow-up counts" aria-busy={detailPending} tabIndex={0}>
            <table>
              <thead>
                <tr>
                  <th scope="col">Measure</th>
                  {detailClinics.map((clinic) => <th key={clinic.id} scope="col">{clinic.name}</th>)}
                </tr>
              </thead>
              {followUpGroups.map(([group, description, measures]) => (
                <tbody key={group}>
                  <tr>
                    <th scope="rowgroup" colSpan={detailClinics.length + 1}>
                      <div className="follow-up-group-heading">
                        <h3>{group}</h3>
                        <CountTooltip group={group} description={description} />
                      </div>
                    </th>
                  </tr>
                  {measures.map(([key, label]) => (
                    <tr key={key}>
                      <th scope="row">{label}</th>
                      {detailClinics.map((clinic) => (
                        <td key={clinic.id}>
                          {detailReady ? monthRows.find((row) => row.clinic_id === clinic.id)?.follow_up?.[key] ?? '—' : (
                            <span aria-label={detailPending ? 'Loading' : 'Unavailable'}>{detailPending ? '…' : '—'}</span>
                          )}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              ))}
            </table>
          </div>
        )}
      </details>
    </Frame>
  );
}
