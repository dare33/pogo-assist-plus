import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadGamemaster, loadTiers, loadRankings } from '../src/node/load.js';
import { analyseBox, FIT_IV_PCT } from '../src/advise.js';
import { toPokeGenieCsv } from '../src/extract/pipeline.js';

const csvOf = (rows) => toPokeGenieCsv(rows.map((r) => ({ shadow: null, ...r })), { scanDate: new Date('2026-10-26T00:00:00Z') });

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

test('Gigantamax entries are never credited to an unmarked box Pokémon, Dynamax ones are flagged', () => {
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

// A synthetic copy: the fields analyseBox reads from an import.
const sCopy = (name, o = {}) => ({ source: 'pokegenie', index: 0, name, form: '', gender: '', cp: 1500, hp: 120, ivs: { atk: 15, def: 15, hp: 15 }, ivPercent: 100,
  levelMin: 20, levelMax: 20, level: 20, moves: [], shadow: false, purified: false, lucky: false, favorite: false, dust: 2500, scanDate: '2026-10-24 00:00', ...o });
const hitsOf = (p) => analyseBox([p], ctx).pokemon[0].hits.filter((h) => h.kind === 'tier');

test('a Shadow copy is credited with the plain species\' raid and Rocket entries, not its gym or max ones', () => {
  const sh = hitsOf(sCopy('Swampert', { shadow: true }));
  assert.ok(sh.some((h) => h.area === 'rocket' && h.tier === 'S' && h.targetId === 'swampert_shadow'), 'Shadow Swampert Rocket S');
  const b = analyseBox([sCopy('Swampert', { shadow: true })], ctx).builds.find((x) => x.targetId === 'swampert_shadow');
  assert.ok(b && b.areas.includes('rocket'));
  const snorlax = hitsOf(sCopy('Snorlax', { shadow: true }));
  assert.ok(!snorlax.some((h) => h.area === 'gym' || h.area === 'max'), 'no gym or max hit for a Shadow Snorlax');
  assert.ok(snorlax.some((h) => h.targetId === 'snorlax_shadow' && h.area === 'ul'), 'its own _shadow entry still counts');
});

test('a plain copy is not changed by the Shadow rule, and an area/section the _shadow id has is not doubled', () => {
  const plain = hitsOf(sCopy('Swampert')).map((h) => `${h.area}/${h.tier}/${h.targetId}`).sort();
  assert.deepEqual(plain, ['raids/B/swampert', 'rocket/S/swampert']);
  // Mewtwo has raids/Psychic/A on both ids: the Shadow copy carries it once, from the _shadow entry; the plain-only Rocket entry is added.
  const mt = hitsOf(sCopy('Mewtwo', { shadow: true }));
  assert.equal(mt.filter((h) => h.area === 'raids' && h.section === 'Psychic').length, 1);
  assert.ok(mt.every((h) => h.targetId === 'mewtwo_shadow'));
  assert.ok(mt.some((h) => h.area === 'rocket'));
  const keys = mt.map((h) => `${h.area}/${h.section}`);
  assert.equal(new Set(keys).size, keys.length);
});

test('the dedupe is on area and section, not tier: a plain entry of another tier is not added next to the _shadow one', () => {
  // Rhyperior: raids/Rock is S on rhyperior_shadow and B on rhyperior. The Shadow copy carries the S one only; the plain Ground raid and
  // Rocket entries (no _shadow counterpart) are still added. Mamoswine: raids/Ice is A on the _shadow id and B on the plain one.
  const rh = hitsOf(sCopy('Rhyperior', { shadow: true }));
  assert.deepEqual(rh.filter((h) => h.area === 'raids' && h.section === 'Rock').map((h) => h.tier), ['S']);
  assert.ok(rh.some((h) => h.area === 'raids' && h.section === 'Ground' && h.tier === 'B'));
  assert.ok(rh.some((h) => h.area === 'rocket'));
  const mam = hitsOf(sCopy('Mamoswine', { shadow: true }));
  assert.deepEqual(mam.filter((h) => h.area === 'raids' && h.section === 'Ice').map((h) => h.tier), ['A']);
});

test('a copy named Shadow without the flag gets the same credit', () => {
  assert.ok(hitsOf(sCopy('Shadow Swampert')).some((h) => h.area === 'rocket' && h.tier === 'S' && h.targetId === 'swampert_shadow'));
});

test('Mega targets are gated on the resolver\'s Shadow flag or the _shadow id: a Shadow by name or by flag gets no Mega credit, a plain copy still does', () => {
  // Charizard: Mega Charizard Y is a raids/Fire A entry; plain Charizard has a Rocket A entry; charizard_shadow has none of its own.
  const plain = hitsOf(sCopy('Charizard'));
  assert.ok(plain.some((h) => h.viaMega === 'charizard_mega_y' && h.area === 'raids' && h.targetId === 'charizard'), 'plain Charizard reaches Mega Charizard Y');
  const named = hitsOf(sCopy('Shadow Charizard'));
  assert.ok(named.length, 'the named copy still has hits');
  assert.ok(!named.some((h) => h.viaMega), 'a copy named Shadow Charizard with the flag false gets no Mega hit (it used to)');
  assert.ok(named.every((h) => h.targetId === 'charizard_shadow'));
  assert.ok(named.some((h) => h.area === 'rocket' && h.tier === 'A'), 'and keeps the plain Rocket credit');
  const flagged = hitsOf(sCopy('Charizard', { shadow: true }));
  assert.ok(!flagged.some((h) => h.viaMega), 'a flagged Shadow still gets no Mega hit');
  assert.deepEqual(flagged.map((h) => `${h.area}/${h.tier}/${h.targetId}`).sort(), named.map((h) => `${h.area}/${h.tier}/${h.targetId}`).sort(), 'flag and name give the same hits');
});

test('Mega hits and Mega gaps agree: a name-only Shadow Charizard leaves Mega Charizard Y a gap, a plain one covers it', () => {
  const named = analyseBox([sCopy('Shadow Charizard')], ctx);
  assert.ok(!named.builds.some((b) => b.viaMega), 'no Mega build for the named Shadow');
  assert.ok(named.gaps.some((g) => g.speciesId === 'charizard_mega_y'), 'Mega Charizard Y (raids/Fire A) is a gap');
  const plain = analyseBox([sCopy('Charizard')], ctx);
  assert.ok(plain.builds.some((b) => b.viaMega), 'plain Charizard has a Mega build');
  assert.ok(!plain.gaps.some((g) => g.speciesId === 'charizard_mega_y'), 'and no Mega gap');
  // An id-style name resolves to charizard_shadow with the resolver's flag false (its word match stops at the underscore): still a Shadow here.
  const idStyle = analyseBox([sCopy('charizard_shadow')], ctx);
  assert.equal(idStyle.pokemon[0].resolved.speciesId, 'charizard_shadow');
  assert.ok(!idStyle.builds.some((b) => b.viaMega), 'no Mega build for an id-style Shadow name');
  assert.ok(idStyle.gaps.some((g) => g.speciesId === 'charizard_mega_y'), 'Mega Charizard Y is a gap for it');
});

test('a Shadow flag on a species with no _shadow id still blocks the Mega, in hits and gaps (Lucario: Mega Lucario is raids/Fighting S)', () => {
  const flagged = analyseBox([sCopy('Lucario', { shadow: true })], ctx);
  assert.equal(flagged.pokemon[0].resolved.speciesId, 'lucario', 'no lucario_shadow in the game master');
  assert.ok(!flagged.pokemon[0].hits.some((h) => h.viaMega), 'a flagged Lucario gets no Mega hit');
  assert.ok(flagged.gaps.some((g) => g.speciesId === 'lucario_mega'), 'Mega Lucario is a gap');
  const plain = analyseBox([sCopy('Lucario')], ctx);
  assert.ok(plain.pokemon[0].hits.some((h) => h.viaMega === 'lucario_mega'), 'a plain Lucario has the Mega hit');
  assert.ok(!plain.gaps.some((g) => g.speciesId === 'lucario_mega'), 'and no Mega gap');
  const both = analyseBox([sCopy('Lucario', { shadow: true }), sCopy('Lucario')], ctx);
  assert.ok(!both.gaps.some((g) => g.speciesId === 'lucario_mega'), 'a plain copy beside the flagged one covers the Mega');
});

test('gaps: a Shadow covers its plain raid and Rocket entries but not its gym entry', () => {
  const swampert = analyseBox([sCopy('Swampert', { shadow: true })], ctx).gaps;
  assert.ok(!swampert.some((g) => g.speciesId === 'swampert' && g.area === 'rocket'), 'no Rocket S gap for Swampert');
  const snorlax = analyseBox([sCopy('Snorlax', { shadow: true })], ctx).gaps;
  assert.ok(snorlax.some((g) => g.speciesId === 'snorlax' && g.area === 'gym' && g.tier === 'S'), 'the gym S gap for Snorlax stays');
  const plain = analyseBox([sCopy('Swampert')], ctx).gaps;
  assert.ok(!plain.some((g) => g.speciesId === 'swampert' && g.area === 'rocket'));
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

test('a hand-set Dynamax flag: true drops the Dynamax-copy step; false is no longer a state and reads as unset', () => {
  const chansey = box.find((p) => p.name === 'Chansey');
  assert.ok(chansey);
  const run = (dynamax) => {
    const p = { ...chansey };
    if (dynamax !== undefined) p.dynamax = dynamax;
    const r = analyseBox([p], ctx);
    return r.builds.filter((b) => b.speciesId === 'chansey' && b.targetId === 'blissey');
  };
  const unset = run(undefined);
  assert.equal(unset.length, 1);
  assert.ok(unset[0].hits.some((h) => h.area === 'max'), 'Chansey has a Max entry in the tier tables');
  assert.ok(unset[0].steps.some((s) => s.kind === 'needsDynamaxCopy'));
  assert.equal(unset[0].needsDynamax, true);

  const yes = run(true);
  assert.equal(yes.length, 1);
  assert.ok(yes[0].hits.some((h) => h.area === 'max'), 'the Max hits are complete, not removed');
  assert.ok(!yes[0].steps.some((s) => s.kind === 'needsDynamaxCopy'));
  assert.ok(yes[0].hits.filter((h) => h.area === 'max').every((h) => !h.needsDynamax), 'the hit agrees with the build');
  assert.equal(yes[0].needsDynamax, false);

  // `false` (the old "No") no longer means anything: it reads as unset, so the Max hits and the step stay.
  const no = run(false);
  assert.deepEqual(no.map((b) => [b.areas, b.needsDynamax, b.steps]), unset.map((b) => [b.areas, b.needsDynamax, b.steps]));
});

test('hygiene never transfers a copy marked Dynamax (it is kept as an extra keep)', () => {
  const base = box.find((p) => p.name === 'Chansey');
  const yes = { ...base, dynamax: true, ivPercent: 0, cp: 100 };
  const best = { ...base, ivPercent: 100, cp: 200 };
  const plain = analyseBox([yes, best], ctx).hygiene.find((h) => h.speciesId === 'chansey');
  assert.equal(plain.keep.length, 2);
  assert.equal(plain.transfer.length, 0);
  assert.ok(plain.keep.some((p) => p.dynamax === true));
  // Unset (or a stored false) at 0% is still the one transferred, as before.
  for (const flag of [undefined, false]) {
    const h = analyseBox([{ ...yes, dynamax: flag }, best], ctx).hygiene.find((x) => x.speciesId === 'chansey');
    assert.equal(h.keep.length, 1);
    assert.equal(h.transfer.length, 1);
  }
});

test('a Dynamax flag of false does not remove Max credit or open a Max gap', () => {
  const base = box.find((p) => p.name === 'Chansey');
  const maxGap = (copies) => analyseBox(copies, ctx).gaps.some((g) => g.area === 'max' && g.speciesId === 'blissey');
  assert.equal(maxGap([{ ...base }]), false);
  assert.equal(maxGap([{ ...base, dynamax: true }]), false);
  assert.equal(maxGap([{ ...base, dynamax: false }]), false);
});

test('hygiene reports how many keeps are Dynamax extras, only when there are some', () => {
  const base = box.find((p) => p.name === 'Chansey');
  const yes = { ...base, dynamax: true, ivPercent: 0, cp: 100 };
  const best = { ...base, ivPercent: 100, cp: 200 };
  assert.equal(analyseBox([yes, best], ctx).hygiene.find((h) => h.speciesId === 'chansey').dynamaxExtras, 1);
  assert.ok(!('dynamaxExtras' in analyseBox([{ ...yes, dynamax: undefined }, best], ctx).hygiene.find((h) => h.speciesId === 'chansey')));
});

// ---- fit and bestOf: Strong / OK / Weak per copy and non-league area ----
// The tag is cost-free worth (S-tier use = strong, A or B = ok, on a copy at FIT_IV_PCT or more); `build` marks the copy that carries the advisor's
// primary build for the area, which says nothing about worth and is a separate field.
const cp = (name, atk, def, hp, o = {}) => ({ ...copy(name, 20, { atk, def, hp }), pvp: undefined, ...o });
const fitOf = (boxCopies) => analyseBox(boxCopies, ctx).pokemon.map((e) => e.fit);
const HUNDO = [15, 15, 15], GOOD = [13, 13, 13], LOW = [10, 10, 10]; // 100%, 86.7%, 66.7%

test('fit: the tag is the best reachable tier, not the build (Charmander rocket is A, so ok, though the copy carries the build)', () => {
  const res = analyseBox([cp('Charmander', ...HUNDO)], ctx);
  const f = res.pokemon[0].fit.rocket, b = res.builds.find((x) => x.areas.includes('rocket'));
  assert.deepEqual(f, { tag: 'ok', as: 'Charizard', tier: 'A', line: 'Rocket A as Charizard', build: true, buildAs: b.targetName, buildCost: { dust: b.cost.dust, candy: b.cost.candy, xl: b.cost.xl } });
  assert.equal(f.buildAs, 'Charizard');
});

test('fit: S tier is strong and A or B is ok, on the same copy (Fennekin raids is Mega Delphox S, rocket has no entry)', () => {
  const [top, spare] = fitOf([cp('Fennekin', ...HUNDO), cp('Fennekin', ...GOOD)]);
  assert.deepEqual([top.raids.tag, top.raids.tier], ['strong', 'S']);
  assert.deepEqual([spare.raids.tag, spare.raids.tier], ['strong', 'S'], 'a spare is as strong as the build copy');
  assert.equal(top.raids.as, 'Mega Delphox', 'the build targets Delphox; the entry is Mega Delphox');
  assert.equal(top.raids.line, 'Raids S as Mega Delphox');
  assert.equal(spare.raids.as, top.raids.as);
});

test('fit: a spare is ok through an evolution when decently rolled, weak when not, and the weak line says why', () => {
  const [top, spare, poor] = fitOf([cp('Charmander', ...HUNDO), cp('Charmander', ...GOOD), cp('Charmander', ...LOW)]);
  assert.equal(top.rocket.tag, 'ok');
  assert.deepEqual(spare.rocket, { tag: 'ok', as: 'Charizard', tier: 'A', line: 'Rocket A as Charizard', build: false });
  assert.deepEqual(poor.rocket, { tag: 'weak', as: null, tier: null, reason: 'iv', line: 'IVs 66.7%, below 80%', ivPct: 66.7, build: false });
  assert.deepEqual(spare.gym, { tag: 'weak', as: null, tier: null, reason: 'none', line: 'No table entry for Charmander in Gym', species: 'Charmander', build: false });
});

test('fit: the IV threshold is FIT_IV_PCT (80 is in, 79.9 is out) for ok and strong alike, and unknown IVs never qualify', () => {
  assert.equal(FIT_IV_PCT, 80);
  // 36/45 = 80%: the export's own IV average is what is compared, so pin it directly too.
  const at = (name, pct) => cp(name, 12, 12, 12, { ivPercent: pct });
  const [eighty, seventyNine, unknown] = fitOf([at('Charmander', 80), at('Charmander', 79.9), cp('Charmander', 15, 15, 15, { ivs: null })]);
  assert.equal(eighty.rocket.tag, 'ok');
  assert.equal(seventyNine.rocket.tag, 'weak');
  assert.equal(seventyNine.rocket.line, 'IVs 79.9%, below 80%');
  assert.equal(seventyNine.rocket.reason, 'iv');
  assert.deepEqual([unknown.rocket.tag, unknown.rocket.reason, unknown.rocket.line], ['weak', 'ivUnknown', 'IVs not known']);
  const [sEighty, sSeventyNine] = fitOf([at('Chansey', 80), at('Chansey', 79.9)]);
  assert.equal(sEighty.gym.tag, 'strong');
  assert.deepEqual([sSeventyNine.gym.tag, sSeventyNine.gym.reason], ['weak', 'iv']);
});

test('fit: a Mega entry counts for a non-Shadow copy of its base species, not for a Shadow copy', () => {
  const plain = fitOf([cp('Fennekin', ...HUNDO), cp('Fennekin', ...GOOD)])[1];
  assert.deepEqual(plain.raids, { tag: 'strong', as: 'Mega Delphox', tier: 'S', line: 'Raids S as Mega Delphox', build: false });
  const shadow = fitOf([cp('Fennekin', ...HUNDO, { shadow: true }), cp('Fennekin', ...GOOD, { shadow: true })]);
  for (const f of shadow) assert.equal(f.raids.tag, 'weak', 'a Shadow copy cannot Mega evolve, however well rolled');
  // Its only raid entry is the Mega one, so the reason is the Mega rule, not a missing entry.
  assert.deepEqual(shadow[1].raids, { tag: 'weak', as: null, tier: null, reason: 'shadowNoMega', line: 'A Shadow copy cannot Mega evolve', build: false });
});

test('fit: a Shadow-only entry counts for a Shadow copy and not for a plain one; a plain entry counts for both', () => {
  const sh = fitOf([cp('Reshiram', ...HUNDO, { shadow: true }), cp('Reshiram', ...GOOD, { shadow: true })]);
  assert.deepEqual(sh.map((f) => f.raids.tag), ['strong', 'strong']);
  assert.equal(sh[1].raids.as, 'Shadow Reshiram');
  const plain = fitOf([cp('Reshiram', ...HUNDO), cp('Reshiram', ...GOOD)]);
  for (const f of plain) assert.equal(f.raids.tag, 'weak', 'no plain Reshiram raid entry');
  // Charmander's plain Rocket Charizard entry serves its Shadow copies too.
  const shadowSpare = fitOf([cp('Charmander', ...HUNDO, { shadow: true }), cp('Charmander', ...GOOD, { shadow: true })])[1];
  assert.equal(shadowSpare.rocket.tag, 'ok');
});

test('fit: Max says it needs a Dynamax copy, for ok and strong alike', () => {
  const [top, spare] = fitOf([cp('Chansey', ...HUNDO), cp('Chansey', ...GOOD)]);
  assert.deepEqual([top.max.tag, spare.max.tag], ['strong', 'strong']);
  const [lapras] = fitOf([cp('Lapras', ...HUNDO)]);
  assert.deepEqual([lapras.max.tag, lapras.max.tier], ['ok', 'A']);
  for (const f of [top.max, spare.max, lapras.max]) assert.match(f.line, / \(needs a Dynamax copy\)$/);
  assert.doesNotMatch(top.gym.line, /Dynamax/);
});

test('fit: build is true on the copy carrying the advisor\'s primary build for the area, with its target name and the cost the Advice panel shows', () => {
  const res = analyseBox([cp('Chansey', ...GOOD), cp('Chansey', ...HUNDO), cp('Chansey', ...GOOD)], ctx);
  const withBuild = res.pokemon.filter((e) => e.fit.gym.build);
  assert.equal(withBuild.length, 1, 'only the copy the report lists the build for');
  const e = withBuild[0], primary = res.builds.find((b) => b.pokemon === e.p && b.areas.includes('gym'));
  assert.equal(e.fit.gym.buildAs, primary.targetName);
  assert.deepEqual(e.fit.gym.buildCost, { dust: primary.cost.dust, candy: primary.cost.candy, xl: primary.cost.xl });
  // With two builds listing the area on one copy the better-scored one (first in the report) is the primary.
  const mine = res.builds.filter((b) => b.pokemon === e.p && b.areas.includes('gym'));
  assert.equal(e.fit.gym.buildAs, mine[0].targetName);
  // A spare, and an area the copy has no build for, carry build false and no buildAs / buildCost.
  for (const x of res.pokemon) if (x !== e) { assert.equal(x.fit.gym.build, false); assert.ok(!('buildAs' in x.fit.gym) && !('buildCost' in x.fit.gym)); }
  assert.equal(e.fit.rocket.build, false);
});

test('fit: the copy that IS the build copy but has IVs under 80 is build true and weak for iv; a hundo spare is strong with build false', () => {
  // A higher level makes the low-IV copy the cheaper build, so it carries the build; the hundo spare does not.
  const lowBuild = { ...copy('Chansey', 35, { atk: 10, def: 10, hp: 10 }), pvp: undefined };
  const spare = cp('Chansey', ...HUNDO);
  const res = analyseBox([lowBuild, spare], ctx);
  const [a, b] = res.pokemon.map((e) => e.fit.gym);
  assert.equal(a.build, true);
  assert.deepEqual([a.tag, a.reason, a.ivPct], ['weak', 'iv', 66.7]);
  assert.equal(a.buildAs, 'Blissey');
  assert.deepEqual([b.tag, b.build], ['strong', false]);
  assert.ok(!('buildAs' in b));
});

test('bestOf: among strong and ok copies, the higher-IV spare beats the build copy (the build does not enter it)', () => {
  // Both copies are strong for Gym; the build goes to the cheaper, higher-level copy, but the hundo spare is the best Chansey for Gym.
  const res = analyseBox([cp('Chansey', ...GOOD, { level: 35 }), cp('Chansey', ...HUNDO)], ctx);
  const [a, b] = res.pokemon;
  assert.equal(a.fit.gym.build, true);
  assert.deepEqual([a.fit.gym.tag, b.fit.gym.tag, b.fit.gym.build], ['strong', 'strong', false]);
  assert.deepEqual([a.bestOf.includes('gym'), b.bestOf.includes('gym')], [false, true]);
});

test('bestOf: one copy per species per area; IV %, then CP, then input order; weak copies are never best', () => {
  const res = analyseBox([cp('Charmander', ...GOOD, { cp: 900 }), cp('Charmander', ...HUNDO, { cp: 100 }), cp('Charmander', ...LOW), cp('Charmander', ...HUNDO, { cp: 100 })], ctx);
  const of = res.pokemon.map((e) => e.bestOf);
  for (const area of ['raids', 'gym', 'rocket', 'max']) assert.ok(of.filter((a) => a.includes(area)).length <= 1, area);
  assert.deepEqual(of.map((a) => a.includes('rocket')), [false, true, false, false], 'the first hundo: IV % before CP, then input order');
  assert.deepEqual(of[2], [], 'a weak copy is never best');
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
    for (const f of Object.values(e.fit)) assert.equal(typeof f.build, 'boolean');
    for (const a of e.bestOf) { const k = `${e.resolved.speciesId}|${a}`; assert.ok(!per.has(k), `${k} best twice`); per.set(k, e); assert.notEqual(e.fit[a].tag, 'weak'); }
  }
  assert.ok(per.size > 0);
  // tag and tier agree on every strong / ok copy (S is strong), and some copy on the fixture carries a build.
  const fits = out.pokemon.flatMap((e) => Object.values(e.fit ?? {}));
  for (const f of fits) if (f.tag !== 'weak') assert.equal(f.tag, f.tier === 'S' ? 'strong' : 'ok');
  assert.ok(fits.some((f) => f.build && f.tag === 'weak') && fits.some((f) => f.build && f.tag === 'strong') && fits.some((f) => f.build && f.tag === 'ok'));
});

test('fit: a shadow-flagged entry that keeps a plain species id (Shadow Pheromosa) is for Shadow copies only', () => {
  const plainBox = analyseBox([cp('Pheromosa', ...HUNDO), cp('Pheromosa', ...GOOD)], ctx);
  const plain = plainBox.pokemon.map((e) => e.fit);
  assert.ok(!plainBox.builds.some((b) => b.areas.includes('raids')), 'a plain Pheromosa has no raids build (the entry is Shadow Pheromosa)');
  const none = { tag: 'weak', as: null, tier: null, reason: 'none', line: 'No table entry for Pheromosa in Raids', species: 'Pheromosa', build: false };
  assert.deepEqual(plain[0].raids, none);
  assert.deepEqual(plain[1].raids, none);
  const shadowBox = analyseBox([cp('Pheromosa', ...HUNDO, { shadow: true }), cp('Pheromosa', ...GOOD, { shadow: true })], ctx);
  const shadow = shadowBox.pokemon.map((e) => e.fit);
  assert.ok(shadowBox.builds.some((b) => b.areas.includes('raids')), 'a Shadow Pheromosa has the raids build');
  assert.deepEqual([shadow[0].raids.tag, shadow[0].raids.as, shadow[0].raids.build], ['ok', 'Shadow Pheromosa', true]);
  assert.deepEqual([shadow[1].raids.tag, shadow[1].raids.as, shadow[1].raids.build], ['ok', 'Shadow Pheromosa', false]);
});

test('fit: a weak "none" names the species the engine uses in its line (the family: the base species with _shadow and _mega stripped)', () => {
  const [stage2, shadow] = fitOf([cp('Charmeleon', ...HUNDO), cp('Charmander', ...HUNDO, { shadow: true })]);
  assert.deepEqual([stage2.gym.reason, stage2.gym.species, stage2.gym.line], ['none', 'Charmeleon', 'No table entry for Charmeleon in Gym']);
  assert.deepEqual([shadow.gym.reason, shadow.gym.species], ['none', 'Charmander']);
  // Only the "none" reason carries it.
  assert.ok(!('species' in fitOf([cp('Charmander', ...LOW)])[0].rocket));
});

test('fit: the same Pokémon object twice in a box is two copies: build for the first position only', () => {
  const p = cp('Charmander', ...HUNDO);
  const f = fitOf([p, p]);
  assert.equal(f[0].rocket.build, true);
  assert.equal(f[1].rocket.build, false);
});

test('fit: a Gigantamax entry is never credited (a plain Charmander spare is not Max ok as Gigantamax Charizard)', () => {
  const [, spare] = fitOf([cp('Charmander', ...HUNDO), cp('Charmander', ...GOOD)]);
  assert.equal(spare.max.tag, 'weak');
  assert.equal(spare.max.reason, 'none');
});

test('fit: with equal-tier entries at two stages the nearest stage wins (a spare Chansey is as Chansey, not Blissey)', () => {
  const [, spare] = fitOf([cp('Chansey', ...HUNDO), cp('Chansey', ...GOOD)]);
  assert.equal(spare.gym.tag, 'strong');
  assert.equal(spare.gym.as, 'Chansey');
});

test('bestOf: a Shadow and a plain copy of one species are separate groups (hygiene\'s resolved species, not the base species)', () => {
  const res = analyseBox([cp('Charmander', ...GOOD), cp('Charmander', ...GOOD, { shadow: true })], ctx);
  assert.deepEqual(res.pokemon.map((e) => e.bestOf.includes('rocket')), [true, true]);
});

test('a Gigantamax-only Max row is not credited to an ordinary Dynamax copy of the species', () => {
  const maxHits = (from, to) => out.builds.find((b) => b.speciesId === from && b.targetId === to)?.hits.filter((h) => h.area === 'max') ?? [];
  // These species are only in the Max tables as Gigantamax (the G-Max Blastoise, Venusaur and Pikachu rows were once split into plain names).
  for (const [from, to] of [['squirtle', 'blastoise'], ['bulbasaur', 'venusaur'], ['pikachu', 'pikachu'], ['caterpie', 'butterfree']])
    assert.deepEqual(maxHits(from, to), [], `${from}->${to}`);
  // Lapras and Snorlax are also Dynamax healers/tanks: only those rows are credited.
  assert.deepEqual(maxHits('lapras', 'lapras').map((h) => h.name), ['Lapras']);
  assert.deepEqual(maxHits('snorlax', 'snorlax').map((h) => [h.name, h.tier]), [['Snorlax', 'A'], ['Snorlax', 'A']]);
  assert.deepEqual(maxHits('regice', 'regice').map((h) => h.name), ['Dynamax Regice']);
});

// ---- Gigantamax mark, hand Shadow / Purified mark, Lucky ----
const gmaxHits = (o) => {
  const base = box.find((p) => p.name === 'Charmander' && !p.shadow);
  const b = analyseBox([{ ...base, ...o }], ctx).builds.find((x) => x.speciesId === 'charmander' && x.targetId === 'charizard');
  return b.hits.filter((h) => h.area === 'max' && /gigantamax|g-max/i.test(h.name));
};

test('a Gigantamax entry is credited only to a copy marked Gigantamax, and needs no Dynamax step', () => {
  assert.deepEqual(gmaxHits({}), [], 'unmarked');
  assert.deepEqual(gmaxHits({ dynamax: true }), [], 'a Dynamax copy is not a Gigantamax one');
  assert.deepEqual(gmaxHits({ gigantamax: false }), []);
  const g = gmaxHits({ gigantamax: true });
  assert.ok(g.length > 0, 'Gigantamax Charizard credited');
  assert.ok(g.every((h) => !h.needsDynamax), 'a Gigantamax copy needs no Dynamax step');
  const withDyn = gmaxHits({ gigantamax: true, dynamax: true });
  assert.equal(withDyn.length, g.length);
});

test('fit: a Gigantamax-marked copy is Max-rated as Gigantamax Charizard; an unmarked one is not', () => {
  const rows = (o) => analyseBox([cp('Charmander', ...HUNDO, o)], ctx).pokemon[0].fit.max;
  assert.equal(rows({}).tag, 'weak');
  const g = rows({ gigantamax: true });
  assert.notEqual(g.tag, 'weak');
  assert.match(g.as, /gigantamax/i);
});

test('hygiene keeps a Gigantamax-marked copy as it does a Dynamax one', () => {
  const base = box.find((p) => p.name === 'Chansey');
  const g = { ...base, gigantamax: true, ivPercent: 0, cp: 100 };
  const best = { ...base, ivPercent: 100, cp: 200 };
  const h = analyseBox([g, best], ctx).hygiene.find((x) => x.speciesId === 'chansey');
  assert.equal(h.transfer.length, 0);
  assert.equal(h.dynamaxExtras, 1);
});

test('a hand Shadow mark reaches the engine as shadow, purified or neither', () => {
  const imp = (sp) => importPokeGenie(csvOf([{ index: 1, name: 'Charmander', form: '', dex: 4, cp: 300, hp: 40, ivs: { atk: 10, def: 10, hp: 10 }, level: 20, levelMax: 20, dust: 2500, shadow: sp }]))[0];
  assert.equal(imp(1).shadow, true);
  assert.equal(imp(2).purified, true);
  for (const sp of [0, null, undefined]) { assert.equal(imp(sp).shadow, false); assert.equal(imp(sp).purified, false); }
  const id = (sp) => analyseBox([imp(sp)], ctx).pokemon[0].resolved.speciesId;
  assert.equal(id(1), 'charmander_shadow');
  assert.equal(id(0), 'charmander');
});

test('Lucky 1 from the CSV writer reaches the engine and halves the power-up dust', () => {
  const row = { index: 1, name: 'Charmander', form: '', dex: 4, cp: 300, hp: 40, ivs: { atk: 10, def: 10, hp: 10 }, level: 20, levelMax: 20, dust: 2500 };
  assert.match(csvOf([{ ...row, lucky: true }]).split('\n')[1], /,1,,,/, 'Lucky column holds 1');
  const lucky = importPokeGenie(csvOf([{ ...row, lucky: true }]))[0];
  const plain = importPokeGenie(csvOf([{ ...row, lucky: false }]))[0];
  assert.equal(lucky.lucky, true);
  assert.equal(plain.lucky, false);
  const dust = (p) => analyseBox([p], ctx).builds.find((b) => b.speciesId === 'charmander' && b.targetId === 'charizard').cost.dust;
  assert.ok(dust(lucky) < dust(plain), `lucky ${dust(lucky)} < plain ${dust(plain)}`);
});
