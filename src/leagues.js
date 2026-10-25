// PvP leagues for one Pokémon: which family member to build for Great, Ultra and Master League, how strong each member is,
// what this exact copy's IVs rank at as each member, and what it costs to get there.
import { evolutionLinks, baseSpeciesId, resolveSpecies, FORM_CHANGES } from './gamemaster.js';
import { powerUpCost } from './cost.js';
import { cpAt } from './cpm.js';
import { ivRank, CAPS } from './pvp-rank.js';
import { evolveCandy, evolutionPath } from './evolve.js';

const LEAGUES = ['gl', 'ul', 'ml'];
// Poke Genie's export columns for the leagues it has; it has none for Master League.
const EXPORT_COLUMN = { gl: 'great', ul: 'ultra' };
// Megas and Primals are not allowed in Battle League, so they are never an option.
const NOT_ALLOWED = /_(mega(_[xy])?|primal)$/;
const MAX_IV = { atk: 15, def: 15, hp: 15 };
// Family members only one sex can become in Pokémon GO. Poke Genie's export carries the sex; a scan does not, so an unknown
// sex keeps every member and the option says which sex it needs.
const GENDER_LOCKED = {
  gallade: 'male', froslass: 'female', vespiquen: 'female', salazzle: 'female', mothim: 'male',
  wormadam_plant: 'female', wormadam_sandy: 'female', wormadam_trash: 'female', oinkologne: 'male', oinkologne_female: 'female',
  meowstic: 'male', meowstic_female: 'female',
};
// IVs outside 0-15 or not whole numbers (a misread scan) are treated as unknown; a throw here would fail the whole box's advice.
const validIvs = (ivs) => !!ivs && ['atk', 'def', 'hp'].every((k) => Number.isInteger(ivs[k]) && ivs[k] >= 0 && ivs[k] <= 15);
const sexOf = (gender) => (gender === '♀' ? 'female' : gender === '♂' ? 'male' : null);

// ============================================================================================================================
// WHICH MEMBER TO SHOW, AND THE EXPERIMENT. Both rules live here, side by side; Greg tunes them over time.
//
// SHOWN pick (`pokeGeniePick`): copies Poke Genie, which is what Greg's family and friends use and trust. PROVISIONAL: fitted
// against fixtures/greg-2026-09-25.pokegenie.csv and checked only on it, so the agreement figures are IN-SAMPLE (test/leagues.test.js
// prints them: currently 272/280 Great and 300/306 Ultra rows where the export names a pick; the cost checks count the 278 and 304
// rows with an exact level, a different subset). The test floors are regression pins, not evidence it generalises; do not overfit.
// The misses are not only near-ties where Poke Genie prefers the later evolution (Fidough -> Dachsbun, Gossifleur -> Eldegoss):
// Crocalor stays Crocalor where Poke Genie picks Skeledirge, and Magmar becomes Magmortar where Poke Genie keeps Magmar. Fitting the
// pools took it from 262/278 and 290/304 (best stat product among the fitting members, ranked or not) to this. Exact ties go to
// the later evolution (the fixture is indifferent). Stat products are compared at ivRank()'s 2-decimal percentage, so two members
// that differ by less than 0.005% count as an exact tie and the later evolution wins.
//   1. If the entry carries Poke Genie's own pick for the league (a Poke Genie CSV), and it is a member of this family, use it.
//   2. Great and Ultra League only: otherwise emulate it, taking the member with the best stat product % (ivRank().pct; on an exact
//      tie the later evolution) from the first of these pools that is not empty: the members this copy is not already too strong
//      for (CP at its current level over the cap: a Pokémon cannot be powered down) that PvPoke ranks in this league; the same
//      without the ranked requirement (Poke Genie does pick unranked stages); the ranked members; all members. Unknown level:
//      nothing is "too strong".
//   3. Master League, and unknown IVs in any league: the highest PvPoke score among the members the copy is not past the cap for (all of them if none fits), then the later evolution; a family with nothing
//      ranked takes its final evolution (or the first member that fits, if the copy is past the cap for that one). Master League is not emulated because Poke Genie exports no Master League pick, so there is
//      nothing to copy and the stat-product rule there only follows ~0.07% noise (Eevee showed Glaceon/Umbreon, Scyther showed
//      Kleavor over Scizor, Shaymin Land over Sky); the species' PvPoke score is the better guide (Greg, 20 Oct 2026).
//
// EXPERIMENTAL pick (`chooseMember`, threshold CLOSE_SCORE): carried in the data (`experimental`) and shown when the app's ranking switch is on Pogo Assist; Greg will switch
// the shown pick to it once it is provably better. Species strength first, but among ranked members within CLOSE_SCORE points of
// the best score the best IV Rank % for this copy wins.
// ============================================================================================================================

// PROVISIONAL default (Greg, 20 Oct 2026): the same for every league, in PvPoke score points.
export const CLOSE_SCORE = 3.0;

/**
 * The shown pick's emulation of Poke Genie (steps 2 and 3 above). `members` = [{ id, depth, score, iv, overCap }] for every allowed
 * member: score = PvPoke score or null when unranked; iv = ivRank() result or null (unknown IVs, or the member cannot fit under
 * the cap); overCap = this copy's CP at its current level (0/0/0 when its IVs are unknown) already exceeds the league's cap as that member.
 * Returns the member, or null when the score rule has no ranked member to choose among the ones that fit (nothing ranked, or every ranked
 * member is over the cap): the caller then takes the final evolution if it fits, else the first member that fits (source 'fallback').
 */
export function pokeGeniePick(members) {
  const rated = members.filter((m) => m.iv);
  if (rated.length) {
    // On an exact tie the later evolution (a 15/15/15 is 100% as every member, so this decides Master League for one).
    const best = (pool) => (pool.length ? pool.reduce((a, b) => (b.iv.pct > a.iv.pct || (b.iv.pct === a.iv.pct && b.depth > a.depth) ? b : a)) : null);
    const fitting = rated.filter((m) => !m.overCap), ranked = rated.filter((m) => m.score != null);
    return best(fitting.filter((m) => m.score != null)) ?? best(fitting) ?? best(ranked) ?? best(rated);
  }
  // The score rule never shows a member the copy is already too strong for while another fits (the cap only ever excludes in Great and
  // Ultra: Master League members are never over it).
  const fitting = members.filter((m) => !m.overCap);
  const ranked = (fitting.length ? fitting : members).filter((m) => m.score != null);
  if (!ranked.length) return null;
  return ranked.reduce((a, b) => (b.score > a.score || (b.score === a.score && b.depth >= a.depth) ? b : a));
}

/**
 * The experimental rule. `candidates` are the RANKED members for one league, each { id, score, rankPct, depth, overCap }:
 * rankPct = this copy's IV Rank % as that member (null when the IVs are unknown or it cannot fit under the cap), depth = evolution
 * steps from the Pokémon itself, overCap as in pokeGeniePick. Returns the winner, or null for no candidates. Unranked members are
 * never candidates, so they cannot win over a ranked one.
 *   0. Members this copy is already too strong for (overCap) are left out entirely, best score included, unless every one is.
 *   1. Keep the members within `closeScore` of the best remaining score (a tiny epsilon stops float error flipping an exact boundary).
 *   2. If the IVs are unknown, the highest score wins; a tie goes to the later evolution.
 *   3. Otherwise the best IV Rank % wins; a tie goes to the higher score, then the later evolution.
 */
export function chooseMember(candidates, closeScore = CLOSE_SCORE) {
  if (!candidates.length) return null;
  const live = candidates.filter((c) => !c.overCap);
  const pool = live.length ? live : candidates;
  const best = Math.max(...pool.map((c) => c.score));
  const close = pool.filter((c) => c.score >= best - closeScore - 1e-9);
  const known = close.some((c) => c.rankPct != null);
  const key = (c) => (known ? [c.rankPct ?? -1, c.score, c.depth] : [c.score, c.depth]);
  return close.reduce((a, b) => {
    const ka = key(a), kb = key(b);
    for (let i = 0; i < ka.length; i++) if (ka[i] !== kb[i]) return kb[i] > ka[i] ? b : a;
    return b; // fully tied: the later one in family order
  });
}

const regionOf = (id) => id.match(/_(alolan|galarian|hisuian|paldean)(?:_|$)/)?.[1] ?? null;

// Everything the Pokémon can become by the game master's evolution links or by a form change (energy, cells, fusion: Zygarde,
// Crowned Zamazenta; the same set the advisor reaches), minus the cross-regional links: a Cubone becomes Marowak, not Alolan Marowak
// (that happens only in special events), while Galarian Meowth still reaches Perrserker, whose id carries no region.
function descendants(gm, start) {
  const out = [];
  const seen = new Set([start]);
  const stack = [start];
  while (stack.length) {
    const parent = stack.pop();
    const links = [...evolutionLinks(gm, parent), ...(FORM_CHANGES[parent] ?? []).filter((id) => gm.byId.has(id))];
    for (const next of links) {
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
 * Returns { gl, ul, ml }; each league is
 *   { options: [Option], pick: int, experimental: int, source: 'export' | 'emulated' | 'ranked' | 'fallback' }
 * `pick` is the index into `options` of the member to show (the Poke Genie-compatible rule), `experimental` the index of the
 * CLOSE_SCORE rule's member (shown under the Pogo Assist ranking); they may be the same index. `experimental` is never a member the copy is already past the
 * cap for, unless every member is, and then it is the shown pick. `source` says how `pick` was decided: 'export' = Poke Genie's own
 * pick from the entry, 'emulated' = the stat-product emulation (Great and Ultra only), 'ranked' = the highest PvPoke score (Master
 * League, or unknown IVs), 'fallback' = the PvPoke-score rule ran (Master League, or unknown IVs) but none of the members it may show is ranked here: either nothing in the family is ranked, or every ranked member is past the cap. The shown member is then the final evolution if it fits, else the first option that fits, which is an unranked one (a level-50 Bulbasaur with unknown IVs shows Ivysaur in Ultra League). If no member fits and nothing is ranked, the final evolution is shown even though it is over the cap. A copy with known IVs in Great or Ultra League and nothing ranked is still 'emulated'.
 * Option = { speciesId, name, self, genderLocked?, strength, moves, needs, iv, overCap, cost }:
 *   speciesId, name: the member (the _shadow id and name where the entry is a Shadow and PvPoke ranks the Shadow);
 *   self: it is the Pokémon itself; genderLocked: 'male'|'female', only when the sex is unknown and one sex can become it;
 *   strength: { score, rank, of } from PvPoke, or null when PvPoke does not rank it in this league;
 *   moves: { fast, charged[] } on every option PvPoke ranks, else null (an unranked option has none); needs: the recommended moves this copy lacks, only on the Pokémon itself, else null;
 *   iv: { rank, pct, rankPct, level, cp } for this copy's IVs as this member, or null (unknown IVs or cannot fit under the cap);
 *   overCap: this copy's CP at its current level (0/0/0 if its IVs are unknown) already exceeds the cap as the member (never when the level is unknown, or in Master League); cost: dust/candy/xl to that level plus the
 *   candy to evolve there (evolveCandy), or null (no IVs, no level, over the cap). A copy whose best level is BELOW its current one (a
 *   level-51 Best Buddy copy, in any league) costs nothing to power up: dust/candy/xl 0, toLevel its best level, evolveCandy still due.
 * Options are every allowed family member: ranked ones first (score, then Rank %, then later evolution), then unranked ones
 * (later evolution first). Unreleased members are left out unless the whole family is unreleased.
 */
export function leaguesFor(entry, resolved, ctx) {
  const { gm, rankings } = ctx;
  const start = baseSpeciesId(gm, resolved.speciesId);
  const sex = sexOf(entry.gender);
  let family = [];
  for (const id of [start, ...descendants(gm, start)]) {
    const base = baseSpeciesId(gm, id);
    // The Pokémon itself always stays (a misread sex must not hide it); evolutions the other sex cannot become go.
    if (sex && base !== start && GENDER_LOCKED[base] && GENDER_LOCKED[base] !== sex) continue;
    if (gm.byId.has(base) && !NOT_ALLOWED.test(id) && !NOT_ALLOWED.test(base) && !family.includes(base)) family.push(base);
  }
  // Unreleased members (nobody can build Farigiraf yet) are skipped; a family with none released keeps them all.
  const released = family.filter((id) => gm.byId.get(id).released !== false);
  if (released.length) family = family.filter((id) => id === start || released.includes(id));
  const depthOf = (base) => (base === start ? 0 : evolutionPath(gm, start, base)?.length ?? family.indexOf(base));
  const ivs = validIvs(entry.ivs) ? entry.ivs : null;
  const have = entry.moves ?? [];
  const level = typeof entry.level === 'number' && Number.isInteger(entry.level * 2) && entry.level >= 1 && entry.level <= 51 ? entry.level : null; // a half-level the game has
  // The final evolution: the strongest one if the family branches (by CP at level 50 with 15/15/15).
  const finals = family.filter((id) => !evolutionLinks(gm, id).some((e) => family.includes(baseSpeciesId(gm, e))));
  const top = (id) => cpAt(gm.byId.get(id).baseStats, MAX_IV, 50);
  const finalEvolution = finals.length ? finals.reduce((a, b) => (top(b) > top(a) ? b : a)) : start;
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
    // Over the cap = the copy's CP at its CURRENT level already exceeds the league's cap (a Pokémon cannot be powered down). With
    // unknown IVs the best case, 0/0/0, is used, so a level-35 Rookidee is over the Great League cap for Corviknight whatever its
    // IVs are. Unknown level: never over. Master League has no cap, so a Best Buddy copy at 51 is simply past the last power-up.
    const ZERO_IVS = { atk: 0, def: 0, hp: 0 };
    const overCapOf = (base) => league !== 'ml' && level != null && cpAt(gm.byId.get(base).baseStats, ivs ?? ZERO_IVS, level) > CAPS[league];

    // One family member rated for this league: everything the Pokémon screen shows for it.
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
      const overCap = overCapOf(base);
      let cost = null;
      // A best level below the current one (a level-51 Best Buddy copy, in any league) leaves nothing to power up, so the cost is the
      // same zero as for a copy already at its best level (powerUpCost goes backwards to nothing), with the evolution candy still due.
      if (iv && level != null && !overCap) {
        const flags = { shadow: entry.shadow, purified: entry.purified, lucky: entry.lucky };
        const up = powerUpCost(level, iv.level, flags);
        const path = evolutionPath(gm, start, base) ?? [];
        const evo = path.reduce((s, [from, to]) => s + (FORM_CHANGES[from]?.includes(to) ? 0 : evolveCandy(gm, from, to)), 0);
        cost = { dust: up.dust, candy: up.candy, xl: up.xl, evolveCandy: evo, toLevel: iv.level };
      }
      return {
        speciesId: rankId, name: gm.byId.get(rankId)?.speciesName ?? gm.byId.get(base).speciesName, self: base === start,
        // Only worth saying when the sex is unknown and the option is an evolution that one sex cannot become.
        ...(!sex && base !== start && GENDER_LOCKED[base] ? { genderLocked: GENDER_LOCKED[base] } : {}),
        strength: row ? { score: row.score, rank: row.rank, of: map.size } : null,
        moves, needs, iv: ivOut, overCap, cost,
      };
    };

    const members = family.map((base) => ({ base, row: map.get(rankedId(base)) ?? null, iv: ivOf(base), depth: depthOf(base), overCap: overCapOf(base) }));
    // Options: ranked first (score, then Rank %, then later evolution), then the unranked, later evolution first (their Rank % does not order them).
    const shown = [...members].sort((a, b) => (b.row ? b.row.score : -1) - (a.row ? a.row.score : -1) || (a.row ? (b.iv?.rankPct ?? -1) - (a.iv?.rankPct ?? -1) : 0) || b.depth - a.depth);
    const options = shown.map((m) => rate(m.base, m.row));
    const indexOf = (base) => shown.findIndex((m) => m.base === base);
    const fitsBase = (base) => { const m = members.find((x) => x.base === base); return !!m && !m.overCap; };
    const asMember = (m) => ({ id: m.base, score: m.row?.score ?? null, depth: m.depth, iv: m.iv, overCap: m.overCap });

    // Shown pick. 1: Poke Genie's own pick, when the entry has it and it is in this family.
    let pickBase = null, source = 'emulated';
    const column = EXPORT_COLUMN[league] && entry.pvp?.[EXPORT_COLUMN[league]];
    if (column?.name) {
      const theirs = resolveSpecies(gm, column.name, { form: column.form });
      const base = theirs && baseSpeciesId(gm, theirs.speciesId);
      if (base && indexOf(base) >= 0) { pickBase = base; source = 'export'; }
    }
    // 2 and 3: the emulation (Great and Ultra only: Poke Genie exports no Master League pick, so there is nothing to copy and the
    // emulation would only follow ~0.07% stat-product noise); Master League and unknown IVs take the PvPoke score, and a family with
    // nothing ranked its final evolution.
    if (!pickBase) {
      const emulate = !!ivs && league !== 'ml';
      const m = pokeGeniePick(members.map((x) => (emulate ? asMember(x) : { ...asMember(x), iv: null })));
      if (m) { pickBase = m.id; source = emulate && m.iv ? 'emulated' : 'ranked'; }
      // Nothing ranked fits: the final evolution, unless the copy is past the cap for it, then the first member that fits.
      else { pickBase = fitsBase(finalEvolution) ? finalEvolution : (shown.find((x) => !x.overCap)?.base ?? finalEvolution); source = 'fallback'; }
    }

    // Experimental pick: the CLOSE_SCORE rule over the ranked members. It is never a member the copy is already too strong for:
    // chooseMember only returns one when every ranked member is over the cap, and then the next best is the shown pick, then the
    // first member that fits; only a family where every member is over the cap takes the shown pick even if it is over the cap.
    const win = chooseMember(members.filter((m) => m.row).map((m) => ({ id: m.base, score: m.row.score, rankPct: m.iv?.rankPct ?? null, depth: m.depth, overCap: m.overCap })));
    let expBase = win && fitsBase(win.id) ? win.id : null;
    if (!expBase && !win && fitsBase(finalEvolution)) expBase = finalEvolution; // nothing ranked at all: the final evolution
    if (!expBase) expBase = fitsBase(pickBase) ? pickBase : (shown.find((m) => !m.overCap)?.base ?? pickBase);
    const pick = indexOf(pickBase), experimental = indexOf(expBase);
    // Every option PvPoke ranks keeps its moves (the Pokémon page's expanded option row shows them), so none is trimmed here.
    out[league] = { options, pick, experimental, source };
  }
  return out;
}
