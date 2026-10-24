#!/usr/bin/env node
// Build data/hub.json (the Pogo Hub's reference data) from the markdown in data/source/10-12.
// Usage: node scripts/build-hub.mjs data/source data/hub.json
// The sources are hand-edited, so a boss or lineup name the game master cannot resolve, a bad date or an
// unknown kind/tie is a hard failure (exit 1), never a silent gap.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadGamemaster } from '../src/node/load.js';
import { resolveSpecies, tokenKey } from '../src/gamemaster.js';

const [srcDir = 'data/source', outPath = 'data/hub.json'] = process.argv.slice(2);
const gm = loadGamemaster();

const KINDS = ['5star', 'mega', 'shadow', 'maxmon', 'maxevent', 'battleday', 'raidhour'];
const TIES = ['everything', 'raids', 'gym', 'rocket', 'pvp', 'max'];
const TYPES = ['normal', 'fire', 'water', 'electric', 'grass', 'ice', 'fighting', 'poison', 'ground', 'flying', 'psychic', 'bug', 'rock', 'ghost', 'dragon', 'dark', 'steel', 'fairy'];
const MULTIPLIERS = [1, 1.6, 0.625, 0.390625];
const TBA = /^to be announced$/i;

const errors = [];
const fail = (msg) => errors.push(msg);

function splitRow(line) { return line.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim()); }

// Same table reader as build-tiers.mjs.
function* tables(md) {
  const lines = md.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim().startsWith('|') && /^\|?\s*:?-{3,}/.test((lines[i + 1] || '').trim())) {
      const header = splitRow(lines[i]).map((c) => c.toLowerCase());
      i += 2;
      const rows = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) { rows.push(splitRow(lines[i])); i++; }
      yield { header, rows };
    }
  }
}

const read = (name) => readFileSync(join(srcDir, name), 'utf8');
const findTable = (md, file, label, test) => {
  const t = [...tables(md)].find(test);
  if (!t) throw new Error(`${file}: no ${label} table`);
  return t;
};
const columns = (t, names, file) => Object.fromEntries(names.map((n) => {
  const i = t.header.indexOf(n);
  if (i < 0) throw new Error(`${file}: table has no "${n}" column (has ${t.header.join(', ')})`);
  return [n, i];
}));

function date(text, where) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  const d = m && new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  if (!d || d.getUTCMonth() !== +m[2] - 1 || d.getUTCDate() !== +m[3]) fail(`${where}: "${text}" is not a yyyy-mm-dd date`);
  return text;
}

// Words the name carries as flags rather than as part of the species.
const FLAG_WORDS = new Set(['shadow', 'mega', 'primal', 'dynamax', 'gigantamax', 'gmax']);
// The form words resolveSpecies adds itself for a species whose plain name is a specific form (DEFAULT_FORMS in src/gamemaster.js, which does not export it).
const DEFAULT_FORM_WORDS = new Set(['ordinary', 'altered', 'incarnate', 'land', 'confined', 'standard', 'average', 'baile', 'aria', 'normal']);

// resolveSpecies is lenient (it guesses a species from the first word of a name it does not know), which is right for a scan and wrong
// for hand-written data: a name that resolves only by that guess, or whose Mega flag does not end on a Mega id, fails the build.
function pokemon(name, where) {
  const r = resolveSpecies(gm, name);
  if (!r) { fail(`${where}: cannot resolve "${name}"`); return null; }
  // Exact: the name's words (without the Shadow / Mega words) must be the species' words, with the game's default-form words allowed on the species
  // ("Keldeo" for "Keldeo (Ordinary)"); a repeated word (a flag word too: "Shadow Shadow Palkia") or an extra one means resolveSpecies guessed.
  const words = tokenKey(name).split(' ').filter(Boolean);
  const mine = words.filter((w) => !FLAG_WORDS.has(w));
  const theirs = tokenKey(r.species.speciesName).split(' ').filter((w) => w && !FLAG_WORDS.has(w));
  const extra = theirs.filter((w) => !mine.includes(w));
  const exact = words.length === new Set(words).size && mine.every((w) => theirs.includes(w)) && extra.every((w) => DEFAULT_FORM_WORDS.has(w));
  if (!exact) { fail(`${where}: "${name}" only resolves by a guess to ${r.speciesId}`); return null; }
  if (r.flags.mega && !/_(mega(_[xy])?|primal)$/.test(r.speciesId)) { fail(`${where}: "${name}" is marked Mega but resolves to ${r.speciesId}, which is not a Mega`); return null; }
  // The game master pads single-type species with "none".
  const boss = { name, speciesId: r.speciesId, types: r.species.types.filter((t) => t && t !== 'none') };
  // A Shadow the game master does not list yet resolves to the plain species: keep the name and say it is a Shadow.
  if (r.flags.shadow && !/_shadow$/.test(r.speciesId)) boss.shadow = true;
  return boss;
}

// Every row must have as many cells as the header (a stray or missing | would shift the columns silently).
function checkWidth(t, where) {
  t.rows.forEach((r, n) => { if (r.length !== t.header.length) fail(`${where} row ${n + 1}: ${r.length} cells, the header has ${t.header.length}`); });
  return t;
}

// ---- rotation and events (10-hub-rotation.md)
const ROT = '10-hub-rotation.md';
const rotMd = read(ROT);
const rot = findTable(rotMd, ROT, 'rotation (From | To | Kind | ...)', (t) => t.header.includes('kind'));
checkWidth(rot, `${ROT} rotation`);
const ri = columns(rot, ['from', 'to', 'kind', 'title', 'boss', 'note', 'source'], ROT);
const rotation = rot.rows.map((r, n) => {
  const where = `${ROT} rotation row ${n + 1}`;
  const from = date(r[ri.from], where), to = date(r[ri.to], where);
  if (from > to) fail(`${where}: from is after to`);
  if (!KINDS.includes(r[ri.kind])) fail(`${where}: unknown kind "${r[ri.kind]}"`);
  if (!r[ri.title]) fail(`${where}: no title`);
  const cell = r[ri.boss];
  // A raid or Max Monday row names its boss or says it is still to be announced; only Raid Hours and Dynamax Trails may have no boss cell.
  if (!cell && ['5star', 'mega', 'shadow', 'maxmon', 'battleday'].includes(r[ri.kind])) fail(`${where}: a ${r[ri.kind]} row needs a boss or "to be announced"`);
  // "to be announced" is a published row whose boss is not known yet: no species, and no failure.
  const bosses = !cell || TBA.test(cell) ? [] : cell.split(/\s+&\s+|,\s+/).map((nm) => pokemon(nm, where)).filter(Boolean);
  const row = { from, to, kind: r[ri.kind], title: r[ri.title], bosses, note: r[ri.note], source: r[ri.source] };
  if (TBA.test(cell)) row.tba = true;
  return row;
});

const ev = findTable(rotMd, ROT, 'events (From | To | Title | Line | Tie | Source)', (t) => t.header.includes('line'));
checkWidth(ev, `${ROT} events`);
const ei = columns(ev, ['from', 'to', 'title', 'line', 'tie', 'source'], ROT);
const events = ev.rows.map((r, n) => {
  const where = `${ROT} events row ${n + 1}`;
  const from = date(r[ei.from], where), to = date(r[ei.to], where);
  if (from > to) fail(`${where}: from is after to`);
  if (!r[ei.title]) fail(`${where}: no title`);
  if (r[ei.tie] && !TIES.includes(r[ei.tie])) fail(`${where}: unknown tie "${r[ei.tie]}"`);
  return { from, to, title: r[ei.title], line: r[ei.line], tie: r[ei.tie], source: r[ei.source] };
});

// ---- Rocket leaders and grunts (11-rocket-lineups.md)
const RK = '11-rocket-lineups.md';
const rkMd = read(RK);
const ld = findTable(rkMd, RK, 'leaders', (t) => t.header[0] === 'leader');
checkWidth(ld, `${RK} leaders`);
const li = columns(ld, ['leader', 'slot 1', 'slot 2', 'slot 3', 'since', 'source'], RK);
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const leaders = ld.rows.map((r) => {
  const where = `${RK} ${r[li.leader]}`;
  // Alternatives for one slot are separated by " / ".
  const slots = ['slot 1', 'slot 2', 'slot 3'].map((s) => r[li[s]].split(/\s+\/\s+/).map((nm) => pokemon(nm, where)).filter(Boolean));
  // "Oct 2026" (no day published) becomes "2026-10"; a full date stays yyyy-mm-dd.
  let since = r[li.since];
  const mon = /^([A-Za-z]{3}) (\d{4})$/.exec(since);
  if (mon) {
    const m = MONTHS.indexOf(mon[1].toLowerCase()) + 1;
    if (!m) fail(`${where}: bad month "${since}"`);
    since = `${mon[2]}-${String(m).padStart(2, '0')}`;
  } else date(since, where);
  return { name: r[li.leader], since, slots, source: r[li.source] };
});
const gr = findTable(rkMd, RK, 'grunt quotes', (t) => t.header[0] === 'type');
checkWidth(gr, `${RK} grunts`);
const gi = columns(gr, ['type', 'quote', 'label'], RK);
// The generic (mixed team) grunt and the Decoy have no type: an empty Type and a Label saying which they are.
const grunts = gr.rows.map((r, n) => {
  const type = r[gi.type], label = r[gi.label];
  if (type && !TYPES.includes(type)) fail(`${RK} grunt row ${n + 1}: "${type}" is not one of the 18 types`);
  if (!type && !label) fail(`${RK} grunt row ${n + 1}: a grunt with no type needs a label`);
  if (!r[gi.quote]) fail(`${RK} grunt row ${n + 1}: no quote`);
  return { type, quote: r[gi.quote], label };
});
for (const t of TYPES) if (!grunts.some((g) => g.type === t)) fail(`${RK}: no grunt quote for ${t}`);

// ---- type chart (12-type-chart.md)
const CH = '12-type-chart.md';
const [ch] = [...tables(read(CH))];
if (!ch) throw new Error(`${CH}: no matrix table`);
checkWidth(ch, CH);
const typeChart = {};
const defs = ch.header.slice(1);
if (defs.join() !== TYPES.join()) fail(`${CH}: columns must be ${TYPES.join(', ')} in that order`);
for (const r of ch.rows) {
  const row = {};
  defs.forEach((d, i) => {
    const v = Number(r[i + 1]);
    if (!MULTIPLIERS.includes(v)) fail(`${CH}: ${r[0]} against ${d}: "${r[i + 1]}" is not 1, 1.6, 0.625 or 0.390625`);
    row[d] = v;
  });
  typeChart[r[0]] = row;
}
if (Object.keys(typeChart).join() !== TYPES.join()) fail(`${CH}: rows must be ${TYPES.join(', ')} in that order`);

if (errors.length) {
  console.error(`build-hub: ${errors.length} problem(s):\n  ${errors.join('\n  ')}`);
  process.exit(1);
}
writeFileSync(outPath, JSON.stringify({ generated: new Date().toISOString(), rotation, events, leaders, grunts, typeChart }, null, 1) + '\n');
console.log(`${rotation.length} rotation rows, ${events.length} events, ${leaders.length} leaders, ${grunts.length} grunts, ${Object.keys(typeChart).length}x${defs.length} chart -> ${outPath}`);
