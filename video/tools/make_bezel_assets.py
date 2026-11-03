#!/usr/bin/env python3
"""Copy Apple's official iPhone 18 Pro Max bezel into the composition and derive the screen mask.

The bezel (Apple Design Resources, Bezel-iPhone-18.dmg, https://developer.apple.com/design/resources/) is used as is,
unmodified. Its screen opening is exactly 1320x2868 at (75, 66), the iPhone 18 Pro Max simulator capture size. The
mask is the transparent screen region, flood-filled from the centre, so the footage follows the real corner shape and
nothing shows outside the device. Neither file is committed (Apple licence; see licenses.md).

Usage: python3 video/tools/make_bezel_assets.py "<path to iPhone 18 Pro Max - Glacier - Portrait.png>"
"""
import os
import shutil
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "video", "app-preview-2026-11-04", "composition", "assets", "brand")
SCREEN = (75, 66, 1320, 2868)  # x, y, w, h of the opening, measured on the bezel's alpha channel


def main(src):
    os.makedirs(OUT, exist_ok=True)
    shutil.copyfile(src, os.path.join(OUT, "bezel.png"))
    alpha = Image.open(src).getchannel("A")
    # Treat anti-aliased edge pixels (< 250) as screen so footage runs under the bezel's soft inner edge.
    region = alpha.point(lambda a: 255 if a < 250 else 0)
    w, h = region.size
    ImageDraw.floodfill(region, (w // 2, h // 2), 128)
    mask = region.point(lambda v: 255 if v == 128 else 0)
    x, y, sw, sh = SCREEN
    crop = mask.crop((x, y, x + sw, y + sh))
    rgba = Image.new("RGBA", crop.size, (255, 255, 255, 0))
    rgba.putalpha(crop)
    rgba.save(os.path.join(OUT, "screen-mask.png"), optimize=True)
    filled = sum(1 for v in crop.getdata() if v)
    print(f"bezel {Image.open(src).size}, mask {crop.size}, {filled / (sw * sh):.4f} of the opening is screen")


if __name__ == "__main__":
    main(sys.argv[1])
