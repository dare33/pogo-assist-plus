# Handoff: League options, Pokémon list, Pogo Hub (Pogo Assist+)

Design session of 22 Oct 2026 with Greg. Started from the "League options" handover (the Leagues panel on the Pokémon page) and grew into: a redesigned Pokémon list and species list, a renamed and restructured second tab ("Pogo Hub") with six content-type screens, an app-wide ranking switch, and small Settings changes. **Scan screens are out of scope**: Greg asked that nothing on scan start / scan done / review be changed or handed over; ignore them in `Prototype v2`.

Repo: `dare33/pogo-assist-plus`, branch `main`. Follow `CLAUDE.md`: nothing in the app acts in the game; plain data in `data/`; `npm test` before commits. The iOS app is SwiftUI, iOS 17+, in `native/PogoAssist/`.

## About the design files

Everything in `design-files/` is a **design reference built in HTML**. It shows intended look and behaviour; it is not code to port. The task is to recreate these screens in the SwiftUI app using its existing pieces: `Theme.swift` tokens, `Typography.swift` (Figtree roles), `Components.swift` (`Panel`, `InsetRow`, `Chip`, `PillButton`, `IconButton`), `FloatingTabBar.swift`, and the screens in `Screens/`. Open `design-files/Prototype v2.dc.html` in a browser for the live prototype (every tap works); the other files are the design history and alternatives.

## Fidelity

**High-fidelity.** Colours, type sizes, radii and spacing are the app's own tokens (listed below). Recreate pixel-close. Exceptions: SF Symbols are stand-in glyphs in the HTML (‹ ✎ ⚙ ⌕ ⚑ ★ ⇅ ▦ ☰); use the real symbols the app already uses (`chevron.left`, `pencil`, `gearshape`, `magnifyingglass`, `flag`, `arrow.up.arrow.down`, `square.grid.2x2`, `list.number`). The scan mark in the tab bar is drawn in the app by `ScanMark.swift`; the HTML approximates it.

## Screens

### 1. Pokémon list (was "Box", `BoxView.swift`) — screenshots 01, 17
Tab bar pill renamed **"Pokémon"** (was "Box"). Header unchanged: account pill (monogram 28 pt teal `#14A3B8`, name 15/600, chevron), Export and More floating circles.

Count line: `2,115` (screenTitle 32/800) `Pokémon · 349 species` (15/600 muted). **Removed**: the "Last scan …" line. **New**: a small "to check" badge at the trailing end of the count line, replacing the "All / To check 39" chip row: `flag` symbol + `39`, 12/800 orangeInk on orangeTint, radius 9, padding 3×9. Tapping it applies the To-check filter (the old chip's action).

Search field unchanged. **Removed**: the chip row ("All", "To check 39") and "By species" from the sort line.

Sort line: left `⇅ Name` (13/700 accentInk). Right: **ranking switch**: label `RANKING` (10/800, letter-spacing .06em, faint) + a 2-segment control (`Default` | `Pogo Assist`, 12/700 ink, segment min-height 26, padding 0×9, selected segment on `surface`, track on `off`, capsule) + an **"i" button** (26 pt circle, Georgia italic "i" 13/800, `off` background / muted ink; when open `accent` background / onAccent ink). The "i" toggles an explainer card below the sort line: accentTint, radius 16, padding 12×14, 13 pt, three paragraphs (copy in §Copy). The switch is **one app-wide setting**; it appears on the Pokémon list, species list, Pokémon page and Pogo Hub and changing it anywhere changes all.

Species rows (one per species, in A–Z sections as today; section letter 15/800 + hairline): row padding 12×16, title 16/700 with the count capsule (surface2, 13/800, min 34×26) and chevron on the right. Below the title a **3-column grid (gap 6) of league tiles**, one per league: radius 12, 3 pt left border in the league colour, background the league tint, padding 6×8. Tile content: top row `GL` / `UL` / `ML` (10/800, letter-spacing .08em, league colour) and this copy's IV % of best (12/800, league colour) at the trailing edge; second line the best species for that league (12/600 ink, single line, ellipsis). Values: the species' best copy's pick for that league under the current ranking. When nothing fits: species line "Over cap" (no %); when IVs are not read: "IVs not read".

### 2. Species list (`SpeciesListView.swift`) — screenshots 02, 20
Header unchanged (back circle, "Eevee · 3", Select). Line under header: left `↓ Best IVs first` (14/700 accentInk); right the same RANKING switch + "i" as the list (explainer card appears under this line when open).

Rows: title 16/600, sub `6/7/12 · 56%` 13 muted, CP figure on the right (`CP` 11/800 muted + value 18/800). **New: tags** under the sub line (flex-wrap, gap 6): soft chips, radius 8, padding 3×8, 11/800: league tags in league tint/colour reading `GL · Flareon 97%` (label 10 pt with .08em tracking, a dimmed `·`, then species and IV %), one per league this copy is the best of the species for; and **activity tags** in the content-type colours (see tokens) reading `RAIDS · as Tyranitar`, `GYM · as Corviknight · defender`, `ROCKET · vs Psychic grunts`, `MAX · needs a Dynamax copy`, for other uses the advisor rates this copy best for. Rows are not tinted. Footer note (13 muted): "Tags mark the copy that is your best for a league, raid, gym, Rocket or Max use, under the scoring chosen above."

Greg's earlier red/filled badge style was rejected; keep the soft tints.

### 3. Pokémon page (`PokemonDetailView.swift`) — screenshots 03–07, 18, 19
Header: back circle, **new settings circle** (`gearshape`) beside the pencil. Heading: name 34/800 tracking −0.025em; CP line `CP 461` 22/800 + `Level 17 · HP 72` 15/600 muted; **the game search moved here** as a small chip at the trailing end of the CP line (orangeTint, radius 15, min-height 30, `magnifyingglass` + `eevee&cp461` 13/800 orangeInk + `· Copy` at 80% opacity); tapping copies and toasts "Copied". The full-width SearchStrip at the bottom is removed.

IVs panel: label `IVs` 13/700 muted. **The PvE % (e.g. 56%) is replaced by three PvP figures** at the trailing edge: for each league, this copy's IV % of best as the shown pick (17/800) over `GREAT` / `ULTRA` / `MASTER` (11/700, .06em), each in its league colour; `—` when nothing fits. Bars unchanged.

**LEAGUES panel** (`leagues-panel`), padding 18, gap 14:
- Header row: `LEAGUES` 13/700 muted; trailing the ranking switch (`Default` | `Pogo Assist`) + "i" (same as above; explainer card appears under the header, accentTint radius 16). In the league view a 30 pt back circle (surface2, `chevron.left`) sits before the label; identifier `leagues-back`.
- **Base state**: one block per league (gap 22). Block title row: 10 pt dot + league name 17/800 in the league colour; trailing cap text `Under 1,500 CP` / `Under 2,500 CP` / `No CP cap` 13/700 in the league colour. Then the **pick card** (identifier `league-gl-pick`, a button): surface2, radius 16, padding 14×16, gap 8. Card content: name 19/800 (`Gallade, if it is male` for a gender lock); chip `PICK` or `POGO ASSIST PICK` (12/700 caps .07em, accentTint/accentInk, radius 10); **over-cap indicator** when any family member is over this league's cap: `▲ N over cap` (11/800, redTint background, red ink, radius 8); trailing chevron (faint). Then two figures in a 2-column grid: `SPECIES` (11/700 caps muted) / score 17/800 (greenInk at ≥ 80) / `#710 of 1,152` 12 muted; `THIS COPY` / IV % 17/800 (greenInk when IV rank ≤ 500) / `IV #216` 12 muted. Then a hairline and a **2-column cost list** 14 pt: `Target level: 18.5`, `Target CP: 1,500`, `6,600 dust`, `31 candy` (candy is one total; XL appended `, 296 XL`). Then move chips (12/700, `off` bg, muted ink; a missing move reads `Needs Overheat` on orangeTint/orangeInk).
  - **Best available**: if the pick is over the cap and another member fits, headline the best member that fits and add a 13/600 muted line: "Corviknight is the stronger species, but this copy is already over 1,500 CP as Corviknight."
  - **Nothing fits**: `No viable option` 15/700 red, then 13 muted "This copy is already above 1,500 CP as every member of the family." (or "as Lugia" for a one-member family). Moves still shown. No figures.
  - IVs not read: figures `—` with `not read`, cost absent; the IV panel header shows nothing.
  - Level unknown: dust `—` / `level not known`; card note "Level not known, so no cost".
  - Past its best level (Best Buddy L51): card note "Past its best Ultra League level; 100 candy". At its level: "Already at level 51; 100 candy".
- **League view** (tap a card): the base blocks are replaced by a 3-segment control `● Great` | `● Ultra` | `● Master` (the app's form-switch style: `off` track, 4 pt padding, selected on `surface`, 15/700, selected label in the league colour, 8 pt dot per segment; identifier `leagues-control`), then the chosen league's pick card (not a button, no chevron), then `Show more` / `Show less` (15/700 accentInk, min-height 44, chevron rotates; identifier `league-gl-more`; closed by default), then the option list: column header `OPTION · SPECIES · THIS COPY · DUST` (11/700 caps faint), rows (identifier `league-gl-option-<species>`, buttons) with name 15/700 + sub `L26.5 · CP 1,481` (or `itself, no evolving`, `if it is male`, `too high already`), and three right-aligned figures 15/700 over 11 pt labels: score / `#24`, IV % / `IV #1,879`, dust short (`57k`, `489k` in muted when XL is needed) / `75 candy` or `296 XL`. Unranked: species figure `—` with a blank label. Over cap: the three figures replaced by `Over 1,500 CP as Corviknight` in red. Tapping a row expands it (surface2 background) with: "Best level 26.5 under the cap, CP 1,481. IVs rank #1,879 of 4,096, 94.75% of best.", the cost sentence, and a moves line (see Data needs). Row grid: `minmax(0,1fr) 64 64 78`, gap 8; at accessibility text sizes it collapses to one column with figures under the name.
- Footnote 13/500 muted: "Pogo Assist is currently unable to detect Shadow Pokémon."

Facts panel unchanged. Delete: `Delete from box` 15/600 red + new 12 pt faint line "Removes this copy from the app's box only, not from the game."

### 4. Pogo Hub (was "Next", `NextView.swift`) — screenshots 08, 21
Tab bar pill renamed **"Pogo Hub"** (was "Next"). Header: account name in accent 22/700 with chevron, centred; More circle. Content, gap 14:
- `HAPPENING IN POKÉMON GO` (13/700 muted) with `All news ›` (13/700 accentInk) trailing. A horizontal card strip (cards 236 pt wide, radius 22, padding 14×16, min-height 112, gradient in the card's own colour, white text in light; in dark a solid of the darker pair with light ink): kicker 11/800 .08em, title 17/800, line 13/600, optional pill `See PvP picks` / `See raid picks` (11/800, white at 22%). Tapping a card with a tie opens that content type.
- `WHAT NEXT` (13/700 muted) with the RANKING switch + "i" trailing (explainer card appears under it).
- A 2-column grid (gap 10) of six **type tiles**: surface, radius 22, padding 14×16, min-height 92, panel shadow; glyph 22 pt top-left, count chip top-right (12/800 muted on surface2), label 16/800, sub 12/600 muted. Tiles: Everything (☰, "Every build, best first"), Raids (◈, "Attackers for raid bosses"), Gym battles (⛫, "Defenders and gym attackers"), Team Rocket (☄, "Counters for grunts and leaders"), PvP leagues (⚔, "Great, Ultra and Master picks"), Max battles (✦, "Dynamax and Gigantamax"). Replace the glyphs with SF Symbols of your choice. Tapping pushes the type screen.

### 5. Type screens (one per tile) — screenshots 09–14, 22
Shared chrome: back circle; title 20/800; trailing count chip (`38 builds`, 12/800 in the type's colour on its tint). Content column, gap 12. Shared blocks:
- *Header line*: 13/700 muted, .04em, optional trailing link 13/700 accentInk.
- *Segments*: the form-switch control, 36 pt segments.
- *Cards strip*: 200–236 pt cards as on the Hub (solid colour for the first, surface for the rest).
- *Grid tiles*: radius 16, padding 10×12, 3 pt left border in the type colour (or hairline when it is a gap), label 11/800 caps, value 14/700, sub 12 muted.
- *Slots*: a surface panel (radius 24, padding 14) titled 15/800, with a 3-column grid of slot tiles (radius 16, min-height 84): filled = type tint background, 34 pt disc in ink with the initial, name 13/700, sub 11 muted; empty = 2 pt dashed hairline border, `+` disc in `off`, "Empty" + the build that would fill it. **Tapping a slot** outlines it 2 pt accent and opens the **picker** directly beneath the panel: a surface card outlined 2 pt accent, header `Defender · slot 2` 14/800 + `Done`; rows with a 22 pt tick circle (accent when current), name 15/700, state chip `Built` (greenTint/greenInk) or `To build` (orangeTint/orangeInk), a role line with **Pokémon type chips** (see tokens), and a trailing figure (CP, dust, candy or score) over its 10 pt label. Tapping a row for an example Pokémon opens its page; in the app it should also assign the slot.
- *Timeline* (Raids, Max): a surface list; each row: date column 54 pt (`28 OCT – 3 NOV` 11/800, current row in the type colour; `in 6 d` 11/600 muted), name 15/700 + tier chip (`5★`, `MEGA`, `SHADOW`, `MAX MON`, `BATTLE DAY`, 10/800 on `off`), a 6 pt readiness bar (counters built / counters needed; greenInk when full, red when zero, otherwise the type colour) with `3 of 4 counters` / `4 of 4 ready`, then a `BRING` line (10/800 faint) of Pokémon type chips, then a to-do sentence 12 muted. The current rotation row is tinted. `Now` | `Coming up` segments switch the list.
- *List*: surface list of builds: rank disc 28 pt (type colour + white when highlighted), name 15/700 + tier chip (`S` in type colour on its tint, `A`/`B` muted on `off`), action 13/600, sub 12 muted, trailing figure 14/800 over 10 pt label, chevron when it opens a Pokémon page.
- *Stardust card* (Everything): surface, radius 24, padding 14×16: 44 pt disc with the stardust mark; `612,400` 22/800 + `STARDUST` 12/700 .05em; `Change` trailing (accentInk); an 8 pt segmented bar showing the share of dust each fitting build takes (segments in their type colour, 2 pt surface gaps); line "The builds below fit: 237k of it, 375k left over."

Per screen:
- **Everything** (09): three cards `DO FIRST` / `CHEAP WIN` / `WORTH SAVING FOR` (raids orange, GL blue, ML purple); the stardust card; `THESE FIT` list; `SHOW ALL 143 ›`.
- **Raids** (10, 22): `Now | Coming up` segments; timeline to 1 Dec (bosses from Niantic's monthly post); `BUILDS THAT CLOSE THE GAPS` list; link `Full schedule on pokemongo.com ›` → https://pokemongo.com/news.
- **Gym battles** (11): slots panel `Top defenders` (six slots; four filled, two empty) with picker; `TOP AVAILABLE` list.
- **Team Rocket** (12): leader cards (Giovanni first, `LEADER · SINCE 4 OCT`); `YOUR TEAM FOR GIOVANNI` + `Change leader`; slots `Slot by slot` with picker; `GRUNTS · WHAT THEY SAY, WHO YOU BRING` 3-column grid (grunt line → your counter; filled when built, plain with the build when not, `—` with `gap:` when nothing); note "Rocket lineups are not announced ahead. They change with each Takeover (every six to eight weeks) and are known a day or two after. Grunt types never change."
- **PvP leagues** (13): `● Great | ● Ultra | ● Master`; slots `Suggested team` (3) with coverage in the header (`Coverage 11 of 18 types`) and a weakness footnote; picker of candidates with PvPoke score; `OTHER CANDIDATES` + `All 46`; note about GBL seasons.
- **Max battles** (14): `Now | Coming up` segments; timeline; `YOUR MAX ROSTER` 2-column grid (Max moves per Dynamax copy; `Not Dynamax` when none); note "Only Pokémon caught as Dynamax can take part; the readiness bar counts those only."

### 6. Settings and Appearance (`SettingsView.swift`, `AppearanceView.swift`) — screenshots 15, 16
Settings: the explanatory lines under **Mega Pokémon** and **Restore previous box** are removed from the flow and replaced by a 24 pt "i" button in the row (same style as the ranking "i"); tapping it expands the text inline beneath the row on accentTint, radius 16. Appearance unchanged (accent swatches, Light/Dark/Auto, help level); in the prototype these apply live.

## Interactions

- Tab bar: `Pokémon` / scan mark / `Pogo Hub`; hidden on pushed screens as today.
- Pokémon list → species list → Pokémon page (push). Hub tile → type screen (push). Hub event card with a tie → that type screen. Type-screen list rows and picker rows → Pokémon page.
- Pokémon page Leagues: card tap → league view (in-panel, animated swap); back circle → base; segments switch league; `Show more`/`Show less`; row tap expands inline. All state is per page.
- Ranking switch: one global preference (suggest `PrefKey.ranking`, values `default` | `pogoAssist`), read by every screen that ranks. The "i" explainer is a local toggle.
- Slot picker: tap slot → picker opens under the panel for that slot; tap again or `Done` closes; tap a row to assign (in the prototype it opens the page).
- Settings "i" rows: local toggles.
- Copy chip on the Pokémon page: copies the search, toasts "Copied".

## State

- `ranking` (global, persisted). `leaguesMode` per Pokémon page (`nil` | `gl` | `ul` | `ml`), `showMore` per league, `expandedOption` per league, `infoOpen` (local). Hub: `typeSegment` per type screen (`now`/`comingUp`, league), `picker` (`{section, slot}` or nil). Settings: two info toggles.

## Copy (new or changed)

- Tabs: `Pokémon`, `Pogo Hub`.
- Ranking: `RANKING`, `Default`, `Pogo Assist`. Explainer: "**Default** takes, for each league, the family member where this copy's IVs rank highest under the CP cap (stat product rank out of 4,096), whatever that species' standing." / "**Pogo Assist** weighs the species first. It ranks each member by PvPoke score and only moves to a weaker one when this copy's IVs fit it clearly better." / "Both use the same IV rank and PvPoke rankings; they differ only in which comes first. The choice applies everywhere in the app." (Check the second paragraph against the real rule in `src/leagues.js`.)
- Leagues: `Under 1,500 CP`, `Under 2,500 CP`, `No CP cap`; `PICK`, `POGO ASSIST PICK`; `▲ 1 over cap`; `No viable option`; `SPECIES`, `THIS COPY`; `Target level:`, `Target CP:`, `N dust`, `N candy`, `, N XL`; `Show more`, `Show less`; `OPTION`, `DUST`; `Needs <move>`; `Over 1,500 CP as Corviknight`; "This copy is already above 1,500 CP as every member of the family."; "<Stronger> is the stronger species, but this copy is already over 1,500 CP as <Stronger>."; "Pogo Assist is currently unable to detect Shadow Pokémon."; "Removes this copy from the app's box only, not from the game."
- Hub: `HAPPENING IN POKÉMON GO`, `All news ›`, `WHAT NEXT`, tile labels and subs above; type-screen headers and notes above; `Top defenders`, `TOP AVAILABLE`, `Suggested team`, `OTHER CANDIDATES`, `BUILDS THAT CLOSE THE GAPS`, `YOUR MAX ROSTER`, `BRING`, `Built`, `To build`, `Full schedule on pokemongo.com ›`.

## Accessibility

Keep `leagues-panel`, `league-gl` / `league-ul` / `league-ml`. New identifiers: `leagues-scoring` (switch), `leagues-scoring-info`, `leagues-control`, `leagues-back`, `league-<key>-pick`, `league-<key>-more`, `league-<key>-option-<speciesId>`. VoiceOver: each pick card is one element (button in the base state): "Great League, under 1,500 CP. Pick: Flareon. Species 68.9, rank 710 of 1,152. This copy 97.2 percent, IV rank 216. Target level 18.5, target CP 1,500, 6,600 dust, 31 candy. Moves Ember, Overheat, Flamethrower." Option rows are single elements/buttons with expanded/collapsed state. The ranking switch is an adjustable element. Dynamic Type: no fixed heights; the figure grids go to one column from AX1; the switch wraps under its label when it no longer fits.

## Design tokens

From `Theme.swift` (light / dark): bg `#F3F5F9`/`#0E1118`; surface `#FFFFFF`/`#181C26`; surface2 `#F3F5F9`/`#20242F`; ink `#15192B`/`#EEF1F8`; muted `#6A7085`/`#9097AB`; faint `#8A90A3`/`#6D7489`; line `#E6E9F0`/`#262B38`; off `#E3E7EF`/`#232836`; orange `#FF8A1F`/`#FF9A3C`; orangeInk `#B34D00`/`#FFB273`; orangeTint `#FFF1E3`/`rgba(255,150,60,.16)`; green `#22A55A`/`#3DCB7A`; greenInk `#1C7A3E`/`#6FD796`; greenTint `#E6F6EC`/`rgba(80,200,120,.16)`; red `#D92D3A`/`#FF6B76`. Accents: the eight in `Accent` (designs checked under Berry and Graphite; everything accent-coloured uses `accent.solid/ink/tint/onSolid`).

**New tokens** (add to `Theme`):
- redTint `#FBE4E6` / `rgba(255,107,118,.16)` (over-cap indicator).
- League colours (after GO Battle League): Great ink `#1F5FD1`/`#8FB0FF`, dot `#3B82F6`/`#6FA3FF`, tint `rgba(59,130,246,.10)`/`rgba(111,163,255,.14)`; Ultra ink `#8A5A00`/`#F0C33C`, dot `#E0A82A`/`#F0C33C`, tint `rgba(224,168,42,.14)`/`rgba(240,195,60,.14)`; Master ink `#7A2FB5`/`#D1A3FF`, dot `#A855F7`/`#C58CFF`, tint `rgba(168,85,247,.10)`/`rgba(197,140,255,.14)`.
- Content-type colours (ink / tint): raids = orangeInk/orangeTint; gym = greenInk/greenTint; rocket = graphite `#2A3042`/`#E9EBF0` (dark `#B5BBCB`/`rgba(90,98,118,.3)`); pvp = `#7A2FB5`/`#EFEBFF` (dark `#D1A3FF`/`rgba(156,131,255,.2)`); max = changeInk/changeTint; everything = accent.
- Pokémon type chips (the game's palette, white 10/800 caps text): Normal `#9FA19F`, Fire `#E62829`, Water `#2980EF`, Electric `#FAC000`, Grass `#3FA129`, Ice `#3DCEF3`, Fighting `#FF8000`, Poison `#9141CB`, Ground `#915121`, Flying `#81B9EF`, Psychic `#EF4179`, Bug `#91A119`, Rock `#AFA981`, Ghost `#704170`, Dragon `#5060E1`, Dark `#624D4E`, Steel `#60A1B8`, Fairy `#EF70EF`.

Radii: panel 28, inset row / pick card 16, chip 10, small tags 8–9, tiles 22, lists 24. Spacing: screen margin 14, panel gap 12, panel padding 18. Type: Figtree only; sizes as stated per element; digits tabular. Shadow: panel shadow in light, none in dark.

## Data needs (flag for the engine)

1. **Moves for non-pick options** are trimmed in the league data; the expanded option row shows a placeholder where they would go. Add `moves` to every option or drop that line.
2. **Ranking switch reads `experimental`.** The original handover kept it hidden; Greg wants it as a visible app-wide Default / Pogo Assist switch. Confirm, and check the explainer wording against `src/leagues.js`.
3. **Pokémon list tiles / species-list tags** need, per species and per copy, the best option per league (already in the league data) and the advisor's "best for" areas per copy (raids, gym, rocket, max) — the latter is new.
4. **Pogo Hub**: a bundled **raid/Max rotation JSON** (5★, Mega, Shadow, Max Mondays, Battle Days; refreshed monthly from Niantic's events post; ~4–6 weeks ahead), **Rocket leader lineups** (per Takeover, typed or fetched), a static **grunt-line → type table**, a **box-wide stardust total** (user-entered or read), a **Dynamax flag** per copy, and a news/events feed for the card strip (placeholder content today). Type coverage for PvP teams uses typing from the game master.
5. Figures marked `illustrative` in `league-data.js` are where the handover listed only part of a league.

## Out of scope

Scan start, scan done and review screens (do not change). Little Cup. The web page.

## Files

- `design-files/Prototype v2.dc.html` — the live whole-app prototype (open in a browser; tweaks: theme, accent). **Source of truth.**
- `design-files/Prototype.dc.html` — earlier single-page prototype of the Pokémon page.
- `design-files/League options.dc.html` — Leagues panel design history, turns 1–6, with build notes at the foot (iPad, large text, states).
- `design-files/Next sections.dc.html` — three options per Hub type and the picked, refined set (turn 2).
- `design-files/Pokemon Detail (today).dc.html` — the current app screen, recreated for comparison.
- `design-files/league-data.js` — example data in the handover's `League` / `Option` shape.
- `design-files/support.js`, `fonts/` — runtime and Figtree so the HTML opens offline.
- `screenshots/` — 01–16 dark (Berry), 17–22 light, 30–34 the design sheets. Scan screens deliberately not captured.
