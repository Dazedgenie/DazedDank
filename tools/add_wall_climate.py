"""Placeholder art for the wall-mounted climate units (sprites 20-31); superseded by the Blender renders from tools/room_art_blender.py.
Run: python tools/add_wall_climate.py (rewrites dazeddank_rooms_01.tiles and its pack; safe to re-run).
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import draw_room_art as art  # noqa: E402
import pzpack  # noqa: E402
import tdef  # noqa: E402

MEDIA = HERE.parent / "Contents/mods/DazedDank/42/media"
TILES = MEDIA / "dazeddank_rooms_01.tiles"
PACK = MEDIA / "texturepacks/dazeddank_rooms_01.pack"
SHEET = "dazeddank_rooms_01"
FIRST = 20                  # first new sprite; each unit takes four (S, E, N, W)
ROWS = 8                    # the sheet grows to 4 x 8 so indices 20-31 exist
LIFT = 112                  # bottom edge this far above the floor line: up high like an overhead cupboard
S = art.S


def face(w, h, painter):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    painter(ImageDraw.Draw(img), w * S, h * S)
    return img


def heater(d, w, h):
    """A red wall heater: dark frame, glowing element bars and a dial."""
    d.rectangle([0, 0, w - 1, h - 1], fill=(40, 26, 24, 255))
    d.rectangle([2 * S, 2 * S, w - 2 * S, h - 2 * S], fill=(168, 58, 44, 255))
    for i in range(4):
        y = (5 + i * 5) * S
        d.rectangle([5 * S, y, w - 12 * S, y + 2 * S], fill=(255, 150 + i * 20, 50, 255))
    d.ellipse([w - 10 * S, 6 * S, w - 4 * S, 12 * S], fill=(230, 230, 236, 255), outline=(30, 30, 34, 255), width=S // 2)


def dehumidifier(d, w, h):
    """A white wall unit: louvred vent, a blue water window and a green light."""
    d.rectangle([0, 0, w - 1, h - 1], fill=(120, 126, 140, 255))
    d.rectangle([2 * S, 2 * S, w - 2 * S, h - 2 * S], fill=(222, 226, 234, 255))
    for i in range(5):
        y = (4 + i * 3) * S
        d.rectangle([4 * S, y, w - 4 * S, y + S], fill=(130, 136, 150, 255))
    d.rectangle([4 * S, h - 10 * S, w // 2, h - 4 * S], fill=(70, 150, 220, 255))
    d.ellipse([w - 9 * S, h - 9 * S, w - 5 * S, h - 5 * S], fill=(60, 220, 120, 255))


def humidifier(d, w, h):
    """A slate-blue wall unit with a misting nozzle and puffs of mist."""
    d.rectangle([0, 0, w - 1, h - 1], fill=(40, 48, 62, 255))
    d.rectangle([2 * S, 2 * S, w - 2 * S, h - 2 * S], fill=(78, 116, 146, 255))
    d.ellipse([w // 2 - 6 * S, 5 * S, w // 2 + 6 * S, 17 * S], fill=(120, 200, 250, 255))
    d.ellipse([w // 2 - 3 * S, 8 * S, w // 2 + 3 * S, 14 * S], fill=(220, 244, 255, 255))
    for i in range(3):
        d.ellipse([(6 + i * 8) * S, h - 8 * S, (10 + i * 8) * S, h - 4 * S], fill=(236, 248, 255, 220))


UNITS = (
    ("Heater", "CannabisMod.Heater", face(34, 26, heater)),
    ("Dehumidifier", "CannabisMod.Dehumidifier", face(34, 30, dehumidifier)),
    ("Humidifier", "CannabisMod.Humidifier", face(34, 26, humidifier)),
)


def main():
    ver, sheets = tdef.rd(TILES.read_bytes())
    sheet = sheets[0]
    w = sheet["w"]
    while len(sheet["tiles"]) < w * ROWS:
        sheet["tiles"].append([])
    sheet["h"] = ROWS

    pver, pages = pzpack.rd(PACK.read_bytes())
    frames = pzpack.frames(pages)

    n = FIRST
    for label, item, img in UNITS:
        for facing in ("S", "E", "N", "W"):
            frames[f"{SHEET}_{n}"] = art.hang(img, art.FACINGS[facing], LIFT)
            sheet["tiles"][n] = [
                ("IsMoveAble", ""), ("CustomName", label), ("GroupName", "Dazed Dank Wall"), ("CustomItem", item),
                ("Facing", facing), ("MoveType", "WallObject"), ("IsHigh", ""),
                ("PickUpLevel", "0"), ("PickUpWeight", "30"), ("Material", "Metal"), ("CanScrap", ""),
            ]
            n += 1

    def index(name):
        return int(name.rsplit("_", 1)[1])
    ordered = sorted(frames.items(), key=lambda kv: index(kv[0]))
    new_pages = pzpack.pack_pages(pages[0]["name"][:-1], 0, ordered)
    TILES.write_bytes(tdef.wr(ver, sheets))
    PACK.write_bytes(pzpack.wr(pver, new_pages))
    print(f"sheet {w}x{ROWS}, {len(ordered)} sprites in {len(new_pages)} page(s): {[p['name'] for p in new_pages]}")


if __name__ == "__main__":
    main()
