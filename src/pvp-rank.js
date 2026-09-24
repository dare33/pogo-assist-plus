// IV rank under a CP cap: the standard stat-product ranking used by PvPoke and Poke Genie.
import { LEVELS, cpAt, statProduct } from './cpm.js';

const CAPS = { gl: 1500, ul: 2500 };

/** Best level under the cap for a spread, and its CP and stat product. */
export function bestUnderCap(base, ivs, cap, maxLevel = 51) {
  let best = null;
  for (const lv of LEVELS) {
    if (lv > maxLevel) break;
    const cp = cpAt(base, ivs, lv);
    if (cp > cap) break;
    best = { level: lv, cp, product: statProduct(base, ivs, lv) };
  }
  return best;
}

const cache = new Map();
/** All 4096 spreads ranked for a species under a cap. Cached per species+cap. */
export function rankTable(speciesId, base, league, maxLevel = 51) {
  const key = `${speciesId}|${league}|${maxLevel}`;
  if (cache.has(key)) return cache.get(key);
  const cap = CAPS[league];
  const rows = [];
  for (let a = 0; a <= 15; a++) for (let d = 0; d <= 15; d++) for (let h = 0; h <= 15; h++) {
    const b = bestUnderCap(base, { atk: a, def: d, hp: h }, cap, maxLevel);
    if (b) rows.push({ ivs: { atk: a, def: d, hp: h }, ...b });
  }
  rows.sort((x, y) => y.product - x.product || x.level - y.level);
  const top = rows[0]?.product ?? 1;
  rows.forEach((r, i) => { r.rank = i + 1; r.pct = Math.round((r.product / top) * 10000) / 100; });
  cache.set(key, rows);
  return rows;
}

/** Rank of one spread: { rank, pct, level, cp } or null if it cannot fit under the cap. */
export function ivRank(speciesId, base, ivs, league, maxLevel = 51) {
  return rankTable(speciesId, base, league, maxLevel).find((r) => r.ivs.atk === ivs.atk && r.ivs.def === ivs.def && r.ivs.hp === ivs.hp) ?? null;
}
