// Match an OCR'd name to the species the game would have shown. The game prints the base name,
// with "Mega" / "Alolan" / "Galarian" style prefixes; other forms (Hero, Altered, Origin...) are
// not in the name, so one display name can map to several game-master species. The solver
// picks between those by CP and HP.

const REGIONAL = { alolan: 'Alola', galarian: 'Galar', hisuian: 'Hisui', paldean: 'Paldea' };

/** Base name and Poke Genie style form ("", "Hero", "Mega Y", "Alola") of a game-master species. */
export function nameAndForm(species) {
  const m = species.speciesName.match(/^(.*?)\s*\((.*)\)$/);
  const base = m ? m[1] : species.speciesName;
  const form = m ? m[2] : '';
  return { name: base, form: REGIONAL[form.toLowerCase()] ?? form };
}

/** Candidate display names from the game master: [{ display, name, form, speciesIds: [] }]. */
export function displayNames(gm) {
  const byDisplay = new Map();
  const add = (display, name, form, speciesId) => {
    const key = normalise(display);
    if (!byDisplay.has(key)) byDisplay.set(key, { display, name, form, speciesIds: [] });
    byDisplay.get(key).speciesIds.push(speciesId);
  };
  for (const p of gm.byId.values()) {
    if (p.speciesId.endsWith('_shadow')) continue; // same name on screen; the shadow flag is elsewhere
    const m = p.speciesName.match(/^(.*?)\s*\((.*)\)$/);
    const base = m ? m[1] : p.speciesName;
    const form = m ? m[2] : '';
    const lower = form.toLowerCase();
    if (/^mega( [xy])?$|^primal$/.test(lower)) add(`${lower.startsWith('mega') ? 'Mega' : 'Primal'} ${base}${/ [xy]$/.test(lower) ? ' ' + form.slice(-1).toUpperCase() : ''}`, base, form, p.speciesId);
    else if (REGIONAL[lower]) add(`${form} ${base}`, base, REGIONAL[lower], p.speciesId);
    else add(base, base, form, p.speciesId);
  }
  return [...byDisplay.values()];
}

export function normalise(text) {
  return String(text).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
}

/** Levenshtein distance. */
export function distance(a, b) {
  const m = a.length, n = b.length;
  if (!m) return n; if (!n) return m;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur;
  }
  return prev[n];
}

/**
 * Best candidate for an OCR'd name. Tries the whole text, then the text with stray one-letter or
 * punctuation tokens dropped (the edit-pencil icon often reads as a dot or a letter). Returns
 * { candidate, distance, text } or null when nothing is close enough.
 */
export function matchName(text, candidates, { maxRatio = 0.25 } = {}) {
  const variants = new Set();
  const norm = normalise(text);
  if (!norm) return null;
  variants.add(norm);
  const tokens = norm.split(' ');
  variants.add(tokens.filter((t) => t.length > 1).join(' '));
  if (tokens.length > 1) { variants.add(tokens.slice(1).join(' ')); variants.add(tokens.slice(0, -1).join(' ')); }
  let best = null;
  for (const v of variants) {
    if (!v) continue;
    for (const c of candidates) {
      const key = normalise(c.display);
      const d = distance(v, key);
      const limit = Math.max(1, Math.floor(key.length * maxRatio));
      if (d <= limit && (!best || d < best.distance || (d === best.distance && v.length > best.text.length))) best = { candidate: c, distance: d, text: v };
    }
  }
  return best;
}
