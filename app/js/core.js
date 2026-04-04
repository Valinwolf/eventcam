export const STORAGE_KEYS = {
  session: 'eventcam.session',
  history: 'eventcam.history',
};

export const MAX_HISTORY = 12;

export const state = {
  eventCode: '',
  eventName: '',
  eventStart: null,
  eventEnd: null,
  participantName: '',
  guestId: '',
  media: [],
  currentMediaIndex: -1,
  cameraStream: null,
  mediaRecorder: null,
  recordedChunks: [],
};

export const els = {
  loginView: document.getElementById('loginView'),
  galleryView: document.getElementById('galleryView'),

  loginForm: document.getElementById('loginForm'),
  eventCodeInput: document.getElementById('eventCodeInput'),
  participantNameInput: document.getElementById('participantNameInput'),
  joinButton: document.getElementById('joinButton'),
  loginMessage: document.getElementById('loginMessage'),

  eventHistoryList: document.getElementById('eventHistoryList'),
  profileHistoryList: document.getElementById('profileHistoryList'),

  galleryTitle: document.getElementById('galleryTitle'),
  gallerySubtitle: document.getElementById('gallerySubtitle'),
  eventBanner: document.getElementById('eventBanner'),

  profileButton: document.getElementById('profileButton'),
  logoutButton: document.getElementById('logoutButton'),

  takePhotoInput: document.getElementById('takePhotoInput'),
  recordVideoInput: document.getElementById('recordVideoInput'),
  fileInput: document.getElementById('fileInput'),

  takePhotoLabel: document.getElementById('takePhotoLabel'),
  recordVideoLabel: document.getElementById('recordVideoLabel'),
  addFilesLabel: document.getElementById('addFilesLabel'),
  captureHelpText: document.getElementById('captureHelpText'),

  retryUploadsButton: document.getElementById('retryUploadsButton'),

  saveAllButton: document.getElementById('saveAllButton'),
  galleryGrid: document.getElementById('galleryGrid'),

  profileDialog: document.getElementById('profileDialog'),
  profileNameInput: document.getElementById('profileNameInput'),
  saveProfileButton: document.getElementById('saveProfileButton'),
  clearHistoryButton: document.getElementById('clearHistoryButton'),

  mediaDialog: document.getElementById('mediaDialog'),
  mediaDialogTitle: document.getElementById('mediaDialogTitle'),
  mediaDialogBody: document.getElementById('mediaDialogBody'),
  closeMediaDialogButton: document.getElementById('closeMediaDialogButton'),
  downloadMediaButton: document.getElementById('downloadMediaButton'),
  deleteMediaButton: document.getElementById('deleteMediaButton'),
};

export function stringOrEmpty(value) {
  return typeof value === 'string' ? value : '';
}

export function nullableString(value) {
  const out = stringOrEmpty(value);
  return out || null;
}

export function normalizeEventCode(value) {
  return String(value || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9_-]/g, '');
}

export function normalizePersonName(value) {
  return String(value || '')
    .trim()
    .replace(/[<>:"/\\|?*\u0000-\u001F]/g, '')
    .replace(/\s+/g, ' ');
}

export function normalizeStatus(status) {
  if (status === 'uploaded' || status === 'failed' || status === 'uploading') {
    return status;
  }
  return 'uploaded';
}

export function cryptoRandomId() {
  if (window.crypto?.randomUUID) {
    return window.crypto.randomUUID();
  }

  return `tmp-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function readJson(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) {
      return fallback;
    }
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

export function createPreviewUrl(file) {
  try {
    return URL.createObjectURL(file);
  } catch {
    return '';
  }
}

export function revokeObjectUrlIfNeeded(url) {
  if (typeof url === 'string' && url.startsWith('blob:')) {
    URL.revokeObjectURL(url);
  }
}

export function inferMimeFromFile(file) {
  const type = String(file?.type || '').trim().toLowerCase();
  if (type) {
    return type;
  }

  const name = String(file?.name || '').toLowerCase();

  const byExt = [
    [/\.jpe?g$/i, 'image/jpeg'],
    [/\.png$/i, 'image/png'],
    [/\.webp$/i, 'image/webp'],
    [/\.gif$/i, 'image/gif'],
    [/\.heic$/i, 'image/heic'],
    [/\.heif$/i, 'image/heif'],
    [/\.avif$/i, 'image/avif'],
    [/\.mp4$/i, 'video/mp4'],
    [/\.mov$/i, 'video/quicktime'],
    [/\.webm$/i, 'video/webm'],
    [/\.3gp$/i, 'video/3gpp'],
    [/\.3g2$/i, 'video/3gpp2'],
    [/\.mkv$/i, 'video/x-matroska'],
    [/\.ogv$/i, 'video/ogg'],
  ];

  for (const [pattern, mime] of byExt) {
    if (pattern.test(name)) {
      return mime;
    }
  }

  return '';
}

export function classifyMime(mime) {
  const value = String(mime || '').toLowerCase();

  if (value.startsWith('image/')) {
    return 'photo';
  }

  if (value.startsWith('video/')) {
    return 'video';
  }

  return '';
}

export function inferMediaTypeFromFilename(value) {
  const lower = String(value || '').toLowerCase();
  if (/\.(mov|mp4|m4v|webm|3gp|3g2|mkv|ogv)$/i.test(lower)) {
    return 'video';
  }
  return 'photo';
}

export function defaultFileNameForType(type, extension = '') {
  const ext = extension ? `.${extension}` : type === 'video' ? '.mp4' : '.jpg';
  return type === 'video' ? `video-${Date.now()}${ext}` : `photo-${Date.now()}${ext}`;
}

export function extensionFromMime(mime) {
  const map = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'image/heic': 'heic',
    'image/heif': 'heif',
    'image/avif': 'avif',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'video/3gpp': '3gp',
    'video/3gpp2': '3g2',
    'video/x-matroska': 'mkv',
    'video/ogg': 'ogv',
  };

  return map[String(mime || '').toLowerCase()] || '';
}

export function normalizeMediaItem(item) {
  if (!item || typeof item !== 'object') {
    return null;
  }

  return {
    localId: stringOrEmpty(item.localId) || cryptoRandomId(),
    id: stringOrEmpty(item.id),
    fileName: stringOrEmpty(item.fileName || item.file),
    type: item.type === 'video' ? 'video' : 'photo',
    status: normalizeStatus(item.status),
    localFile: item.localFile instanceof File ? item.localFile : null,
    previewUrl: stringOrEmpty(item.previewUrl),
    remoteUrl: stringOrEmpty(item.remoteUrl),
    controlToken: stringOrEmpty(item.controlToken || item.control_token),
    createdAt: stringOrEmpty(item.createdAt) || new Date().toISOString(),
    error: stringOrEmpty(item.error),
  };
}

export function stripEphemeralMediaFields(item) {
  return {
    localId: item.localId,
    id: item.id,
    fileName: item.fileName,
    type: item.type,
    status: item.status,
    previewUrl: item.remoteUrl || item.previewUrl || '',
    remoteUrl: item.remoteUrl || '',
    controlToken: item.controlToken,
    createdAt: item.createdAt,
    error: item.error,
  };
}

export function getErrorMessage(error, fallback) {
  if (!error) {
    return fallback;
  }

  if (typeof error === 'string') {
    return error;
  }

  if (error instanceof Error && error.message) {
    return error.message;
  }

  return fallback;
}

export function delay(ms) {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

export function parseEventDate(value) {
  if (!value) {
    return null;
  }

  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function getEventPhase(eventStart, eventEnd, now = new Date()) {
  const start = parseEventDate(eventStart);
  const end = parseEventDate(eventEnd);

  if (start && now < start) {
    return 'upcoming';
  }

  if (end && now > end) {
    return 'ended';
  }

  return 'active';
}