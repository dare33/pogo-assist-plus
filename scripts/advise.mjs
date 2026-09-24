#!/usr/bin/env node
// Print the advisor's report for an export. Usage: node scripts/advise.mjs fixtures/greg-2026-09-25.pokegenie.csv
import { readFileSync } from 'node:fs';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadGamemaster } from '../src/gamemaster.js';
import { loadTiers, loadRankings } from '../src/data.js';
import { analyseBox, AREA_LABEL } from '../src/advise.js';

const [csvPath] = process.argv.slice(2);
const ctx = { gm: loadGamemaster(), tiers: loadTiers(), rankings: loadRankings() };
const box = importPokeGenie(readFileSync(csvPath, 'utf8'));
const { builds, gaps, hygiene, pokemon } = analyseBox(box, ctx);

const iv = (p) => (p.ivs ? `${p.ivs.atk}/${p.ivs.def}/${p.ivs.hp}` : '?');
const label = (p) => `${p.name}${p.form && p.form !== 'Normal' ? ` (${p.form})` : ''}${p.shadow ? ' [Shadow]' : ''} CP ${p.cp} L${p.level} ${iv(p)}`;
const k = (n) => (n >= 1000 ? `${Math.round(n / 1000)}k` : String(n));

console.log(`# Builds (${builds.length}), best first\n`);
console.log('| # | Pokémon | Build | Areas | Tier | Cost from here | Score |');
console.log('|---|---|---|---|---|---|---|');
builds.slice(0, 40).forEach((b, i) => {
  const what = (b.targetId === b.speciesId ? 'power up' : `${b.formChange ? 'form change to' : 'evolve to'} ${b.targetName}`) + (b.viaMega ? ' + Mega' : '') + (b.needsDynamax ? ' (Max needs a Dynamax copy)' : '') + (b.spares.length ? ` [+${b.spares.length} spare]` : '');
  const cost = [`${k(b.cost.dust)} dust`, b.cost.candy ? `${b.cost.candy} candy` : '', b.cost.xl ? `${b.cost.xl} XL` : '', b.moveFlags.elite ? `${b.moveFlags.elite} Elite TM` : '', b.moveFlags.cd ? 'CD move' : ''].filter(Boolean).join(', ');
  const areas = b.areas.map((a) => AREA_LABEL[a]).join(', ');
  const pvp = b.pvpCost ? ` (${b.pvpCost.league.toUpperCase()} rank ${b.pvpCost.rank})` : '';
  const lv = b.targetLevel ? `L${b.level}→${b.targetLevel}: ` : `L${b.level}→best ${b.pvpCost.league.toUpperCase()} level: `;
  console.log(`| ${i + 1} | ${label(b.pokemon)} | ${what}${pvp} | ${areas} | ${b.bestTier} | ${lv}${cost} | ${b.score} |`);
});

console.log(`\n# Gaps: S and A entries nothing in the box can become (${gaps.length})\n`);
for (const g of gaps.filter((g) => g.tier === 'S').slice(0, 40)) console.log(`- ${g.tier} ${AREA_LABEL[g.area]}${g.section ? `/${g.section}` : ''}: **${g.name}** — ${g.obtain ?? ''}`);
console.log(`- … plus ${gaps.filter((g) => g.tier === 'A').length} A-tier gaps`);

console.log(`\n# Hygiene: duplicates (${hygiene.length} species)\n`);
for (const h of hygiene.slice(0, 15)) console.log(`- ${h.name} ×${h.count}: keep ${h.keep.map((p) => `CP ${p.cp} (${iv(p)})`).join(', ')}; transfer ${h.transfer.length}`);

const unresolved = pokemon.filter((e) => e.unresolved).map((e) => `${e.p.name} ${e.p.form}`);
if (unresolved.length) console.log('\nUnresolved:', [...new Set(unresolved)].join(', '));
