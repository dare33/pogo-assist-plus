import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeImage, fillRect } from '../../src/extract/image.js';
import { signature, signatureDiff, diffSeries, segments, bestFrames } from '../../src/extract/segment.js';

const rect = { x: 0, y: 0, w: 100, h: 200 };
const frame = (nameShade, spriteShade) => {
  const img = makeImage(100, 200);
  fillRect(img, { x: 0, y: 0, w: 100, h: 200 }, [nameShade, nameShade, nameShade]);
  fillRect(img, { x: 0, y: 30, w: 100, h: 40 }, [spriteShade, spriteShade, spriteShade]); // sprite area, outside both bands
  return img;
};

test('signature ignores the sprite band but sees the name band', () => {
  const a = signature(frame(200, 0), rect), b = signature(frame(200, 255), rect), c = signature(frame(50, 0), rect);
  assert.equal(signatureDiff(a, b), 0);
  assert.ok(signatureDiff(a, c) > 100);
  assert.equal(a.length, b.length);
});

test('segments split on spikes and keep only settled frames', () => {
  const diffs = [0, 2, 1, 30, 40, 2, 1, 1, 50, 3, 2, 20, 0];
  const segs = segments(diffs, { swipe: 12, settled: 4 });
  assert.equal(segs.length, 4);
  assert.deepEqual(segs[0].frames, [0, 1, 2]);
  assert.deepEqual(segs[1].frames, [5, 6, 7]);
  assert.deepEqual(segs[2].settled, [9, 10]);
  assert.deepEqual(segs[3].frames, [12]);
});

test('segments with no settled frame are dropped', () => {
  const segs = segments([0, 8, 9, 30, 2], { swipe: 12, settled: 4 });
  assert.equal(segs.length, 2);
  assert.deepEqual(segs[0].settled, [0]);
  assert.deepEqual(segs[1].settled, [4]);
});

test('diffSeries starts at 0 and bestFrames ranks by sharpness', () => {
  const sigs = [Float32Array.from([0, 0]), Float32Array.from([10, 10]), Float32Array.from([10, 10])];
  assert.deepEqual(diffSeries(sigs), [0, 10, 0]);
  const seg = { start: 0, end: 4, frames: [0, 1, 2, 3, 4], settled: [1, 2, 3] };
  assert.deepEqual(bestFrames(seg, (i) => [5, 1, 9, 4, 8][i], 2), [2, 3]);
});
