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

test('league build scoring reads leaguesFor (Our pick), not the Poke Genie columns: a scan with no pvp columns scores the same', () => {
  const scan = analyseBox(box.map((p) => ({ ...p, pvp: undefined })), ctx);
  const sig = (o) => o.builds.map((b) => [b.speciesId, b.targetId, b.value, b.score, b.pvpCost, b.cost]);
  assert.deepEqual(sig(scan), sig(out));
  const withCost = out.builds.filter((b) => b.pvpCost);
  assert.ok(withCost.length >= 10, `${withCost.length} builds carry a league cost`);
  for (const b of withCost) {
    assert.ok(['gl', 'ul', 'ml'].includes(b.pvpCost.league));
    assert.ok(b.pvpCost.rankPct >= 0 && b.pvpCost.rankPct <= 100);
  }
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
