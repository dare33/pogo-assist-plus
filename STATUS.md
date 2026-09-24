# Status — Pogo Assist+

**25 Sep 2026, phase 0c built.** `index.html` + `web/app.js`: drop a Poke Genie CSV, get the
Builds, Gaps, Storage and All Pokémon tabs with a text filter and area chips. Runs entirely in
the browser from the same `src/` modules the tests use. `?sample` loads the bundled export.
Pages workflow added (tests, then deploy). Tests: 13 passing.

**Waiting on Greg:** enable GitHub Pages (Settings → Pages → Source: GitHub Actions). Pages on a
private repo needs a paid plan; making the repo public is the free route.

**Next:** Calcy IV import; a "Next steps" style dated view; then the codec spike on an original
(not WhatsApp) iPhone 16 Pro recording before any extractor code. A WhatsApp-compressed
recording (384×848, H.264) was checked on 25 Sep: CP, names, HP and the appraisal bars are still
legible at that size, which bounds the worst case for phase 1.

**Data notes:** evolution candy costs are a table in `advise.js`; Dynamax status is not in
exports, so Max hits are advisory until the extractor captures the badge.
