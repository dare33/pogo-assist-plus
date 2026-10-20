import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseCsv } from '../src/csv.js';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadContext } from '../src/node/load.js';
import { resolveSpecies, baseSpeciesId, evolutionsOf, indexGamemaster } from '../src/gamemaster.js';
import { evolutionPath, evolveCandy } from '../src/evolve.js';
import { analyseBox } from '../src/advise.js';
import { leaguesFor, pokeGeniePick, chooseMember, CLOSE_SCORE } from '../src/leagues.js';
import { ivRank, bestUnderCap, CAPS, rankCacheSize, clearRankCache } from '../src/pvp-rank.js';
import { powerUpCost, step } from '../src/cost.js';
import { cpAt } from '../src/cpm.js';

const ctx = loadContext();
// leaguesFor returns options plus indexes for the shown pick and the experimental one. Most tests below read the SHOWN pick in the
// older flat form ({ pick: { speciesId, name, self, genderLocked? }, strength, moves, needs, iv, overCap, cost }); `raw` is the real thing.
const flatten = (L) => Object.fromEntries(Object.entries(L).map(([k, l]) => {
  const o = l.options[l.pick];
  const pick = { speciesId: o.speciesId, name: o.name, self: o.self, ...(o.genderLocked ? { genderLocked: o.genderLocked } : {}) };
  return [k, { pick, strength: o.strength, moves: o.moves, needs: o.needs, iv: o.iv, overCap: o.overCap, cost: o.cost, raw: l }];
}));
const lf = (e, r, c) => flatten(leaguesFor(e, r, c));
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

// Regression pins (not evidence it generalises: the fixture is the data it was fitted on) for the emulation of Poke Genie's pick, measured WITHOUT reading the export's pick: currently 271/280 Great and 300/306 Ultra rows (the 270/278 and 298/304 counted earlier were the
// cost-check subsets, a different row count; the printed report is the reference). A drop below these means the emulation, the IV rank or the family walk changed.
const EMULATION_FLOOR = { gl: 271, ul: 300 };

test('report: pick agreement with Poke Genie (emulated without its pick, and the experimental rule), cost agreement, ranking convention', () => {
  const lines = [];
  for (const { key, label, league } of PG) {
    if (league === 'lc') continue; // the app computes Great, Ultra and Master only
    let n = 0, emulated = 0, experimental = 0, shownSame = 0;
    let costRows = 0, dustOk = 0, candyOk = 0, candyEvoOk = 0, zeroCost = 0;
    const emulatedMiss = [], experimentalMiss = [];
    for (const p of box) {
      const c = p.pvp[key];
      const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
      const pg = pgPick(p, key);
      if (!r || !pg || !c.name) continue;
      n++;
      const pgBase = baseSpeciesId(gm, pg.speciesId);
      const baseOf = (o) => baseSpeciesId(gm, o.speciesId);
      // (a) the emulation: the same entry with Poke Genie's columns removed, so it cannot read the answer.
      const blind = leaguesFor({ ...p, pvp: undefined }, r, ctx)[league];
      assert.ok(p.ivs ? blind.source === 'emulated' : ['ranked', 'fallback'].includes(blind.source));
      if (sameMember(baseOf(blind.options[blind.pick]), pgBase)) emulated++;
      else if (emulatedMiss.length < 6) emulatedMiss.push(`${p.name}->${baseOf(blind.options[blind.pick])} (PG ${pgBase})`);
      // (b) the experimental CLOSE_SCORE rule (also computed blind: it never reads the columns).
      if (sameMember(baseOf(blind.options[blind.experimental]), pgBase)) experimental++;
      else if (experimentalMiss.length < 6) experimentalMiss.push(`${p.name}->${baseOf(blind.options[blind.experimental])} (PG ${pgBase})`);
      // With the columns the shown pick is Poke Genie's own wherever it is in the family.
      const full = leaguesFor(p, r, ctx)[league];
      const shown = full.options[full.pick];
      if (sameMember(baseOf(shown), pgBase)) shownSame++;
      // Cost: only where it is the same member, the level is exact and the copy is not already past the league's best level.
      if (sameMember(baseOf(shown), pgBase) && p.levelMin === p.levelMax && p.ivs && shown.cost && c.dust != null) {
        costRows++;
        if (shown.cost.dust === c.dust) dustOk++;
        if (shown.cost.candy === c.candy) candyOk++;
        if (shown.cost.candy + shown.cost.evolveCandy === c.candy) candyEvoOk++;
        if (c.dust === 0) zeroCost++;
      }
    }
    lines.push(`${label}: shown pick with the export's columns agrees ${shownSame}/${n}`);
    lines.push(`${label}: emulation WITHOUT the export's pick agrees ${emulated}/${n}; e.g. ${emulatedMiss.join(', ')}`);
    lines.push(`${label}: experimental CLOSE_SCORE rule agrees ${experimental}/${n}; e.g. ${experimentalMiss.join(', ')}`);
    lines.push(`${label}: cost rows ${costRows}: dust ${dustOk}, candy (power-up only) ${candyOk}, candy (power-up + evolution) ${candyEvoOk}`);
    if (EMULATION_FLOOR[league]) assert.ok(emulated >= EMULATION_FLOOR[league], `${label} emulation ${emulated}/${n} is below ${EMULATION_FLOOR[league]}`);
    // The shown pick differs from Poke Genie's only when its pick is not a member of the family (the Oinkologne twins, an unreleased form).
    assert.ok(shownSame >= n - 3, `${label} shown ${shownSame}/${n}`);
  }
  lines.push('Rank % = (N - rank) / (N - 1) over the N = 4096 spreads; rank = 1 + spreads with a strictly better stat product (ties share the best rank), products compared to a relative 1e-12; level cap 50; HP floored.');
  console.log(lines.join('\n'));
});

// ---- unit cases ----
const entry = (name, o = {}) => ({ name, form: '', ivs: { atk: 10, def: 12, hp: 14 }, level: 20, cp: 500, moves: [], shadow: false, purified: false, lucky: false, ...o });
const leaguesOf = (e) => lf(e, resolveSpecies(gm, e.name, { form: e.form, shadow: e.shadow }), ctx);

test('Eevee with unknown IVs picks the eeveelution with the highest PvPoke score in each league', () => {
  // Changed with the CLOSE_SCORE rule: with IVs, a close second (Umbreon 85.5 against Sylveon 85.9 in Ultra) can win on the spread,
  // so the plain "highest score" reading now holds only where the IVs are unknown.
  const L = leaguesOf(entry('Eevee', { ivs: null }));
  for (const league of ['gl', 'ul', 'ml']) {
    const best = ['vaporeon', 'jolteon', 'flareon', 'espeon', 'umbreon', 'leafeon', 'glaceon', 'sylveon']
      .map((id) => rankings.byLeague[league].get(id)).filter(Boolean).sort((a, b) => b.score - a.score)[0];
    assert.equal(L[league].pick.speciesId, best.speciesId, league);
    assert.equal(L[league].pick.self, false);
    assert.equal(L[league].strength.score, best.score);
  }
});

const rawOf = (e) => leaguesFor(e, resolveSpecies(gm, e.name, { form: e.form, shadow: e.shadow }), ctx);
const idsOf = (l) => l.options.map((o) => o.speciesId);
const shownOf = (l) => l.options[l.pick];
const expOf = (l) => l.options[l.experimental];

test('the data shape: options plus two indexes and a source; no per-option pick or ours flag', () => {
  const L = rawOf(entry('Eevee', { ivs: { atk: 6, def: 7, hp: 12 }, moves: ['Quick Attack'] }));
  assert.deepEqual(Object.keys(L), ['gl', 'ul', 'ml']);
  for (const league of ['gl', 'ul', 'ml']) {
    const l = L[league];
    assert.deepEqual(Object.keys(l), ['options', 'pick', 'experimental', 'source']);
    assert.ok(Number.isInteger(l.pick) && l.pick >= 0 && l.pick < l.options.length);
    assert.ok(Number.isInteger(l.experimental) && l.experimental < l.options.length);
    assert.ok(['export', 'emulated', 'ranked', 'fallback'].includes(l.source));
    for (const o of l.options) {
      const keys = Object.keys(o);
      for (const k of ['speciesId', 'name', 'self', 'strength', 'moves', 'needs', 'iv', 'overCap', 'cost']) assert.ok(keys.includes(k), k);
      assert.ok(!('ours' in o) && !('pick' in o));
      assert.equal(o.self, o.speciesId === 'eevee');
      if (o.strength) assert.equal(o.strength.of, rankings.byLeague[league].size); else assert.equal(o.moves, null);
      if (!o.self) assert.equal(o.needs, null);
    }
    // Ranked members first, strongest first; then the unranked.
    const scores = l.options.map((o) => o.strength?.score ?? -1);
    assert.deepEqual(scores, [...scores].sort((a, b) => b - a), league);
  }
  // Every Eevee evolution is listed whether PvPoke ranks it or not, in every league.
  for (const league of ['gl', 'ul', 'ml']) {
    assert.deepEqual(idsOf(L[league]).sort(), ['eevee', 'espeon', 'flareon', 'glaceon', 'jolteon', 'leafeon', 'sylveon', 'umbreon', 'vaporeon']);
  }
});

test('the shown pick copies Poke Genie: its own pick from the export when it is in the family, else the stat-product emulation', () => {
  // Poke Genie's export says Flareon for this Eevee in Great League; the shown pick is Flareon although PvPoke ranks others far above it.
  const withColumns = entry('Eevee', { ivs: { atk: 6, def: 7, hp: 12 }, pvp: { great: { name: 'Flareon', form: '' }, ultra: { name: 'Vaporeon', form: 'Normal' } } });
  const L = rawOf(withColumns);
  assert.equal(shownOf(L.gl).speciesId, 'flareon');
  assert.equal(L.gl.source, 'export');
  assert.equal(shownOf(L.ul).speciesId, 'vaporeon');
  assert.equal(L.ml.source, 'ranked'); // Poke Genie has no Master League column: the PvPoke score decides, not the emulation
  // A pick that is not in the family (or no pick: an app scan has empty columns) is emulated.
  for (const pvp of [{ great: { name: 'Pikachu', form: '' } }, { great: { name: '', form: '' } }, undefined]) {
    assert.equal(rawOf(entry('Eevee', { ivs: { atk: 6, def: 7, hp: 12 }, pvp })).gl.source, 'emulated');
  }
  // The emulation: the best stat product % among the members this copy is not already too strong for, ranked ones first.
  const bare = rawOf(entry('Eevee', { ivs: { atk: 6, def: 7, hp: 12 }, level: 10 })).gl;
  const fitting = bare.options.filter((o) => !o.overCap && o.strength);
  assert.equal(shownOf(bare).speciesId, fitting.reduce((a, b) => (b.iv.pct > a.iv.pct ? b : a)).speciesId);
  assert.equal(bare.source, 'emulated');
});

test('pokeGeniePick: fitting ranked members first, then fitting, then ranked, then all; ties to the later evolution; unknown IVs by score', () => {
  const m = (id, pct, o = {}) => ({ id, depth: 0, score: null, iv: pct == null ? null : { pct }, overCap: false, ...o });
  // A fitting ranked member beats a better-spread fitting unranked one, and any over-cap one.
  assert.equal(pokeGeniePick([m('a', 90, { score: 50 }), m('b', 99), m('c', 99, { score: 40, overCap: true })]).id, 'a');
  // No fitting ranked member: the best fitting one.
  assert.equal(pokeGeniePick([m('a', 90, { overCap: false }), m('b', 99, { score: 40, overCap: true })]).id, 'a');
  // Nothing fits: ranked first, then everything.
  assert.equal(pokeGeniePick([m('a', 99, { overCap: true }), m('b', 90, { score: 1, overCap: true })]).id, 'b');
  assert.equal(pokeGeniePick([m('a', 99, { overCap: true }), m('b', 90, { overCap: true })]).id, 'a');
  // Exact tie: the later evolution.
  assert.equal(pokeGeniePick([m('a', 100, { depth: 0 }), m('b', 100, { depth: 2 }), m('c', 100, { depth: 1 })]).id, 'b');
  // Members whose IVs cannot be rated are never picked while another can.
  assert.equal(pokeGeniePick([m('a', null, { score: 99 }), m('b', 10)]).id, 'b');
  // Unknown IVs: the highest score, the later evolution on a tie; nothing ranked: null.
  assert.equal(pokeGeniePick([m('a', null, { score: 70 }), m('b', null, { score: 80 })]).id, 'b');
  assert.equal(pokeGeniePick([m('a', null, { score: 80 }), m('b', null, { score: 80, depth: 1 })]).id, 'b');
  assert.equal(pokeGeniePick([m('a', null), m('b', null)]), null);
});

test('CLOSE_SCORE is 3 points by default, and the Magnemite / Eevee cases it was chosen for hold in the current rankings', () => {
  assert.equal(CLOSE_SCORE, 3);
  assert.deepEqual(['magnezone', 'magneton'].map((id) => rankings.byLeague.gl.get(id).score), [78.4, 76.4]);
  assert.deepEqual(['sylveon', 'flareon'].map((id) => rankings.byLeague.ul.get(id).score), [85.9, 66.8]);
});

test('chooseMember (experimental): inclusive boundary, unknown spreads take the score, ties, over-cap members left out, nothing ranked is null', () => {
  const c = (id, score, rankPct, depth = 0, overCap = false) => ({ id, score, rankPct, depth, overCap });
  assert.equal(chooseMember([]), null);
  assert.equal(chooseMember([c('a', 80, 10), c('b', 77, 90)]).id, 'b');
  assert.equal(chooseMember([c('a', 80, 10), c('b', 76.9, 90)]).id, 'a');
  assert.equal(chooseMember([c('a', 78.4, 10), c('b', 75.4, 90)]).id, 'b'); // 78.4 - 75.4 is 3.0000000000000004 in floats
  assert.equal(chooseMember([c('a', 80, null), c('b', 79, null)]).id, 'a');
  assert.equal(chooseMember([c('a', 80, null, 0), c('b', 80, null, 1)]).id, 'b');
  assert.equal(chooseMember([c('a', 80, 50), c('b', 79, 50)]).id, 'a');
  assert.equal(chooseMember([c('a', 80, 50, 0), c('b', 80, 50, 1)]).id, 'b');
  assert.equal(chooseMember([c('a', 80, null), c('b', 79, 5)]).id, 'b');
  assert.equal(chooseMember([c('a', 80, 10), c('b', 70, 90)], 10).id, 'b');
  assert.equal(chooseMember([c('a', 80, 10), c('b', 70, 90)], 0).id, 'a');
  // Over-cap members are left out entirely, the best score included: the 90 is gone, so 70 is the best and 69 is close to it.
  assert.equal(chooseMember([c('top', 90, 99, 0, true), c('x', 70, 10), c('y', 69, 80)]).id, 'y');
  // ...unless every member is over the cap.
  assert.equal(chooseMember([c('a', 90, 10, 0, true), c('b', 89, 80, 0, true)]).id, 'b');
});

test('experimental pick: Magnemite GL takes the better spread of two close members; an over-cap member never wins', () => {
  // 2/5/11 at level 20: Magnezone (78.4) is already past the Great League cap here, so the choice is Magneton (76.4) / Magnemite (75.5) on spread.
  const gl = rawOf(entry('Magnemite', { ivs: { atk: 2, def: 5, hp: 11 } })).gl;
  assert.equal(expOf(gl).speciesId, 'magneton');
  // At level 5 nothing is over the cap and the three are close: the best Rank % wins, which is Magneton (68.45 against 60.81 and 41.51).
  const low = rawOf(entry('Magnemite', { ivs: { atk: 2, def: 5, hp: 11 }, level: 5 })).gl;
  assert.deepEqual(low.options.map((o) => o.overCap), [false, false, false]);
  assert.equal(expOf(low).speciesId, 'magneton');
  assert.equal(low.options[0].iv.rankPct, 60.81);
  // Unknown IVs: the highest score.
  // Unknown IVs: the highest score among members the copy still fits. Magnezone is past the cap at level 20 even at 0/0/0, so Magneton; with the level unknown nothing is over the cap.
  assert.equal(expOf(rawOf(entry('Magnemite', { ivs: null })).gl).speciesId, 'magneton');
  assert.equal(expOf(rawOf(entry('Magnemite', { ivs: null, level: null })).gl).speciesId, 'magnezone');
  // Lillipup at a level past Stoutland's Great League best level: it is not the experimental pick there either.
  const lillipup = rawOf(entry('Lillipup', { level: 30, ivs: { atk: 13, def: 13, hp: 11 } })).gl;
  assert.equal(lillipup.options.find((o) => o.speciesId === 'stoutland').overCap, true);
  assert.equal(expOf(lillipup).overCap, false);
});

test('Eevee UL experimental: a far weaker member (Flareon 66.8 against Sylveon 85.9) never wins on spread', () => {
  const l = rawOf(entry('Eevee', { ivs: { atk: 6, def: 7, hp: 12 }, level: 10 })).ul;
  const flareon = l.options.find((o) => o.speciesId === 'flareon'), sylveon = l.options.find((o) => o.speciesId === 'sylveon');
  assert.ok(flareon.iv.rankPct > sylveon.iv.rankPct, 'this copy suits Flareon better');
  assert.notEqual(expOf(l).speciesId, 'flareon');
});

test('unknown IVs: options carry no IV rating or cost; the shown pick is the top PvPoke score and the source says so', () => {
  const L = rawOf(entry('Eevee', { ivs: null, level: null }));
  for (const league of ['gl', 'ul', 'ml']) {
    for (const o of L[league].options) { assert.equal(o.iv, null); assert.equal(o.cost, null); assert.equal(o.overCap, false); }
    assert.equal(L[league].source, 'ranked');
    assert.equal(L[league].pick, 0);
    assert.equal(L[league].experimental, 0);
  }
});

test('the family walk includes form changes: Zygarde 10% reaches Complete, Hero Zamazenta reaches Crowned', () => {
  const z = rawOf(entry('Zygarde', { form: '10%' }));
  const zamazenta = rawOf(entry('Zamazenta', { form: 'Hero' }));
  for (const league of ['gl', 'ul', 'ml']) {
    assert.ok(idsOf(z[league]).includes('zygarde_complete'), league);
    assert.ok(idsOf(zamazenta[league]).includes('zamazenta_crowned_shield'), league);
  }
  assert.ok(z.ml.options.find((o) => o.speciesId === 'zygarde_complete').cost.evolveCandy === 0, 'a form change costs no candy');
});

test('options for a Shadow use the shadow ranking where PvPoke has one; no Mega or Primal; gender locks and unreleased members respected', () => {
  const L = rawOf(entry('Dratini', { shadow: true }));
  for (const league of ['gl', 'ul', 'ml']) {
    for (const o of L[league].options) {
      assert.doesNotMatch(o.speciesId, /mega|primal/);
      const base = o.speciesId.replace(/_shadow$/, '');
      if (o.strength) assert.equal(o.speciesId, rankings.byLeague[league].has(`${base}_shadow`) ? `${base}_shadow` : base);
    }
  }
  assert.ok(L.ml.options.some((o) => o.speciesId === 'dragonite_shadow' && o.name === 'Dragonite (Shadow)'));
  for (const league of ['gl', 'ul', 'ml']) {
    assert.ok(!rawOf(entry('Kirlia', { gender: '♀' }))[league].options.some((o) => o.speciesId === 'gallade'));
    const g = rawOf(entry('Kirlia', { gender: '' }))[league].options.find((o) => o.speciesId === 'gallade');
    assert.equal(g.genderLocked, 'male');
    assert.ok(!idsOf(rawOf(entry('Girafarig'))[league]).includes('farigiraf'), 'unreleased');
  }
});

test('across the whole fixture box, every league is well-formed and the pick is a listed member', () => {
  let checked = 0;
  for (const p of box) {
    const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
    if (!r) continue;
    const L = leaguesFor(p, r, ctx);
    for (const league of ['gl', 'ul', 'ml']) {
      const l = L[league];
      assert.ok(l.options[l.pick] && l.options[l.experimental], `${p.name} ${league}`);
      assert.equal(new Set(idsOf(l)).size, l.options.length, 'no member twice');
      const exp = expOf(l);
      if (exp.strength) {
        const scores = l.options.filter((o) => o.strength && !o.overCap).map((o) => o.strength.score);
        if (scores.length && !exp.overCap) assert.ok(exp.strength.score >= Math.max(...scores) - CLOSE_SCORE - 1e-9, `${p.name} ${league}`);
      }
      checked++;
    }
  }
  assert.ok(checked > 600);
});

test('payload: a box of branching families (Eevees, Zygardes, Kirlias, Poliwags, Tyrogues) stays within an honest size budget', () => {
  const branching = [];
  for (let i = 0; i < 2000; i++) branching.push(entry(['Eevee', 'Zygarde', 'Kirlia', 'Poliwag', 'Tyrogue'][i % 5], { form: i % 5 === 1 ? '10%' : '', index: i + 1, ivs: { atk: i % 16, def: (i >> 2) % 16, hp: (i >> 4) % 16 }, level: 1 + (i % 40) }));
  const t0 = performance.now();
  const out = analyseBox(branching, ctx);
  const s = (performance.now() - t0) / 1000;
  const bytes = JSON.stringify(out.pokemon.map((e) => e.leagues)).length;
  console.log(`branching box: 2,000 entries, leagues JSON ${(bytes / 1e6).toFixed(2)} MB (${Math.round(bytes / 2000)} B each), analysed in ${s.toFixed(2)} s`);
  assert.ok(bytes < 9e6, `${(bytes / 1e6).toFixed(2)} MB`);
  assert.ok(s < 5, `${s.toFixed(2)} s`);
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

test('a family with no ranked member and unknown IVs falls back to its final evolution, without strength', () => {
  // (Changed with the Poke Genie-compatible pick: with IVs known the shown pick is the stat-product emulation, which can pick any stage.)
  // Chewtle and Toxel have no PvPoke ranking in any league in the current snapshot (checked when this test was written).
  for (const l of ['gl', 'ul', 'ml']) for (const id of ['chewtle', 'drednaw']) assert.ok(!rankings.byLeague[l].has(id), `${id} is now ranked in ${l}: pick another unranked family`);
  // (Chewtle's family is wholly unreleased, so all of it stays eligible and the final form is still Drednaw.)
  const L = leaguesOf(entry('Chewtle', { ivs: null }));
  for (const l of ['gl', 'ul', 'ml']) {
    assert.equal(L[l].pick.speciesId, 'drednaw');
    assert.equal(L[l].strength, null);
    assert.equal(L[l].moves, null);
    assert.equal(L[l].needs, null);
    assert.equal(L[l].raw.source, 'fallback');
    assert.equal(L[l].raw.options.length, 2); // both stages are listed, neither ranked
  }
  // Unreleased finals are skipped: Girafarig's Farigiraf is not released. Toxel reaches the released plain Toxtricity through EVOLUTION_OVERRIDES
  // (the game master links only its two unreleased form ids), so its picks are Toxtricity where ranked and in the Master League fallback.
  for (const id of ['toxtricity_amped', 'toxtricity_low_key', 'farigiraf', 'basculegion_male']) assert.equal(gm.byId.get(id).released, false, `${id} is now released: pick another example`);
  assert.ok(!rankings.byLeague.ml.has('toxel') && !rankings.byLeague.ml.has('girafarig') && !rankings.byLeague.ml.has('farigiraf'), 'ranking data changed: pick another example');
  assert.equal(gm.byId.get('toxtricity').released, true);
  for (const l of ['gl', 'ul', 'ml']) assert.equal(leaguesOf(entry('Toxel', { ivs: null }))[l].pick.speciesId, 'toxtricity', l);
  assert.equal(leaguesOf(entry('Girafarig', { ivs: null })).ml.pick.speciesId, 'girafarig');
  // A branching family takes the released final form with the higher CP at level 50 with 15/15/15 (no real family is unranked and branching, so a made-up one).
  const mon = (speciesId, atk, released = true, family = {}) => ({ speciesId, speciesName: speciesId, dex: 1, baseStats: { atk, def: 100, hp: 100 }, types: ['normal'], released, family: { id: 'F', ...family } });
  const fake = indexGamemaster({ timestamp: 0, moves: [], pokemon: [mon('a', 100, true, { evolutions: ['b', 'c', 'd'] }), mon('b', 150), mon('c', 200), mon('d', 300, false)] });
  const fakeCtx = { gm: fake, tiers: ctx.tiers, rankings: { byLeague: { gl: new Map(), ul: new Map(), ml: new Map() } } };
  assert.equal(lf(entry('A', { ivs: null }), { speciesId: 'a' }, fakeCtx).ul.pick.speciesId, 'c');
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
    // Espurr is the same shape: the game master links it to the male Meowstic twice and never to the female form.
    // (Espurr itself outscores both Meowstic forms in Great League, so only the sex rule is asserted, not the form.)
    assert.notEqual(leaguesOf(entry('Espurr', { gender: '♀' }))[league].pick.speciesId, 'meowstic', league);
    assert.notEqual(leaguesOf(entry('Espurr', { gender: '♂' }))[league].pick.speciesId, 'meowstic_female', league);
    if (league !== 'gl') assert.equal(leaguesOf(entry('Espurr', { gender: '♀' }))[league].pick.speciesId, 'meowstic_female', league);
  }
  // Fixture CSV line 90 (Index 89) is a female Lechonk that Poke Genie rates as Oinkologne (Female).
  const row = box.find((p) => p.index === 89); // CSV line 90
  assert.equal(row.name, 'Lechonk');
  assert.equal(row.gender, '♀');
  assert.equal(lf(row, resolveSpecies(gm, row.name, { form: row.form }), ctx).gl.pick.speciesId, 'oinkologne_female');
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
  const L = lf(g, resolveSpecies(gm, g.name, { form: g.form, shadow: true }), ctx);
  for (const [key, league] of [['great', 'gl'], ['ultra', 'ul']]) {
    const c = g.pvp[key], cost = L[league].cost;
    assert.equal(cost.dust, c.dust, key);
    assert.equal(cost.candy + cost.evolveCandy, c.candy, key);
  }
  // Purified is 0.9 of each step, rounded up per step (Bulbapedia Shadow Pokémon (GO) and Power up; no fixture row has a purified cost).
  let candy = 0, xl = 0;
  for (let lv = 30; lv < 45; lv += 0.5) { const s = step(lv); candy += Math.ceil(s.candy * 0.9); xl += Math.ceil(s.xl * 0.9); }
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
  const L = lf(e, r, ctx);
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
  const ok = leaguesOf(entry('Mareep', { ivs: null })); // odd IVs are unknown IVs: the same pick as with none
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
  assert.equal(lf(entry('A'), { speciesId: 'a' }, fakeCtx).ul.pick.speciesId, 'a');
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

test('purified costs round up per power-up like shadow costs (Bulbapedia Shadow Pokémon (GO) and Power up; Fandom example 25 -> 35 = 102 candy)', () => {
  assert.equal(powerUpCost(25, 35, { purified: true }).candy, 102);
  assert.equal(powerUpCost(40, 50, { purified: true }).xl, 272);      // GO Hub's purified table
  assert.equal(powerUpCost(31, 33, { purified: true }).candy, 24);    // 5.4 -> 6 per step, four steps
  assert.equal(powerUpCost(31, 33, { shadow: true }).candy, 32);      // 7.2 -> 8 per step
  assert.equal(powerUpCost(31, 33).candy, 24);
});

test('Master League: the shown pick is the highest PvPoke score, not the stat-product emulation (Poke Genie exports no Master League pick)', () => {
  let rows = 0;
  for (const p of box) {
    const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
    if (!r) continue;
    const l = leaguesFor({ ...p, pvp: undefined }, r, ctx).ml;
    const ranked = l.options.filter((o) => o.strength);
    if (!ranked.length) { assert.equal(l.source, 'fallback'); continue; }
    assert.equal(l.source, 'ranked', p.name);
    assert.equal(l.options[l.pick].strength.score, Math.max(...ranked.map((o) => o.strength.score)), `${p.name} ${p.form}`);
    rows++;
  }
  assert.ok(rows > 100, `${rows} rows checked`);
  // Scyther: Scizor, not Kleavor (which the stat-product emulation preferred by ~0.07%); Great League is still emulated.
  const scyther = rawOf(entry('Scyther', { ivs: { atk: 6, def: 7, hp: 12 }, level: 17 }));
  assert.equal(shownOf(scyther.ml).speciesId, 'scizor');
  assert.equal(scyther.ml.source, 'ranked');
  assert.equal(scyther.gl.source, 'emulated');
});

test('experimental is never a member the copy is already too strong for; only a family with every member over the cap takes the shown pick', () => {
  let checked = 0;
  for (const p of box) {
    const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
    if (!r) continue;
    const L = leaguesFor({ ...p, pvp: undefined }, r, ctx);
    for (const league of ['gl', 'ul', 'ml']) {
      const l = L[league];
      if (l.options.some((o) => !o.overCap)) { assert.equal(l.options[l.experimental].overCap, false, `${p.name} ${league}`); checked++; }
      else assert.equal(l.experimental, l.pick, `${p.name} ${league}`);
    }
  }
  assert.ok(checked > 700, `${checked} leagues checked`);
  // Magnezone (a family of one) at level 40 is past the Great League cap: nothing fits, so the experimental pick is the shown pick.
  const all = rawOf(entry('Magnezone', { ivs: { atk: 2, def: 5, hp: 11 }, level: 40 })).gl;
  assert.ok(all.options.every((o) => o.overCap));
  assert.equal(all.experimental, all.pick);
});

test('moves are carried only on the shown and the experimental option', () => {
  const L = rawOf(entry('Eevee', { ivs: { atk: 6, def: 7, hp: 12 }, level: 17 }));
  for (const league of ['gl', 'ul', 'ml']) {
    const l = L[league];
    l.options.forEach((o, i) => {
      if (i === l.pick || i === l.experimental) assert.ok(o.strength ? o.moves : o.moves === null, `${league} ${o.speciesId}`);
      else assert.equal(o.moves, null, `${league} ${o.speciesId}`);
    });
    assert.ok(l.options.filter((o) => o.moves).length <= 2);
  }
});

test('overCap is CP at the current level over the cap: with unknown IVs it uses 0/0/0, with an unknown level it is never set', () => {
  // Corviknight at level 35 is over the Great League cap even at 0/0/0, so unknown IVs do not hide it.
  const unknown = rawOf(entry('Rookidee', { ivs: null, level: 35 })).gl;
  assert.equal(unknown.options.find((o) => o.speciesId === 'corviknight').overCap, true);
  assert.equal(unknown.options.find((o) => o.speciesId === 'rookidee').overCap, false);
  assert.ok(unknown.options.every((o) => o.iv === null && o.cost === null));
  const low = rawOf(entry('Rookidee', { ivs: null, level: 5 })).gl;
  assert.ok(low.options.every((o) => !o.overCap));
  assert.ok(rawOf(entry('Rookidee', { ivs: null, level: null })).gl.options.every((o) => !o.overCap));
});

test('a level 51 Best Buddy copy is over the cap only if its CP at 51 is: Cramorant and Seaking fit Ultra League, Talonflame does not', () => {
  const hundo = { atk: 15, def: 15, hp: 15 };
  const ul = (name) => rawOf(entry(name, { ivs: hundo, level: 51 })).ul;
  for (const [name, id] of [['Cramorant', 'cramorant'], ['Seaking', 'seaking']]) {
    const o = ul(name).options.find((x) => x.speciesId === id);
    assert.equal(o.overCap, false, name);
    assert.equal(o.cost, null, `${name}: its best level (50) is below the current one, so there is nothing to build towards`);
  }
  assert.equal(ul('Talonflame').options.find((x) => x.speciesId === 'talonflame').overCap, true);
  // The same CP rule at level 50 and below.
  assert.equal(rawOf(entry('Cramorant', { ivs: hundo, level: 50 })).ul.options.find((x) => x.speciesId === 'cramorant').overCap, false);
});
