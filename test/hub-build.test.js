import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const hub = JSON.parse(readFileSync(join(ROOT, 'data', 'hub.json'), 'utf8'));
const TYPES = ['normal', 'fire', 'water', 'electric', 'grass', 'ice', 'fighting', 'poison', 'ground', 'flying', 'psychic', 'bug', 'rock', 'ghost', 'dragon', 'dark', 'steel', 'fairy'];

test('hub.json is a rebuild of data/source (a hand edit without a rebuild fails)', () => {
  const out = join(mkdtempSync(join(tmpdir(), 'hub-')), 'hub.json');
  execFileSync('node', [join(ROOT, 'scripts', 'build-hub.mjs'), join(ROOT, 'data', 'source'), out], { stdio: 'pipe' });
  const rebuilt = JSON.parse(readFileSync(out, 'utf8'));
  // `generated` is the build time, so it is the one field that may differ.
  const strip = ({ generated, ...rest }) => rest;
  assert.deepEqual(strip(rebuilt), strip(hub));
});

test('type chart spot checks', () => {
  const c = hub.typeChart;
  assert.equal(c.fire.grass, 1.6);
  assert.equal(c.water.fire, 1.6);
  assert.equal(c.ground.flying, 0.390625);
  assert.equal(c.normal.ghost, 0.390625);
  assert.equal(c.ghost.normal, 0.390625);
  assert.equal(c.fairy.dragon, 1.6);
  assert.equal(c.steel.fairy, 1.6);
  assert.equal(c.fighting.ghost, 0.390625);
  assert.equal(c.electric.ground, 0.390625);
  assert.equal(c.psychic.dark, 0.390625);
  assert.equal(c.poison.steel, 0.390625);
  assert.equal(c.dragon.fairy, 0.390625);
});

test('chart: how many types are super effective against each defending type', () => {
  const known = { normal: 1, fire: 3, water: 2, electric: 1, grass: 5, ice: 4, fighting: 3, poison: 2, ground: 3, flying: 3, psychic: 3, bug: 3, rock: 5, ghost: 2, dragon: 3, dark: 3, steel: 3, fairy: 2 };
  assert.deepEqual(Object.keys(hub.typeChart), TYPES);
  for (const def of TYPES) {
    const n = TYPES.filter((att) => hub.typeChart[att][def] === 1.6).length;
    assert.equal(n, known[def], `${def}`);
  }
});

test('every rotation boss and leader slot option has a species id and one or two types', () => {
  const all = [...hub.rotation.flatMap((r) => r.bosses), ...hub.leaders.flatMap((l) => l.slots.flat())];
  assert.ok(all.length > 30);
  for (const p of all) {
    assert.ok(p.name && p.speciesId, JSON.stringify(p));
    assert.ok(p.types.length >= 1 && p.types.length <= 2, `${p.name} types ${p.types}`);
    for (const t of p.types) assert.ok(TYPES.includes(t), `${p.name}: ${t}`);
  }
  for (const l of hub.leaders) {
    assert.equal(l.slots.length, 3, l.name);
    for (const s of l.slots) assert.ok(s.length >= 1, l.name);
  }
});

test('the Nov 16 Max Monday has no species yet', () => {
  const row = hub.rotation.find((r) => r.kind === 'maxmon' && r.from === '2026-11-16');
  assert.ok(row);
  assert.deepEqual(row.bosses, []);
});

test('every date parses and from <= to; every event tie is empty or a Hub screen', () => {
  const ok = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s) && new Date(`${s}T00:00:00Z`).toISOString().startsWith(s);
  for (const r of [...hub.rotation, ...hub.events]) {
    assert.ok(ok(r.from) && ok(r.to), `${r.title}: ${r.from} ${r.to}`);
    assert.ok(r.from <= r.to, `${r.title}: from after to`);
  }
  for (const k of new Set(hub.rotation.map((r) => r.kind))) assert.ok(['5star', 'mega', 'shadow', 'maxmon', 'battleday', 'event', 'raidhour'].includes(k), k);
  for (const e of hub.events) assert.ok(['', 'everything', 'raids', 'gym', 'rocket', 'pvp', 'max'].includes(e.tie), `${e.title}: ${e.tie}`);
});

test('leaders and grunts', () => {
  assert.deepEqual(hub.leaders.map((l) => l.name), ['Giovanni', 'Sierra', 'Cliff', 'Arlo']);
  assert.equal(hub.leaders[0].since, '2026-10-04');
  assert.equal(hub.grunts.length, 19);
  assert.equal(hub.grunts.filter((g) => g.type === '').length, 1);
  for (const t of TYPES) assert.ok(hub.grunts.some((g) => g.type === t), t);
});

test('an unresolvable boss name fails the build with exit 1 and names it', () => {
  const dir = mkdtempSync(join(tmpdir(), 'hub-bad-'));
  const src = join(dir, 'src');
  mkdirSync(src);
  for (const f of ['10-hub-rotation.md', '11-rocket-lineups.md', '12-type-chart.md']) {
    const text = readFileSync(join(ROOT, 'data', 'source', f), 'utf8');
    writeFileSync(join(src, f), f === '10-hub-rotation.md' ? text.replace('Palkia', 'Zzyzx') : text);
  }
  assert.throws(() => execFileSync('node', [join(ROOT, 'scripts', 'build-hub.mjs'), src, join(dir, 'out.json')], { stdio: 'pipe' }),
    (e) => e.status === 1 && /Zzyzx/.test(String(e.stderr)));
});
