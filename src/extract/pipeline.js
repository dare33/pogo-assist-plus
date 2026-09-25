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
  const review = rows.filter((r) => r.flags.length).map((r) => ({ index: r.index, name: r.name, cp: r.cp, hp: r.hp, ivs: r.ivs, level: r.level, flags: r.flags, frames: r.frames }));
  return { rows, review };
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
    case 'exact': take(); break;
    case 'corrected': take(); flags.push(`ivs-corrected-from-${row.ivs.atk}/${row.ivs.def}/${row.ivs.hp}`); break;
    case 'ambiguous': take(); flags.push(`ambiguous-ivs:${result.solutions.filter((x) => x.tier === s.tier).length}-fit`); break;
    case 'unknown-ivs': {
      ivs = null;
      const levels = result.solutions.map((x) => x.level);
      if (levels.length) { level = Math.min(...levels); levelMax = Math.max(...levels); }
      flags.push('ivs-unread');
      break;
    }
    default: flags.push('no-level-fits');
  }
  if (hp === null) flags.push('hp-unread');
  if (row.ivs && row.ivConfidence < SETTLED) flags.push('bars-unsettled');
  // Name and form as Poke Genie writes them, from the species the solver settled on (the screen
  // shows "Zamazenta" for both the Hero and the Crowned Shield form).
  const sp = speciesId ? gm.byId.get(speciesId) : null;
  const nf = sp ? nameAndForm(sp) : { name: row.baseName ?? row.name, form: row.form ?? '' };
  return {
    index, name: nf.name, display: row.name, form: nf.form, speciesId, dex: sp?.dex ?? null,
    cp, hp, ivs, level, levelMax,
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
      'Scan Date': date, 'Original Scan Date': date, Lucky: 0, 'Shadow/Purified': 0, Favorite: 0, Dust: r.dust ?? '',
    };
    lines.push(POKEGENIE_COLUMNS.map((c) => q(rec[c] ?? '')).join(','));
  }
  return lines.join('\n') + '\n';
}
