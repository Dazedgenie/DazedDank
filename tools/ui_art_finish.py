"""Copies the Blender UI renders (tools/blender/ui_render.py) into media/ui/DazedDank, grading the grow tent lighter so
it sits in the light card theme. python3 tools/ui_art_finish.py <render dir>"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

SRC = Path(sys.argv[1])
DST = Path(__file__).resolve().parent.parent / "Contents/mods/DazedDank/42/media/ui/DazedDank"


def grade_tent(src, dst):
    """Stretch the mylar's tones into a light, gentle range and keep the dark floor band as it is."""
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(float)
    floor = int(a.shape[0] * 0.933)
    lo, hi = np.percentile(a[:floor], 2), np.percentile(a[:floor], 99.5)
    b = np.clip((a - lo) / (hi - lo), 0, 1)
    b = 0.62 + 0.36 * b ** 0.9
    b[floor:] = a[floor:] / 255 * 1.6
    out = Image.fromarray((np.clip(b, 0, 1) * 255).astype("uint8"))
    ImageEnhance.Color(out).enhance(1.4).save(dst)


for f in sorted(SRC.glob("*.png")):
    if f.name == "photo_tent.png":
        grade_tent(f, DST / f.name)
    else:
        shutil.copy(f, DST / f.name)
    print("->", f.name)
