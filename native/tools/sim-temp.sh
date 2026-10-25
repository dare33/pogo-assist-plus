#!/usr/bin/env bash
# sim-temp.sh create <base name or udid> <label>   clone a simulator for one run, record it
# sim-temp.sh delete <label or udid>               shut it down, delete it, forget it
# sim-temp.sh list                                 every recorded clone, with exists / gone
#
# A simulator cloned for a run is deleted at the END of that run, by the run. Every clone is
# recorded in $ROOT/sims.txt (udid, label, date) so a later session, or build-clean.sh, can remove
# leftovers: on 25 Oct 2026 the Mac held forgotten clones ("iPhone 17 gate", "hist-clone6"...).
# The standing simulators (iPhone 17, iPhone Air; native/README.md) are never recorded here and
# never deleted by these tools. A label must be new (no device of that name yet), so `delete
# <label>` names exactly one clone. Prefer the udid that `create` prints when scripting.
# Records are one line each; `create` appends, `delete` removes its own udid's line. Two sessions
# editing at the same instant is not locked against; a lost line means a clone to find by hand.
set -euo pipefail

ROOT="${POGO_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/pogo-claude-build}"
SIMS="$ROOT/sims.txt"

die() { echo "sim-temp: $*" >&2; exit 2; }
# A root is ours when every entry in it is a name these helpers define (a slot, a lock, swift-<slot>,
# review-copy-*, sims.txt, the marker). `create` adopts and marks such a root, so a first
# `mkdir -p .../review-copy-a` or `swift test --scratch-path .../swift-main` does not lock the helpers
# out; anything else there means a stranger's folder and is refused. `delete` acts on the records, so
# it requires the marker rather than adopting; `list` only reads and marks nothing.
adopt_root() {
  local e
  if [[ -d "$ROOT" && ! -f "$ROOT/.pogo-build-root" ]]; then
    for e in "$ROOT"/* "$ROOT"/.[!.]*; do
      [[ -e "$e" ]] || continue
      case "$(basename "$e")" in
        main|review-a|review-b|merge|*.lock|swift-*|review-copy-*|sims.txt|sims.txt.tmp.*|.pogo-build-root|.DS_Store) ;;
        *) die "$ROOT holds '$(basename "$e")', which these helpers did not make; refusing to use it as the build root" ;;
      esac
    done
  fi
  mkdir -p "$ROOT"
  touch "$ROOT/.pogo-build-root"
}
# all devices, booted or not; a failed listing is an error, never "the device is gone"
devices() { xcrun simctl list devices </dev/null || die "simctl list failed; nothing changed"; }
forget() { awk -F'\t' '$1 != ENVIRON["U"]' "$SIMS" > "$SIMS.tmp.$$" && mv "$SIMS.tmp.$$" "$SIMS"; }

cmd=${1:-}
case "$cmd" in
  create)
    [[ $# -eq 3 ]] || die "usage: sim-temp.sh create <base name or udid> <label>"
    base=$2; label=$3
    [[ -n "$label" && "$label" != *[^[:print:]]* ]] || die "label must be printable text with no tab or newline"
    all=$(devices)
    if [[ "$all" == *"    $label ("* ]]; then die "a device named '$label' already exists; pick a new label"; fi
    adopt_root
    udid=$(xcrun simctl clone "$base" "$label" </dev/null)
    printf '%s\t%s\t%s\n' "$udid" "$label" "$(date +%Y-%m-%dT%H:%M:%S)" >> "$SIMS"
    echo "$udid"
    ;;
  delete)
    [[ $# -eq 2 ]] || die "usage: sim-temp.sh delete <label or udid>"
    [[ -d "$ROOT" ]] || die "nothing recorded: $ROOT does not exist"
    [[ -f "$ROOT/.pogo-build-root" ]] || die "$ROOT was never marked by these helpers (no .pogo-build-root); refusing to act on records there. If it is this project's build root, run xcb.sh or sim-temp.sh create once (or touch the marker) and retry"
    [[ -f "$SIMS" ]] || die "nothing recorded in $SIMS"
    matches=$(K="$2" awk -F'\t' '$1 == ENVIRON["K"] || $2 == ENVIRON["K"] { print $1 }' "$SIMS")
    [[ -n "$matches" ]] || die "'$2' is not recorded in $SIMS (a standing simulator is deleted by hand, on purpose)"
    failed=0
    while IFS= read -r udid; do
      xcrun simctl shutdown "$udid" >/dev/null 2>&1 </dev/null || true   # already shut down is fine
      xcrun simctl delete "$udid" </dev/null || true
      all=$(devices)
      if [[ "$all" == *"($udid)"* ]]; then
        echo "sim-temp: $udid still exists; record kept" >&2; failed=1
      else
        echo "deleted $udid"; U="$udid" forget
      fi
    done <<< "$matches"
    exit "$failed"
    ;;
  list)
    [[ -s "$SIMS" ]] || { echo "none recorded"; exit 0; }   # reads only; never marks a root
    all=$(devices)
    while IFS=$'\t' read -r udid label when; do
      [[ -n "$udid" ]] || continue
      if [[ "$all" == *"($udid)"* ]]; then state=exists; else state=gone; fi
      printf '%s\t%s\t%s\t%s\n' "$udid" "$label" "$when" "$state"
    done < "$SIMS"
    ;;
  *) die "usage: sim-temp.sh create <base> <label> | delete <label or udid> | list" ;;
esac
