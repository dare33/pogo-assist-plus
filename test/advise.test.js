import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadGamemaster, loadTiers, loadRankings } from '../src/node/load.js';
import { analyseBox } from '../src/advise.js';

const ctx = { gm: loadGamemaster(), tiers: loadTiers(), rankings: loadRankings() };
const box = importPokeGenie(readFileSync(new URL('../fixtures/greg-2026-09-25.pokegenie.csv', import.meta.url), 'utf8'));
const out = analyseBox(box, ctx);
const top = (n) => out.builds.slice(0, n).map((b) => `${b.speciesId}->${b.targetId}`);

test('the hand-written phase 1 and 2 builds are in the top 15', () => {
  const t = top(15);
  for (const want of ['mewtwo->mewtwo', 'zamazenta_hero->zamazenta_crowned_shield', 'gastly->gengar', 'tinkatink->tinkaton', 'xurkitree->xurkitree'])
    assert.ok(t.includes(want), `${want} missing from ${t.join(', ')}`);
});

test('duplicate copies fold into one build with spares', () => {
  const charmander = out.builds.find((b) => b.speciesId === 'charmander' && b.targetId === 'charizard');
  assert.ok(charmander);
  assert.equal(charmander.spares.length, 12);
  assert.equal(out.builds.filter((b) => b.speciesId === 'charmander' && b.targetId === 'charizard').length, 1);
});

test('Gigantamax entries are never credited to a box Pokémon, Dynamax ones are flagged', () => {
  for (const b of out.builds) for (const h of b.hits) assert.ok(!/gigantamax|g-max/i.test(h.name), `${h.name} credited to ${b.speciesId}`);
  const chansey = out.builds.find((b) => b.speciesId === 'chansey' && b.targetId === 'blissey');
  assert.ok(chansey.needsDynamax);
});

test('Mega hits fold into the base build and a plus-move is not a second charged move', () => {
  const mewtwo = out.builds.filter((b) => b.speciesId === 'mewtwo');
  assert.equal(mewtwo.length, 1);
  assert.ok(mewtwo[0].viaMega);
  assert.equal(mewtwo[0].cost.secondMove.dust, 0);
  assert.equal(mewtwo[0].cost.dust, 137000);
  // A Shadow's power-ups round up per step (1.2x in float32 for dust): the shadow Beldum build pins the rule in the advisor too.
  const beldum = out.builds.find((b) => b.speciesId === 'beldum_shadow' && b.targetId === 'metagross_shadow');
  assert.ok(beldum, 'shadow Beldum -> Metagross build');
  assert.equal(beldum.cost.dust, 197772);
  assert.equal(beldum.cost.candy, 335);
});

test('gaps list the S-tier things nothing in the box can become, and know when the base is owned', () => {
  const names = out.gaps.map((g) => g.name);
  assert.ok(names.includes('Melmetal'));
  assert.ok(names.includes('Mega Rayquaza'));
  assert.ok(!names.includes('Crowned Shield Zamazenta'), 'reachable by form change');
  assert.ok(!names.includes('Mega Gengar'), 'reachable from Gastly');
});

test('hygiene keeps the best copy and counts transfers', () => {
  const zapdos = out.hygiene.find((h) => h.speciesId === 'zapdos');
  assert.equal(zapdos.count, 6);
  assert.equal(zapdos.keep.length, 2);
  assert.equal(zapdos.keep[0].cp, 1991);
});

const template = box.find((p) => !p.shadow && !p.purified && !p.lucky && (!p.form || p.form === 'Normal'));
const one = (name, o = {}) => analyseBox([{ ...template, name, form: '', pvp: undefined, ...o }], ctx);
const buildTo = (res, target) => res.builds.find((b) => b.targetId === target);

test("league builds are rated by the build target's OWN option, even when it is not the shown pick (Squirtle -> Blastoise)", () => {
  // The fixture Squirtle at level 15: Poke Genie's Great League pick is Wartortle, so Blastoise is not the shown pick there.
  const squirtle = box.find((p) => p.name === 'Squirtle' && p.level === 15 && p.ivs.atk === 14 && p.ivs.def === 14 && p.ivs.hp === 12);
  assert.ok(squirtle);
  const res = analyseBox([{ ...squirtle, pvp: undefined }], ctx);
  const b = buildTo(res, 'blastoise');
  assert.ok(b.areas.includes('gl') || b.areas.includes('ul'));
  assert.ok(b.pvpCost, 'a league cost from the Blastoise option');
  assert.ok(['gl', 'ul'].includes(b.pvpCost.league));
  const L = res.pokemon[0].leagues[b.pvpCost.league];
  const own = L.options.find((o) => o.speciesId === 'blastoise');
  assert.equal(b.pvpCost.rankPct, own.iv.rankPct);
  assert.equal(b.pvpCost.dust, own.cost.dust);
  assert.equal(b.pvpCost.candy, own.cost.candy + own.cost.evolveCandy);
  assert.equal(b.pvpCost.xl, own.cost.xl);
});

test('across the fixture box, many league builds carry a league cost, none from Master League', () => {
  const withCost = out.builds.filter((b) => b.pvpCost);
  assert.ok(withCost.length >= 20, `${withCost.length} builds carry a league cost`);
  for (const b of withCost) {
    assert.ok(['gl', 'ul'].includes(b.pvpCost.league), b.pvpCost.league);
    assert.ok(b.pvpCost.rankPct >= 0 && b.pvpCost.rankPct <= 100);
  }
  // Builds do not depend on Poke Genie's columns at all: a scan scores identically.
  const scan = analyseBox(box.map((p) => ({ ...p, pvp: undefined })), ctx);
  const sig = (o) => o.builds.map((b) => [b.speciesId, b.targetId, b.value, b.score, b.pvpCost, b.cost]);
  assert.deepEqual(sig(scan), sig(out));
});

test('a copy already past the league cap as the target gets no league rating (Rookidee L35 -> Corviknight in Great League)', () => {
  const rookidee = (level) => one('Rookidee', { level, levelMin: level, levelMax: level, ivs: { atk: 10, def: 12, hp: 14 } });
  const high = buildTo(rookidee(35), 'corviknight');
  const L = rookidee(35).pokemon[0].leagues.gl;
  assert.equal(L.options.find((o) => o.speciesId === 'corviknight').overCap, true, 'level 35 is past Corviknight\'s Great League level');
  assert.ok(!high.pvpCost || high.pvpCost.league !== 'gl');
  const low = buildTo(rookidee(5), 'corviknight');
  assert.ok(low.pvpCost, 'at level 5 it is rated');
});

test('Master League keeps the neutral weight and is never the cost league (a hundo Melmetal at level 10)', () => {
  const res = one('Melmetal', { level: 10, levelMin: 10, levelMax: 10, ivs: { atk: 15, def: 15, hp: 15 } });
  const b = buildTo(res, 'melmetal');
  assert.ok(b.areas.includes('ml'));
  assert.ok(!b.pvpCost || b.pvpCost.league !== 'ml');
  const withUnknown = buildTo(one('Melmetal', { level: 10, levelMin: 10, levelMax: 10, ivs: null }), 'melmetal');
  // ML's weight is 0.6 whether or not the IVs are known (any difference would come from GL or UL).
  const ml = (bb) => bb.hits.filter((h) => h.area === 'ml').length;
  assert.ok(ml(b) >= 1 && ml(withUnknown) >= 1);
  assert.ok(b.cost.dust < 400000, `${b.cost.dust} dust`);
});

test("a league build is weighted by this copy's Rank % as Our pick, and neutrally (0.6) when the IVs are unknown", () => {
  const mk = (ivs) => ({ ...box.find((p) => p.name === 'Tinkatink'), ivs, pvp: undefined, ivPercent: 80 });
  const val = (ivs) => analyseBox([mk(ivs)], ctx).builds.find((b) => b.targetId === 'tinkaton');
  const good = val({ atk: 0, def: 15, hp: 15 }), bad = val({ atk: 15, def: 0, hp: 0 }), unknown = val(null);
  assert.ok(good.pvpCost && bad.pvpCost);
  assert.ok(good.pvpCost.rankPct > bad.pvpCost.rankPct);
  assert.ok(good.value > bad.value);
  assert.equal(unknown.pvpCost, null);
  assert.ok(unknown.value > bad.value && unknown.value < good.value);
});
