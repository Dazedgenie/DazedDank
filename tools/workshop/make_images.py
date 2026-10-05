"""Builds the Steam Workshop page images (purple banner, section headers, strain and stage strips, item grid) from the Blender renders.
Run: python tools/workshop/make_images.py out_dir
"""

import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent / "blender"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
LILAC, PINK, DEEP = (226, 208, 255), (255, 170, 230), (24, 10, 44)


def font(path, size):
    return ImageFont.truetype(path, size)


def gradient(w, h, top=(22, 8, 42), bottom=(92, 38, 140)):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img.convert("RGBA")


def glow(img, rng, n=14, spread=1.0):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        x, y = rng.uniform(0, img.width), rng.uniform(0, img.height)
        r = rng.uniform(40, 150) * spread
        col = rng.choice([(190, 110, 255, 46), (255, 120, 220, 34), (130, 90, 255, 40)])
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(28))
    img.alpha_composite(layer)


def sparkles(img, rng, n=60):
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = rng.uniform(0, img.width), rng.uniform(0, img.height)
        r = rng.choice([1, 1, 2])
        d.ellipse([x - r, y - r, x + r, y + r], fill=(240, 225, 255, rng.randint(70, 190)))


def load(path, height=None):
    im = Image.open(path).convert("RGBA")
    box = im.getbbox()
    im = im.crop(box) if box else im
    if height:
        im = im.resize((max(1, round(im.width * height / im.height)), height), Image.LANCZOS)
    return im


def load_image(im, height):
    im = im.convert("RGBA")
    box = im.getbbox()
    im = im.crop(box) if box else im
    return im.resize((max(1, round(im.width * height / im.height)), height), Image.LANCZOS)


def shadow_text(img, xy, text, f, fill=LILAC, anchor="la", glow_col=(180, 90, 255, 200)):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text(xy, text, font=f, fill=glow_col, anchor=anchor)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(10)))
    ImageDraw.Draw(img).text((xy[0] + 3, xy[1] + 4), text, font=f, fill=(10, 0, 24, 220), anchor=anchor)
    ImageDraw.Draw(img).text(xy, text, font=f, fill=fill, anchor=anchor)


def banner(out):
    rng = random.Random(1)
    w, h = 1200, 360
    img = gradient(w, h)
    glow(img, rng)
    sparkles(img, rng)
    x = 800
    for slot, hh in ((8, 320), (4, 250), (12, 290)):
        p = load(ROOT / "plants" / f"slot_{slot:02d}.png", hh)
        img.alpha_composite(p, (x, h - hh - 6))
        x += p.width - 60
    shadow_text(img, (60, 92), "DAZED DANK", font(BOLD, 104))
    shadow_text(img, (64, 218), "Realistic cannabis growing for Project Zomboid", font(SANS, 29), fill=(240, 228, 255))
    shadow_text(img, (64, 262), "BUILD 42   -   FULL MULTIPLAYER SUPPORT", font(BOLD, 21), fill=PINK, glow_col=(255, 90, 200, 120))
    img.convert("RGB").save(out / "banner.png")


def header(out, name, text):
    rng = random.Random(hash(name) & 0xFFFF)
    w, h = 1000, 64
    img = gradient(w, h, (44, 16, 80), (96, 40, 150))
    glow(img, rng, 4, 0.5)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 8, h], fill=(220, 140, 255))
    d.line([0, h - 2, w, h - 2], fill=(255, 170, 230, 255), width=2)
    shadow_text(img, (30, h // 2), text.upper(), font(BOLD, 28), anchor="lm", glow_col=(190, 100, 255, 120))
    img.convert("RGB").save(out / f"header_{name}.png")


def divider(out):
    w, h = 1000, 22
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x in range(w):
        t = 1 - abs(x - w / 2) / (w / 2)
        d.point((x, h // 2), fill=(214, 150, 255, int(255 * t)))
        d.point((x, h // 2 + 1), fill=(214, 150, 255, int(120 * t)))
    for dx in (-26, 0, 26):
        cx = w // 2 + dx
        d.ellipse([cx - 4, h // 2 - 4, cx + 4, h // 2 + 4], fill=(255, 190, 240, 255))
    img.save(out / "divider.png")


def label_tile(img, im, cx, base_y, text, f):
    img.alpha_composite(im, (cx - im.width // 2, base_y - im.height))
    ImageDraw.Draw(img).text((cx, base_y + 14), text, font=f, fill=LILAC, anchor="ma")


def strains(out):
    rng = random.Random(2)
    w, h = 1000, 470
    img = gradient(w, h)
    glow(img, rng, 10)
    sparkles(img, rng, 40)
    for i, (slot, name, tag, hh) in enumerate(((4, "INDICA", "short, bushy, heavy buds", 300), (12, "HYBRID", "balanced in every way", 340), (8, "SATIVA", "tall, airy, long colas", 390))):
        cx = 170 + i * 330
        label_tile(img, load(ROOT / "plants" / f"slot_{slot:02d}.png", hh), cx, 380, name, font(BOLD, 26))
        ImageDraw.Draw(img).text((cx, 424), tag, font=font(SANS, 17), fill=(200, 175, 235), anchor="ma")
    img.convert("RGB").save(out / "strains.png")


def stages(out):
    rng = random.Random(3)
    w, h = 1000, 400
    img = gradient(w, h)
    glow(img, rng, 8)
    names = ["SEEDLING", "VEGETATIVE", "PRE-FLOWER", "FLOWERING", "RIPE"]
    for i, (slot, name) in enumerate(zip((0, 9, 10, 11, 12), names)):
        cx = 100 + i * 200
        hh = (60, 140, 220, 300, 320)[i]
        label_tile(img, load(ROOT / "plants" / f"slot_{slot:02d}.png", hh), cx, 330, name, font(BOLD, 19))
        ImageDraw.Draw(img).text((cx, 366), f"{i + 1} / 5", font=font(SANS, 16), fill=(200, 175, 235), anchor="ma")
    img.convert("RGB").save(out / "stages.png")


def items(out):
    rng = random.Random(4)
    entries = [("seed", "Seeds"), ("cutting", "Cuttings"), ("rooted", "Rooted Cutting"), ("gel", "Rooting Gel"),
               ("dome", "Cloning Dome"), ("veg", "Veg Nutrients"), ("bloom", "Bloom Nutrients"), ("soil", "Potting Soil"),
               ("bagSmall", "Small Grow Bag"), ("bagLarge", "Large Grow Bag"), ("lampBasic", "Basic Lamp"), ("lampPro", "Pro Lamp"),
               ("lampLargeBasic", "Large Basic Lamp"), ("lampLargePro", "Large Pro Lamp"), ("fan", "Drying Fan"), ("rack", "Drying Rack"),
               ("wetIndica", "Wet Plant"), ("driedHybrid", "Dried Plant"), ("bud", "Cannabis Bud"), ("jar", "Curing Jar"),
               ("papers", "Rolling Papers"), ("joint", "Joint"), ("pipe", "Pipe")]
    cols, cell = 6, 166
    rows = (len(entries) + cols - 1) // cols
    w, h = cols * cell + 20, rows * (cell + 34) + 20
    img = gradient(w, h, (28, 12, 52), (70, 28, 110))
    glow(img, rng, 8)
    d = ImageDraw.Draw(img)
    for i, (key, label) in enumerate(entries):
        x, y = 10 + (i % cols) * cell, 10 + (i // cols) * (cell + 34)
        tilelayer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(tilelayer).rounded_rectangle([x + 4, y + 4, x + cell - 4, y + cell + 24], radius=14, fill=(255, 255, 255, 16), outline=(190, 130, 255, 110))
        img.alpha_composite(tilelayer)
        icon_path = ROOT / "icons" / f"{key}.png"
        if icon_path.exists():
            ic = load(icon_path, 112)
        else:
            sys.path.insert(0, str(ROOT.parent))
            import draw_placeholders
            ic = load_image(draw_placeholders.ICONS["SoilSack"](), 112)
        ic.thumbnail((128, 112), Image.LANCZOS)
        img.alpha_composite(ic, (x + (cell - ic.width) // 2, y + 12 + (112 - ic.height) // 2))
        d.text((x + cell // 2, y + cell - 18), label, font=font(BOLD, 15), fill=LILAC, anchor="mm")
    img.convert("RGB").save(out / "items.png")


def main(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    banner(out)
    divider(out)
    for name, text in (("about", "What is Dazed Dank?"), ("start", "Getting started"), ("strains", "Strains and growth"),
                       ("gear", "Grow gear"), ("dry", "Drying, trimming and curing"), ("clone", "Cloning"),
                       ("smoke", "Smoking, tolerance and dependency"), ("loot", "Loot and crafting"),
                       ("options", "Sandbox options"), ("compat", "Compatibility"), ("faq", "FAQ and bug reports")):
        header(out, name, text)
    strains(out)
    stages(out)
    items(out)
    print("wrote", len(list(out.glob("*.png"))), "images to", out)


if __name__ == "__main__":
    main(sys.argv[1])
