#!/usr/bin/env node
// Download the public PokeMiners game master and keep the raid (PvE) stats of every move: type, power, duration and energy.
// data/gamemaster.json (PvPoke's) has PvP move stats only; the raid and Max damage estimates need these.
// Usage: node scripts/fetch-pve-moves.mjs [--from-local <latest.json>]      (local mode reads an already-downloaded copy)
// Writes data/pve-moves.json and the same bytes to native/PogoReader/Sources/PogoBox/Resources/pve-moves.json (the app's copy; the two never differ).
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const SOURCE = 'https://raw.githubusercontent.com/PokeMiners/game_masters/master/latest/latest.json';
const OUT = 'data/pve-moves.json';
const APP_COPY = 'native/PogoReader/Sources/PogoBox/Resources/pve-moves.json';

// PvPoke ids that PokeMiners spells differently. A `_PLUS` (Mega-boosted) move the file lacks takes its base move's stats (`approximated`, which understates it).
//  A Hidden Power variant has the one Hidden Power fast move's stats in its own type.
const ALIASES = { FUTURE_SIGHT: 'FUTURESIGHT', PYRO_BALL: 'PYROBALL', TECHNO_BLAST_DOUSE: 'TECHNO_BLAST_WATER' };
const HIDDEN_POWER = /^HIDDEN_POWER_([A-Z]+)$/;

// Max moves are not in the game master file (it holds only Dynamax Cannon, a locked Eternatus move). Base powers by Max Move level 1 to 3 (Max Attack and G-Max Attack):
// Pokemon GO Wiki (pokemongo.fandom.com), page "Max Moves", section "Max Move effects", revision 187269, read 1 Nov 2026 ("Standard: 250 / 300 / 350 base power;
// G-Max: 350 / 400 / 450"; Max Behemoth Blade and Max Behemoth Bash use the standard power, Max Dynamax Cannon the G-Max power). Bulbapedia's "Max Move (GO)" page
// could not be read: it sits behind a Cloudflare challenge. Review these if the game changes them; the picker bars compare Pokemon with one another.
export const MAX_MOVE_POWER = { maxAttack: [250, 300, 350], gmax: [350, 400, 450] };
export const MAX_MOVE_POWER_SOURCE = 'Pokemon GO Wiki (pokemongo.fandom.com), "Max Moves", revision 187269, read 1 Nov 2026';
export const NOTE = 'A move whose id ends _PLUS and is not in the source takes its base move\'s stats (it understates the Mega-boosted move).';

const typeOf = (t) => String(t).replace(/^POKEMON_TYPE_/, '').toLowerCase();

/** Every `V<nnnn>_MOVE_<NAME>` move setting in a game master list, as { NAME: {type, power, durationMs, energyDelta} }. `_FAST` is dropped from the name, as PvPoke's ids have none. */
export function parsePveMoves(templates) {
  const moves = {};
  for (const t of templates) {
    const m = /^V\d+_MOVE_(.+)$/.exec(t.templateId ?? '');
    const s = t.data?.moveSettings;
    if (!m || !s) continue;
    const id = m[1].replace(/_FAST$/, '');
    if (id in moves) continue;
    moves[id] = { type: typeOf(s.pokemonType), power: s.power ?? 0, durationMs: s.durationMs ?? 0, energyDelta: s.energyDelta ?? 0 };
  }
  return moves;
}

/** The slim file's `moves`, keyed by PvPoke's move id: `moves` plus the aliases above. Returns the moves, the PvPoke ids still without a match and those approximated. */
export function matchToPvpoke(pveMoves, pvpokeMoveIds) {
  const out = {}, unmatched = [], approximated = [];
  for (const id of pvpokeMoveIds) {
    const hp = HIDDEN_POWER.exec(id);
    const found = pveMoves[id] ?? pveMoves[ALIASES[id]] ?? (hp && pveMoves.HIDDEN_POWER ? { ...pveMoves.HIDDEN_POWER, type: hp[1].toLowerCase() } : undefined);
    const baseId = id.endsWith('_PLUS') ? id.slice(0, -5) : undefined;
    const base = !found && baseId ? (pveMoves[baseId] ?? pveMoves[ALIASES[baseId]]) : undefined;
    if (found) out[id] = found; else if (base) { out[id] = base; approximated.push(id); } else unmatched.push(id);
  }
  return { moves: out, unmatched, approximated };
}

export function build(templates, pvpokeMoveIds, fetched = new Date().toISOString()) {
  const { moves, unmatched, approximated } = matchToPvpoke(parsePveMoves(templates), pvpokeMoveIds);
  return { file: { source: SOURCE, fetched, note: NOTE, maxMovePower: MAX_MOVE_POWER, maxMovePowerSource: MAX_MOVE_POWER_SOURCE, moves }, unmatched, approximated };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const li = process.argv.indexOf('--from-local');
  let templates;
  if (li >= 0) templates = JSON.parse(readFileSync(process.argv[li + 1], 'utf8'));
  else {
    const res = await fetch(SOURCE);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    templates = await res.json();
  }
  const gm = JSON.parse(readFileSync('data/gamemaster.json', 'utf8'));
  const { file, unmatched, approximated } = build(templates, gm.moves.map((m) => m.moveId));
  const text = JSON.stringify(file);
  writeFileSync(OUT, text); writeFileSync(APP_COPY, text);
  console.log(`${Object.keys(file.moves).length} moves -> ${OUT} and ${APP_COPY} (${(text.length / 1024).toFixed(0)} KB)`);
  console.log(`${approximated.length} PvPoke moves approximated by their base move: ${approximated.join(', ')}`);
  console.log(`${unmatched.length} PvPoke moves with no PvE match: ${unmatched.join(', ')}`);
}
