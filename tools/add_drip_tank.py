"""Adds the drip irrigation tank (sprite 40) to dazeddank_rooms_01, and its inventory icon.
Run: python tools/add_drip_tank.py [renders_dir]  (safe to re-run). With a Blender renders folder from room_art_blender.py
(drip_tank/ and icons/ inside it) the renders are used; without one, placeholder art is drawn.
"""

import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import draw_room_art as art  # noqa: E402
import pzpack  # noqa: E402
import tdef  # noqa: E402

MEDIA = HERE.parent / "Contents/mods/DazedDank/42/media"
TILES = MEDIA / "dazeddank_rooms_01.tiles"
PACK = MEDIA / "texturepacks/dazeddank_rooms_01.pack"
TEXTURES = MEDIA / "textures"
SHEET = "dazeddank_rooms_01"
ROWS = 11                   # the sheet grows to 4 x 11 so index 40 exists
INDEX = 40
S = art.S


def gauge(d, w, h):
    """The tank's side: dark plastic with a sight strip showing the water inside."""
    d.rectangle([0, 0, w - 1, h - 1], fill=(36, 52, 40, 255))
    d.rectangle([w // 2 - 3 * S, 4 * S, w // 2 + 3 * S, h - 4 * S], fill=(70, 96, 80, 255))
    d.rectangle([w // 2 - 2 * S, h // 2, w // 2 + 2 * S, h - 5 * S], fill=(90, 170, 230, 255))
    for i in range(4):
        y = (8 + i * 9) * S
        d.rectangle([w // 2 + 4 * S, y, w // 2 + 7 * S, y + S], fill=(200, 210, 200, 255))


def pump(d, w, h):
    """The pump end: a grey pump with a timer dial and black drip lines running out."""
    d.rectangle([0, 0, w - 1, h - 1], fill=(30, 44, 34, 255))
    d.rectangle([4 * S, h - 18 * S, w - 4 * S, h - 4 * S], fill=(120, 126, 136, 255))
    d.ellipse([w // 2 - 4 * S, h - 15 * S, w // 2 + 4 * S, h - 7 * S], fill=(230, 230, 236, 255), outline=(30, 30, 34, 255), width=S // 2)
    for i in range(3):
        x = (5 + i * 7) * S
        d.rectangle([x, 4 * S, x + S, h - 20 * S], fill=(16, 16, 18, 255))


def placeholder():
    return art.box_cell(48, (48, 72, 54, 255), (40, 60, 46, 255), (30, 46, 36, 255),
                        art.detail(26, 40, gauge), art.detail(26, 40, pump))


def main(renders=None):
    renders = Path(renders) if renders else None
    ver, sheets = tdef.rd(TILES.read_bytes())
    sheet = sheets[0]
    w = sheet["w"]
    while len(sheet["tiles"]) < w * ROWS:
        sheet["tiles"].append([])
    sheet["h"] = max(sheet["h"], ROWS)

    pver, pages = pzpack.rd(PACK.read_bytes())
    frames = pzpack.frames(pages)
    rendered = sorted((renders / "drip_tank").glob("dd_drip_tank_*_x0_y0.png")) if renders and (renders / "drip_tank").exists() else []
    frames[f"{SHEET}_{INDEX}"] = Image.open(rendered[0]).convert("RGBA") if rendered else placeholder()
    sheet["tiles"][INDEX] = [
        ("IsMoveAble", ""), ("CustomName", "Drip Irrigation Tank"), ("GroupName", "Dazed Dank"),
        ("CustomItem", "CannabisMod.DripTank"), ("PickUpLevel", "0"), ("PickUpWeight", "30"),
        ("Material", "Plastic"), ("CanScrap", ""), ("solidtrans", ""),
    ]

    icon_src = renders and renders / "icons" / "Item_DripTank.png"
    if icon_src and icon_src.exists():
        src = Image.open(icon_src).convert("RGBA")
    else:
        src = frames[f"{SHEET}_{INDEX}"]
    src = src.crop(src.getbbox() or (0, 0, src.width, src.height))
    src.thumbnail((32, 32), Image.LANCZOS)
    icon = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    icon.paste(src, ((32 - src.width) // 2, (32 - src.height) // 2), src)
    icon.save(TEXTURES / "Item_DripTank.png")

    def index(key):
        return int(key.rsplit("_", 1)[1])
    ordered = sorted(frames.items(), key=lambda kv: index(kv[0]))
    new_pages = pzpack.pack_pages(pages[0]["name"][:-1], 0, ordered)
    TILES.write_bytes(tdef.wr(ver, sheets))
    PACK.write_bytes(pzpack.wr(pver, new_pages))
    print(f"sheet {w}x{sheet['h']}, {len(ordered)} sprites; art: {'render' if rendered else 'placeholder'}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
