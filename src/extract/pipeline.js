// The extractor: frames in, roster rows out. Shared by the CLI (frames from ffmpeg PNGs) and the
// web page (frames from a <video> element). Frames arrive through an async iterable so neither
// side has to hold a whole recording in memory.

import { readFrame } from './frame.js';
import { displayNames, nameAndForm } from './names.js';
import { groupRuns, collapseRun, dedupeAdjacent, cpSimilar, ivsCompatible, vote, SETTLED } from './merge.js';
import { solve, speciesFor } from './solve.js';
import { step as dustStep } from '../cost.js';
import { cpAt, hpAt, LEVELS } from '../cpm.js';

/**
 * @param frames    async iterable of { index, time, image, label }
 * @param ocr       from createOcr
 * @param gm        indexed game master
 * @param onProgress ({ done, total, found, reading }) after each frame; total may be null
 * @returns { rows, review, readings }
 */
export async function extract(frames, { ocr, gm, onProgress = () => {}, total = null }) {
  const names = displayNames(gm);
  const readings = [];
  let done = 0, found = 0, lastKey = null;
  for await (const f of frames) {
    const r = await readFrame(f.image, ocr, names, { frame: f.label ?? f.index, time: f.time });
    readings.push(r);
    done++;
    const key = r.cp && r.name ? `${r.name}|${r.cp}` : null;
    if (key && key !== lastKey) { found++; lastKey = key; }
    onProgress({ done, total, found, reading: r });
  }
  return { ...finish(readings, gm), readings };
}

/** Everything after the frames are read: group, vote, solve, dedupe, flag. */
export function finish(readings, gm) {
  readings = supportedNames(readings);
  const runs = groupRuns(readings);
  const collapsed = runs.map((run) => ({ ...collapseRun(run), nameWeak: run.frames.every((f) => f.nameWeak) }));
  const { rows, absorbed } = absorbStrays(dedupeAdjacent(collapsed).map((row) => resolveRow(row, gm)));
  rows.forEach((r, i) => { r.index = i + 1; });
  // What was on screen and did not become a row is listed, so it is not silently missing: frames
  // that showed a CP but no species name (a nickname, or a garbled read: two frames or more in a
  // row with the same CP, so a single frame caught mid-change is not listed); a named Pokémon whose
  // CP was never read (hidden behind its model), with the CPs its HP and bars allow; and a
  // one-frame row folded into its neighbour.
  const unmatched = [...unnamedEntries(readings), ...hiddenEntries(readings, runs, gm), ...absorbed];
  const review = rows.filter((r) => r.flags.length).map((r) => ({ index: r.index, name: r.name, cp: r.cp, hp: r.hp, ivs: r.ivs, ivsRead: r.ivsRead, ivsGuess: r.ivsGuess, level: r.level, levelMax: r.levelMax, flags: r.flags, frames: r.frames }));
  return { rows, review, unmatched };
}

/**
 * The CPs a Pokémon could have, from what a model in front of the CP text cannot hide: its HP and
 * its settled bars. Each level whose HP matches gives one CP. `reads` are the partial CP reads
 * (the model usually covers the leading digits, so a read is the tail of the real number).
 * Returns { options, supported, tailOf }: every CP that fits, those a partial read is the tail
 * of, and for each of those the read that supports it.
 */
export function cpOptions(species, { hp, ivs, ivConfidence = 1 }, reads = []) {
  if (!hp || !ivs || ivConfidence < SETTLED) return { options: [], supported: [], tailOf: new Map() };
  const options = new Set();
  for (const sp of species) for (const level of LEVELS) if (hpAt(sp.baseStats, ivs, level) === hp) options.add(cpAt(sp.baseStats, ivs, level));
  const tails = reads.filter((r) => r >= 10).map(String);
  const all = [...options].sort((a, b) => a - b);
  const tailOf = new Map();
  for (const cp of all) { const t = tails.find((x) => x.length < String(cp).length && String(cp).endsWith(x)); if (t) tailOf.set(cp, Number(t)); }
  return { options: all, supported: [...tailOf.keys()], tailOf };
}

/**
 * A name read without OCR confidence counts only when the nearest named frame before or after it
 * has the same name; otherwise the frame is treated as unnamed. One such frame in the middle of
 * another Pokémon's frames ("Paras" on one frame of a Parasect) would otherwise split its run in
 * two. A Pokémon whose every frame was read that way keeps its frames and its row is flagged.
 */
export function supportedNames(readings) {
  const named = readings.map((r, i) => (r?.name ? i : -1)).filter((i) => i >= 0);
  return readings.map((r, i) => {
    if (!r?.nameWeak) return r;
    const at = named.indexOf(i);
    const around = [named[at - 1], named[at + 1]].filter((j) => j !== undefined).map((j) => readings[j].name);
    if (!around.length || around.includes(r.name)) return r;
    return { ...r, name: null, nameWeak: false, flags: [...(r.flags ?? []), 'name-unsupported'] };
  });
}

function resolveRow(row, gm) {
  const species = speciesFor(gm, row.speciesIds ?? []);
  const flags = [];
  // The CP: the first candidate read (ranked by how many frames read it) that the solver can
  // reconcile with the HP and bars; failing that, the most-read one.
  const candidates = row.cpCandidates ?? [row.cp];
  let cp = row.cp, result = null;
  for (const candidate of candidates) {
    const r = solve({ species, cp: candidate, hp: row.hp, ivs: row.ivs });
    if (r.solutions.length && (!row.ivs || r.solutions[0].tier <= 1)) { cp = candidate; result = r; break; }
  }
  if (result) { if (cp !== row.cp) flags.push(`cp-chosen-${cp}-over-${row.cp}`); }
  else {
    // No read fits. When the model covered the leading digits, the reads are the tail of the real
    // CP: work the CP out from the HP and the settled bars, and take it when exactly one such CP
    // ends in a read and no read at all is as long as it (a full-length read that does not fit
    // means misread bars, not a hidden digit). The row stays flagged for a check in the game.
    const { supported, tailOf } = cpOptions(species, row, candidates);
    if (supported.length === 1 && !candidates.some((c) => String(c).length >= String(supported[0]).length)) { cp = supported[0]; flags.push(`cp-recovered:${cp}-from-${tailOf.get(cp)}`); }
    result = solve({ species, cp, hp: row.hp, ivs: row.ivs });
  }
  let ivs = row.ivs, level = null, levelMax = null, speciesId = species[0]?.speciesId ?? null, hp = row.hp;
  const s = result.solutions[0];
  const take = () => { ivs = s.ivs; level = s.level; levelMax = s.level; speciesId = s.speciesId; if (hp === null) { hp = s.hp; flags.push('hp-computed'); } };
  switch (result.status) {
    case 'exact': {
      take();
      const levels = new Set(result.solutions.filter((x) => x.tier === 0).map((x) => x.level));
      if (levels.size > 1) { level = Math.min(...levels); levelMax = Math.max(...levels); flags.push(`level-ambiguous:${[...levels].join('|')}`); }
      break;
    }
    case 'corrected': take(); flags.push(`ivs-corrected-from-${row.ivs.atk}/${row.ivs.def}/${row.ivs.hp}`); break;
    case 'ambiguous': {
      // Several IV sets fit: export none of them (the advisor must not treat a guess as fact) and
      // give the level range they span; the nearest guess stays in review.json.
      const top = result.solutions.filter((x) => x.tier === s.tier);
      ivs = null; level = Math.min(...top.map((x) => x.level)); levelMax = Math.max(...top.map((x) => x.level)); speciesId = s.speciesId;
      if (hp === null) { hp = s.hp; flags.push('hp-computed'); }
      flags.push(`ambiguous-ivs:${top.length}-fit`);
      break;
    }
    case 'unknown-ivs': {
      ivs = null;
      if (s) speciesId = s.speciesId; // the species that fits, not just the first the name could be
      const levels = result.solutions.map((x) => x.level);
      if (levels.length) { level = Math.min(...levels); levelMax = Math.max(...levels); }
      flags.push('ivs-unread');
      break;
    }
    default: ivs = null; flags.push('no-level-fits');
  }
  if (result.forms?.length > 1) flags.push(`form-ambiguous:${result.forms.join('|')}`);
  if (row.ivsDisagree) flags.push('ivs-disagree');
  // Every frame's name was read without OCR confidence: it can be a longer name cut short by an
  // overlay ("Paras" from "Parasect"), so the row is for a check in the game.
  if (row.nameWeak) flags.push('name-low-confidence');
  // The screen cannot tell Nidoran♀ from Nidoran♂ here (the symbol is not read): the sex is the
  // one whose stats fit the CP, HP and bars, so a misread CP could also pick the wrong one.
  if (row.name === 'Nidoran') flags.push('sex-from-stats');
  if (hp === null) flags.push('hp-unread');
  if (row.ivs && row.ivConfidence < SETTLED) flags.push('bars-unsettled');
  // Name and form as Poke Genie writes them, from the species the solver settled on (the screen
  // shows "Zamazenta" for both the Hero and the Crowned Shield form).
  const sp = speciesId ? gm.byId.get(speciesId) : null;
  const nf = sp ? nameAndForm(sp) : { name: row.baseName ?? row.name, form: row.form ?? '' };
  return {
    index: null, name: nf.name, display: row.name, form: nf.form, speciesId, dex: sp?.dex ?? null,
    cp, hp, ivs, ivsRead: row.ivs, ivsGuess: ivs === null && s ? s.ivs : null, level, levelMax,
    dust: level ? dustStep(level).dust : null,
    solveStatus: result.status, flags, frames: row.frames, merged: row.merged ?? 1,
  };
}

/**
 * Frames that showed a CP but no species name, as entries for `unmatched`: one per stretch of
 * two or more such frames in a row whose CPs agree. { frame, cp, nameText, hp: null, frames, reason }.
 */
function unnamedEntries(readings) {
  const out = [];
  let cur = null;
  const close = () => { if (cur && cur.frames >= 2) out.push({ frame: cur.frame, cp: vote(cur.cps), nameText: vote(cur.texts) ?? '', hp: null, frames: cur.frames, reason: 'name-not-read' }); cur = null; };
  for (const r of readings) {
    if (!r.cp || r.name) { close(); continue; }
    if (cur && cur.cps.some((c) => cpSimilar(c, r.cp))) { cur.cps.push(r.cp); cur.texts.push(r.nameText || null); cur.frames++; }
    else { close(); cur = { frame: r.frame, cps: [r.cp], texts: [r.nameText || null], frames: 1 }; }
  }
  close();
  return out;
}

/**
 * Pokémon that were on screen with a name but no CP on any frame (the model covered it), as
 * entries for `unmatched`: name, HP, settled bars and the CPs those allow, for a check in the
 * game. Such frames never join a run (rows are built exactly as if they were unreadable); a
 * stretch of them is one entry, unless it sits right beside a run of the same Pokémon (same name,
 * HP not different, bars not contradicting, no unreadable frame between), which is that Pokémon
 * with its model in front of the CP for a moment.
 */
function hiddenEntries(readings, runs, gm) {
  const runOf = new Map();
  for (const run of runs) for (const f of run.frames) runOf.set(f, run);
  const settledIvs = (frames) => vote(frames.filter((f) => f.ivs && f.ivConfidence >= SETTLED).map((f) => f.ivs), (x) => `${x.atk}/${x.def}/${x.hp}`);
  const stretches = [];
  let cur = null, prevRun = null, gap = false;
  for (const r of readings) {
    const run = runOf.get(r);
    if (run) {
      if (cur) { cur.next = run; cur.gapAfter = gap; cur = null; }
      prevRun = run; gap = false;
    } else if (r.name && !r.cp) {
      const hp = r.hp?.max ?? null;
      const ivs = r.ivs && r.ivConfidence >= SETTLED ? r.ivs : null;
      const same = cur && cur.name === r.name && (cur.hp === null || hp === null || cur.hp === hp) && (!gap || ivsCompatible(settledIvs(cur.frames), ivs));
      if (same) { cur.frames.push(r); cur.hp ??= hp; }
      else { cur = { name: r.name, hp, frames: [r], prev: prevRun, gapBefore: gap || cur !== null, next: null, gapAfter: true }; stretches.push(cur); }
      gap = false;
    } else gap = true;
  }
  const beside = (s, run, gapBetween) => run && !gapBetween && run.frames[0].name === s.name && (s.hp === null || !run.hp || run.hp.max === s.hp) && ivsCompatible(run.ivs, settledIvs(s.frames));
  return stretches.filter((s) => !beside(s, s.prev, s.gapBefore) && !beside(s, s.next, s.gapAfter)).map((s) => {
    const ivs = settledIvs(s.frames);
    return {
      frame: s.frames[0].frame, cp: null, name: s.name, nameText: s.frames[0].nameText, hp: s.hp, ivs,
      cpOptions: cpOptions(speciesFor(gm, s.frames[0].speciesIds ?? []), { hp: s.hp, ivs }).options, frames: s.frames.length, reason: 'cp-not-read',
    };
  });
}

/**
 * A one-frame row with no HP and no settled bars that did not solve, next to a row of the same
 * Pokémon with a similar CP, is almost always that Pokémon caught on the frame before its screen
 * settled (one digit misread, HP not yet drawn). Its frame goes to the neighbour, and because it
 * could be a Pokémon of its own it is also listed in `unmatched`. The same goes for a one-frame
 * unsolved row sitting between two rows that are one and the same solved Pokémon: a single
 * garbled frame split that Pokémon's run, and the two halves are put back together.
 * Returns { rows, absorbed }.
 */
function absorbStrays(rows) {
  const out = [], absorbed = [];
  const bare = (r) => (r.flags.includes('hp-computed') || r.flags.includes('hp-unread')) && (!r.ivsRead || r.flags.includes('bars-unsettled'));
  const stray = (r, other) => r.frames.length === 1 && bare(r) && r.solveStatus !== 'exact' && other && other.frames.length > 1 && other.display === r.display && cpSimilar(r.cp, other.cp);
  const note = (r, other) => absorbed.push({ frame: r.frames[0].frame, cp: r.cp, name: r.display, nameText: r.frames[0].name, hp: null, reason: 'absorbed', into: other.cp });
  const sameIvs = (a, b) => a && b && a.atk === b.atk && a.def === b.def && a.hp === b.hp;
  const halves = (a, b) => a && b && a.solveStatus === 'exact' && b.solveStatus === 'exact' && a.display === b.display && a.cp === b.cp && a.hp === b.hp && sameIvs(a.ivs, b.ivs);
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i], prev = out[out.length - 1], next = rows[i + 1];
    if (r.frames.length === 1 && r.solveStatus !== 'exact' && halves(prev, next)) {
      note(r, prev);
      prev.frames = [...prev.frames, ...r.frames, ...next.frames];
      prev.flags = [...new Set([...prev.flags, ...next.flags])];
      i++;
      continue;
    }
    if (stray(r, prev)) { note(r, prev); prev.frames = [...prev.frames, ...r.frames]; continue; }
    if (stray(r, next)) { note(r, next); next.frames = [...r.frames, ...next.frames]; continue; }
    out.push(r);
  }
  return { rows: out, absorbed };
}

/** Poke Genie's column layout, so src/import/pokegenie.js reads the result back. */
export const POKEGENIE_COLUMNS = ['Index', 'Name', 'Form', 'Pokemon Number', 'Gender', 'CP', 'HP', 'Atk IV', 'Def IV', 'Sta IV', 'IV Avg', 'Level Min', 'Level Max', 'Quick Move', 'Charge Move', 'Charge Move 2', 'Scan Date', 'Original Scan Date', 'Catch Date', 'Weight', 'Height', 'Lucky', 'Shadow/Purified', 'Favorite', 'Dust', 'Rank % (G)', 'Rank # (G)', 'Stat Prod (G)', 'Dust Cost (G)', 'Candy Cost (G)', 'Name (G)', 'Form (G)', 'Sha/Pur (G)', 'Rank % (U)', 'Rank # (U)', 'Stat Prod (U)', 'Dust Cost (U)', 'Candy Cost (U)', 'Name (U)', 'Form (U)', 'Sha/Pur (U)', 'Rank % (L)', 'Rank # (L)', 'Stat Prod (L)', 'Dust Cost (L)', 'Candy Cost (L)', 'Name (L)', 'Form (L)', 'Sha/Pur (L)', 'Marked for PvP use'];

export function toPokeGenieCsv(rows, { scanDate = new Date() } = {}) {
  const date = `${scanDate.getFullYear()}-${String(scanDate.getMonth() + 1).padStart(2, '0')}-${String(scanDate.getDate()).padStart(2, '0')} ${String(scanDate.getHours()).padStart(2, '0')}:${String(scanDate.getMinutes()).padStart(2, '0')}`;
  const q = (v) => { const s = v === null || v === undefined ? '' : String(v); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const lines = [POKEGENIE_COLUMNS.join(',')];
  for (const r of rows) {
    const rec = {
      Index: r.index, Name: r.name, Form: r.form, 'Pokemon Number': r.dex ?? '', Gender: '', CP: r.cp, HP: r.hp ?? '',
      'Atk IV': r.ivs?.atk ?? '', 'Def IV': r.ivs?.def ?? '', 'Sta IV': r.ivs?.hp ?? '',
      'IV Avg': r.ivs ? ((r.ivs.atk + r.ivs.def + r.ivs.hp) / 45 * 100).toFixed(1) : '',
      'Level Min': r.level !== null ? r.level.toFixed(1) : '', 'Level Max': r.levelMax !== null ? r.levelMax.toFixed(1) : '',
      // Lucky and Favourite are not read from the screen: left blank, not asserted as 0. Shadow/
      // Purified is only known when a batch merge marked the row from a Shadow-filtered pass
      // (1 shadow, 2 purified); otherwise it is unread, so blank rather than 0.
      'Scan Date': date, 'Original Scan Date': date, Lucky: '', 'Shadow/Purified': r.shadow === 1 || r.shadow === 2 ? r.shadow : '', Favorite: '', Dust: r.dust ?? '',
    };
    lines.push(POKEGENIE_COLUMNS.map((c) => q(rec[c] ?? '')).join(','));
  }
  return lines.join('\n') + '\n';
}
