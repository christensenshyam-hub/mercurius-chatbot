#!/usr/bin/env python3
"""Catch Swift that compiles locally (Xcode 26, Swift 6.3) but not on CI
(Xcode 16.2, Swift 6.0.3, the macOS 15 / iOS 18 SDKs).

Two checks a newer local compiler can't make for us:

1. A trailing comma in an argument or parameter list, `f(a, b,)` (Swift 6.1+
   syntax). Array and dictionary literals may keep theirs.
2. An iOS 26 / macOS 26 symbol (Liquid Glass and its relatives) outside a
   `#if compiler(>=6.2)` block. Swift 6.0.3 doesn't skip unknown symbols
   behind `if #available`, only behind `#if compiler(...)`, which it never
   parses. The `#else` of such a block counts as outside.

Not checked (no reliable grep): mixing Double and CGFloat in `sin`/`cos`
and other overloaded maths, which Swift 6.0 rejects as ambiguous (a1754ef).
Keep each trig argument the same type as what it multiplies.

Usage: scripts/ci-compat-lint.py [paths ...]   (default: Packages, MercuriusMac,
Mercurius, MercuriusWidgets under ios/). Exits 1 on any finding.
"""
import os
import re
import sys

GLASS = re.compile(
    r"\b(glassEffect|GlassEffectContainer|glassEffectID|glassEffectUnion|"
    r"glassEffectTransition|Glass\.(regular|clear|identity)|safeAreaBar|"
    r"backgroundExtensionEffect|scrollEdgeEffectStyle|\.glassProminent|"
    r"buttonStyle\(\.glass)\b"
)
COMPILER_IF = re.compile(r"^\s*#if\s+compiler\(\s*>=\s*6\.([2-9]|\d\d)")


def strip(line):
    """The line without its // comment and string literals (roughly)."""
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    return re.sub(r"//.*$", "", line)


def lint(path):
    findings = []
    lines = open(path, encoding="utf-8").read().split("\n")
    # A stack of #if frames: is this frame a compiler(>=6.2) guard, and are we
    # in its #else?
    stack = []
    for i, raw in enumerate(lines):
        code = strip(raw)
        s = code.strip()
        if s.startswith("#if"):
            stack.append([bool(COMPILER_IF.match(code)), False])
        elif s.startswith("#elseif") or s.startswith("#else"):
            if stack:
                stack[-1][1] = True
        elif s.startswith("#endif"):
            if stack:
                stack.pop()
        guarded = any(is_guard and not in_else for is_guard, in_else in stack)
        if GLASS.search(code) and not guarded and not s.startswith("#"):
            findings.append((i + 1, "macOS/iOS 26 symbol outside #if compiler(>=6.2)", raw.strip()))
        if re.search(r",\s*\)", code):
            findings.append((i + 1, "trailing comma in an argument list", raw.strip()))
        if code.rstrip().endswith(",") and i + 1 < len(lines) and strip(lines[i + 1]).strip().startswith(")"):
            findings.append((i + 1, "trailing comma before a closing parenthesis", raw.strip()))
    return findings


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    ios = os.path.dirname(here)
    roots = argv or [os.path.join(ios, p) for p in ("Packages", "MercuriusMac", "Mercurius", "MercuriusWidgets")]
    total = 0
    for root in roots:
        paths = [root] if root.endswith(".swift") else [
            os.path.join(d, f)
            for d, _, files in os.walk(root)
            if "/.build" not in d
            for f in files if f.endswith(".swift")
        ]
        for path in sorted(paths):
            for line, what, text in lint(path):
                print(f"{path}:{line}: {what}: {text}")
                total += 1
    print(f"ci-compat-lint: {total} finding(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
