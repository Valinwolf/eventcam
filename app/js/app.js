import { apiFetch, apiGet } from './api.js';
import {
  state,
  els,
  STORAGE_KEYS,
  readJson,
  normalizeEventCode,
  normalizePersonName,
  nullableString,
  stringOrEmpty,
  normalizeMediaItem,
  revokeObjectUrlIfNeeded,
  getErrorMessage,
  getEventPhase,
} from './core.js';
import {
  showLoginView,
  showGalleryView,
  updateGalleryHeader,
  setBanner,
  setLoginBusy,
  setLoginMessage,
  renderGallery,
  openMediaDialog,
  getActiveMediaItem,
  renderHistoryLists,
  getHistory,
  upsertHistoryEntry,
} from './ui.js';
import {
  persistSession,
  clearSession,
  refreshCurrentGuestMedia,
  onFilesSelected,
  retryFailedUploads,
  downloadActiveMedia,
  saveAllMedia,
  deleteActiveMedia,
} from './media.js';

document.addEventListener('DOMContentLoaded', init);

function init() {
  bindEvents();

  try {
    hydrateFromStorage();
  } catch (error) {
    console.error('Hydrate failed:', error);
    localStorage.removeItem(STORAGE_KEYS.session);
    showLoginView();
  }

  renderHistoryLists(resumeHistoryEntry);
  renderGallery(openMediaDialog);
  updateGalleryHeader();
  updateCaptureAvailability();
}

function bindEvents() {
  els.loginForm?.addEventListener('submit', onLoginSubmit);

  els.takePhotoInput?.addEventListener('change', (event) => onFilesSelected(event, openMediaDialog));
  els.recordVideoInput?.addEventListener('change', (event) => onFilesSelected(event, openMediaDialog));
  els.fileInput?.addEventListener('change', (event) => onFilesSelected(event, openMediaDialog));

  els.retryUploadsButton?.addEventListener('click', () => retryFailedUploads(openMediaDialog));
  els.saveAllButton?.addEventListener('click', saveAllMedia);

  els.profileButton?.addEventListener('click', openProfileDialog);
  els.logoutButton?.addEventListener('click', logout);

  els.saveProfileButton?.addEventListener('click', saveProfileName);
  els.clearHistoryButton?.addEventListener('click', clearHistory);

  els.closeMediaDialogButton?.addEventListener('click', () => {
    els.mediaDialog?.close();
  });

  els.downloadMediaButton?.addEventListener('click', () => downloadActiveMedia(getActiveMediaItem));
  els.deleteMediaButton?.addEventListener('click', () => deleteActiveMedia(getActiveMediaItem, openMediaDialog));

  els.mediaDialog?.addEventListener('click', (event) => {
    const rect = els.mediaDialog.getBoundingClientRect();
    const clickedInDialog =
      rect.top <= event.clientY &&
      event.clientY <= rect.top + rect.height &&
      rect.left <= event.clientX &&
      event.clientX <= rect.left + rect.width;

    if (!clickedInDialog) {
      els.mediaDialog.close();
    }
  });

  window.addEventListener('beforeunload', () => {
    persistSession();
  });
}

function hydrateFromStorage() {
  const session = readJson(STORAGE_KEYS.session, null);

  if (!session || typeof session !== 'object') {
    showLoginView();
    return;
  }

  state.eventCode = normalizeEventCode(session.eventCode || '');
  state.eventName = stringOrEmpty(session.eventName);
  state.eventStart = nullableString(session.eventStart);
  state.eventEnd = nullableString(session.eventEnd);
  state.participantName = stringOrEmpty(session.participantName);
  state.guestId = stringOrEmpty(session.guestId);
  state.media = Array.isArray(session.media)
    ? session.media.map(normalizeMediaItem).filter(Boolean)
    : [];

  els.eventCodeInput.value = state.eventCode;
  els.participantNameInput.value = state.participantName;

  if (state.eventCode && state.participantName && state.guestId) {
    showGalleryView();
    updateGalleryHeader();
    updateCaptureAvailability();
    void refreshCurrentGuestMedia(openMediaDialog);
  } else {
    showLoginView();
  }
}

async function onLoginSubmit(event) {
  event.preventDefault();

  const eventCode = normalizeEventCode(els.eventCodeInput.value);
  const participantName = normalizePersonName(els.participantNameInput.value);

  if (!eventCode) {
    setLoginMessage('Please enter a valid event code.');
    return;
  }

  if (!participantName) {
    setLoginMessage('Please enter your name.');
    return;
  }

  setLoginBusy(true, 'Joining event...');
  setBanner('');

  try {
    const eventRes = await apiGet(`/api/event?id=${encodeURIComponent(eventCode)}`);

    if (!eventRes?.success || !eventRes?.event) {
      throw new Error('Event not found');
    }

    const guestRes = await apiFetch('/api/guest', {
      method: 'PUT',
      body: JSON.stringify({ name: participantName }),
    });

    const guestId = stringOrEmpty(guestRes?.id);
    if (!guestId) {
      throw new Error('Guest creation failed');
    }

    state.eventCode = eventCode;
    state.eventName = stringOrEmpty(eventRes.event.event_name);
    state.eventStart = nullableString(eventRes.event.event_start);
    state.eventEnd = nullableString(eventRes.event.event_end);
    state.participantName = participantName;
    state.guestId = guestId;
    state.media = [];
    state.currentMediaIndex = -1;

    persistSession();
    upsertHistoryEntry({
      eventCode: state.eventCode,
      eventName: state.eventName,
      participantName: state.participantName,
      guestId: state.guestId,
    });

    showGalleryView();
    updateGalleryHeader();
    updateCaptureAvailability();
    renderGallery(openMediaDialog);

    setLoginBusy(false);
    setLoginMessage('');

    void refreshCurrentGuestMedia(openMediaDialog);
  } catch (error) {
    console.error('Join failed:', error);
    setLoginBusy(false);
    setLoginMessage(getErrorMessage(error, 'Unable to join event.'));
    showLoginView();
  }
}

async function resumeHistoryEntry(id) {
  const entry = getHistory().find((item) => item.id === id);
  if (!entry) {
    setLoginMessage('Saved event not found.');
    return;
  }

  setLoginBusy(true, 'Opening saved event...');

  try {
    const eventRes = await apiGet(`/api/event?id=${encodeURIComponent(entry.eventCode)}`);
    if (!eventRes?.success || !eventRes?.event) {
      throw new Error('Event not found');
    }

    state.eventCode = entry.eventCode;
    state.eventName = stringOrEmpty(eventRes.event.event_name);
    state.eventStart = nullableString(eventRes.event.event_start);
    state.eventEnd = nullableString(eventRes.event.event_end);
    state.participantName = entry.participantName;
    state.guestId = entry.guestId;
    state.media = [];
    state.currentMediaIndex = -1;

    els.eventCodeInput.value = state.eventCode;
    els.participantNameInput.value = state.participantName;

    persistSession();
    showGalleryView();
    updateGalleryHeader();
    updateCaptureAvailability();
    renderGallery(openMediaDialog);

    await refreshCurrentGuestMedia(openMediaDialog);

    setLoginBusy(false);
    setLoginMessage('');
  } catch (error) {
    console.error('Resume failed:', error);
    setLoginBusy(false);
    setLoginMessage(getErrorMessage(error, 'Failed to open saved event.'));
    showLoginView();
  }
}

function updateCaptureAvailability() {
  const phase = getEventPhase(state.eventStart, state.eventEnd);

  const allLabels = [
    els.takePhotoLabel,
    els.recordVideoLabel,
    els.addFilesLabel,
  ];

  allLabels.forEach((label) => {
    if (!label) {
      return;
    }
    label.classList.remove('disabled');
    label.removeAttribute('aria-disabled');
  });

  if (phase === 'upcoming') {
    setBanner('This event has not started yet. Uploads will become available when the event begins.');
    allLabels.forEach((label) => {
      if (!label) return;
      label.classList.add('disabled');
      label.setAttribute('aria-disabled', 'true');
    });
    if (els.captureHelpText) {
      els.captureHelpText.textContent = 'Uploads are not available until the event starts.';
    }
    return;
  }

  if (phase === 'ended') {
    setBanner('This event has ended. New uploads are closed.');
    allLabels.forEach((label) => {
      if (!label) return;
      label.classList.add('disabled');
      label.setAttribute('aria-disabled', 'true');
    });
    if (els.captureHelpText) {
      els.captureHelpText.textContent = 'This event is no longer accepting uploads.';
    }
    return;
  }

  setBanner('');
  if (els.captureHelpText) {
    els.captureHelpText.textContent = 'Use your device camera or choose files from your device.';
  }
}

function openProfileDialog() {
  els.profileNameInput.value = state.participantName;
  renderHistoryLists(resumeHistoryEntry);
  els.profileDialog.showModal();
}

function saveProfileName() {
  const nextName = normalizePersonName(els.profileNameInput.value);
  if (!nextName) {
    return;
  }

  state.participantName = nextName;
  els.participantNameInput.value = nextName;
  updateGalleryHeader();
  persistSession();
  upsertHistoryEntry({
    eventCode: state.eventCode,
    eventName: state.eventName,
    participantName: state.participantName,
    guestId: state.guestId,
  });
  els.profileDialog.close();
}

function clearHistory() {
  const confirmed = window.confirm('Clear all saved event history?');
  if (!confirmed) {
    return;
  }

  localStorage.setItem(STORAGE_KEYS.history, JSON.stringify([]));
  renderHistoryLists(resumeHistoryEntry);
}

function logout() {
  state.eventCode = '';
  state.eventName = '';
  state.eventStart = null;
  state.eventEnd = null;
  state.participantName = '';
  state.guestId = '';
  state.media.forEach((item) => revokeObjectUrlIfNeeded(item.previewUrl));
  state.media = [];
  state.currentMediaIndex = -1;

  clearSession();

  els.eventCodeInput.value = '';
  els.participantNameInput.value = '';
  setBanner('');
  renderGallery(openMediaDialog);
  updateCaptureAvailability();
  showLoginView();
}