# Design pass 3 (the Pokémon screens): decisions log

Kept during the design session, 25 Oct 2026 onwards, in the Design canvas "Pokémon screens — design pass 3" (private
claude.ai artifact, https://claude.ai/artifact/5od545NCbCdYdz8yAyxoYd). For every change Greg asks for: his words, then
what changed in the design.

Greg's brief for the pass (relayed by the manager session): "take the learnings that apply to the pokemon screen. and make
those changes. I want the output of this to be a protytpe of the pokemon screens like we have for this one ... once the
protytpe is ready, I want to work with that session to refine the pokemon screen. My major gripe with it right now is that
it goes too many screens deep. So my first question wiilll be - How can we display the same information in less screens.
and in a more visually effective manner".

Starting point: the Box tab, the species list, the Pokémon page, its league view and the Fix a value sheet as built on
`feat/pogo-hub` at 7dcf72f (`BoxView.swift`, `SpeciesListView.swift`, `PokemonDetailView.swift`, `LeaguesPanel.swift`,
`BoxChrome.swift`), redrawn board by board, light and dark, from the app's own tokens (`Theme.swift`, `Typography.swift`,
`Components.swift`). The figures are Greg's own box (export of 22 Oct, 2,125 Pokémon in 349 species) worked out by the
app's own code at that commit: `BoxIndex` and `GameSearch` (app target, copied verbatim into the dump) and `BoxAdvice`,
`LeaguePanel`, `HubTeams`, `HubModel` (PogoBox).

Demo species: Eevee (65 copies). Demo Pokémon: the Eevee at CP 782 (2/11/6), the copy the advisor builds (Glaceon for
raids, Vaporeon for Max); it is 54th of 65 in today's species list.

Known limits of the boards (not decisions):

- The export has no moves, Lucky, Shadow, Purified, favourite or Dynamax marks; the boards show none and the Dynamax switch
  reads Not set.
- Dates are left out of the data: first seen, last seen and the last scan read [date].
- The Pogo Assist ranking is not in the data; the boards show Classic picks only.
- The Box boards start at E in Options A and B (as if jumped there), so Eevee is on the first screen.

## The prototype as first shown (25 Oct 2026)

Rows on the canvas: today (5 boards), pass 2's six lessons as before/after boards, today's three screens with all six
lessons, and the fewer-screens answer (a map of today's path, Option A, Option B). The session's own calls, each written
on the canvas as a note for Greg to confirm:

- **C1. Number grades.** Pass 2's PvP rule (D40) on the league cards and option rows: top = score 92+ or IV rank 1–100;
  good = score 90+ or IV rank 101–500. Today's page greens any score of 80+ and any IV rank to 500.
- **C2. Box row mark.** The upgrade arrow when any copy of the species has work left, with the dust its builds need in
  total (candy when no dust is due); the Full strength tick when it has builds and all are done.
- **C3. IV % grades on Box and species rows.** Top at 100%, good at 93% (42 of 45) or more.
- **C4. Advice, fewer words.** The target's name and types as the heading, the cost beside the upgrade arrow, the work as
  one short line ("Evolve, power up to level 35"); the spare and keep or transfer notes as short tags ("Spare: Umbreon,
  Vaporeon, Glaceon planned", "Keep · best IVs of 65"), the full sentences behind an "i".
- **C5. Rationale behind an "i".** The Shadow note moves into the Leagues "i"; the Dynamax note behind its own "i"; the
  stronger-species note opens with the worth tag; the Delete note goes (its VoiceOver hint stays).
- **C6. Over-cap option rows.** No sub line under the name, and "Over 1,500 CP" without "as Umbreon" (the row names it).
- **C7. Option A** (the Box opens in place): a species row opens in the list, showing every copy with a build, then the two
  best by IVs, then "All N ›". The Pokémon page shows the leagues as three tiles; the chosen tile's family list sits under
  them, with the Advice still on the page.
- **C8. Option B** (one screen per species): a strip of copy cards (copies with a build first, then best IVs), and the
  chosen copy's IVs, Advice, league tiles and facts under it. Recommended by the session.

## Rulings carried over from pass 2

App-wide wording Greg ruled in the Hub read-back (pass 2's `DECISIONS.md`, D54 and D55, relayed by the pass 2 session on
25 Oct 2026). They apply to these screens wherever the words come up:

- **D54 (pass 2).** "TOP AVAILABLE" is "Gym builds".
- **D55 (pass 2).** "Squad" everywhere instead of "team"; the game's own names keep their word (Team GO Rocket, the Mixed
  team grunt).

Neither word is on any pass 3 board as first shown (checked 25 Oct), so no board changed.

## Decisions

### Round 1: Greg's message, 25 Oct 2026

**D1. Option A: top 2 PvP and top 2 IVs when a species opens.** Greg (on Option A): "i do like option A - but i don tlike
whats being shown right now in terms of to build. Could we instead should top 2 PVP and top 2 IVs instead?"
Changed: a species row that opens in place shows TOP PVP (2 copies) then TOP IVS (2 copies), then "All N ›"; the TO BUILD
group is gone. A TOP PVP row reads its league, the pick and its score, and this copy's IV rank ("Great · Umbreon 90.2 ·
IV #99"), both graded as C1. A TOP IVS row keeps the keep or transfer tag. A copy with a build still shows its upgrade
mark on its row. Tapping a TOP PVP row opens the copy with that league's tile chosen. Rule, the session's proposal for
Greg to confirm: a copy's PvP standing is its best Great or Ultra League card that fits under the cap, by the pick's
PvPoke score, ties by this copy's IV rank; Master League is left out (there the IVs decide, which TOP IVS already
shows). TOP IVS takes the next two in the species list's order (best IVs first), skipping copies already in TOP PVP.
Greg, asked whether Master League should count: "Keep top PvP to Great and Ultra League." (confirmed 25 Oct).
On Eevee: TOP PVP is CP 593 (0/14/5, Great League Umbreon, IV #99) and CP 672 (Umbreon, IV #351); TOP IVS is CP 174
(15/12/14) and CP 832. The path map's Option A card now says the same. Option B's strip is unchanged (builds first).

**D2. League names in their league's colour.** Greg (canvas comment on a TOP PVP row's "Great"): "if great here refers to
great leave, it should be colored accordingly".
Changed: on Option A's TOP PVP rows the league name ("Great", "Ultra") is in that league's ink, bold (Great blue #1F5FD1 /
#8FB0FF, Ultra gold #8A5A00 / #F0C33C, Master violet #7A2FB5 / #D1A3FF, as `League.ink`). My call, the same rule applied
elsewhere: the "GREAT FAMILY" heading over the family list (Options A and B) takes the league's ink too. League tiles and
the today boards already used the league colours.

**D3. A league is its full name or GL / UL / ML, nothing in between.** Greg: "actually 1 further change. Everywhere Great
league appears it should only be "Great league" or if short form required, use "GL" and same with the other leagues keep
colors the same. in pokemon tab on the card it shoudl be the short form version".
Changed, on the redesigned boards (today's boards keep today's wording, since they show the app as built): the league
tiles on the Pokémon page (Options A and B) read GL, UL, ML; Option A's TOP PVP rows read "GL · Umbreon 90.2 · IV #99";
the family-list heading reads GREAT LEAGUE FAMILY; on the Pokémon page with the lessons the IV figures read GL / UL / ML and
the league view's switch reads GL | UL | ML; the league blocks keep "Great League" in full; the canvas note says "Great
League or Ultra League". Colours unchanged (`League.ink`, `League.dot`). My calls: capitalised as the game writes it,
"Great League" (Greg typed "Great league"; asked, he answered "Capitalise it as the game does: Great League.", 25 Oct); the switch takes the short form because three
full names do not fit one row at 15 pt.

**D4. Option A's Pokémon page, less cluttered.** Greg (canvas comment on the page): "i do like this page. however, it feels
cluttered at the moment. can we improve this?"
Changed (Option A only; Option B's page keeps the earlier layout), with nothing taken off the page, only moved or folded:
- Heading: the name, types and CP on one line and level and HP under it, with the IV bars in the same card (was a heading,
  a CP line with the search chip, and a separate IV panel). The game search is a circle in the header (orange magnifier,
  labelled "Copy search: eevee&cp782").
- Advice: each build is two lines, the target with types and cost, then one muted line ("Raids · Tier B · Evolve, power
  up to level 35"; the area and tier chips became text). The spare and keep or transfer notes are one muted line; the
  "i" for the full sentences sits beside ADVICE.
- Leagues: the Classic | Pogo Assist switch moved inside the Leagues "i" with its explanation. Under the tiles, one line
  only (the worth line, or why nothing fits); the stronger-species note, the over-cap count, the cost in full, the moves
  and the family list open together from one row, "Great League family and details (8 more) ›", closed at first.
- Facts: power-up dust, spare copies and seen in one row of three, then Dynamax.
My calls, to confirm: the family list starts closed; the ranking switch lives behind the "i".

**D5. Activity tabs on the Pokémon page.** Greg: "great i like it now i want to add tabs across the top below the 1st
segment (pokemon details) with the various activities. on each activity tab it shows how this pokemon fits into that
actiivity - or suggest something to go under ach tab that woudl add utility to the user".
Changed (Option A's Pokémon page): under the details card, a row of tabs in the Hub's area colours and glyphs: Summary,
Raids, Gym, Rocket, PvP, Max (scrolls sideways; Summary first). The facts, Dynamax and Delete stay under every tab.
- **Summary**: one row per activity (glyph, name, one line on how this copy fits, its upgrade or Full strength mark when
  it has a build there; a tap opens that tab), then the Advice panel.
- **Raids**: a card per family member and attacking type the Raids table lists (tier, "ICE ATTACKER" with the type icon),
  the copy's plan ("Planned for this copy: evolve Eevee, 62k dust") or your best attacker of that type in the box, and the
  raids on now and coming whose bosses that type hits (Shadow Landorus, Giratina Origin…, with NOW and the dates).
- **Gym**: a card per family member the Gym table lists, this copy's bulk as that member at its level beside your top
  defender's (Umbreon 30k against Blissey 66k, as bars), and the plan or why it is not one.
- **Rocket**: the members with the most grunt types beaten (grunt type icons) and the leader slots they beat ("Giovanni
  slot 2, 3 · Sierra slot 2"); a tier line when the Rocket table lists one; a note that this is by the Pokémon's own
  types, the export having no moves.
- **PvP**: the league tiles and family list as D3 and D4.
- **Max**: Dynamax state first ("Dynamax: not set"), the members the Max table lists (role, tier, plan), and the Max
  battles on now and coming the family's types hit.
Rules, the session's proposal for Greg to confirm: the family is the copy's own species and what it can still evolve
into (never back up the family: a Staraptor shows only Staraptor); a type "hits" a grunt, boss or leader option when it
does more than normal damage to its types (`HubData.effectiveness`); bulk is pass 2's (Defence × HP with the copy's IVs,
at its current level); raids and Max battles are those on now and coming as of 25 Oct (`HubRaidsModel.timeline`). The data
comes from the dump's new `families`, `act` and `topDefender` (`DesignDumpActivities.swift`).

**D6. The Box header shows the account's name only.** Greg (canvas comment on Option A's header): "change to show only
the account name. No icon + not Account name".
Changed (Options A and B, and the Box with the lessons): the monogram pill is gone; the header shows the active account's
name, centred, 22/700 in the accent ink with the chevron that opens the account menu, as the Hub header after pass 2's D39;
Export and More stay on the right. The canvas shows Greg's trainer name; the committed boards read "Account name" in its
place. Today's Box board keeps the pill as built.

**D7. Search bar under the account name.** Greg (canvas comment on Option A's header): "add search bar under account name
and above first pokemon segment".
Changed (Options A and B): the Box's search field ("Name, CP, or cp1500-2500", as today's) sits directly under the header,
above the first letter group, and stays in place while the list scrolls. My call: it is fixed under the header rather
than scrolling away with the list, so it is there wherever the list is.

**D8. PvP first.** Greg (canvas comment on the activity tabs): "good addition, but put pvp first".
Changed: the tabs read PvP, Summary, Raids, Gym, Rocket, Max, and the page opens on PvP; the Summary's rows also start with
PvP leagues. Consequence, flagged to Greg: the Advice panel sits in Summary, so it is one tap away when the page opens.

**D9. The Box tab is "My Pokémon".** Greg (canvas comment on the tab bar's "Box"): "chnage this to My Pokemon".
Changed (Options A and B, and the Box with the lessons): the first tab of the floating tab bar reads "My Pokémon" (with the
game's é), with the same grid glyph. Today's boards keep "Box". Not changed, for the word check in `CONCEPTS.md`: "your box"
in sentences (the export, the advisor's notes) and the path map's "Box" cards; the read-back should settle whether "box"
stays the word for the player's storage elsewhere in the app.

**D10. Account name small on the left, the screen's name in the middle.** Greg (canvas comment on the header): "make the
account name smaller and left aligned, then in the middle put the name of this screen "My Pokemon"".
Changed (Options A and B, and the Box with the lessons): the header's left end holds the account name, 15/700 in the
accent ink with its chevron (it still opens the account menu); "My Pokémon" sits centred on the header, 17/800 in ink, as
the screen's heading; Export and More stay on the right. This revises D6's centred 22 pt name for this screen; the Hub's
header (pass 2, D39) is unchanged.

**D11. Summary first, PvP second (revises D8).** Greg: "sorry put summary first, then PVP 2nd".
Changed: the tabs read Summary, PvP, Raids, Gym, Rocket, Max, and the page opens on Summary again (so the Advice shows
when the page opens). The Summary's rows keep PvP leagues first, from D8.

**D12. "See all 65 copies".** Greg (canvas comment on the open species' last row): "the All/ 65/Eveee - looks a little
wakward".
Changed (Option A): the link under an open species reads "See all 65 copies ›" (the species is already named on the row
above), centred on a full-width accent-tint button under the TOP IVS rows; its VoiceOver label keeps the species, "See all
65 Eevee". It still opens the full species list.

**D13. Activity names in their Hub colours.** Greg (canvas comment on the Summary rows): "the text on this page seems like
it could be missing color we've applied else whre from pogo hub. e.g  Max/Raids not in their color and PVP leagues".
Changed: on the Summary tab each activity's name (Raids, Gym battles, Team GO Rocket, PvP leagues, Max battles) is in its
Hub tile colour (raids orange, gym green, Rocket slate, PvP purple, Max violet, as pass 2's tiles); the PvP row's league
("ML") is in its league colour (D2, D3); the tab labels take their activity's colour too, not only their glyphs; the PvP
tab's heading reads PVP LEAGUES in the PvP colour, like the other tabs' headings.
Greg, after the first try: "the summary tab doesnt seem to have it. I see an ML on summary not colored and same with Max
and Raids listed". Changed: the colours are now set on the words themselves (not only through the shared stylesheet),
and the Advice lines on Summary colour their areas too ("Max ·" violet, "Raids ·" orange, GL / UL / ML in league
colours), with the tier and the work after them in muted grey.

**D14. Summary rows that say something useful.** Greg (canvas comment on the Summary rows): "i think the informaiton shown in
each activities summary could be more useful".
Changed: each Summary row now has the activity's name, a verdict chip, one line with the fact behind the verdict, and the
upgrade arrow with its cost when this copy has work planned there. On the Eevee at CP 782:
- PvP leagues · OK: all three leagues at a glance, "GL Eevee 54.9 · UL Espeon 65.8 · ML Sylveon 80.1" (league in its
  colour, scores graded as C1).
- Raids · PLANNED ↑62k: "Glaceon, B Ice attacker · counters Shadow Landorus (Incarnate) now and 3 more".
- Gym battles · NOT PICKED: "As Umbreon: bulk 30k, 45% of your top defender (Blissey)" (the top defender itself reads
  "your top defender").
- Team GO Rocket · BEATS 4 GRUNTS: "As Glaceon:" then the four grunt type icons, then "Giovanni slot 2, 3 · Sierra slot 2".
- Max battles · PLANNED ↑25 candy: "Vaporeon, B · Cinderace-specific tanks · Dynamax not set", or the next Max battle that
  member's types hit.
Verdicts, the session's proposal for Greg to confirm: FULL STRENGTH (this copy's build for the activity is done), PLANNED
(it has a build there with work left), SPARE (another copy is your best for that raid type), OPTION (listed in the
table, nobody planned), NOT PICKED (gym: listed, not a top defender), BEATS N GRUNTS (Rocket), NEEDS DYNAMAX (Max: listed
or built, Dynamax not set), STRONG / OK / WEAK (PvP: the best league's worth tag), NOT USED (none of the copy's reach is in
the table). Green chips for full strength, strong and beats; orange for planned and needs Dynamax; grey otherwise. For
Rocket the member shown is the one with a build here, else the one beating most grunts, ties to the later evolution.

**D15. Summary rows, calmer.** Greg (canvas comment on the Summary rows): "good job infomraiton is useful now  but can we
clean up the visuals a little clluttered as it stands".
Changed: the activity glyph sits plain in its colour (no tinted circle); the verdict is small coloured capitals at the
row's right end (no chip background); the detail line is one muted colour and one weight, with only the league
abbreviations in their colours, a graded score when it is top or good, and Rocket's grunt icons; the lines are shorter:
"Glaceon, B Ice attacker · Shadow Landorus (Incarnate) now +3", "As Umbreon, bulk 30k · 45% of Blissey", "As Glaceon"
and the grunt icons (the leader slots stay on the Rocket tab), "Vaporeon, B · Cinderace-specific tanks" (Dynamax is in
the verdict). Rows are a little taller (10 pt padding).

**D16. Verdicts on one edge.** Greg (canvas comment): "better, but maybe align the picked, planned, ok words they are all on
different alignments making it look mesy".
Changed: the cost mark has a fixed 58 pt slot on every row, empty when there is no work, so the verdicts (OK, PLANNED, NOT
PICKED…) all end at the same right edge whether or not the row shows a cost.

**D17. Verdicts in their own column (revises D16).** Greg (with a screenshot of the dark board): "they are less lined up
than before".
Cause (the session's mistake): an older rule from D5 styled every span in a Summary row as 13 pt grey, so the verdicts lost
their small capitals and colours, and the verdict shared the name's line, so a long one ("BEATS 4 GRUNTS") wrapped under
it. The same screenshot showed the league letters and the Advice area words still grey: colours set inline on those
words did not reach them.
Changed: each Summary row is glyph | name and detail line | verdict | cost slot | chevron; the verdict has its own 92 pt
column, left-aligned, level with the name, so every verdict starts at the same place and none wraps; 10/800 capitals in
green (full strength, strong, beats), orange (planned, needs Dynamax) or grey. The old rule is gone, and the activity
names, league letters, graded scores, verdicts and the Advice area words take their colours from classes in the
stylesheet instead of inline.

**D18. Verdicts right-aligned; Rocket's verdict is a status word.** Greg (with a screenshot of the dark board): "much
better, but lets mke the verdict right aligned. also beats 4 grunts doesnt really match the verdict style of the others".
Changed: the verdict sits on the name's line again, right-aligned and never wrapping, its right edge the same on every row
(the cost slot keeps its fixed width, D16); the detail line takes the row's full width under the name, so it wraps less.
Rocket's verdict follows the others' words: PLANNED or FULL STRENGTH with a Rocket build, OPTION when its types beat at
least one grunt type, NOT USED otherwise; the count moved into the detail line, "As Glaceon, beats 4 grunt types" and the
grunt icons.

**D19. Back to D17's layout, verdicts right-aligned in their column (reverts D18's layout).** Greg (with a screenshot of
D18): "might ahve to reverse that, that was a regression. I like verything in the odl one except for the alignment of the
verdict/ok/planned/etc".
Changed: the row is D17's again (name and detail line on the left, the verdict in its own 92 pt column, the cost slot, the
chevron), with the verdicts right-aligned in that column so they all end on one edge. Kept from D18, my reading of
"everything in the old one": Rocket's verdict is OPTION and the count sits in the detail line ("As Glaceon, beats 4 grunt
types"), since that answered his point that BEATS 4 GRUNTS did not match the other verdicts; offered to Greg to restore it.
Greg: "Bring back BEATS 4 GRUNTS as Rocket's verdict." Changed: Rocket's verdict is BEATS N GRUNTS again (green), its
detail line "As Glaceon" and the grunt icons, as in D17.
Greg: "also- Ok/Planned/notpicked/beats4grunts/planned are all still not right aligned, can we just keep eveyrthing the
same but make them right aligned?" Cause: the right alignment was only in the shared stylesheet, which had not reached
his view. Changed: the verdict column's width and right alignment are set on the element itself as well; nothing else
moved.

**D20. Verdicts flush right; one fact per line.** Greg (with a screenshot of D19): "still not. and also the UL/ML should be
on differnet lines - also check the lines of th eother segments could tweak a couple".
What the screenshot showed: the verdicts did end on one edge, but that edge was mid-row, left of the cost slot; "right
aligned" meant the row's right edge. Changed: each Summary row is a grid (layout set on the elements themselves): the
glyph on the left over both rows; on the first row the name and, flush with the row's right edge, the verdict; under it
the detail lines, then the cost and the chevron on the right. One fact per line:
- PvP leagues: "GL Eevee 54.9", "UL Espeon 65.8", "ML Sylveon 80.1" (or "GL over the cap"), each on its own line.
- Raids: "Glaceon, B Ice attacker" / "Counters Shadow Landorus now +3 more" (a boss's form in brackets is dropped).
- Gym battles: "As Umbreon, bulk 30k" / "45% of your top defender, Blissey" (or "Your top defender").
- Team GO Rocket: "As Glaceon" and the grunt icons on one line.
- Max battles: "Vaporeon, B tier" / "Cinderace-specific tanks", then "Hits <boss> in N d" when one is coming.
Empty states shortened ("Not in our raid tables", "No type advantage on any grunt").

**D21. The Raids tab, polished.** Greg (canvas comment on the Raids tab): "polish the visuals of this segment".
Changed (layout and colours set on the elements themselves):
- Heading: RAIDS in the raids orange, "Eevee family" in grey on the right (was "RAIDS · THE EEVEE FAMILY").
- One card per family member and attacking type (on `surface2`, radius 18): the name 18/800 with its type icons and the
  tier chip on the right; under it a pill in the raids tint with the attacking type's icon, "Ice attacker".
- This copy's plan as its own block on `surface`: "Planned for this copy" over "Evolve, power up to level 35", the upgrade
  arrow with 62k dust and 89 candy on the right (or "This copy, full strength" with the tick). When another copy holds the
  plan, one grey line instead: "Another copy (CP 782) is planned as your Glaceon." or "Your best Ice attacker is Mamoswine
  (S), still to build.".
- COUNTERS: one row per raid (up to six), the boss's name, its kind chip (SHADOW, 5★…) and NOW in the accent or "in 3 d"
  in a right-aligned column; a boss's form in brackets is dropped unless two bosses share the name (the two Giratinas).

**D22. Dynamax and Shadow as marks on the details card.** Greg (canvas comment on the Dynamax switch's "Yes"): "turn this +
shadow into a icon on the pokemon card they can click to toggle marking it as either or turning it off the same way".
Changed: two round marks (32 pt, 44 pt tap area) at the right end of the details card's "Level 30 · HP 111" line: Dynamax
(the Max cloud glyph) and Shadow (a flame). Off: grey (`off` circle, faint glyph); on: Dynamax in the Max violet tint with
a violet ring, Shadow in a purple tint with a purple ring. One tap marks, another clears; each is a toggle button for
VoiceOver ("Dynamax: not marked. Tap to mark it as caught as Dynamax"). The Dynamax row and its note left the facts panel;
the Max tab's line reads "Dynamax: not marked." or "Marked as Dynamax." and points to the mark; the Summary's Max verdict
follows it (NEEDS DYNAMAX until marked).
For the read-back, flagged to Greg (meaning changes, so a full review): today's Dynamax switch has three states (Not set,
Yes, No) and the toggle has two, so "No" and "Not set" become one; a hand-set Shadow mark is new (today Shadow is only
known from a clip merge, `ScanRow.shadow`) and would need storing beside the Dynamax edit, and the advisor and league
ratings would have to be worked out again when it changes (the prototype does not recompute them). Purified was not
asked for and is not drawn.

**D23. The list centred on the screen, the A–Z index kept.** Greg (canvas comment on the My Pokémon screen): "on this
screen the table/segment of pokemon isnt aligned in that the centre of this segment is not the cenre of the screen and
thus not the centre of the pogo scan button. i suspect this is due to the alphabet scroll on the right side. is there any
way to fix this other than removing that ?"
Cause, as Greg suspected: the list had 14 pt on the left and 32 pt on the right to leave room for the index. Changed
(Options A and B): equal 24 pt gutters on both sides for the list and the search field, so the list's centre is the
screen's centre and the Scan button's; the index (22 pt wide) sits in the right gutter. Cost: the rows are 10 pt narrower
than before (and 20 pt narrower than a list with no index). Offered alternatives: the index shown only while scrolling,
over the list's edge; or a smaller index inside the panel's right edge.

**D24. The A–Z index only while scrolling.** Greg: "lets keep this sizing but make it only show when scrolling".
Changed (Options A and B): D23's equal 24 pt gutters stay; the index is hidden until the list scrolls, appears in the right
gutter while it moves, and fades out (0.25 s) a second after the last scroll. In Play, scroll the list to see it. For the
read-back: VoiceOver still needs a way to reach the index while it is hidden (today it is one adjustable element).

**D25. The Gym tab: fewer words, one clear comparison.** Greg (canvas comment on the Gym tab): "i like this info, but can
we reduce the writing, improe visuals and enhance clarity of the message".
Changed, in the Raids tab's style (D21): heading GYM BATTLES in the gym green with "Defending" in grey on the right; one
card per family member the Gym table lists (name, types, tier); the copy's bulk as one large number under a BULK caption,
with "45% of the top" in green on the right; one bar (this copy's bulk against the top defender's), captioned "This copy,
level 30" and "Blissey 66k"; then the copy's plan as a block with its cost or tick ("Planned as a defender ↑51k",
"Defender, full strength"), or the single line "Not one of your top defenders". The top defender itself reads "Your top
defender" with a full bar. The sentences about bulk and how the gym list is chosen are gone; the empty state is "Not in our
gym table."

**D26. Advanced details behind an icon.** Greg (canvas comment on the details card): "lets add in a section think advance
details (but show it with an icon) when the icon is clicked this details segment expands and it allows the user to update
the pokemon with more details, e.g. the moves of the pokemon + MAX levels + mega level details + any others. I'd like
there to be logic available e.g. if its a dynamax pokemn or marked as one the  max moves show, otherwise they stay hidden.
and only moves that pokemon can realistcally learn show up".
Changed: a third round mark beside Dynamax and Shadow (a sliders glyph, "Advanced details"; accent ring when open) opens a
section at the foot of the details card:
- FAST MOVE, CHARGED MOVE, SECOND CHARGED MOVE: chips of only the moves this copy's species can learn (the game master's
  `fastMoves` and `chargedMoves`), each with its type icon; Elite TM moves carry an ELITE tag; the second charged move
  starts on "Not unlocked" and cannot repeat the first.
- MAX MOVES, shown only while the Dynamax mark is on: Max Attack named by the fast move's type (Water: Max Geyser; Normal:
  Max Strike) at level 1, 2 or 3; Max Guard and Max Spirit at –, 1, 2 or 3.
- MEGA LEVEL, shown only for a species with a Mega form in the game master (40 in Greg's box: Gardevoir, Kangaskhan,
  Staraptor, Skarmory…): Not yet | Base | High | Max.
- MORE: Lucky, Purified, Best Buddy toggles; Purified and the Shadow mark clear each other.
The session's calls, for the read-back: defaults are the first fast move and the first non-Elite charged move (the export
carries no moves, so nothing is pre-filled from the scan); Gigantamax and G-Max moves are not drawn (the game master has no
Gigantamax entries); none of these values changes the ratings in the prototype; storing them is new (moves, Max levels,
Mega level, Lucky, Purified, Best Buddy beside the Dynamax edit) and is a full-review item. The data adds `fast`,
`charged` and `megas` to each family member in the dump.
Greg: "looks good, add to more - "Weather-boosted"". Changed: MORE reads Lucky, Purified, Best Buddy, Weather-boosted (a
toggle like the others, off by default). For the read-back: in the game a weather-boosted catch has a higher level and IV
floor, so the reader could use the mark when it works out the level and IVs; the prototype only stores it.
