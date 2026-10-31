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
- **Collection**: the area for the player's dex, special sets and missing species, plus the builds, gaps and
  duplicates summaries (replaces Everything; D2, D3).
- **Species (in Collection)**: one dex number released in Pokémon GO; Mega and Shadow entries are not separate species.
- **Showcase**: removed on 31 Oct 2026 (Greg: "we'd just remove the currently highest IV copy showcase as we won't need it with the 'hundo' one"). It was the strip of the player's highest IV copy of each species (name kept, D56; heading "YOUR HIGHEST IV COPIES", Greg, 30 Oct 2026). Each Special set is now laid out like it (rule 26).
- **Special sets**: counts of copies or species in named groups (Hundo, Legendary, Mythical, Ultra Beasts,
  Mega-capable, Lucky, Shadow, Dynamax, Gigantamax, Shiny, Background). Each is a strip of copy cards, laid out like the old Showcase, the set's best Pokémon for its activity first, with "All N ›" opening the set's full list (Greg, 31 Oct 2026: "Best pokemon for that activity first + All").
  Dynamax and Gigantamax are the copies carrying those marks (the hand marks and the Dynamax and Gigantamax passes set them). Shiny and Background hold no data yet: their strips are one "Coming soon" card with no list (Greg, 31 Oct 2026).
  "All N ›" opens a sheet listing the player's Pokémon in the set, in My Pokémon's rows (Greg, phone run 30 Oct 2026): the
  copies in the set for Hundo, Lucky and Shadow, each owned species with all its copies for Legendary, Mythical and Ultra
  Beasts, and for Mega-capable only the copies that can Mega Evolve. The card's count and the list are one definition (`HubCollection.Membership`). Lucky shows
  "Not in your scans yet" until a copy is marked: its strip says so and it has no "All" button. A set with no Pokémon has no "All" button.
  Rulings after review (manager, 31 Oct 2026): the species sets count species but the sheet lists form rows as My Pokémon
  shows them (Giratina Altered and Origin are two rows, one species), and says "Forms are listed separately." under
  the title when it has more rows than species. **Mega-capable** is the copy's own: its species-form has a Mega
  Evolution in the game master and it is not a Shadow (a Shadow Pokémon cannot Mega Evolve), so Galarian Slowbro,
  Armored Mewtwo, Alolan Raichu and any Shadow copy are out; the card, the sheet and the "mega" search follow it.
  **Shadow** follows the hand mark when there is one (Shadow = Shadow, Purified or 0 = not Shadow) and the `_shadow`
  species only decides for a copy with no mark. The sheet's count and list follow the box as it is edited.
- **Hundo**: a copy with 15/15/15 IVs (a perfect IV spread). Was "100% IVs"; renamed, same meaning (Greg, 31 Oct 2026: "Change the name of 100% IVs to 'Hundo'").
- **Missing**: released species with no copy in the box; **you can evolve** means an earlier member of its family is in
  the box. The species are the 959 of rule 25. On the Collection it is one summary card (how many are missing, with a short breakdown: the ones you can evolve now, the Legendary, the Mythical and the region with the most missing) that opens the full list (Greg, 31 Oct 2026: "turn the Missing segment into a bit of a summary card and when clicked it opens up to the list").
- **Build**: one thing the advisor wants done to a copy for an area (power up, evolve, mega evolve, form change, moves).
- **Gap**: an S or A tier Pokémon in a table that nothing in the box can become.
- **Duplicate**: a species with more copies than the advisor keeps; the rest are "copies you can transfer or trade" (Greg, phone run 30 Oct 2026).

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
  Redefined again after Greg's eyeball check of 31 Oct 2026 ("Available vs best - still not thinking we're on the same page
  with this one. I wanted Available to be the one where the app picks for the user ... what it thinks would be the optimal
  team based on the users box right now ... I wanted Best to be - if the user wanted to go out of their way to get the best
  pokemon for this activity what would that be and include the availability of that pokemon").
  **Available** (the default, D29) is the app's suggested squad from the box as it is now: every slot filled with the strongest
  Pokémon the player owns for it, whatever upgrade it needs, with the needs-work status and its cost shown (rule 3).
  **Best** lists the best Pokémon in the game for the slot from our research tier tables, in the tables' order, owned or
  not, each with one of three statuses (rule 6).
- **Slot**: one place in a squad; it has a **role** (Raids, Max, PvP) or a leader slot (Rocket) or a defender place (Gym).
- **Role**: the job a slot's Pokémon does; each screen has its own set (below) plus **All**, which allows any Pokémon
  (D16).
- **Picker**: the list under a squad that opens when a slot is tapped; choosing a row puts that Pokémon in the slot.
- **Best status** (Best only, S1): every Best row and slot carries exactly one of **In your box** (with "needs upgrade" when its
  build needs work), **Can get now** (a raid, Max or Rocket boss now, or obtainable now per the research's obtain line) or **Not
  available now** (with when it is next on, if the schedule knows), rule 6. There is no history of past dates and no "last
  available" text. This replaces **Could get now** and the **Where tags** (retired 30 Oct 2026; D19 and D27 are superseded) and the
  earlier "Not in your box" availability line.
- **In your box · needs upgrade** with no build: a Best row or slot whose Pokémon the box has a copy of, but no build or league candidate
  of this area and slot serves (a Lapras with no Gym build; a PvP species scoring under 80 or past the cap). It shows the
  player's best copy, in amber, and counts as needing work.
- **Same copy as <row>**: a Best row whose only copy is the one a higher row already shows; it still lists, with that note.
- **Available upgrades:** the heading in an Available picker over the player's own Pokémon whose build still needs work;
  the ones at Full strength come first, above it (rule 28; phone feedback item 10).
- **Slot status**: the colour of a slot card's background: **ready** (green), **needs work** (amber), **to get** (red:
  under Best, not in the box) or **empty** (red). A card also
  says it in a word and an icon, so colour is never the only sign. The disc and the role text keep the role colour (rule 29).
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
3. **Available** (S1, 31 Oct 2026, Greg: "I wanted Available to be the one where the app picks for the user (and provides
   alternative options for each slot when clicked on) what it thinks would be the optimal team based on the users box
   right now (would still show the needs work indicator)"): the app's suggested squad from the box as it is now, on all
   five squad screens. Every slot is filled with the strongest Pokémon the player owns for it, **whatever upgrade it
   needs**: power up, evolve, form change or Mega Evolve (Greg: "Yes, include them"); the needs-work status and its cost
   are shown. No build is dropped for being more than a power up (this replaces the old rule that a pick kept the
   copy's own species: `powerUp` and not `formChange` and not `viaMega`, `option.isSelf`).
   **Mega builds belong in the Mega slot, and only there** (manager call, 31 Oct 2026, from the first review). A raid **Mega slot takes a Mega candidate**: a copy
   that can Mega Evolve now (Mega-capable is per copy: its species-form with `_shadow` stripped has a Mega or Primal in the game master that is released and
   tagged `mega`, the Collection's own rule, and the copy is not a Shadow, which never Mega Evolves), or one whose build ends in a Mega or Primal it reaches by
   evolving (a Gastly whose build ends in Mega Gengar; Greg: include Pokémon that need "evolving or Mega Evolving"). In the Mega slot a copy is ranked, graded and
   costed on its Mega build; a copy that can Mega Evolve but has no build that does shows Mega Evolve still to do, and the Mega slot never reads Ready. In every other
   slot, fallback slots included, a copy is ranked, graded and costed as the plain Pokémon: its own table entry for the boss, no Mega Evolve step in its cost; a plain
   form the boss's types do not list ranks below every listed counter. A raid squad holds one Mega only, in either mode: under Best, once a slot holds a Mega row no later slot takes one and the picker offers none (a manager
   call; the slot holding it still lists them). A Mega-capable copy with no Mega build is rated against the table for its Mega form like any other Mega build.
   **Gym, Rocket and Max have no Mega slot** (manager ruling, 31 Oct 2026): every copy there, in every list, squad, Next best and grunt strip, is judged, ranked and
   costed on its plain form (no Mega Evolve step; a build that does not Mega Evolve comes before one that did). Under Available **every copy with a Raids build is a
   raid candidate**: one the tables do not list against the boss is unlisted (tier ""), taken only after every listed one. **Fill with any role** (Greg's choice): each role's own slots are
   filled across the whole squad first, strongest first, among the candidates the tables list against the boss; then a slot still empty takes the strongest unused listed Pokémon of
   another role and shows that role ("Its role: Bulky hitter"); only after that the unlisted ones, the slot's own role's first (manager call, rule 10). The Mega slot never takes a non-Mega. A slot is empty only when the box has nothing left for it; an empty Mega slot says why ("No Mega-capable Pokémon
   in your box", or "... left" when they are all used) and counts as empty: there is no "Not counted" state. Tapping a slot
   lists the alternatives from the box (rule 28). Under Available the picker lists the slot's own role first, then every other unused Pokémon under "Other roles:",
   each with its role, in the order the squad is filled in; the Mega slot lists Mega candidates only. Available never lists a Pokémon the box lacks, and no "could get" list
   is shown under it (a pick of a Pokémon the box lacks is not placed here; it stays stored and returns under Best). A
   stored pick is placed under Available when the box holds the copy and it has a build for the area (a league rating on
   PvP). One copy per squad, the Shadow rules (rule 6), Max rows from Max kinds only and PvP's one species to a squad all
   hold as before.
4. **A Pokémon is in one slot at a time**: a copy in another slot of the same squad is not listed in that squad's
   picker, and neither is any row that shows the same copy (Primal Kyogre and Kyogre are two rows of one copy: a suggested
   squad never uses it twice, and a species pick that resolves to it counts as the copy); the slot being edited lists its own Pokémon, ticked. On Rocket only Pokémon the player chose leave the list
   (D28). One copy may sit in squads on different screens (manager's call, read-back Q6).
5. **Changing a slot's role** relabels the slot, refills it with the best unused Pokémon for the new role, and keeps a
   Pokémon the player chose (a copy, or under Best a species) unless it does not fit the new role (D16).
6. **Best** (replaces Could get now, 30 Oct 2026; S1, 31 Oct 2026, Greg: "if the user wanted to go out of their way to get
   the best pokemon for this activity what would that be and include the availability of that pokemon (aka not
   available, or attainable right now, or its in your box you just need to upgrade it)"): for a slot, the research tier tables' rows for the area, one per Pokémon,
   ranked by tier (S, A, B), then the table's order (the # in the PvP tables). Which rows: Raids, the Raids table entries
   listed under one of the boss's bring types (the strongest bring type first within a tier), with the role `raidRole`
   gives the entry; Max, the Max table's entries with the table's roles (rule 12; Gigantamax entries never), a type that
   hits the boss first within a tier; Gym, the Gym table; Rocket, per leader slot, the Rocket table's entries that hit at
   least one of the slot's options for more than normal damage; PvP, the league's table with the roles of rule 22. Every
   row of the table for the slot is listed (S, A and B). **Owned** means the box has a copy of that species (a Shadow row needs a
   Shadow copy, a plain row a plain one, as the table distinguishes them; area by area, a Shadow copy also serves the plain row in
   Raids (as the advisor credits it: a Shadow Garchomp keeps Garchomp's own Dragon row) and in Rocket, but not on the Gym or in
   Max (a Shadow cannot defend a gym or go Dynamax), and PvP reads the league's own rows). Whether a copy is a Shadow follows its hand
   mark before its species id: mark 1 is Shadow, mark 2 is Purified (not Shadow, even when the species id ends `_shadow`), mark 0 is
   neither; the `_shadow` suffix decides only when the copy has no mark or a copy
   that one of the advisor's builds for this area can make into it (raid builds as `raidEntries` reads them, Rocket and Raids
   builds for Rocket, league candidates for PvP). A row with a build or candidate shows the player's best of them (the build at
   Full strength first, then the least dust, then the least candy) with its mark; a row with only a copy shows the best copy
   (highest CP) as **In your box · needs upgrade · no build for this**; a row with neither is not in the box. **Each row has exactly one of three statuses** (Greg: "Three statuses"): **In your box** (with "needs upgrade" when its build needs work, or when no build serves the copy);
   **Can get now** (the box lacks it and a raid, Max or Rocket boss now has it per `data/hub.json`'s rotation and leaders, or, when the schedule never lists it, the research's obtain line counts as now only when ALL of these hold (manager call, 31 Oct 2026): its difficulty word, up to the first full stop, is Easy or Medium (no range to Hard, no slash); the row is not a Mega,
   Primal, Legendary, Mythical or Ultra Beast (those come through events, so the schedule decides); the line names no month or year; the line is shown after "Can get now". Rocket: only the catchable slot counts as a boss now, Giovanni's third and the first of every other leader); **Not available now** (with when it is next on, "Raids from 9 Nov", when the schedule knows; a Pokémon the schedule lists only later is not got now whatever the obtain line says). Otherwise a Pokémon the schedule does not list reads "Not available now · not on the schedule": no date is invented, and every status but a plain "In your box" carries its reason. No history of past dates is kept, so there is no "last available" text.
   A copy shows against one row at a time: when a row's only copy is the one a higher row shows, the row still lists it with
   "same copy as <that row>", and a pick of that row is a species pick. An availability line matches a boss only when its
   Shadow state agrees with the table entry's; Raid Hours and other kinds with no boss are never read; a one-day event on today
   reads "<title> today", and the last day of a run counts. The suggested squad fills each slot with the first row for its role whose copy is not already in the squad, owned or not; a not-owned Pokémon in a slot shows its status (Can get now or Not available now). A pick of a Pokémon the box lacks is
   stored as its species (rule 27) and reads as the player's copy once the box has one.
7. **Type icons**: every type chip is a round icon in the game's type colour, glyph white or ink by
   `Theme.pokemonTypeText`; the type name is its accessibility label.

### Raids

8. **Raid role of a candidate**: Mega when the build mega evolves (or targets a Mega or Primal); Heavy hitter when the
   copy is Shadow or the target's base Attack ≥ 1.3 × base Defence; Bulky hitter otherwise.
9. **Raid candidates and order**: Raids builds whose target counts for one of the boss's bring types
   (`HubRaidsModel.typesCounted`); ordered by the best tier the Raids table gives the target under a bring type, then
   built first, then how many bring types it covers, then the advisor's order; one entry per copy.
10. **Suggested squad**: slots Mega, Heavy, Heavy, Heavy, Bulky, Bulky, each taking the first unused candidate of its role.
   Under Available (S1) every build is a candidate whatever upgrade it needs, the Mega slot takes a Mega-capable copy (rule 3), and a
   slot with no unused candidate of its role takes the strongest unused one of another role (fill with any role); the Mega
   slot never takes a copy that cannot Mega Evolve. **Manager call, 31 Oct 2026** (on Greg's "the users best available pokemon for that position"
   and "fill with any role"): a role has run out when it has no unused candidate the tables list against this boss. A non-Mega slot under
   Available takes, in order: (1) an unused listed candidate of its own role; (2) an unused listed candidate of any other role, strongest
   first; (3) an unused unlisted (tier "") candidate of its own role; (4) an unused unlisted candidate of any role. So a Bulky slot with
   only an unlisted Bulky left takes a listed Heavy hitter. The Mega slot and Best are unchanged; Max and PvP candidates are always listed
   (Max needs a table entry, PvP a league score), so the rule changes nothing there.
11. **Now as cards**: Raids › Now shows one card per raid on now; the first is chosen on opening; tapping the chosen card
   closes its squad; Coming up stays a list whose rows open and close on tap.

### Max

12. **Max role of a candidate**: from the Max table: section Attackers = Attacker; role text containing "tank" = Tank,
   "healer" = Healer (Blissey both); Gigantamax entries never used. Order: Max tier, then a type that hits the boss,
   then the advisor's order. Suggested: the first Tank, the first Healer, the first Attacker that hits the boss (else the
   first Attacker); under Best that Attacker is the highest-ranked table entry that hits the boss, even over a higher tier
   that does not. Until the app has Dynamax marks every Max pick reads Upgrade available (manager's call, read-back Q7).

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
   role, else the best-scoring unused candidate (fill with any role, shown with its role). Under Available (S1) a candidate may be an
   evolution still to do (its shown option is not the copy itself); never two of one species. Each role's own slots fill across the whole squad before any slot takes another role's Pokémon, under Available and under Best alike (manager call, 31 Oct 2026). Coverage is shown, never used to pick; this replaces today's
   coverage-first `HubTeams.suggestedTeam` (D57).
24. **Number grades**: score ≥ 92 top, ≥ 90 good; IV rank ≤ 100 top, ≤ 500 good; anything else plain.

### Collection

25. **Species count**: game-master entries with `released`, plus eight species released in Pokémon GO that the flag leaves out (Ditto, Shedinja,
   Spewpa, Minior, Cosmog, Cosmoem, Bramblin, Brambleghast; `HubCollection.releasedInGoDespiteFlag`), 959 in all. The flag is PvPoke's and mixes species
   missing from GO with species in GO; the eight are the ones the flag marks unreleased that are NOT on Bulbapedia's "Unreleased Pokémon" list (66 species, page revision 4657810, read 31 Oct 2026);
   the other 66 flagged ones are on it and stay out. Cosmog and Cosmoem are also counted as Legendary (`HubCollection.legendaryDespiteNoTag`): the game master gives them no tag, and
   Bulbapedia's "Legendary Pokémon" page (revision 4642431, read 1 Nov 2026) lists them under "Cosmog and Cosmoem"; none of the other six is on that page or on the Mythical one
   (revision 4646884), so the Legendary set is 54 species, not 52. One per dex number, Mega, Shadow and duplicate entries not
   counted; owned when a box copy's species has that dex number. Regions by dex range (Kanto 1–151 … Paldea 906–1025).
26. **Special set strips** (replaces the Showcase, 31 Oct 2026): a set's strip is its copies, best first, the first ten. Rank: the set's activity, then
   IV % (a copy with no read IVs last), then CP, then entry id. An activity rank is the advisor's tag for the area (Strong, then OK, then Weak, then not in the tables),
   then the table tier (S, A, B); a copy is Weak for the area when it has no table entry for it, its IVs are below 80%, its IVs are unknown, or it is a Shadow copy whose only entries are Mega ones (`src/advise.js`
   `fit`); Weak ranks below every Strong or OK copy, and unranked (no rank shown) means the advice is not
   in yet. The activity per set (Greg: "Per set"): Dynamax and Gigantamax by Max; Shadow, Legendary, Mythical, Ultra Beasts and Mega-capable
   by Raids; Hundo, Lucky, Shiny and Background by the best rank in any activity (Raids, Gym, Rocket, Max, and PvP in Great or Ultra League by the card's worth: Top, Good, Weak).
   A PvP Weak card keeps its league tier (S, A or B) while a Raids, Gym, Rocket or Max Weak has none and ranks last, so in the any-activity sets "PvP Weak" can outrank "Raids Weak".
   A species set (Legendary, Mythical, Ultra Beasts, Mega-capable) shows each species once, its best copy, as its card counts species; a copy set shows copies.

### Keeping squads

27. **Where squads and picks are kept** (D58): per account, on the phone, surviving re-scans. A raid or Max squad is
   dropped when its event ends. A pick whose copy leaves the box empties the slot, and the slot refills with the
   suggestion. Available | Best is remembered per screen. A slot holds either a copy (its entry id) or, for a Best pick of a
   Pokémon the box lacks, a species key; a species pick is not touched when copies leave the box. Choosing a Pokémon takes it out of
   every other slot whose pick is the same copy or the same species, through every Best row that shows the copy (a copy chosen later
   wins over an earlier species pick of it, under Available too, where the stored pick is read through the Best rows). A species
   pick that reads as a copy ticks only the row the player picked. A Max row's rotation line reads the Max battles only.
   A copy picked under one mode that the other mode's list does not hold still shows in that mode's picker, ticked, with its
   own status. A pick that does not fit
   the mode is kept and comes back under its mode. A file saved before species picks existed reads as it did.

28. **Available upgrades** (phone feedback item 10; S1: "provides alternative options for each slot when clicked on"): tapping a slot
   under Available lists the alternatives from the box, the player's own Pokémon with those at Full
   strength first and, under the heading "Available upgrades:", those whose build still needs work (the mark and cost stay
   on each row), each group in the slot's order, then "Other roles:" (rule 3). When the box has nothing for the slot the text is the screen's own "No
   <screen> build in your box." alone; when it has options but they are all in the squad's other slots the text is "Everything
   in your box for this slot is already in your squad.".

### Squad status

29. **Slot status**: **ready** (green) when the slot holds a Pokémon the player has, at Full strength, rated S or A in the
   tier table for this area and slot; **needs work** (amber) when it holds one the player has that shows Upgrade available,
   is rated B or lower, is not in the table, or (Best) is a copy with no build for the slot; **to get** (red) when, under Best, it holds a Pokémon the box lacks;
   **empty** (red) when it holds nothing. The tier is the one for this area and slot: Raids and Max, the candidate's table tier (Raids: under the boss's bring types);
   Gym, the Gym table only (a Pokémon the table does not list needs work); Rocket, the Rocket table only (not a tier from another
   area); the picker's tier chip on both is that same table tier; PvP, the league tier shown everywhere (`LeaguePanel.tier(speciesId:key:score:)`: the table's, else the 88-score band),
   the same under Available and Best. There is no "Not counted" state (S1): an empty raid Mega slot counts as empty like any other. When a squad's options are hidden only by PvP's
   one-species rule, the empty picker says "Your other options are the same species as a Pokémon already in this squad."; The card's background is a soft tint of the status
   colour (`Theme.statusGreenTint`, `statusAmberTint`, `statusRedTint`); the disc and the role text keep
   the role colour; a word and icon (Ready, Needs work, To get, Empty) sit at the card's foot. A card's VoiceOver
   label ends with the status. Under Best a slot's card also carries the row's one status (rule 6). A card with work to do shows its cost beside the upgrade mark, as a picker row does (Greg: "would still show the needs work indicator"; the needs-work status and its cost are shown), at every text size.

30. **Squad status line** (identifier `squad-status`): "Ready" when every slot is ready; else, when no slot is empty or to
   get, "Nearly ready: N need work" (N = the slots needing work; "1 needs work"); else "Not ready: " with "N to get" (Best
   only) and "N empty", in that order, joined by a comma. The dot beside it is green, amber or red as the squad is ready,
   nearly ready or not ready. It sits under the squad's heading, above the slots, on all five screens.

## Word check

Each label against every other label on these screens and against the game's own terms. Items 1 and 4 were settled by
Greg's read-back answers (D54, D55); item 6 he kept (D56).

1. **"Available" (the switch) vs "TOP AVAILABLE" (Gym list heading)**: settled. The heading is now "Gym builds" (D54),
   so "available" means only "usable as it is".
2. **"Best" (the switch) vs "Next best" (Rocket) vs "Best defenders first" (Gym "i") vs "best copies" (Showcase, until 30 Oct 2026; since 31 Oct the Special sets strips, which put the set's best Pokémon for its activity first)**: four
   meanings of "best". (The switch's Best now means the best in the game for the slot, not the best the box can make.) "Next best" was chosen over "Best available" and "Top options" for this reason (D50, D53); the others remain.
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
