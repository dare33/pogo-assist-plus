// Read the three appraisal bars (Attack, Defence, HP). Each bar is a track of 15 units drawn as
// three rounded blocks on the white appraisal panel: filled units are orange, all 15 filled is
// pink, unfilled units are light grey. The panel moves vertically between frames, so the bars
// are found by scanning rows for a long run of track-coloured pixels bounded by panel white.

// Measured on the recordings: pink 218/113/120, orange 242/155/65, track 222/221/223.
export function classifyPixel(r, g, b) {
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  if (min > 240) return 'white';
  if (max - min < 14 && min > 190 && max < 240) return 'grey';
  if (r > 180 && r - b > 70 && g < 200) return 'fill';   // orange or pink (re-encodes mute both)
  return 'other';
}

/**
 * Fill fraction of one track row from its class runs. Runs between the blocks (white, or a blend
 * bounded by the same class on both sides) are gaps and count for nothing; a blend between fill
 * and grey is the fill boundary and counts half, which keeps the estimate unbiased on re-encoded
 * frames where that blend is several pixels wide.
 */
export function fillOfTrack(segs) {
  // Tiny grey runs beside a white gap are the gap's shaded edge, not track.
  const cls = segs.map((s, k) => (s.c === 'grey' && s.n <= 2 && (segs[k - 1]?.c === 'white' || segs[k + 1]?.c === 'white') ? 'white' : s.c));
  let fill = 0, total = 0;
  for (let k = 0; k < segs.length; k++) {
    const c = cls[k], n = segs[k].n;
    if (c === 'fill') { fill += n; total += n; continue; }
    if (c === 'grey') { total += n; continue; }
    if (c === 'white') continue;
    // 'other': boundary if the nearest track classes on each side differ, else a gap.
    let l = k - 1; while (l >= 0 && cls[l] !== 'fill' && cls[l] !== 'grey') l--;
    let r = k + 1; while (r < segs.length && cls[r] !== 'fill' && cls[r] !== 'grey') r++;
    const lc = cls[l], rc = cls[r];
    if (lc && rc && lc !== rc) { fill += n / 2; total += n; }
  }
  return total ? fill / total : 0;
}

/**
 * Scan the search rectangle for bar rows. A bar row has a span of fill/grey pixels at least
 * `minSpan` of the rect width, at least 85% of the pixels inside the span are fill or grey, and
 * the pixels just outside the span are white. Consecutive bar rows with matching spans form a bar.
 * Returns [{ y0, y1, x0, x1, fill }] top to bottom, fill in 0..1.
 */
export function findBars(img, rect, search) {
  const { width, data } = img;
  const x0s = Math.max(0, Math.round(search.x)), x1s = Math.min(img.width, Math.round(search.x + search.w));
  const y0s = Math.max(0, Math.round(search.y)), y1s = Math.min(img.height, Math.round(search.y + search.h));
  const minSpan = 0.15 * rect.w, margin = Math.max(2, Math.round(0.004 * rect.w));
  const gapMax = Math.max(3, Math.round(0.015 * rect.w)); // white gap between the three blocks
  const aliasMax = Math.max(3, Math.round(0.02 * rect.w));  // anti-aliased or blended edge pixels (wider after re-encoding)
  const rows = [];
  for (let y = y0s; y < y1s; y++) {
    // Run-length classes along the row.
    const segs = [];
    let prev = null;
    for (let x = x0s; x < x1s; x++) {
      const i = (y * width + x) * 4;
      const c = classifyPixel(data[i], data[i + 1], data[i + 2]);
      if (prev && prev.c === c) prev.n++; else { prev = { c, x, n: 1 }; segs.push(prev); }
    }
    // A track: a maximal sequence of segments that starts and ends with fill/grey, bridging white
    // gaps up to gapMax and stray other-coloured pixels up to aliasMax. Keep the longest per row.
    let best = null;
    for (let s = 0; s < segs.length; s++) {
      if (segs[s].c !== 'fill' && segs[s].c !== 'grey') continue;
      let e = s, nFill = 0, nGrey = 0;
      for (let k = s; k < segs.length; k++) {
        const seg = segs[k];
        if (seg.c === 'fill') { nFill += seg.n; e = k; }
        else if (seg.c === 'grey') { nGrey += seg.n; e = k; }
        else if (seg.c === 'white' && seg.n <= gapMax) continue;
        else if (seg.c === 'other' && seg.n <= aliasMax) continue;
        else break;
      }
      const first = segs[s].x, last = segs[e].x + segs[e].n - 1;
      const span = last - first + 1;
      if (span >= minSpan && (!best || span > best.span)) best = { s, e, first, last, span, nFill, nGrey };
      s = e;
    }
    if (!best || (best.nFill + best.nGrey) / best.span < 0.85) continue;
    // Panel white on both sides of the track (after any anti-aliased edge).
    const outside = (k, dir) => {
      let need = margin;
      for (let j = k + dir; j >= 0 && j < segs.length && need > 0; j += dir) {
        if (segs[j].c === 'other' && segs[j].n <= aliasMax) continue;
        if (segs[j].c !== 'white') return false;
        need -= segs[j].n;
      }
      return need <= 0 || k + dir < 0 || k + dir >= segs.length;
    };
    if (!outside(best.s, -1) || !outside(best.e, 1)) continue;
    rows.push({ y, x0: best.first, x1: best.last + 1, fill: fillOfTrack(segs.slice(best.s, best.e + 1)) });
  }
  // Group consecutive rows into bars.
  // A row that fails the checks (a glow or a stray pixel) must not split a bar: allow a gap of two rows.
  const bars = [];
  for (const r of rows) {
    const cur = bars[bars.length - 1];
    if (cur && r.y - cur.y1 <= 2 && Math.abs(r.x0 - cur.x0) < margin * 2 && Math.abs(r.x1 - cur.x1) < margin * 2) {
      cur.y1 = r.y + 1; cur.rows.push(r);
    } else bars.push({ y0: r.y, y1: r.y + 1, x0: r.x0, x1: r.x1, rows: [r] });
  }
  // A single row widened by a glow splits a bar in two; rejoin vertically adjacent groups whose
  // middle rows agree.
  const joined = [];
  for (const b of bars) {
    const prev = joined[joined.length - 1];
    if (prev && b.y0 - prev.y1 <= 2 && Math.abs(mid(b).x0 - mid(prev).x0) < 0.03 * rect.w && Math.abs(mid(b).x1 - mid(prev).x1) < 0.03 * rect.w) {
      prev.y1 = b.y1; prev.rows.push(...b.rows);
    } else joined.push(b);
  }
  const minH = Math.max(2, 0.003 * rect.h);
  return joined.filter((b) => b.y1 - b.y0 >= minH).map((b) => {
    // Fill from the middle rows, where the rounded ends do not shorten the span.
    const mid = b.rows.slice(Math.floor(b.rows.length / 4), Math.ceil((b.rows.length * 3) / 4)) ;
    const use = mid.length ? mid : b.rows;
    const fill = use.reduce((s, r) => s + r.fill, 0) / use.length;
    const x0 = Math.round(use.reduce((s, r) => s + r.x0, 0) / use.length), x1 = Math.round(use.reduce((s, r) => s + r.x1, 0) / use.length);
    return { y0: b.y0, y1: b.y1, x0, x1, fill };
  });
}

// Mean extent of a group's middle rows.
function mid(b) {
  const use = b.rows.slice(Math.floor(b.rows.length / 4), Math.max(1, Math.ceil((b.rows.length * 3) / 4)));
  return { x0: use.reduce((s, r) => s + r.x0, 0) / use.length, x1: use.reduce((s, r) => s + r.x1, 0) / use.length };
}

/**
 * Pick the Attack/Defence/HP trio out of the found bars: three bars with the same horizontal
 * extent and near-equal vertical spacing. Returns { ivs: {atk, def, hp}, fills, bars, confidence }
 * or null when no trio is found. Confidence is how close each fill is to a multiple of 1/15.
 */
export function readIvs(bars) {
  let best = null;
  for (let i = 0; i + 2 < bars.length; i++) {
    const trio = bars.slice(i, i + 3);
    const w = trio.map((b) => b.x1 - b.x0);
    const sameWidth = Math.max(...w) - Math.min(...w) < 0.08 * w[0];
    const sameLeft = Math.abs(trio[0].x0 - trio[1].x0) < 0.05 * w[0] && Math.abs(trio[1].x0 - trio[2].x0) < 0.05 * w[0];
    const gap1 = trio[1].y0 - trio[0].y0, gap2 = trio[2].y0 - trio[1].y0;
    const evenGaps = Math.abs(gap1 - gap2) < 0.25 * Math.max(gap1, gap2) && gap1 > (trio[0].y1 - trio[0].y0) * 1.5;
    if (!(sameWidth && sameLeft && evenGaps)) continue;
    const fills = trio.map((b) => b.fill);
    const units = fills.map((f) => f * 15);
    const ivs = units.map((u) => Math.max(0, Math.min(15, Math.round(u))));
    const err = Math.max(...units.map((u, k) => Math.abs(u - ivs[k])));
    const score = Math.abs(gap1 - gap2) / Math.max(gap1, gap2) + (Math.max(...w) - Math.min(...w)) / w[0];
    if (!best || score < best.score) best = { ivs: { atk: ivs[0], def: ivs[1], hp: ivs[2] }, fills, bars: trio, confidence: Math.max(0, 1 - err * 2), score };
  }
  if (!best) return null;
  const { score, ...out } = best;
  return out;
}

/** Convenience: find bars in the search rect and read the IVs. */
export function readBars(img, rect, search) {
  const bars = findBars(img, rect, search);
  return { bars, result: readIvs(bars) };
}
