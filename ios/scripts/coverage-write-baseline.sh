#!/usr/bin/env bash
# coverage-write-baseline.sh — rewrite docs/COVERAGE.md from the outputs
# of coverage.sh.
#
# Invoked by `coverage.sh refresh-baseline` and expects the SPM / Xcode
# summary files to already be in `${BUILD_DIR}`. Pulls the high-level
# total lines out of each and updates the markdown table.
#
# Manual use:
#   cd ios && scripts/coverage.sh refresh-baseline

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IOS_DIR="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
BUILD_DIR="${1:-${IOS_DIR}/build/coverage}"
OUT="${IOS_DIR}/docs/COVERAGE.md"
mkdir -p "${IOS_DIR}/docs"

SPM_SUMMARY="${BUILD_DIR}/spm-summary.txt"
XCODE_SUMMARY="${BUILD_DIR}/xcode-summary.txt"

# Pull the "TOTAL" line from llvm-cov output. Its columns are:
#   TOTAL  <regions> <miss> <pct>  <funcs> <miss> <pct>  <lines> <miss> <pct>  <branches>...
# Line coverage is the most intuitive "how much code did tests touch"
# number, so report that — 3rd percentage column (index 10 counting TOTAL).
spm_lines_pct=""
if [ -f "${SPM_SUMMARY}" ]; then
  spm_lines_pct="$(grep -E '^TOTAL' "${SPM_SUMMARY}" | tail -n 1 | awk '{
    # Collect every field that looks like a percentage (ends with %)
    i = 0
    for (f = 1; f <= NF; f++) if ($f ~ /%$/) { i++; pct[i] = $f }
    # Third percentage is line coverage (regions, funcs, LINES, branches).
    if (i >= 3) print pct[3]
  }')"
fi

# xccov output reports target-level coverage as, e.g.:
#   0  Mercurius.app  1   100.00% (13/13)
# Grab the first percentage on the Mercurius.app line.
xcode_app_pct=""
if [ -f "${XCODE_SUMMARY}" ]; then
  xcode_app_pct="$(grep 'Mercurius\.app' "${XCODE_SUMMARY}" | head -n 1 | grep -oE '[0-9]+\.[0-9]+%' | head -n 1 || true)"
fi

{
  echo "# Coverage baseline"
  echo
  echo "_Last refreshed: $(date -u '+%Y-%m-%d %H:%M:%SZ')_"
  echo
  echo "Regenerate with:"
  echo
  echo '```'
  echo 'cd ios && scripts/coverage.sh refresh-baseline'
  echo '```'
  echo
  echo "## Totals"
  echo
  echo "| Surface | Line coverage |"
  echo "|---|---|"
  echo "| SPM packages (\`swift test\`) | ${spm_lines_pct:-n/a} |"
  echo "| Xcode app target (\`xcodebuild test\`) | ${xcode_app_pct:-n/a} |"
  echo
  echo "## Per-framework (xcodebuild)"
  echo
  echo "Covers everything linked into the test-run process, including the"
  echo "SPM packages that the app embeds. Third-party packages (e.g."
  echo "\`SnapshotTesting\`) appear with low coverage because we exercise"
  echo "our own code through them, not their internals."
  echo
  echo '```'
  if [ -f "${XCODE_SUMMARY}" ]; then
    cat "${XCODE_SUMMARY}"
  else
    echo "(no xcode-summary.txt)"
  fi
  echo '```'
  echo
  echo "## Files"
  echo
  echo "- Full per-file SPM report: \`build/coverage/spm-summary.txt\`"
  echo "- Full per-framework xcodebuild report: \`build/coverage/xcode-summary.txt\`"
  echo "- Raw xcresult bundle: \`build/coverage/xcode.xcresult\` (open in Xcode for the interactive viewer)"
  echo
  echo "## Scope notes"
  echo
  echo "- SPM coverage ignores \`.build/\`, \`Tests/\`, and \`Fixtures/\` dirs."
  echo "- SPM-only tests run with \`swift test\` on macOS. The xcodebuild"
  echo "  run exercises the same modules from the iOS simulator, so"
  echo "  numbers differ by pathway rather than being strictly additive."
  echo "- Views that are only rendered through SwiftUI surface (most"
  echo "  \`*View.swift\` files) score 0% on the SPM side because SPM"
  echo "  tests don't boot a SwiftUI runtime. They're covered by the"
  echo "  xcodebuild snapshot + UI test run instead."
} > "${OUT}"

echo "Wrote ${OUT}"
