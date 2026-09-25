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
