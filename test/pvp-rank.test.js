import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadGamemaster } from '../src/node/load.js';
import { ivRank } from '../src/pvp-rank.js';
const gm = loadGamemaster();
const base = (id) => gm.byId.get(id).baseStats;

test('ranks match Poke Genie for spreads the export scored', () => {
  // From fixtures/greg-2026-09-25.pokegenie.csv: Tinkatink 3/13/7 -> Tinkaton GL rank 449; Mankey 0/0/11 -> Annihilape GL rank 166; Stunfisk (Galar) 0/0/12 GL rank 317
  assert.equal(ivRank('tinkaton', base('tinkaton'), { atk: 3, def: 13, hp: 7 }, 'gl').rank, 449);
  assert.equal(ivRank('annihilape', base('annihilape'), { atk: 0, def: 0, hp: 11 }, 'gl').rank, 166);
  assert.equal(ivRank('stunfisk_galarian', base('stunfisk_galarian'), { atk: 0, def: 0, hp: 12 }, 'gl').rank, 317);
  assert.equal(ivRank('ampharos', base('ampharos'), { atk: 0, def: 15, hp: 15 }, 'ul').rank, 8);
});
