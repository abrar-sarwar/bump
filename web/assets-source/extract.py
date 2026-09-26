#!/usr/bin/env python3
"""
Turn the flattened brand photography into transparent, web-sized layers.

The two phone/hand photos are isolated subjects on white, so we key the white,
keep only the largest connected blob (drops stray specks), then fill interior
holes so the white camera plateau and the gaps between fingers survive.

Run:  python3 assets-source/extract.py
"""
from PIL import Image
import os

SRC = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(SRC, "..", "public", "assets")


def dist(c, r):
    return abs(c[0] - r[0]) + abs(c[1] - r[1]) + abs(c[2] - r[2])


def largest_blob(mask, W, H):
    """Iterative flood fill; returns the biggest 4-connected component."""
    seen = bytearray(W * H)
    best = []
    for sy in range(H):
        row = sy * W
        for sx in range(W):
            i = row + sx
            if not mask[i] or seen[i]:
                continue
            comp, stack = [], [i]
            seen[i] = 1
            while stack:
                j = stack.pop()
                comp.append(j)
                cy, cx = divmod(j, W)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < W and 0 <= ny < H:
                        k = ny * W + nx
                        if mask[k] and not seen[k]:
                            seen[k] = 1
                            stack.append(k)
            if len(comp) > len(best):
                best = comp
    return best


def fill_holes(keep, W, H):
    """Anything not reachable from the border is interior -> keep it."""
    outside = bytearray(W * H)
    stack = []
    for x in range(W):
        for y in (0, H - 1):
            i = y * W + x
            if not keep[i] and not outside[i]:
                outside[i] = 1
                stack.append(i)
    for y in range(H):
        for x in (0, W - 1):
            i = y * W + x
            if not keep[i] and not outside[i]:
                outside[i] = 1
                stack.append(i)
    while stack:
        j = stack.pop()
        cy, cx = divmod(j, W)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < W and 0 <= ny < H:
                k = ny * W + nx
                if not keep[k] and not outside[k]:
                    outside[k] = 1
                    stack.append(k)
    for i in range(W * H):
        if not outside[i]:
            keep[i] = 1
    return keep


def cutout(src, out_name, bg, tol, widths, downscale=2):
    im = Image.open(os.path.join(SRC, src)).convert("RGB")
    # Work at half resolution: the flood fills are O(pixels) in pure Python and
    # the sources are ~2200px, far larger than we ship anyway.
    im = im.resize((im.width // downscale, im.height // downscale), Image.LANCZOS)
    W, H = im.size
    p = im.load()

    mask = bytearray(W * H)
    for y in range(H):
        row = y * W
        for x in range(W):
            if dist(p[x, y], bg) > tol:
                mask[row + x] = 1

    keep = bytearray(W * H)
    for j in largest_blob(mask, W, H):
        keep[j] = 1
    keep = fill_holes(keep, W, H)

    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    o = out.load()
    for y in range(H):
        row = y * W
        for x in range(W):
            if keep[row + x]:
                c = p[x, y]
                o[x, y] = (c[0], c[1], c[2], 255)

    out = out.crop(out.getbbox())
    for w in widths:
        h = round(out.height * w / out.width)
        suffix = "" if w == widths[0] else f"@{w}"
        name = out_name if w == widths[0] else out_name.replace(".png", f"{suffix}.png")
        out.resize((w, h), Image.LANCZOS).save(os.path.join(OUT, name), optimize=True)
        print(f"  {name}  {w}x{h}")


print("phone-blue-hand")
cutout("phone-blue-hand.source.png", "phone-blue.png", (255, 255, 255), 28, [1100, 1600])
print("phone-orange-hand")
cutout("phone-orange-hand.source.png", "phone-orange.png", (255, 255, 255), 28, [1100, 1600])
print("wordmark (ivory ground, drop the editor's purple selection rect)")
cutout("wordmark.source.png", "wordmark.png", (254, 249, 240), 40, [2400], downscale=1)
