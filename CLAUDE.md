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
- Nothing in this repo may contact the game, intercept its traffic, or automate input to it.
  Inputs are CSV exports and, later, the user's own screen recordings.
- Never commit API keys. The optional Claude fallback takes a key at runtime only.
- Fixtures in `fixtures/` are real exports from the owner's account; they contain no personal
  data beyond a Pokémon inventory. Do not add other people's exports without asking them.
- Personal data policy for the future web page: files are read in the browser and never
  uploaded.
