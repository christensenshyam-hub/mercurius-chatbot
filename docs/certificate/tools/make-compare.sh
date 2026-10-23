#!/bin/bash
# Rebuilds docs/certificate/shots (the app's PDFs and 150 dpi PNGs) and
# docs/certificate/compare (design | app), from the worktree's root:
#   docs/certificate/tools/make-compare.sh
# Needs Google Chrome, Python 3 with Pillow, and the SwiftPM toolchain.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DOC="$ROOT/docs/certificate"
TOOLS="$DOC/tools"
SHOTS="$DOC/shots"
CMP="$DOC/compare"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/certificate-compare.XXXXXX")
FONTS="$ROOT/ios/Packages/DesignSystem/Sources/Fonts"
MARK="$ROOT/ios/Packages/DesignSystem/Sources/CertificateArt/certificate-mark.png"
NAME="Alexandria Montgomery-Vasquez"
DATE="October 21, 2026"
mkdir -p "$SHOTS" "$CMP"

# 1. The app's PDFs, from the package's own build.
(cd "$ROOT/ios/Packages" && CERTIFICATE_SHOTS_DIR="$SHOTS" swift test --scratch-path "${SPM_SCRATCH:-/private/tmp/merc-cert-spm}" --filter CertificateShots >/dev/null)

# 2. Each PDF at 150 dpi (and its fonts, images and text, for the record).
swiftc -O "$TOOLS/pdf-render.swift" -o "$WORK/pdf-render"
for pdf in "$SHOTS"/certificate-*.pdf; do
  "$WORK/pdf-render" "$pdf" "${pdf%.pdf}-150dpi.png" 150 > "${pdf%.pdf}.inspect.txt"
done

# 3. The designs, standalone, through Chrome at 150 dpi (1056 CSS px = 11 in).
for k in Laurel LaurelBasics; do
  python3 "$TOOLS/standalone.py" "$DOC/design/$k.dc.html" "$WORK/$k.html" "$NAME" "$DATE" "$MARK" "$FONTS"
  "$TOOLS/chrome-shot.sh" --virtual-time-budget=5000 --force-device-scale-factor=1.5625 \
    --window-size=1056,816 --screenshot="$WORK/$k-150.png" "file://$WORK/$k.html" 2>/dev/null
  cp "$WORK/$k.html" "$CMP/$k.standalone.html"
done

# 4. design | app, and the overlay (design red, app cyan).
python3 "$TOOLS/compare.py" "$WORK/Laurel-150.png" "$SHOTS/certificate-deepDive-150dpi.png" "$CMP/deepDive" "Laurel.dc.html"
python3 "$TOOLS/compare.py" "$WORK/LaurelBasics-150.png" "$SHOTS/certificate-basics-150dpi.png" "$CMP/basics" "LaurelBasics.dc.html"
cp "$WORK/Laurel-150.png" "$CMP/design-deepDive-150dpi.png"
cp "$WORK/LaurelBasics-150.png" "$CMP/design-basics-150dpi.png"
rm -rf "$WORK"
