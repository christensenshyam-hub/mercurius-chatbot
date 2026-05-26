#!/usr/bin/env bash
#
# release.sh — archive Mercurius for TestFlight distribution.
#
# What this does:
#   1. Bumps the build number (CURRENT_PROJECT_VERSION) by +1 unless
#      `--no-bump` is passed.
#   2. Cleans previous archives so codesign doesn't pick up stale bits.
#   3. Builds a signed archive (App Store distribution) into
#      `ios/build/Mercurius.xcarchive`.
#   4. Exports the archive to an .ipa using
#      `scripts/ExportOptions.plist`.
#   5. Prints next-steps for uploading to App Store Connect.
#
# Why two steps (archive → export) instead of `-destination upload`:
#   `xcodebuild -exportArchive -exportPath ...` writes the .ipa to disk;
#   you can then upload via Xcode Organizer (point-and-click) OR via
#   `xcrun altool --upload-app` (script-friendly, needs an
#   app-specific password). Driving upload from a CI runner is the
#   next step — for first launch the GUI flow is friendlier.
#
# Usage:
#   ./scripts/release.sh                 # bumps build, archives, exports
#   ./scripts/release.sh --no-bump       # archive at current version
#   ./scripts/release.sh --archive-only  # skip the .ipa export
#

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IOS_DIR="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

PROJECT="${IOS_DIR}/Mercurius.xcodeproj"
SCHEME="Mercurius"
BUILD_DIR="${IOS_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/Mercurius.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
EXPORT_OPTIONS="${SCRIPT_DIR}/ExportOptions.plist"
PROJECT_YML="${IOS_DIR}/project.yml"

NO_BUMP=0
ARCHIVE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --no-bump) NO_BUMP=1 ;;
    --archive-only) ARCHIVE_ONLY=1 ;;
    *) echo "Unknown arg: $arg"; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. Build-number bump (idempotent — reads from project.yml, writes back)
# ---------------------------------------------------------------------------
if [ "$NO_BUMP" -eq 0 ]; then
  current=$(grep -E '^    CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([0-9]+)".*/\1/')
  if ! [[ "$current" =~ ^[0-9]+$ ]]; then
    echo "Could not parse CURRENT_PROJECT_VERSION from $PROJECT_YML (got: '$current')"; exit 3
  fi
  next=$((current + 1))
  echo "📈  Bumping build number: $current → $next"
  /usr/bin/sed -i '' "s|CURRENT_PROJECT_VERSION: \"$current\"|CURRENT_PROJECT_VERSION: \"$next\"|" "$PROJECT_YML"

  # Regenerate the xcodeproj so the bump lands in the .pbxproj.
  echo "🔧  Regenerating Xcode project..."
  (cd "$IOS_DIR" && xcodegen generate >/dev/null)
fi

# ---------------------------------------------------------------------------
# 2. Clean previous archives
# ---------------------------------------------------------------------------
echo "🧹  Cleaning previous archives..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 3. Archive
# ---------------------------------------------------------------------------
echo "📦  Archiving Mercurius (this takes ~3-5 min)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive \
  | grep -E '\*\* ARCHIVE|error:|warning:' \
  || true

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "❌  Archive failed — see Xcode output above."
  exit 4
fi
echo "✅  Archive at: $ARCHIVE_PATH"

if [ "$ARCHIVE_ONLY" -eq 1 ]; then
  echo ""
  echo "Stopping after archive (--archive-only). Next:"
  echo "   • Open the archive in Xcode Organizer:"
  echo "       open '$ARCHIVE_PATH'"
  echo "   • Or run this script without --archive-only to also export the .ipa."
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Export to .ipa
# ---------------------------------------------------------------------------
echo ""
echo "📤  Exporting .ipa via ExportOptions.plist..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  | grep -E 'EXPORT SUCCEEDED|error:|warning:' \
  || true

IPA_PATH=$(find "$EXPORT_PATH" -name '*.ipa' | head -n 1)
if [ -z "$IPA_PATH" ]; then
  echo "❌  Export failed — see output above."
  exit 5
fi
echo "✅  .ipa at: $IPA_PATH"

# ---------------------------------------------------------------------------
# 5. Next steps
# ---------------------------------------------------------------------------
cat <<EOF

────────────────────────────────────────────────────────────
✅  Build is ready to upload to App Store Connect.

  IPA file:
    $IPA_PATH

Choose one upload path:

  A) Xcode Organizer (GUI, simplest first time):
       open '$ARCHIVE_PATH'
     → Distribute App → App Store Connect → Upload

  B) Transporter app (free from the Mac App Store):
       open -a Transporter '$IPA_PATH'

  C) Command line (needs an App-Specific Password from
     appleid.apple.com → Sign-In and Security → App-Specific Passwords):
       xcrun altool --upload-app -f '$IPA_PATH' -t ios \\
         -u <your-apple-id> -p <app-specific-password>

After upload: Apple processes the build (~10-20 min). It then
appears in App Store Connect → Apps → Mercurius AI → TestFlight.
────────────────────────────────────────────────────────────
EOF
