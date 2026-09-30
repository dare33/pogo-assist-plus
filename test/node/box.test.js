// The batch command with a fake extractor: no ffmpeg, OCR or video is involved. Clip "files" are
// arbitrary bytes; the readings the fake returns are just [{ name, cp }] and the fake `finish`
// turns them into rows.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { cleanFolder, expandArgs, parseArgs, runBox, FatalError, CACHE_VERSION } from '../../src/node/box.js';

// Temp dirs live under <repo>/scratch (gitignored): sandboxed runs may not write to os.tmpdir().
const root = fileURLToPath(new URL('../../', import.meta.url));
const made = [];
function scratchDir() {
  const base = join(root, 'scratch');
  mkdirSync(base, { recursive: true });
  const d = mkdtempSync(join(base, 'box-test-'));
  made.push(d);
  return d;
}
after(() => { for (const d of made) rmSync(d, { recursive: true, force: true }); });

const IVS = { atk: 15, def: 14, hp: 15 };
const mkRow = ({ name, cp }) => ({
  index: 0, name, display: name, form: '', speciesId: name.toLowerCase(), dex: 1, cp, hp: 100, ivs: IVS, ivsRead: IVS, ivsGuess: null,
  level: 20, levelMax: 20, dust: null, solveStatus: 'exact', flags: [], merged: 1, frames: [{ frame: `${name}${cp}`, time: 0 }],
});
const finish = (readings) => ({ rows: readings.map(mkRow), review: [], unmatched: [] });

/** A temp folder with fake clips; `mtimes` are local Dates. Returns { dir, paths }. */
function fixture(names, { under = null, mtime = new Date(2026, 2, 5, 12, 0) } = {}) {
  const base = under ?? scratchDir();
  mkdirSync(base, { recursive: true });
  for (const n of names) { const p = join(base, n); writeFileSync(p, `bytes of ${n}`); utimesSync(p, mtime, mtime); }
  return base;
}
const cleanup = (...dirs) => { for (const d of dirs) rmSync(d, { recursive: true, force: true }); };

/** Fake extractor: reads come from the clip's file name; `fail` names throw. Records every call. */
function fakeExtractor({ fail = [], readings = {} } = {}) {
  const calls = [];
  const extractClip = async (path) => {
    const name = path.split(/[\\/]/).pop();
    calls.push(name);
    if (fail.includes(name)) throw new Error(`cannot read ${name}`);
    return { readings: readings[name] ?? [{ name: name.replace(/\W/g, ''), cp: 100 }], frames: 10 };
  };
  return { extractClip, calls };
}

const run = async (argv, deps) => {
  const lines = [];
  const code = await runBox(argv, { log: (...a) => lines.push(a.join(' ')), finish, codeHash: 'H1', ...deps });
  return { code, log: lines.join('\n') };
};
const csvLines = (p) => readFileSync(p, 'utf8').trim().split('\n');

test('argument hygiene: unknown flags, missing values, fps, account, quotes and drive roots', () => {
  assert.throws(() => parseArgs(['x', '--nope']), /unknown option --nope/);
  assert.throws(() => parseArgs(['x', '--inbox']), /--inbox needs a value/);
  assert.throws(() => parseArgs(['x', '--inbox', '--force']), /--inbox needs a value/);
  assert.throws(() => parseArgs(['x', '--fps', 'abc']), /--fps/);
  assert.throws(() => parseArgs(['x', '--fps', '0']), /--fps/);
  assert.throws(() => parseArgs(['x', '--fps', 'Infinity']), /--fps/);
  assert.throws(() => parseArgs(['x', '--account', '../evil']), /--account/);
  assert.throws(() => parseArgs(['x', '--account', 'a b']), /--account/);
  assert.throws(() => parseArgs(['--force']), /no folder/);
  assert.equal(parseArgs(['x', '--account', 'dare33.a_b-c']).account, 'dare33.a_b-c');
  assert.deepEqual(parseArgs(['a', 'b']).folders, ['a', 'b']);
  assert.equal(cleanFolder('"C:\\a b\\c\\"'), 'C:\\a b\\c');
  assert.equal(cleanFolder('C:\\a b\\c"'), 'C:\\a b\\c');
  assert.equal(cleanFolder('C:\\'), 'C:\\');
  assert.equal(cleanFolder('"C:\\"'), 'C:\\');
});

test('an unknown flag exits 2 with usage before any work', async () => {
  const r = await run(['somewhere', '--bogus']);
  assert.equal(r.code, 2);
  assert.match(r.log, /unknown option --bogus[\s\S]*usage:/);
});

test('extract then all-cached: the export has the recording date, rows are rebuilt from the readings', async () => {
  const dir = fixture(['01-a.mp4', '02-b.mp4']), inbox = fixture([], { under: scratchDir() });
  try {
    const fx = fakeExtractor();
    let r = await run([dir, '--inbox', inbox], { extractClip: fx.extractClip });
    assert.equal(r.code, 0, r.log);
    assert.deepEqual(fx.calls, ['01-a.mp4', '02-b.mp4']);
    const name = `poke-genie-export-${dir.split(/[\\/]/).pop()}-2026-03-05.csv`;
    assert.ok(existsSync(join(dir, name)), r.log);
    assert.ok(existsSync(join(dir, name.replace(/\.csv$/, '.review.json'))));
    assert.deepEqual(readdirSync(inbox), [name]);
    const lines = csvLines(join(dir, name));
    assert.equal(lines.length, 3);
    assert.match(lines[1], /2026-03-05 12:00/, 'scan date is the newest clip time, not now');
    const cache = JSON.parse(readFileSync(join(dir, '01-a.mp4.extract.json'), 'utf8'));
    assert.equal(cache.version, CACHE_VERSION);
    assert.equal(cache.codeHash, 'H1');
    assert.ok(Array.isArray(cache.readings) && !('rows' in cache));

    const before = readFileSync(join(dir, name), 'utf8');
    const fx2 = fakeExtractor();
    r = await run([dir], { extractClip: fx2.extractClip });
    assert.equal(r.code, 0);
    assert.deepEqual(fx2.calls, [], 'nothing re-read');
    assert.match(r.log, /01-a\.mp4: cached/);
    assert.equal(readFileSync(join(dir, name), 'utf8'), before, 'byte-identical export');
  } finally { cleanup(dir, inbox); }
});

test('a fully cached folder needs no ffmpeg at all', async () => {
  const dir = fixture(['01-a.mp4']);
  try {
    await run([dir], { extractClip: fakeExtractor().extractClip });
    // No extractClip injected: the real extractor is built but never asked to read, so the
    // nonexistent --ffmpeg is never looked at.
    const r = await run([dir, '--ffmpeg', 'C:\\nonexistent\\ffmpeg.exe']);
    assert.equal(r.code, 0, r.log);
    assert.match(r.log, /01-a\.mp4: cached/);
  } finally { cleanup(dir); }
});

test('a clip that needs reading with no ffmpeg exits 2 with the install message', async () => {
  const dir = fixture(['01-a.mp4']);
  try {
    const r = await run([dir], { extractClip: async () => { throw new FatalError('ffmpeg not found. Install it with "winget install Gyan.FFmpeg"'); } });
    assert.equal(r.code, 2);
    assert.match(r.log, /ffmpeg not found/);
  } finally { cleanup(dir); }
});

test('stale caches are re-read: clip changed, or the extractor changed', async () => {
  const dir = fixture(['01-a.mp4']);
  try {
    await run([dir], { extractClip: fakeExtractor().extractClip });
    let fx = fakeExtractor();
    let r = await run([dir], { extractClip: fx.extractClip, codeHash: 'H2' });
    assert.deepEqual(fx.calls, ['01-a.mp4']);
    assert.match(r.log, /extractor changed since the cache was written/);
    // H2 was just written; a rerun with H2 is cached, then a changed mtime re-reads.
    fx = fakeExtractor();
    await run([dir], { extractClip: fx.extractClip, codeHash: 'H2' });
    assert.deepEqual(fx.calls, []);
    const later = new Date(2026, 2, 6, 9, 0);
    utimesSync(join(dir, '01-a.mp4'), later, later);
    fx = fakeExtractor();
    r = await run([dir], { extractClip: fx.extractClip, codeHash: 'H2' });
    assert.deepEqual(fx.calls, ['01-a.mp4']);
    assert.match(r.log, /clip or fps changed/);
    // --force re-reads a valid cache; a different fps does too.
    fx = fakeExtractor();
    await run([dir, '--force'], { extractClip: fx.extractClip, codeHash: 'H2' });
    assert.deepEqual(fx.calls, ['01-a.mp4']);
    fx = fakeExtractor();
    await run([dir, '--fps', '10'], { extractClip: fx.extractClip, codeHash: 'H2' });
    assert.deepEqual(fx.calls, ['01-a.mp4']);
  } finally { cleanup(dir); }
});

test('an old version-1 cache is re-read, not trusted', async () => {
  const dir = fixture(['01-a.mp4']);
  try {
    writeFileSync(join(dir, '01-a.mp4.extract.json'), JSON.stringify({ version: 1, rows: [] }));
    const fx = fakeExtractor();
    const r = await run([dir], { extractClip: fx.extractClip });
    assert.deepEqual(fx.calls, ['01-a.mp4']);
    assert.match(r.log, /older version/);
  } finally { cleanup(dir); }
});

test('one failing clip: a .partial export, no inbox copy, exit 1, scan date from the good clips', async () => {
  const dir = fixture(['01-a.mp4', '03-c.mp4']), inbox = scratchDir();
  try {
    const bad = join(dir, '02-bad.mp4');
    writeFileSync(bad, 'garbage');
    utimesSync(bad, new Date(2026, 2, 9, 8, 0), new Date(2026, 2, 9, 8, 0));
    const fx = fakeExtractor({ fail: ['02-bad.mp4'] });
    const r = await run([dir, '--inbox', inbox], { extractClip: fx.extractClip });
    assert.equal(r.code, 1);
    const stem = `poke-genie-export-${dir.split(/[\\/]/).pop()}-2026-03-05`;
    assert.ok(existsSync(join(dir, `${stem}.partial.csv`)), r.log);
    assert.ok(existsSync(join(dir, `${stem}.partial.review.json`)));
    assert.ok(!existsSync(join(dir, `${stem}.csv`)), 'the complete export name is not written');
    assert.deepEqual(readdirSync(inbox), [], 'nothing copied to the inbox');
    assert.match(csvLines(join(dir, `${stem}.partial.csv`))[1], /2026-03-05 12:00/);
    assert.match(r.log, /PARTIAL export/);
    assert.match(r.log, /02-bad\.mp4/);
    const review = JSON.parse(readFileSync(join(dir, `${stem}.partial.review.json`), 'utf8'));
    assert.equal(review.partial, true);
    assert.deepEqual(review.failedClips.map((f) => f.name), ['02-bad.mp4']);
    assert.equal(review.rows, 2);
  } finally { cleanup(dir, inbox); }
});

test('a complete export is not overwritten by a later partial run', async () => {
  const dir = fixture(['01-a.mp4', '02-b.mp4']);
  try {
    await run([dir], { extractClip: fakeExtractor().extractClip });
    const stem = `poke-genie-export-${dir.split(/[\\/]/).pop()}-2026-03-05`;
    const complete = readFileSync(join(dir, `${stem}.csv`), 'utf8');
    const r = await run([dir, '--force'], { extractClip: fakeExtractor({ fail: ['02-b.mp4'] }).extractClip });
    assert.equal(r.code, 1);
    assert.equal(readFileSync(join(dir, `${stem}.csv`), 'utf8'), complete);
  } finally { cleanup(dir); }
});

test('every clip failing writes nothing and exits 1', async () => {
  const dir = fixture(['01-a.mp4']);
  try {
    const r = await run([dir], { extractClip: fakeExtractor({ fail: ['01-a.mp4'] }).extractClip });
    assert.equal(r.code, 1);
    assert.deepEqual(readdirSync(dir).filter((f) => f.endsWith('.csv')), []);
  } finally { cleanup(dir); }
});

test('a parent folder with two account subfolders makes one export per account; several folders work too', async () => {
  const parent = scratchDir(), other = fixture(['01-x.mp4']);
  try {
    fixture(['01-a.mp4'], { under: join(parent, 'alpha') });
    fixture(['01-b.mp4', '02-b.mp4'], { under: join(parent, 'beta') });
    mkdirSync(join(parent, 'empty'));
    const fx = fakeExtractor();
    const r = await run([parent, other], { extractClip: fx.extractClip });
    assert.equal(r.code, 0, r.log);
    assert.ok(existsSync(join(parent, 'alpha', 'poke-genie-export-alpha-2026-03-05.csv')));
    assert.ok(existsSync(join(parent, 'beta', 'poke-genie-export-beta-2026-03-05.csv')));
    assert.equal(csvLines(join(parent, 'beta', 'poke-genie-export-beta-2026-03-05.csv')).length, 3);
    assert.ok(readdirSync(other).some((f) => f.startsWith('poke-genie-export-') && f.endsWith('.csv')));
    assert.ok(!existsSync(join(parent, 'empty', 'poke-genie-export-empty-2026-03-05.csv')));
  } finally { cleanup(parent, other); }
});

test('--account names the export; --out-dir must exist; a folder with no clips exits 2', async () => {
  const dir = fixture(['01-a.mp4']), out = scratchDir(), none = scratchDir();
  try {
    let r = await run([dir, '--account', 'greg', '--out-dir', out], { extractClip: fakeExtractor().extractClip });
    assert.equal(r.code, 0, r.log);
    assert.deepEqual(readdirSync(out), ['poke-genie-export-greg-2026-03-05.csv', 'poke-genie-export-greg-2026-03-05.review.json']);
    r = await run([dir, '--out-dir', join(out, 'missing')], { extractClip: fakeExtractor().extractClip });
    assert.equal(r.code, 2);
    assert.match(r.log, /--out-dir/);
    r = await run([none], { extractClip: fakeExtractor().extractClip });
    assert.equal(r.code, 2);
    assert.match(r.log, /No clips/);
  } finally { cleanup(dir, out, none); }
});

test('shadow clip in the folder marks the matching row in the CSV', async () => {
  const dir = fixture(['01-main.mp4', '02-shadow.mp4']);
  try {
    const readings = { '01-main.mp4': [{ name: 'Mew', cp: 500 }, { name: 'Meltan', cp: 101 }], '02-shadow.mp4': [{ name: 'Mew', cp: 500 }] };
    const r = await run([dir], { extractClip: fakeExtractor({ readings }).extractClip });
    assert.equal(r.code, 0, r.log);
    assert.match(r.log, /shadow pass: 1 matched, 0 appended, 0 ambiguous, 0 weak/);
    const csv = csvLines(join(dir, `poke-genie-export-${dir.split(/[\\/]/).pop()}-2026-03-05.csv`));
    const col = csv[0].split(',').indexOf('Shadow/Purified');
    assert.deepEqual(csv.slice(1).map((l) => l.split(',')[col]), ['1', '']);
  } finally { cleanup(dir); }
});

test('a quoted drive root reaches the parser as C:" and is split back into C:\\ and the words after it', () => {
  assert.deepEqual(expandArgs(['C:" --bogus']), ['C:\\', '--bogus']);
  assert.deepEqual(expandArgs(['C:\\" --force --quiet']), ['C:\\', '--force', '--quiet']);
  assert.deepEqual(expandArgs(['C:"']), ['C:\\']);
  assert.deepEqual(parseArgs(['C:"']).folders, ['C:\\']);
  assert.throws(() => parseArgs(['C:" --bogus']), /unknown option --bogus/);
  assert.deepEqual(expandArgs(['D:\\clips', '--force']), ['D:\\clips', '--force']);
});

test('--account with several accounts, or two accounts with one name, is refused before any work', async () => {
  const parent = scratchDir(), other = scratchDir();
  try {
    fixture(['01-a.mp4'], { under: join(parent, 'alpha') });
    fixture(['01-b.mp4'], { under: join(parent, 'beta') });
    const fx = fakeExtractor();
    let r = await run([parent, '--account', 'greg'], { extractClip: fx.extractClip });
    assert.equal(r.code, 2);
    assert.match(r.log, /--account greg names one account but 2 were found \(alpha, beta\)/);
    // two folders that both resolve to the account name "same"
    const one = fixture(['01-a.mp4'], { under: join(other, 'x', 'same') }), two = fixture(['01-b.mp4'], { under: join(other, 'y', 'same') });
    r = await run([one, two], { extractClip: fx.extractClip });
    assert.equal(r.code, 2);
    assert.match(r.log, /same export name \(same\)/);
    assert.deepEqual(fx.calls, [], 'nothing was read');
  } finally { cleanup(parent, other); }
});

test('a v2 cache without readings is re-read, not a crash', async () => {
  const dir = fixture(['01-a.mp4']);
  try {
    const st = statSync(join(dir, '01-a.mp4'));
    writeFileSync(join(dir, '01-a.mp4.extract.json'), JSON.stringify({ version: CACHE_VERSION, size: st.size, mtimeMs: st.mtimeMs, fps: 5, codeHash: 'H1' }));
    const fx = fakeExtractor();
    const r = await run([dir], { extractClip: fx.extractClip });
    assert.equal(r.code, 0, r.log);
    assert.deepEqual(fx.calls, ['01-a.mp4']);
    assert.match(r.log, /cache is incomplete/);
  } finally { cleanup(dir); }
});

test('a complete run removes a stale .partial export of the same recording', async () => {
  const dir = fixture(['01-a.mp4', '02-b.mp4']);
  try {
    await run([dir], { extractClip: fakeExtractor({ fail: ['02-b.mp4'] }).extractClip });
    const stem = `poke-genie-export-${dir.split(/[\\/]/).pop()}-2026-03-05`;
    assert.ok(existsSync(join(dir, `${stem}.partial.csv`)));
    const r = await run([dir], { extractClip: fakeExtractor().extractClip });
    assert.equal(r.code, 0, r.log);
    assert.ok(!existsSync(join(dir, `${stem}.partial.csv`)));
    assert.ok(!existsSync(join(dir, `${stem}.partial.review.json`)));
    assert.ok(existsSync(join(dir, `${stem}.csv`)));
    assert.match(r.log, /removed the stale partial export/);
  } finally { cleanup(dir); }
});

test('a write that fails is reported per account, the other accounts still run, exit 1', async () => {
  const parent = scratchDir();
  try {
    fixture(['01-a.mp4'], { under: join(parent, 'alpha') });
    fixture(['01-b.mp4'], { under: join(parent, 'beta') });
    // a directory squatting on alpha's CSV name makes the write fail the way a locked file does
    mkdirSync(join(parent, 'alpha', 'poke-genie-export-alpha-2026-03-05.csv'));
    const r = await run([parent], { extractClip: fakeExtractor().extractClip });
    assert.equal(r.code, 1);
    assert.match(r.log, /could not write .*poke-genie-export-alpha-2026-03-05\.csv: .*\(is it open in Excel\?\)/);
    assert.ok(existsSync(join(parent, 'beta', 'poke-genie-export-beta-2026-03-05.csv')), 'the other account was still exported');
  } finally { cleanup(parent); }
});

test('the summary reports an unmatched join', async () => {
  const dir = fixture(['01-a.mp4', '02-b.mp4']);
  try {
    const readings = { '01-a.mp4': [{ name: 'A', cp: 1 }, { name: 'C', cp: 300 }], '02-b.mp4': [{ name: 'C', cp: 308 }, { name: 'D', cp: 4 }] };
    const r = await run([dir], { extractClip: fakeExtractor({ readings }).extractClip });
    assert.match(r.log, /01-a\.mp4 → 02-b\.mp4: no overlap found \(tail C 300, head C 308\)[^\n]*may be listed twice/);
  } finally { cleanup(dir); }
});
