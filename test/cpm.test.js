import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cpAt, hpAt, cpm } from '../src/cpm.js';
import { powerUpCost, step } from '../src/cost.js';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadGamemaster } from '../src/node/load.js';
import { resolveSpecies } from '../src/gamemaster.js';

const gm = loadGamemaster();
const box = importPokeGenie(readFileSync(new URL('../fixtures/greg-2026-09-25.pokegenie.csv', import.meta.url), 'utf8'));

test('known CP anchors', () => {
  const mewtwo = gm.byId.get('mewtwo').baseStats;
  assert.equal(cpAt(mewtwo, { atk: 15, def: 15, hp: 15 }, 40), 4178);
  assert.equal(cpAt(mewtwo, { atk: 15, def: 15, hp: 15 }, 20), 2387);
  assert.equal(cpm(25), 0.667934);
});

test('every fixture row with exact IVs recomputes to its scanned CP and HP', () => {
  let checked = 0;
  const bad = [];
  for (const p of box) {
    if (!p.ivs || p.levelMin !== p.levelMax) continue;
    const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
    assert.ok(r, `unresolved ${p.name} ${p.form}`);
    // A Poke Genie scan of a Mega form records the Mega's CP: use the Mega's own stats then.
    let species = r.species;
    if (r.flags.megaForm) {
      const megaId = `${r.speciesId}_${r.flags.megaForm.toLowerCase().replace(' ', '_')}`;
      species = gm.byId.get(megaId) ?? species;
    }
    const cp = cpAt(species.baseStats, p.ivs, p.level);
    const hp = hpAt(species.baseStats, p.ivs, p.level);
    if (cp !== p.cp || hp !== p.hp) bad.push(`${p.name} ${p.form} L${p.level} ${p.ivs.atk}/${p.ivs.def}/${p.ivs.hp}: cp ${cp} vs ${p.cp}, hp ${hp} vs ${p.hp}`);
    checked++;
  }
  assert.ok(checked > 200, `only ${checked} rows checked`);
  assert.deepEqual(bad, []);
});

test('power-up cost totals match the known milestones', () => {
  assert.deepEqual(powerUpCost(1, 40), { dust: 270000, candy: 304, xl: 0, steps: 78 });
  assert.deepEqual(powerUpCost(40, 50), { dust: 250000, candy: 0, xl: 296, steps: 20 });
  assert.equal(step(35).dust, 8000);
  assert.equal(step(50).dust, 0);
  assert.equal(powerUpCost(20, 21, { shadow: true }).dust, Math.round(5000 * 1.2));
  assert.equal(powerUpCost(20, 21, { lucky: true }).dust, 2500);
});

test('Great League dust and candy costs in the fixture match the tables for non-evolving rows', () => {
  // Poke Genie's Dust/Candy Cost (G) is the cost from the current level to the best GL level of the same species.
  let checked = 0;
  for (const p of box) {
    if (!p.ivs || p.pvp.great.name !== p.name || p.pvp.great.dust === null || p.pvp.great.dust === 0) continue;
    // Walk levels until the dust matches; the candy must match at that level too.
    let target = null;
    for (let lv = p.level + 0.5; lv <= 40; lv += 0.5) {
      if (powerUpCost(p.level, lv).dust === p.pvp.great.dust) { target = lv; break; }
    }
    if (target === null) continue; // above 40: Poke Genie folds XL into its own candy figure; not comparable here
    assert.equal(powerUpCost(p.level, target).candy, p.pvp.great.candy, `${p.name} L${p.level}->${target}`);
    checked++;
  }
  assert.ok(checked >= 40, `only ${checked} rows checked`);
});
