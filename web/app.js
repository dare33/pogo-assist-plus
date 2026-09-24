import { importPokeGenie } from '../src/import/pokegenie.js';
import { indexGamemaster } from '../src/gamemaster.js';
import { indexTiers, indexRankings } from '../src/data.js';
import { analyseBox, AREA_LABEL } from '../src/advise.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const k = (n) => (n >= 1000 ? `${Math.round(n / 1000)}k` : String(n));
const iv = (p) => (p.ivs ? `${p.ivs.atk}/${p.ivs.def}/${p.ivs.hp}` : '?');
const label = (p) => `${p.name}${p.form && p.form !== 'Normal' ? ` (${p.form})` : ''}${p.shadow ? ' · Shadow' : ''}`;
const areaChips = (areas) => areas.map((a) => `<span class="area area-${a}">${AREA_LABEL[a]}</span>`).join('');
const badge = (t) => `<span class="badge badge-${t}">${t}</span>`;

let ctx = null;
let result = null;
let activeArea = null;

async function loadContext() {
  const [gm, tiers, rankings] = await Promise.all(['data/gamemaster.json', 'data/tiers.json', 'data/pvp-rankings.json'].map((u) => fetch(u).then((r) => { if (!r.ok) throw new Error(`${u}: ${r.status}`); return r.json(); })));
  ctx = { gm: indexGamemaster(gm), tiers: indexTiers(tiers), rankings: indexRankings(rankings) };
  $('#datastamp').textContent = `Reference data: game master ${gm.timestamp?.slice(0, 10) ?? ''}, tier tables ${tiers.generated?.slice(0, 10) ?? ''}, PvP rankings ${rankings.fetched?.slice(0, 10) ?? ''}.`;
}

function analyse(csvText, sourceName) {
  let box;
  try { box = importPokeGenie(csvText); } catch (e) { return showError(`Could not read ${sourceName}: ${e.message}`); }
  if (!box.length || !('name' in box[0])) return showError(`${sourceName} does not look like a Poke Genie export (no rows).`);
  result = analyseBox(box, ctx);
  result.box = box;
  render();
}

function showError(msg) {
  $('#intro').insertAdjacentHTML('afterbegin', `<div class="error">${esc(msg)}</div>`);
}

function render() {
  $('#intro').hidden = true;
  $('#results').hidden = false;
  $('#tabs').hidden = false;
  const { box, builds, gaps, hygiene, pokemon } = result;
  const transfers = hygiene.reduce((s, h) => s + h.transfer.length, 0);
  $('#summary').innerHTML = [
    [box.length, 'Pokémon scanned'], [builds.length, 'builds found'], [builds.filter((b) => b.bestTier === 'S').length, 'S-tier builds'],
    [gaps.filter((g) => g.tier === 'S').length, 'S-tier gaps'], [transfers, 'safe to transfer'], [pokemon.filter((e) => e.unresolved).length, 'unrecognised'],
  ].map(([n, l]) => `<div class="tile"><div class="n">${n}</div><div class="l">${l}</div></div>`).join('');
  const areas = ['raids', 'rocket', 'gym', 'gl', 'ul', 'ml', 'max'];
  $('#areaChips').innerHTML = areas.map((a) => `<button class="chip" data-area="${a}" aria-pressed="false">${AREA_LABEL[a]}</button>`).join('');
  renderBuilds(); renderGaps(); renderHygiene(); renderAll();
  applyFilter();
}

function renderBuilds() {
  const rows = result.builds.map((b, i) => {
    const what = (b.targetId === b.speciesId ? 'Power up' : `${b.formChange ? 'Form change to' : 'Evolve to'} <strong>${esc(b.targetName)}</strong>`) + (b.viaMega ? ' + Mega' : '');
    const flags = [
      b.needsDynamax ? '<span class="flag flag-warn">Max needs a Dynamax copy</span>' : '',
      b.moveFlags.elite ? `<span class="flag flag-bad">${b.moveFlags.elite} Elite TM</span>` : '',
      b.moveFlags.cd ? '<span class="flag flag-warn">Community Day move</span>' : '',
      b.moveFlags.legacy ? '<span class="flag flag-locked">Legacy move</span>' : '',
      b.spares.length ? `<span class="flag flag-good">+${b.spares.length} spare</span>` : '',
    ].join('');
    const cost = [`${k(b.cost.dust)} dust`, b.cost.candy ? `${b.cost.candy} candy` : '', b.cost.xl ? `${b.cost.xl} XL` : ''].filter(Boolean).join(', ');
    const lv = b.targetLevel ? `L${b.level} → ${b.targetLevel}` : `L${b.level} → best ${b.pvpCost.league.toUpperCase()} level`;
    const pvp = b.pvpCost ? ` · ${b.pvpCost.league.toUpperCase()} IV rank #${b.pvpCost.rank}` : '';
    const hits = b.hits.map((h) => `<li>${h.tier} ${AREA_LABEL[h.area]}${h.section ? ` / ${esc(h.section)}` : ''}: ${esc(h.name)}${h.moves ? ` — ${esc(h.moves)}` : ''}${h.rank ? ` (PvPoke #${h.rank}, ${h.score})` : ''}</li>`).join('');
    return `<tr data-areas="${b.areas.join(' ')}"><td class="num">${i + 1}</td><td class="name">${esc(label(b.pokemon))}<span class="sub">CP ${b.pokemon.cp} · L${b.pokemon.level} · ${iv(b.pokemon)}${pvp}</span></td><td>${what}${flags ? `<div>${flags}</div>` : ''}<details class="hits"><summary>why</summary><ul>${hits}</ul></details></td><td>${areaChips(b.areas)}</td><td>${badge(b.bestTier)}</td><td class="muted">${lv}<span class="sub">${cost}</span></td><td class="num">${b.score}</td></tr>`;
  }).join('');
  $('#panel-builds').innerHTML = `<div class="table-wrap"><table><thead><tr><th>#</th><th>Pokémon</th><th>Build</th><th>Areas</th><th>Tier</th><th>Cost from here</th><th>Score</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

function renderGaps() {
  const rows = result.gaps.map((g) => `<tr data-areas="${g.area}"><td>${badge(g.tier)}</td><td>${areaChips([g.area])}${g.section ? `<span class="sub">${esc(g.section)}</span>` : ''}</td><td class="name">${esc(g.name)}${g.haveBase ? '<span class="sub">you have the base species; this needs a different variant</span>' : ''}</td><td class="muted">${esc(g.obtain ?? '')}</td></tr>`).join('');
  $('#panel-gaps').innerHTML = `<p class="fine">S and A entries that nothing in your storage can become, by evolution, form change or Mega.</p><div class="table-wrap"><table><thead><tr><th>Tier</th><th>Area</th><th>Pokémon</th><th>How to obtain</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

function renderHygiene() {
  const rows = result.hygiene.map((h) => `<tr><td class="name">${esc(h.name)}</td><td class="num">${h.count}</td><td>${h.keep.map((p) => `CP ${p.cp} (${iv(p)})`).join(', ')}</td><td class="num">${h.transfer.length}</td><td class="muted">${h.transfer.map((p) => `CP ${p.cp} (${iv(p)})`).join(', ')}</td></tr>`).join('');
  $('#panel-hygiene').innerHTML = `<p class="fine">Duplicates by species. Keep the best IVs (two for legendaries); the rest are candy. Favourite the keepers before a mass transfer.</p><div class="table-wrap"><table><thead><tr><th>Species</th><th>Have</th><th>Keep</th><th>Transfer</th><th>Which</th></tr></thead><tbody>${rows || '<tr><td colspan="5" class="empty">No duplicates.</td></tr>'}</tbody></table></div>`;
}

function renderAll() {
  const rows = result.pokemon.map((e) => {
    const p = e.p;
    const best = e.hits?.length ? e.hits.reduce((t, h) => ({ S: 3, A: 2, B: 1 }[h.tier] > ({ S: 3, A: 2, B: 1 }[t]) ? h.tier : t), 'B') : null;
    const areas = e.hits ? [...new Set(e.hits.map((h) => h.area))] : [];
    return `<tr data-areas="${areas.join(' ')}"><td class="name">${esc(label(p))}${e.unresolved ? '<span class="sub">not recognised</span>' : ''}</td><td class="num">${p.cp}</td><td class="num">${p.level ?? ''}</td><td class="num">${iv(p)}</td><td class="num">${p.ivPercent ?? ''}%</td><td>${best ? badge(best) : ''}</td><td>${areaChips(areas)}</td><td class="num">${p.pvp?.great?.rank ?? ''}</td><td class="num">${p.pvp?.ultra?.rank ?? ''}</td></tr>`;
  }).join('');
  $('#panel-all').innerHTML = `<div class="table-wrap"><table><thead><tr><th>Pokémon</th><th>CP</th><th>Lvl</th><th>IVs</th><th>IV %</th><th>Best tier</th><th>Areas</th><th>GL rank</th><th>UL rank</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

function applyFilter() {
  const q = ($('#search').value || '').trim().toLowerCase();
  const panel = document.querySelector('.panel:not([hidden])');
  if (!panel) return;
  panel.querySelectorAll('tbody tr').forEach((tr) => {
    const okQ = !q || tr.textContent.toLowerCase().includes(q);
    const okA = !activeArea || (tr.dataset.areas || '').split(' ').includes(activeArea);
    tr.hidden = !(okQ && okA);
  });
}

function selectTab(id) {
  document.querySelectorAll('.tab').forEach((t) => t.setAttribute('aria-selected', t.dataset.tab === id ? 'true' : 'false'));
  document.querySelectorAll('.panel').forEach((p) => { p.hidden = p.id !== `panel-${id}`; });
  applyFilter();
}

function readFile(file) {
  const reader = new FileReader();
  reader.onload = () => analyse(reader.result, file.name);
  reader.onerror = () => showError(`Could not read ${file.name}.`);
  reader.readAsText(file);
}

document.addEventListener('DOMContentLoaded', async () => {
  const drop = $('#drop'), input = $('#file');
  drop.addEventListener('click', (e) => { if (!e.target.closest('label')) input.click(); });
  drop.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); input.click(); } });
  input.addEventListener('change', () => { if (input.files[0]) readFile(input.files[0]); });
  ['dragenter', 'dragover'].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('over'); }));
  ['dragleave', 'drop'].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove('over'); }));
  drop.addEventListener('drop', (e) => { const f = e.dataTransfer.files[0]; if (f) readFile(f); });
  document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => selectTab(t.dataset.tab)));
  $('#search').addEventListener('input', applyFilter);
  $('#areaChips').addEventListener('click', (e) => {
    const chip = e.target.closest('.chip'); if (!chip) return;
    activeArea = activeArea === chip.dataset.area ? null : chip.dataset.area;
    document.querySelectorAll('.chip').forEach((c) => c.setAttribute('aria-pressed', c.dataset.area === activeArea ? 'true' : 'false'));
    applyFilter();
  });
  try { await loadContext(); } catch (e) { showError(`Reference data failed to load: ${e.message}`); return; }
  // ?sample loads the bundled example export so the page can be seen working without a file.
  if (new URLSearchParams(location.search).has('sample')) {
    const r = await fetch('fixtures/greg-2026-09-25.pokegenie.csv');
    if (r.ok) analyse(await r.text(), 'sample export');
  }
});
