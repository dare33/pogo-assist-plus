// The windowed decode loop with a fake decoder: no ffmpeg or PNG files are involved.

import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { windowedFrames } from '../../src/node/extract-video.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const made = [];
after(() => { for (const d of made) rmSync(d, { recursive: true, force: true }); });

/** Window w (0-based) yields `frames[w]` files; 0 means an empty window. */
async function run(frames, duration) {
  const base = join(root, 'scratch');
  mkdirSync(base, { recursive: true });
  const dir = mkdtempSync(join(base, 'video-test-'));
  made.push(dir);
  const warnings = [];
  const io = {
    decode: (video, d, fps, ff, { start }) => {
      for (const f of readdirSync(d)) rmSync(join(d, f));
      for (let i = 0; i < (frames[start / 60] ?? 0); i++) writeFileSync(join(d, `f${String(i + 1).padStart(4, '0')}.png`), '');
    },
    read: () => ({}),
  };
  const out = [];
  for await (const f of windowedFrames('clip.mp4', dir, 1, 'ffmpeg', { frames: 0 }, 60, duration, (m) => warnings.push(m), io)) out.push(f);
  return { out, warnings };
}

test('a gap that resumes is reported as a window range, not as a short stream', async () => {
  const { out, warnings } = await run([2, 0, 0, 2], 240);
  assert.equal(out.length, 4);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /no frames between 60 s and 180 s/);
  assert.doesNotMatch(warnings[0], /shorter/);
});

test('a gap that runs to the end says the stream may be shorter', async () => {
  const { warnings } = await run([2, 0, 0], 180);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /no frames from 60 s to the end.*may be shorter/);
});

test('warn once, then report the count of gaps at the end', async () => {
  const { warnings } = await run([1, 0, 1, 0, 1, 0], 360);
  assert.equal(warnings.length, 2);
  assert.match(warnings[0], /no frames between 60 s and 120 s/);
  assert.match(warnings[1], /3 stretches of clip\.mp4 had no decodable frames/);
});

test('under a second left at the end is not a gap', async () => {
  const { warnings } = await run([1, 0], 60.4);
  assert.deepEqual(warnings, []);
});
