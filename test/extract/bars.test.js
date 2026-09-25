import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeImage, fillRect } from '../../src/extract/image.js';
import { classifyPixel, fillOfTrack, findBars, readIvs, readBars } from '../../src/extract/bars.js';

const PINK = [218, 113, 120], ORANGE = [242, 155, 65], GREY = [222, 221, 223], WHITE = [255, 255, 255];

/** A synthetic appraisal panel: three tracks of 3 blocks × 5 units, filled to the given IVs. */
function panel(ivs, { w = 600, h = 400, unit = 8, gap = 4, barH = 10, top = 100, left = 60, rowGap = 60 } = {}) {
  const img = makeImage(w, h);
  fillRect(img, { x: 0, y: 0, w, h }, WHITE);
  fillRect(img, { x: 0, y: 0, w, h: 40 }, [200, 180, 120]); // something else above the panel
  const values = [ivs.atk, ivs.def, ivs.hp];
  values.forEach((v, k) => {
    const y = top + k * rowGap;
    const colour = v === 15 ? PINK : ORANGE;
    for (let b = 0; b < 3; b++) {
      const bx = left + b * (5 * unit + gap);
      const filled = Math.max(0, Math.min(5, v - 5 * b));
      fillRect(img, { x: bx, y, w: 5 * unit, h: barH }, GREY);
      if (filled > 0) fillRect(img, { x: bx, y, w: filled * unit, h: barH }, colour);
    }
  });
  return img;
}

test('classifyPixel separates fill, track, white and everything else', () => {
  assert.equal(classifyPixel(...PINK), 'fill');
  assert.equal(classifyPixel(...ORANGE), 'fill');
  assert.equal(classifyPixel(...GREY), 'grey');
  assert.equal(classifyPixel(...WHITE), 'white');
  assert.equal(classifyPixel(30, 30, 30), 'other');
  assert.equal(classifyPixel(120, 200, 150), 'other');
});

test('fillOfTrack ignores block gaps and counts a fill/grey blend as half', () => {
  const segs = (spec) => spec.split(' ').map((t) => ({ c: { f: 'fill', g: 'grey', w: 'white', o: 'other' }[t[0]], n: Number(t.slice(1)) }));
  assert.equal(fillOfTrack(segs('f40 w4 f40 w4 f40')), 1);
  assert.equal(fillOfTrack(segs('g40 w4 g40 w4 g40')), 0);
  assert.equal(fillOfTrack(segs('f40 w4 f40 w4 g40')), 80 / 120);
  // an anti-aliased blend between fill and grey counts half; between two fills it is a gap
  assert.equal(fillOfTrack(segs('f40 o4 f40 w4 f20 o4 g16')), (100 + 2) / 120);
});

test('readBars measures every IV on a synthetic panel, including 0 and 15', () => {
  const rect = { x: 0, y: 0, w: 600, h: 400 };
  for (const ivs of [{ atk: 15, def: 14, hp: 15 }, { atk: 0, def: 7, hp: 3 }, { atk: 12, def: 10, hp: 11 }, { atk: 15, def: 15, hp: 15 }, { atk: 1, def: 0, hp: 6 }]) {
    const { bars, result } = readBars(panel(ivs), rect, { x: 0, y: 50, w: 400, h: 350 });
    assert.equal(bars.length, 3, `bars for ${JSON.stringify(ivs)}`);
    assert.deepEqual(result.ivs, ivs);
    assert.ok(result.confidence > 0.9, `confidence ${result.confidence}`);
  }
});

test('readIvs rejects trios with uneven spacing or different widths', () => {
  const bar = (y0, x0, x1, fill) => ({ y0, y1: y0 + 10, x0, x1, fill });
  assert.equal(readIvs([bar(100, 60, 200, 1), bar(160, 60, 200, 1), bar(300, 60, 200, 1)]), null);
  assert.equal(readIvs([bar(100, 60, 200, 1), bar(160, 60, 300, 1), bar(220, 60, 200, 1)]), null);
  assert.deepEqual(readIvs([bar(100, 60, 200, 1), bar(160, 60, 200, 0.5), bar(220, 60, 200, 0)]).ivs, { atk: 15, def: 8, hp: 0 });
});

test('a mid-animation fill gets a low confidence', () => {
  const bar = (y0, fill) => ({ y0, y1: y0 + 10, x0: 60, x1: 200, fill });
  const r = readIvs([bar(100, 0.5), bar(160, 0.5), bar(220, 7.5 / 15)]);
  assert.ok(r.confidence < 0.2);
});

test('findBars ignores coloured runs that are not on panel white', () => {
  const img = makeImage(300, 100);
  fillRect(img, { x: 0, y: 0, w: 300, h: 100 }, [240, 200, 60]); // a jacket, not a panel
  fillRect(img, { x: 50, y: 40, w: 150, h: 10 }, ORANGE);
  assert.equal(findBars(img, { x: 0, y: 0, w: 300, h: 100 }, { x: 0, y: 0, w: 300, h: 100 }).length, 0);
});
