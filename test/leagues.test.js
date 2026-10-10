import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadContext } from '../src/node/load.js';
import { resolveSpecies, baseSpeciesId } from '../src/gamemaster.js';
import { analyseBox } from '../src/advise.js';
import { leaguesFor } from '../src/leagues.js';
import { ivRank } from '../src/pvp-rank.js';

const ctx = loadContext();
const { gm, rankings } = ctx;
const box = importPokeGenie(readFileSync(new URL('../fixtures/greg-2026-09-25.pokegenie.csv', import.meta.url), 'utf8'));

// Poke Genie's three league columns: Great, Ultra and Little Cup (CP 500; the app never shows Little Cup).
const PG = [
  { key: 'great', label: 'Great', league: 'gl' },
  { key: 'ultra', label: 'Ultra', league: 'ul' },
  { key: 'little', label: 'Little', league: 'lc' },
];
// Rows where our arithmetic is known not to reproduce Poke Genie, each named with the reason.
const EXCLUDED = {
  // Index 'Tyrunt 4/15/14, Ultra': Poke Genie rates it as Tyrantrum 98.70% / rank 106; with the game master's Tyrantrum stats it is 97.20% / rank 930,
  // and no single plausible base-stat tuple reproduces both numbers, so Poke Genie is using Tyrantrum data the game master does not have.
  'ultra|Tyrunt|4/15/14': 'Poke Genie rates Tyrantrum with base stats that differ from the game master',
};
// Corsola (Galar) is rated by Poke Genie as Cursola, but the game master has no family on corsola_galarian, so our family walk cannot reach it.
const KNOWN_PICK_EXCEPTIONS = new Set(['corsola_galarian']);

const sameMember = (a, b) => a === b || [a, b].every((x) => x === 'oinkologne' || x === 'oinkologne_female');
const pgPick = (p, key) => {
  const c = p.pvp[key];
  return c?.name ? resolveSpecies(gm, c.name, { form: c.form }) : null;
};
const fmt = (p, label, c, ours, id) =>
  `${label} ${p.name}${p.form ? ' (' + p.form + ')' : ''} as ${id} ${p.ivs.atk}/${p.ivs.def}/${p.ivs.hp}: Poke Genie rank ${c.rank}, stat prod ${c.statProd}, rank% ${c.rankPct}; ours rank ${ours?.rank}, stat prod ${ours?.pct}, rank% ${ours?.rankPct}`;

test('acceptance: IV rank, stat product and Rank % match every exact-IV row of the Poke Genie export', () => {
  const bad = [];
  let checked = 0;
  const excluded = [];
  for (const p of box) {
    if (!p.ivs) continue;
    for (const { key, label, league } of PG) {
      const c = p.pvp[key];
      const r = pgPick(p, key);
      if (!r || c.rank == null) continue;
      const id = baseSpeciesId(gm, r.speciesId);
      if (!gm.byId.has(id)) continue;
      const exclusion = EXCLUDED[`${key}|${p.name}|${p.ivs.atk}/${p.ivs.def}/${p.ivs.hp}`];
      if (exclusion) { excluded.push(`${label} ${p.name}: ${exclusion}`); continue; }
      const ours = ivRank(id, gm.byId.get(id).baseStats, p.ivs, league);
      checked++;
      if (!ours || ours.rank !== c.rank || Math.abs(ours.pct - c.statProd) > 0.0101 || Math.abs(ours.rankPct - c.rankPct) > 0.0101) bad.push(fmt(p, label, c, ours, id));
    }
  }
  assert.ok(checked > 700, `only ${checked} league ratings checked`);
  console.log(`acceptance: ${checked} league ratings checked, ${excluded.length} excluded (${excluded.join('; ')})`);
  assert.deepEqual(bad, []);
});

test('report: pick agreement with Poke Genie, cost agreement, ranking convention', () => {
  const lines = [];
  for (const { key, label, league } of PG) {
    if (league === 'lc') continue; // the app computes Great, Ultra and Master only
    let n = 0, same = 0, differ = 0, exception = 0;
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
      else if (KNOWN_PICK_EXCEPTIONS.has(baseSpeciesId(gm, r.speciesId))) exception++;
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
    lines.push(`${label}: pick agrees ${same}/${n} (${differ} differ, ${exception} known exception); e.g. ${differing.join(', ')}`);
    lines.push(`${label}: cost rows ${costRows}: dust ${dustOk}, candy (power-up only) ${candyOk}, candy (power-up + evolution) ${candyEvoOk}`);
  }
  lines.push('Rank % = (N - rank) / (N - 1) over the N = 4096 spreads; rank = 1 + spreads with a strictly better stat product (ties share the best rank), products compared to a relative 1e-9; level cap 50; HP floored.');
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

test('needs names the recommended moves the copy lacks; no moves means no needs', () => {
  const L = leaguesOf(entry('Mareep', { moves: ['Tackle', 'Discharge'] }));
  const rec = [L.ul.moves.fast, ...L.ul.moves.charged];
  assert.deepEqual(L.ul.needs, rec.filter((m) => !['Tackle', 'Discharge'].includes(m)));
  assert.ok(L.ul.needs.length >= 2);
  const has = leaguesOf(entry('Mareep', { moves: [L.ul.moves.fast, ...L.ul.moves.charged] }));
  assert.deepEqual(has.ul.needs, []);
  const none = leaguesOf(entry('Mareep'));
  for (const league of ['gl', 'ul', 'ml']) assert.equal(none[league].needs, null);
});

test('a family with no ranked member falls back to its final evolution, without strength', () => {
  // Chewtle and Toxel have no PvPoke ranking in any league in the current snapshot (checked when this test was written).
  for (const l of ['gl', 'ul', 'ml']) for (const id of ['chewtle', 'drednaw', 'toxel', 'toxtricity_amped', 'toxtricity_low_key']) assert.ok(!rankings.byLeague[l].has(id), `${id} is now ranked in ${l}: pick another unranked family`);
  const L = leaguesOf(entry('Chewtle'));
  for (const l of ['gl', 'ul', 'ml']) {
    assert.equal(L[l].pick.speciesId, 'drednaw');
    assert.equal(L[l].strength, null);
    assert.equal(L[l].moves, null);
    assert.equal(L[l].needs, null);
    assert.ok(L[l].iv);
  }
  // A branching family takes the final form with the higher CP at level 50 with 15/15/15.
  const toxel = leaguesOf(entry('Toxel')).ml.pick.speciesId;
  assert.match(toxel, /^toxtricity_(amped|low_key)$/);
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
  console.log(`analyseBox on ${big.length} entries (fixture rows repeated), caches warm from the tests above: ${s.toFixed(2)} s`);
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
