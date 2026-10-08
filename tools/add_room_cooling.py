"""Adds the wall AC (sprites 32-35) and circulation fan (36-39) to dazeddank_rooms_01, and their inventory icons.
Run: python tools/add_room_cooling.py [renders_dir]  (safe to re-run). With a Blender renders folder from room_art_blender.py
(wall_ac/, circ_fan/ and icons/ inside it) the renders are used; without one, flat placeholder art is drawn.
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
TEXTURES = MEDIA / "textures"
SHEET = "dazeddank_rooms_01"
ROWS = 10                   # the sheet grows to 4 x 10 so indices 32-39 exist
LIFT = 112                  # same height as the other wall units
FACINGS = ("S", "E", "N", "W")
S = art.S

# name in the renders folder, first sprite, display name, item, icon name
UNITS = (
    ("wall_ac", 32, "Wall Air Conditioner", "CannabisMod.WallAC", "WallAC"),
    ("circ_fan", 36, "Circulation Fan", "CannabisMod.CirculationFan", "CirculationFan"),
)


def face(w, h, painter):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    painter(ImageDraw.Draw(img), w * S, h * S)
    return img


def ac(d, w, h):
    """A white split-AC head: rounded body, vent lines on top, a dark louvre along the bottom and a green light."""
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=4 * S, fill=(150, 156, 166, 255))
    d.rounded_rectangle([S, S, w - S, h - 2 * S], radius=4 * S, fill=(236, 239, 243, 255))
    for i in range(6):
        x = (6 + i * 6) * S
        d.rectangle([x, 2 * S, x + 3 * S, 3 * S], fill=(196, 200, 208, 255))
    d.rectangle([3 * S, h - 7 * S, w - 3 * S, h - 3 * S], fill=(58, 62, 72, 255))
    d.rectangle([4 * S, h - 6 * S, w - 4 * S, h - 5 * S], fill=(104, 110, 122, 255))
    d.ellipse([w - 8 * S, 6 * S, w - 5 * S, 9 * S], fill=(70, 220, 130, 255))
    d.rectangle([w - 18 * S, 6 * S, w - 10 * S, 9 * S], fill=(90, 170, 230, 255))


def fan(d, w, h):
    """A wall circulation fan: a wire cage over three blue blades on a short wall bracket."""
    r = min(w, h) // 2
    cx, cy = w // 2, h // 2 - S
    d.rectangle([cx - 3 * S, h - 4 * S, cx + 3 * S, h - 1], fill=(60, 64, 74, 255))
    d.ellipse([cx - r + S, cy - r + S, cx + r - S, cy + r - S], fill=(46, 50, 60, 255))
    d.ellipse([cx - r + 3 * S, cy - r + 3 * S, cx + r - 3 * S, cy + r - 3 * S], fill=(26, 28, 34, 255))
    for k in range(3):
        a0 = k * 120 + 20
        d.pieslice([cx - r + 5 * S, cy - r + 5 * S, cx + r - 5 * S, cy + r - 5 * S], a0, a0 + 55, fill=(90, 160, 220, 255))
    d.ellipse([cx - 3 * S, cy - 3 * S, cx + 3 * S, cy + 3 * S], fill=(200, 204, 212, 255))
    for k in range(4):
        rr = r - (2 + k * 3) * S
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(170, 174, 184, 255), width=max(1, S // 2))


PLACEHOLDER = {"wall_ac": face(44, 18, ac), "circ_fan": face(28, 30, fan)}


def icon(name):
    """A 32x32 inventory icon drawn from the placeholder face."""
    src = PLACEHOLDER[name]
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    small = src.copy()
    small.thumbnail((30, 30), Image.LANCZOS)
    img.paste(small, ((32 - small.width) // 2, (32 - small.height) // 2), small)
    return img


def frames_for(name, renders):
    """Four facing frames for a unit: the Blender renders when there are any, else the placeholder hung on each wall."""
    out = {}
    for facing in FACINGS:
        f = renders and renders / name / f"dd_{name}_{facing}_x0_y0.png"
        if f and f.exists():
            out[facing] = Image.open(f).convert("RGBA")
        else:
            out[facing] = art.hang(PLACEHOLDER[name], art.FACINGS[facing], LIFT)
    return out


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
    used = []
    for name, first, label, item, icon_name in UNITS:
        art_frames = frames_for(name, renders)
        for j, facing in enumerate(FACINGS):
            n = first + j
            frames[f"{SHEET}_{n}"] = art_frames[facing]
            sheet["tiles"][n] = [
                ("IsMoveAble", ""), ("CustomName", label), ("GroupName", "Dazed Dank Wall"), ("CustomItem", item),
                ("Facing", facing), ("MoveType", "WallObject"), ("IsHigh", ""),
                ("PickUpLevel", "0"), ("PickUpWeight", "20"), ("Material", "Metal"), ("CanScrap", ""),
            ]
        rendered_icon = renders and renders / "icons" / f"Item_{icon_name}.png"
        if rendered_icon and rendered_icon.exists():
            ic = Image.open(rendered_icon).convert("RGBA")
            ic = ic.crop(ic.getbbox() or (0, 0, ic.width, ic.height))
            ic.thumbnail((32, 32), Image.LANCZOS)
            out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
            out.paste(ic, ((32 - ic.width) // 2, (32 - ic.height) // 2), ic)
        else:
            out = icon(name)
        out.save(TEXTURES / f"Item_{icon_name}.png")
        used.append("render" if renders and (renders / name).exists() else "placeholder")

    def index(key):
        return int(key.rsplit("_", 1)[1])
    ordered = sorted(frames.items(), key=lambda kv: index(kv[0]))
    new_pages = pzpack.pack_pages(pages[0]["name"][:-1], 0, ordered)
    TILES.write_bytes(tdef.wr(ver, sheets))
    PACK.write_bytes(pzpack.wr(pver, new_pages))
    print(f"sheet {w}x{sheet['h']}, {len(ordered)} sprites; art: {', '.join(used)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
