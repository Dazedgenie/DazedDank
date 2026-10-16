"""Grade render_plants_v2.py output exactly like DazedPower (tools/grade_all.py) and put it where
tools/make_overlay_sprites.py looks for plant layers (tools/blender/shapes/<name>.png, 512x1024; the overlay
script does the premultiplied shrink to 128x256).

    python3 tools/blender/plants_v2_post.py <render out dir> [<shapes dir>]
"""
import sys
from pathlib import Path
from PIL import Image, ImageEnhance


def grade(im):                                   # DazedPower tools/grade_all.py
    a = im.getchannel("A")
    rgb = ImageEnhance.Contrast(ImageEnhance.Color(im.convert("RGB")).enhance(0.86)).enhance(0.94)
    rgb = Image.merge("RGB", [c.point(lambda v, k=k: min(255, int(v * k))) for c, k in zip(rgb.split(), (1.02, 1.0, 0.95))])
    out = rgb.convert("RGBA"); out.putalpha(a); return out


def main(src, dst):
    src, dst = Path(src), Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    n = 0
    for p in sorted(src.glob("raw_*.png")):
        grade(Image.open(p).convert("RGBA")).save(dst / (p.stem[4:] + ".png"))
        n += 1
    print(n, "plant layers graded into", dst)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else Path(__file__).parent / "shapes")
