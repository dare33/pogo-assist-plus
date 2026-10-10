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
 * Returns { gl, ul, ml }, each { pick, strength, moves, needs, iv, overCap, cost } (see README).
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
  const ivs = validIvs(entry.ivs) ? entry.ivs : null;
  const have = entry.moves ?? [];
  const level = typeof entry.level === 'number' && Number.isInteger(entry.level * 2) && entry.level >= 1 && entry.level <= 51 ? entry.level : null; // a half-level the game has
  const out = {};
  for (const league of LEAGUES) {
    const map = rankings.byLeague[league];
    // A Shadow is ranked as the Shadow where PvPoke ranks it; its IV rank is the same either way (identical base stats).
    const rankedId = (base) => (entry.shadow && map.has(`${base}_shadow`) ? `${base}_shadow` : base);
    const ivOf = (base) => (ivs ? ivRank(base, gm.byId.get(base).baseStats, ivs, league) : null);

    let pickBase = null, row = null;
    for (const base of family) {
      const r = map.get(rankedId(base));
      if (!r) continue;
      let better = !row || r.score > row.score;
      if (row && r.score === row.score) {
        // Tie on score: the better spread for this copy's IVs, then the later evolution.
        const a = ivOf(base)?.pct ?? 0, b = ivOf(pickBase)?.pct ?? 0;
        better = a >= b;
      }
      if (better) { pickBase = base; row = r; }
    }
    let rankId;
    if (row) rankId = rankedId(pickBase);
    else {
      // Nothing in the family is ranked here: build the final evolution (the strongest one if the family branches).
      // Unreleased members are skipped (nobody can build Farigiraf yet); a family with none released keeps them all.
      const released = family.filter((id) => gm.byId.get(id).released !== false);
      const pool = released.length ? released : family;
      const finals = pool.filter((id) => !evolutionLinks(gm, id).some((e) => pool.includes(baseSpeciesId(gm, e))));
      const top = (id) => cpAt(gm.byId.get(id).baseStats, MAX_IV, 50);
      pickBase = finals.length ? finals.reduce((a, b) => (top(b) > top(a) ? b : a)) : start;
      rankId = pickBase;
    }

    // PvPoke pads short movesets with a "none" placeholder (Unown), and a move the game master lacks has no name to show: drop both.
    const moveName = (id) => gm.moves.get(id)?.name;
    // Slots are kept: the fast move is slot 0 only, so an unknown fast id never promotes a charged move.
    const known = (n) => n && n.toLowerCase() !== 'none';
    const fast = row ? moveName(row.moveset[0]) : null;
    const moves = row && known(fast) ? { fast, charged: row.moveset.slice(1).map(moveName).filter(known) } : null;
    let needs = null;
    // Evolving re-rolls a Pokémon's moves, so what a copy lacks only matters when the copy is itself the pick.
    if (moves && have.length && pickBase === start) {
      const known = new Set(have.map(norm));
      needs = [moves.fast, ...moves.charged].filter((m) => !known.has(norm(m)));
    }

    const iv = ivOf(pickBase);
    const ivOut = iv && { rank: iv.rank, pct: iv.pct, rankPct: iv.rankPct, level: iv.level, cp: iv.cp };
    // Master League has no cap: a Best Buddy copy at 51 is simply past the last power-up, with nothing left to pay.
    const overCap = league !== 'ml' && !!(iv && level != null && level > iv.level);
    let cost = null;
    if (iv && level != null && !overCap) {
      const flags = { shadow: entry.shadow, purified: entry.purified, lucky: entry.lucky };
      const up = powerUpCost(level, iv.level, flags);
      const path = evolutionPath(gm, start, pickBase) ?? [];
      const evo = path.reduce((s, [from, to]) => s + (FORM_CHANGES[from]?.includes(to) ? 0 : evolveCandy(gm, from, to)), 0);
      cost = { dust: up.dust, candy: up.candy, xl: up.xl, evolveCandy: evo, toLevel: iv.level };
    }

    out[league] = {
      pick: {
        speciesId: rankId, name: gm.byId.get(rankId)?.speciesName ?? gm.byId.get(pickBase).speciesName, self: pickBase === start,
        // Only worth saying when the sex is unknown and the pick is an evolution that one sex cannot become.
        ...(!sex && pickBase !== start && GENDER_LOCKED[pickBase] ? { genderLocked: GENDER_LOCKED[pickBase] } : {}),
      },
      strength: row ? { score: row.score, rank: row.rank, of: map.size } : null,
      moves, needs, iv: ivOut, overCap, cost,
    };
  }
  return out;
}
