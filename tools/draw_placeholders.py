"""Draws the placeholder sprites and item icons procedurally, then writes cells and a manifest for pz-sprite-forge.
Run: python tools/draw_placeholders.py out_dir (deterministic, safe to re-run).
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
HYDRO_SHEET = "dazeddank_hydro_01"   # second sheet: the game refuses sheets over 512 tiles
MAX_SHEET_TILES = 512

# ---------------------------------------------------------------------------
# Plant shapes. Heights/widths are 1x pixels at full size (Ripe).
# ---------------------------------------------------------------------------

TYPES = {
    # height width leaflets leaflet internode leaf colour dark colour
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
    # A low mound inside the tile's floor diamond (64 wide x 32 tall
    # half-sizes).
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
    """A cola growing up from (x, y): a tapered body covered in calyxes, small sugar-leaf tips poking out, and pistil hairs."""
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

BLENDER_PLANTS = Path(__file__).parent / "blender" / "plants"


def draw_plant(type_name, stage, seed):
    """Uses the Blender render for this plant when present, else the procedural drawing."""
    slot = sprite_slot(stage, type_name)
    path = BLENDER_PLANTS / f"slot_{slot:02d}.png"
    if path.exists():
        return Image.open(path).convert("RGBA").resize((CELL_W * S, CELL_H * S), Image.LANCZOS)
    return draw_plant_procedural(type_name, stage, seed)


MALE_STAGES = ["PreFlower", "Flowering", "Ripe"]


def draw_male(type_name, stage, seed):
    """A male plant: the Blender render when there is one, else the type's veg plant stretched taller and hung with pollen sacs.
    Pre-flower shows a few small sacs, flowering many, and ripe has some split open and dusted with pollen."""
    rendered = BLENDER_PLANTS / f"male_{type_name}_{stage}.png"
    if rendered.exists():
        return Image.open(rendered).convert("RGBA").resize((CELL_W * S, CELL_H * S), Image.LANCZOS)
    rng = random.Random(seed)
    base = draw_plant(type_name, "Vegetative", seed)
    bbox = base.getbbox()
    if not bbox:
        return base
    # size from the female at the same stage: as wide as 3/4 of her, and taller
    female = draw_plant(type_name, stage, seed).getbbox() or bbox
    fw, fh = female[2] - female[0], female[3] - female[1]
    stretch = {"PreFlower": 1.0, "Flowering": 1.12, "Ripe": 1.15}[stage]
    crop = base.crop(bbox)
    w, h = crop.size
    nw, nh = int(fw * 0.75), int(fh * stretch)
    crop = crop.resize((nw, nh), Image.LANCZOS)
    # thin the foliage a little: males are leggier and sparser
    alpha = crop.getchannel("A")
    holes = Image.new("L", crop.size, 255)
    hd = ImageDraw.Draw(holes)
    for _ in range(int(nw * nh / (90 * S * S))):
        x, y = rng.randrange(nw), rng.randrange(int(nh * 0.85))
        r = rng.uniform(1.5, 3.0) * S
        hd.ellipse([x - r, y - r, x + r, y + r], fill=0)
    crop.putalpha(Image.composite(alpha, Image.new("L", crop.size, 0), holes))
    img = Image.new("RGBA", base.size, (0, 0, 0, 0))
    bx = bbox[0] + (w - nw) // 2
    by = bbox[3] - nh
    img.alpha_composite(crop, (bx, max(0, by)))
    d = ImageDraw.Draw(img)
    # pollen sac clusters on the upper two thirds, sitting where there is foliage
    clusters = {"PreFlower": 9, "Flowering": 22, "Ripe": 24}[stage]
    sac, sac_dark = (148, 188, 92), (70, 104, 44)
    placed = 0
    for _ in range(clusters * 25):
        if placed >= clusters:
            break
        x = rng.randrange(bx, bx + nw)
        y = rng.randrange(max(0, by), max(1, by) + int(nh * 0.7))
        if img.getpixel((x, y))[3] < 200:
            continue
        placed += 1
        for _ in range(rng.randint(3, 6)):
            ox, oy = x + rng.uniform(-3, 3) * S, y + rng.uniform(-3, 2) * S
            r = (1.4 if stage == "PreFlower" else 2.0) * S
            opened = stage == "Ripe" and rng.random() < 0.45
            fill = (222, 214, 140) if opened else sac
            d.ellipse([ox - r, oy - r, ox + r, oy + r * 1.2], fill=fill, outline=sac_dark)
            if opened:
                for _ in range(3):
                    px, py = ox + rng.uniform(-3, 3) * S, oy + rng.uniform(0, 4) * S
                    d.point((px, py), fill=(240, 220, 90))
    return img


def draw_plant_procedural(type_name, stage, seed):
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
# Grow bags (fabric pots). The plant sits on the soil in the top of the bag,
# so the plant layer is lifted by the bag's height.
# ---------------------------------------------------------------------------

BAGS = {
    "small": dict(r=24, h=26),
    "large": dict(r=34, h=40),
}


BLENDER_FURNITURE = Path(__file__).parent / "blender" / "furniture"


def furniture_render(name):
    """The Blender render for `name` at supersampled size, or None when it has not been rendered."""
    path = BLENDER_FURNITURE / (name + ".png")
    if not path.exists():
        return None
    return Image.open(path).convert("RGBA").resize((CELL_W * S, CELL_H * S), Image.LANCZOS)


def draw_bag(size, soil=True):
    rendered = furniture_render(f"bag_{size}_{'soil' if soil else 'dry'}")
    if rendered is not None:
        return rendered, BAGS[size]["h"]
    spec = BAGS[size]
    r, h = spec["r"], spec["h"]
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    ry = r * 0.36                       # ellipse flattening to match the tile angle
    felt, felt_dark, felt_light = (64, 64, 70), (44, 44, 50), (92, 92, 100)
    top = gy - h
    # body: tapered cylinder (slightly wider at the rim, like a filled fabric
    # pot)
    rim_r = r * 1.06
    d.ellipse([P(cx - r, gy - ry), P(cx + r, gy + ry)], fill=felt_dark)
    d.polygon([P(cx - r, gy), P(cx - rim_r, top), P(cx + rim_r, top), P(cx + r, gy)], fill=felt)
    # shading: darker right side, a couple of fabric seam lines
    d.polygon([P(cx + r * 0.35, gy + ry * 0.9), P(cx + rim_r * 0.35, top + ry * 1.0),
               P(cx + rim_r, top), P(cx + r, gy)], fill=felt_dark)
    for f in (-0.55, -0.1, 0.35):
        d.line([P(cx + r * f, gy + ry * (1 - f * f) ** 0.5), P(cx + rim_r * f, top + ry * 1.06 * (1 - f * f) ** 0.5)],
               fill=felt_light, width=max(1, S // 2))
    d.ellipse([P(cx - r, gy - ry), P(cx + r, gy + ry)], outline=felt_dark, width=max(1, S // 2))
    # handles
    for side in (-1, 1):
        hx = cx + side * rim_r * 0.98
        d.arc([P(hx - 5, top - 3), P(hx + 5, top + 9)], 180 if side < 0 else 270, 270 if side < 0 else 360,
              fill=felt_light, width=S)
        d.line([P(hx, top + 3), P(hx, top + 8)], fill=felt_light, width=S)
    # rim and soil
    d.ellipse([P(cx - rim_r, top - ry * 1.06), P(cx + rim_r, top + ry * 1.06)], fill=felt_light)
    if not soil:
        # unfilled: a flat, empty felt interior (no soil yet)
        d.ellipse([P(cx - rim_r + 2, top - ry * 1.06 + 1.5), P(cx + rim_r - 2, top + ry * 1.06 - 1)], fill=felt_dark)
        return img, h
    d.ellipse([P(cx - rim_r + 2, top - ry * 1.06 + 1.5), P(cx + rim_r - 2, top + ry * 1.06 - 1)], fill=(70, 50, 34))
    rng = random.Random(3 if size == "small" else 4)
    for _ in range(60):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0, 1) ** 0.5
        x = cx + math.cos(a) * (rim_r - 5) * rr
        y = top + math.sin(a) * (ry * 1.06 - 2) * rr
        c = rng.choice([(54, 38, 26), (104, 78, 52), (84, 60, 40)])
        d.ellipse([P(x - 0.7, y - 0.5), P(x + 0.7, y + 0.5)], fill=c)
    return img, h


# Tile properties. solidtrans = blocks walking but not sight (collision for
# bags).
BAG_PROPS = {"solidtrans": ""}
LAMP_NAMES = {"Basic": "Basic Grow Lamp", "Pro": "Pro Grow Lamp",
              "LargeBasic": "Large Basic Grow Lamp", "LargePro": "Large Pro Grow Lamp"}
LAMP_PROPS = {"IsMoveAble": "", "CustomName": "Grow Lamp", "PickUpWeight": "25",
              "Material": "Metal", "CanScrap": ""}

# Placeable grow lights (furniture sprites, one tile each). Four tiers.
LIGHTS = {
    # key reflector half-width, stand height, body, glow
    "Basic":      dict(w=22, h=70,  body=(84, 84, 92),  glow=(255, 214, 120)),
    "Pro":        dict(w=26, h=78,  body=(44, 44, 54),  glow=(255, 245, 235)),
    "LargeBasic": dict(w=38, h=96,  body=(84, 84, 92),  glow=(255, 214, 120)),
    "LargePro":   dict(w=46, h=108, body=(44, 44, 54),  glow=(255, 245, 235)),
}


def draw_light(key):
    """A ceiling-hung lamp: mount plate and cords up high, reflector head hanging below."""
    rendered = furniture_render(f"lamp_{key}")
    if rendered is not None:
        return rendered
    spec = LIGHTS[key]
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = BASE[0]
    w = spec["w"]
    body, glow = spec["body"], spec["glow"]
    dark = mix(body, (0, 0, 0), 0.5)
    ceil_y, top = 30, 84 if "Large" not in key else 80   # ceiling plate, reflector top
    d.rectangle([P(cx - 8, ceil_y - 4), P(cx + 8, ceil_y + 2)], fill=dark)
    for dx in (-w * 0.45, w * 0.45):
        d.line([P(cx + dx * 0.3, ceil_y + 2), P(cx + dx, top)], fill=(30, 30, 30), width=S)
    d.polygon([P(cx - w * 0.55, top), P(cx - w, top - 12), P(cx + w, top - 12), P(cx + w * 0.55, top)],
              fill=body, outline=dark)
    d.polygon([P(cx + 2, top), P(cx + 2, top - 12), P(cx + w, top - 12), P(cx + w * 0.55, top)], fill=dark)
    d.rectangle([P(cx - w * 0.55, top), P(cx + w * 0.55, top + 4)], fill=glow, outline=mix(glow, (0, 0, 0), 0.5))
    if key.endswith("Pro"):
        n = 5 if "Large" in key else 4
        for i in range(n):
            x = cx - w * 0.45 + (w * 0.9) * i / max(1, n - 1)
            d.line([P(x, top), P(x, top + 4)], fill=(255, 255, 255), width=S)
    return img


# Floor-standing flood lights (furniture sprites 234-235, one tile each).
FLOOD_NAMES = {"Basic": "Flood Grow Light", "Pro": "Pro Flood Grow Light"}
FLOODS = {
    # key  head half-width, head count, pole top, body, glow
    "Basic": dict(w=22, heads=1, top=96,  body=(214, 168, 40), glow=(255, 224, 140)),
    "Pro":   dict(w=18, heads=2, top=112, body=(48, 48, 58),   glow=(255, 246, 238)),
}


def draw_flood(key):
    """A tripod flood light standing on the ground: three legs, a pole and a tilted lamp head (two side by side for Pro)."""
    rendered = furniture_render(f"flood_{key}")
    if rendered is not None:
        return rendered
    spec = FLOODS[key]
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    body, glow = spec["body"], spec["glow"]
    dark = mix(body, (0, 0, 0), 0.55)
    metal = (150, 152, 160)
    top = spec["top"]
    # legs splay from the pole to the ground
    for dx in (-26, 26, 0):
        foot = (cx + dx, gy + (0 if dx else 7))
        d.line([P(cx, gy - top * 0.55), P(*foot)], fill=dark, width=3 * S)
    d.line([P(cx, gy - top * 0.55), P(cx, gy - top)], fill=metal, width=3 * S)
    d.rectangle([P(cx - 5, gy - top * 0.62), P(cx + 5, gy - top * 0.55)], fill=dark)
    # lamp heads, tilted slightly down toward the viewer
    heads, w = spec["heads"], spec["w"]
    hh = 26 if heads == 1 else 30
    hy = gy - top
    for i in range(heads):
        hx = cx + (0 if heads == 1 else (-w - 3 if i == 0 else w + 3))
        d.rectangle([P(hx - w, hy - hh), P(hx + w, hy + 2)], fill=body, outline=dark, width=S)
        d.polygon([P(hx + w, hy - hh), P(hx + w + 6, hy - hh + 5), P(hx + w + 6, hy + 7), P(hx + w, hy + 2)], fill=dark)
        d.rectangle([P(hx - w + 4, hy - hh + 4), P(hx + w - 4, hy - 4)], fill=glow, outline=mix(glow, (0, 0, 0), 0.5))
        if key == "Pro":
            for k in range(1, 4):
                x = hx - w + 4 + (2 * w - 8) * k / 4
                d.line([P(x, hy - hh + 4), P(x, hy - 4)], fill=(255, 255, 255), width=S)
    if heads == 2:
        d.rectangle([P(cx - 4, hy - 4), P(cx + 4, hy + 6)], fill=dark)
    return img


FURN_PROPS = {"IsMoveAble": "", "PickUpWeight": "30", "Material": "Metal", "CanScrap": "", "IsLow": "", "CustomName": "Drying Fan"}
BAG_FURN_PROPS = {"IsMoveAble": "", "IsLow": "", "CustomName": "Grow Bag", "PickUpWeight": "15", "Material": "Plastic"}


FACING_ORDER = ["E", "S", "W", "N"]


def multi_props(name, item, facing, grid, extra, count):
    """Tile properties for one tile of a multi-tile item: every tile of every facing carries the same set, with game-style offsets."""
    props = {"IsMoveAble": "", "CustomName": name, "GroupName": "Dazed Dank", "CustomItem": item,
             "Facing": facing, "SpriteGridPos": grid, "MoveType": "Object", "PickUpLevel": "0", "ForceSingleItem": ""}
    here = FACING_ORDER.index(facing)
    for i, f in enumerate(FACING_ORDER):
        props[f + "offset"] = str(count * (i - here))
    props.update(extra)
    return props


RACK_EXTRA = {"PickUpWeight": "40", "Material": "Wood", "solidtrans": "", "container": "crate", "ContainerCapacity": "8"}
LAMP_BAR_EXTRA = {"PickUpWeight": "40", "Material": "Metal", "CanScrap": ""}


def grid_positions(facing, count):
    """Grid positions of a bar's tiles in sprite order: south and north run along x, east and west along y."""
    if facing in ("S", "N"):
        return ["%d,0" % i for i in range(count)]
    return ["0,%d" % i for i in range(count)]


def draw_fan():
    """A pedestal fan: round base, pole, caged blades facing the viewer."""
    rendered = furniture_render("fan")
    if rendered is not None:
        return rendered
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    metal, dark = (170, 172, 178), (70, 72, 80)
    d.ellipse([P(cx - 16, gy - 6), P(cx + 16, gy + 6)], fill=dark)
    d.rectangle([P(cx - 2, gy - 36), P(cx + 2, gy)], fill=metal, outline=dark)
    hy = gy - 52
    d.ellipse([P(cx - 20, hy - 20), P(cx + 20, hy + 20)], fill=(210, 212, 216, 90), outline=dark, width=S)
    for ang in (15, 135, 255):
        a = math.radians(ang)
        d.polygon([P(cx, hy), P(cx + 15 * math.cos(a - 0.45), hy + 15 * math.sin(a - 0.45)),
                   P(cx + 15 * math.cos(a + 0.45), hy + 15 * math.sin(a + 0.45))], fill=(90, 100, 120))
    d.ellipse([P(cx - 3, hy - 3), P(cx + 3, hy + 3)], fill=(30, 30, 36))
    return img


def draw_rack(facing):
    """One face of the two-tile drying rack: returns (first tile, second tile) cells."""
    renders = [furniture_render(f"rack_{facing}{part}") for part in (0, 1)]
    if all(r is not None for r in renders):
        return renders
    cells = []
    wood, dark = (126, 92, 58), (78, 56, 34)
    for part in (0, 1):
        img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        cx, gy = BASE
        sgn = 1 if facing == "S" else -1
        a = (cx - 30, gy - 15 * sgn)      # one edge of the tile, along the rack
        b = (cx + 30, gy + 15 * sgn)
        h = 86
        # Posts only at the rack's two outer ends, so the rail runs unbroken across both tiles.
        outer = a if (part == 0) == (facing == "S") else b
        x, y = outer
        d.polygon([P(x - 2, y), P(x - 2, y - h), P(x + 2, y - h), P(x + 2, y)], fill=wood, outline=dark)
        d.line([P(a[0], a[1] - h), P(b[0], b[1] - h)], fill=wood, width=3 * S)
        d.line([P(a[0], a[1] - h * 0.45), P(b[0], b[1] - h * 0.45)], fill=dark, width=S)
        for t in (0.2, 0.5, 0.8):
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t - h
            d.line([P(x, y), P(x, y + 8)], fill=(60, 60, 60), width=S)
            d.polygon([P(x - 5, y + 8), P(x + 5, y + 8), P(x + 4, y + 36), P(x, y + 44), P(x - 4, y + 36)],
                      fill=(70, 130, 56), outline=(34, 76, 28))
        cells.append(img)
    return cells


def draw_barrel():
    """An oak curing barrel standing on end: staves, two iron hoops and a lid."""
    rendered = furniture_render("barrel")
    if rendered is not None:
        return rendered
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    r, h = 24, 62
    wood, dark, light = (128, 84, 46), (82, 52, 28), (160, 110, 64)
    iron = (58, 58, 64)
    top = gy - h
    d.ellipse([P(cx - r, gy - 10), P(cx + r, gy + 10)], fill=dark)
    d.rectangle([P(cx - r, top), P(cx + r, gy)], fill=wood)
    d.rectangle([P(cx + r * 0.25, top), P(cx + r, gy)], fill=dark)
    for k in range(-3, 4):
        x = cx + k * r / 3.6
        d.line([P(x, top + 2), P(x, gy - 1)], fill=mix(wood, dark, 0.5), width=S)
    for hy in (top + h * 0.22, gy - h * 0.22):
        d.rectangle([P(cx - r, hy - 2), P(cx + r, hy + 2)], fill=iron)
    d.ellipse([P(cx - r, top - 10), P(cx + r, top + 10)], fill=light, outline=dark, width=S)
    d.ellipse([P(cx - r + 4, top - 7), P(cx + r - 4, top + 7)], fill=wood)
    d.line([P(cx - r + 6, top), P(cx + r - 6, top)], fill=dark, width=S)
    return img


def icon_barrel():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    wood, dark, light = (128, 84, 46), (82, 52, 28), (160, 110, 64)
    d.rectangle([Q(8, 8), Q(24, 28)], fill=wood, outline=dark)
    d.rectangle([Q(17, 8), Q(24, 28)], fill=dark)
    for y in (12, 24):
        d.rectangle([Q(8, y), Q(24, y + 1)], fill=(58, 58, 64))
    d.ellipse([Q(8, 5), Q(24, 11)], fill=light, outline=dark)
    return img


DWC = dict(r=22, h=40)


def draw_dwc(medium=True, style="dwc"):
    """A hydro bucket with a lid and net pot. DWC: black, with an air pump beside it. RDWC site: blue-grey, with a
    hose fitting at the base. With `medium` the net pot shows clay pebbles around a rockwool cube; the plant is lifted by the bucket."""
    rendered = furniture_render(f"{style}_{'medium' if medium else 'empty'}")
    if rendered is not None:
        return rendered, DWC["h"]
    r, h = DWC["r"], DWC["h"]
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    body, dark, rim = ((36, 36, 40), (20, 20, 24), (70, 70, 76)) if style == "dwc" else ((54, 70, 92), (32, 42, 58), (90, 106, 128))
    top = gy - h
    if style == "dwc":
        # air pump on the floor beside the bucket, with its tube into the lid
        px = cx + r + 6
        d.rectangle([P(px - 6, gy - 7), P(px + 6, gy + 1)], fill=(214, 216, 222), outline=(110, 112, 120), width=S)
        d.line([P(px - 2, gy - 7), P(px - 4, top - 2), P(cx + r * 0.55, top - 1)], fill=(170, 210, 230), width=S)
    else:
        # recirculating line: a fitting low on the bucket and a hose running off along the floor
        d.line([P(cx - r - 14, gy + 4), P(cx - r + 2, gy - 6)], fill=(40, 40, 44), width=3 * S)
    # bucket body, a little narrower at the base
    d.ellipse([P(cx - r * 0.9, gy - 7), P(cx + r * 0.9, gy + 7)], fill=dark)
    d.polygon([P(cx - r * 0.9, gy), P(cx - r, top), P(cx + r, top), P(cx + r * 0.9, gy)], fill=body)
    d.polygon([P(cx + 2, gy), P(cx + 2, top), P(cx + r, top), P(cx + r * 0.9, gy)], fill=dark)
    for k in (0.3, 0.55):
        y = top + h * k
        d.line([P(cx - r * 0.97, y), P(cx + r * 0.97, y)], fill=rim, width=S)
    # lid and net pot
    d.ellipse([P(cx - r - 1, top - 9), P(cx + r + 1, top + 9)], fill=(58, 58, 64), outline=dark, width=S)
    d.ellipse([P(cx - 10, top - 5), P(cx + 10, top + 5)], fill=(24, 24, 28))
    if medium:
        rng = random.Random(7)
        for _ in range(40):
            x, y = cx + rng.uniform(-8, 8), top + rng.uniform(-3.5, 3.5)
            if ((x - cx) / 9) ** 2 + ((y - top) / 4.2) ** 2 <= 1:
                d.ellipse([P(x - 1.3, y - 1.1), P(x + 1.3, y + 1.1)], fill=(176, 92, 52))
        d.rectangle([P(cx - 3, top - 3), P(cx + 3, top + 1)], fill=(206, 200, 160), outline=(150, 140, 100))
    else:
        for k in range(-3, 4):
            d.line([P(cx + k * 2.5, top - 4), P(cx + k * 2.5, top + 4)], fill=(50, 50, 56), width=S)
    return img, h


TABLE_EXTRA = {"PickUpWeight": "40", "Material": "Metal", "IsLow": "", "solidtrans": ""}
TABLE_LIFT = 41   # tray floor (30 px) plus a rockwool block (11 px): where a plant's stem starts


def draw_flood_table(medium):
    """One tile of a flood table: a white tray on legs, with a rockwool block when `medium`. Returns (layer, plant lift in px)."""
    rendered = furniture_render(f"ebb_table_{'medium' if medium else 'empty'}")
    if rendered is not None:
        return rendered, TABLE_LIFT
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    top = gy - 30
    for dx in (-40, 40):
        d.line([P(cx + dx, top + 10), P(cx + dx, gy + 6)], fill=(150, 154, 160), width=2 * S)
    d.line([P(cx, top + 22), P(cx, gy + 20)], fill=(150, 154, 160), width=2 * S)
    d.polygon([P(cx - 62, top), P(cx, top - 31), P(cx + 62, top), P(cx, top + 31)], fill=(228, 228, 222), outline=(170, 170, 166))
    if medium:
        d.polygon([P(cx - 7, top - 4), P(cx, top - 8), P(cx + 7, top - 4), P(cx, top)], fill=(214, 204, 156))
        d.rectangle([P(cx - 7, top - 4), P(cx + 7, top + 6)], fill=(190, 180, 130))
    return img, TABLE_LIFT


def draw_flood_reservoir():
    """A black tote with a grey lid and two hoses (fill and drain) rising out of it."""
    rendered = furniture_render("flood_reservoir")
    if rendered is not None:
        return rendered
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    d.rectangle([P(cx - 26, gy - 36), P(cx + 26, gy)], fill=(32, 32, 36))
    d.rectangle([P(cx - 28, gy - 40), P(cx + 28, gy - 34)], fill=(60, 62, 70))
    for x in (-12, 6):
        d.line([P(cx + x, gy - 40), P(cx + x, gy - 52), P(cx + x - 24, gy - 50)], fill=(34, 34, 38), width=3 * S)
    return img


def draw_control():
    """An RDWC control bucket: a bigger white bucket with a pump on the lid, an air pump, and hoses out to the sites."""
    rendered = furniture_render("rdwc_control")
    if rendered is not None:
        return rendered
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    r, h = 27, 72   # taller than the site buckets so the reservoir reads at a glance
    top = gy - h
    for ang in (-40, 0, 40):
        a = math.radians(ang)
        d.line([P(cx + r * 0.8 * math.sin(a), gy - 4), P(cx + (r + 20) * math.sin(a) * 1.6, gy + 10)], fill=(40, 40, 44), width=3 * S)
    body, dark = (214, 216, 220), (150, 152, 158)
    d.ellipse([P(cx - r * 0.9, gy - 8), P(cx + r * 0.9, gy + 8)], fill=dark)
    d.polygon([P(cx - r * 0.9, gy), P(cx - r, top), P(cx + r, top), P(cx + r * 0.9, gy)], fill=body)
    d.polygon([P(cx + 2, gy), P(cx + 2, top), P(cx + r, top), P(cx + r * 0.9, gy)], fill=dark)
    d.ellipse([P(cx - r - 1, top - 10), P(cx + r + 1, top + 10)], fill=(232, 232, 236), outline=dark, width=S)
    d.rectangle([P(cx - 9, top - 14), P(cx + 9, top - 2)], fill=(50, 52, 60), outline=(20, 20, 24), width=S)
    d.ellipse([P(cx - 3, top - 12), P(cx + 3, top - 7)], fill=(90, 200, 120))
    px = cx + r + 8
    d.rectangle([P(px - 6, gy - 7), P(px + 6, gy + 1)], fill=(214, 216, 222), outline=(110, 112, 120), width=S)
    d.line([P(px - 2, gy - 7), P(px - 4, top - 2), P(cx + r * 0.6, top - 1)], fill=(170, 210, 230), width=S)
    return img


def icon_rdwc_site():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.line([Q(2, 30), Q(9, 25)], fill=(40, 40, 44), width=2 * S)
    d.polygon([Q(8, 28), Q(7, 9), Q(25, 9), Q(24, 28)], fill=(54, 70, 92), outline=(24, 32, 44))
    d.ellipse([Q(6, 6), Q(26, 12)], fill=(90, 106, 128), outline=(24, 32, 44))
    d.ellipse([Q(12, 7), Q(20, 11)], fill=(24, 24, 28))
    return img


def icon_rdwc_control():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    for x in (4, 16, 28):
        d.line([Q(16, 26), Q(x, 31)], fill=(40, 40, 44), width=2 * S)
    d.polygon([Q(7, 28), Q(6, 9), Q(26, 9), Q(25, 28)], fill=(214, 216, 220), outline=(120, 122, 128))
    d.ellipse([Q(5, 6), Q(27, 12)], fill=(232, 232, 236), outline=(120, 122, 128))
    d.rectangle([Q(12, 3), Q(20, 9)], fill=(50, 52, 60), outline=(20, 20, 24))
    return img


def icon_dwc():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.polygon([Q(8, 28), Q(7, 9), Q(25, 9), Q(24, 28)], fill=(36, 36, 40), outline=(16, 16, 18))
    d.ellipse([Q(6, 6), Q(26, 12)], fill=(58, 58, 64), outline=(16, 16, 18))
    d.ellipse([Q(12, 7), Q(20, 11)], fill=(24, 24, 28))
    d.rectangle([Q(24, 24), Q(30, 29)], fill=(214, 216, 222), outline=(110, 112, 120))
    d.line([Q(26, 24), Q(25, 9)], fill=(170, 210, 230), width=S)
    return img


def icon_rockwool():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.polygon([Q(8, 14), Q(16, 10), Q(25, 14), Q(17, 18)], fill=(222, 216, 176))
    d.polygon([Q(8, 14), Q(17, 18), Q(17, 28), Q(8, 24)], fill=(196, 188, 146))
    d.polygon([Q(17, 18), Q(25, 14), Q(25, 24), Q(17, 28)], fill=(170, 162, 122))
    d.ellipse([Q(15, 12), Q(18, 15)], fill=(120, 110, 80))
    return img


def icon_pebbles(fired=True):
    img = icon_canvas(); d = ImageDraw.Draw(img)
    rng = random.Random(3)
    col = (176, 92, 52) if fired else (150, 120, 100)
    d.polygon([Q(6, 26), Q(9, 12), Q(23, 12), Q(26, 26)], fill=(196, 186, 150) if fired else (180, 170, 150), outline=(120, 110, 80))
    for _ in range(26):
        x, y = rng.uniform(8, 24), rng.uniform(6, 14)
        c = tuple(max(0, min(255, int(v * rng.uniform(0.85, 1.1)))) for v in col)
        d.ellipse([Q(x - 2, y - 1.6), Q(x + 2, y + 1.6)], fill=c, outline=tuple(int(v * 0.6) for v in col))
    return img


def icon_hydro_magazine():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.rectangle([Q(6, 3), Q(26, 29)], fill=(40, 110, 170), outline=(16, 40, 70))
    d.rectangle([Q(6, 3), Q(9, 29)], fill=(28, 80, 130))
    d.rectangle([Q(11, 5), Q(24, 8)], fill=(240, 240, 250))
    d.ellipse([Q(12, 11), Q(23, 22)], fill=(120, 190, 230))
    d.polygon([Q(17.5, 12), Q(20, 16), Q(17.5, 20), Q(15, 16)], fill=(90, 190, 90))
    d.rectangle([Q(11, 24), Q(24, 25)], fill=(230, 235, 245))
    return img


def draw_light_bar(key, facing, part=0):
    """One tile of a ceiling-hung bar light (the same segment repeats across its tiles)."""
    rendered = furniture_render(f"bar_{key}_{facing}{part}")
    if rendered is not None:
        return rendered
    spec = LIGHTS[key]
    img = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, gy = BASE
    sgn = 1 if facing == "S" else -1
    a = (cx - 32, gy - 16 * sgn)
    b = (cx + 32, gy + 16 * sgn)
    body, glow = spec["body"], spec["glow"]
    dark = mix(body, (0, 0, 0), 0.5)
    top, ceil_y = 92, 30
    for t in (0.2, 0.8):
        x = a[0] + (b[0] - a[0]) * t
        y = a[1] + (b[1] - a[1]) * t
        d.line([P(x, ceil_y + (y - gy) * 0), P(x, y - gy + top + 20)], fill=(30, 30, 30), width=S)
    pa, pb = (a[0], a[1] - gy + top + 20), (b[0], b[1] - gy + top + 20)
    d.line([P(*pa), P(*pb)], fill=body, width=7 * S)
    d.line([P(pa[0], pa[1] + 4), P(pb[0], pb[1] + 4)], fill=glow, width=3 * S)
    d.line([P(pa[0], pa[1] - 3), P(pb[0], pb[1] - 3)], fill=dark, width=S)
    return img


def bag_variant(plant, condition, bag_layer, lift):
    """Bag + the plant layer (recoloured for condition) lifted onto the soil."""
    base = variant(plant, condition, Image.new("RGBA", plant.size, (0, 0, 0, 0)))
    lifted = Image.new("RGBA", plant.size, (0, 0, 0, 0))
    lifted.paste(base, (0, -lift * S), base)
    out = bag_layer.copy()
    out.alpha_composite(lifted)
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


# Three wet-plant icons: Indica is short and fat with purple-tinged buds,
# Sativa long and thin, Hybrid in between.
WET_STYLES = {
    "Indica": dict(stem_end=22, branches=[(16, 24, 7), (9, 19, 6), (23, 19, 6), (6, 13, 4), (26, 13, 4)],
                   r=3.0, bud=(120, 150, 80), tint=(150, 110, 170), n=4, leaf_len=10),
    "Sativa": dict(stem_end=30, branches=[(16, 30, 14), (12, 21, 9), (20, 21, 9), (11, 11, 6)],
                   r=1.7, bud=(150, 185, 85), tint=None, n=7, leaf_len=8),
    "Hybrid": dict(stem_end=26, branches=[(16, 28, 10), (10, 22, 7), (22, 22, 7), (8, 14, 5), (24, 14, 5)],
                   r=2.2, bud=(130, 170, 80), tint=None, n=5, leaf_len=9),
}


def icon_wet_plant(kind="Hybrid"):
    st = WET_STYLES[kind]
    img = icon_canvas(); d = ImageDraw.Draw(img)
    # whole plant hung upside down: stem at top, colas hanging
    d.line([Q(16, 2), Q(16, st["stem_end"])], fill=(86, 118, 50), width=2 * S)
    d.line([Q(12, 3), Q(20, 3)], fill=(150, 120, 80), width=2 * S)    # twine
    rng = random.Random(7)
    for bx, by, l in st["branches"]:
        d.line([Q(16, by - l), Q(bx, by - l + 2)], fill=(86, 118, 50), width=S)
        for i in range(st["n"]):
            y = by - l + 2 + i * l / st["n"]
            r = st["r"]
            col = st["bud"]
            if st["tint"] and i % 2 == 0:
                col = mix(col, st["tint"], 0.45)
            d.ellipse([Q(bx - r, y - r), Q(bx + r, y + r)], fill=col)
            hx = bx + rng.uniform(-2, 2)
            d.point(Q(hx, y), fill=(240, 240, 230))
    for ang in (-150, -30):
        leaflet_on(d, 16, 8, ang, st["leaf_len"])
    return img


def icon_grow_light(pro):
    img = icon_canvas(); d = ImageDraw.Draw(img)
    body = (70, 70, 78) if not pro else (40, 40, 48)
    glow = (255, 214, 120) if not pro else (255, 245, 235)
    # hanging cord and a wide reflector
    d.line([Q(16, 1), Q(16, 8)], fill=(30, 30, 30), width=S)
    d.polygon([Q(5, 18), Q(11, 8), Q(21, 8), Q(27, 18)], fill=body, outline=(20, 20, 20))
    d.rectangle([Q(7, 18), Q(25, 21)], fill=glow, outline=(150, 120, 60))
    if pro:
        for x in (10, 14, 18, 22):
            d.line([Q(x, 18), Q(x, 21)], fill=(255, 255, 255), width=S)
    # light rays
    for x in (9, 16, 23):
        d.line([Q(x, 23), Q(x + (x - 16) // 3, 30)], fill=mix(glow, (255, 255, 255), 0.2) + (120,), width=S)
    return img


def icon_flood(pro):
    img = icon_canvas(); d = ImageDraw.Draw(img)
    body = (40, 40, 48) if pro else (214, 168, 40)
    glow = (255, 246, 238) if pro else (255, 224, 140)
    dark = mix(body, (0, 0, 0), 0.55)
    # tripod legs, pole and lamp head(s)
    for x in (7, 16, 25):
        d.line([Q(16, 19), Q(x, 30)], fill=dark, width=S)
    d.line([Q(16, 11), Q(16, 19)], fill=(150, 152, 160), width=S)
    heads = [(3, 15), (17, 29)] if pro else [(7, 25)]
    for x0, x1 in heads:
        d.rectangle([Q(x0, 3), Q(x1, 11)], fill=body, outline=dark)
        d.rectangle([Q(x0 + 1, 4), Q(x1 - 1, 9)], fill=glow)
    return img


def icon_light_timer():
    """A plug-in mechanical timer: grey body, dial with on/off pins, and prongs."""
    img = icon_canvas(); d = ImageDraw.Draw(img)
    body, dark = (220, 222, 226), (90, 92, 100)
    d.rounded_rectangle([Q(6, 4), Q(26, 26)], radius=3 * S, fill=body, outline=dark, width=S)
    d.ellipse([Q(9, 7), Q(23, 21)], fill=(250, 250, 250), outline=dark, width=S)
    for k in range(12):
        a = math.radians(k * 30)
        col = (70, 170, 80) if k < 6 else (60, 60, 70)
        d.line([Q(16 + 5 * math.cos(a), 14 + 5 * math.sin(a)), Q(16 + 7 * math.cos(a), 14 + 7 * math.sin(a))], fill=col, width=S)
    d.line([Q(16, 14), Q(16, 9)], fill=(200, 60, 60), width=S)
    for x in (12, 20):
        d.rectangle([Q(x - 1, 26), Q(x + 1, 30)], fill=(180, 160, 90))
    return img


def icon_grow_bag(size):
    img = icon_canvas(); d = ImageDraw.Draw(img)
    big = size == "large"
    w = 12 if big else 9
    top, bot = (8, 28) if big else (13, 28)
    felt, dark, light = (70, 70, 78), (46, 46, 54), (104, 104, 112)
    d.polygon([Q(16 - w, bot), Q(16 - w - 1, top), Q(16 + w + 1, top), Q(16 + w, bot)], fill=felt, outline=dark)
    d.polygon([Q(17, bot), Q(17, top), Q(16 + w + 1, top), Q(16 + w, bot)], fill=dark)
    d.ellipse([Q(16 - w - 1, top - 3), Q(16 + w + 1, top + 3)], fill=light, outline=dark)
    d.ellipse([Q(16 - w + 1, top - 2), Q(16 + w - 1, top + 2)], fill=(80, 58, 40))
    for sx in (-1, 1):
        d.arc([Q(16 + sx * (w + 1) - 3, top - 2), Q(16 + sx * (w + 1) + 3, top + 5)], 0, 360, fill=light, width=S)
    return img


def icon_soil_sack():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    sack, dark = (150, 118, 80), (100, 76, 50)
    d.polygon([Q(8, 10), Q(24, 10), Q(26, 28), Q(6, 28)], fill=sack, outline=dark)
    d.polygon([Q(17, 10), Q(24, 10), Q(26, 28), Q(17, 28)], fill=dark)
    d.polygon([Q(10, 10), Q(12, 5), Q(16, 8), Q(20, 5), Q(22, 10)], fill=sack, outline=dark)
    d.rectangle([Q(11, 16), Q(21, 22)], fill=(70, 50, 34), outline=dark)
    return img


def icon_drying_rack():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    wood = (120, 88, 56)
    d.line([Q(4, 6), Q(28, 6)], fill=wood, width=2 * S)
    d.line([Q(5, 6), Q(5, 28)], fill=wood, width=2 * S)
    d.line([Q(27, 6), Q(27, 28)], fill=wood, width=2 * S)
    for x in (10, 16, 22):
        d.line([Q(x, 6), Q(x, 11)], fill=(60, 60, 60), width=S)
        d.polygon([Q(x - 3, 11), Q(x + 3, 11), Q(x + 2, 22), Q(x, 25), Q(x - 2, 22)], fill=(70, 130, 56), outline=(34, 76, 28))
    return img


def icon_curing_jar():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.rectangle([Q(9, 9), Q(23, 29)], fill=(190, 215, 220, 150), outline=(120, 150, 160))
    d.rectangle([Q(10, 5), Q(22, 9)], fill=(150, 150, 156), outline=(80, 80, 86))
    for x, y in ((12, 24), (16, 22), (20, 25), (14, 18), (18, 17), (13, 13), (19, 12)):
        d.ellipse([Q(x - 2, y - 2), Q(x + 2, y + 2)], fill=(110, 160, 70), outline=(50, 90, 36))
    return img


def icon_fan():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([Q(5, 5), Q(27, 27)], fill=(210, 210, 214), outline=(70, 70, 76))
    for ang in (20, 140, 260):
        a = math.radians(ang)
        d.polygon([Q(16, 16), Q(16 + 10 * math.cos(a - 0.5), 16 + 10 * math.sin(a - 0.5)),
                   Q(16 + 10 * math.cos(a + 0.5), 16 + 10 * math.sin(a + 0.5))], fill=(90, 90, 100))
    d.ellipse([Q(14, 14), Q(18, 18)], fill=(40, 40, 46))
    d.rectangle([Q(12, 27), Q(20, 30)], fill=(70, 70, 76))
    return img


def icon_papers():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.rectangle([Q(8, 8), Q(24, 26)], fill=(236, 232, 214), outline=(150, 140, 110))
    d.rectangle([Q(8, 8), Q(24, 13)], fill=(214, 200, 160), outline=(150, 140, 110))
    d.line([Q(11, 18), Q(21, 18)], fill=(150, 140, 110), width=S)
    return img


def icon_joint():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.polygon([Q(4, 24), Q(6, 21), Q(28, 9), Q(29, 12)], fill=(240, 236, 220), outline=(160, 150, 120))
    d.polygon([Q(26, 10), Q(29, 12), Q(30, 9), Q(28, 8)], fill=(110, 150, 70))
    d.line([Q(4, 24), Q(7, 21)], fill=(150, 120, 80), width=2 * S)
    return img


def icon_pipe():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.line([Q(6, 25), Q(22, 12)], fill=(120, 80, 50), width=3 * S)
    d.ellipse([Q(18, 4), Q(30, 16)], fill=(100, 66, 40), outline=(60, 40, 24))
    d.ellipse([Q(21, 6), Q(27, 12)], fill=(60, 90, 40))
    return img


def icon_bud():
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([Q(9, 8), Q(23, 27)], fill=(112, 150, 72), outline=(50, 84, 36))
    for x, y in ((13, 12), (18, 14), (14, 19), (19, 21), (16, 25)):
        d.ellipse([Q(x - 2, y - 2), Q(x + 2, y + 2)], fill=(140, 180, 90))
    for x, y in ((14, 14), (18, 20), (16, 10)):
        d.line([Q(x, y), Q(x + 2, y - 3)], fill=(230, 150, 60), width=S)
    return img


ICONS = {
    "DryingRack": icon_drying_rack,
    "CuringJar": icon_curing_jar,
    "DryingFan": icon_fan,
    "CannabisBud": icon_bud,
    "RollingPapers": icon_papers,
    "Joint": icon_joint,
    "SmokingPipe": icon_pipe,
    "GrowBagSmall": lambda: icon_grow_bag("small"),
    "GrowBagLarge": lambda: icon_grow_bag("large"),
    "SoilSack": icon_soil_sack,
    "GrowLampBasic": lambda: icon_grow_light(False),
    "GrowLampPro": lambda: icon_grow_light(True),
    "GrowLampLargeBasic": lambda: icon_grow_light(False),
    "GrowLampLargePro": lambda: icon_grow_light(True),
    "LightTimer": icon_light_timer,
    "CuringBarrel": icon_barrel,
    "DWCBucket": icon_dwc,
    "RockwoolCube": icon_rockwool,
    "ClayPebbles": icon_pebbles,
    "ClayPebblesUnfired": lambda: icon_pebbles(False),
    "HydroMagazine": icon_hydro_magazine,
    "RDWCSite": icon_rdwc_site,
    "RDWCControl": icon_rdwc_control,
    "FloodTable": lambda: shrink(draw_flood_table(True)[0].crop((0, 80 * S, 128 * S, 240 * S)), (32 * S, 32 * S)),
    "FloodReservoir": lambda: shrink(draw_flood_reservoir().crop((24 * S, 120 * S, 104 * S, 236 * S)), (32 * S, 32 * S)),
    "FloodTimer": icon_light_timer,
    "GrowFloodBasic": lambda: icon_flood(False),
    "GrowFloodPro": lambda: icon_flood(True),
    "CannabisSeed": icon_seed,
    "CannabisCutting": icon_cutting,
    "RootedCannabisCutting": icon_rooted_cutting,
    "RootingGel": icon_rooting_gel,
    "VegNutrients": lambda: icon_nutrients((70, 150, 60)),
    "BloomNutrients": lambda: icon_nutrients((160, 70, 150)),
    "CloningDome": icon_dome,
    "WetIndicaPlant": lambda: icon_wet_plant("Indica"),
    "WetSativaPlant": lambda: icon_wet_plant("Sativa"),
    "WetHybridPlant": lambda: icon_wet_plant("Hybrid"),
    "DriedIndicaPlant": lambda: recolor(icon_wet_plant("Indica"), (130, 100, 60), 0.55, 0.7, 0.9),
    "DriedSativaPlant": lambda: recolor(icon_wet_plant("Sativa"), (130, 100, 60), 0.55, 0.7, 0.9),
    "DriedHybridPlant": lambda: recolor(icon_wet_plant("Hybrid"), (130, 100, 60), 0.55, 0.7, 0.9),
}


# Blender renders that replace the hand-drawn icons (item name -> render file).
BLENDER_ICONS = {
    "DryingRack": "rack", "CuringJar": "jar", "DryingFan": "fan", "CannabisBud": "bud",
    "RollingPapers": "papers", "Joint": "joint", "SmokingPipe": "pipe",
    "GrowBagSmall": "bagSmall", "GrowBagLarge": "bagLarge",
    "SoilSack": "soil",
    "GrowLampBasic": "lampBasic", "GrowLampPro": "lampPro",
    "GrowLampLargeBasic": "lampLargeBasic", "GrowLampLargePro": "lampLargePro",
    "CannabisSeed": "seed", "CannabisCutting": "cutting", "RootedCannabisCutting": "rooted",
    "RootingGel": "gel", "VegNutrients": "veg", "BloomNutrients": "bloom", "CloningDome": "dome",
"WetIndicaPlant": "wetIndica", "WetSativaPlant": "wetSativa",
    "WetHybridPlant": "wetHybrid", "DriedIndicaPlant": "driedIndica",
    "DriedSativaPlant": "driedSativa", "DriedHybridPlant": "driedHybrid",
    "GrowFloodBasic": "floodBasic", "GrowFloodPro": "floodPro", "CuringBarrel": "barrel",
    "DWCBucket": "dwc", "RDWCSite": "rdwcSite", "RDWCControl": "rdwcControl", "LightTimer": "timer",
    "RockwoolCube": "rockwool", "ClayPebbles": "pebbles", "ClayPebblesUnfired": "pebblesRaw", "HydroMagazine": "hydroMag",
    "FloodTable": "floodTable", "FloodReservoir": "floodReservoir", "FloodTimer": "floodTimer",
    "GrowRoomPanel": "roomGrowRoomPanel", "BlackoutCurtain": "roomBlackoutCurtain", "ExhaustFan": "roomExhaustFan", "IntakeFan": "roomIntakeFan", "Heater": "roomHeater", "Dehumidifier": "roomDehumidifier", "Humidifier": "roomHumidifier",
}


def blender_icon(name):
    """The Blender icon render at the icon canvas size, or None when it does not exist."""
    path = Path(__file__).parent / "blender" / "icons" / (BLENDER_ICONS.get(name, "") + ".png")
    if name not in BLENDER_ICONS or not path.exists():
        return None
    return Image.open(path).convert("RGBA").resize((32 * S, 32 * S), Image.LANCZOS)


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
    ground_previews = list(previews)

    # Grow bag variants: blocks 5-9 (small) and 10-14 (large), same layout.
    bag_previews = []
    for size in ("small", "large"):
        bag_layer, lift = draw_bag(size)
        for cond in CONDITIONS:
            for slot in range(13):
                img = bag_variant(plants[slot], cond, bag_layer, lift)
                small = shrink(img, (CELL_W, CELL_H))
                name = f"{index:03d}_bag_{size}_{cond}_{slot}.png"
                small.save(cells_dir / name)
                manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
                bag_previews.append(small)
                index += 1
    # Empty bags (no plant): small then large.
    for size in ("small", "large"):
        bag_layer, lift = draw_bag(size)
        small = shrink(bag_layer, (CELL_W, CELL_H))
        name = f"{index:03d}_bag_{size}_empty.png"
        small.save(cells_dir / name)
        manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
        bag_previews.append(small)
        index += 1
    # Placeable grow lamps (idx 197-200): moveable furniture, walk-through.
    for key in LIGHTS:
        small = shrink(draw_light(key), (CELL_W, CELL_H))
        name = f"{index:03d}_lamp_{key}.png"
        small.save(cells_dir / name)
        manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": dict(LAMP_PROPS, CustomName=LAMP_NAMES[key])})
        index += 1
    # Unfilled (no soil) bags, idx 201 small and 202 large.
    for size in ("small", "large"):
        bag_layer, lift = draw_bag(size, soil=False)
        small = shrink(bag_layer, (CELL_W, CELL_H))
        name = f"{index:03d}_bag_{size}_dry.png"
        small.save(cells_dir / name)
        manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
        index += 1
    # Furniture bags (203, 204): placed, then turned into plots by the server.
    for size in ("small", "large"):
        bag_layer, lift = draw_bag(size, soil=False)
        small = shrink(bag_layer, (CELL_W, CELL_H))
        name = f"{index:03d}_bag_{size}_furn.png"
        small.save(cells_dir / name)
        manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": dict(BAG_FURN_PROPS, CustomName=size.capitalize() + " Grow Bag")})
        index += 1
    # Drying fan (205).
    small = shrink(draw_fan(), (CELL_W, CELL_H))
    small.save(cells_dir / f"{index:03d}_fan.png")
    manifest["cells"].append({"file": f"{index:03d}_fan.png", "facing": "S", "x": 0, "y": 0, "props": FURN_PROPS})
    index += 1
    # Drying rack, 206-213: two tiles per facing in E, S, W, N order.
    for facing in FACING_ORDER:
        art = "S" if facing in ("S", "N") else "E"
        for part, (img, grid) in enumerate(zip(draw_rack(art), grid_positions(facing, 2))):
            small = shrink(img, (CELL_W, CELL_H))
            name = f"{index:03d}_rack_{facing}{part}.png"
            small.save(cells_dir / name)
            manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0,
                                      "props": multi_props("Drying Rack", "CannabisMod.DryingRack", facing, grid, RACK_EXTRA, 2)})
            index += 1
    # Bar lamps: Large Basic 1x2 (214-221), Large Pro 1x3 (222-233), each in E, S, W, N order.
    for key, count in (("LargeBasic", 2), ("LargePro", 3)):
        for facing in FACING_ORDER:
            art = "S" if facing in ("S", "N") else "E"
            for part, grid in enumerate(grid_positions(facing, count)):
                small = shrink(draw_light_bar(key, art, part), (CELL_W, CELL_H))
                name = f"{index:03d}_lampbar_{key}_{facing}{part}.png"
                small.save(cells_dir / name)
                manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0,
                                          "props": multi_props(LAMP_NAMES[key], "CannabisMod.GrowLamp" + key, facing, grid, dict(LAMP_BAR_EXTRA), count)})
                index += 1
    # Floor flood lights (234 basic, 235 pro): one-tile moveable furniture.
    for key in FLOODS:
        small = shrink(draw_flood(key), (CELL_W, CELL_H))
        name = f"{index:03d}_flood_{key}.png"
        small.save(cells_dir / name)
        manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0,
                                  "props": dict(LAMP_PROPS, CustomName=FLOOD_NAMES[key], PickUpWeight="30")})
        index += 1
    # Curing barrel (236): one-tile furniture container, cures buds like a big jar.
    small = shrink(draw_barrel(), (CELL_W, CELL_H))
    small.save(cells_dir / f"{index:03d}_barrel.png")
    manifest["cells"].append({"file": f"{index:03d}_barrel.png", "facing": "S", "x": 0, "y": 0,
                              "props": {"IsMoveAble": "", "IsLow": "", "CustomName": "Curing Barrel", "PickUpWeight": "40",
                                        "Material": "Wood", "solidtrans": "", "container": "crate",
                                        "ContainerCapacity": "10"}})
    index += 1
    # Male plants (237-371): ground, small bag, large bag; 5 conditions each; Indica, Sativa, Hybrid x pre-flower, flowering, ripe.
    males = {}
    for t in TYPE_ORDER:
        for stage in MALE_STAGES:
            males[(t, stage)] = draw_male(t, stage, zlib.crc32(f"male/{t}/{stage}".encode()))
    male_previews = []
    for where in ("ground", "small", "large"):
        bag_layer, lift = draw_bag(where) if where != "ground" else (None, 0)
        for cond in CONDITIONS:
            for t in TYPE_ORDER:
                for stage in MALE_STAGES:
                    layer = males[(t, stage)]
                    img = variant(layer, cond, furrow) if where == "ground" else bag_variant(layer, cond, bag_layer, lift)
                    small = shrink(img, (CELL_W, CELL_H))
                    name = f"{index:03d}_male_{where}_{cond}_{t}_{stage}.png"
                    small.save(cells_dir / name)
                    props = BAG_PROPS if where != "ground" else None
                    cell = {"file": name, "facing": "S", "x": 0, "y": 0}
                    if props:
                        cell["props"] = props
                    manifest["cells"].append(cell)
                    if where == "ground" and cond == "sprite":
                        male_previews.append(small)
                    index += 1
    # DWC bucket (372 furniture, 373 empty plot, 374 with medium), then its plants: 65 female (375-439), 45 male (440-484).
    furn_props = {"IsMoveAble": "", "IsLow": "", "CustomName": "DWC Bucket", "PickUpWeight": "20", "Material": "Plastic", "solidtrans": ""}
    for name, (layer, _) in (("dwc_furn", draw_dwc(False)), ("dwc_empty", draw_dwc(False)), ("dwc_medium", draw_dwc(True))):
        small = shrink(layer, (CELL_W, CELL_H))
        small.save(cells_dir / f"{index:03d}_{name}.png")
        props = furn_props if name == "dwc_furn" else BAG_PROPS
        manifest["cells"].append({"file": f"{index:03d}_{name}.png", "facing": "S", "x": 0, "y": 0, "props": props})
        index += 1
    dwc_layer, dwc_lift = draw_dwc(True)
    for cond in CONDITIONS:
        for slot in range(13):
            small = shrink(bag_variant(plants[slot], cond, dwc_layer, dwc_lift), (CELL_W, CELL_H))
            name = f"{index:03d}_dwc_{cond}_{slot}.png"
            small.save(cells_dir / name)
            manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
            index += 1
    for cond in CONDITIONS:
        for t in TYPE_ORDER:
            for stage in MALE_STAGES:
                small = shrink(bag_variant(males[(t, stage)], cond, dwc_layer, dwc_lift), (CELL_W, CELL_H))
                name = f"{index:03d}_dwc_male_{cond}_{t}_{stage}.png"
                small.save(cells_dir / name)
                manifest["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
                index += 1
    if index > MAX_SHEET_TILES:
        raise SystemExit(f"{SHEET} has {index} tiles; Project Zomboid allows at most {MAX_SHEET_TILES}")
    main_count = index
    # Hydro sheet (PZ caps a sheet at 512 tiles): RDWC site bucket 0 furniture, 1 empty, 2 with medium, plants 3-67 female, 68-112 male, control 113.
    hydro_dir = out / "hydro_cells"
    hydro_dir.mkdir(parents=True, exist_ok=True)
    hydro = {"sheet": HYDRO_SHEET, "cell": [CELL_W, CELL_H], "scale": "2x", "facings": ["S"], "cells": []}
    index = 0
    site_props = {"IsMoveAble": "", "IsLow": "", "CustomName": "RDWC Site Bucket", "PickUpWeight": "20", "Material": "Plastic", "solidtrans": ""}
    for name, medium in (("rdwc_furn", False), ("rdwc_empty", False), ("rdwc_medium", True)):
        layer, _ = draw_dwc(medium, "rdwc")
        small = shrink(layer, (CELL_W, CELL_H))
        small.save(hydro_dir / f"{index:03d}_{name}.png")
        hydro["cells"].append({"file": f"{index:03d}_{name}.png", "facing": "S", "x": 0, "y": 0,
                                  "props": site_props if name == "rdwc_furn" else BAG_PROPS})
        index += 1
    rdwc_layer, rdwc_lift = draw_dwc(True, "rdwc")
    for cond in CONDITIONS:
        for slot in range(13):
            small = shrink(bag_variant(plants[slot], cond, rdwc_layer, rdwc_lift), (CELL_W, CELL_H))
            name = f"{index:03d}_rdwc_{cond}_{slot}.png"
            small.save(hydro_dir / name)
            hydro["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
            index += 1
    for cond in CONDITIONS:
        for t in TYPE_ORDER:
            for stage in MALE_STAGES:
                small = shrink(bag_variant(males[(t, stage)], cond, rdwc_layer, rdwc_lift), (CELL_W, CELL_H))
                name = f"{index:03d}_rdwc_male_{cond}_{t}_{stage}.png"
                small.save(hydro_dir / name)
                hydro["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
                index += 1
    small = shrink(draw_control(), (CELL_W, CELL_H))
    small.save(hydro_dir / f"{index:03d}_rdwc_control.png")
    hydro["cells"].append({"file": f"{index:03d}_rdwc_control.png", "facing": "S", "x": 0, "y": 0,
                              "props": {"IsMoveAble": "", "IsLow": "", "CustomName": "RDWC Control Bucket", "PickUpWeight": "40",
                                        "Material": "Plastic", "solidtrans": ""}})
    index += 1
    # Ebb and Flow, 114-234: the placed table (E0 E1 S0 S1 W0 W1 N0 N1), a table tile without and with rockwool,
    # its plants (124-188 female, 189-233 male), then the flood reservoir.
    assert index == 114, index
    table_empty, _ = draw_flood_table(False)
    for facing in FACING_ORDER:
        for part, grid in enumerate(grid_positions(facing, 2)):
            name = f"{index:03d}_ebb_furn_{facing}{part}.png"
            shrink(table_empty, (CELL_W, CELL_H)).save(hydro_dir / name)
            hydro["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0,
                                   "props": multi_props("Flood Table", "CannabisMod.FloodTable", facing, grid, TABLE_EXTRA, 2)})
            index += 1
    for name, medium in (("ebb_dry", False), ("ebb_medium", True)):
        layer, _ = draw_flood_table(medium)
        shrink(layer, (CELL_W, CELL_H)).save(hydro_dir / f"{index:03d}_{name}.png")
        hydro["cells"].append({"file": f"{index:03d}_{name}.png", "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
        index += 1
    ebb_layer, ebb_lift = draw_flood_table(True)
    for cond in CONDITIONS:
        for slot in range(13):
            small = shrink(bag_variant(plants[slot], cond, ebb_layer, ebb_lift), (CELL_W, CELL_H))
            name = f"{index:03d}_ebb_{cond}_{slot}.png"
            small.save(hydro_dir / name)
            hydro["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
            index += 1
    for cond in CONDITIONS:
        for t in TYPE_ORDER:
            for stage in MALE_STAGES:
                small = shrink(bag_variant(males[(t, stage)], cond, ebb_layer, ebb_lift), (CELL_W, CELL_H))
                name = f"{index:03d}_ebb_male_{cond}_{t}_{stage}.png"
                small.save(hydro_dir / name)
                hydro["cells"].append({"file": name, "facing": "S", "x": 0, "y": 0, "props": BAG_PROPS})
                index += 1
    small = shrink(draw_flood_reservoir(), (CELL_W, CELL_H))
    small.save(hydro_dir / f"{index:03d}_flood_reservoir.png")
    hydro["cells"].append({"file": f"{index:03d}_flood_reservoir.png", "facing": "S", "x": 0, "y": 0,
                           "props": {"IsMoveAble": "", "IsLow": "", "CustomName": "Flood Reservoir", "PickUpWeight": "40",
                                     "Material": "Plastic", "solidtrans": ""}})
    index += 1
    assert index == 235, index
    (hydro_dir / "manifest.json").write_text(json.dumps(hydro, indent=1))
    hydro_count = index
    index = main_count
    mp = Image.new("RGBA", (9 * CELL_W, CELL_H), (58, 74, 40, 255))
    for i, im in enumerate(male_previews):
        mp.alpha_composite(im, (i * CELL_W, 0))
    mp.save(out / "preview_males.png")
    previews = ground_previews

    # Preview of the bag sprites: healthy rows for small and large, plus the
    # empties.
    bp = Image.new("RGBA", (13 * CELL_W, 3 * CELL_H), (58, 74, 40, 255))
    for i in range(13):
        bp.alpha_composite(bag_previews[i], (i * CELL_W, 0))
        bp.alpha_composite(bag_previews[65 + i], (i * CELL_W, CELL_H))
    bp.alpha_composite(bag_previews[130], (0, 2 * CELL_H))
    bp.alpha_composite(bag_previews[131], (CELL_W, 2 * CELL_H))
    bp.save(out / "preview_bags.png")
    (cells_dir / "manifest.json").write_text(json.dumps(manifest, indent=1))

    icons = []
    for name, fn in ICONS.items():
        ic = shrink(blender_icon(name) or fn(), (32, 32))
        ic.save(icons_dir / f"Item_{name}.png")
        icons.append(ic)

    # preview: 13 columns x 5 condition rows at 1x on a grass background, plus
    # the healthy row again at 2x and the icons at 4x
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
    print(f"wrote {index} cells on {SHEET}, {hydro_count} on {HYDRO_SHEET}, {len(icons)} icons, preview")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/art")
