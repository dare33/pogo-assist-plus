// The extractor: frames in, roster rows out. Shared by the CLI (frames from ffmpeg PNGs) and the
// web page (frames from a <video> element). Frames arrive through an async iterable so neither
// side has to hold a whole recording in memory.

import { readFrame } from './frame.js';
import { displayNames, nameAndForm } from './names.js';
import { groupRuns, collapseRun, dedupeAdjacent, SETTLED } from './merge.js';
import { solve, speciesFor } from './solve.js';
import { step as dustStep } from '../cost.js';

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
  const runs = groupRuns(readings);
  const collapsed = runs.map(collapseRun);
  const rows = dedupeAdjacent(collapsed).map((row, i) => resolveRow(row, gm, i + 1));
  // Frames that showed a CP but no species name (a nickname, or a garbled read) never become a
  // row; list them so a Pokémon that was on screen and not read is not silently missing.
  const unmatched = readings.filter((r) => r.cp && !r.name).map((r) => ({ frame: r.frame, cp: r.cp, nameText: r.nameText, hp: r.hp?.max ?? null }));
  const review = rows.filter((r) => r.flags.length).map((r) => ({ index: r.index, name: r.name, cp: r.cp, hp: r.hp, ivs: r.ivs, ivsRead: r.ivsRead, ivsGuess: r.ivsGuess, level: r.level, levelMax: r.levelMax, flags: r.flags, frames: r.frames }));
  return { rows, review, unmatched };
}

function resolveRow(row, gm, index) {
  const species = speciesFor(gm, row.speciesIds ?? []);
  const flags = [];
  // The CP: the first candidate read (ranked by how many frames read it) that the solver can
  // reconcile with the HP and bars; failing that, the most-read one.
  let cp = row.cp, result = null;
  for (const candidate of row.cpCandidates ?? [row.cp]) {
    const r = solve({ species, cp: candidate, hp: row.hp, ivs: row.ivs });
    if (r.solutions.length && (!row.ivs || r.solutions[0].tier <= 1)) { cp = candidate; result = r; break; }
  }
  if (!result) result = solve({ species, cp, hp: row.hp, ivs: row.ivs });
  if (cp !== row.cp) flags.push(`cp-chosen-${cp}-over-${row.cp}`);
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
      const levels = result.solutions.map((x) => x.level);
      if (levels.length) { level = Math.min(...levels); levelMax = Math.max(...levels); }
      flags.push('ivs-unread');
      break;
    }
    default: ivs = null; flags.push('no-level-fits');
  }
  if (result.forms?.length > 1) flags.push(`form-ambiguous:${result.forms.join('|')}`);
  if (row.ivsDisagree) flags.push('ivs-disagree');
  if (hp === null) flags.push('hp-unread');
  if (row.ivs && row.ivConfidence < SETTLED) flags.push('bars-unsettled');
  // Name and form as Poke Genie writes them, from the species the solver settled on (the screen
  // shows "Zamazenta" for both the Hero and the Crowned Shield form).
  const sp = speciesId ? gm.byId.get(speciesId) : null;
  const nf = sp ? nameAndForm(sp) : { name: row.baseName ?? row.name, form: row.form ?? '' };
  return {
    index, name: nf.name, display: row.name, form: nf.form, speciesId, dex: sp?.dex ?? null,
    cp, hp, ivs, ivsRead: row.ivs, ivsGuess: ivs === null && s ? s.ivs : null, level, levelMax,
    dust: level ? dustStep(level).dust : null,
    solveStatus: result.status, flags, frames: row.frames, merged: row.merged ?? 1,
  };
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
      // Shadow, Lucky and Favourite are not read from the screen: left blank, not asserted as 0.
      'Scan Date': date, 'Original Scan Date': date, Lucky: '', 'Shadow/Purified': '', Favorite: '', Dust: r.dust ?? '',
    };
    lines.push(POKEGENIE_COLUMNS.map((c) => q(rec[c] ?? '')).join(','));
  }
  return lines.join('\n') + '\n';
}
