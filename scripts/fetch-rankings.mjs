#!/usr/bin/env node
// Download PvPoke's overall rankings for Great, Ultra and Master League and keep only what the advisor needs.
// Usage: node scripts/fetch-rankings.mjs [--from-local data/rankings]   (local mode reuses already-downloaded raw files)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';

const BASE = 'https://raw.githubusercontent.com/pvpoke/pvpoke/master/src/data/rankings/all/overall';
const LEAGUES = { gl: 1500, ul: 2500, ml: 10000 };
const local = process.argv.includes('--from-local');
mkdirSync('data/rankings', { recursive: true });

const out = { fetched: new Date().toISOString(), source: BASE, leagues: {} };
for (const [league, cap] of Object.entries(LEAGUES)) {
  const rawPath = `data/rankings/overall-${cap}.json`;
  let rows;
  if (local && existsSync(rawPath)) rows = JSON.parse(readFileSync(rawPath, 'utf8'));
  else {
    const res = await fetch(`${BASE}/rankings-${cap}.json`);
    if (!res.ok) throw new Error(`${league}: HTTP ${res.status}`);
    rows = await res.json();
  }
  out.leagues[league] = rows.map((r, i) => ({
    speciesId: r.speciesId,
    rank: i + 1,
    score: Math.round(r.score * 10) / 10,
    moveset: r.moveset ?? [],
    scores: r.scores ?? null,          // [lead, closer, switch, charger, attacker, consistency] per PvPoke
  }));
  console.log(`${league}: ${out.leagues[league].length} entries`);
}
writeFileSync('data/pvp-rankings.json', JSON.stringify(out));
console.log('-> data/pvp-rankings.json', (readFileSync('data/pvp-rankings.json').length / 1024).toFixed(0), 'KB');
