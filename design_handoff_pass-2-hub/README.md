# Handoff: design pass 2, Pogo Hub (Pogo Assist+)

Design session of 25 Oct 2026 with Greg, run as a Design canvas in the Claude desktop app (private artifact "Pogo Hub —
design pass 2", https://claude.ai/artifact/4iFEHc8NdHvkUbBgCXTPnB). It started from the Hub as built on `feat/pogo-hub`
at 7dcf72f (draft PR #15) and reworked the second tab: Everything became Collection, every squad screen gained a squad
planner with roles and a picker, and the visual language gained type icons, role colours and two status marks.

Read with this file: `DECISIONS.md` (Greg's words for every change, D1 to D53), `CONCEPTS.md` (terms, rules, word check;
confirmed by Greg at 81fd169; the read-back amendments, D54 to D58, and the manager's calls confirmed by Greg on 25 Oct). `READBACK.md` comes from the manager before anything is built.

**Out of scope**: the Box tab, the Pokémon list and page, scanning, Settings. Changes Greg wants app-wide (the upgrade
icon and cost, D24, D30) are noted for those screens but not designed here.

## Files

- `design-files/*.dc.html`: the canvas boards (one per screen, each drawing light and dark side by side) and
  `canvas.json` (their layout). They are the canvas's own source, for reference: they load the box data from the
  artifact's private file store, so they do not run from the repo. The trainer name in the header is replaced by
  "Account name".
- The data behind the boards (`box-data.json`, Greg's box worked through PogoBox at 7dcf72f plus the new rules) is not in
  git (design process section 3). The script that made it is in the design session's git-ignored `out/design-data/`
  (`native/PogoReader/Sources/PogoBox/DesignDump*.swift`, an executable `design-dump` in a copy of the package); the
  read-back should treat it as the reference for the new rules until PogoBox has them.

## Design tokens added

All existing tokens (`Theme.swift`, `Typography.swift`) are unchanged. New:

- **Role colours** (ink, tint; dark values in brackets): pink #B02A5B on #FDE8EF (#FF9EC0 on rgba(240,101,149,.18)),
  violet #5B3FD6 on #EFEBFF (#BFAEFF on rgba(156,131,255,.2)), teal #087680 on #E0F5F6 (#6FDDE4 on
  rgba(46,196,207,.18)), green #1C7A3E on #E6F6EC (#6FD796 on rgba(80,200,120,.16)), grey `muted` on `off`. These are the
  existing question-kind colours (`copies`, `change`, `match`) plus green. Meaning: pink opener, violet damage, teal
  staying power, green healing, grey any.
- **Type icons**: 22 pt circle (18 pt on slot cards, 16 pt in pills, 13 pt for "beaten by"), the game's type colour
  (`Theme.pokemonTypeHex`), glyph white or ink by `Theme.pokemonTypeText`. Grey version: `off` circle, `faint` glyph.
  Glyphs are our own drawings, not the game's artwork (flame, drop, bolt, leaf, snowflake, fist, bubbles, mountain, wing,
  eye, beetle, rock, ghost, horn, moon, nut, sparkle, ring); paths are in any board's `TYPE_PATHS`.
- **Upgrade available**: 18 pt circle, `orangeTint` fill, `orangeInk` up-arrow; in pickers followed by the cost (12/800
  `orangeInk`) and a 12 pt currency icon (stardust sparkle violet #5B3FD6 / #BFAEFF; candy `muted`).
- **Full strength**: 18 pt (26 pt on build lists) solid green circle, light #22A55A with a white tick, dark #3DCB7A
  with a #0E1118 tick.
- **Number grades**: good = `greenInk` 700; top = `greenInk` 800 on `greenTint`, radius 6, padding 0×4.
- **"i" explainer**: the existing `InfoButton` and `RankingExplainer` look (26 pt circle; `accent.tint` card, radius 16,
  13/500, bold terms in `accent.ink`).

## Shared components

- **SUGGESTIONS · Available | Best · (i)**: a right-aligned row, caption 10/800 `faint`, the compact segmented switch
  (12/700, 26 pt segments) and the "i". One setting per screen, default Available.
- **Slot card** (3 per row, radius 16, min 84–92 pt): role row (10/800 caps in the role colour, upgrade or full-strength
  icon at its trailing end), 30 pt disc (filled: role colour; empty: `off`), name 13/700, type icons. Filled = role
  tint; empty = 2 pt inset outline in the role tint; selected = 2 pt inset outline in the accent. Gym and Rocket slots
  have no role row (the icon sits in the top corner).
- **Picker** (under the squad, `surface`, 2 pt inset accent outline, radius 20, padding 12): title 14/800 ("Slot 2 ·
  Heavy hitter"), "i" and Done; caption ROLE FOR THIS SLOT and role chips (12/700, 7×11, selected in the role colour);
  rows (8 pt vertical padding): 22 pt tick (accent when in the slot), name 15/700, upgrade icon and cost or full-strength
  badge, then role word (in its colour), tier chip and type icons. Then "Could get now (N) ›" or the open list (on
  `surface2`, radius 14): name, tier, role, types, where tags (10/800 chips on `surface`; RAIDS NOW on `accent.tint`).
- **Raid card** (Raids › Now; 250 pt, radius 22, padding 14×16): kicker dates · when (11/800, raid ink), boss 17/800 and
  kind chip (★★★★★, MEGA, SHADOW…), readiness bar, BRING icons. Chosen: raid tint and 2 pt inset raid-ink outline.
  Squad set: filled `accent.solid`, contents in the accent's on-solid ink; chosen and set: a raid-ink ring outside.

## Screens

### Hub tab

Header: the active account's name, 22/700 in `accent.ink` with the chevron (opens the account menu), centred; More
circle. HAPPENING NOW IN POKÉMON GO with All news ›, then the events strip as before. SQUADS AND COLLECTION with the
ranking switch and "i". Six tiles (radius 22), new glyphs drawn after the game: Collection (a Pokédex; chip "347/951",
species owned of released), Raids (raid egg with a star), Gym battles (gym tower), Team Rocket (bold R), PvP leagues
(shield with crossed blades), Max battles (Dynamax cloud with a rising arrow). An event that opened Everything opens
Collection.

### Collection (new; replaces Everything)

Header: Collection, sub "2,125 Pokémon in your box", chip "347 of 951". A panel with the species count (28/800 "347" +
"of 951 species"), an 8 pt accent bar and "36% of the species in Pokémon GO. N more you can evolve now." DEX BY REGION:
one row per region (name, "102 of 150", 6 pt bar). SHOWCASE · YOUR BEST COPIES: a sideways strip of 150 pt cards (type
icons, name, IV % 22/800 in green at 100%, "15/15/15 · CP 3,192"). SPECIAL SETS: two-column tiles (name, "14 of 52" and a
bar; Lucky "Not in your scans yet"). MISSING: count, "N you can evolve from one you have…", the first six (name, "#3 ·
Kanto", how to get), All N ›. BUILDS AND CLEAN-UP: three tappable summary cards (BUILDS count + do first + total dust;
GAPS S and A counts + the top S gap; DUPLICATES species + copies to transfer), each opening the lists screen.

### Collection lists (was Everything)

Back to Collection. Builds | Gaps | Duplicates switch; title follows it. Builds: the three headline cards, the stardust
card, THESE FIT when stardust is set, the full build list (no SHOW ALL); a built row shows the Full strength badge in the
figure column and no " · Free". Gaps and Duplicates as before.

### Raids

Header as before. Now | Coming up, then SUGGESTIONS · Available | Best · (i).

- **Now**: the raids on now as a sideways strip of raid cards. Under it, the chosen raid's squad, flat on the card:
  "Your squad – Palkia" (16/800), the advice line under it, six slots (MEGA, HEAVY HITTER ×3, BULKY HITTER ×2), "i" for
  the suggested mix, and "Set this squad" (accent button) or "✓ Squad set" with Undo. Tapping a slot opens the picker;
  tapping the chosen card again closes the squad.
- **Coming up**: the list; a row shows dates, boss, kind chip and readiness; tapped, it opens BRING, the squad (title
  "Your squad – Boss", advice under it) and the picker; a set row is tinted in the accent.
- BUILDS THAT CLOSE THE GAPS (top 3, All N) and Full schedule on pokemongo.com › as before.

### Max battles

Header as before; Now | Coming up and SUGGESTIONS as on Raids. Rows as Raids' Coming up (no BRING or advice until
opened; D7): squad of three, TANK, HEALER, ATTACKER, role chips Tank | Healer | Attacker | All. The roster, its tiles
and its two notes are gone (D8).

### Gym battles

SUGGESTIONS; Top defenders (six slots, all tappable; upgrade or full-strength icon in the corner). Picker "Slot 2 ·
Defender": rows on one line: tick, name with the upgrade cost, tier and type icons under it, a stacked "153 DEF / 429 HP"
column (level in its tooltip), and the BULK figure; the order is explained behind "i". GYM BUILDS (was TOP AVAILABLE; built rows with the
badge and no "Free") and the gaps as before.

### Team Rocket

SUGGESTIONS; the leader cards; YOUR SQUAD FOR GIOVANNI with Change leader; Slot by slot: three slot cards with name,
"beats 2 of 3" (several options only) and "vs Kangaskhan / Rhyperior / Machamp". Picker "Slot 2 · vs …": rows with type
icons in colour when they hit the slot and grey when not; "Next best" with up to three rows when nothing beats the slot;
Could get now. GRUNTS · WHAT THEY SAY, WHO YOU BRING: one row per grunt in two lines: type icon, type word, the quote
(one line), "beaten by" icons at the trailing end; then a sideways strip of counter pills (name + upgrade or
full-strength mark; the first on the Rocket tint). The Takeover note as before.

### PvP leagues

League switch; SUGGESTIONS; Suggested squad with three slots LEAD, SAFE SWAP, CLOSER (role colours, type icons), coverage
and "i"; the weakness line. Picker with Lead | Safe swap | Closer | All, score and IV line graded (top / good). OTHER
CANDIDATES with roles and graded numbers. Foot line: "Current Season: GO Battle League: Twilight Trails. Ends 1 December,
2026."

## State

- Per raid / Max battle row: its squad (six or three picks), the role of each slot, whether the squad is set. Kept per account on the phone and through re-scans; dropped when the event ends (D58, CONCEPTS rule 27).
- Per screen: Available | Best (default Available); which raid card is chosen; which picker is open; the "i" open state;
  Could get now open or folded. Gym: the six defenders the player chose. Rocket: per leader, the three picks. PvP: per
  league, the three picks and their roles.

## Known limits of the boards

The boards predate the read-back answers: they still read TOP AVAILABLE, "team" (Set this team, Suggested team, YOUR
TEAM FOR …, TEAMS AND COLLECTION), and the Gym order assumes level 20 for a copy whose level is unknown. This file and
CONCEPTS.md give the agreed wording and rules (D54 to D58).

Greg's export has no Dynamax, Lucky, Shadow or favourite marks, so Max picks all read Upgrade available, Showcase ranks
by IVs only, and Lucky reads "Not in your scans yet". The split "Gigantamax A / B" data bug (fixed outside this pass) may
make some Max figures wrong (Grimmsnarl for the Sableye Max Monday).
