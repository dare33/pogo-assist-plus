import { readFileSync, readdirSync } from 'node:fs';
import { PNG } from 'pngjs';
const dir = process.argv[2];
const files = readdirSync(dir).filter((f) => f.endsWith('.png')).sort();
function rectOf(png) { const { width, height, data } = png; const on = []; for (let x = 0; x < width; x++) { let s = 0; for (let y = 0; y < height; y += 4) { const i = (y * width + x) * 4; s += data[i] + data[i + 1] + data[i + 2]; } on.push(s / (height / 4) > 30); } let best = [0, 0], cur = null; for (let x = 0; x <= width; x++) { if (x < width && on[x]) { if (cur === null) cur = x; } else if (cur !== null) { if (x - cur > best[1] - best[0]) best = [cur, x]; cur = null; } } return { x: best[0], w: best[1] - best[0], h: height }; }
// Signature of the name+CP band: downsampled grayscale of x 10-90%, y 2-46% of the content rect.
function sig(png, r) { const out = []; for (let fy = 0.02; fy < 0.46; fy += 0.01) for (let fx = 0.1; fx < 0.9; fx += 0.02) { const x = Math.round(r.x + fx * r.w), y = Math.round(fy * r.h); const i = (y * png.width + x) * 4; out.push(0.299 * png.data[i] + 0.587 * png.data[i + 1] + 0.114 * png.data[i + 2]); } return out; }
let prev = null; const diffs = [];
for (const f of files) { const png = PNG.sync.read(readFileSync(`${dir}/${f}`)); const r = rectOf(png); const s = sig(png, r); let d = 0; if (prev) { for (let i = 0; i < s.length; i++) d += Math.abs(s[i] - prev[i]); d /= s.length; } diffs.push({ f, d: Math.round(d * 10) / 10 }); prev = s; }
console.log(diffs.map((x) => `${x.f.slice(1, 5)}:${x.d}`).join('  '));
// Segments: settled = diff < 3 for 2+ consecutive frames; a swipe = diff > 15.
let seg = [], cur = null;
for (const { f, d } of diffs) { if (d > 15) { if (cur) { seg.push(cur); cur = null; } } else { if (!cur) cur = { start: f, frames: [] }; if (d < 3) cur.frames.push(f); } }
if (cur) seg.push(cur);
console.log(`\n${seg.length} segments:`); for (const s of seg) console.log(`  from ${s.start}: ${s.frames.length} settled frames (${s.frames[0] ?? '-'} .. ${s.frames.at(-1) ?? '-'})`);
