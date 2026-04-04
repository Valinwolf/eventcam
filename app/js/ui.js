import {
  state,
  els,
  STORAGE_KEYS,
  MAX_HISTORY,
  readJson,
  cryptoRandomId,
  stringOrEmpty,
  normalizeEventCode,
  normalizePersonName,
  inferMediaTypeFromFilename,
} from './core.js';

export function showLoginView() {
  els.loginView?.classList.add('active');
  els.galleryView?.classList.remove('active');
}

export function showGalleryView() {
  els.loginView?.classList.remove('active');
  els.galleryView?.classList.add('active');
  els.profileNameInput.value = state.participantName;
  setLoginMessage('');
}

export function updateGalleryHeader() {
  els.galleryTitle.textContent = state.eventName || 'Gallery';

  const subtitleParts = [];
  if (state.eventCode) {
    subtitleParts.push(state.eventCode);
  }
  if (state.participantName) {
    subtitleParts.push(state.participantName);
  }
  els.gallerySubtitle.textContent = subtitleParts.join(' • ');
}

export function setBanner(message) {
  if (!els.eventBanner) {
    return;
  }

  if (!message) {
    els.eventBanner.classList.add('hidden');
    els.eventBanner.textContent = '';
    return;
  }

  els.eventBanner.textContent = message;
  els.eventBanner.classList.remove('hidden');
}

export function setLoginMessage(message) {
  if (els.loginMessage) {
    els.loginMessage.textContent = message || '';
  }
}

export function setLoginBusy(isBusy, message = '') {
  if (els.joinButton) {
    els.joinButton.disabled = isBusy;
    els.joinButton.textContent = isBusy ? 'Working...' : 'Join Event';
  }

  if (message) {
    setLoginMessage(message);
  } else if (!isBusy) {
    setLoginMessage('');
  }
}

export function badgeClassForStatus(status) {
  if (status === 'failed') return 'failed';
  if (status === 'uploading') return 'uploading';
  return 'uploaded';
}

export function statusLabelForStatus(status) {
  if (status === 'failed') return 'Failed';
  if (status === 'uploading') return 'Uploading';
  return 'Uploaded';
}

export function renderGallery(openMediaDialog) {
  if (!els.galleryGrid) {
    return;
  }

  els.galleryGrid.innerHTML = '';

  if (!state.media.length) {
    const empty = document.createElement('div');
    empty.className = 'muted';
    empty.textContent = 'No local media yet. Capture something or add files.';
    els.galleryGrid.appendChild(empty);
    return;
  }

  state.media.forEach((item, index) => {
    const card = document.createElement('article');
    card.className = 'gallery-item';
    card.addEventListener('click', () => openMediaDialog(index));

    const thumb = buildGalleryThumb(item);
    const meta = document.createElement('div');
    meta.className = 'gallery-meta';

    const name = document.createElement('strong');
    name.textContent = item.fileName || (item.type === 'video' ? 'Video' : 'Photo');

    const badges = document.createElement('div');
    badges.className = 'badges';

    const statusBadge = document.createElement('span');
    statusBadge.className = `badge ${badgeClassForStatus(item.status)}`;
    statusBadge.textContent = statusLabelForStatus(item.status);
    badges.appendChild(statusBadge);

    const typeBadge = document.createElement('span');
    typeBadge.className = 'badge';
    typeBadge.textContent = item.type === 'video' ? 'Video' : 'Photo';
    badges.appendChild(typeBadge);

    meta.appendChild(name);
    meta.appendChild(badges);

    if (item.error) {
      const err = document.createElement('div');
      err.className = 'muted';
      err.textContent = item.error;
      meta.appendChild(err);
    }

    card.appendChild(thumb);
    card.appendChild(meta);
    els.galleryGrid.appendChild(card);
  });
}

function buildGalleryThumb(item) {
  if (item.type === 'video') {
    const video = document.createElement('video');
    video.className = 'gallery-thumb';
    video.muted = true;
    video.playsInline = true;
    video.preload = 'metadata';
    video.src = item.previewUrl || item.remoteUrl || '';
    return video;
  }

  const img = document.createElement('img');
  img.className = 'gallery-thumb';
  img.loading = 'lazy';
  img.alt = item.fileName || 'Photo';
  img.src = item.previewUrl || item.remoteUrl || '';
  return img;
}

export function openMediaDialog(index) {
  const item = state.media[index];
  if (!item) {
    return;
  }

  state.currentMediaIndex = index;
  els.mediaDialogTitle.textContent = item.fileName || 'Media';
  els.mediaDialogBody.innerHTML = '';

  const source = item.remoteUrl || item.previewUrl || '';

  if (item.type === 'video') {
    const video = document.createElement('video');
    video.controls = true;
    video.playsInline = true;
    video.src = source;
    els.mediaDialogBody.appendChild(video);
  } else {
    const img = document.createElement('img');
    img.alt = item.fileName || 'Photo';
    img.src = source;
    els.mediaDialogBody.appendChild(img);
  }

  els.deleteMediaButton.disabled = !(item.id && item.controlToken);
  els.downloadMediaButton.disabled = !source;

  els.mediaDialog.showModal();
}

export function getActiveMediaItem() {
  return state.media[state.currentMediaIndex] || null;
}

export function getHistory() {
  const raw = readJson(STORAGE_KEYS.history, []);
  if (!Array.isArray(raw)) {
    return [];
  }

  return raw
    .map((item) => {
      if (!item || typeof item !== 'object') {
        return null;
      }

      return {
        id: stringOrEmpty(item.id) || cryptoRandomId(),
        eventCode: normalizeEventCode(item.eventCode || ''),
        eventName: stringOrEmpty(item.eventName),
        participantName: normalizePersonName(item.participantName || ''),
        guestId: stringOrEmpty(item.guestId),
        savedAt: stringOrEmpty(item.savedAt) || new Date().toISOString(),
      };
    })
    .filter(Boolean)
    .filter((item) => item.eventCode && item.participantName);
}

export function saveHistory(history) {
  localStorage.setItem(STORAGE_KEYS.history, JSON.stringify(history.slice(0, MAX_HISTORY)));
}

export function upsertHistoryEntry(entry) {
  const history = getHistory().filter((item) => {
    return !(
      item.eventCode === entry.eventCode &&
      item.participantName.toLowerCase() === entry.participantName.toLowerCase()
    );
  });

  history.unshift({
    id: cryptoRandomId(),
    eventCode: normalizeEventCode(entry.eventCode),
    eventName: stringOrEmpty(entry.eventName),
    participantName: normalizePersonName(entry.participantName),
    guestId: stringOrEmpty(entry.guestId),
    savedAt: new Date().toISOString(),
  });

  saveHistory(history);
  renderHistoryLists();
}

export function removeHistoryEntry(id) {
  const next = getHistory().filter((item) => item.id !== id);
  saveHistory(next);
  renderHistoryLists();
}

export function renderHistoryLists(onResume) {
  renderHistoryListInto(els.eventHistoryList, false, onResume);
  renderHistoryListInto(els.profileHistoryList, true, onResume);
}

function renderHistoryListInto(container, includeDeleteButton, onResume) {
  if (!container) {
    return;
  }

  const history = getHistory();
  container.innerHTML = '';

  if (!history.length) {
    const li = document.createElement('li');
    li.className = 'history-item';
    li.innerHTML = `<span class="muted">No recent events yet.</span>`;
    container.appendChild(li);
    return;
  }

  history.forEach((item) => {
    const li = document.createElement('li');
    li.className = 'history-item';

    const left = document.createElement('button');
    left.type = 'button';
    left.className = 'btn btn-secondary';
    left.style.flex = '1';
    left.style.textAlign = 'left';
    left.innerHTML = `
      <div class="history-code">${escapeHtml(item.eventCode)}</div>
      <div>${escapeHtml(item.participantName)}</div>
      <div class="muted">${escapeHtml(item.eventName || 'Saved session')}</div>
    `;
    left.addEventListener('click', () => onResume(item.id));
    li.appendChild(left);

    if (includeDeleteButton) {
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'btn btn-danger';
      remove.textContent = 'Remove';
      remove.addEventListener('click', () => {
        removeHistoryEntry(item.id);
      });
      li.appendChild(remove);
    }

    container.appendChild(li);
  });
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}