# Extractor report

_Started 26 Sep 2026, overnight session. Per-recording probe results first; extraction results
against the acceptance table are appended as each step lands._

## Recordings (saved under `recordings/`, gitignored)

Probed with ffmpeg 7.1 (imageio-ffmpeg binary; not part of the shipped pipeline).

| File | Source | Container / codec | Frame size | Frame rate | Duration | Notes |
|---|---|---|---|---|---|---|
| `iphone-original.mp4` | iPhone 16 Pro screen recording, untrimmed | MP4, HEVC Main (hvc1), yuvj420p full range | 1320×2868 portrait | 59.92 fps | 42.47 s | The handoff expected 1206×2622; the real file is 1320×2868. Audio track present (AAC, silent). |
| `iphone-whatsapp.mp4` | The same recording after WhatsApp | MP4, H.264 Baseline (avc1) | 384×848 portrait | 59.92 fps | 42.47 s | Heavy downscale, 1.2 Mb/s. Worst case. |
| `iphone-clipchamp-trimmed.mp4` | The same recording trimmed in Clipchamp | MP4, H.264 Main (avc1) | 1920×1080 landscape | 30 fps | 10.07 s | Phone content pillarboxed in the centre of a black frame. Covers Mewtwo and the first Zamazenta only. |
| `ipad-original.mp4` | iPad screen recording | MP4, HEVC Main (hvc1), yuvj420p, `displaymatrix` rotation −90° | 2266×1488 stored, 1488×2266 after rotation | 47.37 fps average (60 tbr) | 17.24 s | ffmpeg applies the rotation when decoding, so frames come out portrait. Ends with the iPad Control Centre pulled over the game. |

Frames were extracted at 5 fps into `frames/<name>/f%04d.png` (gitignored): 212, 212, 50 and 86
frames respectively.

### Layout differences seen in the frames

- iPhone: CP text at about 3% of the content height, name at about 42%, the green HP bar at
  45%, "n / n HP" just under it, appraisal panel bars between 73% and 88%.
- iPad: CP text at about 8%, name at about 52%, green bar at 55%, appraisal panel between 68%
  and 85%. Willow's hair often covers the "n / n HP" text on the iPad.
- Both: three appraisal bars, each a track of three rounded blocks, fill orange (partial), pink
  (full), grey (empty), on a white panel at the left. The panel's vertical position moves.

Consequence: regions are anchored on detected features (white CP text rows at the top, the
green HP bar, the three bar tracks) rather than fixed fractions.

## How the extractor reads a frame

1. **Content rectangle**: widest run of bright columns, then rows (handles the Clipchamp
   pillarboxing; the other three files fill the frame).
2. **CP text**: rows in the top 14% whose centre band holds enough white pixels, then the column
   cluster nearest the centre that is text-sized and not solid. A Mega-evolved Pokémon's CP is
   drawn in pink over the aura, so a pink mask is the fallback (tested on Mega Mewtwo Y only).
   The "CP" prefix is skipped by glyph height and the digits are OCR'd twice (single line and
   single word, 40 px, padded); disagreement keeps the single-line read. Off-centre text marks a
   mid-swipe frame, which is skipped.
3. **Green HP bar** under the name: a thin band of green rows between 34% and 66%. The name band
   sits above it and the "n / n HP" text below it; the appraisal panel is searched below that.
4. **Name**: OCR with a letters-only whitelist, then the nearest game display name by edit
   distance (the pencil icon and stray tokens are dropped). One display name can be several
   forms (Zamazenta is Hero or Crowned Shield); the solver picks the form whose stats fit.
5. **Bars**: rows on panel white holding a long run of orange/pink/grey pixels with small gaps;
   three such bars with equal spacing and width are Attack, Defence, HP. Fill = coloured units
   over all units, with the orange-to-grey blend counted half. A read far from whole units is
   "unsettled" (the panel animates from the previous Pokémon's bars to the new ones).
6. **Runs**: consecutive readable frames with the same name and HP, and a CP within one digit,
   are one Pokémon; unreadable frames between them do not split the run. CP is voted with the
   solver as tie-break, HP is voted, IVs are voted among settled reads.
7. **Solver**: every IV combination and level is checked against CP and HP with the game master;
   the read is exact, corrected by one unit, or ambiguous (flagged with the number of fits).

## Acceptance table

| Pokémon | CP | HP | IVs | Level | Trimmed | Original | WhatsApp |
|---|---|---|---|---|---|---|---|
| Mewtwo (Mega Y) | 3673 | 145 | 15/15/15 | 20 | ✓ once | ✓ once | ✓ once |
| Zamazenta (Hero) | 2692 | 137 | 13/12/14 | 25 | ✓ once | ✓ once | ✓ once |
| Zamazenta (Hero) | 2651 | 135 | 12/10/11 | 25 | ✓ once (last frame of the clip) | ✓ once | ✓ once |
| Xurkitree | 3028 | 145 | 15/14/15 | 27 | ✓ once (the clip contains it) | ✓ once | ✓ once |
| Xurkitree | 2223 | 125 | unknown | — | not in the clip | ✓ once, HP 125, bars 11/15/15 L20 | ✓ once, HP 125, bars 11/15/15 L20 |

The integration test `test/extract/recordings.test.js` asserts exactly this on the trimmed and
original recordings (it skips when neither frames nor a decodable recording is present).
Frame provenance is in each run's `review.json` (`readings` per frame, `frames` per row).

## Results per recording (CLI, 5 fps, Node 24 on Windows)

| Recording | Frames | Rows | Flagged | Time | Rows also in the export | HP right | IVs right | Level right |
|---|---|---|---|---|---|---|---|---|
| iphone-clipchamp-trimmed | 50 | 4 | 0 | 3.4 s | 4 | 4/4 | 4/4 | 4/4 |
| iphone-original | 212 | 47 | 15 | 15.8 s | 35 | 35/35 | 31/35 | 33/35 |
| iphone-whatsapp | 212 | 46 | 31 | 6.9 s | 29 | 29/29 | 26/29 | 27/29 |
| ipad-original | 86 | 20 | 0 | 7.5 s | 0 (different account) | — | — | — |

"Also in the export" means a row whose name and CP appear in `fixtures/greg-2026-09-25.pokegenie.csv`;
the export predates the recording by about 25 minutes and does not hold the Pokémon caught after it,
and it scanned one Charizard as Mega Y (CP 2499) that the recording shows un-Mega'd (CP 1613, same HP
and IVs). Every wrong IV set on the original recording carries a flag; there is no unflagged wrong row
on the original or the trimmed copy. On the WhatsApp copy two CP misreads are unflagged (Scyther 1992
for 1998 and Murkrow 1265 for 1285: at 384 px wide a "9" and a "2", an "8" and a "6", read alike and the
misread happens to fit a level).

### What the four differing rows on the original are

| Row | Read | Export | Why |
|---|---|---|---|
| Zapdos 1970 | 11/13/14, flagged | 11/12/15 | One frame only, taken while the HP bar was still animating (12.66 units). The solver picked the nearest fit within one unit; the true set was two units away. |
| Sawk 1330 | 6/7/10, flagged ambiguous | 1/0/6 | One frame; the appraisal panel still showed the previous Pokémon's bars (7/7/7). Nothing near 7/7/7 fits CP 1330 / HP 108, so the row is flagged with 16 candidate sets. |
| Murkrow 1285 | 10/8/11, flagged corrected | 11/7/11 | One frame, bars read 8.76/6.97/10.81 (attack still animating). Both sets fit CP and HP at level 32. |
| Torracat 1014 | 7/13/5, flagged ambiguous | 2/15/4 | One frame, unsettled bars. |

All four are Pokémon that got a single frame at 5 fps because the swipe did not pause. The
recording protocol's one-second pause gives 3–5 frames and the bars settle; the first eight
Pokémon of the recording (paused) are all right.

### iPad

Twenty rows, none flagged, every row solved to exactly one level from CP, HP and bars, on a layout
where the name sits at 52% of the height instead of 42% and the panel is higher. The Control
Centre overlay at the end produced no row. There is no export for that account, so the rows are
self-consistent rather than verified; the Meltans with CP 13 and 14 at level 1 and the CP 41
Meltan at level 2 look right for freshly hatched Meltan.

## Known limits

- Fast swipes (under about 0.6 s per Pokémon) give one frame; bars may be mid-animation or the
  previous Pokémon's. Such rows are flagged (`bars-unsettled`, `ambiguous-ivs`, `ivs-corrected`)
  but IVs can be wrong. A 10 fps run (`--fps 10`) helps but does not fix a panel that never settled.
- The WhatsApp copy (384 px wide) misreads a CP digit in roughly one frame in eight; voting and
  the solver catch most, not all.
- Shadow and Purified are not detected (no shadow in the recordings); Lucky, gender, moves,
  candy and Dynamax are not read. Nicknamed Pokémon are skipped (name does not match a species).
- Mega CP colour: only Mega Y's pink was seen; other Mega colours may need another mask.
- Browser decode of HEVC (both originals) is untested in the container; see `docs/morning-test.md`.

## Per-recording rows

#### iphone-clipchamp-trimmed

| # | Name | Form | CP | HP | IVs | Level | Frames | Flags | Against the export |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Mewtwo | Mega Y | 3673 | 145 | 15/15/15 | 20 | 23 |  | matches |
| 2 | Xurkitree |  | 3028 | 145 | 15/14/15 | 27 | 10 |  | matches |
| 3 | Zamazenta | Hero | 2692 | 137 | 13/12/14 | 25 | 10 |  | matches |
| 4 | Zamazenta | Hero | 2651 | 135 | 12/10/11 | 25 | 1 |  | matches |

4 rows: 4 match the export in every field, 0 differ, 0 are not in the export (caught after it, or the export scanned the Mega form).

#### iphone-original

| # | Name | Form | CP | HP | IVs | Level | Frames | Flags | Against the export |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Mewtwo | Mega Y | 3673 | 145 | 15/15/15 | 20 | 24 |  | matches |
| 2 | Xurkitree |  | 3028 | 145 | 15/14/15 | 27 | 10 |  | matches |
| 3 | Zamazenta | Hero | 2692 | 137 | 13/12/14 | 25 | 11 |  | matches |
| 4 | Zamazenta | Hero | 2651 | 135 | 12/10/11 | 25 | 9 |  | matches |
| 5 | Xurkitree |  | 2223 | 125 | 11/15/15 | 20 | 3 |  | not in export |
| 6 | Xurkitree |  | 2212 | 123 | 15/12/12 | 20 | 5 |  | matches |
| 7 | Xurkitree |  | 2197 | 124 | 14/10/13 | 20 | 4 |  | matches |
| 8 | Xurkitree |  | 2196 | 125 | 10/12/15 | 20 | 3 |  | matches |
| 9 | Jynx |  | 2008 | 122 | 13/8/7 | 29 | 2 |  | not in export |
| 10 | Scyther |  | 1998 | 123 | 15/8/6 | 27 | 2 |  | matches |
| 11 | Zapdos |  | 1991 | 131 | 15/12/13 | 20 | 1 | bars-unsettled | matches |
| 12 | Zapdos |  | 1982 | 130 | 15/12/11 | 20 | 1 |  | matches |
| 13 | Zapdos |  | 1970 | 132 | 11/13/14 | 20 | 1 | ivs-corrected-from-11/12/13 bars-unsettled | export: HP 132, IVs 11/12/15, L20 |
| 14 | Zapdos |  | 1969 | 130 | 14/11/11 | 20 | 1 |  | matches |
| 15 | Zapdos |  | 1962 | 132 | 10/12/15 | 20 | 1 |  | matches |
| 16 | Hitmonlee |  | 1614 | 94 | 8/1/8 | 24 | 4 |  | matches |
| 17 | Charizard |  | 1613 | 118 | 12/13/13 | 20 | 2 | ambiguous-ivs:15-fit | not in export |
| 18 | Charizard |  | 1608 | 118 | 10/15/13 | 20 | 2 |  | matches |
| 19 | Charizard |  | 1592 | 117 | 12/10/11 | 20 | 1 |  | matches |
| 20 | Squawkabilly |  | 1551 | 145 | 15/12/13 | 28 | 1 |  | matches |
| 21 | Chatot |  | 1377 | 141 | 6/5/10 | 30 | 1 |  | matches |
| 22 | Magmar |  | 1343 | 104 | 0/1/0 | 23 | 2 | ambiguous-ivs:30-fit | matches |
| 23 | Malamar |  | 1341 | 127 | 15/14/14 | 20 | 2 | ambiguous-ivs:13-fit bars-unsettled | not in export |
| 24 | Sawk |  | 1330 | 108 | 6/7/10 | 18 | 1 | ambiguous-ivs:16-fit bars-unsettled | export: HP 108, IVs 1/0/6, L19 |
| 25 | Bibarel |  | 1299 | 135 | 2/12/4 | 28 | 1 | bars-unsettled | matches |
| 26 | Murkrow |  | 1285 | 123 | 10/8/11 | 32 | 1 | ivs-corrected-from-9/7/11 bars-unsettled | export: HP 123, IVs 11/7/11, L32 |
| 27 | Rhyhorn |  | 1105 | 129 | 14/15/8 | 24 | 2 |  | matches |
| 28 | Squawkabilly |  | 1094 | 120 | 12/15/9 | 20 | 1 |  | matches |
| 29 | Lapras |  | 1090 | 149 | 11/12/11 | 15 | 2 |  | not in export |
| 30 | Stufful |  | 1065 | 136 | 4/13/15 | 30 | 2 |  | matches |
| 31 | Munchlax |  | 1064 | 178 | 14/14/12 | 20 | 1 |  | matches |
| 32 | Grimer |  | 1063 | 145 | 4/8/5 | 32 | 2 | ambiguous-ivs:26-fit | matches |
| 33 | Kecleon |  | 1061 | 97 | 9/14/12 | 19 | 1 |  | not in export |
| 34 | Squawkabilly |  | 1056 | 123 | 6/11/14 | 20 | 1 |  | matches |
| 35 | Geodude |  | 1035 | 96 | 12/12/14 | 29 | 1 | bars-unsettled | not in export |
| 36 | Ponyta |  | 1019 | 90 | 15/9/8 | 22 | 1 |  | matches |
| 37 | Torracat |  | 1014 | 106 | 7/13/5 | 22.5 | 1 | ambiguous-ivs:18-fit bars-unsettled | export: HP 106, IVs 2/15/4, L23 |
| 38 | Volbeat |  | 998 | 104 | 11/9/8 | 21 | 1 |  | matches |
| 39 | Skiddo |  | 989 | 127 | 14/8/12 | 29 | 1 |  | not in export |
| 40 | Chatot |  | 977 | 117 | 0/8/4 | 22 | 1 | ambiguous-ivs:10-fit bars-unsettled | not in export |
| 41 | Growlithe |  | 959 | 114 | 4/12/10 | 30 | 1 | ivs-corrected-from-5/12/10 | matches |
| 42 | Oddish |  | 957 | 98 | 6/11/6 | 31 | 1 |  | not in export |
| 43 | Forretress |  | 946 | 99 | 11/15/11 | 15 | 1 | bars-unsettled | matches |
| 44 | Kecleon |  | 946 | 92 | 10/9/13 | 17 | 1 | ambiguous-ivs:19-fit bars-unsettled | not in export |
| 45 | Stufful |  | 944 | 127 | 10/3/12 | 27 | 1 |  | not in export |
| 46 | Phanpy |  | 941 | 157 | 9/9/8 | 30 | 1 |  | matches |
| 47 | Dedenne |  | 902 | 98 | 11/14/7 | 18 | 11 |  | matches |

47 rows: 31 match the export in every field, 4 differ, 12 are not in the export (caught after it, or the export scanned the Mega form).

#### iphone-whatsapp

| # | Name | Form | CP | HP | IVs | Level | Frames | Flags | Against the export |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Mewtwo | Mega Y | 873 | 145 | 15/15/15 | — | 4 | no-level-fits | not in export |
| 2 | Xurkitree |  | 3028 | 145 | 15/14/15 | 27 | 10 |  | matches |
| 3 | Zamazenta | Hero | 2692 | 137 | 13/12/14 | 25 | 11 | bars-unsettled | matches |
| 4 | Zamazenta | Hero | 2651 | 135 | 12/10/11 | 25 | 6 | bars-unsettled | matches |
| 5 | Xurkitree |  | 2223 | 125 | 11/15/15 | 20 | 3 | bars-unsettled | not in export |
| 6 | Xurkitree |  | 2212 | 123 | 15/12/12 | 20 | 5 |  | matches |
| 7 | Xurkitree |  | 2197 | 124 | 14/10/13 | 20 | 4 |  | matches |
| 8 | Xurkitree |  | 2196 | 125 | 10/12/15 | 20 | 3 | bars-unsettled | matches |
| 9 | Jynx |  | 2008 | 122 | 13/8/7 | 29 | 2 |  | not in export |
| 10 | Scyther |  | 1992 | 123 | 15/7/6 | 27 | 1 | ivs-corrected-from-15/8/6 | not in export |
| 11 | Zapdos |  | 5140 | 131 | 15/12/13 | — | 1 | no-level-fits bars-unsettled | not in export |
| 12 | Zapdos |  | 1970 | 132 | 11/13/14 | 20 | 1 | ivs-corrected-from-11/12/13 bars-unsettled | export: HP 132, IVs 11/12/15, L20 |
| 13 | Zapdos |  | 1969 | 130 | 14/11/11 | 20 | 1 | bars-unsettled | matches |
| 14 | Zapdos |  | 1962 | 132 | 10/12/15 | 20 | 1 |  | matches |
| 15 | Hitmonlee |  | 1614 | 94 | 8/1/8 | 24 | 4 |  | matches |
| 16 | Charizard |  | 1613 | 118 | 12/13/13 | 20 | 2 | bars-unsettled | not in export |
| 17 | Charizard |  | 1608 | 118 | 10/15/13 | 20 | 2 |  | matches |
| 18 | Charizard |  | 1592 | 117 | 12/10/11 | 20 | 1 | bars-unsettled | matches |
| 19 | Squawkabilly |  | 1551 | 145 | 15/12/13 | 28 | 1 |  | matches |
| 20 | Chatot |  | 1377 | 141 | 6/5/10 | 30 | 1 | bars-unsettled | matches |
| 21 | Magmar |  | 1343 | 104 | 0/1/0 | 23 | 2 | ambiguous-ivs:30-fit | matches |
| 22 | Malamar |  | 1341 | 127 | 15/14/14 | 20 | 2 | ambiguous-ivs:13-fit bars-unsettled | not in export |
| 23 | Sawk |  | 1330 | 108 | 6/7/10 | 18 | 1 | ambiguous-ivs:16-fit bars-unsettled | export: HP 108, IVs 1/0/6, L19 |
| 24 | Murkrow |  | 1265 | 123 | 9/7/12 | 31.5 | 1 | ambiguous-ivs:2-fit bars-unsettled | not in export |
| 25 | Rhyhorn |  | 1105 | 129 | 14/15/8 | 24 | 2 | bars-unsettled | matches |
| 26 | Squawkabilly |  | 1094 | 120 | 12/15/9 | 20 | 1 | bars-unsettled | matches |
| 27 | Lapras |  | 1090 | 149 | 11/12/11 | 15 | 2 |  | not in export |
| 28 | Stufful |  | 1065 | 136 | 4/13/15 | 30 | 2 |  | matches |
| 29 | Munchlax |  | 1064 | 178 | 14/14/12 | 20 | 1 |  | matches |
| 30 | Grimer |  | 1063 | 145 | 4/8/5 | 32 | 2 |  | matches |
| 31 | Kecleon |  | 1061 | 97 | 9/14/12 | 19 | 1 | bars-unsettled | not in export |
| 32 | Squawkabilly |  | 1056 | 123 | 6/11/14 | 20 | 1 | bars-unsettled | matches |
| 33 | Geodude |  | 1035 | 96 | 12/12/14 | 29 | 1 | bars-unsettled | not in export |
| 34 | Ponyta |  | 1019 | 90 | 15/9/8 | 22 | 1 | bars-unsettled | matches |
| 35 | Torracat |  | 1014 | 106 | 7/13/5 | 22.5 | 1 | ambiguous-ivs:18-fit bars-unsettled | export: HP 106, IVs 2/15/4, L23 |
| 36 | Volbeat |  | 998 | 104 | 11/9/8 | 21 | 1 |  | matches |
| 37 | Skiddo |  | 989 | 127 | 14/8/12 | 29 | 1 | bars-unsettled | not in export |
| 38 | Chatot |  | 977 | 117 | 0/8/4 | 22 | 1 | ambiguous-ivs:10-fit bars-unsettled | not in export |
| 39 | Growlithe |  | 959 | 114 | 4/12/10 | 30 | 1 | ivs-corrected-from-5/12/10 | matches |
| 40 | Oddish |  | 57 | 98 | 6/11/6 | — | 1 | no-level-fits | not in export |
| 41 | Forretress |  | 946 | 99 | 11/15/11 | 15 | 1 | bars-unsettled | matches |
| 42 | Kecleon |  | 946 | 92 | 10/9/13 | 17 | 1 | ambiguous-ivs:19-fit bars-unsettled | not in export |
| 43 | Stufful |  | 944 | 127 | 10/3/12 | 27 | 1 |  | not in export |
| 44 | Phanpy |  | 941 | 157 | 9/9/8 | 30 | 1 |  | matches |
| 45 | Dedenne |  | 50 | 93 | 11/14/8 | — | 1 | no-level-fits bars-unsettled | not in export |
| 46 | Dedenne |  | 902 | 98 | 11/14/7 | 18 | 10 | bars-unsettled | matches |

46 rows: 26 match the export in every field, 3 differ, 17 are not in the export (caught after it, or the export scanned the Mega form).

#### ipad-original

| # | Name | Form | CP | HP | IVs | Level | Frames | Flags | Against the export |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Makuhita |  | 122 | 61 | 7/12/15 | 6 | 9 |  | not in export |
| 2 | Meltan |  | 492 | 74 | 8/14/1 | 18 | 3 |  | not in export |
| 3 | Meltan |  | 734 | 99 | 3/12/13 | 27 | 5 |  | not in export |
| 4 | Meltan |  | 204 | 51 | 2/9/6 | 8 | 4 |  | not in export |
| 5 | Meltan |  | 120 | 38 | 3/6/3 | 5 | 3 |  | not in export |
| 6 | Rookidee |  | 268 | 71 | 7/0/14 | 17 | 3 |  | not in export |
| 7 | Meltan |  | 540 | 79 | 14/0/3 | 20 | 4 |  | not in export |
| 8 | Meltan |  | 711 | 90 | 7/14/3 | 26 | 3 |  | not in export |
| 9 | Meltan |  | 14 | 13 | 12/4/15 | 1 | 3 |  | not in export |
| 10 | Meltan |  | 617 | 90 | 3/3/9 | 24 | 3 |  | not in export |
| 11 | Heatmor |  | 627 | 83 | 11/6/0 | 10 | 3 |  | not in export |
| 12 | Meltan |  | 415 | 72 | 5/15/10 | 15 | 2 |  | not in export |
| 13 | Meltan |  | 41 | 23 | 9/2/11 | 2 | 3 |  | not in export |
| 14 | Meltan |  | 572 | 86 | 15/2/14 | 20 | 2 |  | not in export |
| 15 | Meltan |  | 13 | 13 | 13/0/11 | 1 | 2 |  | not in export |
| 16 | Meltan |  | 375 | 68 | 12/10/12 | 13 | 2 |  | not in export |
| 17 | Meltan |  | 697 | 97 | 2/5/10 | 27 | 2 |  | not in export |
| 18 | Meltan |  | 549 | 83 | 2/10/7 | 21 | 2 |  | not in export |
| 19 | Meltan |  | 626 | 90 | 10/9/14 | 22 | 5 |  | not in export |
| 20 | Meltan |  | 198 | 47 | 15/12/5 | 7 | 6 |  | not in export |

20 rows: 0 match the export in every field, 0 differ, 20 are not in the export (caught after it, or the export scanned the Mega form).
