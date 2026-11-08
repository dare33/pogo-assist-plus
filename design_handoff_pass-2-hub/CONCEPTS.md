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
- **Available | Best | Current** (pass 2-5, Greg, phone run 5: "instead of the button as it is can we exapnd the picker so its Current, Available, Best. Where available and
  Best always show the suggested squad"; pass 2-6, D59: "Maybe we should make Current show up (slightly accented) on the right hand side", no caption, one (i)): the tabs over each squad, with
  no caption. **Available** and **Best** (defined next) are the suggestions and never move; **Current** is the squad the player has set, a third segment on their right that shows only for a squad
  that has one, and the squad opens on it. The player's edits to Available and Best are kept as they are made (rule 27).
- **Current**: the squad the player has set: its picks, species picks, roles and the "listed for <role>" marker. Edits on it are saved at once. Drawn as kept (and so is an edit of Available or
  Best): no mode placement rule hides a kept pick.
- **Set this squad / Squad set** (pass 2-6, D60; one pill): on Available and Best, under the switches on the right of the squad's status. **Set this squad** (solid accent) makes the squad as drawn the
  Current with no question; **✓ Squad set** (accent tint, accent outline, the same size) shows when the squad as drawn is the Current, and tapping it unsets. A squad is set exactly when it has a Current.
  There is no pill on the Current tab.
- **Reset to suggestion**: the link under an edited Available or Best squad that drops the kept edits at once. **Delete current squad** moves the Current to the history, after asking.
- **Earlier current squads** (pass 2-6, D63): the list under Current of the squads that were the Current before, newest first, at most ten per squad, each with its date, one disc per slot, the strength figure it had and a
  **Set squad** pill that makes it the Current again with no question (rule 27.10).
- **Balanced | Max damage** (Raids only, rule 33): the style of the Raids suggestions. **Balanced** is a Mega, three Heavy hitters and two Bulky hitters; **Max damage** is a Mega
  and five Heavy hitters.
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
  not (**on Raids, from pass 2-6, Best ranks every species by the damage estimate against the boss, top 12 per role, the table's tier shown where it lists the Pokémon**: Greg, D65, "agree c2 for raids", "Agreed top 12", "yes fine. if the user wants damage focus they can toggle to damage"; on Raids, a slot whose role has run out takes the best unused row of another role, as Available does; the Mega slot never does), each with one of three statuses (rule 6).
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
- **Status chip** (pass 2-6, D68, rule 35): the small pill with a sign and one word that says a Pokémon's status on a slot card or a picker row: **✓ Ready**, **↑ 206k** (or **↑ Upgrade**, **↑ No build**),
  **◎ Get now** (with an **Easy / Medium / Hard** meter), **◌ Not now** (with the month) and **⇄ Slot 5**. VoiceOver reads the words, not the chips.
- **Slot status**: the colour of a slot card's background: **ready** (green), **needs work** (amber), **to get** (red:
  under Best, not in the box) or **empty** (red). A card also
  says it by its chips, so colour is never the only sign. The disc and the role text keep the role colour (rule 29).
- **Squad status line**: one line over the slots, "Ready", "Nearly ready: 2 need work" or "Not ready: 2 to get, 1 empty",
  with a dot in the same colour (rule 30).
- **Squad strength**: one bar under the status line for the whole squad: the squad's slot figures added up over the Best squad's, "Squad strength 78% of best", with "92% after upgrades"
  when the suggested upgrades add to it, and "Squad strength 100%" at or over it (rule 32).
- **Pinned squad strip**: the chips, one per slot, in rows of three, that stay at the top of the screen while a slot's picker is open (rule 34).
- **Tier chip** (S, A, B): the tier our research tables give a Pokémon for the area.
- **"i"**: the round info button; every explanation of a weight or a rule sits behind one (D17).

**Raids and Max**

- **Now / Coming up**: the raids or Max battles on today, and those still to come.
- **Readiness**: "b of n counters" (or "n of n ready"): how many of the boss's bring types the box has a built counter
  for.
- **Bring**: up to four attacking types that hit the boss for more than normal damage.
- **Your squad – Boss**: the squad planned for one raid or Max battle (D45, D49).
- **Set this squad / Squad set**: the player's own mark that the squad for that raid is ready; a set raid card is filled
  in the accent, a set row is tinted in it (D26, D42, D46, D55). The mark belongs to the Current squad: "Set this squad" on Available or Best saves the shown squad to Current first
  (asking when the squad has one) and sets the mark there (rule 27).
- **Raid roles**: **Mega** (one per lobby, boosts everyone's damage), **Heavy hitter** (most damage, faints sooner),
  **Bulky hitter** (stays in longer). Suggested mix 1 + 3 + 2 (D5); Max damage style 1 + 5 (rule 33).
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
   in your box", or, when the box has at least one Mega candidate (a Pokémon with a Mega view, whether or not it is already in the squad) but the slot is empty (the squad's one Mega sits in another Mega slot), "You can only have 1 Mega slot": Greg's words, phone run 5, in place of "No Mega-capable Pokémon left") and counts as empty: there is no "Not counted" state. Tapping a slot
   lists the alternatives from the box (rule 28). Under Available the picker lists the slot's own role first, then every other unused Pokémon under "Other roles:",
   each with its role, in the order the squad is filled in (**under the Max damage style, rule 33, each of those lists runs by its strength figure instead**); the Mega slot lists Mega candidates only. Available never lists a Pokémon the box lacks, and no "could get" list
   is shown under it (a pick of a Pokémon the box lacks is not placed here; it stays stored and returns under Best). A
   stored pick is placed under Available when the box holds the copy and it has a build for the area (a league rating on
   PvP). One copy per squad, the Shadow rules (rule 6), Max rows from Max kinds only and PvP's one species to a squad all
   hold as before.
4. **A Pokémon is in one slot at a time**: a copy in another slot of the same squad, and any row that shows the same copy (Primal Kyogre and Kyogre are two rows of one
   copy: a suggested squad never uses it twice, and a species pick that resolves to it counts as the copy), is listed in that squad's picker marked "In slot N" when choosing it can
   swap the two, and not listed when it cannot (rule 27, 5-6 Nov 2026; before then these rows were always hidden, and on Rocket only chosen ones). Under Best on Raids another Mega
   row is still not offered while a slot holds a Mega, but the Mega that slot holds is listed for a swap that can happen. The slot being edited lists its own Pokémon, ticked. One copy
   may sit in squads on different screens (manager's call, read-back Q6).
5. **Changing a slot's role** relabels the slot, refills it with the best unused Pokémon for the new role, and keeps a
   Pokémon the player chose (a copy, or under Best a species) unless it does not fit the new role (D16).
6. **Best** (replaces Could get now, 30 Oct 2026; S1, 31 Oct 2026, Greg: "if the user wanted to go out of their way to get
   the best pokemon for this activity what would that be and include the availability of that pokemon (aka not
   available, or attainable right now, or its in your box you just need to upgrade it)"): for a slot, the research tier tables' rows for the area, one per Pokémon,
   ranked by tier (S, A, B), then the table's order (the # in the PvP tables). Which rows: Raids (pass 2-6, D65: not the table; see rule 10: every species ranked by the damage estimate, top 12 per role, the table's tier on the rows it lists under one of the boss's bring types), with the role `raidRole`
   gives the Pokémon; Max, the Max table's entries with the table's roles (rule 12; Gigantamax entries never), a type that
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
   **Best for a raid ranks every species by the damage estimate against the boss (top 12 per role), the table's tier shown where it lists the Pokémon** (pass 2-6; Greg, D65:
   "why are the options so limited ... is this really all there is available for us?", "agree c2 for raids", "Agreed top 12", and, for those who want damage first, "if the user wants damage
   focus they can toggle to damage"). Every released species (and its Mega or Primal forms) is judged at full build against this boss (level 50, 15/15/15, its best moves: the figure a Pokémon the
   box lacks gets, rule 31); a Shadow-eligible species that is not a Mega is a second row as a Shadow **when that Shadow exists**: the Raids table lists it under some type section, or the box holds a Shadow copy of the species (no Shadow row otherwise); the role is `raidRole` (Mega or Primal: Mega; Shadow, or base Attack ≥ 1.3 × Defence: Heavy
   hitter; else Bulky hitter). Each role keeps its 12 highest figures (ties: the table's tier, S before A before B before none, then the game master's order), listed Mega, Heavy hitter, Bulky
   hitter, each in damage order, so the suggested squad fills as before (the Mega slot takes Mega rows only). The tier chip shows only where the Raids table lists that Pokémon (that Shadow or
   not) under one of the boss's bring types; otherwise there is no chip. Availability: in the box; a boss now or coming (the rotation line); else the table's obtain text where it lists the
   Pokémon; else "Not available now" with no reason. Max, Gym, Rocket and PvP Best are unchanged (Max: logged for later, D65).
   **One Mega** (pass 2-6, D67; Greg: "E1", "bold line only and reduce the size of the box to suit", both tabs, the Mega chip stays tappable; the panel's summary of E1 is "the bold line only, in a smaller box"): in a slot's picker on Raids, under Available and under Best, choosing the **Mega** role chip
   on a slot that is not the squad's Mega slot while another slot holds the squad's Mega shows only "You can only have 1 Mega slot" (`squad-picker-one-mega`, a box no taller than its line) in place of the rows and
   of the empty text. The slot's role is not changed by that tap (every other chip changes it at once, as before); another chip brings the rows back. The Mega slot's own picker, and the Mega chip when no slot holds a Mega,
   list the Mega candidates as before; All is unchanged. An empty Mega slot's card keeps its line "You can only have 1 Mega slot".
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

27. **Where squads and picks are kept: Current, Available and Best** (D58; fixed suggestion, 5 Nov 2026; rewritten for pass 2-5, 6 Nov 2026, after Greg's phone run 5): per account,
   on the phone, surviving re-scans. Greg: "instead of the button as it is can we exapnd the picker so its Current, Available, Best. Where available and Best always show the
   suggested squad. And then as you make changes to it those changes poulate what is shown on current", then "when changes are made to best or available. the user has the option
   to 'save' it to current. So it doesnt auto swap/swtich." What is stored is each squad's **Current** squad (a raid or Max squad is dropped when its event ends). Available | Best is
   remembered per screen (the tab a squad with no Current opens on). The suggestion is worked out once and the player edits from there (phone run 4: "can we make it so that the best
   suggest is calculated once, and then the user changes from there").
   1. **Tabs.** Each squad has **Available | Best** and, once the squad has a Current, **Current** as a third segment on their right (identifiers `squad-tab-current|available|best`, the switch `squad-mode`)
      on all five screens. No caption and no (i) of their own: the **title's (i)** (`squad-info`) explains the tabs (Current, Available, Best), then how the squad is suggested and, on Raids, the style, then one line per
      status chip sign (rule 35). A squad opens on the tab it was **last on** (D74: chosen by the player, kept per account and squad in the store, so it survives a relaunch; Greg's check 2.4 found the boss reopening on Current with his edit under Available); a squad never opened before opens on Current when it has one, otherwise on the remembered Available or Best. A stored Current is ignored while the squad has none, and Delete current squad clears the stored tab. A raid or Max squad's stored tab goes when its event ends. On Raids the style switch shares the tabs' row (tabs left, style right; if both do
      not fit on one line the style goes under the tabs, right-aligned, and at the largest text sizes both become stacked choices); on the other screens the tabs sit alone on the left. Every segmented switch in the app draws
      its chosen segment on the accent tint in the accent ink (D59). **Available and Best start from the suggestion** and are refilled whenever drawn until the player edits them (a box change, a Raids style change, a tab switch).
   2. **Edits are kept.** Available and Best are editable in place with every rule below (fixing what is shown before each change, swap, "moves it here", one Mega, Rocket rows describing the edited slot, the role line). Every
      change is **kept as it is made** (Greg, D61: "changes made on best/available auto save"), per account, per squad, per tab (on Raids per style too: Balanced and Max damage keep their own, rule 33), and survives leaving the screen
      and the app. An edit is drawn as kept, like Current: no mode placement rule hides a kept pick. A raid or Max squad's edits go when its event ends. Editing never switches tabs. A re-scan follows the box for an edit as it does for
      Current: a pick whose copy left the box is emptied, that slot alone refills (6) and the refill is kept. Edits belong to the account the screen is showing: another account's are not shown, and a write made under one account
      never reaches another's store. An edit that is drawn the same as the suggestion is not an edit. No tab is marked when it holds edits.
   3. **Reset to suggestion.** Once an edit **differs from the suggestion** (the squad as drawn: each slot's Pokémon or species, and its role, compared with the suggestion as drawn), the tab shows a **Reset to suggestion** link
      (`squad-reset-draft`, underlined, 44 pt tall) under the slots, which drops the kept edits at once, with no question. There is no Save to Current and no "Saved to Current": re-choosing the ticked Pokémon, flipping a role back,
      or "Set this squad" on an unedited tab leaves the tab unedited, and an unedited Best still reads "Squad strength 100%" (rule 32).
   4. **Current** is the stored squad: its picks (a copy as its entry id, a Best row the box lacks as a species key), roles, the "listed for <role>" marker, and how it came to be (the tab it was set from, whether that tab was edited, the strength figure at the time).
      **Edits on Current are saved straight away.** Every change keeps the squad exactly as shown, then applies the change (a Pokémon chosen for a slot, a role changed): each slot's shown Pokémon becomes its kept pick, an empty shown slot is kept empty. **Current is drawn as kept**: no mode placement rule hides a kept pick on it (the pass 2-4
      "a mode switch shows that mode's suggestion" limit is gone for Current), and a species pick the box lacks shows as the not-owned Best slot it is (rule 6). Its picker lists the
      player's own box as Available's does.
   5. **Swap** (Greg: "Swap"): choosing for a slot a Pokémon that already sits in another slot (the same copy or the same species, through every Best row that shows the copy)
      puts the slot's previous Pokémon in that other slot. If the slot was empty the Pokémon moves and the other slot refills with the next best unused ("moves it here"). A picker
      lists the Pokémon of the squad's other slots, marked "In slot N · choosing it swaps the two", **only when the swap can happen**: each Pokémon must fit the slot it would go to
      (Available: be placeable there, the Mega slot taking Mega candidates only; Best: be listed for that slot's role; PvP: be rated in the league; Current: any kept Pokémon). Otherwise
      the row is not listed. A raid squad holds one Mega: a swap only exchanges two Pokémon, so a Mega another slot holds stays listed for a swap that can happen, and no further Mega
      row is offered. Rocket lists every other slot's shown Pokémon, even when it does not beat the edited slot's lineup or no counter list holds it, and describes it against the
      edited slot (its types that hit, "beats n of 3"). PvP still hides another copy of a species the squad holds.
   6. A slot left with no kept Pokémon (its copy left the box, or a swap emptied it) takes the next best unused Pokémon for its role, that slot only, and **that Pokémon is then kept**
      (stored on Current, held in the draft otherwise, when the screen shows it), so it does not change again on a later scan. A kept species pick and an owned copy of that species are the same Pokémon (a role change reads the pick through its copy, so an owned species listed for the new role is kept):
      while the pick holds it, no other slot refills with that copy (Raids, Max, Gym, Rocket), so it is never shown, or counted in the strength, twice. An empty slot of a kept squad takes a Pokémon whenever
      one becomes available (a refill replaces nobody, so it is not a move of anyone's Pokémon).
   7. **Delete current squad** (`squad-delete-current`), a link on Current, asks first with the bold question only ("Delete current squad?" with Delete and Cancel and no message line, D64;
      `squad-delete-current-confirm|cancel`), then moves the Current to the history (27.10) and shows Available, or the remembered tab. Greg: "Delete in Current, asks".
   8. **The pill: Set this squad / Squad set** (D60, D61, D62), on **all five screens** (Gym, Rocket and PvP have no card to fill: there it means only "make this the Current"), on Available and Best, under the switches on
      the right of the squad's status (`SquadStatusLine` on the left); none on Current. Identifier `squad-set`; VoiceOver: "Set this squad, button, makes this your current squad" / "Squad set, button, selected; tap to unset".
      **Set this squad** (solid accent) shows when the tab's squad as drawn differs from the Current as drawn (each slot's Pokémon, species and role), or there is no Current. Tapping it makes the tab's squad as drawn
      the Current **with no question**: the Current segment appears, the player stays on the tab, and the pill turns to **✓ Squad set** (accent tint, 1.5 pt accent outline, accent ink, the same height and padding so nothing moves).
      When a different Current was replaced, a toast "Current squad replaced" with **Undo** shows for five seconds and is announced to VoiceOver; Undo puts that squad back as the Current and drops the one just set; the toast then
      says "Undone". **Tapping ✓ Squad set unsets** at once: the Current moves to the history, the Current segment goes (the screen shows the remembered tab if it was on Current), the pill reads Set this squad, and a toast
      "Squad unset" offers Undo. **Set and has-a-Current are one thing**: a raid card fills in the accent, and a Max row reads SQUAD SET, exactly when the squad has a Current.
   9. **Old files.** A squad saved by an earlier build becomes that squad's Current when it has `changed` set, holds any pick of the player's, or carries the "Squad set" mark (so the
      mark is not lost); a squad with nothing kept has no Current. The migration is durable: such a squad is marked `changed` and written back when loaded, so a later box change refills its slots instead of dropping Current. Files that predate the `changed` flag, species picks, or the Raids style still decode.
   10. **Earlier current squads** (pass 2-6; Greg, D63: "a historical log of previously selected 'current' squads for that activity"; "if they make an error they can just see an old build and make it the current build again").
      A history row is made when a Current is **replaced** (Set this squad, Set squad from the history), **unset** or **deleted**; never for an edit on Current, and not again for a squad equal to the newest row. Each row keeps the
      date, the slots as they were, the tab the squad was set from, whether it was edited and the strength figure it had when it was current (from the bar at that moment, "—" when it was not yet worked out; never recomputed).
      Under the Delete link the Current tab shows **EARLIER CURRENT SQUADS** and up to **ten** rows, newest first (`squad-history-row-N`, N from 1); none when there are no rows. **A picker opened on Current comes straight after the slot cards, above Delete current squad and the history** (D71; Greg: "on current, the pokemon slector when clicking on a swap should appear ABOVE history segment, not below."); on Available and Best the order is cards, Reset to suggestion, picker. On Gym, Rocket and PvP, whose cards sit in a panel with the picker outside it, Delete current squad and the history stay in the panel while no picker is open and follow the picker while one is. A row (44 pt tall): the date ("Today 10:16",
      "Yesterday 18:40", else "5 Nov 09:12"; the device's time style), one 18 pt disc per slot in the slot's role colours with the Pokémon's first letter (a Pokémon no longer in the box: a dashed hollow disc in muted ink with its letter; an
      empty slot: a grey disc), the strength figure, and a **Set squad** pill. Set squad makes that entry the Current with no question, shows "Current squad replaced" with Undo (which puts the previous Current back, as above),
      and the replaced squad goes to the top of the list. A row is one VoiceOver element ("Today 10:16, Gardevoir, Xerneas, Zacian not in your box, Granbull, Togekiss, Primarina, 41% of best") with Set squad as its action; the
      discs are not tappable. A raid or Max squad's history goes with its event. The store remembers the name of each copy a squad holds while it is in the box, so a row can still name one that left.
   "Back to suggested squad" (pass 2-4) is gone: its button, question and identifiers are replaced by Reset to suggestion, Delete current squad and the tabs.
   A slot holds either a copy (its entry id) or, for a Best pick of a Pokémon the box lacks, a species key; a species pick is not touched when copies leave the box. A species pick
   that reads as a copy ticks only the row the player picked. A Max row's rotation line reads the Max battles only. A copy picked under one mode that the other mode's list does not
   hold still shows in that mode's picker, ticked, with its own status.

   **Pass 2-6, engine (slice 1; the screens' behaviour is 27.1 to 27.10 above).** The engine now **stores the edits of Available and Best** (`SquadStore.edits`), per account, per
   squad and per tab, and on Raids per style, so they survive leaving the screen and the app (Greg, D59 to D70: kept edits instead of drafts); `resetEdit` drops one and the screen draws
   the suggestion again. A raid or Max squad's edits go with its event, and a re-scan follows the box for an edit as it does for Current (a pick whose copy left is emptied). It also
   stores the **history** (`SquadStore.history`): per squad, the earlier Current squads, newest first, at most ten, each with its date, slots, the tab it was set from, whether it was
   edited and the strength figure the screen passed in when it was recorded. A row is made when a Current is replaced, restored, unset or deleted, never for an edit on Current, and not
   again for a squad equal to the newest row. History slots are kept as they were (the screen draws a Pokémon that left the box as gone); a restored Current is reconciled as any
   Current. **"Set" is "has a Current"**: the stored `isSet` mark stays in the file for old builds, and an older squad with the mark alone becomes a Current. The file is version 2; a
   version-1 file reads with no edits and no history.

28. **Available upgrades** (phone feedback item 10; S1: "provides alternative options for each slot when clicked on"): tapping a slot
   under Available lists the alternatives from the box, the player's own Pokémon with those at Full
   strength first and, under the heading "Available upgrades:", those whose build still needs work (the mark and cost stay
   on each row), each group in the slot's order, then "Other roles:" (rule 3). When the box has nothing for the slot the text is the screen's own "No
   <screen> build in your box." alone; when it has options but they are all in the squad's other slots the text is "Everything
   in your box for this slot is already in your squad.".

31. **Picker row: CP and IVs, and the strength bar** (phone run 2 of 1 Nov 2026, P1; Greg: "it should display CP + the counters already there, and
    potentially IV ... a visual indicator of strength to facilitate quick choice"). Every picker row on all five squad screens, Available and Best,
    shows the copy's **CP and IVs as it is now**, Attack/Defence/HP ("CP 3,412 · 15/14/15"; "CP not read", "IVs not read"; PvP's row shows them too and keeps its
    graded IV rank line), on one wrapping line with the role word and the type icons, and a **strength bar** across the text column with the tier chip at its end.
    The bar informs; it never sorts or filters (Greg: "Keep the order"). **Solid part** = the copy as it is now; **faint part** (dashed outline, at least 6 pt)
    = after its suggested upgrade. Full strength rows have no faint part. A copy whose level or IVs are not read has no solid part (IVs unread: no bar).
    - **Estimated damage** (Raids: damage per second against the boss; Max: damage of one Max move, every Max role; Rocket: damage per turn with the PvP move
      stats, averaged over the slot's possible Pokémon; several bosses: the mean). Level, IVs and Shadow state are the copy's own. **Moves follow the boss**: a
      copy is judged on its own read moves, else on the best of the table's move lines for its Pokémon against this boss (never the best-tier line); after =
      the best of the build's target's lines (and the copy's own moves) against this boss, never below now. A line naming no known move is skipped.
    - **Mega and Primal forms** count only in the raid Mega slot (the better form against the boss, judged on the best of its own lines, the plain Pokémon's lines and the
      copy's own moves; a Mega Evolve is the faint part). A Mega entry shown under another role's slot (Best, the All chip) is judged as the plain Pokémon. Every other slot, and
      all of Rocket, Gym and Max, judge the plain form: a Rocket row has no Mega form. A Mega or Primal is never a Shadow.
    - **Max**: a Gigantamax copy's Max Attack is its G-Max move (its type from the sourced list, base power 350 at level 1); any other copy's takes the type of
      its fast move (250), except that Crowned Zacian and Zamazenta always use Steel (250), Eternatus Dragon (350) and a Hidden Power fast move gives Normal. The species that can Dynamax or Gigantamax are the two sourced lists in `MaxBattleSpecies` (Pokémon GO Wiki, read 1 Nov 2026).
    - **Best in the game** (a full bar): the strongest released species against this boss at level 50 with 15/15/15 and its best moves; Megas and Shadows on
      Raids, Shadows on Rocket, the sourced Max species and G-Max forms on Max. Greg chose "Best in the game".
    - **Gym** bar = Bulk (now vs after its build) against the best Gym bulk in the game; **PvP** bar = the league Score, one bar (a species the player has no copy
      of takes PvPoke's score for it in this league; with none, no bar and "score not known"). Greg chose "Bulk and Score".
    - A Best row the box lacks: one bar for the species at level 50 with 15/15/15 and no CP line; its moves are the best of every line the tables give the species. Max
      Best lists no Gigantamax entry (rule 12), so no Best row uses a G-Max move today; the estimate takes a Gigantamax flag for a row that would. VoiceOver reads the row as
      one element ("CP 3412, IVs 15, 14, 15, estimated damage 62 percent of the best, 85 percent after upgrade"); the bar is hidden from it.

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
   the role colour; from pass 2-6 the card says its status by its chips (rule 35), no longer by a word and icon at its foot or an arrow badge in its corner (the card keeps its colour). A card's VoiceOver
   label ends with the status. Under Best a slot's card also carries the row's one status (rule 6), as chips. A card with work to do shows its cost in its upgrade chip ("↑ 206k"), at every text size.

30. **Squad status line** (identifier `squad-status`): "Ready" when every slot is ready; else, when no slot is empty or to
   get, "Nearly ready: N need work" (N = the slots needing work; "1 needs work"); else "Not ready: " with "N to get" (Best
   only) and "N empty", in that order, joined by a comma. The dot beside it is green, amber or red as the squad is ready,
   nearly ready or not ready. It sits under the squad's heading, above the slots, on all five screens.

32. **Squad strength** (phone run 4, 5 Nov 2026, rewritten for pass 2-5, 6 Nov 2026; Greg: "Squad bar, avg", then, phone run 5, "shouldnt the best squad be a fully maxed bar and then the other squads go down in relative value from there?"; identifier `squad-strength`): one bar for the squad under the status line (rule 30), on all five squad
    screens, drawn as a picker row's bar is (rule 31), **measured against the squad's Best squad** (Greg: "Total squad damage"). Picker row bars do not change: they stay against the best Pokémon in the game ("Keep vs best in game").
    - **Reference** = the squad's Best suggestion, unedited (on Raids in the chosen style, rule 33), each slot taken at its **full build**: that slot's Pokémon at level 50 with 15/15/15 and
      its best moves, exactly the figure a not-owned Best row gets (rule 31's last bullet), whether or not the box holds a copy. Gym: the Bulk of that Pokémon at full build. PvP: its league Score.
      Rocket: damage against the slot's lineup as rule 31. Max: the Max squad's Best of three.
    - **Value** for a squad on any tab = the sum of its slots' figures (each exactly the figure that slot's Pokémon shows as a row in that slot's picker: now, and after the suggested
      upgrade) over the sum of the reference's slot figures, as a whole percent **rounded down**, **capped at 100%** (100% reads only when the squad matches or beats the reference). A squad at or over the reference reads **"Squad strength 100%"** (pass 2-6; Greg, READBACK 1.7: no "Matches the best squad"). PvP: the mean Score
      over the reference's mean Score, with no "after" part.
    - An **empty slot counts 0** against its reference slot. A slot whose Pokémon has no figure (IVs or level not read, "score not known") is **left out together with the reference's slot at
      the same index**, and the line says "N of M slots scored". A reference slot with no figure leaves that index out of both sides. With no reference figure at all, or no scored slot, the
      line says "Squad strength not read" and draws no bar.
    - Words: "Squad strength 78% of best" and, when the figure after upgrades rounds to a higher whole percent, "92% after upgrades" (only when the bar draws its faint part); at or over the
      reference "Squad strength 100%". **The unedited Best tab reads 100%** ("Squad strength 100%"; no "the best squad", no "Matches the best squad", no dot: the screen draws the line and "87% after upgrades" in one tone, with the figures bold), through the same safeguards (a reference slot with no figure is left out and the line says "N of M slots scored"; with no reference figure there is no bar); an edited Best draft shows its own value against
      the unedited Best. VoiceOver reads the same words. Current's bar compares with the Best of the style now chosen.
    - It follows the squad as drawn, so a swap, a role change, a tab switch and a style change move it. It is worked out off the main thread, keyed by the box generation, the advice, today, the squad, the tab and the style: the row keeps its place with an empty track until the figure is ready. From pass 2-6 it is **one label** ("Squad strength 41% of best · 87% after upgrades", one tone, the two figures bold), which wraps at the accessibility text sizes.

33. **Raids style: Balanced | Max damage** (pass 2-5; Greg, phone run 5: "can we bring in a another toggle/selector. Max damage = prioritises and builds glass cannon with 1 mega. Balanced = the current strcuture we have."; Max battles keep their Tank, Healer and Attacker: "Raids only"). A second control on Raids (identifiers `squad-style-balanced|max-damage`), default Balanced, remembered per account like the tab choice.
    **Balanced** is 1 Mega + 3 Heavy hitter + 2 Bulky hitter (rule 10); **Max damage** is 1 Mega + 5 Heavy hitter. The style sets the default roles of the Available and Best suggestions, and so the
    strength reference (rule 32). When Heavy hitters run out, the fill rule of rule 10 applies (other roles' listed counters, "listed for <role>", and so on). Changing the style keeps each
    style's own Available and Best edits (pass 2-6, D61: "edits kept per style"; switching back shows them again) and leaves Current untouched (one per squad, whatever the style). On Raids the style switch sits on the tabs' row (rule 27.1), with no caption. Max battles, Gym, Rocket and PvP have no style. The squad's (i) explains the two styles:
    "Balanced: a Mega, three heavy hitters and two bulky hitters that stay in longer." "Max damage: a Mega and five heavy hitters; faster, with more relobbies."
    **Under Max damage the Available picker is ordered by damage** (D73; Greg: "when i've toggled suggestsions for max damage, i think the poekmon selector (for the squads/activity) should rank pokemon by max damage, what do you think?"; "agreed"). Each picker group (the slot's own role, then "Other roles:", and the Mega slot's list, which Balanced orders by Mega) lists its rows by the strength figure the row's bar shows against the boss, **after the upgrade the build names** (the figure now when there is no upgrade), strongest first; ties by the figure now, then the order Balanced would give. A row with no figure goes last. Rule 28's split stays: Full strength rows, then "Available upgrades:", each part ordered this way. The Pokémon already in the slot is ticked in its sorted place (one the list does not hold stays at the head). Balanced, Best and Max battles keep their orders. The picker's (i) says so under Max damage.

34. **Pinned squad strip** (pass 2-5; Greg, phone run 5: "when scrolling down on the team/squad selector screens the squad currenlty chosen should remain visible as i scroll down currently it hides and i can only see th elist of pokmeon"; his choice: "Compact strip"; pass 2-6, D66, two rows of three). While a slot's picker is open, a compact strip stays pinned at the top of the screen's scroll area (`squad-strip`) as the player scrolls the
    Pokémon list: one chip per slot (identifier `squad-strip-chip-N`) showing the slot number, the Pokémon's name or "Empty" and the role colour, the slot being edited highlighted by an accent ring; tapping a chip opens that slot's picker. It is hidden when no picker is open, **and while the slot cards are in view** (D72; Greg: "the pill up top with all the pokemon currently selected in squad, shouldnt start showing until the page has scrolled past the actual squads section being shown"): with a picker open it is pinned only once the slot cards are entirely above the top of the scroll area, and goes again when they come back into view (it comes back after the cards have returned 12 pt into view, so it does not flicker at the edge).
    **Two rows of three** on the six-slot squads (Raids, Gym) and one row of three on the three-slot squads (Max, Rocket, PvP), each chip a third of the width, all in view with no sideways scrolling. A chip shows the name **without a trailing "(Shadow)"**
    ("Gardevoir (Shadow)" is "Gardevoir"; every other form stays: "Zamazenta (Crowned Shield)", "Giratina (Origin)", "Mega Charizard X"), on a second line if it needs one, cut with … if it still does not fit; VoiceOver reads the full name. A chip for a Pokémon **not in the box** (a Best pick) has a hollow number and a dashed edge in the role colour, and VoiceOver adds "not in your box"; "Empty" stays grey with the word.
    At accessibility text sizes the rows stay, a chip's name wraps to two lines and the strip grows; the list is inset below it, never pushed off screen. Each chip is one VoiceOver button ("Slot 2, Moltres, Heavy hitter, editing"). On all five squad screens.

35. **Status chips** (pass 2-6; Greg, D68: "f1"; legend "not required going f1"; the panel's summary of that option is "F1 symbol chips with one word, no legend"; the (i) explains the signs). Each status a Pokémon has on a squad screen is said once, as a small capsule (10.5 pt bold) with a sign and one word,
    in a wrapping row under the name on a picker row and after the name on a slot card; colour is never the only sign:
    - **✓ Ready** (green): at Full strength, nothing left to do.
    - **↑ 206k** (orange): a power up, an evolution or a Mega Evolution still to do, with the build's cost as the arrow badge shows it (`HubModel.costShort`, with the dust or candy icon); **↑ Upgrade** when the work has no cost to name;
      **↑ No build** for "In your box · needs upgrade · no build for this".
    - **◎ Get now** (Great League blue), with a second chip, the meter **▮▯▯ Easy / ▮▮▯ Medium / ▮▮▮ Hard**, when the research's obtain text names a difficulty (not for a boss on the schedule).
    - **◌ Not now** (grey), with the month when the schedule gives a date ("◌ Not now · Dec"; the day and month when it is within a month: "◌ Not now · 9 Nov").
    - **⇄ Slot 5** (grey) for a Pokémon in another slot (choosing it swaps the two); **⇄ Empty slot** when the edited slot is empty and choosing it moves the Pokémon here.
    The chips replace the status sentences (the Best note, the amber "no build" note, the swap line), the role word on picker rows (now drawn only while the chosen role chip is All), and on a slot card the status lines, the word and icon at its foot and the corner arrow badge;
    the card's colour (rule 29) stays. Lines that are not a status stay: "Its role: …", "beats 2 of 3", "vs Zekrom", "level not read", "Same copy as …" (muted), the empty Mega slot's "You can only have 1 Mega slot", Gym's figures, PvP's score and IV line, the tier chip and the bars.
    The chips are hidden from VoiceOver: the row's or card's label keeps today's words ("In your box, needs upgrade, 206k dust", "Can get now, Easy", "In slot 5, choosing it swaps the two"). The title's (i) has one line per sign.

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
13. **"Gardevoir (Shadow)" vs the tables' "Shadow Gardevoir"** (pass 2-6, D69): every Shadow row or slot on a squad screen (slots, picker rows, strip chips, Best rows of Raids, Max, Gym, Rocket and PvP) is named as the box names a Shadow, the Pokémon's name and "(Shadow)"; the tables'
   own "Shadow Gardevoir" is not shown there (`SquadWords.boxName` rewrites a leading "Shadow " at draw time). A Mega or Primal is written in front, as the game writes it, and the game master does not: it says "Gardevoir (Mega)", "Charizard (Mega X)", "Groudon (Primal)", and `SquadNames.display` turns them into "Mega Gardevoir", "Mega Charizard X", "Primal Groudon" on every squad screen (Raids Best rows, slot cards, picker rows, strip chips, history discs and the names the store remembers). Same meaning. No clash.
