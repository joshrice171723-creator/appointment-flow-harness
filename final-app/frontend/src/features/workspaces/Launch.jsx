import React, { useState } from 'react';
import { usePage } from '../../shared/usePage';
import { Frame } from '../../shared/ui';

export default function Launch() {
  const page = usePage('/workspaces');
  const [clinicId, setClinicId] = useState('');
  const [selectedStaffId, setSelectedStaffId] = useState('');
  const clinics = page.data?.clinics || [];
  const clinic =
    clinics.find((item) => item.id === Number(clinicId)) || clinics[0];
  const team =
    page.data?.staff.filter((person) => person.clinic_id === clinic?.id) || [];
  const staffId =
    team.find((person) => person.id === Number(selectedStaffId))?.id || team[0]?.id;
  function enterFrontDesk(event) {
    event.preventDefault();
    page.submit('/enter', { workspace: 'desk', clinic: clinic.id, staff: staffId });
  }

  return (
    <Frame area="launch" page={page} title="Workspaces">
      <div className="workspace-grid">
        <section className="workspace-card">
          <h2>Front desk</h2>
          <p>Review appointments and follow up with patients.</p>
          <form onSubmit={enterFrontDesk}>
            <label htmlFor="clinic">Clinic</label>
            <select
              id="clinic"
              value={clinic?.id}
              onChange={(event) => {
                setClinicId(event.target.value);
                setSelectedStaffId('');
              }}
            >
              {clinics.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}, {item.state}
                </option>
              ))}
            </select>
            <label htmlFor="staff">
              Staff member <span className="hint">local sign-in</span>
            </label>
            <select
              id="staff"
              value={staffId}
              onChange={(event) => setSelectedStaffId(event.target.value)}
            >
              {team.map((person) => (
                <option key={person.id} value={person.id}>
                  {person.name}
                </option>
              ))}
            </select>
            <button className="primary wide" disabled={!page.canSubmit || !staffId}>
              Open front desk <span aria-hidden="true">→</span>
            </button>
          </form>
        </section>
        <section className="workspace-card leadership-entry">
          <h2>Apex leadership</h2>
          <p><strong>No PHI. Aggregated data only.</strong></p>
          <div className="entry-stat">
            <strong>
              {page.data?.reporting_clinic_count}
              <span>clinics</span>
            </strong>
          </div>
          <button
            className="primary wide"
            disabled={!page.canSubmit}
            onClick={() => page.submit('/enter', { workspace: 'apex' })}
          >
            Open Apex leadership <span aria-hidden="true">→</span>
          </button>
        </section>
        <section className="workspace-card patient-entry">
          <h2>Patient</h2>
          <p><strong>For internal demo use only.</strong> Simulates a patient’s phone and email.</p>
          <button
            className="primary wide"
            disabled={!page.canSubmit}
            onClick={() => page.submit('/enter', { workspace: 'patient' })}
          >
            Open patient workspace <span aria-hidden="true">→</span>
          </button>
        </section>
      </div>
    </Frame>
  );
}
