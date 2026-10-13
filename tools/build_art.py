#!/usr/bin/env python3
"""Draw the light the banners are made of: python3 tools/build_art.py

Every texture is white with its shape in the alpha channel, so the addon tints it to the colour
of the moment and blends it additively. Nothing here is a picture of anything: glows, rays, a
shockwave ring, claw marks, a screen-edge vignette. Written to Godslayer/Art/*.tga, sizes in
powers of two. Needs numpy and Pillow.
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Godslayer", "Art")
rng = np.random.default_rng(7)


def grid(w, h):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    return (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1


def save(name, alpha):
    a = np.clip(alpha, 0, 1)
    rgba = np.zeros(a.shape + (4,), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255 + 0.5).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, name + ".tga"))
    print("%-9s %dx%d" % (name, a.shape[1], a.shape[0]))


def smooth(edge0, edge1, v):
    t = np.clip((v - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def glow():
    x, y = grid(256, 256)
    r = np.hypot(x, y)
    return (np.exp(-(r / 0.42) ** 2) * 0.85 + np.exp(-(r / 0.16) ** 2) * 0.5) * (1 - smooth(0.85, 1.0, r))


def flare():
    # a horizontal streak of light: a hot core and long thin arms
    x, y = grid(1024, 64)
    arms = np.exp(-np.abs(x) / 0.33) * np.exp(-(y / 0.2) ** 2)
    core = np.exp(-(x / 0.10) ** 2) * np.exp(-(y / 0.45) ** 2)
    return (arms + core * 0.7) * (1 - smooth(0.9, 1.0, np.abs(x)))


def rays():
    # light breaking out from behind something: uneven spokes, fading outward
    x, y = grid(512, 512)
    r, a = np.hypot(x, y), np.arctan2(y, x)
    spokes = np.zeros_like(r)
    for k, weight in ((7, 1.0), (13, 0.7), (23, 0.45), (41, 0.25)):
        spokes += weight * np.sin(a * k + rng.uniform(0, 6.283))
    spokes = smooth(-0.4, 1.6, spokes)
    return spokes * np.exp(-(r / 0.55) ** 2) * (1 - smooth(0.8, 1.0, r)) * smooth(0.02, 0.2, r) * 1.4


def ring():
    x, y = grid(256, 256)
    r = np.hypot(x, y)
    return np.exp(-((r - 0.82) / 0.035) ** 2) + np.exp(-((r - 0.80) / 0.12) ** 2) * 0.25 * (r < 0.82)


def vignette():
    # the edges of the screen: nothing in the middle, where the fight is
    x, y = grid(512, 512)
    r = np.hypot(x, y) / 1.4142
    return smooth(0.52, 1.0, r) ** 1.5


def slash():
    # three claw marks, each a tapered stroke with a bright spine and a torn edge
    w, h = 512, 256
    x, y = grid(w, h)
    out = np.zeros((h, w))
    tear = rng.normal(0, 1, (h, w))
    for _ in range(3):
        tear = (tear + np.roll(tear, 5, 1) + np.roll(tear, -5, 1) + np.roll(tear, 1, 0) + np.roll(tear, -1, 0)) / 5
    tear = tear / tear.std()
    for i, offset in enumerate((-0.52, 0.0, 0.52)):
        reach = 0.86 - 0.1 * abs(i - 1)              # the middle claw cuts longest
        across = y - offset + 0.36 * x
        taper = np.clip(1 - np.abs(x / reach) ** 2.4, 0, 1)
        width = 0.03 + 0.10 * taper
        body = np.exp(-(across / width) ** 2) * taper ** 0.5
        spine = np.exp(-(across / (width * 0.25)) ** 2) * taper
        out = np.maximum(out, body * np.clip(0.7 + 0.35 * tear, 0, 1.2) + spine * 0.7)
    return out


def bar():
    x, y = grid(256, 32)
    return (0.55 + 0.45 * np.exp(-(y / 0.5) ** 2)) * (1 - smooth(0.55, 1.0, np.abs(y)))


def spark():
    x, y = grid(64, 64)
    r = np.hypot(x, y)
    star = np.exp(-np.abs(x) / 0.25) * np.exp(-(y / 0.07) ** 2) + np.exp(-np.abs(y) / 0.25) * np.exp(-(x / 0.07) ** 2)
    return (star * 0.8 + np.exp(-(r / 0.22) ** 2)) * (1 - smooth(0.85, 1.0, r))


def plate():
    # the dark the words sit on: soft-edged, so it reads over snow and over lava
    x, y = grid(512, 128)
    return (1 - smooth(0.35, 1.0, np.abs(x))) * (1 - smooth(0.25, 1.0, np.abs(y)))


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in (("glow", glow), ("flare", flare), ("rays", rays), ("ring", ring), ("vignette", vignette),
                       ("slash", slash), ("bar", bar), ("spark", spark), ("plate", plate)):
        save(name, make())


if __name__ == "__main__":
    main()
