#!/usr/bin/env node
// A folder of screen-recording clips (one Pokémon GO box) in, one merged Poke Genie-layout CSV out.
//
//   node scripts/extract-box.mjs <folder> [--account NAME] [--fps 5] [--order name|mtime]
//                                [--inbox DIR] [--out-dir DIR] [--ffmpeg PATH] [--force] [--quiet]
//
// The folder holds the clips of one account (.mp4, .mov, .m4v). If it holds none but its
// subfolders do, each subfolder is an account. A clip with "shadow" in its filename is the
// Shadow-filtered pass; "purified" likewise. Each clip is cached beside itself as
// <clip>.extract.json so a re-run only reads clips that are new or changed. See docs/whole-box.md.

import { copyFileSync, existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createWorker } from 'tesseract.js';
import { loadGamemaster } from '../src/node/load.js';
import { createOcr } from '../src/extract/ocr.js';
import { toPokeGenieCsv } from '../src/extract/pipeline.js';
import { mergeClips, orderClips, passKind } from '../src/extract/batch.js';
import { findFfmpeg, FFMPEG_NOT_FOUND } from '../src/node/ffmpeg.js';
import { extractVideo } from '../src/node/extract-video.js';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const CACHE_VERSION = 1;
const CLIP_EXT = /\.(mp4|mov|m4v)$/i;
const CHECK_FLAGS = ['ambiguous-ivs', 'no-level-fits', 'shadow-match-ambiguous', 'ivs-unread'];
const CHECK_CAP = 40;

const args = process.argv.slice(2);
const VALUE_FLAGS = new Set(['--account', '--fps', '--order', '--inbox', '--out-dir', '--ffmpeg']);
const opt = (name, dflt) => { const i = args.indexOf(`--${name}`); return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : dflt; };
const flag = (name) => args.includes(`--${name}`);
const folder = args.find((a, i) => !a.startsWith('--') && !(i > 0 && VALUE_FLAGS.has(args[i - 1])));
const usage = 'usage: node scripts/extract-box.mjs <folder> [--account NAME] [--fps 5] [--order name|mtime] [--inbox DIR] [--out-dir DIR] [--ffmpeg PATH] [--force] [--quiet]';
if (!folder) { console.error(usage); process.exit(2); }
const fps = Number(opt('fps', 5));
const order = opt('order', 'name');
if (!(fps > 0)) { console.error(`--fps must be a positive number, got ${opt('fps')}`); process.exit(2); }
if (order !== 'name' && order !== 'mtime') { console.error(`--order must be name or mtime, got ${order}`); process.exit(2); }
const quiet = flag('quiet'), force = flag('force');
const log = (...a) => console.error(...a);

const clipsIn = (dir) => readdirSync(dir, { withFileTypes: true })
  .filter((e) => e.isFile() && CLIP_EXT.test(e.name))
  .map((e) => ({ name: e.name, path: join(dir, e.name), mtimeMs: statSync(join(dir, e.name)).mtimeMs }));

if (!existsSync(folder) || !statSync(folder).isDirectory()) { log(`${folder} is not a folder.`); process.exit(2); }
const accounts = [];
const own = clipsIn(folder);
if (own.length) accounts.push({ name: opt('account', basename(resolve(folder))), folder, clips: own });
else {
  for (const e of readdirSync(folder, { withFileTypes: true }).filter((x) => x.isDirectory()).sort((a, b) => a.name.localeCompare(b.name))) {
    const sub = join(folder, e.name), clips = clipsIn(sub);
    if (clips.length) accounts.push({ name: e.name, folder: sub, clips });
  }
  if (accounts.length && opt('account', null)) log('Note: --account is ignored when each subfolder is its own account.');
}
if (!accounts.length) { log(`No clips (.mp4, .mov, .m4v) in ${folder} or its subfolders.`); process.exit(2); }

let ffmpeg = null;
try { ffmpeg = findFfmpeg({ explicit: opt('ffmpeg', null) }); } catch (e) { log(e.message); process.exit(2); }
if (!ffmpeg) { log(FFMPEG_NOT_FOUND); process.exit(2); }

const d = new Date();
const today = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const inbox = opt('inbox', null);
const inboxOk = inbox && existsSync(inbox) && statSync(inbox).isDirectory();
if (inbox && !inboxOk) log(`Warning: inbox ${inbox} does not exist; the CSV will not be copied there.`);

const gm = loadGamemaster();
// One OCR worker for the whole run, made when the first clip needs reading (a fully cached re-run
// never starts one).
let ocr = null;
const getOcr = async () => (ocr ??= await createOcr(createWorker, { langPath: join(ROOT, 'data/tessdata'), cachePath: join(ROOT, 'data/tessdata'), gzip: false }));

function readCache(clip) {
  const file = `${clip.path}.extract.json`;
  if (force || !existsSync(file)) return null;
  try {
    const c = JSON.parse(readFileSync(file, 'utf8'));
    const st = statSync(clip.path);
    return c.version === CACHE_VERSION && c.size === st.size && c.mtimeMs === st.mtimeMs && c.fps === fps ? c : null;
  } catch { return null; }
}

async function runAccount(acct) {
  const ordered = orderClips(acct.clips, { order });
  log(`\nAccount ${acct.name} (${acct.folder}): ${ordered.length} clip${ordered.length === 1 ? '' : 's'}`);
  for (const c of ordered) log(`  ${c.name}  [${passKind(c.name)}]`);

  const done = [], failedClips = [], clipInfo = [];
  for (const [i, clip] of ordered.entries()) {
    const kind = passKind(clip.name);
    let cache = readCache(clip), cached = true;
    try {
      if (!cache) {
        cached = false;
        const t = Date.now();
        const r = await extractVideo(clip.path, {
          fps, ffmpeg: ffmpeg.path, ocr: await getOcr(), gm,
          onProgress: ({ done: n, total, found }) => { if (!quiet && n % 50 === 0) log(`clip ${i + 1}/${ordered.length} ${clip.name}: ${n}/${total} frames, ${found} Pokémon`); },
        });
        const st = statSync(clip.path);
        cache = { version: CACHE_VERSION, clip: clip.name, size: st.size, mtimeMs: st.mtimeMs, fps, frames: r.frames, rows: r.rows, review: r.review, unmatched: r.unmatched, seconds: Number(((Date.now() - t) / 1000).toFixed(1)) };
        try { writeFileSync(`${clip.path}.extract.json`, JSON.stringify(cache)); } catch (e) { log(`  could not write the cache for ${clip.name}: ${e.message}`); }
      }
      log(`  ${clip.name}: ${cached ? 'cached' : `processed (${cache.frames} frames, ${cache.seconds} seconds)`}; ${cache.rows.length} Pokémon`);
      done.push({ name: clip.name, kind, rows: cache.rows, unmatched: cache.unmatched ?? [] });
      clipInfo.push({ name: clip.name, kind, cached, seconds: cache.seconds, failed: false });
    } catch (e) {
      log(`  ${clip.name}: FAILED: ${String(e.message).split('\n')[0]}`);
      failedClips.push({ name: clip.name, error: e.message });
      clipInfo.push({ name: clip.name, kind, cached: false, seconds: null, failed: true, rows: 0, flagged: 0 });
    }
  }
  if (!done.length) { log(`No clip for ${acct.name} could be read, so no export was written (an earlier export is left untouched).`); return { failed: failedClips.length }; }

  const merged = mergeClips(done);
  const stem = `poke-genie-export-${acct.name}-${today}`;
  const outDir = opt('out-dir', acct.folder);
  const csvPath = join(outDir, `${stem}.csv`), reviewPath = join(outDir, `${stem}.review.json`);
  const clipsOut = clipInfo.map((c) => ({ ...c, ...(merged.clips.find((m) => m.name === c.name) ?? {}) }));
  // The scan date is the newest clip's modified time, not the wall clock, so re-running on the
  // same clips writes a byte-identical CSV.
  const scanDate = new Date(Math.max(...ordered.map((c) => c.mtimeMs)));
  writeFileSync(csvPath, toPokeGenieCsv(merged.rows, { scanDate }));
  writeFileSync(reviewPath, JSON.stringify({
    account: acct.name, folder: acct.folder, date: today, fps, clips: clipsOut, boundaries: merged.boundaries, reconciled: merged.reconciled,
    rows: merged.rows.length, flagged: merged.review.length, failedClips, review: merged.review, unmatched: merged.unmatched,
  }, null, 2));
  let inboxCopy = null;
  if (inboxOk) { inboxCopy = join(inbox, `${stem}.csv`); copyFileSync(csvPath, inboxCopy); }

  log(`\nSummary for ${acct.name}`);
  for (const c of clipsOut) log(`  ${c.name} [${c.kind}]: ${c.failed ? 'FAILED' : `${c.rows} Pokémon, ${c.flagged} flagged, ${c.cached ? 'cached' : `processed in ${c.seconds} s`}`}`);
  for (const b of merged.boundaries) log(`  ${b.before} → ${b.after}: ${b.dropped} duplicate row${b.dropped === 1 ? '' : 's'} dropped`);
  const r = merged.reconciled;
  if (clipsOut.some((c) => c.kind !== 'normal')) log(`  shadow pass: ${r.matched} matched, ${r.appended} appended, ${r.ambiguous} ambiguous`);
  log(`  ${merged.rows.length} Pokémon, ${merged.review.length} flagged for review, ${merged.unmatched.length} frames showed a CP but no known name`);
  if (failedClips.length) log(`  WARNING: ${failedClips.length} clip${failedClips.length === 1 ? '' : 's'} failed (${failedClips.map((f) => f.name).join(', ')}); Pokémon from ${failedClips.length === 1 ? 'that clip are' : 'those clips are'} missing from the export.`);

  const check = merged.rows.filter((row) => row.flags.some((f) => CHECK_FLAGS.some((c) => f === c || f.startsWith(`${c}:`))));
  if (check.length) {
    log('\nCheck these in the game:');
    for (const row of check.slice(0, CHECK_CAP)) log(`  ${row.display ?? row.name} CP ${row.cp}, HP ${row.hp ?? '?'}, ${row.clip}: ${row.flags.join(' ')}`);
    if (check.length > CHECK_CAP) log(`  and ${check.length - CHECK_CAP} more in the review JSON`);
  }
  log(`\nwrote ${csvPath}`);
  log(`wrote ${reviewPath}`);
  if (inboxCopy) log(`copied the CSV to ${inboxCopy}`);
  return { failed: failedClips.length };
}

let failed = 0;
try {
  for (const acct of accounts) failed += (await runAccount(acct)).failed;
} finally {
  if (ocr) await ocr.terminate();
}
if (failed) { log(`\n${failed} clip${failed === 1 ? '' : 's'} failed; Pokémon from ${failed === 1 ? 'it are' : 'them are'} missing from the export.`); process.exit(1); }
