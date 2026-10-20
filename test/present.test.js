// How builds are worded (src/advise.js levelText / actionText, used by the web page and scripts/advise.mjs), and the script itself.
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
const build = (name, level, target = name.toLowerCase()) =>
  analyseBox([{ ...template, name, form: '', pvp: undefined, level, levelMin: level, levelMax: level, ivs: hundo }], ctx).allBuilds.find((b) => b.targetId === target);

test('scripts/advise.mjs runs on the fixture and exits 0 (README documents this command)', () => {
  const r = spawnSync(process.execPath, [new URL('../scripts/advise.mjs', import.meta.url).pathname, fixture.pathname], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /# Builds \(\d+\)/);
  // Every build row names the area its cost is for.
  const rows = r.stdout.split('\n').filter((l) => /^\| \d+ \|/.test(l));
  assert.ok(rows.length >= 30);
  for (const row of rows) assert.match(row, /L\d+(\.5)? (→ [\d.]+ \(|· already at \(or past\) its )/, row);
});

test('levelText names the level the cost is for and the area, and never pairs a league with another area\'s cost', () => {
  assert.equal(levelText(build('Xurkitree', 20)), 'L20 → 35 (Raids)');
  // Nothing left to climb to.
  assert.equal(levelText(build('Xurkitree', 40)), 'L40 · already at (or past) its Raids target level');
  // Squirtle -> Blastoise at level 45: a Raids/Max build whose cost is the 125 evolution candy, labelled Raids, not a league.
  const sq = build('Squirtle', 45, 'blastoise');
  assert.equal(sq.costArea, 'raids');
  assert.equal(levelText(sq), 'L45 · already at (or past) its Raids target level');
  assert.equal(sq.cost.dust, 0);
  // A league-only build: the league's own best level.
  const low = build('Tinkatink', 10, 'tinkaton');
  if (low.costArea === 'gl' || low.costArea === 'ul') assert.match(levelText(low), /^L10 → [\d.]+ \(best (GL|UL) level\)$/);
  // A level-51 copy that fits its league is already past its best level there.
  const cram = build('Cramorant', 51);
  assert.equal(cram.costArea, 'ul');
  assert.equal(levelText(cram), 'L51 · already at (or past) its best UL level');
  // The build the script used to crash on: Electabuzz -> Electivire at level 30 (no target level, no league cost).
  const eb = build('Electabuzz', 30, 'electivire');
  assert.equal(eb.targetLevel, null); assert.equal(eb.pvpCost, null);
  assert.equal(levelText(eb), 'L30 · already at (or past) its Rocket target level');
  // Every fixture build has wording, and a league label only when the cost is the league's.
  for (const b of analyseBox(box, ctx).allBuilds) {
    const t = levelText(b);
    assert.ok(t.startsWith(`L${b.level}`), t);
    if (/best (GL|UL|ML) level/.test(t)) assert.equal(b.costArea, b.pvpCost.league, t);
  }
});

test('actionText: power up only when there is something to power up; otherwise second move, or already built', () => {
  assert.equal(actionText(build('Xurkitree', 20)), 'Power up');
  assert.equal(actionText(build('Xurkitree', 40)), 'Already built');
  assert.equal(actionText(build('Squirtle', 45, 'blastoise')), 'Evolve to Blastoise');
  assert.equal(actionText(build('Cramorant', 51)), 'Second move');
});
