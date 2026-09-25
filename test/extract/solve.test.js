import { test } from 'node:test';
import assert from 'node:assert/strict';
import { solve, speciesFor } from '../../src/extract/solve.js';
import { loadGamemaster } from '../../src/node/load.js';

const gm = loadGamemaster();
const sp = (id) => speciesFor(gm, [id]);

test('exact bars, CP and HP give one level (acceptance rows)', () => {
  const cases = [
    ['mewtwo_mega_y', 3673, 145, { atk: 15, def: 15, hp: 15 }, 20],
    ['zamazenta_hero', 2692, 137, { atk: 13, def: 12, hp: 14 }, 25],
    ['zamazenta_hero', 2651, 135, { atk: 12, def: 10, hp: 11 }, 25],
    ['xurkitree', 3028, 145, { atk: 15, def: 14, hp: 15 }, 27],
  ];
  for (const [id, cp, hp, ivs, level] of cases) {
    const r = solve({ species: sp(id), cp, hp, ivs });
    assert.equal(r.status, 'exact', `${id} ${cp}`);
    assert.equal(r.solutions[0].level, level);
    assert.deepEqual(r.solutions[0].ivs, ivs);
  }
});

test('the name alone can be several forms; CP and HP pick the one that fits', () => {
  const r = solve({ species: speciesFor(gm, ['zamazenta_crowned_shield', 'zamazenta_hero']), cp: 2692, hp: 137, ivs: { atk: 13, def: 12, hp: 14 } });
  assert.equal(r.status, 'exact');
  assert.equal(r.solutions[0].speciesId, 'zamazenta_hero');
});

test('a one-unit bar miss is corrected when exactly one neighbour fits', () => {
  const r = solve({ species: sp('xurkitree'), cp: 3028, hp: 145, ivs: { atk: 15, def: 13, hp: 15 } });
  assert.equal(r.status, 'corrected');
  assert.deepEqual(r.solutions[0].ivs, { atk: 15, def: 14, hp: 15 });
});

test('bars that fit nothing nearby are reported as ambiguous with every fit listed', () => {
  const r = solve({ species: sp('sawk'), cp: 1330, hp: 108, ivs: { atk: 7, def: 7, hp: 7 } });
  assert.equal(r.status, 'ambiguous');
  assert.ok(r.solutions.some((s) => s.ivs.atk === 1 && s.ivs.def === 0 && s.ivs.hp === 6 && s.level === 19));
});

test('no bars gives a level range from CP and HP', () => {
  const r = solve({ species: sp('dedenne'), cp: 902, hp: 98, ivs: null });
  assert.equal(r.status, 'unknown-ivs');
  const levels = r.solutions.map((s) => s.level);
  assert.ok(levels.includes(18));
  assert.ok(r.solutions.some((s) => s.ivs.atk === 11 && s.ivs.def === 14 && s.ivs.hp === 7));
});

test('a wrong CP fits nothing', () => {
  const r = solve({ species: sp('xurkitree'), cp: 3023, hp: 145, ivs: { atk: 15, def: 14, hp: 15 } });
  assert.ok(r.status === 'none' || r.status === 'ambiguous', `status ${r.status}`);
  assert.ok(!r.solutions.length || r.solutions[0].tier === 2);
});
