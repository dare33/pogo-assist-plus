// Find the UI anchors that place the OCR regions, so the same code reads iPhone and iPad frames
// and re-encoded copies: the white CP text at the top and the green HP bar under the name.
// Everything is in pixels of the frame; `rect` is the content rectangle.

import { widestRun } from './image.js';

const isWhite = (d, i) => d[i] > 225 && d[i + 1] > 225 && d[i + 2] > 225;
// The HP bar is bright green on the iPhone and a muted green on the iPad's red-tinted panel.
const isGreen = (d, i) => d[i + 1] > d[i] + 18 && d[i + 1] > d[i + 2] + 22 && d[i + 1] > 100;

// Text colour masks for the CP. White for every ordinary Pokémon; a Mega-evolved Pokémon's CP is
// drawn in the Mega's pink over its aura, so the pink mask is the fallback. (Tested on Mega
// Mewtwo Y only; other Mega colours may need a third mask.)
export const CP_MASKS = {
  white: (r, g, b) => r > 225 && g > 225 && b > 225,
  pink: (r, g, b) => r > 190 && r - g > 100 && r - b > 60 && b > 60,
};

/**
 * The CP text at the top of the screen. Rows in the top 14% of the rect whose centre band
 * (x 30–70%) holds enough mask pixels form runs; the first run of text height whose column
 * cluster nearest the centre is text-like wins. Tries each mask in turn. Returns
 * { x0, x1, y0, y1, centred, mask } or null. The status bar is too sparse in the centre band,
 * the white arc too thin and a white sprite too tall, so they fail one of the tests.
 */
export function findCpText(img, rect, masks = CP_MASKS) {
  let fallback = null;
  for (const [name, mask] of Object.entries(masks)) {
    const found = findTextByMask(img, rect, mask);
    if (found?.centred) return { ...found, mask: name };
    if (found && !fallback) fallback = { ...found, mask: name };
  }
  return fallback;
}

function findTextByMask(img, rect, mask) {
  const { width, data } = img;
  const yEnd = Math.round(rect.y + 0.14 * rect.h);
  const xa = Math.round(rect.x + 0.3 * rect.w), xb = Math.round(rect.x + 0.7 * rect.w);
  const minRow = Math.max(3, Math.round(0.03 * (xb - xa)));
  const on = [];
  for (let y = rect.y; y < yEnd; y++) {
    let n = 0;
    for (let x = xa; x < xb; x++) { const i = (y * width + x) * 4; if (mask(data[i], data[i + 1], data[i + 2])) n++; }
    on.push(n >= minRow);
  }
  // Bridge small gaps between text rows (a blurred re-encode drops rows), then walk the runs.
  const bridgeRows = Math.max(1, Math.round(0.004 * rect.h));
  for (let i = 0, off = -1; i <= on.length; i++) {
    if (i < on.length && !on[i]) { if (off < 0) off = i; continue; }
    if (off >= 0 && i - off <= bridgeRows && off > 0 && i < on.length) on.fill(true, off, i);
    off = -1;
  }
  // Text height limits, and the text starts in the top 10% (a white sprite starts lower).
  const minH = 0.016 * rect.h, maxH = 0.042 * rect.h, maxStart = 0.10 * rect.h;
  let r0 = null, fallback = null;
  for (let i = 0; i <= on.length; i++) {
    if (i < on.length && on[i]) { if (r0 === null) r0 = i; continue; }
    if (r0 === null) continue;
    const run = [r0, i]; r0 = null;
    const h = run[1] - run[0];
    if (h < minH || h > maxH || run[0] > maxStart) continue;
    const found = clusterOfText(img, rect, rect.y + run[0], rect.y + run[1], mask);
    if (found?.centred) return found;
    if (found && !fallback) fallback = found;
  }
  return fallback;
}

// Column clusters of mask pixels within the text rows; the cluster nearest the centre that is
// text-sized and text-like (not a solid pill or circle) wins.
function clusterOfText(img, rect, y0, y1, mask) {
  const { width, data } = img;
  const th = y1 - y0;
  const cols = new Uint16Array(rect.w);
  for (let y = y0; y < y1; y++) for (let x = rect.x; x < rect.x + rect.w; x++) {
    const i = (y * width + x) * 4;
    if (mask(data[i], data[i + 1], data[i + 2])) cols[x - rect.x]++;
  }
  const bridge = Math.round(th * 0.6);
  const clusters = [];
  let c0 = null, gap = 0, ink = 0;
  for (let x = 0; x <= rect.w; x++) {
    const n = x < rect.w ? cols[x] : 0;
    if (n > 0) { if (c0 === null) { c0 = x; ink = 0; } gap = 0; ink += n; }
    else if (c0 !== null && (++gap > bridge || x === rect.w)) { clusters.push({ a: c0, b: x - gap, ink }); c0 = null; gap = 0; }
  }
  const sized = clusters
    .map((c) => ({ ...c, w: c.b - c.a, centre: (c.a + c.b) / 2 / rect.w, solidity: c.ink / ((c.b - c.a) * th) }))
    .filter((c) => c.w >= 0.03 * rect.w && c.w <= 0.4 * rect.w && c.solidity < 0.7);
  if (!sized.length) return null;
  sized.sort((p, q) => Math.abs(p.centre - 0.5) - Math.abs(q.centre - 0.5));
  const best = sized[0];
  // The "CP" prefix is set smaller than the digits: skip leading columns whose ink starts well
  // below the cap height, so the OCR crop holds digits only.
  let digitsFrom = best.a;
  for (let x = best.a; x < best.b; x++) {
    let top = -1;
    for (let y = y0; y < y1 && top < 0; y++) { const i = (y * width + rect.x + x) * 4; if (mask(data[i], data[i + 1], data[i + 2])) top = y; }
    if (top >= 0 && top - y0 <= 0.2 * th) { digitsFrom = x; break; }
  }
  // Back up to the left edge of that glyph (a "9" reaches cap height only in its middle columns).
  while (digitsFrom > best.a && cols[digitsFrom - 1] > 0) digitsFrom--;
  return { x0: rect.x + best.a, x1: rect.x + best.b, digitsX0: rect.x + digitsFrom, y0, y1, centred: Math.abs(best.centre - 0.5) < 0.12 };
}

/**
 * The green HP bar under the name: a thin band of rows between 34% and 66% of the rect whose
 * centre half holds a long run of green. Returns { y0, y1, x0, x1 } or null.
 */
export function findHpBar(img, rect) {
  const { width, data } = img;
  const ya = Math.round(rect.y + 0.34 * rect.h), yb = Math.round(rect.y + 0.66 * rect.h);
  const xa = Math.round(rect.x + 0.2 * rect.w), xb = Math.round(rect.x + 0.8 * rect.w);
  const need = 0.22 * rect.w;
  const rows = [];
  for (let y = ya; y < yb; y++) {
    let n = 0;
    for (let x = xa; x < xb; x++) if (isGreen(data, (y * width + x) * 4)) n++;
    rows.push(n >= need);
  }
  // Candidate bands: runs of green rows that are thin (the bar is under 1.5% of the height); pick the longest thin run.
  const maxH = 0.015 * rect.h, minH = Math.max(2, 0.002 * rect.h);
  let best = null, start = null;
  for (let i = 0; i <= rows.length; i++) {
    if (i < rows.length && rows[i]) { if (start === null) start = i; continue; }
    if (start !== null) {
      const h = i - start;
      if (h >= minH && h <= maxH && (!best || h > best.h)) best = { y0: ya + start, y1: ya + i, h };
      start = null;
    }
  }
  if (!best) return null;
  const ym = Math.round((best.y0 + best.y1) / 2);
  let x0 = Infinity, x1 = -Infinity;
  for (let x = rect.x; x < rect.x + rect.w; x++) if (isGreen(data, (ym * width + x) * 4)) { if (x < x0) x0 = x; if (x > x1) x1 = x; }
  return { y0: best.y0, y1: best.y1, x0, x1: x1 + 1 };
}

/** OCR regions derived from the anchors, in frame pixels. */
export function regionsFrom(rect, cpText, hpBar) {
  const h = rect.h;
  const pad = Math.round(0.006 * h);
  const regions = {};
  if (cpText) {
    const th = cpText.y1 - cpText.y0;
    const x0 = cpText.digitsX0 ?? cpText.x0;
    regions.cp = { x: x0 - 0.1 * th, y: cpText.y0 - pad, w: cpText.x1 - x0 + 0.3 * th, h: th + 2 * pad };
  } else {
    regions.cp = { x: rect.x + 0.25 * rect.w, y: rect.y, w: 0.5 * rect.w, h: 0.14 * h };
  }
  if (hpBar) {
    regions.name = { x: rect.x + 0.14 * rect.w, y: hpBar.y0 - 0.062 * h, w: 0.72 * rect.w, h: 0.055 * h };
    regions.hp = { x: rect.x + 0.25 * rect.w, y: hpBar.y1 + 0.004 * h, w: 0.5 * rect.w, h: 0.026 * h };
    regions.panelSearch = { x: rect.x, y: hpBar.y1 + 0.05 * h, w: 0.55 * rect.w, h: rect.y + rect.h - (hpBar.y1 + 0.05 * h) };
  }
  return regions;
}
