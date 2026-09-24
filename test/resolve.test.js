import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadGamemaster } from '../src/node/load.js';
import { resolveSpecies, evolutionsOf, baseSpeciesId, megaIdsOf } from '../src/gamemaster.js';

const gm = loadGamemaster();
const id = (name, opts) => resolveSpecies(gm, name, opts)?.speciesId ?? null;

test('tier-list style names resolve', () => {
  assert.equal(id('Shadow Rhyperior'), 'rhyperior_shadow');
  assert.equal(id('Mega Charizard Y'), 'charizard_mega_y');
  assert.equal(id('Crowned Shield Zamazenta'), 'zamazenta_crowned_shield');
  assert.equal(id('Galarian Darmanitan'), 'darmanitan_galarian_standard');
  assert.equal(id('White Kyurem'), 'kyurem_white');
  assert.equal(id('Dawn Wings Necrozma'), 'necrozma_dawn_wings');
  assert.equal(id('Origin Palkia'), 'palkia_origin');
  assert.equal(id('Zygarde Complete'), 'zygarde_complete');
  assert.equal(id('Stunfisk (Unovan)'), 'stunfisk');
  assert.equal(id('Primal Groudon'), 'groudon_primal');
  assert.equal(id('Full-Belly Morpeko'), 'morpeko_full_belly');
  assert.equal(id('Gigantamax Inteleon'), 'inteleon');
  assert.equal(id('Dynamax Excadrill'), 'excadrill');
});

test('Poke Genie style names resolve to the base Pokémon', () => {
  assert.equal(id('Mewtwo', { form: 'Mega Y' }), 'mewtwo');
  assert.equal(id('Charizard', { form: 'Mega Y' }), 'charizard');
  assert.equal(id('Zamazenta', { form: 'Hero' }), 'zamazenta_hero');
  assert.equal(id('Zygarde', { form: '10%' }), 'zygarde_10');
  assert.equal(id('Stunfisk', { form: 'Galar' }), 'stunfisk_galarian');
  assert.equal(id('Geodude', { form: 'Alola' }), 'geodude_alolan');
  assert.equal(id('Dratini', { form: '', shadow: true }), 'dratini_shadow');
  assert.equal(id('Oricorio', { form: "Pa'u" }), 'oricorio_pau');
  assert.equal(id('Zapdos', { form: 'Normal' }), 'zapdos');
});

test('families and variants', () => {
  assert.deepEqual(evolutionsOf(gm, 'rhyhorn'), ['rhydon', 'rhyperior']);
  assert.ok(evolutionsOf(gm, 'dratini_shadow').includes('dragonite_shadow'));
  assert.equal(baseSpeciesId(gm, 'charizard_mega_y'), 'charizard');
  assert.equal(baseSpeciesId(gm, 'rhyperior_shadow'), 'rhyperior');
  assert.deepEqual(megaIdsOf(gm, 'charizard'), ['charizard_mega_x', 'charizard_mega_y']);
});
