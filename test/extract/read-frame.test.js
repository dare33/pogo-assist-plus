// readFrame with a stand-in OCR: which reads it accepts, on a synthetic screen whose anchors
// (white CP text at the top, green HP bar) the layout code finds for real.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeImage, fillRect } from '../../src/extract/image.js';
import { WHITELIST } from '../../src/extract/ocr.js';
import { readFrame } from '../../src/extract/frame.js';
import { displayNames } from '../../src/extract/names.js';
import { loadGamemaster } from '../../src/node/load.js';

const names = displayNames(loadGamemaster());
const W = 400, H = 800, BAR_Y = 0.45 * H;
const MARK = [255, 0, 255]; // painted one line above the usual name position

/** Dark header, white card, optional CP "text" blocks, a green HP bar starting at `barX` of the width. */
function screen({ cp = true, barX = 0.26, lucky = false } = {}) {
  const img = makeImage(W, H);
  fillRect(img, { x: 0, y: 0, w: W, h: H }, [60, 80, 100]);
  fillRect(img, { x: 0, y: 0.35 * H, w: W, h: 0.65 * H }, [250, 250, 245]);
  if (cp) for (let i = 0; i < 4; i++) fillRect(img, { x: 0.42 * W + i * 0.045 * W, y: 0.06 * H, w: 0.02 * W, h: Math.round(0.025 * H) }, [255, 255, 255]);
  fillRect(img, { x: barX * W, y: BAR_Y, w: 0.48 * W, h: 0.006 * H }, [102, 231, 170]);
  // The usual name crop starts 0.062 H above the bar; the Lucky retry starts 0.025 H higher.
  if (lucky) fillRect(img, { x: 0.3 * W, y: BAR_Y - 0.08 * H, w: 6, h: 4 }, MARK);
  return img;
}

const hasMark = (img) => { for (let i = 0; i < img.data.length; i += 4) if (img.data[i] === 255 && img.data[i + 1] === 0 && img.data[i + 2] === 255) return true; return false; };
const line = (text, confidence) => ({ text, confidence, words: text ? [{ text, confidence, bbox: { x0: 0, y0: 0, x1: 1, y1: 1 } }] : [] });

/** OCR stand-in. `name` is [text, confidence]; `above` is what the line above the name reads. */
function ocrOf({ cp = '1234', name = ['Zapdos', 92], above = null, hp = '129 / 129 HP' } = {}) {
  const calls = { name: 0 };
  return {
    calls,
    async read(img, { whitelist }) {
      if (whitelist === WHITELIST.digits) return line(cp, 90);
      if (whitelist === WHITELIST.hp) return line(hp, 90);
      calls.name++;
      return above && hasMark(img) ? line(...above) : line(...name);
    },
  };
}
const read = (img, ocr) => readFrame(img, ocr, names, { wantBars: false });

test('a confident name gives a full reading', async () => {
  const r = await read(screen(), ocrOf());
  assert.equal(r.name, 'Zapdos');
  assert.equal(r.cp, 1234);
  assert.deepEqual(r.hp, { current: 129, max: 129 });
  assert.equal(r.nameWeak, false);
});

test('at confidence 0 only an exact, whole name of four letters or more is taken, and it is marked weak', async () => {
  const ok = await read(screen(), ocrOf({ name: ['Zapdos', 0] }));
  assert.equal(ok.name, 'Zapdos');
  assert.equal(ok.nameWeak, true);
  for (const text of ['Zapdo', 'x Rattata', 'Aloan Rattata', 'Mew']) {
    const r = await read(screen(), ocrOf({ name: [text, 0] }));
    assert.equal(r.name, null, text);
    assert.equal(r.cp, 1234, `${text}: an unnamed frame keeps its CP for the unmatched list`);
    assert.ok(r.flags.includes('name-unmatched'), text);
  }
  assert.equal((await read(screen(), ocrOf({ name: ['Zapdo', 90] }))).name, 'Zapdos'); // a near miss still passes with confidence
  // The line between weak and confident is 40.
  assert.equal((await read(screen(), ocrOf({ name: ['Zapdos', 39] }))).nameWeak, true);
  assert.equal((await read(screen(), ocrOf({ name: ['Zapdos', 40] }))).nameWeak, false);
});

test('Nidoran is taken at any confidence and is not marked weak (its symbol is what was not read)', async () => {
  const r = await read(screen(), ocrOf({ name: ['Nidorano', 37] }));
  assert.equal(r.name, 'Nidoran');
  assert.equal(r.nameWeak, false);
  assert.deepEqual([...r.speciesIds].sort(), ['nidoran_female', 'nidoran_male']);
});

test('a frame with no CP text is read only when the HP bar sits where a settled card puts it', async () => {
  const settled = await read(screen({ cp: false }), ocrOf());
  assert.equal(settled.cp, null);
  assert.equal(settled.name, 'Zapdos');
  assert.deepEqual(settled.hp, { current: 129, max: 129 });
  assert.ok(settled.flags.includes('no-cp-text'));
  const sliding = await read(screen({ cp: false, barX: 0.5 }), ocrOf());
  assert.equal(sliding.name, null);
  assert.deepEqual(sliding.flags, ['no-cp-text']);
  const leaving = await read(screen({ cp: false, barX: 0.1 }), ocrOf());
  assert.equal(leaving.name, null);
});

test('the Lucky retry looks one line up, and takes only a confident exact name there', async () => {
  const lucky = ocrOf({ name: ['LUCKY POKEMON', 90], above: ['Rayquaza', 92] });
  const r = await read(screen({ lucky: true }), lucky);
  assert.equal(r.name, 'Rayquaza');
  assert.equal(lucky.calls.name, 2);
  assert.equal((await read(screen({ lucky: true }), ocrOf({ name: ['LUCKY POKEMON', 90], above: ['Rayquaza', 20] }))).name, null);
  assert.equal((await read(screen({ lucky: true }), ocrOf({ name: ['LUCKY POKEMON', 90], above: ['Rayquazo', 92] }))).name, null);
  // A name that matched in its usual place is not looked for again.
  const plain = ocrOf();
  await read(screen({ lucky: true }), plain);
  assert.equal(plain.calls.name, 1);
});
