// How builds are worded: the steps still to do on each build (src/advise.js), their rendering (levelText / actionText, used by the web
// page and scripts/advise.mjs), and the script itself.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadGamemaster, loadTiers, loadRankings } from '../src/node/load.js';
import { analyseBox, levelText, actionText } from '../src/advise.js';

const ctx = { gm: loadGamemaster(), tiers: loadTiers(), rankings: loadRankings() };
const fixture = new URL('../fixtures/greg-2026-09-25.pokegenie.csv', import.meta.url);
const box = importPokeGenie(readFileSync(fixture, 'utf8'));
const template = box.find((p) => !p.shadow && !p.purified && !p.lucky && (!p.form || p.form === 'Normal'));
const hundo = { atk: 15, def: 15, hp: 15 };
const withLevel = (p, level) => ({ ...p, pvp: undefined, level, levelMin: level, levelMax: level });
const build = (name, level, target = name.toLowerCase(), extra = {}) =>
  analyseBox([{ ...withLevel(template, level), name, form: '', ivs: hundo, ...extra }], ctx).allBuilds.find((b) => b.targetId === target);
const fixtureBuild = (index, level, target) => analyseBox([withLevel(box.find((x) => x.index === index), level)], ctx).allBuilds.find((b) => b.targetId === target);
const kinds = (b) => b.steps.map((s) => s.kind);

test('scripts/advise.mjs runs on the fixture and exits 0 (README documents this command)', () => {
  const r = spawnSync(process.execPath, [new URL('../scripts/advise.mjs', import.meta.url).pathname, fixture.pathname], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /# Builds \(\d+\)/);
  const rows = r.stdout.split('\n').filter((l) => /^\| \d+ \|/.test(l));
  assert.ok(rows.length >= 30);
  for (const row of rows) assert.match(row, /L\d+(\.5)? (→ [\d.]+ \(|· already at \(or past\) its )/, row);
});

test('levelText names the level(s) the build climbs to with their areas, or says the copy is already there', () => {
  assert.equal(levelText(build('Xurkitree', 20)), 'L20 → 35 (Raids)');
  assert.equal(levelText(build('Xurkitree', 40)), 'L40 · already at (or past) its Raids target level');
  // Tinkatink -> Tinkaton: a league-only build climbs to the league's own best level.
  const tink = build('Tinkatink', 10, 'tinkaton');
  assert.deepEqual(tink.costAreas, ['ul']);
  assert.equal(levelText(tink), 'L10 → 48.5 (UL)');
  // A level-51 copy that fits its league is already past its best level there.
  const cram = build('Cramorant', 51);
  assert.deepEqual(cram.costAreas, ['ul']);
  assert.equal(levelText(cram), 'L51 · already at (or past) its best UL level');
  // The build the script used to crash on: Electabuzz -> Electivire at level 30.
  const eb = build('Electabuzz', 30, 'electivire');
  assert.equal(eb.targetLevel, null); assert.equal(eb.pvpCost, null);
  assert.equal(levelText(eb), 'L30 · already at (or past) its Rocket target level');
});

test('the cost area and the league label are kept apart (fixture Squirtle #181 and Lapras #30)', () => {
  // Squirtle #181 (0/7/14) at level 45 -> Blastoise (Max, UL, Raids): the cost (125 evolution candy, no dust) is Raids'; Ultra League's best
  // level (49.5) is still above the copy, so it is its own power-up step, not folded into the Raids cost.
  const sq = fixtureBuild(181, 45, 'blastoise');
  assert.deepEqual(sq.areas.slice().sort(), ['max', 'raids', 'ul']);
  assert.deepEqual(sq.costAreas, ['raids']);
  assert.equal(sq.pvpCost.league, 'ul'); assert.equal(sq.pvpCost.toLevel, 49.5);
  assert.equal(sq.cost.dust, 0); assert.equal(sq.cost.candy, 125);
  assert.deepEqual(sq.steps.filter((s) => s.kind === 'powerUp'), [{ kind: 'powerUp', toLevel: 49.5, areas: ['ul'] }]);
  assert.equal(levelText(sq), 'L45 → 49.5 (UL)');
  // At UL's best level itself (49.5) nothing is left to climb: the Raids target is named, and the league's "best level" wording is not
  // used, because the league is not a cost area (the cost is Raids').
  const sq495 = fixtureBuild(181, 49.5, 'blastoise');
  assert.equal(sq495.pvpCost.league, 'ul'); assert.ok(sq495.pvpCost.toLevel <= 49.5);
  assert.deepEqual(sq495.costAreas, ['raids']);
  assert.ok(!kinds(sq495).includes('powerUp'));
  assert.equal(levelText(sq495), 'L49.5 · already at (or past) its Raids target level');
  // Lapras #30 at level 36: Max sets the cost area, Ultra League's best level is 40.
  const lap = fixtureBuild(30, 36, 'lapras');
  assert.deepEqual(lap.costAreas, ['max']);
  assert.equal(lap.pvpCost.league, 'ul');
  assert.equal(levelText(lap), 'L36 → 40 (UL)');
  // Several areas on the same target level are all named.
  const snor = build('Snorlax', 10);
  assert.deepEqual(snor.costAreas, snor.areas.filter((a) => ['gym', 'max'].includes(a)));
  assert.equal(levelText(snor), 'L10 → 30 (Gym/Max)', 'the UL best level (29) is passed on the way to 30: not a step of its own');
});

test('every fixture build: the steps match its flags, and "Already built" only means no steps at all', () => {
  const all = analyseBox(box, ctx).allBuilds;
  for (const b of all) {
    const k = kinds(b);
    assert.equal(k.includes('megaEvolve'), !!b.viaMega, `${b.speciesId}->${b.targetId}`);
    assert.equal(k.includes('needsDynamaxCopy'), !!b.needsDynamax);
    assert.equal(k.includes('eliteTM'), b.moveFlags.elite > 0);
    assert.equal(k.includes('cdMove'), b.moveFlags.cd);
    assert.equal(k.includes('evolve') || k.includes('formChange'), b.targetId !== b.speciesId);
    assert.equal(actionText(b) === 'Already built', b.steps.length === 0, actionText(b));
    assert.ok(!/Already built/.test(actionText(b)) || b.steps.length === 0);
    assert.ok(levelText(b).startsWith(`L${b.level} `));
    // A league label next to a "best level" only when that league is a cost area.
    const m = levelText(b).match(/best (GL|UL|ML) level/);
    if (m) assert.equal(b.pvpCost.league.toUpperCase(), m[1]);
  }
});

test('actionText: what is left, from the steps', () => {
  assert.equal(actionText(build('Xurkitree', 20)), 'Power up to level 35 (Raids)');
  assert.equal(actionText(build('Xurkitree', 40)), 'Already built');
  // Evolution candy is not a power-up: a level-51 Dragonair has no power-up step, and Mega evolve is a step, never a suffix of "Already built".
  const dragon = build('Dragonair', 51, 'dragonite');
  assert.deepEqual(kinds(dragon), ['evolve', 'megaEvolve']);
  assert.equal(actionText(dragon), 'Evolve to Dragonite + Mega evolve');
  // A Max build for a copy that is not Dynamax is not "Already built".
  const sq50 = build('Squirtle', 50, 'blastoise');
  assert.equal(actionText(sq50), 'Evolve to Blastoise + Mega evolve + needs a Dynamax copy');
  assert.equal(actionText(fixtureBuild(181, 45, 'blastoise')), 'Evolve to Blastoise + Mega evolve + Power up to level 49.5 (UL) + needs a Dynamax copy');
  // Elite TMs and Community Day moves are steps.
  const lap = fixtureBuild(30, 36, 'lapras');
  assert.deepEqual(kinds(lap), ['powerUp', 'secondMove', 'eliteTM', 'needsDynamaxCopy']);
  assert.match(actionText(lap), /1 Elite TM/);
  assert.match(actionText(build('Tinkatink', 10, 'tinkaton')), /Community Day move/);
  // A scan records no moves, so the second move may already be there.
  assert.equal(actionText(build('Cramorant', 51)), "Second move (if it doesn't have it)");
});

test('the second move: due only if the recorded moves lack what the entry asks for; free when they hold both', () => {
  const charizard = (moves) => build('Charizard', 40, 'charizard', { moves });
  const unknown = charizard([]), partial = charizard(['Fire Spin', 'Dragon Claw']), both = charizard(['Fire Spin', 'Dragon Claw', 'Blast Burn']);
  assert.deepEqual(unknown.steps.find((s) => s.kind === 'secondMove'), { kind: 'secondMove', certain: false });
  assert.deepEqual(partial.steps.find((s) => s.kind === 'secondMove'), { kind: 'secondMove', certain: true });
  assert.equal(both.steps.some((s) => s.kind === 'secondMove'), false);
  assert.ok(!actionText(both).includes('Second move'));
  // Not charged when the moves prove the copy has it; still charged when unknown or missing (the old behaviour).
  assert.equal(both.cost.dust, both.cost.secondMove.dust);
  assert.equal(both.cost.secondMove.dust, 0);
  assert.ok(unknown.cost.secondMove.dust > 0 && partial.cost.secondMove.dust === unknown.cost.secondMove.dust);
  assert.ok(both.score > unknown.score);
});

test('the web page and the script word builds with the shared functions, not their own labels', () => {
  const app = readFileSync(new URL('../web/app.js', import.meta.url), 'utf8');
  assert.match(app, /const what = esc\(actionText\(b\)\)/);
  assert.match(app, /const lv = levelText\(b\)/);
  const script = readFileSync(new URL('../scripts/advise.mjs', import.meta.url), 'utf8');
  assert.match(script, /actionText\(b\)/);
  assert.match(script, /levelText\(b\)/);
});
