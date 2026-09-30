#!/usr/bin/env node
// Screen recording (or a directory of PNG frames) in, Poke Genie-layout CSV and review.json out.
//
//   node scripts/extract.mjs recordings/iphone-original.mp4 [--fps 5] [--out roster.csv]
//                            [--review review.json] [--frames DIR] [--ffmpeg PATH] [--quiet]
//
// Frames are decoded with ffmpeg, found in this order: --ffmpeg, the FFMPEG env var, `ffmpeg` on
// the PATH, then winget and imageio-ffmpeg install locations (src/node/ffmpeg.js). The web page
// decodes in the browser and needs no ffmpeg. Pass a directory of PNGs to skip decoding.
// For a folder of several clips merged into one export, see scripts/extract-box.mjs.

import { statSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createWorker } from 'tesseract.js';
import { loadGamemaster } from '../src/node/load.js';
import { createOcr } from '../src/extract/ocr.js';
import { extract, toPokeGenieCsv } from '../src/extract/pipeline.js';
import { findFfmpeg, FFMPEG_NOT_FOUND } from '../src/node/ffmpeg.js';
import { extractVideo, compactReadings, pngFrames, countPngs } from '../src/node/extract-video.js';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const args = process.argv.slice(2);
const BOOLEAN_FLAGS = new Set(['--quiet']);
const opt = (name, dflt) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : dflt; };
const flag = (name) => args.includes(`--${name}`);
const input = args.find((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && !BOOLEAN_FLAGS.has(args[i - 1])));
if (!input) { console.error('usage: node scripts/extract.mjs <video|frames-dir> [--fps 5] [--out roster.csv] [--review review.json] [--frames DIR] [--ffmpeg PATH]'); process.exit(2); }
const fps = Number(opt('fps', 5));
const stem = basename(input).replace(/\.[^.]+$/, '');
const outCsv = opt('out', `${stem}.csv`);
const outReview = opt('review', outCsv.replace(/\.csv$/, '') + '.review.json');
const quiet = flag('quiet');

const t0 = Date.now();
const isDir = statSync(input).isDirectory();
let ffmpeg = null;
if (!isDir) {
  try { ffmpeg = findFfmpeg({ explicit: opt('ffmpeg', null) }); } catch (e) { console.error(e.message); process.exit(2); }
  if (!ffmpeg) { console.error(FFMPEG_NOT_FOUND); process.exit(2); }
  if (!quiet) console.error(`decoding ${input} at ${fps} fps with ${ffmpeg.path} (${ffmpeg.source})`);
}
const gm = loadGamemaster();
let ocr = null, result;
try {
  ocr = await createOcr(createWorker, { langPath: join(ROOT, 'data/tessdata'), cachePath: join(ROOT, 'data/tessdata'), gzip: false });
  const onProgress = ({ done, total, found }) => { if (!quiet && done % 25 === 0) console.error(`  ${done}/${total} frames, ${found} Pokémon so far`); };
  if (isDir) {
    const total = countPngs(input);
    result = { ...(await extract(pngFrames(input, fps), { ocr, gm, total, onProgress })), frames: total };
  } else {
    result = await extractVideo(input, { fps, ffmpeg: ffmpeg.path, ocr, gm, framesDir: opt('frames', null), onProgress });
  }
} finally {
  if (ocr) await ocr.terminate();
}
const { rows, review, readings, unmatched, frames: total } = result;

writeFileSync(outCsv, toPokeGenieCsv(rows));
writeFileSync(outReview, JSON.stringify({ input, fps, frames: total, rows: rows.length, flagged: review.length, review, unmatched, readings: compactReadings(readings) }, null, 2));

if (!quiet) {
  console.error(`\n${rows.length} Pokémon from ${total} frames in ${((Date.now() - t0) / 1000).toFixed(1)} s; ${review.length} flagged for review; ${unmatched.length} frames showed a CP but no known name`);
  console.error('idx  name                 cp    hp   ivs       level  frames  flags');
  for (const r of rows) {
    console.error(`${String(r.index).padStart(3)}  ${(r.display ?? r.name).padEnd(20)} ${String(r.cp).padStart(4)}  ${String(r.hp ?? '?').padStart(4)}  ${(r.ivs ? `${r.ivs.atk}/${r.ivs.def}/${r.ivs.hp}` : '?').padEnd(9)} ${(r.level === null ? '?' : r.level === r.levelMax ? String(r.level) : `${r.level}-${r.levelMax}`).padEnd(6)} ${String(r.frames.length).padStart(4)}    ${r.flags.join(' ')}`);
  }
  console.error(`wrote ${outCsv} and ${outReview}`);
}
