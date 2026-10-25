// The entry of the app-core bundle, appended by build-js-bundle.mjs inside the bundle's scope (so it can
// reach the module registry). It defines the one global, PogoCore. Raw module functions are exposed as
// they are; the *JSON functions are what the app calls: JSON text in and out (no bridged objects), with
// the indexed game master, tiers and rankings kept in the context after load().
// JSON.stringify drops undefined; the replacer turns the Maps and Sets the advisor uses into plain data.
const P = __use('src/extract/pipeline.js'), B = __use('src/extract/batch.js'), G = __use('src/gamemaster.js'), D = __use('src/data.js'),
  A = __use('src/advise.js'), I = __use('src/import/pokegenie.js');
let ctx = null;
const need = () => { if (!ctx) throw new Error('PogoCore.load(gamemaster, tiers, rankings) has not been called'); return ctx; };
const replacer = (k, v) => (v instanceof Map ? Object.fromEntries(v) : v instanceof Set ? [...v] : v);
const out = (v) => JSON.stringify(v, replacer);
// The app reads only each Pokémon's CSV index, whether it resolved, its leagues, and its activity fit; the rest of the analysis record (the whole
// game-master species, every hit) was 5 MB of the 6.7 MB for 2,000 entries and the replacer ran on every value of it. Nothing in
// the slimmed entries can be a Map or a Set, so they go through plain JSON.stringify.
// fit crosses as a compact array per area, with tag s / o / w (strong, ok, weak). The tag is worth alone (cost-free); the advisor's build is a separate
// marker carried as a tail on the same array, present only on the copy that carries it:
//   s / o   [tag, as, tier]                                         with the build  [tag, as, tier, true, buildAs, dust, candy, xl]
//   w       [tag, null, null, reason]                               reason iv adds ivPct at 4, reason none adds the species name at 4
//           (none, iv, ivUnknown, shadowNoMega)                     with the build  [tag, null, null, reason, extra|null, true, buildAs, dust, candy, xl]
// so a build tail starts at index 3 for s / o and at 5 for w; `extra` is the engine's one-decimal IV % (which prefers the row's imported figure) for iv,
// and the display name its line uses for none, so the app words "IVs 79.9%" and "No table entry for Meowth (Galarian)" from the engine's own text. The
// engine's sentence (`line`) is not sent; the app composes it from these. buildAs is the primary build's target name; dust, candy and xl are its cost
// figures (the Advice panel's).
const FIT_TAG = { strong: 's', ok: 'o', weak: 'w' };
const slimFit = (fit) => Object.fromEntries(Object.entries(fit).map(([area, f]) => {
  const tail = f.build ? [true, f.buildAs, f.buildCost.dust, f.buildCost.candy, f.buildCost.xl] : [];
  if (f.tag !== 'weak') return [area, [FIT_TAG[f.tag], f.as, f.tier, ...tail]];
  const extra = f.reason === 'iv' ? f.ivPct : f.reason === 'none' ? f.species : undefined;
  const head = ['w', null, null, f.reason];
  return [area, tail.length ? [...head, extra ?? null, ...tail] : extra === undefined ? head : [...head, extra]];
}));
const slim = (e) => {
  if (e.unresolved) return { p: { index: e.p.index }, unresolved: true };
  const o = { p: { index: e.p.index }, speciesId: e.resolved.speciesId, leagues: e.leagues, fit: slimFit(e.fit) };
  if (e.bestOf.length) o.bestOf = e.bestOf;
  return o;
};
global.PogoCore = {
  // raw module functions (objects in, objects out)
  indexGamemaster: G.indexGamemaster, indexTiers: D.indexTiers, indexRankings: D.indexRankings,
  finish: P.finish, cpOptions: P.cpOptions, toPokeGenieCsv: P.toPokeGenieCsv, POKEGENIE_COLUMNS: P.POKEGENIE_COLUMNS,
  mergeClips: B.mergeClips, importPokeGenie: I.importPokeGenie, analyseBox: A.analyseBox, AREA_LABEL: A.AREA_LABEL,
  // JSON-text layer
  load(gmText, tiersText, rankingsText) {
    ctx = { gm: G.indexGamemaster(JSON.parse(gmText)), tiers: D.indexTiers(JSON.parse(tiersText)), rankings: D.indexRankings(JSON.parse(rankingsText)) };
    return true;
  },
  finishJSON(readingsText) { return out(P.finish(JSON.parse(readingsText), need().gm)); },
  // scanDateMs: epoch milliseconds, shown in the device's local time (like new Date() in the CLI)
  csvJSON(rowsText, scanDateMs) { return P.toPokeGenieCsv(JSON.parse(rowsText), { scanDate: scanDateMs == null ? new Date() : new Date(scanDateMs) }); },
  mergeClipsJSON(clipsText, optionsText) { return out(B.mergeClips(JSON.parse(clipsText), optionsText ? JSON.parse(optionsText) : undefined)); },
  importPokeGenieJSON(csvText) { return out(I.importPokeGenie(csvText)); },
  adviseJSON(boxText) {
    const r = A.analyseBox(JSON.parse(boxText), need());
    return `{"builds":${out(r.builds)},"gaps":${out(r.gaps)},"hygiene":${out(r.hygiene)},"pokemon":${JSON.stringify(r.pokemon.map(slim))},"areaLabel":${out(A.AREA_LABEL)}}`;
  },
};
