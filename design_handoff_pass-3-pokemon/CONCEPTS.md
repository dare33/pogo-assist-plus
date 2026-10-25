# Design pass 3 (the Pokémon screens): concepts

Written at the end of the design session of 25 Oct 2026 from `DECISIONS.md` (the session's calls C1 to C8, Greg's
decisions D1 to D26). Status: **confirmed by Greg** on 25 Oct 2026 ("I've read CONCEPTS.md and confirm it as written."). The
read-back (`READBACK.md`, written by the manager) checks these rules against the engine, PogoBox and the app.

The design that stands is **Option A** (the My Pokémon tab whose species open in place, and the Pokémon page with activity
tabs). Option B (one screen per species) was drawn and not chosen; its terms are left out. Where a rule below is the
session's proposal rather than Greg's ruling, it says so; Greg accepted pass 2's rules as "a decent attempt" to be tuned
later, and the same holds here unless he says otherwise.

## Terms

Each label or word the screens use for a rating, ranking, activity or state, in one sentence.

**My Pokémon tab (was the Box tab)**

- **My Pokémon**: the first tab of the floating tab bar and the screen's title, the player's stored Pokémon grouped by
  species (D9, D10). "Box" stays the word for the stored set in sentences ("your box").
- **Species row**: one row per species title (`ScanRow.title`, so a form is its own row), A to Z, with its type icons,
  count, best IV % and top CP, and its build mark.
- **Build mark on a species row**: the upgrade arrow with a cost when any copy of the species has work left; the Full
  strength tick when it has builds and all are done; nothing when it has no build (C2).
- **Open in place**: tapping a species row opens it inside the list, under the row (Option A; C7).
- **TOP PVP**: the two copies of the species with the best PvP standing (D1).
- **TOP IVS**: the next two copies by IVs (D1).
- **See all N copies**: the button under an open species that opens the full species list (D12).
- **A–Z index**: the letters on the right that jump through the list; shown only while the list scrolls (D23, D24).

**The Pokémon page**

- **Details card**: the card at the top of the page: name, types, CP, level and HP, the IV bars, the three marks, and the
  advanced details when open (D4).
- **Dynamax mark**: the player's own mark that this copy was caught as Dynamax; on or off (D22).
- **Shadow mark**: the player's own mark that this copy is a Shadow Pokémon; on or off (D22).
- **Advanced details**: the section the sliders mark opens on the details card, where the player records moves, Max move
  levels, the Mega level and more (D26).
- **Elite**: a move the species can only learn with an Elite TM or an event (the game master's `eliteMoves`).
- **Max moves**: Max Attack (named by the fast move's type, e.g. Max Geyser for Water), Max Guard and Max Spirit, each at a
  level (D26).
- **Mega level**: how far this copy's Mega form has levelled: Not yet, Base, High or Max (D26).
- **Lucky, Purified, Best Buddy, Weather-boosted**: the player's own marks for those states in the game (D26).
- **Activity tabs**: Summary, PvP, Raids, Gym, Rocket, Max, under the details card; each shows how this copy fits that
  activity (D5, D11).
- **Summary**: the first tab: one row per activity (name, verdict, the facts behind it, the cost), then the Advice (D14
  to D20).
- **Verdict**: the one-word status on a Summary row (D14, D18): **FULL STRENGTH** (this copy's build for the activity is
  done), **PLANNED** (it has a build there with work left), **SPARE** (another copy is your best for that raid type),
  **OPTION** (listed in the activity's table, nobody planned), **NOT PICKED** (gym: listed, not the top defender),
  **BEATS N GRUNTS** (Rocket: its types beat N grunt types), **NEEDS DYNAMAX** (Max: listed, not marked as Dynamax),
  **STRONG / OK / WEAK** (PvP: the best league's worth tag), **NOT USED** (nothing the copy can become is in the table).
- **Reach**: the copy's own species and what it can still evolve into; never back up the family (D5).
- **League tile**: one of three tiles on the PvP tab (GL, UL, ML), each with the pick, its score and rank, this copy's IV %
  and rank, the worth tag and the cost mark (C7, D3).
- **Family and details**: the row under the tiles that opens the chosen league's other family members, the reasons and
  the moves ("Great League family and details (8 more)") (D4).
- **Counters** (Raids tab): the raids on now and coming whose bosses the attacking type hits for more than normal damage.
- **Bulk**: Defence × HP of the species with this copy's IVs at its current level (pass 2's rule).
- **Top defender**: the first of the Gym screen's top defenders (pass 2's order), the yardstick on the Gym tab.
- **League names**: a league is named in full ("Great League") or as GL, UL, ML, never "Great" alone (D3).

Pass 2's terms are used unchanged: **Upgrade available**, **Full strength**, **top / good** number grades, the **"i"**,
**worth tags** (Strong, OK, Weak), and the app-wide **squad** for team and **Gym builds** (pass 2, D54, D55).

## Rules

Stated so each can be checked against the code. "Proposal" marks the session's own rule, still open to tuning.

### My Pokémon

1. **Species rows**: `BoxIndex.sections(query:chip:sort:)` as today; the row's types are its first member's species types.
2. **Species build mark** (proposal, C2): the upgrade arrow when any member has a build with work left, the cost being the
   dust of those builds in total, or their candy when no dust is due; the Full strength tick when it has builds and all
   are built (`HubTeams.isBuilt`).
3. **IV % grade on rows** (proposal, C3): top at 100%, good at 93% (42 of 45) or more.
4. **TOP PVP** (D1; rule a proposal, the Great and Ultra limit confirmed by Greg): a copy's PvP standing is its best Great
   or Ultra League card that fits under the cap, by the pick's PvPoke score, ties by this copy's IV rank; Master League is
   left out; the two best copies show, with the league, the pick and its score, and this copy's IV rank, graded as rule 9.
5. **TOP IVS** (D1): the next two copies in the species list's order (best IVs first) that are not in TOP PVP, each with
   its keep or transfer tag.
6. **Tapping a TOP PVP row** opens that copy with its league's tile chosen.
7. **The A–Z index** appears while the list scrolls and fades a second after it stops (D24).

### The Pokémon page

8. **Marks** (D22): the Dynamax and Shadow marks each toggle on and off; a Shadow mark clears Purified and Purified clears
   Shadow.
9. **Number grades** (C1, pass 2's D40): top = score 92+ or IV rank 1–100; good = score 90+ or IV rank 101–500; anything
   else plain. Replaces the page's old green at score 80+ and IV rank to 500.
10. **Reach** (proposal, D5): the activity tabs look only at the copy's species and the evolutions below it
    (`GameMaster.Species.evolutions`, breadth first).
11. **Raids tab** (proposal): one card per reachable member and attacking type the Raids table lists, best tier first;
    the plan is this copy's Raids build for that member, else the box's best Raids build for that type (tier, then built);
    counters are the raids on now and coming (`HubRaidsModel.timeline`) whose `bring` types include the attacking type,
    up to six.
12. **Gym tab** (proposal): one card per reachable member the Gym table lists, best tier then bulk; the bar is this copy's
    bulk over the top defender's.
13. **Rocket tab** (proposal): a member "beats" a grunt type or a leader option when one of its own types hits it for more
    than normal damage (`HubData.effectiveness` > 1); moves are not checked (the export has none); up to four members,
    most grunt types first.
14. **Max tab** (proposal): the reachable members the Max table lists; NEEDS DYNAMAX until the Dynamax mark is on; the Max
    battles on now and coming that a member's types hit.
15. **Summary verdicts** (proposal, D14): as the Terms above; for Rocket the member shown is the one with a Rocket build,
    else the one beating most grunt types, ties to the later evolution.
16. **Summary lines** (D20): one fact per line; PvP lists each league on its own line ("GL Eevee 54.9", or "GL over the
    cap"); a boss's form in brackets is dropped unless two bosses share the name.
17. **Advanced details** (D26): fast and charged moves are only those in the species' `fastMoves` and `chargedMoves`; the
    second charged move starts "Not unlocked" and cannot equal the first; Max moves show only while the Dynamax mark is
    on; Max Attack's name follows the chosen fast move's type, levels 1–3, Max Guard and Max Spirit –, 1–3; the Mega
    level shows only for a species with a `_mega` (or `_mega_x/_y`, `_primal`) entry in the game master.
18. **Defaults** (proposal): the first fast move and the first non-Elite charged move; the export carries no moves, so
    nothing comes from the scan.
19. **The page opens on Summary**; the tabs read Summary, PvP, Raids, Gym, Rocket, Max (D11); Summary's rows start with PvP
    leagues (D8).

## Word check

Each label against the others on these screens, against pass 2's screens and against the game's own terms. Clashes to
settle (none renamed in this pass):

1. **"My Pokémon" (tab) vs "your box" (sentences) vs "Box" (today's code, `BoxView`, and the path map)**: the tab is
   renamed, the word for the stored set is not. Suggest keeping "box" only in code and saying "your Pokémon" in copy.
2. **"Top" again**: TOP PVP and TOP IVS (copies), "Top defender" (gym yardstick), "top" number grade, pass 2's "Top
   defenders" list. A copy in TOP PVP is not necessarily graded "top". Acceptable on different screens; worth a look on
   the Pokémon page, where the grade and "Your top defender" sit together.
3. **"OK" (worth tag and PvP verdict) vs "OPTION" (verdict)**: OK grades a league pick, OPTION says nobody planned it.
   Same screen, different meanings; the verdict OK only repeats the tag.
4. **"PLANNED" vs the advisor's "build"**: Planned means the advisor has a build for this copy in that activity; the
   upgrade arrow means the same build has work left. Consistent, two words for one thing.
5. **"SPARE" (verdict) vs "Spare: Umbreon, Vaporeon, Glaceon planned" (Advice tag)**: the verdict means another copy is
   your best for that raid type; the tag means the advisor already planned a better copy. Close, not identical.
6. **"BEATS 4 GRUNTS" (verdict) vs pass 2's "beats 2 of 3" (Rocket slot cards)**: both are type advantage; the counts are
   of different things (grunt types vs a leader slot's options).
7. **"NOT PICKED" (gym) vs "Gym builds" (pass 2, D54)**: a copy can be in Gym builds and still not be the top defender.
8. **"Counters"**: Raids tab (raids this type helps against) vs the Hub's counters (box Pokémon for a boss); same idea
   seen from the other side. No clash.
9. **"Mega level" (Not yet / Base / High / Max)**: the game calls them Mega Levels; check the game's own level names
   before building.
10. **"Elite"**: the game says "Elite TM"; our tag is short for it. No clash.
11. **"Purified", "Shadow", "Lucky", "Best Buddy", "Weather-boosted", "Max Guard", "Max Spirit"**: the game's own words.
12. **"Summary" (tab) vs pass 2's "SUGGESTIONS"**: different things on different screens. No clash.
13. **"Family"** ("Eevee family", "Great League family and details"): the species' evolution family, as the game's candy
    family. No clash.
