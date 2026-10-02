"""
draw_placeholders.py -- Dazed Dank placeholder art.

Draws, procedurally:
  * plant sprites: one shared seedling, then Indica / Sativa / Hybrid for
    Vegetative, PreFlower, Flowering and Ripe (13 healthy sprites), plus the
    four condition sets vanilla farming asks for (unhealthy, dying, dead,
    trampled) derived from them -- 65 cells of 128x256, the size of vanilla
    B42 tile sprites.
  * item icons for every item in CannabisItems.txt.

Everything is drawn at 4x and shrunk, which gives clean anti-aliased edges.
Re-run any time; the output is deterministic (fixed random seed).

    python tools/draw_placeholders.py out_dir

Writes:
  out_dir/cells/          the 65 cells + manifest.json for pz-sprite-forge
  out_dir/icons/          Item_*.png icons
  out_dir/preview.png     everything on one sheet for checking by eye
"""

import json
import math
import zlib
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

S = 4                      # supersampling factor
CELL_W, CELL_H = 128, 256  # vanilla 2x tile cell
BASE = (64, 226)           # where the stem meets the soil, in 1x cell pixels

SHEET = "dazeddank_plants_01"

# ---------------------------------------------------------------------------
# Plant shapes. Heights/widths are 1x pixels at full size (Ripe).
# ---------------------------------------------------------------------------

TYPES = {
    #            height  width  leaflets  leaflet  internode  leaf colour      dark colour
    "Indica": dict(h=92,  w=112, fingers=7, thin=0.30, nodes=6, leaf=(52, 102, 38), dark=(28, 62, 24),
                   bud=(150, 178, 92), purple=True),
    "Hybrid": dict(h=122, w=96,  fingers=7, thin=0.22, nodes=7, leaf=(66, 128, 44), dark=(34, 76, 28),
                   bud=(165, 190, 96), purple=False),
    "Sativa": dict(h=150, w=78,  fingers=9, thin=0.15, nodes=8, leaf=(92, 152, 52), dark=(46, 92, 32),
                   bud=(180, 200, 104), purple=False),
}

# Fraction of full size at each stage.
STAGE_SCALE = {"Vegetative": 0.45, "PreFlower": 0.78, "Flowering": 1.0, "Ripe": 1.0}

STAGES = ["Seedling", "Vegetative", "PreFlower", "Flowering", "Ripe"]
CONDITIONS = ["sprite", "unhealthySprite", "dyingSprite", "deadSprite", "trampledSprite"]
TYPE_ORDER = ["Indica", "Sativa", "Hybrid"]


def P(x, y):
    """1x cell coordinates -> supersampled canvas coordinates."""
    return (x * S, y * S)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ---------------------------------------------------------------------------
# Soil furrow (vanilla bakes it into every plant sprite)
# ---------------------------------------------------------------------------

def draw_furrow(d, rng):
    cx, cy = BASE
    # A low mound inside the tile's floor diamond (64 wide x 32 tall half-sizes).
    d.ellipse([P(cx - 44, cy - 13), P(cx + 44, cy + 15)], fill=(74, 52, 34))
    d.ellipse([P(cx - 40, cy - 12), P(cx + 40, cy + 10)], fill=(96, 70, 46))
    d.ellipse([P(cx - 30, cy - 9), P(cx + 30, cy + 5)], fill=(110, 82, 54))
    for _ in range(70):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0, 1) ** 0.5
        x = cx + math.cos(a) * 38 * r
        y = cy - 1 + math.sin(a) * 11 * r
        c = rng.choice([(62, 44, 28), (122, 92, 62), (84, 60, 40)])
        d.ellipse([P(x - 0.7, y - 0.5), P(x + 0.7, y + 0.5)], fill=c)


# ---------------------------------------------------------------------------
# Leaves and buds
# ---------------------------------------------------------------------------

def leaflet(d, ox, oy, angle, length, width, col, dark):
    """One pointed, serrated-looking leaflet from (ox, oy) along `angle`."""
    pts_l, pts_r = [], []
    steps = 10
    ca, sa = math.cos(angle), math.sin(angle)
    for i in range(steps + 1):
        t = i / steps
        # widest at ~40% of the length, pointed at the tip
        w = width * math.sin(math.pi * min(1.0, t * 1.15)) * (1 - t) ** 0.3
        if i % 2 and 0 < t < 0.95:
            w *= 1.18                                     # serration
        px, py = ox + ca * length * t, oy + sa * length * t
        pts_l.append((px - sa * w, py + ca * w))
        pts_r.append((px + sa * w, py - ca * w))
    # two-tone: the upper half catches light
    d.polygon([P(*p) for p in pts_l + [(ox + ca * length, oy + sa * length)] + [(ox, oy)]], fill=dark)
    d.polygon([P(*p) for p in pts_r + [(ox + ca * length, oy + sa * length)] + [(ox, oy)]], fill=col)
    d.line([P(ox, oy), P(ox + ca * length * 0.92, oy + sa * length * 0.92)],
           fill=mix(col, (210, 230, 160), 0.35), width=max(1, S // 2))


def fan_leaf(d, ox, oy, direction, size, spec, col, dark, droop=0.0):
    """A palmate fan leaf: `fingers` leaflets spread around `direction`."""
    n = spec["fingers"]
    spread = math.radians(150)
    for i in range(n):
        f = i / (n - 1) - 0.5                       # -0.5 .. 0.5
        ang = direction + f * spread + droop * 0.6
        length = size * (1.0 - abs(f) * 1.1)        # middle finger longest
        if length <= 1:
            continue
        leaflet(d, ox, oy, ang, length, length * spec["thin"] * 0.5, col, dark)


def bud(d, x, y, length, width, spec, rng, ripe, frost):
    """A cola growing up from (x, y): a tapered body covered in calyxes,
    small sugar-leaf tips poking out, and pistil hairs."""
    base = spec["bud"]
    shadow = mix(base, (40, 70, 30), 0.45)
    purple = (112, 86, 116)
    # body: a tapered spindle, widest a third of the way up
    left, right = [], []
    steps = 12
    for i in range(steps + 1):
        t = i / steps
        w = width * (0.75 + 0.5 * math.sin(math.pi * min(1, t * 1.5))) * (1 - t) ** 0.6 * 0.8
        left.append((x - w, y - t * length))
        right.append((x + w, y - t * length))
    d.polygon([P(*p) for p in left + right[::-1]], fill=shadow)
    # calyx texture, dense
    n = int(length * 1.6)
    for i in range(n):
        t = rng.uniform(0, 0.95)
        w = width * (0.75 + 0.5 * math.sin(math.pi * min(1, t * 1.5))) * (1 - t) ** 0.6 * 0.75
        bx = x + rng.uniform(-w, w)
        by = y - t * length
        r = 0.9 + rng.uniform(0, 1.0) * (1 - t * 0.5)
        c = mix(base, (230, 240, 190), rng.uniform(0, 0.25)) if bx > x else mix(base, shadow, 0.35)
        if ripe and spec["purple"] and rng.random() < 0.18:
            c = mix(purple, c, 0.35)
        d.ellipse([P(bx - r, by - r), P(bx + r, by + r)], fill=c)
    # sugar-leaf tips poking out of the cola
    for i in range(int(length / 5)):
        t = rng.uniform(0.1, 0.8)
        side = rng.choice((-1, 1))
        w = width * 0.55 * (1 - t) ** 0.6
        leaflet(d, x + side * w * 0.6, y - t * length, math.radians(-90 + side * rng.uniform(40, 70)),
                rng.uniform(3, 5), 0.9, spec["leaf"], spec["dark"])
    # pistils: white while flowering, orange/amber when ripe
    for i in range(int(length * 1.2)):
        t = rng.uniform(0, 1)
        w = width * 0.6 * (1 - t) ** 0.6
        hx, hy = x + rng.uniform(-w, w), y - t * length
        hc = rng.choice([(214, 128, 52), (190, 100, 40)]) if ripe else (238, 238, 226)
        d.line([P(hx, hy), P(hx + rng.uniform(-1.4, 1.4), hy - rng.uniform(0.6, 1.6))],
               fill=hc, width=max(1, S // 2))
    if frost:
        for i in range(int(length * 1.5)):
            t = rng.uniform(0, 1)
            w = width * 0.55 * (1 - t) ** 0.6
            d.point(P(x + rng.uniform(-w, w), y - t * length), fill=(236, 240, 228))


# ---------------------------------------------------------------------------
# A whole plant
# ---------------------------------------------------------------------------

def draw_plant(type_name, stage, seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = BASE

    if stage == "Seedling":
        spec = TYPES["Hybrid"]
        d.line([P(cx, cy - 1), P(cx, cy - 10)], fill=(96, 140, 60), width=S)
        # two round cotyledons + the first tiny serrated pair
        for side in (-1, 1):
            d.ellipse([P(cx + side * 5 - 3, cy - 9), P(cx + side * 5 + 3, cy - 6)], fill=(110, 160, 70))
        for side in (-1, 1):
            leaflet(d, cx, cy - 10, math.radians(-90 + side * 35), 7, 1.8, (84, 146, 54), (52, 100, 36))
        return img

    spec = TYPES[type_name]
    scale = STAGE_SCALE[stage]
    H, W = spec["h"] * scale, spec["w"] * scale
    col, dark = spec["leaf"], spec["dark"]
    if stage == "Ripe":
        # late flower: fan leaves start to fade (realistic senescence)
        col, dark = mix(col, (150, 150, 60), 0.30), mix(dark, (90, 80, 30), 0.30)
    top = cy - H

    # main stem
    d.line([P(cx, cy - 2), P(cx, top + 4)], fill=(78, 112, 46), width=int(S * 1.6))

    nodes = max(3, int(spec["nodes"] * (0.6 + 0.4 * scale)))
    leaves = []                                    # (depth, draw-call)
    tips = []                                      # branch tips for buds
    for k in range(nodes):
        t = (k + 1) / (nodes + 0.5)                # 0 bottom .. 1 top
        ny = cy - 6 - (H - 10) * t
        # envelope: Indica stays wide, Sativa tapers like a spruce
        reach = W * 0.5 * (1 - t * (0.55 if type_name == "Indica" else 0.75))
        size = max(7.0, reach * 1.0) * (0.8 + rng.uniform(0, 0.25))
        for side in (-1, 1):
            # branch out to the side and a little up
            bx = cx + side * reach * 0.55
            by = ny - reach * 0.18
            d.line([P(cx, ny), P(bx, by)], fill=(74, 106, 44), width=int(S * 1.1))
            direction = math.radians(-90 + side * rng.uniform(35, 60))
            depth = rng.random()
            leaves.append((depth, bx, by, direction, size))
            # a second leaf off the same branch, pointing out and down a bit
            leaves.append((rng.random(), (cx + bx) / 2, (ny + by) / 2,
                           math.radians(-90 + side * rng.uniform(65, 95)), size * 0.8))
            tips.append((bx, by, t))
        # a front/back leaf at the node fills the silhouette out
        leaves.append((rng.random(), cx + rng.uniform(-3, 3), ny, math.radians(-90 + rng.uniform(-20, 20)),
                       size * 0.7))

    # back-to-front, back leaves darker
    for depth, bx, by, direction, size in sorted(leaves):
        shade = 0.55 + 0.45 * depth
        fan_leaf(d, bx, by, direction, size, spec, mix(dark, col, shade), mix((16, 36, 14), dark, shade))

    # top fan leaves
    fan_leaf(d, cx, top + 8, math.radians(-90), max(8, W * 0.22), spec, col, dark)

    # flowers
    if stage in ("PreFlower", "Flowering", "Ripe"):
        ripe = stage == "Ripe"
        if stage == "PreFlower":
            # first white pistils at the top nodes
            for bx, by, t in tips:
                if t > 0.5:
                    for _ in range(3):
                        hx, hy = bx + rng.uniform(-2, 2), by + rng.uniform(-2, 1)
                        d.line([P(hx, hy), P(hx, hy - 1.5)], fill=(240, 240, 230), width=max(1, S // 2))
        else:
            fat = 1.25 if ripe else 1.0
            w_main = (10 if type_name == "Indica" else 7.5 if type_name == "Hybrid" else 6) * fat
            l_main = H * (0.36 if type_name == "Indica" else 0.34 if type_name == "Hybrid" else 0.32)
            # side colas spread across the top of the canopy, following its
            # outline: Indica's canopy is flat and wide, Sativa's is a spear.
            k = {"Indica": 6, "Hybrid": 4, "Sativa": 4}[type_name]
            drop = {"Indica": 0.22, "Hybrid": 0.32, "Sativa": 0.36}[type_name]
            spread = {"Indica": 0.40, "Hybrid": 0.34, "Sativa": 0.26}[type_name]
            for i in range(k):
                fx = (i / (k - 1) - 0.5) * 2                 # -1 .. 1
                if abs(fx) < 0.2:
                    continue                                  # main cola sits there
                bx = cx + fx * W * spread + rng.uniform(-2, 2)
                by = top + l_main * 0.9 + H * drop * abs(fx) ** 1.2
                # a little branch carrying the cola
                d.line([P(cx + fx * W * 0.12, by + 10), P(bx, by + 2)], fill=(74, 106, 44), width=S)
                bud(d, bx, by + 2, l_main * (0.75 - 0.3 * abs(fx)), w_main * (0.8 - 0.2 * abs(fx)),
                    spec, rng, ripe, frost=ripe)
            # the main cola tops the stem
            bud(d, cx, top + l_main * 0.75, l_main, w_main, spec, rng, ripe, frost=True)
    return img


# ---------------------------------------------------------------------------
# Condition variants (vanilla asks for these by name)
# ---------------------------------------------------------------------------

def recolor(img, toward, amount, sat=1.0, bright=1.0):
    """Shift the plant's colours toward `toward`, keeping alpha."""
    rgb = img.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(sat)
    rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    tint = Image.new("RGB", rgb.size, toward)
    rgb = Image.blend(rgb, tint, amount)
    out = rgb.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out


def variant(plant, condition, furrow):
    """Soil + the plant layer recoloured for its condition."""
    if condition == "sprite":
        pass
    elif condition == "unhealthySprite":
        plant = recolor(plant, (190, 170, 60), 0.30, sat=0.85)
    elif condition == "dyingSprite":
        plant = recolor(plant, (150, 110, 50), 0.50, sat=0.6, bright=0.9)
    elif condition == "deadSprite":
        plant = recolor(plant, (110, 80, 45), 0.70, sat=0.3, bright=0.8)
    else:  # trampledSprite: flattened, brown, mostly gone
        plant = recolor(plant, (110, 85, 50), 0.65, sat=0.35, bright=0.85)
        w, h = plant.size
        squashed = plant.resize((w, h // 3), Image.LANCZOS)
        plant = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        # keep the base of the flattened plant on the furrow
        plant.alpha_composite(squashed, (0, BASE[1] * S - squashed.size[1] + 4 * S))
    out = furrow.copy()
    out.alpha_composite(plant)
    return out


# ---------------------------------------------------------------------------
# Item icons (32x32)
# ---------------------------------------------------------------------------

def icon_canvas():
    return Image.new("RGBA", (32 * S, 32 * S), (0, 0, 0, 0))


def Q(x, y):
    return (x * S, y * S)


def icon_seed():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    for (x, y, a) in [(10, 18, -20), (19, 12, 15), (21, 22, 40)]:
        d.ellipse([Q(x - 5, y - 4), Q(x + 5, y + 4)], fill=(70, 56, 38), outline=(36, 28, 18), width=S)
        d.line([Q(x - 3, y - 1), Q(x + 3, y + 1)], fill=(128, 110, 80), width=S)
        d.line([Q(x - 2, y + 2), Q(x + 2, y + 3)], fill=(110, 92, 64), width=S)
    return img


def icon_cutting():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.line([Q(16, 30), Q(16, 12)], fill=(86, 124, 52), width=2 * S)
    d.line([Q(14, 30), Q(18, 27)], fill=(160, 190, 110), width=S)       # angled cut
    spec = dict(TYPES["Hybrid"])
    for ang in (-130, -50):
        leaflet_on(d, 16, 14, ang, 11)
    leaflet_on(d, 16, 12, -90, 13)
    return img


def icon_rooted_cutting():
    img = icon_cutting(); d = ImageDraw.Draw(img)
    rng = random.Random(11)
    # pale roots spreading from the cut end
    for _ in range(7):
        x, y = 16.0, 25.0
        ang = math.radians(rng.uniform(25, 155))
        for _ in range(6):
            nx = x + math.cos(ang) * rng.uniform(1.4, 2.2)
            ny = y + math.sin(ang) * rng.uniform(0.8, 1.4)
            d.line([Q(x, y), Q(nx, ny)], fill=(236, 228, 200), width=S)
            x, y = nx, ny
            ang += math.radians(rng.uniform(-30, 30))
    return img


def leaflet_on(d, x, y, ang_deg, length):
    a = math.radians(ang_deg)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for i in range(9):
        t = i / 8
        w = length * 0.18 * math.sin(math.pi * min(1, t * 1.1)) * (1 - t) ** 0.3
        pts.append((x + ca * length * t - sa * w, y + sa * length * t + ca * w))
    for i in range(8, -1, -1):
        t = i / 8
        w = length * 0.18 * math.sin(math.pi * min(1, t * 1.1)) * (1 - t) ** 0.3
        pts.append((x + ca * length * t + sa * w, y + sa * length * t - ca * w))
    d.polygon([Q(*p) for p in pts], fill=(70, 140, 50), outline=(30, 70, 24))


def icon_bottle(body, cap, label, small=False):
    img = icon_canvas(); d = ImageDraw.Draw(img)
    if small:
        d.rounded_rectangle([Q(11, 12), Q(21, 29)], radius=2 * S, fill=body, outline=(40, 40, 40), width=S)
        d.rectangle([Q(13, 7), Q(19, 12)], fill=cap, outline=(30, 30, 30), width=S)
        d.rectangle([Q(12, 17), Q(20, 24)], fill=label)
    else:
        # jug with handle
        d.rounded_rectangle([Q(7, 10), Q(25, 30)], radius=3 * S, fill=body, outline=(30, 30, 30), width=S)
        d.rectangle([Q(13, 5), Q(19, 10)], fill=cap, outline=(30, 30, 30), width=S)
        d.arc([Q(18, 9), Q(28, 19)], 270, 90, fill=(30, 30, 30), width=2 * S)
        d.rectangle([Q(9, 16), Q(23, 25)], fill=label)
    return img


def icon_nutrients(colour):
    img = icon_bottle((236, 236, 228), (40, 40, 40), colour)
    d = ImageDraw.Draw(img)
    leaflet_on(d, 16, 23, -90, 6)
    return img


def icon_rooting_gel():
    img = icon_bottle((240, 150, 60), (230, 230, 230), (250, 236, 200), small=True)
    return img


def icon_dome():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.rectangle([Q(3, 22), Q(29, 28)], fill=(30, 30, 30))
    for x in (8, 13, 18, 23):
        d.line([Q(x, 22), Q(x, 16)], fill=(80, 140, 50), width=S)
        d.ellipse([Q(x - 2, 14), Q(x + 2, 17)], fill=(90, 160, 60))
    # the clear dome goes on its own layer and is blended over the seedlings
    glass = icon_canvas(); g = ImageDraw.Draw(glass)
    g.chord([Q(3, 6), Q(29, 38)], 180, 360, fill=(200, 230, 240, 70), outline=(150, 190, 210, 255), width=S)
    g.line([Q(9, 11), Q(12, 9)], fill=(255, 255, 255, 200), width=S)
    img.alpha_composite(glass)
    return img


def icon_wet_plant():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    # whole plant hung upside down: stem at top, colas hanging
    d.line([Q(16, 2), Q(16, 26)], fill=(86, 118, 50), width=2 * S)
    d.line([Q(12, 3), Q(20, 3)], fill=(150, 120, 80), width=2 * S)    # twine
    rng = random.Random(7)
    for bx, by, l in [(16, 28, 10), (10, 22, 7), (22, 22, 7), (8, 14, 5), (24, 14, 5)]:
        d.line([Q(16, by - l), Q(bx, by - l + 2)], fill=(86, 118, 50), width=S)
        for i in range(5):
            y = by - l + 2 + i * l / 5
            r = 2.2
            d.ellipse([Q(bx - r, y - r), Q(bx + r, y + r)], fill=(130, 170, 80))
            hx = bx + rng.uniform(-2, 2)
            d.point(Q(hx, y), fill=(240, 240, 230))
    for ang in (-150, -30):
        leaflet_on(d, 16, 8, ang, 9)
    return img


ICONS = {
    "CannabisSeed": icon_seed,
    "CannabisCutting": icon_cutting,
    "RootedCannabisCutting": icon_rooted_cutting,
    "RootingGel": icon_rooting_gel,
    "VegNutrients": lambda: icon_nutrients((70, 150, 60)),
    "BloomNutrients": lambda: icon_nutrients((160, 70, 150)),
    "CloningDome": icon_dome,
    "WetCannabisPlant": icon_wet_plant,
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def shrink(img, size):
    return img.resize(size, Image.LANCZOS)


def sprite_slot(stage, type_name):
    """Index of a healthy sprite inside one condition block of 13."""
    if stage == "Seedling":
        return 0
    return 1 + TYPE_ORDER.index(type_name) * 4 + (STAGES.index(stage) - 1)


def main(out):
    out = Path(out)
    cells_dir = out / "cells"
    icons_dir = out / "icons"
    cells_dir.mkdir(parents=True, exist_ok=True)
    icons_dir.mkdir(parents=True, exist_ok=True)

    # bare furrow, shared by every variant so the soil never changes colour
    furrow = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    draw_furrow(ImageDraw.Draw(furrow), random.Random(1))

    plants = [None] * 13                          # plant layers, no soil
    for stage in STAGES:
        for t in (["Hybrid"] if stage == "Seedling" else TYPE_ORDER):
            seed = zlib.crc32(f"{t}/{stage}".encode())
            plants[sprite_slot(stage, t)] = draw_plant(t, stage, seed)

    manifest = {"sheet": SHEET, "cell": [CELL_W, CELL_H], "scale": "2x",
                "facings": ["S"], "cells": []}
    index = 0
    previews = []
    for cond in CONDITIONS:
        for slot in range(13):
            img = variant(plants[slot], cond, furrow)
            small = shrink(img, (CELL_W, CELL_H))
            name = f"{index:03d}_{cond}_{slot}.png"
            small.save(cells_dir / name)
            manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0})
            previews.append(small)
            index += 1
    (cells_dir / "manifest.json").write_text(json.dumps(manifest, indent=1))

    icons = []
    for name, fn in ICONS.items():
        ic = shrink(fn(), (32, 32))
        ic.save(icons_dir / f"Item_{name}.png")
        icons.append(ic)

    # preview: 13 columns x 5 condition rows at 1x on a grass background,
    # plus the healthy row again at 2x and the icons at 4x
    pw = 13 * CELL_W
    sheet = Image.new("RGBA", (pw, 5 * CELL_H + 2 * CELL_H + 160), (58, 74, 40, 255))
    for i, im in enumerate(previews):
        sheet.alpha_composite(im, ((i % 13) * CELL_W, (i // 13) * CELL_H))
    big_row = Image.new("RGBA", (pw, 2 * CELL_H), (58, 74, 40, 255))
    order = [0, 1, 2, 3, 4, 9, 10, 11, 12, 5, 6, 7, 8]           # seedling, Indica, Hybrid, Sativa
    for j, slot in enumerate(order):
        im = previews[slot]
        big_row.alpha_composite(im, (j * CELL_W, CELL_H // 2))
    sheet.alpha_composite(big_row, (0, 5 * CELL_H))
    for i, ic in enumerate(icons):
        sheet.alpha_composite(ic.resize((128, 128), Image.NEAREST), (16 + i * 150, 7 * CELL_H + 16))
    sheet.save(out / "preview.png")
    print(f"wrote {index} cells, {len(icons)} icons, preview")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/art")
