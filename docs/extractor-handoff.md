# Extractor handoff — build spec for the overnight session

_Written 25 Sep 2026. Goal: a screen recording of Pokémon GO storage in, a roster CSV out, with no
live scanning. This is the project's top priority; everything else in PLAN.md waits._

## Why

Poke Genie's scan reads the screen live during a broadcast and drops Pokémon when frames are
missed. Recording first and processing the file afterwards has no such failure, and a file can
be re-run whenever the pipeline improves. Greg's recording protocol: open a Pokémon, tap
Appraise (the Willow panel stays open across swipes), swipe through storage pausing about a
second on each. Must work for iPhone and iPad recordings, and for files that have been
re-encoded by a messenger or a trimmer (pillarboxed, downscaled).

## What exists

- `src/` advisor modules, `data/gamemaster.json` (base stats), `src/cpm.js` (CP and HP formulas,
  CP multipliers), `src/pvp-rank.js`, `src/import/pokegenie.js` (the CSV layout to emit).
- `experiments/ocr-test.mjs`, `experiments/crop.mjs`, `experiments/segment-test.mjs`: throwaway
  scripts that proved the approach on 25 Sep. Read them, then replace them with real modules.
- `data/tessdata/eng.traineddata` (tessdata_fast) for tesseract.js 7, already a dependency.
- ffmpeg is not on the PATH in the cloud container; `pip install imageio-ffmpeg` provides a
  binary at `python3 -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())"`.
  Chromium in the container has no H.264 decoder, so browser video decode cannot be tested
  there; test frame logic on PNGs instead.

## Fixtures

Recordings are not in git (they show catch locations). Greg attaches them to the session:
`greg-2026-09-25-whatsapp.mp4` (384×848 H.264, 60 fps, 42 s, worst case) and
`greg-2026-09-25-trimmed.mp4` (1920×1080 landscape, phone content pillarboxed to about 498 px
wide, 30 fps, 10 s), plus the untrimmed original if he has it. Save them under `recordings/`
(gitignored). Expected values, from the Poke Genie export in `fixtures/`:

| Pokémon in the recording | CP | HP | IVs | Notes |
|---|---|---|---|---|
| Mewtwo (shown as Mega Mewtwo Y) | 3673 | 145 | 15/15/15 | Level 20; all three bars full pink |
| Zamazenta | 2692 | 137 | 13/12/14 | |
| Zamazenta | 2651 | 135 | 12/10/11 | |
| Xurkitree | 3028 | 145 | 15/14/15 | Level 27 per the export |
| Xurkitree | 2223 | 125 | unknown | Caught after the export; a genuine new Pokémon |

Acceptance: both recordings produce these rows with the right CP, HP, name and IVs, with no
duplicates and no missed Pokémon, and the report says which frame each value came from.

## Findings from the 25 Sep experiments (use them)

- **Content rectangle.** Average brightness per column; the widest run of columns above a small
  threshold is the phone screen. Works on the pillarboxed file. Do the same for rows to handle
  letterboxing. All later coordinates are fractions of this rectangle.
- **OCR regions** (fractions of the content rect, x, y, w, h), 2× upscale, tesseract page
  segmentation mode 7, character whitelist: CP `0.25, 0.02, 0.5, 0.07` white text, invert
  before OCR; name `0.1, 0.39, 0.8, 0.07`; HP `0.2, 0.455, 0.6, 0.04` reads "145 / 145 HP".
  Name read at 90% confidence and HP at 83% on the 498 px wide file; CP text was correct but
  tesseract reports 0 confidence for whitelisted digits, so validate CP by the solver, not by
  confidence. Regions shift on iPad; anchor them on found text where possible.
- **Appraisal bars.** Three rows (Attack, Defense, HP) under the star stamp, each a track of 15
  units drawn as 3 blocks of 5. Fill fraction × 15 rounded gives the IV. Full bars are pink, partial
  orange, empty track grey. The panel's vertical position moves between frames (roughly y 0.68
  to 0.85), so find it by OCR'ing "Attack" in the band x 0.05–0.5, y 0.60–0.90, or by finding the
  three grey tracks, then measure each bar. Star stamp (0 to 4 stars) is a cross-check on the sum.
- **Segmentation.** Mean absolute difference of a downsampled signature of the top 46% of the
  content rect: swipes spike to 25 to 55, settled frames sit at 2 to 3, but Mewtwo's Mega aura kept
  the sprite area at 7 to 9 while settled. Exclude the sprite (use the CP band and the name band
  only) and settled frames will be clean. A segment is the run between two spikes; keep the
  sharpest 3 settled frames (Laplacian variance) per segment.
- **Frame rate.** 5 fps is enough with the one-second pause.

## Build, in order

1. `src/extract/image.js`: content rect, crop by fraction, grayscale, invert, upscale, Laplacian
   sharpness, all on a plain `{width, height, data}` RGBA buffer so Node (pngjs) and the browser
   (ImageData) share it.
2. `src/extract/segment.js`: signature, diff series, segments, best frames.
3. `src/extract/ocr.js`: tesseract.js worker with the regions above, whitelist per region, and
   a `findText(band, word)` for anchoring on "Attack".
4. `src/extract/bars.js`: locate the panel, measure three bars, return IVs and a confidence.
5. `src/extract/solve.js`: given name, CP, HP, IVs, find the level from `src/cpm.js` (Mega forms:
   map "Mega X Y" names to the base species and use the Mega's stats for the CP check); exactly one
   level = validated; none = flag the row.
6. `src/extract/merge.js`: dedupe identical consecutive segments (the same Pokémon settled twice),
   never dedupe non-adjacent identical rows.
7. `scripts/extract.mjs <video> [--fps 5] [--out roster.csv]`: ffmpeg to frames in a temp dir,
   run the pipeline, write a CSV in the Poke Genie column layout (`src/import/pokegenie.js` reads it
   back) plus `review.json` listing flagged rows with the frame file and the raw reads.
8. Tests in `test/extract/`: unit tests on small synthetic buffers for image and segment
   functions; an integration test that runs on the recordings when present under `recordings/`
   and skips (not fails) when absent.
9. `web/extract.html`: the browser version. `<video>` plus canvas frame grabs at 5 fps (WebCodecs
   later), the same modules, a progress bar, the CSV offered for download and a "Load into
   advisor" button that feeds `web/app.js`. Cannot be decode-tested in the container; keep it
   thin and mark it untested in STATUS.md.

Leave alone: the advisor, the tier data, the Pages workflow. Do not add Python to the shipped
pipeline. Do not send frames to any API.

## Report back

Update `STATUS.md` with what works, what was measured (accuracy per field on each recording),
and what is untested. Write `docs/extractor-report.md` with the per-recording results table.
Commit on branch `extractor`, push after each milestone. Merge to `main` only if `npm test`
passes and both recordings meet the acceptance table.
