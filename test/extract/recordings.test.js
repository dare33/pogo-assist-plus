// Integration test on the real recordings. Runs when frames are present under frames/<name>/
// (decoded by scripts/extract.mjs or ffmpeg at 5 fps) or when the recording is under
// recordings/ and ffmpeg can be found; skips otherwise, so CI without the recordings stays green.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { loadGamemaster } from '../../src/node/load.js';
import { createOcr } from '../../src/extract/ocr.js';
import { extract, toPokeGenieCsv } from '../../src/extract/pipeline.js';
import { importPokeGenie } from '../../src/import/pokegenie.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const path = (p) => join(root, p);
// tesseract.js is not installed where the Pages workflow runs npm test; skip rather than fail there.
const tesseract = await import('tesseract.js').catch(() => null);
const nodeIo = await import('../../src/extract/node.js').catch(() => null); // needs pngjs
const readPng = (p) => nodeIo.readPng(p);

// The handoff's acceptance table. Both iPhone recordings must produce every row; the trimmed
// copy only reaches the first Zamazenta of the second (it ends there).
const ACCEPTANCE = [
  { name: 'Mewtwo', form: 'Mega Y', cp: 3673, hp: 145, ivs: { atk: 15, def: 15, hp: 15 }, level: 20 },
  { name: 'Xurkitree', form: '', cp: 3028, hp: 145, ivs: { atk: 15, def: 14, hp: 15 }, level: 27 },
  { name: 'Zamazenta', form: 'Hero', cp: 2692, hp: 137, ivs: { atk: 13, def: 12, hp: 14 }, level: 25 },
  { name: 'Zamazenta', form: 'Hero', cp: 2651, hp: 135, ivs: { atk: 12, def: 10, hp: 11 }, level: 25 },
  { name: 'Xurkitree', form: '', cp: 2223, hp: 125, ivs: null, level: null },
];

function findFfmpeg() {
  if (process.env.FFMPEG && existsSync(process.env.FFMPEG)) return process.env.FFMPEG;
  if (spawnSync('ffmpeg', ['-version'], { stdio: 'ignore' }).status === 0) return 'ffmpeg';
  return null;
}

/** Directory of 5 fps PNG frames for a recording, or null when neither frames nor a decodable recording exist. Cached per name. */
const framesCache = new Map();
function framesFor(name, temps) {
  if (framesCache.has(name)) return framesCache.get(name);
  const dir = resolveFrames(name, temps);
  framesCache.set(name, dir);
  return dir;
}
function resolveFrames(name, temps) {
  const dir = path(`frames/${name}`);
  if (existsSync(dir) && readdirSync(dir).some((f) => f.endsWith('.png'))) return dir;
  const video = path(`recordings/${name}.mp4`);
  const ffmpeg = findFfmpeg();
  if (!existsSync(video) || !ffmpeg) return null;
  const tmp = mkdtempSync(join(tmpdir(), `pogo-test-${name}-`));
  temps.push(tmp);
  execFileSync(ffmpeg, ['-loglevel', 'error', '-y', '-i', video, '-vf', 'fps=5', join(tmp, 'f%04d.png')]);
  return tmp;
}

async function* frames(dir) {
  const files = readdirSync(dir).filter((f) => f.endsWith('.png')).sort();
  for (let i = 0; i < files.length; i++) yield { index: i, time: i / 5, label: files[i], image: readPng(join(dir, files[i])) };
}

async function run(dir) {
  const ocr = await createOcr(tesseract.createWorker, { langPath: path('data/tessdata'), cachePath: path('data/tessdata'), gzip: false });
  try {
    const { rows } = await extract(frames(dir), { ocr, gm: loadGamemaster() });
    return rows;
  } finally { await ocr.terminate(); }
}

function check(rows, expected, label) {
  const csv = importPokeGenie(toPokeGenieCsv(rows));
  const hits = csv.filter((r) => r.name === expected.name && r.cp === expected.cp);
  assert.equal(hits.length, 1, `${label}: ${expected.name} ${expected.cp} should appear exactly once, found ${hits.length}`);
  const r = hits[0];
  assert.equal(r.form, expected.form, `${label}: form of ${expected.name} ${expected.cp}`);
  assert.equal(r.hp, expected.hp, `${label}: HP of ${expected.name} ${expected.cp}`);
  if (expected.ivs) {
    assert.deepEqual(r.ivs, expected.ivs, `${label}: IVs of ${expected.name} ${expected.cp}`);
    assert.equal(r.level, expected.level, `${label}: level of ${expected.name} ${expected.cp}`);
  }
}

const temps = [];
const cleanup = () => { for (const t of temps) rmSync(t, { recursive: true, force: true }); };

test('trimmed recording: acceptance rows it contains, no duplicates', { skip: (!(tesseract && nodeIo) && 'tesseract.js or pngjs not installed') || (!framesFor('iphone-clipchamp-trimmed', temps) && 'no recording or frames present') }, async () => {
  const rows = await run(framesFor('iphone-clipchamp-trimmed', temps));
  for (const e of ACCEPTANCE.slice(0, 4)) check(rows, e, 'trimmed');
  assert.equal(rows.length, 4, `trimmed: expected 4 rows, got ${rows.map((r) => `${r.name} ${r.cp}`).join(', ')}`);
});

test('original recording: every acceptance row, each exactly once', { skip: (!(tesseract && nodeIo) && 'tesseract.js or pngjs not installed') || (!framesFor('iphone-original', temps) && 'no recording or frames present') }, async () => {
  const rows = await run(framesFor('iphone-original', temps));
  for (const e of ACCEPTANCE) check(rows, e, 'original');
  // No row may be a wrong-and-silent duplicate: every unflagged row must solve to one level.
  for (const r of rows) if (!r.flags.length) assert.equal(r.level, r.levelMax, `original: unflagged ${r.name} ${r.cp} has a level range`);
});

// The WhatsApp copy is the worst case and not the merge gate: at 384 px wide the Mega's pink CP
// text is not readable, so Mewtwo comes out with a wrong CP and a flag. The other four rows must
// still be right, and the Mewtwo row must be flagged rather than wrong and silent.
test('WhatsApp copy: four acceptance rows right, Mewtwo present but flagged', { skip: (!(tesseract && nodeIo) && 'tesseract.js or pngjs not installed') || (!framesFor('iphone-whatsapp', temps) && 'no recording or frames present') }, async () => {
  const rows = await run(framesFor('iphone-whatsapp', temps));
  for (const e of ACCEPTANCE.slice(1)) check(rows, e, 'whatsapp');
  const mewtwo = rows.filter((r) => r.name === 'Mewtwo');
  assert.ok(mewtwo.length >= 1, 'a Mewtwo row exists');
  for (const m of mewtwo) if (m.cp !== 3673) assert.ok(m.flags.length, `Mewtwo with CP ${m.cp} must be flagged`);
});

test('clean up decoded frames', () => { cleanup(); });
