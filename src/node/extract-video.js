// One video in, roster rows out: decode with ffmpeg, read the frames, run the extractor. Shared
// by scripts/extract.mjs (one recording) and scripts/extract-box.mjs (a folder of clips).

import { mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { readPng } from '../extract/node.js';
import { extract } from '../extract/pipeline.js';

/** Decode a video to PNG frames at `fps` into `dir` with ffmpeg (rotation metadata is applied). */
export function decodeFrames(video, dir, fps, ffmpegPath) {
  mkdirSync(dir, { recursive: true });
  // A reused --frames directory must not keep frames of an earlier, longer recording.
  for (const f of readdirSync(dir)) if (f.toLowerCase().endsWith('.png')) rmSync(join(dir, f));
  execFileSync(ffmpegPath, ['-loglevel', 'error', '-y', '-i', video, '-vf', `fps=${fps}`, join(dir, 'f%04d.png')], { stdio: 'inherit' });
  return dir;
}

export async function* pngFrames(dir, fps) {
  const files = readdirSync(dir).filter((f) => f.toLowerCase().endsWith('.png')).sort();
  for (let i = 0; i < files.length; i++) yield { index: i, time: i / fps, label: files[i], image: readPng(join(dir, files[i])) };
}

export const countPngs = (dir) => readdirSync(dir).filter((f) => f.toLowerCase().endsWith('.png')).length;

/**
 * Decode `video` to `framesDir` (or a fresh temp dir, removed afterwards) and extract it.
 * `ffmpeg` is the binary path; `ocr` and `gm` are made once by the caller so a batch reuses them.
 * @returns { rows, review, unmatched, readings, frames }
 */
export async function extractVideo(video, { fps, ffmpeg, ocr, gm, framesDir = null, onProgress = () => {} }) {
  const temp = framesDir ? null : mkdtempSync(join(tmpdir(), 'pogo-extract-'));
  const dir = framesDir ?? temp;
  try {
    decodeFrames(video, dir, fps, ffmpeg);
    const total = countPngs(dir);
    if (!total) throw new Error(`ffmpeg produced no frames from ${video}`);
    const result = await extract(pngFrames(dir, fps), { ocr, gm, total, onProgress });
    return { rows: result.rows, review: result.review, unmatched: result.unmatched, readings: result.readings, frames: total };
  } finally {
    if (temp) rmSync(temp, { recursive: true, force: true });
  }
}

/** The per-frame readings as review.json stores them (the raw readings are too large). */
export function compactReadings(readings) {
  return readings.map((r) => ({ frame: r.frame, cp: r.cp, cpText: r.cpText, name: r.name, nameText: r.nameText, nameConfidence: Math.round(r.nameConfidence), hp: r.hp, ivs: r.ivs, ivConfidence: r.ivConfidence && Number(r.ivConfidence.toFixed(2)), fills: r.fills?.map((f) => Number((f * 15).toFixed(2))), sharpness: Math.round(r.sharpness), flags: r.flags }));
}
