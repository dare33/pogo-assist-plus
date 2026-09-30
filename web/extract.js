// Wiring for web/extract.html: pick a recording, decode it in the browser, run it through the
// same extractor modules the CLI uses, show progress and a results table. Nothing here is
// uploaded anywhere — decode, OCR and solving all happen on this device.
//
// Top-level code only registers the DOMContentLoaded listener, guarded so this module can still
// be imported (not run) from Node for a smoke test.

import { extract, toPokeGenieCsv } from '../src/extract/pipeline.js';
import { createOcr } from '../src/extract/ocr.js';
import { indexGamemaster } from '../src/gamemaster.js';
import { mergeClips, orderClips, passKind } from '../src/extract/batch.js';
import { decodeFrames, csvFilename, reviewFilename, mergedCsvFilename, mergedReviewFilename, downloadText, formatElapsed } from './extract-core.js';

const TESSERACT_VERSION = '7.0.0';
const FPS = 5;

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

let run = null; // { cancelled } for the in-progress extraction, so Stop can signal it

function showError(msg) {
  $('#intro').insertAdjacentHTML('afterbegin', `<div class="error">${esc(msg)}</div>`);
}

function clearErrors() {
  $('#intro').querySelectorAll('.error').forEach((e) => e.remove());
}

// `clipLabel` is "clip i of n — name" for several files, empty for one.
function setProgress(done, total, found, clipLabel = '') {
  $('#foundCount').textContent = String(found);
  const frames = total ? `frame ${done} / ${total}` : `frame ${done}`;
  $('#frameStats').textContent = clipLabel ? `${clipLabel}, ${frames}` : frames;
  $('#bar').style.width = total ? `${Math.min(100, (done / total) * 100)}%` : '0%';
}

function elapsedSeconds(t0) {
  return (performance.now() - t0) / 1000;
}

function ivsText(ivs) {
  return ivs ? `${ivs.atk}/${ivs.def}/${ivs.hp}` : '?';
}

function levelText(row) {
  if (row.level === null) return '?';
  return row.level === row.levelMax ? String(row.level) : `${row.level}–${row.levelMax}`;
}

function renderRows(rows) {
  $('#rowCount').textContent = String(rows.length);
  const flagged = rows.filter((r) => r.flags.length).length;
  $('#flagSummary').textContent = flagged ? `${flagged} flagged for review` : 'none flagged for review';
  $('#rows').innerHTML = rows.map((r) => `<tr>
    <td class="num">${r.index}</td>
    <td class="name">${esc(r.display ?? r.name)}</td>
    <td>${esc(r.form)}</td>
    <td class="num">${r.cp}</td>
    <td class="num">${r.hp ?? '?'}</td>
    <td class="num">${esc(ivsText(r.ivs))}</td>
    <td class="num">${esc(levelText(r))}</td>
    <td>${r.shadow === 1 ? 'Shadow' : r.shadow === 2 ? 'Purified' : ''}</td>
    <td><div class="flagset">${r.flags.map((f) => `<span class="flagtag">${esc(f)}</span>`).join('')}</div></td>
    <td class="muted">${esc([r.clip, r.frames?.[0]?.frame].filter(Boolean).join(' · '))}${r.frames?.length > 1 ? ` +${r.frames.length - 1}` : ''}</td>
  </tr>`).join('') || '<tr><td colspan="10" class="empty">No Pokémon found.</td></tr>';
}

// One or more recordings of one account: each is decoded and read in turn, then merged the way
// scripts/extract-box.mjs merges a folder (boundary duplicates dropped, a "shadow" clip marks the
// Shadow column). A file that cannot be decoded is reported and the rest still count.
async function runExtraction(fileList) {
  const files = orderClips(fileList.map((f) => ({ name: f.name, mtimeMs: f.lastModified, file: f }))).map((c) => c.file);
  clearErrors();
  $('#intro').hidden = true;
  $('#results').hidden = true;
  $('#run').hidden = false;
  setProgress(0, null, 0);
  $('#elapsed').textContent = '0:00';

  const controller = { cancelled: false };
  run = controller;
  const t0 = performance.now();
  const timer = setInterval(() => { $('#elapsed').textContent = formatElapsed(elapsedSeconds(t0)); }, 250);
  let ocr = null;

  try {
    // The ESM bundle has a default export only (checked against dist/tesseract.esm.min.js).
    const Tesseract = (await import(`https://cdn.jsdelivr.net/npm/tesseract.js@${TESSERACT_VERSION}/dist/tesseract.esm.min.js`)).default;
    const createWorker = Tesseract.createWorker;
    ocr = await createOcr(createWorker, {
      workerPath: `https://cdn.jsdelivr.net/npm/tesseract.js@${TESSERACT_VERSION}/dist/worker.min.js`,
      corePath: `https://cdn.jsdelivr.net/npm/tesseract.js-core@${TESSERACT_VERSION}`,
      langPath: new URL('../data/tessdata', location.href).href,
      gzip: false,
    });
    const gmJson = await fetch(new URL('../data/gamemaster.json', location.href)).then((r) => {
      if (!r.ok) throw new Error(`data/gamemaster.json: ${r.status}`);
      return r.json();
    });
    const gm = indexGamemaster(gmJson);

    const done = [], failed = [], notes = [];
    let foundBefore = 0;
    for (const [i, file] of files.entries()) {
      if (controller.cancelled) break;
      const clipLabel = files.length > 1 ? `clip ${i + 1} of ${files.length} — ${file.name}` : '';
      setProgress(0, null, foundBefore, clipLabel);
      let totalEstimate = null, stoppedEarly = null;
      try {
        const decoded = decodeFrames(file, FPS, (ev) => {
          if (ev.phase === 'start') totalEstimate = ev.totalEstimate;
          if (ev.phase === 'end') stoppedEarly = ev.stoppedEarly;
        });
        async function* guarded() {
          for await (const frame of decoded) {
            if (controller.cancelled) return;
            yield frame;
          }
        }
        const r = await extract(guarded(), {
          ocr, gm,
          onProgress: ({ done: n, found }) => setProgress(n, totalEstimate, foundBefore + found, clipLabel),
        });
        foundBefore += r.rows.length;
        const where = files.length > 1 ? ` in ${file.name}` : '';
        if (controller.cancelled) notes.push(`Stopped early by you: rows${where} cover only the part of the recording that was processed.`);
        else if (stoppedEarly) notes.push(`The browser stopped decoding${where} before the end (${stoppedEarly}); rows cover only the part that was decoded.`);
        done.push({ name: file.name, kind: passKind(file.name), rows: r.rows, unmatched: r.unmatched });
      } catch (e) {
        failed.push({ name: file.name, error: e.message });
      }
    }
    if (!done.length) throw new Error(failed.length ? failed.map((f) => f.error).join('\n\n') : 'No recording was processed.');
    for (const f of failed) notes.push(`Could not read "${f.name}", so its Pokémon are missing: ${f.error}`);

    const merged = mergeClips(done);
    for (const c of merged.clips) if (c.kind !== 'normal') notes.push(`"${c.name}" was treated as a ${c.kind}-filtered pass: matching Pokémon are marked in the Shadow column.`);
    const r = merged.reconciled;
    if (r.appended) notes.push(`${r.appended} Pokémon appeared only in the shadow/purified pass and were added to the end of the list.`);
    if (r.ambiguous) notes.push(`${r.ambiguous} shadow/purified Pokémon matched several identical rows; the first was marked and flagged shadow-match-ambiguous.`);
    if (merged.unmatched.length) notes.push(`${merged.unmatched.length} frame${merged.unmatched.length === 1 ? '' : 's'} showed a CP but no recognisable species name (a nickname, or a garbled read); they are listed in the review JSON, not in the table.`);

    $('#run').hidden = true;
    $('#results').hidden = false;
    $('#elapsedFinal').textContent = formatElapsed(elapsedSeconds(t0));
    $('#notes').innerHTML = notes.map((n) => `<div class="note">${esc(n)}</div>`).join('');
    renderRows(merged.rows);
    wireResultActions(files, merged, failed);
  } catch (e) {
    $('#run').hidden = true;
    $('#intro').hidden = false;
    showError(e.message);
  } finally {
    clearInterval(timer);
    if (ocr) await ocr.terminate();
    run = null;
  }
}

function wireResultActions(files, merged, failedClips) {
  const { rows, review, unmatched, boundaries, reconciled, clips } = merged;
  const one = files.length === 1;
  const today = new Date();
  $('#downloadCsv').onclick = () => downloadText(toPokeGenieCsv(rows), one ? csvFilename(files[0]) : mergedCsvFilename(today), 'text/csv');
  $('#downloadReview').onclick = () => downloadText(JSON.stringify({ rows, review, unmatched, boundaries, reconciled, clips, failedClips }, null, 2), one ? reviewFilename(files[0]) : mergedReviewFilename(today), 'application/json');
  // Rows whose name, CP, HP and bars cannot be reconciled are misreads, not Pokémon: the advisor
  // gets the rest. Ambiguous rows go through with blank IVs (the CSV already leaves them blank).
  const junk = rows.filter((r) => r.flags.includes('no-level-fits'));
  const good = rows.filter((r) => !junk.includes(r));
  $('#loadAdvisor').textContent = junk.length ? `Load ${good.length} into advisor (${junk.length} unreadable left out)` : 'Load into advisor';
  $('#loadAdvisor').onclick = () => {
    sessionStorage.setItem('pogo-extracted-csv', toPokeGenieCsv(good));
    location.href = '../index.html?extracted';
  };
}

function pickFiles(list) {
  const files = Array.from(list ?? []);
  if (!files.length) return;
  runExtraction(files);
}

function init() {
  const drop = $('#drop'), input = $('#file');
  drop.addEventListener('click', (e) => { if (!e.target.closest('label')) input.click(); });
  drop.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); input.click(); } });
  input.addEventListener('change', () => { pickFiles(input.files); input.value = ''; });
  ['dragenter', 'dragover'].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('over'); }));
  ['dragleave', 'drop'].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove('over'); }));
  drop.addEventListener('drop', (e) => pickFiles(e.dataTransfer.files));
  $('#stop').addEventListener('click', () => { if (run) run.cancelled = true; });
}

if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init);
}
