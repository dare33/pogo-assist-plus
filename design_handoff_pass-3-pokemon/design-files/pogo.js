// Data helpers for the design pass 3 boards: they load Greg's box (worked out by the app's own PogoBox code) and turn it into the
// values the boards show. No UI is built here; each board's own template draws everything.
(function () {
  var BOX = '/_blob/538c8eb6cef3f4d7a199d6bae8a296f8';
  var cache = null;
  function load() { if (!cache) cache = fetch(BOX).then(function (r) { return r.json(); }); return cache; }

  // Our own glyphs (pass 2, D22), not the game's artwork.
  var TYPE_PATHS = {
    normal: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zm0 4.5a4.5 4.5 0 1 1 0 9a4.5 4.5 0 1 1 0-9z',
    fire: 'M12 2c1 4 6 6 6 12a6 6 0 0 1-12 0c0-3 2-5 3-6c0 2 1 3 2 3c0-4-1-6 1-9z',
    water: 'M12 2.5c3 4.5 6 8 6 11.5a6 6 0 0 1-12 0c0-3.5 3-7 6-11.5z',
    electric: 'M13.5 2L5 13.5h6L9.5 22L19 9.5h-6.5L13.5 2z',
    grass: 'M19 3C9 3 4.5 9 4.5 15.5c0 1.2.2 2.4.6 3.5L7 17.1C9.6 17.9 19 15 19 3z',
    ice: 'M11 2h2v7.3l6.3-3.6 1 1.7L14 11l6.3 3.6-1 1.7L13 12.7V22h-2v-9.3l-6.3 3.6-1-1.7L10 11 3.7 7.4l1-1.7L11 9.3z',
    fighting: 'M6 10a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v5a5 5 0 0 1-5 5h-2a5 5 0 0 1-5-5zM7.5 3.5h2.5v3.5H7.5zM11 2.5h2.5v4.5H11zM14.5 3.5H17v3.5h-2.5z',
    poison: 'M4 14a5 5 0 1 0 10 0a5 5 0 1 0-10 0zM14 7a3 3 0 1 0 6 0a3 3 0 1 0-6 0zM15 17a2 2 0 1 0 4 0a2 2 0 1 0-4 0z',
    ground: 'M2 19L9 7l4 6 2.5-3.5L22 19z',
    flying: 'M3 14c4-1 7-4 9-10c1 4 1 7-1 9c3 0 6-1 9-3c-2 5-6 8-11 8c-2 0-4-1-6-4z',
    psychic: 'M12 6C7 6 3.5 9.5 2 12c1.5 2.5 5 6 10 6s8.5-3.5 10-6c-1.5-2.5-5-6-10-6zm0 3a3 3 0 1 1 0 6a3 3 0 1 1 0-6z',
    bug: 'M8 4.5l2.2 2.2h3.6L16 4.5l1.2 1.2-2 2.2A5 5 0 0 1 17 11.5v3.5a5 5 0 0 1-10 0v-3.5a5 5 0 0 1 1.8-3.6l-2-2.2z',
    rock: 'M7 4h9l5 6-3 9H7l-4-8z',
    ghost: 'M12 3a7 7 0 0 0-7 7v11l2.5-2 2.3 2 2.2-2 2.2 2 2.3-2 2.5 2V10a7 7 0 0 0-7-7zM9.5 9a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3zm5 0a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3z',
    dragon: 'M4 20c0-8 4.5-14 15-16c-4 3-6 6-6 9c2-1 4.5-1 6.5 0c-4.5 1-7.5 3-8.5 7z',
    dark: 'M15 3a9 9 0 1 0 6 15.5A7 7 0 0 1 15 3z',
    steel: 'M12 2l8.7 5v10L12 22l-8.7-5V7zm0 6.5a3.5 3.5 0 1 0 0 7a3.5 3.5 0 1 0 0-7z',
    fairy: 'M11 2c.8 5 2 7.2 7 8-5 .8-6.2 3-7 8-.8-5-2-7.2-7-8 5-.8 6.2-3 7-8zM18.5 14c.3 2 1 2.7 3 3-2 .3-2.7 1-3 3-.3-2-1-2.7-3-3 2-.3 2.7-1 3-3z',
  };
  function types(list) {
    return (list || []).map(function (t) {
      var k = String(t).toLowerCase();
      return { cls: 'pt-' + k, name: k.charAt(0).toUpperCase() + k.slice(1), path: TYPE_PATHS[k] || TYPE_PATHS.normal };
    });
  }
  function fmt(n) { return n == null ? '' : Number(n).toLocaleString('en-US'); }
  function lvl(n) { return n == null ? '' : (n === Math.round(n) ? String(n) : String(n)); }
  function rows(d) { var out = []; (d ? d.sections : []).forEach(function (s) { s.rows.forEach(function (r) { out.push(r); }); }); return out; }
  function speciesRow(d, title) { return rows(d).find(function (r) { return r.title === title; }) || null; }
  function copy(d, id) { var c = d && d.copies[id]; if (!c) return null; var o = Object.assign({ id: id }, c); return o; }
  function members(d, title) { var r = speciesRow(d, title); return r ? r.members.map(function (id) { return copy(d, id); }) : []; }
  function ivLine(c) { return c.ivs ? c.ivs.join('/') + ' · ' + c.pct + '%' : 'IVs not read'; }

  // "62k dust" / "25 candy" / "Free" (HubModel.costShort) as the number and its currency icon (pass 2, D30).
  function costParts(s) {
    if (!s || s === 'Free') return { hasCost: false, costValue: '', isDust: false, isCandy: false };
    var m = s.split(' ');
    return { hasCost: true, costValue: m[0], isDust: m[1] === 'dust', isCandy: m[1] === 'candy' };
  }
  function short(n) { return n >= 10000 ? Math.round(n / 1000) + 'k' : fmt(n); }
  // One copy's mark: Upgrade available (its first build, in the advisor's order, still has work) or Full strength (every build done).
  function mark(c) {
    var open = (c.builds || []).filter(function (b) { return !b.built; });
    if (open.length) {
      var b = open[0];
      return Object.assign({ up: true, done: false, upTitle: 'Upgrade available: ' + b.todo + (b.costShort && b.costShort !== 'Free' ? ', ' + b.costShort : '') }, costParts(b.costShort));
    }
    if ((c.builds || []).length) return { up: false, done: true, upTitle: 'Full strength', hasCost: false, costValue: '', isDust: false, isCandy: false };
    return { up: false, done: false, upTitle: '', hasCost: false, costValue: '', isDust: false, isCandy: false };
  }
  // A species row's mark (my call, to confirm): Upgrade available when any copy has work left, with the dust those builds need in
  // total (candy when no dust is due); Full strength when it has builds and all are done.
  function speciesMark(d, r) {
    var builds = [];
    r.members.forEach(function (id) { (d.copies[id].builds || []).forEach(function (b) { builds.push(b); }); });
    var open = builds.filter(function (b) { return !b.built; });
    if (open.length) {
      var dust = 0, candy = 0, copies = 0;
      r.members.forEach(function (id) { if ((d.copies[id].builds || []).some(function (b) { return !b.built; })) copies++; });
      open.forEach(function (b) { dust += b.dust; candy += b.candy; });
      var s = dust > 0 ? short(dust) + ' dust' : candy > 0 ? fmt(candy) + ' candy' : 'Free';
      return Object.assign({ up: true, done: false, upTitle: 'Upgrade available: ' + copies + (copies === 1 ? ' copy' : ' copies') + ' to build' + (s !== 'Free' ? ', ' + s : '') }, costParts(s));
    }
    if (builds.length) return { up: false, done: true, upTitle: 'Full strength', hasCost: false, costValue: '', isDust: false, isCandy: false };
    return { up: false, done: false, upTitle: '', hasCost: false, costValue: '', isDust: false, isCandy: false };
  }
  // Number grades (pass 2, D40): top = score 92+ or IV rank within the best 100; good = score 90+ or IV rank within 500.
  function scoreGrade(n) { return n == null ? '' : n >= 92 ? 'num-top' : n >= 90 ? 'num-good' : ''; }
  function rankGrade(n) { return n == null ? '' : n <= 100 ? 'num-top' : n <= 500 ? 'num-good' : ''; }
  // IV % on Box and species rows (my proposal, tunable): top = 100%, good = 93% or more (42 of 45).
  function pctGrade(p) { return p == null ? '' : p >= 100 ? 'num-top' : p >= 93 ? 'num-good' : ''; }
  function letter(t) { var c = t.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().charAt(0); return /[A-Z]/.test(c) ? c : '#'; }
  // Fewer words (pass 2, D51 and D53): the Advice notes as short labels; the full sentences sit behind an "i".
  function shortNotes(c) {
    var out = [];
    var planned = (c.spareFor || []).filter(function (x, i, a) { return a.indexOf(x) === i && x !== c.title; });
    if (c.spare) out.push((c.builds || []).length ? 'Also spare' + (planned.length ? ' for ' + planned.join(', ') : '') : 'Spare' + (planned.length ? ': ' + planned.join(', ') + ' planned' : ''));
    var v = c.verdict || '', n = /One of (\d+) /.exec(v);
    var keep = /\*\*Keep it:\*\* (.*?)\.?$/.exec(v);
    if (keep) out.push('Keep · ' + keep[1].replace(/^it has (one of )?your /, '').replace(/^it is (one of )?your /, '').replace(/^it is /, '').replace('of the ', 'of '));
    else if (/transfer/.test(v)) out.push('Transfer' + (n ? ' · one of ' + n[1] : ''));
    return out;
  }
  // `abbr` is the only short form of a league's name on the redesigned boards (Greg, D3); `short` is today's app wording.
  var LEAGUES = [{ key: 'gl', name: 'Great League', abbr: 'GL', short: 'Great', cap: 'Under 1,500 CP' }, { key: 'ul', name: 'Ultra League', abbr: 'UL', short: 'Ultra', cap: 'Under 2,500 CP' }, { key: 'ml', abbr: 'ML', name: 'Master League', short: 'Master', cap: 'No CP cap' }];

  window.Pogo = { load: load, types: types, fmt: fmt, lvl: lvl, rows: rows, speciesRow: speciesRow, copy: copy, members: members, ivLine: ivLine,
    costParts: costParts, short: short, mark: mark, speciesMark: speciesMark, scoreGrade: scoreGrade, rankGrade: rankGrade, pctGrade: pctGrade,
    letter: letter, shortNotes: shortNotes, LEAGUES: LEAGUES };
})();
