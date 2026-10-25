import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../scripts/build-tiers.mjs', import.meta.url));

// Runs the real build on a one-file source folder holding a Max table with the given Pokémon cell.
function buildMax(cell) {
  const dir = mkdtempSync(join(tmpdir(), 'tiers-'));
  try {
    const src = join(dir, 'src'); const out = join(dir, 'tiers.json');
    mkdirSync(src);
    writeFileSync(join(src, '08-max-battles.md'), `## Attackers\n\n| Tier | Pokémon | Max move |\n|---|---|---|\n| A | ${cell} | x |\n`);
    const r = spawnSync(process.execPath, [script, src, out], { encoding: 'utf8' });
    return { r, tiers: r.status === 0 ? JSON.parse(readFileSync(out, 'utf8')) : null };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

test('the build refuses an unprefixed later name in a Gigantamax or Dynamax row, naming file, row and name', () => {
  for (const cell of ['Gigantamax Charizard, Toxtricity', 'Dynamax Inteleon / Kingler']) {
    const { r } = buildMax(cell);
    assert.notEqual(r.status, 0, cell);
    assert.match(r.stderr, /08-max-battles\.md/);
    assert.ok(r.stderr.includes(cell), `row missing from: ${r.stderr}`);
    assert.match(r.stderr, new RegExp(`"${cell.split(/, | \/ /)[1]}"`));
  }
});

test('the build accepts a fully prefixed Max row and marks every name as a Max entry', () => {
  const { r, tiers } = buildMax('Gigantamax Charizard, Gigantamax Toxtricity, Gigantamax Lapras');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(tiers.entries.map((e) => e.name), ['Gigantamax Charizard', 'Gigantamax Toxtricity', 'Gigantamax Lapras']);
  assert.ok(tiers.entries.every((e) => e.flags.max));
});

test('the committed tiers have no plain-named Max entry from a Gigantamax/Dynamax attacker row', () => {
  const tiers = JSON.parse(readFileSync(new URL('../data/tiers.json', import.meta.url), 'utf8'));
  const attackers = tiers.entries.filter((e) => e.area === 'max' && e.section === 'Attackers');
  assert.ok(attackers.length > 10);
  for (const e of attackers) if (!/^Crowned /.test(e.name)) assert.match(e.name, /^(Gigantamax|Dynamax) /, e.name);
  for (const n of ['Toxtricity', 'Lapras', 'Grimmsnarl', 'Venusaur', 'Blastoise', 'Butterfree', 'Snorlax', 'Pikachu', 'Meowth', 'Kingler'])
    assert.ok(tiers.entries.some((e) => e.name === `Gigantamax ${n}` && e.flags.max), n);
});
