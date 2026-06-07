#!/usr/bin/env bash
#
# screenshots.sh — capture App Store screenshots on the required device sizes.
#
# Runs the MercuriusUITests/AppStoreScreenshots UI test (seeded, no network) on
# an iPhone 6.9" + iPad 13" simulator, then exports the PNGs to
# build/screenshots/<device>/. Drag those into App Store Connect.
#
# Usage:
#   ./scripts/screenshots.sh           # both devices
#   ./scripts/screenshots.sh iphone    # iPhone only
#   ./scripts/screenshots.sh ipad      # iPad only
#
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IOS_DIR="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
cd "$IOS_DIR"

PROJECT="Mercurius.xcodeproj"
SCHEME="Mercurius"
TEST_ID="MercuriusUITests/AppStoreScreenshots"
OUT="${IOS_DIR}/build/screenshots"
FILTER="${1:-all}"

# Newest installed iOS simulator runtime id.
RUNTIME="$(xcrun simctl list runtimes 2>/dev/null | grep -i 'iOS' | tail -1 | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+')"
[ -n "$RUNTIME" ] || { echo "❌ No iOS simulator runtime installed."; exit 1; }
echo "Runtime: $RUNTIME"

# label | sim name | device-type id
DEVICES=(
  "iphone|Mercurius-Shots-iPhone|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
  "ipad|Mercurius-Shots-iPad|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-16GB"
)

echo "🔧  Regenerating project (pick up the screenshot test)…"
xcodegen generate >/dev/null

mkdir -p "$OUT"

for entry in "${DEVICES[@]}"; do
  IFS='|' read -r label simname devtype <<< "$entry"
  [ "$FILTER" = "all" ] || [ "$FILTER" = "$label" ] || continue

  echo ""
  echo "═══ $label ($simname) ═══"

  # Reuse the sim if it exists, else create it.
  udid="$(xcrun simctl list devices | grep -F " $simname (" | grep -oE '[0-9A-Fa-f-]{36}' | head -1 || true)"
  if [ -z "$udid" ]; then
    echo "  creating simulator…"
    udid="$(xcrun simctl create "$simname" "$devtype" "$RUNTIME")"
  fi
  echo "  udid: $udid"

  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  # Clean, marketing-friendly status bar.
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true

  result="${IOS_DIR}/build/shots-${label}.xcresult"
  rm -rf "$result"

  echo "  running UI test (this takes a few minutes)…"
  set +e
  # NOTE: do NOT pass CODE_SIGNING_ALLOWED=NO — the app needs its keychain
  # entitlement at runtime (SessionIdentity), which requires the simulator
  # build to be signed (Debug = Automatic signing). Without it the app shows
  # "Couldn't start — Could not create a session."
  xcodebuild test \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "id=$udid" \
    -only-testing:"$TEST_ID" \
    -resultBundlePath "$result" \
    -allowProvisioningUpdates \
    > "${IOS_DIR}/build/shots-${label}.log" 2>&1
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "  ⚠️  test exited $rc — see build/shots-${label}.log (still trying to export any captured shots)"
  fi

  destdir="${OUT}/${label}"
  rm -rf "$destdir"; mkdir -p "$destdir"
  xcrun xcresulttool export attachments --path "$result" --output-path "$destdir" >/dev/null 2>&1 || true

  # Rename exported files to the human-readable names from the manifest.
  python3 - "$destdir" <<'PY'
import json, os, re, sys
d = sys.argv[1]
mf = os.path.join(d, "manifest.json")
def walk(o):
    if isinstance(o, dict):
        if "exportedFileName" in o: yield o
        for v in o.values(): yield from walk(v)
    elif isinstance(o, list):
        for v in o: yield from walk(v)
n = 0
if os.path.exists(mf):
    for att in walk(json.load(open(mf))):
        name = att.get("suggestedHumanReadableName") or att.get("name") or ""
        # strip XCUITest's "_<index>_<uuid>" suffix + extension → clean "01-chat"
        name = re.sub(r"_[0-9]+_[0-9A-Fa-f-]{36}", "", name)
        name = re.sub(r"\.png$", "", name, flags=re.I)
        src = os.path.join(d, att["exportedFileName"])
        if name and os.path.exists(src):
            os.replace(src, os.path.join(d, name + ".png")); n += 1
print(f"  renamed {n} screenshot(s)")
PY

  echo "  → $destdir"
  for f in "$destdir"/*.png; do
    [ -e "$f" ] || { echo "    (no PNGs captured — check the log)"; break; }
    echo "    $(basename "$f")  $(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixel/{print $2}' | paste -sd'x' -)"
  done

  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
done

echo ""
echo "✅  Done. Screenshots in: $OUT"
echo "   iPhone slot wants 6.9\" (1320×2868); iPad wants 13\" (2064×2752)."
echo "   Drag them into App Store Connect → iOS App 1.0 → Previews and Screenshots."
