// Given what was read off the screen (species candidates, CP, HP, bar IVs), find the IVs and
// level that reproduce CP and HP. Megas use the Mega form's stats (the fixture confirms Poke
// Genie records the Mega's CP and HP).
//
// The appraisal bars animate from the previous Pokémon's values to this one's when the panel
// changes, so a frame taken mid-animation reads anything between the two. The solver ranks
// candidate IV sets against the read:
//   tier 0  exactly the bars read
//   tier 1  every bar within one unit (a rounding miss on a small frame)
//   tier 2  anything else that fits CP and HP (the read was mid-animation or another panel)

import { cpm, hpAt, LEVELS } from '../cpm.js';

const LEVEL_CPM = LEVELS.map(cpm);
const cpFast = (y, i) => Math.max(10, Math.floor((y * LEVEL_CPM[i] * LEVEL_CPM[i]) / 10));

/**
 * @param species  [{ speciesId, baseStats }] candidates the name could be
 * @param cp       read CP (required)
 * @param hp       read HP or null
 * @param ivs      { atk, def, hp } from the bars, or null when the panel was not read
 * @returns { status, solutions: [{ speciesId, ivs, level, hp, tier }], forms } sorted best first;
 *   `forms` lists the species ids that fit equally well (same stats), first one used.
 *   status: 'exact' | 'corrected' (one tier-1 set) | 'ambiguous' (several sets in the best
 *           tier, or nothing near the read) | 'unknown-ivs' (no bars) | 'none'
 */
export function solve({ species, cp, hp = null, ivs = null }) {
  if (!cp || !species?.length) return { status: 'none', solutions: [] };
  const fits = [];
  const combos = allCombos();
  for (const sp of species) {
    // The CP formula of cpm.js `cpAt`, with the parts that do not depend on the level hoisted out of the loop
    // (same operations in the same order, so the same floating-point results). CP never falls as the level
    // rises, so the first level that can give `cp` is found by bisection and the scan starts there (the levels
    // below it are all under `cp`).
    const { atk: A, def: D, hp: S } = sp.baseStats;
    for (let a = 0, k = 0; a <= 15; a++) {
      for (let d = 0; d <= 15; d++) {
        const x = (A + a) * Math.sqrt(D + d);
        // CP also never falls as the hp IV rises, so the first level for h is at or below the one for h - 1.
        let bound = LEVELS.length;
        for (let h = 0; h <= 15; h++, k++) {
          const y = x * Math.sqrt(S + h);
          let lo = 0, hi = bound;
          while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (cpFast(y, mid) < cp) lo = mid + 1; else hi = mid;
          }
          bound = lo;
          const c = combos[k];
          for (let i = lo; i < LEVELS.length; i++) {
            const v = cpFast(y, i);
            if (v > cp) break;
            if (v !== cp) continue;
            const level = LEVELS[i];
            const hpv = hpAt(sp.baseStats, c, level);
            if (hp !== null && hpv !== hp) continue;
            fits.push({ speciesId: sp.speciesId, ivs: c, level, hp: hpv, tier: ivs ? tierOf(ivs, c) : 3 });
          }
        }
      }
    }
  }
  if (!fits.length) return { status: ivs ? 'none' : 'unknown-ivs', solutions: [] };
  // Ties between forms with the same stats (costume Pikachu, say) go to the plainest id, and are
  // reported so the row can be flagged: the screen name does not say which form it is.
  fits.sort((a, b) => a.tier - b.tier || dist(ivs, a.ivs) - dist(ivs, b.ivs) || a.level - b.level || a.speciesId.length - b.speciesId.length || (a.speciesId < b.speciesId ? -1 : 1));
  const bestTier = fits[0].tier;
  const top = fits.filter((f) => f.tier === bestTier);
  const forms = new Set(top.map((s) => s.speciesId));
  const out = (status) => ({ status, solutions: fits, forms: [...forms] });
  if (!ivs) return out('unknown-ivs');
  const distinct = new Set(top.map((s) => `${s.ivs.atk}/${s.ivs.def}/${s.ivs.hp}`));
  if (distinct.size > 1 && bestTier > 0) return out('ambiguous');
  return out(['exact', 'corrected', 'ambiguous'][bestTier]);
}

function tierOf(read, c) {
  const r = [read.atk, read.def, read.hp], t = [c.atk, c.def, c.hp];
  if (r.every((v, i) => v === t[i])) return 0;
  if (r.every((v, i) => Math.abs(v - t[i]) <= 1)) return 1;
  return 2;
}

function dist(a, b) { return a ? Math.abs(a.atk - b.atk) + Math.abs(a.def - b.def) + Math.abs(a.hp - b.hp) : 0; }

let ALL = null;
function allCombos() {
  if (!ALL) { ALL = []; for (let a = 0; a <= 15; a++) for (let d = 0; d <= 15; d++) for (let h = 0; h <= 15; h++) ALL.push({ atk: a, def: d, hp: h }); }
  return ALL;
}

/** Species candidates for a matched display name: the base stats each id would be checked with. */
export function speciesFor(gm, speciesIds) {
  return speciesIds.map((id) => gm.byId.get(id)).filter(Boolean).map((p) => ({ speciesId: p.speciesId, baseStats: p.baseStats, speciesName: p.speciesName }));
}
