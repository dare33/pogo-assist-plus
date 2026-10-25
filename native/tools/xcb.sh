#!/usr/bin/env bash
# xcb.sh <slot> <xcodebuild args...>
#
# Runs xcodebuild in the project's FIXED derived-data location for the slot, so build output never
# lands in a fresh per-run folder (25 Oct 2026: 143 GB of them under /private/tmp/claude-*).
# Slots: main, main-2, review-a, review-b, merge (ask Greg for another named one; never invent a path).
# One xcodebuild per slot at a time: the slot is held by a kernel lock (/usr/bin/lockf) on the slot's
# lock file, which the running xcodebuild inherits, so it is released once both this shell and that
# xcodebuild have ended, however either ends. A -derivedDataPath of your own is refused: the path is not a
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

ROOT="${POGO_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/pogo-claude-build}"

die() { echo "xcb: $*" >&2; exit 2; }

[[ $# -ge 2 ]] || die "usage: xcb.sh <slot> <xcodebuild args...>   (slots: main main-2 review-a review-b merge)"
slot=$1; shift
case "$slot" in
  main|main-2|review-a|review-b|merge) ;;
  *) die "unknown slot '$slot' (slots: main main-2 review-a review-b merge; a further NAMED slot is Greg's call, see native/README.md)" ;;
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
# A root is ours when every entry in it is a name these helpers define (a slot, a lock, swift-<slot>,
# review-copy-*, sims.txt, the marker). Such a root is adopted and marked, so a first `mkdir -p .../review-copy-a`
# or `swift test --scratch-path .../swift-main` does not lock the helpers out. Anything else there
# means a stranger's folder, so refuse: build-clean.sh empties whatever carries the marker, and only
# the helpers that add to a root (this one, sim-temp.sh create) may mark it.
adopt_root() {
  local e
  if [[ -d "$ROOT" && ! -f "$ROOT/.pogo-build-root" ]]; then
    for e in "$ROOT"/* "$ROOT"/.[!.]*; do
      [[ -e "$e" ]] || continue
      case "$(basename "$e")" in
        main|main-2|review-a|review-b|merge|*.lock|swift-*|review-copy-*|sims.txt|sims.txt.tmp.*|.pogo-build-root|.DS_Store) ;;
        *) die "$ROOT holds '$(basename "$e")', which these helpers did not make; refusing to use it as the build root" ;;
      esac
    done
  fi
  mkdir -p "$ROOT"
  touch "$ROOT/.pogo-build-root"
}
adopt_root

# Take the slot lock: a kernel lock (flock, through /usr/bin/lockf) on the slot's lock file, which
# this shell opens on fd 9. The descriptor is inherited by the xcodebuild started below, so the lock
# is held while either holder lives (this shell, xcodebuild) and the kernel releases it when the
# last of them exits: no pid file, no stale-lock
# judgement, nothing to reclaim. A waiter blocks in lockf, saying so every 30 s (lockf exits 75
# when the wait times out; anything else is an error). The lock file is empty and permanent: it is
# never removed, because a waiter that had opened it would otherwise lock a vanished file while a
# new build locks its replacement, and both would run. Known limits: a helper from before this
# scheme (a checkout that has not taken this change) cannot mkdir over the file and waits forever,
# never building (safe; update that checkout); a lock directory it left is refused here, not judged.
[[ -d "$lock" ]] && die "$lock is a directory left by the previous (mkdir) lock scheme; when nothing is building, rm -rf it and retry"
# The traps come first so a signal while waiting ends the wait (exit 130/143/129, nothing built;
# a signal sent to this shell alone, not its process group, takes effect when the current lockf
# returns, within 30 s). Once the build runs they forward the signal to it: xcodebuild is a
# background child of a non-interactive shell and ignores INT, so INT sends TERM. $! covers the
# instant between starting the build and recording its pid; it is unset until then, hence set +u.
xpid=""
on_signal() {   # $1 signal to forward to the build, $2 exit status
  set +u; local pid="${xpid:-$!}"
  if [[ -n "$pid" ]]; then kill -"$1" "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  exit "$2"
}
trap 'on_signal TERM 130' INT
trap 'on_signal TERM 143' TERM
trap 'on_signal HUP 129' HUP
exec 9>>"$lock" || die "could not open the lock file $lock"
until /usr/bin/lockf -s -t 30 9; do
  rc=$?; (( rc == 75 )) || die "lockf failed on $lock (exit $rc)"
  echo "xcb: waiting for slot '$slot' (lock $lock is held by another build)" >&2
done

echo "xcb: slot '$slot' -> $dd" >&2
# xcodebuild inherits fd 9, so the slot stays held for as long as xcodebuild runs even if this shell
# is killed, and the kernel releases it when every holder has exited. The processes xcodebuild
# starts do not inherit it (measured 25 Oct 2026 through a cold build: lsof showed only this shell
# and xcodebuild holding the lock, never the build service or a compiler), so the lock lasts as
# long as this shell or xcodebuild, whichever lives longer. Known limit: a kill -9 of xcodebuild
# frees the slot while a compiler it left behind may still write there (as the pid scheme did).
xcodebuild -derivedDataPath "$dd" "$@" </dev/null &
xpid=$!
rc=0
wait "$xpid" || rc=$?
exit "$rc"
