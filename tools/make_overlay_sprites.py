"""
make_overlay_sprites.py -- build the plant layer sheets: dazeddank_overlay_01 (standard) and dazeddank_overlay_02 (XL pots).

Each sheet: per condition a seedling plus 4 stages for each of the 7 shapes (145), males 3 stages per shape per condition
(105), then the coloured flowering and ripe plants, healthy and unhealthy (112). The game raises each layer onto its
plot (furrow, bag, bucket or table). Also writes the bare furrow a ground plant stands in (dazeddank_plants_01_65) and
drops the old ground plant sprites. Uses Blender renders from tools/blender/shapes when present:
    shape_<shape>_<Stage>.png, male_<shape>_<Stage>.png, colour_<colour>_<shape>_<Stage>.png
and otherwise stands in a reshaped, recoloured copy of the three original type renders. Run from the repo root:

    python tools/make_overlay_sprites.py
"""
import math, os, random, sys, zlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance
sys.path.insert(0, os.path.dirname(__file__))
import draw_placeholders as dp
import pzpack, tdef

MEDIA = "Contents/mods/DazedDank/42/media/"
SHEETS = (("dazeddank_overlay_01", 1.0), ("dazeddank_overlay_02", 1.10))   # the XL plant is 10% bigger
WIDTH = 8
SHAPES = ["landrace", "haze", "hybrid", "kush", "afghan", "auto", "tree"]
COLOURS = ["purple", "frosty", "gold", "dark"]          # green is the plain set
STAGES = ["Vegetative", "PreFlower", "Flowering", "Ripe"]
MALE_STAGES = ["PreFlower", "Flowering", "Ripe"]
RENDERS = Path(__file__).parent / "blender" / "plants"
SHAPE_RENDERS = Path(__file__).parent / "blender" / "shapes"     # output of tools/blender/render_shapes.py
# Stand-ins until the Blender pass: which original type render a shape borrows, and how it is stretched (width, height).
STAND_IN = {"landrace": ("Sativa", 0.85, 1.10), "haze": ("Sativa", 1.0, 1.0), "hybrid": ("Hybrid", 1.0, 1.0),
            "kush": ("Indica", 1.0, 1.0), "afghan": ("Indica", 1.2, 0.85), "auto": ("Hybrid", 0.65, 0.65),
            "tree": ("Hybrid", 0.8, 1.05)}
FURROW_TILE = 65
OLD_GROUND = list(range(0, 65)) + list(range(237, 282))


def load(name):
    path = SHAPE_RENDERS / name
    if path.exists():
        return Image.open(path).convert("RGBA").resize((dp.CELL_W * dp.S, dp.CELL_H * dp.S), Image.LANCZOS)
    return None


def stretch(im, kx, ky):
    """Scale a plant layer by kx, ky about the point where its stem meets the soil."""
    ax, ay = dp.BASE[0] * dp.S, dp.BASE[1] * dp.S
    W, H = im.size
    big = im.resize((max(1, round(W * kx)), max(1, round(H * ky))), Image.LANCZOS)
    out = Image.new("RGBA", (W, H))
    out.paste(big, (round(ax - ax * kx), round(ay - ay * ky)), big)
    return out


def tint(im, colour):
    """Stand-in colouring for a coloured phenotype: the whole plant shifted toward the colour."""
    if colour == "purple":
        return dp.recolor(im, (110, 40, 140), 0.38, sat=1.1)
    if colour == "frosty":
        return dp.recolor(im, (236, 240, 236), 0.42, sat=0.7, bright=1.15)
    if colour == "gold":
        return dp.recolor(im, (205, 190, 60), 0.35, sat=1.15, bright=1.05)
    return dp.recolor(im, (18, 34, 20), 0.45, sat=0.8, bright=0.7)   # dark


def female(shape, stage):
    got = load(f"shape_{shape}_{stage}.png")
    if got:
        return got
    t, kx, ky = STAND_IN[shape]
    return stretch(dp.draw_plant(t, stage, zlib.crc32(f"{t}/{stage}".encode())), kx, ky)


def male(shape, stage):
    got = load(f"male_{shape}_{stage}.png")
    if got:
        return got
    t, kx, ky = STAND_IN[shape]
    return stretch(dp.draw_male(t, stage, zlib.crc32(f"male/{t}/{stage}".encode())), kx, ky)


def coloured(colour, shape, stage):
    return load(f"colour_{colour}_{shape}_{stage}.png") or tint(female(shape, stage), colour)


def layers():
    """Every plant layer in sheet order, as (kind, image, condition)."""
    blank = Image.new("RGBA", (dp.CELL_W * dp.S, dp.CELL_H * dp.S))
    seedling = dp.draw_plant("Hybrid", "Seedling", zlib.crc32(b"Hybrid/Seedling"))
    fem = {(s, st): female(s, st) for s in SHAPES for st in STAGES}
    mal = {(s, st): male(s, st) for s in SHAPES for st in MALE_STAGES}
    col = {(c, s, st): coloured(c, s, st) for c in COLOURS for s in SHAPES for st in ("Flowering", "Ripe")}
    out = []
    for cond in dp.CONDITIONS:
        out.append((seedling, cond))
        for s in SHAPES:
            for st in STAGES:
                out.append((fem[(s, st)], cond))
    for cond in dp.CONDITIONS:
        for s in SHAPES:
            for st in MALE_STAGES:
                out.append((mal[(s, st)], cond))
    for c in COLOURS:
        for s in SHAPES:
            for cond in ("sprite", "unhealthySprite"):
                for st in ("Flowering", "Ripe"):
                    out.append((col[(c, s, st)], cond))
    return out, blank


def write_sheet(name, frames):
    pages = pzpack.pack_pages(name, 0, [(f"{name}_{n}", f) for n, f in enumerate(frames)])
    open(MEDIA + f"texturepacks/{name}.pack", "wb").write(pzpack.wr(1, pages))
    rows = math.ceil(len(frames) / WIDTH)
    tiles = [[("CustomName", "Cannabis")] if i < len(frames) else [] for i in range(WIDTH * rows)]
    open(MEDIA + f"{name}.tiles", "wb").write(tdef.wr(1, [dict(name=name, img=name + ".png", w=WIDTH, h=rows, id=1, tiles=tiles)]))
    return len(pages)


def write_furrow():
    """Put the bare furrow on the plants sheet and drop the old ground plant sprites it replaces."""
    furrow = Image.new("RGBA", (dp.CELL_W * dp.S, dp.CELL_H * dp.S))
    dp.draw_furrow(ImageDraw.Draw(furrow), random.Random(1))
    sheet = "dazeddank_plants_01"
    pf = MEDIA + f"texturepacks/{sheet}.pack"
    ver, pages = pzpack.rd(open(pf, "rb").read())
    F = pzpack.frames(pages)
    for n in OLD_GROUND:
        F.pop(f"{sheet}_{n}", None)
    F[f"{sheet}_{FURROW_TILE}"] = dp.shrink(furrow, (dp.CELL_W, dp.CELL_H))
    keep = sorted(F.items(), key=lambda kv: int(kv[0].rsplit("_", 1)[1]))
    open(pf, "wb").write(pzpack.wr(ver, pzpack.pack_pages(sheet, 0, keep)))
    tf = MEDIA + f"{sheet}.tiles"
    v, s = tdef.rd(open(tf, "rb").read())
    for n in OLD_GROUND:
        s[0]["tiles"][n] = []
    s[0]["tiles"][FURROW_TILE] = [("CustomName", "Cannabis")]
    open(tf, "wb").write(tdef.wr(v, s))


def main():
    out, blank = layers()
    for name, k in SHEETS:
        frames = []
        for img, cond in out:
            layer = img if k == 1.0 else stretch(img, k, k)
            frames.append(dp.shrink(dp.variant(layer, cond, blank), (dp.CELL_W, dp.CELL_H)))
        pages = write_sheet(name, frames)
        print(name, len(frames), "sprites in", pages, "pages")
    write_furrow()
    print("furrow written; old ground plant sprites dropped")


if __name__ == "__main__":
    main()
