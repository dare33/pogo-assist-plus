// Merge several clips of one account into one roster. Pure and browser-safe (no node: imports):
// the batch CLI and the extractor page both call mergeClips with rows from extract().
//
// A box is recorded as several clips (a phone recording is restarted, or a Shadow-filtered pass
// is recorded separately). Within a kind of pass the clips are joined in order, dropping the
// Pokémon repeated where one clip ended and the next began; the Shadow/Purified passes are then
// reconciled into the normal pass by marking the rows they match.
//
// Rows here are what resolveRow() in pipeline.js produces: they carry `ivs` (null when unread or
// ambiguous), `hp`, `flags` and `solveStatus`, but no ivConfidence, so "could these two rows be
// the same Pokémon" is judged from the flags: bars that were never settled, corrected or
// disagreeing IVs, and a computed HP are guesses and do not count as a conflict.

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

const has = (v) => v !== null && v !== undefined;
const flagged = (r, f) => (r.flags ?? []).some((x) => x === f || x.startsWith(`${f}-`) || x.startsWith(`${f}:`));

/** IVs on this row are a guess (bars unsettled, corrected, disagreeing), so they cannot conflict. */
export const ivsLenient = (r) => flagged(r, 'bars-unsettled') || flagged(r, 'ivs-corrected-from') || flagged(r, 'ivs-disagree') || r.solveStatus === 'corrected';
/** HP on this row was computed from the solved level, not read. */
export const hpLenient = (r) => flagged(r, 'hp-computed');

/** Could two extractor rows be the same Pokémon? Guessed HP or IVs, and a missing HP, do not conflict. */
export function sameMon(a, b) {
  if (a.name !== b.name || (a.form ?? '') !== (b.form ?? '') || a.cp !== b.cp) return false;
  if (has(a.hp) && has(b.hp) && !hpLenient(a) && !hpLenient(b) && a.hp !== b.hp) return false;
  if (a.ivs && b.ivs && !ivsLenient(a) && !ivsLenient(b) && !ivsCompatible(a.ivs, b.ivs, a.ivConfidence ?? 1, b.ivConfidence ?? 1)) return false;
  return true;
}

/** A match that rests on less than both rows' HP and IVs being read and equal. */
export function weakPair(a, b) {
  return !has(a.hp) || !has(b.hp) || !a.ivs || !b.ivs || ivsLenient(a) || ivsLenient(b) || hpLenient(a) || hpLenient(b);
}

/**
 * How the end of `tailRows` overlaps the start of `headRows`. `k` is the SMALLEST k <= max such
 * that the last k of the tail match the first k of the head pairwise (for distinct Pokémon only
 * the true overlap is consistent; for a run of identical rows the smallest k drops the fewest,
 * so no Pokémon is lost). `weak` when more than one k is consistent or any matched pair is weak.
 */
export function overlapInfo(tailRows, headRows, { max = 10 } = {}) {
  const consistent = [];
  for (let k = 1; k <= Math.min(max, tailRows.length, headRows.length); k++) {
    let ok = true;
    for (let i = 0; i < k && ok; i++) ok = sameMon(tailRows[tailRows.length - k + i], headRows[i]);
    if (ok) consistent.push(k);
  }
  if (!consistent.length) return { k: 0, weak: false };
  const k = consistent[0];
  let weak = consistent.length > 1;
  for (let i = 0; i < k; i++) weak ||= weakPair(tailRows[tailRows.length - k + i], headRows[i]);
  return { k, weak };
}

export const overlapLength = (tailRows, headRows, opts) => overlapInfo(tailRows, headRows, opts).k;

const richness = (r) => [r.ivs ? 1 : 0, has(r.hp) ? 1 : 0, r.frames?.length ?? 0];
const richer = (a, b) => { const x = richness(a), y = richness(b); for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i]; return false; };

/**
 * One row standing for the same Pokémon seen twice: the fuller row (IVs, then HP, then frames),
 * frames and flags unioned, and flags that the other row's data has made stale removed.
 */
export function combine(a, b) {
  const bFuller = richer(b, a);
  const keep = { ...(bFuller ? b : a) }, other = bFuller ? a : b;
  // HP: a read beats a computed one, and any HP beats none.
  let computed = hpLenient(keep);
  if (has(other.hp) && (!has(keep.hp) || (computed && !hpLenient(other)))) { keep.hp = other.hp; computed = hpLenient(other); }
  if (!keep.ivs && other.ivs) keep.ivs = other.ivs;
  const flags = new Set([...(a.flags ?? []), ...(b.flags ?? [])]);
  if (keep.ivs) for (const f of flags) if (f.startsWith('ambiguous-ivs') || f === 'ivs-unread' || f === 'no-level-fits') flags.delete(f);
  if (has(keep.hp)) flags.delete('hp-unread');
  if (has(keep.hp) && computed) flags.add('hp-computed'); else flags.delete('hp-computed');
  keep.frames = [...(a.frames ?? []), ...(b.frames ?? [])];
  keep.flags = [...flags];
  return keep;
}

const nameCp = (r) => ({ name: r.display ?? r.name, cp: r.cp });

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
    for (const c of tagged.filter((x) => x.kind === kind)) {
      let rows = c.rows;
      if (out.length) {
        const { k, weak } = overlapInfo(out, rows, { max: maxOverlap });
        if (k) {
          // The tail row may itself belong to an earlier clip (a clip that was wholly overlap).
          const before = out[out.length - 1].clip;
          const droppedRows = rows.slice(0, k).map(nameCp);
          for (let i = 0; i < k; i++) {
            const at = out.length - k + i, clipOf = out[at].clip;
            out[at] = combine(out[at], rows[i]);
            out[at].clip = clipOf;
            if (weak && !out[at].flags.includes('boundary-weak')) out[at].flags.push('boundary-weak');
          }
          boundaries.push({ before, after: c.name, dropped: k, weak, droppedRows });
          rows = rows.slice(k);
        }
      }
      out.push(...rows);
    }
    return out;
  };

  const merged = joinKind('normal');
  const reconciled = { matched: 0, appended: 0, ambiguous: 0, weak: 0 };
  const strong = (s, r) => !weakPair(s, r) && s.hp === r.hp && s.ivs.atk === r.ivs.atk && s.ivs.def === r.ivs.def && s.ivs.hp === r.ivs.hp;
  for (const [kind, mark] of [['shadow', 1], ['purified', 2]]) {
    for (const s of joinKind(kind)) {
      s.shadow = mark;
      const candidates = merged.filter((r) => !r.shadow && sameMon(s, r));
      if (!candidates.length) { merged.push(s); reconciled.appended++; continue; }
      const strongOnes = candidates.filter((r) => strong(s, r));
      const pool = strongOnes.length ? strongOnes : candidates;
      const r = pool[0], at = merged.indexOf(r);
      const isWeak = !strong(s, r), isAmbiguous = pool.length > 1;
      const m = combine(r, s);
      m.clip = r.clip; m.shadow = mark;
      if (isAmbiguous && !m.flags.includes('shadow-match-ambiguous')) m.flags.push('shadow-match-ambiguous');
      if (isWeak && !m.flags.includes('shadow-match-weak')) m.flags.push('shadow-match-weak');
      merged[at] = m;
      if (isAmbiguous) reconciled.ambiguous++;
      if (isWeak) reconciled.weak++;
      if (!isAmbiguous && !isWeak) reconciled.matched++;
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
