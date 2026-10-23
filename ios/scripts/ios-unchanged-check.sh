#!/usr/bin/env bash
# Proves the iPhone app still renders as it did before the Mac's Night Studio
# work: runs the snapshot comparison suite with recording forced OFF and
# checks it against the committed baseline
# (docs/mac-night-studio/ios-snapshot-baseline.txt).
#
# The baseline holds, for each of the 23 ViewSnapshotTests, whether it passes
# against its reference image (11) or fails as an already-stale reference
# (12), and for each failing one the SHA-256 of its rendered pixels. A stale
# test's render is attached to the result bundle, so it can be compared
# exactly: the same hash means the iPhone draws that view pixel for pixel as
# the base branch did. A passing test is compared at the suite's own 98%
# precision only (its render isn't kept).
#
# Recording can't happen: TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never makes a
# missing reference fail instead of being written, and the script fails if
# anything under MercuriusTests/Snapshots changed.
#
# Usage, from ios/:
#   scripts/ios-unchanged-check.sh <out-dir>
#   WRITE_BASELINE=1 scripts/ios-unchanged-check.sh <out-dir>   # on the base branch only
# Environment: SIM (a simulator id; default "Audit 16PM", the iPhone 16 Pro Max
# on iOS 26.4 the references and the baseline were made on), DD (derived
# data; default /private/tmp/merc-mac-ns-dd).
set -uo pipefail

OUT=${1:?usage: ios-unchanged-check.sh <out-dir>}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
IOS=$(dirname "$HERE")
REPO=$(dirname "$IOS")
BASELINE="$REPO/docs/mac-night-studio/ios-snapshot-baseline.txt"
SIM=${SIM:-04DB5F67-DB97-4DCB-B8BC-C050A26AD10A}
DD=${DD:-/private/tmp/merc-mac-ns-dd}
RESULT="$OUT/snapshots.xcresult"

cd "$IOS" || exit 1
xcodegen generate >/dev/null || { echo "xcodegen failed" >&2; exit 1; }

for attempt in 1 2 3; do
  rm -rf "$RESULT"
  TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never xcodebuild test \
    -project Mercurius.xcodeproj -scheme Mercurius \
    -destination "platform=iOS Simulator,id=$SIM" \
    -derivedDataPath "$DD" \
    -only-testing:MercuriusTests/ViewSnapshotTests \
    -resultBundlePath "$RESULT" > "$OUT/xcodebuild.log" 2>&1
  grep -q "detritus not allowed" "$OUT/xcodebuild.log" || break
  echo "codesign xattr failure, retry $attempt" >&2
done

if ! grep -q "Executed 23 tests" "$OUT/xcodebuild.log"; then
  echo "the suite didn't run its 23 tests; see $OUT/xcodebuild.log" >&2
  grep -E "error:|BUILD FAILED" "$OUT/xcodebuild.log" | head -20 >&2
  exit 1
fi

rm -rf "$OUT/attachments" "$OUT/renders"
mkdir -p "$OUT/attachments" "$OUT/renders"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT/attachments" >/dev/null 2>&1

python3 - "$OUT" <<'EOF'
import hashlib, json, os, re, shutil, sys
from PIL import Image
out = sys.argv[1]
log = open(os.path.join(out, "xcodebuild.log"), encoding="utf-8", errors="replace").read()
status = {}
for name, result in re.findall(r"-\[MercuriusTests\.ViewSnapshotTests (test\w+)\]' (passed|failed)", log):
    status[name] = "pass" if result == "passed" else "fail"
renders = {}
manifest = os.path.join(out, "attachments", "manifest.json")
for test in json.load(open(manifest)) if os.path.exists(manifest) else []:
    name = re.search(r"/(test\w+)\(\)", test["testIdentifier"]).group(1)
    for a in test["attachments"]:
        if a["suggestedHumanReadableName"].startswith("failure_"):
            src = os.path.join(out, "attachments", a["exportedFileName"])
            dst = os.path.join(out, "renders", name + ".png")
            shutil.copyfile(src, dst)
            img = Image.open(dst).convert("RGBA")
            h = hashlib.sha256(img.tobytes()).hexdigest()
            renders[name] = f"{img.size[0]}x{img.size[1]}:{h}"
with open(os.path.join(out, "results.txt"), "w") as f:
    for name in sorted(status):
        line = f"{status[name]} {name}"
        if status[name] == "fail":
            line += " " + renders.get(name, "no-render")
        f.write(line + "\n")
EOF

cat "$OUT/results.txt"
echo "pass: $(grep -c '^pass ' "$OUT/results.txt"), fail: $(grep -c '^fail ' "$OUT/results.txt")"

FAILED=0
if [ -n "$(git -C "$IOS" status --porcelain -- MercuriusTests/Snapshots)" ]; then
  echo "PROBLEM: files under MercuriusTests/Snapshots changed (a recording?)" >&2
  git -C "$IOS" status --porcelain -- MercuriusTests/Snapshots >&2
  FAILED=1
fi

if [ "${WRITE_BASELINE:-0}" = "1" ]; then
  {
    echo "# ViewSnapshotTests on $(git -C "$REPO" rev-parse --short HEAD) ($(git -C "$REPO" rev-parse --abbrev-ref HEAD)),"
    echo "# simulator $SIM, recording off. fail = stale reference; the hash is the render's RGBA pixels."
    cat "$OUT/results.txt"
  } > "$BASELINE"
  echo "wrote $BASELINE"
elif [ -f "$BASELINE" ]; then
  if diff <(grep -v '^#' "$BASELINE") "$OUT/results.txt" > "$OUT/baseline.diff"; then
    echo "iOS unchanged: the same 23 results and the same pixels for every stale render as the baseline"
  else
    echo "PROBLEM: differs from the baseline:" >&2
    cat "$OUT/baseline.diff" >&2
    FAILED=1
  fi
else
  echo "no baseline at $BASELINE" >&2
  FAILED=1
fi
exit "$FAILED"
