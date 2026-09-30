# Status — Pogo Assist+

**30 Sep 2026: batch mode for a whole box.** `node scripts/extract-box.mjs <folder>` (or drag the
folder onto `extract-box.cmd`) reads every clip in an account folder, drops the Pokémon repeated at
clip joins, marks the Shadow column from a `shadow`-named clip, and writes one Poke Genie-layout
CSV plus a review JSON (optionally copied to an inbox). ffmpeg is found automatically (PATH,
winget, imageio-ffmpeg). Per-clip results are cached beside the clips. The browser page takes
several clips and merges them the same way. Protocol and summary lines: `docs/whole-box.md`.
New modules: `src/extract/batch.js` (pure merge), `src/node/ffmpeg.js`, `src/node/extract-video.js`.
Tests: 123 passing, 3 skipped (`npm test`, after the three review folds below).

**Verified (30 Sep, Windows, Node 24, ffmpeg found as imageio-ffmpeg with no `FFMPEG` set):**
three clips (trimmed, original, trimmed again named `03-shadow-trimmed.mp4`) in one folder gave
48 rows: 4 boundary duplicates dropped at 01 to 02, shadow pass 4 matched, 0 appended, 0
ambiguous, and exactly those four rows (Mewtwo 3673, Xurkitree 3028, Zamazenta 2692, Zamazenta
2651) have Shadow/Purified = 1. Running `02-original.mp4` alone gives the same 48 rows. A second
run reported all three clips `cached` and wrote a byte-identical CSV (same SHA-256); running on the parent folder
processed the `dare33` subfolder as the account; `extract-box.cmd` ran from PowerShell (also with
`&`, spaces and parentheses in the folder path); `scripts/extract.mjs` on one clip still gives its 4 rows.

**Review fold (30 Sep, same day).** Two adversarial reviews (Opus reviewer: mergeable with fixes; Sol 5.6
cross-vendor: not mergeable) agreed on the substance; all of it was folded. Found and fixed: the
cache ignored code and data changes (now keyed on the extractor and stores raw readings, rows rebuilt
every run); the "same Pokémon" leniency was dead code because resolved rows carry no ivConfidence
(now judged from flags); the overlap took the largest consistent k and could swallow real identical
Pokémon (now the smallest, weak joins flagged `boundary-weak` and listed by name and CP); weak
shadow matches flagged `shadow-match-weak`; stale flags after merging rows; a partial run could
overwrite the complete export and reach the inbox (now `.partial` files, no inbox copy); ffmpeg
was required even for an all-cached folder (now looked for only when a clip needs reading); export
name used the run date (now the recording date, matching the scan date); argument hygiene; explicit
ffmpeg paths are probed; Python versions sorted naturally; the launcher passes `%*` and keeps a
drive root; `.gitattributes` forces CRLF for `.cmd`; a whole-box clip no longer needs its whole
decode on disk (60 s windows, under about 720 MB); the browser page has per-clip Shadow/Purified
ticks and lists clips skipped by Stop. Re-run after the fold on the same three clips: identical
CSV (SHA-256 `0291af71...b9a3`) before and after windowing; 02-original alone gives the same 48 rows
with the window at 60, 10 and 7 seconds; a folder with all clips cached merged with
`--ffmpeg C:\nonexistent`; a garbage clip gave a `.partial.csv`, no inbox copy and exit 1.

**Second review round (30 Sep, same day)** (Opus: mergeable with fixes; Sol 5.6: not mergeable) confirmed the
first fixes and found more, all folded: when several overlaps fit, the smallest is still dropped but
every row up to the largest fitting overlap is flagged and listed as a possible repeat; a join where
nothing matches is now reported ("no overlap found"); combining rows no longer hides a
`no-level-fits`, flags a computed HP replaced by a different read HP (`hp-mismatch`), and drops the
IV-guess flags of the losing row; two folders (or `--account` with several accounts) that would
write the same export are refused up front; the cache key also covers `node.js`, `extract-video.js`,
the tesseract.js and pngjs versions and the full language file; a cache without readings is
re-read; a stale `.partial` export is removed by a complete run; a failed write (file open in
Excel) is reported per account instead of aborting; the tests use `scratch/` not `os.tmpdir()`;
the windowed decode continues through an empty window when the clip's duration says there is more;
a quoted drive root (`"C:\"`) no longer breaks the launcher's argument handling; an unreadable
folder under a drive root is skipped. Re-run: the batch CSV hash is unchanged (`0291af71...b9a3`).

**Final review round (30 Sep, same day)** (Opus and Sol 5.6, both "mergeable with fixes") confirmed the
third fold and left small items, all folded: a correctly read Pokémon joined with a misread partner
no longer keeps `no-level-fits` (and the page's "Load into advisor" drops only rows with that flag
and no IVs); a stale `.partial` that cannot be deleted is a warning after the inbox copy, not a
failed write; two accounts of one name are refused only when their exports would land in the same
place; the launcher rebuilds its arguments one at a time so `"C:\" --out-dir "D:\Output Files"`
survives; per-clip flagged counts come from the final rows; an empty-window warning is printed once.

**Not yet tested:** a real multi-clip whole-box recording (overlap dropping is tested on synthetic
rows and on one exact-duplicate clip pair only); a real Shadow-filtered pass (the shadow clip in
the run above is a copy of the trimmed clip); `.mov` and `.m4v` inputs; the browser multi-file
path on a device (import-checked in Node only).

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
