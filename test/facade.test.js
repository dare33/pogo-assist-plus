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
  // fit is compact: per area [tag, as, tier] with tag s / o / w, as and tier null for weak, then for weak the reason (and its extra at 4: the IV % for iv, the
  // species name for none), then, only on the copy carrying the advisor's build, [true, buildAs, dust, candy, xl] (from index 3 for s / o, from 5 for w); no sentence crosses.
  assert.deepEqual(Object.keys(r.pokemon[0].fit), ['raids', 'gym', 'rocket', 'max']);
  for (const f of Object.values(r.pokemon[0].fit)) {
    assert.ok(Array.isArray(f) && ['s', 'o', 'w'].includes(f[0]));
    if (f[0] === 'w') {
      assert.deepEqual([f[1], f[2], ['none', 'iv', 'ivUnknown', 'shadowNoMega'].includes(f[3])], [null, null, true]);
      assert.equal(f.length, f[3] === 'iv' || f[3] === 'none' ? 5 : 4);
      if (f[3] === 'iv') assert.equal(typeof f[4], 'number');
      if (f[3] === 'none') assert.equal(typeof f[4], 'string');
    } else assert.deepEqual([typeof f[1], typeof f[2], f.length], ['string', 'string', 3]);
  }
  assert.ok(r.pokemon.every((e) => e.unresolved || !('bestOf' in e) || (Array.isArray(e.bestOf) && e.bestOf.length)), 'bestOf is left out when empty');
  assert.deepEqual(r.pokemon[0].p, { index: box[0].index });
  assert.deepEqual(Object.keys(r.pokemon[0].leagues), ['gl', 'ul', 'ml']);
  for (const k of ['options', 'pick', 'experimental', 'source']) assert.ok(k in r.pokemon[0].leagues.gl, k);
  assert.ok(r.pokemon[0].leagues.gl.options[r.pokemon[0].leagues.gl.pick].speciesId);
  assert.deepEqual(r.pokemon[1], { p: { index: 2 }, unresolved: true });
  assert.equal(r.builds[0].pokemon.index !== undefined, true);
});

test('adviseJSON: 2,000 entries come back at 6.94 MB or less (6.7 MB before the slimming, 4 MB after it, then league options, then trimming moves, then the compact fit, then the build marker), the pokemon part about 4.9 MB', () => {
  const big = [];
  while (big.length < 2000) for (const p of box) if (big.length < 2000) big.push(p);
  const text = core.adviseJSON(JSON.stringify(big));
  const r = JSON.parse(text);
  assert.equal(r.pokemon.length, 2000);
  const pokemonChars = JSON.stringify(r.pokemon).length;
  // Sizes are characters (a JavaScript string length), not bytes: UTF-8 is 4,650 more on the total. The compact fit (and bestOf) added 257,900 to both figures (6,417,866 total and 4,520,798 pokemon part before, 6,675,766 and 4,778,698 after it; the iv figure in the weak arrays then made them 6,678,554 and 4,781,486). The build marker (a tail on the copies carrying a build) and the species name on the "none" lines then made them 6,757,539 and 4,860,471; both caps rose by the 78,985 that added, keeping the 179,346 and 76,414 of headroom the figures left (179,361 and 76,429 now, the caps being rounded to four digits).
  // ~2.2 KB of leagues per entry (the shown pick plus all members' own ratings, moves only on the shown and experimental ones) is most of it; builds and hygiene still carry whole Pokemon records (1.9 MB for this box).
  assert.ok(pokemonChars < 4.9369e6, `pokemon ${(pokemonChars / 1e6).toFixed(2)} MB`);
  assert.ok(text.length < 6.9369e6, `${(text.length / 1e6).toFixed(2)} MB`);
});

test('adviseJSON: the whole fixture keeps bestOf, a string tier on every strong / ok fit, the iv figure and species name on weak ones, and the build tail where a build is', () => {
  const r = JSON.parse(core.adviseJSON(JSON.stringify(box)));
  assert.equal(r.pokemon.length, 311);
  assert.ok(r.pokemon.some((e) => Array.isArray(e.bestOf) && e.bestOf.length), 'bestOf reaches the app');
  const fits = r.pokemon.flatMap((e) => Object.values(e.fit ?? {}));
  assert.ok(fits.some((f) => f[0] === 's') && fits.some((f) => f[0] === 'o') && fits.some((f) => f[0] === 'w' && f[3] === 'iv') && fits.some((f) => f[0] === 'w' && f[3] === 'none'));
  const tailAt = (f) => (f[0] === 'w' ? 5 : 3);
  let withBuild = 0;
  for (const f of fits) {
    if (f[0] !== 'w') assert.equal(typeof f[2], 'string', `tier of ${JSON.stringify(f)}`);
    else if (f[3] === 'iv') assert.equal(typeof f[4], 'number');
    else if (f[3] === 'none') assert.equal(typeof f[4], 'string');
    if (f.length > tailAt(f)) {
      // A tail is exactly [true, buildAs, dust, candy, xl]; a weak array with a tail holds its extra (or null) at 4.
      withBuild++;
      const t = f.slice(tailAt(f));
      assert.deepEqual([t.length, t[0], typeof t[1], typeof t[2], typeof t[3], typeof t[4]], [5, true, 'string', 'number', 'number', 'number'], JSON.stringify(f));
      if (f[0] === 'w') assert.ok(f.length === 10 && (f[4] === null || typeof f[4] !== 'object'), JSON.stringify(f));
    }
  }
  assert.ok(withBuild > 0, 'at least one fit carries a build');
  assert.ok(fits.some((f) => f[0] === 's' && f[3] === true) && fits.some((f) => f[0] === 'w' && f[5] === true), 'a build on a strong and on a weak copy');
});
