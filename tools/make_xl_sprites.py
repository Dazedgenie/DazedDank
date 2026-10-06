"""
Retired: plants in pots are now drawn from dazeddank_overlay_01 (tools/make_overlay_sprites.py), and the pot+plant
sprites this script read and wrote have been dropped from the packs. Kept for the empty XL pot art.

make_xl_sprites.py -- build the XL Grow Bag and XL DWC Bucket sprites from the large bag and DWC renders.

Scales the empty pot up 25% about its footprint and lifts the plant (10% bigger) onto the new rim, then
writes the 226 sprites into dazeddank_hydro_01 (tiles 235-460) and their tile properties. Safe to re-run:
old XL entries are replaced. Run from the repo root after re-rendering the large bag or DWC:

    python tools/make_xl_sprites.py
"""
import math, os, sys
from PIL import Image, ImageChops
sys.path.insert(0, os.path.dirname(__file__))
import pzpack, tdef

MEDIA = "Contents/mods/DazedDank/42/media/"
SRC = "dazeddank_plants_01_"
DST = "dazeddank_hydro_01_"
# kind: source sprites (furn, dry, empty, first plant, first male), footprint y, soil y, then where they go on the hydro sheet.
KINDS = {
    "xlbag": dict(furn=204, dry=202, empty=196, plant=130, male=327, ay=245, rim=180,
                  to=dict(furn=235, empty=236, dry=237, plant=238, male=303), name="XL Grow Bag", weight="20"),
    "xldwc": dict(furn=372, dry=373, empty=374, plant=375, male=440, ay=238, rim=182,
                  to=dict(furn=348, dry=349, empty=350, plant=351, male=416), name="XL DWC Bucket", weight="30"),
}
POT_SCALE, PLANT_SCALE, AX = 1.25, 1.10, 64


def scale_about(im, k, ax, ay):
    """Scale a frame by k about (ax, ay), keeping its size."""
    W, H = im.size
    big = im.resize((round(W * k), round(H * k)), Image.LANCZOS)
    out = Image.new("RGBA", (W, H))
    out.paste(big, (round(ax - ax * k), round(ay - ay * k)), big)
    return out


def plant_layer(sprite, base, thresh=18):
    """The pixels of a plant sprite that differ from the empty pot."""
    diff = ImageChops.difference(sprite, base).convert("L").point(lambda v: 255 if v > thresh else 0)
    mask = ImageChops.multiply(diff, sprite.getchannel("A"))
    out = Image.new("RGBA", sprite.size)
    out.paste(sprite, (0, 0), mask)
    return out


def build(F, d):
    pot = lambda im: scale_about(im, POT_SCALE, AX, d["ay"])
    base = F[SRC + str(d["empty"])]
    dy = round(-(d["ay"] - d["rim"]) * (POT_SCALE - 1))

    def compose(src):
        pl = scale_about(plant_layer(src, base), PLANT_SCALE, AX, d["rim"])
        out = pot(base)
        moved = Image.new("RGBA", out.size)
        moved.paste(pl, (0, dy), pl)
        out.alpha_composite(moved)
        return out

    t = d["to"]
    out = [(t["furn"], pot(F[SRC + str(d["furn"])])), (t["dry"], pot(F[SRC + str(d["dry"])])), (t["empty"], pot(base))]
    out += [(t["plant"] + i, compose(F[SRC + str(d["plant"] + i)])) for i in range(65)]
    out += [(t["male"] + i, compose(F[SRC + str(d["male"] + i)])) for i in range(45)]
    return out


def main():
    _, ppages = pzpack.rd(open(MEDIA + "texturepacks/dazeddank_plants_01.pack", "rb").read())
    F = pzpack.frames(ppages)
    made = []
    for d in KINDS.values():
        made += build(F, d)
    names = {DST + str(n) for n, _ in made}

    hp = MEDIA + "texturepacks/dazeddank_hydro_01.pack"
    ver, pages = pzpack.rd(open(hp, "rb").read())
    # Drop old XL entries; a page left holding none of the rest is dropped, and the others are re-packed with new pages.
    keep_frames = pzpack.frames(pages)
    keep = [(n, f) for n, f in keep_frames.items() if n not in names]
    old_pages = [pg for pg in pages if not any(e[0] in names for e in pg["ents"])]
    loose = [(n, f) for n, f in keep if not any(n == e[0] for pg in old_pages for e in pg["ents"])]
    stem = "dazeddank_hydro_01"
    new_pages = pzpack.pack_pages(stem, len(old_pages), loose + [(DST + str(n), f) for n, f in made])
    open(hp, "wb").write(pzpack.wr(ver, old_pages + new_pages))

    tf = MEDIA + "dazeddank_hydro_01.tiles"
    ver, sheets = tdef.rd(open(tf, "rb").read())
    sh = sheets[0]
    top = max(n for n, _ in made) + 1
    sh["h"] = max(sh["h"], math.ceil(top / sh["w"]))
    while len(sh["tiles"]) < sh["w"] * sh["h"]:
        sh["tiles"].append([])
    for d in KINDS.values():
        t = d["to"]
        sh["tiles"][t["furn"]] = [("CustomName", d["name"]), ("IsMoveAble", ""), ("IsLow", ""),
                                  ("PickUpWeight", d["weight"]), ("Material", "Plastic"), ("solidtrans", "")]
        for n in [t["empty"], t["dry"]] + list(range(t["plant"], t["plant"] + 65)) + list(range(t["male"], t["male"] + 45)):
            sh["tiles"][n] = [("CustomName", "Cannabis"), ("solidtrans", "")]
    open(tf, "wb").write(tdef.wr(ver, sheets))
    print("wrote", len(made), "XL sprites;", len(old_pages + new_pages), "pages")


if __name__ == "__main__":
    main()
