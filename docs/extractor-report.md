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
