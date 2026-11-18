import React from 'react';
import { monthName, percentage } from '../../shared/format';

export default function ClinicComparison({ clinics, rows, periods, month, activityMonth }) {
  return (
    <>
      <section className="panel operations-comparison" aria-labelledby="clinic-comparison">
        <div className="section-heading">
          <h2 id="clinic-comparison">Clinic comparison</h2>
          <details className="explanation">
            <summary>How rates are calculated</summary>
            <p>
              Completed ÷ all recorded visits in this report. In the practice management system,
              complete means completed, broken means rescheduled, and unscheduled means canceled.
              Past visits still scheduled have an unknown result. Future scheduled visits are excluded.
              These statuses do not identify no-shows or arrival times.
            </p>
          </details>
        </div>
        {!month ? (
          <p>No appointment outcomes have been recorded.</p>
        ) : (
          <div className="table-wrap" role="region" aria-label="Clinic outcome comparison" tabIndex={0}>
            <table>
              <thead>
                <tr>
                  <th scope="col">Clinic</th>
                  <th scope="col">Completion rate</th>
                  <th scope="col">Recorded visits</th>
                  <th scope="col">Rescheduled</th>
                  <th scope="col">Canceled</th>
                  <th scope="col">Unknown</th>
                </tr>
              </thead>
              <tbody>
                {clinics.map((clinic) => {
                  const outcome = rows.find((row) => row.clinic_id === clinic.id && row.outcome_month === month);
                  return (
                    <tr key={clinic.id}>
                      <th scope="row">
                        {clinic.name}
                        <small>{clinic.messaging_available ? 'Reminders clinic' : 'Comparison clinic'}</small>
                      </th>
                      <td>
                        {outcome?.total > 0 ? <strong>{percentage(outcome.completed, outcome.total)}</strong> : '—'}
                        {outcome && <small>{outcome.completed.toLocaleString()} completed</small>}
                      </td>
                      <td>{outcome?.total.toLocaleString() ?? '—'}</td>
                      <td>{outcome?.rescheduled.toLocaleString() ?? '—'}</td>
                      <td>{outcome?.canceled.toLocaleString() ?? '—'}</td>
                      <td>{outcome?.unknown.toLocaleString() ?? '—'}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
      {month && (
        <details className="panel operations-detail">
          <summary>Monthly history and reminder activity</summary>
          <p>Activity is grouped by appointment month. Reply rates use visits reached as the denominator.</p>
          <div className="table-wrap" role="region" aria-label="Monthly clinic history" tabIndex={0}>
            <table>
              <thead>
                <tr>
                  <th scope="col">Month</th>
                  <th scope="col">Clinic</th>
                  <th scope="col">Completed</th>
                  <th scope="col">Messages sent</th>
                  <th scope="col">Matched replies</th>
                  <th scope="col">Confirmed by YES</th>
                </tr>
              </thead>
              <tbody>
                {periods.flatMap((period) => clinics.map((clinic) => {
                  const outcome = rows.find((row) => row.clinic_id === clinic.id && row.outcome_month === period);
                  if (!outcome) return null;
                  return (
                    <tr key={period + clinic.id}>
                      <td>{monthName(period, true)}{period === activityMonth ? ' so far' : ''}</td>
                      <th scope="row">{clinic.name}</th>
                      <td>
                        {outcome.completed}/{outcome.total}
                        {outcome.total > 0 && <small>{percentage(outcome.completed, outcome.total)}</small>}
                      </td>
                      <td>{outcome.messages_sent}</td>
                      <td>
                        {outcome.messaged > 0 ? (
                          <>
                            {outcome.replied}/{outcome.messaged}
                            <small>{percentage(outcome.replied, outcome.messaged)}</small>
                          </>
                        ) : '—'}
                      </td>
                      <td>{outcome.patient_confirmed}</td>
                    </tr>
                  );
                }))}
              </tbody>
            </table>
          </div>
        </details>
      )}
    </>
  );
}
