// The advisor: turns an imported box plus the tier tables and PvP rankings into ranked builds, gaps and hygiene.
import { resolveSpecies, evolutionsOf, formChangesOf, megaIdsOf, baseSpeciesId, FORM_CHANGES } from './gamemaster.js';
import { evolveCandy, evolutionPath } from './evolve.js';
import { leaguesFor } from './leagues.js';
import { powerUpCost, secondMoveCost } from './cost.js';
import { cpAt } from './cpm.js';
import { clearRankCache } from './pvp-rank.js';

export const AREA_LABEL = { raids: 'Raids', rocket: 'Rocket', gym: 'Gym', gl: 'GL', ul: 'UL', ml: 'ML', max: 'Max' };

// ---- how a build is worded: shared by the web page and scripts/advise.mjs (the Swift side renders the same steps in BoxAdvice.Build.action) ----
//
// A build carries `steps`, the list of things still to do, computed once in analyseBox. Kinds:
//   { kind: 'evolve', to, candy } | { kind: 'formChange', to } | { kind: 'megaEvolve' }
//   { kind: 'powerUp', toLevel, areas }   exactly the climb the build's cost covers: the pvpCost league's best level for a league-only
//                                         build, else the highest non-league target level (areas = every area tied on it). At most one.
//   { kind: 'secondMove', certain }       certain=false: the copy's moves are unknown (a scan), so it may already have it
//   { kind: 'eliteTM', count }            distinct Elite moves the entry asks for that the copy does not have
//   { kind: 'cdMove' }                    a Community Day move the entry asks for that the copy does not have
//   { kind: 'needsDynamaxCopy' }          only the Max area needs it: it does not make the other areas unfinished
// The list is empty (or holds only needsDynamaxCopy) when the copy is already built. `leavesLeague` is a note, not a step: a league whose
// best level the climb goes past ({ league, bestLevel }).

const labels = (areas) => areas.map((a) => AREA_LABEL[a]).join('/');

/** The level the build climbs to (the one its cost covers) with its areas, or why there is nothing to climb to. */
export function levelText(b) {
  const up = b.steps.find((x) => x.kind === 'powerUp');
  const note = (b.leavesLeague ?? []).map((x) => `going past ${x.bestLevel} leaves ${AREA_LABEL[x.league]}`).join(', ');
  if (up) return `L${b.level} → ${up.toLevel} (${labels(up.areas)})${note ? `; ${note}` : ''}`;
  // Nothing to power up: say for which area's target (or the league's own best level) the copy is already there.
  const league = b.pvpCost && b.costAreas.includes(b.pvpCost.league);
  return `L${b.level} · already at (or past) its ${league ? `best ${AREA_LABEL[b.pvpCost.league]} level` : `${labels(b.costAreas)} target level`}`;
}

/**
 * What is left to do, plain text, from the steps. The Dynamax requirement is Max's alone: it is said inside the Max power-up bracket
 * ("(Max; needs a Dynamax copy)") or after the rest, and a build for Max alone that lacks nothing else reads "Needs a Dynamax copy";
 * a build with other areas and nothing left reads "Already built (Max needs a Dynamax copy)".
 */
export function actionText(b) {
  const dynamax = b.steps.some((x) => x.kind === 'needsDynamaxCopy');
  let inlined = false;
  const parts = [];
  for (const x of b.steps) {
    if (x.kind === 'evolve') parts.push(`Evolve to ${x.to}`);
    else if (x.kind === 'formChange') parts.push(`Form change to ${x.to}`);
    else if (x.kind === 'megaEvolve') parts.push('Mega evolve');
    else if (x.kind === 'powerUp') {
      const say = dynamax && x.areas.includes('max');
      inlined = inlined || say;
      parts.push(`Power up to level ${x.toLevel} (${labels(x.areas)}${say ? '; needs a Dynamax copy' : ''})`);
    }
    else if (x.kind === 'secondMove') parts.push(x.certain ? 'Second move' : "Second move (if it doesn't have it)");
    else if (x.kind === 'eliteTM') parts.push(x.count === 1 ? '1 Elite TM' : `${x.count} Elite TMs`);
    else if (x.kind === 'cdMove') parts.push('Community Day move');
  }
  if (!parts.length) return dynamax && b.areas?.length === 1 && b.areas[0] === 'max' ? 'Needs a Dynamax copy' : dynamax ? 'Already built (Max needs a Dynamax copy)' : 'Already built';
  const base = parts.join(' + ');
  return dynamax && !inlined ? `${base} (Max needs a Dynamax copy)` : base;
}

/** The leagues a climb to `climbTo` goes past: those whose best level is at or above the copy's level and below the climb. */
export function leagueNotes(climbTo, level, bests) {
  if (climbTo == null || climbTo <= level) return [];
  return bests.filter((x) => x.bestLevel != null && x.bestLevel >= level && climbTo > x.bestLevel);
}

/**
 * The Elite and Community Day moves tier-table entries name: "Fast (Elite fast) / Charged (CD) + Charged (Elite)" gives the move names from
 * EVERY part, the fast move included. Each entry is read on its own: a marker the text has but the parser could not attach to a name
 * (an odd format) counts as one move that cannot be held, so an unreadable entry never hides a requirement or inflates another's.
 */
export function markedMoves(texts) {
  const elite = new Set(), cd = new Set();
  texts.forEach((text, i) => {
    const entryElite = new Set(), entryCd = new Set();
    for (const part of String(text).split('/')) {
      for (const slot of part.split(/\s\+\s/)) {
        for (const alt of slot.split(/\s+or\s+/i)) {
          const name = alt.replace(/\([^)]*\)/g, '').trim();
          const quals = [...alt.matchAll(/\(([^)]*)\)/g)].map((m) => m[1]);
          if (name && quals.some((q) => /^Elite/i.test(q))) entryElite.add(name);
          if (name && quals.some((q) => /^(CD|Community Day)/i.test(q))) entryCd.add(name);
        }
      }
    }
    const mentions = (re) => (String(text).match(re) || []).length;
    for (let k = entryElite.size; k < mentions(/\(Elite[^)]*\)/gi); k++) entryElite.add(`?${i}:${k}`);
    if (!entryCd.size && /\((CD|Community Day)[^)]*\)/i.test(String(text))) entryCd.add(`?${i}`);
    entryElite.forEach((m) => elite.add(m)); entryCd.forEach((m) => cd.add(m));
  });
  return { elite, cd };
}
const normMove = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');

const TIER_W = { S: 3, A: 2, B: 1 };
// How much a hit in each area is worth relative to a raid hit. Gym is shallow; Max hits need a Dynamax-capable copy.
const AREA_W = { raids: 1, gl: 1, ul: 1, ml: 1, rocket: 0.6, max: 0.6, gym: 0.35 };
// PvPoke overall score at or above which a species counts as PvP-relevant even if no tier table names it.
const PVP_SCORE = { gl: 88, ul: 88, ml: 88 };
// Target level per area for costing (PvP uses leaguesFor's per-league cost when available).
const TARGET_LEVEL = { raids: 35, rocket: 30, gym: 30, max: 30, ml: 50, gl: 30, ul: 40 };

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
  const needLeagues = [];            // entries whose leagues are worked out after the loop, grouped by species

  for (const p of box) {
    const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
    if (!r) { pokemon.push({ p, unresolved: true }); continue; }
    ownedIds.add(r.speciesId); ownedBase.add(baseSpeciesId(gm, r.speciesId));
    const reach = [r.speciesId, ...evolutionsOf(gm, r.speciesId), ...formChangesOf(gm, r.speciesId)];
    const targets = new Set(reach);
    // A Shadow can never Mega evolve. Keyed on the resolved id, like the credit rule and the gap check below, so a copy named "Shadow X"
    // without the flag is a Shadow here too (it used to read the flag and gave such a copy Mega credit).
    if (!r.speciesId.endsWith('_shadow')) for (const id of reach) for (const m of megaIdsOf(gm, id)) targets.add(m);

    const hits = [];
    for (const id of targets) {
      for (const e of tiers.bySpecies.get(id) || []) {
        // A Gigantamax entry is only ever satisfied by a Gigantamax catch, which an export cannot show: never credit it to a box Pokémon.
        if (e.area === 'max' && /gigantamax|g-max/i.test(e.name)) continue;
        // Mega targets are the same Pokémon plus Mega Energy: credit them to the base target.
        const targetId = /_(mega(_[xy])?|primal)$/.test(id) ? baseSpeciesId(gm, id) : id;
        hits.push({ kind: 'tier', area: e.area, section: e.section, tier: e.tier, name: e.name, targetId, viaMega: targetId !== id ? id : null, needsDynamax: e.area === 'max', moves: e.moves, obtain: e.obtain, notes: e.notes });
      }
      // A Shadow copy also does the job of the plain species' raid and Rocket entries (a Shadow attacks as well as, and harder than, the plain
      // one). Not the plain gym entry (a Shadow defends worse, 0.83x; a manager call) and not max (a Shadow is never a Dynamax catch).
      // Credited to the _shadow id, the copy stays Shadow; when the _shadow id already has an entry for the same area and section, the
      // plain one is not added whatever its tier. The gap check below mirrors this rule.
      if (id.endsWith('_shadow') && gm.byId.has(id.replace(/_shadow$/, ''))) {
        for (const e of tiers.bySpecies.get(id.replace(/_shadow$/, '')) || []) {
          if (e.area !== 'raids' && e.area !== 'rocket') continue;
          if (hits.some((h) => h.kind === 'tier' && h.targetId === id && h.area === e.area && h.section === e.section)) continue;
          hits.push({ kind: 'tier', area: e.area, section: e.section, tier: e.tier, name: e.name, targetId: id, viaMega: null, needsDynamax: false, moves: e.moves, obtain: e.obtain, notes: e.notes });
        }
      }
      for (const [league, map] of Object.entries(rankings.byLeague)) {
        const row = map.get(id);
        if (row && row.score >= PVP_SCORE[league]) {
          const already = hits.some((h) => h.kind === 'tier' && h.area === league && h.targetId === id);
          if (!already) hits.push({ kind: 'rank', area: league, section: null, tier: row.score >= 92 ? 'S' : row.score >= 90 ? 'A' : 'B', name: gm.byId.get(id).speciesName, targetId: id, moves: row.moveset.join(' / '), rank: row.rank, score: row.score });
        }
      }
    }
    const entry = { p, resolved: r, hits, leagues: null };
    pokemon.push(entry);
    needLeagues.push(entry);
  }

  // Leagues next, one species at a time: the IV rank tables are the expensive part, and the same species (so the same family)
  // reuses the tables it just built, which keeps the table cache small however the box is ordered. Results land on the entries,
  // so pokemon[] keeps the box's order.
  needLeagues.sort((x, y) => (x.resolved.speciesId < y.resolved.speciesId ? -1 : x.resolved.speciesId > y.resolved.speciesId ? 1 : 0));
  for (const e of needLeagues) e.leagues = leaguesFor(e.p, e.resolved, ctx);

  // Builds: one per (Pokémon, targetId), aggregating the areas it serves.
  const builds = [];
  for (const entry of pokemon) {
    if (entry.unresolved) continue;
    const { p, resolved: r, hits } = entry;
    const byTarget = new Map();
    for (const h of hits) { if (!byTarget.has(h.targetId)) byTarget.set(h.targetId, []); byTarget.get(h.targetId).push(h); }
    for (const [targetId, allHits] of byTarget) {
      // This copy's rating in a league AS THE BUILD'S TARGET: the target's own option in leaguesFor, whether or not it is the member
      // shown as the pick. Read from leaguesFor rather than the Poke Genie columns so that scans (which have none) are rated too.
      // No rating (neutral weight, no league cost) when the IVs are unknown, and for Master League, which keeps its old behaviour:
      // neutral weight, and never the cost league (a level-50 ML cost would swamp the GL and UL chips of a Pokémon that is not built for it).
      const targetBase = baseSpeciesId(gm, targetId);
      const optionOf = (a) => entry.leagues?.[a]?.options.find((x) => baseSpeciesId(gm, x.speciesId) === targetBase);
      const ourLeague = (a) => (a === 'ml' ? null : optionOf(a)?.iv ? optionOf(a) : null);
      // A league is not an area of this build when the copy is already past that league's cap as the target (a level-35 Rookidee for
      // Corviknight in Great League): there is nothing to build towards, and a neutral weight would outrank a usable copy. A build
      // left with no area at all is dropped.
      const ths = allHits.filter((h) => !['gl', 'ul', 'ml'].includes(h.area) || !optionOf(h.area)?.overCap);
      if (!ths.length) continue;
      // Value: raids count each attacking type covered (up to three); other areas count once at their best tier.
      // PvP areas are scaled by this exact Pokémon's rank in that league as Our pick (squared: a mid-rank spread is worth little).
      const areas = new Map();
      const raidTypes = new Map();
      for (const h of ths) {
        const w = TIER_W[h.tier];
        if (h.area === 'raids' && h.section && h.section !== 'S tier — build first' && !/tier/i.test(h.section)) { if (!raidTypes.has(h.section) || raidTypes.get(h.section) < w) raidTypes.set(h.section, w); }
        if (!areas.has(h.area) || areas.get(h.area) < w) areas.set(h.area, w);
      }
      const leagueQ = (a) => {
        const L = ourLeague(a);
        return L ? 0.15 + 0.85 * (L.iv.rankPct / 100) ** 2 : 0.6;
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
      // Costing: the most demanding area decides the target level; PvP uses leaguesFor's figures when Our pick is the target.
      const flags = { shadow: p.shadow, purified: p.purified, lucky: p.lucky };
      const level = p.level ?? 20;
      const pvpAreas = [...areas.keys()].filter((a) => ['gl', 'ul', 'ml'].includes(a));
      const otherAreas = [...areas.keys()].filter((a) => !pvpAreas.includes(a));
      // leaguesFor knows this exact Pokémon's cost to its best level in each league (evolution candy included, as Poke Genie's
      // column was); take the league where it ranks best.
      let pvpCost = null;
      for (const a of pvpAreas) {
        const L = ourLeague(a);
        if (L?.cost && (!pvpCost || L.iv.rankPct > pvpCost.rankPct)) {
          pvpCost = { league: a, dust: L.cost.dust, candy: L.cost.candy + L.cost.evolveCandy, xl: L.cost.xl, rankPct: L.iv.rankPct, rank: L.iv.rank, toLevel: L.cost.toLevel };
        }
      }
      let targetLevel = otherAreas.length ? Math.max(...otherAreas.map((a) => TARGET_LEVEL[a])) : Math.max(...pvpAreas.map((a) => TARGET_LEVEL[a]));
      let cost = powerUpCost(level, Math.max(level, targetLevel), flags);
      if (pvpCost && !otherAreas.length) { cost = { dust: pvpCost.dust, candy: pvpCost.candy, xl: pvpCost.xl, steps: 0 }; targetLevel = null; }
      // A copy already at or above its target level has nothing to power up to: no target level to show (screens say "already there").
      if (targetLevel != null && targetLevel <= level) targetLevel = null;
      // Which areas the cost above is for (all that tie on the target level, in the order of the hits): the league when only league
      // areas drive it and leaguesFor costed one, else the non-league areas with the highest target level.
      const costPool = otherAreas.length ? otherAreas : pvpAreas;
      const costTop = pvpCost && !otherAreas.length ? null : Math.max(...costPool.map((a) => TARGET_LEVEL[a]));
      const costAreas = pvpCost && !otherAreas.length ? [pvpCost.league] : costPool.filter((a) => TARGET_LEVEL[a] === costTop);
      const mf = moveFlags(ths.map((h) => h.moves).join(' '));
      // The second charged move: due unless the copy's second charged slot is already unlocked (Poke Genie's "Charge Move 2" is filled;
      // the slot survives evolution, so it is the slot that counts, not the move names, and moves may still need TMs: no step for that).
      // A scan records no moves, so it may already have it: still charged, and worded "if it doesn't have it".
      const slotsKnown = Array.isArray(p.chargedMoves);
      const secondState = !mf.plusMove ? 'none' : slotsKnown && p.chargedMoves[1] ? 'have' : slotsKnown ? 'due' : 'unknown';
      const secondMove = secondState === 'due' || secondState === 'unknown' ? secondMoveCost(gm.byId.get(stepTarget)?.thirdMoveCost ?? 50000, flags) : { dust: 0, candy: 0 };
      const totalDust = cost.dust + secondMove.dust;
      const totalCandy = (pvpCost && !otherAreas.length ? cost.candy : cost.candy + evoCandy) + secondMove.candy;
      const effort = totalDust / 100000 + totalCandy / 100 + cost.xl / 148 + mf.elite * 1.5 + (formChange ? 1.5 : 0) + (viaMega ? 0.3 : 0);
      // The steps still to do. The power-up step is exactly the climb the cost above covers (never a level or league it does not pay
      // for): the league's best level for a league-only build, else the highest non-league target. A league's own best level shows
      // up only as the note that the climb goes past it.
      const steps = [];
      const heldMoves = new Set((p.moves ?? []).map(normMove));
      const climbTo = pvpCost && !otherAreas.length ? pvpCost.toLevel : targetLevel;
      if (targetId !== r.speciesId) steps.push(formChange ? { kind: 'formChange', to: gm.byId.get(targetId)?.speciesName ?? targetId } : { kind: 'evolve', to: gm.byId.get(targetId)?.speciesName ?? targetId, candy: evoCandy });
      if (viaMega) steps.push({ kind: 'megaEvolve' });
      if (climbTo != null && climbTo > level) steps.push({ kind: 'powerUp', toLevel: climbTo, areas: costAreas });
      const leavesLeague = leagueNotes(climbTo, level, pvpAreas.filter((a) => !costAreas.includes(a) && a !== 'ml').map((a) => ({ league: a, bestLevel: ourLeague(a)?.cost?.toLevel })));
      if (secondState === 'due' || secondState === 'unknown') steps.push({ kind: 'secondMove', certain: secondState === 'due' });
      // Elite and Community Day moves the entries ask for: counted by distinct move name, and dropped when the recorded moves already hold
      // them (the effort above still counts table mentions, as before).
      const marked = markedMoves(ths.map((h) => h.moves || ''));
      const missing = (set) => [...set].filter((m) => !heldMoves.has(normMove(m)));
      const eliteCount = missing(marked.elite).length;
      if (eliteCount > 0) steps.push({ kind: 'eliteTM', count: eliteCount });
      if (missing(marked.cd).length > 0) steps.push({ kind: 'cdMove' });
      if (needsDynamax) steps.push({ kind: 'needsDynamaxCopy' });
      // IV quality: PvP uses this copy's league rank % (squared, so a mid-rank spread is worth little); everything else uses IV average, mildly.
      const ivQ = (p.ivPercent ? 0.8 + 0.2 * (p.ivPercent / 100) : 0.9) * (evoCandy === 0 && !formChange ? 1.3 : 1); // already the final form: phase 1 material
      builds.push({
        pokemon: p, speciesId: r.speciesId, targetId, targetName: gm.byId.get(targetId)?.speciesName ?? targetId,
        areas: [...areas.keys()], bestTier, value: Math.round(value * 100) / 100, hits: ths, path, evoCandy, formChange, viaMega, needsDynamax,
        level, targetLevel, costAreas, steps, leavesLeague,
        cost: { ...cost, dust: totalDust, candy: totalCandy, secondMove }, pvpCost, moveFlags: mf,
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
      // Same rule as the Shadow credit above: a Shadow of the species covers its plain raid and Rocket entries.
      if ((e.area === 'raids' || e.area === 'rocket') && reach.includes(`${e.speciesId}_shadow`)) return true;
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

  // The IV rank tables are only worth keeping while this box is being analysed; the app caches the advice per box snapshot.
  clearRankCache();
  return { pokemon, builds: primaryBuilds, allBuilds: builds, gaps, hygiene };
}
