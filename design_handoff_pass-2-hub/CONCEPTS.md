# Design pass 2 (Pogo Hub): concepts

Written at the end of the design session of 25 Oct 2026 from `DECISIONS.md` (D1 to D53), then amended the same evening with
Greg's read-back answers (D54 to D58) and three of the manager's calls, which are marked as such. Status: Greg confirmed the
version at 81fd169 as written, and **confirmed the amendments, including the manager's calls, on 25 Oct 2026**. (Confirmation is the manager's addition to the
design process.) The read-back (`READBACK.md`, written by the manager) checks these rules against the engine and PogoBox.

Weights and thresholds below are a first version, accepted by Greg as "a decent attempt" to be tuned later (D15).

## Terms

Each label or word the screens use for a rating, ranking, activity or state, in one sentence.

**Hub and Collection**

- **Squads and collection**: the section on the Hub tab that holds the six area tiles (was WHAT NEXT; D4, D55).
- **Collection**: the area for the player's dex, best copies, sets and missing species, plus the builds, gaps and
  duplicates summaries (replaces Everything; D2, D3).
- **Species (in Collection)**: one dex number released in Pokémon GO; Mega and Shadow entries are not separate species.
- **Showcase**: the strip of the player's best copy of each species, ranked by IV % (name kept, D56).
- **Special sets**: counts of copies or species in named groups (100% IVs, Legendary, Mythical, Ultra Beasts,
  Mega-capable, Lucky, Shadow).
- **Missing**: released species with no copy in the box; **you can evolve** means an earlier member of its family is in
  the box.
- **Build**: one thing the advisor wants done to a copy for an area (power up, evolve, mega evolve, form change, moves).
- **Gap**: an S or A tier Pokémon in a table that nothing in the box can become.
- **Duplicate**: a species with more copies than the advisor keeps; the rest are "copies you can transfer".

**Shared by the squad screens (Raids, Max, Gym, Rocket, PvP)**

- **Squad**: the Pokémon the player takes into one raid, Max battle, gym, Rocket battle or league; the app's one
  word for a team (D55). The game's own names keep their word (Team GO Rocket, the Mixed team grunt).

- **Full strength**: a Pokémon with nothing left to do in its build; shown by a green tick badge (D33).
- **Upgrade available**: a Pokémon whose build still has something to do; shown by an orange up-arrow, with the cost
  (dust or candy) beside it in pickers (D24, D30).
- **Suggestions: Available | Best**: the switch that decides which Pokémon the suggested squads and pickers list. Redefined
  after Greg's phone run of 30 Oct 2026 ("setting a team is confusing right now. available toggle should show available
  pokemon the user has. and best should show a list of pokemon they should aim for including unavailable + available
  ranked"). He ruled: "Available = the users best available pokemon for that position." "Best = the best pokemon
  obtainable in the game even if not current obtainable (with ideally an indicator of when they might be available next
  if thats known, and if not known then when it was last available)".
  **Available** (the default, D29) lists only Pokémon in the player's box, best first for the slot, usable as they are
  (rule 3). **Best** lists the best Pokémon in the game for the slot from our research tier tables, in the tables' order,
  whether or not the player has it and whether or not it can be got now (rule 6).
- **Slot**: one place in a squad; it has a **role** (Raids, Max, PvP) or a leader slot (Rocket) or a defender place (Gym).
- **Role**: the job a slot's Pokémon does; each screen has its own set (below) plus **All**, which allows any Pokémon
  (D16).
- **Picker**: the list under a squad that opens when a slot is tapped; choosing a row puts that Pokémon in the slot.
- **Not in your box** (Best only): a row, or a slot, whose Pokémon the player does not have. It carries an **availability
  line** saying when it might be had: the rotation when the species is a raid or Max boss now or coming ("Raid boss
  now", "Max battle now", "Raids from 9 Nov", "Max Monday 2 Nov", "Max battles from 16 Nov"), else the research table's
  obtain text ("Medium. T5 raids"), which is the only "last available" information the app has (there is no history of
  past dates); "Last available not known" only when the table has no obtain text either. This replaces **Could get now**
  and the **Where tags** (retired 30 Oct 2026; D19 and D27 are superseded).
- **Available upgrades:** the heading in an Available picker over the player's own Pokémon whose build still needs work;
  the ones at Full strength come first, above it (rule 28; phone feedback item 10).
- **Slot status**: the colour of a slot card's background: **ready** (green), **needs work** (amber), **to get** (red:
  under Best, not in the box) or **empty** (red). The disc and the role text keep the role colour (rule 29).
- **Squad status line**: one line over the slots, "Ready", "Nearly ready: 2 need work" or "Not ready: 2 to get, 1 empty",
  with a dot in the same colour (rule 30).
- **Tier chip** (S, A, B): the tier our research tables give a Pokémon for the area.
- **"i"**: the round info button; every explanation of a weight or a rule sits behind one (D17).

**Raids and Max**

- **Now / Coming up**: the raids or Max battles on today, and those still to come.
- **Readiness**: "b of n counters" (or "n of n ready"): how many of the boss's bring types the box has a built counter
  for.
- **Bring**: up to four attacking types that hit the boss for more than normal damage.
- **Your squad – Boss**: the squad planned for one raid or Max battle (D45, D49).
- **Set this squad / Squad set**: the player's own mark that the squad for that raid is ready; a set raid card is filled
  in the accent, a set row is tinted in it (D26, D42, D46, D55).
- **Raid roles**: **Mega** (one per lobby, boosts everyone's damage), **Heavy hitter** (most damage, faints sooner),
  **Bulky hitter** (stays in longer). Suggested mix 1 + 3 + 2 (D5).
- **Max roles**: **Tank**, **Healer**, **Attacker**; suggested one of each (D6).

**Gym**

- **Top defenders**: six suggested defenders, each slot replaceable through the picker (D9).
- **Bulk**: a copy's Defence × HP with its own IVs at the level its build reaches (D20).
- **Level not read**: shown in place of the bulk figure for a copy whose level the scan did not read (manager's call,
  read-back Q5).
- **Gym builds** (was TOP AVAILABLE): the list of Gym builds in the box; built rows carry the Full strength badge
  (D33, D54).

**Team Rocket**

- **Leader card**: one Team GO Rocket leader and the Pokémon it may bring in each of its three slots.
- **Your squad for <leader>**: the three counters the player takes against one leader (D55).
- **Slot by slot**: the player's counter for each leader slot; "beats 2 of 3" when the slot has several options (D51).
- **Next best**: up to three choices when nothing in the box beats a slot (D48, D53).
- **Beaten by**: the small type icons under a grunt's type: the types that hit it for more than normal damage (D35).
- **Counter (grunt list)**: a box Pokémon that hits the grunt's type for more than normal damage.

**PvP**

- **PvP roles**: **Lead** (opens), **Safe swap** (comes in on a bad matchup), **Closer** (finishes) (D13).
- **Score**: our PvPoke-based score for the copy in the league.
- **Top pick / Good pick**: graded numbers (D40): top pick green in a green box, good pick green text.
- **Suggested squad**: the three PvP picks the app proposes for a league, chosen by role (D57).
- **Coverage**: how many of the 18 types the squad hits for more than normal damage; shown, not used to pick (D57).

## Rules

Stated so each can be checked against the code.

### Shared

1. **Full strength vs upgrade**: a Pokémon is full strength when its build is built (`HubTeams.isBuilt`: nothing left to
   do apart from the Dynamax requirement); otherwise it shows Upgrade available.
2. **Cost beside the arrow**: the build's `HubModel.costShort` split into value and currency: "19k" + stardust icon when
   dust is due; the candy count + candy icon when only candy is due; nothing when free. What the work is goes in the
   icon's label ("Upgrade available: power up to level 30").
3. **Available**: only Pokémon in the player's box. A raid, Max, Gym or Rocket pick qualifies when its build keeps the
   copy's own species (`powerUp` and not `formChange` and not `viaMega`); a PvP pick when the option is the copy itself
   (`option.isSelf`). In Available a raid Mega slot is always empty. Available never lists a Pokémon the box lacks, and no
   "could get" list is shown under it (a pick of a Pokémon the box lacks is not placed here; it stays stored and returns
   under Best).
4. **A Pokémon is in one slot at a time**: a copy in another slot of the same squad is not listed in that squad's
   picker; the slot being edited lists its own Pokémon, ticked. On Rocket only Pokémon the player chose leave the list
   (D28). One copy may sit in squads on different screens (manager's call, read-back Q6).
5. **Changing a slot's role** relabels the slot, refills it with the best unused Pokémon for the new role, and keeps a
   Pokémon the player chose (a copy, or under Best a species) unless it does not fit the new role (D16).
6. **Best** (replaces Could get now, 30 Oct 2026): for a slot, the research tier tables' rows for the area, one per Pokémon,
   ranked by tier (S, A, B), then the table's order (the # in the PvP tables). Which rows: Raids, the Raids table entries
   listed under one of the boss's bring types (the strongest bring type first within a tier), with the role `raidRole`
   gives the entry; Max, the Max table's entries with the table's roles (rule 12; Gigantamax entries never), a type that
   hits the boss first within a tier; Gym, the Gym table; Rocket, per leader slot, the Rocket table's entries that hit at
   least one of the slot's options for more than normal damage; PvP, the league's table with the roles of rule 22. Every
   row of the table for the slot is listed (S, A and B). A row shows the player's best copy or build of that Pokémon when
   the box has one (the build at Full strength first, then the least dust, then the least candy), with its mark (Full
   strength, or Upgrade available with the cost); a copy that serves a higher row is not repeated lower down. A row the box
   lacks reads **Not in your box** and its availability line. The suggested squad fills each slot with the first unused row
   for its role, owned or not; a not-owned Pokémon in a slot reads "Not in your box". A pick of a Pokémon the box lacks is
   stored as its species (rule 27) and reads as the player's copy once the box has one.
7. **Type icons**: every type chip is a round icon in the game's type colour, glyph white or ink by
   `Theme.pokemonTypeText`; the type name is its accessibility label.

### Raids

8. **Raid role of a candidate**: Mega when the build mega evolves (or targets a Mega or Primal); Heavy hitter when the
   copy is Shadow or the target's base Attack ≥ 1.3 × base Defence; Bulky hitter otherwise.
9. **Raid candidates and order**: Raids builds whose target counts for one of the boss's bring types
   (`HubRaidsModel.typesCounted`); ordered by the best tier the Raids table gives the target under a bring type, then
   built first, then how many bring types it covers, then the advisor's order; one entry per copy.
10. **Suggested squad**: slots Mega, Heavy, Heavy, Heavy, Bulky, Bulky, each taking the first unused candidate of its role
   (under Available only usable-as-is candidates).
11. **Now as cards**: Raids › Now shows one card per raid on now; the first is chosen on opening; tapping the chosen card
   closes its squad; Coming up stays a list whose rows open and close on tap.

### Max

12. **Max role of a candidate**: from the Max table: section Attackers = Attacker; role text containing "tank" = Tank,
   "healer" = Healer (Blissey both); Gigantamax entries never used. Order: Max tier, then a type that hits the boss,
   then the advisor's order. Suggested: the first Tank, the first Healer, the first Attacker that hits the boss (else the
   first Attacker). Until the app has Dynamax marks every Max pick reads Upgrade available (manager's call, read-back Q7).

### Gym

13. **Defender order**: Gym table tier, then bulk (rule 14); CP is not a sort key. Within a tier, copies whose level is
   not read come after those with a known level and show "level not read"; no level is assumed (manager's call,
   read-back Q5; the design helper assumed level 20).
14. **Bulk**: (target base Defence + copy's Defence IV) × CPM × floor((target base HP + copy's HP IV) × CPM), at the
   build's target level, or the copy's level when built; CPM from `src/cpm.js`.
15. **Built rows on build lists**: a built row shows the Full strength badge in place of the cost figure, and its sub
   line drops " · Free".

### Team Rocket

16. **Slot picker order**: builds with the Rocket or Raids area that hit at least one of the slot's options for more than
   normal damage; most options hit first, then built first, then Rocket area, then tier, score, advisor order.
17. **Type advantage on picker rows**: a row's type icon is in colour when that type hits one of the slot's options for
   more than normal damage, grey otherwise (D52).
18. **Next best**: when no build hits any option: Rocket and Raids builds ordered by fewest of the slot's options that hit
   them for more than normal damage, then built first, Rocket area, tier, score; one per species; up to three, following
   Available | Best; "Not weak to this slot" when none hit them.
19. **Grunt counters**: up to eight per grunt type, one per species, built first, then `HubTeams.gruntCounter`'s order
   (Rocket area, tier, score); the first is the app's own pick. Mixed team and Decoy: "Any strong attacker".
20. **Beaten by**: `HubData.weaknesses(of: [grunt type])`.
21. **Slot lines**: one-option slot: no beats line; several options: "beats all n" or "beats k of n".

### PvP

22. **PvP role of a candidate**: from the league table's role text: "lead" = Lead; "safe swap" or "switch" = Safe swap;
   "closer" = Closer; a candidate may have several or none.
23. **Suggested squad**: slots Lead, Safe swap, Closer, each taking the best-scoring unused candidate listed for that
   role, else the best-scoring unused candidate. Coverage is shown, never used to pick; this replaces today's
   coverage-first `HubTeams.suggestedTeam` (D57).
24. **Number grades**: score ≥ 92 top, ≥ 90 good; IV rank ≤ 100 top, ≤ 500 good; anything else plain.

### Collection

25. **Species count**: game-master entries with `released`, one per dex number, Mega, Shadow and duplicate entries not
   counted; owned when a box copy's species has that dex number. Regions by dex range (Kanto 1–151 … Paldea 906–1025).
26. **Showcase**: each species' best copy by IV %, ties by CP, first twelve.

### Keeping squads

27. **Where squads and picks are kept** (D58): per account, on the phone, surviving re-scans. A raid or Max squad is
   dropped when its event ends. A pick whose copy leaves the box empties the slot, and the slot refills with the
   suggestion. Available | Best is remembered per screen. A slot holds either a copy (its entry id) or, for a Best pick of a
   Pokémon the box lacks, a species key; a species pick is not touched when copies leave the box. A pick that does not fit
   the mode is kept and comes back under its mode. A file saved before species picks existed reads as it did.

28. **Available upgrades** (phone feedback item 10): an Available picker lists the player's own Pokémon with those at Full
   strength first and, under the heading "Available upgrades:", those whose build still needs work (the mark and cost stay
   on each row), each group in the slot's order. When the box has nothing for the slot the text is the screen's own "No
   <screen> build in your box." alone.

### Squad status

29. **Slot status**: **ready** (green) when the slot holds a Pokémon the player has, at Full strength, rated S or A in the
   tier table for this area and slot; **needs work** (amber) when it holds one the player has that shows Upgrade available,
   is rated B or lower, or is not in the table; **to get** (red) when, under Best, it holds a Pokémon the box lacks;
   **empty** (red) when it holds nothing. The card's background is a soft tint of the status colour (Theme's green,
   orange and red); the disc and the role text keep the role colour. A card's VoiceOver label ends with the status.

30. **Squad status line** (identifier `squad-status`): "Ready" when every slot is ready; else, when no slot is empty or to
   get, "Nearly ready: N need work" (N = the slots needing work; "1 needs work"); else "Not ready: " with "N to get" (Best
   only) and "N empty", in that order, joined by a comma. The dot beside it is green, amber or red as the squad is ready,
   nearly ready or not ready. It sits under the squad's heading, above the slots, on all five screens.

## Word check

Each label against every other label on these screens and against the game's own terms. Items 1 and 4 were settled by
Greg's read-back answers (D54, D55); item 6 he kept (D56).

1. **"Available" (the switch) vs "TOP AVAILABLE" (Gym list heading)**: settled. The heading is now "Gym builds" (D54),
   so "available" means only "usable as it is".
2. **"Best" (the switch) vs "Next best" (Rocket) vs "Best defenders first" (Gym "i") vs "best copies" (Showcase)**: four
   meanings of "best". (The switch's Best now means the best in the game for the slot, not the best the box can make.) "Next best" was chosen over "Best available" and "Top options" for this reason (D50, D53); the
   others remain.
3. **"Top"**: "Top defenders" (a squad), "Top 3" (Raids list toggle), "top pick" (PvP grade). A top pick is a grade,
   the rest are lists; acceptable. ("TOP AVAILABLE" is gone, D54.)
4. **"Team" vs "Squad"**: settled. "Squad" everywhere (D55): Set this squad / Squad set, Suggested squad, YOUR SQUAD
   FOR GIOVANNI, SQUADS AND COLLECTION. "Team" stays only in the game's own names (Team GO Rocket, the Mixed team grunt).
5. **"Collection"**: the game has Collection Challenges (sets of species to catch for an event). Our Collection is the
   whole dex; acceptable, but a player may expect challenges there.
6. **"Showcase"**: the game has PokéStop Showcases (contests to enter a Pokémon). Our Showcase is the player's own shelf;
   a real clash in the game's vocabulary. Greg kept the name (D56).
7. **Tier chips S / A / B vs raid stars ★★★★★**: two different tier scales near each other on Raids (our research tier
   of a counter; the game's raid level). They look different (letter chip vs stars); acceptable.
8. **"Upgrade available"**: the game says "Power up" and "Evolve"; "upgrade" covers both. No clash; it is our term.
9. **"Mega" (raid role)**: the role is "the Mega in the squad", which matches the game's rule of one Mega boosting the
   lobby. No clash.
10. **"Heavy hitter", "Bulky hitter", "Lead", "Safe swap", "Closer", "Tank", "Healer", "Attacker"**: the last three are
   the game's own Max battle words; the PvP three are the community's; the raid two are ours. No clash.
11. **"Raids now" (where tag) vs "Now" (segment)**: same meaning (on now). No clash.
12. **"Gaps" (Collection) vs "gap: …" (old Rocket slot text)**: the Rocket slot no longer says "gap:" except for a slot
   with no counter in the box; same meaning. No clash.
