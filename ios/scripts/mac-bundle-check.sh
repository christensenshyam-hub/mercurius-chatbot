#!/usr/bin/env bash
# Checks a built Mercurius.app (the native Mac app) for what the Mac App
# Store and the universal purchase need, reading the bundle itself — the
# Info.plist as built, not project.yml.
#
# Usage:
#   scripts/mac-bundle-check.sh <Mercurius.app> debug|release
#
#   - bundle id: com.mayoailiteracy.mercurius.native in Release (the iOS
#     app's, for the universal purchase), ….macdev in Debug
#   - version and build number filled in (no $(…) left), and the same as the
#     iOS app's in project.yml
#   - LSMinimumSystemVersion 14.0, category Education, no non-exempt
#     encryption, HTTPS only, the mercurius:// scheme
#   - the app icon compiled in (CFBundleIconName MacAppIcon + AppIcon.icns)
#   - the privacy manifest in Contents/Resources
#   - release: arm64 and x86_64 both in the executable (the Mac App Store
#     sells to Intel Macs that run macOS 14 too)
#   - when the app is signed: the sandbox entitlement (an unsigned CI build
#     has no entitlements to read, and says so)
#
# Exits non-zero on the first failed check, after printing every result.
set -euo pipefail

APP=${1:?usage: mac-bundle-check.sh <Mercurius.app> debug|release}
CONFIG=${2:?usage: mac-bundle-check.sh <Mercurius.app> debug|release}
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_YML="${SCRIPT_DIR}/../project.yml"
INFO="$APP/Contents/Info.plist"
[ -f "$INFO" ] || { echo "no Info.plist at $INFO" >&2; exit 1; }

failed=0
check() {
  local what=$1 got=$2 want=$3
  if [ "$got" = "$want" ]; then
    echo "ok    $what: $got"
  else
    echo "FAIL  $what: got '$got', want '$want'" >&2
    failed=1
  fi
}
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null || echo "<missing>"; }

case "$CONFIG" in
  release) check "bundle id" "$(value CFBundleIdentifier)" "com.mayoailiteracy.mercurius.native" ;;
  debug)   check "bundle id" "$(value CFBundleIdentifier)" "com.mayoailiteracy.mercurius.native.macdev" ;;
  *) echo "config must be debug or release" >&2; exit 2 ;;
esac

marketing=$(grep -E '^    MARKETING_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([^"]+)".*/\1/')
build=$(grep -E '^    CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([^"]+)".*/\1/')
check "version (as iOS)" "$(value CFBundleShortVersionString)" "$marketing"
check "build (as iOS)" "$(value CFBundleVersion)" "$build"
check "minimum macOS" "$(value LSMinimumSystemVersion)" "14.0"
check "category" "$(value LSApplicationCategoryType)" "public.app-category.education"
check "non-exempt encryption" "$(value ITSAppUsesNonExemptEncryption)" "false"
check "arbitrary loads" "$(value NSAppTransportSecurity:NSAllowsArbitraryLoads)" "false"
check "URL scheme" "$(value CFBundleURLTypes:0:CFBundleURLSchemes:0)" "mercurius"
check "icon name" "$(value CFBundleIconName)" "MacAppIcon"
check "icon file" "$([ -f "$APP/Contents/Resources/$(value CFBundleIconFile).icns" ] && echo present || echo missing)" "present"
check "privacy manifest" "$([ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ] && echo present || echo missing)" "present"

EXE="$APP/Contents/MacOS/$(value CFBundleExecutable)"
archs=$(lipo -archs "$EXE" 2>/dev/null || echo "?")
echo "info  architectures: $archs"
if [ "$CONFIG" = release ]; then
  check "arm64 + x86_64" "$(for a in arm64 x86_64; do [[ " $archs " == *" $a "* ]] && printf '%s ' "$a"; done)" "arm64 x86_64 "
fi

if entitlements=$(codesign -d --entitlements :- "$APP" 2>/dev/null) && [ -n "$entitlements" ]; then
  sandbox=$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" /dev/stdin <<<"$entitlements" 2>/dev/null || echo "<missing>")
  check "sandbox entitlement" "$sandbox" "true"
else
  echo "info  no entitlements to read (unsigned build); the sandbox is checked in project.yml by swift test"
fi

exit "$failed"
