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

// One sorted list of the products of every spread that fits, per species+cap: a large box touches hundreds of these tables, and a
// table that also kept every spread's product and level was 80 KB (169 MB for a diverse 2,000-entry box). A spread's own product and
// level are recomputed on demand with bestUnderCap, which is one bisection. The cache is bounded (analyseBox asks for one species
// at a time, so a small one is enough) and analyseBox empties it when done.
const CACHE_LIMIT = 512;
const cache = new Map();
export function clearRankCache() { cache.clear(); }
export const rankCacheSize = () => cache.size;

function tableFor(speciesId, base, league, maxLevel) {
  // The base stats are part of the key: a reloaded game master can change them under the same id.
  const key = `${speciesId}|${base.atk}/${base.def}/${base.hp}|${league}|${maxLevel}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const sorted = sortedProducts(base, CAPS[league], maxLevel);
  const t = { sorted, n: sorted.length, top: sorted[0] ?? 1 };
  if (cache.size >= CACHE_LIMIT) cache.delete(cache.keys().next().value); // the oldest; Map keeps insertion order
  cache.set(key, t);
  return t;
}

// The products of all 4,096 spreads that fit under the cap, best first. Same arithmetic as bestUnderCap and cpAt (the operations are
// in the same order, so the floats are identical), but the best level of each spread starts from its neighbour's: CP rises with
// every IV, so it moves by a step or two instead of a fresh bisection (about 12 CP evaluations) per spread. That matters on a phone
// whose JavaScript engine runs without a JIT.
function sortedProducts(base, cap, maxLevel) {
  let top = LEVELS.length - 1;
  while (top > 0 && LEVELS[top] > maxLevel) top--;
  const mult = new Float64Array(top + 1);
  for (let i = 0; i <= top; i++) mult[i] = cpm(LEVELS[i]);
  const sqrtDef = [], sqrtHp = [];
  for (let i = 0; i <= 15; i++) { sqrtDef.push(Math.sqrt(base.def + i)); sqrtHp.push(Math.sqrt(base.hp + i)); }
  const cpAtIndex = (atk, sd, sh, i) => Math.max(10, Math.floor((atk * sd * sh * mult[i] * mult[i]) / 10));
  const out = new Float64Array(4096);
  let n = 0, rowStart = 0;
  for (let a = 0; a <= 15; a++) {
    const atk = base.atk + a;
    for (let d = 0; d <= 15; d++) {
      const sd = sqrtDef[d];
      let i = rowStart;
      for (let h = 0; h <= 15; h++) {
        const sh = sqrtHp[h];
        while (i < top && cpAtIndex(atk, sd, sh, i + 1) <= cap) i++;
        while (i > 0 && cpAtIndex(atk, sd, sh, i) > cap) i--;
        if (h === 0) rowStart = i;
        if (i === 0 && cpAtIndex(atk, sd, sh, 0) > cap) continue; // not even level 1 fits
        const m = mult[i];
        out[n++] = atk * m * (base.def + d) * m * Math.floor((base.hp + h) * m);
      }
    }
  }
  const sorted = out.slice(0, n).sort();
  return sorted.reverse();
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
  const b = bestUnderCap(base, ivs, CAPS[league], maxLevel);
  if (!b) return null;
  const t = tableFor(speciesId, base, league, maxLevel);
  const rank = rankOf(t, b.product);
  return {
    rank, of: t.n, level: b.level, cp: b.cp, product: b.product,
    pct: Math.round((b.product / t.top) * 10000) / 100,
    rankPct: t.n > 1 ? Math.round(((t.n - rank) / (t.n - 1)) * 10000) / 100 : 100,
  };
}

/** All spreads that fit under a cap, best first: [{ ivs, level, cp, product, rank, pct }]. Not cached (the ranking itself is). */
export function rankTable(speciesId, base, league, maxLevel = MAX_LEVEL) {
  const t = tableFor(speciesId, base, league, maxLevel);
  const rows = [];
  for (let i = 0; i < 4096; i++) {
    const ivs = { atk: i >> 8, def: (i >> 4) & 15, hp: i & 15 };
    const b = bestUnderCap(base, ivs, CAPS[league], maxLevel);
    if (!b) continue;
    rows.push({ ivs, level: b.level, cp: b.cp, product: b.product, rank: rankOf(t, b.product), pct: Math.round((b.product / t.top) * 10000) / 100 });
  }
  rows.sort((x, y) => y.product - x.product || x.level - y.level);
  return rows;
}
