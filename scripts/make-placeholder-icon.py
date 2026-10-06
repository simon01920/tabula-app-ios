#!/usr/bin/env python3
"""Generate the placeholder 1024x1024 app icon with the Python stdlib only (zlib + struct).

Output: opaque RGB PNG (App Store icons must not have an alpha channel), written to
  Resources/AppIcon.png                                   (xtool iconPath)
  Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png (XcodeGen/CI asset catalog)
Placeholder only: replace with real artwork before Phase 11.
"""
import pathlib
import struct
import zlib

SIZE = 1024
BG = (31, 58, 147)       # deep blue
GRID = (236, 241, 255)   # near-white grid lines
ACCENT = (255, 196, 61)  # one highlighted "lesson" cell


def build_pixels() -> bytes:
    margin, cols, rows, line = 160, 5, 6, 18
    cell_w = (SIZE - 2 * margin) // cols
    cell_h = (SIZE - 2 * margin) // rows
    rows_out = bytearray()
    for y in range(SIZE):
        rows_out.append(0)  # PNG filter type 0 (None) for this scanline
        for x in range(SIZE):
            color = BG
            inside = margin <= x < SIZE - margin and margin <= y < SIZE - margin
            if inside:
                cx, cy = (x - margin) // cell_w, (y - margin) // cell_h
                if (cx, cy) == (2, 2):
                    color = ACCENT
                on_v = (x - margin) % cell_w < line
                on_h = (y - margin) % cell_h < line
                if on_v or on_h or x >= SIZE - margin - line or y >= SIZE - margin - line:
                    color = GRID
            rows_out.extend(color)
    return bytes(rows_out)


def png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def encode_png(raw: bytes) -> bytes:
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit, colour type 2 = RGB, no alpha
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr)
            + png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b""))


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    png = encode_png(build_pixels())
    targets = [root / "Resources" / "AppIcon.png",
               root / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"]
    for target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(png)
        print(f"wrote {target.relative_to(root)} ({len(png)} bytes)")


if __name__ == "__main__":
    main()
