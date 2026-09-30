# Recording and extracting a whole box

One clip per pass, one folder per account, one merged Poke Genie-layout CSV out. This is the
batch mode added on 30 Sep 2026; single recordings still work with `node scripts/extract.mjs`.

## Recording protocol

- Open a Pokémon in storage and tap Appraise so the Willow panel stays open for the whole clip.
- Spend about one second on each Pokémon. Faster swipes give one frame per Pokémon and the bars
  may still be animating (rows come out flagged `bars-unsettled`).
- One clip per pass. A long box is fine as several clips: when you stop and restart, begin from the
  last Pokémon you saw. The repeated Pokémon at the join are dropped automatically (up to 10
  rows of overlap; only rows at a join are ever dropped, so two identical Pokémon in the middle of
  a box stay two Pokémon).
- Record the Shadow-filtered pass (search `shadow`) as its own clip with `shadow` in the file name,
  for example `03-shadow.mp4`. Its Pokémon are matched to the same Pokémon in the main pass and the
  Shadow column is set to 1. Optionally do the same with a `purified` clip (column set to 2).
  If the main pass was recorded with a `!shadow` search, the Shadow Pokémon appear only in the
  shadow clip and are added to the end of the list.
- Put each account in its own folder on Drive:
  `F. Hobbies & Gaming/Pogo Assist recordings/<account>/`, holding only that session's clips.
  Name the clips so they sort in order: `01-`, `02-`, `03-`. Sorting is by name with numbers
  compared as numbers (`clip2` before `clip10`); `--order mtime` sorts by modified time instead.

## Running it

- Windows: drag the folder onto `extract-box.cmd` in the repository (or double-click it and paste
  the folder path). The window stays open at the end. If `%USERPROFILE%\dare33\pokemon-go-tier-list\inbox`
  exists the CSV is also copied there.
- Anywhere: `npm run extract:box -- "<folder>"` or `node scripts/extract-box.mjs "<folder>"`.
  Options: `--account NAME` (default: the folder name), `--fps 5`, `--order name|mtime`,
  `--inbox DIR`, `--out-dir DIR` (default: the folder), `--ffmpeg PATH`, `--force` (ignore the
  cache), `--quiet`.
- A folder with no clips but with subfolders that have clips is treated as several accounts: each
  subfolder is processed separately.
- The browser page (`web/extract.html`) takes several files at once and merges them the same way;
  it decodes in the browser, so HEVC recordings need Safari (see `docs/morning-test.md`).
- ffmpeg is found automatically: `--ffmpeg`, the `FFMPEG` variable, PATH, then winget and
  imageio-ffmpeg install locations. If none is found the tool says how to install it
  (`winget install Gyan.FFmpeg` or `brew install ffmpeg`).

Output, written next to the clips: `poke-genie-export-<account>-<YYYY-MM-DD>.csv` and
`poke-genie-export-<account>-<YYYY-MM-DD>.review.json`. A re-run the same day overwrites them.
The CSV's scan date is the newest clip's modified time, so re-running on unchanged clips gives a
byte-identical file.

## Cache files

Each clip gets `<clip>.extract.json` beside it: its rows, review list, unmatched frames, frame
count and time taken, keyed by file size, modified time and fps. A re-run reuses it (`cached`)
and only reads new or changed clips (`processed`). `--force` re-reads everything. Delete the
`.extract.json` files to reclaim space; they are safe to remove.

## Reading the summary

```
01-a.mp4 → 02-b.mp4: 3 duplicate rows dropped   (the last 3 Pokémon of clip 1 were the first 3 of clip 2)
shadow pass: 12 matched, 0 appended, 1 ambiguous
```

- `matched`: a shadow-clip Pokémon found exactly one unmarked match in the main pass; that row is
  marked Shadow.
- `appended`: no match in the main pass, so it was added to the end of the list as a Shadow.
- `ambiguous`: it matched several identical rows; the first was marked and flagged
  `shadow-match-ambiguous`. Which of the identical Pokémon is the Shadow cannot be told from the
  screen, so check it in the game.
- If a clip fails (unreadable file, ffmpeg error) the others still run, the export is still
  written, the failed clip is listed under `failedClips` in the review JSON, and the command exits
  with status 1. Pokémon from that clip are missing from the export.

## "Check these in the game"

The run ends with a list (capped at 40 lines; the rest is in the review JSON) of the rows worth
checking: name, CP, HP, clip and flags. It covers `ambiguous-ivs`, `no-level-fits`,
`shadow-match-ambiguous` and `ivs-unread`.

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
| `shadow-match-ambiguous` | A shadow/purified row matched several identical main-pass rows; the first was marked. |

The full glossary, with what each flag looks like in practice, is in `docs/morning-test.md`.
