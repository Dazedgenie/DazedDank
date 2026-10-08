# Writes common/media/depthmaps/DEPTH_dazeddank_rooms_01.png so Build 42 knows how deep each grow-room tile is.
# Without it the game treats every pixel as the front of a solid block filling the square, so a curtain or a
# wall fan hides a player standing on its square. Run from the repo root after changing the room art.
import os
import sys

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import pzdepth
import pzpack

MOD = "Contents/mods/DazedDank"
SHEET = "dazeddank_rooms_01"
PACK = f"{MOD}/42/media/texturepacks/{SHEET}.pack"
OUT = f"{MOD}/common/media/depthmaps/DEPTH_{SHEET}.png"

# Wall pieces by tile: the edge they hang on and how far their front stands off it, in squares.
# Facing S hangs on the north edge, E on the west, N on the south and W on the east.
FACING_EDGE = ("N", "W", "S", "E")
# Curtains sit flush in the frame (0.03), so nobody can stand between a curtain and its door.
WALL = {4: ("N", 0.03), 5: ("W", 0.03), 6: ("N", 0.03), 7: ("W", 0.03)}
for first, standoff in ((0, 0.12), (8, 0.20), (12, 0.20), (20, 0.22), (24, 0.22), (28, 0.22), (32, 0.26), (36, 0.22)):
    for k in range(4):
        WALL[first + k] = (FACING_EDGE[k], standoff)
FLOOR = (16, 17, 18)   # free-standing units in the middle of the square


def slab(edge, t):
    """The box a wall piece fills, and the face of it the camera sees."""
    lo, hi = [-0.5, 0.0, -0.5], [0.5, pzdepth.LEVEL, 0.5]
    axis = 2 if edge in ("N", "S") else 0
    if edge in ("N", "W"):
        hi[axis] = -0.5 + t
    else:
        lo[axis] = 0.5 - t
    return lo, hi, axis, hi[axis]


def tile_depth(frame, index):
    """One 128x256 depth tile for a sprite frame: grey = depth, clear where the sprite is clear."""
    out = Image.new("RGBA", frame.size)
    alpha = frame.split()[3].point(lambda a: 255 if a > 0 else 0)
    mask = alpha.filter(ImageFilter.MaxFilter(3)).load()
    if index in WALL:
        lo, hi, axis, face = slab(*WALL[index])
    else:
        bb = frame.getbbox()
        h = min(0.5, max(0.15, (bb[3] - 224) / 64)) if bb else 0.5
        lo, hi, axis, face = [-h, 0.0, -h], [h, pzdepth.LEVEL, h], 2, h
    px = out.load()
    for y in range(frame.size[1]):
        for x in range(frame.size[0]):
            if not mask[x, y]:
                continue
            d = pzdepth.box_depth(x, y, lo, hi)
            if d is None:
                d = pzdepth.plane_depth(x, y, axis, face)
            v = max(0, min(255, round(d * 255)))
            px[x, y] = (v, v, v, 255)
    return out


def main():
    _, pages = pzpack.rd(open(PACK, "rb").read())
    frames = pzpack.frames(pages)
    count = max(int(n.rsplit("_", 1)[1]) for n in frames if n.startswith(SHEET + "_")) + 1
    rows = (count + 7) // 8   # the game reads depth sheets 8 tiles wide, whatever the tile sheet's own width
    sheet = Image.new("RGBA", (8 * 128, rows * 256))
    for i in range(count):
        frame = frames.get(f"{SHEET}_{i}")
        if frame is not None:
            sheet.paste(tile_depth(frame, i), ((i % 8) * 128, (i // 8) * 256))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT, optimize=True)
    print(f"wrote {OUT} ({count} tiles)")


if __name__ == "__main__":
    main()
