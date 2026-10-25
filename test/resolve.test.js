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

test('a Shadow copy resolves to the _shadow id whatever the name sorts like', () => {
  // The lookup key is sorted tokens. Before the fix " shadow" was appended unsorted, so names sorting after "shadow"
  // (Tyranitar, Victreebel) missed the index and resolved to the plain species with the shadow flag set.
  assert.equal(id('Tyranitar', { shadow: true }), 'tyranitar_shadow');
  assert.equal(id('Victreebel', { shadow: true }), 'victreebel_shadow');
  assert.equal(id('Alakazam', { shadow: true }), 'alakazam_shadow');
  assert.equal(id('Shadow Tyranitar'), 'tyranitar_shadow');
  assert.equal(id('Weezing', { form: 'Galarian', shadow: true }), 'weezing_galarian_shadow');
  assert.equal(id('Sneasel', { form: 'Hisuian', shadow: true }), 'sneasel_hisuian_shadow');
  // Poke Genie writes form "Normal" for a plain form; the Shadow lookup must still be sorted then.
  assert.equal(id('Tyranitar', { form: 'Normal', shadow: true }), 'tyranitar_shadow');
  assert.equal(id('Zapdos', { form: 'Normal', shadow: true }), 'zapdos_shadow');
});

test('an unreleased Shadow resolves to the plain species, flagged only when the name says Shadow', () => {
  // Zekrom has no Shadow in the game master. On the flag path (a box copy) the plain name matches before the unreleased-Shadow
  // fallback, so flags.unreleasedShadow is not set there; with "Shadow" in the name text (tier-list entries such as
  // "Shadow Roserade") the plain key misses and the fallback runs and sets it.
  assert.equal(gm.byId.has('zekrom_shadow'), false);
  const r = resolveSpecies(gm, 'Zekrom', { shadow: true });
  assert.equal(r.speciesId, 'zekrom');
  assert.equal(r.flags.shadow, true);
  assert.equal(r.flags.unreleasedShadow, undefined);
  const named = resolveSpecies(gm, 'Shadow Zekrom');
  assert.equal(named.speciesId, 'zekrom');
  assert.equal(named.flags.shadow, true);
  assert.equal(named.flags.unreleasedShadow, true);
});
