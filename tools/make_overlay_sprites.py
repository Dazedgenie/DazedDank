"""
make_overlay_sprites.py -- build dazeddank_overlay_01: cannabis plants with no pot or soil, drawn on top of any container.

Two sizes (standard, then XL for the mother pots), each 65 female (5 conditions x 13 slots) and 45 male sprites.
The game raises each one onto its pot's soil, so one set serves every container. Run from the repo root:

    python tools/make_overlay_sprites.py
"""
import math, os, sys, zlib
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import draw_placeholders as dp
import pzpack, tdef

MEDIA = "Contents/mods/DazedDank/42/media/"
SHEET = "dazeddank_overlay_01"
WIDTH = 8
XL_SCALE = 1.10          # the mother-pot plant is 10% bigger, as in make_xl_sprites
PER_SIZE = 110


def scale_about_base(im, k):
    """Scale a supersampled plant layer by k about the point where its stem meets the soil."""
    ax, ay = dp.BASE[0] * dp.S, dp.BASE[1] * dp.S
    W, H = im.size
    big = im.resize((round(W * k), round(H * k)), Image.LANCZOS)
    out = Image.new("RGBA", (W, H))
    out.paste(big, (round(ax - ax * k), round(ay - ay * k)), big)
    return out


def main():
    blank = Image.new("RGBA", (dp.CELL_W * dp.S, dp.CELL_H * dp.S), (0, 0, 0, 0))
    plants = [None] * 13
    for stage in dp.STAGES:
        for t in (["Hybrid"] if stage == "Seedling" else dp.TYPE_ORDER):
            plants[dp.sprite_slot(stage, t)] = dp.draw_plant(t, stage, zlib.crc32(f"{t}/{stage}".encode()))
    males = {(t, s): dp.draw_male(t, s, zlib.crc32(f"male/{t}/{s}".encode())) for t in dp.TYPE_ORDER for s in dp.MALE_STAGES}

    frames = []
    for size, k in enumerate((1.0, XL_SCALE)):
        n = size * PER_SIZE
        for cond in dp.CONDITIONS:
            for slot in range(13):
                layer = plants[slot] if k == 1.0 else scale_about_base(plants[slot], k)
                frames.append((n, dp.shrink(dp.variant(layer, cond, blank), (dp.CELL_W, dp.CELL_H))))
                n += 1
        for cond in dp.CONDITIONS:
            for t in dp.TYPE_ORDER:
                for s in dp.MALE_STAGES:
                    layer = males[(t, s)] if k == 1.0 else scale_about_base(males[(t, s)], k)
                    frames.append((n, dp.shrink(dp.variant(layer, cond, blank), (dp.CELL_W, dp.CELL_H))))
                    n += 1

    named = [(f"{SHEET}_{n}", f) for n, f in frames]
    pages = pzpack.pack_pages(SHEET, 0, named)
    open(MEDIA + f"texturepacks/{SHEET}.pack", "wb").write(pzpack.wr(1, pages))
    rows = math.ceil(len(frames) / WIDTH)
    tiles = [[("CustomName", "Cannabis")] if i < len(frames) else [] for i in range(WIDTH * rows)]
    sheet = dict(name=SHEET, img=SHEET + ".png", w=WIDTH, h=rows, id=1, tiles=tiles)
    open(MEDIA + f"{SHEET}.tiles", "wb").write(tdef.wr(1, [sheet]))
    print("wrote", len(frames), "overlay sprites in", len(pages), "pages")


if __name__ == "__main__":
    main()
