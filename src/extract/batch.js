// Merge several clips of one account into one roster. Pure and browser-safe (no node: imports):
// the batch CLI and the extractor page both call mergeClips with rows from extract().
//
// A box is recorded as several clips (a phone recording is restarted, or a Shadow-filtered pass
// is recorded separately). Within a kind of pass the clips are joined in order, dropping the
// Pokémon repeated where one clip ended and the next began; the Shadow/Purified passes are then
// reconciled into the normal pass by marking the rows they match.

import { ivsCompatible } from './merge.js';

/** Which pass a clip is, from its file name (directories are ignored). */
export function passKind(filename) {
  const base = String(filename).split(/[\\/]/).pop().toLowerCase();
  if (base.includes('shadow')) return 'shadow';
  if (base.includes('purified')) return 'purified';
  return 'normal';
}

/** String compare where digit runs compare as numbers (clip2 before clip10), ignoring case. */
export function naturalCompare(a, b) {
  const x = String(a).toLowerCase().match(/\d+|\D+/g) ?? [];
  const y = String(b).toLowerCase().match(/\d+|\D+/g) ?? [];
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    if (x[i] === y[i]) continue;
    const nx = /^\d/.test(x[i]), ny = /^\d/.test(y[i]);
    if (nx && ny) { const d = Number(x[i]) - Number(y[i]); if (d) return d; if (x[i].length !== y[i].length) return x[i].length - y[i].length; }
    else return x[i] < y[i] ? -1 : 1;
  }
  return x.length - y.length;
}

/** Sort `[{ name, mtimeMs }]` by name (natural), or by modified time then name. Returns a new array. */
export function orderClips(clips, { order = 'name' } = {}) {
  const byName = (a, b) => naturalCompare(a.name, b.name);
  return [...clips].sort(order === 'mtime' ? (a, b) => (a.mtimeMs - b.mtimeMs) || byName(a, b) : byName);
}

/** Could two extractor rows be the same Pokémon? A missing HP or unsettled bars do not conflict. */
export function sameMon(a, b) {
  if (a.name !== b.name || (a.form ?? '') !== (b.form ?? '') || a.cp !== b.cp) return false;
  if (a.hp !== null && a.hp !== undefined && b.hp !== null && b.hp !== undefined && a.hp !== b.hp) return false;
  return ivsCompatible(a.ivs ?? null, b.ivs ?? null, a.ivConfidence ?? 1, b.ivConfidence ?? 1);
}

/** Largest k <= max such that the last k of `tailRows` match the first k of `headRows` pairwise. */
export function overlapLength(tailRows, headRows, { max = 10 } = {}) {
  for (let k = Math.min(max, tailRows.length, headRows.length); k > 0; k--) {
    let ok = true;
    for (let i = 0; i < k && ok; i++) ok = sameMon(tailRows[tailRows.length - k + i], headRows[i]);
    if (ok) return k;
  }
  return 0;
}

const has = (v) => v !== null && v !== undefined;
const score = (r) => (has(r.hp) ? 1 : 0) + (r.ivs ? 2 : 0) + (r.frames?.length ?? 0) / 100;

/** One row standing for the same Pokémon seen twice: the fuller row, frames and flags unioned. */
function combine(a, b) {
  const bFuller = score(b) > score(a);
  const keep = { ...(bFuller ? b : a) }, other = bFuller ? a : b;
  if (!has(keep.hp)) keep.hp = other.hp ?? keep.hp;
  if (!keep.ivs && other.ivs) keep.ivs = other.ivs;
  keep.frames = [...(a.frames ?? []), ...(b.frames ?? [])];
  keep.flags = [...new Set([...(a.flags ?? []), ...(b.flags ?? [])])];
  return keep;
}

/**
 * @param clips ordered `[{ name, kind, rows, unmatched = [] }]`
 * @returns { rows, review, unmatched, boundaries, reconciled, clips }
 */
export function mergeClips(clips, { maxOverlap = 10 } = {}) {
  const tagged = clips.map((c) => ({
    ...c,
    rows: c.rows.map((r) => ({ ...r, clip: c.name, flags: [...(r.flags ?? [])], frames: (r.frames ?? []).map((f) => ({ ...f, clip: c.name })) })),
  }));

  const boundaries = [];
  const joinKind = (kind) => {
    const out = [];
    let prev = null;
    for (const c of tagged.filter((x) => x.kind === kind)) {
      let rows = c.rows;
      if (prev) {
        const k = overlapLength(prev.rows, rows, { max: maxOverlap });
        if (k) {
          for (let i = 0; i < k; i++) out[out.length - k + i] = combine(out[out.length - k + i], rows[i]);
          boundaries.push({ before: prev.name, after: c.name, dropped: k });
          rows = rows.slice(k);
        }
      }
      out.push(...rows);
      // The next boundary compares against this clip's own tail, which after a full-overlap
      // clip is the previous clip's rows, so track what is actually at the end of `out`.
      prev = { name: c.name, rows: out };
    }
    return out;
  };

  const merged = joinKind('normal');
  const reconciled = { matched: 0, appended: 0, ambiguous: 0 };
  for (const [kind, mark] of [['shadow', 1], ['purified', 2]]) {
    for (const s of joinKind(kind)) {
      s.shadow = mark;
      const hits = merged.filter((r) => !r.shadow && sameMon(s, r) && (!s.ivs || !r.ivs || (s.ivs.atk === r.ivs.atk && s.ivs.def === r.ivs.def && s.ivs.hp === r.ivs.hp)));
      if (hits.length === 0) { merged.push(s); reconciled.appended++; continue; }
      const r = hits[0];
      r.shadow = mark;
      r.frames = [...(r.frames ?? []), ...(s.frames ?? [])];
      if (hits.length > 1) { r.flags = [...new Set([...r.flags, 'shadow-match-ambiguous'])]; reconciled.ambiguous++; }
      else reconciled.matched++;
    }
  }

  merged.forEach((r, i) => { r.index = i + 1; });
  const review = merged.filter((r) => r.flags.length).map((r) => ({ index: r.index, name: r.name, cp: r.cp, hp: r.hp, ivs: r.ivs, ivsRead: r.ivsRead, ivsGuess: r.ivsGuess, level: r.level, levelMax: r.levelMax, flags: r.flags, frames: r.frames, clip: r.clip, shadow: r.shadow }));
  const unmatched = tagged.flatMap((c) => (c.unmatched ?? []).map((u) => ({ ...u, clip: c.name })));
  return {
    rows: merged, review, unmatched, boundaries, reconciled,
    clips: tagged.map((c) => ({ name: c.name, kind: c.kind, rows: c.rows.length, flagged: c.rows.filter((r) => r.flags.length).length })),
  };
}
