# Status — Pogo Assist+

**25 Sep 2026, phase 0a done.** Game master loader with a name resolver (tier-list and Poke
Genie naming both handled), CP multipliers and power-up cost tables validated against a real
311-row export, Poke Genie importer, tier-table builder (317 entries from the eight markdown
tables), and a box dump script. Tests: 7 passing.

**Known data gaps found by the dump:** Pokémon that the tier tables only mention in prose
(Annihilape, Dachsbun, Ampharos, Galarian Stunfisk, regular Moltres) get no hit. Phase 0b adds
PvPoke's overall rankings (fetched to `data/rankings/`, not yet slimmed or committed) as a
second signal so PvP-relevant species are found by score, not just by table row.

**Next, phase 0b:** slim and load the rankings; build ranking (tier weight × areas ÷ cost);
gap list with obtain routes; storage hygiene; compare against the hand-written build plan.

**Blocked:** remote `dare33/pogo-assist-plus` does not exist yet; the GitHub App cannot create
repositories. Greg to create it, then it gets attached and this history pushed.
