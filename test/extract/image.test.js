import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeImage, fillRect, contentRect, crop, cropFrac, toGray, invert, upscale, laplacianVariance, widestRun, meanColour, threshold } from '../../src/extract/image.js';

test('contentRect finds the phone screen inside black pillarboxing and letterboxing', () => {
  const img = makeImage(200, 100);
  fillRect(img, { x: 60, y: 10, w: 80, h: 80 }, [200, 150, 100]);
  assert.deepEqual(contentRect(img, { step: 1 }), { x: 60, y: 10, w: 80, h: 80 });
});

test('contentRect returns the whole frame when there is no border', () => {
  const img = makeImage(50, 40);
  fillRect(img, { x: 0, y: 0, w: 50, h: 40 }, [120, 120, 120]);
  assert.deepEqual(contentRect(img, { step: 1 }), { x: 0, y: 0, w: 50, h: 40 });
});

test('contentRect picks the widest bright run, not the first', () => {
  const img = makeImage(100, 20);
  fillRect(img, { x: 5, y: 0, w: 10, h: 20 }, [255, 255, 255]);
  fillRect(img, { x: 40, y: 0, w: 50, h: 20 }, [255, 255, 255]);
  assert.equal(contentRect(img, { step: 1 }).x, 40);
  assert.deepEqual(widestRun([true, false, true, true, true, false]), [2, 5]);
});

test('crop and cropFrac copy the right pixels and clamp to the image', () => {
  const img = makeImage(10, 10);
  fillRect(img, { x: 3, y: 4, w: 2, h: 2 }, [1, 2, 3]);
  const c = crop(img, { x: 3, y: 4, w: 2, h: 2 });
  assert.equal(c.width, 2); assert.equal(c.height, 2);
  assert.deepEqual([...c.data.slice(0, 4)], [1, 2, 3, 255]);
  const clamped = crop(img, { x: 8, y: 8, w: 5, h: 5 });
  assert.equal(clamped.width, 2); assert.equal(clamped.height, 2);
  const f = cropFrac(img, { x: 0, y: 0, w: 10, h: 10 }, 0.3, 0.4, 0.2, 0.2);
  assert.deepEqual([...f.data.slice(0, 3)], [1, 2, 3]);
});

test('toGray, invert and threshold', () => {
  const img = makeImage(1, 1);
  fillRect(img, { x: 0, y: 0, w: 1, h: 1 }, [255, 0, 0]);
  const g = toGray(img);
  assert.equal(Math.round(g.data[0]), 76);
  assert.equal(g.data[0], g.data[1]);
  const inv = invert(img);
  assert.deepEqual([...inv.data], [0, 255, 255, 255]);
  assert.equal(threshold(g, 100).data[0], 0);
  assert.equal(threshold(g, 50).data[0], 255);
});

test('upscale doubles the size and keeps flat colour flat', () => {
  const img = makeImage(4, 3);
  fillRect(img, { x: 0, y: 0, w: 4, h: 3 }, [10, 20, 30]);
  const up = upscale(img, 2);
  assert.equal(up.width, 8); assert.equal(up.height, 6);
  for (let i = 0; i < up.data.length; i += 4) assert.deepEqual([...up.data.slice(i, i + 3)], [10, 20, 30]);
});

test('laplacianVariance is higher for a sharp edge than for a blur', () => {
  const sharp = makeImage(20, 20);
  fillRect(sharp, { x: 10, y: 0, w: 10, h: 20 }, [255, 255, 255]);
  const flat = makeImage(20, 20);
  fillRect(flat, { x: 0, y: 0, w: 20, h: 20 }, [128, 128, 128]);
  const soft = makeImage(20, 20);
  for (let x = 0; x < 20; x++) fillRect(soft, { x, y: 0, w: 1, h: 20 }, [x * 12, x * 12, x * 12]);
  assert.ok(laplacianVariance(sharp) > laplacianVariance(soft));
  assert.equal(laplacianVariance(flat), 0);
  assert.ok(laplacianVariance(soft) < 1);
});

test('meanColour averages a region', () => {
  const img = makeImage(4, 4);
  fillRect(img, { x: 0, y: 0, w: 2, h: 4 }, [0, 0, 0]);
  fillRect(img, { x: 2, y: 0, w: 2, h: 4 }, [200, 100, 50]);
  assert.deepEqual(meanColour(img, { x: 0, y: 0, w: 4, h: 4 }), { r: 100, g: 50, b: 25 });
});
