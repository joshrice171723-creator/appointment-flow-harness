import React from 'react';
import { outcomes } from '../../shared/constants';
import { formatWallTime, confirmationLabel } from '../../shared/format';

export default function AppointmentTable({ clinic, matching, changingDate, loading, readError, filter }) {
  return (
    <div
      className="panel table-wrap"
      role="region"
      aria-label="Appointments for selected date"
      aria-busy={changingDate && loading}
      tabIndex={0}
    >
      <table>
        <thead>
          <tr>
            <th>Patient</th>
            <th title="Appointment times use the clinic's local time zone.">
              Appointment · {clinic?.timezone}
            </th>
            <th title="What the patient replied or staff confirmed. A NO requires follow-up; it does not cancel the PMS booking.">
              Confirmation or reply
            </th>
            <th title="Attendance or scheduling outcome from the PMS. A reply alone cannot establish whether someone attended.">
              Visit outcome
            </th>
            <th title="Open current follow-up or review the history of a handled reply. Scheduling changes happen in the PMS.">
              Next step
            </th>
          </tr>
        </thead>
        <tbody>
          {matching.map((visit) => {
            const followUp = visit.reply || visit.follow_up;
            const isConfirmed = visit.confirmed_at && !visit.reply;
            return (
              <tr key={visit.appointment_id}>
                <td>
                  <strong>{visit.name}</strong>
                  <small>Appointment #{visit.appointment_id}</small>
                  {visit.patient_id && <small><a href={'/patient-details/' + visit.patient_id}>Patient details</a></small>}
                </td>
                <td>
                  {formatWallTime(visit.start_at)}
                  <small>{visit.provider_name || 'Provider not recorded'}</small>
                </td>
                <td>
                  <span className={'pill ' + (isConfirmed ? 'positive' : 'neutral')}>
                    {confirmationLabel(visit, visit.status === 'scheduled' ? 'Unconfirmed' : '—')}
                  </span>
                  {visit.declined_reply && isConfirmed && (
                    <small>Previously replied NO</small>
                  )}
                  {visit.patient_reply && (
                    <small>{visit.patient_reply.body}</small>
                  )}
                  {visit.hold && <small>{visit.hold}</small>}
                </td>
                <td>
                  {outcomes[visit.outcome] || '—'}
                  {visit.status && visit.status !== 'scheduled' && (
                    <small>PMS status · {visit.status}</small>
                  )}
                </td>
                <td>
                  <div className="table-actions">
                    {followUp && (
                      <a
                        title="Open the reply, affected appointment, and staff follow-up actions."
                        href={'/work/' + followUp.case_id}
                      >
                        {visit.reply
                          ? 'Review patient reply →'
                          : 'Review follow-up →'}
                      </a>
                    )}
                    {!followUp && visit.patient_reply?.case_id && (
                      <a
                        title="See the earlier reply and how its follow-up was handled."
                        href={'/work/' + visit.patient_reply.case_id}
                      >
                        View reply history →
                      </a>
                    )}
                  </div>
                </td>
              </tr>
            );
          })}
          {changingDate ? (
            <tr>
              <td colSpan="5" role="status">
                {readError
                  ? 'Appointments for this date are unavailable.'
                  : 'Loading appointments…'}
              </td>
            </tr>
          ) : (
            !matching.length && (
              <tr>
                <td colSpan="5">
                  {filter === 'review'
                    ? 'No replies to review for this date.'
                    : 'No matching appointments for this date.'}
                </td>
              </tr>
            )
          )}
        </tbody>
      </table>
    </div>
  );
}
