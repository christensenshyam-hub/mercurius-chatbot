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
# off screen before it is drawn (the window server still renders it). The
# app activates itself and makes the window key, so the picture shows it as
# it looks in use (red traffic lights, full-contrast sidebar): it takes the
# keyboard for those few seconds, so run the set when nobody is typing.
# ACTIVATE=NO leaves the keyboard alone and accepts inactive pictures.
# Liquid Glass surfaces that blend with what's behind the window (sidebar,
# toolbar, checkbox and pop-up bezels) come out dark or missing in the PNGs;
# see MercuriusMac/App/MacSnapshot.swift.
#
# The screen must be unlocked: while it is locked the window server draws
# nothing, and every picture comes out black at the wrong size.
#
# Usage (from ios/, after building the MercuriusMac scheme into the derived
# data below):
#   scripts/mac-snapshots.sh <out-dir> [shot ...]
# Each window shot is taken four ways: <shot>.png (1280×800, light),
# <shot>-dark.png, <shot>-min.png (700×600, the window's minimum) and
# <shot>-min-dark.png. The Settings and Help windows have their own size:
# light and dark only. Set VARIANTS="light" (or any of light dark min
# min-dark) to take fewer. VARIANTS="store" takes <shot>-store.png instead:
# light, square corners, no alpha, at STORE_SIZE points (default 1280x800,
# 2560×1600 px on a Retina display; STORE_SIZE=1440x900 gives 2880×1800 px
# on a display whose visible area is at least 900 pt tall). See
# mac-store-screenshots.sh.
#
# Night Studio's accessibility variants, through the app's DEBUG overrides
# (the Mac's own settings are never touched): hc / hc-dark (Increase
# Contrast, -NightContrast increased), rt / rt-dark (Reduce Transparency),
# rm (Reduce Motion), noglass / noglass-dark (the macOS 14–25 and CI-build
# material fallback, drawn on macOS 26). Each is <shot>-<variant>.png at
# 1280×800.
#
# The harness prints anything it couldn't do as asked ("MacSnapshot:
# problem …", e.g. a size below the window's minimum) and checks its own
# picture: the right pixel size, not one colour (blank), and — activated —
# a key window. Any problem fails that shot. The script also checks each
# PNG's pixel size itself against the size the harness expected, and fails
# a shot with no picture or no expected size. It exits non-zero if any shot
# failed.
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
ISOLATED=(-UITests YES -EphemeralSession YES -UseLocalServer YES -ApplePersistenceIgnoreState YES
          -MacSnapshotActivate "${ACTIVATE:-YES}")
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
    # The PNG's own size against what the harness expected (its frame at
    # the display's scale): a locked screen gives a smaller, black picture.
    local expect got
    expect=$(sed -n 's/^MacSnapshot: expect \([0-9]*x[0-9]*\)$/\1/p' "$log" | tail -1)
    got="$(sips -g pixelWidth "$OUT/$name.png" | awk '/pixelWidth/ {print $2}')x$(sips -g pixelHeight "$OUT/$name.png" | awk '/pixelHeight/ {print $2}')"
    if [ -z "$expect" ]; then
      echo "$name: problem: the harness reported no expected size (no window-server picture)" >&2
      FAILED=1
    elif [ "$got" != "$expect" ]; then
      echo "$name: problem: the PNG is $got px, expected $expect" >&2
      FAILED=1
    fi
    if [ -n "$problems" ] || [ -z "$expect" ] || [ "$got" != "$expect" ]; then
      echo "$name: FAILED ($got)" >&2
    else
      echo "$name: ok ($got)"
    fi
  else
    echo "$name: FAILED" >&2
    cat "$log" >&2
    FAILED=1
  fi
  # The control dump and the composer log once per state (the light,
  # full-size shot), not once per variant.
  case $name in
    *-dark|*-min|*-store|*-hc|*-rt|*-rm|*-noglass) ;;
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
      min)      snap "$name-min"      "$@" -MacSnapshotAppearance light -MacSnapshotSize 700x600 ;;
      min-dark) snap "$name-min-dark" "$@" -MacSnapshotAppearance dark -MacSnapshotSize 700x600 ;;
      store)    snap "$name-store"    "$@" -MacSnapshotAppearance light -MacSnapshotSize "$STORE_SIZE" -MacSnapshotOpaque YES ;;
      hc)       snap "$name-hc"       "$@" -MacSnapshotAppearance light -NightContrast increased ;;
      hc-dark)  snap "$name-dark-hc"  "$@" -MacSnapshotAppearance dark -NightContrast increased ;;
      rt)       snap "$name-rt"       "$@" -MacSnapshotAppearance light -NightReduceTransparency YES ;;
      rt-dark)  snap "$name-dark-rt"  "$@" -MacSnapshotAppearance dark -NightReduceTransparency YES ;;
      rm)       snap "$name-rm"       "$@" -MacSnapshotAppearance light -NightReduceMotion YES ;;
      noglass)  snap "$name-noglass"  "$@" -MacSnapshotAppearance light -NightNoGlass YES ;;
      noglass-dark) snap "$name-dark-noglass" "$@" -MacSnapshotAppearance dark -NightNoGlass YES ;;
    esac
  done
}

# The Settings or Help window, or a sheet: its own size, light and dark.
panel_shot() {
  local name=$1; shift
  for variant in $VARIANTS; do
    case $variant in
      light) snap "$name"      "$@" -MacSnapshotAppearance light ;;
      dark)  snap "$name-dark" "$@" -MacSnapshotAppearance dark ;;
      hc)    snap "$name-hc"   "$@" -MacSnapshotAppearance light -NightContrast increased ;;
      hc-dark) snap "$name-dark-hc" "$@" -MacSnapshotAppearance dark -NightContrast increased ;;
      rt)    snap "$name-rt"   "$@" -MacSnapshotAppearance light -NightReduceTransparency YES ;;
      rt-dark) snap "$name-dark-rt" "$@" -MacSnapshotAppearance dark -NightReduceTransparency YES ;;
    esac
  done
}

LESSON=(-LessonPreview YES -LessonReplay YES -LessonSkipIntro YES)

run() {
  case $1 in
    gate-meet)       window_shot "$1" "${GATE[@]}" -GateStep meet ;;
    gate-age)        window_shot "$1" "${GATE[@]}" -GateStep age -MacSnapshotDumpControls YES ;;
    gate-consent)    window_shot "$1" "${GATE[@]}" -GateStep disclosure -MacSnapshotDumpControls YES ;;
    gate-limits)     window_shot "$1" "${GATE[@]}" -GateStep limits ;;
    gate-paused)     window_shot "$1" "${GATE[@]}" -GateStep paused ;;
    gate-under13)    window_shot "$1" "${GATE[@]}" -GateStep underThirteen ;;
    gate-path)       window_shot "$1" "${GATE[@]}" -GateStep path ;;
    today)           window_shot "$1" "${PAST_GATE[@]}" -EnterShell YES ;;
    # Today with a week in it: two lessons this week, Lesson 3 opened, a
    # 4-day streak and a saved chat (DEBUG -TodayDemo; nothing is pushed).
    today-week)      window_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -TodayDemo YES -SeedDemoChat YES ;;
    path)            window_shot "$1" "${PAST_GATE[@]}" -EnterShellCurriculum YES ;;
    # Night Studio's unit page (DEBUG seeds in the -UITests progress suite,
    # never pushed): two lessons done and 1.3 lit; every lesson done and the
    # check open; the check passed (-NightPathUnit keeps Unit 1 on screen).
    path-week)       window_shot "$1" "${PAST_GATE[@]}" -EnterShellCurriculum YES -TodayDemo YES ;;
    path-check)      window_shot "$1" "${PAST_GATE[@]}" -EnterShellCurriculum YES -NightPathDemo check ;;
    path-mastered)   window_shot "$1" "${PAST_GATE[@]}" -EnterShellCurriculum YES -NightPathDemo mastered -NightPathUnit unit_1 ;;
    lesson-intro)    window_shot "$1" "${PAST_GATE[@]}" -LessonPreview YES ;;
    lesson)          window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -MacSnapshotDelay 10 ;;
    # Night Studio's check (DEBUG -NightCheckState, -NightScrollToPart): the
    # recorded first reply's check with B picked and Lock it in showing; then
    # locked in, which sends "I picked B) …" through the real path and
    # replays Merc's second reply, the part strip's jump back to the check.
    lesson-top)      window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightScrollToPart 1 -MacSnapshotDelay 10 ;;
    # AUD-29 in Night: the first reply (its opening paragraphs) drops
    # mid-stream and is kept, with its failure line and Retry.
    lesson-cut)      window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -LessonReplayCut YES -LessonReplayShort YES -MacSnapshotDelay 8 ;;
    # Lesson 1.1's interactive, "How a model reads “bank”" (DEBUG
    # -NightScrollToInteractive): the replay's first reply settles with the
    # card closing its Tokenization part, before the check. The card's top;
    # its map, with no opening and with each opening picked (-NightTokenizer);
    # the compact "Try it" card (-NightTokenizerCompact, as a card narrower
    # than 440 pt starts).
    lesson-interactive)         window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightScrollToInteractive top -MacSnapshotDelay 11 ;;
    lesson-interactive-map)     window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightScrollToInteractive map -MacSnapshotDelay 11 ;;
    lesson-interactive-money)   window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightScrollToInteractive map -NightTokenizer money -MacSnapshotDelay 11 ;;
    lesson-interactive-river)   window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightScrollToInteractive map -NightTokenizer river -MacSnapshotDelay 11 ;;
    lesson-interactive-compact) window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightScrollToInteractive top -NightTokenizerCompact YES -MacSnapshotDelay 11 ;;
    lesson-check)    window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightScrollToPart 3 -NightCheckState picked -MacSnapshotDelay 11 ;;
    lesson-answered) window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightScrollToPart 3 -NightCheckState answered -MacSnapshotDelay 18 ;;
    # Night Studio's complete card: the replay's first reply streams in
    # (its two key ideas), then the card shows (-NightCompleteAfterReply);
    # -NightCompleteDemo counts Lesson 1 as finished a minute ago, so the
    # week row reads 1 of 2. Nothing is pushed.
    lesson-complete) window_shot "$1" "${PAST_GATE[@]}" "${LESSON[@]}" -NightCompleteAfterReply YES -NightCompleteDemo YES -MacSnapshotDelay 12 ;;
    chat)            window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES ;;
    chat-thread)     window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -SeedDemoChat YES ;;
    # A real recorded Socratic thread (DEBUG -NightChatDemo): Merc's last
    # reply cites a source and ends on a question (the source chip, Your turn).
    chat-socratic)   window_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -NightChatDemo YES -MacSnapshotDelay 6 ;;
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
    unit-test-quiz)  window_shot "$1" "${PAST_GATE[@]}" -UnitTestPreview YES -UnitTestStage partial ;;
    unit-test-written) window_shot "$1" "${PAST_GATE[@]}" -UnitTestPreview YES -UnitTestStage written ;;
    unit-test-mastered) window_shot "$1" "${PAST_GATE[@]}" -UnitTestPreview YES -UnitTestStage mastered ;;
    unit-test-almost) window_shot "$1" "${PAST_GATE[@]}" -UnitTestPreview YES -UnitTestStage almost ;;
    unit-test-unavailable) window_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -NightUnitTestUnavailable YES ;;
    # The chat's Quiz me sheet (DEBUG -NightOpenQuiz). With no local server
    # the quiz request fails fast: its failure state and Try again.
    chat-quiz)       panel_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -NightChatDemo YES -NightOpenQuiz YES -MacSnapshotWindow sheet -MacSnapshotDelay 7 ;;
    # The mode explainer sheet itself (chat-mode-intro shows the window
    # under it).
    chat-mode-sheet) panel_shot "$1" "${PAST_GATE[@]}" -ChatPreview YES -ChatPreviewMode debate -seenModeDescription.debate NO -MacSnapshotWindow sheet ;;
    start-failure)   window_shot "$1" "${PAST_GATE[@]}" -NightStartFailure YES ;;
    crisis)          window_shot "$1" "${PAST_GATE[@]}" -UnitTestCrisisPreview YES -MacSnapshotDelay 5 ;;
    settings-general) panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow settings -MacSnapshotWindow settings -MacSettingsTab general ;;
    settings-privacy) panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow settings -MacSnapshotWindow settings -MacSettingsTab privacy ;;
    settings-about)   panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow settings -MacSnapshotWindow settings -MacSettingsTab about ;;
    settings-gated)   panel_shot "$1" "${GATE[@]}" -MacOpenWindow settings -MacSnapshotWindow settings ;;
    help)            panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow help -MacSnapshotWindow help -MacSnapshotSize 600x640 ;;
    help-mac)        panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow help -MacSnapshotWindow help -MacSnapshotSize 600x640 -MacHelpTab mac ;;
    help-support)    panel_shot "$1" "${PAST_GATE[@]}" -EnterShell YES -MacOpenWindow help -MacSnapshotWindow help -MacSnapshotSize 600x640 -MacHelpTab help ;;
    *) echo "unknown shot: $1" >&2; return 1 ;;
  esac
}

ALL="gate-meet gate-age gate-consent gate-limits gate-paused gate-under13 gate-path today today-week path path-week path-check path-mastered lesson-intro lesson lesson-top lesson-cut lesson-interactive lesson-interactive-map lesson-interactive-money lesson-interactive-river lesson-interactive-compact lesson-check lesson-answered lesson-complete chat chat-thread chat-socratic chat-mode-intro chat-mode-sheet chat-typing chat-failed chat-quiz unit-test unit-test-quiz unit-test-written unit-test-mastered unit-test-almost unit-test-unavailable crisis start-failure settings-general settings-privacy settings-about settings-gated help help-mac help-support"
if [ $# -eq 0 ]; then
  # shellcheck disable=SC2086
  set -- $ALL
fi
for name in "$@"; do run "$name"; done
exit "$FAILED"
