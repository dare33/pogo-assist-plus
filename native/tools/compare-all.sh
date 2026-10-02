#!/bin/sh
# Verify the package and the app build, then read every clip's frames with the Swift reader through
# the device path (420 pixel buffers, width 750) and compare with the JavaScript extractor's rows.
#
#   native/tools/compare-all.sh <frames root> <reference checkout with src/extract> [clip ...]
#
# <frames root>/<clip>/f0001.png ... are 5 fps frames; <frames root>/_out/<clip>.js.csv is the
# JavaScript roster for the same frames (node scripts/extract.mjs <frames dir> --out ...).
set -u
F=${1:?frames root}; REF=${2:?reference checkout}; shift 2
O="$F/_out"
cd "$(dirname "$0")/.." || exit 1
if [ $# -eq 0 ]; then set -- $(cd "$F" && ls -d */ | tr -d / | grep -v '^_out$'); fi

git log --oneline -1
(cd PogoReader && swift test 2>&1 | grep -E "Executed .* tests" | tail -1 && swift build -c release 2>&1 | tail -1)
xcodebuild -project PogoAssist/PogoAssist.xcodeproj -scheme PogoAssist -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | head -5

for c in "$@"; do
  echo "=== $c"
  PogoReader/.build/release/pogo-read "$F/$c" --width 750 --via-pixelbuffer \
    --out "$O/$c.swift.readings.json" --rows "$O/$c.swift.rows.json" 2>&1 | grep -iE "peak|rows|ms" | tr '\n' ' '
  echo
  node tools/finish-readings.mjs --repo "$REF" "$O/$c.swift.readings.json" --out "$O/$c.swift.review.json" >/dev/null 2>&1
  [ -f "$O/$c.js.csv" ] || { echo "no JavaScript roster for $c"; continue; }
  echo "-- reader vs reader (both through the JavaScript grouping)"
  node tools/compare-readers.mjs "$O/$c.js.csv" "$O/$c.swift.review.json" 2>&1 | grep -E "^rows:|^name \+ CP match|^same name|^rows only|^on screen"
  node tools/compare-readers.mjs "$O/$c.js.csv" "$O/$c.swift.review.json" --json > "$O/$c.compare.json" 2>/dev/null
  echo "-- JavaScript rows vs live grouper rows"
  node tools/compare-readers.mjs "$O/$c.js.csv" "$O/$c.swift.rows.json" 2>&1 | grep -E "^rows:|^name \+ CP match|^same name|^rows only"
  node tools/compare-readers.mjs "$O/$c.js.csv" "$O/$c.swift.rows.json" --json > "$O/$c.compare-live.json" 2>/dev/null
done
