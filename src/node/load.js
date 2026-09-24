// Node-only loaders. The browser fetches the same files and calls the index* functions directly.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { indexGamemaster } from '../gamemaster.js';
import { indexTiers, indexRankings } from '../data.js';

const DATA = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'data');
const read = (name) => JSON.parse(readFileSync(join(DATA, name), 'utf8'));

export const loadGamemaster = (path) => indexGamemaster(path ? JSON.parse(readFileSync(path, 'utf8')) : read('gamemaster.json'));
export const loadTiers = (path) => indexTiers(path ? JSON.parse(readFileSync(path, 'utf8')) : read('tiers.json'));
export const loadRankings = (path) => indexRankings(path ? JSON.parse(readFileSync(path, 'utf8')) : read('pvp-rankings.json'));
export const loadContext = () => ({ gm: loadGamemaster(), tiers: loadTiers(), rankings: loadRankings() });
