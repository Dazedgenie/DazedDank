"""Draws the Grow Room Panel, blackout curtains and climate equipment, and writes cells plus a manifest for pz-sprite-forge.
Run: python tools/draw_room_art.py out_dir (deterministic, safe to re-run).
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

S = 4                       # supersampling factor
CELL_W, CELL_H = 128, 256   # vanilla 2x tile cell
SHEET = "dazeddank_rooms_01"

# Each facing hangs on one edge of the tile's floor diamond: (edge start x, edge start y, slope of the edge).
# S hangs on the north wall (upper right edge), E on the west wall (upper left), N on the south wall, W on the east wall.
FACINGS = {
    "S": (64, 192, 0.5),
    "E": (0, 224, -0.5),
    "N": (0, 224, 0.5),
    "W": (64, 256, -0.5),
}
FACE_W, FACE_H = 36, 44     # flat panel size in 1x pixels along the wall
LIFT = 118                  # how high the panel's bottom edge hangs above the floor line


def draw_face():
    """The flat front of the panel: housing, screen, three lights and a dial."""
    img = Image.new("RGBA", (FACE_W * S, FACE_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w, h = FACE_W * S, FACE_H * S
    d.rectangle([0, 0, w - 1, h - 1], fill=(30, 32, 40, 255))
    d.rectangle([2 * S, 2 * S, w - 2 * S, h - 2 * S], fill=(58, 62, 74, 255))
    d.rectangle([5 * S, 5 * S, w - 5 * S, 21 * S], fill=(10, 24, 18, 255))
    d.rectangle([6 * S, 6 * S, w - 6 * S, 20 * S], fill=(42, 176, 96, 255))
    for i in range(3):
        d.rectangle([(7 + i * 3) * S, 9 * S, (8 + i * 3) * S, 17 * S], fill=(26, 120, 66, 255))
    for i, color in enumerate(((146, 64, 238, 255), (192, 132, 252, 255), (230, 60, 60, 255))):
        x = (7 + i * 9) * S
        d.ellipse([x, 26 * S, x + 4 * S, 30 * S], fill=color)
    d.ellipse([w - 12 * S, 34 * S, w - 5 * S, 41 * S], fill=(150, 154, 164, 255), outline=(30, 32, 40, 255), width=S // 2)
    d.rectangle([5 * S, 35 * S, 17 * S, 38 * S], fill=(110, 114, 124, 255))
    return img


def hang(face, edge, lift=LIFT):
    """Shear a flat face onto a wall edge of the tile, centred on the edge, its bottom `lift` pixels above the floor line."""
    ex, ey, slope = edge
    fw, fh = face.width // S, face.height // S
    canvas = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    left = ex + (64 - fw) / 2
    x0 = left * S
    y_at_left = (ey + (left - ex) * slope - lift) * S
    # Inverse affine: output (X, Y) -> face (fx, fy) with fy = Y - slope * (X - x0) - (y_at_left - fh * S).
    f = -(y_at_left - fh * S) + slope * x0
    sheared = face.transform(canvas.size, Image.AFFINE, (1.0, 0.0, -x0, -slope, 1.0, f), resample=Image.BICUBIC)
    return sheared.resize((CELL_W, CELL_H), Image.LANCZOS)


def draw_curtain(w, h):
    """A blackout curtain: dark fabric with soft vertical folds hung from a rod."""
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pw, ph = w * S, h * S
    d.rectangle([0, 3 * S, pw - 1, ph - 1], fill=(34, 26, 52, 255))
    folds = max(4, w // 6)
    for i in range(folds):
        x = int((i + 0.5) * pw / folds)
        d.rectangle([x - S, 4 * S, x + S, ph - 2 * S], fill=(52, 40, 78, 255))
        d.rectangle([x + S, 4 * S, x + 2 * S, ph - 2 * S], fill=(22, 16, 36, 255))
    d.rectangle([0, 0, pw - 1, 3 * S], fill=(120, 108, 136, 255))
    d.rectangle([0, ph - 2 * S, pw - 1, ph - 1], fill=(20, 14, 32, 255))
    return img


def draw_fan(accent):
    """A square wall fan: housing with a coloured rim, a round guard, four blades and a hub."""
    size = 34
    img = Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = size * S
    d.rectangle([0, 0, w - 1, w - 1], fill=(30, 32, 40, 255))
    d.rectangle([2 * S, 2 * S, w - 2 * S, w - 2 * S], fill=accent)
    d.rectangle([3 * S, 3 * S, w - 3 * S, w - 3 * S], fill=(88, 92, 104, 255))
    c = w // 2
    r = 13 * S
    d.ellipse([c - r, c - r, c + r, c + r], fill=(20, 22, 28, 255), outline=(150, 154, 164, 255), width=S)
    for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
        x2, y2 = c + dx * 10 * S, c + dy * 10 * S
        d.line([c, c, x2 + dy * 3 * S, y2 + dx * 3 * S], fill=(176, 180, 190, 255), width=4 * S)
    d.ellipse([c - 3 * S, c - 3 * S, c + 3 * S, c + 3 * S], fill=accent)
    for i in range(1, 4):  # guard rings
        rr = r * i // 4 + S
        d.ellipse([c - rr, c - rr, c + rr, c + rr], outline=(120, 124, 134, 255), width=1)
    return img


def place(face, xl, yb, slope):
    """Shear a flat face so its bottom-left corner sits at (xl, yb) and its bottom edge runs with `slope`."""
    fw, fh = face.width // S, face.height // S
    canvas = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    x0 = xl * S
    f = -(yb * S - fh * S) + slope * x0
    sheared = face.transform(canvas.size, Image.AFFINE, (1.0, 0.0, -x0, -slope, 1.0, f), resample=Image.BICUBIC)
    return sheared.resize((CELL_W, CELL_H), Image.LANCZOS), fw, fh


def box_cell(height, top, left, right, left_detail=None, right_detail=None):
    """A floor-standing box on a tile: isometric top, left and right faces with optional flat details sheared onto the sides."""
    a = 36                              # half-width of the footprint on screen
    cx, cy = 64, 224
    T, R, B, L = (cx, cy - a // 2), (cx + a, cy), (cx, cy + a // 2), (cx - a, cy)
    base = Image.new("RGBA", (CELL_W * S, CELL_H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)

    def pts(*ps):
        return [(x * S, y * S) for x, y in ps]

    up = lambda p: (p[0], p[1] - height)
    d.polygon(pts(L, B, up(B), up(L)), fill=left)
    d.polygon(pts(B, R, up(R), up(B)), fill=right)
    d.polygon(pts(up(T), up(R), up(B), up(L)), fill=top)
    out = base.resize((CELL_W, CELL_H), Image.LANCZOS)
    for detail, xl, yb, slope in ((left_detail, L[0], L[1], 0.5), (right_detail, B[0], B[1], -0.5)):
        if detail is not None:
            img, _, _ = place(detail, xl + (a - detail.width // S) // 2, yb - 6 + (a // 2) // 2 * (1 if slope > 0 else -1) - 0, slope)
            out = Image.alpha_composite(out, img)
    return out


def detail(w, h, painter):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    painter(ImageDraw.Draw(img), w * S, h * S)
    return img


def heater_cells():
    def grille(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=(30, 20, 18, 255))
        for i in range(5):
            y = (3 + i * 6) * S
            d.rectangle([3 * S, y, w - 3 * S, y + 3 * S], fill=(255, 140 + i * 12, 40, 255))

    def knob(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=(40, 40, 46, 255))
        d.ellipse([w // 2 - 5 * S, 3 * S, w // 2 + 5 * S, 13 * S], fill=(200, 60, 40, 255), outline=(20, 20, 24, 255), width=S // 2)
    return box_cell(34, (150, 52, 40, 255), (178, 66, 50, 255), (130, 44, 34, 255), detail(26, 24, grille), detail(26, 16, knob))


def dehumidifier_cell():
    def vent(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=(210, 214, 222, 255))
        for i in range(6):
            d.rectangle([3 * S, (3 + i * 4) * S, w - 3 * S, (4 + i * 4) * S], fill=(120, 126, 140, 255))

    def tank(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=(190, 196, 208, 255))
        d.rectangle([3 * S, 4 * S, w - 3 * S, h - 12 * S], fill=(70, 150, 220, 255))
        d.ellipse([w // 2 - 3 * S, h - 9 * S, w // 2 + 3 * S, h - 3 * S], fill=(60, 220, 120, 255))
    return box_cell(46, (226, 230, 238, 255), (200, 205, 216, 255), (170, 176, 190, 255), detail(26, 30, vent), detail(26, 34, tank))


def humidifier_cell():
    def panel(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=(60, 64, 78, 255))
        d.ellipse([w // 2 - 6 * S, 4 * S, w // 2 + 6 * S, 16 * S], fill=(120, 200, 250, 255))
        d.ellipse([w // 2 - 3 * S, 7 * S, w // 2 + 3 * S, 13 * S], fill=(210, 240, 255, 255))

    def mist(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=(200, 232, 248, 255))
        d.rectangle([3 * S, 3 * S, w - 3 * S, h - 3 * S], fill=(150, 205, 238, 255))
        for i in range(3):
            d.ellipse([(5 + i * 6) * S, (6 + (i % 2) * 5) * S, (9 + i * 6) * S, (10 + (i % 2) * 5) * S], fill=(236, 248, 255, 255))
    return box_cell(30, (86, 126, 156, 255), (70, 108, 138, 255), (54, 88, 116, 255), detail(26, 20, panel), detail(26, 22, mist))


def main(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    face = draw_face()
    cells = []
    for i, facing in enumerate(("S", "E", "N", "W")):
        name = f"{i:03d}_panel_{facing}.png"
        hang(face, FACINGS[facing]).save(out / name)
        cells.append({
            "file": name, "facing": "S", "x": 0, "y": 0,
            "props": {
                "IsMoveAble": "", "CustomName": "Grow Room Panel", "GroupName": "Dazed Dank",
                "CustomItem": "CannabisMod.GrowRoomPanel", "Facing": facing,
                "PickUpLevel": "0", "PickUpWeight": "30", "Material": "Metal", "CanScrap": "",
            },
        })
    # Curtain overlays: a door-sized and a window-sized one for each wall edge (N = upper right edge, W = upper left edge).
    door, window = draw_curtain(46, 150), draw_curtain(30, 54)
    edges = {"N": FACINGS["S"], "W": FACINGS["E"]}
    i = len(cells)
    for kind, face, lift in (("door", door, 2), ("window", window, 78)):
        for edge_name in ("N", "W"):
            name = f"{i:03d}_curtain_{kind}_{edge_name}.png"
            hang(face, edges[edge_name], lift).save(out / name)
            # Attached to its wall edge so it draws with the wall, behind people and fittings on the square.
            cells.append({"file": name, "facing": "S", "x": 0, "y": 0,
                          "props": {"attached" + edge_name: "", "CustomName": "Blackout Curtain"}})
            i += 1
    # Climate equipment: fans hang on a wall in four facings (exhaust 8-11, intake 12-15), then three floor units (16-18).
    for kind, label, accent, item in (("exhaust", "Exhaust Fan", (222, 130, 40, 255), "ExhaustFan"), ("intake", "Intake Fan", (60, 150, 222, 255), "IntakeFan")):
        fan = draw_fan(accent)
        for facing in ("S", "E", "N", "W"):
            name = f"{i:03d}_{kind}_{facing}.png"
            hang(fan, FACINGS[facing], 70).save(out / name)
            cells.append({"file": name, "facing": "S", "x": 0, "y": 0, "props": {
                "IsMoveAble": "", "CustomName": label, "GroupName": "Dazed Dank", "CustomItem": "CannabisMod." + item,
                "Facing": facing, "PickUpLevel": "0", "PickUpWeight": "20", "Material": "Metal", "CanScrap": "",
            }})
            i += 1
    for kind, label, item, cell in (("heater", "Heater", "Heater", heater_cells()), ("dehumidifier", "Dehumidifier", "Dehumidifier", dehumidifier_cell()),
                                    ("humidifier", "Humidifier", "Humidifier", humidifier_cell())):
        name = f"{i:03d}_{kind}.png"
        cell.save(out / name)
        cells.append({"file": name, "facing": "S", "x": 0, "y": 0, "props": {
            "IsMoveAble": "", "CustomName": label, "GroupName": "Dazed Dank", "CustomItem": "CannabisMod." + item,
            "PickUpLevel": "0", "PickUpWeight": "30", "Material": "Metal", "CanScrap": "",
        }})
        i += 1
    (out / "manifest.json").write_text(json.dumps({"sheet": SHEET, "cell": [CELL_W, CELL_H], "scale": "2x", "facings": ["S"], "cells": cells}, indent=1))
    print(f"wrote {len(cells)} cells to {out}")


if __name__ == "__main__":
    main(sys.argv[1])
