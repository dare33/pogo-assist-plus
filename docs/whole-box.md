# Recording and extracting a whole box

One clip per pass, one folder per account, one merged Poke Genie-layout CSV out. This is the
batch mode added on 30 Sep 2026; single recordings still work with `node scripts/extract.mjs`.

## Recording protocol

- Open a Pokémon in storage and tap Appraise so the Willow panel stays open for the whole clip.
- Spend about one second on each Pokémon. Faster swipes give one frame per Pokémon and the bars
  may still be animating (rows come out flagged `bars-unsettled`).
- One clip per pass. A long box is fine as several clips: when you stop and restart, begin from the
  last Pokémon you saw. The repeated Pokémon at the join are dropped automatically (see "How clips
  are joined" below).
- Record the Shadow-filtered pass (search `shadow`) as its own clip with `shadow` in the file name,
  for example `03-shadow.mp4`. Its Pokémon are matched to the same Pokémon in the main pass and the
  Shadow column is set to 1. Optionally do the same with a `purified` clip (column set to 2).
  Do not use the word `shadow` or `purified` in the name of any other clip: the pass is decided by
  that word appearing anywhere in the file name (not the folder).
- Put each account in its own folder on Drive:
  `F. Hobbies & Gaming/Pogo Assist recordings/<account>/`, holding only that session's clips.
  Name the clips so they sort in order: `01-`, `02-`, `03-`. Sorting is by name with numbers
  compared as numbers (`clip2` before `clip10`); `--order mtime` sorts by modified time instead.

## Running it

- Windows: drag the folder onto `extract-box.cmd` in the repository (or double-click it and paste
  the folder path). The window stays open at the end. If `%USERPROFILE%\dare33\pokemon-go-tier-list\inbox`
  exists the CSV is also copied there.
- Anywhere: `npm run extract:box -- "<folder>"` or `node scripts/extract-box.mjs "<folder>"`.
  Several folders can be given, each handled as an account or a parent of accounts. `--account`
  is only for one folder that holds clips directly: with several resulting accounts it is refused
  (exit 2), and so are two accounts of the same name whose exports would land in the same place (a
  shared `--out-dir` or `--inbox`, or the same folder given twice); without those each account writes
  into its own folder and `C:\one\same` and `D:\two\same` both run. Both checks happen before
  anything is read. When calling the script directly, write a drive root as `C:\.` or `C:/` (a
  quoted `"C:\"` loses its closing quote on Windows; `extract-box.cmd` fixes that for you, including
  for `--out-dir` values with spaces). Options: `--account NAME` (letters, digits, `.`, `_`, `-`; default:
  the folder name), `--fps 5`, `--order name|mtime`, `--inbox DIR`, `--out-dir DIR` (must exist;
  default: the folder), `--ffmpeg PATH`, `--force` (ignore the cache), `--quiet`. Unknown options,
  and options missing their value, are an error (exit 2).
- A folder with no clips but with subfolders that have clips is treated as several accounts: each
  subfolder is processed separately.
- The browser page (`web/extract.html`) takes several files at once and merges them the same way.
  After you choose the files it lists the clips in order with a "Shadow" and a "Purified" tick per
  clip (ticked from the file name when it says so) and a Start button. On an iPhone the Photos
  picker cannot rename a video, so ticking the box there is how you mark the Shadow clip. The page
  decodes in the browser, so HEVC recordings need Safari (see `docs/morning-test.md`).
- ffmpeg is found automatically, and only when a clip actually needs reading: `--ffmpeg`, the
  `FFMPEG` variable, PATH, then winget and imageio-ffmpeg install locations. A folder whose clips
  are all cached merges on a machine without ffmpeg. If none is found when one is needed the tool
  says how to install it (`winget install Gyan.FFmpeg` or `brew install ffmpeg`) and exits 2.
- Disk: each clip is decoded to PNGs 60 seconds at a time and the frames deleted as they are read
  (about 12 MB per second of recording, so under about 720 MB in `%TEMP%` whatever the clip length).

## Output files

Written next to the clips (or in `--out-dir`): `poke-genie-export-<account>-<YYYY-MM-DD>.csv` and
`poke-genie-export-<account>-<YYYY-MM-DD>.review.json`. The date is the **recording date**, the local
date of the newest clip that was read (not the day you ran it), and it is also the CSV's scan date.
So re-running on unchanged clips, on any day, rewrites the same file byte for byte and the copy in
the inbox is replaced rather than a second file added.

If any clip failed, the files are named `...-<date>.partial.csv` and `...-<date>.partial.review.json`
instead, the inbox copy is skipped, and the command exits 1. A complete export from an earlier run is
never overwritten by a partial one. The failed clips are listed under `failedClips` in the review
JSON; Pokémon from them are missing. When a later run is complete, the stale `.partial` files for the
same recording are deleted and the log says so.

If a file cannot be written (for example the CSV is open in Excel) the tool says
`could not write <path>: <reason> (is it open in Excel?)`, carries on with the other accounts, and
exits 1.

## How clips are joined

- At each join the tail of the merged list is compared with the head of the next clip. Rows match
  when name, form and CP are equal and HP and IVs do not conflict. HP or IVs that were only guessed
  (`hp-computed`, `bars-unsettled`, `ivs-corrected-from-...`, `ivs-disagree`) never count as a
  conflict, and a missing HP or IVs never does either.
- The **smallest** overlap that is consistent (at most 10 rows) is dropped. For a run of distinct
  Pokémon only the true overlap is consistent, so this loses nothing; for identical Pokémon (a run
  of the same Meltan) it drops the fewest, so no real Pokémon is lost.
- When **more than one** overlap length is consistent, the rows between the smallest and the largest
  may be repeats that were kept. Every head row up to the largest fitting overlap, and the tail rows
  they would repeat, get `boundary-weak`, and the summary lists them:
  `01-a.mp4 → 02-b.mp4: 1 duplicate row dropped (Meltan 150); 2 more may be repeats: Zapdos 1969, Meltan 150 — check (flagged boundary-weak)`.
  The review JSON has `alternatives` (every consistent length) and `maybeRepeated` on the boundary.
- A join is also **weak** when any matched pair had a missing or guessed HP or IVs; its rows get
  `boundary-weak` and the dropped rows are listed by name and CP.
- A join where **nothing matches** is reported too, since restarting on the last Pokémon you saw
  should always overlap: `01-a.mp4 → 02-b.mp4: no overlap found (tail Meltan 300, head Meltan 308):
  if you restarted on the last Pokémon you saw, it may be listed twice — check` (a misread at the
  join is the usual cause). It is recorded in the review JSON with `unmatched: true`.
- Only rows at a join are ever dropped: two identical Pokémon in the middle of a box stay two
  Pokémon. Two different Pokémon of the same name and CP with different HP or settled IVs are never
  merged.
- Where a dropped row had information the kept row lacked (HP, IVs), it is filled in, and flags that
  no longer apply (`ivs-unread`, `ambiguous-ivs`, `hp-unread`, IV-guess flags when the kept IVs are
  settled) are removed. `no-level-fits` stays only when the kept row itself carried it (or the HP swap below disagreed): a
  misread partner does not condemn a row whose own read solved. If a computed HP is replaced by a different
  read HP, the row is flagged `hp-mismatch:<computed>/<read>` (its IVs and level were solved for the
  old HP) and goes on the "check these" list. Settled IVs are preferred over a guess whatever the
  number of frames.

## Shadow and purified passes

- A shadow-clip Pokémon matches a main-pass row when name, form and CP agree and HP and IVs do not
  conflict. A **strong** match has both HP and both IV sets read and equal. It is preferred over a
  weak candidate.
- Exactly one strong match: that row is marked Shadow (`matched`). Several: the first is marked and
  flagged `shadow-match-ambiguous` (`ambiguous`); which of identical Pokémon is the Shadow cannot be
  told from the screen.
- A **weak** match (either side lacks HP or IVs, or they were guessed) still marks the row but adds
  `shadow-match-weak` (`weak`), and the row goes on the "check these" list. If the main-pass row
  lacked HP or IVs and the shadow row has them, they are copied across.
- No match: the Pokémon is added to the end of the list as a Shadow (`appended`). This is what
  happens when the main pass was recorded with a `!shadow` search. Note the limit in that mode: a
  shadow Pokémon with the same name, CP and HP as a non-shadow one and no readable IVs is marked
  weak on that non-shadow row rather than appended, so `shadow-match-weak` rows deserve a look.
- With a `purified` clip present the summary line reads `shadow/purified passes`.

## Cache files

Each clip gets `<clip>.extract.json` beside it: the raw per-frame readings (not the rows), the frame
count and time taken, keyed by file size, modified time, fps and a hash of the extractor. The hash
covers the frame-reading code (`frame`, `ocr`, `bars`, `image`, `layout`, `names`, `png`, `node` under
`src/extract/`), the decode step (`src/node/extract-video.js`), `data/gamemaster.json`, the full
contents of the OCR language file, and the installed versions of `tesseract.js` and `pngjs`. On every
run the rows are rebuilt from the readings, so fixes to the solver, merge and export take effect
without re-reading video. If the reading code or data changed, the tool says "extractor changed since
the cache was written" and re-reads that clip. A cache with no readings is re-read. `--force`
re-reads everything. The `.extract.json` files are safe to delete.

## Reading the summary

```
shadow pass: 12 matched, 0 appended, 1 ambiguous, 2 weak
```

- If a clip fails (unreadable file, ffmpeg error) the others still run, a `.partial` export is
  written, and the command exits with status 1.
- "Check these in the game" (capped at 40 lines; the rest is in the review JSON) lists the rows worth
  checking: name, CP, HP, clip and flags. It covers `ambiguous-ivs`, `no-level-fits`,
  `shadow-match-ambiguous`, `shadow-match-weak`, `hp-mismatch` and `ivs-unread`. Weak joins are listed on their
  own boundary lines.

## Flags

| Flag | Meaning |
|---|---|
| `bars-unsettled` | The appraisal bars were still animating on every frame this Pokémon got; the IVs are a best guess. |
| `ivs-corrected-from-A/D/H` | The bars read A/D/H, which fits no level; the one set within one unit that fits was used. |
| `ambiguous-ivs:N-fit` | Nothing near the bar read fits CP and HP; N IV sets do. IVs are left blank in the CSV. Check in the game. |
| `ivs-unread` | No appraisal panel was readable; level is a range from CP and HP. |
| `hp-unread` / `hp-computed` | The HP text was covered; HP is missing, or computed from the solved level. |
| `cp-chosen-X-over-Y` | Frames disagreed on the CP; X fits the HP and bars, Y was read more often. |
| `no-level-fits` | Name, CP, HP and bars cannot be reconciled at any level: a misread somewhere. |
| `hp-mismatch:C/R` | Clips were joined and a computed HP (C) was replaced by a different read HP (R); IVs and level were solved for C. Check it. |
| `boundary-weak` | The row is at a clip join that could not be confirmed (several overlaps fit, or a matched pair lacked HP or IVs). |
| `shadow-match-ambiguous` | A shadow/purified row matched several identical main-pass rows; the first was marked. |
| `shadow-match-weak` | A shadow/purified row was matched without both HP and IVs read on both sides. |

The full glossary, with what each flag looks like in practice, is in `docs/morning-test.md`.
