#!/usr/bin/env bash
#
# release.sh — fully automated TestFlight build + upload.
#
# What this does:
#   1. Reads App Store Connect API credentials from ~/.appstoreconnect/
#   2. Refuses a dirty tree (or iCloud " 2" duplicates) — the archive is
#      whatever is on disk, and a build must map back to one commit
#   3. Bumps CURRENT_PROJECT_VERSION by +1 (skip with --no-bump); a failed
#      run puts project.yml back, so a rerun doesn't skip a number
#   4. Cleans previous archives
#   5. Builds a signed Release archive with API-key auth — Xcode
#      doesn't need to be signed in. xcodebuild fetches the right
#      provisioning profile from App Store Connect using the .p8 key.
#      Retried up to 3 times for the intermittent xattr codesign race.
#   6. Exports the archive to a .ipa via ExportOptions.plist
#   7. Uploads the .ipa to App Store Connect with xcrun altool +
#      the same API key. From there it appears in TestFlight after
#      Apple finishes processing (~10–20 min).
#   8. Tags the commit it built: ios/v<marketing>-<build> (local; push it)
#
# Credentials (one-time setup):
#   ~/.appstoreconnect/key_id        — App Store Connect API Key ID
#   ~/.appstoreconnect/issuer_id     — App Store Connect Issuer ID
#   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#                                    — downloaded once from
#                                      appstoreconnect.apple.com →
#                                      Users and Access → Integrations
#                                      → App Store Connect API
#
# Usage:
#   ./scripts/release.sh                 # bump → archive → export → upload
#   ./scripts/release.sh --no-bump       # skip the build-number bump
#   ./scripts/release.sh --no-upload     # archive + export only, skip upload
#   ./scripts/release.sh --allow-dirty   # skip the clean-tree check
#
# The codesigning keychain password comes from MERCURIUS_KEYCHAIN_PASSWORD
# (provision.sh's default when unset).
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

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
ASC_DIR="${HOME}/.appstoreconnect"
KEY_ID_FILE="${ASC_DIR}/key_id"
ISSUER_ID_FILE="${ASC_DIR}/issuer_id"

if [ ! -f "$KEY_ID_FILE" ] || [ ! -f "$ISSUER_ID_FILE" ]; then
  echo "❌ Missing credentials:"
  echo "   $KEY_ID_FILE"
  echo "   $ISSUER_ID_FILE"
  echo ""
  echo "Set them up with:"
  echo "   mkdir -p ${ASC_DIR}"
  echo "   echo '<your-key-id>' > $KEY_ID_FILE"
  echo "   echo '<your-issuer-id>' > $ISSUER_ID_FILE"
  exit 10
fi

ASC_KEY_ID=$(cat "$KEY_ID_FILE" | tr -d '[:space:]')
ASC_ISSUER_ID=$(cat "$ISSUER_ID_FILE" | tr -d '[:space:]')
ASC_KEY_PATH="${ASC_DIR}/private_keys/AuthKey_${ASC_KEY_ID}.p8"

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "❌ Missing private key: $ASC_KEY_PATH"
  echo ""
  echo "Download AuthKey_${ASC_KEY_ID}.p8 from App Store Connect →"
  echo "Users and Access → Integrations → App Store Connect API, then:"
  echo "   mkdir -p ${ASC_DIR}/private_keys"
  echo "   mv ~/Downloads/AuthKey_${ASC_KEY_ID}.p8 ${ASC_DIR}/private_keys/"
  exit 11
fi

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
NO_BUMP=0
NO_UPLOAD=0
ALLOW_DIRTY=0

# Any exit before the upload finishes puts the build number back.
BUMPED=0
restore_bump() {
  if [ "$BUMPED" -eq 1 ]; then
    mv -f "${PROJECT_YML}.prebump" "$PROJECT_YML"
    echo "↩️   Restored the build number in project.yml."
  fi
}
trap restore_bump EXIT
keep_bump() {
  BUMPED=0
  rm -f "${PROJECT_YML}.prebump"
}
for arg in "$@"; do
  case "$arg" in
    --no-bump) NO_BUMP=1 ;;
    --no-upload) NO_UPLOAD=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    *) echo "Unknown arg: $arg"; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# 0. Clean tree
# ---------------------------------------------------------------------------
REPO_DIR="$(git -C "$IOS_DIR" rev-parse --show-toplevel)"
if [ "$ALLOW_DIRTY" -eq 0 ]; then
  if ! git -C "$REPO_DIR" diff --quiet || ! git -C "$REPO_DIR" diff --cached --quiet; then
    echo "❌  Uncommitted changes — commit or stash them first (or pass --allow-dirty)."
    git -C "$REPO_DIR" status --short
    exit 6
  fi
  DUPES=$(find "$IOS_DIR" \( -path "$IOS_DIR/build" -o -name .build -o -name '*.xcodeproj' \) -prune \
    -o -name '* 2.*' -print)
  if [ -n "$DUPES" ]; then
    echo "❌  iCloud duplicate files would be archived — delete them first:"
    echo "$DUPES"
    exit 7
  fi
fi

# ---------------------------------------------------------------------------
# 1. Build-number bump (reads from project.yml, writes back)
# ---------------------------------------------------------------------------
if [ "$NO_BUMP" -eq 0 ]; then
  current=$(grep -E '^    CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([0-9]+)".*/\1/')
  if ! [[ "$current" =~ ^[0-9]+$ ]]; then
    echo "❌ Could not parse CURRENT_PROJECT_VERSION (got: '$current')"; exit 3
  fi
  next=$((current + 1))
  echo "📈  Bumping build number: $current → $next"
  cp "$PROJECT_YML" "${PROJECT_YML}.prebump"
  BUMPED=1
  /usr/bin/sed -i '' "s|CURRENT_PROJECT_VERSION: \"$current\"|CURRENT_PROJECT_VERSION: \"$next\"|" "$PROJECT_YML"
  echo "🔧  Regenerating Xcode project..."
  (cd "$IOS_DIR" && xcodegen generate >/dev/null)
fi

# ---------------------------------------------------------------------------
# 2. Clean
# ---------------------------------------------------------------------------
echo "🧹  Cleaning previous archives..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 2.5. Unlock the dedicated codesigning keychain.
# `provision.sh` creates `mercurius-codesign.keychain-db` and stores the
# Apple Distribution cert + key there. macOS will re-lock it after the
# configured idle timeout, so re-unlock it here every release. If the
# keychain doesn't exist yet, the user hasn't run provision.sh — tell
# them what to do.
# ---------------------------------------------------------------------------
CODESIGN_KEYCHAIN="${HOME}/Library/Keychains/mercurius-codesign.keychain-db"
CODESIGN_KEYCHAIN_PASSWORD="${MERCURIUS_KEYCHAIN_PASSWORD:-mercurius-ci}"
if [ ! -f "$CODESIGN_KEYCHAIN" ]; then
  echo "❌  Dedicated codesigning keychain not found."
  echo "    Run ./scripts/provision.sh once to create it."
  exit 12
fi
echo "🔓  Unlocking codesigning keychain..."
security unlock-keychain -p "$CODESIGN_KEYCHAIN_PASSWORD" "$CODESIGN_KEYCHAIN"
security set-keychain-settings -lut 21600 "$CODESIGN_KEYCHAIN"

# ---------------------------------------------------------------------------
# 3. Archive — uses API-key auth (no Xcode sign-in needed)
# ---------------------------------------------------------------------------
echo "📦  Archiving Mercurius (this takes ~3-5 min)..."
# The "resource fork, Finder information, or similar detritus" codesign
# failure is a race; a plain retry clears it.
archived=0
for attempt in 1 2 3; do
  rm -rf "$ARCHIVE_PATH"
  if xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    archive; then
    archived=1
    break
  fi
  echo "⚠️   Archive attempt $attempt failed."
done

if [ "$archived" -ne 1 ] || [ ! -d "$ARCHIVE_PATH" ]; then
  echo "❌  Archive failed — see Xcode output above."
  exit 4
fi
echo "✅  Archive at: $ARCHIVE_PATH"

# ---------------------------------------------------------------------------
# 4. Export .ipa
# ---------------------------------------------------------------------------
echo ""
echo "📤  Exporting .ipa..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

IPA_PATH=$(find "$EXPORT_PATH" -name '*.ipa' | head -n 1)
if [ -z "$IPA_PATH" ]; then
  echo "❌  Export failed — see output above."
  exit 5
fi
echo "✅  .ipa at: $IPA_PATH"

if [ "$NO_UPLOAD" -eq 1 ]; then
  keep_bump
  echo ""
  echo "Stopping after export (--no-upload). To upload later, run:"
  echo "   xcrun altool --upload-app -f '$IPA_PATH' -t ios \\"
  echo "     --apiKey '$ASC_KEY_ID' --apiIssuer '$ASC_ISSUER_ID'"
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Upload to App Store Connect via altool — same API key
# ---------------------------------------------------------------------------
echo ""
echo "☁️   Uploading to App Store Connect..."
xcrun altool --upload-app \
  --file "$IPA_PATH" \
  --type ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

# Uploaded: the bump stands.
keep_bump

MARKETING=$(grep -E '^    MARKETING_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(grep -E '^    CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([0-9]+)".*/\1/')
TAG="ios/v${MARKETING}-${BUILD}"
if git -C "$REPO_DIR" tag "$TAG" 2>/dev/null; then
  echo "🏷   Tagged $(git -C "$REPO_DIR" rev-parse --short HEAD) as $TAG — push it: git push origin $TAG"
else
  echo "⚠️   Could not tag $TAG (it may already exist)."
fi

cat <<EOF

────────────────────────────────────────────────────────────
✅  Upload complete. Commit the build-number bump in ios/project.yml.

Apple is now processing the build (~10–20 min). It will appear in:
   App Store Connect → Apps → Mercurius AI → TestFlight tab

The first build always needs you to answer Apple's encryption-use
question in the TestFlight UI — we already declared
ITSAppUsesNonExemptEncryption=false in Info.plist, so it should
auto-pass and the build will go into the "Internal Testing"
section ready to assign to testers.

If you don't see the build after 30 minutes, check:
   • App Store Connect → Apps → Mercurius AI → Activity tab
   • Your email — Apple sends a notification if processing failed.
────────────────────────────────────────────────────────────
EOF
