import { useCallback, useEffect, useRef, useState } from 'react';
import { loadJson, postJson, RequestError } from './requests';

const REFRESH_INTERVAL_MS = 5 * 60 * 1000;
const NO_SUBMISSION = { status: 'idle' };

export function usePage(url, { autoRefresh = false } = {}) {
  const [snapshot, setSnapshot] = useState(null);
  const [read, setRead] = useState(null);
  const [submission, setSubmission] = useState(NO_SUBMISSION);
  const activeRead = useRef(null);
  const loading = read?.url !== url || read.status === 'loading';
  const readError = read?.url === url ? read.error : '';
  const saveRefreshFailed = Boolean(readError && read.afterSave);
  const busy = submission.status === 'saving';

  const refresh = useCallback(async ({ afterSave = false } = {}) => {
    activeRead.current?.abort();
    const controller = new AbortController();
    activeRead.current = controller;
    setRead({ url, status: 'loading' });

    try {
      const data = await loadJson(url, controller.signal);
      if (controller.signal.aborted) return false;
      setSnapshot({ url, data });
      setRead({ url, status: 'ready' });
      return true;
    } catch (error) {
      if (controller.signal.aborted) return false;
      if (!(error instanceof RequestError)) throw error;
      setRead({ url, status: 'failed', error: error.message, afterSave });
      return false;
    }
  }, [url]);

  useEffect(() => {
    setSubmission(NO_SUBMISSION);
    refresh();
    return () => activeRead.current?.abort();
  }, [refresh]);

  useEffect(() => {
    if (!autoRefresh || busy) return;

    const timer = window.setInterval(() => {
      if (!document.hidden) refresh();
    }, REFRESH_INTERVAL_MS);
    return () => window.clearInterval(timer);
  }, [autoRefresh, busy, refresh]);

  const data = snapshot?.url === url ? snapshot.data : null;
  const canSubmit = Boolean(data) && !snapshot.needsRefresh && !busy && !readError && submission.status !== 'uncertain';
  const feedbackId = ['rejected', 'uncertain', 'reviewed'].includes(submission.status)
    ? 'action-feedback'
    : undefined;

  function requireFreshDetails() {
    setSnapshot((current) => current?.url === url ? { ...current, needsRefresh: true } : current);
  }

  async function submit(target, fields, afterSuccess) {
    if (!canSubmit) return;
    // A background read may have started before this write. Keep the submitted view stable.
    activeRead.current?.abort();
    setRead({ url, status: 'ready' });
    setSubmission({ status: 'saving' });

    let result;
    try {
      result = await postJson(target, fields);
    } catch (error) {
      if (!(error instanceof RequestError)) {
        setSubmission(NO_SUBMISSION);
        throw error;
      }
      if (!error.rejected) requireFreshDetails();
      setSubmission({ status: error.rejected ? 'rejected' : 'uncertain', message: error.message });
      return;
    }

    if (result.path) {
      window.location.assign(result.path);
      return;
    }

    // A successful POST is final even if reading the updated record fails.
    requireFreshDetails();
    setSubmission({ status: 'accepted', message: result.message });
    afterSuccess?.();
    await refresh({ afterSave: true });
  }

  async function reviewLatest() {
    if (await refresh()) {
      setSubmission((current) => current.status === 'uncertain'
        ? { ...current, status: 'reviewed' }
        : current);
    }
  }

  return {
    data,
    lastLoadedData: snapshot?.data,
    readError,
    saveRefreshFailed,
    loading,
    busy,
    canSubmit,
    submission,
    feedbackId,
    submit,
    reviewLatest,
    clearSubmission: () => setSubmission(NO_SUBMISSION),
  };
}
