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
  echo "## Two pathways, one codebase"
  echo
  echo "Every file is potentially exercised by two independent test"
  echo "pipelines — read the numbers as MAX(SPM, xcodebuild), not as"
  echo "either one alone:"
  echo
  echo "- **SPM** (\`swift test\` on macOS) covers view models, networking,"
  echo "  persistence, parsers — anything that doesn't need a SwiftUI"
  echo "  runtime. Reports per-file % with line coverage."
  echo "- **xcodebuild** on iOS Simulator covers views through"
  echo "  snapshot + XCUITest. Reports per-framework % aggregated across"
  echo "  all files in each package product."
  echo
  echo "Known rows to ignore:"
  echo
  echo "- \`NetworkingKit  0  0.00% (0/0)\` in the xcodebuild table is the"
  echo "  empty \`*_PackageProduct\` wrapper, not the module. NetworkingKit"
  echo "  is thoroughly covered by the SPM pathway — see spm-summary.txt."
  echo "- \`SnapshotTesting\` low coverage is expected — we ship our code"
  echo "  through that library, we don't test its internals."
  echo
  echo "## Per-framework (xcodebuild)"
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
} > "${OUT}"

echo "Wrote ${OUT}"
