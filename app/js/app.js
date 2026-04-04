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
  stripEphemeralMediaFields,
  revokeObjectUrlIfNeeded,
  getErrorMessage,
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
import {
  openCamera,
  closeCamera,
  takePhoto,
  startVideoRecording,
  stopVideoRecording,
} from './camera.js';

document.addEventListener('DOMContentLoaded', init);

function init() {
  bindEvents();
  hydrateFromStorage();
  renderHistoryLists(resumeHistoryEntry);
  renderGallery(openMediaDialog);
  updateGalleryHeader();
}

function bindEvents() {
  els.loginForm?.addEventListener('submit', onLoginSubmit);

  els.openCameraButton?.addEventListener('click', openCamera);
  els.takePhotoButton?.addEventListener('click', () => takePhoto(openMediaDialog));
  els.startVideoButton?.addEventListener('click', () => startVideoRecording(openMediaDialog));
  els.stopVideoButton?.addEventListener('click', stopVideoRecording);
  els.closeCameraButton?.addEventListener('click', closeCamera);

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
    closeCamera();
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

  state.eventCode = eventCode;
  state.participantName = participantName;
  state.media = [];

  setLoginBusy(true, 'Joining event...');

  try {
    const eventRes = await apiGet(`/api/event?id=${encodeURIComponent(eventCode)}`);

    if (!eventRes?.success || !eventRes?.event) {
      throw new Error('Event not found');
    }

    state.eventName = stringOrEmpty(eventRes.event.event_name);
    state.eventStart = nullableString(eventRes.event.event_start);
    state.eventEnd = nullableString(eventRes.event.event_end);

    const guestRes = await apiFetch('/api/guest', {
      method: 'PUT',
      body: JSON.stringify({ name: participantName }),
    });

    state.guestId = stringOrEmpty(guestRes?.id);
    if (!state.guestId) {
      throw new Error('Guest creation failed');
    }

    showGalleryView();
    updateGalleryHeader();
    persistSession();
    upsertHistoryEntry({
      eventCode: state.eventCode,
      eventName: state.eventName,
      participantName: state.participantName,
      guestId: state.guestId,
    });

    setBanner('');
    renderGallery(openMediaDialog);
  } catch (error) {
    console.error(error);
    setLoginMessage(getErrorMessage(error, 'Unable to join event.'));
  } finally {
    setLoginBusy(false);
  }
}

async function resumeHistoryEntry(id) {
  const entry = getHistory().find((item) => item.id === id);
  if (!entry) {
    setLoginMessage('Saved event not found.');
    return;
  }

  state.eventCode = entry.eventCode;
  state.participantName = entry.participantName;
  state.guestId = entry.guestId;
  state.media = [];

  els.eventCodeInput.value = state.eventCode;
  els.participantNameInput.value = state.participantName;

  setLoginBusy(true, 'Opening saved event...');

  try {
    const eventRes = await apiGet(`/api/event?id=${encodeURIComponent(state.eventCode)}`);
    if (!eventRes?.success || !eventRes?.event) {
      throw new Error('Event not found');
    }

    state.eventName = stringOrEmpty(eventRes.event.event_name);
    state.eventStart = nullableString(eventRes.event.event_start);
    state.eventEnd = nullableString(eventRes.event.event_end);

    showGalleryView();
    updateGalleryHeader();
    persistSession();

    await refreshCurrentGuestMedia(openMediaDialog);
  } catch (error) {
    console.error(error);
    setLoginMessage(getErrorMessage(error, 'Failed to open saved event.'));
    showLoginView();
  } finally {
    setLoginBusy(false);
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
  closeCamera();

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
  showLoginView();
}