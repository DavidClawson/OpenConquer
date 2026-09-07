#!/usr/bin/env python3
"""Generate the OpenConquer app icon (.icns) from an original vector-ish design.

This draws the icon procedurally — it uses NO game art. "Command & Conquer" and
"Tiberian Dawn" are EA trademarks and their art is never redistributed by this
project, so the app mark is our own: an isometric map cell over a dark ground,
in the amber/green of the classic sidebar palette.

Usage:
    python3 tools/make_icon.py out/OpenConquer.icns

Requires Pillow (`pip3 install Pillow`) and macOS `iconutil`. If either is
missing, `make-app.sh` skips the icon and the app gets the generic one.
"""

import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow is required: pip3 install Pillow")

BG_OUTER = (18, 20, 18)
BG_INNER = (28, 34, 28)
GREEN = (0, 216, 88)
GREEN_DIM = (0, 128, 56)
AMBER = (240, 176, 32)


def rounded_rect(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def iso(cx, cy, gx, gy, tw, th):
    """Grid coords -> screen coords for a 2:1 isometric projection."""
    return (cx + (gx - gy) * tw / 2, cy + (gx + gy) * th / 2)


def draw_icon(size):
    """Render the icon at `size` px square, supersampled 4x then downscaled."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # macOS icon grid: the art sits in ~82% of the canvas with rounded corners.
    m = s * 0.09
    rounded_rect(d, (m, m, s - m, s - m), radius=s * 0.185, fill=BG_OUTER)
    inset = s * 0.115
    rounded_rect(d, (inset, inset, s - inset, s - inset),
                 radius=s * 0.165, fill=BG_INNER)

    # A 3x3 isometric tile grid — the unit of a tile-based RTS map. One cell is
    # the objective (amber); the rest are terrain (green), with a lit front edge
    # so the plate reads as solid rather than as a flat diamond.
    n = 3
    tw = s * 0.205           # tile width in screen px
    th = tw / 2              # 2:1 isometric
    depth = s * 0.075
    cx = s / 2
    cy = s / 2 - (n * th) / 2 - depth / 2 + s * 0.012

    # Front-facing skirt: the outline of the whole plate, dropped by `depth`.
    hull = [iso(cx, cy, 0, 0, tw, th), iso(cx, cy, n, 0, tw, th),
            iso(cx, cy, n, n, tw, th), iso(cx, cy, 0, n, tw, th)]
    skirt = [hull[3], hull[2], (hull[2][0], hull[2][1] + depth),
             (hull[3][0], hull[3][1] + depth)]
    d.polygon([hull[1], hull[2], (hull[2][0], hull[2][1] + depth),
               (hull[1][0], hull[1][1] + depth)], fill=GREEN_DIM)
    d.polygon(skirt, fill=GREEN_DIM)

    objective = (1, 1)
    for gy in range(n):
        for gx in range(n):
            quad = [iso(cx, cy, gx, gy, tw, th), iso(cx, cy, gx + 1, gy, tw, th),
                    iso(cx, cy, gx + 1, gy + 1, tw, th), iso(cx, cy, gx, gy + 1, tw, th)]
            fill = AMBER if (gx, gy) == objective else GREEN
            d.polygon(quad, fill=fill, outline=BG_INNER, width=max(1, int(s * 0.006)))

    # Scanline texture over the whole face — a nod to the CRT look, drawn, not sampled.
    scan = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scan)
    step = max(4, s // 128)
    for y in range(int(inset), int(s - inset), step * 2):
        sd.rectangle((inset, y, s - inset, y + step - 1), fill=(0, 0, 0, 26))
    img = Image.alpha_composite(img, scan)

    return img.resize((size, size), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "OpenConquer.icns"
    out = os.path.abspath(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "OpenConquer.iconset")
        os.makedirs(iconset)
        # The sizes `iconutil` expects, each with its @2x partner.
        for base in (16, 32, 128, 256, 512):
            draw_icon(base).save(os.path.join(iconset, f"icon_{base}x{base}.png"))
            draw_icon(base * 2).save(
                os.path.join(iconset, f"icon_{base}x{base}@2x.png"))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)

    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
