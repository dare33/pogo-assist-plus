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

import { cpAt, hpAt, LEVELS } from '../cpm.js';

/**
 * @param species  [{ speciesId, baseStats }] candidates the name could be
 * @param cp       read CP (required)
 * @param hp       read HP or null
 * @param ivs      { atk, def, hp } from the bars, or null when the panel was not read
 * @returns { status, solutions: [{ speciesId, ivs, level, hp, tier }] } sorted best first.
 *   status: 'exact' | 'corrected' (one tier-1 set) | 'ambiguous' (several sets in the best
 *           tier, or nothing near the read) | 'unknown-ivs' (no bars) | 'none'
 */
export function solve({ species, cp, hp = null, ivs = null }) {
  if (!cp || !species?.length) return { status: 'none', solutions: [] };
  const fits = [];
  for (const sp of species) {
    for (const c of allCombos()) {
      for (const level of LEVELS) {
        const v = cpAt(sp.baseStats, c, level);
        if (v > cp) break;
        if (v !== cp) continue;
        const h = hpAt(sp.baseStats, c, level);
        if (hp !== null && h !== hp) continue;
        fits.push({ speciesId: sp.speciesId, ivs: c, level, hp: h, tier: ivs ? tierOf(ivs, c) : 3 });
      }
    }
  }
  if (!fits.length) return { status: ivs ? 'none' : 'unknown-ivs', solutions: [] };
  fits.sort((a, b) => a.tier - b.tier || dist(ivs, a.ivs) - dist(ivs, b.ivs) || a.level - b.level);
  if (!ivs) return { status: 'unknown-ivs', solutions: fits };
  const bestTier = fits[0].tier;
  const top = fits.filter((f) => f.tier === bestTier);
  const distinct = new Set(top.map((s) => `${s.speciesId}:${s.ivs.atk}/${s.ivs.def}/${s.ivs.hp}`));
  if (distinct.size > 1 && bestTier > 0) return { status: 'ambiguous', solutions: fits };
  return { status: ['exact', 'corrected', 'ambiguous'][bestTier], solutions: fits };
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
