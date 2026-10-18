#!/usr/bin/env node
// Writes the compact species table the Swift reader loads (and the broadcast extension carries):
// id, name, dex and base stats only, shadow ids skipped (same name on screen, as names.js does).
//
//   node native/tools/build-species.mjs [data/gamemaster.json] [native/PogoReader/Sources/PogoReader/Resources/species.json]
//
// Format: {"version":1,"species":[[id, speciesName, dex, atk, def, hp], ...]}, in game master order
// (the name matcher breaks ties by order, so the order is kept).

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const input = process.argv[2] ?? join(root, 'data', 'gamemaster.json');
const output = process.argv[3] ?? join(root, 'native', 'PogoReader', 'Sources', 'PogoReader', 'Resources', 'species.json');

const gm = JSON.parse(readFileSync(input, 'utf8'));
const species = gm.pokemon
  .filter((p) => !p.speciesId.endsWith('_shadow') && p.baseStats)
  .map((p) => [p.speciesId, p.speciesName, p.dex, p.baseStats.atk, p.baseStats.def, p.baseStats.hp]);
// One species per line keeps diffs readable and the file small.
writeFileSync(output, `{"version":1,"species":[\n${species.map((s) => JSON.stringify(s)).join(',\n')}\n]}\n`);
console.error(`${species.length} species -> ${output}`);
