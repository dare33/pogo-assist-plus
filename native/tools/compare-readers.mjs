#!/usr/bin/env node
// Compare two readers' rows on the same frames: the JavaScript reader's roster against the Swift reader's.
//
//   node native/tools/compare-readers.mjs <js side> <swift side> [--json]
//
// Each side is one of (the shape is detected, and an input of any other shape is refused with exit
// code 2 rather than guessed at):
//   - a finish-readings.mjs output ({ rows: [{ name, form, cp, hp, ivs, solveStatus... }], unmatched })
//     (finish-readings.mjs run on Swift readings, or on JS readings);
//   - a Poke Genie-layout roster CSV from scripts/extract.mjs (headers Name, Form, CP, HP, Atk IV,
//     Def IV, Sta IV), or the scripts/extract.mjs review JSON beside one (`<stem>.review.json` for
//     `<stem>.csv`; that JSON has only a row count, the rows are read from the CSV);
//   - LiveGrouper rows from `pogo-read --rows` (an array of { name, cp, hp, ivs, frames, flags,
//     firstFrame ... }) or a pogo-read output that holds them.
// LiveGrouper rows carry the name as the game prints it ("Alolan Raichu", "Mega Mewtwo Y", "Nidoran♀"),
// not the roster's name and form; they are mapped (Alolan X -> X, Alola; Mega X Y -> X, Mega Y) and
// compared on name and form. A live row has no form beyond that: a roster form it cannot know (Hero,
// Altered ...) is not a disagreement, and a roster form it should have printed (Alola, Mega Y ...) is.
// "(name not read)" rows have no roster counterpart: they are counted apart, not as rows only in Swift.
// Rows are aligned in order (a longest common subsequence on species + CP); two rows of the same species
// with a CP one digit wrong or dropped (`cpSimilar`) align as a mismatch, not as an insert plus a delete.

import { readFileSync, existsSync } from 'node:fs';

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const [jsPath, swiftPath] = args.filter((a) => !a.startsWith('--'));
const refuse = (msg) => { console.error(`compare-readers: ${msg}`); process.exit(2); };
if (!jsPath || !swiftPath) refuse('usage: node compare-readers.mjs <js side> <swift side> [--json]');

/** Two CP reads that could be the same number: equal, one digit different, or one digit dropped (merge.js). */
export function cpSimilar(a, b) {
  const x = String(a), y = String(b);
  if (x === y) return true;
  if (x.length === y.length && x.length >= 3) { let d = 0; for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) d++; return d <= 1; }
  const [s, l] = x.length < y.length ? [x, y] : [y, x];
  if (l.length - s.length !== 1 || s.length < 2) return false;
  for (let i = 0; i < l.length; i++) if (l.slice(0, i) + l.slice(i + 1) === s) return true;
  return false;
}

function parseCsv(text) {
  const rows = [];
  let row = [], cell = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(cell); cell = ''; if (row.length > 1 || row[0] !== '') rows.push(row); row = []; }
    else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

const num = (v) => (v === '' || v === undefined || v === null ? null : Number(v));
// Forms the game prints in the NAME, so a live row has them: everything else (Hero, Altered...) it cannot know.
const PRINTED = /^(Alola|Galar|Hisui|Paldea|Mega( [XY])?|Primal)$/;
const REGIONAL = { Alolan: 'Alola', Galarian: 'Galar', Hisuian: 'Hisui', Paldean: 'Paldea' };

/** name and form of a name as the game prints it; form null when it cannot be known. */
function fromDisplay(display) {
  let m = display.match(/^(Alolan|Galarian|Hisuian|Paldean) (.+)$/);
  if (m) return { name: m[2], form: REGIONAL[m[1]] };
  m = display.match(/^Mega (.+?)( [XY])?$/);
  if (m) return { name: m[1], form: `Mega${m[2] ?? ''}` };
  m = display.match(/^Primal (.+)$/);
  if (m) return { name: m[1], form: 'Primal' };
  return { name: display, form: null };
}

const canon = (name, form, r) => ({ name, form, cp: r.cp ?? null, hp: r.hp ?? null, ivs: r.ivs ?? null, flags: r.flags ?? [], frame: r.firstFrame ?? null });

function fromCsv(path) {
  const [head, ...body] = parseCsv(readFileSync(path, 'utf8'));
  const need = ['Name', 'Form', 'CP', 'HP', 'Atk IV', 'Def IV', 'Sta IV'];
  if (!head || need.some((h) => !head.includes(h))) refuse(`${path}: not a roster CSV (needs the columns ${need.join(', ')})`);
  const col = (n) => head.indexOf(n);
  return body.map((r) => {
    const atk = num(r[col('Atk IV')]);
    return canon(r[col('Name')], r[col('Form')], { cp: num(r[col('CP')]), hp: num(r[col('HP')]), ivs: atk === null ? null : { atk, def: num(r[col('Def IV')]), hp: num(r[col('Sta IV')]) } });
  });
}

const looksFinish = (r) => r && typeof r === 'object' && 'name' in r && 'cp' in r && ('solveStatus' in r || 'display' in r);
const looksLive = (r) => r && typeof r === 'object' && 'name' in r && 'cp' in r && typeof r.frames === 'number' && !('solveStatus' in r);

function loadSide(path, label) {
  if (!existsSync(path)) refuse(`${label} side ${path}: no such file`);
  if (path.toLowerCase().endsWith('.csv')) return { rows: fromCsv(path), unmatched: null, kind: 'roster CSV' };
  let j;
  try { j = JSON.parse(readFileSync(path, 'utf8')); } catch { refuse(`${label} side ${path}: not JSON or CSV`); }
  const unmatched = Array.isArray(j?.unmatched) ? j.unmatched.length : null;
  if (Array.isArray(j) || Array.isArray(j?.rows)) {
    const rows = Array.isArray(j) ? j : j.rows;
    if (rows.length === 0) return { rows: [], unmatched, kind: 'empty' };
    if (looksFinish(rows[0])) return { rows: rows.map((r) => canon(r.name, r.form ?? '', r)), unmatched, kind: 'finish rows' };
    if (looksLive(rows[0])) return { rows: rows.map((r) => { const d = fromDisplay(r.name); return canon(d.name, d.form, r); }), unmatched, kind: 'live rows', live: true };
    refuse(`${label} side ${path}: rows are neither finish-readings rows (name, cp, solveStatus) nor LiveGrouper rows (name, cp, frames)`);
  }
  if (typeof j?.rows === 'number') {
    const csv = path.replace(/\.review\.json$/, '.csv');
    if (csv !== path && existsSync(csv)) return { rows: fromCsv(csv), unmatched, kind: 'roster CSV beside the review JSON' };
    refuse(`${label} side ${path}: a scripts/extract.mjs review JSON holds only a row count; pass the roster CSV (<stem>.csv) instead`);
  }
  refuse(`${label} side ${path}: no rows (expected a finish-readings output, a roster CSV, or pogo-read --rows output)`);
}

const js = loadSide(jsPath, 'JS'), swift = loadSide(swiftPath, 'Swift');
const unnamedSwift = swift.rows.filter((r) => r.name === '(name not read)');
const unnamedJs = js.rows.filter((r) => r.name === '(name not read)');
const A = js.rows.filter((r) => r.name !== '(name not read)'), B = swift.rows.filter((r) => r.name !== '(name not read)');

/** Same species: names equal and forms agree (a form a live row cannot know is no disagreement). */
function sameSpecies(a, b) {
  const nidoran = (x, y) => x.name === 'Nidoran' && y.name.startsWith('Nidoran');
  if (a.name !== b.name && !nidoran(a, b) && !nidoran(b, a)) return false;
  const fa = a.form, fb = b.form;
  if (fa !== null && fb !== null) return fa === fb || (fa === '' && fb === '') ;
  const known = fa ?? fb;   // the other is null: a live row that printed no form
  return !PRINTED.test(known ?? '');
}
const score = (a, b) => (!sameSpecies(a, b) || a.cp === null || b.cp === null ? 0 : a.cp === b.cp ? 2 : cpSimilar(a.cp, b.cp) ? 1 : 0);

// Longest common subsequence by score (exact species + CP counts 2, same species with a similar CP counts 1).
const n = A.length, m = B.length;
const dp = Array.from({ length: n + 1 }, () => new Int32Array(m + 1));
for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) {
  const s = score(A[i], B[j]);
  dp[i][j] = Math.max(dp[i + 1][j], dp[i][j + 1], s ? dp[i + 1][j + 1] + s : 0);
}
const pairs = [], onlyJs = [], onlySwift = [];
for (let i = 0, j = 0; i < n || j < m;) {
  if (i < n && j < m) {
    const s = score(A[i], B[j]);
    if (s && dp[i][j] === dp[i + 1][j + 1] + s) { pairs.push([i, j, s === 2]); i++; j++; continue; }
  }
  if (i < n && (j >= m || dp[i][j] === dp[i + 1][j])) onlyJs.push(i++);
  else onlySwift.push(j++);
}

const ivStr = (v) => (v ? `${v.atk}/${v.def}/${v.hp}` : '?');
const ivEq = (a, b) => ivStr(a) === ivStr(b);
const brief = (r, idx) => ({ index: idx + 1, name: r.name, form: r.form ?? '', cp: r.cp, hp: r.hp ?? null, ivs: r.ivs ?? null, flags: r.flags ?? [] });

const exact = pairs.filter((p) => p[2]);
const cpMismatches = pairs.filter((p) => !p[2]).map(([i, j]) => ({ js: brief(A[i], i), swift: brief(B[j], j) }));
const fieldDiffs = exact.filter(([i, j]) => A[i].hp !== B[j].hp || !ivEq(A[i].ivs, B[j].ivs)).map(([i, j]) => ({ js: brief(A[i], i), swift: brief(B[j], j) }));
const result = {
  rowsJs: n, rowsSwift: m,
  matchNameCp: exact.length,
  matchAlsoHp: exact.filter(([i, j]) => A[i].hp === B[j].hp).length,
  matchAlsoIvs: exact.filter(([i, j]) => ivEq(A[i].ivs, B[j].ivs)).length,
  matchAlsoHpAndIvs: exact.filter(([i, j]) => A[i].hp === B[j].hp && ivEq(A[i].ivs, B[j].ivs)).length,
  cpMismatches, fieldDiffs,
  onlyJs: onlyJs.map((i) => brief(A[i], i)),
  onlySwift: onlySwift.map((j) => brief(B[j], j)),
  unnamedRowsJs: unnamedJs.length, unnamedRowsSwift: unnamedSwift.length,
  unmatchedJs: js.unmatched, unmatchedSwift: swift.unmatched,
  sources: { js: js.kind, swift: swift.kind },
};

if (asJson) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

const fmt = (r) => `${r.name}${r.form ? ` (${r.form})` : ''} CP ${r.cp} HP ${r.hp ?? '?'} IVs ${ivStr(r.ivs)}`;
const un = (v) => (v === null ? 'n/a' : v);
console.log(`inputs: JS ${js.kind}, Swift ${swift.kind}`);
console.log(`rows: JS ${n}, Swift ${m}${unnamedSwift.length ? ` (+${unnamedSwift.length} unnamed "(name not read)" rows in Swift, not compared)` : ''}`);
console.log(`name + CP match: ${exact.length}; of those HP also matches ${result.matchAlsoHp}, IVs also match ${result.matchAlsoIvs}, both ${result.matchAlsoHpAndIvs}`);
console.log(`same species, CP differs (one digit wrong or dropped): ${cpMismatches.length}`);
for (const x of cpMismatches) console.log(`  JS #${x.js.index} ${fmt(x.js)}   |   Swift #${x.swift.index} ${fmt(x.swift)}`);
console.log(`name + CP match but HP or IVs differ: ${fieldDiffs.length}`);
for (const x of fieldDiffs) console.log(`  JS #${x.js.index} ${fmt(x.js)}   |   Swift #${x.swift.index} ${fmt(x.swift)}`);
console.log(`rows only in JS: ${onlyJs.length}`);
for (const r of result.onlyJs) console.log(`  #${r.index} ${fmt(r)} ${r.flags.join(' ')}`);
console.log(`rows only in Swift: ${onlySwift.length}`);
for (const r of result.onlySwift) console.log(`  #${r.index} ${fmt(r)} ${r.flags.join(' ')}`);
console.log(`on screen but not read (unmatched): JS ${un(result.unmatchedJs)}, Swift ${un(result.unmatchedSwift)}`);
