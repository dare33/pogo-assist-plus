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

## Phone run 2, 1 Nov 2026 (build fe6ce9e, test/greg-build)

Greg ran the 16-step walkthrough on his phone. Steps 1-3 (A-Z), 5-9 (squads), 10-15 (Collection) and 16 (Special
scan): "green". The screenshots page (taken at fe6ce9e): "screenshots look good".

- P1 (step 4, the Available picker). Greg: "green. but ... The pokemon picker that comes up doesn't really tell me
  enough information to make a choice straight from that screen. At a minimum it should display CP + the counters
  already there, and potentially IV. I do like the green tick next to the gnames which i believe indicates that this
  pokemon is a suitable choice? Also space out the information to use the bar more effectively (maybe a visual
  indicator of strength to faciliate quick choice by the user?)" Answered: the filled circle on the left marks the
  Pokémon in the slot now; the small green tick after a name is Full strength (built for this job, no work left); the
  orange arrow and cost mean it needs work. Asked, Greg chose: the strength bar shows "estimated damage on bar, Tier
  displayed next to it"; IVs as "Attack/Defence/HP"; "All five" squad screens. Decision: each picker row shows the
  copy's CP and IVs (Attack/Defence/HP), a strength bar of its estimated damage with the tier beside it, and uses the
  row's width; on all five squad screens. Asked further, Greg chose: the bar shows "Both" (a solid part for the copy as
  it is now and a faint part up to after its suggested upgrade); a full bar is the "Best in the game" against this
  boss; Gym and PvP bars show their "Bulk and Score"; the picker "Keep[s] the order" (the bar informs, it does not
  sort). Manager's calls (in the read-back): raid damage needs raid move stats, which `data/gamemaster.json` (PvP
  only) lacks, so a new generated file comes from the public PokeMiners game master by a script; Raids estimate damage
  per second against the boss; Max the damage of one Max move (its fast move's type) against the boss, for every Max
  role; Rocket damage per turn with the PvP move stats, averaged over the slot's options; "best in the game" is the
  strongest released species (Megas and Shadows on Raids and Rocket, Dynamax-capable on Max) at level 50 with
  15/15/15 and its best moves; a copy whose moves were not read uses the moves its build names; CP and IVs are the
  copy's now ("not read" when unknown); a Best row the box lacks shows one bar at level 50 with 15/15/15. Size: full
  (new data, a new calculation, new information on five screens).

## Phone run 3, 4 Nov 2026 (build b902a34, test/greg-build)

Greg ran the 8-step P1 walkthrough on his phone after Product > Clean Build Folder: the picker rows on Raids, the
Raids Mega slot, Max (fixed Max moves for Crowned Zacian, Crowned Zamazenta and Eternatus), Gym (Bulk), Rocket, PvP
(Score), Best mode on each screen, and how fast each picker opens. Greg: "fantastic all green". No new items. The
known limits listed in STATUS (the AX5 CP/IV wrap, "Charizard" broken at AX5 on the PvP OTHER CANDIDATES card, the 35
tier-table move lines that fall back to the species' best moves) were not raised and stay open.

## Rulings after phone run 3, 4-5 Nov 2026

- Review of P1's post-review commits. Greg: "Review them first". Done (paired review, fold, confirmation; STATUS 4 Nov).
- Not-owned Mega in the raid Mega slot judged on its own Mega line only. Greg: "Fix it, reviewed". Done: judged as an
  owned copy built to Mega is (STATUS 4 Nov, second entry).
- A Best row naming one of two Mega forms (Mega Raichu X, Mega Mewtwo X, Mega Charizard Y): the reviewers split (Opus:
  not a defect; Sol: contradicts "the better form against the boss"). Asked "keep the named form or show the better of X
  and Y?", Greg: "Keep the named form". Decision: such a row's bar is the form it names; an owned copy built to Mega
  still takes the better of X and Y against the boss. No code change.

## Phone run 4, 5 Nov 2026 (build 8de8855, test/greg-build)

Five checks of the changes since phone run 3, after Clean Build Folder. Greg's words:

1. Raids, Mega slot, not-owned Mega and Primal rows: "green". Questions: "is the damage taking into account
   counters/effectiveness already or separate to that?" and, of the Mega Sableye raid in Best (screenshot not received
   in the session): "is this right that when selected to best for mega sableye raid that theres only 2 best pokemon? No
   other suitable megas with comparable effective dmg?"
2. Raids, other slots, not-owned Mega rows judged as plain: "green".
3. Max: "couldnt check".
4. Gym, picker speed and the tick: "green but swapping out blissey makes my blissey go to the next raid slot. it seems
   like thers some sort of auto pick best pokemon calculation happening after every user switch. can we make it so that
   the best suggest is calculated once, and then the user changes from there"
5. Rocket and PvP: "green".

New request in the same message: "i'd like to include an indicator of overall team strenght for each activity - can
you suggest the indicator most suitable?"

Cause of item 4 (manager): rule 27 keeps only the player's own picks; every slot without a pick is filled again from
the ranked list each time the squad is drawn (`HubSquads.fill`), so a Pokémon replaced in one slot drops into the next
slot that has no pick. Working as rule 27 says; Greg's request changes the rule.

Greg's choices, 5 Nov 2026 (one-click answers to the manager's questions):
- A Pokémon put into a slot that is already in another slot: "Swap (Recommended)".
- A "Back to suggested squad" button on each squad: "Yes, add it (Recommended)".
- Where the fixed suggestion applies: "All five screens (Recommended)".
- Squad strength indicator: "Squad bar, avg (Recommended)": one bar per squad, the mean of the slot bars, with the
  now and after-upgrade parts, beside the Ready line.
Built on design/pass-2-4 (stacked on design/pass-2-3, so PR #25 can merge first), full paired review.

## Phone run 5, 6 Nov 2026 (build 747c10b, test/greg-build)

Greg's words, per check of the manager's walkthrough:

1. Gym, the Blissey swap: "green".
2. One change, nothing else moves: "green".
3. Back to suggested squad: "green but i kinda want to cahnge this funcitonality. instead of the button as it is can we exapnd the picker so its Current, Available, Best. Where available and Best always show the suggested squad. And then as you make changes to it those changes poulate what is shown on current."
4. Squad strength bar: "im cnofused by the bar - when i go to raids, and toggle on best. shouldnt the best squad be a fully maxed bar and then the other squads go down in relative value from there? Why isnt the hypothetical best squad maxed out?"
5. Raids swaps and the Mega slot: "green but change wording from 'no mega-capable pokemon left' to 'You can only have 1 mega slot'".
6. Max: "green". 7. Rocket: "green". 8. PvP: "green". 9. Available/Best switch: "green".

New note: "when scrolling down on the team/squad selector screens the squad currenlty chosen should remain visible as i scroll down currently it hides and i can only see th elist of pokmeon"

Manager's note on 4: 100% is the single strongest released Pokémon in the game against the boss (level 50, 15/15/15, best moves; rule 31), so a slot can reach 100% only by holding that one Pokémon. A raid squad holds one Mega, the other slots are judged as plain forms, and Bulky hitter slots are chosen for survival rather than damage, so even the Best squad sits well below 100%.

## Greg's choices after phone run 5, 6 Nov 2026

Built on `design/pass-2-5` (stacked on `design/pass-2-4`, so PR #26 can merge first), full paired review.

- **Current | Available | Best** replaces the Back to suggested squad button, on all five squad screens. Greg: "instead of the button as it is can we exapnd the picker so its Current, Available, Best. Where available and Best always show the suggested squad." Then: "when changes are made to best or available. the user has the option to 'save' it to current. So it doesnt auto swap/swtich."
  - Edits made on Available or Best last until the player leaves the screen ("Until you leave"); a Reset link undoes them.
  - Saving over an existing Current squad asks first ("Ask, then replace").
  - Current has a Delete current squad link that asks first ("Delete in Current, asks").
- **Squad strength is measured against the Best squad.** Greg: "Best = the BEST you can get in the game (if unavailable its marked as unavaialble to get right now, but still shows)"; "Available = the BEST that you can put together with the pokemon in your box (with the upgrade/potential showing as it is now) this should be ranked againts the BEST squad you can get in the game (regardless of availability)". "Best squad bar should show the strenght of the current best tab so default is full."
  - Comparison: total squad damage against the Best squad's ("Total squad damage").
  - Picker row bars stay against the best Pokémon in the game ("Keep vs best in game").
- **Raids style selector** (Raids only): Greg: "can we bring in a another toggle/selector. Max damage = prioritises and builds glass cannon with 1 mega. Balanced = the current strcuture we have." Max battles keep their Tank, Healer and Attacker ("Raids only").
- **Pinned squad strip** while the picker is open ("Compact strip").
- **Wording:** "No Mega-capable Pokémon left" becomes "You can only have 1 Mega slot".

Manager's calls in the plan Greg answered (not his rulings): a squad that beats Best reads 100%, "Matches the best squad"; "Set this squad" on Available or Best saves to Current; the screen opens on Current when the squad has one; the style choice is remembered.

## Phone run 6, 7 Nov 2026 (build de5d3f2, test/greg-build)

Greg's words, with his three screenshots kept outside the repo (manager's scratchpad, `phone-run-6/1.png`–`3.png`).

1. Opening a squad: "green. but see attach 1 in downloads - can we make the style/squad/notready/setthissquad be more space efficient? currently they are all on seaprate lines + set this squad i think should be up top"
2. Drafts: "green. However see attach 2- the save to current and set this squad button seem to be duplicates of the same function? Is this right, or is there a slight different between the two buttons. Either way. It feels unncessary tohave both - let me know waht you think. EDIT: I think i understand this better now. The se this squad is for the individual avaialbel/best pages and current butotn affects current direftly (however oplease note that both buttons override current squad currently). What I want this to actually be - changes made on best/available auto save. The button overrides the current squad only based on whats last saved/selected on the current best/available page."
3. Replacing a Current: "green". 4. Editing and deleting Current: "green".
5. Strength bar: "green. a couple of ntes though a) why are the options so limited, e.g. mega sableye raid, heavy hitter slot 6, only 5 heavy hitters, 2 bulky hitters and 1 mega listed for best. is this really all there is available for us?"
6. Raids style: "green".
7. Pinned strip: "attach 3 - the pinned strip is not useful as we cant see all fo the squad at once. Make it two levels 3 per level for raids."
8. Mega wording: "green. But can we hae the list also not show up the pokemon but instead the same message"
9. Other screens: "green". 10. Speed: "no all good". 11. VoiceOver and AX5: "skipping for now".

Manager's answer to 5a (for the design panel): Best for a raid lists only the hand-written Raids table (`data/source/01-general-pve-by-type.md`) under the boss's bring types. Mega Sableye's only weakness is Fairy, and that table's Fairy section has nine Pokémon (Mega Gardevoir; Xerneas; Crowned Sword Zacian and Mega Diancie; Shadow Gardevoir, Tapu Koko, Togekiss, Granbull, Primarina), so that is all Best can choose from. It is the table, not the game: other Fairy attackers exist, and against a boss with one weakness strong neutral attackers can out-damage weak super-effective ones. Two ways to widen it are for Greg: add rows to the table, or rank Best from the game master's own damage estimate (the one the picker bars already use).

How Greg wants the next work run (his words): "For the next lot of works i want to do it slightly differently. First output should be a design panel in session that I can give comments on directly to tweak some design elements that we've added new. Once I confirm changes on that we then build".

## Phone run 7, 8 Nov 2026 (build 253d91b, test/greg-build)

Greg's words, his screenshot kept outside the repo (manager's scratchpad, `phone-run-7/4.png`: the Raids screen with the strip pinned
while the slot cards are still in view).

1. Set, Undo, set again (one history entry): "green. one note - on current, the pokemon slector when clicking on a swap should appear
   ABOVE history segment, not below."
2. Edits kept: "1, 2, 3, 5 green. 4 - killing the app from swticher, my chnage was no longer there tested 2x, both times not there."
   Manager: the edit was kept; the boss reopened on Current (rule 27.1, a squad with a Current opens on it) and the Available edit was
   under the Available tab. Greg, after checking: "you are right. green now."
3. Delete current squad: "green". 4. A history row with a transferred Pokémon: "not testing this for now".
5. Raids, Max damage: "1 green. 2 i didnt see the "working out best squad...." it just loaded immeidately. 3.- green 4 - green".
   Manager: expected; the timeline and the squad screen pre-rank the boss in the background (H4, J5), so the rows are cached before Best
   is tapped.
6. Extra 1: "the pill up top with all the pokemon currently selected in squad, shouldnt start showing until the page has scrolled past the
   actual squads section being shown - does this make sense?"
7. Extra 2: "when i've toggled suggestsions for max damage, i think the poekmon selector (for the squads/activity) should rank pokemon by
   max damage, what do you think?"

Manager's proposals (picker above the history on Current; the strip once the cards have scrolled off; Max damage ordering the picker by
the row's strength figure; the chosen tab remembered across relaunches; the strip as three rows of two at accessibility sizes). Greg:
"agreed on the others". "↑ Upgrade" on a free Mega Evolution and the "Rayquaza" / "Mega Rayquaza" naming stay as they are (logged).
