// Smoke test for the browser extractor page. Video decode itself needs a real <video> element
// and cannot be exercised in Node (no HTMLVideoElement/canvas), so this only checks that the
// modules extract.html loads are well-formed ES modules and that the pure helpers behave, using
// `web/extract-core.js` which does no DOM work at import time.

import { test } from 'node:test';
import assert from 'node:assert/strict';

test('web/extract.js (the module extract.html loads) parses and imports cleanly', async () => {
  const mod = await import('../../web/extract.js');
  // Top-level DOM wiring is guarded behind `typeof document`, so importing under Node (no DOM)
  // must not throw and must not register anything.
  assert.equal(typeof mod, 'object');
});

test('web/extract-core.js parses cleanly and exports the frame/CSV/blob helpers', async () => {
  const mod = await import('../../web/extract-core.js');
  assert.equal(typeof mod.decodeFrames, 'function');
  assert.equal(typeof mod.csvFilename, 'function');
  assert.equal(typeof mod.reviewFilename, 'function');
  assert.equal(typeof mod.downloadText, 'function');
  assert.equal(typeof mod.formatElapsed, 'function');
});

test('csvFilename and reviewFilename strip the extension and match the CLI naming', async () => {
  const { csvFilename, reviewFilename } = await import('../../web/extract-core.js');
  assert.equal(csvFilename({ name: 'iphone-original.mp4' }), 'iphone-original.pokegenie.csv');
  assert.equal(csvFilename({ name: 'ipad-original.mov' }), 'ipad-original.pokegenie.csv');
  assert.equal(reviewFilename({ name: 'iphone-original.mp4' }), 'iphone-original.review.json');
});

test('formatElapsed renders m:ss', async () => {
  const { formatElapsed } = await import('../../web/extract-core.js');
  assert.equal(formatElapsed(0), '0:00');
  assert.equal(formatElapsed(65), '1:05');
  assert.equal(formatElapsed(3661), '61:01');
});

test('merged export filenames use the date, from a Date or a string', async () => {
  const { mergedCsvFilename, mergedReviewFilename } = await import('../../web/extract-core.js');
  assert.equal(mergedCsvFilename('2026-09-30'), 'poke-genie-export-2026-09-30.csv');
  assert.equal(mergedReviewFilename('2026-09-30'), 'poke-genie-export-2026-09-30.review.json');
  assert.equal(mergedCsvFilename(new Date(2026, 8, 5)), 'poke-genie-export-2026-09-05.csv');
});

test('decodeFrames failure text names the file and the three fixes', async () => {
  const { decodeFrames } = await import('../../web/extract-core.js');
  // Drive the private message builder through a stub document whose video element errors on load.
  const listeners = {};
  const video = { error: { code: 4 }, addEventListener: (e, f) => { listeners[e] = f; }, removeEventListener() {}, set src(_) { queueMicrotask(() => listeners.error?.()); } };
  globalThis.document = { createElement: () => video };
  globalThis.URL.createObjectURL = () => 'blob:x';
  globalThis.URL.revokeObjectURL = () => {};
  try {
    await assert.rejects(decodeFrames({ name: 'my clip.mp4' }, 5).next(), (e) => {
      assert.match(e.message, /"my clip\.mp4"/);
      assert.match(e.message, /HEVC/);
      assert.match(e.message, /Safari/);
      assert.match(e.message, /extract-box\.cmd/);
      assert.match(e.message, /Most Compatible/);
      assert.ok(e.message.split(/\s+/).length < 110);
      return true;
    });
  } finally { delete globalThis.document; }
});
