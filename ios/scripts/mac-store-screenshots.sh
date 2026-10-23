#!/usr/bin/env bash
# Mac App Store screenshots of the native Mac app.
#
# Takes each main-window state through the DEBUG -MacSnapshot harness
# (mac-snapshots.sh, VARIANTS=store): the harness's light flag (the app is
# dark only, so the windows keep the night look anyway), the window's rounded
# corners filled, no alpha channel, at STORE_SIZE points.
#
# Sizes. The Mac App Store takes four 16:10 sizes: 1280×800, 1440×900,
# 2560×1600 and 2880×1800 px. The harness photographs the real window at the
# display's scale, so the pixel size is STORE_SIZE × the backing scale:
#   STORE_SIZE=1280x800 (the default) → 2560×1600 on a Retina display.
#   STORE_SIZE=1440x900               → 2880×1800, but only on a display whose
#     visible area (below the menu bar, beside the Dock) is at least 900 pt
#     tall — not a 13- or 14-inch MacBook at its default resolution (the
#     14-inch has 888 pt). Too tall a window is shrunk by macOS, and the
#     harness reports a problem instead of a wrong-sized picture.
# The script accepts any of the four sizes, fails on anything else, on a PNG
# with alpha and on anything the harness couldn't do as asked, and prints the
# size it got.
#
# Runs are isolated like every harness run: in-memory chats and session id,
# the local server URL, nothing reaches production. Each launch shows a
# window for a few seconds, almost entirely off screen.
#
# Usage (from ios/, after building the MercuriusMac scheme, Debug, into the
# derived data mac-snapshots.sh expects — or set MAC_APP):
#   scripts/mac-store-screenshots.sh <out-dir> [state ...]
# Default states, in store order: path lesson chat today gate-consent
# chat-thread. Files come out numbered in that order: 01-path.png, …
#
# What these pictures can't show (see MercuriusMac/App/MacSnapshot.swift):
# Liquid Glass surfaces blend with what's behind the window, and the
# capture has only the window. Check every shot by eye before uploading —
# in particular the chat toolbar, whose scroll-edge band can show the
# thread's text behind the mode picker instead of blurring it.
set -euo pipefail

OUT=${1:?usage: mac-store-screenshots.sh <out-dir> [state ...]}
shift || true
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

STATES=("$@")
if [ ${#STATES[@]} -eq 0 ]; then
  STATES=(path lesson chat today gate-consent chat-thread)
fi

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
RAW=$(mktemp -d)
trap 'rm -rf "$RAW"' EXIT

status=0
VARIANTS=store "$SCRIPT_DIR/mac-snapshots.sh" "$RAW" "${STATES[@]}" || status=1

index=0
for state in "${STATES[@]}"; do
  index=$((index + 1))
  src="$RAW/$state-store.png"
  dest="$OUT/$(printf '%02d' "$index")-$state.png"
  if [ ! -f "$src" ]; then
    echo "$state: no picture" >&2
    status=1
    continue
  fi
  width=$(sips -g pixelWidth "$src" | awk '/pixelWidth/ {print $2}')
  height=$(sips -g pixelHeight "$src" | awk '/pixelHeight/ {print $2}')
  alpha=$(sips -g hasAlpha "$src" | awk '/hasAlpha/ {print $2}')
  case "${width}x${height}" in
    2880x1800|2560x1600|1440x900|1280x800) ;;
    *)
      echo "$state: ${width}x${height} is not a Mac App Store size (2880x1800, 2560x1600, 1440x900 or 1280x800)" >&2
      status=1
      continue
      ;;
  esac
  if [ "$alpha" != "no" ]; then
    echo "$state: the PNG has an alpha channel" >&2
    status=1
    continue
  fi
  cp "$src" "$dest"
  echo "$(basename "$dest"): ${width}x${height}, no alpha"
done

exit "$status"
