# Design handover: League options (Pogo Assist+)

For a Claude Design session. Goal: design how the iPhone app's Pokémon page shows a Pokémon's PvP league options. The design comes back to the Pogo Assist+ repo to be built. The engine and data already exist (merged in PR #7). This is screens only.

## Where to look in the repo (`dare33/pogo-assist-plus`, branch `main`)

The repo is large: a Pokémon-reading engine, a web page, scan tooling and long notes. Most of it is not relevant here. Read only the files below, and ignore the rest, especially `native/PogoReader/Sources/PogoReader/` (screen reading), `src/extract/` and `experiments/`, and almost all of `native/README.md`.

**The app's look (the design system to work within)**
- `native/PogoAssist/PogoAssist/UI/Theme.swift`: colour tokens for light and dark, the accent themes, corner radii, spacing and the panel shadow.
- `native/PogoAssist/PogoAssist/UI/Typography.swift`: the Figtree type scale.
- `native/PogoAssist/PogoAssist/UI/Components.swift`: `Panel` and the other building blocks screens are made of.
- `native/PogoAssist/PogoAssist/UI/ComponentGallery.swift`: every component in one place.
- `native/PogoAssist/PogoAssist/Screens/AppearanceView.swift`: the user-selectable appearance themes. The design must work under every accent colour, not only the default.

**The screen being redesigned**
- `native/PogoAssist/PogoAssist/Screens/PokemonDetailView.swift`: the Pokémon page. The Leagues panel is under `// MARK: leagues` (`leaguesPanel`, `leagueRow`). Look at the rest of the page for context: the header, the advice panel and the facts panel.
- `native/PogoReader/Sources/PogoBox/LeagueText.swift`: every sentence the Leagues panel shows today.

**The data the screen receives**
- `src/leagues.js`: the comment block above `leaguesFor` is the authoritative description of the data shape. It is repeated below.
- `native/PogoReader/Sources/PogoBox/BoxAdvice.swift`: `LeagueRating` and `Option`, the same data as the Swift app decodes it.

**Neighbouring screens, for consistency**
- `native/PogoAssist/PogoAssist/Screens/BoxView.swift`, which lists the Pokémon.
- `native/PogoAssist/PogoAssist/Screens/NextView.swift`, which shows build advice.

**Project rules**
- `CLAUDE.md`. Short. Note that nothing in the app acts in the game.

## The product in one paragraph

Pogo Assist+ is a free iPhone app, with a web page, for Pokémon GO players. It reads your Pokémon storage from a Poke Genie CSV or from the app's own screen scan, then tells you what to power up, evolve and build. This handover covers **PvP leagues**: Great League (CP cap 1,500), Ultra League (CP cap 2,500) and Master League (no cap). For each league, any Pokémon could be built as itself or as any member of its evolution family. The app picks one, and it now also knows all the alternatives.

## What to design

The **Leagues** section of the Pokémon detail page, for one Pokémon, across three leagues. For each league it should show:

1. **Our recommended pick**, the "shown pick". It copies Poke Genie's choice, because that's what the owner's family and friends already use and trust. It's the headline.
2. **Every option**: each family member this Pokémon could become, with how strong that species is in the league and how good this copy's IVs are as that species.
3. **Why the pick was chosen**, where useful. The `source` field says whether the pick is Poke Genie's own, an emulation of Poke Genie, the strongest species, or a fallback.
4. **Cost and moves for the pick**: stardust, candy, XL candy and evolution candy to reach its best level. The pick's recommended moves, and which of them this copy lacks.
5. **Blocking states**: "already too high a level for this league" (over the cap), "IVs not read", and "level not known".

Not shown, and not to be designed as visible: the **experimental pick**. It's a second rule the owner is tuning, and it stays hidden until the owner switches to it. It may get a hidden or debug affordance later, so leave room for that but don't design it now.

## Constraints

- **Platform.** iPhone first, iPad second. SwiftUI, iOS 17+. The screen is a single scroll column (max content width 640 pt) of rounded "panels".
- **Type.** Figtree throughout. The current section header is uppercase 13 pt bold in the muted colour, the league title is 17 pt heavy, and body lines are 15 pt regular with monospaced digits.
- **Colours.** These are existing tokens, each with a light and a dark value:

  | Token | Light | Dark |
  |---|---|---|
  | bg | #F3F5F9 | #0E1118 |
  | surface | #FFFFFF | #181C26 |
  | surface2 | #F3F5F9 | #20242F |
  | ink | #15192B | #EEF1F8 |
  | muted | #6A7085 | #9097AB |
  | faint | #8A90A3 | #6D7489 |
  | line | #E6E9F0 | #262B38 |
  | orange | #FF8A1F | #FF9A3C |
  | orangeInk | #B34D00 | #FFB273 |
  | green | #22A55A | #3DCB7A |
  | greenInk | #1C7A3E | #6FD796 |
  | red | #D92D3A | #FF6B76 |
  | match (teal) | #0E9AA7 | #2EC4CF |

- **Shapes and spacing.** Panel radius 28, inset-row radius 16, chip radius 10, screen margin 14, gap between panels 12. Design both light and dark.
- **Accessibility.** Dynamic Type must reflow. Each league needs a sensible VoiceOver reading order: today each league row is read as one element. Keep the accessibility identifiers `leagues-panel` and `league-gl`, `league-ul` and `league-ml`, or name their replacements.
- **Density.** A family can have up to 9 options per league (Eevee), and there are 3 leagues, so as many as 27 rows for one Pokémon. Most families have 2–3 options. The design must handle 1, 3 and 9 options gracefully. Options to consider: collapse to the pick plus a "See all N options" control, a league segmented control, or a compact comparison list.
- **Options without a ranking.** Many options are "unranked" (PvPoke doesn't rank that species in that league). They still have IV numbers and a cost, but no strength score.
- **Display only.** Nothing on this screen changes game data; it's advice to read.

## Today's screen, to replace

One panel titled LEAGUES. For each league it shows a bold league name, then plain lines:
- "As Magneton", only when the pick isn't the Pokémon itself; with a gender lock it reads "As Gallade, if it is male";
- "PvPoke ranks Magneton 449th of 1,152 in Great League, score 76.4", or "Not ranked in Great League by PvPoke";
- "IVs rank #1,293 of 4,096 · 95.5% of best", or "Already above 1,500 CP, so it cannot be used in Great League", or "IVs not read, so no rank";
- "Moves: Spark, Discharge, Magnet Bomb";
- "Needs Discharge";
- "To level 23: 54,000 dust, 56 candy (25 to evolve)", or "Past its best Ultra League level; 50 candy to evolve", or "Level not known, so no cost".

A footnote follows: "A scan cannot tell a Shadow Pokémon, so a Shadow is rated as its normal form here." It's all text, and none of the alternatives are shown.

## The data, exactly as the screen receives it

For each Pokémon there's one object per league, `gl`, `ul` and `ml`:

```
League = {
  options: [Option],         // every allowed family member, ordered: PvPoke-ranked first (by score, then IV Rank %),
                             //   then unranked (later evolution first)
  pick: Int,                 // index into options of the SHOWN pick
  experimental: Int,         // index of the hidden experimental pick (may equal pick) - do not show
  source: "export" | "emulated" | "ranked" | "fallback"
}
Option = {
  speciesId: String, name: String,
  self: Bool,                // it is this Pokémon itself (no evolving)
  genderLocked?: "male"|"female",  // only when this copy's sex is unknown and only one sex can become it
  strength: { score: Number, rank: Int, of: Int } | null,   // PvPoke score (0-100) and rank in the league; null = unranked
  moves: { fast: String, charged: [String] } | null,        // recommended moves; ONLY on the shown and experimental options
  needs: [String] | null,    // recommended moves this copy lacks; only on the option where self = true
  iv: { rank: Int,           // 1..4096, this copy's IV spread rank as that member (1 = best)
        pct: Number,         // stat product as % of the best possible spread
        rankPct: Number,     // 0-100 percentile of the rank
        level: Number,       // best level under the cap
        cp: Int } | null,    // CP at that level; null = IVs unknown or cannot fit under the cap
  overCap: Bool,             // this copy is already too high a level for this league as that member
  cost: { dust: Int, candy: Int, xl: Int, evolveCandy: Int, toLevel: Number } | null
}
```

What each `source` means, if you want to explain it to the user:
- **export:** this is Poke Genie's own pick, from the user's Poke Genie CSV.
- **emulated:** our reconstruction of Poke Genie's choice, used for app scans. It matches Poke Genie about 95% of the time.
- **ranked:** the strongest species by PvPoke score. Master League always uses this, as does any copy with unknown IVs.
- **fallback:** nothing usable is ranked, so we show the final evolution, or the first member that fits.

## Real examples from the owner's box (25 Sep 2026 export)

### Eevee, CP 461, level 17, IVs 6/7/12

The shown pick follows Poke Genie, and here Poke Genie disagrees with species strength: it picks Flareon, which is weak but suits these IVs. This is the key tension the design has to make readable.

Great League, shown pick **Flareon** (source: export). Options:

| Option | PvPoke | IV rank | % of best | Best level, CP | Cost |
|---|---|---|---|---|---|
| Umbreon | #24, 90.2 | #1,879 | 94.75% | L26.5, CP 1481 | 56,800 dust, 50 candy, +25 to evolve |
| Sylveon | #192, 82.9 | #1,583 | 95.06% | L18, CP 1475 | 4,400 dust, +25 to evolve |
| Vaporeon | #550, 73.5 | #681 | 96.59% | | |
| **Flareon** | #710, 68.9 | #216 | 97.24% | L18.5, CP 1500 | 6,600 dust, 6 candy, +25 to evolve |
| Leafeon | #785 | #511 | | | |
| Jolteon | #790 | #2,826 | | | |
| Espeon | #862 | #933 | | | |
| Eevee (itself) | #1,039 | #1,778 | | L50 | 488,800 dust, 296 XL |
| Glaceon | #1,097 | #2,618 | | | |

Ultra League, shown pick **Flareon** (export). Sylveon is #100 (score 85.9) and Umbreon #116. Flareon is #623 but has the best IVs. The hidden experimental pick is Sylveon.

Master League, shown pick **Sylveon** (ranked, #70, score 80.1). Eight other options follow, all costed to level 50 at 488,800 dust and 296 XL.

### Magnemite, CP 305, level 9, IVs 2/5/11

Great League, shown pick **Magneton** (export).

| Option | PvPoke | IV rank | Best level | Cost |
|---|---|---|---|---|
| Magnezone | #365, 78.4 | #1,606 | L17.5 | 25,400 dust, +125 to evolve |
| **Magneton** | #449, 76.4 | #1,293 | L23 | 54,000 dust, 56 candy, +25 to evolve |
| Magnemite (itself) | #480, 75.5 | #2,396 | L50 | 512,000 dust, 296 XL |

Ultra League shows Magneton as well. Master League shows Magnezone (ranked); the other two are unranked.

### Charmander, CP 53, level 2.5, IVs 10/10/10

Great League, shown pick **Charizard** (export).

| Option | PvPoke | IV rank | Best level | Cost |
|---|---|---|---|---|
| **Charizard** | #260, 80.8 | #607 | L19 | 39,400 dust, +125 to evolve |
| Charmeleon | #651, 70.8 | #2,155 | | |
| Charmander (itself) | unranked | #743 | | |

Ultra League: Charizard is #97. Charmeleon and Charmander are unranked there, but still have IV and cost figures.

### Edge states to design for

- **Over the cap.** A level-35 Rookidee is already too high for Great League as Corviknight, so that option has `overCap: true`, with no IV rank and no cost.
- **IVs unknown,** for example a scan that couldn't read the bars: `iv: null` and `cost: null`. The pick is the strongest species that fits.
- **Level unknown:** `cost: null`, shown as "Level not known, so no cost".
- **Best Buddy at level 51,** past its best level: the cost is 0, with evolution candy only. It reads "Past its best Ultra League level; 50 candy to evolve".
- **Gender-locked,** such as Kirlia to Gallade when the sex is unknown: "As Gallade, if it is male".
- **Shadow,** which a scan can't detect: the footnote stays.
- **One-member families,** such as a legendary with no evolutions: a single option per league.

## Questions for the design to answer

1. **Headline the pick and still show the options.** How does the screen lead with the shown pick while making the alternatives easy to compare? The comparison is mainly species strength (PvPoke) against this copy's IV fit.
2. **Explain a pick that isn't the strongest species.** When the pick isn't the strongest species (Eevee → Flareon), how do we explain it without overwhelming the user? Possibly with a short "Why Flareon?" line based on the IV fit.
3. **Many options.** How does the screen handle 9 options and 3 leagues on a phone?
4. **Comparing costs.** Costs vary hugely: 4,400 dust versus 488,800 dust plus 296 XL. How do we show that so cheap and expensive options are easy to tell apart?
5. **Unranked options.** How do they look next to ranked ones?
6. **Blocking states.** What do over-cap, IVs-unknown and level-unknown look like?
7. **iPad.** Does the larger width allow a side-by-side three-league comparison?

## Deliverables wanted back

- **Screens:** mock-ups for iPhone, light and dark: Eevee (many options), Magnemite (three options, all ranked), Charmander (unranked options), and one each for over the cap, IVs unknown, and a single-member family.
- **iPad:** one mock-up.
- **Interactions:** expanding and collapsing, switching leagues, and what tapping an option does, if anything (for example, showing that option's cost and IV detail).
- **Copy:** any new copy, such as headings, "Why …" lines and labels for unranked or over-cap options.
- **Data needs:** any data the design needs that isn't in the shape above, flagged clearly. For example, moves for non-pick options are currently trimmed to keep the data small; if the design shows them, say so.

## Out of scope

The experimental pick UI. Changing how the pick is chosen. The web page (it gets a lighter version later). Little Cup.
