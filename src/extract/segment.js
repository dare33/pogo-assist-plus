// Split a frame sequence into "one Pokémon on screen" segments. A swipe between two Pokémon makes
// the header and name band change sharply for a few frames; while the user pauses, those bands
// are still even when the sprite animates. So the signature covers only the CP band and the name
// band, and a segment is the run of frames between two spikes.

import { lumaAt } from './image.js';

// Bands as fractions of the content rect; wide enough to cover the iPhone and iPad layouts
// (name at 42% on iPhone, 52% on iPad) and to exclude the sprite on both.
export const SIGNATURE_BANDS = [
  { fy: 0.0, fh: 0.12 },
  { fy: 0.36, fh: 0.22 },
];

/**
 * Downsampled luma of the signature bands: `cols` samples across x 10–90% of the rect and one
 * sample per `rowStep` fraction of the rect height. Cheap, and the same on every device.
 */
export function signature(img, rect, { cols = 40, rowStep = 0.01, bands = SIGNATURE_BANDS } = {}) {
  const out = [];
  for (const band of bands) {
    for (let fy = band.fy; fy < band.fy + band.fh; fy += rowStep) {
      const y = Math.min(img.height - 1, Math.round(rect.y + fy * rect.h));
      for (let c = 0; c < cols; c++) {
        const x = Math.min(img.width - 1, Math.round(rect.x + (0.1 + 0.8 * (c + 0.5) / cols) * rect.w));
        out.push(lumaAt(img, x, y));
      }
    }
  }
  return Float32Array.from(out);
}

/** Mean absolute difference between two signatures of the same length. */
export function signatureDiff(a, b) {
  let d = 0;
  for (let i = 0; i < a.length; i++) d += Math.abs(a[i] - b[i]);
  return a.length ? d / a.length : 0;
}

/** Diff of each frame against the previous one; the first frame is 0. */
export function diffSeries(signatures) {
  return signatures.map((s, i) => (i === 0 ? 0 : signatureDiff(s, signatures[i - 1])));
}

/**
 * Segments from the diff series. A frame with diff > `swipe` ends the current segment; frames with
 * diff <= `settled` are the ones worth reading. Segments with no settled frame are dropped (a
 * swipe that never paused). Each segment lists frame indices.
 */
export function segments(diffs, { swipe = 12, settled = 4, minSettled = 1 } = {}) {
  const out = [];
  let cur = null;
  for (let i = 0; i < diffs.length; i++) {
    const d = diffs[i];
    if (d > swipe) {
      if (cur) { out.push(cur); cur = null; }
      continue;
    }
    if (!cur) cur = { start: i, end: i, frames: [], settled: [] };
    cur.end = i;
    cur.frames.push(i);
    if (d <= settled) cur.settled.push(i);
  }
  if (cur) out.push(cur);
  return out.filter((s) => s.settled.length >= minSettled);
}

/**
 * The `n` sharpest settled frames of a segment, sharpest first. `sharpness` maps a frame index to
 * a score (Laplacian variance of the name band, typically).
 */
export function bestFrames(segment, sharpness, n = 3) {
  const pool = segment.settled.length ? segment.settled : segment.frames;
  return pool.map((i) => ({ i, s: sharpness(i) })).sort((a, b) => b.s - a.s).slice(0, n).map((f) => f.i);
}
