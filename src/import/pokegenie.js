import { parseCsv } from '../csv.js';

const num = (v) => (v === '' || v === undefined ? null : Number(v));
const pct = (v) => (v === '' || v === undefined ? null : Number(String(v).replace('%', '')));

/**
 * Parse a Poke Genie storage export into normalised records.
 * Shadow/Purified column: 0 = neither, 1 = shadow, 2 = purified.
 */
export function importPokeGenie(csvText) {
  return parseCsv(csvText).map((r) => {
    const sp = Number(r['Shadow/Purified'] || 0);
    const ivs = { atk: num(r['Atk IV']), def: num(r['Def IV']), hp: num(r['Sta IV']) };
    const ivsKnown = ivs.atk !== null && ivs.def !== null && ivs.hp !== null;
    return {
      source: 'pokegenie',
      index: num(r.Index),
      name: r.Name.trim(),
      form: (r.Form || '').trim(),          // as Poke Genie writes it: '', 'Normal', 'Galar', 'Mega Y', 'Hero', '10%' ...
      gender: r.Gender || '',
      cp: num(r.CP),
      hp: num(r.HP),
      ivs: ivsKnown ? ivs : null,
      ivPercent: num(r['IV Avg']),
      levelMin: num(r['Level Min']),
      levelMax: num(r['Level Max']),
      level: num(r['Level Min']),          // Poke Genie's best estimate; equals levelMax when IVs are exact
      moves: [r['Quick Move'], r['Charge Move'], r['Charge Move 2']].map((m) => (m || '').trim()).filter(Boolean),
      shadow: sp === 1,
      purified: sp === 2,
      lucky: r.Lucky === '1',
      favorite: r.Favorite === '1',
      dust: num(r.Dust),                    // power-up dust at current level, as shown in game
      scanDate: r['Scan Date'] || '',
      pvp: {
        great: { rankPct: pct(r['Rank % (G)']), rank: num(r['Rank # (G)']), name: r['Name (G)'], form: r['Form (G)'], dust: num(r['Dust Cost (G)']), candy: num(r['Candy Cost (G)']) },
        ultra: { rankPct: pct(r['Rank % (U)']), rank: num(r['Rank # (U)']), name: r['Name (U)'], form: r['Form (U)'], dust: num(r['Dust Cost (U)']), candy: num(r['Candy Cost (U)']) },
        master: { rankPct: pct(r['Rank % (L)']), rank: num(r['Rank # (L)']), name: r['Name (L)'], form: r['Form (L)'], dust: num(r['Dust Cost (L)']), candy: num(r['Candy Cost (L)']) },
      },
      markedForPvp: (r['Marked for PvP use'] || '').trim() !== '',
    };
  });
}
