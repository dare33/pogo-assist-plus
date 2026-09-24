#!/usr/bin/env node
// Annotate a Poke Genie export with tier hits. Usage: node scripts/dump-box.mjs fixtures/greg-2026-09-25.pokegenie.csv
import { readFileSync } from 'node:fs';
import { importPokeGenie } from '../src/import/pokegenie.js';
import { loadGamemaster } from '../src/node/load.js';
import { resolveSpecies, evolutionsOf, formChangesOf, megaIdsOf } from '../src/gamemaster.js';

const [csvPath, tiersPath = 'data/tiers.json'] = process.argv.slice(2);
if (!csvPath) { console.error('usage: dump-box.mjs <pokegenie.csv> [tiers.json]'); process.exit(1); }
const gm = loadGamemaster();
const tiers = JSON.parse(readFileSync(tiersPath, 'utf8')).entries;
const byId = new Map();
for (const e of tiers) { if (!byId.has(e.speciesId)) byId.set(e.speciesId, []); byId.get(e.speciesId).push(e); }

const box = importPokeGenie(readFileSync(csvPath, 'utf8'));
const TIER_W = { S: 3, A: 2, B: 1 };
let unresolved = [];
const rows = [];
for (const p of box) {
  const r = resolveSpecies(gm, p.name, { form: p.form, shadow: p.shadow });
  if (!r) { unresolved.push(`${p.name} ${p.form}`); continue; }
  // Candidate ids: itself, its evolutions, and (if regular) the megas of each; shadows only match shadow entries.
  const ids = new Set([r.speciesId, ...evolutionsOf(gm, r.speciesId), ...formChangesOf(gm, r.speciesId)]);
  if (!p.shadow) for (const id of [...ids]) for (const m of megaIdsOf(gm, id)) ids.add(m);
  const hits = [];
  for (const id of ids) for (const e of byId.get(id) || []) hits.push({ ...e, via: id === r.speciesId ? 'self' : id });
  if (!hits.length) continue;
  const score = hits.reduce((s, h) => s + TIER_W[h.tier], 0);
  rows.push({ p, r, hits, score });
}
rows.sort((a, b) => b.score - a.score || b.p.cp - a.p.cp);
for (const { p, r, hits } of rows) {
  const iv = p.ivs ? `${p.ivs.atk}/${p.ivs.def}/${p.ivs.hp}` : '?/?/?';
  console.log(`\n${p.name}${p.form && p.form !== 'Normal' ? ` (${p.form})` : ''}${p.shadow ? ' [Shadow]' : ''}  CP ${p.cp}  L${p.level}  IV ${iv}  -> ${r.speciesId}`);
  const seen = new Set();
  for (const h of hits.sort((a, b) => TIER_W[b.tier] - TIER_W[a.tier])) {
    const key = `${h.area}|${h.section}|${h.name}|${h.tier}`;
    if (seen.has(key)) continue; seen.add(key);
    const where = h.area + (h.section ? `/${h.section}` : '');
    console.log(`   ${h.tier}  ${where.padEnd(22)} ${h.name}${h.via !== 'self' ? `  (as ${h.via})` : ''}${h.moves ? `  — ${h.moves}` : ''}`);
  }
}
console.log(`\n${rows.length} of ${box.length} Pokémon have at least one tier hit; ${box.length - rows.length} have none.`);
if (unresolved.length) console.log('Unresolved:', [...new Set(unresolved)].join(', '));
