# CLAUDE.md — Pogo Assist+

Turns a Pokémon GO storage export (Poke Genie or Calcy IV CSV) into build decisions: what to
power up, evolve, chase, and in what order. Free, runs entirely in the browser, no account.
`PLAN.md` is the build plan and the source of the phase order; `STATUS.md` is where the project
is up to. Read both before working.

## Rules

- Plain JavaScript (ES modules) with no build step until a UI needs one. Node 20+. Tests with
  `node --test` in `test/`. Run `npm test` before every commit.
- Reference data lives in `data/`: `gamemaster.json` is PvPoke's game master (refresh with
  `scripts/fetch-gamemaster.mjs`); `tiers.json` is generated from the markdown tables in
  `data/source/` by `npm run build:tiers`. Edit the markdown, never the JSON.
- Nothing in this repo may contact the game, intercept its traffic, or play it. Inputs are CSV
  exports and the user's own screen recordings (or the live screen, read on the device). Also an input, decided by Greg
  on 20 Oct 2026: screenshots of the player's own Pokémon GO screens, read on the device.
  One exception, decided by Greg on 1 Oct 2026: paging through the player's own storage so it can
  be read, by an iOS Voice Control gesture that only taps or swipes to move from one Pokémon to
  the next (`experiments/voice-control/`). It reads and changes nothing in the game. A second exception, decided by Greg on 4 Oct 2026: after the player starts a broadcast, the app may open Pokémon GO by its URL scheme (pokemongo://) with no parameters, so the player is taken back to the game. It only brings the game to the front; it passes nothing to the game and reads and changes nothing in it. Anything beyond these two exceptions that taps, catches, battles, trades, transfers or otherwise acts in the game stays forbidden.
- Never commit API keys. The optional Claude fallback takes a key at runtime only.
- Fixtures in `fixtures/` are real exports from the owner's account; they contain no personal
  data beyond a Pokémon inventory. Do not add other people's exports without asking them.
- Personal data policy for the future web page: files are read in the browser and never
  uploaded.

## Build hygiene

Build output from a session never goes in the session scratchpad or in a fresh per-run folder: on
25 Oct 2026 the per-run derived-data folders sessions had left under `/private/tmp/claude-*` came to
143 GB. The rule in full is in `native/README.md`, "Build hygiene"; the binding part:

- Every command-line `xcodebuild` goes through `native/tools/xcb.sh <slot> <args...>`, which builds
  in the fixed, reused `~/Library/Developer/Xcode/DerivedData/pogo-claude-build/<slot>` (slots:
  `main`, `review-a`, `review-b`, `merge`) and holds that slot's lock while the build runs. Never
  pass `-derivedDataPath`; never build under `/private/tmp/claude-*`; a fifth slot is Greg's call.
  A cold build takes minutes: run it in the background or with a long timeout.
- `swift build` / `swift test` use the package's own git-ignored `native/PogoReader/.build`, or
  `--scratch-path ~/Library/Developer/Xcode/DerivedData/pogo-claude-build/swift-<slot>`.
- A reviewer that must build a read-only copy copies `native/` (without `.build`) to
  `~/Library/Developer/Xcode/DerivedData/pogo-claude-build/review-copy-a` (slot `review-a`) or
  `review-copy-b` (slot `review-b`) and deletes it when the review is returned.
- A simulator cloned for a run is made with `native/tools/sim-temp.sh create` and deleted with
  `sim-temp.sh delete` before that run ends. The standing simulators are iPhone 17 (single UI tests)
  and iPhone Air (full suites); they are never deleted, and two runs never test on one simulator
  at once.
- The scratchpad holds small intermediate files only (briefs, logs, screenshots, JSON diffs).
  `native/tools/build-clean.sh` empties the fixed location when it is stale and nothing is building.

## Design passes

A design pass (a design session's handoff built into the app) follows `docs/design-process.md`, agreed by Greg on
25 Oct 2026. The binding part:

- The brief tells the design session to log Greg's changes as he makes them (`DECISIONS.md`) and to write the terms and
  rules from them at the end (`CONCEPTS.md`), confirmed by Greg. The prototype runs on Greg's own box data.
- Before any code, the manager writes `READBACK.md` (each screen's behaviour as checkable statements, the rules checked
  against the engine, every gap as a question) and Greg answers it.
- One branch `design/<pass>` off `main`, one draft pull request; the local preview build is kept current; screenshots
  per screen (light, dark, default text and AX5) go on a private page for Greg's comments between phone runs.
- Review is sized to the change: a cosmetic change (looks and wording only, nothing computed, stored, matched, sorted
  or filtered) gets the builds, the affected UI tests, before and after screenshots and one `reviewer` pass; anything
  else, or anything mixed or unsure, gets the full paired review. The size is named in the commit and the pull request.
