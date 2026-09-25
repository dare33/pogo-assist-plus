import { test } from 'node:test';
import assert from 'node:assert/strict';
import { displayNames, matchName, distance, normalise } from '../../src/extract/names.js';
import { loadGamemaster } from '../../src/node/load.js';

const names = displayNames(loadGamemaster());

test('display names follow what the game prints', () => {
  const find = (d) => names.find((n) => n.display === d);
  assert.deepEqual(find('Mega Mewtwo Y').speciesIds, ['mewtwo_mega_y']);
  assert.equal(find('Mega Mewtwo Y').form, 'Mega Y');
  assert.ok(find('Zamazenta').speciesIds.includes('zamazenta_hero'));
  assert.ok(find('Alolan Raichu'));
  assert.equal(find('Alolan Raichu').form, 'Alola');
  assert.ok(!names.some((n) => n.speciesIds.some((id) => id.endsWith('_shadow'))));
});

test('matchName survives the pencil icon, a stray token and one wrong letter', () => {
  assert.equal(matchName('Meltan .', names).candidate.display, 'Meltan');
  assert.equal(matchName('be Meltan', names).candidate.display, 'Meltan');
  assert.equal(matchName('Xurkitrea', names).candidate.display, 'Xurkitree');
  assert.equal(matchName('Mega Mewtwo Y', names).candidate.display, 'Mega Mewtwo Y');
  assert.equal(matchName('ime COIlouUurrul os', names), null);
  assert.equal(matchName('', names), null);
});

test('distance and normalise', () => {
  assert.equal(distance('kitten', 'sitting'), 3);
  assert.equal(normalise('Flabébé!'), 'flabebe');
});
