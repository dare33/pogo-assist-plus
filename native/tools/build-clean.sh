#!/usr/bin/env bash
# build-clean.sh [-n]   empty the project's fixed build location and delete the simulators it recorded
#
# The fixed location ($ROOT, see xcb.sh) is reused run after run, so it only needs emptying when it
# is stale (a toolchain change, a corrupt module cache, or to get the disk back). Run it when nothing
# is building. -n prints what would go and stops. Each xcodebuild slot is emptied while holding its
# lock (the kernel lock xcb.sh takes), so a slot with a live build is skipped and a build cannot start
# into a folder being removed; swift-<slot> and review-copy-* have no lock and are removed outright. A
# booted simulator is skipped.
set -euo pipefail

ROOT="${POGO_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/pogo-claude-build}"
SIMS="$ROOT/sims.txt"
dry=0
case "$#:${1:-}" in
  0:) ;;
  1:-n) dry=1 ;;
  *) echo "build-clean: the only option is -n (a dry run); refusing '$*' rather than deleting" >&2; exit 2 ;;
esac
rc=0

[[ -d "$ROOT" ]] || { echo "build-clean: $ROOT does not exist; nothing to do"; exit 0; }
# Only a root that xcb.sh or sim-temp.sh marked is emptied: with POGO_BUILD_ROOT pointing one level up,
# this script would otherwise empty every project's derived data. This script never marks a root
# itself (a cleaner must not decide what it may clean); a hand-made root is marked by the first
# xcb.sh or sim-temp.sh run in it.
if [[ ! -f "$ROOT/.pogo-build-root" ]]; then
  echo "build-clean: $ROOT has no .pogo-build-root marker, so these helpers never built there; refusing." >&2
  echo "build-clean: if it is this project's build root, run xcb.sh or sim-temp.sh create once, or touch that marker, then retry." >&2
  exit 2
fi
du -sh "$ROOT" 2>/dev/null || true

# 1. Simulators this project cloned (recorded by sim-temp.sh). The list is read once; each clone
# that is confirmed gone is removed from the file by udid, so a line appended meanwhile survives.
if [[ -s "$SIMS" ]]; then
  recorded=$(cat "$SIMS")
  all=$(xcrun simctl list devices </dev/null) || { echo "build-clean: simctl list failed; simulators left alone" >&2; rc=1; recorded=""; }
  while IFS=$'\t' read -r udid label _; do
    [[ -n "$udid" ]] || continue
    if [[ "$all" == *"($udid) (Booted)"* ]]; then echo "skip: simulator $label ($udid) is booted"; continue; fi
    echo "simulator: $label ($udid)"
    (( dry )) && continue
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 </dev/null || true
    xcrun simctl delete "$udid" </dev/null 2>/dev/null || true
    all=$(xcrun simctl list devices </dev/null) || { echo "build-clean: simctl list failed; records kept" >&2; rc=1; break; }
    if [[ "$all" == *"($udid)"* ]]; then
      echo "build-clean: $udid still exists; record kept" >&2; rc=1
    else
      U="$udid" awk -F'\t' '$1 != ENVIRON["U"]' "$SIMS" > "$SIMS.tmp.$$" && mv "$SIMS.tmp.$$" "$SIMS"
    fi
  done <<< "$recorded"
fi

# 2. The xcodebuild slots, each emptied while holding its lock: the same kernel lock xcb.sh takes
# (/usr/bin/lockf on the slot's lock file, opened here on fd 9), tried without waiting, so a slot with
# a live build fails the try (lockf exits 75) and is skipped, and a build cannot start into a folder
# being removed. The lock file itself is never removed (see xcb.sh: a waiter that had opened it would
# otherwise lock a vanished file while a new build locks its replacement). A dry run opens an existing
# lock file read-only and creates nothing.
for slot in main review-a review-b merge; do
  dir="$ROOT/$slot"; l="$ROOT/$slot.lock"
  if [[ -d "$l" ]]; then
    echo "skip: $l is a lock directory from the previous (mkdir) scheme; when nothing is building, rm -rf it by hand" >&2; rc=1; continue
  fi
  [[ -e "$dir" ]] || continue
  # try the lock: 0 = taken (held on fd 9 until it is closed), 75 = a live build holds it, else an error
  if (( dry )); then
    [[ -e "$l" ]] || { echo "would remove: $dir"; continue; }
    exec 9<"$l" || { echo "build-clean: cannot open $l; $slot not judged" >&2; rc=1; continue; }
  else
    exec 9>>"$l" || { echo "build-clean: cannot open $l; $slot left alone" >&2; rc=1; continue; }
  fi
  lrc=0; /usr/bin/lockf -s -t 0 9 || lrc=$?
  if (( lrc == 75 )); then echo "skip: $slot is in use"
  elif (( lrc != 0 )); then echo "build-clean: lockf failed on $l (exit $lrc); $slot left alone" >&2; rc=1
  elif (( dry )); then echo "would remove: $dir"
  else echo "remove: $dir"; rm -rf "$dir"
  fi
  exec 9>&-
done

# 3. The other folders these helpers define: swift-<slot> and review-copy-*. Anything else is
# reported and left alone, so a root that was marked by mistake cannot have a stranger's folders
# emptied from it.
for path in "$ROOT"/*; do
  [[ -e "$path" ]] || continue
  name=$(basename "$path")
  case "$name" in
    sims.txt|main|review-a|review-b|merge|*.lock) continue ;;
    swift-*|review-copy-*|sims.txt.tmp.*)
      if (( dry )); then echo "would remove: $path"; else echo "remove: $path"; rm -rf "$path"; fi ;;
    *) echo "leave: $path (not a folder these helpers make; remove it by hand if it is yours)" ;;
  esac
done
(( dry )) && echo "(dry run; nothing removed)"
exit "$rc"
