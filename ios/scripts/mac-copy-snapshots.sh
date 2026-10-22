#!/usr/bin/env bash
# Photograph a COPY of the built Mac app, under its own bundle id, while
# someone keeps using the real Mercurius on the same Mac.
#
# Why a copy: a second process of the same bundle id shares the first one's
# sandbox container (preferences, the SwiftData store), and the harness's
# default build path may be the very app that is open. So this script:
#
#   1. copies the Debug build (SRC_APP) to COPY_DIR/Mercurius-macns<N>.app;
#   2. gives the copy the bundle id com.mayoailiteracy.mercurius.native.macns<N>
#      (PlistBuddy) and re-signs it ad hoc, keeping the build's sandbox
#      entitlements (so it runs in a container of its own); a codesign
#      "detritus" failure is retried after an xattr strip, three times;
#   3. notes every Mercurius process already running, then runs
#      scripts/mac-snapshots.sh with MAC_APP=<copy> and ACTIVATE=NO by
#      default: the harness launches the copy's own binary, moves its window
#      off screen, never activates it, photographs it and quits it. A copy
#      that hangs is killed by the PID the harness launched — never by name;
#   4. watches the frontmost app while it runs, and fails if the copy ever
#      came to the front, if any Mercurius that was running before is gone,
#      or if a process of the copy is left behind.
#
# It never runs pkill/killall and never reads or writes the build it was
# not given. SRC_APP under /private/tmp/merc-mac-dd (the founder's own
# build) is refused.
#
# Usage, from ios/, after building MercuriusMac into the derived data below:
#   scripts/mac-copy-snapshots.sh <out-dir> [shot ...]
# Environment: N (copy number, default 1), SUFFIX (the bundle id's last
# label before N, default macns: SUFFIX=macnight N=1 gives ….macnight1),
# SRC_APP, COPY_DIR, VARIANTS and ACTIVATE (passed through to
# mac-snapshots.sh; ACTIVATE defaults to NO).
set -euo pipefail

OUT=${1:?usage: mac-copy-snapshots.sh <out-dir> [shot ...]}
shift || true
N=${N:-1}
SUFFIX=${SUFFIX:-macns}
SRC_APP=${SRC_APP:-/private/tmp/merc-mac-ns-dd/Build/Products/Debug/Mercurius.app}
COPY_DIR=${COPY_DIR:-/private/tmp/merc-mac-ns-copies}
BUNDLE_ID="com.mayoailiteracy.mercurius.native.$SUFFIX$N"
COPY="$COPY_DIR/Mercurius-$SUFFIX$N.app"
HERE=$(cd "$(dirname "$0")" && pwd)

case $(cd "$SRC_APP" 2>/dev/null && pwd -P) in
  /private/tmp/merc-mac-dd/*|"") echo "refusing SRC_APP=$SRC_APP (missing, or the build in use)" >&2; exit 2 ;;
esac
[ -x "$SRC_APP/Contents/MacOS/Mercurius" ] || { echo "no Mac build at $SRC_APP" >&2; exit 1; }

# A copy of ours that is still running would be replaced under its feet.
if pgrep -f "$COPY/Contents/MacOS/Mercurius" >/dev/null; then
  echo "a process of $COPY is still running; not replacing it" >&2
  exit 1
fi

mkdir -p "$COPY_DIR"
rm -rf "$COPY"
ditto "$SRC_APP" "$COPY"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$COPY/Contents/Info.plist"

ENTITLEMENTS=$(mktemp)
codesign -d --entitlements - --xml "$SRC_APP" > "$ENTITLEMENTS" 2>/dev/null || true
signed=0
for _ in 1 2 3; do
  xattr -cr "$COPY"
  if [ -s "$ENTITLEMENTS" ]; then
    codesign --force --deep -s - --entitlements "$ENTITLEMENTS" "$COPY" 2>/dev/null && signed=1
  else
    codesign --force --deep -s - "$COPY" 2>/dev/null && signed=1
  fi
  [ $signed -eq 1 ] && break
  sleep 1
done
rm -f "$ENTITLEMENTS"
[ $signed -eq 1 ] || { echo "could not re-sign $COPY" >&2; exit 1; }
got=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$COPY/Contents/Info.plist")
[ "$got" = "$BUNDLE_ID" ] || { echo "the copy's bundle id is $got" >&2; exit 1; }
codesign --verify "$COPY"
echo "copy: $COPY ($BUNDLE_ID, ad hoc)"

# Every Mercurius running before (the founder's), to prove they survive.
BEFORE=$(pgrep -x Mercurius | tr '\n' ' ' || true)
echo "running before: ${BEFORE:-none}"

# The frontmost app, twice a second, while the shots run.
FRONT_LOG=$(mktemp)
(
  while :; do
    asn=$(lsappinfo front 2>/dev/null || true)
    [ -n "$asn" ] && lsappinfo info -only bundleid "$asn" 2>/dev/null | sed -n 's/.*"CFBundleIdentifier"="\(.*\)"/\1/p' >> "$FRONT_LOG"
    sleep 0.5
  done
) &
WATCH=$!

status=0
MAC_APP="$COPY" ACTIVATE="${ACTIVATE:-NO}" "$HERE/mac-snapshots.sh" "$OUT" "$@" || status=$?

kill "$WATCH" 2>/dev/null || true
wait "$WATCH" 2>/dev/null || true

if grep -qx "$BUNDLE_ID" "$FRONT_LOG"; then
  echo "problem: the copy came to the front at some point" >&2
  status=1
fi
echo "frontmost apps seen: $(sort -u "$FRONT_LOG" | tr '\n' ' ')"
rm -f "$FRONT_LOG"

for pid in $BEFORE; do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "problem: Mercurius $pid, running before, is gone" >&2
    status=1
  fi
done
LEFT=$(pgrep -f "$COPY/Contents/MacOS/Mercurius" | tr '\n' ' ' || true)
if [ -n "$LEFT" ]; then
  echo "problem: the copy is still running ($LEFT); quitting it by PID" >&2
  for pid in $LEFT; do kill "$pid" 2>/dev/null || true; done
  status=1
fi
echo "running after: $(pgrep -x Mercurius | tr '\n' ' ' || true)"
exit "$status"
