#!/usr/bin/env python3
"""Render the fictional printed timetable used by the App Preview import shot.

Output: video/assets/import-source.png (a phone-style photo of a printed sheet) and
video/assets/import-source-flat.png (the flat sheet, a fallback). Deterministic: same input, same pixels.
The grid is the `preview` seed's week (Class 11B), so the imported result matches the rest of the video.
Font: Inter (SIL OFL 1.1). Run: python3 video/tools/make_import_photo.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets")
FONT_DIR = "C:/Windows/Fonts" if os.name == "nt" else "/usr/share/fonts/truetype/inter"
REG, BOLD = os.path.join(FONT_DIR, "Inter-Regular.ttf"), os.path.join(FONT_DIR, "Inter-SemiBold.ttf")

DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
BELLS = ["08:00–08:45", "08:55–09:40", "09:55–10:40", "10:50–11:35", "11:45–12:30", "13:15–14:00"]
GRID = [  # rows = periods, columns = days; (subject, room) or None
    [("English", "112"), ("History", "118"), ("Mathematics", "204"), ("Chemistry", "Lab 1"), ("Biology", "Lab 2")],
    [("Mathematics", "204"), ("English", "112"), ("Physics", "Lab 3"), ("Mathematics", "204"), ("Geography", "120")],
    [("History", "118"), ("Mathematics", "204"), ("English", "112"), ("Biology", "Lab 2"), ("Mathematics", "204")],
    [("Chemistry", "Lab 1"), ("Biology", "Lab 2"), ("Geography", "120"), ("History", "118"), ("English", "112")],
    [("PE", "Sports hall"), ("Computer Science", "IT 1"), ("Biology", "Lab 2"), ("English", "112"), ("History", "118")],
    [("Geography", "120"), ("Physics", "Lab 3"), ("PE", "Sports hall"), ("Computer Science", "IT 1"), None],
]


def sheet():
    w, h = 2400, 3200
    img = Image.new("RGB", (w, h), (252, 251, 248))
    d = ImageDraw.Draw(img)
    f_title, f_sub = ImageFont.truetype(BOLD, 96), ImageFont.truetype(REG, 56)
    f_head, f_cell, f_room = ImageFont.truetype(BOLD, 50), ImageFont.truetype(BOLD, 50), ImageFont.truetype(REG, 44)
    ink = (28, 30, 36)
    d.text((140, 150), "Class 11B · Timetable", font=f_title, fill=ink)
    d.text((140, 280), "Autumn term 2026", font=f_sub, fill=(90, 94, 102))
    x0, y0, first, col, head, row = 140, 440, 360, 352, 130, 420
    cols = [x0, x0 + first] + [x0 + first + col * (i + 1) for i in range(5)]
    rows = [y0, y0 + head] + [y0 + head + row * (i + 1) for i in range(6)]
    for x in cols:
        d.line([(x, rows[0]), (x, rows[-1])], fill=ink, width=4)
    for y in rows:
        d.line([(cols[0], y), (cols[-1], y)], fill=ink, width=4)

    def centred(text, font, cx, cy):
        l, t, r, b = d.textbbox((0, 0), text, font=font)
        d.text((cx - (r - l) / 2, cy - (b - t) / 2 - t), text, font=font, fill=ink)

    for i, day in enumerate(DAYS):
        centred(day, f_head, (cols[i + 1] + cols[i + 2]) / 2, (rows[0] + rows[1]) / 2)
    for p, bell in enumerate(BELLS):
        cy = (rows[p + 1] + rows[p + 2]) / 2
        centred(str(p + 1), f_head, (cols[0] + cols[1]) / 2, cy - 40)
        centred(bell, ImageFont.truetype(REG, 40), (cols[0] + cols[1]) / 2, cy + 40)
        for i, cell in enumerate(GRID[p]):
            if not cell:
                continue
            cx = (cols[i + 1] + cols[i + 2]) / 2
            name, room = cell
            parts = name.split(" ") if d.textlength(name, font=f_cell) > col - 40 else [name]
            top = cy - 30 * len(parts) - 20
            for k, part in enumerate(parts):
                centred(part, f_cell, cx, top + 60 * k)
            centred(room, f_room, cx, top + 60 * len(parts) + 20)
    return img


def perspective_coeffs(dst, src):
    """PIL PERSPECTIVE coefficients mapping output points `dst` back to input points `src`."""
    a = []
    for (x, y), (u, v) in zip(dst, src):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    return np.linalg.solve(np.array(a, float), np.array(src, float).reshape(8)).tolist()


def photo(flat):
    W, H = 3024, 4032
    yy, xx = np.mgrid[0:H, 0:W]
    base = np.array([168, 150, 128], float)  # plain warm desk tone
    shade = 1.0 - 0.18 * ((xx / W - 0.35) ** 2 + (yy / H - 0.3) ** 2)
    bg = np.clip(base[None, None, :] * shade[..., None] + np.random.default_rng(3).normal(0, 3, (H, W, 1)), 0, 255)
    canvas = Image.fromarray(bg.astype("uint8"))
    w, h = flat.size
    corners = [(330, 470), (2720, 560), (2790, 3640), (250, 3560)]  # slight tilt + perspective
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).polygon([(x + 30, y + 40) for x, y in corners], fill=120)
    canvas.paste((60, 50, 40), (0, 0), shadow.filter(ImageFilter.GaussianBlur(45)))
    coeffs = perspective_coeffs(corners, [(0, 0), (w, 0), (w, h), (0, h)])
    warped = flat.transform((W, H), Image.Transform.PERSPECTIVE, coeffs, Image.Resampling.BICUBIC)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(corners, fill=255)
    light = np.clip(1.0 - 0.10 * (xx / W) - 0.06 * (yy / H), 0, 1)[..., None]
    lit = Image.fromarray(np.clip(np.asarray(warped, float) * light, 0, 255).astype("uint8"))
    canvas.paste(lit, (0, 0), mask)
    return canvas.filter(ImageFilter.GaussianBlur(0.8))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    flat = sheet()
    flat.save(os.path.join(OUT, "import-source-flat.png"), optimize=True)
    photo(flat).save(os.path.join(OUT, "import-source.png"), optimize=True)
    print("wrote", os.path.join(OUT, "import-source.png"))
