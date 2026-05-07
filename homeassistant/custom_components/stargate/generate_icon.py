#!/usr/bin/env python3
"""Generate icon.png for the Stargate HA custom component. No dependencies."""
import math
import struct
import zlib
from pathlib import Path

W = H = 256
CX = CY = 128

BG     = (10,  22,  40)
RING   = (74,  144, 217)
BLUE   = (30,  144, 255)
MID    = (99,  179, 237)
LIGHT  = (144, 205, 244)
WHITE  = (255, 255, 255)


def dist(x, y):
    return math.sqrt((x - CX) ** 2 + (y - CY) ** 2)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def point_in_triangle(px, py, ax, ay, bx, by, cx2, cy2):
    def sign(x1, y1, x2, y2, x3, y3):
        return (x1-x3)*(y2-y3) - (x2-x3)*(y1-y3)
    d1 = sign(px, py, ax, ay, bx, by)
    d2 = sign(px, py, bx, by, cx2, cy2)
    d3 = sign(px, py, cx2, cy2, ax, ay)
    has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)


# --- build pixel grid ---
pixels = [[BG] * W for _ in range(H)]

for y in range(H):
    for x in range(W):
        d = dist(x, y)

        if 115 <= d <= 123:       # outer ring
            pixels[y][x] = RING
        elif 85 <= d <= 91:       # inner ring
            pixels[y][x] = RING
        elif d < 85:              # vortex interior
            if 57 <= d <= 62:
                pixels[y][x] = BLUE
            elif 41 <= d <= 46:
                pixels[y][x] = MID
            elif 25 <= d <= 29:
                pixels[y][x] = LIGHT
            elif d <= 14:
                t = d / 14
                pixels[y][x] = lerp(WHITE, BLUE, t)
            else:
                pixels[y][x] = BG

# --- draw 9 chevrons (V-shape pointing outward) ---
for i in range(9):
    a = math.radians(i * 40 - 90)          # angle of chevron centre

    half_w = math.radians(7)               # half-width of the V arms

    # tip of the V (outer edge)
    tip_r  = 122
    tx = CX + tip_r * math.cos(a)
    ty = CY + tip_r * math.sin(a)

    # left and right base of the V (inner, spread apart)
    base_r = 106
    lx = CX + base_r * math.cos(a - half_w)
    ly = CY + base_r * math.sin(a - half_w)
    rx = CX + base_r * math.cos(a + half_w)
    ry = CY + base_r * math.sin(a + half_w)

    # rasterise the triangle
    min_x = max(0, int(min(tx, lx, rx)) - 2)
    max_x = min(W - 1, int(max(tx, lx, rx)) + 2)
    min_y = max(0, int(min(ty, ly, ry)) - 2)
    max_y = min(H - 1, int(max(ty, ly, ry)) + 2)

    for py in range(min_y, max_y + 1):
        for px in range(min_x, max_x + 1):
            if point_in_triangle(px, py, tx, ty, lx, ly, rx, ry):
                pixels[py][px] = RING

# --- encode PNG (stdlib only) ---
def make_chunk(chunk_type: bytes, data: bytes) -> bytes:
    body = chunk_type + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

def save_png(path: Path, w: int, h: int, pixel_grid) -> None:
    raw_rows = b"".join(
        b"\x00" + bytes(c for pixel in row for c in pixel)
        for row in pixel_grid
    )
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + make_chunk(b"IHDR", ihdr)
        + make_chunk(b"IDAT", zlib.compress(raw_rows, 9))
        + make_chunk(b"IEND", b"")
    )
    path.write_bytes(data)
    print(f"Created {path} ({len(data)} bytes)")


def scale_pixels(src, factor: int):
    """Nearest-neighbour upscale."""
    return [
        [src[y // factor][x // factor] for x in range(len(src[0]) * factor)]
        for y in range(len(src) * factor)
    ]


def recolor(src, old_bg, new_bg):
    """Swap background colour (for light/dark variants)."""
    return [
        [new_bg if px == old_bg else px for px in row]
        for row in src
    ]


base = Path(__file__).parent / "icons"
base.mkdir(exist_ok=True)

# dark theme variants (current blue-on-dark design)
save_png(base / "dark_icon.png",   W,   H,   pixels)
save_png(base / "dark_icon@2x.png", W*2, H*2, scale_pixels(pixels, 2))

# light theme variants (swap dark background for near-white)
LIGHT_BG = (240, 244, 248)
light = recolor(pixels, BG, LIGHT_BG)
save_png(base / "icon.png",   W,   H,   light)
save_png(base / "icon@2x.png", W*2, H*2, scale_pixels(light, 2))
