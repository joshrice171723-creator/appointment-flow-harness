export const MAX_REPLY_LENGTH = 1000;
export const MAX_FOLLOW_UP_NOTE_LENGTH = 1000;

export const path = window.location.pathname;
export const params = new URLSearchParams(window.location.search);

export const states = {
  attention: 'Needs attention',
  progress: 'In progress',
  resolved: 'Resolved',
};

export const workSummary = {
  attention: 'Open patient concerns and due follow-up',
  progress: 'Owned by a team member',
  resolved: 'Follow-up history',
};

export const outcomes = {
  completed: 'Completed',
  canceled: 'Canceled',
  rescheduled: 'Rescheduled',
  unknown: 'Unknown',
};
