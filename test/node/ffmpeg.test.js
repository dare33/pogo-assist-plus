import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { findFfmpeg, globFiles } from '../../src/node/ffmpeg.js';

const never = () => { throw new Error('should not be called'); };
const win = { platform: 'win32', env: { LOCALAPPDATA: 'C:\\L', APPDATA: 'C:\\A' } };

test('--ffmpeg wins over everything and must exist', () => {
  const r = findFfmpeg({ ...win, explicit: 'X', env: { FFMPEG: 'Y' }, exists: (p) => p === 'X', probe: (p) => p === 'X', glob: never });
  assert.deepEqual(r, { path: 'X', source: '--ffmpeg' });
  assert.throws(() => findFfmpeg({ explicit: 'nope', exists: () => false, probe: never, glob: never }), /--ffmpeg is nope/);
  assert.throws(() => findFfmpeg({ explicit: 'notffmpeg', exists: () => true, probe: () => false, glob: never }), /--ffmpeg is notffmpeg, which exists but does not run as ffmpeg/);
});

test('FFMPEG env var wins over PATH', () => {
  const r = findFfmpeg({ env: { FFMPEG: 'E' }, exists: () => true, probe: (p) => p === 'E', glob: never });
  assert.deepEqual(r, { path: 'E', source: 'FFMPEG' });
});

test('FFMPEG pointing at a missing file throws', () => {
  assert.throws(() => findFfmpeg({ env: { FFMPEG: 'gone' }, exists: () => false, probe: never, glob: never }), /FFMPEG is set to gone but no such file exists/);
});

test('FFMPEG pointing at something that does not run is a configuration error', () => {
  assert.throws(() => findFfmpeg({ env: { FFMPEG: 'junk' }, exists: () => true, probe: () => false, glob: never }), /FFMPEG is set to junk, which exists but does not run as ffmpeg/);
});

test('the highest Python version wins (Python312 before Python39)', () => {
  const p = (v) => `C:\\L\\Programs\\Python\\Python${v}\\Lib\\site-packages\\imageio_ffmpeg\\binaries\\ffmpeg-win-x86_64-v7.1.exe`;
  const r = findFfmpeg({ ...win, exists: () => false, glob: (pat) => (pat.includes('imageio_ffmpeg') && pat.startsWith('C:\\L') ?[p('39'), p('312'), p('310')] : []), probe: (c) => c !== 'ffmpeg' && c !== 'ffmpeg.exe' });
  assert.equal(r.path, p('312'));
});

test('PATH is used when its -version probe succeeds', () => {
  const r = findFfmpeg({ ...win, exists: never, glob: never, probe: (c) => c === 'ffmpeg' });
  assert.deepEqual(r, { path: 'ffmpeg', source: 'PATH' });
});

test('known install locations are found through glob and probed last', () => {
  const found = 'C:\\L\\Programs\\Python\\Python312\\Lib\\site-packages\\imageio_ffmpeg\\binaries\\ffmpeg-win-x86_64-v7.1.exe';
  const probed = [];
  const r = findFfmpeg({
    ...win, exists: () => false,
    glob: (pattern) => (pattern.includes('imageio_ffmpeg') && pattern.startsWith('C:\\L') ? [found] : []),
    probe: (c) => { probed.push(c); return c === found; },
  });
  assert.deepEqual(r, { path: found, source: 'imageio-ffmpeg' });
  assert.deepEqual(probed, ['ffmpeg', 'ffmpeg.exe', found]);
});

test('a winget link is found by a plain file check', () => {
  const link = 'C:\\L\\Microsoft\\WinGet\\Links\\ffmpeg.exe';
  const r = findFfmpeg({ ...win, exists: (p) => p === link, glob: () => [], probe: (c) => c === link });
  assert.deepEqual(r, { path: link, source: 'winget' });
});

test('homebrew and system paths on a Mac or Linux', () => {
  const notOnPath = (c) => c !== 'ffmpeg';
  assert.deepEqual(findFfmpeg({ platform: 'darwin', env: { HOME: '/h' }, exists: (p) => p === '/opt/homebrew/bin/ffmpeg', glob: () => [], probe: notOnPath }), { path: '/opt/homebrew/bin/ffmpeg', source: 'homebrew' });
  assert.deepEqual(findFfmpeg({ platform: 'linux', env: { HOME: '/h' }, exists: (p) => p === '/usr/bin/ffmpeg', glob: () => [], probe: notOnPath }), { path: '/usr/bin/ffmpeg', source: 'system' });
});

test('nothing found returns null', () => {
  assert.equal(findFfmpeg({ ...win, exists: () => false, glob: () => [], probe: () => false }), null);
});

test('a binary that exists but fails its probe is skipped', () => {
  assert.equal(findFfmpeg({ ...win, exists: () => true, glob: () => ['bad'], probe: () => false }), null);
});

test('globFiles matches * and ** against a real directory', () => {
  const d = mkdtempSync(join(tmpdir(), 'glob-'));
  try {
    mkdirSync(join(d, 'Gyan.FFmpeg_x', 'ffmpeg-7', 'bin'), { recursive: true });
    writeFileSync(join(d, 'Gyan.FFmpeg_x', 'ffmpeg-7', 'bin', 'ffmpeg.exe'), '');
    mkdirSync(join(d, 'Other'));
    writeFileSync(join(d, 'Other', 'ffmpeg-1.exe'), '');
    assert.deepEqual(globFiles(join(d, 'Gyan.FFmpeg*', '**', 'bin', 'ffmpeg.exe')), [join(d, 'Gyan.FFmpeg_x', 'ffmpeg-7', 'bin', 'ffmpeg.exe')]);
    assert.deepEqual(globFiles(join(d, 'Other', 'ffmpeg-*.exe')), [join(d, 'Other', 'ffmpeg-1.exe')]);
    assert.deepEqual(globFiles(join(d, 'Missing*', 'x')), []);
    writeFileSync(join(d, 'Other', 'ffmpeg-2.exe'), '');
    assert.deepEqual(globFiles(join(d, 'Other', 'ffmpeg-?.exe')), [], 'a question mark is literal, not a wildcard');
  } finally { rmSync(d, { recursive: true, force: true }); }
});
