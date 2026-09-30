import { test } from 'node:test';
import assert from 'node:assert/strict';
import { passKind, naturalCompare, orderClips, sameMon, overlapLength, mergeClips } from '../../src/extract/batch.js';
import { toPokeGenieCsv } from '../../src/extract/pipeline.js';
import { importPokeGenie } from '../../src/import/pokegenie.js';

// A row shaped like resolveRow's output, with just enough of the rest to survive a CSV round trip.
const IVS = { atk: 15, def: 14, hp: 15 };
const row = (name, cp, { form = '', hp = 100, ivs = IVS, flags = [], frames = 1, frame = `${name}-${cp}`, level = 20 } = {}) => ({
  index: 0, name, display: name, form, speciesId: name.toLowerCase(), dex: 1, cp, hp, ivs, ivsRead: ivs, ivsGuess: null,
  level: ivs ? level : null, levelMax: ivs ? level : null, dust: null, solveStatus: 'exact', flags, merged: 1,
  frames: Array.from({ length: frames }, (_, i) => ({ frame: `${frame}#${i}`, time: i })),
});
const clip = (name, rows, unmatched = []) => ({ name, kind: passKind(name), rows, unmatched });

test('passKind reads the basename only, case-insensitively', () => {
  assert.equal(passKind('01-main.mp4'), 'normal');
  assert.equal(passKind('02-Shadow.MP4'), 'shadow');
  assert.equal(passKind('C:\\shadow box\\01-main.mp4'), 'normal');
  assert.equal(passKind('/x/shadows/01-main.mp4'), 'normal');
  assert.equal(passKind('/x/03-PURIFIED-pass.mov'), 'purified');
});

test('naturalCompare and orderClips: clip2 before clip10, or by modified time', () => {
  assert.ok(naturalCompare('clip2', 'clip10') < 0);
  assert.ok(naturalCompare('Clip2', 'clip2') === 0);
  assert.ok(naturalCompare('a1', 'b0') < 0);
  const clips = [{ name: 'clip10.mp4', mtimeMs: 1 }, { name: 'clip2.mp4', mtimeMs: 3 }, { name: 'Clip1.mp4', mtimeMs: 2 }];
  assert.deepEqual(orderClips(clips).map((c) => c.name), ['Clip1.mp4', 'clip2.mp4', 'clip10.mp4']);
  assert.deepEqual(orderClips(clips, { order: 'mtime' }).map((c) => c.name), ['clip10.mp4', 'Clip1.mp4', 'clip2.mp4']);
  assert.deepEqual(orderClips([{ name: 'b', mtimeMs: 1 }, { name: 'a', mtimeMs: 1 }], { order: 'mtime' }).map((c) => c.name), ['a', 'b']);
});

test('sameMon tolerates a missing HP, not a different form or settled IVs', () => {
  assert.ok(sameMon(row('Zapdos', 1969), row('Zapdos', 1969)));
  assert.ok(sameMon(row('Zapdos', 1969, { hp: null }), row('Zapdos', 1969, { hp: 130 })));
  assert.ok(!sameMon(row('Zapdos', 1969, { hp: 129 }), row('Zapdos', 1969, { hp: 130 })));
  assert.ok(!sameMon(row('Zamazenta', 2692, { form: 'Hero' }), row('Zamazenta', 2692, { form: 'Crowned Shield' })));
  assert.ok(!sameMon(row('Zapdos', 1969), row('Zapdos', 1970)));
  assert.ok(sameMon(row('Zapdos', 1969, { ivs: null }), row('Zapdos', 1969)));
  assert.ok(!sameMon(row('Zapdos', 1969), row('Zapdos', 1969, { ivs: { atk: 1, def: 2, hp: 3 } })));
});

test('overlapLength: none, one, four, and capped', () => {
  const seq = (from, to) => Array.from({ length: to - from }, (_, i) => row('Meltan', 100 + from + i));
  assert.equal(overlapLength(seq(0, 5), seq(10, 15)), 0);
  assert.equal(overlapLength(seq(0, 5), seq(4, 9)), 1);
  assert.equal(overlapLength(seq(0, 8), seq(4, 12)), 4);
  assert.equal(overlapLength(seq(0, 30), seq(0, 30), { max: 10 }), 0); // tail 20..29 is not head 0..9
  const same = Array.from({ length: 20 }, () => row('Meltan', 150));
  assert.equal(overlapLength(same, same, { max: 10 }), 10);
  assert.equal(overlapLength(same, same, { max: 3 }), 3);
  assert.equal(overlapLength([], same), 0);
});

test('mergeClips drops a 4-row boundary overlap, keeps the fuller row, unions frames', () => {
  const a = [row('Meltan', 101), row('Meltan', 102), row('Meltan', 103, { hp: null, ivs: null, frames: 1, frame: 'a' }), row('Meltan', 104), row('Meltan', 105), row('Meltan', 106)];
  const b = [row('Meltan', 103, { frames: 3, frame: 'b' }), row('Meltan', 104), row('Meltan', 105), row('Meltan', 106), row('Meltan', 107)];
  const m = mergeClips([clip('01.mp4', a), clip('02.mp4', b)]);
  assert.deepEqual(m.rows.map((r) => r.cp), [101, 102, 103, 104, 105, 106, 107]);
  assert.deepEqual(m.boundaries, [{ before: '01.mp4', after: '02.mp4', dropped: 4 }]);
  const kept = m.rows[2];
  assert.ok(kept.ivs && kept.hp === 100, 'the row with IVs and HP wins');
  assert.equal(kept.frames.length, 4, 'frames of both rows are kept');
  assert.deepEqual([...new Set(kept.frames.map((f) => f.clip))].sort(), ['01.mp4', '02.mp4']);
});

test('mergeClips never deduplicates identical rows away from a boundary', () => {
  const a = [row('Meltan', 150), row('Meltan', 150), row('Zapdos', 1969)];
  const b = [row('Mew', 500), row('Mew', 500)];
  const m = mergeClips([clip('01.mp4', a), clip('02.mp4', b)]);
  assert.equal(m.rows.length, 5);
  assert.deepEqual(m.boundaries, []);
});

test('mergeClips chains three normal clips and reindexes 1..n', () => {
  const mk = (from, to) => Array.from({ length: to - from }, (_, i) => row('Meltan', 100 + from + i));
  const m = mergeClips([clip('01.mp4', mk(0, 6)), clip('02.mp4', mk(4, 10)), clip('03.mp4', mk(8, 14))]);
  assert.deepEqual(m.rows.map((r) => r.cp), mk(0, 14).map((r) => r.cp));
  assert.deepEqual(m.rows.map((r) => r.index), Array.from({ length: 14 }, (_, i) => i + 1));
  assert.deepEqual(m.boundaries.map((b) => b.dropped), [2, 2]);
});

test('mergeClips: a shadow clip marks the matching normal row and its own row is dropped', () => {
  const normal = [row('Meltan', 101), row('Mew', 500), row('Meltan', 103)];
  const shadow = [row('Mew', 500, { frames: 2, frame: 's' })];
  const m = mergeClips([clip('01.mp4', normal), clip('02-shadow.mp4', shadow)]);
  assert.equal(m.rows.length, 3);
  assert.deepEqual(m.rows.map((r) => r.shadow), [undefined, 1, undefined]);
  assert.equal(m.rows[1].frames.length, 3);
  assert.deepEqual(m.reconciled, { matched: 1, appended: 0, ambiguous: 0 });
});

test('mergeClips: a shadow row with no normal match is appended with shadow 1', () => {
  const m = mergeClips([clip('01.mp4', [row('Meltan', 101)]), clip('02-shadow.mp4', [row('Mew', 500)])]);
  assert.deepEqual(m.rows.map((r) => [r.name, r.shadow, r.index]), [['Meltan', undefined, 1], ['Mew', 1, 2]]);
  assert.deepEqual(m.reconciled, { matched: 0, appended: 1, ambiguous: 0 });
});

test('mergeClips: two identical unmarked matches mark the first and flag it', () => {
  const normal = [row('Mew', 500), row('Meltan', 101), row('Mew', 500)];
  const m = mergeClips([clip('01.mp4', normal), clip('02-shadow.mp4', [row('Mew', 500)])]);
  assert.equal(m.rows.length, 3);
  assert.equal(m.rows[0].shadow, 1);
  assert.ok(m.rows[0].flags.includes('shadow-match-ambiguous'));
  assert.equal(m.rows[2].shadow, undefined);
  assert.deepEqual(m.reconciled, { matched: 0, appended: 0, ambiguous: 1 });
  assert.equal(m.review.length, 1);
});

test('mergeClips: a purified clip marks 2; review carries clip and shadow', () => {
  const m = mergeClips([clip('01.mp4', [row('Mew', 500, { flags: ['ivs-unread'] })]), clip('03-Purified.mp4', [row('Mew', 500)])]);
  assert.equal(m.rows[0].shadow, 2);
  assert.equal(m.review[0].clip, '01.mp4');
  assert.equal(m.review[0].shadow, 2);
  assert.deepEqual(m.clips.map((c) => [c.name, c.kind, c.rows, c.flagged]), [['01.mp4', 'normal', 1, 1], ['03-Purified.mp4', 'purified', 1, 0]]);
});

test('mergeClips tags unmatched frames with their clip and does not mutate its input', () => {
  const input = [row('Mew', 500)];
  const m = mergeClips([clip('01.mp4', input, [{ frame: 'f0001.png', cp: 12 }])]);
  assert.deepEqual(m.unmatched, [{ frame: 'f0001.png', cp: 12, clip: '01.mp4' }]);
  assert.equal(input[0].clip, undefined);
  assert.equal(input[0].frames[0].clip, undefined);
});

test('toPokeGenieCsv writes Shadow/Purified 1, 2 and blank', () => {
  const rows = [{ ...row('Mew', 500), shadow: 1 }, { ...row('Mew', 501), shadow: 2 }, { ...row('Mew', 502) }, { ...row('Mew', 503), shadow: 0 }];
  const csv = toPokeGenieCsv(rows);
  const back = importPokeGenie(csv);
  assert.deepEqual(back.map((r) => [r.shadow, r.purified]), [[true, false], [false, true], [false, false], [false, false]]);
  const col = csv.split('\n')[0].split(',').indexOf('Shadow/Purified');
  assert.deepEqual(csv.trim().split('\n').slice(1).map((l) => l.split(',')[col]), ['1', '2', '', '']);
});
