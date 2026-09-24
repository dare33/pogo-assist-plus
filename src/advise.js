// The advisor: turns an imported box plus the tier tables and PvP rankings into ranked builds, gaps and hygiene.
import { resolveSpecies, evolutionsOf, formChangesOf, megaIdsOf, baseSpeciesId, FORM_CHANGES } from './gamemaster.js';
import { powerUpCost, secondMoveCost } from './cost.js';
import { cpAt } from './cpm.js';

export const AREA_LABEL = { raids: 'Raids', rocket: 'Rocket', gym: 'Gym', gl: 'GL', ul: 'UL', ml: 'ML', max: 'Max' };
const TIER_W = { S: 3, A: 2, B: 1 };
// How much a hit in each area is worth relative to a raid hit. Gym is shallow; Max hits need a Dynamax-capable copy.
const AREA_W = { raids: 1, gl: 1, ul: 1, ml: 1, rocket: 0.6, max: 0.6, gym: 0.35 };
// PvPoke overall score at or above which a species counts as PvP-relevant even if no tier table names it.
const PVP_SCORE = { gl: 88, ul: 88, ml: 88 };
// Target level per area for costing (PvP uses the export's own per-league cost when available).
const TARGET_LEVEL = { raids: 35, rocket: 30, gym: 30, max: 30, ml: 50, gl: 30, ul: 40 };

// Evolution candy: the game master does not carry it. Defaults by position in the family plus known exceptions.
const EVOLVE_CANDY_OVERRIDES = {
  swablu: 400, magikarp: 400, wailmer: 400, meltan: 400, feebas: 100, pidgey: 12, weedle: 12, caterpie: 12, wurmple: 12,
  rattata: 25, rattata_alolan: 25, eevee: 25, sunkern: 50, rhydon: 100, machoke: 100, haunter: 100, dragonair: 100, metang: 100,
  pupitar: 100, shelgon: 100, larvitar: 25, bagon: 25, beldum: 25, dratini: 25, gastly: 25, gible: 25, gabite: 100, riolu: 50,
  swinub: 25, piloswine: 100, rhyhorn: 25, munchlax: 50, chansey: 50, tinkatink: 25, tinkatuff: 100, rookidee: 25, corvisquire: 100,
  mankey: 50, primeape: 100, fletchling: 25, fletchinder: 100, fuecoco: 25, crocalor: 100, mareep: 25, flaaffy: 100, fidough: 50,
  drilbur: 50, cubone: 50, wooper: 50, wooper_paldean: 50, dewpider: 50, spearow: 50, slakoth: 25, vigoroth: 100, frillish: 50,
  piplup: 25, prinplup: 100, totodile: 25, croconaw: 100, sobble: 25, drizzile: 100, charmander: 25, charmeleon: 100, mudkip: 25,
  marshtomp: 100, machop: 25, timburr: 50, gurdurr: 200, teddiursa: 50, ursaring: 100, roggenrola: 50, boldore: 200, litwick: 25, lampent: 100,
  nickit: 50, flabebe: 25, floette: 100, tympole: 25, palpitoad: 100, scorbunny: 25, raboot: 100, grookey: 25, thwackey: 100, vulpix: 50,
  vulpix_alolan: 50, ralts: 25, kirlia: 100, electabuzz: 100, magmar: 100, sneasel: 100, duskull: 25, dusclops: 100, larvesta: 400,
};
function evolveCandy(index, fromId, toId) {
  const from = baseSpeciesId(index, fromId);
  if (EVOLVE_CANDY_OVERRIDES[from] !== undefined) return EVOLVE_CANDY_OVERRIDES[from];
  const p = index.byId.get(from);
  const isFirst = !p?.family?.parent;
  const hasGrandchild = (p?.family?.evolutions ?? []).some((e) => (index.byId.get(e)?.family?.evolutions ?? []).length);
  return isFirst ? (hasGrandchild ? 25 : 50) : 100;
}

/** Path of evolution steps from one id to a descendant: [[from, to], ...]. */
function evolutionPath(index, fromId, toId) {
  const queue = [[fromId, []]];
  const seen = new Set([fromId]);
  while (queue.length) {
    const [id, path] = queue.shift();
    if (id === toId) return path;
    for (const next of [...(index.byId.get(id)?.family?.evolutions ?? []), ...(FORM_CHANGES[id] ?? [])]) {
      if (!seen.has(next)) { seen.add(next); queue.push([next, [...path, [id, next]]]); }
    }
  }
  return null;
}

function moveFlags(movesText) {
  const t = movesText || '';
  return {
    elite: (t.match(/\(Elite[^)]*\)/gi) || []).length,
    cd: /\((CD|Community Day)[^)]*\)/i.test(t),
    legacy: /\(legacy[^)]*\)/i.test(t),
    plusMove: /\s\+\s/.test(t), // "Move A + Move B" means a second charged move; "Future Sight+" does not
  };
}

/**
 * Analyse a box. Returns { pokemon: [...per-Pokémon analyses], builds, gaps, hygiene }.
 * ctx = { gm, tiers, rankings }
 */
export function analyseBox(box, ctx) {
  const { gm, tiers, rankings } = ctx;
  const pokemon = [];
  const ownedBase = new Set();       // base species ids present in the box (any variant)
  const ownedIds = new Set();

  for (const p of box) {
    const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
    if (!r) { pokemon.push({ p, unresolved: true }); continue; }
    ownedIds.add(r.speciesId); ownedBase.add(baseSpeciesId(gm, r.speciesId));
    const reach = [r.speciesId, ...evolutionsOf(gm, r.speciesId), ...formChangesOf(gm, r.speciesId)];
    const targets = new Set(reach);
    if (!p.shadow) for (const id of reach) for (const m of megaIdsOf(gm, id)) targets.add(m);

    const hits = [];
    for (const id of targets) {
      for (const e of tiers.bySpecies.get(id) || []) {
        // A Gigantamax entry is only ever satisfied by a Gigantamax catch, which an export cannot show: never credit it to a box Pokémon.
        if (e.area === 'max' && /gigantamax|g-max/i.test(e.name)) continue;
        // Mega targets are the same Pokémon plus Mega Energy: credit them to the base target.
        const targetId = /_(mega(_[xy])?|primal)$/.test(id) ? baseSpeciesId(gm, id) : id;
        hits.push({ kind: 'tier', area: e.area, section: e.section, tier: e.tier, name: e.name, targetId, viaMega: targetId !== id ? id : null, needsDynamax: e.area === 'max', moves: e.moves, obtain: e.obtain, notes: e.notes });
      }
      for (const [league, map] of Object.entries(rankings.byLeague)) {
        const row = map.get(id);
        if (row && row.score >= PVP_SCORE[league]) {
          const already = hits.some((h) => h.kind === 'tier' && h.area === league && h.targetId === id);
          if (!already) hits.push({ kind: 'rank', area: league, section: null, tier: row.score >= 92 ? 'S' : row.score >= 90 ? 'A' : 'B', name: gm.byId.get(id).speciesName, targetId: id, moves: row.moveset.join(' / '), rank: row.rank, score: row.score });
        }
      }
    }
    pokemon.push({ p, resolved: r, hits });
  }

  // Builds: one per (Pokémon, targetId), aggregating the areas it serves.
  const builds = [];
  for (const entry of pokemon) {
    if (entry.unresolved) continue;
    const { p, resolved: r, hits } = entry;
    const byTarget = new Map();
    for (const h of hits) { if (!byTarget.has(h.targetId)) byTarget.set(h.targetId, []); byTarget.get(h.targetId).push(h); }
    for (const [targetId, ths] of byTarget) {
      // Value: raids count each attacking type covered (up to three); other areas count once at their best tier.
      // PvP areas are scaled by this exact Pokémon's rank in that league from the export (squared: a mid-rank spread is worth little).
      const areas = new Map();
      const raidTypes = new Map();
      for (const h of ths) {
        const w = TIER_W[h.tier];
        if (h.area === 'raids' && h.section && h.section !== 'S tier — build first' && !/tier/i.test(h.section)) { if (!raidTypes.has(h.section) || raidTypes.get(h.section) < w) raidTypes.set(h.section, w); }
        if (!areas.has(h.area) || areas.get(h.area) < w) areas.set(h.area, w);
      }
      const leagueQ = (a) => {
        const league = a === 'gl' ? 'great' : a === 'ul' ? 'ultra' : 'master';
        const c = p.pvp?.[league];
        const same = c && resolveSpecies(gm, c.name, { form: c.form })?.speciesId === baseSpeciesId(gm, targetId);
        return same && c.rankPct != null ? 0.15 + 0.85 * (c.rankPct / 100) ** 2 : 0.6;
      };
      let value = 0;
      for (const [area, w] of areas) {
        if (area === 'raids') value += [...raidTypes.values()].sort((x, y) => y - x).slice(0, 3).reduce((s, x) => s + x, 0) || w;
        else if (['gl', 'ul', 'ml'].includes(area)) value += w * AREA_W[area] * leagueQ(area);
        else value += w * AREA_W[area];
      }
      const bestTier = ths.reduce((t, h) => (TIER_W[h.tier] > TIER_W[t] ? h.tier : t), 'B');
      const isMega = false;
      const viaMega = ths.some((h) => h.viaMega);
      const needsDynamax = ths.some((h) => h.needsDynamax);
      const stepTarget = targetId;
      const path = evolutionPath(gm, r.speciesId, stepTarget) ?? [];
      const evoCandy = path.reduce((s, [from, to]) => s + (FORM_CHANGES[from]?.includes(to) ? 0 : evolveCandy(gm, from, to)), 0);
      const formChange = path.some(([from, to]) => FORM_CHANGES[from]?.includes(to));
      // Costing: the most demanding area decides the target level; PvP uses the export's own figures when they match the target.
      const flags = { shadow: p.shadow, purified: p.purified, lucky: p.lucky };
      const level = p.level ?? 20;
      const pvpAreas = [...areas.keys()].filter((a) => ['gl', 'ul', 'ml'].includes(a));
      const otherAreas = [...areas.keys()].filter((a) => !pvpAreas.includes(a));
      // The export knows this exact Pokémon's cost to its best level in each league; take the league where it ranks best.
      let pvpCost = null;
      for (const a of pvpAreas) {
        const league = a === 'gl' ? 'great' : a === 'ul' ? 'ultra' : 'master';
        const c = p.pvp?.[league];
        if (c && c.dust !== null && resolveSpecies(gm, c.name, { form: c.form })?.speciesId === baseSpeciesId(gm, targetId)) {
          if (!pvpCost || (c.rankPct ?? 0) > (pvpCost.rankPct ?? 0)) pvpCost = { league: a, dust: c.dust, candy: c.candy, rankPct: c.rankPct, rank: c.rank };
        }
      }
      let targetLevel = otherAreas.length ? Math.max(...otherAreas.map((a) => TARGET_LEVEL[a])) : Math.max(...pvpAreas.map((a) => TARGET_LEVEL[a]));
      let cost = powerUpCost(level, Math.max(level, targetLevel), flags);
      if (pvpCost && !otherAreas.length) { cost = { dust: pvpCost.dust, candy: pvpCost.candy, xl: 0, steps: 0 }; targetLevel = null; }
      const mf = moveFlags(ths.map((h) => h.moves).join(' '));
      const secondMove = mf.plusMove ? secondMoveCost(gm.byId.get(stepTarget)?.thirdMoveCost ?? 50000, flags) : { dust: 0, candy: 0 };
      const totalDust = cost.dust + secondMove.dust;
      const totalCandy = (pvpCost && !otherAreas.length ? cost.candy : cost.candy + evoCandy) + secondMove.candy;
      const effort = totalDust / 100000 + totalCandy / 100 + cost.xl / 148 + mf.elite * 1.5 + (formChange ? 1.5 : 0) + (viaMega ? 0.3 : 0);
      // IV quality: PvP uses the export's rank % (squared, so a mid-rank spread is worth little); everything else uses IV average, mildly.
      const ivQ = (p.ivPercent ? 0.8 + 0.2 * (p.ivPercent / 100) : 0.9) * (evoCandy === 0 && !formChange ? 1.3 : 1); // already the final form: phase 1 material
      builds.push({
        pokemon: p, speciesId: r.speciesId, targetId, targetName: gm.byId.get(targetId)?.speciesName ?? targetId,
        areas: [...areas.keys()], bestTier, value: Math.round(value * 100) / 100, hits: ths, path, evoCandy, formChange, viaMega, needsDynamax,
        level, targetLevel, cost: { ...cost, dust: totalDust, candy: totalCandy, secondMove }, pvpCost, moveFlags: mf,
        effort: Math.round(effort * 100) / 100, score: Math.round((value ** 1.5 * ivQ) / Math.max(0.3, effort) ** 0.6 * 100) / 100,
      });
    }
  }
  builds.sort((a, b) => b.score - a.score);
  // One row per (species, target): the best copy carries the build, the rest are spares.
  const seenBuild = new Map();
  for (const b of builds) {
    const key = `${b.speciesId}|${b.targetId}`;
    if (seenBuild.has(key)) { seenBuild.get(key).spares.push(b.pokemon); b.duplicate = true; } else { b.spares = []; seenBuild.set(key, b); }
  }
  const primaryBuilds = builds.filter((b) => !b.duplicate);

  // Gaps: S and A tier species with nothing in the box that can become them.
  const gaps = [];
  const seenGap = new Set();
  for (const e of tiers.entries) {
    if (!/^[SA]$/.test(e.tier)) continue;
    const base = baseSpeciesId(gm, e.speciesId);
    const reachable = [...ownedIds].some((id) => {
      const reach = [id, ...evolutionsOf(gm, id), ...formChangesOf(gm, id)];
      if (reach.includes(e.speciesId)) return true;
      return !id.endsWith('_shadow') && reach.some((r) => megaIdsOf(gm, r).includes(e.speciesId));
    });
    if (reachable) continue;
    const key = `${e.area}|${e.speciesId}`;
    if (seenGap.has(key)) continue; seenGap.add(key);
    gaps.push({ area: e.area, section: e.section, tier: e.tier, name: e.name, speciesId: e.speciesId, obtain: e.obtain, haveBase: ownedBase.has(base) });
  }
  gaps.sort((a, b) => TIER_W[b.tier] - TIER_W[a.tier] || a.area.localeCompare(b.area));

  // Hygiene: duplicates by resolved species; keep the best IV (and anything with a tier-S hit), transfer the rest.
  const groups = new Map();
  for (const e of pokemon) { if (e.unresolved) continue; const k = e.resolved.speciesId; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(e); }
  const hygiene = [];
  for (const [id, es] of groups) {
    if (es.length < 2) continue;
    const sorted = [...es].sort((a, b) => (b.p.ivPercent ?? 0) - (a.p.ivPercent ?? 0) || b.p.cp - a.p.cp);
    const legendary = (gm.byId.get(id)?.tags ?? []).some((t) => ['legendary', 'mythical', 'ultrabeast'].includes(t));
    const keepCount = legendary ? Math.min(2, es.length) : 1;
    hygiene.push({ speciesId: id, name: gm.byId.get(id).speciesName, count: es.length, keep: sorted.slice(0, keepCount).map((e) => e.p), transfer: sorted.slice(keepCount).map((e) => e.p) });
  }
  hygiene.sort((a, b) => b.transfer.length - a.transfer.length);

  return { pokemon, builds: primaryBuilds, allBuilds: builds, gaps, hygiene };
}
