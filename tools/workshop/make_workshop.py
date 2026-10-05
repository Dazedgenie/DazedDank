"""Builds the purple Steam Workshop images for Dazed Dank: banner, section headers and diagrams.
Run: python3 make_workshop.py <sprite cells dir> <hydro cells dir> <item icons dir> <out dir>."""

import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

CELLS, HYDRO, ICONS, OUT = sys.argv[1:5]
os.makedirs(OUT, exist_ok=True)

W = 1280
# Purple palette: deep backgrounds, a vivid primary, and lavender for text.
BG_TOP, BG_BOT = (26, 12, 40), (12, 6, 20)
PANEL, PANEL_EDGE = (36, 18, 58), (110, 52, 190)
PRIMARY, BRIGHT, SOFT = (146, 64, 238), (192, 132, 252), (221, 196, 255)
TEXT, MUTED = (246, 238, 255), (184, 160, 214)

FONT_DIR = "/usr/share/fonts/opentype/noto/"


def font(weight, size):
    """Noto Sans in the given weight (Black, Bold, Medium, Regular)."""
    return ImageFont.truetype(FONT_DIR + "NotoSansCJK-%s.ttc" % weight, size, index=0)


def gradient(w, h, top, bot):
    """A vertical two-colour gradient."""
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        col.putpixel((0, y), tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return col.resize((w, h))


def glow_spot(img, cx, cy, r, color, strength):
    """Add a soft round glow of `color` centred at cx, cy."""
    layer = Image.new("RGB", img.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=tuple(int(c * strength) for c in color))
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.6))
    return ImageChops.add(img, layer)


def background(w, h, spots=()):
    """Dark purple gradient with a few glows."""
    img = gradient(w, h, BG_TOP, BG_BOT)
    for cx, cy, r, s in spots:
        img = glow_spot(img, cx, cy, r, PRIMARY, s)
    return img.convert("RGBA")


def rounded(img, box, radius, fill, outline=None, width=2):
    """Draw a rounded rectangle on img (RGBA) with alpha-aware fill."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius, fill=fill, outline=outline, width=width)
    img.alpha_composite(layer)


def text_size(fnt, s):
    """Width and height of a string's ink box."""
    b = fnt.getbbox(s)
    return b[2] - b[0], b[3] - b[1]


def glow_text(img, xy, s, fnt, fill=TEXT, glow=PRIMARY, blur=10, anchor="la"):
    """Text with a soft purple glow behind it."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text(xy, s, font=fnt, fill=glow + (255,), anchor=anchor)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(layer)
    img.alpha_composite(layer)
    ImageDraw.Draw(img).text(xy, s, font=fnt, fill=fill, anchor=anchor)


def gradient_text(img, xy, s, fnt, top=TEXT, bot=BRIGHT, anchor="la"):
    """Text filled with a top-to-bottom gradient, with a glow behind it."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text(xy, s, font=fnt, fill=255, anchor=anchor)
    bbox = mask.getbbox()
    glow = Image.new("RGBA", img.size, PRIMARY + (0,))
    glow.putalpha(mask.filter(ImageFilter.GaussianBlur(14)))
    img.alpha_composite(glow)
    img.alpha_composite(glow)
    fill = Image.new("RGBA", img.size, (0, 0, 0, 0))
    if bbox:
        g = gradient(bbox[2] - bbox[0], bbox[3] - bbox[1], top, bot).convert("RGBA")
        fill.paste(g, bbox[:2])
    fill.putalpha(mask)
    img.alpha_composite(fill)


def cell(sheet_dir, index):
    """A sprite cell by sheet index, cropped to its visible pixels."""
    name = [f for f in os.listdir(sheet_dir) if f.startswith("%03d_" % index)][0]
    im = Image.open(os.path.join(sheet_dir, name)).convert("RGBA")
    return im.crop(im.getbbox())


def plant(i):
    return cell(CELLS, i)


def hydro(i):
    return cell(HYDRO, i)


def icon(name, scale=3):
    """An item icon, enlarged with crisp pixels."""
    im = Image.open(os.path.join(ICONS, "Item_%s.png" % name)).convert("RGBA")
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


def scaled(im, factor):
    return im.resize((int(im.width * factor), int(im.height * factor)), Image.LANCZOS)


def paste_bottom(img, sprite, cx, base_y, shadow=True):
    """Paste a sprite centred on cx with its bottom on base_y, over a soft purple floor shadow."""
    x, y = int(cx - sprite.width / 2), int(base_y - sprite.height)
    if shadow:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((cx - sprite.width * 0.45, base_y - 10, cx + sprite.width * 0.45, base_y + 12),
                                   fill=PRIMARY + (110,))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(8)))
    img.alpha_composite(sprite, (x, y))


def save(img, name):
    img.convert("RGB").save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)


# --------------------------------------------------------------------------
# Banner
# --------------------------------------------------------------------------

def banner():
    h = 620
    img = background(W, h, [(W // 2, 0, 420, 0.55), (180, 520, 260, 0.3), (1100, 520, 260, 0.3)])
    # Grow-light glow from above: a soft cone.
    cone = Image.new("RGBA", (W, h), (0, 0, 0, 0))
    ImageDraw.Draw(cone).polygon([(W // 2 - 70, 0), (W // 2 + 70, 0), (W // 2 + 560, h), (W // 2 - 560, h)],
                                 fill=BRIGHT + (38,))
    img.alpha_composite(cone.filter(ImageFilter.GaussianBlur(40)))
    # A row of ripe plants along the floor: bags, ground and buckets.
    row = [(hydro(7), 0.9), (plant(134), 0.92), (plant(8), 1.0), (plant(4), 1.05), (plant(12), 1.0),
           (plant(138), 0.92), (plant(383), 0.9)]
    xs = [95, 270, 455, 640, 825, 1010, 1185]
    for (sp, f), x in zip(row, xs):
        s = scaled(sp, f)
        dim = Image.new("RGBA", s.size, (20, 8, 34, 0))
        s = Image.alpha_composite(s, dim)
        paste_bottom(img, s, x, h - 18)
    # Fade the plants into the dark at the top so the title reads.
    fade = Image.new("RGBA", (W, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fade)
    for y in range(h):
        a = int(max(0, 1 - y / 380) * 235)
        fd.line([(0, y), (W, y)], fill=BG_TOP + (a,))
    img.alpha_composite(fade)
    gradient_text(img, (W // 2, 150), "DAZED DANK", font("Black", 150), anchor="mm")
    glow_text(img, (W // 2, 255), "Realistic cannabis growing for Project Zomboid Build 42", font("Bold", 34),
              fill=SOFT, blur=8, anchor="mm")
    chips = ["Multiplayer", "Hydroponics", "Breeding", "Cloning", "Dry · Trim · Cure", "Smoking"]
    f = font("Bold", 22)
    widths = [text_size(f, c)[0] + 40 for c in chips]
    gap = 14
    x = (W - (sum(widths) + gap * (len(chips) - 1))) // 2
    for c, cw in zip(chips, widths):
        rounded(img, (x, 300, x + cw, 340), 20, (60, 24, 96, 220), outline=BRIGHT + (200,), width=2)
        ImageDraw.Draw(img).text((x + cw // 2, 320), c, font=f, fill=TEXT, anchor="mm")
        x += cw + gap
    save(img, "banner.jpg")


# --------------------------------------------------------------------------
# Section headers
# --------------------------------------------------------------------------

HEADERS = [
    ("h-grow", "01", "Grow from seed", "CannabisSeed"),
    ("h-light", "02", "Light it right", "GrowLampPro"),
    ("h-bags", "03", "Grow bags & soil", "GrowBagLarge"),
    ("h-hydro", "04", "Go hydro", "DWCBucket"),
    ("h-breed", "05", "Breed your own strains", "WetHybridPlant"),
    ("h-clone", "06", "Clone your keepers", "CloningDome"),
    ("h-cure", "07", "Dry, trim & cure", "CuringJar"),
    ("h-smoke", "08", "Smoke it", "Joint"),
    ("h-skill", "09", "Know your plants", "GrowersHandbook"),
    ("h-parts", "10", "Finding gear", "VegNutrients"),
    ("h-good", "11", "Good to know", "LightTimer"),
    ("h-help", "12", "Help & feedback", "HydroMagazine"),
]


def header(name, num, title, icon_name):
    h = 150
    img = background(W, h, [(90, 75, 160, 0.55), (W, 0, 300, 0.25)])
    # Icon tile.
    tile = (26, 23, 130, 127)
    rounded(img, tile, 22, (74, 30, 128, 255), outline=BRIGHT + (255,), width=3)
    ic = icon(icon_name, 3)
    img.alpha_composite(ic, (78 - ic.width // 2, 75 - ic.height // 2))
    d = ImageDraw.Draw(img)
    d.text((160, 30), num, font=font("Black", 24), fill=BRIGHT)
    glow_text(img, (158, 52), title, font("Black", 62), fill=TEXT, blur=9)
    # Underline that fades out to the right.
    line = Image.new("RGBA", (W, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line)
    for x in range(160, W - 30):
        a = int(255 * max(0, 1 - (x - 160) / (W - 190)))
        ld.line([(x, 136), (x, 139)], fill=BRIGHT + (a,))
    img.alpha_composite(line)
    save(img, name + ".png")


# --------------------------------------------------------------------------
# Diagrams
# --------------------------------------------------------------------------

def panel(h, spots=()):
    img = background(W, h, spots)
    rounded(img, (8, 8, W - 8, h - 8), 26, PANEL + (200,), outline=PANEL_EDGE + (255,), width=3)
    return img


def arrow(img, x1, x2, y):
    """A purple arrow from x1 to x2 at height y."""
    d = ImageDraw.Draw(img)
    d.line([(x1, y), (x2 - 12, y)], fill=BRIGHT, width=5)
    d.polygon([(x2, y), (x2 - 16, y - 11), (x2 - 16, y + 11)], fill=BRIGHT)


def stages():
    h = 470
    img = panel(h, [(W // 2, 0, 400, 0.35)])
    d = ImageDraw.Draw(img)
    names = ["Seedling", "Vegetative", "Pre-flower", "Flowering", "Ripe"]
    notes = ["sow a seed or clone", "18/6 keeps it here", "flip to 12/12", "males drop pollen", "harvest window"]
    sprites = [plant(0), plant(9), plant(10), plant(11), plant(12)]
    xs = [140, 390, 640, 890, 1140]
    base = 330
    for i, (sp, x) in enumerate(zip(sprites, xs)):
        paste_bottom(img, scaled(sp, 1.15), x, base)
        if i < 4:
            arrow(img, x + 75, xs[i + 1] - 75, base - 60)
    for n, note, x in zip(names, notes, xs):
        d.text((x, base + 45), n, font=font("Black", 34), fill=TEXT, anchor="mm")
        d.text((x, base + 88), note, font=font("Medium", 24), fill=MUTED, anchor="mm")
    save(img, "stages.png")


def strains():
    h = 470
    img = panel(h, [(W // 2, 0, 400, 0.35)])
    d = ImageDraw.Draw(img)
    cards = [(plant(4), "Indica", "short, bushy, heavy"), (plant(8), "Sativa", "tall, airy, uplifting"),
             (plant(12), "Hybrid", "a bit of both"), (plant(245), "Male", "pollen, not buds")]
    xs = [170, 490, 810, 1110]
    for (sp, n, note), x in zip(cards, xs):
        paste_bottom(img, scaled(sp, 1.2), x, 330)
        d.text((x, 375), n, font=font("Black", 36), fill=TEXT if n != "Male" else SOFT, anchor="mm")
        d.text((x, 418), note, font=font("Medium", 24), fill=MUTED, anchor="mm")
    save(img, "strains.png")


def lights():
    h = 640
    img = panel(h, [(W // 2, 0, 420, 0.4)])
    d = ImageDraw.Draw(img)
    d.text((W // 2, 52), "Every lamp lights a round zone and sets a quality ceiling", font=font("Bold", 30),
           fill=SOFT, anchor="mm")
    lamps = [("GrowLampBasic", "Basic", "2 tiles", "85"), ("GrowLampPro", "Pro", "2.5 tiles", "100"),
             ("GrowLampLargeBasic", "Large Basic", "3 tiles", "85"), ("GrowLampLargePro", "Large Pro", "4 tiles", "100"),
             ("GrowFloodBasic", "Flood", "3.5 tiles", "85"), ("GrowFloodPro", "Pro Flood", "4.5 tiles", "100")]
    cw, gap = 190, 14
    x0 = (W - (cw * 6 + gap * 5)) // 2
    for i, (ic, n, reach, cap) in enumerate(lamps):
        x = x0 + i * (cw + gap)
        rounded(img, (x, 90, x + cw, 330), 18, (52, 24, 86, 255), outline=PANEL_EDGE + (255,), width=2)
        im = icon(ic, 3)
        img.alpha_composite(im, (x + cw // 2 - im.width // 2, 104))
        d.text((x + cw // 2, 222), n, font=font("Black", 26), fill=TEXT, anchor="mm")
        d.text((x + cw // 2, 260), reach, font=font("Medium", 22), fill=MUTED, anchor="mm")
        d.text((x + cw // 2, 298), "ceiling " + cap, font=font("Bold", 22), fill=BRIGHT, anchor="mm")
    d.text((70, 362), "Light timers", font=font("Black", 32), fill=TEXT)
    d.text((300, 368), "sun = 70 · no timer runs 24/0 and holds plants in veg", font=font("Medium", 22), fill=MUTED)
    rows = [("18/6  veg", 6, 24), ("12/12  flower", 6, 18)]
    bx0, bx1 = 300, 1200
    for r, (label, on, off) in enumerate(rows):
        y = 430 + r * 80
        d.text((70, y + 20), label, font=font("Bold", 28), fill=TEXT, anchor="lm")
        rounded(img, (bx0, y, bx1, y + 40), 12, (20, 10, 32, 255), outline=PANEL_EDGE + (255,), width=2)
        a = bx0 + (bx1 - bx0) * on / 24
        b = bx0 + (bx1 - bx0) * off / 24
        rounded(img, (int(a), y + 4, int(b), y + 36), 10, BRIGHT + (255,))
    for hr in (0, 6, 12, 18, 24):
        x = bx0 + (bx1 - bx0) * hr / 24
        d.text((x, 595), "%02d:00" % (hr % 24), font=font("Medium", 20), fill=MUTED, anchor="mm")
    save(img, "lights.png")


def hydro_cards():
    h = 660
    img = panel(h, [(W // 2, 0, 420, 0.4)])
    d = ImageDraw.Draw(img)
    cards = [
        ("DWC", [(plant(379), 1.0)], ["15 L bucket reservoir", "Air pump needs power", "Yield ×1.3", "Care penalties ×0.75",
                                      "Quality up to 100"]),
        ("RDWC", [(hydro(113), 0.9), (hydro(7), 1.0)], ["40 L + 20 L per site", "Up to 6 sites per control",
                                                         "Yield ×1.4", "Care penalties ×0.6", "Top Shelf: up to 115"]),
        ("Ebb & Flow", [(hydro(128), 1.0), (hydro(234), 0.9)], ["60 L flood reservoir", "Up to 12 sites, rockwool",
                                                                 "Yield ×1.2", "Root rot ×0.25", "Flood timer automates"]),
    ]
    cw, gap = 380, 30
    x0 = (W - (cw * 3 + gap * 2)) // 2
    for i, (name, sprites, lines) in enumerate(cards):
        x = x0 + i * (cw + gap)
        rounded(img, (x, 30, x + cw, h - 30), 22, (52, 24, 86, 255), outline=BRIGHT + (255,), width=3)
        d.text((x + cw // 2, 78), name, font=font("Black", 40), fill=TEXT, anchor="mm")
        if len(sprites) == 1:
            paste_bottom(img, scaled(sprites[0][0], sprites[0][1] * 1.3), x + cw // 2, 372)
        else:
            paste_bottom(img, scaled(sprites[0][0], sprites[0][1] * 1.2), x + cw // 2 - 90, 372)
            paste_bottom(img, scaled(sprites[1][0], sprites[1][1] * 1.2), x + cw // 2 + 80, 372)
        for j, line in enumerate(lines):
            y = 412 + j * 42
            d.ellipse((x + 34, y - 6, x + 46, y + 6), fill=BRIGHT)
            d.text((x + 60, y), line, font=font("Medium", 25), fill=TEXT, anchor="lm")
    save(img, "hydro.png")


def cure_flow():
    h = 430
    img = panel(h, [(W // 2, 0, 420, 0.35)])
    d = ImageDraw.Draw(img)
    steps = [("WetIndicaPlant", "Harvest", "wet whole plant"), ("DryingRack", "Dry", "~48 h on a rack"),
             ("DriedIndicaPlant", "Trim", "scissors or knife"), ("CannabisBud", "Buds", "named by quality"),
             ("CuringJar", "Cure", "6 days, burp it"), ("Joint", "Enjoy", "up to +10%")]
    xs = [120 + i * 208 for i in range(6)]
    for i, ((ic, n, note), x) in enumerate(zip(steps, xs)):
        rounded(img, (x - 78, 60, x + 78, 216), 24, (74, 30, 128, 255), outline=BRIGHT + (255,), width=3)
        im = icon(ic, 4)
        img.alpha_composite(im, (x - im.width // 2, 138 - im.height // 2))
        d.text((x, 262), n, font=font("Black", 34), fill=TEXT, anchor="mm")
        d.text((x, 304), note, font=font("Medium", 22), fill=MUTED, anchor="mm")
        if i < 5:
            arrow(img, x + 84, xs[i + 1] - 84, 138)
    d.text((W // 2, 372), "Warm air and a fan dry faster · damp, rain and an unburped jar grow mold",
           font=font("Medium", 24), fill=SOFT, anchor="mm")
    save(img, "curing.png")


def skill_ladder():
    tiers = [("0", "Stage and water, roughly"), ("2", "Exact stage, hours left, water %, last feed, reservoir"),
             ("3", "Strain, sex, light source and cycle, roots and root rot"),
             ("5", "Health, stress, warnings, root rot trend"), ("7", "Harvest window, pollinated, hermie signs"),
             ("9", "Generation and genetics"), ("10", "Expected quality")]
    h = 110 + len(tiers) * 64
    img = panel(h, [(0, h // 2, 300, 0.35)])
    d = ImageDraw.Draw(img)
    d.text((W // 2, 52), "What Inspect shows at each Agriculture level", font=font("Bold", 30), fill=SOFT, anchor="mm")
    for i, (lvl, what) in enumerate(tiers):
        y = 100 + i * 64
        t = i / (len(tiers) - 1)
        col = tuple(int(PRIMARY[k] + (BRIGHT[k] - PRIMARY[k]) * t) for k in range(3))
        rounded(img, (60, y, 150, y + 50), 14, col + (255,))
        d.text((105, y + 25), lvl, font=font("Black", 30), fill=(20, 8, 34), anchor="mm")
        # Bars grow with the level but always fit their text.
        need = text_size(font("Medium", 25), what)[0] + 50
        bar_w = max(need, 300 + int(760 * (i + 1) / len(tiers)))
        rounded(img, (170, y, 170 + bar_w, y + 50), 14, (52, 24, 86, 255), outline=PANEL_EDGE + (255,), width=2)
        d.text((192, y + 25), what, font=font("Medium", 25), fill=TEXT, anchor="lm")
    save(img, "skill.png")


def gear():
    items = [("GrowBagSmall", "Grow bags"), ("CannabisSeed", "Seeds"), ("VegNutrients", "Veg food"),
             ("BloomNutrients", "Bloom food"), ("GrowLampPro", "Grow lamps"), ("LightTimer", "Light timer"),
             ("DWCBucket", "DWC bucket"), ("RDWCControl", "RDWC"), ("FloodTable", "Flood table"),
             ("RockwoolCube", "Rockwool"), ("ClayPebbles", "Clay pebbles"), ("CloningDome", "Cloning dome"),
             ("RootingGel", "Rooting gel"), ("DryingRack", "Drying rack"), ("DryingFan", "Drying fan"),
             ("CuringBarrel", "Curing barrel"), ("RollingPapers", "Papers"), ("SmokingPipe", "Pipe")]
    cols, cw, ch = 6, 196, 170
    rows = (len(items) + cols - 1) // cols
    h = 40 + rows * (ch + 14) + 26
    img = panel(h, [(W // 2, h, 420, 0.3)])
    d = ImageDraw.Draw(img)
    x0 = (W - (cols * cw + (cols - 1) * 12)) // 2
    for i, (ic, label) in enumerate(items):
        r, c = divmod(i, cols)
        x, y = x0 + c * (cw + 12), 34 + r * (ch + 14)
        rounded(img, (x, y, x + cw, y + ch), 18, (52, 24, 86, 255), outline=PANEL_EDGE + (255,), width=2)
        im = icon(ic, 3)
        img.alpha_composite(im, (x + cw // 2 - im.width // 2, y + 18))
        d.text((x + cw // 2, y + 140), label, font=font("Bold", 24), fill=TEXT, anchor="mm")
    save(img, "gear.png")


banner()
for args in HEADERS:
    header(*args)
stages()
strains()
lights()
hydro_cards()
cure_flow()
skill_ladder()
gear()
