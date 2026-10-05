"""Blender script: renders the grow bags, lamps, fan, drying rack and bar lamps as isometric sprites.
Run inside Blender after render_plants.py is next to it: exec(open(path).read()). Optional globals: DD_ONLY (name prefixes), DD_SAMPLES, DD_FOUT.
"""

import bpy
import math
import os
import random
from mathutils import Vector, Matrix

DD_NO_MAIN = True
HERE = globals().get("DD_DIR", r"C:\Users\Shado\Zomboid\DazedDank_art")
exec(open(os.path.join(HERE, "render_plants.py")).read(), globals())

FOUT = globals().get("DD_FOUT", os.path.join(HERE, "furniture"))
ONLY = globals().get("DD_ONLY", None)


def disc_geo(z, r, seg=28, rng=None, lump=0.0):
    verts = [Vector((0, 0, z))]
    uvs = [(0.5, 0.5)]
    for s in range(seg):
        a = 2 * math.pi * s / seg
        j = 1 + (rng.uniform(-lump, lump) if rng else 0)
        verts.append(Vector((math.cos(a) * r * j, math.sin(a) * r * j, z + (rng.uniform(0, lump * 0.15) if rng else 0))))
        uvs.append((0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)))
    faces = [(0, 1 + s, 1 + (s + 1) % seg) for s in range(seg)]
    return verts, faces, uvs


def cone_geo(z0, z1, r0, r1, seg=28, rng=None, wob=0.0, rings=1):
    verts, faces, uvs = [], [], []
    for k in range(rings + 1):
        t = k / rings
        z = z0 + (z1 - z0) * t
        r = r0 + (r1 - r0) * t
        for s in range(seg):
            a = 2 * math.pi * s / seg
            j = 1 + (rng.uniform(-wob, wob) if rng else 0)
            verts.append(Vector((math.cos(a) * r * j, math.sin(a) * r * j, z)))
            uvs.append((s / seg, t))
    for k in range(rings):
        for s in range(seg):
            s2 = (s + 1) % seg
            faces.append((k * seg + s, k * seg + s2, (k + 1) * seg + s2, (k + 1) * seg + s))
    return verts, faces, uvs


def ring_path(G, pts, r, seg=5, closed=False):
    n = len(pts)
    for i in range(n if closed else n - 1):
        G.add(*tube_geo(pts[i], pts[(i + 1) % n], r, r, seg))


def emit_mat(name, col, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    N, L = mat.node_tree.nodes, mat.node_tree.links
    N.clear()
    out = N.new('ShaderNodeOutputMaterial')
    em = N.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = lin(col) + (1,)
    em.inputs['Strength'].default_value = strength
    L.new(em.outputs['Emission'], out.inputs['Surface'])
    return mat


def new_geos(*names):
    return {n: Geo() for n in names}


# ------------------------------------------------------------------ models

BAG_SPEC = {"small": (24, 26), "large": (34, 40)}


def model_bag(size, soil):
    rng = random.Random(5 if size == "small" else 6)
    r = BAG_SPEC[size][0] / PX_H
    h = BAG_SPEC[size][1] / PX_V
    rim = r * 1.06
    G = new_geos("felt", "rim", "soil", "dry", "perl")
    G["felt"].add(*cone_geo(0.0, h, r, rim, 30, rng, 0.012, 6))
    G["felt"].add(*disc_geo(0.004, r, 30))
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        pts = [Vector((math.cos(a) * (r + (rim - r) * t) * 1.004, math.sin(a) * (r + (rim - r) * t) * 1.004, h * t)) for t in (0.02, 0.5, 0.98)]
        ring_path(G["rim"], pts, 0.004, 4)
    ring_path(G["rim"], [Vector((math.cos(2 * math.pi * s / 36) * rim, math.sin(2 * math.pi * s / 36) * rim, h)) for s in range(36)], 0.016, 5, True)
    right = Vector((-1, 1, 0)).normalized()
    for side in (-1, 1):
        out = right * side
        pts = []
        for i in range(11):
            ph = math.pi * i / 10
            pts.append(out * (rim * 0.98 + 0.05 * math.sin(ph)) + Vector((0, 0, h - 0.05 + 0.12 * (1 - math.cos(ph)) / 2)))
        ring_path(G["rim"], pts, 0.014, 4)
    if soil:
        G["soil"].add(*disc_geo(h - 0.02, rim - 0.02, 28, rng, 0.04))
        for _ in range(14):
            a = rng.uniform(0, 6.28)
            d = rim * 0.8 * rng.random() ** 0.5
            G["perl"].add(*blob_geo((math.cos(a) * d, math.sin(a) * d, h - 0.012), (0.012, 0.012, 0.008), rng, 0.2, 3, 5))
    else:
        G["dry"].add(*disc_geo(0.02, r * 0.96, 28))
    return G


LIGHT_SPEC = {
    # Glow matches the light each tier casts in game: basic LEDs purple, pro lamps warm yellow.
    "Basic": dict(w=22, body=(120, 120, 130), glow=(150, 60, 255), strength=1.6),
    "Pro": dict(w=26, body=(70, 72, 84), glow=(255, 200, 110), strength=2.4),
    "LargeBasic": dict(w=38, body=(120, 120, 130), glow=(150, 60, 255), strength=1.6),
    "LargePro": dict(w=46, body=(70, 72, 84), glow=(255, 200, 110), strength=2.4),
}


def model_lamp(key, icon=False):
    sp = LIGHT_SPEC[key]
    w = sp["w"] / PX_H
    G = new_geos("body", "dark", "glow", "cord")
    top = (226 - (80 if "Large" in key else 84)) / PX_V
    ceil = top + 0.5 if icon else (226 - 30) / PX_V
    G["dark"].add(*cone_geo(ceil - 0.03, ceil + 0.04, 0.1, 0.1, 16))
    G["dark"].add(*disc_geo(ceil + 0.04, 0.1, 16))
    for a in (0.8, 0.8 + math.pi):
        top_pt = Vector((math.cos(a) * w * 0.15, math.sin(a) * w * 0.15, ceil - 0.03))
        bot_pt = Vector((math.cos(a) * w * 0.9, math.sin(a) * w * 0.9, top + 0.14))
        G["cord"].add(*tube_geo(top_pt, bot_pt, 0.006, 0.006, 4))
    G["body"].add(*cone_geo(top, top + 0.16, w * 0.55, w, 28, None, 0, 3))
    G["body"].add(*disc_geo(top + 0.16, w, 28))
    G["glow"].add(*disc_geo(top - 0.005, w * 0.55, 28))
    ring_path(G["glow"], [Vector((math.cos(2 * math.pi * s / 32) * w * 0.56, math.sin(2 * math.pi * s / 32) * w * 0.56, top + 0.004)) for s in range(32)], 0.01, 4, True)
    if key.endswith("Pro"):
        n = 5 if "Large" in key else 4
        for i in range(n):
            x = -w * 0.45 + w * 0.9 * i / (n - 1)
            G["dark"].add(*tube_geo((x, -w * 0.5, top - 0.012), (x, w * 0.5, top - 0.012), 0.004, 0.004, 4))
    return G


def hang_bundle(G, x, z_rail, rng, axis):
    """A drying cola hanging upside down from the rail by a short string."""
    pos = axis * x
    G["string"].add(*tube_geo(pos + Vector((0, 0, z_rail)), pos + Vector((0, 0, z_rail - 0.1)), 0.004, 0.004, 4))
    add_bud(G["bud"], G["pist"], G["sugar"], pos + Vector((0, 0, z_rail - 0.1)), Vector((0.001, 0, -1)), 0.4, 0.15, rng, True)


def model_rack(facing, part, count):
    rng = random.Random(40 + part)
    axis = Vector((0, 1, 0)) if facing == "S" else Vector((1, 0, 0))
    side = Vector((1, 0, 0)) if facing == "S" else Vector((0, 1, 0))
    G = new_geos("wood", "dark", "string", "bud", "pist", "sugar")
    h = 86 / PX_V
    half = 0.48
    for off in (-0.13, 0.13):
        G["wood"].add(*tube_geo(axis * -half + side * off + Vector((0, 0, h)), axis * half + side * off + Vector((0, 0, h)), 0.022, 0.022, 4))
        G["dark"].add(*tube_geo(axis * -half + side * off + Vector((0, 0, h * 0.45)), axis * half + side * off + Vector((0, 0, h * 0.45)), 0.01, 0.01, 4))
    ends = []
    if part == 0:
        ends.append(-half + 0.03)
    if part == count - 1:
        ends.append(half - 0.03)
    for e in ends:
        for off in (-0.13, 0.13):
            G["wood"].add(*tube_geo(axis * e + side * off, axis * e + side * off + Vector((0, 0, h)), 0.026, 0.026, 4))
        G["wood"].add(*tube_geo(axis * e - side * 0.13 + Vector((0, 0, h * 0.2)), axis * e + side * 0.13 + Vector((0, 0, h * 0.2)), 0.012, 0.012, 4))
    for x in (-0.3, 0.0, 0.3):
        hang_bundle(G, x, h, rng, axis)
    return G


def model_bar(key, facing, part, count, icon=False):
    sp = LIGHT_SPEC[key]
    axis = Vector((0, 1, 0)) if facing == "S" else Vector((1, 0, 0))
    side = Vector((1, 0, 0)) if facing == "S" else Vector((0, 1, 0))
    G = new_geos("body", "dark", "glow", "cord")
    hz = (226 - 112) / PX_V
    ceil = hz + 0.45 if icon else (226 - 30) / PX_V
    half = 0.5
    for x in (-0.3, 0.3):
        G["cord"].add(*tube_geo(axis * x + Vector((0, 0, ceil)), axis * x + Vector((0, 0, hz + 0.05)), 0.006, 0.006, 4))
    G["body"].add(*tube_geo(axis * -half + Vector((0, 0, hz + 0.04)), axis * half + Vector((0, 0, hz + 0.04)), 0.07, 0.07, 4))
    G["dark"].add(*tube_geo(axis * -half + Vector((0, 0, hz + 0.11)), axis * half + Vector((0, 0, hz + 0.11)), 0.03, 0.03, 4))
    strips = (-0.035, 0.035) if key.endswith("Pro") else (0.0,)
    for o in strips:
        G["glow"].add(*tube_geo(axis * -half + side * o + Vector((0, 0, hz - 0.012)), axis * half + side * o + Vector((0, 0, hz - 0.012)), 0.018, 0.018, 4))
    return G


# ------------------------------------------------------------------ rendering

def mats_for(kind, key=None):
    felt = (64, 64, 70)
    return {
        "felt": new_mat("felt", (84, 84, 94), 0.9, bump=0.6, scale=80, patch=0.08),
        "rim": new_mat("rim", (92, 92, 100), 0.85, bump=0.3, scale=60),
        "soil": new_mat("soil", (70, 50, 34), 0.95, bump=0.8, scale=60, patch=0.3),
        "perl": new_mat("perl", (230, 228, 215), 0.8),
        "dry": new_mat("dry", (40, 40, 46), 0.9),
        "body": new_mat("body", LIGHT_SPEC[key]["body"] if key in LIGHT_SPEC else (84, 84, 92), 0.5, metal=0.2),
        "dark": new_mat("dark", (44, 44, 52), 0.5, metal=0.2),
        "cord": new_mat("cord", (24, 24, 24), 0.6),
        "glow": emit_mat("glow", LIGHT_SPEC[key]["glow"] if key in LIGHT_SPEC else (255, 230, 160),
                         LIGHT_SPEC[key].get("strength", 5.0) if key in LIGHT_SPEC else 5.0),
        "metal": new_mat("metal", (170, 172, 178), 0.35, metal=0.9),
        "blade": new_mat("blade", (90, 100, 120), 0.4),
        "wood": new_mat("wood", (126, 92, 58), 0.75, bump=0.5, scale=25, patch=0.22),
        "string": new_mat("string", (150, 130, 90), 0.8),
        "bud": new_mat("dbud", (96, 112, 54), 0.7, frost=0.25),
        "pist": new_mat("dpist", (150, 90, 50), 0.7),
        "sugar": new_mat("dsugar", (84, 104, 50), 0.6),
    }


def render_geo(name, G, matrix=None):
    sc = bpy.context.scene
    keep = [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT')]
    for ob in list(bpy.data.objects):
        if ob not in keep:
            bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for ma in list(bpy.data.materials):
        bpy.data.materials.remove(ma)
    key = name.split("_")[1] if name.startswith(("lamp_", "bar_")) else None
    mats = mats_for(name, key)
    for k, g in G.items():
        if g.v:
            ob = g.to_object(k, mats[k])
            if matrix is not None:
                ob.matrix_world = matrix
    os.makedirs(FOUT, exist_ok=True)
    sc.render.filepath = os.path.join(FOUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


def want(name):
    return ONLY is None or any(name.startswith(p) for p in ONLY)


def run():
    setup_render()
    for size in ("small", "large"):
        for soil, tag in ((True, "soil"), (False, "dry")):
            n = f"bag_{size}_{tag}"
            if want(n):
                render_geo(n, model_bag(size, soil))
    for key in LIGHT_SPEC:
        n = f"lamp_{key}"
        if want(n):
            render_geo(n, model_lamp(key))
    if want("fan"):
        render_geo("fan", model_fan_world())
    for facing in ("E", "S"):
        for part in range(2):
            n = f"rack_{facing}{part}"
            if want(n):
                render_geo(n, model_rack(facing, part, 2))
    for key, count in (("LargeBasic", 2), ("LargePro", 3)):
        for facing in ("E", "S"):
            for part in range(count):
                n = f"bar_{key}_{facing}{part}"
                if want(n):
                    render_geo(n, model_bar(key, facing, part, count))
    print("DD FURNITURE DONE")


def model_fan_world():
    """Fan with its head (cage, spokes, blades, hub) built in a local frame and rotated to face the camera."""
    G = new_geos("metal", "dark", "blade")
    rng = random.Random(1)
    n = Vector((1, 1, 0.25)).normalized()
    M = Matrix.Translation(Vector((0, 0, 0.66))) @ n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    G["dark"].add(*cone_geo(0.0, 0.05, 0.18, 0.15, 24))
    G["dark"].add(*disc_geo(0.05, 0.15, 24))
    G["metal"].add(*tube_geo((0, 0, 0.05), (0, 0, 0.6), 0.016, 0.016, 8))
    G["dark"].add(*blob_geo((0, 0, 0.0), (0.07, 0.07, 0.06), rng, 0.0, 5, 10), m=M @ Matrix.Translation(Vector((0, 0, -0.08))))
    for rr, sg in ((0.22, 36), (0.13, 28), (0.06, 20)):
        pts = [Vector((math.cos(2 * math.pi * s / sg) * rr, math.sin(2 * math.pi * s / sg) * rr, 0.0)) for s in range(sg)]
        for i in range(sg):
            G["metal"].add(*tube_geo(pts[i], pts[(i + 1) % sg], 0.006, 0.006, 4), m=M)
    for k in range(10):
        a = 2 * math.pi * k / 10
        G["metal"].add(*tube_geo((0, 0, 0), (math.cos(a) * 0.22, math.sin(a) * 0.22, 0), 0.003, 0.003, 4), m=M)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.3
        c = Vector((math.cos(a) * 0.09, math.sin(a) * 0.09, 0.01))
        G["blade"].add(*blob_geo((0, 0, 0), (0.1, 0.04, 0.008), rng, 0.0, 5, 10), m=M @ Matrix.Translation(c) @ Matrix.Rotation(a, 4, 'Z'))
    G["dark"].add(*blob_geo((0, 0, 0), (0.035, 0.035, 0.03), rng, 0.0, 4, 8), m=M)
    return G


if not globals().get("DD_NO_RUN"):
    run()
