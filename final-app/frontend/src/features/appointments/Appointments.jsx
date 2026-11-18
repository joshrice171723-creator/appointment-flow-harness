import React, { useState } from 'react';
import AppointmentTable from './AppointmentTable';
import AppointmentCalendar from './AppointmentCalendar';
import { usePage } from '../../shared/usePage';
import { Frame } from '../../shared/ui';
import { params } from '../../shared/constants';
import { moveDate } from '../../shared/format';

const appointmentFilters = {
  all: {
    label: 'All appointments',
    help: 'Every appointment on the selected date, including past and canceled visits.',
    matches: () => true,
  },
  confirmed: {
    label: 'Confirmed',
    help: 'Confirmation is recorded and no reply needs review. This does not mean the patient attended.',
    matches: (visit) => !!visit.confirmed_at && !visit.reply,
  },
  unconfirmed: {
    label: 'Unconfirmed',
    help: 'Scheduled visits without confirmation or a recorded NO or reply awaiting review.',
    matches: (visit) => visit.status === 'scheduled'
      && !visit.confirmed_at
      && !visit.reply
      && !visit.patient_reply,
  },
  review: {
    label: 'Replies to review',
    help: 'Replies that still need staff review, including NO and unclear responses.',
    matches: (visit) => !!visit.reply,
  },
};

export default function Appointments() {
  const [date, setDate] = useState(params.get('date') || 'today');
  const query = new URLSearchParams(params);
  query.set('date', date);
  const page = usePage('/appointments?' + query, { autoRefresh: true });
  const {
    clinic,
    visits = [],
    week,
    date: selectedDay,
    today,
  } = page.lastLoadedData || {};
  const requestedDay = date === 'today' ? selectedDay : date;
  const changingDate = !page.data;
  const dailyVisits = visits.filter(
    (visit) => visit.start_at.slice(0, 10) === selectedDay,
  );
  const days = week
    ? Array.from({ length: 7 }, (_, offset) => moveDate(week, offset))
    : [];
  const [filter, setFilter] = useState(params.get('status') || 'all');
  const selectedFilter = appointmentFilters[filter] || appointmentFilters.all;
  const matching = changingDate ? [] : dailyVisits.filter(selectedFilter.matches);
  return (
    <Frame
      title="Appointments"
      eyebrow={clinic?.name}
      subtitle="A clear YES can confirm a current visit. A NO needs review. Schedule changes are recorded in the practice management system."
      page={page}
      clinic={clinic}
      headingAction={
        clinic && (
          <a className="button" href={'/front-desk?clinic=' + clinic.id}>
            Open patient flow →
          </a>
        )
      }
    >
      {selectedDay && (
        <AppointmentCalendar requestedDay={requestedDay} today={today} days={days} visits={visits} onDateChange={setDate} />
      )}
      <div className="tabs appointment-tabs">
        {Object.entries(appointmentFilters).map(([id, option]) => (
          <button
            key={id}
            title={option.help}
            aria-description={option.help}
            aria-pressed={filter === id}
            onClick={() => setFilter(id)}
          >
            {option.label}{' '}
            {!changingDate && (
              <strong>{dailyVisits.filter(option.matches).length}</strong>
            )}
          </button>
        ))}
      </div>
      <AppointmentTable clinic={clinic} matching={matching} changingDate={changingDate} loading={page.loading} readError={page.readError} filter={filter} />
    </Frame>
  );
}
