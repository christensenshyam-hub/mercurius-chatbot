#!/bin/bash
# Headless Chrome with a throwaway profile, quit by its PID (and any helper
# by the profile's unique path) — never by name, so a Chrome in use is left
# alone. Usage: chrome-shot.sh <chrome args…>
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROF=$(mktemp -d "${TMPDIR:-/tmp}/certificate-chrome.XXXXXX")
"$CH" --headless=new --disable-gpu --no-first-run --user-data-dir="$PROF" \
  --allow-file-access-from-files --hide-scrollbars "$@" &
PID=$!
for _ in $(seq 1 120); do kill -0 $PID 2>/dev/null || break; sleep 0.5; done
kill $PID 2>/dev/null; sleep 0.5; kill -9 $PID 2>/dev/null
for p in $(pgrep -f "$PROF"); do kill $p 2>/dev/null; done
sleep 0.3
for p in $(pgrep -f "$PROF"); do kill -9 $p 2>/dev/null; done
rm -rf "$PROF"
