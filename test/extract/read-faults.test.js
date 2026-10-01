// Reading faults found on the 1 Oct 2026 Voice Control test clips: Nidoran's gender symbol, a
// green type-icon row taken for the HP bar (Paras), an HP read cut short by the iPad's team
// leader, and a CP partly or wholly hidden behind a tall model (Moltres, Zapdos).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { displayNames, matchName, nameAndForm } from '../../src/extract/names.js';
import { parseHp } from '../../src/extract/ocr.js';
import { makeImage, fillRect } from '../../src/extract/image.js';
import { findHpBar } from '../../src/extract/layout.js';
import { groupRuns } from '../../src/extract/merge.js';
import { finish, cpOptions, supportedNames } from '../../src/extract/pipeline.js';
import { cpAt, hpAt } from '../../src/cpm.js';
import { loadGamemaster } from '../../src/node/load.js';

const gm = loadGamemaster();
const names = displayNames(gm);
const find = (display) => names.find((n) => n.display === display);

test('both Nidoran share one display name and export under Poke Genie names', () => {
  assert.deepEqual([...find('Nidoran').speciesIds].sort(), ['nidoran_female', 'nidoran_male']);
  assert.equal(nameAndForm(gm.byId.get('nidoran_female')).name, 'Nidoran♀');
  assert.equal(nameAndForm(gm.byId.get('nidoran_male')).name, 'Nidoran♂');
});

test('matchName reads Nidoran with its symbol dropped or misread, and still tells Nidorino and Nidorina apart', () => {
  for (const text of ['Nidoran', 'Nidorano', 'Nidoran 9', 'Nidoran .']) {
    const m = matchName(text, names);
    assert.equal(m.candidate.display, 'Nidoran', text);
    assert.equal(m.distance, 0, text);
  }
  assert.equal(matchName('Nidorino', names).candidate.display, 'Nidorino');
  assert.equal(matchName('Nidorina', names).candidate.display, 'Nidorina');
});

test('parseHp rejects a read whose current is above its max (the end of the text was covered)', () => {
  assert.equal(parseHp('139 / 13'), null);
  assert.equal(parseHp('130/13'), null);
  assert.deepEqual(parseHp('100 / 139 HP'), { current: 100, max: 139 }); // a damaged Pokémon is still a read
});

test('findHpBar takes the long bar, not a taller row of green type icons or a green background strip', () => {
  const W = 660, H = 1434, green = [80, 220, 150];
  const img = makeImage(W, H);
  fillRect(img, { x: 0, y: 0, w: W, h: H }, [255, 255, 255]);
  fillRect(img, { x: 0, y: 0, w: 14, h: H }, [60, 160, 40]);            // grass background beside the card
  fillRect(img, { x: 165, y: 645, w: 330, h: 9 }, green);               // the HP bar
  fillRect(img, { x: 180, y: 759, w: 60, h: 13 }, green);               // Bug and Grass type icons: a taller band,
  fillRect(img, { x: 260, y: 759, w: 60, h: 13 }, green);               // two runs, each long enough to count
  const bar = findHpBar(img, { x: 0, y: 0, w: W, h: H });
  assert.deepEqual(bar, { y0: 645, y1: 654, x0: 165, x1: 495 });
});

// Readings as readFrame returns them, for a real species so the solver has stats to work with.
const moltres = gm.byId.get('moltres');
const IVS = { atk: 11, def: 14, hp: 11 };
const LEVEL = 25;
const CP = cpAt(moltres.baseStats, IVS, LEVEL), HP = hpAt(moltres.baseStats, IVS, LEVEL);
const frame = (cp, { hp = HP, ivs = IVS, name = 'Moltres', n = 0 } = {}) => ({
  frame: `f${n}`, time: n / 5, name, nameText: name, baseName: name, form: '', speciesIds: find(name).speciesIds,
  cp, cpReads: cp ? [cp] : [], cpText: cp ? String(cp) : '', hp: hp ? { current: hp, max: hp } : null,
  ivs, ivConfidence: ivs ? 0.95 : 0, sharpness: 1, flags: cp ? [] : ['no-cp-text'],
});

const swipe = { frame: 'swipe', name: null, cp: null, flags: ['mid-swipe'] };

test('frames with the CP hidden never join or split a run: rows are built as if they were unreadable', () => {
  assert.equal(groupRuns([frame(null, { n: 1 }), frame(null, { n: 2 })]).length, 0);
  const runs = groupRuns([frame(CP, { n: 1 }), frame(null, { n: 2 }), frame(CP, { n: 3 })]);
  assert.equal(runs.length, 1);
  assert.equal(runs[0].frames.length, 2);
  // The same Pokémon with its model in front of the CP for two frames, between unreadable frames:
  // one row, as before these frames were read at all (a second, identical row would be a
  // duplicate nobody could tell from a real twin).
  const { rows } = finish([...[1, 2, 3].map((n) => frame(CP, { n })), swipe, frame(null, { n: 5 }), frame(null, { n: 6 }), swipe, ...[8, 9, 10].map((n) => frame(CP, { n }))], gm);
  assert.deepEqual(rows.map((r) => [r.cp, r.flags]), [[CP, []]]);
});

test('a hidden-CP frame of the next Pokémon sliding in does not pull two Pokémon into one row', () => {
  // The whatsapp fixture's Charizards: 1613 with bars not yet settled, then a frame with no CP text
  // that already shows the next Charizard's HP and settled bars, then that Charizard (1608).
  const zard = (cp, n, o = {}) => ({ ...frame(cp, { name: 'Charizard', hp: 118, ivs: { atk: 10, def: 15, hp: 13 }, n, ...o }) });
  const unsettled = (cp, n) => ({ ...zard(cp, n), ivConfidence: 0.6 });
  const { rows, unmatched } = finish([unsettled(1613, 1), unsettled(1613, 2), zard(null, 3), zard(1608, 4), zard(1608, 5)], gm);
  assert.deepEqual(rows.map((r) => r.cp), [1613, 1608]);
  assert.equal(unmatched.length, 0); // the sliding frame sits right beside its own Pokémon's run
});

test('a hidden-CP stretch right beside a run of the same Pokémon is that Pokémon, not an entry', () => {
  const after = finish([frame(CP, { n: 1 }), frame(CP, { n: 2 }), frame(null, { n: 3 }), frame(null, { n: 4 })], gm);
  assert.equal(after.rows.length, 1);
  assert.equal(after.unmatched.length, 0);
  const before = finish([frame(null, { n: 1 }), frame(CP, { n: 2 }), frame(CP, { n: 3 })], gm);
  assert.equal(before.unmatched.length, 0);
  // Different settled bars next to a run say it is another Pokémon: listed.
  const other = finish([frame(CP, { n: 1 }), frame(CP, { n: 2 }), frame(null, { ivs: { atk: 1, def: 2, hp: IVS.hp }, n: 3 }), frame(null, { ivs: { atk: 1, def: 2, hp: IVS.hp }, n: 4 })], gm);
  assert.equal(other.unmatched.length, 1);
  // A hidden Pokémon whose HP was never read is still listed.
  const noHp = finish([frame(null, { hp: null, n: 1 }), frame(null, { hp: null, n: 2 })], gm);
  assert.deepEqual(noHp.unmatched.map((u) => [u.name, u.hp, u.reason, u.frames]), [['Moltres', null, 'cp-not-read', 2]]);
});

test('a hidden-CP Pokémon followed by its twin with a visible CP is listed, not merged away', () => {
  const { rows, unmatched } = finish([frame(null, { n: 1 }), frame(null, { n: 2 }), swipe, frame(CP, { n: 4 }), frame(CP, { n: 5 })], gm);
  assert.deepEqual(rows.map((r) => r.cp), [CP]);
  assert.deepEqual(unmatched.map((u) => [u.name, u.cp, u.hp, u.reason, u.frames]), [['Moltres', null, HP, 'cp-not-read', 2]]);
});

test('cpOptions lists the CPs that fit the HP and bars, and which of them a partial read is the tail of', () => {
  const { options, supported, tailOf } = cpOptions([moltres], { hp: HP, ivs: IVS, ivConfidence: 0.95 }, [CP % 1000, CP % 100]);
  assert.ok(options.includes(CP));
  assert.deepEqual(supported, [CP]);
  assert.equal(tailOf.get(CP), CP % 1000);
  assert.deepEqual(cpOptions([moltres], { hp: HP, ivs: IVS, ivConfidence: 0.3 }, []).options, []); // unsettled bars prove nothing
});

test('a CP whose leading digit is hidden is recovered from the HP, the bars and the digits that were read', () => {
  const tail = CP % 1000;
  assert.ok(CP >= 1000 && tail >= 100, 'the example needs a four-digit CP');
  const { rows } = finish([1, 2, 3, 4, 5].map((n) => frame(tail, { n })), gm);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].cp, CP);
  assert.deepEqual(rows[0].ivs, IVS);
  assert.deepEqual(rows[0].flags, [`cp-recovered:${CP}-from-${tail}`]);
});

test('a CP read in full that does not fit is never replaced by a recovered one', () => {
  // The bars are misread (so the full read does not solve) and one frame dropped a digit; the
  // dropped-digit read must not pick a CP built from the wrong bars.
  const wrongBars = { atk: IVS.atk + 2, def: IVS.def, hp: IVS.hp };
  const { options } = cpOptions([moltres], { hp: HP, ivs: wrongBars }, []);
  const decoy = options[0];
  assert.ok(decoy && decoy !== CP, 'the wrong bars give another CP');
  const { rows } = finish([...[1, 2, 3].map((n) => frame(CP, { ivs: wrongBars, n })), frame(decoy % 1000, { ivs: wrongBars, n: 4 })], gm);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].cp, CP);
  assert.ok(!rows[0].flags.some((f) => f.startsWith('cp-recovered')));
});

test('any full-length read in the run blocks recovery, even one frame against several short reads', () => {
  const wrongBars = { atk: IVS.atk + 2, def: IVS.def, hp: IVS.hp };
  const decoy = cpOptions([moltres], { hp: HP, ivs: wrongBars }, []).options[0];
  const tail = decoy % 100;
  assert.ok(tail >= 10);
  const { rows } = finish([frame(CP, { ivs: wrongBars, n: 1 }), ...[2, 3, 4].map((n) => frame(tail, { ivs: wrongBars, n }))], gm);
  assert.ok(rows.every((r) => !r.flags.some((f) => f.startsWith('cp-recovered'))));
  assert.ok(rows.every((r) => r.cp !== decoy));
});

test('frames with a CP but no species name are listed once per Pokémon, and a lone frame is not', () => {
  const nick = (cp, n) => ({ frame: `f${n}`, time: n / 5, name: null, nameText: 'Firebird', cp, cpReads: [cp], cpText: String(cp), hp: null, ivs: null, ivConfidence: 0, sharpness: 1, flags: ['name-unmatched'] });
  const { rows, unmatched } = finish([nick(2409, 1), nick(2409, 2), nick(2409, 3), swipe, ...[5, 6, 7].map((n) => frame(CP, { n })), swipe, nick(1500, 9)], gm);
  assert.equal(rows.length, 1);
  assert.deepEqual(unmatched.map((u) => [u.cp, u.nameText, u.frames, u.reason]), [[2409, 'Firebird', 3, 'name-not-read']]);
});

test('a Nidoran with no bars read is exported as the one that fits, not the first in the list', () => {
  const male = gm.byId.get('nidoran_male');
  const ivs = { atk: 9, def: 10, hp: 13 };
  const cp = cpAt(male.baseStats, ivs, 20), hp = hpAt(male.baseStats, ivs, 20);
  const { rows } = finish([1, 2, 3].map((n) => frame(cp, { name: 'Nidoran', hp, ivs: null, n })), gm);
  assert.equal(rows.length, 1);
  const femaleFits = rows[0].flags.some((f) => f.startsWith('form-ambiguous'));
  assert.ok(rows[0].speciesId === 'nidoran_male' || femaleFits, `${rows[0].speciesId} ${rows[0].flags}`);
});

test('a wholly hidden CP never becomes a row: it is listed with the CPs its HP and bars allow', () => {
  const before = [0, 1].map((n) => frame(CP + 9, { hp: HP + 1, ivs: null, n })), after = [8, 9].map((n) => frame(CP - 9, { hp: HP - 1, ivs: null, n }));
  const { rows, unmatched } = finish([...before, swipe, frame(null, { n: 3 }), frame(null, { n: 4 }), frame(null, { n: 5 }), swipe, ...after], gm);
  assert.deepEqual(rows.map((r) => r.cp), [CP + 9, CP - 9]);
  assert.deepEqual(rows.map((r) => r.index), [1, 2]);
  assert.equal(unmatched.length, 1);
  assert.deepEqual([unmatched[0].name, unmatched[0].cp, unmatched[0].hp, unmatched[0].reason, unmatched[0].frames], ['Moltres', null, HP, 'cp-not-read', 3]);
  assert.deepEqual(unmatched[0].ivs, IVS);
  assert.ok(unmatched[0].cpOptions.includes(CP));
  // One Pokémon seen on both sides of an unreadable frame is one entry, not two.
  const split = finish([frame(null, { n: 1 }), frame(null, { n: 2 }), swipe, frame(null, { n: 4 })], gm);
  assert.equal(split.rows.length, 0);
  assert.deepEqual(split.unmatched.map((u) => u.frames), [3]);
  // Two hidden Pokémon with the same HP and different settled bars stay two entries.
  const other = { atk: 1, def: 2, hp: IVS.hp };
  const two = finish([frame(null, { n: 1 }), frame(null, { n: 2 }), swipe, frame(null, { ivs: other, n: 4 }), frame(null, { ivs: other, n: 5 })], gm);
  assert.equal(two.unmatched.length, 2);
});

test('a one-frame row with nothing but a similar CP is folded into its neighbour and listed', () => {
  // The frame before the screen settles: the whole CP is visible but one digit is misread and the
  // HP and bars are not drawn yet; then the model moves in front of the leading digit.
  const wrong = CP % 10 === 9 ? CP - 1 : CP + 1, tail = CP % 1000;
  const early = frame(wrong, { hp: null, ivs: null, n: 0 });
  const { rows, unmatched } = finish([early, ...[1, 2, 3, 4].map((n) => frame(tail, { n }))], gm);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].cp, CP);
  assert.equal(rows[0].frames.length, 5);
  assert.deepEqual(unmatched.map((u) => [u.name, u.cp, u.reason, u.into]), [['Moltres', wrong, 'absorbed', CP]]);
  // A one-frame row whose HP was read, or whose bars were read settled, is a Pokémon in its own
  // right and stays.
  const withHp = finish([frame(wrong, { hp: HP + 2, ivs: null, n: 0 }), ...[1, 2, 3, 4].map((n) => frame(tail, { n }))], gm);
  assert.equal(withHp.rows.length, 2);
  const withBars = finish([frame(wrong, { hp: null, ivs: { atk: 1, def: 0, hp: 0 }, n: 0 }), swipe, ...[2, 3, 4, 5].map((n) => frame(tail, { n }))], gm);
  assert.equal(withBars.rows.length, 2);
  assert.equal(withBars.unmatched.length, 0);
});

test('matchName says whether the whole text matched, so a dropped word cannot pass without confidence', () => {
  assert.equal(matchName('Rattata', names).whole, true);
  assert.equal(matchName('Rattata .', names).whole, true);          // the pencil icon read as a dot
  assert.equal(matchName('Rattata a', names).whole, true);          // or as a letter
  const lead = matchName('x Rattata', names);                        // what is left of "Alolan"
  assert.ok(!(lead.distance === 0 && lead.whole));
  const dropped = matchName('Aloan Rattata', names);
  assert.ok(!(dropped.distance === 0 && dropped.whole), 'an exact match on a part of the text is not a whole match');
});

test('recovery needs exactly one candidate CP with a read as its tail, and a tail of two digits or more', () => {
  // A species, bars and HP that two levels share, so there are two candidate CPs.
  let found = null;
  for (const sp of gm.byId.values()) {
    if (found || sp.speciesId.includes('_') || !sp.baseStats) continue;
    const ivs = { atk: 7, def: 7, hp: 7 };
    for (const hp of [20, 25, 30, 35, 40]) {
      const { options } = cpOptions([sp], { hp, ivs }, []);
      if (options.length === 2 && options.every((c) => c >= 100 && c % 100 >= 10) && options[0] % 100 !== options[1] % 100) { found = { sp, ivs, hp, options }; break; }
    }
  }
  assert.ok(found, 'a species with two levels at one HP');
  const { sp, ivs, hp, options } = found;
  const display = names.find((n) => n.speciesIds.includes(sp.speciesId)).display;
  const f = (cp, n) => frame(cp, { name: display, hp, ivs, n });
  const both = finish([f(options[0] % 100, 1), f(options[0] % 100, 2), f(options[1] % 100, 3), f(options[1] % 100, 4)], gm);
  assert.ok(both.rows.every((r) => !r.flags.some((x) => x.startsWith('cp-recovered'))), 'two candidates fit the reads: none is taken');
  const one = finish([1, 2, 3].map((n) => f(options[0] % 100, n)), gm);
  assert.deepEqual(one.rows.map((r) => [r.cp, r.flags.filter((x) => x.startsWith('cp-'))]), [[options[0], [`cp-recovered:${options[0]}-from-${options[0] % 100}`]]]);
  assert.deepEqual(cpOptions([sp], { hp, ivs }, [options[0] % 10]).supported, [], 'one digit is not evidence');
});

test('absorbStrays leaves alone a one-frame row of another species or with an unrelated CP, and works in both directions', () => {
  const tail = CP % 1000, wrong = CP % 10 === 9 ? CP - 1 : CP + 1;
  const run = (from) => [0, 1, 2, 3].map((k) => frame(tail, { n: from + k }));
  const lone = (o) => frame(wrong, { hp: null, ivs: null, n: 9, ...o });
  // After the run instead of before it.
  const after = finish([...run(1), lone()], gm);
  assert.equal(after.rows.length, 1);
  assert.deepEqual(after.unmatched.map((u) => [u.cp, u.reason, u.into]), [[wrong, 'absorbed', CP]]);
  // Another species with a similar CP is not this Pokémon.
  const zapdos = finish([...run(1), lone({ name: 'Zapdos' })], gm);
  assert.equal(zapdos.rows.length, 2);
  assert.equal(zapdos.unmatched.length, 0);
  // Nor is the same species with a CP that is not a one-digit misread.
  const far = finish([...run(1), frame(CP - 333, { hp: null, ivs: null, n: 9 })], gm);
  assert.equal(far.rows.length, 2);
  assert.equal(far.unmatched.length, 0);
});

test('a hidden-CP stretch is listed when its HP or name differs from the run beside it, or a swipe lies between', () => {
  const run = [1, 2].map((n) => frame(CP, { n }));
  const listed = (hidden) => finish([...run, ...hidden], gm).unmatched.filter((u) => u.reason === 'cp-not-read').length;
  assert.equal(listed([frame(null, { n: 3 }), frame(null, { n: 4 })]), 0);
  assert.equal(listed([frame(null, { hp: HP + 1, n: 3 }), frame(null, { hp: HP + 1, n: 4 })]), 1);
  assert.equal(listed([frame(null, { name: 'Zapdos', n: 3 }), frame(null, { name: 'Zapdos', n: 4 })]), 1);
  assert.equal(listed([swipe, frame(null, { n: 4 }), frame(null, { n: 5 })]), 1);
});

test('unnamed frames with unrelated CPs are separate entries', () => {
  const nick = (cp, n) => ({ frame: `f${n}`, name: null, nameText: 'Buddy', cp, cpReads: [cp], cpText: String(cp), hp: null, ivs: null, ivConfidence: 0, flags: ['name-unmatched'] });
  const { unmatched } = finish([nick(2409, 1), nick(2409, 2), nick(1500, 3), nick(1500, 4)], gm);
  assert.deepEqual(unmatched.map((u) => [u.cp, u.frames]), [[2409, 2], [1500, 2]]);
});

test('a name read without confidence counts only when a neighbouring frame agrees', () => {
  const weak = (r) => ({ ...r, nameWeak: true });
  // One "Paras" frame in the middle of a Parasect: unnamed, so it cannot split the run.
  const sect = (n) => frame(1531, { name: 'Parasect', hp: 118, ivs: null, n });
  const gated = supportedNames([sect(1), sect(2), weak(frame(1531, { name: 'Paras', hp: 118, ivs: null, n: 3 })), sect(4), sect(5)]);
  assert.deepEqual(gated.map((r) => r.name), ['Parasect', 'Parasect', null, 'Parasect', 'Parasect']);
  assert.ok(gated[2].flags.includes('name-unsupported'));
  assert.equal(finish([sect(1), sect(2), weak(frame(1531, { name: 'Paras', hp: 118, ivs: null, n: 3 })), sect(4), sect(5)], gm).rows.length, 1);
  // Weak frames that agree with each other stay, and the row says how its name was read.
  const all = finish([1, 2, 3].map((n) => weak(frame(CP, { n }))), gm);
  assert.deepEqual(all.rows.map((r) => [r.cp, r.flags]), [[CP, ['name-low-confidence']]]);
  // A weak frame next to a confident one of the same name is ordinary.
  const mixed = finish([frame(CP, { n: 1 }), weak(frame(CP, { n: 2 })), frame(CP, { n: 3 })], gm);
  assert.deepEqual(mixed.rows.map((r) => [r.cp, r.flags]), [[CP, []]]);
});

test('one garbled frame in the middle of a Pokémon does not leave it in the export twice', () => {
  const garbled = frame(312, { hp: null, ivs: null, n: 3 });
  const { rows, unmatched } = finish([frame(CP, { n: 1 }), frame(CP, { n: 2 }), garbled, frame(CP, { n: 4 }), frame(CP, { n: 5 })], gm);
  assert.deepEqual(rows.map((r) => [r.cp, r.frames.length, r.flags]), [[CP, 5, []]]);
  assert.deepEqual(unmatched.map((u) => [u.cp, u.reason, u.into]), [[312, 'absorbed', CP]]);
  // Two different solved Pokémon either side are not halves of one: nothing is folded.
  const other = { atk: 1, def: 2, hp: 3 };
  const cp2 = cpAt(moltres.baseStats, other, LEVEL), hp2 = hpAt(moltres.baseStats, other, LEVEL);
  const apart = finish([frame(CP, { n: 1 }), frame(CP, { n: 2 }), garbled, frame(cp2, { hp: hp2, ivs: other, n: 4 }), frame(cp2, { hp: hp2, ivs: other, n: 5 })], gm);
  assert.equal(apart.rows.length, 3);
});

test('every Nidoran row says its sex came from the stats', () => {
  const female = gm.byId.get('nidoran_female');
  const ivs = { atk: 1, def: 9, hp: 12 };
  const cp = cpAt(female.baseStats, ivs, 20), hp = hpAt(female.baseStats, ivs, 20);
  const { rows } = finish([1, 2, 3].map((n) => frame(cp, { name: 'Nidoran', hp, ivs, n })), gm);
  assert.equal(rows[0].name, 'Nidoran♀');
  assert.ok(rows[0].flags.includes('sex-from-stats'));
});
