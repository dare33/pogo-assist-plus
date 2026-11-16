# READBACK: design pass 2, Pogo Hub

Written by the manager on 25 Oct 2026 from the handoff (`design_handoff_pass-2-hub/` at 81fd169 on `claude/pass-2-hub-f555bc`:
README, CONCEPTS rules 1-26, DECISIONS D1-D53), checked against PR #15's head (5142d1d), the engine and the design
session's helper (`out/design-data/.../DesignDumpPlans.swift`, git-ignored). Goes into the handoff folder as `READBACK.md`
once Greg has answered. Nothing is built until then. Reviewers check the build against section 1.

## 1. What each screen does (checkable on a device)

Hub tab
1.1 The header shows the active account's name in the accent colour with a chevron that opens the account menu; no initials disc.
1.2 HAPPENING NOW IN POKÉMON GO strip as before; an event that used to open Everything opens Collection.
1.3 TEAMS AND COLLECTION holds six tiles with the new glyphs; Collection's chip reads "owned/released species" (e.g. 347/951).

Collection (replaces Everything)
1.4 Shows the species count, a bar and "N% of the species in Pokémon GO. N more you can evolve now."
1.5 DEX BY REGION: one row per region with "owned of total" and a bar; regions by dex range Kanto 1-151 … Paldea 906-1025.
1.6 SHOWCASE: the best copy of up to twelve species by IV % (ties by CP), as sideways cards.
1.7 SPECIAL SETS: two-column tiles (100% IVs, Legendary, Mythical, Ultra Beasts, Mega-capable, Lucky, Shadow) with counts; Lucky reads "Not in your scans yet" while no copy carries a Lucky mark.
1.8 MISSING: the count, the evolvable count, the first six with dex number, region and how to get; "All N ›" lists the rest.
1.9 BUILDS AND CLEAN-UP: three summary cards; each opens the Collection lists screen on its tab.
1.10 Collection lists: Builds | Gaps | Duplicates; Builds shows the headline cards, the stardust card, THESE FIT when stardust is set, and the full list with no SHOW ALL; a built row shows the Full strength badge and no " · Free".

Shared on every team screen
1.11 SUGGESTIONS · Available | Best · (i), default Available, one setting per screen.
1.12 A slot shows its role (Raids, Max, PvP), the Pokémon, its type icons and either the Full strength tick or the Upgrade available arrow.
1.13 Tapping a slot opens the picker under the team; choosing a row puts it in the slot and ticks it; a Pokémon already in another slot of the same team is not offered; the edited slot's own Pokémon is listed, ticked.
1.14 Changing a slot's role relabels it, refills it with the best unused Pokémon for the new role, and keeps a Pokémon the player chose if it fits the new role.
1.15 "Could get now (N) ›" lists S/A gaps for the slot that are attainable now, with where tags; it is open when the box has no option for the slot.
1.16 Under Available, a raid/Max/Gym/Rocket pick must keep its own species (power up only); a PvP pick must be the copy itself; the raid Mega slot is empty.
1.17 Every explanation of a weight or rule is behind an "i".

Raids
1.18 Now: one card per raid on now, first chosen on opening; the chosen card's squad shows below ("Your squad – Palkia", advice line, MEGA + HEAVY HITTER ×3 + BULKY HITTER ×2, "i", Set this team / ✓ Team set with Undo); tapping the chosen card again closes it.
1.19 Coming up: a list; a tapped row opens BRING, the squad and the picker; a set row is tinted in the accent.
1.20 A set raid card is filled in the accent; chosen and set shows a raid-ink ring.
1.21 BUILDS THAT CLOSE THE GAPS (top 3, All N) and the schedule link as before.

Max
1.22 As Raids' Coming up for Now and Coming up; squads of three: TANK, HEALER, ATTACKER; role chips Tank | Healer | Attacker | All. The roster and its notes are gone.

Gym
1.23 Top defenders: six slots, each replaceable; picker rows show DEF / HP and BULK; order is Gym tier, then bulk; "i" explains it.
1.24 TOP AVAILABLE (built rows with the badge, no "Free") and the gaps as before.

Rocket
1.25 Leader cards; YOUR TEAM FOR <LEADER> with Change leader; three slot cards with "beats k of n" (several options only) and "vs …".
1.26 Picker rows show type icons in colour when they hit the slot, grey otherwise; "Next best" (up to three) when nothing beats the slot.
1.27 GRUNTS: one row per grunt type: icon, word, quote, "beaten by" icons; a sideways strip of up to eight counters (first on the Rocket tint).

PvP
1.28 League switch; Suggested team LEAD, SAFE SWAP, CLOSER with coverage and "i"; weakness line; picker with role chips; scores and IV ranks graded top / good; OTHER CANDIDATES; the season foot line.

## 2. Rules checked against the code

Most of the new logic exists only in the design helper; the build moves it into PogoBox with tests. Exists = already in PogoBox at 5142d1d.

| Rule | Where it is today | Note |
|---|---|---|
| 1 Full strength | Exists: `HubTeams.isBuilt` (HubTeamsModel.swift:10) | Agrees with #15's fold (Dynamax step ignored). But Raids/Max already use a stricter `HubRaidsModel.isBuilt` (HubRaidsModel.swift:187: the covering Max build must be finished); the build uses that one on Raids and Max so the badge and the readiness bar agree. |
| 2 Cost beside arrow | Exists: `HubModel.costShort` | Split into value + currency is new UI. |
| 3 Available | Helper only (`asIs`) | Consistent with rule 1 and with #15's "unknown cost reads To build" for PvP. |
| 4 One slot at a time, 5 role change refill | Neither | New app-side logic; needs persistence (Q2). |
| 6 Could get now, where tags | Helper only, placeholder | Reads gap `obtain` text; one function so it can be redefined (D19). |
| 7 Type icons | Exists (`Theme.pokemonTypeText`, type colours) | Glyphs are new drawings. |
| 8-10 Raid roles, candidates, squad | Helper only | Uses `HubRaidsModel.typesCounted`. |
| 11 Now as cards | Neither (today a list) | New view. |
| 12 Max roles | Helper only | Reads the Max table's role text; depends on PR #20's corrected names, so build on top of #20. |
| 13-14 Gym order, bulk | Helper only | Helper assumes level 20 when the level is unknown, a 0.6 CPM fallback and HP ≥ 10, none of which the rule states (Q5). |
| 15 Built rows | Exists (`needsSomething`) | Badge in place of cost is new UI. |
| 16-19 Rocket picker, colours, Next best, grunt counters | Helper only, building on `HubTeams.gruntCounter` | Fine. |
| 20 Beaten by | Exists: `HubData.weaknesses` | |
| 21 Slot lines | Exists | |
| 22 PvP roles | Helper only | League tables carry role text; a candidate with none falls back to best unused. |
| 23 Suggested PvP team | Changes existing behaviour | Today `HubTeams.suggestedTeam` picks for type coverage; the new rule picks by role and shows coverage only (Q3). |
| 24 Grades | Bands exist (92/90); IV-rank grades new | |
| 25 Species count | Data supports it | 951 released species in the game master, verified. |
| 26 Showcase | Helper only | |

## 3. Gaps the design does not cover, with recommendations

Q1 Base branch: pass 2 rebuilds screens on #15. Recommended: wait until #9, #10, #15, #14 (and #20) merge, then build on `design/pass-2-hub` off main, as `docs/design-process.md` says. Alternative: stack on #15 now.
Q2 Where squads and picks are kept: recommended per account on the device (as stardust is), surviving re-scans; a raid/Max squad is dropped once its event ends; a pick whose copy leaves the box empties its slot and the slot refills with the suggestion; Available | Best per screen remembered.
Q3 PvP suggested team: recommended the new role-first rule (Lead, Safe swap, Closer), coverage shown not optimised. Alternative: keep picking for coverage and only label roles.
Q4 Word clashes from CONCEPTS: recommended rename SHOWCASE to "Best copies" (clashes with the game's PokéStop Showcases) and TOP AVAILABLE to "Gym builds"; "squad" for raid and Max titles, "team" elsewhere as designed.
Q5 Gym bulk when a copy's level is unknown: recommended rank it after copies with a known level and show "level not read", not assume level 20.
Q6 The same copy in two different teams (a raid squad and the Gym): recommended allowed (rule 4 is per team).
Q7 Dynamax: all Max picks read Upgrade available until the filtered pass marks Dynamax copies (planned, built after the stack merges). Accept as a known limit.
Q8 Build order: one commit per screen (Hub tab, Collection, Collection lists, shared components, Raids, Max, Gym, Rocket, PvP); phone one screen first or a batch is Greg's open choice.

Also needed: Greg's confirmation of CONCEPTS.md (the design session is asking).

## 4. Greg's answers (25 Oct 2026, ~23:00 AEDT, one-click)
- Q1: build after the stack merges (#9, #10, #14, #15, #20), on `design/pass-2-hub` off main.
- Q2: per account on the phone, as recommended (survives re-scans; a raid/Max squad dropped when its event ends; a pick whose copy leaves the box empties the slot and it refills with the suggestion; Available | Best remembered per screen).
- Q3: PvP suggested team by role (rule 23); coverage shown, not optimised.
- Q4: rename TOP AVAILABLE to "Gym builds"; "squad" everywhere instead of "team" (Set this squad / Squad set, Suggested squad, YOUR SQUAD FOR GIOVANNI, SQUADS AND COLLECTION); SHOWCASE keeps its name.
- Q5-Q7 not asked; the manager's recommendations stand unless Greg says otherwise: unknown-level Gym copies rank after known ones and read "level not read"; one copy may sit in teams on different screens; Max picks read Upgrade available until Dynamax marks exist.
- Q8 and CONCEPTS.md confirmation: with the design session.
