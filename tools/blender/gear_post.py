"""Grade, shrink, compare and install render_gear.py output (and room_render.py's), like DazedPower's
grade_all.py + import_art.py, through the same functions as room_post.py.

    python3 tools/blender/gear_post.py post <render out> <final dir>       # grade + shrink cells and icons
    python3 tools/blender/gear_post.py compare <final dir> <sheet dir>     # old | new contact sheets at 2x
    python3 tools/blender/gear_post.py install <final dir>                 # repack the frames, copy the icons

<render out>/<sheet>/<index>.png (256x512, with an optional <index>_s.png contact pass) -> <final>/<sheet>/<index>.png
(128x256). Cells of plants_01 and hydro_01 are moved down 2 px (1x) first: those sheets' plants were rendered by
render_plants.py with the ground origin at row 226, this rig puts it at 224, and the pots must stay under the plants.
<render out>/icons/Item_*.png (256x256) -> <final>/icons/Item_*.png (32x32); the XL items get the old XL badge back.

install replaces only the frames found in <final>/<sheet>/ in 42/media/texturepacks/dazeddank_<sheet>.pack; every
other frame, the .tiles files and the sprite names stay as they are. It refuses a frame name the pack doesn't have.
"""
import io
import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(HERE))
import pzpack  # noqa: E402
from room_post import grade, shrink, icon, with_shadow  # noqa: E402

MEDIA = REPO / "Contents/mods/DazedDank/42/media"
TEXTURES = MEDIA / "textures"
SHEETS = ("plants_01", "hydro_01", "rooms_01")
SHIFT = {"plants_01": 2, "hydro_01": 2, "rooms_01": 0}          # 1x pixels down
XL_BADGE = ("GrowBagXL", "DWCBucketXL")


def pack_path(sheet):
    return MEDIA / "texturepacks" / f"dazeddank_{sheet}.pack"


def old_frames(sheet):
    return pzpack.frames(pzpack.rd(pack_path(sheet).read_bytes())[1])


def moved(im, dy):
    if not dy: return im
    out = Image.new("RGBA", im.size); out.paste(im, (0, dy)); return out


def badge(old_icon):
    """The XL badge from the old icon: its gold-on-dark pixels in the top-left corner."""
    out = Image.new("RGBA", old_icon.size)
    px, po = old_icon.load(), out.load()
    for y in range(12):
        for x in range(14):
            r, g, b, a = px[x, y]
            if a > 0: po[x, y] = (r, g, b, a)
    return out


def post(src, dst):
    src, dst = Path(src), Path(dst)
    n = 0
    for sheet in SHEETS:
        d = src / sheet
        if not d.is_dir(): continue
        (dst / sheet).mkdir(parents=True, exist_ok=True)
        for p in sorted(d.glob("*.png")):
            if not p.stem.isdigit(): continue
            im = grade(Image.open(p).convert("RGBA"))
            sp = p.with_name(p.stem + "_s.png")
            if sp.exists(): im = with_shadow(im, sp)
            shrink(moved(im, SHIFT[sheet] * 2)).save(dst / sheet / p.name); n += 1
    if (src / "icons").is_dir():
        (dst / "icons").mkdir(parents=True, exist_ok=True)
        for p in sorted((src / "icons").glob("Item_*.png")):
            ic = icon(grade(Image.open(p).convert("RGBA")))
            if p.stem[5:] in XL_BADGE:
                ic.alpha_composite(badge(Image.open(TEXTURES / p.name).convert("RGBA")))
            ic.save(dst / "icons" / p.name); n += 1
    print(n, "files graded and shrunk")


def font(sz):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",):
        if os.path.exists(f): return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def compare(final, out, per_row=3):
    """Per sheet: each changed sprite as old | new at 2x on a floor diamond, labelled; split into parts ~2000 px wide."""
    final, out = Path(final), Path(out); out.mkdir(parents=True, exist_ok=True)
    f, fs = font(18), font(14)
    for sheet in SHEETS:
        d = final / sheet
        if not d.is_dir(): continue
        old = old_frames(sheet)
        idx = sorted(int(p.stem) for p in d.glob("*.png") if p.stem.isdigit())
        # identical old+new pairs are shown once
        seen, shown = {}, []
        for i in idx:
            key = (old[f"dazeddank_{sheet}_{i}"].tobytes(), Image.open(d / f"{i}.png").tobytes())
            if key in seen: seen[key].append(i); continue
            seen[key] = [i]; shown.append(seen[key])
        W, H = 256, 512; cw = 2 * W + 16
        rows = [shown[k:k + per_row] for k in range(0, len(shown), per_row)]
        parts = [rows[k:k + 2] for k in range(0, len(rows), 2)]
        for pi, part in enumerate(parts):
            sh = Image.new("RGBA", (per_row * cw, len(part) * (H + 50)), (52, 54, 58, 255)); dr = ImageDraw.Draw(sh)
            for r, row in enumerate(part):
                for c, grp in enumerate(row):
                    x, y = c * cw, r * (H + 50)
                    for k, im in enumerate((old[f"dazeddank_{sheet}_{grp[0]}"], Image.open(d / f"{grp[0]}.png"))):
                        ox = x + k * W
                        dr.polygon([(ox + 128, y + 30 + 384), (ox + 256, y + 30 + 448), (ox + 128, y + 30 + 512), (ox, y + 30 + 448)],
                                   outline=(96, 100, 104))
                        sh.alpha_composite(im.convert("RGBA").resize((W, H), Image.NEAREST), (ox, y + 30))
                    txt = ",".join(str(i) for i in grp) if len(grp) < 5 else f"{grp[0]}..{grp[-1]} ({len(grp)})"
                    dr.text((x + 6, y + 6), txt, fill=(255, 230, 120), font=f)
                    dr.text((x + 6, y + H + 30), "old", fill=(200, 200, 200), font=fs)
                    dr.text((x + W + 6, y + H + 30), "new", fill=(140, 230, 140), font=fs)
            name = out / (f"{sheet}.png" if len(parts) == 1 else f"{sheet}_{pi + 1}.png")
            sh.save(name); print("wrote", name, sh.size)
    icons = sorted((final / "icons").glob("Item_*.png")) if (final / "icons").is_dir() else []
    if icons:
        cols = 8; cw, chh = 230, 140
        sh = Image.new("RGBA", (cols * cw, ((len(icons) + cols - 1) // cols) * chh), (52, 54, 58, 255)); dr = ImageDraw.Draw(sh)
        for k, p in enumerate(icons):
            x, y = (k % cols) * cw, (k // cols) * chh
            for j, im in enumerate((Image.open(TEXTURES / p.name), Image.open(p))):
                sh.alpha_composite(im.convert("RGBA").resize((96, 96), Image.NEAREST), (x + 8 + j * 106, y + 8))
            dr.text((x + 8, y + 110), p.stem[5:], fill=(230, 230, 230), font=fs)
        sh.save(out / "icons.png"); print("wrote", out / "icons.png", sh.size)


def install(final):
    final = Path(final)
    for sheet in SHEETS:
        d = final / sheet
        if not d.is_dir(): continue
        pk = pack_path(sheet)
        ver, pages = pzpack.rd(pk.read_bytes())
        frames = pzpack.frames(pages)
        replaced = []
        for p in sorted(d.glob("*.png"), key=lambda q: int(q.stem) if q.stem.isdigit() else -1):
            if not p.stem.isdigit(): continue
            name = f"dazeddank_{sheet}_{int(p.stem)}"
            if name not in frames: raise SystemExit(f"{name} is not in the pack; refusing to add new sprites")
            im = Image.open(p).convert("RGBA"); assert im.size == (128, 256), (p, im.size)
            frames[name] = im; replaced.append(int(p.stem))
        ordered = sorted(frames.items(), key=lambda kv: int(kv[0].rsplit("_", 1)[1]))
        new_pages = pzpack.pack_pages(pages[0]["name"][:-1], 0, ordered)
        pk.write_bytes(pzpack.wr(ver, new_pages))
        print(f"{sheet}: replaced {len(replaced)} of {len(ordered)} frames, pages {[q['name'] for q in new_pages]}")
    if (final / "icons").is_dir():
        for p in sorted((final / "icons").glob("Item_*.png")):
            if not (TEXTURES / p.name).exists(): raise SystemExit(f"{p.name} is not an existing icon")
            Image.open(p).save(TEXTURES / p.name); print("icon", p.name)
    if (final / "rooms_01").is_dir():
        cwd = os.getcwd()
        try:
            os.chdir(REPO); import make_room_depth; make_room_depth.main()
        finally:
            os.chdir(cwd)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "post": post(sys.argv[2], sys.argv[3])
    elif cmd == "compare": compare(sys.argv[2], sys.argv[3])
    elif cmd == "install": install(sys.argv[2])
    else: raise SystemExit(__doc__)
