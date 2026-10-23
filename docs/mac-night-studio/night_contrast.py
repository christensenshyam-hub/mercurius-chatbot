#!/usr/bin/env python3
"""WCAG 2.x contrast for the Mac's Night Studio tokens (SPEC.md section 1).

Run: python3 docs/mac-night-studio/night_contrast.py [--markdown]

Every text token is checked on every surface it can sit on, in light and
dark, at the standard contrast and under Increase Contrast. Translucent
fills are composited in sRGB over their base, the way AppKit draws them
(the same model as DesignSystem's BrandContrastTests). The canvas "light
pools" are checked at their peak alpha, so text sitting anywhere on the
canvas is covered. Non-text checks (focus ring, field and selection
strokes) use WCAG 1.4.11's 3:1.

This script is the reference for NightContrastTests: the Swift test must
hold the same pairs to the same minimums. Exit status 1 if any pair fails.
"""
import sys

TEXT_MIN = 4.5          # WCAG AA, normal text
TEXT_MIN_HC = 7.0       # what Increase Contrast holds the text tokens to
NONTEXT_MIN = 3.0       # WCAG 1.4.11, UI components and focus indicators
CHROME_TINT = 0.92      # surface over the material, floating chrome fallback

# ---------------------------------------------------------------------------
# Tokens. Hex RGB; (hex, alpha) for a translucent fill.
# ---------------------------------------------------------------------------
TOKENS = {
    "standard": {
        "light": {
            "canvasTop": 0xF6F5FC, "canvasBottom": 0xECEBF8,
            "surface": 0xFFFFFF, "surfaceRaised": 0xF2F1FB,
            "sidebar": 0xEEEDF7,
            "ink": 0x0E1230, "ink2": 0x434A6E, "ink3": 0x575F83,
            "accentText": 0x4F46E5, "successText": 0x166534, "errorText": 0xB91C1C,
            "accent": 0x6366F1, "violet": 0x8B5CF6, "lumen": 0x6366F1,
            "success": 0x16A34A, "error": 0xDC2626,
            "prominent": 0x4338CA, "prominentHover": 0x4F46E5,
            "fieldStroke": (0x4F46E5, 0.72), "hairline": (0x1B1F4B, 0.10),
            "poolAccent": 0.12, "poolViolet": 0.08,
            "hero": [0x4338CA, 0x5B32D6, 0x6D28D9], "heroLamp": 0.22, "heroSecondary": 0.92,
        },
        "dark": {
            "canvasTop": 0x0B0E2E, "canvasBottom": 0x05071A,
            "surface": 0x121641, "surfaceRaised": 0x1A1F52,
            "sidebar": 0x0A0D29,
            "ink": 0xF1F2FF, "ink2": 0xB7BDE2, "ink3": 0x959DCB,
            "accentText": 0xA5B4FC, "successText": 0x6EE7A8, "errorText": 0xFCA5A5,
            "accent": 0x6366F1, "violet": 0x8B5CF6, "lumen": 0x9EA4FF,
            "success": 0x34D399, "error": 0xF87171,
            "prominent": 0x4338CA, "prominentHover": 0x4F46E5,
            "fieldStroke": (0xA5B4FC, 0.62), "hairline": (0xFFFFFF, 0.12),
            "poolAccent": 0.24, "poolViolet": 0.16,
            "hero": [0x2B2486, 0x3B2A92, 0x4E2A8E], "heroLamp": 0.22, "heroSecondary": 0.92,
        },
    },
    # Increase Contrast (colorSchemeContrast == .increased; on the Mac the
    # high-contrast NSAppearance names). Surfaces flatten (no light pools,
    # no stars), secondary inks move toward ink, strokes become solid.
    "increased": {
        "light": {
            "canvasTop": 0xFAFAFE, "canvasBottom": 0xFAFAFE,
            "surface": 0xFFFFFF, "surfaceRaised": 0xF1F0FA,
            "sidebar": 0xF1F0FA,
            "ink": 0x05071A, "ink2": 0x2A3052, "ink3": 0x363D62,
            "accentText": 0x3730A3, "successText": 0x14532D, "errorText": 0x991B1B,
            "accent": 0x6366F1, "violet": 0x8B5CF6, "lumen": 0x4F46E5,
            "success": 0x15803D, "error": 0xB91C1C,
            "prominent": 0x3730A3, "prominentHover": 0x312E81,
            "fieldStroke": (0x3730A3, 1.0), "hairline": (0x1B1F4B, 0.55),
            "poolAccent": 0.0, "poolViolet": 0.0,
            "hero": [0x3730A3, 0x4C1D95, 0x5B21B6], "heroLamp": 0.0, "heroSecondary": 1.0,
        },
        "dark": {
            "canvasTop": 0x05071A, "canvasBottom": 0x05071A,
            "surface": 0x0E1238, "surfaceRaised": 0x161B4A,
            "sidebar": 0x05071A,
            "ink": 0xFFFFFF, "ink2": 0xDDE0F7, "ink3": 0xC3C8EA,
            "accentText": 0xC7D2FE, "successText": 0xA7F3D0, "errorText": 0xFECACA,
            "accent": 0x6366F1, "violet": 0x8B5CF6, "lumen": 0xC7D2FE,
            "success": 0x34D399, "error": 0xF87171,
            "prominent": 0x3730A3, "prominentHover": 0x312E81,
            "fieldStroke": (0xC7D2FE, 1.0), "hairline": (0xFFFFFF, 0.40),
            "poolAccent": 0.0, "poolViolet": 0.0,
            "hero": [0x1E1B4B, 0x2E1065, 0x3B0764], "heroLamp": 0.0, "heroSecondary": 1.0,
        },
    },
}

TEXT_TOKENS = ["ink", "ink2", "ink3", "accentText", "successText", "errorText"]
# Where Night text sits. "canvasPool" is the canvas under the indigo light
# pool at its peak (the darkest the light canvas gets, the brightest the
# dark one does); "canvasViolet" the same for the violet pool.
SURFACES = ["canvasTop", "canvasBottom", "canvasPool", "canvasViolet",
            "surface", "surfaceRaised", "sidebar"]


def rgb(h):
    return ((h >> 16) & 0xFF) / 255, ((h >> 8) & 0xFF) / 255, (h & 0xFF) / 255


def over(fg, alpha, bg):
    return tuple(f * alpha + b * (1 - alpha) for f, b in zip(fg, bg))


def lum(c):
    def lin(x):
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(x) for x in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    hi, lo = max(lum(a), lum(b)), min(lum(a), lum(b))
    return (hi + 0.05) / (lo + 0.05)


def resolve(t, name):
    """A surface as drawn: plain hex, or composited (pools, tints)."""
    if name == "canvasPool":
        return over(rgb(t["accent"]), t["poolAccent"], rgb(t["canvasTop"]))
    if name == "canvasViolet":
        return over(rgb(t["violet"]), t["poolViolet"], rgb(t["canvasBottom"]))
    return rgb(t[name])


def tinted_uses(t, scheme):
    """(name, text colour, background colour) for every tinted surface."""
    dark = scheme == "dark"
    surf = rgb(t["surface"])
    pool = resolve(t, "canvasPool")
    sel_a = 0.20 if dark else 0.10
    stu_a = 0.24 if dark else 0.11
    key_a = 0.16 if dark else 0.12
    chip_a = 0.16 if dark else 0.12
    sel = over(rgb(t["accent"]), sel_a, surf)
    ok = over(rgb(t["success"]), 0.14, surf)
    bad = over(rgb(t["error"]), 0.14, surf)
    student = over(rgb(t["accent"]), stu_a, pool)
    keywash = over(rgb(t["lumen"]), key_a, surf)
    chip = over(rgb(t["lumen"]), chip_a, surf)
    uses = [
        ("option text, selected row", rgb(t["ink"]), sel),
        ("option letter, selected row", rgb(t["accentText"]), sel),
        ("option text, correct row", rgb(t["ink"]), ok),
        ("correct mark, correct row", rgb(t["successText"]), ok),
        ("option text, wrong row", rgb(t["ink"]), bad),
        ("wrong mark, wrong row", rgb(t["errorText"]), bad),
        ("student turn text", rgb(t["ink"]), student),
        ("KEY idea text under the lumen wash", rgb(t["ink"]), keywash),
        ("KEY eyebrow under the lumen wash", rgb(t["accentText"]), keywash),
        ("token chip text", rgb(t["accentText"]), chip),
        ("caption (ink3) on the KEY wash", rgb(t["ink3"]), keywash),
    ]
    white = (1.0, 1.0, 1.0)
    lamp = rgb(0xB9B7FF)
    lamp_a = t["heroLamp"]
    sub_a = t["heroSecondary"]
    for i, stop in enumerate(t["hero"]):
        s = rgb(stop)
        lit = over(lamp, lamp_a, s)
        uses.append((f"white on hero stop {i + 1}", white, s))
        uses.append((f"white on hero stop {i + 1} under the lamp", white, lit))
        uses.append((f"hero secondary (white {int(sub_a * 100)}%) on stop {i + 1}", over(white, sub_a, s), s))
        uses.append((f"hero secondary on stop {i + 1} under the lamp", over(white, sub_a, lit), lit))
    # Floating chrome without glass (macOS 14-25, CI's Xcode 16.2): the
    # surface tint at CHROME_TINT over a material. Worst case: the material
    # is blurring a line of ink, so the tint sits over ink itself.
    chrome = over(rgb(t["surface"]), CHROME_TINT, rgb(t["ink"]))
    uses.append(("placeholder (ink3) on fallback chrome, worst case", rgb(t["ink3"]), chrome))
    uses.append(("accentText on fallback chrome, worst case", rgb(t["accentText"]), chrome))
    uses.append(("hero button label (prominent on white)", rgb(t["prominent"]), white))
    uses.append(("white on prominentHover", white, rgb(t["prominentHover"])))
    uses.append(("white on prominent", white, rgb(t["prominent"])))
    return uses


def nontext_uses(t, contrast):
    canvas = rgb(t["canvasTop"])
    pool = resolve(t, "canvasPool")
    surf = rgb(t["surface"])
    raised = rgb(t["surfaceRaised"])
    fs, fa = t["fieldStroke"]
    return [
        ("focus ring (accentText) on canvas", rgb(t["accentText"]), canvas),
        ("focus ring (accentText) on pool", rgb(t["accentText"]), pool),
        ("focus ring (accentText) on surface", rgb(t["accentText"]), surf),
        ("selected-row stroke (accentText) on raised", rgb(t["accentText"]), raised),
        ("field stroke on canvas", over(rgb(fs), fa, canvas), canvas),
        ("field stroke on pool", over(rgb(fs), fa, pool), pool),
        ("field stroke on surface", over(rgb(fs), fa, surf), surf),
    ] + ([
        # Under Increase Contrast every card edge is a solid hairline that
        # must itself read as a boundary.
        ("hairline on surface", over(rgb(t["hairline"][0]), t["hairline"][1], surf), surf),
        ("hairline on canvas", over(rgb(t["hairline"][0]), t["hairline"][1], canvas), canvas),
    ] if contrast == "increased" else [])


# The meaning sky (Lesson 1.1's interactive): night in both appearances, so
# one set of values per contrast setting. Words sit on the panel's top and
# bottom and under a neighbourhood's glow at its peak (NightSkyContrastTests).
SKY = {
    "standard": {"top": 0x0D1035, "bottom": 0x070923, "ink2": (0xFFFFFF, 0.74), "glow": 0.42,
                 "link": 0xC7CBFF},
    "increased": {"top": 0x05071A, "bottom": 0x05071A, "ink2": (0xDDE0F7, 1.0), "glow": 0.0,
                  "link": 0xFFFFFF},
}
SKY_BANK = [0x4338CA, 0x5B32D6]


def sky_checks(contrast):
    """(name, ratio, minimum) for every word and mark on the sky panel."""
    k = SKY[contrast]
    tmin = TEXT_MIN_HC if contrast == "increased" else TEXT_MIN
    top, bottom = rgb(k["top"]), rgb(k["bottom"])
    grounds = [("sky top", top), ("sky bottom", bottom),
               ("indigo glow", over(rgb(0x6366F1), k["glow"], top)),
               ("violet glow", over(rgb(0x8B5CF6), k["glow"], top))]
    white = (1.0, 1.0, 1.0)
    out = []
    for gname, g in grounds:
        out.append((f"skyInk on {gname}", ratio(white, g), tmin))
        out.append((f"skyInk2 on {gname}", ratio(over(rgb(k["ink2"][0]), k["ink2"][1], g), g), tmin))
        out.append((f"link on {gname}", ratio(rgb(k["link"]), g), NONTEXT_MIN))
    for stop in SKY_BANK:
        out.append((f"white on bank pill {stop:06X}", ratio(white, rgb(stop)), 7.0))
    return out


def main():
    md = "--markdown" in sys.argv
    failures = []
    for contrast in SKY:
        print(f"\n## the meaning sky / {contrast}")
        for name, r, minimum in sky_checks(contrast):
            bad = r < minimum
            if bad:
                failures.append(f"sky/{contrast}: {name} = {r:.2f}")
            print(f"    {name:48s} {r:5.2f}{' FAIL' if bad else ''}")
    for contrast, schemes in TOKENS.items():
        tmin = TEXT_MIN_HC if contrast == "increased" else TEXT_MIN
        for scheme, t in schemes.items():
            print(f"\n## {contrast} / {scheme}  (text minimum {tmin}:1)")
            if md:
                print("\n| text \\ surface | " + " | ".join(SURFACES) + " |")
                print("|---" * (len(SURFACES) + 1) + "|")
            for tok in TEXT_TOKENS:
                cells = []
                for s in SURFACES:
                    r = ratio(rgb(t[tok]), resolve(t, s))
                    bad = r < tmin
                    if bad:
                        failures.append(f"{contrast}/{scheme}: {tok} on {s} = {r:.2f}")
                    cells.append(f"{r:.2f}{' FAIL' if bad else ''}")
                if md:
                    print(f"| {tok} | " + " | ".join(cells) + " |")
                else:
                    print(f"  {tok:12s} " + "  ".join(f"{s}={c}" for s, c in zip(SURFACES, cells)))
            print("  tinted:")
            for name, fg, bg in tinted_uses(t, scheme):
                r = ratio(fg, bg)
                # Increase Contrast holds tinted text to the same AA floor;
                # the inks themselves are already at 7:1 on plain surfaces.
                bad = r < TEXT_MIN
                if bad:
                    failures.append(f"{contrast}/{scheme}: {name} = {r:.2f}")
                print(f"    {name:48s} {r:5.2f}{' FAIL' if bad else ''}")
            print("  non-text (3:1):")
            for name, fg, bg in nontext_uses(t, contrast):
                r = ratio(fg, bg)
                bad = r < NONTEXT_MIN
                if bad:
                    failures.append(f"{contrast}/{scheme}: {name} = {r:.2f}")
                print(f"    {name:48s} {r:5.2f}{' FAIL' if bad else ''}")
    print()
    if failures:
        print("FAILURES:")
        for f in failures:
            print("  " + f)
        sys.exit(1)
    print("All pairs pass.")


if __name__ == "__main__":
    main()
