// Browser-safe helpers for the extractor page: video decode and small file/format utilities.
// Nothing here touches the DOM at import time (only inside function bodies), so this module can
// be imported from Node for a smoke test even though `decodeFrames` and `downloadText` only work
// in a browser when actually called.

/** Wait for one event on `el`, rejecting on the element's own 'error' event or a timeout. */
function waitFor(el, event, { timeout = 20000, describeError } = {}) {
  return new Promise((resolve, reject) => {
    const cleanup = () => { el.removeEventListener(event, onEvent); el.removeEventListener('error', onError); clearTimeout(timer); };
    const onEvent = () => { cleanup(); resolve(); };
    const onError = () => { cleanup(); reject(describeError ? describeError() : new Error(`"${event}" failed`)); };
    const timer = setTimeout(() => { cleanup(); reject(new Error(`timed out waiting for "${event}"`)); }, timeout);
    el.addEventListener(event, onEvent, { once: true });
    el.addEventListener('error', onError, { once: true });
  });
}

/** A friendly message for a video element that failed to decode, with a guess at why. */
function decodeErrorMessage(video, file) {
  const codeNames = { 1: 'aborted', 2: 'network error', 3: 'decode error', 4: 'format not supported' };
  const code = video.error?.code;
  const reason = code ? ` (${codeNames[code] ?? `code ${code}`})` : '';
  return new Error(
    `This browser could not decode "${file.name}"${reason}. If the recording is HEVC/H.265 — common for `
    + `iPhone recordings that have not been re-encoded — try AirDropping the original to a Mac or opening `
    + `it on the iPhone itself (Safari decodes HEVC natively there), or re-export it as H.264 (WhatsApp and `
    + `Clipchamp both do this automatically). You can also run "node scripts/extract.mjs <file>" from a `
    + `checkout instead.`,
  );
}

/**
 * Decode `file` (a video Blob/File) to one frame every `1/fps` seconds, as an async generator of
 * `{ index, time, label, image }` with `image` an ImageData at the video's natural size — no
 * downscaling. Frames are pulled lazily: nothing after the current frame decodes until the
 * consumer asks for the next one.
 *
 * `onFrame` is called with `{ phase: 'start', width, height, duration, totalEstimate }` once
 * metadata is known (duration/totalEstimate are null when the file's duration cannot be read),
 * then `{ phase: 'frame', frame }` for each frame, then `{ phase: 'end' }`. It is a side channel
 * for progress UI; the generator's own yields are the source of truth for frame data.
 *
 * This is the one place video decode happens, so callers get one clear failure mode instead of
 * scattered try/catches around the various things a `<video>` element can do wrong.
 */
export async function* decodeFrames(file, fps, onFrame = () => {}) {
  const video = document.createElement('video');
  video.muted = true;
  video.playsInline = true;
  video.preload = 'auto';
  const url = URL.createObjectURL(file);
  try {
    video.src = url;
    await waitFor(video, 'loadedmetadata', { describeError: () => decodeErrorMessage(video, file) });
    if (!video.videoWidth || !video.videoHeight) {
      throw new Error(`This browser read "${file.name}"'s metadata but reports a 0×0 video, which usually means the codec is not supported here. Try a different browser or device, or re-export as H.264.`);
    }
    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const duration = Number.isFinite(video.duration) ? video.duration : null;
    onFrame({ phase: 'start', width: video.videoWidth, height: video.videoHeight, duration, totalEstimate: duration !== null ? Math.ceil(duration * fps) + 1 : null });

    const step = 1 / fps;
    // Start a hair after 0: setting currentTime to the position the element is already at does
    // not fire 'seeked' in every browser, and the first frame of a recording is the same screen.
    let index = 0, t = 0.05, lastActual = -1, stuck = 0;
    // Some recordings (seen on the iPad fixture) report NaN/Infinity duration; keep seeking until
    // a seek fails, the video reports ended, or two seeks in a row land on the same time (the
    // video has clamped to its real end and stopped moving).
    while (duration === null || t <= duration + step / 2) {
      video.currentTime = t;
      try {
        await waitFor(video, 'seeked', { describeError: () => decodeErrorMessage(video, file) });
      } catch {
        break;
      }
      if (video.ended) break;
      if (Math.abs(video.currentTime - lastActual) < step / 4) {
        stuck++;
        if (stuck >= 2) break;
      } else {
        stuck = 0;
      }
      lastActual = video.currentTime;
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const frame = { index, time: video.currentTime, label: `t=${video.currentTime.toFixed(1)}s`, image };
      onFrame({ phase: 'frame', frame });
      yield frame;
      index++;
      t += step;
      if (duration === null && index > 20000) break; // safety valve if a duration can never be pinned down
    }
    if (index === 0) throw new Error(`No frames could be decoded from "${file.name}". The browser accepted the file but never produced a picture, which usually means the codec is not supported here; see the notes on HEVC below.`);
    onFrame({ phase: 'end' });
  } finally {
    URL.revokeObjectURL(url);
  }
}

/** `some-recording.mp4` -> `some-recording.pokegenie.csv`, matching the CLI's naming. */
export function csvFilename(file) {
  return `${file.name.replace(/\.[^.]+$/, '')}.pokegenie.csv`;
}

/** `some-recording.mp4` -> `some-recording.review.json`. */
export function reviewFilename(file) {
  return `${file.name.replace(/\.[^.]+$/, '')}.review.json`;
}

/** Trigger a browser download of `text` as `filename`. */
export function downloadText(text, filename, type = 'text/plain') {
  const blob = new Blob([text], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/** `125.4` seconds -> `2:05`. */
export function formatElapsed(seconds) {
  const s = Math.max(0, Math.round(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
