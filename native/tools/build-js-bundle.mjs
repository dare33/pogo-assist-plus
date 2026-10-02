#!/usr/bin/env node
// Build the app core's JavaScript: ONE classic script for JavaScriptCore from the project's ES modules.
//
//   node native/tools/build-js-bundle.mjs --repo <checkout> --out <dir>      (writes pogo-core.js + the data files)
//   node native/tools/build-js-bundle.mjs --self-test <pogo-core.js>          (load it in a bare vm and run finish)
//
// No dependencies, no bundler. The import graph is resolved from ENTRIES below; each module becomes a
// function scope (so top-level names cannot collide) and `import`/`export` are rewritten to a tiny
// registry. Only the plain `import { a, b as c } from './x.js'` and `export function|const|class` forms
// the project uses are understood; anything else fails the build rather than being guessed at.
// The bundle must not reach Node APIs, frame reading, OCR or PNG code: ALLOWED lists the modules that may
// be in the graph, STUBS the one import that is cut (pipeline.js imports readFrame only for `extract`,
// which the app never calls). The entry that defines the `PogoCore` global is pogo-core-facade.js.

import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, join, dirname, posix } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import vm from 'node:vm';

const ENTRIES = ['src/extract/pipeline.js', 'src/extract/batch.js', 'src/gamemaster.js', 'src/data.js', 'src/advise.js', 'src/import/pokegenie.js'];
const ALLOWED = new Set([
  'src/extract/pipeline.js', 'src/extract/merge.js', 'src/extract/solve.js', 'src/extract/names.js', 'src/extract/batch.js',
  'src/cpm.js', 'src/cost.js', 'src/gamemaster.js', 'src/advise.js', 'src/data.js', 'src/pvp-rank.js', 'src/csv.js', 'src/import/pokegenie.js',
]);
const STUBS = { 'src/extract/frame.js': ['readFrame'] };
const DATA_FILES = ['gamemaster.json', 'tiers.json', 'pvp-rankings.json'];
const NODE_WORDS = /\b(process|require|Buffer|__dirname|__filename)\b|node:|import\.meta|\bawait\s+import\b/;
const FACADE = readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'pogo-core-facade.js'), 'utf8');

const fail = (msg) => { console.error(`build-js-bundle: ${msg}`); process.exit(1); };
const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };

function selfTest(code) {
  // A bare context: no require, no process, no console, no timers. Whatever the bundle needs must be in it.
  const ctx = vm.createContext({});
  vm.runInContext(code, ctx, { filename: 'pogo-core.js' });
  const core = vm.runInContext('PogoCore', ctx);
  for (const k of ['indexGamemaster', 'finish', 'toPokeGenieCsv', 'mergeClips', 'importPokeGenie', 'analyseBox', 'load', 'finishJSON', 'csvJSON', 'mergeClipsJSON', 'adviseJSON', 'importPokeGenieJSON']) {
    if (typeof core[k] !== 'function') throw new Error(`self-test: PogoCore.${k} missing`);
  }
  const leaks = vm.runInContext('[typeof require, typeof process, typeof Buffer, typeof module].join(",")', ctx);
  if (leaks !== 'undefined,undefined,undefined,undefined') throw new Error(`self-test: unexpected globals ${leaks}`);
  // Smallest honest run: a tiny gamemaster, four frames of one Pokemon, one row out.
  const gm = { timestamp: 0, moves: [], pokemon: [{ speciesId: 'bulbasaur', speciesName: 'Bulbasaur', dex: 1, baseStats: { atk: 118, def: 111, hp: 128 }, types: ['grass', 'poison'], released: true }] };
  core.load(JSON.stringify(gm), '{"entries":[]}', '{"leagues":{}}');
  const frame = (i) => ({ frame: `f${i}`, time: i * 0.2, cp: 500, cpText: 'CP500', name: 'Bulbasaur', baseName: 'Bulbasaur', form: 'Normal', speciesIds: ['bulbasaur'], nameText: 'Bulbasaur', nameConfidence: 90, hp: { cur: 50, max: 50 }, hpText: '50/50', ivs: null, ivConfidence: 0, fills: null, sharpness: 1, flags: [] });
  const res = JSON.parse(core.finishJSON(JSON.stringify([0, 1, 2, 3].map(frame))));
  if (!Array.isArray(res.rows) || res.rows.length !== 1 || res.rows[0].cp !== 500 || res.rows[0].display !== 'Bulbasaur') throw new Error(`self-test: unexpected finish result ${JSON.stringify(res).slice(0, 300)}`);
  const csv = core.csvJSON(JSON.stringify(res.rows), Date.UTC(2026, 9, 2));
  if (!csv.startsWith('Index,Name,Form') || csv.trim().split('\n').length !== 2) throw new Error('self-test: unexpected csv');
  console.error('self-test: bare vm context loads the bundle and finish() gives 1 row from 4 readings');
}

if (opt('self-test')) { selfTest(readFileSync(opt('self-test'), 'utf8')); process.exit(0); }

const repo = opt('repo'), out = opt('out');
if (!repo || !out) fail('usage: build-js-bundle.mjs --repo <checkout> --out <dir>   |   --self-test <pogo-core.js>');
const root = resolve(repo);
const sha = (buf) => createHash('sha256').update(buf).digest('hex');

// ---- resolve the graph (depth-first, dependencies first; a cycle is an error) ----
const modules = new Map();   // rel path -> { imports: [{names, from, target}], body, exportsList }
const order = [];
const visiting = new Set();

function parseModule(rel) {
  const full = join(root, rel);
  if (!existsSync(full)) fail(`${rel}: not found in ${root}`);
  const src = readFileSync(full, 'utf8');
  const imports = [];
  let body = src.replace(/^import\s*\{([^}]*)\}\s*from\s*'([^']+)';?[ \t]*$/gm, (_, names, from) => {
    const list = names.split(',').map((s) => s.trim()).filter(Boolean).map((s) => {
      const m = /^([\w$]+)(?:\s+as\s+([\w$]+))?$/.exec(s);
      if (!m) fail(`${rel}: cannot read import specifier "${s}"`);
      return { name: m[1], local: m[2] ?? m[1] };
    });
    imports.push({ names: list, from });
    return '';
  });
  if (/^\s*import\b/m.test(body)) fail(`${rel}: an import form this tool does not understand`);
  if (/\bimport\s*\(/.test(body)) fail(`${rel}: dynamic import`);
  if (/^\s*export\s+(default|\*|\{)/m.test(body)) fail(`${rel}: export default / export * / export { } not supported`);
  const exportsList = [];
  body = body.replace(/^export\s+(async\s+function|function|const|class)\s+([\w$]+)/gm, (_, kw, name) => { exportsList.push(name); return `${kw} ${name}`; });
  if (/^\s*export\b/m.test(body)) fail(`${rel}: an export form this tool does not understand`);
  return { imports, body, exportsList };
}

function visit(rel) {
  if (modules.has(rel)) return;
  if (visiting.has(rel)) fail(`import cycle through ${rel}`);
  if (!ALLOWED.has(rel)) fail(`${rel} is in the import graph but is not allowed in the app core (Node, frame reading, OCR and PNG code stay out)`);
  visiting.add(rel);
  const m = parseModule(rel);
  for (const imp of m.imports) {
    if (!imp.from.startsWith('.')) fail(`${rel}: imports "${imp.from}", which is not a relative project module`);
    const target = posix.normalize(posix.join(dirname(rel), imp.from));
    imp.target = target;
    if (STUBS[target]) {
      for (const n of imp.names) if (!STUBS[target].includes(n.name)) fail(`${rel}: imports ${n.name} from stubbed ${target}`);
      continue;
    }
    visit(target);
  }
  visiting.delete(rel);
  modules.set(rel, m);
  order.push(rel);
}
for (const e of ENTRIES) visit(e);

// ---- emit ----
const git = (...a) => execFileSync('git', ['-C', root, ...a], { encoding: 'utf8' }).trim();
const commit = git('rev-parse', 'HEAD'), branch = git('rev-parse', '--abbrev-ref', 'HEAD');
const dirty = git('status', '--porcelain', '--', ...order.map((r) => join(root, r)), ...DATA_FILES.map((f) => join(root, 'data', f)));
if (dirty) fail(`source files have uncommitted changes in ${root}:\n${dirty}`);

const lines = [];
lines.push('// GENERATED by native/tools/build-js-bundle.mjs - do not edit. Classic script for JavaScriptCore; defines the global `PogoCore`.');
lines.push(`// Source: Pogo Assist+ JavaScript, commit ${commit} (branch ${branch}). Rebuild: node native/tools/build-js-bundle.mjs --repo <checkout> --out <dir>`);
lines.push('// SHA-256 of each source file in the bundle:');
for (const rel of order) lines.push(`//   ${sha(readFileSync(join(root, rel)))}  ${rel}`);
lines.push('// SHA-256 of the data files copied beside it:');
for (const f of DATA_FILES) lines.push(`//   ${sha(readFileSync(join(root, 'data', f)))}  data/${f}`);
lines.push('(function (global) {');
lines.push("'use strict';");
lines.push('const __modules = Object.create(null);');
lines.push('function __def(path, fn) { __modules[path] = fn(); }');
lines.push('function __use(path) { const m = __modules[path]; if (!m) throw new Error("PogoCore: module not loaded: " + path); return m; }');
for (const [path, names] of Object.entries(STUBS)) {
  lines.push(`__def(${JSON.stringify(path)}, function () { const cut = (n) => function () { throw new Error(n + " is not part of the app core"); }; return { ${names.map((n) => `${n}: cut(${JSON.stringify(n)})`).join(', ')} }; });`);
}
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/\s\/\/ .*$/gm, '');
for (const rel of order) {
  const m = modules.get(rel);
  if (NODE_WORDS.test(strip(m.body))) fail(`${rel}: mentions a Node API (process, require, Buffer, node:, import.meta)`);
  lines.push(`__def(${JSON.stringify(rel)}, function () {`);
  for (const imp of m.imports) {
    const names = imp.names.map((n) => (n.name === n.local ? n.name : `${n.name}: ${n.local}`)).join(', ');
    lines.push(`const { ${names} } = __use(${JSON.stringify(imp.target)});`);
  }
  lines.push(m.body.trim());
  lines.push(`return { ${m.exportsList.join(', ')} };`);
  lines.push('});');
}
lines.push(FACADE.trim());
lines.push('})(typeof globalThis !== "undefined" ? globalThis : this);');
const text = lines.join('\n') + '\n';

mkdirSync(resolve(out), { recursive: true });
writeFileSync(join(resolve(out), 'pogo-core.js'), text);
for (const f of DATA_FILES) copyFileSync(join(root, 'data', f), join(resolve(out), f));
console.error(`pogo-core.js: ${text.length} bytes, ${order.length} modules from ${commit.slice(0, 7)}; data: ${DATA_FILES.join(', ')} -> ${resolve(out)}`);
selfTest(text);
