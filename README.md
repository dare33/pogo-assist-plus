# Pogo Assist+

Turns a Pokémon GO storage export into build decisions. Import your Poke Genie CSV and get:
what to power up, what to evolve, what you are missing and how to get it, in priority order,
plus which duplicates are safe to transfer. Free, runs in the browser, nothing is uploaded.

Status: phase 0 (advisor on Poke Genie exports) working. See `PLAN.md` for the plan and
`STATUS.md` for progress.

## Use it

Live at https://dare33.github.io/pogo-assist-plus/ (sample: https://dare33.github.io/pogo-assist-plus/?sample).

Open the page, drop your Poke Genie export, read the Builds, Gaps and Storage tabs.
Add `?sample` to the URL to see it with a bundled example export.

## Develop

```
npm test                       # unit tests (node --test)
npm run build:tiers            # regenerate data/tiers.json from data/source/*.md
node scripts/fetch-rankings.mjs   # refresh data/pvp-rankings.json from PvPoke
node scripts/advise.mjs fixtures/greg-2026-09-25.pokegenie.csv   # the report, as text
python3 -m http.server 8765    # then open http://127.0.0.1:8765/?sample
```

The page is plain ES modules with no build step: `index.html` loads `web/app.js`, which imports
the same `src/` modules the tests use and fetches `data/*.json`.

## Deploy

`.github/workflows/pages.yml` runs the tests and publishes the repository root to GitHub Pages
on every push to `main`. One-time setup in the repository settings: Pages → Source →
"GitHub Actions". Note that GitHub Pages on a private repository needs a paid plan; making the
repository public is the free route, and the only personal data in it is a Pokémon inventory.
