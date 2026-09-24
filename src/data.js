// Pure indexers for the two generated data files (browser-safe; Node loaders live in src/node/load.js).
export function indexTiers(t) {
  const bySpecies = new Map();
  for (const e of t.entries) { if (!bySpecies.has(e.speciesId)) bySpecies.set(e.speciesId, []); bySpecies.get(e.speciesId).push(e); }
  return { ...t, bySpecies };
}

export function indexRankings(r) {
  const byLeague = {};
  for (const [league, rows] of Object.entries(r.leagues)) byLeague[league] = new Map(rows.map((x) => [x.speciesId, x]));
  return { ...r, byLeague };
}
