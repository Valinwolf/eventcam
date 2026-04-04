import {
  state,
  els,
  extensionFromMime,
  inferMimeFromFile,
  getErrorMessage,
} from './core.js';
import { setBanner } from './ui.js';
import { stageAndUploadFile } from './media.js';

export async function openCamera() {
  if (state.cameraStream) {
    return;
  }

  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: { ideal: 'environment' },
      },
      audio: true,
    });

    state.cameraStream = stream;
    els.cameraPreview.srcObject = stream;
    els.cameraPreview.classList.remove('hidden');
    els.cameraControls.classList.remove('hidden');
    els.openCameraButton.disabled = true;
  } catch (error) {
    console.error(error);
    setBanner('Unable to open camera. Check camera permissions.');
  }
}

export function closeCamera() {
  if (state.mediaRecorder && state.mediaRecorder.state !== 'inactive') {
    state.mediaRecorder.stop();
  }

  if (state.cameraStream) {
    state.cameraStream.getTracks().forEach((track) => track.stop());
    state.cameraStream = null;
  }

  state.mediaRecorder = null;
  state.recordedChunks = [];

  if (els.cameraPreview) {
    els.cameraPreview.pause?.();
    els.cameraPreview.srcObject = null;
    els.cameraPreview.classList.add('hidden');
  }

  if (els.cameraControls) {
    els.cameraControls.classList.add('hidden');
  }

  if (els.openCameraButton) {
    els.openCameraButton.disabled = false;
  }

  if (els.stopVideoButton) {
    els.stopVideoButton.classList.add('hidden');
  }

  if (els.startVideoButton) {
    els.startVideoButton.classList.remove('hidden');
    els.startVideoButton.disabled = false;
  }

  if (els.takePhotoButton) {
    els.takePhotoButton.disabled = false;
  }
}

export async function takePhoto(openMediaDialog) {
  if (!state.cameraStream || !els.cameraPreview.videoWidth || !els.cameraPreview.videoHeight) {
    setBanner('Camera is not ready yet.');
    return;
  }

  const canvas = document.createElement('canvas');
  canvas.width = els.cameraPreview.videoWidth;
  canvas.height = els.cameraPreview.videoHeight;

  const ctx = canvas.getContext('2d');
  if (!ctx) {
    setBanner('Failed to capture photo.');
    return;
  }

  ctx.drawImage(els.cameraPreview, 0, 0, canvas.width, canvas.height);

  const blob = await new Promise((resolve) => {
    canvas.toBlob(resolve, 'image/jpeg', 0.92);
  });

  if (!(blob instanceof Blob)) {
    setBanner('Failed to create photo.');
    return;
  }

  const file = new File(
    [blob],
    `photo-${Date.now()}.jpg`,
    { type: 'image/jpeg', lastModified: Date.now() }
  );

  await stageAndUploadFile(file, openMediaDialog);
}

export async function startVideoRecording(openMediaDialog) {
  if (!state.cameraStream) {
    setBanner('Camera is not open.');
    return;
  }

  if (state.mediaRecorder && state.mediaRecorder.state !== 'inactive') {
    return;
  }

  const mimeType = pickSupportedRecordingMimeType();
  if (!mimeType) {
    setBanner('This browser does not support video recording here.');
    return;
  }

  state.recordedChunks = [];
  state.mediaRecorder = new MediaRecorder(state.cameraStream, { mimeType });

  state.mediaRecorder.addEventListener('dataavailable', (event) => {
    if (event.data && event.data.size > 0) {
      state.recordedChunks.push(event.data);
    }
  });

  state.mediaRecorder.addEventListener('stop', async () => {
    try {
      const blob = new Blob(state.recordedChunks, { type: mimeType });
      const detectedMime = inferMimeFromFile({ type: mimeType, name: `video.${extensionFromMime(mimeType)}` });
      const extension = extensionFromMime(detectedMime) || 'mp4';

      const file = new File(
        [blob],
        `video-${Date.now()}.${extension}`,
        { type: detectedMime || mimeType, lastModified: Date.now() }
      );

      await stageAndUploadFile(file, openMediaDialog);
    } catch (error) {
      console.error(error);
      setBanner(getErrorMessage(error, 'Failed to process recorded video.'));
    } finally {
      state.recordedChunks = [];
      if (els.stopVideoButton) {
        els.stopVideoButton.classList.add('hidden');
      }
      if (els.startVideoButton) {
        els.startVideoButton.classList.remove('hidden');
        els.startVideoButton.disabled = false;
      }
      if (els.takePhotoButton) {
        els.takePhotoButton.disabled = false;
      }
    }
  });

  state.mediaRecorder.start();

  if (els.stopVideoButton) {
    els.stopVideoButton.classList.remove('hidden');
  }
  if (els.startVideoButton) {
    els.startVideoButton.classList.add('hidden');
  }
  if (els.takePhotoButton) {
    els.takePhotoButton.disabled = true;
  }
}

export function stopVideoRecording() {
  if (state.mediaRecorder && state.mediaRecorder.state !== 'inactive') {
    state.mediaRecorder.stop();
  }
}

function pickSupportedRecordingMimeType() {
  const candidates = [
    'video/mp4;codecs=h264,aac',
    'video/mp4',
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
  ];

  for (const candidate of candidates) {
    if (window.MediaRecorder && MediaRecorder.isTypeSupported(candidate)) {
      return candidate;
    }
  }

  return '';
}