// IV rank under a CP cap: the stat-product ranking used by PvPoke and Poke Genie, matched to Poke Genie's export
// (fixtures/greg-2026-09-25.pokegenie.csv, test/leagues.test.js): best level at or under the cap with a level cap of 50,
// stat product atk * def * floor(hp) at that level, ties share the best rank (rank = 1 + spreads strictly better),
// and Poke Genie's Rank % is (N - rank) / (N - 1) over the N = 4096 spreads.
import { LEVELS, cpAt, cpm } from './cpm.js';

// ml has no cap (everything goes to level 50); lc is Little Cup, which Poke Genie exports as its third league and the app never shows.
export const CAPS = { gl: 1500, ul: 2500, ml: Infinity, lc: 500 };
export const MAX_LEVEL = 50;
// Two products closer than this (relative) are the same product: the same arithmetic done in a different order differs by ~1e-16.
// 1e-9 was too loose: it merged 129 genuinely different adjacent products across the 3,804 tables (Ivysaur GL 11/7/14 at 35 against
// 5/5/6 at 39.5), while 1e-12 still reproduces every Poke Genie rank in the fixture.
const TIE = 1e-12;

/** Best level under the cap for a spread, and its CP and stat product. CP only rises with level, so this bisects. */
export function bestUnderCap(base, ivs, cap, maxLevel = MAX_LEVEL) {
  let lo = 0, hi = LEVELS.length - 1;
  while (hi > 0 && LEVELS[hi] > maxLevel) hi--;
  if (cpAt(base, ivs, LEVELS[lo]) > cap) return null;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (cpAt(base, ivs, LEVELS[mid]) <= cap) lo = mid; else hi = mid - 1;
  }
  const level = LEVELS[lo];
  const m = cpm(level);
  return { level, cp: cpAt(base, ivs, level), product: (base.atk + ivs.atk) * m * (base.def + ivs.def) * m * Math.floor((base.hp + ivs.hp) * m) };
}

// Per species+cap, kept compact (typed arrays): a large box touches hundreds of these tables. Spread index = atk * 256 + def * 16 + hp.
const cache = new Map();
function tableFor(speciesId, base, league, maxLevel) {
  // The base stats are part of the key: a reloaded game master can change them under the same id.
  const key = `${speciesId}|${base.atk}/${base.def}/${base.hp}|${league}|${maxLevel}`;
  if (cache.has(key)) return cache.get(key);
  const cap = CAPS[league];
  const product = new Float64Array(4096).fill(NaN);
  const level = new Float32Array(4096);
  const fitting = [];
  for (let a = 0; a <= 15; a++) for (let d = 0; d <= 15; d++) for (let h = 0; h <= 15; h++) {
    const b = bestUnderCap(base, { atk: a, def: d, hp: h }, cap, maxLevel);
    if (!b) continue;
    const i = a * 256 + d * 16 + h;
    product[i] = b.product; level[i] = b.level; fitting.push(b.product);
  }
  const sorted = Float64Array.from(fitting).sort().reverse();
  const t = { product, level, sorted, n: sorted.length, top: sorted[0] ?? 1 };
  cache.set(key, t);
  return t;
}

// 1 + the number of spreads whose product is strictly better, by bisection on the descending sorted products.
function rankOf(t, p) {
  const limit = p * (1 + TIE);
  let lo = 0, hi = t.n;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (t.sorted[mid] > limit) lo = mid + 1; else hi = mid; }
  return lo + 1;
}

/** Rank of one spread: { rank, pct, rankPct, level, cp, product, of } or null if it cannot fit under the cap.
 *  pct = stat product as a % of the best spread; rankPct = Poke Genie's Rank %. Both to 2 dp. */
export function ivRank(speciesId, base, ivs, league, maxLevel = MAX_LEVEL) {
  const t = tableFor(speciesId, base, league, maxLevel);
  const i = ivs.atk * 256 + ivs.def * 16 + ivs.hp;
  const product = t.product[i];
  if (Number.isNaN(product)) return null;
  const rank = rankOf(t, product);
  const lv = t.level[i];
  return {
    rank, of: t.n, level: lv, cp: cpAt(base, ivs, lv), product,
    pct: Math.round((product / t.top) * 10000) / 100,
    rankPct: t.n > 1 ? Math.round(((t.n - rank) / (t.n - 1)) * 10000) / 100 : 100,
  };
}

/** All spreads that fit under a cap, best first: [{ ivs, level, cp, product, rank, pct }]. Not cached (the ranking itself is). */
export function rankTable(speciesId, base, league, maxLevel = MAX_LEVEL) {
  const t = tableFor(speciesId, base, league, maxLevel);
  const rows = [];
  for (let i = 0; i < 4096; i++) {
    if (Number.isNaN(t.product[i])) continue;
    const ivs = { atk: i >> 8, def: (i >> 4) & 15, hp: i & 15 };
    rows.push({ ivs, level: t.level[i], cp: cpAt(base, ivs, t.level[i]), product: t.product[i], rank: rankOf(t, t.product[i]), pct: Math.round((t.product[i] / t.top) * 10000) / 100 });
  }
  rows.sort((x, y) => y.product - x.product || x.level - y.level);
  return rows;
}
