"""Blender script: renders the item icons (256x256, auto-framed) that the sprite pipeline shrinks to 32x32.
Run inside Blender with render_plants.py and render_furniture.py next to it. Optional globals: DD_ONLY, DD_SAMPLES, DD_IOUT.
"""

import bpy
import math
import os
import random
from mathutils import Vector, Matrix

DD_NO_MAIN = True
DD_NO_RUN = True
HERE = globals().get("DD_DIR", r"C:\Users\Shado\Zomboid\DazedDank_art")
exec(open(os.path.join(HERE, "render_furniture.py")).read(), globals())

IOUT = globals().get("DD_IOUT", os.path.join(HERE, "icons"))
RIGHT = Vector((-1, 1, 0)).normalized()      # screen-right on the ground
TOWARD = Vector((1, 1, 0)).normalized()      # toward the viewer


def box_geo(c, sx, sy, sz):
    c = Vector(c)
    verts, uvs = [], []
    for dx in (-1, 1):
        for dy in (-1, 1):
            for dz in (-1, 1):
                verts.append(c + Vector((dx * sx / 2, dy * sy / 2, dz * sz / 2)))
                uvs.append((0.5, 0.5))
    idx = lambda dx, dy, dz: (dx > 0) * 4 + (dy > 0) * 2 + (dz > 0)
    faces = []
    for dx in (-1, 1):
        faces.append((idx(dx, -1, -1), idx(dx, 1, -1), idx(dx, 1, 1), idx(dx, -1, 1)))
    for dy in (-1, 1):
        faces.append((idx(-1, dy, -1), idx(1, dy, -1), idx(1, dy, 1), idx(-1, dy, 1)))
    for dz in (-1, 1):
        faces.append((idx(-1, -1, dz), idx(1, -1, dz), idx(1, 1, dz), idx(-1, 1, dz)))
    return verts, faces, uvs


def capped(G, p0, p1, r0, r1, seg=14):
    """A tube between two points with flat caps."""
    p0, p1 = Vector(p0), Vector(p1)
    G.add(*tube_geo(p0, p1, r0, r1, seg))
    d = (p1 - p0).normalized()
    q = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    G.add(*disc_geo(0, r0, seg), m=Matrix.Translation(p0) @ q)
    G.add(*disc_geo(0, r1, seg), m=Matrix.Translation(p1) @ q)


def dome_geo(rx, ry, rz, seg=24, rings=8):
    verts, faces, uvs = [], [], []
    for r in range(rings + 1):
        th = (math.pi / 2) * r / rings
        for s in range(seg):
            ph = 2 * math.pi * s / seg
            verts.append(Vector((math.sin(th) * math.cos(ph) * rx, math.sin(th) * math.sin(ph) * ry, math.cos(th) * rz)))
            uvs.append((s / seg, r / rings))
    for r in range(rings):
        for s in range(seg):
            s2 = (s + 1) % seg
            faces.append((r * seg + s, r * seg + s2, (r + 1) * seg + s2, (r + 1) * seg + s))
    return verts, faces, uvs


def glass_mat(name, tint, clear=0.82):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    N, L = mat.node_tree.nodes, mat.node_tree.links
    N.clear()
    out = N.new('ShaderNodeOutputMaterial')
    tr = N.new('ShaderNodeBsdfTransparent')
    tr.inputs['Color'].default_value = lin(tint) + (1,)
    gl = N.new('ShaderNodeBsdfGlossy')
    gl.inputs['Roughness'].default_value = 0.08
    mx = N.new('ShaderNodeMixShader')
    mx.inputs[0].default_value = 1 - clear
    L.new(tr.outputs['BSDF'], mx.inputs[1])
    L.new(gl.outputs['BSDF'], mx.inputs[2])
    L.new(mx.outputs['Shader'], out.inputs['Surface'])
    return mat


# ------------------------------------------------------------------ icon models

def m_seed():
    G = new_geos("seed")
    rng = random.Random(3)
    for k, (x, y, a) in enumerate(((-0.08, 0.0, 0.5), (0.07, 0.04, 2.0), (0.0, -0.08, 1.2))):
        G["seed"].add(*blob_geo((0, 0, 0), (0.055, 0.037, 0.032), rng, 0.03, 6, 10),
                      m=Matrix.Translation(Vector((x, y, 0.03))) @ Matrix.Rotation(a, 4, 'Z'))
    return G


def m_cutting(roots=False):
    G = new_geos("stem", "leaf", "root")
    rng = random.Random(9)
    z0 = 0.18 if roots else 0.0
    G["stem"].add(*tube_geo((0, 0, z0), (0, 0, z0 + 0.55), 0.014, 0.009, 7))
    for k, (z, yaw, size) in enumerate(((0.25, 0.4, 0.2), (0.25, 0.4 + math.pi, 0.2), (0.42, 1.9, 0.17), (0.42, 1.9 + math.pi, 0.17))):
        place_leaf(G["leaf"], Vector((0, 0, z0 + z)) + Vector((-math.sin(yaw), math.cos(yaw), 0)) * 0.04, yaw, math.radians(25), size, 5, 0.26, 0.7)
    for k in range(3):
        place_leaf(G["leaf"], Vector((0, 0, z0 + 0.55)), k * 2.1, math.radians(55), 0.13, 5, 0.26, 0.2)
    if roots:
        for k in range(9):
            a = 2 * math.pi * k / 9 + rng.uniform(-0.2, 0.2)
            p = Vector((0, 0, z0))
            d = Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, -1)).normalized()
            for _ in range(5):
                n = p + d * rng.uniform(0.04, 0.06)
                G["root"].add(*tube_geo(p, n, 0.005, 0.004, 4))
                p = n
                d = (d + Vector((rng.uniform(-.3, .3), rng.uniform(-.3, .3), 0))).normalized()
    return G


def m_gel():
    G = new_geos("orange", "white", "label")
    capped(G["orange"], (0, 0, 0), (0, 0, 0.22), 0.09, 0.09, 20)
    G["orange"].add(*cone_geo(0.22, 0.28, 0.09, 0.045, 20))
    capped(G["white"], (0, 0, 0.28), (0, 0, 0.34), 0.05, 0.05, 20)
    capped(G["label"], (0, 0, 0.06), (0, 0, 0.17), 0.094, 0.094, 20)
    return G


def m_jug(label):
    G = new_geos("plastic", "cap", label)
    G["plastic"].add(*cone_geo(0, 0.3, 0.14, 0.14, 22, None, 0, 2))
    G["plastic"].add(*disc_geo(0, 0.14, 22))
    G["plastic"].add(*cone_geo(0.3, 0.38, 0.14, 0.05, 22))
    capped(G["cap"], (0, 0, 0.38), (0, 0, 0.44), 0.055, 0.055, 14)
    capped(G[label], (0, 0, 0.07), (0, 0, 0.25), 0.145, 0.145, 22)
    pts = []
    for i in range(11):
        ph = math.pi * i / 10
        pts.append(RIGHT * (0.12 + 0.07 * math.sin(ph)) + Vector((0, 0, 0.26 + 0.1 * math.cos(ph) * 0.9 + 0.04)))
    ring_path(G["plastic"], pts, 0.012, 5)
    return G


def m_dome():
    G = new_geos("dark", "stem", "cot", "glass", "rim")
    G["dark"].add(*box_geo((0, 0, 0.02), 0.5, 0.34, 0.04))
    rng = random.Random(4)
    for x in (-0.14, 0.0, 0.14):
        for y in (-0.06, 0.07):
            G["stem"].add(*tube_geo((x, y, 0.04), (x, y, 0.11), 0.006, 0.005, 5))
            for side in (-1, 1):
                G["cot"].add(*blob_geo((x + side * 0.03, y, 0.12), (0.03, 0.018, 0.006), rng, 0.0, 4, 8))
    G["glass"].add(*dome_geo(0.24, 0.16, 0.2, 28, 8), m=Matrix.Translation(Vector((0, 0, 0.04))))
    ring_path(G["rim"], [Vector((math.cos(2 * math.pi * s / 36) * 0.24, math.sin(2 * math.pi * s / 36) * 0.16, 0.045)) for s in range(36)], 0.006, 4, True)
    return G


def m_soil():
    G = new_geos("sack", "sackdark", "label")
    rng = random.Random(6)
    G["sack"].add(*blob_geo((0, 0, 0.2), (0.2, 0.12, 0.2), rng, 0.02, 8, 14))
    G["sackdark"].add(*box_geo((0, 0, 0.42), 0.22, 0.05, 0.06), m=Matrix.Rotation(0.3, 4, 'Z'))
    G["label"].add(*box_geo((0, 0, 0.2), 0.13, 0.005, 0.1), m=Matrix.Rotation(math.radians(45), 4, 'Z') @ Matrix.Translation(Vector((0, 0.115, 0))))
    return G


def m_jar():
    G = new_geos("glass", "metal", "bud", "pist", "sugar")
    rng = random.Random(8)
    G["glass"].add(*cone_geo(0, 0.32, 0.14, 0.14, 26, None, 0, 2))
    G["glass"].add(*disc_geo(0.0, 0.14, 26))
    G["glass"].add(*cone_geo(0.32, 0.36, 0.14, 0.1, 26))
    capped(G["metal"], (0, 0, 0.36), (0, 0, 0.42), 0.11, 0.11, 26)
    for k in range(22):
        a = rng.uniform(0, 6.28)
        d = 0.09 * rng.random() ** 0.5
        z = rng.uniform(0.06, 0.26)
        r = rng.uniform(0.04, 0.06)
        G["bud"].add(*blob_geo((math.cos(a) * d, math.sin(a) * d, z), (r, r, r * 1.1), rng, 0.2, 5, 8))
    return G


def m_bud():
    G = new_geos("bud", "pist", "sugar")
    rng = random.Random(12)
    add_bud(G["bud"], G["pist"], G["sugar"], Vector((0, 0, 0)), Vector((0.25, 0, 1)), 0.34, 0.19, rng, True)
    return G


def m_papers():
    G = new_geos("paper", "paperdark", "ink")
    G["paper"].add(*box_geo((0, 0, 0.03), 0.3, 0.2, 0.06))
    G["paperdark"].add(*box_geo((0, 0, 0.065), 0.3, 0.2, 0.012))
    G["ink"].add(*box_geo((0, 0, 0.074), 0.16, 0.02, 0.004))
    return G


def m_joint():
    G = new_geos("white", "filter", "green", "ember")
    d = (RIGHT * 0.95 + Vector((0, 0, 0.3))).normalized()
    p0 = d * -0.34
    p1 = d * 0.3
    capped(G["filter"], p0, p0 + d * 0.07, 0.022, 0.022, 14)
    capped(G["white"], p0 + d * 0.07, p1, 0.022, 0.034, 14)
    capped(G["white"], p1, p1 + d * 0.06, 0.034, 0.012, 14)
    G["green"].add(*disc_geo(0, 0.01, 10), m=Matrix.Translation(p1 + d * 0.065) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4())
    return G


def m_pipe():
    G = new_geos("wood", "dark", "green")
    d = (RIGHT * 0.9 + Vector((0, 0, 0.2))).normalized()
    p0 = d * -0.34
    p1 = d * 0.12
    capped(G["dark"], p0, p0 + d * 0.06, 0.02, 0.02, 12)
    capped(G["wood"], p0 + d * 0.06, p1, 0.02, 0.026, 12)
    bc = p1 + Vector((0.0, 0.0, 0.04))
    capped(G["wood"], bc, bc + Vector((0, 0, 0.11)), 0.05, 0.075, 18)
    G["green"].add(*disc_geo(0, 0.062, 16), m=Matrix.Translation(bc + Vector((0, 0, 0.105))))
    return G


def m_rack():
    G = model_rack("S", 0, 1)
    return G


def hung_plant(typ, dried):
    G = build_plant(typ, "Ripe", zlib.crc32(f"{typ}/Ripe".encode()))
    return G


def m_hung(typ, dried):
    G = hung_plant(typ, dried)
    G["twine"] = Geo()
    H = TYPES[typ]["h"] / PX_V
    G["twine"].add(*tube_geo((0, 0, -0.02), (0, 0, -0.2), 0.006, 0.006, 5))
    ring_path(G["twine"], [Vector((math.cos(2 * math.pi * s / 16) * 0.05, 0, -0.2 - math.sin(2 * math.pi * s / 16) * 0.05)) for s in range(16)], 0.005, 4, True)
    return G


EXTRA = {
    "seed": lambda: new_mat("seed", (90, 70, 45), 0.35, patch=0.6, scale=40),
    "stem": lambda: new_mat("stem", (78, 112, 46), 0.7),
    "leaf": lambda: new_mat("leaf", (66, 128, 44), 0.45, trans=0.3, vein=(190, 215, 150)),
    "root": lambda: new_mat("root", (236, 228, 200), 0.7),
    "cot": lambda: new_mat("cot", (110, 160, 70), 0.5),
    "orange": lambda: new_mat("orange", (240, 150, 60), 0.35),
    "white": lambda: new_mat("white", (240, 238, 228), 0.6),
    "label": lambda: new_mat("label", (236, 226, 190), 0.6),
    "plastic": lambda: new_mat("plastic", (236, 236, 228), 0.3),
    "cap": lambda: new_mat("cap", (40, 40, 44), 0.4),
    "green": lambda: new_mat("greenb", (70, 110, 44), 0.7, bump=0.4, scale=60),
    "purple": lambda: new_mat("purple", (160, 70, 150), 0.6),
    "vegl": lambda: new_mat("vegl", (70, 150, 60), 0.6),
    "sack": lambda: new_mat("sack", (150, 118, 80), 0.9, bump=0.5, scale=50, patch=0.15),
    "sackdark": lambda: new_mat("sackdark", (100, 76, 50), 0.9),
    "paper": lambda: new_mat("paper", (236, 232, 214), 0.7),
    "paperdark": lambda: new_mat("paperdark", (214, 200, 160), 0.7),
    "ink": lambda: new_mat("ink", (120, 110, 90), 0.8),
    "filter": lambda: new_mat("filter", (196, 160, 110), 0.8),
    "ember": lambda: emit_mat("ember", (255, 120, 40), 4.0),
    "glass": lambda: glass_mat("glass", (200, 230, 235)),
    "rim": lambda: new_mat("rimm", (150, 150, 156), 0.4, metal=0.5),
    "twine": lambda: new_mat("twine", (170, 140, 90), 0.8, bump=0.4, scale=90),
}


def icon_mats(name, key):
    mats = mats_for(name, key)
    for k, fn in EXTRA.items():
        if k not in mats:
            mats[k] = fn()
    return mats


def plant_mats(typ, dried):
    spec = TYPES[typ]
    leaf = mixc(spec["leaf"], (150, 150, 60), 0.3)
    if dried:
        leaf = (112, 96, 54)
    return {
        "stem": new_mat("stem", (96, 90, 52) if dried else (78, 112, 46), 0.7),
        "leaf": new_mat("leaf", leaf, 0.5, trans=0.1 if dried else 0.3, vein=mixc(leaf, (210, 220, 170), 0.4)),
        "cot": new_mat("cot", leaf, 0.5),
        "bud": new_mat("bud", (110, 100, 56) if dried else mixc(spec["bud"], (60, 100, 40), 0.45), 0.6, frost=0.3),
        "pist": new_mat("pist", (130, 86, 50) if dried else (196, 96, 36), 0.7),
        "sugar": new_mat("sugar", (104, 94, 54) if dried else mixc(spec["bud"], leaf, 0.4), 0.55),
        "twine": new_mat("twine", (170, 140, 90), 0.8, bump=0.4, scale=90),
    }


def fit_camera(objs, fit=1.0, margin=1.14):
    cam = bpy.context.scene.camera
    inv = cam.matrix_world.inverted()
    xs, ys = [], []
    for ob in objs:
        mw = ob.matrix_world
        for v in ob.data.vertices:
            p = inv @ (mw @ v.co)
            xs.append(p.x)
            ys.append(p.y)
    span = max(max(xs) - min(xs), max(ys) - min(ys)) * margin / fit
    cam.data.ortho_scale = span
    cam.data.shift_x = ((min(xs) + max(xs)) / 2) / span
    cam.data.shift_y = ((min(ys) + max(ys)) / 2) / span


def render_icon(name, G, mats, fit=1.0, matrix=None):
    sc = bpy.context.scene
    keep = [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT')]
    for ob in list(bpy.data.objects):
        if ob not in keep:
            bpy.data.objects.remove(ob, do_unlink=True)
    objs = []
    for k, g in G.items():
        if g.v:
            ob = g.to_object(k, mats[k])
            if matrix is not None:
                ob.matrix_world = matrix
            objs.append(ob)
    fit_camera(objs, fit)
    os.makedirs(IOUT, exist_ok=True)
    sc.render.filepath = os.path.join(IOUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


def clear_data():
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for ma in list(bpy.data.materials):
        bpy.data.materials.remove(ma)


def run_icons():
    setup_render()
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = 256
    sc.camera.data.shift_y = 0.0
    sc.camera.data.sensor_fit = 'HORIZONTAL'

    def go(name, G, mats=None, fit=1.0, matrix=None, key=None):
        if not want(name):
            return
        clear_data()
        render_icon(name, G, mats if mats is not None else icon_mats(name, key), fit, matrix)

    go("seed", m_seed())
    go("cutting", m_cutting())
    go("rooted", m_cutting(True))
    go("gel", m_gel())
    clear_data()
    for label, lname in (("vegl", "veg"), ("purple", "bloom")):
        G = m_jug(label)
        go(lname, G)
    go("dome", m_dome())
    go("bagSmall", model_bag("small", True), fit=0.8)
    go("bagLarge", model_bag("large", True), fit=1.0)
    for key in ("Basic", "Pro"):
        go(f"lamp{key}", model_lamp(key, True), key=key)
    for key in ("LargeBasic", "LargePro"):
        go(f"lamp{key}", model_bar(key, "S", 0, 1, True), key=key)
    go("soil", m_soil())
    go("rack", m_rack())
    go("jar", m_jar())
    go("fan", model_fan_world())
    go("bud", m_bud())
    go("papers", m_papers())
    go("joint", m_joint())
    go("pipe", m_pipe())
    for typ in TYPE_ORDER:
        for dried in (False, True):
            name = ("dried" if dried else "wet") + typ
            if want(name):
                clear_data()
                G = m_hung(typ, dried)
                render_icon(name, G, plant_mats(typ, dried), 1.0,
                            Matrix.Translation(Vector((0, 0, 1.6))) @ Matrix.Rotation(math.pi, 4, 'X'))
    print("DD ICONS DONE")


if not globals().get("DD_NO_RUN_ICONS"):
    run_icons()
