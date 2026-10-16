"""Procedural cannabis leaf textures (RGBA) for the alpha leaf cards of render_plants_v2.py.

Fan leaf: n serrated lanceolate leaflets radiating from the card centre; leaflet 0 points to -Y in the image
(= +V, the leaf's forward direction on the card). Variants bake the colour: green, young, yellowing (yellow1 a little,
yellow2 late-flower fade), plus frosty sugar leaves and the seedling's first leaves. One set per leaflet-width class
(t14 = slender sativa leaflets ... t46 = broad afghan ones); render_plants_v2.py picks the class per shape.

    python3 tools/blender/plant_textures.py tools/blender/shapes/tex        (about 40 s on 4 cores; skips existing files)
"""
import math, random, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 2                       # supersample
N = 1024                     # final texture size


def leaflet_poly(cx, cy, ang, length, width, teeth, rng, start=0.03):
    """Outline of one serrated leaflet from the centre outward along `ang` (0 = up in the image)."""
    d = (math.sin(ang), -math.cos(ang))
    nrm = (math.cos(ang), math.sin(ang))
    steps = teeth * 6
    left, right = [], []
    amp = 0.022 * length
    for k in range(steps + 1):
        t = k / steps
        # lanceolate: widest about a third of the way out, long tapered tip
        w = width * 0.5 * (math.sin(math.pi * min(1.0, t ** 0.75)) ** 0.9)
        w *= 1.0 - 0.15 * t
        if t < 0.06:
            w *= t / 0.06
        # sawtooth serration, teeth pointing toward the tip
        ph = (t * teeth) % 1.0
        s = amp * (ph ** 1.6) * min(1.0, t * 5) * (1 - t) ** 0.3
        r = start * length + t * length * (1 - start)
        for side, lst in ((1, left), (-1, right)):
            ww = w + s * (1.0 + 0.15 * rng.uniform(-1, 1))
            lst.append((cx + d[0] * r + nrm[0] * ww * side, cy + d[1] * r + nrm[1] * ww * side))
    return left + right[::-1], d, nrm


def fan_leaf(n, thin=0.17, spread=105.0, col=(60, 94, 40), yellow=0.0, young=0.0, frost=0.0, seed=1, size=N):
    rng = random.Random(seed)
    S = size * SS
    cx, cy = S / 2, S / 2
    R = S * 0.48
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    vein = Image.new("L", (S, S), 0)
    lid = Image.new("L", (S, S), 0)          # which leaflet (for per-leaflet tone)
    dr, dv, dl = ImageDraw.Draw(img), ImageDraw.Draw(vein), ImageDraw.Draw(lid)
    m = (n - 1) // 2
    order = sorted(range(-m, m + 1), key=lambda j: -abs(j))        # draw outer ones first, centre on top
    for j in order:
        a = 0.0 if m == 0 else math.radians(j * spread / m + rng.uniform(-4, 4))
        fall = abs(j) / max(m, 1)
        length = R * (1.0 - 0.62 * fall ** 1.5) * rng.uniform(0.94, 1.0)
        if n == 1:
            length = R
        width = length * thin * (1.0 + 0.25 * fall)
        poly, d, nrm = leaflet_poly(cx, cy, a, length, width, 17 if n > 1 else 13, rng)
        dl.polygon(poly, fill=60 + (j + m) * 20)
        dr.polygon(poly, fill=(255, 255, 255, 255))
        # midrib
        dv.line([(cx + d[0] * length * 0.03, cy + d[1] * length * 0.03), (cx + d[0] * length * 0.97, cy + d[1] * length * 0.97)],
                fill=255, width=max(2, int(S * 0.0045)))
        # secondary veins: from midrib toward the margin, angled to the tip
        for k in range(1, 14):
            t = k / 14.0
            r = length * (0.06 + 0.86 * t)
            w = width * 0.5 * (math.sin(math.pi * min(1.0, t ** 0.75)) ** 0.9) * 0.9
            for side in (1, -1):
                p0 = (cx + d[0] * r, cy + d[1] * r)
                p1 = (p0[0] + d[0] * w * 0.9 + nrm[0] * w * side, p0[1] + d[1] * w * 0.9 + nrm[1] * w * side)
                dv.line([p0, p1], fill=110, width=max(1, int(S * 0.0018)))
    a = np.asarray(img.getchannel("A"), dtype=np.float32) / 255.0
    v = np.asarray(vein, dtype=np.float32) / 255.0
    li = np.asarray(lid, dtype=np.float32)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    r = np.hypot(xx - cx, yy - cy) / R
    # low-frequency mottling
    nrng = np.random.default_rng(seed)
    noise = Image.fromarray((nrng.random((S // 64, S // 64)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)
    noise = np.asarray(noise, dtype=np.float32) / 255.0 - 0.5
    base = np.array(col, dtype=np.float32) / 255.0
    young_c = np.array((108, 150, 66), dtype=np.float32) / 255.0
    base = base * (1 - young) + young_c * young
    tone = 0.93 + 0.1 * ((li * 7.3) % 1.0) + 0.12 * noise          # per-leaflet + mottle
    tone = tone * (0.92 + 0.12 * np.clip(r, 0, 1))                 # darker toward the centre
    rgb = base[None, None, :] * tone[..., None]
    # veins lighter
    rgb = rgb + (v[..., None] * 0.55) * (np.array((150, 175, 110), dtype=np.float32) / 255.0 - rgb)
    if yellow > 0:
        # yellowing from tips/margins inward, blotchy
        ynoise = Image.fromarray((nrng.random((S // 160, S // 160)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)
        ynoise = np.asarray(ynoise, dtype=np.float32) / 255.0
        ymask = np.clip((r * 0.8 + ynoise * 0.6 - (1.05 - yellow * 0.9)) * 3.0, 0, 1)
        ycol = np.array((176, 160, 70), dtype=np.float32) / 255.0
        bcol = np.array((128, 96, 50), dtype=np.float32) / 255.0
        yc = ycol[None, None, :] * (0.95 + 0.1 * noise[..., None])
        rgb = rgb * (1 - ymask[..., None]) + yc * ymask[..., None]
        bm = np.clip((ymask - 0.85) * 4 * yellow, 0, 1) * (ynoise > 0.6)
        rgb = rgb * (1 - bm[..., None]) + bcol * bm[..., None]
    if frost > 0:
        spk = nrng.random((S, S)) < 0.05 * frost
        spk = np.asarray(Image.fromarray((spk * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)), dtype=np.float32) / 255.0
        rgb = rgb * (1 - spk[..., None] * 0.85) + np.array((0.92, 0.94, 0.88))[None, None, :] * spk[..., None] * 0.85
        rgb = rgb * (1 - 0.25 * frost) + 0.25 * frost * np.array((0.78, 0.84, 0.72))
    # darker edge line
    edge = np.asarray(img.getchannel("A").filter(ImageFilter.MinFilter(5)), dtype=np.float32) / 255.0
    rgb = rgb * (0.88 + 0.12 * edge[..., None])
    out = np.dstack([np.clip(rgb, 0, 1) * 255, a * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA").resize((size, size), Image.LANCZOS)



CLASSES = [14, 18, 22, 27, 32, 38, 46]
G = (74, 128, 56)
VAR = {"green": dict(col=G), "young": dict(col=G, young=0.55), "yellow1": dict(col=(84, 122, 50), yellow=0.45),
       "yellow2": dict(col=(96, 120, 52), yellow=0.85)}


def _job(a):
    out, name, kw = a
    p = Path(out) / f"{name}.png"
    if not p.exists():
        fan_leaf(**kw).save(p)


def jobs(out):
    js = [(out, f"leaf{n}_{v}_t{c}", dict(n=n, thin=c / 100.0, seed=n * 7 + c, size=768, **VAR[v]))
          for c in CLASSES for n in (3, 5, 7, 9) for v in VAR]
    js += [(out, f"leaf{n}_young", dict(n=n, thin=0.22 if n > 1 else 0.3, col=G, young=0.55, seed=n + 10)) for n in (1, 3)]
    js += [(out, "sugar1_light", dict(n=1, thin=0.24, spread=60, col=(76, 104, 46), frost=0.6, seed=41, size=512)),
           (out, "sugar3_light", dict(n=3, thin=0.24, spread=60, col=(76, 104, 46), frost=0.6, seed=43, size=512)),
           (out, "sugar1_heavy", dict(n=1, thin=0.24, spread=60, col=(70, 98, 44), frost=1.5, seed=51, size=512)),
           (out, "sugar3_heavy", dict(n=3, thin=0.24, spread=60, col=(70, 98, 44), frost=1.5, seed=53, size=512))]
    return js


def main(out):
    from multiprocessing import Pool
    Path(out).mkdir(parents=True, exist_ok=True)
    js = jobs(out)
    with Pool() as p:
        p.map(_job, js)
    print(len(js), "leaf textures in", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).parent / "shapes" / "tex"))
