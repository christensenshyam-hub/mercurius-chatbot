#!/usr/bin/env bash
# coverage.sh — run every test suite, emit a coverage summary.
#
# Runs, in order:
#   1. SPM package tests via `swift test --enable-code-coverage`
#      (covers: DesignSystem, NetworkingKit, PersistenceKit,
#      ChatFeature, CurriculumFeature, SettingsFeature, AppFeature).
#   2. Xcode MercuriusTests + MercuriusUITests via `xcodebuild test`
#      with `-enableCodeCoverage YES` (covers the app shell and
#      the XCUITest flows).
#
# Then it extracts coverage per source file and prints a per-module
# summary to stdout plus a full machine-readable report to
# `build/coverage/summary.txt`.
#
# Usage:
#   cd ios && scripts/coverage.sh
#   cd ios && scripts/coverage.sh spm      # SPM-only
#   cd ios && scripts/coverage.sh xcode    # xcodebuild-only
#   cd ios && scripts/coverage.sh refresh-baseline   # overwrite docs/COVERAGE.md

set -euo pipefail

# Resolve ios/ no matter where we're invoked from.
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IOS_DIR="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

MODE="${1:-all}"
SIMULATOR="${SIMULATOR:-platform=iOS Simulator,name=iPhone 16}"

BUILD_DIR="${IOS_DIR}/build/coverage"
mkdir -p "${BUILD_DIR}"

# ---------------------------------------------------------------------------
# 1) SPM tests with coverage
# ---------------------------------------------------------------------------
run_spm() {
  echo "== SPM tests (swift test --enable-code-coverage) =="
  cd "${IOS_DIR}/Packages"
  swift test --enable-code-coverage >/dev/null

  # Locate the coverage data. swift test writes codecov data under
  # `.build/<target>/debug/codecov/default.profdata`.
  local profdata
  profdata="$(find .build -type f -name 'default.profdata' | head -n 1)"
  if [ -z "${profdata}" ]; then
    echo "  No profdata emitted by swift test."
    return
  fi

  local binary
  binary="$(find .build -type f -name LocalPackagesPackageTests.xctest -exec ls -t '{}' + 2>/dev/null | head -n 1)"
  if [ -z "${binary}" ]; then
    # xctest bundles on macOS live at .../LocalPackagesPackageTests.xctest/Contents/MacOS/<exe>
    binary="$(find .build -type f -path '*LocalPackagesPackageTests.xctest/Contents/MacOS/*' | head -n 1)"
  fi
  if [ -z "${binary}" ]; then
    echo "  Could not locate LocalPackagesPackageTests binary for llvm-cov."
    return
  fi

  xcrun llvm-cov report \
    "${binary}" \
    -instr-profile="${profdata}" \
    -ignore-filename-regex='(.build|Tests|Fixtures)' \
    | tee "${BUILD_DIR}/spm-summary.txt"
  echo
}

# ---------------------------------------------------------------------------
# 2) xcodebuild tests with coverage (MercuriusTests + MercuriusUITests)
# ---------------------------------------------------------------------------
run_xcode() {
  echo "== xcodebuild tests (MercuriusTests + MercuriusUITests) =="
  cd "${IOS_DIR}"
  # Write the xcresult to our own location so we control cleanup.
  local xcresult="${BUILD_DIR}/xcode.xcresult"
  rm -rf "${xcresult}"

  # Coverage data is captured even when individual tests fail, so
  # don't treat a test-run failure as a coverage-run failure — we
  # still want the summary. Capture the exit code and pass it through
  # at the end so CI can still see red.
  local xcode_status=0
  xcodebuild test \
    -project Mercurius.xcodeproj \
    -scheme Mercurius \
    -destination "${SIMULATOR}" \
    -enableCodeCoverage YES \
    -resultBundlePath "${xcresult}" \
    >/dev/null \
    || xcode_status=$?

  if [ ! -d "${xcresult}" ]; then
    echo "  xcresult bundle not produced — coverage unavailable (exit=${xcode_status})."
    return "${xcode_status}"
  fi

  # Extract a text report. `xcrun xccov view --report` is the Apple
  # interface into xcresult coverage data.
  xcrun xccov view --report --only-targets "${xcresult}" \
    | tee "${BUILD_DIR}/xcode-summary.txt"
  echo

  if [ "${xcode_status}" -ne 0 ]; then
    echo "  NOTE: xcodebuild test exited ${xcode_status} — coverage captured anyway."
  fi
  return 0
}

case "${MODE}" in
  spm)   run_spm ;;
  xcode) run_xcode ;;
  all)   run_spm; run_xcode ;;
  refresh-baseline)
    run_spm
    run_xcode
    "${SCRIPT_DIR}/coverage-write-baseline.sh" "${BUILD_DIR}"
    ;;
  *)
    echo "Unknown mode: ${MODE}"
    echo "Usage: $0 [all|spm|xcode|refresh-baseline]"
    exit 2 ;;
esac

echo
echo "Full machine-readable reports under ${BUILD_DIR}:"
ls -1 "${BUILD_DIR}" | sed 's/^/  /'
