// The batch command behind scripts/extract-box.mjs, kept here so it can be tested with a fake
// extractor: argument handling, finding accounts, the per-clip cache, merging and writing the
// export. tesseract.js, pngjs and ffmpeg are only touched by the real extractor (loaded lazily),
// so importing this module needs none of them.

import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { finish, toPokeGenieCsv } from '../extract/pipeline.js';
import { mergeClips, orderClips, passKind } from '../extract/batch.js';
import { findFfmpeg, FFMPEG_NOT_FOUND } from './ffmpeg.js';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
/** 2: the cache holds the raw frame readings (rows are rebuilt on load), keyed on the extractor. */
export const CACHE_VERSION = 2;
const CLIP_EXT = /\.(mp4|mov|m4v)$/i;
const CHECK_FLAGS = ['ambiguous-ivs', 'no-level-fits', 'cp-recovered', 'name-low-confidence', 'shadow-match-ambiguous', 'shadow-match-weak', 'ivs-unread', 'hp-mismatch'];
const CHECK_CAP = 40;
const VALUE_FLAGS = new Set(['account', 'fps', 'order', 'inbox', 'out-dir', 'ffmpeg']);
const BOOLEAN_FLAGS = new Set(['force', 'quiet']);

export const USAGE = 'usage: node scripts/extract-box.mjs <folder>... [--account NAME] [--fps 5] [--order name|mtime] [--inbox DIR] [--out-dir DIR] [--ffmpeg PATH] [--force] [--quiet]';

/** Stop the whole run (not just one clip) with this exit code. */
export class FatalError extends Error {
  constructor(message, exitCode = 2) { super(message); this.exitCode = exitCode; }
}
export class UsageError extends Error {}

/** Quotes a launcher may have left around a path, and a trailing separator (but not a drive root). */
export function cleanFolder(p) {
  let s = String(p).replace(/^"+|"+$/g, '');
  if (s.length > 3 && !/^[A-Za-z]:[\\/]$/.test(s)) s = s.replace(/[\\/]+$/, '');
  return s;
}

/**
 * A quoted drive root, "C:\", reaches node as C:" (Windows reads \" as a literal quote) and swallows
 * the rest of the command line into the same argument. Split it back into C:\ and the words after.
 */
export function expandArgs(argv) {
  const out = [];
  for (const a of argv) {
    const m = /^([A-Za-z]):\\?"(.*)$/.exec(a);
    if (m) out.push(`${m[1]}:\\`, ...m[2].split(/\s+/).filter(Boolean));
    else out.push(a);
  }
  return out;
}

export function parseArgs(rawArgv) {
  const argv = expandArgs(rawArgv);
  const opts = {}, folders = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) { folders.push(cleanFolder(a)); continue; }
    const name = a.slice(2);
    if (BOOLEAN_FLAGS.has(name)) opts[name] = true;
    else if (VALUE_FLAGS.has(name)) {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) throw new UsageError(`--${name} needs a value`);
      opts[name] = v; i++;
    } else throw new UsageError(`unknown option ${a}`);
  }
  if (!folders.length) throw new UsageError('no folder given');
  const fps = Number(opts.fps ?? 5);
  if (!Number.isFinite(fps) || fps <= 0) throw new UsageError(`--fps must be a positive number, got ${opts.fps}`);
  const order = opts.order ?? 'name';
  if (order !== 'name' && order !== 'mtime') throw new UsageError(`--order must be name or mtime, got ${order}`);
  if (opts.account !== undefined && (!/^[A-Za-z0-9._-]+$/.test(opts.account) || /^\.+$/.test(opts.account))) {
    throw new UsageError(`--account must be a plain name of letters, digits, dot, dash or underscore, got "${opts.account}"`);
  }
  return { folders, fps, order, account: opts.account ?? null, inbox: opts.inbox ?? null, outDir: opts['out-dir'] ?? null, ffmpeg: opts.ffmpeg ?? null, force: Boolean(opts.force), quiet: Boolean(opts.quiet) };
}

// A folder that cannot be read (system folders when a drive root is given) simply has no clips.
const clipsIn = (dir) => {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isFile() && CLIP_EXT.test(e.name))
      .map((e) => ({ name: e.name, path: join(dir, e.name), mtimeMs: statSync(join(dir, e.name)).mtimeMs }));
  } catch { return []; }
};

/** A folder with clips is one account; one with none but with subfolders that have clips is several. */
export function discoverAccounts(folder, account = null) {
  const own = clipsIn(folder);
  if (own.length) return [{ name: account ?? basename(resolve(folder)), folder, clips: own }];
  const accounts = [];
  for (const e of readdirSync(folder, { withFileTypes: true }).filter((x) => x.isDirectory()).sort((a, b) => a.name.localeCompare(b.name))) {
    const sub = join(folder, e.name), clips = clipsIn(sub);
    if (clips.length) accounts.push({ name: e.name, folder: sub, clips });
  }
  return accounts;
}

const EXTRACTOR_FILES = ['frame', 'ocr', 'bars', 'image', 'layout', 'names', 'png', 'node'].map((n) => `src/extract/${n}.js`).concat('src/node/extract-video.js');

/** version of an installed dependency, looked for in node_modules from the repo upwards; '' if absent. */
function depVersion(root, pkg) {
  for (let dir = root, i = 0; i < 6; i++, dir = dirname(dir)) {
    const p = join(dir, 'node_modules', pkg, 'package.json');
    if (existsSync(p)) { try { return String(JSON.parse(readFileSync(p, 'utf8')).version ?? ''); } catch { return ''; } }
  }
  return '';
}

/**
 * What the frame readings depend on: the reading code and the decode step, the game master (name
 * matching), the OCR language file (contents) and the versions of the OCR and PNG libraries. Line
 * endings are normalised so a Windows and a Mac checkout agree.
 */
export function computeCodeHash(root = ROOT) {
  const h = createHash('sha256');
  for (const f of [...EXTRACTOR_FILES, 'data/gamemaster.json']) h.update(f).update(readFileSync(join(root, f), 'utf8').replace(/\r\n/g, '\n'));
  h.update(`tessdata:${createHash('sha256').update(readFileSync(join(root, 'data/tessdata/eng.traineddata'))).digest('hex')}`);
  h.update(`tesseract.js:${depVersion(root, 'tesseract.js')}`).update(`pngjs:${depVersion(root, 'pngjs')}`);
  return h.digest('hex');
}

const localDate = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** A usable cache for the clip, or { why } naming the reason it must be re-read (null: none written). */
function readCache(clipPath, st, { fps, codeHash }) {
  const file = `${clipPath}.extract.json`;
  if (!existsSync(file)) return { cache: null, why: null };
  let c;
  try { c = JSON.parse(readFileSync(file, 'utf8')); } catch { return { cache: null, why: 'cache unreadable' }; }
  if (c.version !== CACHE_VERSION) return { cache: null, why: 'cache from an older version of this tool' };
  if (!Array.isArray(c.readings)) return { cache: null, why: 'cache is incomplete' };
  if (c.size !== st.size || c.mtimeMs !== st.mtimeMs || c.fps !== fps) return { cache: null, why: 'clip or fps changed since the cache was written' };
  if (c.codeHash !== codeHash) return { cache: null, why: 'extractor changed since the cache was written' };
  return { cache: c, why: null };
}

/**
 * One account: read (or load) every clip, merge, write the export.
 * ctx: { fps, order, force, quiet, inbox, outDir, codeHash, finish(readings), extractClip(path, { onProgress }), log }
 * `extractClip` returns { readings, frames }. Returns { failed, csvPath }.
 */
export async function runAccount(acct, ctx) {
  const { fps, log } = ctx;
  const ordered = orderClips(acct.clips, { order: ctx.order });
  log(`\nAccount ${acct.name} (${acct.folder}): ${ordered.length} clip${ordered.length === 1 ? '' : 's'}`);
  for (const c of ordered) log(`  ${c.name}  [${passKind(c.name)}]`);

  const done = [], failedClips = [], clipInfo = [], failedMtimes = [];
  for (const [i, clip] of ordered.entries()) {
    const kind = passKind(clip.name);
    try {
      const st = statSync(clip.path);
      let cache = null, cached = true;
      if (!ctx.force) {
        const r = readCache(clip.path, st, ctx);
        cache = r.cache;
        if (r.why) log(`  ${clip.name}: re-reading (${r.why})`);
      }
      if (!cache) {
        cached = false;
        const t = Date.now();
        const r = await ctx.extractClip(clip.path, {
          onProgress: ({ done: n, total, found }) => { if (!ctx.quiet && n % 50 === 0) log(`clip ${i + 1}/${ordered.length} ${clip.name}: ${n}/${total ?? '?'} frames, ${found} Pokémon`); },
        });
        cache = { version: CACHE_VERSION, clip: clip.name, size: st.size, mtimeMs: st.mtimeMs, fps, codeHash: ctx.codeHash, frames: r.frames, readings: r.readings, seconds: Number(((Date.now() - t) / 1000).toFixed(1)) };
        try { writeFileSync(`${clip.path}.extract.json`, JSON.stringify(cache)); } catch (e) { log(`  could not write the cache for ${clip.name}: ${e.message}`); }
      }
      // Rows are always rebuilt from the readings, so solver and merge fixes need no re-read.
      const { rows, unmatched } = ctx.finish(cache.readings);
      log(`  ${clip.name}: ${cached ? 'cached' : `processed (${cache.frames} frames, ${cache.seconds} seconds)`}; ${rows.length} Pokémon`);
      done.push({ name: clip.name, kind, rows, unmatched, mtimeMs: st.mtimeMs });
      clipInfo.push({ name: clip.name, kind, cached, seconds: cache.seconds, failed: false });
    } catch (e) {
      if (e instanceof FatalError) throw e;
      log(`  ${clip.name}: FAILED: ${String(e.message).split('\n')[0].slice(0, 200)}`);
      failedClips.push({ name: clip.name, error: e.message });
      clipInfo.push({ name: clip.name, kind, cached: false, seconds: null, failed: true, rows: 0, flagged: 0 });
      // A failed clip still counts towards the recording date (see below), when it can be stat'ed.
      try { failedMtimes.push(statSync(clip.path).mtimeMs); } catch { /* unreadable: no date */ }
    }
  }
  if (!done.length) { log(`No clip for ${acct.name} could be read, so no export was written (an earlier export is left untouched).`); return { failed: failedClips.length, csvPath: null }; }

  const merged = mergeClips(done.map(({ name, kind, rows, unmatched }) => ({ name, kind, rows, unmatched })));
  // The recording date (newest clip in the folder by modified time, counting clips that failed to
  // read), not the run date: re-running on a later day updates the same file. Counting failed clips
  // means a partial written after a failed newest clip carries the same date as the later complete
  // run, so that run finds and removes it. It is also the CSV's scan date, so an unchanged folder
  // re-exports byte for byte.
  const scanDate = new Date(Math.max(...done.map((c) => c.mtimeMs), ...failedMtimes));
  const date = localDate(scanDate);
  const partial = failedClips.length > 0;
  const stem = `poke-genie-export-${acct.name}-${date}`;
  const suffix = partial ? '.partial' : '';
  const outDir = ctx.outDir ?? acct.folder;
  const csvPath = join(outDir, `${stem}${suffix}.csv`), reviewPath = join(outDir, `${stem}${suffix}.review.json`);
  const clipsOut = clipInfo.map((c) => ({ ...c, ...(merged.clips.find((m) => m.name === c.name) ?? {}) }));
  let writing = csvPath, inboxCopy = null;
  try {
    writeFileSync(csvPath, toPokeGenieCsv(merged.rows, { scanDate }));
    writing = reviewPath;
    writeFileSync(reviewPath, JSON.stringify({
      account: acct.name, folder: acct.folder, date, partial, fps, clips: clipsOut, boundaries: merged.boundaries, reconciled: merged.reconciled,
      rows: merged.rows.length, flagged: merged.review.length, failedClips, review: merged.review, unmatched: merged.unmatched,
    }, null, 2));
    // A partial export must never reach the inbox, where the complete one would be replaced by it.
    if (ctx.inbox && !partial) { inboxCopy = join(ctx.inbox, `${stem}.csv`); writing = inboxCopy; copyFileSync(csvPath, inboxCopy); }
  } catch (e) {
    log(`could not write ${writing}: ${e.code ? `${e.code} ` : ''}${e.message} (is it open in Excel?)`);
    return { failed: failedClips.length, writeFailed: true, csvPath: null };
  }
  // A complete run supersedes an earlier partial export of the same recording. Best effort: a
  // partial that is open in Excel must not stop the inbox copy or the summary.
  if (!partial) {
    for (const stale of [join(outDir, `${stem}.partial.csv`), join(outDir, `${stem}.partial.review.json`)]) {
      if (!existsSync(stale)) continue;
      try { rmSync(stale); log(`removed the stale partial export ${stale}`); } catch (e) { log(`could not remove stale ${stale}: ${e.code ?? e.message}`); }
    }
  }

  log(`\nSummary for ${acct.name}`);
  for (const c of clipsOut) log(`  ${c.name} [${c.kind}]: ${c.failed ? 'FAILED' : `${c.rows} Pokémon read, ${c.flagged} flagged rows attributed to this clip, ${c.cached ? 'cached' : `processed in ${c.seconds} s`}`}`);
  const names = (rows) => rows.map((r) => `${r.name} ${r.cp}`).join(', ');
  for (const b of merged.boundaries) {
    if (b.unmatched) {
      log(`  ${b.before} → ${b.after}: no overlap found (tail ${b.tail.name} ${b.tail.cp}, head ${b.head.name} ${b.head.cp}): if you restarted on the last Pokémon you saw, it may be listed twice — check`);
      continue;
    }
    let line = `  ${b.before} → ${b.after}: ${b.dropped} duplicate row${b.dropped === 1 ? '' : 's'} dropped (${names(b.droppedRows)})`;
    if (b.maybeRepeated.length) line += `; ${b.maybeRepeated.length} more may be repeats: ${names(b.maybeRepeated)} — check (flagged boundary-weak)`;
    else if (b.weak) line += ' (weak join, flagged boundary-weak: check these)';
    log(line);
  }
  const r = merged.reconciled;
  if (clipsOut.some((c) => c.kind !== 'normal')) {
    const label = clipsOut.some((c) => c.kind === 'purified') ? 'shadow/purified passes' : 'shadow pass';
    log(`  ${label}: ${r.matched} matched, ${r.appended} appended, ${r.ambiguous} ambiguous, ${r.weak} weak`);
  }
  log(`  ${merged.rows.length} Pokémon, ${merged.review.length} flagged for review, ${merged.unmatched.length} on screen but not read (see "unmatched" in the review JSON)`);
  if (partial) log(`  WARNING: ${failedClips.length} clip${failedClips.length === 1 ? '' : 's'} failed (${failedClips.map((f) => f.name).join(', ')}); Pokémon from ${failedClips.length === 1 ? 'that clip are' : 'those clips are'} missing, so this is a PARTIAL export (${stem}${suffix}.csv) and was not copied to the inbox.`);

  const check = merged.rows.filter((row) => row.flags.some((f) => CHECK_FLAGS.some((c) => f === c || f.startsWith(`${c}:`))));
  if (check.length) {
    log('\nCheck these in the game:');
    for (const row of check.slice(0, CHECK_CAP)) log(`  ${row.display ?? row.name} CP ${row.cp}, HP ${row.hp ?? '?'}, ${row.clip}: ${row.flags.join(' ')}`);
    if (check.length > CHECK_CAP) log(`  and ${check.length - CHECK_CAP} more in the review JSON`);
  }
  log(`\nwrote ${csvPath}`);
  log(`wrote ${reviewPath}`);
  if (inboxCopy) log(`copied the CSV to ${inboxCopy}`);
  return { failed: failedClips.length, csvPath };
}

/**
 * The real extractor: ffmpeg is looked for, and the OCR worker started, only when the first clip
 * needs reading, so a fully cached folder needs neither.
 */
function realExtractor({ explicitFfmpeg, fps, gm, root }) {
  let ffmpeg = null, ocr = null, mod = null;
  return {
    async extractClip(clipPath, { onProgress }) {
      if (!ffmpeg) {
        try { ffmpeg = findFfmpeg({ explicit: explicitFfmpeg }); } catch (e) { throw new FatalError(e.message); }
        if (!ffmpeg) throw new FatalError(FFMPEG_NOT_FOUND);
      }
      mod ??= await import('./extract-video.js');
      if (!ocr) {
        const { createWorker } = await import('tesseract.js');
        const { createOcr } = await import('../extract/ocr.js');
        ocr = await createOcr(createWorker, { langPath: join(root, 'data/tessdata'), cachePath: join(root, 'data/tessdata'), gzip: false });
      }
      const r = await mod.extractVideo(clipPath, { fps, ffmpeg: ffmpeg.path, ocr, gm: gm(), onProgress });
      return { readings: r.readings, frames: r.frames };
    },
    async close() { if (ocr) await ocr.terminate(); },
  };
}

/**
 * Run the batch command. `deps` (all optional) lets tests replace the extractor: { log,
 * extractClip, finish, codeHash }. Returns the exit code.
 */
export async function runBox(argv, deps = {}) {
  const log = deps.log ?? ((...a) => console.error(...a));
  let args;
  try { args = parseArgs(argv); } catch (e) {
    if (!(e instanceof UsageError)) throw e;
    log(`${e.message}\n${USAGE}`);
    return 2;
  }
  const accounts = [];
  for (const folder of args.folders) {
    if (!existsSync(folder) || !statSync(folder).isDirectory()) { log(`${folder} is not a folder.`); return 2; }
    const found = discoverAccounts(folder, args.account);
    if (!found.length) { log(`No clips (.mp4, .mov, .m4v) in ${folder} or its subfolders.`); return 2; }
    if (args.account && found.some((a) => a.folder !== folder)) log('Note: --account is ignored when each subfolder is its own account.');
    accounts.push(...found);
  }
  if (args.account && accounts.length > 1) { log(`--account ${args.account} names one account but ${accounts.length} were found (${accounts.map((a) => a.name).join(', ')}); give one folder that holds clips directly.`); return 2; }
  if (args.outDir && !(existsSync(args.outDir) && statSync(args.outDir).isDirectory())) { log(`--out-dir ${args.outDir} is not a folder.`); return 2; }
  const inboxOk = args.inbox && existsSync(args.inbox) && statSync(args.inbox).isDirectory();
  if (args.inbox && !inboxOk) log(`Warning: inbox ${args.inbox} does not exist; the CSV will not be copied there.`);
  // Two accounts of one name collide only where their exports land in the same place: a shared
  // --out-dir, an inbox that exists (so the copy will really happen), or the same folder. A missing
  // inbox only warns above and each account then writes into its own folder.
  const shared = Boolean(args.outDir || inboxOk);
  const seen = new Map();
  for (const a of accounts) {
    // Windows paths are case-insensitive; elsewhere two folders differing in case are different.
    const folderKey = process.platform === 'win32' ? resolve(a.folder).toLowerCase() : resolve(a.folder);
    const key = shared ? a.name.toLowerCase() : folderKey;
    if (seen.has(key)) {
      log(shared
        ? `Two accounts would write the same export name (${a.name}): ${seen.get(key)} and ${a.folder}, into the same --out-dir or --inbox. Rename one folder or run them separately.`
        : `${a.folder} was given twice.`);
      return 2;
    }
    seen.set(key, a.folder);
  }

  let gm = null;
  const getGm = async () => (gm ??= (await import('./load.js')).loadGamemaster());
  if (!deps.finish) await getGm();
  const real = deps.extractClip ? null : realExtractor({ explicitFfmpeg: args.ffmpeg, fps: args.fps, gm: () => gm, root: ROOT });
  const ctx = {
    fps: args.fps, order: args.order, force: args.force, quiet: args.quiet, inbox: inboxOk ? args.inbox : null, outDir: args.outDir, log,
    codeHash: deps.codeHash ?? computeCodeHash(),
    finish: deps.finish ?? ((readings) => finish(readings, gm)),
    extractClip: deps.extractClip ?? real.extractClip,
  };
  let failed = 0, writeFailures = 0;
  try {
    for (const acct of accounts) { const r = await runAccount(acct, ctx); failed += r.failed; if (r.writeFailed) writeFailures++; }
  } catch (e) {
    if (!(e instanceof FatalError)) throw e;
    log(e.message);
    return e.exitCode;
  } finally {
    if (real) await real.close();
  }
  if (writeFailures) { log(`\n${writeFailures} account${writeFailures === 1 ? '' : 's'} could not be written (see above).`); if (!failed) return 1; }
  if (failed) { log(`\n${failed} clip${failed === 1 ? '' : 's'} failed; Pokémon from ${failed === 1 ? 'it are' : 'them are'} missing from the export (the file written is marked .partial and was not copied to the inbox).`); return 1; }
  return 0;
}
