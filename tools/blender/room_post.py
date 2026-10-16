"""Grade, shrink and install room_render.py output, exactly like DazedPower (tools/grade_all.py + tools/import_art.py).

    python3 tools/blender/room_post.py <render out dir> <final dir>            # grade + shrink only
    python3 tools/blender/room_post.py <render out dir> <final dir> --install  # ... then repack and copy icons

<render out>/cells/<index>.png (256x512) -> <final>/cells/<index>.png (128x256); a floor unit's <index>_s.png contact
shadow pass is laid under it first. <render out>/icons/Item_*.png (256x256) -> <final>/icons/Item_*.png (32x32).

--install replaces those frames in 42/media/texturepacks/dazeddank_rooms_01.pack (every other frame is kept, the
.tiles file is not touched, so indices, names and tile properties stay as they are), copies the icons into
42/media/textures and rebuilds common/media/depthmaps/DEPTH_dazeddank_rooms_01.png with tools/make_room_depth.py.
"""
import os
import sys
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import pzpack  # noqa: E402

MEDIA = REPO / "Contents/mods/DazedDank/42/media"
PACK = MEDIA / "texturepacks/dazeddank_rooms_01.pack"
TEXTURES = MEDIA / "textures"
SHEET = "dazeddank_rooms_01"
CW, CH = 128, 256
SHADOW = 0.85                                    # strength of the contact shadow pass


def grade(im):                                   # grade_all.py
    a = im.getchannel("A")
    rgb = ImageEnhance.Contrast(ImageEnhance.Color(im.convert("RGB")).enhance(0.86)).enhance(0.94)
    rgb = Image.merge("RGB", [c.point(lambda v, k=k: min(255, int(v * k))) for c, k in zip(rgb.split(), (1.02, 1.0, 0.95))])
    out = rgb.convert("RGBA"); out.putalpha(a); return out


def shrink(im):                                  # import_art.py
    small = im.convert("RGBa").resize((CW, CH), Image.LANCZOS)
    small = small.filter(ImageFilter.UnsharpMask(radius=0.8, percent=70, threshold=1))
    return small.convert("RGBA")


def icon(im):                                    # import_art.py
    im = im.crop(im.getbbox()).convert("RGBa")
    im.thumbnail((30, 30), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=1)).convert("RGBA")
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.alpha_composite(im, ((32 - im.width) // 2, (32 - im.height) // 2))
    return out


def with_shadow(im, sp):
    """Lay the contact pass under the unit: keep the occlusion near it, drop the catcher's flat sky darkening."""
    sh = Image.open(sp).convert("RGBA")
    a = sh.getchannel("A")
    vals = sorted(v for v in (a.get_flattened_data() if hasattr(a, "get_flattened_data") else a.getdata()) if v > 0)
    base = vals[len(vals) // 2] + 6 if vals else 0
    a = a.point(lambda v: max(0, min(255, int((v - base) * 255 / max(1, 255 - base) * SHADOW))))
    out = Image.new("RGBA", sh.size, (24, 22, 18, 0)); out.putalpha(a)
    out.alpha_composite(im)
    return out


def post(src, dst):
    src, dst = Path(src), Path(dst)
    (dst / "cells").mkdir(parents=True, exist_ok=True); (dst / "icons").mkdir(parents=True, exist_ok=True)
    n = 0
    for p in sorted((src / "cells").glob("*.png")):
        if not p.stem.isdigit(): continue
        im = grade(Image.open(p).convert("RGBA"))
        sp = p.with_name(p.stem + "_s.png")
        if sp.exists(): im = with_shadow(im, sp)
        shrink(im).save(dst / "cells" / p.name); n += 1
    for p in sorted((src / "icons").glob("*.png")):
        icon(grade(Image.open(p).convert("RGBA"))).save(dst / "icons" / p.name); n += 1
    print(n, "files graded and shrunk")


def install(dst):
    dst = Path(dst)
    ver, pages = pzpack.rd(PACK.read_bytes())
    frames = pzpack.frames(pages)
    replaced = []
    for p in sorted((dst / "cells").glob("*.png"), key=lambda q: int(q.stem)):
        name = f"{SHEET}_{int(p.stem)}"
        if name not in frames: raise SystemExit(f"{name} is not in the pack; refusing to add new sprites")
        im = Image.open(p).convert("RGBA")
        assert im.size == (CW, CH), (p, im.size)
        frames[name] = im; replaced.append(int(p.stem))
    ordered = sorted(frames.items(), key=lambda kv: int(kv[0].rsplit("_", 1)[1]))
    new_pages = pzpack.pack_pages(pages[0]["name"][:-1], 0, ordered)
    PACK.write_bytes(pzpack.wr(ver, new_pages))
    print(f"pack: replaced {len(replaced)} of {len(ordered)} frames, {len(new_pages)} page(s): {[q['name'] for q in new_pages]}")
    for p in sorted((dst / "icons").glob("Item_*.png")):
        Image.open(p).save(TEXTURES / p.name); print("icon", p.name)
    cwd = os.getcwd()
    try:
        os.chdir(REPO)
        import make_room_depth
        make_room_depth.main()
    finally:
        os.chdir(cwd)


if __name__ == "__main__":
    post(sys.argv[1], sys.argv[2])
    if "--install" in sys.argv[3:]: install(sys.argv[2])
