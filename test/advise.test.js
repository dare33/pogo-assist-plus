import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadGamemaster, loadTiers, loadRankings } from '../src/node/load.js';
import { analyseBox, FIT_IV_PCT } from '../src/advise.js';

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
  // A Shadow's power-ups round up per step (1.2x in float32 for dust): the shadow Beldum build pins the rule in the advisor too.
  const beldum = out.builds.find((b) => b.speciesId === 'beldum_shadow' && b.targetId === 'metagross_shadow');
  assert.ok(beldum, 'shadow Beldum -> Metagross build');
  assert.equal(beldum.cost.dust, 197772);
  assert.equal(beldum.cost.candy, 335);
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

const template = box.find((p) => !p.shadow && !p.purified && !p.lucky && (!p.form || p.form === 'Normal'));
const one = (name, o = {}) => analyseBox([{ ...template, name, form: '', pvp: undefined, ...o }], ctx);
const buildTo = (res, target) => res.builds.find((b) => b.targetId === target);

// A build is rated by its target's own option, not by the shown pick: Eevee 134 (level 17) has Flareon as the shown pick in Great
// League, yet the Umbreon build is rated, costed and valued from Umbreon's option; the same for Mankey 149, shown as Mankey.
for (const [index, target] of [[134, 'umbreon'], [149, 'annihilape']]) {
  test(`league builds are rated by the build target's OWN option, even when it is not the shown pick (fixture index ${index} -> ${target})`, () => {
    const p = box.find((x) => x.index === index);
    const res = analyseBox([{ ...p, pvp: undefined }], ctx);
    const L = res.pokemon[0].leagues.gl;
    const b = buildTo(res, target);
    assert.ok(b.areas.includes('gl'));
    assert.notEqual(L.options[L.pick].speciesId, target, 'the target is not the shown pick');
    assert.equal(b.pvpCost.league, 'gl');
    const own = L.options.find((o) => o.speciesId === target);
    assert.equal(b.pvpCost.rankPct, own.iv.rankPct);
    assert.equal(b.pvpCost.dust, own.cost.dust);
    assert.equal(b.pvpCost.candy, own.cost.candy + own.cost.evolveCandy);
    assert.equal(b.pvpCost.xl, own.cost.xl);
    // The Great League chip is weighted from that option's Rank %, not the neutral 0.6 (a tier-weighted sum, so just check the
    // build is worth more than the same build with the option's rating removed).
    const neutral = analyseBox([{ ...p, pvp: undefined, ivs: null }], ctx);
    assert.equal(buildTo(neutral, target).pvpCost, null);
    assert.notEqual(buildTo(neutral, target).value, b.value);
  });
}

test('across the fixture box, many league builds carry a league cost, none from Master League', () => {
  const withCost = out.builds.filter((b) => b.pvpCost);
  assert.ok(withCost.length >= 20, `${withCost.length} builds carry a league cost`);
  for (const b of withCost) {
    assert.ok(['gl', 'ul'].includes(b.pvpCost.league), b.pvpCost.league);
    assert.ok(b.pvpCost.rankPct >= 0 && b.pvpCost.rankPct <= 100);
  }
  // Builds do not depend on Poke Genie's columns at all: a scan scores identically.
  const scan = analyseBox(box.map((p) => ({ ...p, pvp: undefined })), ctx);
  const sig = (o) => o.builds.map((b) => [b.speciesId, b.targetId, b.value, b.score, b.pvpCost, b.cost]);
  assert.deepEqual(sig(scan), sig(out));
});

test('a copy already past the league cap as the target has no league there: Rookidee L35 -> Corviknight is Ultra only, and ranks below a usable L5 copy', () => {
  const rookidee = (level) => one('Rookidee', { level, levelMin: level, levelMax: level, ivs: { atk: 10, def: 12, hp: 14 } });
  const high = rookidee(35), low = rookidee(5);
  const gl35 = high.pokemon[0].leagues.gl.options.find((o) => o.speciesId === 'corviknight');
  assert.equal(gl35.overCap, true, "level 35 is past Corviknight's Great League level");
  const b35 = buildTo(high, 'corviknight'), b5 = buildTo(low, 'corviknight');
  assert.deepEqual(b35.areas, ['ul']);
  assert.ok(b35.hits.every((h) => h.area !== 'gl'));
  assert.equal(b35.pvpCost.league, 'ul');
  assert.deepEqual(b5.areas, ['gl', 'ul']);
  assert.equal(b35.value, 1.49);
  assert.equal(b5.value, 3.13);
  assert.ok(b5.value > b35.value && b5.score > b35.score);
});

test('a build whose every league is past the cap is dropped (fixture Swablu, index 205, level 28, Altaria)', () => {
  const swablu = box.find((p) => p.index === 205);
  assert.equal(swablu.name, 'Swablu');
  const res = analyseBox([{ ...swablu, pvp: undefined }], ctx);
  const L = res.pokemon[0].leagues.gl;
  assert.equal(L.options.find((o) => o.speciesId === 'altaria').overCap, true);
  assert.equal(buildTo(res, 'altaria'), undefined);
  assert.equal(res.builds.length, 0);
  assert.ok(!out.builds.some((b) => b.pokemon.index === 205 && b.targetId === 'altaria'));
});

test('Master League keeps the neutral weight 0.6 and is never the cost league (a hundo Melmetal at level 10)', () => {
  const res = one('Melmetal', { level: 10, levelMin: 10, levelMax: 10, ivs: { atk: 15, def: 15, hp: 15 } });
  const b = buildTo(res, 'melmetal');
  assert.deepEqual(b.areas, ['gl', 'ul', 'ml']);
  assert.ok(!b.pvpCost || b.pvpCost.league !== 'ml');
  // value = sum of tier weight x area weight x league quality. GL and UL are S tier (3) with their own Rank %; ML is B tier (1) at 0.6.
  const L = res.pokemon[0].leagues;
  const q = (a) => { const o = L[a].options.find((x) => x.speciesId === 'melmetal'); return 0.15 + 0.85 * (o.iv.rankPct / 100) ** 2; };
  assert.ok(Math.abs(b.value - (3 * q('gl') + 3 * q('ul') + 1 * 0.6)) < 0.006, `${b.value}`);
  // Unknown IVs: every league is neutral, so 3 x 0.6 + 3 x 0.6 + 1 x 0.6.
  const unknown = buildTo(one('Melmetal', { level: 10, levelMin: 10, levelMax: 10, ivs: null }), 'melmetal');
  assert.equal(unknown.value, 4.2);
  assert.ok(b.cost.dust < 400000, `${b.cost.dust} dust`);
});

test("a league build is weighted by this copy's Rank % as Our pick, and neutrally (0.6) when the IVs are unknown", () => {
  const mk = (ivs) => ({ ...box.find((p) => p.name === 'Tinkatink'), ivs, pvp: undefined, ivPercent: 80 });
  const val = (ivs) => analyseBox([mk(ivs)], ctx).builds.find((b) => b.targetId === 'tinkaton');
  const good = val({ atk: 0, def: 15, hp: 15 }), bad = val({ atk: 15, def: 0, hp: 0 }), unknown = val(null);
  assert.ok(good.pvpCost && bad.pvpCost);
  assert.ok(good.pvpCost.rankPct > bad.pvpCost.rankPct);
  assert.ok(good.value > bad.value);
  assert.equal(unknown.pvpCost, null);
  assert.ok(unknown.value > bad.value && unknown.value < good.value);
});

test('unknown IVs do not hide an over-cap target: a level-35 Rookidee without IVs ranks below a usable L5 copy for Corviknight', () => {
  const mk = (level, ivs) => ({ ...template, name: 'Rookidee', form: '', pvp: undefined, level, levelMin: level, levelMax: level, ivs });
  const res = analyseBox([mk(35, null), mk(5, { atk: 10, def: 12, hp: 14 })], ctx);
  const all = res.allBuilds.filter((b) => b.targetId === 'corviknight');
  const old = all.find((b) => b.pokemon.level === 35), fresh = all.find((b) => b.pokemon.level === 5);
  assert.ok(!old.areas.includes('gl'));
  assert.ok(fresh.areas.includes('gl'));
  assert.ok(fresh.value > old.value && fresh.score > old.score);
  assert.ok(!fresh.duplicate && old.duplicate, 'the usable copy carries the build');
});

test('level 51 Best Buddy copies keep Ultra League when their CP fits (Cramorant, Seaking) and lose it when it does not (Talonflame)', () => {
  const hundo51 = (name) => one(name, { level: 51, levelMin: 51, levelMax: 51, ivs: { atk: 15, def: 15, hp: 15 } });
  for (const [name, id] of [['Cramorant', 'cramorant'], ['Seaking', 'seaking']]) assert.ok(buildTo(hundo51(name), id)?.areas.includes('ul'), name);
  assert.ok(!buildTo(hundo51('Talonflame'), 'talonflame')?.areas.includes('ul'));
});

test('a build never carries a target level at or below the copy\'s own level (a level-51 copy that fits is already at its best level)', () => {
  for (const b of out.allBuilds) assert.ok(b.targetLevel == null || b.targetLevel > b.level, `${b.speciesId}->${b.targetId} L${b.level} -> ${b.targetLevel}`);
  const res = one('Cramorant', { level: 51, levelMin: 51, levelMax: 51, ivs: { atk: 15, def: 15, hp: 15 } });
  const b = buildTo(res, 'cramorant');
  assert.ok(b.areas.includes('ul'));
  assert.equal(b.targetLevel, null);
  assert.equal(b.cost.dust - b.cost.secondMove.dust, 0, "no power-up dust");
  // A copy above an area's target level (a level-38 power-up for a Gym target of 30) shows none either, with the cost still zero.
  const high = analyseBox([{ ...template, name: 'Cramorant', form: '', pvp: undefined, level: 38, levelMin: 38, levelMax: 38, ivs: { atk: 15, def: 15, hp: 15 } }], ctx);
  for (const x of high.allBuilds) assert.ok(x.targetLevel == null || x.targetLevel > 38);
});

test('a copy above the only area\'s target level has no target level and nothing to power up (raids only, level 45)', () => {
  const b = buildTo(one('Xurkitree', { level: 45, levelMin: 45, levelMax: 45, ivs: { atk: 15, def: 15, hp: 15 } }), 'xurkitree');
  assert.deepEqual(b.areas, ['raids']);
  assert.equal(b.targetLevel, null);
  assert.equal(b.pvpCost, null);
  assert.equal(b.cost.dust - b.cost.secondMove.dust, 0);
  assert.ok(!b.steps.some((x) => x.kind === 'powerUp'));
});

// ---- one copy, several builds (the Pokémon page's Advice panel lists every build a copy carries, best first) ----
const copy = (name, level, ivs) => {
  const proto = box[0];
  return { ...proto, name, form: 'Normal', cp: 300, level, ivs, ivPercent: Math.round(((ivs.atk + ivs.def + ivs.hp) / 45) * 1000) / 10, shadow: false, purified: false };
};

test('a copy with several targets carries one build per target, best score first', () => {
  const eevee = analyseBox([copy('Eevee', 20, { atk: 10, def: 12, hp: 11 })], ctx).builds;
  assert.ok(eevee.length >= 2, `Eevee should carry several builds, got ${eevee.map((b) => b.targetId).join(', ')}`);
  assert.equal(new Set(eevee.map((b) => b.targetId)).size, eevee.length, 'one build per target');
  for (let i = 1; i < eevee.length; i++) assert.ok(eevee[i - 1].score >= eevee[i].score, 'best first');
});

test('a league build for a target the copy is already over the cap for is dropped', () => {
  const targets = (level) => analyseBox([copy('Duskull', level, { atk: 10, def: 12, hp: 11 })], ctx).builds.map((b) => b.targetId);
  assert.ok(targets(20).includes('dusclops'), 'a low-level Duskull still has the Great League Dusclops build');
  assert.ok(!targets(40).includes('dusclops'), 'at level 40 Dusclops is over the Great League cap: no build left, so none shown');
  assert.ok(targets(40).includes('dusknoir'), 'the Ultra League Dusknoir build stays');
});

test('a Pokémon with no league-viable target carries only its other areas (Abra: Alakazam raids, not GL/UL/ML)', () => {
  const abra = analyseBox([copy('Abra', 17, { atk: 0, def: 14, hp: 15 })], ctx).builds;
  assert.deepEqual(abra.map((b) => [b.targetId, b.areas]), [['alakazam', ['raids']]]);
});

// ---- fit and bestOf: Strong / OK / Weak per copy and non-league area ----
const cp = (name, atk, def, hp, o = {}) => ({ ...copy(name, 20, { atk, def, hp }), pvp: undefined, ...o });
const fitOf = (boxCopies) => analyseBox(boxCopies, ctx).pokemon.map((e) => e.fit);
const HUNDO = [15, 15, 15], GOOD = [13, 13, 13], LOW = [10, 10, 10]; // 100%, 86.7%, 66.7%

test('fit: a copy whose own build lists the area is strong, named for that build\'s target and best tier there', () => {
  const res = analyseBox([cp('Charmander', ...HUNDO)], ctx);
  const f = res.pokemon[0].fit.rocket, b = res.builds.find((x) => x.areas.includes('rocket'));
  assert.deepEqual(f, { tag: 'strong', as: b.targetName, tier: 'A', line: `Rocket A as ${b.targetName}` });
  assert.equal(f.as, 'Charizard');
});

test('fit: a spare copy is ok through an evolution when decently rolled, weak when not, and the weak line says why', () => {
  const [top, spare, poor] = fitOf([cp('Charmander', ...HUNDO), cp('Charmander', ...GOOD), cp('Charmander', ...LOW)]);
  assert.equal(top.rocket.tag, 'strong');
  assert.deepEqual(spare.rocket, { tag: 'ok', as: 'Charizard', tier: 'A', line: 'Rocket A as Charizard' });
  assert.deepEqual(poor.rocket, { tag: 'weak', as: null, tier: null, line: 'IVs 66.7%, below 80%' });
  assert.equal(spare.gym.tag, 'weak');
  assert.equal(spare.gym.line, 'No table entry for Charmander in Gym');
});

test('fit: the IV threshold is FIT_IV_PCT (80 is ok, 79 is weak) and unknown IVs never qualify', () => {
  assert.equal(FIT_IV_PCT, 80);
  // 36/45 = 80%, 35/45 = 77.8%: the export's own IV average is what is compared, so pin it directly too.
  const at = (pct) => cp('Charmander', 12, 12, 12, { ivPercent: pct });
  const [, eighty, seventyNine, unknown] = fitOf([cp('Charmander', ...HUNDO), at(80), at(79.9), cp('Charmander', 15, 15, 15, { ivs: null })]);
  assert.equal(eighty.rocket.tag, 'ok');
  assert.equal(seventyNine.rocket.tag, 'weak');
  assert.equal(seventyNine.rocket.line, 'IVs 79.9%, below 80%');
  assert.deepEqual(unknown.rocket, { tag: 'weak', as: null, tier: null, line: 'IVs not known' });
});

test('fit: a Mega entry counts for a non-Shadow copy of its base species, not for a Shadow copy', () => {
  const plain = fitOf([cp('Fennekin', ...HUNDO), cp('Fennekin', ...GOOD)])[1];
  assert.deepEqual(plain.raids, { tag: 'ok', as: 'Mega Delphox', tier: 'S', line: 'Raids S as Mega Delphox' });
  const shadow = fitOf([cp('Fennekin', ...HUNDO, { shadow: true }), cp('Fennekin', ...GOOD, { shadow: true })]);
  for (const f of shadow) assert.equal(f.raids.tag, 'weak', 'a Shadow copy cannot Mega evolve, however well rolled');
  assert.equal(shadow[1].raids.line, 'No table entry for Fennekin in Raids');
});

test('fit: a Shadow-only entry counts for a Shadow copy and not for a plain one; a plain entry counts for both', () => {
  const sh = fitOf([cp('Reshiram', ...HUNDO, { shadow: true }), cp('Reshiram', ...GOOD, { shadow: true })]);
  assert.equal(sh[0].raids.tag, 'strong');
  assert.equal(sh[1].raids.tag, 'ok');
  assert.equal(sh[1].raids.as, 'Shadow Reshiram');
  const plain = fitOf([cp('Reshiram', ...HUNDO), cp('Reshiram', ...GOOD)]);
  for (const f of plain) assert.equal(f.raids.tag, 'weak', 'no plain Reshiram raid entry');
  // Charmander's plain Rocket Charizard entry serves its Shadow copies too.
  const shadowSpare = fitOf([cp('Charmander', ...HUNDO, { shadow: true }), cp('Charmander', ...GOOD, { shadow: true })])[1];
  assert.equal(shadowSpare.rocket.tag, 'ok');
});

test('fit: Max says it needs a Dynamax copy, for ok and strong alike', () => {
  const [top, spare] = fitOf([cp('Chansey', ...HUNDO), cp('Chansey', ...GOOD)]);
  assert.equal(top.max.tag, 'strong');
  assert.equal(spare.max.tag, 'ok');
  for (const f of [top.max, spare.max]) assert.match(f.line, / \(needs a Dynamax copy\)$/);
  assert.doesNotMatch(top.rocket.line, /Dynamax/);
});

test('bestOf: one copy per species per area, strong first, then IV %, then CP, then input order', () => {
  const res = analyseBox([cp('Charmander', ...GOOD, { cp: 900 }), cp('Charmander', ...HUNDO, { cp: 100 }), cp('Charmander', ...LOW), cp('Charmander', ...HUNDO, { cp: 100 })], ctx);
  const of = res.pokemon.map((e) => e.bestOf);
  const strongCopy = res.pokemon.findIndex((e) => e.fit.rocket.tag === 'strong');
  assert.equal(strongCopy, 1, 'the hundo carries the build');
  assert.ok(of[1].includes('rocket'));
  for (const area of ['raids', 'gym', 'rocket', 'max']) assert.ok(of.filter((a) => a.includes(area)).length <= 1, area);
  assert.deepEqual(of[2], [], 'a weak copy is never best');
  // Strong beats ok even when the ok copy has the better IVs and CP is no help: the build-carrying copy is the one (here the hundo).
  const strongFirst = analyseBox([cp('Charmander', ...GOOD, { cp: 900 }), cp('Charmander', ...HUNDO)], ctx).pokemon;
  assert.deepEqual(strongFirst.map((e) => e.fit.rocket.tag), ['ok', 'strong']);
  assert.deepEqual(strongFirst.map((e) => e.bestOf.includes('rocket')), [false, true]);
  // Shadow copies carry no build here, so they are all ok and the tie-breaks decide: IV % first, then CP, then the first in input order.
  const sh = (iv, c) => cp('Charmander', iv, iv, iv, { shadow: true, cp: c });
  const best = (copies) => analyseBox(copies, ctx).pokemon.map((e) => e.bestOf.includes('rocket'));
  assert.deepEqual(best([sh(13, 900), sh(14, 100), sh(12, 900)]), [false, true, false], 'IV % before CP');
  assert.deepEqual(best([sh(13, 300), sh(13, 500), sh(13, 500)]), [false, true, false], 'CP, then the first in input order');
});

test('fit and bestOf: no species is best twice, and every resolved copy carries all four areas', () => {
  const per = new Map();
  for (const e of out.pokemon) {
    if (e.unresolved) { assert.equal(e.fit, undefined); continue; }
    assert.deepEqual(Object.keys(e.fit), ['raids', 'gym', 'rocket', 'max']);
    for (const a of e.bestOf) { const k = `${e.resolved.speciesId}|${a}`; assert.ok(!per.has(k), `${k} best twice`); per.set(k, e); assert.notEqual(e.fit[a].tag, 'weak'); }
  }
  assert.ok(per.size > 0);
});
