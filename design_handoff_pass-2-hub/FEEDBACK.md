# Feedback: design pass 2 (Pogo Hub)

Each eyeball item with Greg's words, the decision and its review size (`docs/design-process.md` sections 7 and 8).

## Phone run 1, 30 Oct 2026 (build 413a8a3)

6. Greg: "showcase in collection - your best copies should read your highest IV copies." Decision: the heading reads
   SHOWCASE · YOUR HIGHEST IV COPIES (the strip already holds each species' highest IV copy). Size: cosmetic.
7. Greg: "duplicates in collection - 'copies you can transfer or trade.'" Decision: the Duplicates card's line reads
   "N copies you can transfer or trade." Size: cosmetic.
8. Greg: "raid screen, gym battles, team rocket, pvp max - setting a team is confusing right now. available toggle
   should show available pokemon the user has. and best should show a list of pokemon they should aim for including
   unavailable + available ranked preferably. Right now its the opposite for the first issue and for the 2nd issue
   theres not enough suggestions." Asked, Greg ruled: "Available = the users best available pokemon for that
   position." "Best = the best pokemon obtainable in the game even if not current obtainable (with ideally an indicator
   of when they might be available next if thats known, and if not known then when it was last available)".
   Decision: Available uses only the box; Best ranks the research tables' Pokémon for the slot, owned or not, with when
   each is next on (the rotation) or the research's obtain line. The app holds no history of past availability dates.
   Size: full.
9. Greg: "raid screen - additionally on the your squad tiles - lets keep the circles as the color of the indicators
   matching the name. but make the background of the tile a colored system for flagging if they've got a good team or
   not. tile backgrounds should indicate individual + an overall team indicator that makes it clear to the user
   whether they need to prepare more for this raid or if they are fine as they are." Asked, Greg chose the rule
   "Strength and tier" on all five squad screens: green, a top-tier (S or A) pick at full strength; amber, it needs an
   upgrade or is a lower-tier pick; red, the slot is empty (or, under Best, the Pokémon is not in the box); a team line
   Ready / Nearly ready / Not ready. Size: full.
10. Greg: "another universal update on the AVAILABLE (as it currently stands before my requested fix) remove 'no gym
    build in your box. You could get these now' with 'Available upgrades:'". Decision (manager's reading, for Greg to
    confirm on the phone): under Available the picker lists the player's own Pokémon, full strength first, then those
    still needing work under "Available upgrades:"; the could-get list no longer shows under Available. Size: full
    (goes with item 8).
11. Greg (30 Oct, later): "collections tab - the cards in special sets clicking them should open up a popup with a list of
    that pokemon (keep formatting matching)". Decision: each Special sets card opens a sheet listing the player's
    Pokémon in that set, drawn with the same species rows as My Pokémon. Size: full (a new tap target and screen).
12. Greg (30 Oct, later): "should be able to search for the special types (shadow/max/etc) in the pokemon main box".
    Decision: My Pokémon's search understands the game's own words for the special types (shadow, purified, lucky,
    dynamax, gigantamax, legendary, mythical, ultra beasts, mega, 100%), alone or combined. Size: full (search matching).

## Eyeball check, 31 Oct 2026 (build db4a01b, phone and screenshots page)

Greg checked the changes built from phone run 1, screen by screen.

- Items 5, 6, 7 and 11: Greg: "ok".
- C1. Greg: "we need to add a special scan also to the special scan tab". Today the Scan screen's Special scan offers
  four passes: Shadow, Purified, Dynamax, Gigantamax. Asked which, Greg: "lucky + shiny + Background (placeholder
  'coming soon' tag until scans are developed for it)". Decision: Special scan lists Lucky, Shiny and Background, each
  tagged "Coming soon" and not choosable until its scan is built. Size: full (new options).
- C2. Greg: "special sets we need to include - Dynamax, gigantamax, shiny, background cards to this lsit (we'll need to
  create scans for the ones we dont have (show the options in special scans but marked as 'coming soon'). Change the
  name of 100% IVs to 'Hundo'." Decision: Special sets gains Dynamax, Gigantamax, Shiny and Background. Dynamax and
  Gigantamax read the marks the box already has (from the hand marks and the Dynamax and Gigantamax passes). The box
  holds no shiny or background data today, so Shiny and Background show in Special scan as passes marked "Coming soon"
  (not choosable) and their set cards say so; reading them is a later piece of work. "100% IVs" is renamed "Hundo"
  everywhere it shows (same meaning; CONCEPTS.md updated). Size: full (new sets and Special scan options); the rename
  alone is cosmetic.
- C3. Greg: "turn the Missing segment, into a bit of a summary card and when clicked it opens up to the list you have."
  Decision: the Missing section becomes one summary card (how many species are missing, with a short breakdown);
  tapping it opens the full Missing list that "All N ›" opens today. Size: full (tap target and what shows).
- C4. Greg: "actually turn special sets into similar formats as the showcases - i.e. each speacial set is alid out like
  the showcase for highest IV copies. And we'd just remov ethe currently highest IV copy showcase as we wont need it
  with the 'hundo' one". Asked what a strip shows, Greg: "Best pokemon for that activity first + All". Asked how Shiny
  and Background show before they can be scanned, Greg chose "Card says Coming soon". Decision: each special set becomes
  a strip of copy cards laid out like the showcase, the set's best Pokémon for its activity first, with "All N ›"
  opening the set's full list (today's sheet); the SHOWCASE · YOUR HIGHEST IV COPIES section is removed. Asked which
  ranking, Greg chose "Per set": Dynamax and Gigantamax by Max battle rank; Shadow, Legendary, Mythical, Ultra Beasts
  and Mega-capable by raid rank; Hundo, Lucky, Shiny and Background by their best rank in any activity. Size: full (layout of which items appear, sections removed).
- Item 9: Greg: "yes good".
- S1 (items 8 and 10). Greg: "Available vs best - still not thinking we're on the same page with thi sone. I wanted
  Available to be the one where the app picks fo rthe user (and provides alterantive optiosn for each slot when clicked
  on) what it thinks would be the optimal tema based on the users box right now (would sitll show the needs work
  indicator). Currently available does not do this. I wanted Best to be - if the user wanted to go out of their way to
  get the best pokemon for this activity what would that be and include the availablity of that poekmon (aka not
  avaialble, or attainiable right now, or its in your box you just need to upgrade it)". Item 10: "see above".
  Greg's phone screenshot (31 Oct, not committed): Raids, Giratina (Origin), Available: one slot filled (Yveltal, needs
  work), four empty, the Mega slot "Not counted", while "Builds that close the gaps" lists 38. Asked, Greg: "even if
  not ideal, surely there are enough pokemon in my box to fill those 5 slots"; Available should include Pokémon that
  need evolving or Mega Evolving ("Yes, include them"); Best rows carry one of three statuses ("Three statuses").
  Cause (today's rules 3 and 10): Available places only a copy of the slot's own role whose build is power-up only
  (no evolution, form change or Mega), and leaves the raid Mega slot empty.
  Decision: **Available** is the app's suggested squad from the box as it is now, on all five squad screens: every slot
  filled with the strongest Pokémon the player owns for it, whatever upgrade it needs (power up, evolve, form change,
  Mega Evolve), the needs-work status and cost shown; the raid Mega slot takes a copy that can Mega Evolve; a slot is
  empty only when the box has nothing left for it. Tapping a slot lists the alternatives from the box (Full strength
  first, then "Available upgrades:"). Asked, Greg chose "Fill with any role": when no unused Pokémon of the slot's role is
  left, the slot takes the strongest unused one of another role and shows that role.
  **Best** is the strongest Pokémon in the game for each slot if the player went out of their way, owned or not, each
  row with one status: "In your box" (with "needs upgrade" when its build needs work), "Can get now" (a raid, Max or
  Rocket boss now, or obtainable now per the research), or "Not available now" (with when it is next on, if known).
  CONCEPTS rules 3, 6, 10, 23, 28 and 29 change with Greg's words. Size: full.
- Item 12 and the three search quirks the last session flagged (a comma means AND here and OR in the game; "pikachu,"
  with a trailing comma finds nothing; "nidoran♀" finds nothing because the data says "Nidoran Female"): Greg: "All
  good". Decision: no change.

Points the last build session flagged, put to Greg in this check:

- F1. An alert raised from a copy's page opened inside a Special sets sheet (such as "No level fits") closes the sheet;
  the edit is saved but the player lands back on Collection. Greg chose "Keep sheet open". Decision: the alert shows
  over the sheet, and once it is dismissed the player is still in the set where they were. Size: full (what shows and
  when).
- F2. Duplicates counts copies that cannot be traded (Mythicals and the like). Greg chose "Leave as is": they can still
  be transferred, so "copies you can transfer or trade" stays true. No change.
- F3. Open question (a), one copy's several builds (say a raid build and a PvP build) all count in its species'
  upgrade cost today. Greg chose "Count one per copy". Decision: each copy adds the cost of one build, its top one, to
  the species' total. Size: full (computed value).
- F4. Open question (b), "of 951 species" leaves out Ditto, Shedinja and a few others because of the game-master
  source. Greg chose "Yes, fix it". Decision: fix the source so the total and the Missing list include every released
  species. Size: full (data); its own branch from `main` if it is not part of the design.
- F5. Item 10 and how Best shows Pokémon the player does not own (both flagged for the phone): replaced by S1 above.
  "Last available" (no history data, so Best falls back to the research's obtain line): Greg's three Best statuses in
  S1 carry when a Pokémon is next on, if known; no history of past dates is added.

Read back to Greg at the end of the check (the build list in the pass-2 and pass-3 FEEDBACK entries above, all full review except the Hundo rename alone): Greg: "Agreed, build it".
