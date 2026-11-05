# Design pass 2 (Pogo Hub): decisions log

Kept during the design session, 25 Oct 2026 onwards, in the Design canvas "Pogo Hub — design pass 2" (private claude.ai
artifact). For every change Greg asks for: his words, then what changed in the design.

Starting point: the Hub as built on `feat/pogo-hub` at 7dcf72f (draft PR #15), redrawn on the canvas board by board
(Hub tab, Everything, Raids now and coming up, Gym battles, Team Rocket, PvP leagues, Max battles), light and dark, from
the app's own tokens (`Theme.swift`, `Typography.swift`, `Components.swift`). The figures on the boards are Greg's own
box (export of 22 Oct, 2,125 Pokémon) worked out by the app's own PogoBox code at that commit, for 25 Oct 2026.

Known limits of the starting boards (not decisions):

- The export carries no Dynamax marks, so the Max roster is empty and every Max row reads 0 counters.
- Split "Gigantamax A / B" rows in `data/source/08-max-battles.md` lose the Gigantamax prefix in `data/tiers.json`
  (a known bug, fixed outside this pass); Max figures for Toxtricity, Lapras, Grimmsnarl and others may be wrong.
- The header showed "Account" in place of the trainer name (until D37).
- Everything's full list is drawn to its first 12 builds.

## Decisions

### Round 1: Greg's 14 canvas comments, 25 Oct 2026, and four one-click answers

**D1. Events header.** Greg: "Happening now in Pokemon GO".
Changed: the Hub tab's header reads HAPPENING NOW IN POKÉMON GO (kept in the caps of the other section headers; say if you
meant sentence case).

**D2. Everything becomes Collection.** Greg: "lets replace everything actually - and instead of everything. one aspect of
pogo is collection. Suggest for me a module that will allow my users to admire their pokemon collections. Perhaps the
ability for them to showcase their pokemon? or see how their collection efforts are going to identify missing pokemon
they still need." Asked where Everything's lists go, Greg chose "Inside Collection"; asked what Collection shows, he
chose all four: Dex progress, Missing Pokémon, Showcase, Special sets.
Changed: the first Hub tile is Collection ("Dex, showcase and builds", chip "347/951", the species you have of those
released). An event card that opened Everything opens Collection. New Collection screen: a species count with a bar
("347 of 951 species", "36% of the species in Pokémon GO. N more you can evolve now."); DEX BY REGION (Kanto to Paldea,
have of total, a bar each); SHOWCASE · YOUR BEST COPIES (a strip of the best copy of each species by IV %, 100% in green);
SPECIAL SETS (100% IVs, Legendary, Mythical, Ultra Beasts, Mega-capable, Lucky, Shadow); MISSING (count, how many you can
evolve from one you have, the first six with dex number, region and how to get it); BUILDS AND CLEAN-UP (see D3).

**D3. Everything condensed into cards.** Greg: "Let's condense whats showing on this screen it sa bit overwhelming.
Instead reduce these builds/gaps/etc categories down into a card each which highlights/high lelve data showing on the
card. Then when you click in it takes you to these lists".
Changed: on Collection, three summary cards: BUILDS (count, "Do first: ...", total dust for all), GAPS (S and A counts,
the top S gap named), DUPLICATES (species count, copies you can transfer). Each opens the lists screen, which has a
Builds | Gaps | Duplicates switch: Builds keeps the three headline cards, the stardust card, THESE FIT and the full list
(SHOW ALL is gone: the list is shown in full); Gaps and Duplicates are the lists as before.

**D4. Section name.** Greg: "Organise your squads - find me a name that suits htis more. Pogo Hub is very quickly
becoming somewhere the user can easily organise their pokemon teams and collection". Offered four names; Greg chose
"Teams and collection".
Changed: WHAT NEXT reads TEAMS AND COLLECTION. The ranking switch stays beside it.

**D5. Raid team planner.** Greg: "I would like the ability to click on each of these raids in Now & /coming Up. And be
able to pre-plan my raid teams for each one. I.e. I click on this, it expands its segment to show case X pokemon slots.
I'd like to come up with pokemon roles for raid (think tank/damage/etc -may need to tap on our rsearch to see what roles
make sense). Then in our raid suggestions i'd love there to be a suggested number of X roles (e..g tank/carry/damage/etc)
when a user clicks on that pokemon slot. It should offer our user the choice of a Role pick + an All roles card. When
picked pokemon best suitable to that role + the boss fight will show up in order of suitablity." Offered the research's
three roles; Greg chose "Yes, these three": Mega, Heavy hitter, Bulky hitter, suggested mix 1 + 3 + 2.
Changed: each raid row (Now and Coming up) taps open. Closed, it shows dates, name, kind chip and the readiness bar. Open,
it shows BRING, the to-do line and "Your team": six slots labelled MEGA, HEAVY HITTER x3, BULKY HITTER x2, each filled
with a suggestion from the box (or Empty), "Suggested: 1 Mega · 3 Heavy · 2 Bulky". Tapping a slot outlines it and opens
a picker under the team: "Slot 2 · Heavy hitter", Done, role chips All roles | Mega | Heavy hitter | Bulky hitter (the
slot's role chosen first), then the box's counters for this boss in order, each with a tick, name, Built / To build, role,
tier, types and what is left to do. Tapping one puts it in the slot. The rules behind the roles and the order are new
(see "Rules to confirm" below).

**D6. Max: same as raids.** Greg: "same treatment as raids. For each now and upcoming raid alow the user to click on the
raid to set their team ahead of time."
Changed: Max rows tap open the same way; the team is three slots, TANK, HEALER, ATTACKER (the research's standard team:
one tank, one healer, one or two attackers), "Suggested: Tank · Healer · Attacker", with the same picker (role chips
All roles | Tank | Healer | Attacker).

**D7. Max: fewer notes.** Greg: "lets keep the extra notes to a minimal on this page. I.e. remove all the extra comments,
lett the advice show after the user clicks on that particular raid."
Changed: a closed Max row shows no BRING line and no to-do; both appear when the row is opened. The two notes under the
roster went (see D8). My call, for you to confirm: Raids rows were made the same (BRING and the to-do only when opened),
so the two timelines behave alike.

**D8. Max: no roster.** Greg: "hide all this" (on YOUR MAX ROSTER).
Changed: YOUR MAX ROSTER, its tiles, "N Pokémon not set: mark Dynamax on each Pokémon's page" and "Only Pokémon caught as
Dynamax can take part; ..." are gone from the Max screen. Open question: where marking Dynamax is explained now that the
line has gone (today only the Pokémon page has the switch).

**D9. Gym slot picker.** Greg: "siimialr to raid change. When the user clicks this empty slot- a list of suggested pokemon
should show up in the order of best suited for the role at hand (here it woul dbe for the purposes of defending the gym so
sorted in HP/DEF/CP etc, refer to our resarch for actual weights)".
Changed: every Top defenders slot taps (filled ones too). The picker under the panel reads "Slot 2 · Defender", "Best
defenders first: gym tier, then bulk (Defence × HP), then CP.", and lists the Gym builds in that order with Def and HP and
a BULK figure. Note: the research (`03-gym-defense.md`) gives no numeric weights; it says bulk matters most, low max CP
decays slowest, and never to stack Normal types. The order above is my proposal (see "Rules to confirm").

**D10. Rocket slot picker.** Greg: "same change to this as the gym + raid changes".
Changed: each leader slot taps; the picker reads "Slot 2 · vs Kangaskhan / Rhyperior / Machamp", "Most of the slot's
Pokémon beaten first, then built before to build.", and lists the counters in the order the app already uses to pick the
slot's counter (most options beaten, built first, Rocket area, tier, score), each with "beats all 3" style text.

**D11. Grunts shown better.** Greg: "usefu information, but lets improve the way we display it."
Changed: the 3-column tiles became a list, one row per grunt: the type as a chip in the game's colour (MIXED TEAM / DECOY
in grey), the quote in italics, then who to bring with Built / To build / Not in your box, and what is left to do.

**D12. PvP slot picker.** Greg: "sme changes here as the raid/rocket changes".
Changed: each Suggested team slot taps and opens the same picker, role chips All roles | Lead | Safe swap | Closer, rows
with the roles, tier, Built / To build, types, "From ..." and the score.

**D13. PvP roles.** Greg: "consider do roles make sense for pvp too?"
Answer: yes; the league tables already give each Pokémon a role (lead, safe swap or switch, closer). Changed: the three
slots are LEAD, SAFE SWAP, CLOSER; each is filled with the best-scoring candidate the league table lists for that role,
or the best other candidate when none is listed (Great League's lead today: no listed lead in your box, so Melmetal). The
coverage and weakness line follow the new team. OTHER CANDIDATES shows each one's roles.

**D14. Season line.** Greg: "replace this with just "Current Season: GO Battle League: Twilight Trails. Ends 1 December,
2026."
Changed: the PvP foot line reads exactly that, built from the season event in the Hub data.

### Round 2: Greg's message and two canvas comments, 25 Oct 2026

**D15. Round 1's calls and rules accepted as a first attempt.** Greg: "this is good some thoughts. happy with the calls
you've made. note - my understanding is we can fine tune the weights later, so main thing here is a decent attempt at it
+ more on the visuals".
Recorded: the calls in D1, D7 and D13 stand; the rules below are the first version and their weights may be tuned later
without a new design pass.

**D16. Slot roles can be swapped, and an All role.** Greg: "the role type - lets keep it that we suggest a default raid
types, but allow the user to swap out the raid type to further customise their team. Also add in an "All" raid type -
just in cse the play wants to pick a pokemon that somehow didnt fit into the types and suggestions".
Changed: each slot still gets its suggested role. The picker's chips are now "ROLE FOR THIS SLOT": Mega | Heavy hitter |
Bulky hitter | All. Choosing one changes that slot's role (its label changes), refills the slot with the best unused
Pokémon for the new role, and filters the list; All lists every counter for the boss. A Pokémon you picked yourself stays
unless it does not fit the new role. My call: the same on Max (Tank | Healer | Attacker | All) and PvP (Lead | Safe swap
| Closer | All). "All roles" is gone; All replaces it.

**D17. Rationale behind an "i".** Greg: "put all rationale for weights behind an icon - dont have them just showing".
Changed: the round "i" (as the ranking switch's) holds every explanation: beside "Your team" / "Suggested team" (the
suggested mix and what each role is; the "Suggested: 1 Mega · 3 Heavy · 2 Bulky" line went behind it), in each picker's
header beside Done (how the list is ordered and what the roles mean; the Gym and Rocket order lines went behind it), and
beside the new Available | Best switch. Tapping "i" opens an accent-tint card under it; tapping again closes it.

**D18. Available | Best.** Greg (comment on Raids): "for the builds. Include an Available and Best slider on the pages -
consider the best/cleanest/convenient place to put this. What it does is swaps the suggested teams to either their best
available with NO action, and their best available if they wantted to min max".
Changed: a compact "SUGGESTIONS  Available | Best  (i)" switch, styled as the ranking switch, right-aligned on its own
line at the top of Raids and Max (under Now | Coming up), PvP (under the league switch), Gym and Rocket (top of the
screen). It is one setting per screen and changes every suggested team and picker there. Best is today's behaviour.
Available suggests and lists only Pokémon usable as they are (see "Rules" below). My call: Best is the default; say if
Available should be.

**D19. Pokémon you could get now.** Greg (comment on the PvP picker): "if the user has NO options, it should show
suggested options that are ATTAINABLE right now. if the user has options the suggest attainable options should be
collapsed by default. I'm happy for you to do a placeholder rule for attainable right now (try your best to get it
right), but lets build it so that atttainables definition can be reimagined later if needed".
Changed: every picker (Raids, Max, Gym, Rocket, PvP) ends with "YOU COULD GET NOW": top-tier Pokémon for the slot that
nothing in your box can become and that are attainable (placeholder rule below), each with its tier, role, types and
why ("Easy to get: Dewpider wild", "Boss on right now"). It is shown open, under "Nothing in your box for this role. You
could get these now:", when the box has no option; otherwise it is folded into a "Could get now (N) ›" link, with Hide
to fold it again. The rule lives in one place (one function in the data script) so it can be redefined.

**Q1 (ruled in D20).** Greg: "quesito on bulk - is DEf and HP equal in value or should they be weighted? and What
is CP's impact on the score, imagine CP is most important?" Answered in the session (see the reply of 25 Oct): Defence
× HP already weighs them equally; CP is mostly Attack and raises decay; the proposal is to rank by the copy's own Defence
× HP at its level instead of species stats then CP. Waiting on Greg.

### Round 3: Greg's message and three canvas comments, 25 Oct 2026

**D20. Gym order by the copy's own bulk (answers Q1).** Greg: "agreed, use copy's bulk".
Changed: the gym picker ranks by gym tier, then the copy's own bulk: Defence × HP of the target species with this copy's
IVs at the level its build reaches (its current level when nothing is left to do), from the engine's CP-multiplier table.
CP is no longer a sort key. Each row reads "Defence 153 · HP 429 at level 50" and the BULK figure is that product
(your built level-50 Blissey 66k, ahead of the to-build Blissey at level 30, 50k). The "i" text says why CP is left out.

**D21. Five stars.** Greg: "lets express 5* with actually five *'s like in the game".
Changed: the raid kind chip "5★" reads "★★★★★" (Raids, Now and Coming up).

**D22. Types as coloured icons.** Greg: "can we change thse types (ice/dragon/etc) to colored icons instead of the words
(use official icons orimitiate it for convenience for the user)".
Changed: every type chip (BRING lines on Raids and Max, every picker row, "You could get now", the Collection showcase)
is a round icon in the type's game colour with a white or dark glyph (contrast as `Theme.pokemonTypeText`), the type name
as its accessibility label and tooltip. The grunt list keeps the word beside the icon, because the word is what the quote
gives away. The glyphs are our own simple drawings in the spirit of the game's icons (flame, drop, bolt, leaf, snowflake,
fist, bubbles, mountain, wing, eye, beetle, rock, ghost, horn, moon, nut, sparkle, ring), not the official artwork, which
belongs to Niantic / The Pokémon Company; using the official set is a licence question for Greg.

**D23. Role colours.** Greg: "good job with the changes. One more change - lets give different roles different colors
please consider if the whole card should be the color of the role".
Changed: each role has a colour, kept to meaning across screens: pink for the special opener (raid Mega, PvP Lead),
violet for damage (raid Heavy hitter, Max Attacker, PvP Closer), teal for staying power (raid Bulky hitter, Max Tank, PvP
Safe swap), green for Max Healer, grey for All. The whole slot card takes the role's tint, with the role label in the
role's colour and the disc filled in it; an empty slot is outlined in the tint; the selected slot keeps the accent
outline. The role chips in the picker and the role words in its rows use the same colours. A full-strength card with
white text was considered and not used: six saturated cards side by side overpower the Pokémon names and the Built / To
build chips. PvP slots now read as filled whenever a Pokémon is in them (they were filled only when built), matching
Raids and Max; Built / To build stays on the chip.

### Round 4: Greg's seven canvas comments, 25 Oct 2026 (round 1 to 3 threads resolved by Greg)

**D24. "Upgrade available" icon replaces Built / To build.** Greg: "change to build - "Upgrade Available"", then
"consider if an icon w/ name on hover works well here to save space", then "this icon should be ubiquitous throughout
the app. When the user sees it , he/she understands it means that the pokmeon is not full strength and should be
upgraded if they wish to use it".
Changed: one icon, an orange up-arrow in an orange-tint circle (18 pt), named "Upgrade available" as its accessibility
label and tooltip, marks a Pokémon that is not at full strength (its build has something left to do). It sits in the top
corner of a slot card, after the name in picker rows, PvP OTHER CANDIDATES and the Rocket grunt list. The "Built" chip
is gone: no icon means full strength. "Not in your box" (a Rocket grunt with no counter in the box) stays a grey chip.
Orange is the app's "look in the game" colour, which fits a job done in the game. Open for the build: Greg wants it
everywhere in the app, so the Box list, the Pokémon page and the Collection lists should take it too (outside this
pass's screens; the manager to raise it).

**D25. Types on the slot cards.** Greg: "lets show the pokemon type on this card too."
Changed: raid, Max and PvP slot cards show the Pokémon's type icons (18 pt) at the foot of the card. PvP's "Steel/Fairy"
text line on the card went; an empty card keeps "No candidate".

**D26. Raid row coloured once the team is set.** Greg: "when a raid team has been set for the boss. it should turn the
segment a new color. maybe the accent color?"
Changed: the team panel ends with a "Set this team" button (accent). Tapped, the raid's row takes the accent tint with a
4 pt accent bar on its leading edge, its dates in the accent ink, a TEAM SET chip beside the name, and the button reads
"Team set · Undo". Same on Max. The demo boards show one set row (Palkia on Raids, Machop on Max). My call: a team counts
as set only when the player says so with the button, not as soon as one slot is chosen, because every slot already has
a suggestion in it.

**D27. "Could get now" says where.** Greg: "include where the user can get this. Think of how we can display this
information most concisely".
Changed: each row shows where as short tags from the research's obtain text: WILD, TEAM ROCKET, RAIDS, RAIDS NOW (accent;
a boss on right now), EGGS, COMMUNITY DAY, RESEARCH, INCENSE, EVOLVE, TRADE, GO PASS; the full research text is the
tooltip. A row with no source in the research reads EASY TO GET. The tag rule sits beside the attainable rule, so both can
be redefined together.

**D28. A chosen Pokémon leaves the list.** Greg (Gym picker): "when a pokemon is selected, it should disappear off this
list".
Changed: a copy placed in another slot of the same team no longer appears in that team's picker (Gym, Raids, Max, PvP,
Rocket). The slot being edited still lists its own Pokémon, ticked, so the player can see what is there while choosing a
replacement. My call, for Greg to confirm: on Rocket only Pokémon the player chose themselves leave the list; the app's
own suggested counters stay listed.

### Round 5: Greg's four canvas comments, 25 Oct 2026

**D29. Available is the default.** Greg (on the Gym switch): "default should be available".
Changed: every team screen (Raids, Max, Gym, Rocket, PvP) opens on Available; Best is one tap away. This replaces my
call in D18. Consequence worth seeing on the boards: in Available a raid's Mega slot starts empty (mega evolving is work).

**D30. Cost beside the upgrade icon, not a sentence.** Greg: "remove 'power up XX - XX dust" the add next to the upgrade
avialable arrow - XX And a dust icon. apply this change app wide where this format exists".
Changed: picker rows (Raids, Max, Gym, Rocket) no longer carry the "power up to level 30 · 19k dust" line. Beside the
upgrade arrow they show the cost and its currency as an icon: "19k" with a stardust sparkle (violet), or "100" with a
candy icon when the work costs candy and no dust, nothing when it is free. What the work is ("Upgrade available: power up
to level 30") is the icon's tooltip and accessibility label. The Rocket grunt list lost its to-do line the same way; it
has no cost to show (the grunt data carries the counter but not its price). Not changed, on purpose: the build lists
(Collection's Builds list, BUILDS THAT CLOSE THE GAPS, Gym TOP AVAILABLE), where the action line is the content of the
row and the DUST figure already sits in its own column. "App wide" for the build: the Pokémon page and the Box list should
use the same icon and cost wherever they show work left to do (outside this pass; the manager to raise it).

**D31. Gym picker rows: stacked stats, slimmer.** Greg: "can we improve how we display stats on these cards? I'm thinking
we change this to stacked stats and put them on the same level as Blissey/49k bulk. and then reduce the vertifacl hight of
cards slightly".
Changed: each row is one line high: tick, name with the upgrade cost, tier and type icons beneath, then a stacked "153
DEF / 429 HP" column on the same line, then the BULK figure. The level ("At level 30") is the stats' tooltip. Row padding
went from 10 to 7 pt; other pickers went from 10 to 8 now that their to-do line is gone.

**D32. Upgrade icon no longer covers the role.** Greg: "upgrade available icons are overlapping with role names".
Changed: on the raid, Max and PvP slot cards the icon sits in the role row, at its trailing end, instead of floating over
the card's corner. Gym and Rocket slots have no role label, so their icon stays in the corner.

### Round 6: Greg's two canvas comments, 25 Oct 2026

**D33. "Full strength" badge; no "Free" on a built Pokémon.** Greg (on Gym TOP AVAILABLE): "if its already built - don't
display free. Suggest to me an icon to be used for 'completed'/'built' pokemon. Something that feels good to look at and
accomplish".
Changed: a built Pokémon (nothing left to do) carries a "Full strength" badge: a solid green circle with a white tick
(light: #22A55A; dark: #3DCB7A with a dark tick), named "Full strength" for screen readers and on hover. It pairs with
"Upgrade available" (orange up-arrow): every Pokémon in a team or list shows one or the other. It sits where the upgrade
icon would (slot cards, picker rows, PvP OTHER CANDIDATES, Rocket counters) and, at 26 pt, in place of the cost figure on
the build lists (Gym TOP AVAILABLE, Collection's Builds list), whose sub line drops " · Free" for a built row
("Gym, Max" not "Gym, Max · Free"). A build that still has free work (Mega evolve Rayquaza) keeps "Free". This brings
back a "built" mark that D24 had removed. Proposed name "Full strength", Greg's words from D24; alternatives offered: a
gold star, a medal. Greg: "Keep the green tick as the Full strength badge." (confirmed 25 Oct).

**D34. Every viable Rocket grunt counter, scrolling sideways.** Greg: "if there are multiple viable options, id like you
to list them with a horizontal scroll. keep the thinness of these cards as is. Additionally display the counter types
somewhere ont his card, keep things as clean as possible."
Changed: each grunt row keeps its height (type, quote, one line) and the one-counter line becomes a strip that scrolls
sideways: up to eight counters from the box, one per species, each a pill with the name, its type icons (16 pt) and the
upgrade arrow or the full-strength badge; the first pill (the app's pick) is on the Rocket tint. Order: built first, then
the app's own order for the grunt counter (Rocket area, tier, score). The strip follows Available | Best. Mixed team and
Decoy keep "Any strong attacker"; a type with no counter in the box keeps its single line ("Not in your box").

### Round 7: Greg's three canvas comments, 25 Oct 2026

**D35. Counter types under each grunt's type.** Greg: "can we add the actual counters under the TR type? make them
sufficiently small so its not too much repetition".
Changed: under the grunt's type (icon and word) in the Rocket list, a row of small type icons (13 pt) shows the types
that beat it, from the Hub's type chart (Normal: Fighting; Grass: Fire, Ice, Poison, Flying, Bug). They carry no words;
"Beaten by Fire, Ice, ..." is their accessibility label and tooltip. Mixed team and Decoy show none.

**D36. Hub tile icons closer to the game.** Greg: "can we improve the icons of our main areas in pogo hub - maybe
something more aligned to the visuals used in pokemon go for these categories".
Changed: the six tile glyphs are redrawn after what each area looks like in the game, as our own line drawings: Collection
a Pokédex (device with a lens), Raids a raid egg with a star, Gym battles a gym tower topped by a ball, Team Rocket a bold
R, PvP leagues a battle shield with crossed blades, Max battles a Dynamax cloud with a rising arrow. Same size, stroke and
type colours as before. They are not the game's artwork or logos (Niantic's and The Pokémon Company's); the Team Rocket R
is a plain letter, not their emblem. Using official artwork is a licence question for Greg (as in D22).

**D37. The active account in the header.** Greg: "instead of account - can we show which account is active right now".
Changed: the Hub header shows the active account, "[trainer name]", with its monogram (its initials in the account's colour, the
app's `AccountMonogram` rule) before the name, in the accent ink with the chevron that opens the account menu. The app
already shows the name there; the canvas had hidden it, and the monogram is new on this header.

**D38. Grunt rows tidied.** Greg (comment sent to Claude, on the Rocket counters): "i like all the elements on this
page, but it sa little too messy as it stands. how can we improve this?"
Changed: each grunt row is two lines. Line 1: the type icon, the type word, the quote (one line, truncated) and the
"beaten by" type icons at its trailing end. Line 2: the counters strip. The counter pills lost their own type icons
(the "beaten by" icons say the same thing once per row) and keep the name and one mark (upgrade arrow or full-strength
tick); the detail stays in each pill's tooltip. This takes back the per-pill types from D34; the counter types now live
once per row (D35). Offered to Greg: put the pill types back, or move the quote to a tooltip for thinner rows.

**D39. No monogram in the header.** Greg (on the initials disc): "lets remove this icon. uncneesary here i believe".
Changed: the Hub header shows the active account's name only ("[trainer name]", accent ink, chevron), as the app does today.
D37's monogram is withdrawn.

**D40. Good numbers highlighted on PvP.** Greg (on the PvP candidate rows): "lets highlight good numbers please. 1 color
for a top pick, a good pick, and then no highight/accent/font for any others similar logic to the strengths".
Changed: on the PvP picker rows and OTHER CANDIDATES, the SCORE figure and the IV line ("#528 · 96.8%") are graded: a
top pick is green on a green-tint box, bold; a good pick is green text; anything else is plain. Thresholds (my proposal,
tunable like the other weights): score top 92 or more (the S chip), good 90 or more (A); IV rank top within the best 100,
good within the best 500 (the Leagues panel's existing "strong IV" line). The picker's "i" explains the colours.

**D41. Current raids as sideways cards.** Greg (on the Raids switch): "can we have the current ('now') raids set up like
the team rocket page where they are slides of currently available raids rather than stacked like here." and "coming up
list stays stacked/list format".
Changed: Raids › Now shows the raids on now as a strip of cards that scrolls sideways (250 pt wide, radius 22, as the
Rocket leader cards): dates and "now" as the kicker, the boss name and its kind chip (and TEAM SET when set), the
readiness bar, and BRING with its type icons. The chosen card has the raid tint and a 2 pt raid-colour outline; a card
whose team is set keeps the accent bar on its leading edge. The first raid is chosen when the screen opens. Under the
strip, "YOUR TEAM FOR PALKIA" heads the chosen raid's to-do line, team, Set this team and picker, unchanged from D5 to
D33. Coming up stays the tappable list (D7). My call: Max keeps its list for both, since nothing is on there now; say if
its Now should become cards too.

**D42. "Team set" state redrawn.** Greg (comment sent to Claude, on the button): "team set undo seems incorrectly
formatted".
Changed: a prototype bug squashed the set button into a small circle (its style name clashed with D33's badge). Fixed, and
the set state is now a "✓ Team set" label in the accent ink with an underlined "Undo" text button beside it, in place of
the button; unset is the accent "Set this team" button (Raids and Max).

**D43. Tap the chosen raid card again to close its team.** Greg (comment sent to Claude, on a raid card): "click this
again should hide/collapse the team selection panel."
Changed: tapping the chosen card on Raids › Now collapses its team panel (heading, to-do, team, picker) and the card
loses its outline; tapping any card opens that raid. Coming up rows already open and close on tap.

**D44. Raid name inside the team panel.** Greg (comment sent to Claude, on "YOUR TEAM FOR PALKIA"): "put this inside the
your team segment".
Changed: the heading under the raid cards is gone; the team panel's title reads "Your team for Palkia" (the chosen raid).
Coming up rows keep "Your team", their row already names the boss.

**D45. "Your squad – Boss", advice under it.** Greg (comment sent to Claude, on the team title): "change the wording for
your team. to just "Your squad - Boss Name." And the advice should come under neath this title. also make the Your team -
left aligend to the card, no need to align with the choices below - this is the tiel of this segment".
Changed: the team panel's title reads "Your squad – Palkia" (16/800, the segment's title), and the advice line (the
row's to-do) sits directly under it, inside the panel. Under the raid cards the squad is no longer a panel inside the
card, so the title starts at the card's own left edge. My call: the same title and advice placement on Max and in the
Coming up rows; a row with no team (Raid Hour) keeps its note where it was. "Squad" replaces "team" in this title only;
"Set this team" and "Team set" are unchanged (word check for CONCEPTS.md).

**D46. A set raid card is filled in the accent.** Greg (comment sent to Claude, on a raid card): "instead of th eblue
border, fille the whole card blue once selected - i'm assuming blue is the acent here. so its hwatever accent color
they'ved picked". (Earlier he asked about the blue border; it was the Team set bar.)
Changed: on Raids › Now a card whose team is set is filled with the accent's solid, with its kicker, chips, readiness bar
and labels in the accent's on-solid ink (white in light mode, dark in dark mode); the leading-edge bar is gone. The chosen
card that is also set gets the raid-colour ring outside the card instead of the inner outline. My call: a set row in the
Coming up list and on Max is tinted in the accent with no bar (a solid fill behind an open row and its squad is heavy).

**D47. Squad title back to the panel-title style (reverts D45's layout).** Greg (comment sent to Claude, on the title):
"revert my changes around this title - make it reflect the other titles of other segments. but keep the wording
changes".
Changed: the squad is a panel again inside the open raid, its title styled as the Hub's other panel titles ("Top
defenders", "Suggested team", "Slot by slot": 15/800, inside the panel), and the advice line is back above the panel.
Kept from D45: the wording "Your squad – Palkia" (Raids and Max).

**D48. Closest options when nothing beats a Rocket slot.** Greg (comment sent to Claude, on "Nothing in your box beats this
slot"): "when nothing in the box beats this slot - i'd like you to offer the top 3 possible choices even if not ideal."
Changed: the Rocket picker then reads "Nothing in your box beats this slot. The closest options, with no type
advantage:" and lists up to three choosable rows from the box (following Available | Best), with "No type advantage" or
"No type advantage · not weak to this slot" as their line. "You could get now" stays open below. Rule (proposed,
tunable): among Rocket and Raids builds that hit none of the slot's options for extra damage, the fewest options that hit
them for extra damage first, then built first, Rocket area, tier, score; one per species.

**D49. D47 withdrawn; D45 stands.** Greg (comment sent to Claude, on the squad title): "sorry actually revert back to the
last version i like it better. sorry about that".
Changed: back to D45 on Raids and Max: "Your squad – Palkia" as a 16/800 title, the advice line directly under it inside
the squad, and under the raid cards the squad flat on the card with the title on its left edge.

**D50. "Best available" heads the closest options.** Greg (comment sent to Claude, on D48's line): "repalce this wording
with "Best available"".
Changed: the line above the closest options in the Rocket picker reads "Best available"; each row keeps "No type
advantage". Word check flagged for CONCEPTS.md: "Best available" sits on the same screen as the Available | Best switch
with a different meaning.

**D51. Fewer words on Rocket slot cards.** Greg (comment sent to Claude, on a slot's line): "theres a bit of a double up on
beats zekrom vs zekrom and hte same for persian, can we reduce words on the cards".
Changed: a slot the leader fills with one Pokémon shows only "vs Zekrom"; a slot with several shows a count, "beats all
3" or "beats 2 of 3", above "vs Kangaskhan / Rhyperior / Machamp". The picker rows use the same short form (its title
names the slot). A slot with no counter keeps "No counter" or its gap.

**D52. Grey type icons instead of "No type advantage".** Greg (comment sent to Claude, on a closest-option row): "lets
remove "no type advantage" instead when the type of the pokemon is NOT a type advantage just make it a colorless version
of its icon".
Changed: in the Rocket picker every row's type icons show the advantage: a type that hits one of the slot's options for
more than normal damage keeps its colour; any other type is the grey (`off` background, faint glyph) version of its
icon, read as "Steel, no advantage here". The words "No type advantage" are gone; a closest option that takes no extra
damage from the slot keeps "Not weak to this slot". Not applied to Raids, Max or PvP pickers (their rows list only
counters chosen for the boss's weak types, or PvP picks where the idea does not apply); say if Raids should do the same.

**D53. "Next best" replaces "Best available".** Greg (comment sent to Claude): "good point around woridng shared - can you
ssuggest an alternative? maybe Top options?"
Changed: the heading reads "Next best". "Top options" was not used because "Top" already means the best on these screens
(Top defenders, Top 3, a top pick in PvP numbers). Offered alternatives: "Closest options", "No counter: try these".

### Rules (first version, accepted by Greg on 25 Oct as a decent attempt; weights to be tuned later, D15)

- Available (D18): a raid, Max, Gym or Rocket pick is usable as it is when its build keeps the copy's own species (no
  evolve, form change or mega evolve; power-ups, second moves and TMs do not count against it); a PvP pick when it is
  the copy itself, not "From ..." an earlier family member. Consequence: in Available the Mega slot is always empty.
- Attainable now (D19, placeholder): an S or A gap (nothing in the box can become it) for that area and slot (a raid
  gap must be listed under one of the boss's bring types; a Rocket gap must beat one of the slot's options) that is a
  raid or Max boss on right now, or that the research rates Easy or Easy–Medium to get.

- Raid role: Mega when the build mega evolves (or targets a Mega or Primal); Heavy hitter when the copy is Shadow or the
  target's base Attack is at least 1.3 times its base Defence; Bulky hitter otherwise. Your export has no Shadow marks, so
  only the stats decide today.
- Raid counter order: the best tier the Raids table gives the target for one of the boss's bring types, then built before
  to build, then how many bring types it covers, then the advisor's order. The suggested team takes the first unused copy
  of each slot's role.
- Max role: from the Max table, Attackers section = Attacker, Role "Tank" / "Healer" / "Tank and healer". Order: tier,
  then a type that hits the boss, then the advisor's order.
- Gym defender order (D20, Greg's ruling): Gym table tier, then the copy's own bulk (Defence × HP of the target species
  with the copy's IVs, at the build's target level or its current level). CP is not a sort key.
- PvP role: from the league table's role text: "lead" = Lead; "safe swap" or "switch" = Safe swap; "closer" = Closer.
- Collection: a species counts once per dex number, released in Pokémon GO (the game master's released list, Mega and
  Shadow entries not counted separately); regions by dex range; "you can evolve" = an earlier member of its family is in
  the box.

### After the session, 25 Oct 2026 (one-click answers)

- CONCEPTS.md: Greg chose "Confirm as is". The word clashes it lists are left for the read-back to settle.
- Phone runs: Greg chose "One screen first". One screen goes to the phone first, and the rest follow once it looks right.
- The CONCEPTS.md confirmation was given on the version at 81fd169, before Greg's read-back answers below.

### Read-back answers, 25 Oct 2026, about 23:00 (Greg's one-click answers in the manager session, relayed by the manager)

Greg's words are the answers as the manager relayed them (`READBACK-pass-2-hub.md`, section 4).

**D54. TOP AVAILABLE becomes "Gym builds".** Greg (Q4): "rename TOP AVAILABLE to "Gym builds"".
Changed: the Gym list heading reads GYM BUILDS, so "available" now means only the Available | Best switch.

**D55. "Squad" everywhere instead of "team".** Greg (Q4): ""squad" everywhere instead of "team" (Set this squad / Squad
set, Suggested squad, YOUR SQUAD FOR GIOVANNI, SQUADS AND COLLECTION)".
Changed: Raids and Max "Set this squad" / "✓ Squad set"; PvP "Suggested squad"; Rocket "YOUR SQUAD FOR <LEADER>"; the Hub
section reads SQUADS AND COLLECTION. The game's own names keep their word (Team GO Rocket, the Mixed team grunt). The
canvas boards still show the old words.

**D56. Showcase keeps its name.** Greg (Q4): "SHOWCASE keeps its name".
Changed: nothing; the clash with the game's PokéStop Showcases is accepted.

**D57. PvP suggested squad by role.** Greg (Q3): "PvP suggested team by role (rule 23); coverage shown, not optimised."
Changed: nothing on the boards (they already pick by role). This replaces today's coverage-first pick
(`HubTeams.suggestedTeam`); coverage is shown as a figure only.

**D58. Where squads and picks are kept.** Greg (Q2): "per account on the phone, as recommended (survives re-scans; a
raid/Max squad dropped when its event ends; a pick whose copy leaves the box empties the slot and it refills with the
suggestion; Available | Best remembered per screen)."
Changed: CONCEPTS rule 27.

Not asked of Greg. These are the manager's calls and stand unless he objects:
- Q5: a Gym copy whose level is unknown ranks after the copies with a known level and reads "level not read". It is not
  given an assumed level. The design helper assumed level 20 for these copies, so its Gym order differs here.
- Q6: one copy may sit in squads on different screens (a raid squad and the Gym, for example).
- Q7: every Max pick reads Upgrade available until the app has Dynamax marks.

**Confirmation of the amendments.** Greg: "I confirm the amended CONCEPTS.md, including the manager's calls on Q5 to Q7."
Changed: CONCEPTS.md status reads confirmed; Q5 to Q7 now stand as confirmed by Greg.
