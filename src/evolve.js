// Evolution candy and the path of evolution steps between two species. Shared by the advisor and the PvP leagues function.
import { baseSpeciesId, evolutionLinks, FORM_CHANGES } from './gamemaster.js';

// Evolution candy: the game master does not carry it. Defaults by position in the family plus known exceptions.
const EVOLVE_CANDY_OVERRIDES = {
  swablu: 400, magikarp: 400, wailmer: 400, meltan: 400, feebas: 100, pidgey: 12, weedle: 12, caterpie: 12, wurmple: 12,
  rattata: 25, rattata_alolan: 25, eevee: 25, sunkern: 50, rhydon: 100, machoke: 100, haunter: 100, dragonair: 100, metang: 100,
  pupitar: 100, shelgon: 100, larvitar: 25, bagon: 25, beldum: 25, dratini: 25, gastly: 25, gible: 25, gabite: 100, riolu: 50,
  swinub: 25, piloswine: 100, rhyhorn: 25, munchlax: 50, chansey: 50, tinkatink: 25, tinkatuff: 100, rookidee: 25, corvisquire: 100,
  mankey: 50, primeape: 100, fletchling: 25, fletchinder: 100, fuecoco: 25, crocalor: 100, mareep: 25, flaaffy: 100, fidough: 50,
  drilbur: 50, cubone: 50, wooper: 50, wooper_paldean: 50, dewpider: 50, spearow: 50, slakoth: 25, vigoroth: 100, frillish: 50,
  piplup: 25, prinplup: 100, totodile: 25, croconaw: 100, sobble: 25, drizzile: 100, charmander: 25, charmeleon: 100, mudkip: 25,
  marshtomp: 100, machop: 25, timburr: 50, gurdurr: 200, teddiursa: 50, ursaring: 100, roggenrola: 50, boldore: 200, litwick: 25, lampent: 100,
  nickit: 50, flabebe: 25, floette: 100, tympole: 25, palpitoad: 100, scorbunny: 25, raboot: 100, grookey: 25, thwackey: 100, vulpix: 50,
  vulpix_alolan: 50, ralts: 25, kirlia: 100, electabuzz: 100, magmar: 100, sneasel: 100, duskull: 25, dusclops: 100, larvesta: 400,
  // Poke Genie's candy costs in the fixture (test/leagues.test.js report) show the position rule is wrong for these; karrablast is shelmet's twin.
  corsola_galarian: 50,
  pikachu: 50, metapod: 50, kakuna: 50, pidgeotto: 50, tranquill: 50, pidove: 12, shelmet: 200, karrablast: 200, lickitung: 100, murkrow: 100,
};
export function evolveCandy(index, fromId, toId) {
  const from = baseSpeciesId(index, fromId);
  if (EVOLVE_CANDY_OVERRIDES[from] !== undefined) return EVOLVE_CANDY_OVERRIDES[from];
  const p = index.byId.get(from);
  const isFirst = !p?.family?.parent;
  const hasGrandchild = (p?.family?.evolutions ?? []).some((e) => (index.byId.get(e)?.family?.evolutions ?? []).length);
  return isFirst ? (hasGrandchild ? 25 : 50) : 100;
}

/** Path of evolution steps from one id to a descendant: [[from, to], ...]. */
export function evolutionPath(index, fromId, toId) {
  const queue = [[fromId, []]];
  const seen = new Set([fromId]);
  while (queue.length) {
    const [id, path] = queue.shift();
    if (id === toId) return path;
    for (const next of [...evolutionLinks(index, id), ...(FORM_CHANGES[id] ?? [])]) {
      if (!seen.has(next)) { seen.add(next); queue.push([next, [...path, [id, next]]]); }
    }
  }
  return null;
}
