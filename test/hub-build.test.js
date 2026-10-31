import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync } from 'node:fs';
import { spawnSync, execFileSync } from 'node:child_process';
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

test('rows with a boss still to be announced say so; Dynamax Trails is its own Max kind with no boss cell', () => {
  const tba = hub.rotation.filter((r) => r.tba);
  assert.deepEqual(tba.map((r) => `${r.kind} ${r.from}`), ['maxmon 2026-11-16', 'battleday 2026-11-28']);
  for (const r of tba) assert.deepEqual(r.bosses, []);
  const trails = hub.rotation.find((r) => r.title === 'Dynamax Trails');
  assert.equal(trails.kind, 'maxevent');
  assert.deepEqual(trails.bosses, []);
  assert.ok(!trails.tba);
  assert.ok(hub.rotation.filter((r) => !r.tba).every((r) => r.tba === undefined));
});

test('the rotation holds raids and Max battles only (seasonal events are in the strip)', () => {
  assert.deepEqual([...new Set(hub.rotation.map((r) => r.kind))].sort(), ['5star', 'battleday', 'maxevent', 'maxmon', 'mega', 'raidhour', 'shadow']);
  for (const title of ['Halloween Part Two', 'Into the Wild', 'Global GO Wild Area', 'Twilight Wishes', 'Pawniard Community Day']) {
    assert.ok(!hub.rotation.some((r) => r.title.startsWith(title)), title);
    assert.ok(hub.events.some((e) => e.title.startsWith(title)), title);
  }
});

test('an unreleased Shadow keeps its name and is marked shadow', () => {
  const persian = hub.leaders[0].slots[0][0];
  assert.equal(persian.name, 'Shadow Persian');
  assert.ok(persian.speciesId.endsWith('_shadow') && persian.shadow === undefined);
  const zekrom = hub.leaders[0].slots[2][0];
  assert.equal(zekrom.name, 'Shadow Zekrom');
  assert.equal(zekrom.shadow, true);
});

test('every date parses and from <= to; every event tie is empty or a Hub screen', () => {
  const ok = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s) && new Date(`${s}T00:00:00Z`).toISOString().startsWith(s);
  for (const r of [...hub.rotation, ...hub.events]) {
    assert.ok(ok(r.from) && ok(r.to), `${r.title}: ${r.from} ${r.to}`);
    assert.ok(r.from <= r.to, `${r.title}: from after to`);
  }
  for (const k of new Set(hub.rotation.map((r) => r.kind))) assert.ok(['5star', 'mega', 'shadow', 'maxmon', 'maxevent', 'battleday', 'raidhour'].includes(k), k);
  for (const e of hub.events) assert.ok(['', 'everything', 'raids', 'gym', 'rocket', 'pvp', 'max'].includes(e.tie), `${e.title}: ${e.tie}`);
});

test('leaders and grunts', () => {
  assert.deepEqual(hub.leaders.map((l) => l.name), ['Giovanni', 'Sierra', 'Cliff', 'Arlo']);
  assert.ok(hub.leaders.every((l) => l.since === '2026-10'));
  assert.equal(hub.grunts.length, 20);
  assert.deepEqual(hub.grunts.filter((g) => g.type === '').map((g) => g.label), ['Mixed team', 'Decoy']);
  assert.equal(hub.grunts.find((g) => g.type === 'normal').quote, 'Normal does not mean weak.');
  assert.equal(hub.grunts.find((g) => g.label === 'Mixed team').quote, 'Winning is for winners');
  const cliff = hub.leaders.find((l) => l.name === 'Cliff');
  assert.deepEqual(cliff.slots[1].map((p) => p.name), ['Shadow Snorlax', 'Shadow Golurk', 'Shadow Galarian Weezing']);
  for (const t of TYPES) assert.ok(hub.grunts.some((g) => g.type === t), t);
});

// Each case edits one line of a source and expects the build to refuse it (exit 1) and name the problem.
function build(file, from, to) {
  const dir = mkdtempSync(join(tmpdir(), 'hub-bad-'));
  const src = join(dir, 'src');
  mkdirSync(src);
  for (const f of ['10-hub-rotation.md', '11-rocket-lineups.md', '12-type-chart.md']) {
    let text = readFileSync(join(ROOT, 'data', 'source', f), 'utf8');
    if (f === file) { assert.ok(text.includes(from), `${from} is in ${f}`); text = text.replace(from, to); }
    writeFileSync(join(src, f), text);
  }
  return spawnSync('node', [join(ROOT, 'scripts', 'build-hub.mjs'), src, join(dir, 'out.json')], { encoding: 'utf8' });
}

const ROT = '10-hub-rotation.md', RK = '11-rocket-lineups.md', CH = '12-type-chart.md';
for (const [label, file, from, to, message] of [
  ['an unresolvable boss name', ROT, '| Palkia |', '| Zzyzx |', /cannot resolve "Zzyzx"/],
  ['a name that resolves only by the first-word guess', ROT, '| Palkia |', '| Cryogonal Zzyzx |', /only resolves by a guess/],
  ['a name with a repeated word', ROT, '| Palkia |', '| Cryogonal Cryogonal |', /only resolves by a guess/],
  ['a repeated Shadow word', ROT, '| Palkia |', '| Shadow Shadow Palkia |', /only resolves by a guess/],
  ['a Mega name that does not end on a Mega', ROT, '| Palkia |', '| Mega Palkia |', /not a Mega/],
  ['a 5-star row with no boss', ROT, '| 5star | 5-star raid | Palkia |', '| 5star | 5-star raid | |', /needs a boss or "to be announced"/],
  ['a row with a missing cell', ROT, '| 5star | 5-star raid | Palkia | |', '| 5star | 5-star raid | Palkia |', /cells, the header has 7/],
  ['a row with an extra cell', ROT, '| 5star | 5-star raid | Palkia |', '| 5star | 5-star raid | Palkia | | extra |', /cells, the header has 7/],
  ['an unknown kind', ROT, '| 5star | 5-star raid | Palkia |', '| 5star2 | 5-star raid | Palkia |', /unknown kind "5star2"/],
  ['an empty title', ROT, '| 5star | 5-star raid | Palkia |', '| 5star | | Palkia |', /no title/],
  ['an unknown tie', ROT, '| pvp |', '| pvpx |', /unknown tie/],
  ['a bad date', ROT, '| 2026-10-21 | 2026-10-27 | 5star', '| 2026-10-32 | 2026-10-27 | 5star', /not a yyyy-mm-dd date/],
  ['a grunt type that is not one of the 18', RK, '| fire | Do you know', '| fyre | Do you know', /not one of the 18 types/],
  ['a typeless grunt with no label', RK, '|  | Fooled ya, twerp | Decoy |', '|  | Fooled ya, twerp | |', /needs a label/],
  ['a chart cell that is not a multiplier', CH, '| normal | 1 |', '| normal | 2 |', /is not 1, 1.6/],
]) {
  test(`the build refuses ${label}`, () => {
    const r = build(file, from, to);
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stderr, message);
  });
}
