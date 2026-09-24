import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const HERE = dirname(fileURLToPath(import.meta.url));
const DATA = join(HERE, '..', 'data');

export function loadTiers(path = join(DATA, 'tiers.json')) {
  const t = JSON.parse(readFileSync(path, 'utf8'));
  const bySpecies = new Map();
  for (const e of t.entries) { if (!bySpecies.has(e.speciesId)) bySpecies.set(e.speciesId, []); bySpecies.get(e.speciesId).push(e); }
  return { ...t, bySpecies };
}

export function loadRankings(path = join(DATA, 'pvp-rankings.json')) {
  const r = JSON.parse(readFileSync(path, 'utf8'));
  const byLeague = {};
  for (const [league, rows] of Object.entries(r.leagues)) byLeague[league] = new Map(rows.map((x) => [x.speciesId, x]));
  return { ...r, byLeague };
}
