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
  analyseBox([{ ...withLevel(template, level), name, form: '', ivs: hundo, moves: [], chargedMoves: undefined, ...extra }], ctx).allBuilds.find((b) => b.targetId === target);
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

test('levelText names the level the cost covers with its areas, or says the copy is already there', () => {
  assert.equal(levelText(build('Xurkitree', 20)), 'L20 → 35 (Raids)');
  assert.equal(levelText(build('Xurkitree', 40)), 'L40 · already at (or past) its Raids target level');
  // Mankey -> Annihilape (GL, UL): the cost is Great League's, and so is the step.
  const mankey = build('Mankey', 12, 'annihilape');
  assert.equal(mankey.pvpCost.league, 'gl');
  assert.equal(levelText(mankey), 'L12 → 16 (GL)');
  // Tinkatink -> Tinkaton: the Ultra League cost is what is shown; Great League's best level is only a note.
  const tink = build('Tinkatink', 10, 'tinkaton');
  assert.deepEqual(tink.costAreas, ['ul']);
  assert.equal(levelText(tink), 'L10 → 48.5 (UL); going past 23 leaves GL');
  // A level-51 copy that fits its league is already past its best level there.
  const cram = build('Cramorant', 51);
  assert.deepEqual(cram.costAreas, ['ul']);
  assert.equal(levelText(cram), 'L51 · already at (or past) its best UL level');
  // The build the script used to crash on: Electabuzz -> Electivire at level 30.
  const eb = build('Electabuzz', 30, 'electivire');
  assert.equal(eb.targetLevel, null); assert.equal(eb.pvpCost, null);
  assert.equal(levelText(eb), 'L30 · already at (or past) its Rocket target level');
});

test('no uncosted power-up step: Squirtle #181 at L45 and Lapras #30 at L36 are at their costed targets', () => {
  // Squirtle #181 -> Blastoise (Max, UL, Raids): the cost is Raids' (125 evolution candy); Ultra League's best level (49.5) is not paid for, so not a step.
  const sq = fixtureBuild(181, 45, 'blastoise');
  assert.deepEqual(sq.areas.slice().sort(), ['max', 'raids', 'ul']);
  assert.deepEqual(sq.costAreas, ['raids']);
  assert.equal(sq.pvpCost.league, 'ul'); assert.equal(sq.pvpCost.toLevel, 49.5);
  assert.equal(sq.cost.dust, 0); assert.equal(sq.cost.candy, 125);
  assert.ok(!kinds(sq).includes('powerUp'));
  assert.equal(levelText(sq), 'L45 · already at (or past) its Raids target level');
  assert.equal(actionText(sq), 'Evolve to Blastoise + Mega evolve (Max needs a Dynamax copy)');
  // At UL's best level itself the wording is the same, and the league is not named as a cost area.
  const sq495 = fixtureBuild(181, 49.5, 'blastoise');
  assert.deepEqual(sq495.costAreas, ['raids']);
  assert.equal(levelText(sq495), 'L49.5 · already at (or past) its Raids target level');
  // Lapras #30 at level 36: Max sets the cost area (target 30, already passed); Ultra League's best level (40) is not a step.
  const lap = fixtureBuild(30, 36, 'lapras');
  assert.deepEqual(lap.costAreas, ['max']);
  assert.equal(lap.pvpCost.league, 'ul');
  assert.ok(!kinds(lap).includes('powerUp'));
  assert.equal(levelText(lap), 'L36 · already at (or past) its Max target level');
  // Several areas on the same target level are all named, and the league the climb goes past is a note.
  const snor = build('Snorlax', 10);
  assert.deepEqual(snor.costAreas, snor.areas.filter((a) => ['gym', 'max'].includes(a)));
  assert.equal(levelText(snor), 'L10 → 30 (Gym/Max); going past 27 leaves UL, going past 16 leaves GL');
  assert.deepEqual(snor.leavesLeague.map((x) => x.league), ['ul', 'gl']);
});

test('invariant over many copies: the power-up step is exactly the climb the cost covers', () => {
  let steps = 0, leagueSteps = 0, otherSteps = 0;
  for (const level of [null, 3, 10, 22, 35, 45]) {
    const rows = box.map((p) => (level == null ? { ...p, pvp: undefined } : withLevel(p, level)));
    for (const b of analyseBox(rows, ctx).allBuilds) {
      const ups = b.steps.filter((s) => s.kind === 'powerUp');
      assert.ok(ups.length <= 1, `${b.speciesId}->${b.targetId}: one power-up step at most`);
      const leagueOnly = b.pvpCost && b.costAreas.length === 1 && b.costAreas[0] === b.pvpCost.league;
      if (!ups.length) {
        // Nothing to climb to: the covered level is at or below the copy's.
        const covered = leagueOnly ? b.pvpCost.toLevel : b.targetLevel;
        assert.ok(covered == null || covered <= b.level, `${b.speciesId}->${b.targetId} L${b.level}: no step but the cost covers ${covered}`);
        continue;
      }
      const [up] = ups;
      steps++;
      assert.deepEqual(up.areas, b.costAreas, 'the step names the cost areas, nothing else');
      for (const a of up.areas) assert.ok(b.areas.includes(a));
      assert.ok(up.toLevel > b.level);
      if (leagueOnly) { leagueSteps++; assert.equal(up.toLevel, b.pvpCost.toLevel, `${b.targetId}: the league's own best level`); }
      else { otherSteps++; assert.equal(up.toLevel, b.targetLevel); if (b.pvpCost && b.costAreas.some((a) => a === b.pvpCost.league)) assert.fail('a league cost area next to a non-league cost'); }
      // The extra leagues the climb passes are notes, never steps.
      for (const x of b.leavesLeague) { assert.ok(!up.areas.includes(x.league)); assert.ok(up.toLevel > x.bestLevel); }
    }
  }
  assert.ok(steps > 150 && leagueSteps > 20 && otherSteps > 60, `${steps} steps: ${leagueSteps} league, ${otherSteps} other`);
});

test('every fixture build: the steps match its flags', () => {
  const all = analyseBox(box, ctx).allBuilds;
  for (const b of all) {
    const k = kinds(b);
    assert.equal(k.includes('megaEvolve'), !!b.viaMega, `${b.speciesId}->${b.targetId}`);
    assert.equal(k.includes('needsDynamaxCopy'), !!b.needsDynamax);
    // Elite and Community Day steps follow the table's moves; a copy that records no moves is missing every one of them.
    assert.equal(k.includes('eliteTM'), b.moveFlags.elite > 0);
    assert.equal(k.includes('cdMove'), b.moveFlags.cd);
    assert.equal(k.includes('evolve') || k.includes('formChange'), b.targetId !== b.speciesId);
    const onlyDynamax = b.steps.every((s) => s.kind === 'needsDynamaxCopy');
    assert.equal(actionText(b).startsWith('Already built'), onlyDynamax, actionText(b));
    assert.ok(levelText(b).startsWith(`L${b.level} `));
    const m = levelText(b).match(/best (GL|UL|ML) level/);
    if (m) assert.equal(b.pvpCost.league.toUpperCase(), m[1]);
  }
});

test('actionText: what is left, from the steps', () => {
  assert.equal(actionText(build('Xurkitree', 20)), 'Power up to level 35 (Raids)');
  assert.equal(actionText(build('Xurkitree', 40)), 'Already built');
  // Evolution candy is not a power-up; Mega evolve is a step, never a suffix of "Already built".
  const dragon = build('Dragonair', 51, 'dragonite');
  assert.deepEqual(kinds(dragon), ['evolve', 'megaEvolve']);
  assert.equal(actionText(dragon), 'Evolve to Dragonite + Mega evolve');
  // The Dynamax requirement is Max's alone: it does not make the other areas unfinished, but it is not hidden either.
  const sq50 = build('Squirtle', 50, 'blastoise');
  assert.equal(actionText(sq50), 'Evolve to Blastoise + Mega evolve (Max needs a Dynamax copy)');
  const xurkMax = { ...build('Xurkitree', 40), steps: [{ kind: 'needsDynamaxCopy' }] };
  assert.equal(actionText(xurkMax), 'Already built (Max needs a Dynamax copy)');
  // A scan records no moves, so the second move may already be there.
  assert.equal(actionText(build('Cramorant', 51)), "Second move (if it doesn't have it)");
  assert.match(actionText(build('Tinkatink', 10, 'tinkaton')), /Community Day move$/);
});

test('Elite TMs: counted by distinct move, joined with +, singular for one; dropped when the recorded moves hold them', () => {
  const synthetic = (steps) => ({ level: 40, steps, costAreas: ['raids'], pvpCost: null });
  assert.equal(actionText(synthetic([{ kind: 'eliteTM', count: 1 }])), '1 Elite TM');
  assert.equal(actionText(synthetic([{ kind: 'eliteTM', count: 2 }])), '2 Elite TMs');
  assert.equal(actionText(synthetic([{ kind: 'evolve', to: 'X', candy: 1 }, { kind: 'eliteTM', count: 1 }, { kind: 'cdMove' }])), 'Evolve to X + 1 Elite TM + Community Day move');
  // Real copies: Corviknight asks for Air Cutter (CD) and Iron Head (Elite) in one entry (the same Elite move in another entry is not a second TM).
  const corv = build('Corviknight', 40);
  assert.equal(corv.steps.find((s) => s.kind === 'eliteTM')?.count, new Set(corv.hits.flatMap((h) => [...String(h.moves).matchAll(/([A-Za-z' -]+?)\s*\(Elite[^)]*\)/g)].map((m) => m[1].split(/[/+]/).pop().trim()))).size);
  const held = build('Corviknight', 40, 'corviknight', { moves: ['Sand Attack', 'Air Cutter', 'Iron Head'], chargedMoves: ['Air Cutter', 'Iron Head'] });
  assert.ok(!kinds(held).includes('eliteTM') && !kinds(held).includes('cdMove'), 'both moves are recorded');
  const half = build('Corviknight', 40, 'corviknight', { moves: ['Sand Attack', 'Air Cutter', 'Brave Bird'], chargedMoves: ['Air Cutter', 'Brave Bird'] });
  assert.ok(kinds(half).includes('eliteTM') && !kinds(half).includes('cdMove'), 'Iron Head (Elite) is still missing, Air Cutter (CD) is held');
  // The effort (and so the score) still counts table mentions, as before.
  assert.equal(held.score, build('Corviknight', 40, 'corviknight', { moves: ['x', 'y', 'z'], chargedMoves: ['y', 'z'] }).score);
});

test('the second move: due when the copy\'s second charged slot is empty; an unlocked slot needs no step and no charge, whatever the move names', () => {
  const charizard = (extra) => build('Charizard', 40, 'charizard', extra);
  const unknown = charizard({}), locked = charizard({ moves: ['Fire Spin', 'Dragon Claw'], chargedMoves: ['Dragon Claw', ''] });
  // The slot is unlocked by an unrelated second move (it would have been a different move before evolving): still no second-move step.
  const unlocked = charizard({ moves: ['Ember', 'Scratch', 'Body Slam'], chargedMoves: ['Scratch', 'Body Slam'] });
  assert.deepEqual(unknown.steps.find((s) => s.kind === 'secondMove'), { kind: 'secondMove', certain: false });
  assert.deepEqual(locked.steps.find((s) => s.kind === 'secondMove'), { kind: 'secondMove', certain: true });
  assert.equal(unlocked.steps.some((s) => s.kind === 'secondMove'), false);
  assert.equal(unlocked.cost.secondMove.dust, 0);
  assert.ok(unknown.cost.secondMove.dust > 0 && locked.cost.secondMove.dust === unknown.cost.secondMove.dust);
  assert.ok(unlocked.score > unknown.score);
  // The import keeps the slots by position.
  const row = importPokeGenie('Name,Form,Quick Move,Charge Move,Charge Move 2\nCharmander,,Ember,,Flamethrower\n')[0];
  assert.deepEqual(row.chargedMoves, ['', 'Flamethrower']);
  assert.deepEqual(row.moves, ['Ember', 'Flamethrower']);
});

test('the web page and the script word builds with the shared functions, not their own labels', () => {
  const app = readFileSync(new URL('../web/app.js', import.meta.url), 'utf8');
  assert.match(app, /const what = esc\(actionText\(b\)\)/);
  assert.match(app, /const lv = levelText\(b\)/);
  const script = readFileSync(new URL('../scripts/advise.mjs', import.meta.url), 'utf8');
  assert.match(script, /actionText\(b\)/);
  assert.match(script, /levelText\(b\)/);
});
