"""Draw Dazed Dank's occupation (64x64, media/textures) and trait (18x18, media/ui/traits) icons.

    python3 tools/make_trait_icons.py
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw

MEDIA = Path(__file__).resolve().parent.parent / "Contents/mods/DazedDank/42/media"
PURPLE, DEEP, GOLD, GREEN, DARKGREEN, RED, WHITE = (124, 72, 176), (62, 30, 96), (232, 186, 74), (98, 176, 74), (46, 104, 40), (196, 62, 52), (240, 236, 228)


def leaf(d, cx, cy, s, fill, outline=None, blades=7, spread=150):
    """A cannabis leaf of `blades` blades fanned over `spread` degrees, centred on its stem base at (cx, cy)."""
    for i in range(blades):
        a = math.radians(-90 - spread / 2 + spread * i / (blades - 1))
        length = s * (1.0 - abs(i - (blades - 1) / 2) / blades * 0.9)
        tip = (cx + math.cos(a) * length, cy + math.sin(a) * length)
        side = math.radians(90)
        w = s * 0.16
        l1 = (cx + math.cos(a + side) * w * 0.4 + math.cos(a) * length * 0.45, cy + math.sin(a + side) * w * 0.4 + math.sin(a) * length * 0.45)
        l2 = (cx + math.cos(a - side) * w * 0.4 + math.cos(a) * length * 0.45, cy + math.sin(a - side) * w * 0.4 + math.sin(a) * length * 0.45)
        d.polygon([(cx, cy), l1, tip, l2], fill=fill, outline=outline)
    d.line([(cx, cy), (cx, cy + s * 0.35)], fill=fill, width=max(1, int(s * 0.08)))


def badge(name, draw_fn):
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((2, 2, 61, 61), fill=PURPLE, outline=GOLD, width=3)
    draw_fn(d)
    im.save(MEDIA / "textures" / ("profession_dd_%s.png" % name))


def small(name, draw_fn, scale=4):
    big = Image.new("RGBA", (18 * scale, 18 * scale), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(big), scale)
    big.resize((18, 18), Image.LANCZOS).save(MEDIA / "ui" / "traits" / ("trait_%s.png" % name))


def jar(d, x, y, w, h, fill):
    d.rounded_rectangle((x, y + h * 0.18, x + w, y + h), radius=w * 0.18, fill=WHITE, outline=fill, width=2)
    d.rectangle((x + w * 0.12, y, x + w * 0.88, y + h * 0.2), fill=GOLD)
    d.ellipse((x + w * 0.2, y + h * 0.45, x + w * 0.8, y + h * 0.9), fill=fill)


def scissors(d, s):
    d.line([(4 * s, 3 * s), (14 * s, 13 * s)], fill=WHITE, width=2 * s)
    d.line([(14 * s, 3 * s), (4 * s, 13 * s)], fill=WHITE, width=2 * s)
    for cx in (4, 14):
        d.ellipse(((cx - 3) * s, 12 * s, (cx + 3) * s, 17 * s), outline=GOLD, width=s + 1)


def main():
    (MEDIA / "ui" / "traits").mkdir(parents=True, exist_ok=True)
    badge("cultivationtech", lambda d: leaf(d, 32, 40, 24, GREEN, DARKGREEN))
    badge("budtender", lambda d: jar(d, 20, 14, 24, 36, GREEN))
    def breeder(d):
        leaf(d, 22, 42, 15, GREEN, DARKGREEN, blades=5)
        leaf(d, 42, 42, 15, (150, 90, 196), DEEP, blades=5)
        d.line([(22, 50), (32, 56), (42, 50)], fill=GOLD, width=3)
    badge("breeder", breeder)
    small("cultivationtech", lambda d, s: leaf(d, 9 * s, 12 * s, 9 * s, GREEN, DARKGREEN))
    small("budtender", lambda d, s: jar(d, 4 * s, 2 * s, 10 * s, 15 * s, GREEN))
    small("breeder", lambda d, s: (leaf(d, 6 * s, 13 * s, 6 * s, GREEN, blades=5), leaf(d, 12 * s, 13 * s, 6 * s, (150, 90, 196), blades=5)))
    small("greenthumb", lambda d, s: (d.rounded_rectangle((6 * s, 9 * s, 12 * s, 17 * s), radius=2 * s, fill=(222, 178, 140)),
                                      leaf(d, 9 * s, 9 * s, 8 * s, GREEN, DARKGREEN, blades=5)))
    small("trimhand", scissors)
    small("chronic", lambda d, s: (leaf(d, 9 * s, 13 * s, 8 * s, GREEN, DARKGREEN),
                                   d.arc((10 * s, 1 * s, 17 * s, 8 * s), 180, 360, fill=(200, 200, 200), width=s + 1),
                                   d.ellipse((12 * s, 12 * s, 17 * s, 17 * s), fill=RED)))
    small("lightweight", lambda d, s: (d.line([(3 * s, 16 * s), (15 * s, 2 * s)], fill=WHITE, width=s + 1),
                                       d.polygon([(6 * s, 12 * s), (15 * s, 2 * s), (12 * s, 11 * s)], fill=(200, 210, 230), outline=WHITE)))
    print("icons written")


if __name__ == "__main__":
    main()
