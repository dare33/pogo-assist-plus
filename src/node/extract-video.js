// One video in, roster rows out: decode with ffmpeg, read the frames, run the extractor. Shared
// by scripts/extract.mjs (one recording) and scripts/extract-box.mjs (a folder of clips).

import { mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { readPng } from '../extract/node.js';
import { extract } from '../extract/pipeline.js';

/** Seconds of recording decoded to PNGs at a time: about 12 MB per second at 5 fps, so ~720 MB peak. */
export const WINDOW_SECONDS = 60;

/**
 * Decode a video to PNG frames at `fps` into `dir` with ffmpeg (rotation metadata is applied).
 * `start` and `duration` (seconds) decode only that window of the recording.
 */
export function decodeFrames(video, dir, fps, ffmpegPath, { start = null, duration = null } = {}) {
  mkdirSync(dir, { recursive: true });
  // A reused directory must not keep frames of an earlier window or a longer recording.
  for (const f of readdirSync(dir)) if (f.toLowerCase().endsWith('.png')) rmSync(join(dir, f));
  const window = [...(start !== null ? ['-ss', String(start)] : []), ...(duration !== null ? ['-t', String(duration)] : [])];
  execFileSync(ffmpegPath, ['-loglevel', 'error', '-y', ...window, '-i', video, '-vf', `fps=${fps}`, join(dir, 'f%04d.png')], { stdio: 'inherit' });
  return dir;
}

export async function* pngFrames(dir, fps) {
  const files = readdirSync(dir).filter((f) => f.toLowerCase().endsWith('.png')).sort();
  for (let i = 0; i < files.length; i++) yield { index: i, time: i / fps, label: files[i], image: readPng(join(dir, files[i])) };
}

export const countPngs = (dir) => readdirSync(dir).filter((f) => f.toLowerCase().endsWith('.png')).length;

/** The clip's duration in seconds as ffmpeg -i reports it, or null when unknown. */
function probeDuration(video, ffmpegPath) {
  const r = spawnSync(ffmpegPath, ['-hide_banner', '-i', video], { encoding: 'utf8' });
  const m = /Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/.exec(`${r.stderr ?? ''}`);
  return m ? Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) : null;
}

/**
 * Frames of a whole recording, decoded a window at a time so a long clip never needs its whole
 * decode on disk. Index and time continue across windows (time = start + i/fps) and labels are
 * the running frame number, the same as a single full decode would give.
 * With a known duration the loop runs until the start reaches it, so a window with no decodable
 * frames (variable frame rate, a damaged stretch) does not silently drop the rest of the clip;
 * with an unknown duration the first empty window is the end.
 * A run of empty windows is a gap. Only the first gap is warned about (a container that outruns
 * its video stream would otherwise warn per window); the total is reported at the end. `io` lets
 * a test replace ffmpeg and the PNG reader.
 */
export async function* windowedFrames(video, dir, fps, ffmpegPath, counter, windowSeconds, duration, warn, io = { decode: decodeFrames, read: readPng }) {
  let gaps = 0, gapStart = null;
  const closeGap = (end, toEnd) => {
    gaps++;
    if (gaps === 1) {
      warn(toEnd
        ? `no frames from ${gapStart} s to the end; the file reports ${duration.toFixed(1)} s, so the video stream may be shorter (${video})`
        : `no frames between ${gapStart} s and ${end} s, then decoding resumed (${video})`);
    }
    gapStart = null;
  };
  for (let w = 0; ; w++) {
    const start = w * windowSeconds;
    if (duration !== null && start >= duration) break;
    io.decode(video, dir, fps, ffmpegPath, { start, duration: windowSeconds });
    const files = readdirSync(dir).filter((f) => f.toLowerCase().endsWith('.png')).sort();
    if (!files.length) {
      if (duration === null) return;
      gapStart ??= start;
      continue;
    }
    if (gapStart !== null) closeGap(start, false);
    for (let i = 0; i < files.length; i++) {
      const index = counter.frames++;
      yield { index, time: start + i / fps, label: `f${String(index + 1).padStart(4, '0')}.png`, image: io.read(join(dir, files[i])) };
    }
  }
  // Under a second of footage left is just the tail of the duration rounding up.
  if (gapStart !== null && duration - gapStart > 1) closeGap(duration, true);
  if (gaps > 1) warn(`${gaps} stretches of ${video} had no decodable frames`);
}

/**
 * Extract one video. With `framesDir` the whole recording is decoded there first (kept, so the
 * PNGs can be inspected); otherwise it is decoded in windows into a temp dir that is removed
 * afterwards. `ocr` and `gm` are made once by the caller so a batch reuses them.
 * @returns { rows, review, unmatched, readings, frames }
 */
export async function extractVideo(video, { fps, ffmpeg, ocr, gm, framesDir = null, onProgress = () => {}, windowSeconds = WINDOW_SECONDS, warn = (m) => console.error(`warning: ${m}`) }) {
  if (framesDir) {
    decodeFrames(video, framesDir, fps, ffmpeg);
    const total = countPngs(framesDir);
    if (!total) throw new Error(`ffmpeg produced no frames from ${video}`);
    const r = await extract(pngFrames(framesDir, fps), { ocr, gm, total, onProgress });
    return { rows: r.rows, review: r.review, unmatched: r.unmatched, readings: r.readings, frames: total };
  }
  const temp = mkdtempSync(join(tmpdir(), 'pogo-extract-'));
  const counter = { frames: 0 };
  try {
    const duration = probeDuration(video, ffmpeg);
    const total = duration === null ? null : Math.ceil(duration * fps);
    const r = await extract(windowedFrames(video, temp, fps, ffmpeg, counter, windowSeconds, duration, warn), { ocr, gm, total, onProgress });
    if (!counter.frames) throw new Error(`ffmpeg produced no frames from ${video}`);
    return { rows: r.rows, review: r.review, unmatched: r.unmatched, readings: r.readings, frames: counter.frames };
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

/** The per-frame readings as review.json stores them (the raw readings are too large). */
export function compactReadings(readings) {
  return readings.map((r) => ({ frame: r.frame, cp: r.cp, cpText: r.cpText, name: r.name, nameText: r.nameText, nameConfidence: Math.round(r.nameConfidence), hp: r.hp, ivs: r.ivs, ivConfidence: r.ivConfidence && Number(r.ivConfidence.toFixed(2)), fills: r.fills?.map((f) => Number((f * 15).toFixed(2))), sharpness: Math.round(r.sharpness), flags: r.flags }));
}
