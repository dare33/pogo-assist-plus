// The entry of the app-core bundle, appended by build-js-bundle.mjs inside the bundle's scope (so it can
// reach the module registry). It defines the one global, PogoCore. Raw module functions are exposed as
// they are; the *JSON functions are what the app calls: JSON text in and out (no bridged objects), with
// the indexed game master, tiers and rankings kept in the context after load().
// JSON.stringify drops undefined; the replacer turns the Maps and Sets the advisor uses into plain data.
const P = __use('src/extract/pipeline.js'), B = __use('src/extract/batch.js'), G = __use('src/gamemaster.js'), D = __use('src/data.js'),
  A = __use('src/advise.js'), L = __use('src/leagues.js'), I = __use('src/import/pokegenie.js');
let ctx = null;
const need = () => { if (!ctx) throw new Error('PogoCore.load(gamemaster, tiers, rankings) has not been called'); return ctx; };
const replacer = (k, v) => (v instanceof Map ? Object.fromEntries(v) : v instanceof Set ? [...v] : v);
const out = (v) => JSON.stringify(v, replacer);
// The app reads only each Pokémon's CSV index, whether it resolved, and its leagues; the rest of the analysis record (the whole
// game-master species, every hit) was 5 MB of the 6.7 MB for 2,000 entries and the replacer ran on every value of it. Nothing in
// the slimmed entries can be a Map or a Set, so they go through plain JSON.stringify.
const slim = (e) => (e.unresolved ? { p: { index: e.p.index }, unresolved: true } : { p: { index: e.p.index }, speciesId: e.resolved.speciesId, leagues: e.leagues });
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
    return `{"builds":${out(r.builds)},"gaps":${out(r.gaps)},"hygiene":${out(r.hygiene)},"pokemon":${JSON.stringify(r.pokemon.map(slim))},"areaLabel":${out(A.AREA_LABEL)},"pvpScore":${out(L.PVP_SCORE)}}`;
  },
};
