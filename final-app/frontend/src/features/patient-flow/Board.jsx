import React, { useEffect, useState } from 'react';
import { usePage } from '../../shared/usePage';
import { Frame, IssuePill, ResolutionSummary } from '../../shared/ui';
import { params, states, workSummary } from '../../shared/constants';
import { formatWallTime } from '../../shared/format';

const resolutionLabels = {
  confirmed: 'Confirmed',
  confirmation: 'Confirmed',
  canceled: 'Canceled',
  rescheduled: 'Rescheduled',
};

function WorkCard({ followUp, clinic }) {
  const isResolved = followUp.state === 'resolved';
  const reason = isResolved ? followUp.resolution?.reason : followUp.reason;
  const summary = reason || followUp.latest || 'Open to review the next step.';
  const showLatestAction = followUp.reason
    && followUp.latest
    && followUp.reason !== followUp.latest;

  return (
    <a className="work-card" href={'/patient-details/' + followUp.patient_id}>
      <div className="card-top">
        <div className="actions">
          {isResolved ? (
            <span className="pill neutral">
              {resolutionLabels[followUp.resolution?.kind] || 'Closed'}
            </span>
          ) : (
            <>
              {followUp.reply_review && <IssuePill code="patient" />}
              {followUp.no_response && <IssuePill code="no_response" appointmentAt={followUp.no_response_start_at} />}
              {followUp.reminders_blocked && <IssuePill code="contact" />}
              {followUp.delivery_failed && <IssuePill code="delivery" />}
            </>
          )}
        </div>
        <span className="arrow" aria-hidden="true">↗</span>
      </div>
      <h3>{followUp.name}</h3>
      <p className="card-reason">{summary}</p>
      {followUp.visits > 0 && (
        <>
          <div className="card-meta">
            {followUp.visits} affected{' '}
            {followUp.visits === 1 ? 'visit' : 'visits'} · {clinic.name}
          </div>
          <div className="card-meta">{formatWallTime(followUp.first_visit)}</div>
        </>
      )}
      <div className="card-bottom">
        {isResolved ? (
          <ResolutionSummary
            resolution={followUp.resolution}
            timezone={clinic.timezone}
          />
        ) : (
          <>
            <span className="avatar" aria-hidden="true">
              {followUp.owner?.[0] || '?'}
            </span>
            <span>{followUp.owner || 'Unassigned'}</span>
          </>
        )}
      </div>
      {showLatestAction && <p className="last-action">{followUp.latest}</p>}
    </a>
  );
}

const queuePageSizes = [10, 20, 30];

function QueuePage({ state, matching, clinic, pageSize, changePageSize, emptyMessage }) {
  const [page, setPage] = useState(1);
  const total = matching.length;
  const lastPage = Math.max(1, Math.ceil(total / pageSize));
  const currentPage = Math.min(page, lastPage);
  const start = (currentPage - 1) * pageSize;
  const label = states[state];

  useEffect(() => {
    setPage((previousPage) => Math.min(previousPage, lastPage));
  }, [lastPage]);

  return (
    <>
      <div className="queue-pagination" role="group" aria-label={label + ' pagination'}>
        <label>
          Per page
          <select value={pageSize} onChange={(event) => {
            changePageSize(Number(event.target.value));
            setPage(1);
          }}>
            {queuePageSizes.map((size) => <option key={size}>{size}</option>)}
          </select>
        </label>
        <span role="status">{total ? (start + 1) + '–' + Math.min(start + pageSize, total) + ' of ' + total : '0 of 0'}</span>
        <div className="queue-page-buttons">
          <button type="button" disabled={currentPage === 1} onClick={() => setPage(currentPage - 1)}>Previous</button>
          <button type="button" disabled={currentPage === lastPage} onClick={() => setPage(currentPage + 1)}>Next</button>
        </div>
      </div>
      <div className="queue-cards">
        {matching.slice(start, start + pageSize).map((followUp) => (
          <WorkCard key={followUp.id} followUp={followUp} clinic={clinic} />
        ))}
        {!total && emptyMessage}
      </div>
    </>
  );
}

export default function Board() {
  const page = usePage('/board?' + params, { autoRefresh: true });
  const { clinic, staff, cases = [] } = page.data || {};
  const initialState = params.get('state');
  const [filter, setFilter] = useState(
    Object.hasOwn(states, initialState) ? initialState : 'active',
  );
  const [search, setSearch] = useState('');
  const [issueFilter, setIssueFilter] = useState('all');
  const [pageSizes, setPageSizes] = useState({});
  const searchText = search.trim().toLowerCase();
  const results = cases.filter((followUp) =>
    followUp.name.toLowerCase().includes(searchText)
      && (filter === 'resolved' || issueFilter === 'all' || followUp[issueFilter]),
  );
  const counts = Object.fromEntries(
    Object.keys(states).map((state) => [
      state,
      results.filter((item) => item.state === state).length,
    ]),
  );
  const shown = filter === 'active' ? ['attention', 'progress'] : [filter];
  return (
    <Frame
      title="Patient flow"
      eyebrow={clinic?.name}
      page={page}
      clinic={clinic}
      headingAction={
        clinic && (
          <div className="clinic-context">
            <strong>
              {clinic.name}, {clinic.state}
            </strong>
            <small>
              {staff.name} · {clinic.timezone}
            </small>
          </div>
        )
      }
    >
      <div className="metrics work-metrics">
        {Object.entries(states).map(([state, label]) => (
          <button
            key={state}
            className={'metric' + (filter === state ? ' active' : '')}
            aria-pressed={filter === state}
            onClick={() => setFilter((current) => current === state ? 'active' : state)}
          >
            <span>{label}</span>
            <strong>{counts[state]}</strong>
            <small>{workSummary[state]}</small>
          </button>
        ))}
      </div>
      <div className="board-toolbar">
        <div className="tabs">
          <button
            aria-pressed={filter === 'active'}
            onClick={() => setFilter('active')}
          >
            Active work
          </button>
          <button
            aria-pressed={filter === 'resolved'}
            onClick={() => setFilter('resolved')}
          >
            Resolved
          </button>
          <a href={'/appointments?clinic=' + clinic?.id}>All appointments →</a>
        </div>
        <div className="search">
          <label className="sr-only" htmlFor="search">
            Find a patient
          </label>
          <input
            id="search"
            value={search}
            maxLength={80}
            placeholder="Find a patient…"
            onChange={(event) => setSearch(event.target.value)}
          />
        </div>
      </div>
      {filter !== 'resolved' && (
        <div className="board-toolbar">
          <div>
            <label htmlFor="work-type">Follow-up type</label>
            <select id="work-type" value={issueFilter} onChange={(event) => setIssueFilter(event.target.value)}>
              <option value="all">All follow-up types</option>
              <option value="reply_review">Reply needs review</option>
              <option value="no_response">No reply</option>
              <option value="reminders_blocked">Reminders blocked</option>
              <option value="delivery_failed">Delivery failed</option>
            </select>
          </div>
        </div>
      )}
      <div className={'board' + (filter === 'active' ? '' : ' single-column')}>
        {shown.map((state) => {
          const matching = results.filter((item) => item.state === state);
          if (issueFilter === 'no_response' && state !== 'resolved') {
            matching.sort((a, b) =>
              (a.no_response_start_at || '9999').localeCompare(b.no_response_start_at || '9999'),
            );
          }
          const isActive = state !== 'resolved';
          const emptyMessage = (
            <div className="empty-column">
              <strong>No matching work</strong>
              <p>{searchText ? 'Try a different patient name.' : 'New follow-ups will appear here.'}</p>
            </div>
          );
          return (
            <section className={'column ' + state + (isActive ? ' active-queue' : '')} key={state}>
              <div className="column-heading">
                <h2>
                  <span className="column-dot" />
                  {states[state]} <span className="count">{counts[state]}</span>
                </h2>
                <p>{workSummary[state]}</p>
              </div>
              <QueuePage
                key={JSON.stringify([filter, searchText, issueFilter])}
                state={state}
                matching={matching}
                clinic={clinic}
                pageSize={pageSizes[state] ?? queuePageSizes[0]}
                changePageSize={(size) => setPageSizes((current) => ({ ...current, [state]: size }))}
                emptyMessage={emptyMessage}
              />
            </section>
          );
        })}
      </div>
      <div className="pagination">
        <span>
          {shown.reduce((sum, state) => sum + counts[state], 0)} matching work
          items
        </span>
      </div>
    </Frame>
  );
}
