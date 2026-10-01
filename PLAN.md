# Pogo Assist+ — build plan

_Revised 25 Sep 2026 from Greg's "Collection Extractor" draft. The change in one line: build
the advisor first on top of existing exports, and build our own extractor second, only for the
fields those exports lack._

**Decisions taken 25 Sep 2026:** name is Pogo Assist+; phase 0 (advisor) goes first; family
will need the extractor, so phase 2 is committed and follows Path A (browser-only); first
recordings come from an iPhone 16 Pro.

## Goal

A free tool that turns a Pokémon GO storage export into build decisions: what to power up,
what to evolve, what is missing, how to get it, and in what order. The tier data, obtain
routes and build-plan logic already exist in `pokemon-go-tier-list/`; this project automates
what was done by hand there.

## What changed from the draft and why

| Draft | Revised | Reason |
|---|---|---|
| Build a screen-recording extractor first | Import Poke Genie and Calcy IV CSVs first; extractor is phase 2 | Those tools already do recording-to-IVs well and free. The unfilled gap is the advice layer. |
| Frames go to the Anthropic API | Local OCR by default; Claude only as an optional fallback | A free download for family cannot depend on each user holding an API key. |
| Python CLI plus Streamlit | Phase 0 and the advisor ship as a static web page; Python stays a personal prototyping tool | Family will not install ffmpeg, OpenCV and Python. A static page is zero-install and free to host. |
| Appraisal visible while swiping, dust used to narrow level | Two recording passes: appraisal pass (IVs) and info pass (moves, dust, candy, XL) | The appraisal overlay hides dust and moves. Exact IVs plus CP and HP already pin the level. |
| Pixel-geometry bar calibration per device | Colour-threshold the 15 bar segments and count them | Resolution-independent, no calibration step. |
| Fingerprint upsert across recordings | Snapshot semantics: each full scan is a snapshot; latest is the collection | Power-ups between scans create phantom duplicates under fingerprinting. |

## Phase 0 — Importer and advisor (the product)

**Inputs.** Poke Genie CSV (49 columns; sample in `pokemon-go-tier-list/inbox/`) and Calcy IV
CSV. Both give species, form, CP, HP, IVs, level, shadow and purified flags, and Poke Genie
adds PvP rank per league. Neither gives moves, candy or XL counts; the advisor treats those as
unknown and says so.

**Reference data**, loaded from files the tool ships with and refreshes from public sources:

- Game master: PvPoke `gamemaster.json` (base stats, CP multipliers, moves, forms). Cache a copy; the live file is at raw.githubusercontent.com/pvpoke/pvpoke/master/src/data/gamemaster.json.
- PvP rankings: PvPoke `rankings-1500/2500/10000.json` (same repo) rather than recomputing.
- Tier tables and obtain routes: convert the markdown tables in `pokemon-go-tier-list/` to JSON with a small script. That project stays the editable source; this tool consumes the JSON.

**Logic** (all deterministic, no model calls):

1. Parse and normalise the CSV; map species and form names to game-master IDs.
2. For each Pokémon, find tier hits per game area (raids by type, high-tier raids, Rocket, gym, GL, UL, ML, Max), including hits via its evolution line.
3. Compute build cost from current level to the target level for each hit: dust, candy, XL, Shadow multiplier, second-move cost. Formulas and tables live in one module with unit tests.
4. Flag required moves that are legacy or Community Day only, with the obtain route.
5. Rank builds by value (tier weight × number of areas served ÷ cost) into the phased plan format of `11-build-plan.md`.
6. Gap list: S and A entries with no candidate in the box, each with its obtain route.
7. Storage hygiene: duplicates by species, which copy to keep, how many to transfer.

**Output.** A page with the same tabs as the current tier list plus "Your box", "Build plan" and
"Next steps", generated from the user's own CSV. CSV and JSON export of the build plan.

**Delivery.** One static HTML page plus JS, hosted free on GitHub Pages. The CSV is read in the
browser with the File API and never uploaded. No install, no account, no cost per run. This
alone satisfies "friends and family can use it for free".

**Tests.** Greg's 25 Sep export is the fixture. Expected outputs are the hand-written
`10-your-box.md` and `11-build-plan.md`; the tool should reproduce their top rows.

**Effort.** Roughly one to two weeks of evenings. Most of the work is data wrangling (name
mapping, form handling) and the cost tables.

## Phase 1 — Extractor (moved to first priority 25 Sep; detailed spec in docs/extractor-handoff.md)

Purpose: prove segmentation and OCR on real recordings and capture the fields the CSV
exports lack (moves, candy and XL counts, Dynamax flag, Mega energy, gender, favourite).

Because phase 2 is now committed to the browser, phase 1 should build the extractor in
JavaScript from the start and use Python only for throwaway experiments (bar-colour
thresholds, OCR accuracy on the game font, segmentation settings). Prototyping the whole
pipeline in Python and porting it later would be a second build of the same thing.

**iPhone 16 Pro specifics.** Screen recordings are 1206 × 2622 at 60 fps, portrait, in a
`.mov` container, H.264 or HEVC depending on the device setting. Two consequences: keep the
frame rate at 5 fps after decode (the 60 fps source is wasted work), and run the phase 2
codec spike below before writing any extraction code, because HEVC decoding differs by
browser. Dynamic Island and the home indicator overlap the top and bottom of the game view;
locate regions relative to detected UI anchors (the CP text, the appraisal panel edge), never
from the frame edges. Recordings that passed through a trimmer or a messenger arrive
re-encoded, sometimes pillarboxed into a landscape frame (seen 25 Sep: Clipchamp output at
1920×1080 with the phone content 608 px wide), so the first step is to find the content
rectangle (non-black columns) and work in its coordinates.

**Recording protocol (README).** Two passes over the same storage order. Do Not Disturb on,
default display scaling, chunks of 50 to 100 Pokémon, one-second pause per Pokémon.

- Appraisal pass: open the first Pokémon, tap Appraise, then swipe through. The appraisal stays open across swipes. Yields name, CP, HP, three IV bars, star rating, flags.
- Info pass: swipe through without the appraisal. Yields moves, dust cost, candy and XL counts, Mega energy, Dynamax badge, buddy and favourite state.

**Pipeline.** Same stage layout as the draft, each stage writing its output so any stage
can be rerun (IndexedDB in the browser build; files on disk for Python experiments):

1. Ingest: video files plus metadata.
2. Frames: WebCodecs decode sampled to 5 fps (ffmpeg for Python experiments). The one-second pause makes 10 fps unnecessary.
3. Segmentation: frame differencing on the name and CP region to find swipes; settled frames by low difference for N frames; keep the 3 sharpest per segment by Laplacian variance. Output a contact sheet for eyeballing.
4. Extraction, local first: Tesseract.js (or an ONNX text model) on anchored regions with a character whitelist for CP, HP, dust, candy; colour-threshold segment counting for the IV bars; icon templates for lucky, shadow, purified, Dynamax, favourite. A Claude vision fallback (`claude-haiku-4-5`, structured output via `output_config.format`) stays optional and off by default: it needs the user's own API key typed into the page, so it is for Greg's runs and for species identification when a nickname replaces the name, never a dependency for family. Cost if every frame went to Claude: about $2 per 1,000 Pokémon, half with the Batches API in a scripted run.
5. Solve and validate: game master base stats and CP multipliers; solve level from CP, HP and exact IVs; a single solution is validated, none means a misread (retry next frame, then escalate, then flag). Dust, when present from the info pass, is a cross-check, not an input.
6. Merge passes by (species, form, CP, HP, IVs, flags) within one snapshot; flag collisions for review rather than dedupe.
7. Review queue: a page in the same web app showing the frame beside the extracted values with confirm and edit. (Streamlit only if a Python experiment needs a quick viewer.)
8. Output: SQLite snapshot plus a CSV in the Poke Genie column layout extended with the new fields, so phase 0 consumes it unchanged.

**Solver test cases.** Level 51 Best Buddy (CP shown only while the buddy is active), Shadow 1.2× and purified 0.9× dust, lucky 0.5× dust, CP floor of 10, half-level ties broken by HP, regional and costume forms, Mega and Primal CP (detect by name and map to base form), Alolan, Galarian, Hisuian and Paldean forms.

**Benchmark.** Record Greg's box and diff against the Poke Genie CSV of the same day. Report
species match, IV match, level match and flagged rate per run.

## Phase 2 — Distributable extractor (committed, Path A)

Family will need the extractor, so this phase is committed and the browser-only path is
chosen. Phase 1 is therefore the first half of phase 2, not a separate prototype. The two
paths, for the record:

| | Path A: browser-only | Path B: desktop app bundle |
|---|---|---|
| How | WebCodecs decodes the recording in the page; Tesseract.js or an ONNX text model runs in-browser; same solver as phase 0 in JS | PyInstaller or Tauri bundle of the phase 1 Python with ffmpeg and OpenCV inside |
| Install | None; a link | Download and run; unsigned-app warnings on macOS and Windows |
| Hosting cost | $0 (static page) | $0 (GitHub release) |
| Per-run cost | $0 | $0 with local OCR |
| Privacy | Video never leaves the device | Same |
| Effort | Three to six weeks: port the solver, tune OCR on the game font, handle Safari and Chrome codec differences | One to two weeks: packaging and testing on two OSes |
| Risk | WebCodecs support (Safari 16.4+, Chrome, not Firefox until recently); OCR accuracy without tuning | Bundle size (hundreds of MB); platform signing; users must move videos from phone to computer anyway |

Path A is chosen because it matches the free-and-zero-install goal and reuses the phase 0
page. A hosted upload service (Path C) is ruled out: it costs money to run, and other people's
recordings would sit on a server.

**Codec spike (do first, half a day).** Tool: `web/codec-check.html`, run on the device with the original file. Record 20 Pokémon on the iPhone 16 Pro, then confirm
the `.mov` decodes through WebCodecs in Safari on iPhone, Safari on Mac and Chrome on
Windows. If it is HEVC and Chrome on Windows refuses it, the fallback is `ffmpeg.wasm`
transcoding in the page (slow but works everywhere) or a README instruction to set the
iPhone to record in the compatible format. The result decides the video ingest design.

## Phase 3 — Native iPhone app (proposed 1 Oct 2026, awaiting Greg's approval)

**Why.** Greg wants friends and family to capture their boxes with as little effort as possible;
a seamless experience is the core goal. The browser path (phase 2) leaves three manual steps no
web page can remove: starting a screen recording, finding and picking a file of 700 MB to 1.5 GB,
and waiting for it to be read. A native app receives the screen live and reads as the player
pages, so there is no recording file at all. Phase 2's page stays as the web viewer and the
route for Android and desktop.

**Decisions taken 1 Oct 2026 (Greg):** go native for iPhone; distribute through TestFlight to
friends and family first (a public App Store listing is a later, separate decision); Greg has a
Mac and an Apple developer account; prove the two unknowns below before building the app.

**What the app does**

- Capture: one tap starts a screen broadcast (ReplayKit Broadcast Upload Extension); the player
  switches to Pokémon GO and pages through storage; the extension reads each detail screen with
  Apple's Vision text recognition and hands rows to the app. Precedent: the open-source
  `BaesTheorem/pogo-lens` reads Pokémon GO this way.
- Paging: by hand, or hands-off with an iOS Voice Control custom gesture (slow swipes about two
  seconds apart) chained to cover a whole box. The app supplies the commands file for the
  player's phone and the shortest possible checklist.
- Box: stored on the device; a later capture of only the new Pokémon merges into it.
- Stats and advice: a concise box view with the existing advisor on top; raid, PvP and gym tips
  from `data/`, tuned over time.

**What no app can do (stays with the player).** An app cannot send touches to another app, turn
Voice Control on, change its settings or import its commands. One-time setup: import the commands
file; turn off Voice Control's Show Confirmation and Show Hints (their labels cover the CP). Each
scan: start the scan in the app, turn Voice Control on ("Hey Siri, turn on Voice Control"), say
the command. Voice Control is optional: without it the player swipes by hand.

**Voice Control commands file (findings, 1 Oct).** An exported `.voicecontrolcommands` file is an
XML property list. A gesture is a keyed archive (`AXMutableReplayableGesture`) of touch events:
finger positions in screen points, forces, timestamps, with `ArePointsDeviceRelative` false. A
chained command (`CACRecordedUserActionFlow`) is a list of repeats of a command identifier. Both
can be generated. Getting the positions right on another phone, in order of preference: (1) a
mid-screen swipe, which needs no precision and may let one file serve every iPhone; (2) the
player gives the app one screenshot and the app sizes the gesture to it; (3) a table of screen
sizes with proportional scaling, only if the game's layout proves proportional.

**Proofs before any app work**

1. *Generated commands file.* A file with a synthesised nine-swipe gesture ("Pogo swipe test")
   and a twelve-repeat chain that was never spoken ("Pogo chain test") is imported on Greg's
   iPhone. Pass: both import, the gesture pages one Pokémon per swipe, and the chain plays all
   twelve repeats. Then the same file on a second, different-sized iPhone.
   **Result, 1 Oct 2026 (Greg's iPhone, 440 x 956 points, iOS 27.2 beta; iPad mini 6; clips read
   with `scripts/extract.mjs` on Windows): passed.** Generated files import. A synthesised swipe
   (x 340 to 75 at y 340, 0.85 s, one every 2.1 s) moves one Pokémon per swipe and gives 7 frames
   at 5 fps with the appraisal bars read. No opening touch is needed; an opening *tap* closes the
   appraisal panel and must not be used. Chains never spoken aloud play in full: 12 repeats of 9
   swipes and 40 repeats of 3. A single gesture of 50 swipes (104 s) plays in full on both
   devices. A faster pace (0.6 s swipe, one every 1.6 s) gives 5 to 6 frames and still reads, on
   a 20-Pokémon sample. At the end of the list the game stays on the last Pokémon (no wrap), so
   overshooting is harmless. The phone's positions, unscaled, also work on the iPad mini, as do
   proportionally scaled ones, so one file may serve every device. At a join between repeats
   the Pokémon on screen gets about 1.7 s (4 to 5 frames). Voice Control can mishear similar
   command names ("Pogo test long" probably ran as "Pogo test phone"), so shipped commands need
   distinct names. Reading faults found on the way, all in the extractor: Nidoran♂ and Nidoran♀
   names unread, Paras unread twice, CP hidden behind tall models (Zapdos, Moltres), and more
   unread or misread rows on the iPad layout than on the iPhone.
   **Design consequence:** the app asks for the storage count and generates one command sized
   to it (Greg, 1 Oct), built from repeats of a fixed batch.
2. *Live-read prototype.* A minimal Xcode project (app plus broadcast extension) shows name and CP
   for each Pokémon as "Pogo Scan" pages through storage on Greg's phone. Pass: every Pokémon in
   a 50-swipe run is read, within the extension's memory limit (about 50 MB), with the phone
   staying responsive. Built and run on the Mac; this Windows machine cannot build it.

**Build order after the proofs**

1. Reader: port the detail-screen reading (CP, name, HP, appraisal bars, moves) to Swift with
   Vision; benchmark against the darentas box CSV.
2. Solver and advisor: reuse the JavaScript modules in `src/` inside the app (JavaScriptCore or a
   web view) before considering a Swift port, so the web page and the app share one
   implementation and one test suite.
3. Capture flow and first-run setup (commands file, two-line checklist).
4. Box storage, incremental capture, stats view.
5. TestFlight build to two family members; watch them use it; then widen.

**Risks and open decisions**

- **Repository rule.** `CLAUDE.md` says nothing here may "automate input to" the game, and the
  tier-list project says never automate play. Shipping a Voice Control commands file that pages
  through storage is automated input, even though it only reads and uses an Apple accessibility
  feature. Greg to decide: amend the rule to permit read-only paging through the player's own
  storage, or keep the commands file out of the repo and the app. Players must be told that
  Niantic's terms discourage automation.
- App Review may object to a public listing that documents automated swiping; TestFlight avoids
  full review but builds expire after 90 days.
- Voice Control behaviour on other iOS versions is unknown (Greg's phone runs an iOS 27.2 beta).
- Where the Swift code lives: a folder in this repo (shared data and tests) or its own repo.
- Android has no Voice Control; Android players use the web page or page by hand.

## Tech stack

- Phase 0 and the extractor: a small Vite project in plain JavaScript or TypeScript. PapaParse for CSV, Tesseract.js for OCR, WebCodecs for video, IndexedDB (via `idb`) for snapshots and intermediate stages. Hosted on GitHub Pages.
- Experiments only: Python 3.11+, ffmpeg, OpenCV, Pillow, pytesseract. Kept in an `experiments/` folder, never shipped.
- Optional Claude fallback: the `anthropic` SDK in a script for Greg's own bulk runs; in the page, the user's key is held in memory only and never stored.

## Phases and check-ins

1. Phase 0a: CSV import, name and form mapping, cost tables with unit tests. Check in with a console dump of Greg's box annotated with tier hits.
2. Phase 0b: build ranking, gap list, hygiene. Check in against `11-build-plan.md`.
3. Phase 0c: the web page and GitHub Pages deploy. Share with one friend and watch them use it.
4. Codec spike on the iPhone 16 Pro recording.
5. Phase 1a: WebCodecs frames and segmentation with a contact sheet in the page.
6. Phase 1b: Tesseract.js OCR, bar counting, solver, benchmark against the Poke Genie CSV.
7. Phase 1c: review queue, two-pass merge, export in the extended CSV layout.
8. Phase 2: hardening for other people's phones (Android sizes, older iPhones), README with the recording protocol, optional Claude fallback.
9. Phase 3 (proposed): the two proofs, then the native iPhone app in the build order given in its section.

## Remaining open items

- Where the code lives: its own repository (recommended, e.g. `dare33/pogo-assist-plus`, kicked off with the project-initiation suite from the second brain) or a folder in this workspace to start. Decide before phase 0a.
- The first iPhone 16 Pro recording, 20 to 50 Pokémon, both passes, for the codec spike and the first fixtures.
- Whether the phase 0 page should also accept the Calcy IV CSV from day one or add it after Poke Genie works. Poke Genie first is the default.
