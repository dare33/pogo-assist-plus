import { test } from 'node:test';
import assert from 'node:assert/strict';
import { passKind, naturalCompare, orderClips, sameMon, overlapLength, overlapInfo, combine, mergeClips } from '../../src/extract/batch.js';
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

test('overlapLength takes the smallest consistent k; weak when several fit or a pair is incomplete', () => {
  const seq = (from, to) => Array.from({ length: to - from }, (_, i) => row('Meltan', 100 + from + i));
  assert.equal(overlapLength(seq(0, 5), seq(10, 15)), 0);
  assert.deepEqual(overlapInfo(seq(0, 5), seq(4, 9)), { k: 1, weak: false, ks: [1] });
  assert.deepEqual(overlapInfo(seq(0, 8), seq(4, 12)), { k: 4, weak: false, ks: [4] });
  assert.equal(overlapLength(seq(0, 30), seq(0, 30), { max: 10 }), 0); // tail 20..29 is not head 0..9
  // A run of identical rows: k = 1, 2, ... are all consistent, so the fewest is dropped and it is weak.
  const same = Array.from({ length: 20 }, () => row('Meltan', 150));
  assert.deepEqual(overlapInfo(same, same, { max: 10 }), { k: 1, weak: true, ks: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] });
  assert.deepEqual(overlapInfo(same, same, { max: 3 }), { k: 1, weak: true, ks: [1, 2, 3] });
  assert.equal(overlapLength([], same), 0);
  // A distinct overlap with an unread HP or IVs is weak too.
  assert.equal(overlapInfo([row('A', 1), row('B', 2, { hp: null })], [row('B', 2), row('C', 3)]).weak, true);
});

test('mergeClips drops a 4-row boundary overlap unflagged and lists what was dropped', () => {
  const mk = (from, to, frame) => Array.from({ length: to - from }, (_, i) => row('Meltan', 100 + from + i, { frame }));
  const m = mergeClips([clip('01.mp4', mk(1, 7, 'a')), clip('02.mp4', mk(3, 8, 'b'))]);
  assert.deepEqual(m.rows.map((r) => r.cp), [101, 102, 103, 104, 105, 106, 107]);
  assert.deepEqual(m.boundaries, [{ before: '01.mp4', after: '02.mp4', dropped: 4, weak: false, droppedRows: [103, 104, 105, 106].map((cp) => ({ name: 'Meltan', cp })), alternatives: [4], maybeRepeated: [] }]);
  assert.ok(m.rows.every((r) => !r.flags.length));
  assert.equal(m.rows[2].frames.length, 2, 'frames of both rows are kept');
  assert.deepEqual([...new Set(m.rows[2].frames.map((f) => f.clip))].sort(), ['01.mp4', '02.mp4']);
});

test('mergeClips keeps the fuller row at an incomplete join and flags the join boundary-weak', () => {
  const a = [row('Meltan', 101), row('Meltan', 102), row('Meltan', 103, { hp: null, ivs: null, flags: ['hp-unread', 'ivs-unread'] }), row('Meltan', 104)];
  const b = [row('Meltan', 103, { frames: 3, frame: 'b' }), row('Meltan', 104), row('Meltan', 105)];
  const m = mergeClips([clip('01.mp4', a), clip('02.mp4', b)]);
  assert.deepEqual(m.rows.map((r) => r.cp), [101, 102, 103, 104, 105]);
  assert.equal(m.boundaries[0].dropped, 2);
  assert.equal(m.boundaries[0].weak, true);
  assert.ok(m.rows[2].ivs && m.rows[2].hp === 100, 'the row with IVs and HP wins');
  assert.equal(m.rows[2].frames.length, 4);
  assert.deepEqual(m.rows[2].flags, ['boundary-weak'], 'stale hp-unread and ivs-unread are dropped');
  assert.ok(m.rows[3].flags.includes('boundary-weak') && !m.rows[4].flags.length);
});

test('mergeClips never deduplicates identical rows away from a boundary', () => {
  const a = [row('Meltan', 150), row('Meltan', 150), row('Zapdos', 1969)];
  const b = [row('Mew', 500), row('Mew', 500)];
  const m = mergeClips([clip('01.mp4', a), clip('02.mp4', b)]);
  assert.equal(m.rows.length, 5);
  assert.deepEqual(m.boundaries.map((b) => [b.dropped, b.unmatched]), [[0, true]]);
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
  assert.deepEqual(m.reconciled, { matched: 1, appended: 0, ambiguous: 0, weak: 0 });
});

test('mergeClips: a shadow row with no normal match is appended with shadow 1', () => {
  const m = mergeClips([clip('01.mp4', [row('Meltan', 101)]), clip('02-shadow.mp4', [row('Mew', 500)])]);
  assert.deepEqual(m.rows.map((r) => [r.name, r.shadow, r.index]), [['Meltan', undefined, 1], ['Mew', 1, 2]]);
  assert.deepEqual(m.reconciled, { matched: 0, appended: 1, ambiguous: 0, weak: 0 });
});

test('mergeClips: two identical unmarked matches mark the first and flag it', () => {
  const normal = [row('Mew', 500), row('Meltan', 101), row('Mew', 500)];
  const m = mergeClips([clip('01.mp4', normal), clip('02-shadow.mp4', [row('Mew', 500)])]);
  assert.equal(m.rows.length, 3);
  assert.equal(m.rows[0].shadow, 1);
  assert.ok(m.rows[0].flags.includes('shadow-match-ambiguous'));
  assert.equal(m.rows[2].shadow, undefined);
  assert.deepEqual(m.reconciled, { matched: 0, appended: 0, ambiguous: 1, weak: 0 });
  assert.equal(m.review.length, 1);
});

test('mergeClips: a purified clip marks 2; review carries clip and shadow', () => {
  const m = mergeClips([clip('01.mp4', [row('Mew', 500, { flags: ['cp-chosen-500-over-501'] })]), clip('03-Purified.mp4', [row('Mew', 500)])]);
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

// Rows as pipeline.js resolveRow makes them: no ivConfidence, the guesses are only in `flags`.
test('sameMon judges guessed IVs and HP from flags on pipeline-shaped rows', () => {
  const a = row('Mew', 500), noConf = (r) => { assert.equal(r.ivConfidence, undefined); return r; };
  const other = { atk: 1, def: 2, hp: 3 };
  assert.ok(!sameMon(noConf(a), noConf(row('Mew', 500, { ivs: other }))), 'settled IVs that differ conflict');
  assert.ok(sameMon(a, row('Mew', 500, { ivs: other, flags: ['bars-unsettled'] })));
  assert.ok(sameMon(a, row('Mew', 500, { ivs: other, flags: ['ivs-corrected-from-1/2/3'] })));
  assert.ok(sameMon(a, row('Mew', 500, { ivs: other, flags: ['ivs-disagree'] })));
  assert.ok(sameMon(a, { ...row('Mew', 500, { ivs: other }), solveStatus: 'corrected' }));
  assert.ok(!sameMon(a, row('Mew', 500, { hp: 90 })));
  assert.ok(sameMon(a, row('Mew', 500, { hp: 90, flags: ['hp-computed'] })));
});

test('two different Mew 500 at a join are not merged', () => {
  const x = row('Mew', 500, { hp: 90, ivs: { atk: 0, def: 0, hp: 0 } }), y = row('Mew', 500, { hp: 95, ivs: { atk: 15, def: 15, hp: 15 } });
  const m = mergeClips([clip('01.mp4', [row('A', 1), x]), clip('02.mp4', [y, row('B', 2)])]);
  assert.equal(m.rows.length, 4);
  assert.deepEqual(m.boundaries.map((b) => [b.dropped, b.unmatched]), [[0, true]]);
});

test('identical Meltans at a join drop the fewest and are flagged boundary-weak', () => {
  const M = () => row('Meltan', 150), X = row('Xurkitree', 3028), Y = row('Yveltal', 3000);
  const m = mergeClips([clip('01.mp4', [X, M(), M()]), clip('02.mp4', [M(), M(), Y])]);
  assert.deepEqual(m.rows.map((r) => r.name), ['Xurkitree', 'Meltan', 'Meltan', 'Meltan', 'Yveltal']);
  assert.equal(m.boundaries[0].dropped, 1);
  assert.equal(m.boundaries[0].weak, true);
  assert.deepEqual(m.rows.map((r) => r.flags.includes('boundary-weak')), [false, true, true, true, false]);
  assert.deepEqual(m.boundaries[0].alternatives, [1, 2]);
  assert.deepEqual(m.boundaries[0].maybeRepeated, [{ name: 'Meltan', cp: 150 }]);
});

test('boundary before names the clip the tail row belongs to', () => {
  const mk = (from, to) => Array.from({ length: to - from }, (_, i) => row('Meltan', 100 + from + i));
  // 02 is nothing but overlap, so 03 joins against a row that came from 01.
  const m = mergeClips([clip('01.mp4', mk(0, 5)), clip('02.mp4', mk(3, 5)), clip('03.mp4', mk(4, 8))]);
  assert.deepEqual(m.boundaries.map((b) => [b.before, b.after]), [['01.mp4', '02.mp4'], ['01.mp4', '03.mp4']]);
});

test('combine drops flags that the other row has made stale', () => {
  const bare = row('Mew', 500, { ivs: null, hp: null, flags: ['ambiguous-ivs:3-fit', 'hp-unread', 'no-level-fits', 'ivs-unread'] });
  const full = row('Mew', 500, { flags: ['cp-chosen-500-over-501'] });
  for (const c of [combine(bare, full), combine(full, bare)]) {
    assert.deepEqual(c.flags, ['cp-chosen-500-over-501'], "a discarded row's misread does not condemn the row that solved");
    assert.equal(c.hp, 100);
  }
  // A read HP replaces a computed one, and hp-computed goes; a computed HP alone keeps its flag.
  const computed = row('Mew', 500, { hp: 99, flags: ['hp-computed'] });
  const read = combine(computed, row('Mew', 500, { hp: 100 }));
  assert.equal(read.hp, 100);
  assert.ok(!read.flags.includes('hp-computed'));
  assert.ok(combine(computed, row('Mew', 500, { hp: null, flags: ['hp-unread'] })).flags.includes('hp-computed'));
});

test('shadow match on incomplete readings marks the row weak; strong matches do not', () => {
  const normal = [row('Mew', 500, { hp: null, ivs: null, flags: ['hp-unread', 'ivs-unread'] }), row('Zapdos', 1969)];
  const shadow = [row('Mew', 500), row('Zapdos', 1969)];
  const m = mergeClips([clip('01.mp4', normal), clip('02-shadow.mp4', shadow)]);
  assert.equal(m.rows.length, 2);
  assert.deepEqual(m.reconciled, { matched: 1, appended: 0, ambiguous: 0, weak: 1 });
  assert.equal(m.rows[0].shadow, 1);
  assert.deepEqual(m.rows[0].flags, ['shadow-match-weak'], 'the shadow row supplied the missing HP and IVs');
  assert.ok(m.rows[0].ivs && m.rows[0].hp === 100);
  assert.deepEqual(m.rows[1].flags, []);
  assert.equal(m.review.length, 1);
});

test('a strong shadow match is preferred over a weak candidate', () => {
  const weakRow = row('Mew', 500, { ivs: null, flags: ['ivs-unread'] }), strongRow = row('Mew', 500);
  const m = mergeClips([clip('01.mp4', [weakRow, strongRow]), clip('02-shadow.mp4', [row('Mew', 500)])]);
  assert.deepEqual(m.rows.map((r) => r.shadow), [undefined, 1]);
  assert.deepEqual(m.reconciled, { matched: 1, appended: 0, ambiguous: 0, weak: 0 });
});

test('A1 probe: several overlaps fit, so rows up to the largest are flagged and listed as possible repeats', () => {
  const X = row('Xurkitree', 3028), Y = row('Yveltal', 3000), Z = () => row('Zapdos', 1969), M = () => row('Meltan', 150);
  const m = mergeClips([clip('01.mp4', [X, M(), Z(), M()]), clip('02.mp4', [M(), Z(), M(), Y])]);
  const b = m.boundaries[0];
  assert.equal(b.dropped, 1);
  assert.deepEqual(b.alternatives, [1, 3]);
  assert.deepEqual(b.droppedRows, [{ name: 'Meltan', cp: 150 }]);
  assert.deepEqual(b.maybeRepeated, [{ name: 'Zapdos', cp: 1969 }, { name: 'Meltan', cp: 150 }]);
  assert.equal(b.weak, true);
  assert.deepEqual(m.rows.map((r) => r.name), ['Xurkitree', 'Meltan', 'Zapdos', 'Meltan', 'Zapdos', 'Meltan', 'Yveltal']);
  assert.deepEqual(m.rows.map((r) => r.flags.includes('boundary-weak')), [false, true, true, true, true, true, false]);
});

test('A2: a join where nothing matches is recorded as unmatched with tail and head', () => {
  const A = row('A', 1), B = row('B', 2), D = row('D', 4);
  const m = mergeClips([clip('01.mp4', [A, B, row('C', 300)]), clip('02.mp4', [row('B', 2), row('C', 308), D])]);
  assert.equal(m.rows.length, 6);
  assert.deepEqual(m.boundaries, [{ before: '01.mp4', after: '02.mp4', dropped: 0, unmatched: true, tail: { name: 'C', cp: 300 }, head: { name: 'B', cp: 2 } }]);
});

test('A3: a read HP replacing a computed HP that differs is flagged hp-mismatch', () => {
  const computed = row('Mew', 500, { hp: 99, flags: ['hp-computed'] });
  const c = combine(computed, row('Mew', 500, { hp: 100, ivs: null, flags: [] }));
  assert.equal(c.hp, 100);
  assert.ok(c.flags.includes('hp-mismatch:99/100'));
  assert.ok(!c.flags.includes('hp-computed'));
  assert.ok(!combine(computed, row('Mew', 500, { hp: 99 })).flags.some((f) => f.startsWith('hp-mismatch')), 'equal HP: no mismatch');
});

test('A4: settled IVs win over a lenient guess, and the guess flags of the loser go', () => {
  const guess = row('Mew', 500, { ivs: { atk: 1, def: 2, hp: 3 }, flags: ['bars-unsettled'], frames: 50 });
  const settled = row('Mew', 500, { frames: 1, flags: ['ivs-disagree'] });
  const settledClean = row('Mew', 500, { frames: 1 });
  const c = combine(guess, settledClean);
  assert.deepEqual(c.ivs, IVS);
  assert.ok(!c.flags.includes('bars-unsettled'));
  // Both orders keep the settled row; its own lenient flag stays when its own IVs are the doubtful ones.
  assert.deepEqual(combine(settledClean, guess).ivs, IVS);
  assert.ok(combine(guess, settled).flags.includes('ivs-disagree'));
});

test('no-level-fits stays when the kept row itself carried it, or an hp-mismatch fired', () => {
  const bad = () => row('Mew', 500, { ivs: null, hp: null, flags: ['no-level-fits', 'hp-unread'] });
  assert.ok(combine(bad(), bad()).flags.includes('no-level-fits'));
  const computed = row('Mew', 500, { hp: 99, frames: 9, flags: ['hp-computed'] });
  const c = combine(computed, row('Mew', 500, { hp: 100, frames: 1, flags: ['no-level-fits'] }));
  assert.ok(c.flags.some((f) => f.startsWith('hp-mismatch')));
  assert.ok(c.flags.includes('no-level-fits'), 'kept because the HP swap disagreed');
});

test('a clip join: a misread partner does not leave no-level-fits on the row that solved', () => {
  const misread = row('Mew', 500, { ivs: null, hp: null, flags: ['no-level-fits', 'bars-unsettled'] });
  const m = mergeClips([clip('01.mp4', [row('A', 1), misread]), clip('02.mp4', [row('Mew', 500, { hp: 100 }), row('B', 2)])]);
  assert.deepEqual(m.rows.map((r) => r.name), ['A', 'Mew', 'B']);
  assert.deepEqual(m.rows[1].ivs, IVS);
  assert.ok(!m.rows[1].flags.includes('no-level-fits'));
  assert.ok(!m.rows[1].flags.includes('bars-unsettled'));
});

test('a shadow match: a misread shadow row does not put no-level-fits on the read main row', () => {
  const shadow = row('Mew', 500, { ivs: null, flags: ['no-level-fits'] });
  const m = mergeClips([clip('01.mp4', [row('Mew', 500)]), clip('02-shadow.mp4', [shadow])]);
  assert.equal(m.rows.length, 1);
  assert.equal(m.rows[0].shadow, 1);
  assert.ok(!m.rows[0].flags.includes('no-level-fits'));
});

test('per-clip flagged counts come from the final rows, after boundary marking', () => {
  const M = () => row('Meltan', 150);
  const m = mergeClips([clip('01.mp4', [row('X', 1), M(), M()]), clip('02.mp4', [M(), M(), row('Y', 2)])]);
  const flaggedRows = (name) => m.rows.filter((r) => r.clip === name && r.flags.length).length;
  assert.deepEqual(m.clips.map((c) => c.flagged), [flaggedRows('01.mp4'), flaggedRows('02.mp4')]);
  assert.ok(m.clips[0].flagged > 0);
});
