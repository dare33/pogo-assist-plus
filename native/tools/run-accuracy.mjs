#!/usr/bin/env node
// How accurate was a device run, judged against another run of the same Pokemon? Runs `pogo-rows` on each
// replay log and prints, per log: rows, rows that match the truth exactly, wrong rows, how many of those
// carry no flag the app would show for a look ("unflagged"), truth rows the log lacks, and how many
// readings a row has (the number a faster reader is meant to raise).
//
//   node native/tools/run-accuracy.mjs [--pogo-rows <path>] [--paging command|hand] [--truth a.jsonl[,b.jsonl]] [--verbose] <replay.jsonl>...
//
// The truth is the rows both truth logs agree on (in order), or the one truth log's rows; with no --truth the
// table has no accuracy columns. A truth log should be an earlier scan of the SAME Pokemon in the same order:
// a wrong row that both scans share cannot be seen this way, and a row only the better scan got right shows as
// the other's miss. "Flagged" is what the app asks the person to check (`FlagInfo`: a flag that is only a note
// when the CP, HP and bars fit one level is not a check), not any flag at all.
//
// Run `swift build -c release --product pogo-rows` in native/PogoReader first; the default --pogo-rows is
// native/PogoReader/.build/release/pogo-rows.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : d; };
const verbose = args.includes('--verbose');
const here = dirname(fileURLToPath(import.meta.url));
const tool = opt('pogo-rows', join(here, '..', 'PogoReader', '.build', 'release', 'pogo-rows'));
const paging = opt('paging', 'command');
const truthLogs = (opt('truth', '') || '').split(',').filter(Boolean);
const valued = ['--pogo-rows', '--paging', '--truth'];
const logs = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && valued.includes(args[i - 1])));
if (!logs.length) { console.error('usage: run-accuracy.mjs [--truth a.jsonl[,b.jsonl]] <replay.jsonl>...'); process.exit(2); }

// FlagInfo.rules: the flags that are only notes, always or when the row's solver status is exact.
const NOTE = ['form-ambiguous', 'level-ambiguous'];
const NOTE_WHEN_EXACT = ['ivs-disagree', 'bars-unsettled', 'cp-chosen', 'cp-recovered', 'cp-outlier-dropped', 'absorbed-fragment', 'ivs-corrected', 'hp-computed'];
const hasPrefix = (f, p) => f === p || f.startsWith(`${p}:`) || f.startsWith(`${p}-`);
function checkFlags(row) {
  return (row.flags ?? []).filter((f) => {
    if (NOTE.some((p) => hasPrefix(f, p))) return false;
    if (NOTE_WHEN_EXACT.some((p) => hasPrefix(f, p))) return row.solveStatus !== 'exact';
    return true;
  });
}

const key = (r) => `${r.display || r.name}|${r.cp}|${r.hp}|${r.ivs ? `${r.ivs.atk}/${r.ivs.def}/${r.ivs.hp}` : '?'}`;

/** Longest common subsequence of two key lists: which positions of each are matched. */
function lcs(a, b) {
  const d = Array.from({ length: a.length + 1 }, () => new Int16Array(b.length + 1));
  for (let i = a.length - 1; i >= 0; i--) for (let j = b.length - 1; j >= 0; j--) d[i][j] = a[i] === b[j] ? d[i + 1][j + 1] + 1 : Math.max(d[i + 1][j], d[i][j + 1]);
  const inA = new Set(), inB = new Set();
  for (let i = 0, j = 0; i < a.length && j < b.length;) {
    if (a[i] === b[j]) { inA.add(i); inB.add(j); i++; j++; } else if (d[i + 1][j] >= d[i][j + 1]) i++; else j++;
  }
  return { inA, inB };
}

const dir = mkdtempSync(join(tmpdir(), 'run-accuracy-'));
function rowsOf(log) {
  const out = join(dir, `${basename(log)}.json`);
  execFileSync(tool, [log, '--paging', paging, '--json', out], { stdio: 'ignore' });
  return JSON.parse(readFileSync(out, 'utf8')).rows;
}

try {
  let truth = null;
  if (truthLogs.length) {
    truth = rowsOf(truthLogs[0]).map(key);
    if (truthLogs[1]) { const other = rowsOf(truthLogs[1]).map(key); const { inA } = lcs(truth, other); truth = truth.filter((_, i) => inA.has(i)); }
  }
  console.log(['log', 'rows', 'exact', 'wrong', 'wrong unflagged', 'missing', 'check-flagged', 'readings/row'].join('\t'));
  for (const log of logs) {
    const rows = rowsOf(log);
    const flagged = rows.filter((r) => checkFlags(r).length).length;
    const perRow = (rows.reduce((n, r) => n + r.frames.length, 0) / Math.max(1, rows.length)).toFixed(2);
    let cells = [rows.length, '-', '-', '-', '-'];
    let detail = [];
    if (truth) {
      const { inA, inB } = lcs(rows.map(key), truth);
      const wrong = rows.filter((_, i) => !inA.has(i));
      cells = [rows.length, rows.length - wrong.length, wrong.length, wrong.filter((r) => !checkFlags(r).length).length, truth.length - inB.size];
      detail = [...wrong.map((r) => `  wrong #${r.index} ${key(r)} [${(r.flags ?? []).join(' ')}] ${checkFlags(r).length ? 'flagged' : 'UNFLAGGED'}, ${r.frames.length} reading(s)`),
        ...truth.filter((_, i) => !inB.has(i)).map((k) => `  missing ${k}`)];
    }
    console.log([basename(log), ...cells, flagged, perRow].join('\t'));
    if (verbose) for (const d of detail) console.log(d);
  }
} finally { rmSync(dir, { recursive: true, force: true }); }
