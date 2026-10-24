# Status — Pogo Assist+

**24 Oct 2026, branch `feat/settings-info-rows` (PR 5 of 5 of the design handover, stacked on `feat/settings-history-scans`, not merged): Settings "i" rows.** The explanatory lines under Mega Pokémon and Restore previous box are gone from the flow; each row has a 24 pt "i" (`InfoButton`) that opens the text inline as an `ExplainerCard` (accent tint, radius 16; `RankingExplainer` now uses the same card). As in Prototype v2, the Mega row's "i" sits straight after its title (8 pt from the title's text frame by construction, as the overlay mirrors the row; checked by eye at the default size, AX3 and AX5 on the iPhone 17), with the value and chevron at the trailing edge, and the Restore row's "i" is at the trailing edge. The Mega "i" is drawn over a gap the row's label leaves, outside the Menu's label, so a tap on it never opens the menu and a tap elsewhere on the row still does; the overlay is a second, hidden copy of the whole row (title, value, chevron, paddings) so both copies wrap alike. The Restore "i" is outside its Button, so it works while the row is disabled. At accessibility sizes the Mega row wraps: the title and "i" on the first line (at AX5 the title wraps to two lines and the "i" sits beside that block, vertically centred), value and chevron on the next. The Restore "i" has its circle's right edge 16 pt in at every size. Local state, not persisted. Identifiers: `settings-mega-info`, `settings-mega-explainer`, `settings-restore-info`, `settings-restore-explainer`. Deviation from the prototype: the explainer card is drawn inside the panel beneath its row (the prototype shows it as a separate block below the panel). Verified on greg-mb-16, iPhone 17 simulator, iOS 27.0: the unsigned simulator build succeeded; `GuideScreensTests/testSettingsInfoRows` (cards absent, open, text, close, the "i" does not open the menu, Restore button disabled while its "i" is enabled, the Mega row still opens its menu and tapping Normal closes it, light and dark), `testSettingsInfoRowsLargeText` (AX3, `AccessibilityXL`), `testSettingsInfoRowsLargestText` (AX5, `AccessibilityXXXL`; the account is made at the normal size first because the first screen does not fit at AX5) and `testAppearanceSettings` passed; the AX screenshots were read (no word breaks mid-word). Some earlier AX attempts failed or crashed the test runner (a card that did not appear, a runner restart); another xcodebuild was driving the same simulator at the time (the dd-hub xcresults overlap 00:56 to 01:01), the likely cause, and the same tests passed when re-run with no other run on the iPhone 17. Known limit: at AX5 the UI test could not tap the Trainer name field on the welcome screen (it creates the account at the normal size first), which may mean a real user at AX5 cannot create an account; not checked. Not verified: a second accent, iPad, a real device. Paired review (Opus + Sol): three rounds (placement and AX layout, the overlay geometry, the mirrored overlay), the last confirming the code and the tests; passed. The final tidy (the Restore "i" inset, wording) was build-checked and one UI test re-run, not re-reviewed.

**20 Oct 2026: screenshot import (branch `feat/screenshot-import-fold`, on `feat/screenshot-import`, not merged).** Quick import of Pokémon GO appraisal screenshots, from the app (system photo picker) and from
Photos (Share > Pogo Assist+), each read once, merged as a partial Add and update and saved as source "screenshot import". Design, rules and limits: `native/README.md`, "Screenshot import". The latest reviews (of the ledger-cap fold) were Opus "ship after fixes" and Sol "do not ship" on small items, which this fold addresses; account-name hardening is deliberately on hold (see the known limits below). **The review gate is not passed.** Verified on the Mac (greg-mb-16, Xcode 27.1): `swift test` in `native/PogoReader`
179 + 65 + 707, 0 failures (1 + 6 skipped); `npm test` 244 tests, 240 pass, 4 skipped (the recordings are not in that checkout), 0 fail; the app builds unsigned with the extension; the picker flow
(`ScreenshotImportTests`) passed in the iPhone 17 simulator. Not verified: the Share extension running (it needs a signed build, the `com.dare33.pogoassist.share` App ID and the App Group), the new app
glue beyond what the simulator test touches (backgrounding, the sheet opening by itself), and anything on a real iPhone or iPad.
**Known limits (screenshot import):** account identity is by name, so renaming an account and then creating a new one with the old name while screenshots are queued can leave holds counted for neither account or ask
which box; stable account IDs (`docs/stable-account-ids-plan.md` on `claude/great-moore-21a56d`) are the planned fix, separate work awaiting Greg's approval. A share queued before a rename-and-reuse of an account's name can be filed into the new account without asking, and after "Start a new import record" re-shared screenshots are not held. The Share extension has not run on a device. The app glue
(sheet, background pause and resume, auto-opening) is tested only by the build and the simulator picker flow.

**20 Oct 2026, branch `feat/league-options` (merged in PR #7): league options.** `leaguesFor` (`src/leagues.js`) now returns, per league,
every allowed family member (PvPoke-ranked or not, form changes such as Zygarde included) as `options`, each rated for the copy
(PvPoke rank and score, IV rank, cost; moves only on the shown and experimental options), plus `pick` (index of the member to SHOW),
`experimental` (index of the other rule's member) and `source` (`export`, `emulated`, `ranked`, or `fallback`: the PvPoke-score rule ran (Master League, or unknown IVs) but none of the members it may show is ranked here: either nothing in the family is ranked, or every ranked member is past the cap. The shown member is then the final evolution if it fits, else the first option that fits, which is an unranked one (a level-50 Bulbasaur with unknown IVs shows Ivysaur in Ultra League). If no member fits and nothing is ranked, the final evolution is shown even though it is over the cap. A copy with known IVs in Great or Ultra League and nothing ranked is still `emulated`). The shown pick copies Poke Genie: its own pick from the export when the entry has one and it is in the
family. Otherwise, in Great and Ultra League, `pokeGeniePick`, a PROVISIONAL emulation (best stat product % among the members the
copy is not already too strong for, ranked ones first). Master League has no Poke Genie pick to copy and the emulation there only
followed ~0.07% stat-product noise (Eevee showed Glaceon, Scyther Kleavor over Scizor, Shaymin Land over Sky), so Master League
shows the highest PvPoke score, as `main` does (Greg's decision, 20 Oct). Without reading the export's pick the emulation matches
Poke Genie on 272/280 Great and 300/306 Ultra fixture rows (the 278/304 seen in the cost checks are the rows with an exact level, a
different count). Those figures are IN-SAMPLE, on one fixture (the data it was fitted on), and the test floors are regression pins,
not evidence it generalises. The misses are not only near-ties where Poke Genie prefers the later evolution: Crocalor stays Crocalor
where Poke Genie picks Skeledirge, and Magmar becomes Magmortar where Poke Genie keeps Magmar. The earlier idea, species strength
first with a `CLOSE_SCORE` (3.0) window decided by IV Rank %, is kept as `chooseMember`, computed in the background and not shown
(250/280 Great, 296/306 Ultra against Poke Genie, same caveat); `experimental` is never a member the copy is already past the cap
for, unless every member is (then it is the shown pick). Greg swaps the shown pick to it once it is provably better. Both rules and
the threshold sit together at the top of `src/leagues.js`. The advisor rates league builds from the build target's own option
(scans have no Poke Genie columns); a league where the copy is already past the cap as the target is not an area of that build, and
a build left with no area is dropped; "past the cap" means the copy's CP at its current level (0/0/0 if its IVs are unknown) is over it, so a level-51 Best Buddy copy that still fits stays. A level-35 Rookidee no longer outranks a usable level-5 one for Corviknight. Master League
keeps its neutral 0.6 weight and is never the cost league. XL candy now counts towards a build's effort for GL and UL (the league cost carries it; before, it was taken as 0). The display for the league options is being designed separately: the Leagues
section still shows the shown pick only. What DID change on screen and in the exports is the wording of each build: every build now carries
`steps`, the list of things still to do (evolve or form change, Mega evolve, one power-up step, second move, Elite TM, Community Day move,
and the Max-only "needs a Dynamax copy"), and its action, the web table, `scripts/advise.mjs`, the Pokémon page and the export's Advice
column all word it from that list ("Evolve to Annihilape + Power up to level 16 (GL)"). The power-up step is exactly the climb the shown
cost pays for: a league-only build climbs to the cost league's best level, any other build to its highest non-league target level (areas
tied on it are all named, "(Gym/Max)"); another league's best level is never a step, only a note when the climb goes past it ("going past
27 leaves UL"). "Already built" means nothing is left; a Dynamax requirement belongs to the Max area alone, so it reads "Already built (Max
needs a Dynamax copy)" when that is all (a build for Max alone reads "Needs a Dynamax copy"). The second charged move is a step (and charged) unless the copy's second charged slot is already
unlocked (Poke Genie's Charge Move 2 is filled; kept by position as `chargedMoves`); a scan records no moves, so it reads "Second move (if
it doesn't have it)" and is still charged, as before. Elite TM and Community Day move steps are dropped when the recorded moves already hold
the move, and Elite TMs are counted by distinct move name in the step text. The fixture records moves for one Pokémon only (a Mareep whose
second charged slot is empty), so scores, costs and order are byte-identical to 7c43c85 on the fixture and 11 variants. A spare reads "spare
for the X build". The app decodes the data (`BoxAdvice.LeagueRating`, `Build.steps`; advice cache version 8). Not verified on a device.

**Known limits / follow-up (league options branch; not changed here, scores must stay as they are).**
- Costing is single-area: a build is costed to ONE target (the league's best level for a league-only build, else the highest non-league
  target), so a league whose best level is above that target is not paid for, and the cost does not reach other leagues (they appear only
  as the "going past N leaves X" note).
- The effort figure counts Elite TMs by mentions in the tier tables (`(Elite)` markers across entries), so one Elite move named in several
  entries counts more than once; the step text counts distinct moves. Fix together with the costing above, then re-check the order.
- Community Day and Elite flags come from the tier tables' text, not from the game data; a table entry that names them differently is missed.
- The second-move charge is a flat third-move cost; a copy with an unlocked slot may still need a TM for the recommended move (no step for that).
- Master League has no cap and no per-league cost from `leaguesFor`: it keeps a neutral quality weight (0.6) and is never the `pvpCost`
  league or a "going past N leaves X" note. A build for Master League ALONE is costed like a non-league one, to the table's level 50
  (e.g. a level-30 Lugia: "L30 → 50 (ML)", 500k dust); with other areas it follows their target.
- Behaviour that DOES differ from `main` and from 7c43c85 on exports that record moves: a copy whose Charge Move 2 (second charged slot) is
  filled is no longer charged the third-move cost and has no "Second move" step (intended: the slot is unlocked). Probe: a level-40
  Charizard (Rocket, Raids) scores 9.73 and costs 10,000 dust with no recorded moves, and 13.23 and 0 dust with both charged slots filled.
  The fixture and its 11 variants (levels, Shadow/Lucky/Purified, no level, no moves, other moves) are byte-identical to 7c43c85, because
  the fixture records moves for one Pokémon only and not a second charged slot.
- Not verified on a device: the app's screens with the new wording.

**20 Oct 2026: where it stands (handover).** `main` now holds everything: the iPhone app (`native/`, v1.0 build 3,
merged from `native-ui-v1` in PR #2), the shared JavaScript changes (extractor read fixes, CP recovery, PvP leagues,
CP multipliers, shadow/purified/lucky cost rounding, refreshed PvPoke rankings of 10 Oct), the Pages CI fix (PR #1:
the workflow now runs `npm ci`; the public page had not deployed since 25 Sep and deploys again) and the app review
fold (PR #3). App and engine detail: `native/README.md` (the "App fold" section covers PR #3).

- **Verified 19-20 Oct on greg-mb-16 (macOS 26.6, Xcode 27.1, Node 26):** `npm test` 198 pass, 1 skipped (Windows-only),
  0 fail, with the recordings present; `swift test` in `native/PogoReader` 166 + 578, 0 failures (with the real-data
  checks on: `POGO_PARITY=1 POGO_DEVICE_RUNS=~/Developer/personal/pogo-frames/device-runs`); the app builds signed and
  unsigned. The live page (https://dare33.github.io/pogo-assist-plus/) loads with no errors and shows the 10 Oct rankings.
- **Review:** every merge went through an Opus and a Sol (Codex) review; PR #3 took five rounds. Its stated limits and
  remaining findings are in the PR #3 description and the README's "App fold" known limits.
- **Not verified anywhere:** the app's own screens and flows after PR #3 (no simulator on this Mac; the app target has no
  unit tests). Before the next TestFlight upload, on a phone: finish a scan, kill the app, reopen; start a second scan
  while one waits; rename an account; re-scan from the Box; check the "Try again" explanation shows over the review screen.

**Open decisions and checks (Greg):**
1. **Report upload: settled 20 Oct.** The TestFlight builds include it ("Make scans better" shows) and use a publishable key
   (all four signing files on greg-mac-14 checked by Greg). The app's privacy manifest declares what a report sends from
   build 4 on (PR #5: Gameplay Content, Other Diagnostic Data, Performance Data, Product Interaction, Other User Content;
   not linked, no tracking) and App Store Connect's App Privacy answers match (Greg, 20 Oct). Not checked: that the
   Supabase `scan-reports` bucket allows uploads only (no read or list with that key).
2. **Build 3 is in App Store Connect** (Greg, 20 Oct). The next upload is build 4 (`project.yml`), after the phone checks above.
3. **Stable account IDs:** plan written, not approved: `docs/stable-account-ids-plan.md` on local branch
   `claude/great-moore-21a56d` (commit 1b276fb, not pushed), with 10 open decisions at its top. Accounts are identified by
   name today, which is why rename needed a journal and why reusing an old account name can misfile a scan.
4. **Hand-paged scans** fold two Pokémon with the same CP and HP but different IVs into one `ivs-disagree` row (rule from
   bf12a12; the Darentas Fidough 768 / 89 pair is the known case). Keep, or split when each bar state clearly holds?
5. **`native-fast-reader`:** an unadopted faster Vision mode, kept unmerged. Merged branches on GitHub can be deleted.

**Setting up a machine:** `npm ci` (Node 20+); Xcode with `sudo xcodebuild -runFirstLaunch`; `brew install xcodegen ffmpeg`;
sign in to the Apple developer account in Xcode and copy `native/PogoAssist/Config/Signing.local.xcconfig.example` to
`Signing.local.xcconfig` with the team id (git-ignored); recordings from Google Drive `F. Hobbies & Gaming/Pogo Assist
recordings/tests/` into `recordings/`; the device logs and frames (`pogo-frames`, about 19 GB, copied from Mac to Mac) into
`~/Developer/personal/pogo-frames`. Signed builds ask for the keychain: answer Always Allow once.

**2 Oct 2026: proof 2, the live-read prototype** (history; the app grew from it and is merged, see above).
`native/` holds a Swift package with the appraisal-screen reader ported from `src/extract/` on
`extractor-read-faults` (Apple Vision for the text), a live grouper, an Xcode project with the app
and a ReplayKit broadcast extension, Mac tools and comparison scripts; see `native/README.md`.
**Verified (MacBook, Xcode 26.6, commit 52c415d):** 110 Swift tests pass; the app and extension
compile for the iOS simulator unsigned. Against the JavaScript reader on the same 5 fps frames
(Swift at 750 px through 420 pixel buffers, both through the JavaScript grouping, measured at
e4ab948): darentas parts 1 to 3 agree on name and CP for 445 of 448, 767 of 779 and 144 of 147
JavaScript rows; v3 109 of 110; pogo-test-fast 21 of 21; marathon-phone 42 of 45.
**Not verified:** anything on a device. Mac peak footprint with Vision is 150 to 165 MB against
the extension's limit of about 50 MB; whether iOS charges the extension the same is unknown.
**Review:** three rounds (Opus-tier reviewer and Sol-tier cross-vendor); the last found no
blocker for a first device run but timing flaws in the swipe detection, folded in 7dfb20a and
addc6ef; a fourth round on 4898acc found the extension sound and the live grouper not; the grouper pass that followed (7b2c7cc, 6a9d29d) is NOT reviewed. **The review gate is not passed.** `npm test` on the Mac: 129 pass,
4 skipped, 1 fails (a Windows path assertion in `test/node/ffmpeg.test.js`).

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
processed the `dare33` subfolder as the account; the 30 Sep claim that `extract-box.cmd` ran with
arguments is withdrawn: argument-driven launches were broken until the 1 Oct fold below; `scripts/extract.mjs` on one clip still gives its 4 rows.

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
place; the launcher rebuilds its arguments one at a time (untested until the 1 Oct fold, which found it
failed for every argument-driven launch); per-clip flagged counts come from the final rows; an empty-window warning is printed once.

**Post-merge review fold (1 Oct 2026)** on 2fa7a45 (Opus and Sol 5.6 agreed), all folded: the launcher
took its own folder after `shift`, so every argument-driven launch failed with MODULE_NOT_FOUND (now
captured first; an empty argument no longer drops the ones after it); the page's advisor now leaves
out every `no-level-fits` and `hp-mismatch` row; the duplicate-account check follows an inbox that
really exists and compares folder paths case-insensitively only on Windows; the export date counts
a failed newest clip, so its stale partial is found; the gap warning names the window and the
total count. Verified 1 Oct on Windows, Node 24, from `cmd /c` as Explorer starts it: a folder path
with spaces, parentheses and `&` reached the script and wrote an export (4 rows from the trimmed
clip); `"C:\" --out-dir "<folder with spaces>"` reached the script's own "No clips" message (no
drive-root export run). A launcher test runs `cmd /c` with a nonexistent folder and fails on the
old launcher. Tests: 131 passing, 3 skipped (`npm test`).

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
