# Status — Pogo Assist+

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
