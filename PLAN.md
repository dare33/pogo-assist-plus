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

## Phase 1 — Extractor prototype

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

## Remaining open items

- Where the code lives: its own repository (recommended, e.g. `dare33/pogo-assist-plus`, kicked off with the project-initiation suite from the second brain) or a folder in this workspace to start. Decide before phase 0a.
- The first iPhone 16 Pro recording, 20 to 50 Pokémon, both passes, for the codec spike and the first fixtures.
- Whether the phase 0 page should also accept the Calcy IV CSV from day one or add it after Poke Genie works. Poke Genie first is the default.
