// The solver must give exactly what it gave before it was sped up. `solveOracle` below is the previous
// implementation (a scan of every level for each IV combination), kept verbatim as the oracle.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { solve } from '../../src/extract/solve.js';
import { cpAt, hpAt, LEVELS } from '../../src/cpm.js';
import { loadGamemaster } from '../../src/node/load.js';

function solveOracle({ species, cp, hp = null, ivs = null }) {
  if (!cp || !species?.length) return { status: 'none', solutions: [] };
  const fits = [];
  for (const sp of species) {
    for (const c of allCombos()) {
      for (const level of LEVELS) {
        const v = cpAt(sp.baseStats, c, level);
        if (v > cp) break;
        if (v !== cp) continue;
        const h = hpAt(sp.baseStats, c, level);
        if (hp !== null && h !== hp) continue;
        fits.push({ speciesId: sp.speciesId, ivs: c, level, hp: h, tier: ivs ? tierOf(ivs, c) : 3 });
      }
    }
  }
  if (!fits.length) return { status: ivs ? 'none' : 'unknown-ivs', solutions: [] };
  // Ties between forms with the same stats (costume Pikachu, say) go to the plainest id, and are
  // reported so the row can be flagged: the screen name does not say which form it is.
  fits.sort((a, b) => a.tier - b.tier || dist(ivs, a.ivs) - dist(ivs, b.ivs) || a.level - b.level || a.speciesId.length - b.speciesId.length || (a.speciesId < b.speciesId ? -1 : 1));
  const bestTier = fits[0].tier;
  const top = fits.filter((f) => f.tier === bestTier);
  const forms = new Set(top.map((s) => s.speciesId));
  const out = (status) => ({ status, solutions: fits, forms: [...forms] });
  if (!ivs) return out('unknown-ivs');
  const distinct = new Set(top.map((s) => `${s.ivs.atk}/${s.ivs.def}/${s.ivs.hp}`));
  if (distinct.size > 1 && bestTier > 0) return out('ambiguous');
  return out(['exact', 'corrected', 'ambiguous'][bestTier]);
}

function tierOf(read, c) {
  const r = [read.atk, read.def, read.hp], t = [c.atk, c.def, c.hp];
  if (r.every((v, i) => v === t[i])) return 0;
  if (r.every((v, i) => Math.abs(v - t[i]) <= 1)) return 1;
  return 2;
}

function dist(a, b) { return a ? Math.abs(a.atk - b.atk) + Math.abs(a.def - b.def) + Math.abs(a.hp - b.hp) : 0; }

let ALL = null;
function allCombos() {
  if (!ALL) { ALL = []; for (let a = 0; a <= 15; a++) for (let d = 0; d <= 15; d++) for (let h = 0; h <= 15; h++) ALL.push({ atk: a, def: d, hp: h }); }
  return ALL;
}


function rng(seed) { let s = seed >>> 0; return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; }; }

test('solve gives the same result as the level-scanning original on random inputs', () => {
  const gm = loadGamemaster();
  const all = [...gm.byId.values()].filter((p) => p.baseStats);
  const rand = rng(20261002);
  const pick = (a) => a[Math.floor(rand() * a.length)];
  const int = (lo, hi) => lo + Math.floor(rand() * (hi - lo + 1));
  let withFits = 0;
  const N = 3000;
  for (let n = 0; n < N; n++) {
    const k = rand() < 0.3 ? int(2, 3) : 1;
    const species = Array.from({ length: k }, () => { const p = pick(all); return { speciesId: p.speciesId, baseStats: p.baseStats, speciesName: p.speciesName }; });
    const base = species[0].baseStats;
    // mostly a real Pokemon (CP and HP from a random level and IVs), sometimes perturbed or impossible
    const iv = { atk: int(0, 15), def: int(0, 15), hp: int(0, 15) };
    const level = pick(LEVELS);
    let cp = cpAt(base, iv, level), hp = hpAt(base, iv, level);
    const r = rand();
    if (r < 0.1) cp += int(-3, 3);
    else if (r < 0.15) cp = int(0, 6000);
    else if (r < 0.18) cp = null;
    else if (r < 0.2) cp = 0;
    else if (r < 0.22) cp = -5;
    else if (r < 0.24) cp = 1e9;
    const h = rand();
    if (h < 0.2) hp = null; else if (h < 0.3) hp += int(-2, 2); else if (h < 0.35) hp = 1;
    let ivs = { ...iv };
    const b = rand();
    if (b < 0.2) ivs = null;
    else if (b < 0.4) ivs = { atk: Math.min(15, Math.max(0, iv.atk + int(-1, 1))), def: Math.min(15, Math.max(0, iv.def + int(-1, 1))), hp: Math.min(15, Math.max(0, iv.hp + int(-1, 1))) };
    else if (b < 0.5) ivs = { atk: int(0, 15), def: int(0, 15), hp: int(0, 15) };
    else if (b < 0.52) ivs = { atk: 16, def: -1, hp: 40 };
    const input = { species: n % 97 === 0 ? [] : species, cp, hp, ivs };
    const want = solveOracle(structuredClone(input)), got = solve(structuredClone(input));
    assert.deepEqual(got, want, `case ${n}: ${JSON.stringify(input)}`);
    if (want.solutions.length) withFits++;
  }
  assert.ok(withFits > N / 2, `only ${withFits} of ${N} cases had a fit; the generator is not exercising the solver`);
  // an input with no `hp` key and one with an undefined cp, as callers may pass them
  assert.deepEqual(solve({ species: [{ speciesId: 'x', baseStats: all[0].baseStats }], cp: 500 }), solveOracle({ species: [{ speciesId: 'x', baseStats: all[0].baseStats }], cp: 500 }));
  assert.deepEqual(solve({ species: [], cp: 500 }), solveOracle({ species: [], cp: 500 }));
  assert.deepEqual(solve({ species: undefined, cp: 500 }), solveOracle({ species: undefined, cp: 500 }));
});
