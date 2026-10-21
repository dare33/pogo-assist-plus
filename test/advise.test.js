import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadGamemaster, loadTiers, loadRankings } from '../src/node/load.js';
import { analyseBox } from '../src/advise.js';

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
