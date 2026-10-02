#!/usr/bin/env node
// Cut a slice of a pogo-read output (readings and their signatureDiffs) for a test fixture.
//
//   node native/tools/cut-readings.mjs <readings.json> <from-to> <out.json>      (frame indexes, inclusive)
import { readFileSync, writeFileSync } from 'node:fs';
const [input, range, out] = process.argv.slice(2);
const [a, b] = range.split('-').map(Number);
const d = JSON.parse(readFileSync(input, 'utf8'));
writeFileSync(out, JSON.stringify({ readings: d.readings.slice(a, b + 1), signatureDiffs: d.signatureDiffs.slice(a, b + 1) }));
console.error(`${out}: ${b - a + 1} readings, t ${d.readings[a].time}..${d.readings[b].time}`);
