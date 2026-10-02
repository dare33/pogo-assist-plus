#!/usr/bin/env node
// Cut the PogoBox parity fixture: a slice of a readings file plus what the JavaScript gives for it.
//
//   node native/tools/make-core-fixture.mjs --repo <checkout> <readings.json> <from-to,from-to,...> <out-dir>
//
// Writes <out-dir>/readings.json ({readings}), expected.json (finish-readings.mjs's output shape: rows,
// review, unmatched) and expected.csv (the JS toPokeGenieCsv with a fixed scan date, 2026-10-02 12:00 local;
// the Swift test ignores the two scan-date columns). The ranges are frame indexes, inclusive.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const ri = args.indexOf('--repo');
if (ri < 0) { console.error('need --repo'); process.exit(2); }
const repo = resolve(args.splice(ri, 2)[1]);
const [input, ranges, outDir] = args;
const load = (rel) => import(pathToFileURL(join(repo, rel)).href);
const { loadGamemaster } = await load('src/node/load.js');
const { finish, toPokeGenieCsv } = await load('src/extract/pipeline.js');

const all = JSON.parse(readFileSync(input, 'utf8')).readings;
const readings = ranges.split(',').flatMap((r) => { const [a, b] = r.split('-').map(Number); return all.slice(a, b + 1); });
const { rows, review, unmatched } = finish(readings, loadGamemaster());
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'readings.json'), JSON.stringify({ readings }));
writeFileSync(join(outDir, 'expected.json'), JSON.stringify({ rows, review, unmatched }, null, 1));
writeFileSync(join(outDir, 'expected.csv'), toPokeGenieCsv(rows, { scanDate: new Date(2026, 9, 2, 12, 0) }));
console.error(`${readings.length} readings -> ${rows.length} rows, ${review.length} flagged, ${unmatched.length} unmatched`);
