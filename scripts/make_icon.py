#!/usr/bin/env python3
"""Generate the PocketBrains app icon: the candlelight aurora orb resting in
ink. Pure stdlib (zlib PNG writer) so it runs anywhere. Output: 1024x1024."""
import math
import random
import struct
import sys
import zlib

S = 1024
random.seed(7)

INK_TOP = (13, 14, 18)
INK_BOTTOM = (9, 10, 13)
LUMEN = (228, 197, 111)
CORE = (255, 243, 214)

ORB_X, ORB_Y = S / 2, S * 0.46
ORB_R = S * 0.30


def pixel(x, y):
    t = y / S
    r = INK_TOP[0] + (INK_BOTTOM[0] - INK_TOP[0]) * t
    g = INK_TOP[1] + (INK_BOTTOM[1] - INK_TOP[1]) * t
    b = INK_TOP[2] + (INK_BOTTOM[2] - INK_TOP[2]) * t

    # Vignette keeps the corners quiet.
    dx, dy = (x - S / 2) / S, (y - S / 2) / S
    vig = 1.0 - 0.55 * (dx * dx + dy * dy) * 2.2
    r, g, b = r * vig, g * vig, b * vig

    # The orb: gaussian glow with a hot core, slightly oval (breathing).
    ox, oy = (x - ORB_X) / ORB_R, (y - ORB_Y) / (ORB_R * 0.96)
    d2 = ox * ox + oy * oy
    glow = math.exp(-d2 * 1.55)
    core = math.exp(-d2 * 7.0)

    r += LUMEN[0] * glow * 0.85 + (CORE[0] - LUMEN[0]) * core * 0.9
    g += LUMEN[1] * glow * 0.85 + (CORE[1] - LUMEN[1]) * core * 0.9
    b += LUMEN[2] * glow * 0.85 + (CORE[2] - LUMEN[2]) * core * 0.9

    # A thin meridian ring of light around the orb — the "thinking" halo.
    dist = math.sqrt(d2)
    ring = math.exp(-((dist - 1.22) ** 2) * 220.0)
    r += LUMEN[0] * ring * 0.30
    g += LUMEN[1] * ring * 0.30
    b += LUMEN[2] * ring * 0.30

    # Soft pool of reflected light below the orb.
    py = (y - (ORB_Y + ORB_R * 1.9)) / (ORB_R * 0.5)
    px = (x - ORB_X) / (ORB_R * 1.6)
    pool = math.exp(-(px * px + py * py) * 2.2)
    r += LUMEN[0] * pool * 0.10
    g += LUMEN[1] * pool * 0.10
    b += LUMEN[2] * pool * 0.10

    # Fine grain to kill gradient banding.
    n = random.uniform(-1.6, 1.6)
    return (
        max(0, min(255, int(r + n))),
        max(0, min(255, int(g + n))),
        max(0, min(255, int(b + n))),
    )


def write_png(path):
    rows = bytearray()
    for y in range(S):
        rows.append(0)  # filter: none
        for x in range(S):
            rows.extend(pixel(x, y))

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
    write_png(out)
    print(f"wrote {out} ({S}x{S})")
