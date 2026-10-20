#!/usr/bin/env python3
"""Show what the iOS compiler sees differently between a base ref and the
working tree: the source-level half of "iOS is unchanged".

For every Swift file under ios/ that differs from <base-ref>, both versions
are reduced to the text an iOS build compiles: `#if` blocks whose condition
can be decided for iOS are resolved (os(macOS) false, os(iOS) true,
canImport(UIKit) true, canImport(AppKit) false, targetEnvironment(macCatalyst)
false); any other condition (DEBUG, compiler(...), swift(...)) keeps all its
branches. Comments and blank lines are dropped and runs of whitespace
collapsed. If the two reductions are equal, the change is invisible to iOS.

Reported:
  same      the file changed, but not for iOS (e.g. only #if os(macOS) code);
  CHANGED   iOS compiles different text: review it (a unified diff follows);
  NEW       a new file with iOS-visible code: new symbols. Nothing iOS already
            compiles can call them unless a CHANGED file does, but a new
            overload or extension member can capture an existing call: give
            new API a `night`/`Night` prefix and review these by hand;
  new/mac   a new file that iOS doesn't compile at all.
Exit status 1 if anything is CHANGED (NEW is reported, not failed).

Usage, from anywhere in the repo:
  ios/scripts/ios-source-diff.py [base-ref]      (default feat/mac-app-2026-10)
"""
import difflib
import re
import subprocess
import sys

KNOWN = {
    "os(macOS)": False, "os(iOS)": True, "os(visionOS)": False, "os(tvOS)": False, "os(watchOS)": False,
    "canImport(UIKit)": True, "canImport(AppKit)": False,
    "targetEnvironment(macCatalyst)": False,
}


def decide(cond):
    """True/False for iOS, or None when it depends on something else
    (three-valued: `DEBUG && os(macOS)` is False whatever DEBUG is)."""
    tokens = re.findall(r"&&|\|\||!|\(|\)|[A-Za-z_][A-Za-z0-9_]*(?:\([^()]*\))?", cond)
    pos = 0

    def peek():
        return tokens[pos] if pos < len(tokens) else None

    def take():
        nonlocal pos
        pos += 1
        return tokens[pos - 1]

    def primary():
        t = take()
        if t == "!":
            v = primary()
            return None if v is None else not v
        if t == "(":
            v = disjunction()
            take()  # ")"
            return v
        return KNOWN.get(t)  # unknown atom (DEBUG, compiler(>=6.2), …) -> None

    def conjunction():
        v = primary()
        while peek() == "&&":
            take()
            w = primary()
            v = False if (v is False or w is False) else (None if (v is None or w is None) else True)
        return v

    def disjunction():
        v = conjunction()
        while peek() == "||":
            take()
            w = conjunction()
            v = True if (v is True or w is True) else (None if (v is None or w is None) else False)
        return v

    try:
        return disjunction()
    except IndexError:
        return None


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        # Drop // comments outside string literals (roughly: after the last quote pair).
        code = re.sub(r'"(?:\\.|[^"\\])*"', lambda m: m.group(0).replace("//", "\x00"), line)
        code = code.split("//")[0].replace("\x00", "//")
        code = " ".join(code.split())
        if code:
            out.append(code)
    return out


def ios_view(text):
    lines = strip_comments(text)
    out = []
    # Each frame: [decided (True/False/None), this branch active, a branch taken already]
    stack = []

    def active():
        return all(f[1] for f in stack)

    for line in lines:
        m = re.match(r"#(if|elseif)\s+(.*)$", line)
        if m:
            value = decide(m.group(2))
            if m.group(1) == "if":
                if value is None:
                    stack.append([None, True, False])
                    out.append(line) if active() else None
                else:
                    stack.append([value, value, value])
            else:
                frame = stack[-1]
                if frame[0] is None or value is None:
                    frame[0], frame[1] = None, True
                    if active():
                        out.append(line)
                else:
                    frame[1] = value and not frame[2]
                    frame[2] = frame[2] or value
            continue
        if line == "#else":
            frame = stack[-1]
            if frame[0] is None:
                frame[1] = True
                if active():
                    out.append(line)
            else:
                frame[1] = not frame[2]
            continue
        if line == "#endif":
            frame = stack.pop()
            if frame[0] is None and active():
                out.append(line)
            continue
        if active():
            out.append(line)
    return out


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "feat/mac-app-2026-10"
    root = git("rev-parse", "--show-toplevel").strip()
    changed = git("-C", root, "diff", "--name-status", base, "--", "ios").splitlines()
    untracked = git("-C", root, "ls-files", "--others", "--exclude-standard", "--", "ios").splitlines()
    entries = [l.split("\t") for l in changed] + [["A", p] for p in untracked]
    bad = 0
    for entry in entries:
        status, path = entry[0], entry[-1]
        if not path.endswith(".swift"):
            continue
        if path.startswith("ios/MercuriusMac/"):
            print(f"mac-app  {path}")  # the Mac target's own sources: never in an iOS build
            continue
        head = open(f"{root}/{path}", encoding="utf-8").read() if not status.startswith("D") else ""
        try:
            old = git("-C", root, "show", f"{base}:{path}") if not status.startswith("A") else None
        except subprocess.CalledProcessError:
            old = None
        new_view = ios_view(head)
        if old is None:
            print(f"{'NEW     ' if new_view else 'new/mac '} {path}")
            continue
        old_view = ios_view(old)
        if old_view == new_view:
            print(f"same     {path}")
        else:
            bad += 1
            print(f"CHANGED  {path}")
            for d in difflib.unified_diff(old_view, new_view, "base (iOS)", "head (iOS)", lineterm="", n=1):
                print("    " + d)
    print(f"ios-source-diff against {base}: {bad} file(s) with iOS-visible changes")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
