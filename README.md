# Pogo Assist+

Turns a Pokémon GO storage export into build decisions. Import your Poke Genie or Calcy IV
CSV and get: what to power up, what to evolve, what you are missing and how to get it, in
priority order. Free, runs in the browser, nothing is uploaded.

Status: early build. See `PLAN.md` for the plan and `STATUS.md` for progress.

## Develop

```
npm test               # unit tests
npm run build:tiers    # regenerate data/tiers.json from data/source/*.md
npm run dump -- fixtures/greg-2026-09-25.pokegenie.csv   # annotate a box with tier hits
```
