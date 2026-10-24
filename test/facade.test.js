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

test('adviseJSON: pokemon entries are only { p: { index }, unresolved, speciesId, leagues, fit, bestOf when present }', () => {
  const rows = [box[0], { ...box[1], name: 'Notamon', index: 2 }, box[2]];
  const r = JSON.parse(core.adviseJSON(JSON.stringify(rows)));
  assert.deepEqual(Object.keys(r).sort(), ['areaLabel', 'builds', 'gaps', 'hygiene', 'pokemon']);
  assert.equal(r.pokemon.length, 3);
  const keys = Object.keys(r.pokemon[0]).sort();
  assert.deepEqual(keys.filter((k) => k !== 'bestOf'), ['fit', 'leagues', 'p', 'speciesId']);
  // fit is compact: per area [tag, as, tier, reason] with tag s / o / w, as and tier null for weak, reason only for weak; no sentence crosses.
  assert.deepEqual(Object.keys(r.pokemon[0].fit), ['raids', 'gym', 'rocket', 'max']);
  for (const f of Object.values(r.pokemon[0].fit)) {
    assert.ok(Array.isArray(f) && ['s', 'o', 'w'].includes(f[0]));
    if (f[0] === 'w') assert.deepEqual([f[1], f[2], ['none', 'iv', 'ivUnknown', 'shadowNoMega'].includes(f[3])], [null, null, true]);
    else assert.equal(typeof f[1], 'string');
  }
  assert.ok(r.pokemon.every((e) => e.unresolved || !('bestOf' in e) || (Array.isArray(e.bestOf) && e.bestOf.length)), 'bestOf is left out when empty');
  assert.deepEqual(r.pokemon[0].p, { index: box[0].index });
  assert.deepEqual(Object.keys(r.pokemon[0].leagues), ['gl', 'ul', 'ml']);
  for (const k of ['options', 'pick', 'experimental', 'source']) assert.ok(k in r.pokemon[0].leagues.gl, k);
  assert.ok(r.pokemon[0].leagues.gl.options[r.pokemon[0].leagues.gl.pick].speciesId);
  assert.deepEqual(r.pokemon[1], { p: { index: 2 }, unresolved: true });
  assert.equal(r.builds[0].pokemon.index !== undefined, true);
});

test('adviseJSON: 2,000 entries come back at 6.9 MB or less (6.7 MB before the slimming, 4 MB after it, then league options, then trimming moves, then the compact fit), the pokemon part about 4.8 MB', () => {
  const big = [];
  while (big.length < 2000) for (const p of box) if (big.length < 2000) big.push(p);
  const text = core.adviseJSON(JSON.stringify(big));
  const r = JSON.parse(text);
  assert.equal(r.pokemon.length, 2000);
  const pokemonBytes = JSON.stringify(r.pokemon).length;
  // The compact fit (and bestOf) added 257,900 bytes to both figures (6,417,866 total and 4,520,798 pokemon part before, 6,675,766 and 4,778,698 now); both caps rose by that, keeping the 182,134 and 79,202 bytes of headroom the old caps had.
  // ~2.2 KB of leagues per entry (the shown pick plus all members' own ratings, moves only on the shown and experimental ones) is most of it; builds and hygiene still carry whole Pokemon records (1.9 MB for this box).
  assert.ok(pokemonBytes < 4.8579e6, `pokemon ${(pokemonBytes / 1e6).toFixed(2)} MB`);
  assert.ok(text.length < 6.8579e6, `${(text.length / 1e6).toFixed(2)} MB`);
});
