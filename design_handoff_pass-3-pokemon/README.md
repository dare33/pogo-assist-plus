# Handoff: design pass 3, the Pokémon screens (Pogo Assist+)

Design session of 25 Oct 2026 with Greg, run as a Design canvas in the Claude desktop app (private artifact "Pokémon
screens — design pass 3", https://claude.ai/artifact/5od545NCbCdYdz8yAyxoYd). It started from the Box tab, the species
list, the Pokémon page, its league view and the Fix a value sheet as built on `feat/pogo-hub` at 7dcf72f, applied pass 2's
lessons, and answered Greg's question "How can we display the same information in less screens. and in a more visually
effective manner" with two layouts. Greg chose **Option A** and refined it.

Read with this file: `DECISIONS.md` (Greg's words for every change; the session's calls C1–C8, decisions D1–D26),
`CONCEPTS.md` (terms, rules, word check; confirmed by Greg on 25 Oct). `READBACK.md` comes from the manager before anything
is built.

**Out of scope**: scanning, the Review, Settings, the Hub (pass 2). The Fix a value sheet is drawn as today and was not
changed.

## The path, before and after

Today: My Pokémon (Box) › species list › Pokémon page › league view, plus the Fix a value sheet: four levels to see one
copy's league options, and the copy the advisor wants to build was row 54 of 65 for Greg's Eevee.

Option A: **My Pokémon › Pokémon page**. A species opens in place in the list (its top 2 for PvP and top 2 by IVs, then
"See all N copies" to the full list, which stays as a screen); the Pokémon page holds everything else behind activity tabs;
the league view is no longer a level (its family list folds out under the league tiles). Fix a value stays a sheet.

## Files

- `design-files/*.dc.html`, `design-files/canvas.json`: the canvas's own source, for reference. `pogo.css` (tokens and
  pieces) and `pogo.js` (data helpers, no UI) are shared by every board. The boards load Greg's box from the artifact's
  private file store, so they do not run from the repo. The trainer name in the header is replaced by "Account name".
- **The final design is `OptionA.dc.html`** (My Pokémon and the Pokémon page, light and dark) with `SpeciesNew.dc.html`
  (the full species list "See all" opens, with the lessons). The other boards are the record of the pass: today
  (`Main`, `Species`, `Pokemon`, `PokemonLeague`, `FixValue`), the six lesson boards (`Lesson*`), today's screens with the
  lessons (`BoxNew`, `SpeciesNew`, `PokemonNew`), the path map (`PathMap`) and Option B (`OptionB`, not chosen; it carries
  some of D6–D24 because it shares the My Pokémon screen).
- The data (`box-data.json`, Greg's box worked through the app's code) is not in git (design process section 3). The
  script that made it is in the session's git-ignored `out/design-data/native/PogoReader` (pass 2's `design-dump`, plus
  `Sources/design-dump/Pokemon.swift`, `BoxIndex.swift` and `GameSearch.swift` copied verbatim from the app target, and
  `Sources/PogoBox/DesignDumpActivities.swift`); run `design-dump <csv> pokemon`. A copy of the four source files is in the
  session-notes folder named in the hand-over message. The read-back should treat `DesignDumpActivities.swift` as the
  reference for the activity-tab rules until PogoBox has them.

## Design tokens added

Existing tokens (`Theme.swift`, `Typography.swift`) and pass 2's additions (type icons, upgrade icon and cost, Full
strength, top / good grades, the "i") are unchanged. New:

- **Activity colours** (ink, tint; dark in brackets), the Hub tiles' own: raids `orangeInk` on `orangeTint`; gym
  `greenInk` on `greenTint`; Rocket #2A3042 on #E9EBF0 (#B5BBCB on rgba(90,98,118,.3)); PvP #7A2FB5 on #EFEBFF (#D1A3FF on
  rgba(156,131,255,.2)); Max #5B3FD6 on #EFEBFF (#BFAEFF on rgba(156,131,255,.2)); Summary the accent.
- **League colours** are `League.ink` and `League.dot`; league names in text take the ink, bold (D2, D3).
- **Marks** (32 pt circle, 44 pt tap area): off `off` with a `faint` glyph; Dynamax on: Max tint, Max ink, 2 pt inset ring;
  Shadow on: #EFE6FA, #6A2DAF, ring (dark rgba(160,110,230,.2), #C9A3FF); Advanced details open: accent tint, accent ink,
  ring.
- **Verdict text**: 10/800 capitals, letter-spacing .5; green `greenInk` (full strength, strong, beats), orange
  `orangeInk` (planned, needs Dynamax), `muted` (the rest).
- **Mega level caption**: `copiesInk` (#B02A5B / #FF9EC0).

## Shared components

- **Header (My Pokémon)**: the account name, 15/700 accent ink with a chevron, on the left (opens the account menu);
  "My Pokémon" centred, 17/800 ink; Export and More circles on the right (D6, D10). The search field sits under it and
  stays while the list scrolls (D7).
- **Species row** (as today with the lessons): name and type icons (18 pt), "best 91% · top 832" with the % graded, the
  build mark, the count, a chevron that turns down when the species is open.
- **Open species** (inside the list's panel): captions TOP PVP and TOP IVS (10/800 `faint`); copy rows on `surface2`,
  radius 14: CP figure, IVs and graded %, a sub line (TOP PVP: league in its colour, pick, graded score, graded IV rank;
  TOP IVS: keep or transfer), the copy's build mark; the selected copy has an accent ring; then "See all N copies ›" on an
  accent-tint button (D12).
- **List gutters**: 24 pt on both sides for the list and the search, so the list is centred under the Scan button; the A–Z
  index (22 pt) lives in the right gutter (D23).
- **Details card** (`surface`, radius 28, padding 16×18): name 28/800 and type icons, "CP 782" on the right; "Level 30 · HP
  111" and the three marks on the next line; the three IV bars side by side (6 pt); the advanced details below a hairline
  when open. The game search is the orange magnifier circle in the header (D4).
- **Activity tabs**: pills (38 pt) with the activity glyph and label in its colour, `surface` when off, the activity tint
  with a 2 pt ring when on; the row scrolls sideways.
- **Summary row** (D20): a grid: glyph in its colour (col 1, both rows); the name 15/700 in its colour and the verdict flush
  right (row 1); the detail lines 13/500 `muted`, one fact each, with league abbreviations in their colours and top / good
  scores graded (row 2); the cost slot (upgrade arrow, value, currency icon, or the Full strength tick) and the chevron.
- **Activity card** (Raids, Gym, Max tabs; D21, D25): `surface2`, radius 18, padding 14: name 18/800, type icons, tier chip
  on the right; a role pill in the activity's tint; this copy's plan as a `surface` block ("Planned for this copy" or
  "This copy, full strength", the work in one line, the cost on the right), or one muted line; Raids: COUNTERS rows (boss,
  kind chip, NOW in the accent or "in 3 d" right-aligned); Gym: the bulk as a 24/800 number, "45% of the top" in green, a
  bar against the top defender.
- **League tiles** (PvP tab): three across, `surface2`, radius 16, a 2 pt ring in the league's ink when chosen; then one
  muted line (the worth line) and "Great League family and details (8 more) ›", folded at first (D4).
- **Advanced details** (D26): captions 10/800; move chips (32 pt, `surface2`; chosen: accent tint and ring) with a type icon
  and an ELITE tag (orange tint); level switches (`off` track, `surface` thumb) for Max moves and the Mega level; flag
  chips for Lucky, Purified, Best Buddy, Weather-boosted.

## Screens

### My Pokémon (Option A)

Header as above; search; the letter groups and species rows. Tapping a species row opens it in place (another tap
closes it); tapping a copy in it opens the Pokémon page for that copy (in the prototype the page beside the list
updates); "See all N copies" opens the species list (as today with the lessons: name and build mark, IVs with the graded
%, CP; sorted best IVs first). The A–Z index shows while the list scrolls.

### The Pokémon page (Option A)

Header: back, the orange search circle (copies the game search), the pencil (Fix a value). The details card. The tabs:

- **Summary**: the five activity rows (PvP leagues first), then the Advice (each build: target and type icons with its cost
  or tick; one line with the area in its colour, the tier and the work; the spare and keep or transfer notes as one line,
  the full sentences behind the "i").
- **PvP**: PVP LEAGUES with the "i" (the Classic | Pogo Assist switch and its explanation inside), the three league tiles,
  the worth line, the family and details fold.
- **Raids**, **Gym**, **Rocket**, **Max**: as the activity card above; Rocket lists the members that beat the most grunt
  types with grunt icons and leader slots; Max starts with the Dynamax state.

Under every tab: power-up dust, spare copies and seen (one row of three), and Delete from box.

## State

- Per copy, stored (new; a full-review item): the Dynamax mark (replacing today's Not set | Yes | No), the Shadow mark,
  the fast and charged moves, the Max move levels, the Mega level, Lucky, Purified, Best Buddy, Weather-boosted. Today only
  the Dynamax choice is stored (`BoxMerge.DynamaxEdit`).
- Per screen, not stored: which species is open, the chosen copy, the chosen tab (Summary first), the chosen league tile,
  whether the family fold, the "i" cards and the advanced details are open.

## Known limits of the boards

- Greg's export has no moves, Lucky, Shadow, Purified, favourite or Dynamax marks; nothing is pre-filled from it.
- The prototype does not recompute ratings when a mark or a move changes (a Shadow mark, a move, Lucky would change the
  advisor's and the leagues' figures in the app).
- Dates are left out of the data: "seen" and the last scan read [date].
- The Pogo Assist ranking is not in the data; the boards show Classic picks.
- My Pokémon is drawn from the letter E onwards (as if jumped there), so Eevee is on the first screen.
- Gigantamax and G-Max moves are not drawn: the bundled game master has no Gigantamax entries.

## Open for the read-back

Flagged during the session (details in `DECISIONS.md`): the three-state Dynamax choice becoming a two-state mark (D22);
storing a hand-set Shadow mark and the advanced details, and re-running the advice when they change (D22, D26);
VoiceOver access to the A–Z index while it is hidden (D24); the Weather-boosted mark's use in the level and IV reading
(D26); the session's proposed rules in `CONCEPTS.md` (TOP PVP, the species build mark, the IV % grades, reach, the activity
tabs, the verdicts); two oddities in Greg's data that the canvas notes flag (a #1 Ultra League Tinkaton tagged OK; Classic
picking Vaporeon over Umbreon for a Great League Eevee).
