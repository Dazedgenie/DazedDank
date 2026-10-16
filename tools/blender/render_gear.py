"""Dazed Dank grow gear on the plant sheets (dazeddank_plants_01, dazeddank_hydro_01) and the gear item icons,
rendered in Dazed Power's art style on its rig (dz_render.py), with the detail of render_detail_samples.py.

    python3 tools/blender/render_gear.py -- <out dir> [all|plants|hydro|icons|<sheet>:<idx,...>|icon:<Name,...>]

Raw 256x512 cells land in <out>/<sheet>/<index>.png (floor pieces also get <index>_s.png, a contact-shadow pass) and
256x256 icon renders in <out>/icons/Item_<Name>.png. Then grade, shrink and install them with gear_post.py.

Only the non-plant sprites are drawn here. The plant layers (dazeddank_overlay_01/02) were rendered with the older
camera of render_plants.py, whose ground origin sits 2 px (1x) lower in the cell than this rig's; gear_post.py moves
these cells down by that much so pots, lids and trays stay exactly under the plants (Config.PLANT_LIFT). Pot and tray
heights below are the old ones in pixels (PX_V = 78.4 px per unit of height, PX_H = 90.51 px per unit on the ground).

Directions: the model's -Y is the game's south (the left-hand face on screen), +X is east (the right-hand face).
"""
import os, sys, math, random, time

_ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
_OUT_DIR = os.path.abspath(_ARGS[0] if _ARGS else "gear_render_out")
_JOBS = _ARGS[1:] or ["all"]
_HERE = os.path.dirname(os.path.abspath(__file__))
DZ_LIBRARY = True
sys.argv = [sys.argv[0], "--", _OUT_DIR]
__file__ = os.path.join(_HERE, "dz_render.py")
exec(compile(open(__file__).read(), __file__, "exec"))         # mat, box, cyl, tube, P(), tile_camera, ...
__file__ = os.path.join(_HERE, "render_gear.py")
import bpy, bmesh
from mathutils import Vector, Matrix, Euler

scene.cycles.samples = 80
PX_V, PX_H = 78.4, 90.51
CEIL_Z = 2.5                       # the ceiling the hanging lamps hang from
ICON = [False]                     # icon renders drop cords and hangers that run to the ceiling or floor
SCREEN_R = Vector((1, 1, 0)).normalized()      # screen right, on the ground
TOWARD = Vector((1, -1, 0)).normalized()       # toward the viewer, on the ground


def pv(px): return px / PX_V
def ph(px): return px / PX_H


# ------------------------------------------------------------------ shared small parts (as render_detail_samples.py)
def cord(pts, r=0.006, col="#1f1f21"):
    if ICON[0]:
        a, b = Vector(pts[0]), Vector(pts[1])
        if (b - a).length > 0.1: b = a + (b - a).normalized() * 0.1
        pts = [a, b]
    path(pts, r, mat(col, 0.6, dirt=0.1), segs=8)


def screws(pts, r=0.006, axis="Y"):
    for c in pts: cyl(r, 0.004, c, P()["steel"], axis=axis, segs=10)


def label(size, loc, col="#d8d2bd", rot=(0, 0, 0)):
    box(size, loc, mat(col, 0.7, var=0.08, dirt=0.25), rot=rot, bevel=0.0005)


def print_lines(x0, x1, z, y, n, gap=0.012, col="#3a3a3a", t=0.003, axis="Y"):
    """Little printed text lines on a label facing -Y (or +X)."""
    for i in range(n):
        w = (x1 - x0) * (1.0 if i == 0 else 0.6 + 0.3 * ((i * 37) % 7) / 7)
        if axis == "Y":
            box((w, 0.0015, t), (x0 + w / 2, y, z - i * gap), mat(col, 0.6, dirt=0, wear=False), bevel=0)
        else:
            box((0.0015, w, t), (y, x0 + w / 2, z - i * gap), mat(col, 0.6, dirt=0, wear=False), bevel=0)


def ratchet_hanger(x, y, z0, z1):
    """Rope ratchet hanger: rope up to the ceiling with the ratchet body near the lamp."""
    p = P()
    if not ICON[0]:
        tube((x, y, z0), (x, y, z1), 0.004, mat("#2a2b2d", 0.8, dirt=0.1), 6)
        box((0.03, 0.03, 0.012), (x, y, z1 - 0.006), p["steel_dark"], bevel=0.003)
    else:
        tube((x, y, z0), (x, y, z0 + 0.22), 0.004, mat("#2a2b2d", 0.8, dirt=0.1), 6)
    box((0.028, 0.012, 0.05), (x, y, z0 + 0.14), mat("#1d1e20", 0.55, dirt=0.1), bevel=0.004)
    box((0.006, 0.016, 0.03), (x + 0.016, y, z0 + 0.15), mat("#c23a2e", 0.5, dirt=0.05), bevel=0.001)
    torus(0.012, 0.003, (x, y, z0 + 0.012), p["steel"], axis="Y", seg=14, rseg=5)


def fabric_mat(col, var=0.25, dirt=0.35):
    """Felt grow-bag fabric: coarse colour noise plus a bump so the weave catches the light."""
    m = mat(col, 0.95, var=var, dirt=dirt)
    nt = m.node_tree; b = nt.nodes.get("Principled BSDF")
    if not b.inputs["Normal"].is_linked:
        bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.35
        nt.links.new(noise(nt, 160.0, 2), bp.inputs["Height"]); nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m


def bumpy(col, rough=0.95, var=0.3, dirt=0.2, scale=120.0, strength=0.5):
    """A rough material with a fine bump (soil, rockwool, clay)."""
    m = mat(col, rough, var=var, dirt=dirt)
    nt = m.node_tree; b = nt.nodes.get("Principled BSDF")
    if not b.inputs["Normal"].is_linked:
        bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = strength
        nt.links.new(noise(nt, scale, 4), bp.inputs["Height"]); nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m


def disc_bm(r, z, seg=32, rng=None, lump=0.0):
    bm = bmesh.new()
    c = bm.verts.new((0, 0, z)); ring = []
    for i in range(seg):
        a = 2 * math.pi * i / seg; j = 1 + (rng.uniform(-lump, lump) if rng else 0)
        ring.append(bm.verts.new((math.cos(a) * r * j, math.sin(a) * r * j, z + (rng.uniform(0, lump * 0.2) if rng else 0))))
    for i in range(seg): bm.faces.new((c, ring[i], ring[(i + 1) % seg]))
    return bm


def soil_top(r, z, rng, perlite=60, col="#4a3524"):
    """A lumpy soil surface with clods and white perlite."""
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=24, y_segments=24, size=r)
    for v in list(bm.verts):
        d = math.hypot(v.co.x, v.co.y)
        if d > r * 1.02:
            v.co.x *= r / d; v.co.y *= r / d
        v.co.z = rng.uniform(-0.004, 0.006) + 0.01 * (1 - min(1, d / r)) ** 2
    obj(bm, bumpy(col, 0.98, 0.35, 0.0, 90, 0.8), M((0, 0, z)), smooth=True)
    for _ in range(int(perlite)):
        a = rng.uniform(0, 6.283); d = (r - 0.02) * rng.random() ** 0.5
        ball(rng.uniform(0.005, 0.008), (math.cos(a) * d, math.sin(a) * d, z + 0.008), mat("#e8e6dc", 0.8, dirt=0), segs=6)
    for _ in range(int(perlite / 4)):
        a = rng.uniform(0, 6.283); d = (r - 0.03) * rng.random() ** 0.5
        ball(rng.uniform(0.008, 0.014), (math.cos(a) * d, math.sin(a) * d, z + 0.006), mat("#3c2a1c", 0.95, var=0.3, dirt=0), scale=(1, 1, 0.6), segs=7)


def pebbles(r, z, rng, n=60, fired=True, s=(0.010, 0.015)):
    m = bumpy("#a85a33" if fired else "#968070", 0.85, 0.3, 0.05, 140, 0.3)
    for _ in range(n):
        a = rng.uniform(0, 6.283); d = (r - 0.012) * rng.random() ** 0.5; k = rng.uniform(*s)
        ball(k, (math.cos(a) * d, math.sin(a) * d, z + rng.uniform(0, 0.01)), m, scale=(1, 1, 0.85), segs=8)


def rockwool(c, size, h, rot=0.0, hole=True):
    m = bumpy("#d6cc9c", 0.97, 0.18, 0.15, 220, 0.9)
    box((size, size, h), c, m, rot=(0, 0, rot), bevel=0.004)
    if hole: cyl(0.016, 0.003, Vector(c) + Vector((0, 0, h / 2 + 0.0005)), mat("#3a3226", 0.9, dirt=0), segs=14)


# ------------------------------------------------------------------ old plant geometry, for the drying-rack bundles
_OLD = {}


def old_plants():
    """render_plants.py's functions (bud geometry and materials), loaded once in their own namespace."""
    if not _OLD:
        ns = {"DD_NO_MAIN": True, "__name__": "old_plants"}
        src = os.path.join(_HERE, "render_plants.py")
        exec(compile(open(src).read(), src, "exec"), ns)
        _OLD.update(ns)
    return _OLD


def old_bundles(axis_old, part):
    """The three hanging buds of the old drying rack, built exactly as render_furniture.model_rack did in the old
    frame (x south, y east) and turned into this one, so they look as they did."""
    o = old_plants()
    rng = random.Random(40 + part)
    G = {k: o["Geo"]() for k in ("string", "bud", "pist", "sugar")}
    h = 86 / PX_V
    for x in (-0.3, 0.0, 0.3):
        pos = axis_old * x
        G["string"].add(*o["tube_geo"](pos + Vector((0, 0, h)), pos + Vector((0, 0, h - 0.1)), 0.004, 0.004, 4))
        o["add_bud"](G["bud"], G["pist"], G["sugar"], pos + Vector((0, 0, h - 0.1)), Vector((0.001, 0, -1)), 0.4, 0.15, rng, True)
    mats = {"string": o["new_mat"]("string", (150, 130, 90), 0.8), "bud": o["new_mat"]("dbud", (96, 112, 54), 0.7, frost=0.25),
            "pist": o["new_mat"]("dpist", (150, 90, 50), 0.7), "sugar": o["new_mat"]("dsugar", (84, 104, 50), 0.6)}
    turn = Matrix.Rotation(math.radians(-90), 4, "Z")
    for k, g in G.items():
        if not g.v: continue
        ob = g.to_object(k, mats[k])
        for c in list(ob.users_collection): c.objects.unlink(ob)
        MODEL.objects.link(ob); ob.matrix_world = HEAD[-1] @ turn
        BUILT.append(ob)


# ------------------------------------------------------------------ hanging dish lamps (plants_01 197-200)
LAMPS = {  # rim radius, rim height (old sprites), glow
    "Basic": (ph(22) * 1.1, pv(226 - 84), "#9a3cff"),
    "Pro": (ph(26) * 1.1, pv(226 - 84), "#ffd27a"),
    "LargeBasic": (ph(38) * 1.05, pv(226 - 80), "#9a3cff"),
    "LargePro": (ph(46) * 1.0, pv(226 - 80), "#ffd27a"),
}


def dish_lamp(kind):
    """Basic: a white-enamelled spun dish with a purple LED disc and a small driver on top, one hanger cable.
    Pro: a hammered aluminium reflector, finned ballast and a warm HPS bulb, on two ratchet hangers.
    The large ones are the same, wider, with more LEDs or a bigger ballast."""
    p = P(); R, z, glow_col = LAMPS[kind]; z += 0.06; pro = kind.endswith("Pro"); large = kind.startswith("Large")
    d = R * 0.58                                                     # depth of the dish
    if pro:
        refl = mat("#b9bcc0", 0.28, 0.85, var=0.18, dirt=0.25)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=False, segments=40, radius1=R, radius2=R * 0.32, depth=d)
        bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.01], cuts=3)
        for v in bm.verts:                                           # hammered dimples
            n = random.Random(int(v.co.x * 997 + v.co.y * 131 + v.co.z * 71)).uniform(-0.012, 0.012)
            v.co.x *= 1 + n; v.co.y *= 1 + n
        obj(bm, refl, M((0, 0, z + d / 2)), smooth=True)
    else:
        # UFO LED: a finned round heatsink, its sides tapering down to the LED face (the old saucer outline)
        hs = mat("#9fa2a8", 0.38, 0.7, var=0.1, dirt=0.25)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=48, radius1=R * 0.62, radius2=R, depth=0.1)
        obj(bm, hs, M((0, 0, z + 0.05)), smooth=True)
        cyl(R, 0.025, (0, 0, z + 0.112), hs, segs=48)
        nf = 28 if large else 20
        for i in range(nf):                                          # radial fins on top
            a_ = 360.0 * i / nf
            box((R * 0.52, 0.006, 0.03), (math.cos(math.radians(a_)) * R * 0.66, math.sin(math.radians(a_)) * R * 0.66, z + 0.14),
                hs, rot=(0, 0, a_), bevel=0.001)
        cyl(R * 0.36, 0.035, (0, 0, z + 0.14), mat("#3a3c40", 0.5, 0.3, dirt=0.2), segs=32)
        for i in range(3):                                           # fan grilles in the hub
            torus(R * (0.1 + 0.1 * i), 0.003, (0, 0, z + 0.158), P()["steel_dark"], seg=28, rseg=4)
    if pro: torus(R, 0.009, (0, 0, z), mat("#c9ccd0", 0.3, 0.7, dirt=0.2), seg=48, rseg=6)
    top = z + (d if pro else 0.12)
    cyl(R * (0.33 if pro else 0.39), 0.03, (0, 0, top + 0.012), p["steel_dark"], segs=28)
    if pro:
        # socket, warm HPS bulb glowing under the reflector
        tube((0, 0, top - 0.02), (0, 0, z + 0.07), 0.03, mat("#d9d4c4", 0.6), 16)
        ball(0.05 if large else 0.042, (0, 0, z + 0.02), glow("#ffd890", 16), scale=(1, 1, 1.7))
        cyl(R * 0.97, 0.022, (0, 0, z - 0.012), glow(glow_col, 3.0), segs=48, caps=False)    # light on the lip
        # ballast with fins, a sticker and a pilot lamp
        bw = 0.26 if large else 0.2; bz = top + 0.08
        box((bw, 0.13, 0.08), (0, 0, bz), mat("#2e3034", 0.5, 0.4, dirt=0.25), bevel=0.008)
        for i in range(8): box((0.004, 0.13, 0.025), (-bw / 2 + 0.02 + i * (bw - 0.04) / 7, 0, bz + 0.052), p["alu"], bevel=0.001)
        label((0.08, 0.002, 0.035), (0.04, -0.066, bz), "#d4a23a")
        print_lines(0.01, 0.07, bz + 0.008, -0.068, 2, 0.01)
        lamp((-0.07, -0.066, bz + 0.012), True, "#ff7a2a", r=0.006)
        screws([(sx, -0.066, bz + sz) for sx in (-bw / 2 + 0.012, bw / 2 - 0.012) for sz in (-0.028, 0.028)], 0.004)
        for a in (45, 225):
            ax, ay = math.cos(math.radians(a)) * 0.09, math.sin(math.radians(a)) * 0.09
            ratchet_hanger(ax, ay, bz + 0.04, CEIL_Z)
        cord([(bw / 2, 0, bz), (bw / 2 + 0.06, 0.05, bz + 0.08), (bw / 2 + 0.09, 0.12, CEIL_Z)])
    else:
        # purple LED disc: a dark board with rows of chips, and a lens ring
        rr = R * 0.6
        cyl(rr, 0.008, (0, 0, z - 0.004), mat("#2a2b2e", 0.5, 0.3, dirt=0.1), segs=40)
        n = 7 if large else 5; step = 2 * rr * 0.8 / (n - 1)
        for i in range(n):
            for j in range(n):
                x, y = -rr * 0.8 + i * step, -rr * 0.8 + j * step
                if math.hypot(x, y) < rr * 0.86:
                    box((0.018, 0.018, 0.004), (x, y, z - 0.009), glow(glow_col, 9), bevel=0)
        cyl(rr * 0.98, 0.002, (0, 0, z - 0.008), glow(glow_col, 1.8), segs=40)
        cyl(R * 0.64, 0.02, (0, 0, z - 0.004), glow(glow_col, 2.6), segs=48, caps=False)    # lens ring under the face
        # driver can on top, a sticker, a hook and one cable to the ceiling
        dz = top + 0.085
        box((0.13, 0.09, 0.06), (0, 0, dz), mat("#3a3c40", 0.5, 0.3, dirt=0.2), bevel=0.008)
        for i in range(5): box((0.12, 0.004, 0.004), (0, -0.03 + i * 0.015, dz + 0.031), p["alu"], bevel=0)
        label((0.06, 0.002, 0.03), (0.02, -0.046, dz), "#c9c3ae")
        lamp((-0.045, -0.046, dz + 0.01), True, "#57d36a", r=0.005)
        torus(0.016, 0.004, (0, 0, dz + 0.05), p["steel"], axis="Y", seg=14, rseg=5)
        if not ICON[0]:
            path([(0, 0, dz + 0.066), (0, 0, CEIL_Z)], 0.0035, p["steel"], segs=6)
            box((0.03, 0.03, 0.012), (0, 0, CEIL_Z - 0.006), p["steel_dark"], bevel=0.003)
        cord([(0.065, 0, dz), (0.1, 0.04, dz + 0.1), (0.12, 0.08, CEIL_Z)])
    return 0


# ------------------------------------------------------------------ LED bars (plants_01 214-233): one tile of a long bar
BAR_Z = pv(226 - 112) + 0.03


def bar_segment(pro, along_y):
    """One tile of a bar lamp; the bar runs on into the next tile through a coupler at each end.
    Basic: a brushed grey bar with one purple LED strip. Pro: a dark finned bar with two warm strips."""
    p = P(); z = BAR_Z
    L = 1.0; half = 0.5
    HEAD.append(HEAD[-1] @ (M((0, 0, 0), (0, 0, 90)) if along_y else Matrix.Identity(4)))
    body = mat("#3a3c41", 0.4, 0.6, dirt=0.2) if pro else mat("#9a9ca2", 0.35, 0.65, var=0.1, dirt=0.2)
    W = 0.13 if pro else 0.1
    box((L - 0.02, W, 0.04), (0, 0, z), body, bevel=0.008)
    if pro:
        for i in range(12):
            box((L - 0.06, 0.005, 0.03), (0, -W / 2 + 0.01 + i * (W - 0.02) / 11, z + 0.035), p["alu"], bevel=0.001)
        for y in (-0.03, 0.03):
            box((L - 0.06, 0.035, 0.006), (0, y, z - 0.022), glow("#ffe2a0", 14), bevel=0.001)
            for i in range(24):                                   # diode rows on the strip
                box((0.012, 0.012, 0.003), (-half + 0.05 + i * 0.039, y, z - 0.026), glow("#fff1c8", 18), bevel=0)
        for y in (-W / 2 - 0.002, W / 2 + 0.002):
            box((L - 0.04, 0.004, 0.012), (0, y, z - 0.012), glow("#ffd27a", 5), bevel=0.0005)
    else:
        for i in range(4):
            box((L - 0.05, 0.006, 0.012), (0, -0.03 + i * 0.02, z + 0.024), mat("#b4b6ba", 0.3, 0.7, dirt=0.15), bevel=0.001)
        box((L - 0.06, 0.04, 0.006), (0, 0, z - 0.022), mat("#26272a", 0.4, dirt=0), bevel=0.001)
        for i in range(20):
            box((0.016, 0.016, 0.004), (-half + 0.055 + i * 0.047, 0, z - 0.026), glow("#a050ff", 10), bevel=0)
        box((L - 0.06, 0.03, 0.002), (0, 0, z - 0.028), glow("#9a3cff", 2.2), bevel=0)
        for y in (-W / 2 - 0.002, W / 2 + 0.002):
            box((L - 0.04, 0.004, 0.01), (0, y, z - 0.014), glow("#a050ff", 4), bevel=0.0005)
    # couplers at the tile ends (half of each shows in this tile)
    for x in (-half + 0.012, half - 0.012):
        box((0.024, W + 0.012, 0.05), (x, 0, z), p["plastic"], bevel=0.003)
        screws([(x, -W / 2 - 0.007, z)], 0.004)
    # driver box on top, label and pilot light, hangers and the power cord
    dc = (0.12, 0, z + 0.05)
    box((0.22, 0.08, 0.05), dc, mat("#24262a", 0.5, 0.3, dirt=0.2) if pro else mat("#4a4c50", 0.5, 0.3, dirt=0.2), bevel=0.006)
    label((0.07, 0.002, 0.025), (0.14, -0.041, z + 0.05), "#c9c3ae" if pro else "#d4a23a")
    print_lines(0.11, 0.17, z + 0.056, -0.043, 2, 0.008)
    lamp((0.05, -0.041, z + 0.058), True, "#57d36a", r=0.005)
    screws([(0.02, -0.041, z + 0.035), (0.22, -0.041, z + 0.035)], 0.003)
    for x in (-0.3, 0.3):
        if pro: ratchet_hanger(x, 0, z + 0.03, CEIL_Z)
        else:
            torus(0.012, 0.003, (x, 0, z + 0.035), p["steel"], axis="X", seg=14, rseg=5)
            if not ICON[0]: path([(x, 0, z + 0.047), (x, 0, CEIL_Z)], 0.003, p["steel"], segs=6)
            if not ICON[0]: box((0.03, 0.03, 0.012), (x, 0, CEIL_Z - 0.006), p["steel_dark"], bevel=0.003)
    cord([(0.23, 0, z + 0.055), (0.3, 0.03, z + 0.2), (0.33, 0.05, CEIL_Z)])
    HEAD.pop()
    return 0


def bar_icon(pro):
    """A bar for the icon: one tile's length with its hangers."""
    for k, x in enumerate((0.0,)):
        HEAD.append(HEAD[-1] @ M((x, 0, 0)))
        bar_segment(pro, False)
        HEAD.pop()
    return 0


# ------------------------------------------------------------------ flood stands (plants_01 234-235)
def flood_stand(pro):
    """A tripod work-light stand. Basic: one yellow flood head with a purple LED panel. Pro: a charcoal T-bar with
    two finned heads, warm white. Heads face the viewer, tipped down at the plants."""
    p = P()
    leg = mat("#2c2e31", 0.45, 0.6, dirt=0.25)
    top = pv(112 if pro else 96) - 0.05
    hub = top * 0.32
    tube((0, 0, hub - 0.04), (0, 0, top), 0.016, leg, 12)
    tube((0, 0, top * 0.45), (0, 0, top * 0.8), 0.02, p["steel"], 12)                 # telescoping section
    box((0.034, 0.034, 0.05), (0, 0, top * 0.8), p["plastic"], bevel=0.004)
    cyl(0.01, 0.03, (0.025, 0, top * 0.8), mat("#c23a2e", 0.5), axis="X", segs=10)      # lock knob
    box((0.04, 0.04, 0.06), (0, 0, hub), p["plastic"], bevel=0.004)
    for a in (90, 210, 330):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        tube(Vector((0, 0, hub)), d * 0.34 + Vector((0, 0, 0.01)), 0.011, leg, 8)
        tube(d * 0.03 + Vector((0, 0, hub - 0.09)), d * 0.19 + Vector((0, 0, hub * 0.45)), 0.006, leg, 6)
        cyl(0.02, 0.014, d * 0.34 + Vector((0, 0, 0.007)), p["rubber"])
    ycol = mat("#d0a32e", 0.45, 0.15, var=0.08, dirt=0.25)
    if pro:
        heads = [(-0.225,), (0.225,)]
        tube((-0.44, 0, top), (0.44, 0, top), 0.014, leg, 10)
        for x in (-0.44, 0.44): cyl(0.016, 0.02, (x, 0, top), p["plastic"], axis="X", segs=10)
    else:
        heads = [(0.0,)]
        tube((-0.26, 0, top), (0.26, 0, top), 0.013, leg, 10)
    hw, hh = (0.4, 0.25) if pro else (0.46, 0.28)
    for (x,) in heads:
        # yoke arms up from the bar
        for s in (-1, 1):
            box((0.012, 0.03, 0.12), (x + s * (hw / 2 + 0.012), 0, top + 0.06), p["steel_dark"], bevel=0.002)
            cyl(0.02, 0.016, (x + s * (hw / 2 + 0.022), 0, top + 0.11), p["plastic"], axis="X", segs=14)
        hc = Vector((x, 0, top + 0.11))
        HEAD.append(HEAD[-1] @ M(hc, (-24, 0, 0)))                                    # tipped down at the plants
        shell = mat("#2b2d31", 0.45, 0.5, dirt=0.3) if pro else ycol
        box((hw, 0.08, hh), (0, 0, 0), shell, bevel=0.012)
        for i in range(9):                                                          # cooling fins at the back
            box((0.006, 0.05, hh - 0.04), (-hw / 2 + 0.03 + i * (hw - 0.06) / 8, 0.06, 0), p["alu"], bevel=0.001)
        box((hw - 0.03, 0.006, hh - 0.03), (0, -0.041, 0), mat("#1d1e20", 0.4, dirt=0), bevel=0.002)
        if pro:
            box((hw - 0.05, 0.004, hh - 0.05), (0, -0.045, 0), glow("#ffd98a", 5), bevel=0.001)
            for i in range(6):
                for j in range(4):
                    box((0.02, 0.003, 0.02), (-hw / 2 + 0.05 + i * (hw - 0.1) / 5, -0.048, -hh / 2 + 0.05 + j * (hh - 0.1) / 3),
                        glow("#fff3d0", 14), bevel=0)
        else:
            box((hw - 0.05, 0.004, hh - 0.05), (0, -0.045, 0), glow("#a050ff", 2.6), bevel=0.001)
            for i in range(6):
                for j in range(5):
                    box((0.018, 0.003, 0.018), (-hw / 2 + 0.05 + i * (hw - 0.1) / 5, -0.048, -hh / 2 + 0.05 + j * (hh - 0.1) / 4),
                        glow("#b070ff" if (i + j) % 3 else "#ff4a6a", 12), bevel=0)
        for i in range(3):                                                          # guard bars over the lens
            box((hw - 0.03, 0.006, 0.006), (0, -0.052, -hh / 2 + 0.03 + i * (hh - 0.06) / 2), p["steel_dark"], bevel=0)
        for sx in (-1, 1):
            for sz in (-1, 1): screws([(sx * (hw / 2 - 0.014), -0.042, sz * (hh / 2 - 0.014))], 0.005)
        label((0.07, 0.002, 0.022), (hw / 2 - 0.06, 0.041, -hh / 2 + 0.02), "#e1c43f" if pro else "#2b2c2e", rot=(0, 0, 0))
        HEAD.pop()
        cord([(x + 0.1, 0.04, top + 0.03), (x + 0.12, 0.05, top - 0.05)], 0.005)
    # switch box on the pole and the cord down to the floor
    box((0.08, 0.05, 0.1), (0, 0.035, top * 0.6), mat("#26282b", 0.5, 0.3), bevel=0.006)
    box((0.03, 0.01, 0.02), (0, 0.006, top * 0.6 + 0.02), mat("#c23a2e", 0.5), bevel=0.003)
    lamp((0, 0.004, top * 0.6 - 0.02), True, "#57d36a", r=0.005)
    cord([(0, 0.06, top * 0.6 - 0.04), (0.04, 0.1, top * 0.35), (0.12, 0.2, 0.05), (0.3, 0.32, 0.01), (0.42, 0.36, 0.008)])
    return 45


# ------------------------------------------------------------------ drying fan (plants_01 205)
def drying_fan():
    """A pedestal fan on a round cast base: telescoping pole, motor pod, three blades in a chrome cage, speed
    buttons on the base and a cord. Head turned to the viewer, tipped up a little."""
    p = P(); body = mat("#3c4048", 0.45, 0.3, dirt=0.25); chrome = mat("#c3c6c8", 0.3, 0.8, dirt=0.15)
    cyl(0.17, 0.035, (0, 0, 0.018), body, segs=40, r2=0.15)
    cyl(0.15, 0.012, (0, 0, 0.04), mat("#2c2f35", 0.5, 0.3, dirt=0.2), segs=40)
    for i, col in enumerate(("#d9d5c6", "#d9d5c6", "#d9d5c6", "#c23a2e")):
        a = math.radians(-70 - i * 16)
        box((0.022, 0.016, 0.012), (math.cos(a) * 0.11, math.sin(a) * 0.11, 0.043), mat(col, 0.5, dirt=0.1),
            rot=(0, 0, math.degrees(a) + 90), bevel=0.003)
    tube((0, 0, 0.04), (0, 0, 0.42), 0.02, body, 14)
    tube((0, 0, 0.4), (0, 0, 0.6), 0.014, chrome, 12)
    cyl(0.026, 0.03, (0, 0, 0.42), mat("#2c2f35", 0.5), segs=16)
    cyl(0.008, 0.03, (0.03, 0, 0.42), mat("#2c2f35", 0.5), axis="X", segs=10)
    c = Vector((0, 0, 0.66))
    HEAD.append(HEAD[-1] @ M(c, (8, 0, 0)))
    box((0.05, 0.05, 0.05), (0, 0.02, -0.04), body, bevel=0.006)
    cyl(0.055, 0.1, (0, 0.06, 0), body, axis="Y", segs=24)
    ball(0.055, (0, 0.11, 0), body, scale=(1, 0.6, 1))
    for i in range(6): box((0.004, 0.03, 0.02), (-0.025 + i * 0.01, 0.12, 0.03), mat("#1f2125", 0.5), bevel=0)
    cyl(0.008, 0.06, (0, -0.02, 0), p["steel"], axis="Y", segs=10)
    blades = mat("#6f97bd", 0.2, alpha=0.85, dirt=0, var=0.05)
    for i in range(3):
        bm = blade_bm(0.16, 0.08, 0.12, 0.004, -10, pitch=25, curve=0.02)
        obj(bm, blades, Matrix.Translation((0, -0.04, 0)) @ Euler((0, math.radians(30 + 120 * i), 0)).to_matrix().to_4x4() @ M((0, 0, 0.03)), smooth=True)
    cyl(0.035, 0.03, (0, -0.045, 0), mat("#2c2f35", 0.4), axis="Y", segs=20)
    for side, rings, sp, dep in ((0.0, (0.4, 0.7, 0.9), 16, -0.02), (-0.08, (0.3, 0.55, 0.8), 24, 0.04)):
        cc = Vector((0, side, 0))
        for f in rings: torus(0.2 * f, 0.0025, cc + Vector((0, -dep * (1 - f * f), 0)), chrome, axis="Y", seg=40, rseg=5)
        torus(0.2, 0.0045, cc, chrome, axis="Y", seg=48, rseg=6)
        for i in range(sp):
            a = 2 * math.pi * i / sp
            path([cc + Vector((math.cos(a) * 0.2 * f, -dep * (1 - f * f), math.sin(a) * 0.2 * f)) for f in (0.12, 0.5, 1.0)], 0.0022, chrome, segs=5)
    cyl(0.04, 0.01, (0, -0.125, 0), mat("#3c5f86", 0.4, dirt=0), axis="Y", segs=24)
    torus(0.2, 0.008, (0, -0.04, 0), mat("#3c4048", 0.4, 0.3), axis="Y", seg=48, rseg=6)
    HEAD.pop()
    cord([(0.1, 0.12, 0.03), (0.2, 0.2, 0.012), (0.36, 0.26, 0.008)])
    return 45


# ------------------------------------------------------------------ drying rack (plants_01 206-213)
def drying_rack(along_y, part):
    """One tile of a two-tile wooden drying rack: two top rails with cross bars the buds hang from on twine,
    a low brace rail, and on the outer tile end an H-frame with feet and a diagonal brace."""
    wood = mat("#8b6a48", 0.8, var=0.2, dirt=0.3); dark = mat("#5f4a36", 0.85, var=0.2, dirt=0.3)
    p = P(); h = 86 / PX_V; half = 0.5
    # local frame: the rack runs along +X; part 0 holds the -X end (north for E racks, west for S racks)
    HEAD.append(HEAD[-1] @ (M((0, 0, 0), (0, 0, -90)) if along_y else Matrix.Identity(4)))
    for off in (-0.13, 0.13):
        box((1.0, 0.04, 0.045), (0, off, h + 0.01), wood, bevel=0.005)
        box((1.0, 0.025, 0.02), (0, off, h * 0.45), dark, bevel=0.003)
    for x in (-0.3, 0.0, 0.3):                                       # cross bars and hooks the twine ties to
        box((0.03, 0.3, 0.025), (x, 0, h + 0.045), wood, bevel=0.003)
        torus(0.01, 0.0025, (x, 0, h + 0.025), p["steel"], axis="X", seg=12, rseg=4)
    for x in (-0.5, 0.5):                                            # rail joints with a bolt plate
        for off in (-0.13, 0.13):
            box((0.03, 0.046, 0.052), (x * 0.985, off, h + 0.01), mat("#4b4e52", 0.5, 0.5, dirt=0.3), bevel=0.002)
            screws([(x * 0.985, off - 0.024, h + 0.01)], 0.004)
    end = -half + 0.03 if part == 0 else half - 0.03
    for off in (-0.13, 0.13):
        box((0.05, 0.05, h + 0.06), (end, off, (h + 0.06) / 2), wood, bevel=0.005)
        box((0.06, 0.12, 0.025), (end, off, 0.012), dark, bevel=0.004)
        cyl(0.012, 0.01, (end, off - 0.045, 0.005), p["rubber"], segs=10)
        cyl(0.012, 0.01, (end, off + 0.045, 0.005), p["rubber"], segs=10)
    box((0.04, 0.3, 0.04), (end, 0, h * 0.2), wood, bevel=0.004)
    box((0.04, 0.3, 0.04), (end, 0, h - 0.04), wood, bevel=0.004)
    s = 1 if part == 0 else -1
    for off in (-0.13, 0.13):                                        # diagonal braces to the low rail
        tube((end, off, h * 0.82), (end + s * 0.22, off, h + 0.0), 0.012, wood, 6)
    screws([(end, -0.155, h * 0.2), (end, -0.155, h - 0.04)], 0.005)
    HEAD.pop()
    # the buds, as they were
    old_bundles(Vector((0, 1, 0)) if not along_y else Vector((1, 0, 0)), part)
    return 0


def rack_icon():
    drying_rack(False, 0)
    HEAD.append(HEAD[-1] @ M((1.0, 0, 0))); drying_rack(False, 1); HEAD.pop()
    return 0


# ------------------------------------------------------------------ curing barrel (plants_01 236)
def curing_barrel():
    """An oak barrel on end: bulging staves with seams and a little colour each, four riveted iron hoops,
    a planked lid with a cross batten and a brass bung, and a chalked label."""
    p = P(); r, h = ph(24), pv(62)
    rnd = random.Random(3)
    n = 18
    for i in range(n):
        a0 = 2 * math.pi * i / n
        col = random.Random(i * 7).choice(("#8a5d36", "#80552f", "#93653c", "#7a5230"))
        st = mat(col, 0.75, var=0.22, dirt=0.3)
        bm = bmesh.new(); rows = []
        for k in range(9):
            t = k / 8; rr = r * (1 + 0.1 * math.sin(math.pi * t)); z = h * t; row = []
            for j in range(3):
                a = a0 + (2 * math.pi / n) * (0.04 + 0.92 * j / 2)
                row.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
            rows.append(row)
        for k in range(8):
            for j in range(2): bm.faces.new((rows[k][j], rows[k][j + 1], rows[k + 1][j + 1], rows[k + 1][j]))
        sol = obj(bm, st, smooth=True)
        md = sol.modifiers.new("s", "SOLIDIFY"); md.thickness = 0.012
    cyl(r * 1.0, 0.02, (0, 0, 0.012), mat("#4e3520", 0.85), segs=40)
    iron = mat("#38383a", 0.55, 0.5, var=0.12, dirt=0.3)
    for t in (0.1, 0.3, 0.7, 0.9):
        rr = r * (1 + 0.1 * math.sin(math.pi * t)) + 0.006
        cyl(rr, 0.03, (0, 0, h * t), iron, segs=48, caps=False)
        for k in range(10):
            a = 2 * math.pi * (k + 0.5) / 10
            ball(0.004, (math.cos(a) * (rr + 0.001), math.sin(a) * (rr + 0.001), h * t), p["steel"], segs=6)
    lid = mat("#9a6a40", 0.75, var=0.2, dirt=0.25)
    cyl(r * 0.95, 0.02, (0, 0, h - 0.02), lid, segs=40)
    for k in range(-2, 3):
        box((0.004, r * 1.8 * math.sqrt(max(0.05, 1 - (k * 0.33) ** 2)), 0.004), (k * r * 0.33, 0, h - 0.009), mat("#4e3520", 0.85), bevel=0)
    box((r * 1.5, 0.04, 0.02), (0, 0, h + 0.002), mat("#7a5230", 0.8, var=0.2), rot=(0, 0, 90), bevel=0.004)
    for y in (-r * 0.6, r * 0.6): screws([(0, y, h + 0.013)], 0.005, axis="Z")
    cyl(0.025, 0.012, (r * 0.5, -r * 0.3, h - 0.004), p["brass"], segs=16)
    label((0.1, 0.002, 0.07), (0.0, -r * 1.09 - 0.002, h * 0.5), "#d9d2bc", rot=(0, 0, 0))
    print_lines(-0.035, 0.035, h * 0.5 + 0.02, -r * 1.09 - 0.004, 4, 0.012, "#5a4632")
    return 30


# ------------------------------------------------------------------ grow bags (plants_01 195/196/201-204, hydro_01 235-237)
BAGS = {"small": (ph(24) * 1.06, pv(26)), "large": (ph(34) * 1.06, pv(40)), "xl": (ph(34) * 1.3, pv(56))}


def grow_bag(size, soil):
    """A fabric pot: sagging felt walls, a stitched rim band, two strap handles and a sewn-on label;
    with soil, a lumpy top dressed with perlite, else the empty felt inside."""
    p = P(); rnd = random.Random({"small": 4, "large": 5, "xl": 6}[size])
    R, H = BAGS[size]
    felt = fabric_mat("#3a3b3e"); band = mat("#2a2b2d", 0.9, var=0.1, dirt=0.3); inner = fabric_mat("#2a2b2e", dirt=0.2)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=48, radius1=R * 0.94, radius2=R, depth=H)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.1], cuts=6)
    for v in bm.verts:                                               # soft bulge and creases
        a = math.atan2(v.co.y, v.co.x); t = (v.co.z + H / 2) / H
        bulge = 1 + 0.045 * math.sin(t * math.pi) + 0.012 * math.sin(a * 7 + t * 3) + 0.006 * math.sin(a * 13 - t * 5)
        v.co.x *= bulge; v.co.y *= bulge
    sol = obj(bm, felt, M((0, 0, H / 2)), smooth=True)
    md = sol.modifiers.new("s", "SOLIDIFY"); md.thickness = 0.01
    cyl(R * 1.035 + 0.006, 0.05, (0, 0, H - 0.022), band, segs=48, caps=False)
    torus(R * 1.035 + 0.004, 0.008, (0, 0, H + 0.002), band, seg=48, rseg=6)
    cyl(R * 0.94, 0.012, (0, 0, 0.006), band, segs=48)
    stitch = mat("#8a8a86", 0.8, dirt=0.2)
    for z in (H - 0.004, H - 0.044):
        for i in range(72):
            a = 2 * math.pi * i / 72
            box((0.012, 0.002, 0.003), (math.cos(a) * (R * 1.035 + 0.01), math.sin(a) * (R * 1.035 + 0.01), z),
                stitch, rot=(0, 0, math.degrees(a) + 90), bevel=0)
    for a in (45, 225):                                              # strap handles, sewn to the band
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        pts = []
        for k in range(9):
            t = k / 8; ang = math.radians(a) + (t - 0.5) * 0.45
            rr = R * 1.045 + 0.012 + 0.03 * math.sin(math.pi * t)
            pts.append((math.cos(ang) * rr, math.sin(ang) * rr, H - 0.045 + 0.075 * math.sin(math.pi * t)))
        path(pts, 0.009, band, segs=6)
        for t in (0, 1):
            ang = math.radians(a) + (t - 0.5) * 0.45
            box((0.03, 0.006, 0.04), (math.cos(ang) * (R * 1.045 + 0.012), math.sin(ang) * (R * 1.045 + 0.012), H - 0.04),
                band, rot=(0, 0, math.degrees(ang) + 90), bevel=0.002)
    if soil:
        soil_top(R * 1.0, H - 0.026, rnd, 26 * (R / 0.3) ** 2)
    else:
        cyl(R * 0.93, 0.006, (0, 0, 0.03), inner, segs=48)
    # sewn label: pale tag with a leaf mark and two lines
    la = math.radians(-62); lr = R * 1.0 + 0.012
    lc = Vector((math.cos(la) * lr, math.sin(la) * lr, H * 0.45))
    label((0.12 * min(1.2, R / 0.3), 0.003, 0.07 * min(1.2, R / 0.3)), lc, "#c9c1a5", rot=(0, 0, math.degrees(la) + 90))
    n = Vector((math.cos(la), math.sin(la), 0)) * 0.003
    box((0.022, 0.002, 0.022), lc + n + Vector((math.sin(la) * 0.03, -math.cos(la) * 0.03, 0.008)), mat("#4f7a3a", 0.6, dirt=0),
        rot=(0, 45, math.degrees(la) + 90), bevel=0)
    return 0


# ------------------------------------------------------------------ DWC and RDWC buckets
BUCKETS = {"dwc": (ph(22), pv(40), "#25272a"), "xldwc": (ph(22) * 1.25, pv(54), "#25272a"),
           "rdwc": (ph(22), pv(40), "#45607e"), "control": (ph(27), pv(72), "#dcdcd8")}


def bucket(kind, medium):
    """A ribbed bucket with a snap lid and a net pot; DWC buckets have their own air pump on the floor, RDWC
    sites a bulkhead fitting and return hose off to the side. `medium`: clay pebbles round a rockwool cube."""
    p = P(); rnd = random.Random(hash(kind) % 100 + 2)
    R, H, col = BUCKETS[kind]
    body = mat(col, 0.5, var=0.12, dirt=0.35)
    lidm = mat({"rdwc": "#5a7493", "control": "#e8e8e4"}.get(kind, "#2f3135"), 0.5, dirt=0.3)
    hb = H - 0.035
    cyl(R * 0.88, hb, (0, 0, hb / 2), body, segs=40, r2=R)
    for t in (0.28, 0.5, 0.72):
        z = hb * t; rr = R * (0.88 + 0.12 * t)
        torus(rr + 0.004, 0.006, (0, 0, z), body, seg=40, rseg=6)
    torus(R + 0.006, 0.01, (0, 0, hb - 0.012), body, seg=40, rseg=6)
    cyl(R + 0.012, 0.035, (0, 0, H - 0.017), lidm, segs=40)
    for i in range(16):                                              # lid tabs
        a = 2 * math.pi * i / 16
        box((0.016, 0.008, 0.024), (math.cos(a) * (R + 0.014), math.sin(a) * (R + 0.014), H - 0.022), lidm,
            rot=(0, 0, math.degrees(a) + 90), bevel=0.002)
    rp = 0.085 * (1.15 if kind == "xldwc" else 1.0)
    torus(rp, 0.008, (0, 0, H + 0.006), mat("#1a1b1d", 0.6), seg=32)
    cyl(rp, 0.004, (0, 0, H + 0.001), mat("#0c0c0d", 0.8, dirt=0), segs=32)
    if medium:
        pebbles(rp, H + 0.012, rnd, 70)
        rockwool((0, 0, H + 0.03), 0.05, 0.04, 0.3)
    else:
        for k in range(-3, 4):                                       # the net pot's slots
            box((0.006, rp * 1.8 * math.sqrt(max(0.1, 1 - (k * 0.27) ** 2)), 0.004), (k * rp * 0.27, 0, H + 0.004),
                mat("#1a1b1d", 0.6), bevel=0)
    # handle and side sticker, a level window
    torus(R + 0.02, 0.0045, (0, 0, hb - 0.05), p["steel"], axis="X", seg=40, rseg=6, rot=(68, 0, 0))
    for s in (-1, 1): cyl(0.014, 0.012, (s * (R + 0.004), 0, hb - 0.05), body, axis="X", segs=12)
    la = math.radians(-60)
    box((0.026, 0.004, hb * 0.6), (math.cos(la - 0.35) * R * 0.97, math.sin(la - 0.35) * R * 0.97, hb * 0.42),
        mat("#4f6a73", 0.2, alpha=0.6, dirt=0, wear=False), rot=(0, 0, math.degrees(la - 0.35) + 90), bevel=0.002)
    lc = (math.cos(la + 0.2) * R * 0.98, math.sin(la + 0.2) * R * 0.98, hb * 0.6)
    label((0.1, 0.002, 0.075), lc, "#d9d2bc" if kind != "control" else "#2f6fb0", rot=(0, 0, math.degrees(la + 0.2) + 90))
    if kind in ("dwc", "xldwc"):
        ap = SCREEN_R * (R + 0.15) + TOWARD * 0.05
        box((0.13, 0.08, 0.065), ap + Vector((0, 0, 0.035)), mat("#d8d6cf", 0.55, dirt=0.35), rot=(0, 0, 35), bevel=0.012)
        box((0.05, 0.003, 0.02), ap + Vector((-0.02, -0.04, 0.035)), mat("#2f6fb0", 0.5), rot=(0, 0, 35), bevel=0)
        lamp(ap + Vector((0.03, -0.035, 0.05)), True, "#57d36a", r=0.004)
        for s in (-1, 1): ball(0.008, ap + Vector((s * 0.04, s * 0.02, 0.004)), p["rubber"], segs=6)
        lid_pt = Vector((R * 0.55, R * 0.25, H + 0.01))
        a0 = ap + Vector((0, 0.04, 0.06))
        path([a0, a0 + Vector((0, 0.02, 0.1)), (a0 + lid_pt) / 2 + Vector((0, 0.02, 0.18)), lid_pt + Vector((0, 0, 0.06)), lid_pt],
             0.004, mat("#b8d4d6", 0.3, alpha=0.8, dirt=0))
        cyl(0.012, 0.012, lid_pt, mat("#1a1b1d", 0.6), segs=10)
        cord([ap + Vector((0.06, 0.02, 0.02)), ap + Vector((0.12, 0.08, 0.008)), ap + Vector((0.13, 0.22, 0.006))], 0.005)
    elif kind == "rdwc":
        out = -SCREEN_R
        fit = out * R * 0.95 + Vector((0, 0, 0.06))
        cyl(0.03, 0.03, fit, mat("#1a1b1d", 0.5), axis="X", rot=(0, 90, -135), segs=16)
        reach = 0.22 if ICON[0] else 0.55
        path([fit + out * 0.02, fit + out * 0.09 + Vector((0, 0, -0.03)), out * (R + 0.2) + TOWARD * 0.04 + Vector((0, 0, 0.02)),
              out * (R + reach) + TOWARD * 0.1 + Vector((0, 0, 0.02))], 0.02, mat("#1d1e20", 0.6, dirt=0.2), segs=10)
        torus(0.024, 0.004, fit + out * 0.05, P()["steel"], axis="X", rot=(0, 90, -135), seg=16, rseg=5)
        lid_pt = Vector((R * 0.55, R * 0.25, H + 0.008))
        cyl(0.012, 0.014, lid_pt, mat("#1a1b1d", 0.6), segs=10)
        if not ICON[0]:
            path([lid_pt, lid_pt + Vector((0, 0, 0.05)), lid_pt + Vector((0.08, 0.1, 0.04)), Vector((R + 0.1, R + 0.2, 0.01))],
                 0.004, mat("#b8d4d6", 0.3, alpha=0.8, dirt=0))
    return 0


def rdwc_control():
    """The RDWC control bucket: a tall white reservoir with a level gauge, a pump head and its control box on the
    lid, an air pump on the floor and three return hoses lying out to the sites."""
    p = P(); R, H, _ = BUCKETS["control"]
    bucket("control", False)
    cyl(0.085, 0.006, (0, 0, H + 0.002), mat("#2f3135", 0.5), segs=32)
    box((0.15, 0.11, 0.075), (0, 0, H + 0.04), mat("#2e3034", 0.5, 0.3, dirt=0.2), rot=(0, 0, 45), bevel=0.008)
    box((0.13, 0.004, 0.004), (0, 0, H + 0.08), p["alu"], rot=(0, 0, 45), bevel=0)
    lamp(TOWARD * 0.062 + Vector((0, 0, H + 0.05)), True, "#57d36a", r=0.007)
    label((0.05, 0.002, 0.025), TOWARD * 0.058 + SCREEN_R * 0.035 + Vector((0, 0, H + 0.035)), "#e1c43f", rot=(0, 0, 45))
    cyl(0.012, 0.03, (0, 0, H + 0.09), mat("#1a1b1d", 0.6), segs=10)
    # level gauge tube up the side
    g = Vector((math.cos(math.radians(-100)), math.sin(math.radians(-100)), 0)) * (R * 0.97 + 0.012)
    tube(g + Vector((0, 0, 0.06)), g + Vector((0, 0, H - 0.08)), 0.012, mat("#cfd6d4", 0.15, alpha=0.6, dirt=0, wear=False), 12)
    tube(g + Vector((0, 0, 0.065)), g + Vector((0, 0, H * 0.62)), 0.008, mat("#4f86b5", 0.2, dirt=0), 10)
    for z in (0.06, H - 0.08): cyl(0.016, 0.016, g + Vector((0, 0, z)), mat("#2f3135", 0.5), segs=12)
    # air pump
    ap = SCREEN_R * (R + 0.16) + TOWARD * 0.06
    box((0.13, 0.08, 0.065), ap + Vector((0, 0, 0.035)), mat("#d8d6cf", 0.55, dirt=0.35), rot=(0, 0, 35), bevel=0.012)
    lamp(ap + Vector((0.03, -0.035, 0.05)), True, "#57d36a", r=0.004)
    lid_pt = Vector((R * 0.55, R * 0.25, H + 0.01))
    a0 = ap + Vector((0, 0.04, 0.06))
    path([a0, a0 + Vector((0, 0.02, 0.12)), (a0 + lid_pt) / 2 + Vector((0, 0.02, 0.22)), lid_pt + Vector((0, 0, 0.06)), lid_pt],
         0.004, mat("#b8d4d6", 0.3, alpha=0.8, dirt=0))
    hose = mat("#1d1e20", 0.6, dirt=0.2)
    for a in (-1.5, 1.5, 2.7):                                       # old directions, turned into this frame
        o_old = Vector((math.cos(a), -math.sin(a), 0))               # (TOWARD cos - RIGHT sin) in the old frame
        out = (TOWARD * o_old.x + SCREEN_R * o_old.y).normalized()
        fit = out * R * 0.92 + Vector((0, 0, 0.07))
        tube(fit, fit + out * 0.05, 0.026, mat("#1a1b1d", 0.5), 14)
        torus(0.028, 0.004, fit + out * 0.045, p["steel"], axis="Z", seg=16, rseg=5,
              rot=(0, 90, math.degrees(math.atan2(out.y, out.x))))
        path([fit + out * 0.05, fit + out * 0.13 + Vector((0, 0, -0.045)), out * (R + 0.32) + Vector((0, 0, 0.02)),
              out * (R + (0.36 if ICON[0] else 0.58)) + Vector((0, 0, 0.02))], 0.02, hose, segs=10)
    return 0


# ------------------------------------------------------------------ flood table and reservoir (hydro_01)
TABLE_TOP = pv(30)


def flood_table(medium, icon=False):
    """One tile of an ebb-and-flow bench: a ribbed white tray with a lip on a galvanised stand, a drain and an
    overflow fitting, and with `medium` a 4-inch rockwool block in the middle."""
    p = P(); galv = p["galv"]; top = TABLE_TOP; half = 0.47
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (half - 0.035), sy * (half - 0.035)
            box((0.032, 0.032, top - 0.03), (x, y, (top - 0.03) / 2), galv, bevel=0.004)
            box((0.05, 0.05, 0.012), (x, y, 0.006), p["rubber"], bevel=0.003)
            box((0.036, 0.036, 0.02), (x, y, top - 0.035), mat("#2c2d30", 0.6), bevel=0.003)
    for z in (0.09,):
        rect(-half + 0.035, half - 0.035, -half + 0.035, half - 0.035, z, 0.01, galv)
    rect(-half + 0.035, half - 0.035, -half + 0.035, half - 0.035, top - 0.05, 0.012, galv)
    tray = mat("#eeece6", 0.5, var=0.08, dirt=0.25)
    box((2 * half, 2 * half, 0.03), (0, 0, top - 0.02), tray, bevel=0.01)
    for x in (-half + 0.012, half - 0.012):
        box((0.024, 2 * half, 0.06), (x, 0, top + 0.02), tray, bevel=0.008)
    for y in (-half + 0.012, half - 0.012):
        box((2 * half, 0.024, 0.06), (0, y, top + 0.02), tray, bevel=0.008)
    for i in range(10):                                              # drainage ribs and channels
        box((0.02, 2 * half - 0.12, 0.012), (-0.36 + i * 0.08, 0, top + 0.0), mat("#e4e1d8", 0.55, dirt=0.3), bevel=0.003)
    box((2 * half - 0.08, 0.04, 0.004), (0, half - 0.07, top - 0.004), mat("#cfccc2", 0.6, dirt=0.4), bevel=0)
    wet = mat("#9aa6a2", 0.15, var=0.3, alpha=0.07, dirt=0, wear=False)
    box((2 * half - 0.06, 2 * half - 0.06, 0.002), (0, 0, top + 0.004), wet, bevel=0)
    # drain (with a strainer) and an overflow in the back corners
    cyl(0.03, 0.02, (half - 0.1, half - 0.1, top + 0.006), p["plastic"], segs=20)
    for k in range(4): box((0.04, 0.003, 0.003), (half - 0.1, half - 0.1, top + 0.017), mat("#1a1b1d", 0.6), rot=(0, 0, 45 * k), bevel=0)
    cyl(0.02, 0.06, (-half + 0.1, half - 0.1, top + 0.03), mat("#3d6fae", 0.45), segs=16)
    cyl(0.026, 0.006, (-half + 0.1, half - 0.1, top + 0.06), mat("#2f5a90", 0.45), segs=16)
    if not icon:
        hose = mat("#202325", 0.6, dirt=0.15)
        path([(half - 0.1, half - 0.1, top - 0.03), (half - 0.1, half - 0.1, 0.15), (half - 0.12, half - 0.16, 0.02)], 0.013, hose)
    label((0.12, 0.002, 0.03), (-0.18, -half - 0.001, top + 0.02), "#2f6fb0")
    print_lines(-0.23, -0.15, top + 0.025, -half - 0.003, 2, 0.01, "#e8e4d8", 0.003)
    if medium:
        h = pv(11)
        rockwool((0, 0, top + 0.006 + h / 2), 0.16, h, 0.2)
    return 0


def flood_reservoir():
    """The flood reservoir: a black tote with a ribbed grey lid and handles, fill and drain hoses up to table
    height, a level sticker and the pump's control box with its pilot lamp."""
    p = P(); w, d, h = 0.6, 0.6, 0.44
    tote = mat("#2a2b2e", 0.55, var=0.1, dirt=0.35)
    box((w - 0.04, d - 0.04, h), (0, 0, h / 2), tote, bevel=0.02)
    for k in range(4):                                               # moulded ribs
        box((0.02, 0.012, h - 0.12), (-0.21 + k * 0.14, -(d - 0.04) / 2 - 0.004, h / 2 - 0.02), tote, bevel=0.004)
        box((0.012, 0.02, h - 0.12), ((w - 0.04) / 2 + 0.004, -0.21 + k * 0.14, h / 2 - 0.02), tote, bevel=0.004)
    lid = mat("#6a6d72", 0.5, var=0.08, dirt=0.3)
    box((w, d, 0.035), (0, 0, h + 0.012), lid, bevel=0.01)
    for k in range(5): box((w - 0.08, 0.012, 0.008), (0, -0.2 + k * 0.1, h + 0.032), lid, bevel=0.002)
    for s in (-1, 1):
        box((0.12, 0.03, 0.03), (0, s * (d / 2 - 0.005), h - 0.04), mat("#1f2023", 0.5), bevel=0.006)
    label((0.11, 0.002, 0.08), (0.12, -(d - 0.04) / 2 - 0.012, h * 0.55), "#d9d2bc")
    box((0.015, 0.002, 0.06), (0.1, -(d - 0.04) / 2 - 0.014, h * 0.55), mat("#2f6fb0", 0.5, dirt=0), bevel=0)
    print_lines(0.12, 0.165, h * 0.55 + 0.025, -(d - 0.04) / 2 - 0.014, 4, 0.012)
    hose = mat("#202325", 0.6, dirt=0.15)
    out = -SCREEN_R
    for k, off in enumerate((-0.12, 0.08)):
        base = -SCREEN_R * 0.16 + TOWARD * off + Vector((0, 0, h + 0.03))
        cyl(0.026, 0.025, base, mat("#3d6fae" if k else "#1a1b1d", 0.45), segs=14)
        path([base, base + Vector((0, 0, 0.1)), base + out * 0.12 + Vector((0, 0, 0.14)), base + out * 0.34 + Vector((0, 0, 0.1))],
             0.016, hose, segs=10)
    bc = SCREEN_R * 0.21 + TOWARD * 0.21 + Vector((0, 0, h * 0.62))
    box((0.13, 0.13, 0.14), bc, mat("#d8d6cf", 0.5, dirt=0.3), bevel=0.01)
    box((0.08, 0.004, 0.03), bc + Vector((0, -0.066, 0.03)), mat("#1b2a20", 0.2, dirt=0), bevel=0)
    lamp(bc + Vector((-0.04, -0.067, -0.02)), True, "#57d36a", 0.007)
    box((0.03, 0.01, 0.02), bc + Vector((0.03, -0.068, -0.02)), mat("#c23a2e", 0.5), bevel=0.003)
    box((0.004, 0.06, 0.03), bc + Vector((0.066, 0, 0.0)), mat("#e1c43f", 0.6, dirt=0), bevel=0)
    cord([bc + Vector((0.05, 0.06, -0.06)), bc + Vector((0.12, 0.12, -h * 0.6)), bc + Vector((0.2, 0.2, -h * 0.62 + 0.01))], 0.005)
    return 0


# ------------------------------------------------------------------ ground plot (plants_01 65)
def ground_plot():
    """A dug, raked patch of soil: a low round mound with a ragged edge, clods and a few stones."""
    rnd = random.Random(65)
    R = 0.5; nr, ns = 14, 72
    bm = bmesh.new(); rings = []
    edge = [R * (0.93 + 0.07 * math.sin(a * 5 + 1) * 0.5 + rnd.uniform(-0.03, 0.03)) for a in [2 * math.pi * j / ns for j in range(ns)]]
    c = bm.verts.new((0, 0, 0.05))
    for i in range(1, nr + 1):
        t = i / nr; ring = []
        for j in range(ns):
            a = 2 * math.pi * j / ns; r = edge[j] * t
            x, y = math.cos(a) * r, math.sin(a) * r
            z = 0.03 * (1 - t ** 4) + 0.022 * math.exp(-((t - 0.8) / 0.09) ** 2) + (rnd.uniform(-0.004, 0.006) + 0.005 * math.sin(x * 38 + y * 6)) * (1 - t)
            ring.append(bm.verts.new((x, y, max(0.002, z) if i < nr else 0.0)))
        rings.append(ring)
    for j in range(ns): bm.faces.new((c, rings[0][j], rings[0][(j + 1) % ns]))
    for i in range(nr - 1):
        for j in range(ns):
            k = (j + 1) % ns
            bm.faces.new((rings[i][j], rings[i + 1][j], rings[i + 1][k], rings[i][k]))
    obj(bm, bumpy("#5a3e26", 0.98, 0.3, 0.0, 70, 0.9), smooth=True)
    for _ in range(24):
        a = rnd.uniform(0, 6.283); d = 0.42 * rnd.random() ** 0.6
        x, y = math.cos(a) * d, math.sin(a) * d
        z = 0.03 * (1 - (d / 0.5) ** 4) + 0.022 * math.exp(-((d / 0.5 - 0.8) / 0.09) ** 2)
        ball(rnd.uniform(0.008, 0.016), (x, y, z), mat("#3e2c1d", 0.95, var=0.3, dirt=0), scale=(1, 0.8, 0.5), segs=7)
    for _ in range(7):
        a = rnd.uniform(0, 6.283); d = 0.42 * rnd.random() ** 0.5
        x, y = math.cos(a) * d, math.sin(a) * d
        ball(rnd.uniform(0.01, 0.018), (x, y, 0.03 * (1 - (d / 0.5) ** 4) + 0.022 * math.exp(-((d / 0.5 - 0.8) / 0.09) ** 2)), mat("#8a8378", 0.8, var=0.2, dirt=0.2),
             scale=(1.2, 0.9, 0.6), segs=8)
    return 0


# ------------------------------------------------------------------ cells
# sheet -> [(indices, builder, floor piece)]
CELLS = {
    "plants_01": [
        ((65,), ground_plot, False),
        ((195,), lambda: grow_bag("small", True), True), ((196,), lambda: grow_bag("large", True), True),
        ((201, 203), lambda: grow_bag("small", False), True), ((202, 204), lambda: grow_bag("large", False), True),
        ((197,), lambda: dish_lamp("Basic"), False), ((198,), lambda: dish_lamp("Pro"), False),
        ((199,), lambda: dish_lamp("LargeBasic"), False), ((200,), lambda: dish_lamp("LargePro"), False),
        ((205,), drying_fan, True),
        ((206, 210), lambda: drying_rack(True, 0), True), ((207, 211), lambda: drying_rack(True, 1), True),
        ((208, 212), lambda: drying_rack(False, 0), True), ((209, 213), lambda: drying_rack(False, 1), True),
        ((214, 215, 218, 219), lambda: bar_segment(False, True), False), ((216, 217, 220, 221), lambda: bar_segment(False, False), False),
        ((222, 223, 224, 228, 229, 230), lambda: bar_segment(True, True), False),
        ((225, 226, 227, 231, 232, 233), lambda: bar_segment(True, False), False),
        ((234,), lambda: flood_stand(False), True), ((235,), lambda: flood_stand(True), True),
        ((236,), curing_barrel, True),
        ((372, 373), lambda: bucket("dwc", False), True), ((374,), lambda: bucket("dwc", True), True),
    ],
    "hydro_01": [
        ((0, 1), lambda: bucket("rdwc", False), True), ((2,), lambda: bucket("rdwc", True), True),
        ((113,), rdwc_control, True),
        ((114, 115, 116, 117, 118, 119, 120, 121, 122), lambda: flood_table(False), True),
        ((123,), lambda: flood_table(True), True),
        ((234,), flood_reservoir, True),
        ((235, 237), lambda: grow_bag("xl", False), True), ((236,), lambda: grow_bag("xl", True), True),
        ((348, 349), lambda: bucket("xldwc", False), True), ((350,), lambda: bucket("xldwc", True), True),
    ],
}

CONTACT_SAMPLES = 48


def contact_plane():
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.6)
    o = obj(bm, mat("#808080", 1.0, dirt=0, wear=False), name="contact")
    o.is_shadow_catcher = True; o.hide_render = True
    return o


def render_contact(path_, plane):
    """Only the soft sky occlusion under a floor piece, on a catcher round it (see room_post.with_shadow)."""
    suns = [bpy.data.objects[n] for n in ("Key", "Rim")]
    parts = [o for o in MODEL.objects if o.type == "MESH" and o is not plane]
    keep = scene.cycles.samples
    for o in suns: o.hide_render = True
    for o in parts: o.is_holdout = True
    plane.hide_render = False; scene.cycles.samples = CONTACT_SAMPLES
    try: render(path_)
    finally:
        for o in suns: o.hide_render = False
        for o in parts: o.is_holdout = False
        plane.hide_render = True; scene.cycles.samples = keep


def build_root(fn):
    clear(); WEAR.update(rust=0.0, dirt=0.05, scorch=0.0)
    start = len(BUILT); yaw = fn() or 0
    root = bpy.data.objects.new("root", None); MODEL.objects.link(root)
    for ob in BUILT[start:]: ob.parent = root
    root.rotation_euler = (0, 0, math.radians(yaw))
    return root, BUILT[start:]


def render_cells(sheet, only=None):
    tile_camera(); out = os.path.join(_OUT_DIR, sheet); os.makedirs(out, exist_ok=True)
    for idxs, fn, floor in CELLS[sheet]:
        if only and not set(idxs) & set(only): continue
        ICON[0] = False
        build_root(fn)
        plane = contact_plane() if floor else None
        first = os.path.join(out, "%d.png" % idxs[0])
        render(first)
        if plane: render_contact(os.path.join(out, "%d_s.png" % idxs[0]), plane)
        for i in idxs[1:]:                                           # identical sprites share one render
            for suf in ("", "_s") if plane else ("",):
                src = os.path.join(out, "%d%s.png" % (idxs[0], suf))
                open(os.path.join(out, "%d%s.png" % (i, suf)), "wb").write(open(src, "rb").read())
        log("cell", sheet, idxs); print("cell", sheet, idxs, flush=True)


# ------------------------------------------------------------------ icon-only models
def jug(cap, body, label_col, art):
    """A plastic nutrient jug with a handle, screw cap and a wrap label with a leaf or flower mark."""
    p = P(); bm_ = mat(body, 0.4, var=0.05, dirt=0.15)
    box((0.15, 0.1, 0.2), (0, 0, 0.1), bm_, bevel=0.03)
    cyl(0.04, 0.05, (0.0, 0, 0.215), bm_, segs=20, r2=0.03)
    cyl(0.032, 0.035, (0, 0, 0.255), mat(cap, 0.45, dirt=0.1), segs=20)
    for i in range(12): box((0.003, 0.004, 0.03), (math.cos(i * 0.52) * 0.033, math.sin(i * 0.52) * 0.033, 0.255), mat(cap, 0.45), rot=(0, 0, i * 30), bevel=0)
    path([(0.05, 0.0, 0.2), (0.1, 0.0, 0.18), (0.11, 0, 0.12), (0.075, 0, 0.09)], 0.016, bm_, segs=8)
    box((0.152, 0.004, 0.12), (0, -0.051, 0.095), mat(label_col, 0.5, dirt=0.1), bevel=0.002)
    box((0.004, 0.102, 0.12), (0.076, 0, 0.095), mat(label_col, 0.5, dirt=0.1), bevel=0.002)
    box((0.12, 0.002, 0.024), (0, -0.054, 0.14), mat("#f2efe6", 0.5, dirt=0, wear=False), bevel=0)
    art(Vector((0, -0.055, 0.092)))
    print_lines(-0.05, 0.05, 0.05, -0.054, 2, 0.012, "#f2efe6")


def leaf_mark(c, col="#4f9a3a", s=1.0, axis="Y"):
    """A little seven-finger leaf printed on a face facing -Y."""
    m = mat(col, 0.5, dirt=0, wear=False)
    for k in range(-3, 4):
        a = k * 26; L = (0.05 - abs(k) * 0.008) * s
        box((0.009 * s, 0.002, L), Vector(c) + Vector((math.sin(math.radians(a)) * L / 2, 0, math.cos(math.radians(a)) * L / 2 - 0.012 * s)),
            m, rot=(0, a, 0), bevel=0)
    box((0.003 * s, 0.002, 0.02 * s), Vector(c) + Vector((0, 0, -0.022 * s)), m, bevel=0)


def flower_mark(c, col="#e05a8a"):
    m = mat(col, 0.5, dirt=0, wear=False)
    for k in range(6):
        a = math.radians(60 * k)
        ball(0.012, Vector(c) + Vector((math.cos(a) * 0.016, 0, math.sin(a) * 0.016)), m, scale=(1, 0.2, 1), segs=8)
    ball(0.009, Vector(c) + Vector((0, -0.002, 0)), mat("#f2c44c", 0.5, dirt=0, wear=False), scale=(1, 0.2, 1), segs=8)


def book(cover, accent, emblem, thick=0.03, title_col="#f2efe6"):
    """A closed manual lying flat: hard cover, page block and spine, a title band and cover art."""
    box((0.2, 0.28, thick), (0, 0, thick / 2), mat(cover, 0.7, var=0.15, dirt=0.25), bevel=0.006)
    box((0.19, 0.272, thick - 0.008), (0.006, 0, thick / 2), mat("#e8e2cf", 0.8, dirt=0.15))
    for k in range(4): box((0.19, 0.0015, 0.0015), (0.006, -0.137, 0.008 + k * (thick - 0.016) / 3), mat("#c9c2ac", 0.8, dirt=0), bevel=0)
    box((0.014, 0.28, thick + 0.004), (-0.098, 0, thick / 2), mat(cover, 0.6, dirt=0.2), bevel=0.004)
    box((0.2, 0.28, 0.005), (0, 0, thick + 0.0), mat(cover, 0.7, var=0.15, dirt=0.25), bevel=0.003)
    z = thick + 0.003
    box((0.15, 0.05, 0.002), (0.01, -0.09, z), mat(accent, 0.6, dirt=0.05), bevel=0)
    for i in range(2): box((0.1 - i * 0.03, 0.008, 0.002), (0.0 - i * 0.015, -0.082 - i * 0.016, z + 0.001), mat(title_col, 0.6, dirt=0, wear=False), bevel=0)
    box((0.12, 0.012, 0.002), (0.01, 0.115, z), mat(title_col, 0.6, dirt=0, wear=False), bevel=0)
    emblem(z)


def leaf_flat(c, col="#4f9a3a", s=1.0, z=0.0):
    m = mat(col, 0.5, dirt=0, wear=False)
    for k in range(-3, 4):
        a = math.radians(k * 26); L = (0.06 - abs(k) * 0.01) * s
        box((0.011 * s, L, 0.002), (c[0] + math.sin(a) * L / 2, c[1] + math.cos(a) * L / 2 - 0.012 * s, z), m,
            rot=(0, 0, -math.degrees(a)), bevel=0)
    box((0.003, 0.03 * s, 0.002), (c[0], c[1] - 0.03 * s, z), m, bevel=0)


def m_magazine(kind):
    if kind == "hydro":
        book("#2f6fb0", "#e8e2cf", lambda z: (cyl(0.045, 0.002, (0.01, 0.03, z), mat("#7cc6e8", 0.5, dirt=0), segs=28),
                                              leaf_flat((0.01, 0.035), "#3d8a3a", 0.8, z + 0.002),
                                              [box((0.12, 0.004, 0.002), (0.01, -0.025 + 0.012 * i - 0.0, z + 0.0005), mat("#2a5a90", 0.5, dirt=0), bevel=0) for i in ()]),
             thick=0.012)
    elif kind == "env":
        book("#d0a52e", "#7a3a8a", lambda z: (cyl(0.045, 0.002, (0.01, 0.03, z), mat("#f0d6b8", 0.5, dirt=0), segs=28),
                                              cyl(0.025, 0.002, (0.01, 0.03, z + 0.001), mat("#e0507a", 0.5, dirt=0), segs=24),
                                              leaf_flat((0.01, 0.035), "#3d7a32", 0.55, z + 0.003)), thick=0.012)
    else:
        book("#4a2f7a", "#e8e2cf", lambda z: (box((0.13, 0.13, 0.002), (0.01, 0.03, z), mat("#2f7a46", 0.5, dirt=0), bevel=0),
                                              leaf_flat((0.01, 0.035), "#a8d86a", 0.9, z + 0.002)), thick=0.035, title_col="#e8e2cf")


def m_timer(kind):
    """The plug-in timers come from room_render.py's plug_timer (kept in step by gear_post)."""
    raise RuntimeError("timer icons are rendered by room_render.py")


def m_rockwool():
    rockwool((0, 0, 0.05), 0.1, 0.1, 0.0)
    box((0.1, 0.1, 0.003), (0, 0, 0.0015), mat("#e8e2cf", 0.6, alpha=0.6, dirt=0, wear=False), bevel=0)


def m_pebbles(fired):
    """A sack of clay pebbles, top folded open, a heap of them in front."""
    rnd = random.Random(9 if fired else 10)
    sack = mat("#b08c5f", 0.9, var=0.2, dirt=0.3)
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=4)
    for v in bm.verts:
        x, y, z = v.co
        v.co.x = x * 0.2 * (1 + 0.12 * (0.5 - abs(z)) * 2); v.co.y = y * 0.13 * (1 + 0.15 * (0.5 - abs(z)) * 2); v.co.z = (z + 0.5) * 0.28
    obj(bm, sack, smooth=True)
    pebbles(0.09, 0.28, rnd, 60, fired, (0.012, 0.018))
    box((0.16, 0.003, 0.09), (0, -0.075, 0.13), mat("#e8e2cf", 0.6, dirt=0.15), bevel=0)
    for i in range(5):
        ball(0.012, (-0.035 + i * 0.018, -0.0765, 0.15), bumpy("#a85a33" if fired else "#968070", 0.85, 0.3, 0.05, 140, 0.3), scale=(1, 0.3, 1), segs=8)
    print_lines(-0.06, 0.06, 0.115, -0.078, 3, 0.012)
    for _ in range(14):
        a = rnd.uniform(-1, 1); d = rnd.uniform(0.12, 0.2)
        ball(rnd.uniform(0.012, 0.016), (0.12 + a * 0.05, -d, 0.012), bumpy("#a85a33" if fired else "#968070", 0.85, 0.3, 0.05, 140, 0.3), segs=8)


def m_soil():
    """A plastic potting-soil sack, open at the top with soil showing."""
    rnd = random.Random(11)
    sack = mat("#3f6a3a", 0.45, var=0.1, dirt=0.25)
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=5)
    for v in bm.verts:
        x, y, z = v.co; s = 1 + 0.25 * (0.25 - (z) ** 2)
        v.co.x = x * 0.22 * s; v.co.y = y * 0.12 * s; v.co.z = (z + 0.5) * 0.32
    obj(bm, sack, smooth=True)
    soil_top(0.1, 0.31, rnd, 20)
    box((0.18, 0.003, 0.11), (0, -0.08, 0.15), mat("#e8d9a8", 0.6, dirt=0.1), bevel=0)
    leaf_mark((0.05, -0.083, 0.16), "#3d7a32", 0.8)
    print_lines(-0.07, 0.0, 0.18, -0.083, 3, 0.016, "#5a3c22")
    box((0.18, 0.003, 0.02), (0, -0.08, 0.06), mat("#7a4a2a", 0.6, dirt=0), bevel=0)


def m_gel():
    """A small tub of rooting gel with a green screw lid and a label."""
    cyl(0.05, 0.11, (0, 0, 0.055), mat("#e8e4d8", 0.4, dirt=0.1), segs=28)
    cyl(0.052, 0.03, (0, 0, 0.125), mat("#3f8a3e", 0.45, dirt=0.1), segs=28)
    for i in range(24): box((0.003, 0.004, 0.026), (math.cos(i * 0.26) * 0.052, math.sin(i * 0.26) * 0.052, 0.125), mat("#3f8a3e", 0.45), rot=(0, 0, i * 15), bevel=0)
    cyl(0.0505, 0.06, (0, 0, 0.055), mat("#d8a43a", 0.5, dirt=0.05), segs=28, caps=False)
    leaf_mark((0.0, -0.052, 0.06), "#2f6a2a", 0.6)


def m_jar(buds=True):
    """A mason jar: clear glass, a brass band lid, buds inside."""
    p = P(); rnd = random.Random(12)
    glass = mat("#bcd2d0", 0.05, alpha=0.32, dirt=0, wear=False)
    cyl(0.07, 0.17, (0, 0, 0.085), glass, segs=36)
    cyl(0.055, 0.02, (0, 0, 0.18), glass, segs=36)
    cyl(0.058, 0.022, (0, 0, 0.198), mat("#b9a06a", 0.35, 0.8, dirt=0.1), segs=36)
    cyl(0.05, 0.004, (0, 0, 0.21), mat("#c9c3ae", 0.35, 0.6, dirt=0.1), segs=30)
    if buds:
        bud = bumpy("#6c8a3e", 0.7, 0.35, 0.1, 60, 0.6)
        for _ in range(12):
            a = rnd.uniform(0, 6.28); d = rnd.uniform(0, 0.04)
            ball(rnd.uniform(0.022, 0.03), (math.cos(a) * d, math.sin(a) * d, rnd.uniform(0.03, 0.13)), bud, scale=(1, 1, 1.3), segs=10)
            ball(0.004, (math.cos(a) * d + 0.01, math.sin(a) * d - 0.02, rnd.uniform(0.04, 0.12)), mat("#c27a3a", 0.6, dirt=0), segs=6)
    label((0.07, 0.002, 0.04), (0, -0.0705, 0.07), "#e8e2cf")
    print_lines(-0.025, 0.025, 0.08, -0.0715, 3, 0.01)


def m_dome():
    """A propagation tray with a clear vented dome and rockwool plugs."""
    p = P()
    box((0.42, 0.24, 0.05), (0, 0, 0.025), mat("#232426", 0.5, dirt=0.2), bevel=0.01)
    for i in range(6):
        for j in range(3):
            rockwool((-0.17 + i * 0.068, -0.07 + j * 0.07, 0.05), 0.045, 0.03, 0.0, hole=True)
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3)
    for v in bm.verts:
        x, y, z = v.co; z = z + 0.5
        k = 1 - 0.18 * z ** 2
        v.co.x, v.co.y, v.co.z = x * 0.43 * k, y * 0.25 * k, 0.05 + z * 0.13
    o = obj(bm, mat("#d6e4e6", 0.05, alpha=0.28, dirt=0, wear=False), smooth=True)
    for x in (-0.1, 0.1):
        box((0.06, 0.03, 0.012), (x, 0, 0.185), mat("#bfc9ca", 0.3, alpha=0.6, dirt=0), bevel=0.004)
        for k in range(3): box((0.04, 0.003, 0.004), (x, -0.008 + k * 0.008, 0.192), mat("#2b2c2e", 0.5, dirt=0), bevel=0)
    sprout = mat("#6fae4a", 0.6, dirt=0)
    for i in range(0, 6, 2):
        for j in range(3):
            c = Vector((-0.17 + i * 0.068, -0.07 + j * 0.07, 0.07))
            tube(c, c + Vector((0, 0, 0.025)), 0.002, sprout, 5)
            for s in (-1, 1): ball(0.008, c + Vector((s * 0.008, 0, 0.026)), sprout, scale=(1, 0.5, 0.25), segs=6)


def m_papers():
    """A booklet of rolling papers: card cover with a fold and a paper tongue sticking out."""
    box((0.12, 0.07, 0.016), (0, 0, 0.008), mat("#e8e0c8", 0.6, dirt=0.15), bevel=0.003)
    box((0.12, 0.07, 0.004), (0, 0, 0.017), mat("#c23a2e", 0.55, dirt=0.1), bevel=0.0015)
    box((0.11, 0.04, 0.0015), (0.0, -0.045, 0.012), mat("#f4f1e8", 0.6, dirt=0, wear=False), bevel=0)
    box((0.06, 0.03, 0.001), (0.0, 0.0, 0.0195), mat("#f2c44c", 0.5, dirt=0, wear=False), bevel=0)
    leaf_flat((0.0, 0.005), "#e8e0c8", 0.35, 0.0205)


def m_pipe():
    """A briar pipe: bowl with a charred rim, a shank and a black stem."""
    briar = mat("#7a4a2a", 0.4, var=0.2, dirt=0.1)
    cyl(0.04, 0.09, (0.1, 0, 0.065), briar, segs=28, r2=0.045)
    cyl(0.03, 0.004, (0.1, 0, 0.11), mat("#1a1512", 0.9, dirt=0), segs=24)
    torus(0.04, 0.006, (0.1, 0, 0.108), mat("#3a2414", 0.6), seg=28, rseg=6)
    ball(0.042, (0.1, 0, 0.03), briar, scale=(1, 1, 0.7))
    tube((0.06, 0, 0.03), (-0.04, 0, 0.04), 0.017, briar, 16, r2=0.014)
    torus(0.0145, 0.003, (-0.04, 0, 0.04), mat("#b9a06a", 0.35, 0.8, dirt=0), axis="X", seg=20, rseg=5)
    tube((-0.04, 0, 0.04), (-0.17, 0, 0.055), 0.012, mat("#1d1d1f", 0.3), 14, r2=0.008)
    box((0.03, 0.02, 0.006), (-0.175, 0, 0.056), mat("#1d1d1f", 0.3), bevel=0.002)


def m_leaf(col, curl=0.0):
    """A big seven-finger fan leaf lying flat, its fingers curled a little when dried."""
    m = mat(col, 0.65, var=0.2, dirt=0.05)
    HEAD.append(HEAD[-1] @ M((0, 0, 0), (0, 0, 45)) @ M((0, 0, 0), (62, 0, 0)))      # stood up, facing the viewer
    for k in range(-3, 4):
        a = math.radians(k * 27); L = 0.3 - abs(k) * 0.05
        bm = blade_bm(L, 0.02, 0.0, 0.003, 0, pitch=0, curve=curl)
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1)
        for v in bm.verts:                                         # leaflet outline: wide in the middle, serrated
            t = v.co.z / L; w = math.sin(math.pi * min(1, t) ** 0.8) * (0.045 - abs(k) * 0.004)
            if abs(v.co.x) > 1e-5: v.co.x = math.copysign(w * (0.85 if int(t * 14) % 2 else 1.0), v.co.x)
            v.co.y += curl * (t ** 2) * 0.08
        obj(bm, m, M((0, -0.05, 0.004), (-90, 0, 0)) @ M((0, 0, 0), (0, math.degrees(a), 0)), smooth=True)
        tube((0, -0.05, 0.006), (math.sin(a) * L * 0.9, -0.05 + math.cos(a) * L * 0.9, 0.006), 0.0018, mat("#c9d0a0" if col == "#4f8f34" else col, 0.6, dirt=0), 4)
    tube((0, -0.05, 0.006), (0, -0.2, 0.006), 0.004, m, 6)
    HEAD.pop()


def m_blunt(half=False):
    """A blunt: a brown leaf wrap with a twisted tail; half-smoked, it is short with an ashy, charred end."""
    wrap = mat("#6a4a2a", 0.55, var=0.25, dirt=0.15)
    L = 0.16 if half else 0.32
    tube((-L / 2, 0, 0.022), (L / 2, 0, 0.022), 0.022, wrap, 20, r2=0.02)
    for i in range(7):                                             # wrap seam spiral
        x = -L / 2 + (i + 0.5) * L / 7
        torus(0.0215, 0.0016, (x, 0, 0.022), mat("#4e331c", 0.6, dirt=0), axis="X", seg=20, rseg=4, rot=(0, 90, 25))
    if half:
        cyl(0.02, 0.012, (L / 2 + 0.004, 0, 0.022), mat("#8c8a86", 0.9, dirt=0), axis="X", segs=18)
        cyl(0.019, 0.004, (L / 2 + 0.011, 0, 0.022), mat("#3a3632", 0.9, dirt=0), axis="X", segs=18)
        cyl(0.021, 0.008, (L / 2 - 0.004, 0, 0.022), mat("#2a1d14", 0.8, dirt=0), axis="X", segs=18)
    else:
        cyl(0.02, 0.006, (L / 2 + 0.002, 0, 0.022), mat("#4e3a22", 0.8, dirt=0), axis="X", segs=18)
        for k in range(5):
            ball(0.004, (L / 2 + 0.004, math.cos(k) * 0.01, 0.022 + math.sin(k) * 0.01), mat("#5d7a3a", 0.7, dirt=0), segs=6)
    tube((-L / 2, 0, 0.022), (-L / 2 - 0.03, 0, 0.022), 0.02, wrap, 16, r2=0.006)
    ball(0.006, (-L / 2 - 0.032, 0, 0.022), wrap, segs=8)


def icon_wrap(fn, *a):
    def f():
        fn(*a); return 0
    return f


ICONS = {
    "GrowLampBasic": lambda: dish_lamp("Basic"), "GrowLampPro": lambda: dish_lamp("Pro"),
    "GrowLampLargeBasic": lambda: bar_icon(False), "GrowLampLargePro": lambda: bar_icon(True),
    "GrowFloodBasic": lambda: flood_stand(False), "GrowFloodPro": lambda: flood_stand(True),
    "GrowBagSmall": lambda: grow_bag("small", True), "GrowBagLarge": lambda: grow_bag("large", True),
    "GrowBagXL": lambda: grow_bag("xl", True),
    "DWCBucket": lambda: bucket("dwc", False), "DWCBucketXL": lambda: bucket("xldwc", False),
    "RDWCSite": lambda: bucket("rdwc", False), "RDWCControl": rdwc_control,
    "FloodTable": lambda: flood_table(False, True), "FloodReservoir": flood_reservoir,
    "DryingFan": drying_fan, "DryingRack": rack_icon, "CuringBarrel": curing_barrel,
    "CuringJar": icon_wrap(m_jar), "CloningDome": icon_wrap(m_dome), "RockwoolCube": icon_wrap(m_rockwool),
    "ClayPebbles": icon_wrap(m_pebbles, True), "ClayPebblesUnfired": icon_wrap(m_pebbles, False),
    "VegNutrients": icon_wrap(jug, "#2b2c2e", "#e8e4d8", "#3f8a3e", lambda c: leaf_mark(c, "#e8f2d8", 0.8)),
    "BloomNutrients": icon_wrap(jug, "#2b2c2e", "#e8e4d8", "#8a3a9a", lambda c: flower_mark(c, "#f2b6d8")),
    "RootingGel": icon_wrap(m_gel), "RollingPapers": icon_wrap(m_papers), "SoilSack": icon_wrap(m_soil),
    "SmokingPipe": icon_wrap(m_pipe),
    "HydroMagazine": icon_wrap(m_magazine, "hydro"), "ControlledEnvMagazine": icon_wrap(m_magazine, "env"),
    "GrowersHandbook": icon_wrap(m_magazine, "handbook"),
    "FanLeaf": icon_wrap(m_leaf, "#4f8f34", 0.0), "DriedFanLeaf": icon_wrap(m_leaf, "#8a8a48", 0.25),
    "CuredFanLeaf": icon_wrap(m_leaf, "#7a5a32", 0.15),
    "Blunt": icon_wrap(m_blunt, False), "HalfSmokedBlunt": icon_wrap(m_blunt, True),
}
ICON_YAW = {"GrowLampLargeBasic": 0, "GrowLampLargePro": 0}


def render_icons(names):
    out = os.path.join(_OUT_DIR, "icons"); os.makedirs(out, exist_ok=True)
    for name in names:
        ICON[0] = True
        root, parts = build_root(ICONS[name])
        bpy.context.view_layer.update()
        icon_camera([o for o in parts if o.type == "MESH"], 256)
        render(os.path.join(out, "Item_%s.png" % name)); log("icon", name); print("icon", name, flush=True)
    ICON[0] = False


for job in _JOBS:
    t0 = time.time()
    if job == "all":
        for sh in CELLS: render_cells(sh)
        render_icons(list(ICONS))
    elif job in ("plants", "hydro"): render_cells(job + "_01")
    elif job == "icons": render_icons(list(ICONS))
    elif job.startswith("icon:"): render_icons(job[5:].split(","))
    elif ":" in job:
        sh, idx = job.split(":"); render_cells(sh, [int(i) for i in idx.split(",")])
    else: raise SystemExit("unknown job %r" % job)
    log("job", job, "took %.0fs" % (time.time() - t0))
log("finished")
