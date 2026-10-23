// The app-core facade (native/tools/pogo-core-facade.js), run against the real modules in a vm: the bundle tool wraps each module in a
// function scope and hands the facade `__use`; here `__use` hands it the ES modules directly, so no build (and no clean tree) is needed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import { importPokeGenie } from '../src/import/pokegenie.js';

const modules = {
  'src/extract/pipeline.js': await import('../src/extract/pipeline.js'),
  'src/extract/batch.js': await import('../src/extract/batch.js'),
  'src/gamemaster.js': await import('../src/gamemaster.js'),
  'src/data.js': await import('../src/data.js'),
  'src/advise.js': await import('../src/advise.js'),
  'src/leagues.js': await import('../src/leagues.js'),
  'src/import/pokegenie.js': await import('../src/import/pokegenie.js'),
};
const sandbox = { __use: (path) => modules[path] };
sandbox.global = sandbox;
vm.createContext(sandbox);
vm.runInContext(readFileSync(new URL('../native/tools/pogo-core-facade.js', import.meta.url), 'utf8'), sandbox);
const core = sandbox.PogoCore;
const data = (f) => readFileSync(new URL(`../data/${f}`, import.meta.url), 'utf8');
core.load(data('gamemaster.json'), data('tiers.json'), data('pvp-rankings.json'));
const box = importPokeGenie(readFileSync(new URL('../fixtures/greg-2026-09-25.pokegenie.csv', import.meta.url), 'utf8'));

test('adviseJSON: pokemon entries are only { p: { index }, unresolved, speciesId, leagues }', () => {
  const rows = [box[0], { ...box[1], name: 'Notamon', index: 2 }, box[2]];
  const r = JSON.parse(core.adviseJSON(JSON.stringify(rows)));
  assert.deepEqual(Object.keys(r).sort(), ['areaLabel', 'builds', 'gaps', 'hygiene', 'pokemon', 'pvpScore']);
  assert.deepEqual(r.pvpScore, { gl: 88, ul: 88, ml: 88 }, "the advisor's PvP bar, which the Leagues card reads");
  assert.equal(r.pokemon.length, 3);
  assert.deepEqual(Object.keys(r.pokemon[0]).sort(), ['leagues', 'p', 'speciesId']);
  assert.deepEqual(r.pokemon[0].p, { index: box[0].index });
  assert.deepEqual(Object.keys(r.pokemon[0].leagues), ['gl', 'ul', 'ml']);
  for (const k of ['options', 'pick', 'experimental', 'source']) assert.ok(k in r.pokemon[0].leagues.gl, k);
  assert.ok(r.pokemon[0].leagues.gl.options[r.pokemon[0].leagues.gl.pick].speciesId);
  assert.deepEqual(r.pokemon[1], { p: { index: 2 }, unresolved: true });
  assert.equal(r.builds[0].pokemon.index !== undefined, true);
});

test('adviseJSON: 2,000 entries come back at 6.6 MB or less (6.7 MB before the slimming, 4 MB after it, then league options, then trimming moves), the pokemon part about 4.4 MB', () => {
  const big = [];
  while (big.length < 2000) for (const p of box) if (big.length < 2000) big.push(p);
  const text = core.adviseJSON(JSON.stringify(big));
  const r = JSON.parse(text);
  assert.equal(r.pokemon.length, 2000);
  const pokemonBytes = JSON.stringify(r.pokemon).length;
  // ~2.2 KB of leagues per entry (every member's own rating, with moves on each member PvPoke ranks) is most of it; builds and hygiene still carry whole Pokemon records (1.9 MB for this box).
  assert.ok(pokemonBytes < 4.6e6, `pokemon ${(pokemonBytes / 1e6).toFixed(2)} MB`);
  assert.ok(text.length < 6.6e6, `${(text.length / 1e6).toFixed(2)} MB`);
});
