// Crop regions (fractions of the detected content rect) from frames into one contact image for inspection.
import { readFileSync, writeFileSync } from 'node:fs';
import { PNG } from 'pngjs';
const [out, ...args] = process.argv.slice(2);
const specs = []; // frame,fx,fy,fw,fh
for (const a of args) { const [f, fx, fy, fw, fh] = a.split(','); specs.push({ f, fx: +fx, fy: +fy, fw: +fw, fh: +fh }); }
function rectOf(png) {
  const { width, height, data } = png; const on = [];
  for (let x = 0; x < width; x++) { let s = 0; for (let y = 0; y < height; y += 4) { const i = (y * width + x) * 4; s += data[i] + data[i + 1] + data[i + 2]; } on.push(s / (height / 4) > 30); }
  let best = [0, 0], cur = null; for (let x = 0; x <= width; x++) { if (x < width && on[x]) { if (cur === null) cur = x; } else if (cur !== null) { if (x - cur > best[1] - best[0]) best = [cur, x]; cur = null; } }
  return { x: best[0], w: best[1] - best[0], h: height };
}
const tiles = specs.map((s) => { const png = PNG.sync.read(readFileSync(s.f)); const r = rectOf(png); const x0 = Math.round(r.x + s.fx * r.w), y0 = Math.round(s.fy * r.h), w = Math.round(s.fw * r.w), h = Math.round(s.fh * r.h); return { png, x0, y0, w, h }; });
const scale = 2; const W = Math.max(...tiles.map((t) => t.w)) * scale; const H = tiles.reduce((s, t) => s + t.h * scale + 4, 0);
const out_ = new PNG({ width: W, height: H }); let yoff = 0;
for (const t of tiles) { for (let y = 0; y < t.h * scale; y++) for (let x = 0; x < t.w * scale; x++) { const si = ((t.y0 + Math.floor(y / scale)) * t.png.width + t.x0 + Math.floor(x / scale)) * 4, oi = ((yoff + y) * W + x) * 4; out_.data[oi] = t.png.data[si]; out_.data[oi + 1] = t.png.data[si + 1]; out_.data[oi + 2] = t.png.data[si + 2]; out_.data[oi + 3] = 255; } yoff += t.h * scale + 4; }
writeFileSync(out, PNG.sync.write(out_));
console.log('wrote', out, W, 'x', H);
