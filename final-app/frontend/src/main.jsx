import React from 'react';
import { createRoot } from 'react-dom/client';
import { path } from './shared/constants';
import Launch from './features/workspaces/Launch';
import Board from './features/patient-flow/Board';
import Appointments from './features/appointments/Appointments';
import PatientWorkspace from './features/patient-workspace/PatientWorkspace';
import Patient from './features/patient-inbox/Patient';
import Operations from './features/operations/Operations';

const screens = {
  '/appointments': Appointments,
  '/front-desk': Board,
  '/patient': Patient,
  '/operations': Operations,
};
function screenForPath() {
  if (path.startsWith('/work/') || path.startsWith('/patient-details/')) return PatientWorkspace;
  return screens[path] || Launch;
}

const App = screenForPath();
createRoot(document.getElementById('root')).render(<App />);
