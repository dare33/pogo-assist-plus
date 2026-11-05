import test from 'node:test';
import assert from 'node:assert/strict';
import { parsePveMoves, matchToPvpoke, build, MAX_MOVE_POWER } from '../scripts/fetch-pve-moves.mjs';

const settings = (templateId, over) => ({ templateId, data: { templateId, moveSettings: { pokemonType: 'POKEMON_TYPE_DRAGON', power: 14, durationMs: 1000, energyDelta: 8, ...over } } });
const fixture = [
  { templateId: 'ACCESSIBILITY_CLIENT_SETTINGS', data: {} },
  settings('V0253_MOVE_DRAGON_TAIL_FAST'),
  settings('V0082_MOVE_DRAGON_CLAW', { power: 45, durationMs: 1500, energyDelta: -33 }),
  settings('V0999_MOVE_FUTURESIGHT', { pokemonType: 'POKEMON_TYPE_PSYCHIC', power: 120, durationMs: 2700, energyDelta: -100 }),
  settings('V0301_MOVE_HIDDEN_POWER_FAST', { pokemonType: 'POKEMON_TYPE_NORMAL', power: 15, durationMs: 1500, energyDelta: 10 }),
  // The PvP combat entry of the same move is not the raid one and is ignored.
  { templateId: 'COMBAT_V0253_MOVE_DRAGON_TAIL_FAST', data: { combatMove: { uniqueId: 'DRAGON_TAIL_FAST', type: 'POKEMON_TYPE_DRAGON', power: 9 } } },
];

test('parsePveMoves keeps the raid stats and drops _FAST from the id', () => {
  const m = parsePveMoves(fixture);
  assert.deepEqual(m.DRAGON_TAIL, { type: 'dragon', power: 14, durationMs: 1000, energyDelta: 8 });
  assert.deepEqual(m.DRAGON_CLAW, { type: 'dragon', power: 45, durationMs: 1500, energyDelta: -33 });
  assert.equal(m.COMBAT_V0253_MOVE_DRAGON_TAIL_FAST, undefined);
});

test('matchToPvpoke uses aliases, types a Hidden Power variant, and reports the rest', () => {
  const { moves, unmatched, approximated } = matchToPvpoke(parsePveMoves(fixture), ['DRAGON_TAIL', 'FUTURE_SIGHT', 'HIDDEN_POWER_FIRE', 'MYSTICAL_FIRE_PLUS', 'DRAGON_CLAW_PLUS', 'FUTURE_SIGHT_PLUS']);
  assert.deepEqual(approximated, ['DRAGON_CLAW_PLUS', 'FUTURE_SIGHT_PLUS']);
  assert.equal(moves.DRAGON_CLAW_PLUS.power, 45);
  assert.equal(moves.FUTURE_SIGHT.power, 120);
  assert.equal(moves.HIDDEN_POWER_FIRE.type, 'fire');
  assert.equal(moves.HIDDEN_POWER_FIRE.durationMs, 1500);
  assert.deepEqual(unmatched, ['MYSTICAL_FIRE_PLUS']);
});

test('build writes the source, the fetch time and the Max move powers', () => {
  const { file } = build(fixture, ['DRAGON_TAIL'], '2026-11-01T00:00:00.000Z');
  assert.equal(file.fetched, '2026-11-01T00:00:00.000Z');
  assert.match(file.source, /PokeMiners/);
  assert.deepEqual(file.maxMovePower, MAX_MOVE_POWER);
  assert.match(file.maxMovePowerSource, /Max Moves/);
  assert.match(file.note, /_PLUS/);
  assert.deepEqual(Object.keys(file.moves), ['DRAGON_TAIL']);
});
