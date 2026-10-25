#!/usr/bin/env bash
# build-clean.sh [-n]   empty the project's fixed build location and delete the simulators it recorded
#
# The fixed location ($ROOT, see xcb.sh) is reused run after run, so it only needs emptying when it
# is stale (a toolchain change, a corrupt module cache, or to get the disk back). Run it when nothing
# is building. -n prints what would go and stops. Each xcodebuild slot is emptied while holding its
# lock, so a slot with a live build is skipped and a build cannot start into a folder being removed;
# swift-<slot> and review-copy-* have no lock and are removed outright. A booted simulator is skipped.
set -euo pipefail

ROOT="${POGO_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/PogoAssist-claude}"
SIMS="$ROOT/sims.txt"
STALE_AFTER=60
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

now() { date +%s; }
age_of() { echo $(( $(now) - $(stat -f %m "$1" 2>/dev/null || now) )); }
# 0 when the lock dir holds a live build; 1 when there is no lock or it is stale
lock_live() {
  local l=$1 holder
  [[ -d "$l" ]] || return 1
  holder=$(cat "$l/pid" 2>/dev/null || true)
  if [[ -n "$holder" ]]; then kill -0 "$holder" 2>/dev/null; return; fi
  (( $(age_of "$l") <= STALE_AFTER ))
}

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

# 2. The xcodebuild slots, each under its own lock. A stale lock is judged and removed only under
# the same reclaim mutex xcb.sh uses, so this cannot remove a lock a waiter has just re-taken.
reclaim="$ROOT/.reclaim.lock"
for slot in main review-a review-b merge; do
  dir="$ROOT/$slot"; l="$ROOT/$slot.lock"
  [[ -e "$dir" || -e "$l" ]] || continue
  if lock_live "$l"; then echo "skip: $slot is in use (pid $(cat "$l/pid" 2>/dev/null))"; continue; fi
  if (( dry )); then echo "would remove: $dir"; continue; fi
  if ! mkdir "$reclaim" 2>/dev/null; then
    if (( $(age_of "$reclaim") > STALE_AFTER )); then rm -rf "$reclaim"; fi
    mkdir "$reclaim" 2>/dev/null || { echo "skip: $slot (another run is reclaiming a lock right now)"; continue; }
  fi
  # a stale lock is removed; an absent one is left for mkdir to race for, so a build that took the
  # slot a moment ago keeps it and this run skips
  taken=0
  if [[ -d "$l" ]] && ! lock_live "$l"; then rm -rf "$l"; fi
  if [[ ! -d "$l" ]] && mkdir "$l" 2>/dev/null; then taken=1; fi   # losing the mkdir race is a skip, not an exit
  rmdir "$reclaim" 2>/dev/null || true
  (( taken )) || { echo "skip: $slot was taken just now"; continue; }
  echo $$ > "$l/pid"
  echo "remove: $dir"
  rm -rf "$dir"
  rm -rf "$l"
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
# a reclaim mutex left by a run that died mid-judgement; a live one (under 60 s old) is left alone
if (( ! dry )) && [[ -d "$ROOT/.reclaim.lock" ]] && (( $(age_of "$ROOT/.reclaim.lock") > STALE_AFTER )); then rm -rf "$ROOT/.reclaim.lock"; fi
(( dry )) && echo "(dry run; nothing removed)"
exit "$rc"
