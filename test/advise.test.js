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
