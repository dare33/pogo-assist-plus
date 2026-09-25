import { readFileSync, writeFileSync } from 'node:fs';
import { PNG } from 'pngjs';
import { createWorker } from 'tesseract.js';

const frame = process.argv[2];
const png = PNG.sync.read(readFileSync(frame));
const { width, height, data } = png;

// 1. Content rectangle: columns that are not black (pillarboxing) — take the widest run.
function contentRect() {
  const colBright = new Array(width).fill(0);
  for (let x = 0; x < width; x++) {
    let s = 0;
    for (let y = 0; y < height; y += 4) { const i = (y * width + x) * 4; s += data[i] + data[i + 1] + data[i + 2]; }
    colBright[x] = s / (height / 4);
  }
  const on = colBright.map((v) => v > 30);
  let best = [0, 0], cur = null;
  for (let x = 0; x <= width; x++) {
    if (x < width && on[x]) { if (cur === null) cur = x; }
    else if (cur !== null) { if (x - cur > best[1] - best[0]) best = [cur, x]; cur = null; }
  }
  return { x: best[0], w: best[1] - best[0], y: 0, h: height };
}
const rect = contentRect();
console.log('frame', width, 'x', height, 'content rect', rect);

// 2. Crop helper by fraction of the content rect, upscaled 2x for OCR, thresholded to dark text on white.
function crop(fx, fy, fw, fh, invert = false, scale = 2) {
  const x0 = Math.round(rect.x + fx * rect.w), y0 = Math.round(rect.y + fy * rect.h);
  const w = Math.round(fw * rect.w), h = Math.round(fh * rect.h);
  const out = new PNG({ width: w * scale, height: h * scale });
  for (let y = 0; y < h * scale; y++) for (let x = 0; x < w * scale; x++) {
    const sx = x0 + Math.floor(x / scale), sy = y0 + Math.floor(y / scale);
    const i = (sy * width + sx) * 4, o = (y * w * scale + x) * 4;
    let g = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
    if (invert) g = 255 - g;
    out.data[o] = out.data[o + 1] = out.data[o + 2] = g; out.data[o + 3] = 255;
  }
  return PNG.sync.write(out);
}
const regions = {
  cp: { box: [0.25, 0.02, 0.5, 0.07], invert: true, whitelist: 'CP0123456789' },     // white "CP3673" on the coloured header
  name: { box: [0.1, 0.39, 0.8, 0.07], invert: false, whitelist: '' },                 // dark name on light panel
  hp: { box: [0.2, 0.455, 0.6, 0.04], invert: false, whitelist: 'HP0123456789/ ' },    // "145 / 145 HP"
};
const worker = await createWorker('eng', 1, { langPath: 'data/tessdata', gzip: false, cachePath: 'data/tessdata' });
for (const [name, r] of Object.entries(regions)) {
  const img = crop(...r.box, r.invert);
  writeFileSync(`${process.env.S}/crop-${name}.png`, img);
  await worker.setParameters({ tessedit_char_whitelist: r.whitelist, tessedit_pageseg_mode: '7' });
  const { data: { text, confidence } } = await worker.recognize(img);
  console.log(`${name.padEnd(5)} conf ${confidence.toFixed(0).padStart(3)}  "${text.trim()}"`);
}
await worker.terminate();
