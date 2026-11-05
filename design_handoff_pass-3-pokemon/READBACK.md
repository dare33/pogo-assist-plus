# READBACK: design pass 3, the Pokémon screens (Option A)

Written by the manager on 26 Oct 2026 (AEDT) from the handoff `design_handoff_pass-3-pokemon/` (13fac82 + 2df18fb on
`claude/pass-3-pokemon-d2aaf3`: README, CONCEPTS rules 1-19, DECISIONS C1-C8 and D1-D26, CONCEPTS confirmed by Greg), checked
against lane A (5719451, PR #21), lane B (e75dd32), the Hub branch (5142d1d, the Dynamax flag) and the design helper
`DesignDumpActivities.swift` (copied to the hub-design-2 notes folder). Goes into the handoff folder as `READBACK.md` once
answered. Built together with pass 2 (Greg, 26 Oct) on one design branch.

## 1. What each screen does (checkable on a device)

My Pokémon (was the Box tab)
3.1 Header: the account name small on the left with its chevron (opens the account menu), "My Pokémon" centred, Export and More on the right; the search field under it stays put while the list scrolls.
3.2 Species rows: name, type icons, "best N% · top R" with the % graded (top at 100%, good at 93%+), the species build mark (upgrade arrow with the summed cost, or the Full strength tick), the count, a chevron that turns down when open.
3.3 Tapping a species opens it in place: TOP PVP (the two copies with the best Great or Ultra League card under the cap, by the pick's score, ties by IV rank; league in its colour, pick, graded score, graded IV rank) and TOP IVS (the next two by IVs, each with keep/transfer); tapping again closes it.
3.4 Tapping a TOP PVP copy opens its Pokémon page with that league's tile chosen; a TOP IVS copy opens on Summary.
3.5 "See all N copies" opens the species list: lane B's YOUR BEST cards and 1-3 place markers stay on it (Greg, 26 Oct), with pass 3's row lessons (graded %, build mark).
3.6 The A–Z index shows while the list scrolls and fades a second after it stops.

Pokémon page
3.7 Header: back, the search circle (copies the game search), the pencil (Fix a value).
3.8 Details card with the Dynamax and Shadow marks (each on or off; Shadow on clears Purified and the reverse) and an Advanced details fold: fast and charged moves (only the species' own; the second charged starts "Not unlocked" and never equals the first; Elite tagged), Max moves only while Dynamax is on, Mega level only for species with a Mega or Primal form, Lucky, Purified, Best Buddy, Weather-boosted.
3.9 Tabs Summary, PvP, Raids, Gym, Rocket, Max; the page opens on Summary.
3.10 Summary: one verdict row per activity (PvP leagues first, one league per line), then the Advice (each build: target and type icons with cost or tick, one line with area, tier and work, spare/keep notes in one line, full sentences behind "i").
3.11 PvP: PVP LEAGUES with "i" (the Classic | Pogo Assist switch inside it), three league tiles, the worth line, the family and details fold.
3.12 Raids, Gym, Rocket, Max: activity cards per reachable family member (this species and the evolutions below it, never back up) as CONCEPTS rules 11-14; Max starts with the Dynamax state and reads NEEDS DYNAMAX until the mark is on.
3.13 Under every tab: power-up dust, spare copies and seen (one row of three), and Delete from box.
3.14 Number grades everywhere on these screens: top = score 92+ or IV rank 1-100; good = score 90+ or IV rank 101-500 (replaces the page's old green at 80+ / rank 500).

## 2. Rules checked against the code

Exists = in app or PogoBox code today. Most of pass 3 is new: the activity tabs, verdicts, marks storage and advanced details exist only in the design helper or not at all.

| Rule | Today | Note |
|---|---|---|
| 1 Species rows | Exists (`BoxIndex.sections`) | |
| 2 Species build mark, 3 IV % grade | Helper/new | Proposals (C2, C3). |
| 4-6 TOP PVP / TOP IVS, tap opens league | New | TOP PVP uses Great and Ultra only (Greg); needs a route that opens a copy with a league chosen. |
| 7 A–Z index | Partly (the list has letter sections) | VoiceOver gap (Q4). |
| 8 Marks | Mismatch | Dynamax today is `Bool?` on the Hub branch (Not set / Yes / No; No removes Max credit); Shadow is the row's `shadow` from the scan only, no hand mark (Q1, Q2). |
| 9 Grades | Bands exist for scores (92/90); IV-rank grades new | Same as pass 2's D40. |
| 10-14 Reach and activity tabs | Helper only (`DesignDumpActivities.swift`) | Move into PogoBox with tests; reuse pass 2's Hub models where they overlap. |
| 15-16 Verdicts and lines | New | |
| 17-18 Advanced details, defaults | New; nothing read from scans (the export has no moves) | Q2, Q3. |
| 19 Tabs and order | New (the page is a single column today) | |

## 3. Questions, with recommendations

Q1 Dynamax as two states: recommended "on" = caught as Dynamax (today's Yes), "off" = not marked (today's Not set; the advisor keeps today's behaviour: Max credit with a "needs a Dynamax copy" step). Today's "No" (no Max credit at all) goes; existing No values become off. The Dynamax/Shadow scan passes then only ever turn marks on.
Q2 What the new marks and details feed into in this build: recommended Shadow, Purified and Lucky feed the advisor and league ratings now (the engine already costs Shadow and Purified; Lucky halves power-up dust), with the advice recomputed when one changes; moves, Max move levels, Mega level, Best Buddy and Weather-boosted are stored and shown only, feeding the advisor in a later pass.
Q3 Weather-boosted and the level/IV reading: recommended not in this build (stored only).
Q4 A–Z index for VoiceOver: recommended the index is always reachable by VoiceOver as one adjustable "Jump to letter" element, even while hidden on screen.
Q5 The session's proposed rules (species build mark, IV % grades 100/93, TOP PVP tie order, reach, tab card rules, verdicts): recommended accepted as a first version, tuned after the phone run (as pass 2's D15).
Q6 The two headers: pass 2's Hub tab keeps the account name large and centred; pass 3's My Pokémon puts it small on the left with a centred title. Recommended one style on both tabs: pass 3's (small name left, title centred, so each tab says what it is).
Q7 Lane A's frozen header (count line, search, chips, rescan, sort line) vs pass 3's header (search stays under the title): recommended pass 3's design wins on My Pokémon; the chips and sort line scroll with the list unless the design shows them fixed (the build follows the board).
Q8 First screen to the phone (one screen first, Greg's choice): recommended My Pokémon with the species opening in place (the most-used screen, and it exercises the shared pieces: type icons, grades, build mark).

Also: the two data oddities on the canvas (a #1 Ultra League Tinkaton tagged OK; Classic picking Vaporeon over Umbreon for a Great League Eevee) go to a scout as possible bugs, separate from the build.

## 4. Greg's answers (26 Oct 2026, ~01:45 AEDT, one-click)
- Q1: Dynamax on = caught as Dynamax; off = not marked (today's Not set behaviour); today's "No" goes; existing No values become off.
- Q2: Shadow, Purified and Lucky feed the advisor and league ratings in this build, advice recomputed on change; moves, Max move levels, Mega level, Best Buddy, Weather-boosted are stored and shown only.
- Q6: one header style on both tabs: account name small on the left, the tab's title centred (pass 2's Hub header changes to match).
- Q8: My Pokémon (species opening in place) goes to the phone first.
- Q3, Q4, Q5, Q7 not asked; the manager's recommendations stand unless Greg says otherwise: Weather-boosted stored only; the A–Z index always reachable by VoiceOver; the session's proposed rules accepted as a first version; pass 3's header wins on My Pokémon (chips and sort line follow the board).
