# Status — Pogo Assist+

**25 Oct 2026, branch `feat/pogo-hub` (PR 4 of 5, slice 3, stacked on `feat/league-ui-leagues-panel`, not merged): the Raids and Max battles screens.** `HubRaidsView` and `HubMaxView` replace the stopgap bodies for those two tiles (`HubTypeDestination`); Gym, Rocket and PvP keep theirs for slice 4. Both show a `Now | Coming up` switch (`hub-raids-segment`, `hub-max-segment`; it opens on Coming up when nothing is under way) over a timeline of the `hub.json` rotation rows, from today (`HubModel.today()`: the device's Gregorian day; a debug build honours `-uitest-today yyyy-mm-dd`) with past rows dropped. The timeline shows without advice (no bars or to-do until it is ready). The sub line is the last `to` of the screen's rows ("Bosses to 1 Dec", "Max Mondays and events to 30 Nov"). **Rules (`PogoBox/HubRaidsModel.swift`, pinned by `HubRaidsModelTests`; the tables are read through `PogoBox/TierTable.swift`, pinned by `TierTableTests`):** Raids list `5star`, `mega`, `shadow`, `battleday` (Super Mega Raid Days, chip BATTLE DAY) and `raidhour`; Max lists `maxmon` and `maxevent` (Dynamax Trails); rows sort by first day, then kind. A row is "now" when today is within its first to last day, both included; the date column reads "28 OCT – 3 NOV", "9 – 24 NOV" inside a month, "26 OCT" for one day, over "now" or "in N d" (spoken "28 October to 3 November, in 3 days"). **Bring:** the types that hit any boss of the row super-effectively (`HubData.weaknesses`), best multiplier across the bosses first, ties in the chart's order, at most four; none for a row with no boss. **A counter, Raids:** a built build (Raids area; nothing left but the Dynamax requirement; a build read without `steps` is NOT built, as in `HubModel.needsSomething`) counts for the attacking types its TARGET species is listed under in the Raids table (`pve-by-type`, tier S, A or B), not its own types: Kartana (Grass/Steel) is listed under Grass and Fighting, Lucario (Fighting/Steel) under Fighting only. A build that mega evolves also reads the target's Mega entries. A target with Raids entries but none sectioned by a type counts for its own species' types; a target the table does not list counts for nothing. **A counter, Max (as coded):** the Max table has no type sections, so each Dynamax-Yes COPY counts for the types of the species of its Max entry, and only when it is ready. The entry is chosen from the species' non-Gigantamax Max entries, best tier first (S, then A, then B; of equal tiers the first in the table) and the roster lists copies with an entry first by tier, then CP (a Gigantamax entry is never used, as in the advisor: Gengar has none, Kingler takes its A entry). A copy whose own species has such an entry is ready when the build covering it (as carrier or spare) with the Max area is finished, or when no build covers it at all (it is already at the table's target); an unfinished Max build, or a build covering it without the Max area, makes it "To build" and not ready. A copy with no entry of its own species reaches one through a Max-area build that covers it and whose target has an entry, and is ready once that build is finished. Copies marked No or not set count for nothing. In the Raids rule a Shadow entry listed under a plain id (Shadow Pheromosa) is credited only to a Shadow copy (`row.shadow` or a `_shadow` target). **Readiness:** counted bring types out of needed ("3 of 4 counters", "4 of 4 ready"; the bar and its text green when full, red at zero, else the type's ink). **To do:** "Ready."; else, for the FIRST missing type, the first unbuilt build of the area in the advisor's order that counts for it, worded with the Pokémon and its cost ("Power up Xurkitree to level 35 (137k dust)."; the power-up's area bracket is dropped); only when none counts for that type, the next missing type; on Max, a finished build with no Yes copy among its carrier, spares and species reads "Mark <name> as Dynamax on its page."; else "No <Type> counter in your box." (Raids) or "No <Type> Max attacker marked Dynamax." (Max); a to-be-announced row "Boss not announced yet."; a row with no boss otherwise shows its note. **Builds that close the gaps** (Raids): the unbuilt builds of the area that count for a type the rows on show ask for, the top 3 with `All N` (`hub-raids-all`), then "Full schedule on pokemongo.com ›". **Max roster:** the copies marked Dynamax Yes; each tile reads the Max entry's tier and role ("S · Tank and healer"; the section for an attacker) with "Built" or "To build" by the same rule as ready (Built only when the build covering the copy, as carrier or spare, with the Max area is finished, or when no build covers it at all; an unfinished Max build, or a build covering it without the Max area, reads To build), or "No Max use in the tables"; entries first (best tier, then CP). "N Pokémon not set" counts unset copies that have a Max entry. The footnote says the bar counts the copies you have marked. Slice 4's Gym role can read the same `TierTable` (`gym`/`defence` entries) later. **Accessibility:** a row is one element (label: dates in words, name, kind, counters with the bring types in words, to-do); at accessibility text sizes the date sits above the name and the counters wrap. **Verified on the Mac (greg-mb-16, Xcode 27.1):** `npm test` 275 tests, 271 pass, 4 skipped, 0 fail; `swift test` in `native/PogoReader` 804 PogoBox tests (26 in `HubRaidsModelTests` and `TierTableTests`), 0 failures (6 skipped); PogoAssist builds for the generic iOS Simulator; `HubRaidsMaxTests/testRaidsTimeline` (both segments, the row labels, the gap-closer header, light, dark and AX3) and `testMaxRosterFollowsTheSwitch` (a Max timeline row, Now empty, Dynamax Yes on the first Pokémon, the roster) on the iPhone 17 simulator, with `-uitest-today 2026-10-25` so they do not depend on the day. **Product notes for Greg:** (1) the advisor picks a build's carrier by score without regard to the Dynamax flag, so a Yes copy that is only a spare counts once the carrier's build is done; the proper fix is in the advisor. (2) A Mega counter never fills a readiness bar: the `megaEvolve` step is never known to be done, because an export cannot show Mega state. **Not verified:** a real iPhone or iPad; VoiceOver; `HubView`'s events strip still reads the clock (slice 2's file; `HubModel.dayKey` is being fixed to a Gregorian calendar on the slice-2 branch, and `HubView` should call `HubModel.today()`). `project.pbxproj` was regenerated with xcodegen, so slice 4's new files will conflict there; regenerate on merge. The advisor's `steps` arrived with advice cache version 7. The review gate is passed: after two NEEDS-FIX rounds, a paired confirmation round on 25 Oct (Opus; Sol via the Codex wrapper) found the remaining defects listed above, they were folded in 6ac0f56, and a paired re-check of that fold returned CONFIRMED-OK from both. The STATUS-only edits after it are not reviewed. Known wrong for now: split Gigantamax rows lose their prefix in `data/tiers.json`, so the Max figures for Toxtricity, Lapras, Grimmsnarl and the other split Gigantamax rows are wrong until the fix on `fix/tiers-gmax-split` reaches this branch.

**25 Oct 2026, branch `feat/pogo-hub` (PR 4 of 5, slice 4, stacked on `feat/league-ui-leagues-panel`, not merged): the Gym battles, Team Rocket and PvP leagues screens.** Three screens replace their stopgap bodies (`HubGymView`, `HubRocketView`, `HubPvPView`; the type dispatcher routes to them). Their rules are in `PogoBox/HubTeamsModel.swift`, pinned by `HubTeamsModelTests` (20 tests). **Slot pickers deferred (manager call):** the design's tap-a-slot picker and saved assignments are not built; every team is a read-only suggestion the app works out, and the slot tiles do not respond to taps. **Built** means a build whose `steps` is nil or holds only `needsDynamaxCopy`. **Gym:** `Top defenders` are the six best built Gym builds (S, A, B, then score, one per species); an empty slot names an unbuilt Gym build ("Power up Lapras"), then a Gym gap ("Catch Snorlax"), a different one per empty slot; `TOP AVAILABLE` lists every Gym build in advisor order, then the Gym gaps. **Rocket:** a slot's counter is the build with the Rocket or Raids area that beats the most of the slot's options (a type super-effective against one of its types), then built before unbuilt, then the Rocket area, tier, score; the tile says what it beats ("beats all 3", "beats Machamp only") and a build still to do reads "gap: mega evolve Lucario". A copy (entry id) serves one slot of a leader's team; two copies of one species may serve two. A slot nothing in the box fills gets the first S or A gap (Rocket area first) that would beat one of its options, else "—". A grunt's counter is the best built build whose target type beats the grunt's type (Rocket area first), else the best unbuilt one ("Normal · mega evolve Lucario"), else the first S or A gap with such a type ("Fire · gap: Swampert"), else "—"; the two typeless grunts show "any strong attacker". The label line of a grunt tile is its type in quotes ("NORMAL", "MIXED TEAM"); the quote is in the accessibility label. A gap's species comes from its `speciesId` (new optional field on `BoxAdvice.Gap`, which the engine already sent; an advice cached before decodes it as nil and the name is used; no version bump), so a Mega gap uses its own types. **PvP:** a candidate is each copy's shown option (the Classic or Pogo Assist pick, following the ranking switch) that is not over the cap and scores 80 or more (the design lists candidates down to 68.9; 88, the advisor's `PVP_SCORE`, left teams short); the tier chip is S 92, A 90, B 88 and none below 88 (the bands are named once in `HubTeams`); one per species (the best copy), best score then IV rank. A member reads "Built" when it is the copy itself with no dust, candy or XL candy left in its own league cost and no move to learn (`needs`), else "To build" (orange, dashed tile; an evolution is always To build); this reads the option's own league data, not the advisor's builds (a copy with no build, under the advisor's 88 floor or a spare, still reads To build when it has dust left; an unknown cost, meaning the IVs or the level were not read, reads To build, and unknown moves do not block Built); a sex-locked member reads "Gallade, if it is male". The team is the top candidate then, twice, the candidate covering the most types not yet covered (ties: score); coverage counts the 18 types some member's type beats; the note names types that beat two or more members (none for a team of one), and a swap sentence only when a candidate outside the team raises coverage by taking the place of the lowest-scored non-lead member (the candidate raising it most). Season line: the first `GO Battle League` event in `hub.json` that has not ended. The three-column grids go to one column at accessibility text sizes (not looked at). **Overlap with slice 3 (merge):** both slices touch `HubTypeScreen.swift` (the type dispatcher), `PogoAssist.xcodeproj/project.pbxproj` (regenerate with xcodegen) and `STATUS.md` (each adds its own top entry); everything else in this slice is in new files. **Differences from the brief, on purpose:** the leader card line drops the "Shadow" prefix (every Rocket Pokémon is one); a leader's `since` is month-only in the data, so the cards read "SINCE OCT 2026"; `OTHER CANDIDATES` shows five, with `All N` for the rest, only when there are more than five. `PogoAssist.xcodeproj` regenerated with xcodegen. **Verified on the Mac (greg-mb-16, Xcode 27.1):** `npm test` 275 tests, 271 pass, 4 skipped, 0 fail; `swift test` in `native/PogoReader` all pass (0 failures); PogoAssist builds for the generic iOS Simulator; `HubTeamsTests/testGymRocketPvPScreens` passed on the iPhone 17 simulator (Gym slots and TOP AVAILABLE; Rocket: leader cards, Giovanni slot 1 reads Lucario and slot 2 Zamazenta (Crowned Shield), Change leader to Sierra changes slot 1, the Normal grunt tile; PvP: Ultra shows a team, coverage and one OTHER CANDIDATES row that opens the Pokémon page, Great shows no candidate, Master: slot 2's label names Zamazenta and slot 3's reads empty; Rocket in dark), screenshots looked at. The UI test failed three times in the sample-scan setup under machine load (a 30 s main-thread stall before the Hub was reached) and passed on the next run. **Not verified:** the `All N` toggle (the sample scan has one other candidate in Ultra, none in Great or Master); accessibility text sizes and VoiceOver; PvP and Gym in dark; a real iPhone or iPad. Confirmation fold verification (no code changes): `npm test` 275 tests, 271 pass, 4 skipped, 0 fail; `swift test` 804 executed, 6 skipped, 0 failures; the PogoAssist build and `HubTeamsTests/testGymRocketPvPScreens` passed on a simulator clone (25 Oct 2026, this Mac). The review gate is passed: after two NEEDS-FIX rounds, a paired confirmation round on 25 Oct (Opus; Sol via the Codex wrapper) found the remaining defects listed above, they were folded in 6ac0f56, and a paired re-check of that fold returned CONFIRMED-OK from both. The STATUS-only edits after it are not reviewed.

**25 Oct 2026, branch `feat/pogo-hub` (PR 4 of 5, slice 2, stacked on `feat/league-ui-leagues-panel`, not merged): the Pogo Hub tab and the Everything screen.** The second tab is now "Pogo Hub" (SF Symbol `line.3.horizontal`, `AppTab.next` kept; the FlowTests' one tap and two assertions and the tab-bar label assertion say "Pogo Hub". The nine "Next" taps in `ScanScreensTests` are on the scan guide's own Next button, not the tab, and stay "Next"). `HubView` replaces `NextView` (deleted): the account name centred in the accent ink (the account menu) with the More circle; `HAPPENING IN POKÉMON GO` with `All news ›` (https://pokemongo.com/news) and a card strip of the `hub.json` events (at accessibility text sizes the cards stack full width and nothing is cut off) whose last day is today or later (device-local day), sorted by first day, kicker "1 – 5 NOV" / "21 NOV" / "NOW TO 1 DEC", a tie shows `See raid/PvP/Max/gym/Rocket picks` and pushes that screen; `WHAT NEXT` with the ranking switch (`hub-ranking`) and its "i"; six tiles (`hub-tile-<type>`) with the build count for the area (Everything = all builds; none shown until the advice is ready). SF Symbols: everything `line.3.horizontal`, raids `diamond`, gym `building.columns`, rocket `sparkle`, pvp `figure.fencing`, max `sparkles` (all iOS 17 or earlier by the system's own availability table; the stardust disc uses `sparkle`). `HubTypeScreen` is the shared chrome (tab bar hidden, back circle, title, "N builds" chip) with `HubHeaderLine`, `HubBuildList`, `TierChip` and `HubGapList`; the five type screens not yet built (Raids, Gym, Rocket, PvP, Max) show `THESE BUILDS` and the area's gaps so the tiles lead somewhere; slices 3 and 4 replace their bodies. **Everything:** `DO FIRST`, `CHEAP WIN` and `WORTH SAVING FOR` cards; the stardust card (per account, `Change` opens an alert with a number field, empty clears); `THESE FIT`; `SHOW ALL N ›` opens every build, then the gaps and duplicates the old Next list ended with. **Rules (`PogoBox/HubModel.swift`, pinned on the fixture report by `HubModelTests`):** a tile counts the builds whose areas include the type (PvP = GL, UL or ML); `fitting` takes builds in the advisor's order while the running dust stays within the stardust, the first build that does not fit ends dust spending (a cheaper one further down does not jump the queue), and a build that needs no dust still fits (an evolve paid in candy), and a build with nothing left to do (already built, or only a Dynamax copy missing) is not listed; `doFirst` is the first build that has something to do; `cheapWin` is the lowest-dust (then candy, then advisor order) S or A build that is not `doFirst` and has a step other than the Dynamax requirement; `worthSavingFor` is the highest-score build that costs more dust than is on hand (without a stardust figure, the highest-dust S build) and is neither of the others. **Card colours (rule, fold of the paired review):** a Hub card, and a highlighted rank disc, is one fixed colour in both modes: the type's light-mode ink (`ContentType.solid`, `League.solid`, `Accent.inkLight`) under white text, a gradient towards black in light mode and the plain solid in dark mode. Contrast of white on each: raids B34D00 5.28, gym 1C7A3E 5.38, rocket 2A3042 13.13, PvP and Master 7A2FB5 7.24, Max 5B3FD6 6.72, Great 1F5FD1 5.81; the accent's light ink: blue 6.78, indigo 10.81, sky 6.04, teal 5.64, forest 8.88, berry 6.49, plum 9.74, graphite 13.13. The first build washed the dark card with 30% of the pale dark-mode ink and used that ink for the text, which fell to 4.2 to 4.5:1 for several colours. The card's pill is black at 22% (white text 7.6:1 or better): the design's white at 22% leaves white text at 3.5 to 4.5:1 on raids, gym, Great, Ultra, sky, teal, blue, berry, Max and PvP/Master. The old Next list's per-row CP, IV and spare lines are not in the new list (they are on the Pokémon page), and the 40-row cap is gone. The duplicates list's "Keep" lines will need the Dynamax-extra marker once slice 1's `dynamaxExtras` merges (left to the merge). A bad stardust entry (more than nine digits, or not a number) shows a red line under the card and changes nothing; an empty entry clears it. **Verified on the Mac (greg-mb-16, Xcode 27.1):** `npm test` 256 tests, 252 pass, 4 skipped, 0 fail; `swift test` in `native/PogoReader` 751 PogoBox tests (739 + 12 in `HubModelTests`), 0 failures (6 skipped); PogoAssist builds for the generic iOS Simulator; on the iPhone 17 simulator `HubScreensTests/testHubTilesAndEverything` (tiles and counts on all six, the stardust card Not set, a ten-digit entry rejected with the red line, then 100,000 kept across a dark and an AX1 relaunch, `THESE FIT` with a dust figure, `SHOW ALL <n> ›` matching the count, the GAPS header, screenshots looked at), `ScanScreensTests/testMoreAboutScanningAndPaging` (the guide's Next button; it failed once at the Eggs field of the options panel on the same final code and passed on the re-run: a flaky run, not a fix) and `FlowTests/testWholeFlow` (taps the Pogo Hub tab) all passed. The other FlowTests and ScanScreensTests tests were not run. A Menu in a hidden tab stays reachable by accessibility, so the header menus of both the Hub and the Box are only built while their tab is showing (`active:`); before, "More" matched twice. **Not verified:** on a real iPhone or iPad; VoiceOver; contrast measured by eye and by the token values, not by a tool; the five type screens beyond their stopgap bodies. Paired review (Opus + Sol): round 1 both NEEDS-FIX (the scan-guide taps, dark contrast, fit rules); round 2 confirmation CONFIRMED-OK on the code and tests (the black 22% pill kept: white at 22% fails 4.5:1 on ten colours); passed. Merged into feat/pogo-hub with IconButton's identifier applied only when given (a reviewer's safety note).

**25 Oct 2026, branch `feat/pogo-hub` (PR 4 of 5, slice 1, stacked on `feat/league-ui-leagues-panel`, not merged): hub reference data and the per-copy Dynamax flag.** Slice 1 of the Pogo Hub: the data the Hub screens will read and the one flag they need from the player. No Hub screen exists yet. **Data:** `data/source/10-hub-rotation.md` (22 rotation rows, raids and Max battles only: 5-star, Mega and Shadow raids, Max Mondays, the two Super Mega Raid Days (kind `battleday`, shown with the raids), Dynamax Trails (kind `maxevent`, no boss cell), four Raid Hours; kinds `5star`, `mega`, `shadow`, `maxmon`, `maxevent`, `battleday`, `raidhour`; a row whose boss is "to be announced" (the 16 Nov Max Monday, the 28 Nov Super Mega Raid Day) gets `tba: true` and no species), and 11 events-strip rows (Community Days, the November events, Dynamax Trails, the GBL season with its cup schedule worded as the research gives it) with a `tie` of everything, raids, gym, rocket, pvp, max or empty. The seasonal events and Community Days are in the strip only. `11-rocket-lineups.md`: Giovanni, Sierra, Cliff and Arlo as read from leekduck.com/rocket-lineups on 25 Oct 2026 (the page says updated 2 Oct 2026; it showed Sierra slot 2 + Ferrothorn and slot 3 + Steelix, Cliff slot 2 + Galarian Weezing and slot 3 + Camerupt and Gallade, Arlo slot 2 + Golurk, so those are in), all four `since` "2026-10" because no source gives the takeover start (the 4 Oct date came from the design handoff's mock, "Lineups since the 4 Oct Takeover", and no source supports it); 18 typed grunt quotes, where the Normal grunt says "Normal does not mean weak." (the research had given the generic grunt's "Winning is for winners" for it), and two typeless grunt rows (empty type, a `label`): "Mixed team" (the generic grunt) and "Decoy". `12-type-chart.md`: the game's 18 by 18 chart (1.6, 0.625, 0.390625). Every row cites its source. `npm run build:hub` (`scripts/build-hub.mjs`) resolves every Pokémon through `resolveSpecies` and writes `data/hub.json`. It exits 1, naming the cell, on: a name that does not resolve; a name that does not match its species word for word (a guess, a repeated or extra word); a Mega name that does not end on a Mega id; a row with the wrong number of cells; an unknown kind or tie; a raid, Max Monday or Super Mega Raid Day row with no boss and no "to be announced"; an empty title; a bad date or `from` after `to`; a grunt type that is not one of the 18 (or a typeless grunt with no label); a chart cell that is not one of the four multipliers. A Shadow the game master does not list yet keeps its name and gets `shadow: true` on the boss. A leader's `since` is `yyyy-mm-dd`, or `yyyy-mm` when only the month is published. `hub.json` ships in `PogoBox/Resources`; `PogoBox/HubData.swift` decodes it (`HubData.bundled()`; a rotation kind it does not know decodes as `.other`) and answers `weaknesses(of:)` (more than 1.0 only, strongest first, ties in the chart's type order) and `effectiveness(_:against:)`. **Dynamax flag:** `ScanRow.dynamax: Bool?` (nil = unknown, not written when nil, so every stored box and reader output decodes as before); set only by hand from the facts panel's "Dynamax" row on the Pokémon page (Not set | Yes | No, identifier `dynamax-switch`; the row is hidden while the page shows the Mega form), through `BoxMerge.Edit(dynamax: BoxMerge.DynamaxEdit?)`. A change is a new box version noted "Dynamax set for <name>" but not a correction (no "was" is kept); choosing the value already set saves nothing. A re-scan merge keeps the saved value (`BoxMerge.updated` copies it from the saved row), and joining a Mega pair keeps the base entry's value or takes the removed entry's when the base has none. "Read again" lists a Dynamax change among the edits made after the scan ("Corrected or set by hand"). The Advice panel words a copy kept only for being marked Dynamax as "it is marked as caught as a Dynamax" (hygiene reports `dynamaxExtras` when it adds such keeps, and the IV wording counts only the IV-ranked keeps). Two quick taps on the switch save once. It is not in `ReviewEntry`, the CSV or the readers. The advisor gets it by `CoreEngine.advise(rows:)` setting `dynamax` on the imported records by Index before `advise(box:)`, since the CSV has no column for it. `src/advise.js`: **Yes** adds no `needsDynamaxCopy` step (the Max hits say `needsDynamax` false, and so does the build) and hygiene never puts the copy in `transfer` (it is an extra `keep`, so the keep list can be longer than usual); **No** credits no Max-area hit to the copy and the copy does not count as covering a Max entry in the gaps (with every Chansey marked No, Blissey's Max entry is a gap); unset is as before. For Greg: the build carrier is still chosen by score, so a Yes copy that is not the carrier of its build still shows the carrier's "needs a Dynamax copy" step. The fixture report is unchanged (`scripts/advise.mjs` output byte-identical to the one from b86d846, and the whole `analyseBox` result for the fixture box identical as JSON, 1,697,377 bytes). `pogo-core.js` rebuilt; `BoxAdvice.currentVersion` stays 9 (the bridge shape is unchanged). `AppModel.stardust` (`stardust.<account>` in UserDefaults, moved on an account rename by `moveAccountKeys`) exists for slice 2; no screen uses it yet. **Verified on the Mac (greg-mb-16, Xcode 27.1):** `npm test` 274 tests, 270 pass, 4 skipped, 0 fail (baseline 247); `swift test` in `native/PogoReader` 179 + 65 + 743, 0 failures (1 + 6 skipped); PogoAssist, PogoBroadcast and PogoShare build for the generic iOS Simulator; `BoxScreensTests/testDynamaxSwitchOnThePokemonPage` passed on the iPhone 17 simulator (it starts at Not set; Yes is still set after leaving the page and reopening it). **Not verified:** on a real iPhone or iPad, and in dark mode or at large text sizes (the Dynamax row wraps its switch under the label in a `ViewThatFits`, checked by the build only). Paired review (Opus + Sol): three rounds, the last confirming the fold; passed. The bundle header names 4741da7 (the Swift-only commit after the engine change; the JavaScript is identical).

**23 Oct 2026, branch `feat/league-ui-leagues-panel` (PR 2 of 5 of the design handover, stacked on the PR 1 branch, not merged): the Pokémon page.** New Leagues panel (pick cards, league view with the option list, the app-wide ranking switch choosing `pick` or `experimental`), the game search as a chip beside the CP line, a Settings circle in the header, three PvP IV figures in the IVs panel, the Shadow footnote only while `ScanRow.shadow` is nil. Its logic is `PogoBox/LeaguePanel.swift` (replaces `LeagueText`), pinned by `LeaguePanelTests`. `leaguesFor` now keeps `moves` on every option PvPoke ranks; advice cache version 9; `pogo-core.js` rebuilt. The review gate is not passed; not verified on a device.

**20 Oct 2026: screenshot import (branch `feat/screenshot-import-fold`, on `feat/screenshot-import`, not merged).** Quick import of Pokémon GO appraisal screenshots, from the app (system photo picker) and from
Photos (Share > Pogo Assist+), each read once, merged as a partial Add and update and saved as source "screenshot import". Design, rules and limits: `native/README.md`, "Screenshot import". The latest reviews (of the ledger-cap fold) were Opus "ship after fixes" and Sol "do not ship" on small items, which this fold addresses; account-name hardening is deliberately on hold (see the known limits below). **The review gate is not passed.** Verified on the Mac (greg-mb-16, Xcode 27.1): `swift test` in `native/PogoReader`
179 + 65 + 707, 0 failures (1 + 6 skipped); `npm test` 244 tests, 240 pass, 4 skipped (the recordings are not in that checkout), 0 fail; the app builds unsigned with the extension; the picker flow
(`ScreenshotImportTests`) passed in the iPhone 17 simulator. Not verified: the Share extension running (it needs a signed build, the `com.dare33.pogoassist.share` App ID and the App Group), the new app
glue beyond what the simulator test touches (backgrounding, the sheet opening by itself), and anything on a real iPhone or iPad.
**Known limits (screenshot import):** account identity is by name, so renaming an account and then creating a new one with the old name while screenshots are queued can leave holds counted for neither account or ask
which box; stable account IDs (`docs/stable-account-ids-plan.md` on `claude/great-moore-21a56d`) are the planned fix, separate work awaiting Greg's approval. A share queued before a rename-and-reuse of an account's name can be filed into the new account without asking, and after "Start a new import record" re-shared screenshots are not held. The Share extension has not run on a device. The app glue
(sheet, background pause and resume, auto-opening) is tested only by the build and the simulator picker flow.

**20 Oct 2026, branch `feat/league-options` (merged in PR #7): league options.** `leaguesFor` (`src/leagues.js`) now returns, per league,
every allowed family member (PvPoke-ranked or not, form changes such as Zygarde included) as `options`, each rated for the copy
(PvPoke rank and score, IV rank, cost; moves only on the shown and experimental options), plus `pick` (index of the member to SHOW),
`experimental` (index of the other rule's member) and `source` (`export`, `emulated`, `ranked`, or `fallback`: the PvPoke-score rule ran (Master League, or unknown IVs) but none of the members it may show is ranked here: either nothing in the family is ranked, or every ranked member is past the cap. The shown member is then the final evolution if it fits, else the first option that fits, which is an unranked one (a level-50 Bulbasaur with unknown IVs shows Ivysaur in Ultra League). If no member fits and nothing is ranked, the final evolution is shown even though it is over the cap. A copy with known IVs in Great or Ultra League and nothing ranked is still `emulated`). The shown pick copies Poke Genie: its own pick from the export when the entry has one and it is in the
family. Otherwise, in Great and Ultra League, `pokeGeniePick`, a PROVISIONAL emulation (best stat product % among the members the
copy is not already too strong for, ranked ones first). Master League has no Poke Genie pick to copy and the emulation there only
followed ~0.07% stat-product noise (Eevee showed Glaceon, Scyther Kleavor over Scizor, Shaymin Land over Sky), so Master League
shows the highest PvPoke score, as `main` does (Greg's decision, 20 Oct). Without reading the export's pick the emulation matches
Poke Genie on 272/280 Great and 300/306 Ultra fixture rows (the 278/304 seen in the cost checks are the rows with an exact level, a
different count). Those figures are IN-SAMPLE, on one fixture (the data it was fitted on), and the test floors are regression pins,
not evidence it generalises. The misses are not only near-ties where Poke Genie prefers the later evolution: Crocalor stays Crocalor
where Poke Genie picks Skeledirge, and Magmar becomes Magmortar where Poke Genie keeps Magmar. The earlier idea, species strength
first with a `CLOSE_SCORE` (3.0) window decided by IV Rank %, is kept as `chooseMember`, computed in the background and not shown
(250/280 Great, 296/306 Ultra against Poke Genie, same caveat); `experimental` is never a member the copy is already past the cap
for, unless every member is (then it is the shown pick). Greg swaps the shown pick to it once it is provably better. Both rules and
the threshold sit together at the top of `src/leagues.js`. The advisor rates league builds from the build target's own option
(scans have no Poke Genie columns); a league where the copy is already past the cap as the target is not an area of that build, and
a build left with no area is dropped; "past the cap" means the copy's CP at its current level (0/0/0 if its IVs are unknown) is over it, so a level-51 Best Buddy copy that still fits stays. A level-35 Rookidee no longer outranks a usable level-5 one for Corviknight. Master League
keeps its neutral 0.6 weight and is never the cost league. XL candy now counts towards a build's effort for GL and UL (the league cost carries it; before, it was taken as 0). The display for the league options is being designed separately: the Leagues
section still shows the shown pick only. What DID change on screen and in the exports is the wording of each build: every build now carries
`steps`, the list of things still to do (evolve or form change, Mega evolve, one power-up step, second move, Elite TM, Community Day move,
and the Max-only "needs a Dynamax copy"), and its action, the web table, `scripts/advise.mjs`, the Pokémon page and the export's Advice
column all word it from that list ("Evolve to Annihilape + Power up to level 16 (GL)"). The power-up step is exactly the climb the shown
cost pays for: a league-only build climbs to the cost league's best level, any other build to its highest non-league target level (areas
tied on it are all named, "(Gym/Max)"); another league's best level is never a step, only a note when the climb goes past it ("going past
27 leaves UL"). "Already built" means nothing is left; a Dynamax requirement belongs to the Max area alone, so it reads "Already built (Max
needs a Dynamax copy)" when that is all (a build for Max alone reads "Needs a Dynamax copy"). The second charged move is a step (and charged) unless the copy's second charged slot is already
unlocked (Poke Genie's Charge Move 2 is filled; kept by position as `chargedMoves`); a scan records no moves, so it reads "Second move (if
it doesn't have it)" and is still charged, as before. Elite TM and Community Day move steps are dropped when the recorded moves already hold
the move, and Elite TMs are counted by distinct move name in the step text. The fixture records moves for one Pokémon only (a Mareep whose
second charged slot is empty), so scores, costs and order are byte-identical to 7c43c85 on the fixture and 11 variants. A spare reads "spare
for the X build". The app decodes the data (`BoxAdvice.LeagueRating`, `Build.steps`; advice cache version 8). Not verified on a device.

**Known limits / follow-up (league options branch; not changed here, scores must stay as they are).**
- Costing is single-area: a build is costed to ONE target (the league's best level for a league-only build, else the highest non-league
  target), so a league whose best level is above that target is not paid for, and the cost does not reach other leagues (they appear only
  as the "going past N leaves X" note).
- The effort figure counts Elite TMs by mentions in the tier tables (`(Elite)` markers across entries), so one Elite move named in several
  entries counts more than once; the step text counts distinct moves. Fix together with the costing above, then re-check the order.
- Community Day and Elite flags come from the tier tables' text, not from the game data; a table entry that names them differently is missed.
- The second-move charge is a flat third-move cost; a copy with an unlocked slot may still need a TM for the recommended move (no step for that).
- Master League has no cap and no per-league cost from `leaguesFor`: it keeps a neutral quality weight (0.6) and is never the `pvpCost`
  league or a "going past N leaves X" note. A build for Master League ALONE is costed like a non-league one, to the table's level 50
  (e.g. a level-30 Lugia: "L30 → 50 (ML)", 500k dust); with other areas it follows their target.
- Behaviour that DOES differ from `main` and from 7c43c85 on exports that record moves: a copy whose Charge Move 2 (second charged slot) is
  filled is no longer charged the third-move cost and has no "Second move" step (intended: the slot is unlocked). Probe: a level-40
  Charizard (Rocket, Raids) scores 9.73 and costs 10,000 dust with no recorded moves, and 13.23 and 0 dust with both charged slots filled.
  The fixture and its 11 variants (levels, Shadow/Lucky/Purified, no level, no moves, other moves) are byte-identical to 7c43c85, because
  the fixture records moves for one Pokémon only and not a second charged slot.
- Not verified on a device: the app's screens with the new wording.

**20 Oct 2026: where it stands (handover).** `main` now holds everything: the iPhone app (`native/`, v1.0 build 3,
merged from `native-ui-v1` in PR #2), the shared JavaScript changes (extractor read fixes, CP recovery, PvP leagues,
CP multipliers, shadow/purified/lucky cost rounding, refreshed PvPoke rankings of 10 Oct), the Pages CI fix (PR #1:
the workflow now runs `npm ci`; the public page had not deployed since 25 Sep and deploys again) and the app review
fold (PR #3). App and engine detail: `native/README.md` (the "App fold" section covers PR #3).

- **Verified 19-20 Oct on greg-mb-16 (macOS 26.6, Xcode 27.1, Node 26):** `npm test` 198 pass, 1 skipped (Windows-only),
  0 fail, with the recordings present; `swift test` in `native/PogoReader` 166 + 578, 0 failures (with the real-data
  checks on: `POGO_PARITY=1 POGO_DEVICE_RUNS=~/Developer/personal/pogo-frames/device-runs`); the app builds signed and
  unsigned. The live page (https://dare33.github.io/pogo-assist-plus/) loads with no errors and shows the 10 Oct rankings.
- **Review:** every merge went through an Opus and a Sol (Codex) review; PR #3 took five rounds. Its stated limits and
  remaining findings are in the PR #3 description and the README's "App fold" known limits.
- **Not verified anywhere:** the app's own screens and flows after PR #3 (no simulator on this Mac; the app target has no
  unit tests). Before the next TestFlight upload, on a phone: finish a scan, kill the app, reopen; start a second scan
  while one waits; rename an account; re-scan from the Box; check the "Try again" explanation shows over the review screen.

**Open decisions and checks (Greg):**
1. **Report upload: settled 20 Oct.** The TestFlight builds include it ("Make scans better" shows) and use a publishable key
   (all four signing files on greg-mac-14 checked by Greg). The app's privacy manifest declares what a report sends from
   build 4 on (PR #5: Gameplay Content, Other Diagnostic Data, Performance Data, Product Interaction, Other User Content;
   not linked, no tracking) and App Store Connect's App Privacy answers match (Greg, 20 Oct). Not checked: that the
   Supabase `scan-reports` bucket allows uploads only (no read or list with that key).
2. **Build 3 is in App Store Connect** (Greg, 20 Oct). The next upload is build 4 (`project.yml`), after the phone checks above.
3. **Stable account IDs:** plan written, not approved: `docs/stable-account-ids-plan.md` on local branch
   `claude/great-moore-21a56d` (commit 1b276fb, not pushed), with 10 open decisions at its top. Accounts are identified by
   name today, which is why rename needed a journal and why reusing an old account name can misfile a scan.
4. **Hand-paged scans** fold two Pokémon with the same CP and HP but different IVs into one `ivs-disagree` row (rule from
   bf12a12; the Darentas Fidough 768 / 89 pair is the known case). Keep, or split when each bar state clearly holds?
5. **`native-fast-reader`:** an unadopted faster Vision mode, kept unmerged. Merged branches on GitHub can be deleted.

**Setting up a machine:** `npm ci` (Node 20+); Xcode with `sudo xcodebuild -runFirstLaunch`; `brew install xcodegen ffmpeg`;
sign in to the Apple developer account in Xcode and copy `native/PogoAssist/Config/Signing.local.xcconfig.example` to
`Signing.local.xcconfig` with the team id (git-ignored); recordings from Google Drive `F. Hobbies & Gaming/Pogo Assist
recordings/tests/` into `recordings/`; the device logs and frames (`pogo-frames`, about 19 GB, copied from Mac to Mac) into
`~/Developer/personal/pogo-frames`. Signed builds ask for the keychain: answer Always Allow once.

**2 Oct 2026: proof 2, the live-read prototype** (history; the app grew from it and is merged, see above).
`native/` holds a Swift package with the appraisal-screen reader ported from `src/extract/` on
`extractor-read-faults` (Apple Vision for the text), a live grouper, an Xcode project with the app
and a ReplayKit broadcast extension, Mac tools and comparison scripts; see `native/README.md`.
**Verified (MacBook, Xcode 26.6, commit 52c415d):** 110 Swift tests pass; the app and extension
compile for the iOS simulator unsigned. Against the JavaScript reader on the same 5 fps frames
(Swift at 750 px through 420 pixel buffers, both through the JavaScript grouping, measured at
e4ab948): darentas parts 1 to 3 agree on name and CP for 445 of 448, 767 of 779 and 144 of 147
JavaScript rows; v3 109 of 110; pogo-test-fast 21 of 21; marathon-phone 42 of 45.
**Not verified:** anything on a device. Mac peak footprint with Vision is 150 to 165 MB against
the extension's limit of about 50 MB; whether iOS charges the extension the same is unknown.
**Review:** three rounds (Opus-tier reviewer and Sol-tier cross-vendor); the last found no
blocker for a first device run but timing flaws in the swipe detection, folded in 7dfb20a and
addc6ef; a fourth round on 4898acc found the extension sound and the live grouper not; the grouper pass that followed (7b2c7cc, 6a9d29d) is NOT reviewed. **The review gate is not passed.** `npm test` on the Mac: 129 pass,
4 skipped, 1 fails (a Windows path assertion in `test/node/ffmpeg.test.js`).

**30 Sep 2026: batch mode for a whole box.** `node scripts/extract-box.mjs <folder>` (or drag the
folder onto `extract-box.cmd`) reads every clip in an account folder, drops the Pokémon repeated at
clip joins, marks the Shadow column from a `shadow`-named clip, and writes one Poke Genie-layout
CSV plus a review JSON (optionally copied to an inbox). ffmpeg is found automatically (PATH,
winget, imageio-ffmpeg). Per-clip results are cached beside the clips. The browser page takes
several clips and merges them the same way. Protocol and summary lines: `docs/whole-box.md`.
New modules: `src/extract/batch.js` (pure merge), `src/node/ffmpeg.js`, `src/node/extract-video.js`.
Tests: 123 passing, 3 skipped (`npm test`, after the three review folds below).

**Verified (30 Sep, Windows, Node 24, ffmpeg found as imageio-ffmpeg with no `FFMPEG` set):**
three clips (trimmed, original, trimmed again named `03-shadow-trimmed.mp4`) in one folder gave
48 rows: 4 boundary duplicates dropped at 01 to 02, shadow pass 4 matched, 0 appended, 0
ambiguous, and exactly those four rows (Mewtwo 3673, Xurkitree 3028, Zamazenta 2692, Zamazenta
2651) have Shadow/Purified = 1. Running `02-original.mp4` alone gives the same 48 rows. A second
run reported all three clips `cached` and wrote a byte-identical CSV (same SHA-256); running on the parent folder
processed the `dare33` subfolder as the account; the 30 Sep claim that `extract-box.cmd` ran with
arguments is withdrawn: argument-driven launches were broken until the 1 Oct fold below; `scripts/extract.mjs` on one clip still gives its 4 rows.

**Review fold (30 Sep, same day).** Two adversarial reviews (Opus reviewer: mergeable with fixes; Sol 5.6
cross-vendor: not mergeable) agreed on the substance; all of it was folded. Found and fixed: the
cache ignored code and data changes (now keyed on the extractor and stores raw readings, rows rebuilt
every run); the "same Pokémon" leniency was dead code because resolved rows carry no ivConfidence
(now judged from flags); the overlap took the largest consistent k and could swallow real identical
Pokémon (now the smallest, weak joins flagged `boundary-weak` and listed by name and CP); weak
shadow matches flagged `shadow-match-weak`; stale flags after merging rows; a partial run could
overwrite the complete export and reach the inbox (now `.partial` files, no inbox copy); ffmpeg
was required even for an all-cached folder (now looked for only when a clip needs reading); export
name used the run date (now the recording date, matching the scan date); argument hygiene; explicit
ffmpeg paths are probed; Python versions sorted naturally; the launcher passes `%*` and keeps a
drive root; `.gitattributes` forces CRLF for `.cmd`; a whole-box clip no longer needs its whole
decode on disk (60 s windows, under about 720 MB); the browser page has per-clip Shadow/Purified
ticks and lists clips skipped by Stop. Re-run after the fold on the same three clips: identical
CSV (SHA-256 `0291af71...b9a3`) before and after windowing; 02-original alone gives the same 48 rows
with the window at 60, 10 and 7 seconds; a folder with all clips cached merged with
`--ffmpeg C:\nonexistent`; a garbage clip gave a `.partial.csv`, no inbox copy and exit 1.

**Second review round (30 Sep, same day)** (Opus: mergeable with fixes; Sol 5.6: not mergeable) confirmed the
first fixes and found more, all folded: when several overlaps fit, the smallest is still dropped but
every row up to the largest fitting overlap is flagged and listed as a possible repeat; a join where
nothing matches is now reported ("no overlap found"); combining rows no longer hides a
`no-level-fits`, flags a computed HP replaced by a different read HP (`hp-mismatch`), and drops the
IV-guess flags of the losing row; two folders (or `--account` with several accounts) that would
write the same export are refused up front; the cache key also covers `node.js`, `extract-video.js`,
the tesseract.js and pngjs versions and the full language file; a cache without readings is
re-read; a stale `.partial` export is removed by a complete run; a failed write (file open in
Excel) is reported per account instead of aborting; the tests use `scratch/` not `os.tmpdir()`;
the windowed decode continues through an empty window when the clip's duration says there is more;
a quoted drive root (`"C:\"`) no longer breaks the launcher's argument handling; an unreadable
folder under a drive root is skipped. Re-run: the batch CSV hash is unchanged (`0291af71...b9a3`).

**Final review round (30 Sep, same day)** (Opus and Sol 5.6, both "mergeable with fixes") confirmed the
third fold and left small items, all folded: a correctly read Pokémon joined with a misread partner
no longer keeps `no-level-fits` (and the page's "Load into advisor" drops only rows with that flag
and no IVs); a stale `.partial` that cannot be deleted is a warning after the inbox copy, not a
failed write; two accounts of one name are refused only when their exports would land in the same
place; the launcher rebuilds its arguments one at a time (untested until the 1 Oct fold, which found it
failed for every argument-driven launch); per-clip flagged counts come from the final rows; an empty-window warning is printed once.

**Post-merge review fold (1 Oct 2026)** on 2fa7a45 (Opus and Sol 5.6 agreed), all folded: the launcher
took its own folder after `shift`, so every argument-driven launch failed with MODULE_NOT_FOUND (now
captured first; an empty argument no longer drops the ones after it); the page's advisor now leaves
out every `no-level-fits` and `hp-mismatch` row; the duplicate-account check follows an inbox that
really exists and compares folder paths case-insensitively only on Windows; the export date counts
a failed newest clip, so its stale partial is found; the gap warning names the window and the
total count. Verified 1 Oct on Windows, Node 24, from `cmd /c` as Explorer starts it: a folder path
with spaces, parentheses and `&` reached the script and wrote an export (4 rows from the trimmed
clip); `"C:\" --out-dir "<folder with spaces>"` reached the script's own "No clips" message (no
drive-root export run). A launcher test runs `cmd /c` with a nonexistent folder and fails on the
old launcher. Tests: 131 passing, 3 skipped (`npm test`).

**Not yet tested:** a real multi-clip whole-box recording (overlap dropping is tested on synthetic
rows and on one exact-duplicate clip pair only); a real Shadow-filtered pass (the shadow clip in
the run above is a copy of the trimmed clip); `.mov` and `.m4v` inputs; the browser multi-file
path on a device (import-checked in Node only).

**26 Sep 2026, overnight: the screen-recording extractor is built** on branch `extractor`
(`src/extract/`, `scripts/extract.mjs`, `web/extract.html`, tests in `test/extract/`). Full
results and method in `docs/extractor-report.md`; what to click in the morning in
`docs/morning-test.md`. Tests: 60 passing (`npm test`, Node 24, Windows), including an
integration test that runs the real recordings when they are present and skips when not.

**What works (measured on the four recordings, CLI at 5 fps):**
- Trimmed Clipchamp copy (1920×1080 pillarboxed): 4 rows, all four acceptance rows right in
  every field, none flagged, 3.4 s.
- iPhone original (1320×2868 HEVC, not the 1206×2622 the handoff expected): 47 rows in 15.8 s;
  all five acceptance rows present exactly once; of the 35 rows also in the Poke Genie export,
  HP 35/35, IVs 31/35, level 33/35, and every wrong row is flagged. The four misses are
  single-frame Pokémon from the fast-swipe half of the recording (bars still animating, or the
  previous Pokémon's panel).
- WhatsApp copy (384×848): 46 rows; four of the five acceptance rows right, Mega Mewtwo Y's
  pink CP is unreadable at that size (row present, flagged `no-level-fits`); 31 rows in the
  export with HP 30/31, IVs 26/31; one CP misread unflagged (9↔2 at that size).
- iPad (1488×2266 after rotation, 4:3, HEVC): 20 rows, none flagged, all solved to one level;
  no export exists for that account so they are self-consistent, not verified. Layout
  independence holds: regions are anchored on the CP text, the green HP bar and the bar tracks.
- Mega Mewtwo Y: pink CP text handled by a colour-mask fallback; Mega stats used for the solve.

**Assumptions made overnight (Greg was not asked):** recordings saved as
`recordings/{iphone-original,iphone-whatsapp,iphone-clipchamp-trimmed,ipad-original}.mp4`;
the acceptance table is checked against the trimmed and original recordings (the trimmed copy
also contains Xurkitree 3028, and ends on the second Zamazenta); the CLI may locate ffmpeg via
the imageio-ffmpeg Python package as a last resort (development convenience only; the browser
page uses no ffmpeg and no Python); the web page loads tesseract.js 7.0.0 from jsdelivr and the
language file from the site's `data/tessdata`; `web/app.js` gained one hook (`?extracted`
reads a CSV from sessionStorage) and `index.html` one link, nothing else in the advisor changed.

**Untested:** browser video decode (no H.264/HEVC decoder in the container's Chromium), so
`web/extract.html` has only been import-checked in Node; the morning test covers it. Shadow,
Purified, Lucky, gender, moves, candy and Dynamax are not read. Mega colours other than Mega Y.
Nicknamed Pokémon (skipped as unmatched names). Recordings with the appraisal panel closed give
rows with `ivs-unread` and a level range.

**Review gate:** two adversarial reviews (Opus reviewer, Sol 5.6 cross-vendor) on the first
build commit; every finding folded except shadow detection and browser colour range, which are
recorded as limits in the report. Tests after the fold: 62 passing; in a clean copy without
`node_modules` (what the Pages workflow runs) 58 pass and 4 skip.

**Merge state:** `extractor` merged into `main` on 26 Sep 2026 once `npm test` was green and the
CLI met the acceptance table on the trimmed and original recordings (the two gates Greg set).
The Pages deploy publishes `web/extract.html`; the morning test is the first run of the page on
real video. To pick this up on another machine see `docs/continue-on-laptop.md`; the recordings
are in Google Drive under `F. Hobbies & Gaming/Pogo Assist recordings/`.

## Earlier

**25 Sep, evening: priority changed.** The screen-recording extractor is now first; see
`docs/extractor-handoff.md`. Experiments on 25 Sep proved content-rect detection, OCR of name,
CP and HP with tesseract.js, appraisal-bar geometry and swipe detection on a re-encoded 1080p
recording. Calcy import and the dated view are deferred.

**25 Sep 2026, phase 0c built.** `index.html` + `web/app.js`: drop a Poke Genie CSV, get the
Builds, Gaps, Storage and All Pokémon tabs with a text filter and area chips. Runs entirely in
the browser from the same `src/` modules the tests use. `?sample` loads the bundled export.
Pages workflow added (tests, then deploy). Tests: 13 passing.

**Deployed:** repo made public and Pages enabled 25 Sep; the workflow's first successful run
(#3) published https://dare33.github.io/pogo-assist-plus/ . Codec check page at
https://dare33.github.io/pogo-assist-plus/web/codec-check.html .

**Codec spike, 25 Sep (partial):** two recordings checked with ffmpeg. WhatsApp copy: 384×848
H.264 Baseline, 60 fps; text and appraisal bars still legible. Trimmed-in-Clipchamp copy:
1920×1080 landscape H.264 Main 30 fps with the portrait phone content pillarboxed to about
608 px wide. Both are re-encodes; the original 1206×2622 file has not been seen yet. The
container's Chromium has no H.264 decoder, so browser decoding is checked with
`web/codec-check.html` on Greg's own devices instead (iPhone Safari, Mac Safari, Windows
Chrome). Design consequence: the extractor must locate the phone content inside the frame
(pillarboxing, letterboxing) rather than assume the frame is the screen.

**25 Sep, late:** added `src/pvp-rank.js` (stat-product IV rank and target level under a CP cap;
matches Poke Genie's ranks on the fixture). Not yet used by the page; the advisor should switch
to it for PvP builds so ranks no longer depend on the export having scored the evolved form.

**Data notes:** evolution candy costs are a table in `advise.js`; Dynamax status is not in
exports, so Max hits are advisory until the extractor captures the badge.
