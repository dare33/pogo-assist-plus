# Morning test — the browser extractor

_For Greg. This walks through the four recordings against the extractor page. It only works
from the deployed site (`https://dare33.github.io/pogo-assist-plus/web/extract.html`) or a local
static server such as `npx serve .` — not by double-clicking `extract.html` from a `file://`
path — because the page imports ES modules and starts a tesseract.js worker, both of which
browsers block from `file://`. Once this branch is merged to `main` and the Pages build has run,
the page is at that URL._

## Before you start

- The first time the page runs OCR in a given browser, it downloads `data/tessdata/eng.traineddata`
  (about 4 MB) and the tesseract.js worker/core files from jsdelivr. Give it a few seconds on a
  slow connection; after that it's cached.
- Nothing is uploaded. The video, the frames and the OCR all stay on your device — the page says
  so, and you can check the browser's network tab if you want to be sure.
- Recordings are big; don't attach them anywhere, just pick them from local storage / Photos.

## What a decode failure looks like

If your browser can't decode the file's video codec, the page shows a red error box instead of a
progress bar, with a message like *"This browser could not decode … (format not supported)"*. The
usual cause is HEVC/H.265 (the untrimmed iPhone and iPad originals) on a browser/OS combination
that doesn't have an HEVC decoder — Windows Chrome, mainly. If you see that:

- Try the same file in Safari on the iPhone or a Mac first (both decode HEVC natively).
- Or re-export the file as H.264 (AirDrop it to a Mac and re-save, or send it through WhatsApp/
  Clipchamp the way the two re-encoded fixtures were made) and try again.
- Or run it through the command-line version instead: `node scripts/extract.mjs <file>` from a
  checkout of this repo (needs ffmpeg; see `scripts/extract.mjs`'s header comment).

## Which browsers to try

Try each recording in whichever of these you have to hand — you don't need all four for every
file, but between them we want to know: does Windows Chrome handle H.264 recordings fine, and
does HEVC only work on Apple's own browsers?

- **iPhone Safari** — should decode everything, including the HEVC originals.
- **Mac Safari** — same.
- **Windows Chrome** — expected to handle the two H.264 recordings; the HEVC ones may fail to
  decode (see above). Worth trying anyway in case Windows has an HEVC extension installed.

## The four recordings, in order

### 1. `iphone-clipchamp-trimmed.mp4` — start here

1920×1080 landscape, H.264, about 10 seconds. The Pokémon GO screen is pillarboxed to a narrow
strip in the middle of the frame — this is the easiest file and a good first check that the page
works at all.

**Expect:** 4 rows —

| Name | CP | HP | IVs | Level |
|---|---|---|---|---|
| Mega Mewtwo Y | 3673 | 145 | 15/15/15 | 20 |
| Xurkitree | 3028 | 145 | 15/14/15 | 27 |
| Zamazenta | 2692 | 137 | 13/12/14 | 25 |
| Zamazenta | 2651 | 135 | 12/10/11 | 25 |

No flags expected on any of the four rows. Takes well under a minute to process (about 50 frames).

### 2. `iphone-whatsapp.mp4`

384×848 portrait, H.264, 42 seconds — the same recording sent through WhatsApp, so it's small
and blurrier. About 212 frames, so it'll take longer (OCR is the slow part, not the video decode).

**Expect:** the four Pokémon above plus Xurkitree 2223, in among many more (the untrimmed recording covers
the whole box; the CLI found 46 rows, 31 of them flagged) — lower accuracy than the trimmed file,
so expect flags such as `ivs-unread`, `bars-unsettled` or `ambiguous-ivs:N-fit`. Check the four
known Pokémon above come out right; the rest is a general accuracy check, not a pass/fail line.
One known miss: Mega Mewtwo Y's pink CP text is not readable at this size, so the CLI gives it
CP 873 with a `no-level-fits` flag (and "Load into advisor" leaves such rows out).

### 3. `iphone-original.mp4`

1320×2868 portrait, HEVC, 42 seconds, about 48 Pokémon expected. This is the file most likely to
fail to decode on Windows Chrome (see "What a decode failure looks like" above) — try it on
iPhone or Mac Safari first. It's the full, undegraded recording, so if OCR accuracy is going to
be good anywhere, it's here.

### 4. `ipad-original.mp4`

2266×1488 as stored, rotated to 1488×2266 portrait, HEVC, about 17 seconds; the CLI found 20
Pokémon, mostly Meltan. Also HEVC — same browser caveat as above. This one also proves the layout isn't
hard-coded to the iPhone's proportions (the iPad's panel sits in different places on screen); if
rows come out with plausible CP/HP/IV combinations at all, that's the layout-independence check
done, even if a few flag for review. It ends with the iPad's Control Centre pulled down over the
game for a couple of seconds — don't worry if the last row or two look odd, that's why.

## What the flags mean

| Flag | Meaning |
|---|---|
| `bars-unsettled` | The appraisal bars were still animating on every frame this Pokémon got; the IVs are a best guess. |
| `ivs-corrected-from-A/D/H` | The bars read A/D/H, which fits no level; the one set within one unit that fits was used. |
| `ambiguous-ivs:N-fit` | Nothing near the bar read fits CP and HP; N IV sets do, the nearest is shown. Check this one in the game. |
| `ivs-unread` | No appraisal panel was readable; level is a range from CP and HP. |
| `hp-unread` / `hp-computed` | The "n / n HP" text was covered (Willow's hair does this on the iPad); HP is missing, or computed from the solved level. |
| `cp-chosen-X-over-Y` | Frames disagreed on the CP; X fits the HP and bars, Y was read more often. |
| `no-level-fits` | Name, CP, HP and bars cannot be reconciled at any level: a misread somewhere. |

Rows with no flag solved to exactly one level from name, CP, HP and bars, which is the same
check Poke Genie does.

## Already verified without a video

The OCR side of the page was run in a real browser (Chromium) against the local site with six
PNG frames of the trimmed recording fed in place of video frames: tesseract.js, its worker and
core loaded from jsdelivr, the language file loaded from `data/tessdata`, and the four expected
rows came out with no flags. The "Load into advisor" hand-off was also exercised: the advisor
page opened with the four Pokémon and their builds. What remains untested is only the `<video>`
decode of your actual files, which is what this morning's run is for.

## While it's running

- A progress bar and a live count of Pokémon found update as frames are processed.
- Elapsed time is shown; OCR is the slow part, so don't judge speed by the video's own length.
- **Stop** cancels the run and still shows whatever rows were found up to that point — useful if
  you want to sanity-check the start of a long recording without waiting for the whole thing.

## When it's done

- The results table shows index, name, form, CP, HP, IVs, level and any flags per row, plus which
  frame each reading came from.
- **Download CSV** saves a Poke Genie-format file you can open directly, or drop into the advisor
  at the main page.
- **Download review JSON** saves the full row and flag detail — this is the one to send back to
  me. Please send it for all four recordings you manage to run, even the ones that look right, so
  the acceptance numbers above can be checked against real output rather than eyeballing the page.
- **Load into advisor** jumps straight to the build-decision page with these rows already loaded.

## Sending results back

For each recording you try: which browser/device, whether it decoded, and the downloaded review
JSON (or, if it failed to decode, the error message text). That's enough for me to work out what
still needs fixing.
