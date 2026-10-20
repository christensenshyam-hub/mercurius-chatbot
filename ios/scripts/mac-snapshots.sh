#!/usr/bin/env bash
# Screenshots of the native Mac app, rendered by the app itself.
#
# Each shot launches the DEBUG build with `-MacSnapshot <dir>` plus a state
# argument; the app draws its own window into a PNG (NSView.cacheDisplay — no
# screencapture, no Screen Recording permission), writes it and quits. Every
# run is isolated: in-memory chats (-UITests), an in-memory session id
# (-EphemeralSession, no Keychain item) and the local server URL
# (-UseLocalServer), so nothing reaches production.
#
# Each launch opens a real window for a few seconds, moved almost entirely
# off screen before it is drawn (the window server still renders it). Liquid
# Glass surfaces that blend with what's behind the window (sidebar, toolbar
# edge, checkbox and pop-up bezels) come out dark or missing in the PNGs;
# the gate shots also write <shot>.controls.txt, the window's AppKit controls,
# to show those are present. See MercuriusMac/App/MacSnapshot.swift.
#
# Usage (from ios/, after building the MercuriusMac scheme into the derived
# data below):
#   scripts/mac-snapshots.sh <out-dir> [shot ...]
# Shots: gate-meet gate-age gate-consent today path lesson chat today-dark
# (default: all).
set -euo pipefail

OUT=${1:?usage: mac-snapshots.sh <out-dir> [shot ...]}
shift || true
APP=${MAC_APP:-/private/tmp/merc-mac-dd/Build/Products/Debug/Mercurius.app}
BIN="$APP/Contents/MacOS/Mercurius"
[ -x "$BIN" ] || { echo "no Mac build at $APP" >&2; exit 1; }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# Every flag carries a value: AppKit takes a bare word after a value-less
# flag (`-EnterShell -MacSnapshotDelay 9`) as a document to open, and SwiftUI
# then opens no window.
ISOLATED=(-UITests YES -EphemeralSession YES -UseLocalServer YES -ApplePersistenceIgnoreState YES)
GATE=(-consentVersion 0 -hasSeenOnboarding NO)
PAST_GATE=(-consentVersion 1 -hasSeenOnboarding YES)

shot() {
  local name=$1; shift
  local log
  log=$(mktemp)
  rm -f "${OUT:?}/$name.png"
  "$BIN" -MacSnapshot "$OUT" -MacSnapshotName "$name" "${ISOLATED[@]}" "$@" 2>"$log" &
  local pid=$!
  # The app quits itself after its delay; give it a hard ceiling anyway.
  for _ in $(seq 1 40); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
    echo "$name: timed out" >&2
  fi
  wait "$pid" 2>/dev/null || true
  # The sandbox may refuse <out-dir>; the app then writes to its container's
  # tmp and says where.
  local wrote
  wrote=$(sed -n 's/^MacSnapshot: wrote //p' "$log" | tail -1)
  if [ -n "$wrote" ] && [ "$wrote" != "$OUT/$name.png" ]; then
    cp "$wrote" "$OUT/$name.png"
  fi
  if [ -f "$OUT/$name.png" ]; then echo "$name: $OUT/$name.png"; else echo "$name: FAILED" >&2; cat "$log" >&2; fi
  grep '^CONTROL' "$log" > "$OUT/$name.controls.txt" || rm -f "$OUT/$name.controls.txt"
  rm -f "$log"
}

run() {
  case $1 in
    gate-meet)    shot "$1" "${GATE[@]}" -GateStep meet ;;
    gate-age)     shot "$1" "${GATE[@]}" -GateStep age -MacSnapshotDumpControls YES ;;
    gate-consent) shot "$1" "${GATE[@]}" -GateStep disclosure -MacSnapshotDumpControls YES ;;
    today)        shot "$1" "${PAST_GATE[@]}" -EnterShell YES ;;
    path)         shot "$1" "${PAST_GATE[@]}" -EnterShellCurriculum YES ;;
    lesson)       shot "$1" "${PAST_GATE[@]}" -LessonPreview YES -LessonReplay YES -LessonSkipIntro YES -MacSnapshotDelay 9 ;;
    chat)         shot "$1" "${PAST_GATE[@]}" -ChatPreview YES ;;
    today-dark)   shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacSnapshotAppearance dark ;;
    *) echo "unknown shot: $1" >&2; return 1 ;;
  esac
}

if [ $# -eq 0 ]; then
  set -- gate-meet gate-age gate-consent today path lesson chat today-dark
fi
for name in "$@"; do run "$name"; done
