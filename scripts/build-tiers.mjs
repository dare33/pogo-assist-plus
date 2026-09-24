#!/usr/bin/env node
// Build data/tiers.json from the markdown tier tables in data/source/.
// Usage: node scripts/build-tiers.mjs data/source data/tiers.json
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, basename } from 'node:path';
import { loadGamemaster } from '../src/node/load.js';
import { resolveSpecies } from '../src/gamemaster.js';

const [srcDir = 'data/source', outPath = 'data/tiers.json'] = process.argv.slice(2);
const gm = loadGamemaster();

// Which markdown file feeds which game area. Sections (## headings) inside 01 are attacking types.
const AREAS = {
  '01-general-pve-by-type.md': { area: 'raids', kind: 'pve-by-type', useSection: true },
  '02-high-tier-raids.md': { area: 'raids', kind: 'high-tier' },
  '03-gym-defense.md': { area: 'gym', kind: 'defence' },
  '04-team-rocket.md': { area: 'rocket', kind: 'attacker' },
  '05-great-league.md': { area: 'gl', kind: 'pvp' },
  '06-ultra-league.md': { area: 'ul', kind: 'pvp' },
  '07-master-league.md': { area: 'ml', kind: 'pvp' },
  '08-max-battles.md': { area: 'max', kind: 'max' },
};

function splitRow(line) { return line.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim()); }

function* tables(md) {
  const lines = md.split('\n');
  let section = '';
  for (let i = 0; i < lines.length; i++) {
    const h = lines[i].match(/^##\s+(.*)$/);
    if (h) section = h[1].trim();
    if (lines[i].trim().startsWith('|') && /^\|?\s*:?-{3,}/.test((lines[i + 1] || '').trim())) {
      const header = splitRow(lines[i]).map((c) => c.toLowerCase());
      i += 2;
      const rows = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) { rows.push(splitRow(lines[i])); i++; }
      yield { section, header, rows };
    }
  }
}

// "Shadow Blaziken, Shadow Chandelure (Fire Spin / Overheat), Flareon" -> [{name, moves}]
// "Mega Sceptile / Mega Chesnaught" -> two names. Keep parenthesised move hints as moves when the row has none.
function splitNames(cell) {
  const out = [];
  const parts = cell.split(/,\s*(?![^()]*\))/); // split on commas outside parentheses
  for (let part of parts) {
    part = part.trim();
    if (!part) continue;
    const m = part.match(/^(.*?)\s*\(([^)]*)\)\s*$/);
    let name = m ? m[1].trim() : part;
    const hint = m ? m[2].trim() : '';
    for (const sub of name.split(/\s+\/\s+/)) {
      const n = sub.replace(/\b(the|best of \d+|x\d+)\b/gi, '').replace(/\s+\d+\/\d+\/\d+.*$/, '').trim();
      if (n) out.push({ name: n, hint });
    }
  }
  return out;
}

const entries = [];
const unresolved = new Map();
for (const file of readdirSync(srcDir).filter((f) => f.endsWith('.md')).sort()) {
  const meta = AREAS[basename(file)];
  if (!meta) continue;
  const md = readFileSync(join(srcDir, file), 'utf8');
  for (const t of tables(md)) {
    const ti = t.header.indexOf('tier');
    const ni = t.header.findIndex((h) => h === 'pokémon' || h === 'pokemon');
    if (ti < 0 || ni < 0) continue; // not a tier table (lineups, schedules, etc.)
    const col = (name) => t.header.indexOf(name);
    const mi = ['moves', 'best moves', 'max move'].map(col).find((i) => i >= 0) ?? -1;
    const oi = ['obtain', 'obtain / cost', 'how to get'].map(col).find((i) => i >= 0) ?? -1;
    const xi = ['notes', 'maximise it', 'why'].map(col).find((i) => i >= 0) ?? -1;
    const ri = col('role'), ii = col('rank-1 ivs @ level'), rk = col('#');
    for (const row of t.rows) {
      const tier = row[ti];
      if (!/^[SAB]$/.test(tier)) continue;
      for (const { name, hint } of splitNames(row[ni])) {
        const r = resolveSpecies(gm, name);
        if (!r) { unresolved.set(name, (unresolved.get(name) || 0) + 1); continue; }
        entries.push({
          area: meta.area,
          kind: meta.kind,
          section: meta.useSection ? t.section : (t.section || null),
          tier,
          rank: rk >= 0 && row[rk] ? Number(row[rk]) : null,
          name,
          speciesId: r.speciesId,
          flags: { shadow: r.flags.shadow, mega: r.flags.mega, max: r.flags.max },
          role: ri >= 0 ? row[ri] : null,
          moves: mi >= 0 && row[mi] ? row[mi] : hint || null,
          ivs: ii >= 0 ? row[ii] : null,
          obtain: oi >= 0 ? row[oi] : null,
          notes: xi >= 0 ? row[xi] : null,
          source: basename(file),
        });
      }
    }
  }
}
writeFileSync(outPath, JSON.stringify({ generated: new Date().toISOString(), gamemaster: gm.timestamp, entries }, null, 1));
console.log(`${entries.length} tier entries -> ${outPath}`);
if (unresolved.size) {
  console.log(`UNRESOLVED (${unresolved.size}):`);
  for (const [n, c] of [...unresolved].sort()) console.log(`  ${n} ×${c}`);
}
