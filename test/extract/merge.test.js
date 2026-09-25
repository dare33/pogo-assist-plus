import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSimilar, groupRuns, collapseRun, dedupeAdjacent, vote, ranked } from '../../src/extract/merge.js';

const reading = (name, cp, hp, ivs, ivConfidence = 0.9, extra = {}) => ({
  frame: `${name}-${cp}`, name, cp, cpReads: [cp], hp: hp === null ? null : { current: hp, max: hp }, ivs, ivConfidence, sharpness: 1, nameText: name, ...extra,
});

test('cpSimilar accepts one wrong digit or one dropped digit, nothing looser', () => {
  assert.ok(cpSimilar(3028, 3023));
  assert.ok(cpSimilar(902, 92));
  assert.ok(!cpSimilar(902, 2)); // a single digit is not evidence
  assert.ok(cpSimilar(2223, 223));
  assert.ok(cpSimilar(1969, 1962)); // one digit different: similar
  assert.ok(!cpSimilar(3028, 2592));
  assert.ok(!cpSimilar(22, 2692));
  assert.ok(!cpSimilar(1614, 94));
});

test('groupRuns keeps a Pokémon together across an unreadable frame and a garbled CP read', () => {
  const rs = [
    reading('Xurkitree', 3028, 145, { atk: 15, def: 14, hp: 15 }),
    { frame: 'swipe', name: null, cp: null, flags: ['mid-swipe'] },
    reading('Xurkitree', 3023, 145, { atk: 15, def: 14, hp: 15 }),
    reading('Xurkitree', 3028, 145, { atk: 15, def: 14, hp: 15 }),
    reading('Zamazenta', 2692, 137, { atk: 13, def: 12, hp: 14 }),
  ];
  const runs = groupRuns(rs);
  assert.equal(runs.length, 2);
  assert.equal(runs[0].frames.length, 3);
});

test('groupRuns splits on a different HP even with the same name and CP', () => {
  const rs = [reading('Meltan', 14, 13, { atk: 12, def: 4, hp: 15 }), reading('Meltan', 14, 12, { atk: 1, def: 1, hp: 1 })];
  assert.equal(groupRuns(rs).length, 2);
});

test('groupRuns splits two different Zapdos with different CP and HP', () => {
  const rs = [reading('Zapdos', 1969, 130, { atk: 14, def: 11, hp: 11 }), reading('Zapdos', 1962, 132, { atk: 10, def: 12, hp: 15 })];
  assert.equal(groupRuns(rs).length, 2);
});

test('collapseRun votes the CP, the HP and the settled bars', () => {
  const rs = [
    reading('Hitmonlee', 1614, 94, { atk: 8, def: 4, hp: 8 }, 0.58),
    reading('Hitmonlee', 1614, 94, { atk: 8, def: 1, hp: 8 }, 0.92),
    reading('Hitmonlee', 1641, 94, { atk: 8, def: 1, hp: 8 }, 0.92),
    reading('Hitmonlee', 1614, null, { atk: 8, def: 1, hp: 8 }, 0.92),
  ];
  const row = collapseRun(groupRuns(rs)[0]);
  assert.equal(row.cp, 1614);
  assert.deepEqual(row.cpCandidates, [1614, 1641]);
  assert.equal(row.hp, 94);
  assert.deepEqual(row.ivs, { atk: 8, def: 1, hp: 8 });
  assert.equal(row.frames.length, 4);
});

test('collapseRun falls back to the last unsettled read and keeps its low confidence', () => {
  const rs = [reading('Zapdos', 1970, 132, { atk: 6, def: 6, hp: 6 }, 0.1), reading('Zapdos', 1970, 132, { atk: 11, def: 12, hp: 13 }, 0.3)];
  const row = collapseRun(groupRuns(rs)[0]);
  assert.deepEqual(row.ivs, { atk: 11, def: 12, hp: 13 });
  assert.ok(row.ivConfidence < 0.7);
});

test('dedupeAdjacent merges the same Pokémon settled twice but never non-adjacent copies', () => {
  const row = (name, cp, hp, ivs) => ({ name, cp, hp, ivs, ivConfidence: 0.9, frames: [{ frame: `${name}${cp}` }], cpCandidates: [cp] });
  const out = dedupeAdjacent([row('Mewtwo', 3673, 145, null), row('Mewtwo', 3673, 145, { atk: 15, def: 15, hp: 15 }), row('Meltan', 14, 13, null), row('Mewtwo', 3673, 145, { atk: 15, def: 15, hp: 15 })]);
  assert.equal(out.length, 3);
  assert.deepEqual(out[0].ivs, { atk: 15, def: 15, hp: 15 });
  assert.equal(out[0].frames.length, 2);
  assert.equal(out[0].merged, 2);
});

test('vote and ranked', () => {
  assert.equal(vote([1, 2, 2, null, 3]), 2);
  assert.deepEqual(ranked(['a', 'b', 'a']).map((e) => [e.v, e.n]), [['a', 2], ['b', 1]]);
});
