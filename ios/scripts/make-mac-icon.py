#!/usr/bin/env python3
"""Build the macOS app icon set from the iOS 1024 px icon.

macOS icons are not full-bleed squares: the artwork sits on an 824 px
rounded-rectangle plate centred in a 1024 px transparent canvas, with a soft
drop shadow (Apple's macOS icon grid). The iOS icon is the plate's content,
unchanged, so both platforms show the same artwork.

Usage (from ios/):
    python3 scripts/make-mac-icon.py \
        Mercurius/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png \
        MercuriusMac/Resources/MacAssets.xcassets/MacAppIcon.appiconset

Re-run it whenever the iOS icon changes. Needs Pillow.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

CANVAS = 1024
PLATE = 824                 # Apple's macOS grid: 824 px plate in 1024 px
RADIUS = 185                # corner radius of the plate at 1024 px
SHADOW_OFFSET_Y = 12
SHADOW_BLUR = 18
SHADOW_ALPHA = 90           # out of 255

# (point size, scale) pairs a macOS app icon set needs.
SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
         (256, 1), (256, 2), (512, 1), (512, 2)]


def rounded_mask(size, radius):
    # Supersample the mask so the corners are smooth.
    factor = 4
    big = Image.new("L", (size * factor, size * factor), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, size * factor - 1, size * factor - 1), radius=radius * factor, fill=255)
    return big.resize((size, size), Image.LANCZOS)


def build_master(source_path):
    art = Image.open(source_path).convert("RGBA").resize((PLATE, PLATE), Image.LANCZOS)
    mask = rounded_mask(PLATE, RADIUS)
    plate = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    plate.paste(art, (0, 0), mask)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    origin = (CANVAS - PLATE) // 2

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_mask = Image.new("L", (CANVAS, CANVAS), 0)
    shadow_mask.paste(mask, (origin, origin + SHADOW_OFFSET_Y))
    shadow.putalpha(shadow_mask.point(lambda v: v * SHADOW_ALPHA // 255))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))

    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(plate, (origin, origin))
    return canvas


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    master = build_master(source)

    images = []
    for points, scale in SIZES:
        pixels = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        master.resize((pixels, pixels), Image.LANCZOS).save(os.path.join(out_dir, name))
        images.append({
            "filename": name,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{points}x{points}",
        })

    with open(os.path.join(out_dir, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
