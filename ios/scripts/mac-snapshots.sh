#!/usr/bin/env bash
# Screenshots of the native Mac app, rendered by the app itself.
#
# Each shot launches the DEBUG build with `-MacSnapshot <dir>` plus state
# arguments; the app photographs its own window (the window server's image
# of it — no screencapture, no Screen Recording permission), writes the PNG
# and quits. Every run is isolated: in-memory chats (-UITests), an in-memory
# session id (-EphemeralSession, no Keychain item) and the local server URL
# (-UseLocalServer), so nothing reaches production. A send in a shot fails
# fast against the (absent) local server, which is how `chat-failed` gets
# its Retry state.
#
# Each launch opens a real window for a few seconds, moved almost entirely
# off screen before it is drawn (the window server still renders it), and
# never takes the keyboard. Liquid Glass surfaces that blend with what's
# behind the window (sidebar, toolbar, checkbox and pop-up bezels) come out
# dark or missing in the PNGs; see MercuriusMac/App/MacSnapshot.swift.
#
# Usage (from ios/, after building the MercuriusMac scheme into the derived
# data below):
#   scripts/mac-snapshots.sh <out-dir> [shot ...]
# Each window shot is taken four ways: <shot>.png (1280×800, light),
# <shot>-dark.png, <shot>-min.png (860×600, the window's minimum) and
# <shot>-min-dark.png. The Settings and Help windows have their own size:
# light and dark only. Set VARIANTS="light" (or any of light dark min
# min-dark) to take fewer. VARIANTS="store" takes <shot>-store.png instead:
# light, square corners, no alpha, at STORE_SIZE points (default 1280x800,
# 2560×1600 px on a Retina display; STORE_SIZE=1440x900 gives 2880×1800 px
# on a display whose visible area is at least 900 pt tall). See
# mac-store-screenshots.sh.
#
# The harness prints anything it couldn't do as asked ("MacSnapshot:
# problem …", e.g. a size below the window's minimum); that shot then
# counts as failed. The script exits non-zero if any shot failed.
set -euo pipefail

OUT=${1:?usage: mac-snapshots.sh <out-dir> [shot ...]}
shift || true
APP=${MAC_APP:-/private/tmp/merc-mac-dd/Build/Products/Debug/Mercurius.app}
BIN="$APP/Contents/MacOS/Mercurius"
[ -x "$BIN" ] || { echo "no Mac build at $APP" >&2; exit 1; }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
VARIANTS=${VARIANTS:-"light dark min min-dark"}
STORE_SIZE=${STORE_SIZE:-1280x800}

# Every flag carries a value: AppKit takes a bare word after a value-less
# flag (`-EnterShell -MacSnapshotDelay 9`) as a document to open, and SwiftUI
# then opens no window.
ISOLATED=(-UITests YES -EphemeralSession YES -UseLocalServer YES -ApplePersistenceIgnoreState YES)
GATE=(-consentVersion 0 -hasSeenOnboarding NO)
PAST_GATE=(-consentVersion 1 -hasSeenOnboarding YES -hasSeenChatInputHint NO)

FAILED=0

# One launch → one PNG.
snap() {
  local name=$1; shift
  local log
  log=$(mktemp)
  rm -f "${OUT:?}/$name.png"
  "$BIN" -MacSnapshot "$OUT" -MacSnapshotName "$name" "${ISOLATED[@]}" "$@" 2>"$log" &
  local pid=$!
  # The app quits itself after its delay; give it a hard ceiling anyway.
  for _ in $(seq 1 50); do
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
  local problems
  problems=$(sed -n 's/^MacSnapshot: problem //p' "$log")
  if [ -n "$problems" ]; then
    echo "$problems" | sed "s/^/$name: problem: /" >&2
    FAILED=1
  fi
  if [ -f "$OUT/$name.png" ]; then
    echo "$name: ok"
  else
    echo "$name: FAILED" >&2
    cat "$log" >&2
    FAILED=1
  fi
  # The control dump and the composer log once per state (the light,
  # full-size shot), not once per variant.
  case $name in
    *-dark|*-min|*-store) ;;
    *)
      grep '^CONTROL' "$log" > "$OUT/$name.controls.txt" || rm -f "$OUT/$name.controls.txt"
      grep '^COMPOSER' "$log" > "$OUT/$name.composer.txt" || rm -f "$OUT/$name.composer.txt"
      ;;
  esac
  rm -f "$log"
}

# A main-window state in each variant.
window_shot() {
  local name=$1; shift
  for variant in $VARIANTS; do
    case $variant in
      light)    snap "$name"          "$@" -MacSnapshotAppearance light ;;
      dark)     snap "$name-dark"     "$@" -MacSnapshotAppearance dark ;;
      min)      snap "$name-min"      "$@" -MacSnapshotAppearance light -MacSnapshotSize 860x600 ;;
      min-dark) snap "$name-min-dark" "$@" -MacSnapshotAppearance dark -MacSnapshotSize 860x600 ;;
      store)    snap "$name-store"    "$@" -MacSnapshotAppearance light -MacSnapshotSize "$STORE_SIZE" -MacSnapshotOpaque YES ;;
    esac
  done
}

# The Settings or Help window: its own size, light and dark.
panel_shot() {
  local name=$1; shift
  for variant in $VARIANTS; do
    case $variant in
      light) snap "$name"      "$@" -MacSnapshotAppearance light ;;
      dark)  snap "$name-dark" "$@" -MacSnapshotAppearance dark ;;
    esac
  done
}

LESSON=(-LessonPreview YES -LessonReplay YES -LessonSkipIntro YES)

run() {
  case $1 in
    gate-meet)       window_shot "$1" "${GATE[@]}" -GateStep meet ;;
    gate-age)        window_shot "$1" "${GATE[@]}" -GateStep age -MacSnapshotDumpControls YES ;;
    gate-consent)    window_shot "$1" "${GATE[@]}" -GateStep disclosure -MacSnapshotDumpControls YES ;;
    today)           window_shot "$1" "${PAST_GATE[@]}" -EnterShell YES ;;
    path)            window_shot "$1" "${PAST_GATE[@]}" -EnterShellCurriculum YES ;;
    lesson-intro)    window_shot "$1" "${PAST_GATE[@]}" -LessonPreview YES ;;
    lesson)          window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -MacSnapshotDelay 10 ;;
    lesson-complete) window_shot "$1" "${PAST_GATE[@]}" -LessonPreview YES -ForceCelebrate YES -MacSnapshotDelay 5 ;;
    chat)            window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES ;;
    chat-thread)     window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -SeedDemoChat YES ;;
    # The toolbar's mode switch (as ⌘2/⌘3): Debate's one-time description,
    # then the chat in Debate and in Discussion. The switch asks the server
    # first, so the last two need a local server on :3000 that answers
    # POST /api/mode with {"mode": …}; without one they show "Couldn't
    # switch modes". Not in the default set for that reason.
    chat-mode-intro) window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -ChatPreviewMode debate -seenModeDescription.debate NO ;;
    chat-debate)     window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -ChatPreviewMode debate -seenAllModeDescriptions YES -MacSnapshotDelay 6 ;;
    chat-discussion) window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -ChatPreviewMode discussion -seenAllModeDescriptions YES -MacSnapshotDelay 6 ;;
    chat-typing)     window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -MacSnapshotType "Why do chatbots sound so sure?|Even when they're wrong?" -MacSnapshotDelay 6 ;;
    chat-failed)     window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -MacSnapshotType "What is a token?" -MacSnapshotSubmit YES -MacSnapshotDelay 8 ;;
    unit-test)       window_shot "$1" "${PAST_GATE[@]}" -UnitTestPreview YES -UnitTestStage review ;;
    crisis)          window_shot "$1" "${PAST_GATE[@]}" -UnitTestCrisisPreview YES -MacSnapshotDelay 5 ;;
    settings-general) panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow settings -MacSnapshotWindow settings -MacSettingsTab general ;;
    settings-privacy) panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow settings -MacSnapshotWindow settings -MacSettingsTab privacy ;;
    settings-about)   panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow settings -MacSnapshotWindow settings -MacSettingsTab about ;;
    help)            panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow help -MacSnapshotWindow help -MacSnapshotSize 600x640 ;;
    help-mac)        panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow help -MacSnapshotWindow help -MacSnapshotSize 600x640 -MacHelpTab mac ;;
    help-support)    panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow help -MacSnapshotWindow help -MacSnapshotSize 600x640 -MacHelpTab help ;;
    *) echo "unknown shot: $1" >&2; return 1 ;;
  esac
}

ALL="gate-meet gate-age gate-consent today path lesson-intro lesson lesson-complete chat chat-thread chat-mode-intro chat-typing chat-failed unit-test crisis settings-general settings-privacy settings-about help help-mac help-support"
if [ $# -eq 0 ]; then
  # shellcheck disable=SC2086
  set -- $ALL
fi
for name in "$@"; do run "$name"; done
exit "$FAILED"
