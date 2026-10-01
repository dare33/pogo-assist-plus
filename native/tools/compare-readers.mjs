#!/usr/bin/env node
// Compare the JavaScript reader's rows with the Swift reader's on the same frames.
//
//   node native/tools/compare-readers.mjs <js review.json | js roster.csv> <swift review.json> [--json]
//
// The Swift side is the output of finish-readings.mjs (it has a `rows` array). The JS side is a
// review JSON with a `rows` array (finish-readings.mjs run on JS readings, say) or, for what
// scripts/extract.mjs writes (a review JSON whose `rows` is only a count), the roster CSV beside it
// (`<stem>.csv` for `<stem>.review.json`) or given directly. Rows are aligned in order (a longest
// common subsequence on name + CP); two rows with the same name and a `cpSimilar` CP (one digit
// wrong or dropped) are aligned as a mismatch, not as an insert plus a delete.

import { readFileSync, existsSync } from 'node:fs';

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const [jsPath, swiftPath] = args.filter((a) => !a.startsWith('--'));
if (!jsPath || !swiftPath) { console.error('usage: node compare-readers.mjs <js review.json | js roster.csv> <swift review.json> [--json]'); process.exit(2); }

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

function rowsFromCsv(path) {
  const [head, ...body] = parseCsv(readFileSync(path, 'utf8'));
  const col = (n) => head.indexOf(n);
  const num = (v) => (v === '' || v === undefined ? null : Number(v));
  return body.map((r) => {
    const atk = num(r[col('Atk IV')]), def = num(r[col('Def IV')]), hp = num(r[col('Sta IV')]);
    return { name: r[col('Name')], form: r[col('Form')], cp: num(r[col('CP')]), hp: num(r[col('HP')]), ivs: atk === null ? null : { atk, def, hp }, flags: [] };
  });
}

function loadSide(path, label) {
  if (path.toLowerCase().endsWith('.csv')) return { rows: rowsFromCsv(path), unmatched: null, source: 'csv' };
  const j = JSON.parse(readFileSync(path, 'utf8'));
  if (Array.isArray(j.rows)) return { rows: j.rows, unmatched: Array.isArray(j.unmatched) ? j.unmatched.length : null, source: 'json' };
  const csv = path.replace(/\.review\.json$/, '.csv');
  if (csv !== path && existsSync(csv)) return { rows: rowsFromCsv(csv), unmatched: Array.isArray(j.unmatched) ? j.unmatched.length : null, source: 'csv beside json' };
  console.error(`${label} side ${path}: no rows array and no roster CSV beside it`);
  process.exit(2);
}

const js = loadSide(jsPath, 'JS'), swift = loadSide(swiftPath, 'Swift');
const A = js.rows, B = swift.rows;
const key = (r) => `${r.name}`;
const score = (a, b) => (key(a) !== key(b) || a.cp === null || b.cp === null ? 0 : a.cp === b.cp ? 2 : cpSimilar(a.cp, b.cp) ? 1 : 0);

// Longest common subsequence by score (exact name+CP counts 2, same name with a similar CP counts 1).
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
  unmatchedJs: js.unmatched, unmatchedSwift: swift.unmatched,
  sources: { js: js.source, swift: swift.source },
};

if (asJson) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

const fmt = (r) => `${r.name}${r.form ? ` (${r.form})` : ''} CP ${r.cp} HP ${r.hp ?? '?'} IVs ${ivStr(r.ivs)}`;
const un = (v) => (v === null ? 'n/a' : v);
console.log(`rows: JS ${n}, Swift ${m}`);
console.log(`name + CP match: ${exact.length}; of those HP also matches ${result.matchAlsoHp}, IVs also match ${result.matchAlsoIvs}, both ${result.matchAlsoHpAndIvs}`);
console.log(`same name, CP differs (one digit wrong or dropped): ${cpMismatches.length}`);
for (const x of cpMismatches) console.log(`  JS #${x.js.index} ${fmt(x.js)}   |   Swift #${x.swift.index} ${fmt(x.swift)}`);
console.log(`name + CP match but HP or IVs differ: ${fieldDiffs.length}`);
for (const x of fieldDiffs) console.log(`  JS #${x.js.index} ${fmt(x.js)}   |   Swift #${x.swift.index} ${fmt(x.swift)}`);
console.log(`rows only in JS: ${onlyJs.length}`);
for (const r of result.onlyJs) console.log(`  #${r.index} ${fmt(r)} ${r.flags.join(' ')}`);
console.log(`rows only in Swift: ${onlySwift.length}`);
for (const r of result.onlySwift) console.log(`  #${r.index} ${fmt(r)} ${r.flags.join(' ')}`);
console.log(`on screen but not read (unmatched): JS ${un(result.unmatchedJs)}, Swift ${un(result.unmatchedSwift)}`);
