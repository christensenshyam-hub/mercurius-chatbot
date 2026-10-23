#!/usr/bin/env bash
#
# release.sh — fully automated TestFlight build + upload, for the iOS app
# or (--platform mac) the native Mac app.
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
#      (Mac: a signed .pkg via ExportOptionsMac.plist)
#   7. Uploads the .ipa to App Store Connect with xcrun altool +
#      the same API key (Mac: the .pkg, --type macos). From there it
#      appears in TestFlight after Apple finishes processing (~10–20 min).
#   8. Tags the commit it built: ios/v<marketing>-<build> (local; push it)
#      (Mac: mac/v<marketing>-<build>)
#
# Before any of that it checks, in a few seconds, what would otherwise fail
# minutes in:
#   - Mac: the "Mercurius Mac App Store" profile is installed and the
#     dedicated keychain holds the Apple Distribution and Mac Installer
#     Distribution identities (./scripts/provision.sh --platform mac makes
#     them). Missing → exit 13, nothing built.
#   - Both: App Store Connect answers the API key. A missing agreement
#     (HTTP 403, FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED) stops an
#     uploading run with an explanation (exit 21); with --no-upload it is a
#     warning and the archive + export go ahead. If xcodebuild or altool
#     later refuse for the same reason, the script says so too.
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
#   ./scripts/release.sh --platform mac  # the Mac app (any flag above too)
#
# iOS and Mac share MARKETING_VERSION and CURRENT_PROJECT_VERSION
# (project.yml). A bump for one platform skips a number on the other, which
# App Store Connect allows: each platform's builds only have to increase.
#
# The codesigning keychain password comes from MERCURIUS_KEYCHAIN_PASSWORD
# (provision.sh's default when unset).
#

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IOS_DIR="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

PROJECT="${IOS_DIR}/Mercurius.xcodeproj"
BUILD_DIR="${IOS_DIR}/build"
PROJECT_YML="${IOS_DIR}/project.yml"

# ---------------------------------------------------------------------------
# Credentials (asc-api.sh: ~/.appstoreconnect/, exits 10 / 11 when missing)
# ---------------------------------------------------------------------------
# shellcheck source=asc-api.sh
. "${SCRIPT_DIR}/asc-api.sh"
asc_load_credentials

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
NO_BUMP=0
NO_UPLOAD=0
ALLOW_DIRTY=0
PLATFORM=ios

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
while [ $# -gt 0 ]; do
  case "$1" in
    --no-bump) NO_BUMP=1 ;;
    --no-upload) NO_UPLOAD=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --platform) PLATFORM="${2:-}"; shift ;;
    --platform=*) PLATFORM="${1#--platform=}" ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
  shift
done

# Per platform: what to build, how to export it, what comes out, how it
# uploads and what the tag is called.
case "$PLATFORM" in
  ios)
    SCHEME="Mercurius"
    DESTINATION="generic/platform=iOS"
    ARCHIVE_PATH="${BUILD_DIR}/Mercurius.xcarchive"
    EXPORT_PATH="${BUILD_DIR}/export"
    EXPORT_OPTIONS="${SCRIPT_DIR}/ExportOptions.plist"
    ARTIFACT_EXT="ipa"
    ALTOOL_TYPE="ios"
    TAG_PREFIX="ios"
    ;;
  mac)
    SCHEME="MercuriusMac"
    DESTINATION="generic/platform=macOS"
    ARCHIVE_PATH="${BUILD_DIR}/MercuriusMac.xcarchive"
    EXPORT_PATH="${BUILD_DIR}/export-mac"
    EXPORT_OPTIONS="${SCRIPT_DIR}/ExportOptionsMac.plist"
    ARTIFACT_EXT="pkg"
    ALTOOL_TYPE="macos"
    TAG_PREFIX="mac"
    MAC_PROFILE_NAME="Mercurius Mac App Store"
    ;;
  *) echo "Unknown platform '$PLATFORM' (ios or mac)"; exit 2 ;;
esac
LOG_DIR="${BUILD_DIR}/release-logs"
mkdir -p "$LOG_DIR"

# xcodebuild / altool output that is Apple refusing for want of an accepted
# agreement gets the same explanation as the API's 403.
explain_if_agreement() {
  if asc_log_mentions_agreement "$1"; then
    asc_explain_agreement
    exit "$ASC_EXIT_AGREEMENT"
  fi
}

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
# 0.5. Preflight: the signing assets (Mac) and App Store Connect's answer.
# Nothing has been bumped or built yet, so a stop here changes nothing.
# ---------------------------------------------------------------------------
CODESIGN_KEYCHAIN="${HOME}/Library/Keychains/mercurius-codesign.keychain-db"
if [ "$PLATFORM" = mac ]; then
  echo "🔎  Checking the Mac signing assets..."
  missing=()
  # Installed, unexpired profile with this name (old or Xcode 16+ folder).
  have_profile=0
  for dir in "${HOME}/Library/MobileDevice/Provisioning Profiles" \
             "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    [ -d "$dir" ] || continue
    for file in "$dir"/*.provisionprofile; do
      [ -f "$file" ] || continue
      if security cms -D -i "$file" 2>/dev/null | /usr/bin/python3 -c '
import sys, plistlib, datetime
p = plistlib.loads(sys.stdin.buffer.read())
ok = p.get("Name") == sys.argv[1] and p.get("ExpirationDate", datetime.datetime.max) > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
sys.exit(0 if ok else 1)
' "$MAC_PROFILE_NAME"; then
        have_profile=1
      fi
    done
  done
  [ "$have_profile" -eq 1 ] || missing+=("the \"$MAC_PROFILE_NAME\" provisioning profile")
  identities=""
  [ -f "$CODESIGN_KEYCHAIN" ] && identities=$(security find-identity -v -p basic "$CODESIGN_KEYCHAIN" 2>/dev/null || true)
  grep -q "Apple Distribution" <<<"$identities" \
    || missing+=("the Apple Distribution identity in mercurius-codesign.keychain-db")
  grep -Eq "3rd Party Mac Developer Installer|Mac Installer Distribution" <<<"$identities" \
    || missing+=("the Mac Installer Distribution identity (\"3rd Party Mac Developer Installer\") in mercurius-codesign.keychain-db")
  if [ ${#missing[@]} -gt 0 ]; then
    echo "❌  The Mac app can't be signed for the Mac App Store yet. Missing:"
    for item in "${missing[@]}"; do echo "    • $item"; done
    echo ""
    echo "    Make them with:  ./scripts/provision.sh --platform mac"
    echo "    (./scripts/provision.sh --check --platform mac shows what exists.)"
    echo "    If App Store Connect answers 403 about an agreement, the Account Holder"
    echo "    has to accept it first (the provision script explains where)."
    echo "    Nothing was bumped or built."
    exit 13
  fi
  echo "    profile and identities present."
fi

echo "🔎  Asking App Store Connect whether it will take this key..."
asc_make_jwt
probe=0
asc_probe "com.mayoailiteracy.mercurius.native" || probe=$?
case "$probe" in
  0) echo "    it answers." ;;
  "$ASC_EXIT_AGREEMENT")
    asc_explain_agreement "${ASC_PROBE_DETAIL:-}"
    if [ "$NO_UPLOAD" -eq 0 ]; then
      echo "Stopping before the build: the upload would be refused. (--no-upload archives"
      echo "and exports anyway.) Nothing was bumped or built."
      exit "$ASC_EXIT_AGREEMENT"
    fi
    echo "⚠️   Going on with archive + export only (--no-upload). Signing may still need"
    echo "    App Store Connect if a profile has to be fetched."
    ;;
  "$ASC_EXIT_AUTH")
    echo "❌  App Store Connect refused the API key (check ~/.appstoreconnect/)."
    [ "$NO_UPLOAD" -eq 1 ] || exit "$ASC_EXIT_AUTH"
    ;;
  *)
    echo "⚠️   Couldn't reach App Store Connect; going on (the upload will tell)."
    ;;
esac

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
echo "📦  Archiving $SCHEME (this takes ~3-5 min)..."
# The "resource fork, Finder information, or similar detritus" codesign
# failure is a race; a plain retry clears it.
archived=0
for attempt in 1 2 3; do
  rm -rf "$ARCHIVE_PATH"
  if xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "$DESTINATION" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    archive 2>&1 | tee "${LOG_DIR}/archive.log"; then
    archived=1
    break
  fi
  echo "⚠️   Archive attempt $attempt failed."
  # A refusal for want of an agreement won't clear on a retry.
  explain_if_agreement "${LOG_DIR}/archive.log"
done

if [ "$archived" -ne 1 ] || [ ! -d "$ARCHIVE_PATH" ]; then
  echo "❌  Archive failed — see Xcode output above (also ${LOG_DIR}/archive.log)."
  exit 4
fi
echo "✅  Archive at: $ARCHIVE_PATH"

# ---------------------------------------------------------------------------
# 4. Export .ipa
# ---------------------------------------------------------------------------
echo ""
echo "📤  Exporting .${ARTIFACT_EXT}..."
if ! xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" 2>&1 | tee "${LOG_DIR}/export.log"; then
  explain_if_agreement "${LOG_DIR}/export.log"
fi

IPA_PATH=$(find "$EXPORT_PATH" -name "*.${ARTIFACT_EXT}" 2>/dev/null | head -n 1)
if [ -z "$IPA_PATH" ]; then
  explain_if_agreement "${LOG_DIR}/export.log"
  echo "❌  Export failed — see output above (also ${LOG_DIR}/export.log)."
  exit 5
fi
echo "✅  .${ARTIFACT_EXT} at: $IPA_PATH"

if [ "$NO_UPLOAD" -eq 1 ]; then
  keep_bump
  echo ""
  echo "Stopping after export (--no-upload). To upload later, run:"
  echo "   xcrun altool --upload-app -f '$IPA_PATH' -t ${ALTOOL_TYPE} \\"
  echo "     --apiKey '$ASC_KEY_ID' --apiIssuer '$ASC_ISSUER_ID'"
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Upload to App Store Connect via altool — same API key
# ---------------------------------------------------------------------------
echo ""
echo "☁️   Uploading to App Store Connect..."
if ! xcrun altool --upload-app \
  --file "$IPA_PATH" \
  --type "$ALTOOL_TYPE" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "${LOG_DIR}/upload.log"; then
  explain_if_agreement "${LOG_DIR}/upload.log"
  echo "❌  Upload failed — see output above (also ${LOG_DIR}/upload.log)."
  exit 8
fi

# Uploaded: the bump stands.
keep_bump

MARKETING=$(grep -E '^    MARKETING_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(grep -E '^    CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([0-9]+)".*/\1/')
TAG="${TAG_PREFIX}/v${MARKETING}-${BUILD}"
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
   (the ${PLATFORM} builds: iOS and macOS are listed separately there)

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
