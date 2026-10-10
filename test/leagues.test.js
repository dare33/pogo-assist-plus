import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseCsv } from '../src/csv.js';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadContext } from '../src/node/load.js';
import { resolveSpecies, baseSpeciesId, evolutionsOf, indexGamemaster } from '../src/gamemaster.js';
import { evolutionPath, evolveCandy } from '../src/evolve.js';
import { analyseBox } from '../src/advise.js';
import { leaguesFor } from '../src/leagues.js';
import { ivRank, bestUnderCap, CAPS, rankCacheSize, clearRankCache } from '../src/pvp-rank.js';
import { powerUpCost, step } from '../src/cost.js';
import { cpAt } from '../src/cpm.js';

const ctx = loadContext();
const { gm, rankings } = ctx;
const box = importPokeGenie(readFileSync(new URL('../fixtures/greg-2026-09-25.pokegenie.csv', import.meta.url), 'utf8'));

// Poke Genie's three league columns: Great, Ultra and Little Cup (CP 500; the app never shows Little Cup).
const PG = [
  { key: 'great', label: 'Great', league: 'gl' },
  { key: 'ultra', label: 'Ultra', league: 'ul' },
  { key: 'little', label: 'Little', league: 'lc' },
];
// Poke Genie's `Sha/Pur (G|U|L)` column says how it rated the copy for that league: 0 as it is, 1 as a Shadow, 2 as PURIFIED.
// A purified Pokémon has each IV raised by 2 (capped at 15) and is set to level 25, so Poke Genie ranks the IVs the copy WOULD have;
// the one row where this matters is Index 176, a Tyrunt rated as a purified Tyrantrum for Ultra (6/15/15, not the 4/15/14 it is now).
// The core has no purify option (a product decision that has not been made); only this test models it.
const rawRows = new Map(parseCsv(readFileSync(new URL('../fixtures/greg-2026-09-25.pokegenie.csv', import.meta.url), 'utf8')).map((r) => [Number(r.Index), r]));
const ratedIvs = (p, label) => {
  const purified = rawRows.get(p.index)[`Sha/Pur (${label[0]})`] === '2';
  return purified ? { atk: Math.min(15, p.ivs.atk + 2), def: Math.min(15, p.ivs.def + 2), hp: Math.min(15, p.ivs.hp + 2) } : p.ivs;
};
const sameMember = (a, b) => a === b || [a, b].every((x) => x === 'oinkologne' || x === 'oinkologne_female');
const pgPick = (p, key) => {
  const c = p.pvp[key];
  return c?.name ? resolveSpecies(gm, c.name, { form: c.form }) : null;
};
const fmt = (p, label, c, ours, id, ivs) =>
  `${label} ${p.name}${p.form ? ' (' + p.form + ')' : ''} as ${id} ${ivs.atk}/${ivs.def}/${ivs.hp}: Poke Genie rank ${c.rank}, stat prod ${c.statProd}, rank% ${c.rankPct}; ours rank ${ours?.rank}, stat prod ${ours?.pct}, rank% ${ours?.rankPct}`;

test('acceptance: IV rank, stat product and Rank % match every exact-IV row of the Poke Genie export', () => {
  const bad = [];
  let checked = 0;
  let purifiedRows = 0;
  for (const p of box) {
    if (!p.ivs) continue;
    for (const { key, label, league } of PG) {
      const c = p.pvp[key];
      const r = pgPick(p, key);
      if (!r || c.rank == null) continue;
      const id = baseSpeciesId(gm, r.speciesId);
      if (!gm.byId.has(id)) continue;
      const ivs = ratedIvs(p, label);
      if (ivs !== p.ivs) purifiedRows++;
      const ours = ivRank(id, gm.byId.get(id).baseStats, ivs, league);
      checked++;
      if (!ours || ours.rank !== c.rank || ours.pct !== c.statProd || ours.rankPct !== c.rankPct) bad.push(fmt(p, label, c, ours, id, ivs));
    }
  }
  // 278 Great + 304 Ultra + 150 Little rated exact-IV rows, none excluded.
  assert.equal(checked, 732);
  assert.equal(purifiedRows, 1);
  console.log(`acceptance: ${checked} league ratings checked, 0 excluded (${purifiedRows} rated as purified)`);
  assert.deepEqual(bad, []);
});

test('report: pick agreement with Poke Genie, cost agreement, ranking convention', () => {
  const lines = [];
  for (const { key, label, league } of PG) {
    if (league === 'lc') continue; // the app computes Great, Ultra and Master only
    let n = 0, same = 0, differ = 0;
    let costRows = 0, dustOk = 0, candyOk = 0, candyEvoOk = 0, zeroCost = 0;
    const differing = [];
    for (const p of box) {
      const c = p.pvp[key];
      const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
      const pg = pgPick(p, key);
      if (!r || !pg || !c.name) continue;
      n++;
      const ours = leaguesFor(p, r, ctx)[league];
      const ourBase = baseSpeciesId(gm, ours.pick.speciesId);
      const pgBase = baseSpeciesId(gm, pg.speciesId);
      if (sameMember(ourBase, pgBase)) same++;
      else { differ++; if (differing.length < 6) differing.push(`${p.name}->${ourBase} (PG ${pgBase})`); }
      // Cost: only where it is the same member, the level is exact and the copy is not already past the league's best level.
      if (sameMember(ourBase, pgBase) && p.levelMin === p.levelMax && p.ivs && ours.cost && c.dust != null) {
        costRows++;
        if (ours.cost.dust === c.dust) dustOk++;
        if (ours.cost.candy === c.candy) candyOk++;
        if (ours.cost.candy + ours.cost.evolveCandy === c.candy) candyEvoOk++;
        if (c.dust === 0) zeroCost++;
      }
    }
    lines.push(`${label}: pick agrees ${same}/${n} (${differ} differ); e.g. ${differing.join(', ')}`);
    lines.push(`${label}: cost rows ${costRows}: dust ${dustOk}, candy (power-up only) ${candyOk}, candy (power-up + evolution) ${candyEvoOk}`);
  }
  lines.push('Rank % = (N - rank) / (N - 1) over the N = 4096 spreads; rank = 1 + spreads with a strictly better stat product (ties share the best rank), products compared to a relative 1e-12; level cap 50; HP floored.');
  console.log(lines.join('\n'));
});

// ---- unit cases ----
const entry = (name, o = {}) => ({ name, form: '', ivs: { atk: 10, def: 12, hp: 14 }, level: 20, cp: 500, moves: [], shadow: false, purified: false, lucky: false, ...o });
const leaguesOf = (e) => leaguesFor(e, resolveSpecies(gm, e.name, { form: e.form, shadow: e.shadow }), ctx);

test('Eevee picks the eeveelution with the highest PvPoke score in each league', () => {
  const L = leaguesOf(entry('Eevee'));
  for (const league of ['gl', 'ul', 'ml']) {
    const best = ['vaporeon', 'jolteon', 'flareon', 'espeon', 'umbreon', 'leafeon', 'glaceon', 'sylveon']
      .map((id) => rankings.byLeague[league].get(id)).filter(Boolean).sort((a, b) => b.score - a.score)[0];
    assert.equal(L[league].pick.speciesId, best.speciesId, league);
    assert.equal(L[league].pick.self, false);
    assert.equal(L[league].strength.score, best.score);
  }
});

test('a shadow Dratini picks the shadow Dragonite ranking where it exists', () => {
  const L = leaguesOf(entry('Dratini', { shadow: true }));
  assert.ok(rankings.byLeague.ul.has('dragonite_shadow') && rankings.byLeague.ml.has('dragonite_shadow'));
  assert.equal(L.ul.pick.speciesId, 'dragonite_shadow');
  assert.equal(L.ml.pick.speciesId, 'dragonite_shadow');
  assert.equal(L.ml.pick.name, 'Dragonite (Shadow)');
  for (const league of ['gl', 'ul', 'ml']) assert.match(L[league].pick.speciesId, /_shadow$/);
  assert.match(leaguesOf(entry('Dratini')).ml.pick.speciesId, /^dragonite$/);
});

test("Charizard's family never yields a Mega", () => {
  const L = leaguesOf(entry('Charizard'));
  for (const league of ['gl', 'ul', 'ml']) assert.doesNotMatch(L[league].pick.speciesId, /mega/);
  const eevee = leaguesOf(entry('Charmander'));
  for (const league of ['gl', 'ul', 'ml']) assert.doesNotMatch(eevee[league].pick.speciesId, /mega/);
});

test('Master League has level 50 and no cap', () => {
  const L = leaguesOf(entry('Mewtwo', { ivs: { atk: 15, def: 15, hp: 15 }, level: 40 }));
  assert.equal(L.ml.iv.level, 50);
  assert.equal(L.ml.overCap, false);
  assert.equal(L.ml.cost.toLevel, 50);
  assert.ok(L.ml.cost.xl > 0);
});

test('a copy already above the league cap is over it and has no cost', () => {
  const e = entry('Dragonite', { ivs: { atk: 15, def: 15, hp: 15 }, level: 40 });
  const L = leaguesOf(e);
  assert.equal(L.gl.overCap, true);
  assert.equal(L.gl.cost, null);
  assert.equal(L.ul.overCap, true);
  assert.ok(L.ml.cost);
});

test('unknown IVs: no IV rank and no cost, but the pick and moves are still given', () => {
  const L = leaguesOf(entry('Mareep', { ivs: null }));
  for (const league of ['gl', 'ul', 'ml']) {
    assert.equal(L[league].iv, null);
    assert.equal(L[league].cost, null);
    assert.equal(L[league].overCap, false);
    assert.equal(L[league].pick.speciesId, 'ampharos');
    assert.ok(L[league].moves.fast && L[league].moves.charged.length >= 1);
  }
});

test('needs names the recommended moves the copy lacks, only for the Pokémon itself; no moves means no needs', () => {
  // Ampharos is its own pick in Ultra and Master.
  const L = leaguesOf(entry('Ampharos', { moves: ['Volt Switch', 'Tackle'] }));
  assert.equal(L.ul.pick.self, true);
  const rec = [L.ul.moves.fast, ...L.ul.moves.charged];
  assert.deepEqual(L.ul.needs, rec.filter((m) => !['Volt Switch', 'Tackle'].includes(m)));
  assert.ok(L.ul.needs.length >= 2);
  const has = leaguesOf(entry('Ampharos', { moves: [L.ul.moves.fast, ...L.ul.moves.charged] }));
  assert.deepEqual(has.ul.needs, []);
  for (const league of ['gl', 'ul', 'ml']) assert.equal(leaguesOf(entry('Ampharos'))[league].needs, null);
  // A Mareep is not the pick (evolving re-rolls moves): needs is null even with moves known.
  const mareep = leaguesOf(entry('Mareep', { moves: ['Tackle', 'Discharge'] }));
  for (const league of ['gl', 'ul', 'ml']) { assert.equal(mareep[league].pick.self, false); assert.equal(mareep[league].needs, null); }
});

test('a family with no ranked member falls back to its final evolution, without strength', () => {
  // Chewtle and Toxel have no PvPoke ranking in any league in the current snapshot (checked when this test was written).
  for (const l of ['gl', 'ul', 'ml']) for (const id of ['chewtle', 'drednaw', 'toxel', 'toxtricity_amped', 'toxtricity_low_key']) assert.ok(!rankings.byLeague[l].has(id), `${id} is now ranked in ${l}: pick another unranked family`);
  // (Chewtle's family is wholly unreleased, so all of it stays eligible and the final form is still Drednaw.)
  const L = leaguesOf(entry('Chewtle'));
  for (const l of ['gl', 'ul', 'ml']) {
    assert.equal(L[l].pick.speciesId, 'drednaw');
    assert.equal(L[l].strength, null);
    assert.equal(L[l].moves, null);
    assert.equal(L[l].needs, null);
    assert.ok(L[l].iv);
  }
  // Unreleased finals are skipped: Toxel's Toxtricity forms are not released, Girafarig's Farigiraf is not.
  for (const id of ['toxtricity_amped', 'toxtricity_low_key', 'farigiraf', 'basculegion_male']) assert.equal(gm.byId.get(id).released, false, `${id} is now released: pick another example`);
  assert.ok(!rankings.byLeague.ml.has('toxel') && !rankings.byLeague.ml.has('girafarig') && !rankings.byLeague.ml.has('farigiraf'), 'ranking data changed: pick another example');
  assert.equal(leaguesOf(entry('Toxel')).ml.pick.speciesId, 'toxel');
  assert.equal(leaguesOf(entry('Girafarig')).ml.pick.speciesId, 'girafarig');
  // A branching family takes the released final form with the higher CP at level 50 with 15/15/15 (no real family is unranked and branching, so a made-up one).
  const mon = (speciesId, atk, released = true, family = {}) => ({ speciesId, speciesName: speciesId, dex: 1, baseStats: { atk, def: 100, hp: 100 }, types: ['normal'], released, family: { id: 'F', ...family } });
  const fake = indexGamemaster({ timestamp: 0, moves: [], pokemon: [mon('a', 100, true, { evolutions: ['b', 'c', 'd'] }), mon('b', 150), mon('c', 200), mon('d', 300, false)] });
  const fakeCtx = { gm: fake, tiers: ctx.tiers, rankings: { byLeague: { gl: new Map(), ul: new Map(), ml: new Map() } } };
  assert.equal(leaguesFor(entry('A'), { speciesId: 'a' }, fakeCtx).ul.pick.speciesId, 'c');
});

test('analyseBox: resolved entries carry leagues, unresolved ones do not, and the result is plain JSON', () => {
  const out = analyseBox([entry('Mareep'), entry('Notamon')], ctx);
  assert.ok(out.pokemon[0].leagues.gl);
  assert.equal(out.pokemon[1].unresolved, true);
  assert.equal(out.pokemon[1].leagues, undefined);
  const json = JSON.parse(JSON.stringify(out.pokemon[0].leagues));
  assert.deepEqual(json, out.pokemon[0].leagues);
});

test('performance: a 2,000-entry box analyses in well under 5 seconds', () => {
  const big = [];
  while (big.length < 2000) for (const p of box) if (big.length < 2000) big.push(p);
  const t0 = performance.now();
  analyseBox(big, ctx);
  const s = (performance.now() - t0) / 1000;
  console.log(`analyseBox on ${big.length} entries (fixture rows repeated), cache cleared after each analysis: ${s.toFixed(2)} s`);
  assert.ok(s < 5, `${s.toFixed(2)} s`);
});

test('gender-locked evolutions: a female Kirlia never picks Gallade, a female Lechonk picks Oinkologne (Female), unknown sex says so', () => {
  const kirlia = (gender) => leaguesOf(entry('Kirlia', { gender }));
  for (const league of ['gl', 'ul', 'ml']) {
    assert.notEqual(kirlia('♀')[league].pick.speciesId, 'gallade', league);
    assert.equal(kirlia('♀')[league].pick.genderLocked, undefined);
    assert.equal(leaguesOf(entry('Lechonk', { gender: '♀' }))[league].pick.speciesId, 'oinkologne_female', league);
    assert.equal(leaguesOf(entry('Lechonk', { gender: '♂' }))[league].pick.speciesId, 'oinkologne', league);
  }
  // Fixture CSV line 90 (Index 89) is a female Lechonk that Poke Genie rates as Oinkologne (Female).
  const row = box.find((p) => p.index === 89); // CSV line 90
  assert.equal(row.name, 'Lechonk');
  assert.equal(row.gender, '♀');
  assert.equal(leaguesFor(row, resolveSpecies(gm, row.name, { form: row.form }), ctx).gl.pick.speciesId, 'oinkologne_female');
  // Unknown sex: Gallade stays a candidate and is labelled where it wins.
  const picked = ['gl', 'ul', 'ml'].map((l) => kirlia('')[l].pick).filter((p) => p.speciesId === 'gallade');
  assert.ok(picked.length > 0, 'Gallade should win at least one league for a Kirlia of unknown sex');
  for (const p of picked) assert.equal(p.genderLocked, 'male');
  // A male Snorunt never picks Froslass.
  for (const league of ['gl', 'ul', 'ml']) assert.notEqual(leaguesOf(entry('Snorunt', { gender: '♂' }))[league].pick.speciesId, 'froslass');
});

test('shadow costs round per power-up: the Grubbin row matches Poke Genie to the dust and candy; purified rounds per step too', () => {
  const g = box.find((p) => p.name === 'Grubbin' && p.shadow);
  assert.ok(g && g.level === 8);
  const L = leaguesFor(g, resolveSpecies(gm, g.name, { form: g.form, shadow: true }), ctx);
  for (const [key, league] of [['great', 'gl'], ['ultra', 'ul']]) {
    const c = g.pvp[key], cost = L[league].cost;
    assert.equal(cost.dust, c.dust, key);
    assert.equal(cost.candy + cost.evolveCandy, c.candy, key);
  }
  // Purified is 0.9 of each step, rounded HALF DOWN per step (Bulbapedia, Candy (GO); no fixture row has a purified cost, so this pins the rule, it does not verify it).
  let candy = 0, xl = 0;
  for (let lv = 30; lv < 45; lv += 0.5) { const s = step(lv); candy += Math.ceil(s.candy * 0.9 - 0.5); xl += Math.ceil(s.xl * 0.9 - 0.5); }
  const pure = powerUpCost(30, 45, { purified: true });
  assert.equal(pure.candy, candy);
  assert.equal(pure.xl, xl);
  assert.ok(pure.candy <= powerUpCost(30, 45).candy);
});

test('the rank table is keyed by base stats as well as id, so changed stats give different ranks', () => {
  const ivs = { atk: 10, def: 12, hp: 14 };
  const a = ivRank('fake_mon', { atk: 200, def: 150, hp: 180 }, ivs, 'ul');
  const b = ivRank('fake_mon', { atk: 120, def: 200, hp: 160 }, ivs, 'ul');
  assert.notDeepEqual([a.rank, a.level, a.cp], [b.rank, b.level, b.cp]);
  assert.equal(b.cp, cpAt({ atk: 120, def: 200, hp: 160 }, ivs, b.level));
  assert.deepEqual(ivRank('fake_mon', { atk: 200, def: 150, hp: 180 }, ivs, 'ul'), a);
});

test('Galarian Corsola evolves to Cursola: it is the Ultra pick (Galarian Corsola itself outscores it in Great), reached by the advisor, and costs 50 candy', () => {
  const e = entry('Corsola', { form: 'Galar' });
  const r = resolveSpecies(gm, e.name, { form: e.form });
  assert.equal(r.speciesId, 'corsola_galarian');
  const L = leaguesFor(e, r, ctx);
  // Galarian Corsola itself scores 91.5 in Great against Cursola's 60, and is unranked in Ultra and Master.
  assert.ok(rankings.byLeague.ul.has('cursola') && !rankings.byLeague.ul.has('corsola_galarian'), 'ranking data changed: pick another example');
  assert.equal(L.gl.pick.speciesId, 'corsola_galarian');
  assert.equal(L.ul.pick.speciesId, 'cursola');
  assert.equal(L.ul.cost.evolveCandy, 50);
  assert.ok(evolutionsOf(gm, 'corsola_galarian').includes('cursola'));
  assert.deepEqual(evolutionPath(gm, 'corsola_galarian', 'cursola'), [['corsola_galarian', 'cursola']]);
  assert.ok(evolutionsOf(gm, 'corsola').every((id) => id !== 'cursola'), 'plain Corsola still has no evolution');
});

test("PvPoke's none placeholder (Unown) is never a move or a need", () => {
  assert.ok(rankings.byLeague.gl.get('unown').moveset.includes('none'), 'Unown no longer has a placeholder move: pick another example');
  const have = leaguesOf(entry('Unown')).gl.moves;
  assert.ok(have.charged.length >= 1);
  for (const m of [have.fast, ...have.charged]) assert.doesNotMatch(m, /^none$/i);
  const L = leaguesOf(entry('Unown', { moves: [have.fast, ...have.charged] }));
  assert.deepEqual(L.gl.needs, []);
  assert.ok(![L.gl.moves.fast, ...L.gl.moves.charged].some((m) => /none/i.test(m)));
});

test('Master League: a level 51 Best Buddy copy is not over the cap and has nothing left to pay', () => {
  const L = leaguesOf(entry('Mewtwo', { ivs: { atk: 15, def: 15, hp: 15 }, level: 51 }));
  assert.equal(L.ml.overCap, false);
  assert.deepEqual(L.ml.cost, { dust: 0, candy: 0, xl: 0, evolveCandy: 0, toLevel: 50 });
  assert.equal(L.gl.overCap, true);
  const evo = leaguesOf(entry('Dragonair', { ivs: { atk: 15, def: 15, hp: 15 }, level: 51 }));
  assert.equal(evo.ml.cost.dust, 0);
  assert.ok(evo.ml.cost.evolveCandy > 0);
});

test('regional families: Cubone picks Marowak not Alolan Marowak; Galarian Meowth still reaches Perrserker', () => {
  assert.ok(evolutionsOf(gm, 'cubone').includes('marowak_alolan'), 'the game master no longer links Cubone to Alolan Marowak: drop this guard');
  for (const league of ['gl', 'ul', 'ml']) assert.notEqual(leaguesOf(entry('Cubone'))[league].pick.speciesId, 'marowak_alolan');
  assert.equal(leaguesOf(entry('Cubone')).ul.pick.speciesId, 'marowak');
  const meowth = leaguesOf(entry('Meowth', { form: 'Galar' }));
  assert.ok(['gl', 'ul', 'ml'].some((l) => meowth[l].pick.speciesId === 'perrserker'), JSON.stringify(['gl', 'ul', 'ml'].map((l) => meowth[l].pick.speciesId)));
  // A regional parent keeps its own regional children (Alolan Sandshrew -> Alolan Sandslash).
  assert.match(leaguesOf(entry('Sandshrew', { form: 'Alola' })).ul.pick.speciesId, /^sandslash_alolan$/);
});

test('evolution candy: Sinnoh Stone evolutions cost 100, Wurmple and baby lines 50 for the second stage, Gimmighoul none', () => {
  const candy = (id) => evolveCandy(gm, id, 'x');
  for (const id of ['yanma', 'tangela', 'aipom', 'misdreavus', 'gligar', 'snorunt']) assert.equal(candy(id), 100, id);
  for (const id of ['silcoon', 'cascoon', 'clefairy', 'jigglypuff']) assert.equal(candy(id), 50, id);
  assert.equal(candy('applin'), 200);
  assert.equal(candy('gimmighoul'), 0);
  assert.equal(candy('toxel'), 400);
});

test('rank ties are exact products, not near ones: Ivysaur GL 11/7/14 and 5/5/6 are different spreads', () => {
  const base = gm.byId.get('ivysaur').baseStats;
  const a = ivRank('ivysaur', base, { atk: 11, def: 7, hp: 14 }, 'gl');
  const b = ivRank('ivysaur', base, { atk: 5, def: 5, hp: 6 }, 'gl');
  assert.notEqual(a.product, b.product);
  assert.notEqual(a.rank, b.rank);
});

test('bad inputs are treated as unknown instead of throwing: odd IVs, odd levels, missing moves', () => {
  const ok = leaguesOf(entry('Mareep'));
  for (const ivs of [{ atk: 1.5, def: 3, hp: 4 }, { atk: 16, def: 3, hp: 4 }, { atk: -1, def: 3, hp: 4 }, { atk: 3, def: 3 }, { atk: '3', def: 3, hp: 4 }, { atk: NaN, def: 3, hp: 4 }]) {
    const L = leaguesOf(entry('Mareep', { ivs }));
    for (const league of ['gl', 'ul', 'ml']) {
      assert.equal(L[league].iv, null, JSON.stringify(ivs));
      assert.equal(L[league].cost, null);
      assert.equal(L[league].pick.speciesId, ok[league].pick.speciesId);
    }
  }
  for (const level of [0.5, 52, 20.3, NaN, '20', undefined]) {
    const L = leaguesOf(entry('Mareep', { level }));
    for (const league of ['gl', 'ul', 'ml']) { assert.ok(L[league].iv); assert.equal(L[league].cost, null); assert.equal(L[league].overCap, false); }
  }
  const e = entry('Mareep');
  delete e.moves;
  const L = leaguesOf(e);
  for (const league of ['gl', 'ul', 'ml']) assert.equal(L[league].needs, null);
  assert.doesNotThrow(() => analyseBox([entry('Mareep', { ivs: { atk: 99, def: 1, hp: 1 } }), e], ctx));
});

test('the Mega check works on the raw id: a Mega the family walk reaches is never a pick', () => {
  const mon = (speciesId, atk, family = {}) => ({ speciesId, speciesName: speciesId, dex: 1, baseStats: { atk, def: 100, hp: 100 }, types: ['normal'], released: true, family: { id: 'F', ...family } });
  // baseSpeciesId would turn b_mega into b, which is allowed; the raw id must be what is tested.
  const fake = indexGamemaster({ timestamp: 0, moves: [], pokemon: [mon('a', 100, { evolutions: ['b_mega'] }), mon('b', 100), mon('b_mega', 300)] });
  const fakeCtx = { gm: fake, tiers: ctx.tiers, rankings: { byLeague: { gl: new Map(), ul: new Map(), ml: new Map() } } };
  assert.equal(leaguesFor(entry('A'), { speciesId: 'a' }, fakeCtx).ul.pick.speciesId, 'a');
});

test('rank tables built by walking from the neighbouring spread equal a fresh bisection per spread', () => {
  let seed = 99; const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32;
  for (const id of ['mewtwo', 'azumarill', 'stunfisk_galarian', 'tinkaton', 'blissey', 'shuckle']) {
    const base = gm.byId.get(id).baseStats;
    for (const league of ['gl', 'ul', 'ml', 'lc']) {
      const products = [];
      for (let i = 0; i < 4096; i++) { const b = bestUnderCap(base, { atk: i >> 8, def: (i >> 4) & 15, hp: i & 15 }, CAPS[league]); if (b) products.push(b.product); }
      products.sort((x, y) => y - x);
      for (let j = 0; j < 150; j++) {
        const ivs = { atk: Math.floor(rnd() * 16), def: Math.floor(rnd() * 16), hp: Math.floor(rnd() * 16) };
        const r = ivRank(`walk_${id}`, base, ivs, league);
        const p = bestUnderCap(base, ivs, CAPS[league])?.product;
        if (p === undefined) { assert.equal(r, null); continue; }
        // brute force: 1 + the spreads whose product is strictly better by more than the tie tolerance
        const rank = 1 + products.filter((x) => x > p * (1 + 1e-12)).length;
        assert.equal(r.rank, rank, `${id} ${league} ${JSON.stringify(ivs)}`);
        assert.equal(r.of, products.length);
      }
    }
  }
});

test('cold cache, diverse box: 2,000 Pokemon of ~600 species analyse quickly and leave no rank tables behind', () => {
  // The fixture repeats ~150 species; a real account has many more. Every released first-stage species, random IVs (a fixed seed).
  const firsts = [...gm.byId.values()].filter((p) => p.released !== false && !p.family?.parent && !/_(shadow|mega|primal)/.test(p.speciesId));
  let seed = 12345; const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32;
  const diverse = [];
  for (let i = 0; i < 2000; i++) {
    diverse.push(entry(firsts[i % firsts.length].speciesName, { index: i + 1, ivs: { atk: Math.floor(rnd() * 16), def: Math.floor(rnd() * 16), hp: Math.floor(rnd() * 16) }, level: 1 + Math.floor(rnd() * 40) }));
  }
  clearRankCache();
  const t0 = performance.now();
  const out = analyseBox(diverse, ctx);
  const s = (performance.now() - t0) / 1000;
  console.log(`analyseBox cold on ${diverse.length} diverse entries (${new Set(out.pokemon.map((e) => e.resolved?.speciesId)).size} species): ${s.toFixed(2)} s`);
  assert.equal(rankCacheSize(), 0);
  assert.ok(out.pokemon.every((e, i) => e.p === diverse[i]), 'pokemon[] keeps the box order');
  assert.ok(out.pokemon.every((e) => e.unresolved || e.leagues.gl), 'every resolved entry has leagues');
  // About 0.4 s here; the phone runs without a JIT, which is ~5x slower, so this is a guard against a return to ~10 s, not a measurement.
  assert.ok(s < 5, `${s.toFixed(2)} s`);
});

test('purified costs round half down per power-up, shadow costs round up (manager fold, Bulbapedia Candy (GO))', () => {
  // 31 -> 33 is four power-ups of 6,000 dust and 6 candy each: purified 0.9x gives 5,400 dust and 5.4 -> 5 candy per step.
  assert.deepEqual(powerUpCost(31, 33, { purified: true }), { dust: 21600, candy: 20, xl: 0, steps: 4 });
  assert.equal(powerUpCost(31, 33, { shadow: true }).candy, 32);   // 7.2 -> 8 per step
  assert.equal(powerUpCost(31, 33).candy, 24);
});
