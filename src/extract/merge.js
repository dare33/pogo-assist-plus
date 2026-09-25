// Turn per-frame readings into one row per Pokémon. Consecutive frames that could be the same
// Pokémon form a run: same name, and the CP, HP and bar reads do not contradict each other (a
// dropped or invented digit in one CP read is not a contradiction; a different HP is).
// Unreadable frames (mid-swipe) do not break a run. Within a run the fields are decided by vote;
// the pipeline then validates the CP candidates with the solver. Adjacent rows that are the
// same Pokémon settled twice are merged; non-adjacent identical rows are never merged.

/** Identity of a frame reading, or null when the frame did not identify a Pokémon. */
export function identity(r) {
  return r && r.cp && r.name ? `${r.name}|${r.cp}` : null;
}

/** Two CP reads that could be the same number: equal, one digit different, or one digit dropped. */
export function cpSimilar(a, b) {
  const x = String(a), y = String(b);
  if (x === y) return true;
  if (x.length === y.length && x.length >= 3) { let d = 0; for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) d++; return d <= 1; }
  const [s, l] = x.length < y.length ? [x, y] : [y, x];
  if (l.length - s.length !== 1 || s.length < 2) return false;
  for (let i = 0; i < l.length; i++) if (l.slice(0, i) + l.slice(i + 1) === s) return true;
  return false;
}

const hpAgree = (a, b) => !a || !b || a.max === b.max;
/** Bars settle to whole units; a read far from whole units is mid-animation and says nothing. */
export const SETTLED = 0.7;
/** Two bar reads agree when either is unsettled, or both are settled and equal. */
export function ivsCompatible(a, b, ca = 1, cb = 1) {
  if (!a || !b || ca < SETTLED || cb < SETTLED) return true;
  return a.atk === b.atk && a.def === b.def && a.hp === b.hp;
}

/**
 * Group consecutive compatible readings into runs: [{ key, frames: [reading] }]. A frame joins the
 * current run when it is compatible with the previous frame and with the run as a whole: the
 * run's HP (first read), its fullest bar read, and its most-read CP.
 */
export function groupRuns(readings) {
  const runs = [];
  let cur = null;
  for (const r of readings) {
    if (!identity(r)) continue;
    if (cur && joins(cur, r)) {
      cur.frames.push(r);
      if (r.hp && !cur.hp) cur.hp = r.hp;
      if (r.ivs && r.ivConfidence >= SETTLED && !cur.ivs) cur.ivs = r.ivs;
      for (const c of r.cpReads ?? [r.cp]) cur.cpCounts.set(c, (cur.cpCounts.get(c) ?? 0) + 1);
    } else {
      cur = { key: identity(r), frames: [r], hp: r.hp ?? null, ivs: r.ivs && r.ivConfidence >= SETTLED ? r.ivs : null, cpCounts: new Map((r.cpReads ?? [r.cp]).map((c) => [c, 1])) };
      runs.push(cur);
    }
  }
  return runs;
}

function joins(run, r) {
  const last = run.frames[run.frames.length - 1];
  if (last.name !== r.name) return false;
  // Bars are not used to split runs: a mid-animation read can look settled by chance, and two
  // consecutive Pokémon with the same name, CP and HP but different IVs are rarer than that.
  if (!hpAgree(run.hp, r.hp)) return false;
  const topCp = [...run.cpCounts.entries()].sort((a, b) => b[1] - a[1])[0][0];
  const reads = r.cpReads ?? [r.cp];
  if (reads.some((c) => cpSimilar(c, last.cp) || cpSimilar(c, topCp))) return true;
  // A badly garbled CP read on a frame whose HP and settled bars match the run exactly is still the same Pokémon.
  return Boolean(run.hp && r.hp && run.ivs && r.ivs && (r.ivConfidence ?? 0) >= SETTLED && run.hp.max === r.hp.max && run.ivs.atk === r.ivs.atk && run.ivs.def === r.ivs.def && run.ivs.hp === r.ivs.hp);
}

/** Values ranked by count (ties: the later value); returns [{ v, n }]. */
export function ranked(values, keyOf = (v) => JSON.stringify(v)) {
  const counts = new Map();
  for (const v of values) {
    if (v === null || v === undefined) continue;
    const k = keyOf(v);
    const e = counts.get(k) ?? { v, n: 0 };
    e.n++; e.v = v; counts.set(k, e);
  }
  return [...counts.values()].sort((a, b) => b.n - a.n);
}

export function vote(values, keyOf) { return ranked(values, keyOf)[0]?.v ?? null; }

/**
 * Collapse a run to one reading. CP candidates are every CP read in the run ranked by count (the
 * pipeline picks the first that the solver accepts); HP by vote; the bars from the frame with the
 * fullest confident read (the latest point of the fill animation).
 */
export function collapseRun(run) {
  const frames = run.frames;
  const cpCandidates = ranked(frames.flatMap((f) => f.cpReads ?? [f.cp]));
  const hp = vote(frames.map((f) => f.hp?.max ?? null));
  // Bars: the panel animates from the previous Pokémon's bars to this one's, so only settled
  // reads (whole units) count; they are voted, ties to the later frame. With no settled read the
  // last read is the closest to the final state and is flagged.
  const settled = frames.filter((f) => f.ivs && f.ivConfidence >= SETTLED);
  let best = null;
  if (settled.length) { const v = vote(settled.map((f) => f.ivs), (x) => `${x.atk}/${x.def}/${x.hp}`); best = { f: settled.filter((f) => f.ivs.atk === v.atk && f.ivs.def === v.def && f.ivs.hp === v.hp).pop() }; }
  else { const any = frames.filter((f) => f.ivs); if (any.length) best = { f: any[any.length - 1] }; }
  return {
    name: frames[0].name, cp: cpCandidates[0].v, cpCandidates: cpCandidates.map((c) => c.v),
    hp, ivs: best?.f.ivs ?? null, ivConfidence: best?.f.ivConfidence ?? 0, fills: best?.f.fills ?? null,
    speciesIds: frames[0].speciesIds, form: frames[0].form, baseName: frames[0].baseName,
    frames: frames.map((f) => ({ frame: f.frame, time: f.time, cp: f.cp, cpText: f.cpText, name: f.nameText, hp: f.hp ? `${f.hp.current}/${f.hp.max}` : null, ivs: f.ivs ? `${f.ivs.atk}/${f.ivs.def}/${f.ivs.hp}` : null, ivConfidence: f.ivConfidence, sharpness: f.sharpness })),
  };
}

/**
 * Merge adjacent rows that are the same Pokémon (same name and CP, HP and IVs not in conflict).
 * Keeps the row with more information. Never merges rows that are not adjacent.
 */
export function dedupeAdjacent(rows) {
  const out = [];
  for (const r of rows) {
    const prev = out[out.length - 1];
    if (prev && prev.name === r.name && prev.cp === r.cp && agree(prev.hp, r.hp) && ivsCompatible(prev.ivs, r.ivs, prev.ivConfidence, r.ivConfidence)) {
      const keep = score(r) > score(prev) ? { ...r } : { ...prev };
      keep.hp = prev.hp ?? r.hp; keep.ivs = keep.ivs ?? prev.ivs ?? r.ivs;
      keep.cpCandidates = [...new Set([...(prev.cpCandidates ?? []), ...(r.cpCandidates ?? [])])];
      keep.frames = [...prev.frames, ...r.frames];
      keep.merged = (prev.merged ?? 1) + 1;
      out[out.length - 1] = keep;
    } else out.push({ ...r });
  }
  return out;
}

const agree = (a, b) => a === null || b === null || a === undefined || b === undefined || a === b;
const score = (r) => (r.hp ? 1 : 0) + (r.ivs ? 2 : 0) + r.frames.length / 100;
