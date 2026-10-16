#!/usr/bin/env python3
"""Zeichnet die Technologie-Icons (256 px) nach graphics/technology/.

  item-gamble.png       Coin mit Würfel davor
  item-gamble-luck.png  dasselbe mit gelbem Plus wie bei Vanilla-Upgrade-Forschungen

Gezeichnet wird vierfach groß und dann verkleinert, das glättet die Kanten.
"""
import pathlib

from PIL import Image, ImageDraw

SIZE = 256
K = 4                      # Überabtastung
S = SIZE * K
OUT = pathlib.Path(__file__).resolve().parent.parent / "graphics" / "technology"

GOLD = (233, 178, 52, 255)
GOLD_DARK = (176, 120, 24, 255)
GOLD_LIGHT = (255, 222, 120, 255)
OUTLINE = (24, 20, 16, 255)
WHITE = (238, 236, 230, 255)
SHADE = (196, 192, 184, 255)
PIP = (30, 28, 26, 255)
YELLOW = (255, 204, 40, 255)


def px(v):
    return int(v * K)


def coin(d, cx, cy, r):
    d.ellipse([px(cx - r - 6), px(cy - r - 6), px(cx + r + 6), px(cy + r + 6)], fill=OUTLINE)
    d.ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], fill=GOLD_DARK)
    d.ellipse([px(cx - r), px(cy - r - 6), px(cx + r - 6), px(cy + r - 12)], fill=GOLD)
    inner = r * 0.68
    d.ellipse([px(cx - inner - 3), px(cy - inner - 6), px(cx + inner - 3), px(cy + inner - 6)],
              outline=GOLD_DARK, width=px(7))
    d.arc([px(cx - r + 12), px(cy - r + 6), px(cx + r - 18), px(cy + r - 24)], 200, 260,
          fill=GOLD_LIGHT, width=px(8))


def die(d, x, y, w, pips):
    r = w * 0.18
    d.rounded_rectangle([px(x - 6), px(y - 6), px(x + w + 6), px(y + w + 6)], radius=px(r + 6), fill=OUTLINE)
    d.rounded_rectangle([px(x), px(y), px(x + w), px(y + w)], radius=px(r), fill=SHADE)
    d.rounded_rectangle([px(x), px(y), px(x + w - 7), px(y + w - 9)], radius=px(r), fill=WHITE)
    pr = w * 0.09
    for fx, fy in pips:
        cx, cy = x + fx * (w - 7), y + fy * (w - 9)
        d.ellipse([px(cx - pr), px(cy - pr), px(cx + pr), px(cy + pr)], fill=PIP)


def plus(d, cx, cy, arm, thick):
    o = 9
    for t, color in ((thick + o * 2, OUTLINE), (thick, YELLOW)):
        a = arm + (o if color == OUTLINE else 0)
        d.rectangle([px(cx - a), px(cy - t / 2), px(cx + a), px(cy + t / 2)], fill=color)
        d.rectangle([px(cx - t / 2), px(cy - a), px(cx + t / 2), px(cy + a)], fill=color)


def base():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    coin(d, 104, 104, 82)
    five = [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)]
    die(d, 118, 118, 116, five)
    return img, d


def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / name)
    print(OUT / name)


img, _ = base()
save(img, "item-gamble.png")

img, d = base()
plus(d, 206, 206, 40, 26)
save(img, "item-gamble-luck.png")
