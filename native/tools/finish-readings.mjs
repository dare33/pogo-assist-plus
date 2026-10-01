#!/usr/bin/env node
// Feed the Swift reader's per-frame readings through the JavaScript `finish()` (group, vote, solve,
// dedupe, flag) of a checkout that has src/extract, and write the result.
//
//   node native/tools/finish-readings.mjs --repo <checkout> <readings.json> --out <review.json>
//
// <readings.json> is what `pogo-read --out` writes ({ readings: [...] }) or a bare array of readings.
// The gamemaster is loaded the way scripts/extract.mjs does (src/node/load.js in that checkout).
// Output: { input, frames, rows: [...], rowCount, flagged, review, unmatched }. `rows` holds the
// full finished rows (scripts/extract.mjs writes only their count into its review JSON and the rows
// into the CSV); `review` and `unmatched` are the same as extract.mjs's.

import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };
const input = args.find((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
const repo = opt('repo'), out = opt('out');
if (!input || !repo || !out) {
  console.error('usage: node finish-readings.mjs --repo <checkout with src/extract> <readings.json> --out <review.json>');
  process.exit(2);
}

const load = (rel) => import(pathToFileURL(join(resolve(repo), rel)).href);
const { loadGamemaster } = await load('src/node/load.js');
const { finish } = await load('src/extract/pipeline.js');

const parsed = JSON.parse(readFileSync(input, 'utf8'));
const readings = Array.isArray(parsed) ? parsed : parsed.readings;
if (!Array.isArray(readings)) { console.error(`${input}: no readings array`); process.exit(2); }

const { rows, review, unmatched } = finish(readings, loadGamemaster());
writeFileSync(out, JSON.stringify({ input, frames: readings.length, rows, rowCount: rows.length, flagged: review.length, review, unmatched }, null, 2));
console.error(`${rows.length} rows from ${readings.length} frames; ${review.length} flagged; ${unmatched.length} on screen but not read -> ${out}`);
