"""Draws the TSV dumps from preview_tabs.lua into PNG mockups of the panel tabs. Run: python tools/render_previews.py tsv_dir out_dir"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

W, H, TITLE = 560, 392, 28
TABS = ["Lights", "Hydro", "Plants", "Climate", "Log"]


def font(size):
    for name in ("DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "LiberationSans-Regular.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def color(r, g, b):
    return tuple(int(max(0, min(1, float(v))) * 255) for v in (r, g, b))


def render(tsv, out, active):
    small, medium = font(12), font(16)
    img = Image.new("RGB", (W, H + TITLE * 2), (24, 24, 28))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, TITLE], fill=(40, 40, 48))
    d.text((10, 6), "Mother Room - Grow Room Panel", fill=(235, 235, 240), font=small)
    d.rectangle([0, TITLE, W, TITLE * 2], fill=(34, 34, 40))
    x = 8
    for name in TABS:
        on = name.lower() == active
        w = int(d.textlength(name, font=small)) + 28
        d.rectangle([x, TITLE + 3, x + w, TITLE * 2], fill=(92, 40, 150) if on else (52, 52, 62))
        d.text((x + 14, TITLE + 8), name, fill=(255, 255, 255), font=small)
        x += w + 4
    oy = TITLE * 2
    for line in Path(tsv).read_text().splitlines():
        p = line.split("\t")
        if p[0] == "T":
            tx, ty, r, g, b, f, text = float(p[1]), float(p[2]), p[3], p[4], p[5], p[6], "\t".join(p[7:])
            d.text((tx, oy + ty), text, fill=color(r, g, b), font=medium if f == "M" else small)
        elif p[0] == "R":
            rx, ry, rw, rh = (float(v) for v in p[1:5])
            d.rectangle([rx, oy + ry, rx + max(rw - 1, 0), oy + ry + max(rh - 1, 0)], fill=color(*p[5:8]))
        elif p[0] == "B":
            bx, by, bw, on, label = float(p[1]), float(p[2]), float(p[3]), p[4] == "1", p[5]
            d.rectangle([bx, oy + by, bx + bw, oy + by + 24], fill=(146, 64, 238) if on else (38, 38, 46), outline=(150, 150, 178))
            tw = d.textlength(label, font=small)
            d.text((bx + (bw - tw) / 2, oy + by + 5), label, fill=(255, 255, 255), font=small)
    img.save(out)


def main(tsv_dir, out_dir):
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    for name in TABS:
        render(Path(tsv_dir) / f"{name.lower()}.tsv", Path(out_dir) / f"tab_{name.lower()}.png", name.lower())
    print("rendered", len(TABS), "tabs")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
