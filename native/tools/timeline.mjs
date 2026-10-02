#!/usr/bin/env node
// Which Pokemon were on screen, and what became of each? Splits a frame sequence into on-screen
// segments by frame evidence (swipes and anchor-less frames separate them; names are not used to
// split) and says, per segment, what was read and which row it ended up in.
//
//   node native/tools/timeline.mjs <readings.json> [--rows <rows source>] [--json] [--min-frames N]
//
// <readings.json>: anything with a `readings` array in the shared shape (pogo-read's output, a
// scripts/extract.mjs review JSON) or a bare array. Rows, in order of preference:
//   --rows <file>    a finish-readings.mjs output (rows carry their frames: matched by frame label),
//                    or a rows array / pogo-read output (LiveGrouper rows with firstFrame/lastFrame
//                    or firstTime/lastTime), or a roster CSV (matched by name + CP);
//   otherwise the `rows` array inside <readings.json>, if it is one.
// A frame is "a card" when it has a CP or an HP read; 3 or more frames in a row without one (swipes,
// anchor-less frames, a card sliding past) end a segment (--swipe-frames N). Two cards with no
// swipe between them are one segment (flagged MULTI-NAME when the names differ).

import { readFileSync, existsSync } from 'node:fs';

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : d; };
const asJson = args.includes('--json');
const minFrames = Number(opt('min-frames', 1));
const positional = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && ['--rows', '--min-frames', '--swipe-frames'].includes(args[i - 1])));
const [readingsPath] = positional;
if (!readingsPath) { console.error('usage: node timeline.mjs <readings.json> [--rows <file>] [--json] [--min-frames N]'); process.exit(2); }

const top = JSON.parse(readFileSync(readingsPath, 'utf8'));
const readings = Array.isArray(top) ? top : top.readings;
if (!Array.isArray(readings)) { console.error('no readings array'); process.exit(2); }

// ---- rows
function parseCsv(text) {
  const rows = []; let row = [], cell = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += c; }
    else if (c === '"') q = true; else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(cell); cell = ''; if (row.length > 1) rows.push(row); row = []; }
    else cell += c;
  }
  const [head, ...body] = rows;
  return body.map((r) => ({ index: Number(r[head.indexOf('Index')]), name: r[head.indexOf('Name')], cp: Number(r[head.indexOf('CP')]), hp: Number(r[head.indexOf('HP')]) || null, frames: [] }));
}
const rowsPath = opt('rows', null);
let rowSource = rowsPath ? (rowsPath.endsWith('.csv') ? parseCsv(readFileSync(rowsPath, 'utf8')) : JSON.parse(readFileSync(rowsPath, 'utf8'))) : top.rows;
if (rowSource && !Array.isArray(rowSource)) rowSource = rowSource.rows;
const rows = Array.isArray(rowSource) ? rowSource.map((r, i) => ({ ...r, index: r.index ?? i + 1 })) : [];

const labelOf = (f) => (typeof f === 'string' ? f : f?.frame);
const rowByLabel = new Map();
for (const r of rows) if (Array.isArray(r.frames)) for (const f of r.frames) { const l = labelOf(f); if (l !== undefined) (rowByLabel.get(l) ?? rowByLabel.set(l, []).get(l)).push(r.index); }
const labelIndex = new Map(readings.map((r, i) => [r.frame, i]));

// ---- segments
// A card frame has a CP or an HP read. A run of SWIPE_FRAMES or more frames without one (mid-swipe,
// no anchors, a card sliding past with only its name and bars) is a swipe and ends the segment; a
// shorter gap (a hidden CP, a covered HP) stays inside it. Names are not used to split.
const SWIPE_FRAMES = Number(opt('swipe-frames', 3));
const isCard = (r) => r.cp != null || r.hp != null;
const segs = [];
let cur = null, sep = 0;
readings.forEach((r, i) => {
  if (!isCard(r)) { sep++; return; }
  if (!cur || sep >= SWIPE_FRAMES) { cur = { first: i, last: i, frames: [] }; segs.push(cur); }
  cur.last = i; cur.frames.push(r); sep = 0;
});

// Cards that follow each other with fewer than SWIPE_FRAMES frames between them (an iPad swipe leaves
// fewer) stay one segment above. Split them on frame evidence: a different max HP, or two settled
// bar reads in a row that differ from the segment's. --split-content turns this on (off by default: a settled-looking bar read mid-animation splits real cards).
const keyOf = (f) => (f.ivs && (f.ivConfidence ?? 1) >= 0.7 ? `${f.ivs.atk}/${f.ivs.def}/${f.ivs.hp}` : null);
function splitByContent(seg) {
  const parts = [];
  let part = null, hp = null, iv = null, pending = [];
  const start = (f, i) => { part = { first: i, last: i, frames: [f] }; parts.push(part); hp = f.hp ? (f.hp.max ?? f.hp) : null; iv = keyOf(f); pending = []; };
  seg.frames.forEach((f, k) => {
    const i = seg.first + k;
    if (!part) return start(f, i);
    const fhp = f.hp ? (f.hp.max ?? f.hp) : null, fiv = keyOf(f);
    if (fhp !== null && hp !== null && fhp !== hp) return start(f, i);
    if (fiv !== null && iv !== null && fiv !== iv) {
      pending.push([f, i, fiv]);
      if (pending.length >= 2 && pending.every((p) => p[2] === fiv)) { const [f0, i0] = pending[0]; part.frames.length -= 0; const keep = part.frames.filter((x) => !pending.some((p) => p[0] === x)); part.frames = keep; const prevLast = keep.length; start(f0, i0); for (const [pf, pi] of pending.slice(1)) { part.frames.push(pf); part.last = pi; } return; }
    } else pending = [];
    if (fhp !== null && hp === null) hp = fhp;
    if (fiv !== null && iv === null) iv = fiv;
    part.frames.push(f); part.last = i;
  });
  return parts;
}
if (args.includes('--split-content')) { const split = segs.flatMap(splitByContent); segs.length = 0; segs.push(...split); }

const tally = (vals) => { const m = new Map(); for (const v of vals) if (v !== null && v !== undefined) m.set(v, (m.get(v) ?? 0) + 1); return [...m.entries()].sort((a, b) => b[1] - a[1]); };
const fmt = (t, n = 3) => t.slice(0, n).map(([v, c]) => `${v}x${c}`).join(' ');
const cpSimilar = (a, b) => {
  const x = String(a), y = String(b);
  if (x === y) return true;
  if (x.length === y.length && x.length >= 3) { let d = 0; for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) d++; return d <= 1; }
  const [s, l] = x.length < y.length ? [x, y] : [y, x];
  if (l.length - s.length !== 1 || s.length < 2) return false;
  for (let i = 0; i < l.length; i++) if (l.slice(0, i) + l.slice(i + 1) === s) return true;
  return false;
};

const out = segs.filter((s) => s.frames.length >= minFrames).map((s, k) => {
  const names = tally(s.frames.map((f) => f.name));
  const cps = tally(s.frames.map((f) => f.cp));
  const hps = tally(s.frames.map((f) => (f.hp ? f.hp.max ?? f.hp : null)));
  const ivs = tally(s.frames.filter((f) => f.ivs && (f.ivConfidence ?? 1) >= 0.7).map((f) => `${f.ivs.atk}/${f.ivs.def}/${f.ivs.hp}`));
  const flags = tally(s.frames.flatMap((f) => f.flags ?? []));
  // Rows: by frame label, then by time / label range, then by name + CP.
  let hit = new Set();
  for (const f of s.frames) for (const idx of rowByLabel.get(f.frame) ?? []) hit.add(idx);
  const how = hit.size ? 'frames' : null;
  if (!hit.size) {
    const t0 = s.frames[0].time, t1 = s.frames[s.frames.length - 1].time;
    for (const r of rows) {
      if (r.firstFrame !== undefined && labelIndex.has(r.firstFrame) && labelIndex.has(r.lastFrame)) { const a = labelIndex.get(r.firstFrame), b = labelIndex.get(r.lastFrame); if (a <= s.last && b >= s.first) hit.add(r.index); }
      else if (r.firstTime !== undefined && t0 != null && r.firstTime <= t1 && r.lastTime >= t0) hit.add(r.index);
    }
  }
  if (!hit.size && names.length) {
    for (const r of rows) if (r.name === names[0][0] && cps.some(([c]) => r.cp != null && cpSimilar(c, r.cp))) hit.add(r.index);
  }
  return {
    segment: k + 1, firstFrame: s.frames[0].frame ?? s.first, frameCount: s.frames.length, span: [s.first, s.last],
    names: fmt(names, 2), cps: fmt(cps), hp: fmt(hps, 2), ivs: fmt(ivs, 2), flags: fmt(flags, 4),
    multiName: names.length > 1 && names[1][1] >= 2, rows: [...hit].sort((a, b) => a - b), via: how ?? (hit.size ? 'time/name+cp' : null),
  };
});

const rowsCover = new Map();
for (const s of out) for (const r of s.rows) rowsCover.set(r, (rowsCover.get(r) ?? 0) + 1);
const summary = {
  frames: readings.length, segments: out.length,
  segmentsWithRow: out.filter((s) => s.rows.length).length, segmentsWithoutRow: out.filter((s) => !s.rows.length).length,
  rows: rows.length, rowsCovering2PlusSegments: [...rowsCover.entries()].filter(([, n]) => n >= 2).map(([r, n]) => ({ row: r, segments: n })),
};
if (asJson) { console.log(JSON.stringify({ summary, segments: out }, null, 2)); process.exit(0); }
console.log('seg  first       n   names                          cps                       hp          ivs          row(s)  flags');
for (const s of out) console.log(`${String(s.segment).padStart(3)}  ${String(s.firstFrame).padEnd(11)} ${String(s.frameCount).padStart(3)} ${s.names.padEnd(30)} ${s.cps.padEnd(25)} ${s.hp.padEnd(11)} ${s.ivs.padEnd(12)} ${(s.rows.join(',') || 'NONE').padEnd(7)} ${s.multiName ? 'MULTI-NAME ' : ''}${s.flags}`);
console.log(`\nsegments ${summary.segments}, with a row ${summary.segmentsWithRow}, without ${summary.segmentsWithoutRow}; rows ${summary.rows}; rows covering 2+ segments: ${summary.rowsCovering2PlusSegments.map((x) => `#${x.row} (${x.segments})`).join(' ') || 'none'}`);
