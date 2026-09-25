import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseCp, parseHp } from '../../src/extract/ocr.js';
import { encodePng } from '../../src/extract/png.js';
import { makeImage, fillRect } from '../../src/extract/image.js';
import { findCpText, findHpBar, regionsFrom } from '../../src/extract/layout.js';

test('parseCp takes the digits after the last letter and maps O to 0', () => {
  assert.equal(parseCp('CP3028'), 3028);
  assert.equal(parseCp('P2651'), 2651);
  assert.equal(parseCp('cp3O28'), 3028);
  assert.equal(parseCp('23028'), 3028);
  assert.equal(parseCp('711'), 711);
  assert.equal(parseCp('7'), null);
  assert.equal(parseCp(''), null);
});

test('parseHp reads current and max', () => {
  assert.deepEqual(parseHp('145 / 145 HP'), { current: 145, max: 145 });
  assert.deepEqual(parseHp('79/79 1'), { current: 79, max: 79 });
  assert.equal(parseHp('HP'), null);
});

// pngjs is a dependency the Pages workflow never installs (it runs npm test without npm ci), so
// this test skips rather than fails when the package is missing.
const pngjs = await import('pngjs').catch(() => null);
test('encodePng round-trips through pngjs', { skip: !pngjs && 'pngjs not installed' }, () => {
  const { PNG } = pngjs;
  const img = makeImage(70, 3);
  fillRect(img, { x: 0, y: 0, w: 70, h: 3 }, [10, 20, 30]);
  fillRect(img, { x: 5, y: 1, w: 1, h: 1 }, [200, 100, 50]);
  const png = PNG.sync.read(Buffer.from(encodePng(img)));
  assert.equal(png.width, 70); assert.equal(png.height, 3);
  assert.deepEqual([...png.data.slice((1 * 70 + 5) * 4, (1 * 70 + 5) * 4 + 4)], [200, 100, 50, 255]);
  assert.deepEqual([...png.data.slice(0, 4)], [10, 20, 30, 255]);
  // large enough to need more than one stored deflate block
  const big = makeImage(300, 100);
  const png2 = PNG.sync.read(Buffer.from(encodePng(big)));
  assert.equal(png2.data.length, 300 * 100 * 4);
});

/** A synthetic phone screen: dark header with white "text" made of a few blocks, a green HP bar. */
function screen({ w = 400, h = 800, textY = 0.06, textBlocks = 4, barY = 0.45 } = {}) {
  const img = makeImage(w, h);
  fillRect(img, { x: 0, y: 0, w, h }, [60, 80, 100]);
  fillRect(img, { x: 0, y: 0.35 * h, w, h: 0.65 * h }, [250, 250, 245]);
  const th = Math.round(0.025 * h);
  for (let i = 0; i < textBlocks; i++) fillRect(img, { x: 0.42 * w + i * 0.045 * w, y: textY * h, w: 0.02 * w, h: th }, [255, 255, 255]);
  fillRect(img, { x: 0.26 * w, y: barY * h, w: 0.48 * w, h: 0.006 * h }, [102, 231, 170]);
  return img;
}

test('findCpText and findHpBar locate the anchors on a synthetic screen and derive regions', () => {
  const img = screen();
  const rect = { x: 0, y: 0, w: 400, h: 800 };
  const cp = findCpText(img, rect);
  assert.ok(cp, 'cp text found');
  assert.ok(cp.centred);
  assert.ok(Math.abs(cp.y0 - 0.06 * 800) <= 2);
  const bar = findHpBar(img, rect);
  assert.ok(bar);
  assert.ok(Math.abs(bar.y0 - 0.45 * 800) <= 1);
  const regions = regionsFrom(rect, cp, bar);
  assert.ok(regions.name.y < bar.y0 && regions.name.y + regions.name.h <= bar.y0);
  assert.ok(regions.hp.y >= bar.y1);
  assert.ok(regions.panelSearch.y > bar.y1);
});

test('findCpText rejects a solid off-centre shape and a thin line', () => {
  const rect = { x: 0, y: 0, w: 400, h: 800 };
  const solid = makeImage(400, 800);
  fillRect(solid, { x: 0, y: 0, w: 400, h: 800 }, [60, 80, 100]);
  fillRect(solid, { x: 130, y: 20, w: 140, h: 24 }, [255, 255, 255]); // a solid pill
  assert.equal(findCpText(solid, rect), null);
  const line = makeImage(400, 800);
  fillRect(line, { x: 0, y: 0, w: 400, h: 800 }, [60, 80, 100]);
  fillRect(line, { x: 100, y: 80, w: 200, h: 3 }, [255, 255, 255]); // the arc apex
  assert.equal(findCpText(line, rect), null);
});
