import React, { useEffect, useState } from 'react';
import { MAX_REPLY_LENGTH } from '../../shared/constants';
import { usePage } from '../../shared/usePage';
import { Frame } from '../../shared/ui';
import { formatInstant } from '../../shared/format';

function sameTextConversation(first, second) {
  return first.sender === second.sender && first.destination === second.destination;
}

function ReplyForm({ canSend, sending, locked, feedbackId, sendReply }) {
  const [draft, setDraft] = useState('');

  function submitReply(event) {
    event.preventDefault();
    sendReply(draft, () => setDraft(''));
  }

  return (
    <form className="panel patient-reply" onSubmit={submitReply} aria-describedby={feedbackId}>
      <label htmlFor="body">Your reply</label>
      <textarea
        id="body"
        required
        maxLength={MAX_REPLY_LENGTH}
        rows="3"
        value={draft}
        readOnly={locked}
        onChange={(event) => setDraft(event.target.value)}
        placeholder="Type any reply"
      />
      <button className="primary" disabled={!canSend}>
        {sending ? 'Sending reply…' : 'Send reply'}
      </button>
    </form>
  );
}

export default function Patient() {
  const [channel, setChannel] = useState('SMS');
  const [clinicId, setClinicId] = useState('');
  const [patientId, setPatientId] = useState('');
  const [selectedMessageToken, setSelectedMessageToken] = useState('');
  const [attempt, setAttempt] = useState(null);
  const [patientOptions, setPatientOptions] = useState([]);
  const optionsFlag = patientId ? '&include_patients=0' : '';
  const page = usePage(`/patient?clinic=${clinicId}&patient=${patientId}${optionsFlag}`);
  const awaitingReplyOutcome = ['uncertain', 'reviewed'].includes(page.submission.status);
  const canChangeConversation = !page.busy && !awaitingReplyOutcome;
  const data = page.data || {};
  const currentOptions = page.data?.patients;

  useEffect(() => {
    if (currentOptions) setPatientOptions(currentOptions);
  }, [currentOptions]);

  const patients = (currentOptions || patientOptions).filter(
    (patient) => patient.clinic_id === Number(clinicId),
  );
  const messages = (data.messages || []).filter(
    (message) =>
      message.clinic_id === Number(clinicId) &&
      message.patient_id === Number(patientId) &&
      message.channel === channel,
  );

  const conversations = [];
  for (const message of messages) {
    const alreadyListed = channel === 'SMS' && conversations.some(
      (conversation) => sameTextConversation(conversation, message),
    );
    if (!alreadyListed) conversations.push(message);
  }

  const selectedMessage = (!canChangeConversation && attempt?.receipt) || conversations.find(
    (message) => message.token === selectedMessageToken,
  ) || conversations[0];
  let thread = [];
  if (selectedMessage) {
    thread = channel === 'SMS'
      ? messages.filter((message) => sameTextConversation(message, selectedMessage))
      : [selectedMessage];
  }

  const threadTokens = new Set(thread.map((message) => message.token));
  const history = [
    ...thread.map((message) => ({
      ...message,
      id: message.token,
      from: 'Clinic reminder',
    })),
    ...(data.replies || [])
      .filter((reply) => threadTokens.has(reply.token))
      .map((reply) => ({ ...reply, from: 'Your reply' })),
  ].sort(
    (first, second) => Date.parse(first.created_at) - Date.parse(second.created_at),
  );

  function clearConversation() {
    setSelectedMessageToken('');
    setAttempt(null);
    page.clearSubmission();
  }

  function changeClinic(event) {
    setClinicId(event.target.value);
    setPatientId('');
    clearConversation();
  }

  function changePatient(event) {
    setPatientId(event.target.value);
    clearConversation();
  }

  function changeChannel(nextChannel) {
    if (nextChannel === channel) return;
    setChannel(nextChannel);
    clearConversation();
  }

  function changeConversation(event) {
    setSelectedMessageToken(event.target.value);
    setAttempt(null);
    page.clearSubmission();
  }

  function sendReply(draft, clearDraft) {
    if (!page.canSubmit) return;

    const sameAttempt = attempt?.receipt.token === selectedMessage.token && attempt.body === draft;
    const submission = sameAttempt ? attempt : { receipt: selectedMessage, body: draft, key: crypto.randomUUID() };
    setAttempt(submission);
    page.submit('/patient/messages/' + submission.receipt.token, {
      body: submission.body,
      key: submission.key,
    }, () => {
      setAttempt(null);
      clearDraft();
    });
  }

  return (
    <Frame
      introduction={
        <div className="patient-shell">
          {canChangeConversation && (
            <a className="back" href="/">
              ← Workspaces
            </a>
          )}
          <h1>Patient inbox</h1>
        </div>
      }
      page={page}
      area="patient"
    >
      <div className="patient-shell">
        <label htmlFor="inbox-clinic">Clinic</label>
        <select
          id="inbox-clinic"
          value={clinicId}
          disabled={!canChangeConversation}
          onChange={changeClinic}
        >
          <option value="">Choose a clinic</option>
          {page.lastLoadedData?.clinics.map((clinic) => (
            <option key={clinic.id} value={clinic.id}>
              {clinic.name}
            </option>
          ))}
        </select>
        {clinicId && (
          <>
            <label htmlFor="inbox-patient">Patient</label>
            <select
              id="inbox-patient"
              value={patientId}
              disabled={!canChangeConversation}
              onChange={changePatient}
            >
              <option value="">Choose a patient</option>
              {patients.map((patient) => (
                <option key={patient.id} value={patient.id}>
                  {patient.name}
                </option>
              ))}
            </select>
          </>
        )}
        {patientId && (
          <nav className="channel-tabs" aria-label="Message channel">
            {['SMS', 'Email'].map((item) => (
              <button
                key={item}
                aria-pressed={channel === item}
                disabled={!canChangeConversation}
                onClick={() => changeChannel(item)}
              >
                {item === 'SMS' ? 'Text messages' : 'Email'}
              </button>
            ))}
          </nav>
        )}
        {selectedMessage ? (
          <>
            {conversations.length > 1 && (
              <>
                <label htmlFor="example-message">
                  {channel === 'SMS' ? 'Text conversation' : 'Email reminder'}
                </label>
                <select
                  id="example-message"
                  value={selectedMessage.token}
                  disabled={!canChangeConversation}
                  onChange={changeConversation}
                >
                  {conversations.map((item) => (
                    <option key={item.token} value={item.token}>
                      {formatInstant(item.created_at, 'UTC')} UTC ·{' '}
                      {item.destination}
                    </option>
                  ))}
                </select>
              </>
            )}
            {selectedMessage.sent_to_guarantor && (
              <p className="notice">
                This reminder went to the patient's authorized adult.
              </p>
            )}
            <h2 className="message-history-title">Message history</h2>
            <ol className="message-history">
              {history.map((entry) => (
                <li
                  key={entry.id}
                  className={
                    'message-preview ' +
                    (entry.from === 'Your reply'
                      ? 'incoming'
                      : channel.toLowerCase())
                  }
                >
                  <span className="message-from">
                    {entry.from} · {formatInstant(entry.created_at, 'UTC')} UTC
                  </span>
                  <p>{entry.body}</p>
                </li>
              ))}
            </ol>
            <ReplyForm
              key={selectedMessage.token}
              canSend={page.canSubmit}
              sending={page.busy}
              locked={!canChangeConversation}
              feedbackId={page.feedbackId}
              sendReply={sendReply}
            />
          </>
        ) : (
          patientId && (page.loading ? (
            <p role="status">Loading messages…</p>
          ) : !page.readError && (
            <p>
              No simulated {channel === 'SMS' ? 'texts' : 'emails'} for this
              patient yet.
            </p>
          ))
        )}
      </div>
    </Frame>
  );
}
