#!/usr/bin/env bash
# Type-checks NightCIProbe.swift the ways the app's code is compiled:
# macOS 14 (arm64, x86_64 — the Mac App Store build is universal) and the
# iOS 17 simulator, each with the glass path and with the forced material
# fallback, in Swift 5 language mode with complete concurrency checking (the
# app targets' settings). Then two negative checks: glass outside
# `#available` must be rejected for a macOS 14 target, and a Swift 6.1+
# trailing comma in an argument list is NOT rejected by this compiler, which
# is why ../ARCHITECTURE.md §5 keeps a grep for it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PROBE="$HERE/NightCIProbe.swift"
MAC_SDK=$(xcrun --sdk macosx --show-sdk-path)
SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
TMP=$(mktemp -d)
FAIL=0

check() {
  local label=$1; shift
  if xcrun swiftc -typecheck -swift-version 5 -strict-concurrency=complete "$@" "$PROBE" 2>"$TMP/err"; then
    echo "ok    $label"
  else
    echo "FAIL  $label"; sed 's/^/      /' "$TMP/err"; FAIL=1
  fi
}

echo "compiler: $(xcrun swiftc --version 2>&1 | head -1)"
check "macOS 14 arm64, glass path"          -target arm64-apple-macos14.0  -sdk "$MAC_SDK"
check "macOS 14 arm64, material fallback"   -target arm64-apple-macos14.0  -sdk "$MAC_SDK" -D NIGHT_FORCE_MATERIAL
check "macOS 14 x86_64, glass path"         -target x86_64-apple-macos14.0 -sdk "$MAC_SDK"
check "macOS 14 arm64, DEBUG"               -target arm64-apple-macos14.0  -sdk "$MAC_SDK" -D DEBUG
check "iOS 17 simulator, glass path"        -target arm64-apple-ios17.0-simulator -sdk "$SIM_SDK"
check "iOS 17 simulator, material fallback" -target arm64-apple-ios17.0-simulator -sdk "$SIM_SDK" -D NIGHT_FORCE_MATERIAL

# Negative 1: an unguarded glassEffect must not compile for macOS 14.
cat > "$TMP/Unguarded.swift" <<'EOF'
import SwiftUI
struct Unguarded: View {
    var body: some View { Text("x").glassEffect(.regular, in: Capsule()) }
}
EOF
if xcrun swiftc -typecheck -target arm64-apple-macos14.0 -sdk "$MAC_SDK" "$TMP/Unguarded.swift" 2>"$TMP/err"; then
  echo "FAIL  an unguarded glassEffect compiled for macOS 14"; FAIL=1
else
  echo "ok    unguarded glassEffect rejected: $(grep -m1 'error:' "$TMP/err" | sed 's/.*error: //')"
fi

# Negative 2: a trailing comma in an argument list (Swift 6.1+). This
# compiler accepts it, so only a grep (or CI's Swift 6.0.3) catches it.
cat > "$TMP/Trailing.swift" <<'EOF'
func pair(_ a: Int, _ b: Int) -> Int { a + b }
let x = pair(1, 2,)
EOF
if xcrun swiftc -typecheck "$TMP/Trailing.swift" 2>/dev/null; then
  echo "note  a trailing comma in an argument list compiles here (Swift 6.1+); CI's 6.0.3 rejects it — grep for it"
else
  echo "note  this compiler rejects argument-list trailing commas"
fi

# The mechanism that protects CI: a compiler skips (doesn't even parse) the
# body of a `#if compiler(>=N)` it is older than. Shown with a version no
# compiler has yet, around text that isn't Swift at all.
cat > "$TMP/Skipped.swift" <<'EOF'
#if compiler(>=99.0)
this is not Swift ⟨ glassEffect(.future) ⟩ and is never parsed
#else
let fallback = 1
#endif
EOF
if xcrun swiftc -typecheck "$TMP/Skipped.swift" 2>"$TMP/err"; then
  echo "ok    a #if compiler(>=99) body is skipped unparsed (as 6.0.3 skips >=6.2)"
else
  echo "FAIL  the compiler parsed an inactive #if compiler block"; sed 's/^/      /' "$TMP/err"; FAIL=1
fi

rm -rf "$TMP"
exit "$FAIL"
