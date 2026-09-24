# Status — Pogo Assist+

**25 Sep 2026, phase 0b done (core logic).** `src/advise.js` turns an export into ranked builds,
a gap list and storage hygiene. Scoring: raid value counts each attacking type covered (up to
three); PvP areas are scaled by the Pokémon's own rank in that league from the export; Gym and
Max count less; Mega hits fold into the base Pokémon; Gigantamax entries are never credited to
an evolution; Dynamax entries are flagged "needs a Dynamax copy"; duplicate copies fold into one
build with spares. `scripts/advise.mjs` prints the report. Tests: 13 passing.

Against the hand-written build plan the top of the list agrees (Mewtwo, Zamazenta Crowned,
Gengar, Tyranitar, Rhyperior, Charizard, Blissey, Tinkaton). Known differences: Snorlax ranks
higher here because it scores in four areas; Xurkitree ranks lower because it is a single-area
build. Both are defensible; revisit after the page exists and real use shows what people want.

**Next, phase 0c:** the web page. Drop a CSV, see the builds, gaps and hygiene; GitHub Pages
deploy. Then the codec spike on an iPhone 16 Pro recording before any extractor code.

**Data notes:** evolution candy costs are a table in `advise.js` (the game master lacks them);
unknown species default by family position. Dynamax status is not in exports, so Max hits are
advisory until the extractor captures the badge.
