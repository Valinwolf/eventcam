import { apiFetch, apiGet } from './api.js';
import {
  state,
  els,
  normalizeMediaItem,
  stringOrEmpty,
  createPreviewUrl,
  revokeObjectUrlIfNeeded,
  inferMimeFromFile,
  classifyMime,
  inferMediaTypeFromFilename,
  defaultFileNameForType,
  getErrorMessage,
  delay,
  stripEphemeralMediaFields,
} from './core.js';
import { renderGallery, setBanner } from './ui.js';

export function persistSession() {
  const payload = {
    eventCode: state.eventCode,
    eventName: state.eventName,
    eventStart: state.eventStart,
    eventEnd: state.eventEnd,
    participantName: state.participantName,
    guestId: state.guestId,
    media: state.media.map(stripEphemeralMediaFields),
  };

  localStorage.setItem('eventcam.session', JSON.stringify(payload));
}

export function clearSession() {
  localStorage.removeItem('eventcam.session');
}

export async function refreshCurrentGuestMedia(openMediaDialog) {
  if (!state.eventCode || !state.guestId) {
    return;
  }

  try {
    const result = await apiGet(
      `/api/media?event_code=${encodeURIComponent(state.eventCode)}&id=${encodeURIComponent(state.guestId)}`
    );

    const serverItems = Array.isArray(result?.media) ? result.media : [];
    state.media = mergeServerMediaIntoLocal(serverItems);
    renderGallery(openMediaDialog);
    persistSession();
  } catch (error) {
    const message = getErrorMessage(error, '');
    if (message && !/Guest not found/i.test(message)) {
      console.warn('Failed to refresh media:', message);
    }
  }
}

function mergeServerMediaIntoLocal(serverItems) {
  const existing = [...state.media];
  const normalizedServer = serverItems
    .map((item) =>
      normalizeMediaItem({
        id: stringOrEmpty(item.id),
        fileName: stringOrEmpty(item.file),
        remoteUrl: stringOrEmpty(item.url),
        previewUrl: stringOrEmpty(item.url),
        status: 'uploaded',
        type: inferMediaTypeFromFilename(item.file || item.url),
        controlToken: findControlTokenById(stringOrEmpty(item.id)),
      })
    )
    .filter(Boolean);

  normalizedServer.forEach((serverItem) => {
    const idx = existing.findIndex((localItem) => localItem.id && localItem.id === serverItem.id);

    if (idx >= 0) {
      const local = existing[idx];
      existing[idx] = normalizeMediaItem({
        ...local,
        ...serverItem,
        localFile: local.localFile || null,
        previewUrl: local.previewUrl || serverItem.previewUrl,
        status: 'uploaded',
      });
    } else {
      existing.unshift(serverItem);
    }
  });

  return existing
    .map(normalizeMediaItem)
    .filter(Boolean)
    .sort((a, b) => {
      const aTime = Date.parse(a.createdAt || 0) || 0;
      const bTime = Date.parse(b.createdAt || 0) || 0;
      return bTime - aTime;
    });
}

function findControlTokenById(id) {
  const found = state.media.find((item) => item.id === id);
  return found?.controlToken || '';
}

export async function onFilesSelected(event, openMediaDialog) {
  const files = Array.from(event.target.files || []);
  if (!files.length) {
    return;
  }

  for (const file of files) {
    await stageAndUploadFile(file, openMediaDialog);
  }

  event.target.value = '';
}

export async function stageAndUploadFile(file, openMediaDialog) {
  const detectedMime = inferMimeFromFile(file);
  const mediaType = classifyMime(detectedMime);

  if (!mediaType || !detectedMime) {
    setBanner(`Unsupported file type: ${file.type || file.name}`);
    return;
  }

  const item = normalizeMediaItem({
    localId: crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`,
    id: '',
    fileName: file.name || defaultFileNameForType(mediaType),
    type: mediaType,
    status: 'uploading',
    localFile: file,
    previewUrl: createPreviewUrl(file),
    remoteUrl: '',
    controlToken: '',
    createdAt: new Date().toISOString(),
    error: '',
  });

  state.media.unshift(item);
  renderGallery(openMediaDialog);
  persistSession();

  await uploadMediaItem(item.localId, openMediaDialog);
}

export async function uploadMediaItem(localId, openMediaDialog) {
  const item = state.media.find((entry) => entry.localId === localId);
  if (!item || !item.localFile) {
    return;
  }

  try {
    const detectedMime = inferMimeFromFile(item.localFile);
    if (!detectedMime) {
      throw new Error('Could not determine file type');
    }

    const reserve = await apiFetch('/api/media', {
      method: 'PUT',
      body: JSON.stringify({
        event_code: state.eventCode,
        guest_id: state.guestId,
        mime: detectedMime,
      }),
    });

    const id = stringOrEmpty(reserve?.id);
    const controlToken = stringOrEmpty(reserve?.control_token);
    const upload = reserve?.upload;

    if (!id || !upload?.url || !upload?.method) {
      throw new Error('Upload reservation failed');
    }

    updateMediaItem(localId, { id, controlToken }, openMediaDialog);

    await uploadFileToSignedTarget(item.localFile, upload);

    await apiFetch('/api/media', {
      method: 'PATCH',
      body: JSON.stringify({
        id,
        status: 'uploaded',
      }),
    });

    const remoteUrl = await resolveMediaUrl(id, item);
    updateMediaItem(localId, {
      status: 'uploaded',
      remoteUrl,
      error: '',
    }, openMediaDialog);
  } catch (error) {
    console.error(error);

    const current = state.media.find((entry) => entry.localId === localId);
    if (current?.id) {
      try {
        await apiFetch('/api/media', {
          method: 'PATCH',
          body: JSON.stringify({
            id: current.id,
            status: 'failed',
            reason: getErrorMessage(error, 'Upload failed'),
          }),
        });
      } catch (patchError) {
        console.warn('Failed to patch media as failed:', patchError);
      }
    }

    updateMediaItem(localId, {
      status: 'failed',
      error: getErrorMessage(error, 'Upload failed'),
    }, openMediaDialog);

    setBanner(getErrorMessage(error, 'Upload failed.'));
  }
}

async function resolveMediaUrl(id, fallbackItem) {
  try {
    const result = await apiGet(
      `/api/media?event_code=${encodeURIComponent(state.eventCode)}&id=${encodeURIComponent(state.guestId)}`
    );

    const media = Array.isArray(result?.media) ? result.media : [];
    const match = media.find((entry) => stringOrEmpty(entry.id) === id);

    if (match?.url) {
      return String(match.url);
    }
  } catch (error) {
    console.warn('Could not resolve uploaded media URL:', error);
  }

  return fallbackItem.remoteUrl || fallbackItem.previewUrl || '';
}

async function uploadFileToSignedTarget(file, upload) {
  const headers = new Headers();
  const headerMap = upload.headers && typeof upload.headers === 'object' ? upload.headers : {};

  Object.entries(headerMap).forEach(([key, value]) => {
    if (typeof value === 'string' && value !== '') {
      headers.set(key, value);
    }
  });

  const response = await fetch(upload.url, {
    method: upload.method,
    headers,
    body: file,
  });

  if (!response.ok) {
    throw new Error(`Direct upload failed (${response.status})`);
  }
}

function updateMediaItem(localId, patch, openMediaDialog) {
  const index = state.media.findIndex((entry) => entry.localId === localId);
  if (index < 0) {
    return;
  }

  state.media[index] = normalizeMediaItem({
    ...state.media[index],
    ...patch,
  });

  renderGallery(openMediaDialog);
  persistSession();
}

export async function retryFailedUploads(openMediaDialog) {
  const failed = state.media.filter((item) => item.status === 'failed' && item.localFile);
  if (!failed.length) {
    setBanner('No failed uploads to retry.');
    return;
  }

  setBanner(`Retrying ${failed.length} failed upload${failed.length === 1 ? '' : 's'}...`);

  for (const item of failed) {
    updateMediaItem(item.localId, { status: 'uploading', error: '' }, openMediaDialog);
    await uploadMediaItem(item.localId, openMediaDialog);
  }

  setBanner('');
}

export async function downloadActiveMedia(getActiveMediaItem) {
  const item = getActiveMediaItem();
  if (!item) {
    return;
  }

  const url = item.remoteUrl || item.previewUrl;
  if (!url) {
    return;
  }

  await downloadUrl(url, item.fileName || (item.type === 'video' ? 'video' : 'photo'));
}

export async function saveAllMedia() {
  const downloadable = state.media.filter((item) => (item.remoteUrl || item.previewUrl));
  if (!downloadable.length) {
    setBanner('Nothing to save yet.');
    return;
  }

  for (const item of downloadable) {
    const url = item.remoteUrl || item.previewUrl;
    await downloadUrl(url, item.fileName || (item.type === 'video' ? 'video' : 'photo'));
    await delay(150);
  }
}

export async function deleteActiveMedia(getActiveMediaItem, openMediaDialog) {
  const item = getActiveMediaItem();
  if (!item || !item.id || !item.controlToken) {
    return;
  }

  const confirmed = window.confirm(`Delete ${item.fileName || 'this media'}?`);
  if (!confirmed) {
    return;
  }

  try {
    await apiFetch(
      `/api/media?id=${encodeURIComponent(item.id)}&token=${encodeURIComponent(item.controlToken)}`,
      { method: 'DELETE' }
    );

    revokeObjectUrlIfNeeded(item.previewUrl);

    state.media.splice(state.currentMediaIndex, 1);
    state.currentMediaIndex = -1;
    persistSession();
    renderGallery(openMediaDialog);
    els.mediaDialog.close();
  } catch (error) {
    console.error(error);
    setBanner(getErrorMessage(error, 'Failed to delete media.'));
  }
}

async function downloadUrl(url, fileName) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Download failed (${response.status})`);
  }

  const blob = await response.blob();
  const objectUrl = URL.createObjectURL(blob);

  const anchor = document.createElement('a');
  anchor.href = objectUrl;
  anchor.download = fileName || 'download';
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();

  setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
}