/** Index PvPoke's game master JSON for lookups. Node code loads the file via src/node/load.js; the browser fetches it. */
export function indexGamemaster(gm) {
  const byId = new Map();
  const byTokens = new Map();      // sorted normalised tokens of speciesName -> speciesId
  const byDex = new Map();         // dex -> [species]
  const moves = new Map(gm.moves.map((m) => [m.moveId, m]));
  for (const p of gm.pokemon) {
    byId.set(p.speciesId, p);
    byTokens.set(tokenKey(p.speciesName), p.speciesId);
    if (!byDex.has(p.dex)) byDex.set(p.dex, []);
    byDex.get(p.dex).push(p);
  }
  return { raw: gm, byId, byTokens, byDex, moves, timestamp: gm.timestamp };
}

// Words that do not identify a species or form and can be dropped when matching names.
const NOISE = new Set(['forme', 'form', 'unovan', 'the', 'regular', 'standard', 'dynamax', 'gigantamax', 'gmax', 'g', 'max']);
const DEFAULT_FORMS = ['ordinary', 'altered', 'incarnate', 'land', 'confined', 'standard', 'average', 'baile', 'aria', 'normal'];
const FORM_ALIASES = {
  galar: 'galarian', alola: 'alolan', hisui: 'hisuian', paldea: 'paldean',
  '10%': '10', '50%': '50', 'pa\'u': 'pau', 'pau': 'pau',
};

export function tokenKey(name) {
  const tokens = String(name)
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')   // strip accents: Flabébé -> flabebe
    .replace(/♀/g, ' female').replace(/♂/g, ' male')
    .toLowerCase()
    .replace(/[()]/g, ' ')
    .replace(/[-_]/g, ' ')
    .replace(/[^a-z0-9%'.\s]/g, '')
    .split(/\s+/)
    .filter(Boolean)
    .map((t) => FORM_ALIASES[t] ?? t)
    .map((t) => t.replace(/[.']/g, ''))
    .filter((t) => !NOISE.has(t));
  return tokens.sort().join(' ');
}

/**
 * Resolve a display name plus optional form and flags to a game-master speciesId.
 * Accepts tier-list style names ("Shadow Rhyperior", "Mega Charizard Y", "Crowned Shield Zamazenta")
 * and Poke Genie style (name "Charizard", form "Mega Y", shadow flag).
 * Returns { speciesId, species, flags: {shadow, mega, max} } or null.
 */
export function resolveSpecies(index, name, { form = '', shadow = false } = {}) {
  const flags = { shadow, mega: false, max: false, megaForm: null };
  // A Poke Genie scan taken while Mega-evolved writes the Mega as the form; the Pokémon is the base species.
  if (/\b(mega|primal)\b/i.test(form)) { flags.mega = true; flags.megaForm = form; form = ''; }
  let text = `${name} ${form}`;
  const lower = text.toLowerCase();
  if (/\b(dynamax|gigantamax|g-max|gmax)\b/.test(lower)) flags.max = true;
  if (/\bmega\b|\bprimal\b/.test(lower)) flags.mega = true;
  if (/\bshadow\b/.test(lower)) flags.shadow = true;
  if (form.toLowerCase() === 'normal') text = name;

  const tryKeys = [];
  const base = tokenKey(text);
  tryKeys.push(flags.shadow && !/\bshadow\b/.test(lower) ? `${base} shadow` : base);
  // Poke Genie writes the Mega form as the Pokémon's form; a scan of a Mega is really the base Pokémon.
  tryKeys.push(tokenKey(text.replace(/\bmega( [xy])?\b/gi, '').replace(/\bprimal\b/gi, '')));
  tryKeys.push(tokenKey(name));
  for (const key of tryKeys) {
    const id = index.byTokens.get(key);
    if (id) return { speciesId: id, species: index.byId.get(id), flags };
    // Species whose plain name is a specific form in the game master (Keldeo -> Ordinary, Giratina -> Altered ...).
    for (const df of DEFAULT_FORMS) {
      const id2 = index.byTokens.get([...key.split(' '), df].sort().join(' '));
      if (id2) return { speciesId: id2, species: index.byId.get(id2), flags };
    }
  }
  // A Shadow that the game master does not list yet (unreleased): fall back to the regular form, flagged.
  if (flags.shadow) {
    const plain = resolveSpecies(index, name.replace(/\bshadow\b/gi, ''), { form });
    if (plain) return { ...plain, flags: { ...plain.flags, shadow: true, unreleasedShadow: true } };
  }
  // Fallback: Poke Genie sometimes writes a form the game master names differently; try each species with the same first token.
  const first = tokenKey(name).split(' ').sort((a, b) => b.length - a.length)[0];
  const candidates = [...index.byId.values()].filter((p) => tokenKey(p.speciesName).split(' ').includes(first));
  if (candidates.length === 1) return { speciesId: candidates[0].speciesId, species: candidates[0], flags };
  return null;
}

/** All speciesIds reachable by evolution from a species (excluding itself), following the game master's family links. */
export function evolutionsOf(index, speciesId) {
  const out = [];
  const seen = new Set([speciesId]);
  const stack = [speciesId];
  while (stack.length) {
    const p = index.byId.get(stack.pop());
    for (const next of p?.family?.evolutions ?? []) {
      if (!seen.has(next)) { seen.add(next); out.push(next); stack.push(next); }
    }
  }
  return out;
}

// Form changes that are projects rather than evolutions: energy, cells or fusion turn the left id into the right ones.
export const FORM_CHANGES = {
  zamazenta_hero: ['zamazenta_crowned_shield'],
  zacian_hero: ['zacian_crowned_sword'],
  zygarde_10: ['zygarde_50', 'zygarde_complete'],
  zygarde_50: ['zygarde_complete'],
  kyurem: ['kyurem_white', 'kyurem_black'],
  necrozma: ['necrozma_dawn_wings', 'necrozma_dusk_mane'],
  hoopa_confined: ['hoopa_unbound'],
  shaymin_land: ['shaymin_sky'],
};

/** Ids reachable by a form change (energy, cells, fusion) from a species, excluding itself. */
export function formChangesOf(index, speciesId) {
  const out = [];
  const stack = [speciesId];
  while (stack.length) {
    for (const next of FORM_CHANGES[stack.pop()] ?? []) if (!out.includes(next) && index.byId.has(next)) { out.push(next); stack.push(next); }
  }
  return out;
}

/** The base (non-shadow, non-mega) speciesId for any variant, e.g. rhyperior_shadow -> rhyperior, charizard_mega_y -> charizard. */
export function baseSpeciesId(index, speciesId) {
  let id = speciesId.replace(/_shadow$/, '');
  if (!index.byId.has(id)) id = speciesId;
  const m = id.match(/^(.*)_(mega(?:_[xy])?|primal)$/);
  if (m && index.byId.has(m[1])) id = m[1];
  return id;
}

export function shadowIdOf(index, speciesId) {
  const id = `${baseSpeciesId(index, speciesId)}_shadow`;
  return index.byId.has(id) ? id : null;
}

/** Mega/Primal variant ids of a base species. */
export function megaIdsOf(index, speciesId) {
  const base = baseSpeciesId(index, speciesId);
  return ['_mega', '_mega_x', '_mega_y', '_primal'].map((s) => base + s).filter((id) => index.byId.has(id));
}
