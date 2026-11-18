import React, { useEffect, useRef, useState } from 'react';
import { path } from './constants';
import { formatInstant } from './format';

const issuePills = {
  patient: ['reply-review', 'Reply needs review'],
  no_response: ['reply-missing', 'No reply'],
  contact: ['urgent', 'Reminders blocked'],
  delivery: ['neutral', 'Delivery failed'],
};

export function IssuePill({ code, appointmentAt }) {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    if (code !== 'no_response' || !appointmentAt) return;
    setNow(Date.now());
    const timer = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, [code, appointmentAt]);
  const issueType = code === 'ambiguous_reply' ? 'patient' : code;
  const [tone, label] = issuePills[issueType] || ['neutral', 'Appointment follow-up'];
  let text = label;
  if (code === 'no_response') {
    const remaining = new Date(appointmentAt).getTime() - now;
    if (!appointmentAt || !Number.isFinite(remaining)) text += ' · appointment time unavailable';
    else if (remaining <= 0) text += ' · appointment time passed';
    else {
      const hours = Math.ceil(remaining / 3_600_000);
      text += ` · appointment in ${hours} ${hours === 1 ? 'hr' : 'hrs'}`;
    }
  }
  return <span className={'pill ' + tone}>{text}</span>;
}

export function Frame({
  title,
  subtitle,
  eyebrow,
  headingAction,
  introduction,
  page,
  clinic,
  area = 'desk',
  renderBeforeLoad = false,
  children,
}) {
  const sync = page.data?.sync_status;
  const { status, message } = page.submission;
  const rejected = status === 'rejected';
  const uncertain = status === 'uncertain';
  const actionAlert = useRef(null);
  const focusActionAlert = rejected || uncertain || page.saveRefreshFailed;
  useEffect(() => {
    if (focusActionAlert) actionAlert.current?.focus();
  }, [focusActionAlert]);
  return (
    <div className={area}>
      <a className="skip" href="#main">
        Skip to content
      </a>
      {area !== 'patient' && (
        <header className="topbar">
          <a className="brand" href="/">
            <span className="brandmark">
              A<span>↗</span>
            </span>
            <span>
              APEX<small>APPOINTMENT FLOW</small>
            </span>
          </a>
          <nav aria-label="Workspace navigation">
            {clinic && (
              <>
                <a
                  className={path === '/front-desk' ? 'selected' : undefined}
                  aria-current={path === '/front-desk' ? 'page' : undefined}
                  href={'/front-desk?clinic=' + clinic.id}
                >
                  Patient flow
                </a>
                <a
                  className={path === '/appointments' ? 'selected' : undefined}
                  aria-current={path === '/appointments' ? 'page' : undefined}
                  href={'/appointments?clinic=' + clinic.id}
                >
                  Appointments
                </a>
              </>
            )}
            {area === 'ops' && (
              <span className="workspace-name">{eyebrow}</span>
            )}
            <a href="/">Workspaces ↗</a>
          </nav>
        </header>
      )}
      <main id="main" tabIndex={-1}>
        {page.readError && (
          <div
            className="flash error"
            role="alert"
            ref={page.saveRefreshFailed ? actionAlert : undefined}
            tabIndex={page.saveRefreshFailed ? -1 : undefined}
          >
            {status === 'accepted'
              ? 'Action saved, but the updated details could not be loaded.'
              : page.readError}
          </div>
        )}
        {(rejected || uncertain) && (
          <div className="flash error" id="action-feedback" role="alert" ref={actionAlert} tabIndex={-1}>
            {rejected ? 'Action rejected. ' : ''}{message}
          </div>
        )}
        {status === 'reviewed' && (
          <div className="flash" id="action-feedback" role="status">
            Details reloaded. Check whether the action appears before submitting again.
          </div>
        )}
        {(page.readError || rejected || uncertain) && (
          <button type="button" className="reload-details" onClick={page.reviewLatest} disabled={page.loading || page.busy}>
            Reload details
          </button>
        )}
        {status === 'accepted' && !page.readError && (
          <div className="flash success" role="status">
            {message}
          </div>
        )}
        {introduction || (
          <section className="page-heading">
            <div>
              {eyebrow && <p className="eyebrow">{eyebrow}</p>}
              <h1>{title}</h1>
              {subtitle && <p>{subtitle}</p>}
            </div>
            {headingAction}
          </section>
        )}
        {sync && (
          <div
            className={sync.stale ? 'notice sync-status' : 'sync-status'}
            role={sync.stale ? 'status' : undefined}
          >
            {sync.stale && (
              <strong>
                {sync.message || 'Appointment data may be stale.'}
              </strong>
            )}
            <span>
              {sync.last_synced_at ? (
                <>
                  Last PMS sync:{' '}
                  <time dateTime={sync.last_synced_at}>
                    {formatInstant(
                      sync.last_synced_at,
                      clinic?.timezone || 'UTC',
                    )}
                  </time>
                  {' · '}
                  {clinic?.timezone || 'UTC'}
                </>
              ) : (
                'No successful PMS sync recorded.'
              )}
            </span>
          </div>
        )}
        {page.lastLoadedData || renderBeforeLoad ? children : page.loading && <p role="status">Loading…</p>}
      </main>
    </div>
  );
}

export function ResolutionSummary({ resolution, timezone }) {
  let label = 'Resolver not recorded';
  if (resolution?.actor) {
    if (resolution.kind === 'follow_up_resolved') label = 'Automatically closed';
    else if (resolution.actor === 'Patient') label = 'Confirmed by patient reply';
    else label = `Resolved by ${resolution.actor}`;
  }
  return (
    <div>
      <strong>{label}</strong>
      {resolution?.at && (
        <div className="card-meta">
          {formatInstant(resolution.at, timezone)}
        </div>
      )}
    </div>
  );
}
