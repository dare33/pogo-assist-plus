#!/usr/bin/env bash
# xcb.sh <slot> <xcodebuild args...>
#
# Runs xcodebuild in the project's FIXED derived-data location for the slot, so build output never
# lands in a fresh per-run folder (25 Oct 2026: 143 GB of them under /private/tmp/claude-*).
# Slots: main, review-a, review-b, merge (ask Greg for another named one; never invent a path).
# One xcodebuild per slot at a time: the slot is held by a mkdir mutex (mkdir is atomic, so of two
# callers racing for it exactly one wins) whose pid file names the running xcodebuild, and it is
# released when that xcodebuild ends. A -derivedDataPath of your own is refused: the path is not a
# choice. So are SYMROOT/OBJROOT-style overrides, and an output path (result bundle, archive) that is
# not relative to a checkout or inside the fixed location.
#
# A cold build takes minutes, longer than a tool's default timeout: run it in the background or
# with a long timeout. xcodebuild needs -scheme (or -xctestrun) with -derivedDataPath, so this is
# for scheme builds and tests; `xcodebuild -list` writes nothing and needs no helper.
#
#   native/tools/xcb.sh main -project native/PogoAssist/PogoAssist.xcodeproj -scheme PogoAssist \
#     -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
set -euo pipefail

ROOT="${POGO_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/PogoAssist-claude}"
STALE_AFTER=60   # seconds: a lock with no pid file older than this was left by a run killed mid-claim

die() { echo "xcb: $*" >&2; exit 2; }
now() { date +%s; }
age_of() { echo $(( $(now) - $(stat -f %m "$1" 2>/dev/null || now) )); }

[[ $# -ge 2 ]] || die "usage: xcb.sh <slot> <xcodebuild args...>   (slots: main review-a review-b merge)"
slot=$1; shift
case "$slot" in
  main|review-a|review-b|merge) ;;
  *) die "unknown slot '$slot' (slots: main review-a review-b merge; a further NAMED slot is Greg's call, see native/README.md)" ;;
esac

prev=""
for a in "$@"; do
  case "$a" in
    -derivedDataPath|-derivedDataPath=*|--derivedDataPath|--derivedDataPath=*)
      die "-derivedDataPath is set by the slot; drop it" ;;
    SYMROOT=*|OBJROOT=*|DSTROOT=*|BUILD_DIR=*|BUILD_ROOT=*|CONFIGURATION_BUILD_DIR=*|DERIVED_DATA_DIR=*|MODULE_CACHE_DIR=*|SHARED_PRECOMPS_DIR=*)
      die "'$a' would move build output out of the slot; drop it" ;;
  esac
  case "$prev" in
    -resultBundlePath|-archivePath|-resultStreamPath|-testProductsPath|-clonedSourcePackagesDirPath)
      # a relative path lands under the current directory, which must be a checkout (git-ignored out/
      # is the place), never a temp folder; an absolute one must be inside the fixed location
      [[ "$a" != *..* ]] || die "$prev may not contain ..: $a"
      case "$a" in
        "$ROOT"/*) ;;
        /*) die "$prev must be a relative path inside the checkout (its git-ignored out/) or under $ROOT, not $a" ;;
        *) case "$PWD" in /private/tmp|/private/tmp/*|/tmp|/tmp/*|/var/folders|/var/folders/*|/private/var/folders|/private/var/folders/*)
             die "$prev is relative and the current directory is a temp folder; cd to the checkout" ;; esac ;;
      esac ;;
  esac
  prev=$a
done

dd="$ROOT/$slot"
lock="$ROOT/$slot.lock"
reclaim="$ROOT/.reclaim.lock"   # held only while judging and removing a stale slot lock
# A root is ours when every entry in it is a name these helpers define (a slot, a lock, swift-<slot>,
# review-copy-*, sims.txt). Such a root is adopted and marked, so a first `mkdir -p .../review-copy-a`
# or `swift test --scratch-path .../swift-main` does not lock the helpers out. Anything else there
# means a stranger's folder, so refuse: build-clean.sh empties whatever carries the marker, and only
# the helpers that add to a root (this one, sim-temp.sh create) may mark it.
adopt_root() {
  local e
  if [[ -d "$ROOT" && ! -f "$ROOT/.pogo-build-root" ]]; then
    for e in "$ROOT"/* "$ROOT"/.[!.]*; do
      [[ -e "$e" ]] || continue
      case "$(basename "$e")" in
        main|review-a|review-b|merge|*.lock|swift-*|review-copy-*|sims.txt|sims.txt.tmp.*|.reclaim.lock|.DS_Store) ;;
        *) die "$ROOT holds '$(basename "$e")', which these helpers did not make; refusing to use it as the build root" ;;
      esac
    done
  fi
  mkdir -p "$ROOT"
  touch "$ROOT/.pogo-build-root"
}
adopt_root

# Take the slot lock. Wait while a live xcodebuild holds it. A stale lock (its pid is gone, or it
# has had no pid for STALE_AFTER seconds) is removed, but only under the reclaim mutex, so two
# waiters can never both judge the same lock stale and one of them remove a lock the other has just
# re-taken; a plain mkdir cannot replace a lock while it exists, so a judgement made under the
# reclaim mutex stays true until the removal.
waited=0
until mkdir "$lock" 2>/dev/null; do
  if mkdir "$reclaim" 2>/dev/null; then
    holder=$(cat "$lock/pid" 2>/dev/null || true)
    stale=0
    if [[ -n "$holder" ]]; then kill -0 "$holder" 2>/dev/null || stale=1
    elif [[ -d "$lock" ]] && (( $(age_of "$lock") > STALE_AFTER )); then stale=1; fi
    if (( stale )); then
      echo "xcb: reclaiming stale lock $lock (pid '${holder:-none}' is gone)" >&2
      rm -rf "$lock"
    fi
    rmdir "$reclaim" 2>/dev/null || true
    (( stale )) && continue
  elif (( $(age_of "$reclaim") > STALE_AFTER )); then
    rm -rf "$reclaim"; continue   # a reclaimer that died mid-judgement
  fi
  if (( waited % 30 == 0 )); then
    echo "xcb: waiting for slot '$slot' (held by pid ${holder:-?}; lock $lock)" >&2
  fi
  sleep 2; waited=$((waited + 2))
done
# Release: under the reclaim mutex, and only if the lock still records our build. Without the mutex a
# waiter could judge our lock stale in the instant after xcodebuild ends, re-take it, and then have
# this trap remove the lock it just took.
mine=$$
release() {
  local tries=0
  until mkdir "$reclaim" 2>/dev/null; do
    if (( $(age_of "$reclaim") > STALE_AFTER )); then rm -rf "$reclaim"; continue; fi
    # a reclaimer holds the mutex for milliseconds; if it is still held after 5 s something is wrong,
    # so leave the lock alone: with the build's pid dead it is stale and the next waiter reclaims it
    (( tries++ < 50 )) || return 0
    sleep 0.1
  done
  [[ "$(cat "$lock/pid" 2>/dev/null)" == "$mine" ]] && rm -rf "$lock"
  rmdir "$reclaim" 2>/dev/null || true
}
trap release EXIT
echo $$ > "$lock/pid" || die "could not record the lock owner in $lock/pid"

echo "xcb: slot '$slot' -> $dd" >&2
# xcodebuild runs as a child and its own pid goes in the lock, so the slot stays held for as long
# as the build runs even if this shell is killed (the lock then goes stale when the build ends).
# Known limit: in the instant (microseconds) between the launch and the pid write below, a SIGKILL
# leaves the shell's pid in the lock, so a waiter may reclaim it while the build runs; an INT/TERM
# there kills a build the pid file does not yet name, which leaves a reclaimable lock (harmless).
# Also residual: two parties finding a reclaim mutex older than 60 s (a crashed reclaimer) can race
# to remove it. A background child of a non-interactive shell ignores INT, so INT sends TERM.
xpid=""
trap 'kill -TERM "$xpid" 2>/dev/null; wait "$xpid" 2>/dev/null || true; exit 130' INT
trap 'kill -TERM "$xpid" 2>/dev/null; wait "$xpid" 2>/dev/null || true; exit 143' TERM
trap 'kill -HUP  "$xpid" 2>/dev/null; wait "$xpid" 2>/dev/null || true; exit 129' HUP
xcodebuild -derivedDataPath "$dd" "$@" </dev/null &
xpid=$!
mine=$xpid
echo "$xpid" > "$lock/pid" || true
rc=0
wait "$xpid" || rc=$?
exit "$rc"
