// PvP leagues for one Pokémon: which family member to build for Great, Ultra and Master League, how strong that is,
// what this exact copy's IVs rank at, and what it costs to get there.
import { evolutionLinks, baseSpeciesId, FORM_CHANGES } from './gamemaster.js';
import { powerUpCost } from './cost.js';
import { cpAt } from './cpm.js';
import { ivRank } from './pvp-rank.js';
import { evolveCandy, evolutionPath } from './evolve.js';

const LEAGUES = ['gl', 'ul', 'ml'];
// Megas and Primals are not allowed in Battle League, so they are never a pick.
const NOT_ALLOWED = /_(mega(_[xy])?|primal)$/;
// ---- Our pick: the rule, in one place (Greg tunes this over time) ----
// PROVISIONAL default, decided 20 Oct 2026 and expected to change as Greg tunes the algorithm: the same for every league.
// Species strength comes first. Every ranked family member whose PvPoke score is within CLOSE_SCORE points of the best-scoring
// member's counts as "close"; among those, the one whose IV Rank % for this exact copy is best wins (Magnemite Great League:
// Magnezone 78.4 against Magneton 76.4 is close, so the better spread decides; Eevee Ultra League: Sylveon 85.9 against Flareon 66.8
// is not, so Sylveon stays). Poke Genie, by comparison, picks mostly on the IVs alone.
export const CLOSE_SCORE = 3.0;

/**
 * The rule. `candidates` are the RANKED family members for one league, each { id, score, rankPct, depth }:
 * score = PvPoke overall score, rankPct = this copy's IV Rank % as that member (null when the IVs are unknown or the member cannot
 * fit under the cap), depth = evolution steps from the Pokémon itself (later evolution = larger). Returns the winner, or null for no
 * candidates. Unranked members are never candidates, so they cannot win over a ranked one.
 *   1. Keep the members within `closeScore` of the best score (a tiny epsilon stops float error flipping an exact boundary).
 *   2. If this copy's IVs are unknown, the highest score wins (as before the rule existed); a tie goes to the later evolution.
 *   3. Otherwise the best IV Rank % wins; a tie goes to the higher score, then the later evolution.
 */
export function chooseMember(candidates, closeScore = CLOSE_SCORE) {
  if (!candidates.length) return null;
  const best = Math.max(...candidates.map((c) => c.score));
  const close = candidates.filter((c) => c.score >= best - closeScore - 1e-9);
  const known = close.some((c) => c.rankPct != null);
  const key = (c) => (known ? [c.rankPct ?? -1, c.score, c.depth] : [c.score, c.depth]);
  return close.reduce((a, b) => {
    const ka = key(a), kb = key(b);
    for (let i = 0; i < ka.length; i++) if (ka[i] !== kb[i]) return kb[i] > ka[i] ? b : a;
    return b; // fully tied: the later one in family order
  });
}

const MAX_IV = { atk: 15, def: 15, hp: 15 };
// Family members only one sex can become in Pokémon GO. Poke Genie's export carries the sex; a scan does not, so an unknown
// sex keeps every member and the pick says which sex it needs.
const GENDER_LOCKED = {
  gallade: 'male', froslass: 'female', vespiquen: 'female', salazzle: 'female', mothim: 'male',
  wormadam_plant: 'female', wormadam_sandy: 'female', wormadam_trash: 'female', oinkologne: 'male', oinkologne_female: 'female',
  meowstic: 'male', meowstic_female: 'female',
};
// IVs outside 0-15 or not whole numbers (a misread scan) are treated as unknown; a throw here would fail the whole box's advice.
const validIvs = (ivs) => !!ivs && ['atk', 'def', 'hp'].every((k) => Number.isInteger(ivs[k]) && ivs[k] >= 0 && ivs[k] <= 15);
const sexOf = (gender) => (gender === '♀' ? 'female' : gender === '♂' ? 'male' : null);

const regionOf = (id) => id.match(/_(alolan|galarian|hisuian|paldean)(?:_|$)/)?.[1] ?? null;

// Everything the Pokémon can evolve into by the game master's links, minus the cross-regional links: a Cubone becomes Marowak, not
// Alolan Marowak (that happens only in special events), while Galarian Meowth still reaches Perrserker, whose id carries no region.
function descendants(gm, start) {
  const out = [];
  const seen = new Set([start]);
  const stack = [start];
  while (stack.length) {
    const parent = stack.pop();
    for (const next of evolutionLinks(gm, parent)) {
      const region = regionOf(next);
      if (seen.has(next) || (region && region !== regionOf(parent))) continue;
      seen.add(next); out.push(next); stack.push(next);
    }
  }
  return out;
}

const norm = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');

/**
 * Leagues for one imported entry. `resolved` is resolveSpecies' result for it; ctx = { gm, tiers, rankings }.
 * Returns { gl, ul, ml }. Each league is the rating of Our pick, { pick, strength, moves, needs, iv, overCap, cost }, plus
 * `options`: every ranked family member rated the same way, Our pick among them marked `ours: true` (see README, "League options").
 */
export function leaguesFor(entry, resolved, ctx) {
  const { gm, rankings } = ctx;
  const start = baseSpeciesId(gm, resolved.speciesId);
  const sex = sexOf(entry.gender);
  const family = [];
  for (const id of [start, ...descendants(gm, start)]) {
    const base = baseSpeciesId(gm, id);
    // The Pokémon itself always stays (a misread sex must not hide it); evolutions the other sex cannot become go.
    if (sex && base !== start && GENDER_LOCKED[base] && GENDER_LOCKED[base] !== sex) continue;
    if (gm.byId.has(base) && !NOT_ALLOWED.test(id) && !NOT_ALLOWED.test(base) && !family.includes(base)) family.push(base);
  }
  const depthOf = (base) => (base === start ? 0 : evolutionPath(gm, start, base)?.length ?? family.indexOf(base));
  const ivs = validIvs(entry.ivs) ? entry.ivs : null;
  const have = entry.moves ?? [];
  const level = typeof entry.level === 'number' && Number.isInteger(entry.level * 2) && entry.level >= 1 && entry.level <= 51 ? entry.level : null; // a half-level the game has
  const out = {};
  for (const league of LEAGUES) {
    const map = rankings.byLeague[league];
    // A Shadow is ranked as the Shadow where PvPoke ranks it; its IV rank is the same either way (identical base stats).
    const rankedId = (base) => (entry.shadow && map.has(`${base}_shadow`) ? `${base}_shadow` : base);
    const ivMemo = new Map();
    const ivOf = (base) => {
      if (!ivs) return null;
      if (!ivMemo.has(base)) ivMemo.set(base, ivRank(base, gm.byId.get(base).baseStats, ivs, league));
      return ivMemo.get(base);
    };

    // One family member rated for this league: everything the Pokémon screen shows for a pick.
    const rate = (base, row) => {
      const rankId = rankedId(base);
      // PvPoke pads short movesets with a "none" placeholder (Unown), and a move the game master lacks has no name to show: drop both.
      const moveName = (id) => gm.moves.get(id)?.name;
      // Slots are kept: the fast move is slot 0 only, so an unknown fast id never promotes a charged move.
      const known = (n) => n && n.toLowerCase() !== 'none';
      const fast = row ? moveName(row.moveset[0]) : null;
      const moves = row && known(fast) ? { fast, charged: row.moveset.slice(1).map(moveName).filter(known) } : null;
      let needs = null;
      // Evolving re-rolls a Pokémon's moves, so what a copy lacks only matters when the copy is itself the option.
      if (moves && have.length && base === start) {
        const haveSet = new Set(have.map(norm));
        needs = [moves.fast, ...moves.charged].filter((m) => !haveSet.has(norm(m)));
      }

      const iv = ivOf(base);
      const ivOut = iv && { rank: iv.rank, pct: iv.pct, rankPct: iv.rankPct, level: iv.level, cp: iv.cp };
      // Master League has no cap: a Best Buddy copy at 51 is simply past the last power-up, with nothing left to pay.
      const overCap = league !== 'ml' && !!(iv && level != null && level > iv.level);
      let cost = null;
      if (iv && level != null && !overCap) {
        const flags = { shadow: entry.shadow, purified: entry.purified, lucky: entry.lucky };
        const up = powerUpCost(level, iv.level, flags);
        const path = evolutionPath(gm, start, base) ?? [];
        const evo = path.reduce((s, [from, to]) => s + (FORM_CHANGES[from]?.includes(to) ? 0 : evolveCandy(gm, from, to)), 0);
        cost = { dust: up.dust, candy: up.candy, xl: up.xl, evolveCandy: evo, toLevel: iv.level };
      }
      return {
        pick: {
          speciesId: rankId, name: gm.byId.get(rankId)?.speciesName ?? gm.byId.get(base).speciesName, self: base === start,
          // Only worth saying when the sex is unknown and the option is an evolution that one sex cannot become.
          ...(!sex && base !== start && GENDER_LOCKED[base] ? { genderLocked: GENDER_LOCKED[base] } : {}),
        },
        strength: row ? { score: row.score, rank: row.rank, of: map.size } : null,
        moves, needs, iv: ivOut, overCap, cost,
      };
    };

    const ranked = [];
    for (const base of family) {
      const row = map.get(rankedId(base));
      if (row) ranked.push({ base, row });
    }
    const win = chooseMember(ranked.map(({ base, row }) => ({ id: base, score: row.score, rankPct: ivOf(base)?.rankPct ?? null, depth: depthOf(base) })));
    let pickBase, options;
    if (win) {
      pickBase = win.id;
      // Strongest species first; among equal scores the better spread, then the later evolution.
      const order = ranked.map(({ base, row }) => ({ base, row, pct: ivOf(base)?.rankPct ?? -1, depth: depthOf(base) }))
        .sort((a, b) => b.row.score - a.row.score || b.pct - a.pct || b.depth - a.depth);
      options = order.map(({ base, row }) => ({ ...rate(base, row), ours: base === pickBase }));
    } else {
      // Nothing in the family is ranked here: build the final evolution (the strongest one if the family branches).
      // Unreleased members are skipped (nobody can build Farigiraf yet); a family with none released keeps them all.
      const released = family.filter((id) => gm.byId.get(id).released !== false);
      const pool = released.length ? released : family;
      const finals = pool.filter((id) => !evolutionLinks(gm, id).some((e) => pool.includes(baseSpeciesId(gm, e))));
      const top = (id) => cpAt(gm.byId.get(id).baseStats, MAX_IV, 50);
      pickBase = finals.length ? finals.reduce((a, b) => (top(b) > top(a) ? b : a)) : start;
      options = [{ ...rate(pickBase, null), ours: true }];
    }
    const { ours, ...mine } = options.find((o) => o.ours);
    out[league] = { ...mine, options };
  }
  return out;
}
