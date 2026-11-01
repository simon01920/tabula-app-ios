#!/usr/bin/env python3
"""Generate the Tabula app icon from one geometry, with the Python stdlib only (zlib + struct + math).

Concept: a "T" for Tabula drawn as a day's timetable column. The bar on top is the highlighter "Now"
stroke (the app's signature element, UX_OVERHAUL_PLAN D1); the three tiles below are the day's lessons,
fading into the future. Colours are the Exercise-book tokens (TimetableUI DesignTokens.swift):
ink #2541B2 / ink-dark #8EA2FF background and tiles, highlighter #FFE04A.

Outputs (run from anywhere: python3 scripts/make-app-icon.py):
  Resources/AppIcon.icon/Assets/*.svg   Icon Composer layers (Xcode 26 path: Liquid Glass, dark/clear/tinted)
  Resources/AppIcon.png                 flattened light icon with baked depth (shadows, glass rims), opaque RGB
                                        (xtool iconPath; App Store: no alpha)
  Resources/Assets.xcassets/AppIcon.appiconset/AppIcon{,-dark,-tinted}.png   asset-catalog fallback
Resources/AppIcon.icon/icon.json (fills, glass, shadows) is hand-maintained and names the layer files below.
"""
import math
import pathlib
import struct
import zlib

SIZE = 1024
TILE_R, BAR_R = 32, 32
TILES = [(394, 402, 236, 118), (394, 550, 236, 118), (394, 698, 236, 118)]  # x, y, w, h
BAR = [(256, 234), (812, 234), (784, 340), (228, 340)]  # chisel-cut stroke, clockwise; grown by BAR_R
BAR_TILT, BAR_PIVOT = -3.0, (512, 284)                    # degrees, as SVG rotate(): negative = counter-clockwise

LAYER_TILE, LAYER_BAR, LAYER_FADE = "#F4F6FF", "#FFE04A", (1, 0.66, 0.36)  # .icon layers: flat, system lights them

# Flattened PNGs get no system Liquid Glass, so they carry their own depth: the T floats above the background.
APPEARANCES = {  # background, tile and bar top/bottom gradients, shadow colour, tile opacities (now -> later)
    "": dict(bg=("#3D60E3", "#1F3699"), tile=("#FFFFFF", "#D9E1FB"), bar=("#FFEC80", "#F6C92A"),
             shadow="#0A1448", fade=LAYER_FADE),
    "-dark": dict(bg=("#1C2A66", "#0A0F2B"), tile=("#A6B5FF", "#7B8FF2"), bar=("#FFEC80", "#F2C42A"),
                  shadow="#000000", fade=(1, 0.62, 0.32)),
    "-tinted": dict(bg=("#000000", "#000000"), tile=("#FFFFFF", "#D6D6D6"), bar=("#FFFFFF", "#E4E4E4"),
                    shadow="#000000", fade=(0.62, 0.42, 0.24)),
}
SHADOWS = ((26, 40, 0.55), (7, 9, 0.35))  # y offset, blur, opacity (px at 1024): ambient + contact shadow
RIM, LIGHT = 8.0, (-0.34, -0.94)          # lit-rim width; light direction (from above, slightly left)


def rgb(hex_colour: str) -> tuple:
    return tuple(int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))


def rotate(x: float, y: float, degrees: float) -> tuple:
    a, (cx, cy) = math.radians(degrees), BAR_PIVOT
    return (cx + (x - cx) * math.cos(a) - (y - cy) * math.sin(a),
            cy + (x - cx) * math.sin(a) + (y - cy) * math.cos(a))


BAR_PTS = [rotate(x, y, BAR_TILT) for x, y in BAR]


# --- vector layers ----------------------------------------------------------------------------------------

def svg(body: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
            f'viewBox="0 0 {SIZE} {SIZE}">\n  {body}\n</svg>\n')


def bar_path() -> str:
    """The bar polygon grown by BAR_R, outlined (no strokes) so Icon Composer gets clean filled edges."""
    out, n = [], len(BAR_PTS)
    for i in range(n):
        (ax, ay), (bx, by) = BAR_PTS[i], BAR_PTS[(i + 1) % n]
        length = math.hypot(bx - ax, by - ay)
        nx, ny = (by - ay) / length * BAR_R, -(bx - ax) / length * BAR_R  # outward normal (clockwise, y down)
        out.append(("L" if out else "M") + f"{ax + nx:.2f} {ay + ny:.2f} L{bx + nx:.2f} {by + ny:.2f}")
        (cx, cy), (dx, dy) = BAR_PTS[(i + 1) % n], BAR_PTS[(i + 2) % n]
        length = math.hypot(dx - cx, dy - cy)
        mx, my = (dy - cy) / length * BAR_R, -(dx - cx) / length * BAR_R
        out.append(f"A{BAR_R} {BAR_R} 0 0 1 {cx + mx:.2f} {cy + my:.2f}")
    return " ".join(out) + " Z"


def layers() -> dict:
    files = {"highlighter.svg": svg(f'<path d="{bar_path()}" fill="{LAYER_BAR}"/>')}
    for i, ((x, y, w, h), opacity) in enumerate(zip(TILES, LAYER_FADE), start=1):
        files[f"lesson-{i}.svg"] = svg(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{TILE_R}" '
                                       f'fill="{LAYER_TILE}" fill-opacity="{opacity}"/>')
    return files


# --- flattened PNGs (signed distance fields, 1 px anti-aliasing) ------------------------------------------

def rect_sdf(px: float, py: float, x: int, y: int, w: int, h: int) -> float:
    qx = abs(px - (x + w / 2)) - (w / 2 - TILE_R)
    qy = abs(py - (y + h / 2)) - (h / 2 - TILE_R)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - TILE_R


def bar_sdf(px: float, py: float) -> float:
    best, inside, n = float("inf"), False, len(BAR_PTS)
    for i in range(n):
        (ax, ay), (bx, by) = BAR_PTS[i], BAR_PTS[i - 1]
        ex, ey, wx, wy = bx - ax, by - ay, px - ax, py - ay
        t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
        best = min(best, (wx - ex * t) ** 2 + (wy - ey * t) ** 2)
        if (ay > py) != (by > py) and px < ax + (py - ay) * ex / ey:
            inside = not inside
    return (-1 if inside else 1) * math.sqrt(best) - BAR_R


def clamp(v: float) -> float:
    return max(0.0, min(1.0, v))


def mix(c0: tuple, c1: tuple, t: float) -> tuple:
    return tuple(a + (b - a) * t for a, b in zip(c0, c1))


def blend(img: bytearray, x: int, y: int, colour: tuple, a: float) -> None:
    i = (y * SIZE + x) * 3
    img[i:i + 3] = bytes(round(img[i + k] + (colour[k] - img[i + k]) * a) for k in range(3))


def pixels(box: tuple):
    x0, y0, x1, y1 = (max(0, min(SIZE, int(v))) for v in box)
    return ((x, y) for y in range(y0, y1) for x in range(x0, x1))


def shadows(img: bytearray, shapes: list, look: dict) -> None:
    """Soft drop shadows of the whole T as one silhouette (max per pixel, so overlaps don't double-darken)."""
    for dy, blur, strength in SHADOWS:
        alpha = {}
        for sdf, box, _, opacity in shapes:
            for x, y in pixels((box[0] - blur, box[1] - blur + dy, box[2] + blur, box[3] + blur + dy)):
                s = clamp((blur - sdf(x + 0.5, y + 0.5 - dy)) / (2 * blur))
                if s:
                    alpha[x, y] = max(alpha.get((x, y), 0.0), strength * opacity * s * s * (3 - 2 * s))
        for (x, y), a in alpha.items():
            blend(img, x, y, rgb(look["shadow"]), a)


def body(img: bytearray, sdf, box: tuple, look: dict, part: str, opacity: float) -> None:
    """One glass shape: a top-lit gradient, a bright top rim and a darker bottom rim."""
    shadow, (top, bottom) = rgb(look["shadow"]), (rgb(c) for c in look[part])
    for x, y in pixels(box):
        px, py = x + 0.5, y + 0.5
        d = sdf(px, py)
        a = clamp(0.5 - d)
        if not a:
            continue
        blend(img, x, y, mix(top, bottom, clamp((py - box[1]) / (box[3] - box[1]))), a * opacity)
        if d > -RIM:  # outward normal from the distance field; rims stay visible on translucent tiles
            nx, ny = sdf(px + 1, py) - sdf(px - 1, py), sdf(px, py + 1) - sdf(px, py - 1)
            lit = (nx * LIGHT[0] + ny * LIGHT[1]) / (math.hypot(nx, ny) or 1)
            edge = a * clamp(1 + d / RIM) ** 2
            blend(img, x, y, (255, 255, 255) if lit > 0 else shadow, edge * lit * lit * (0.85 if lit > 0 else 0.3))


def render(look: dict) -> bytes:
    top, bottom = rgb(look["bg"][0]), rgb(look["bg"][1])
    img = bytearray()
    for y in range(SIZE):
        t = (y + 0.5) / SIZE
        img += bytes(round(a + (b - a) * t) for a, b in zip(top, bottom)) * SIZE
    xs, ys = [p[0] for p in BAR_PTS], [p[1] for p in BAR_PTS]
    shapes = [(lambda px, py, r=(x, y, w, h): rect_sdf(px, py, *r), (x - 1, y - 1, x + w + 1, y + h + 1),
               "tile", opacity) for (x, y, w, h), opacity in zip(TILES, look["fade"])]
    shapes.append((bar_sdf, (min(xs) - BAR_R - 1, min(ys) - BAR_R - 1, max(xs) + BAR_R + 2, max(ys) + BAR_R + 2),
                   "bar", 1))
    shadows(img, shapes, look)  # the T floats as one element: shadows land on the background only
    for sdf, box, part, opacity in shapes:
        body(img, sdf, box, look, part, opacity)
    return bytes(img)


def png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def encode_png(pixels: bytes) -> bytes:
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit, colour type 2 = RGB, no alpha
    stride = SIZE * 3
    raw = b"".join(b"\x00" + pixels[y * stride:(y + 1) * stride] for y in range(SIZE))  # filter 0 per row
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr)
            + png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b""))


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent / "Resources"
    writes = {root / "AppIcon.icon" / "Assets" / name: body.encode() for name, body in layers().items()}
    for suffix, look in APPEARANCES.items():
        png = encode_png(render(look))
        writes[root / "Assets.xcassets" / "AppIcon.appiconset" / f"AppIcon{suffix}.png"] = png
        if not suffix:
            writes[root / "AppIcon.png"] = png
    for target, data in writes.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        print(f"wrote {target.relative_to(root.parent)} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
