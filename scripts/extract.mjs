#!/usr/bin/env node
// Screen recording (or a directory of PNG frames) in, Poke Genie-layout CSV and review.json out.
//
//   node scripts/extract.mjs recordings/iphone-original.mp4 [--fps 5] [--out roster.csv]
//                            [--review review.json] [--frames DIR] [--quiet]
//
// Frames are decoded with ffmpeg: the FFMPEG env var, else `ffmpeg` on the PATH. (On a machine
// with only the imageio-ffmpeg Python package: FFMPEG="$(python -c 'import imageio_ffmpeg;
// print(imageio_ffmpeg.get_ffmpeg_exe())')". The web page decodes in the browser and needs no
// ffmpeg.) Pass a directory of PNGs to skip decoding.

import { existsSync, mkdtempSync, readdirSync, rmSync, statSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';
import { createWorker } from 'tesseract.js';
import { loadGamemaster } from '../src/node/load.js';
import { readPng } from '../src/extract/node.js';
import { createOcr } from '../src/extract/ocr.js';
import { extract, toPokeGenieCsv } from '../src/extract/pipeline.js';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const args = process.argv.slice(2);
const BOOLEAN_FLAGS = new Set(['--quiet']);
const opt = (name, dflt) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : dflt; };
const flag = (name) => args.includes(`--${name}`);
const input = args.find((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && !BOOLEAN_FLAGS.has(args[i - 1])));
if (!input) { console.error('usage: node scripts/extract.mjs <video|frames-dir> [--fps 5] [--out roster.csv] [--review review.json] [--frames DIR]'); process.exit(2); }
const fps = Number(opt('fps', 5));
const stem = basename(input).replace(/\.[^.]+$/, '');
const outCsv = opt('out', `${stem}.csv`);
const outReview = opt('review', outCsv.replace(/\.csv$/, '') + '.review.json');
const quiet = flag('quiet');

function findFfmpeg() {
  if (process.env.FFMPEG) {
    if (!existsSync(process.env.FFMPEG)) throw new Error(`FFMPEG is set to ${process.env.FFMPEG} but no such file exists`);
    return process.env.FFMPEG;
  }
  for (const cmd of ['ffmpeg', 'ffmpeg.exe']) {
    const r = spawnSync(cmd, ['-version'], { stdio: 'ignore' });
    if (r.status === 0) return cmd;
  }
  return null;
}

/** Decode a video to PNG frames at `fps` into `dir` with ffmpeg (rotation metadata is applied). */
function decodeFrames(video, dir, fps) {
  const ffmpeg = findFfmpeg();
  if (!ffmpeg) throw new Error('ffmpeg not found: set FFMPEG to the binary or put ffmpeg on the PATH');
  mkdirSync(dir, { recursive: true });
  // A reused --frames directory must not keep frames of an earlier, longer recording.
  for (const f of readdirSync(dir)) if (f.toLowerCase().endsWith('.png')) rmSync(join(dir, f));
  execFileSync(ffmpeg, ['-loglevel', 'error', '-y', '-i', video, '-vf', `fps=${fps}`, join(dir, 'f%04d.png')], { stdio: 'inherit' });
  return dir;
}

async function* pngFrames(dir, fps) {
  const files = readdirSync(dir).filter((f) => f.toLowerCase().endsWith('.png')).sort();
  for (let i = 0; i < files.length; i++) yield { index: i, time: i / fps, label: files[i], image: readPng(join(dir, files[i])) };
}

const t0 = Date.now();
let framesDir = input, temp = null;
if (!statSync(input).isDirectory()) {
  framesDir = opt('frames', null) ?? (temp = mkdtempSync(join(tmpdir(), 'pogo-extract-')));
  if (!quiet) console.error(`decoding ${input} at ${fps} fps -> ${framesDir}`);
  decodeFrames(input, framesDir, fps);
}
const total = readdirSync(framesDir).filter((f) => f.toLowerCase().endsWith('.png')).length;
const gm = loadGamemaster();
let ocr = null, result;
try {
  ocr = await createOcr(createWorker, { langPath: join(ROOT, 'data/tessdata'), cachePath: join(ROOT, 'data/tessdata'), gzip: false });
  result = await extract(pngFrames(framesDir, fps), {
    ocr, gm, total,
    onProgress: ({ done, found }) => { if (!quiet && done % 25 === 0) console.error(`  ${done}/${total} frames, ${found} Pokémon so far`); },
  });
} finally {
  if (ocr) await ocr.terminate();
  if (temp) rmSync(temp, { recursive: true, force: true });
}
const { rows, review, readings, unmatched } = result;

writeFileSync(outCsv, toPokeGenieCsv(rows));
writeFileSync(outReview, JSON.stringify({ input, fps, frames: total, rows: rows.length, flagged: review.length, review, unmatched, readings: readings.map((r) => ({ frame: r.frame, cp: r.cp, cpText: r.cpText, name: r.name, nameText: r.nameText, nameConfidence: Math.round(r.nameConfidence), hp: r.hp, ivs: r.ivs, ivConfidence: r.ivConfidence && Number(r.ivConfidence.toFixed(2)), fills: r.fills?.map((f) => Number((f * 15).toFixed(2))), sharpness: Math.round(r.sharpness), flags: r.flags })) }, null, 2));

if (!quiet) {
  console.error(`\n${rows.length} Pokémon from ${total} frames in ${((Date.now() - t0) / 1000).toFixed(1)} s; ${review.length} flagged for review; ${unmatched.length} frames showed a CP but no known name`);
  console.error('idx  name                 cp    hp   ivs       level  frames  flags');
  for (const r of rows) {
    console.error(`${String(r.index).padStart(3)}  ${(r.display ?? r.name).padEnd(20)} ${String(r.cp).padStart(4)}  ${String(r.hp ?? '?').padStart(4)}  ${(r.ivs ? `${r.ivs.atk}/${r.ivs.def}/${r.ivs.hp}` : '?').padEnd(9)} ${(r.level === null ? '?' : r.level === r.levelMax ? String(r.level) : `${r.level}-${r.levelMax}`).padEnd(6)} ${String(r.frames.length).padStart(4)}    ${r.flags.join(' ')}`);
  }
  console.error(`wrote ${outCsv} and ${outReview}`);
}
