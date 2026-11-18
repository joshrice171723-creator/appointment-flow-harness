import React from 'react';
import { moveDate, calendarLabel } from '../../shared/format';

export default function AppointmentCalendar({ requestedDay, today, days, visits, onDateChange }) {
  return (
    <section
      className="panel appointment-calendar"
      aria-label="Appointment calendar"
    >
      <div className="calendar-controls">
        <div className="actions">
          <button onClick={() => onDateChange(moveDate(requestedDay, -7))}>
            ← Previous week
          </button>
          <button onClick={() => onDateChange(today)}>Today</button>
          <button onClick={() => onDateChange(moveDate(requestedDay, 7))}>
            Next week →
          </button>
        </div>
        <label htmlFor="appointment-date">Jump to date</label>
        <input
          id="appointment-date"
          type="date"
          value={requestedDay}
          onChange={(event) => {
            if (event.target.value) onDateChange(event.target.value);
          }}
        />
      </div>
      <div className="calendar-days">
        {days.map((day) => (
          <button
            key={day}
            aria-pressed={day === requestedDay}
            onClick={() => onDateChange(day)}
          >
            <strong>{calendarLabel(day)}</strong>
            <small>
              {
                visits.filter(
                  (visit) => visit.start_at.slice(0, 10) === day,
                ).length
              }{' '}
              visits
            </small>
          </button>
        ))}
      </div>
    </section>
  );
}
