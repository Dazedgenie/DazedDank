"""Dazed Dank grow-room equipment (dazeddank_rooms_01) and their item icons, rendered in DazedPower's art style.

It loads dz_render.py (a copy of DazedPower/tools/blender/dz_render.py) from its own folder as a library, so the
camera (2:1 ortho tile camera), sky fill + key sun + rim sun, worn materials and bevelled geometry are exactly
DazedPower's. Run with Blender 4.2+ or the bpy module:

    blender -b --factory-startup -P tools/blender/room_render.py -- <out dir> [all|cells|icons|<set> ...]
    python  tools/blender/room_render.py -- <out dir> all            (with `pip install bpy`)

Raw 256x512 cells land in <out>/cells/<sprite index>.png (floor units also get <index>_s.png, a contact-shadow pass)
and 256x256 icon renders in <out>/icons/Item_<Name>.png. Then grade, shrink and install them with room_post.py.

Sheet layout (must match dazeddank_rooms_01.tiles and CannabisConfig.lua; nothing here changes it):
    0-3   Grow Room Panel        S E N W     wall      4-7  blackout curtains: door N, door W, window N, window W
    8-11  exhaust fan            S E N W     wall      12-15 intake fan          S E N W   wall
    16    heater (oil radiator)  floor                 17   dehumidifier         floor    18 humidifier   floor
    20-23 wall heater            S E N W     wall      24-27 wall dehumidifier   S E N W   wall
    28-31 wall humidifier        S E N W     wall      32-35 wall AC             S E N W   wall
    36-39 circulation fan        S E N W     wall      40   drip irrigation tank floor
Facing S hangs on the north wall (+Y here), E on the west wall, N on the south wall and W on the east wall, so the
N and W cells show the back of the unit, as the game draws a unit hung on a wall in front of the camera.
Every model is built facing S: its back on the wall plane y = +0.5, its front toward -Y.
"""
import os, sys, math, random, time

_ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
_OUT_DIR = os.path.abspath(_ARGS[0] if _ARGS else "room_render_out")
_JOBS = _ARGS[1:] or ["all"]
_HERE = os.path.dirname(os.path.abspath(__file__))
DZ_LIBRARY = True                                              # dz_render.py runs no job of its own
sys.argv = [sys.argv[0], "--", _OUT_DIR]
__file__ = os.path.join(_HERE, "dz_render.py")
exec(compile(open(__file__).read(), __file__, "exec"))         # defines mat, box, cyl, tube, P(), tile_camera, ...
__file__ = os.path.join(_HERE, "room_render.py")
import bpy, bmesh
from mathutils import Vector, Matrix, Euler

B = 0.5                     # the wall plane a wall unit's back sits on
WALL_Z = 1.74               # centre height of the high wall units (like an overhead cupboard)
ICON = [False]              # icon renders skip the cords and conduit that run to the floor or ceiling
DANK_FACINGS = [("S", 0), ("E", 90), ("N", 180), ("W", 270)]


# ------------------------------------------------------------------ shared bits
def cord(pts, col="#1f1f21", r=0.006):
    """A power cord or hose; in icons only its first stretch is kept."""
    if ICON[0]:
        pts = pts[:2]
        a, b = Vector(pts[0]), Vector(pts[1])
        if (b - a).length > 0.12: pts = [a, a + (b - a).normalized() * 0.12]
    path(pts, r, mat(col, 0.6, dirt=0.1))


def wall_drop(x, y, z0, col="#1f1f21", r=0.006):
    """A cord from a wall unit straight down the wall to the floor, with a little slack at the bottom."""
    cord([(x, y, z0), (x, y + 0.004, z0 - 0.08), (x + 0.004, B - 0.012, z0 - 0.2), (x + 0.006, B - 0.012, 0.05),
          (x + 0.03, B - 0.03, 0.01)], col, r)


def screw(c, axis="Y", r=0.008):
    cyl(r, 0.006, c, mat("#9a9c9e", 0.35, 0.8, dirt=0.15), axis=axis, segs=10)


def slats(x0, x1, z0, z1, y, n, m, tilt=0.0, t=0.008):
    """Horizontal louvre slats across a face at depth y."""
    for i in range(n):
        z = z0 + (z1 - z0) * (i + 0.5) / n
        box((x1 - x0, t, (z1 - z0) / n * 0.55), ((x0 + x1) / 2, y, z), m, rot=(tilt, 0, 0), bevel=0.002)


def plate_with_hole(w, h, r, t, center, m, n=64):
    """A flat plate in the XZ plane (facing -Y) with a round hole through it, like a fan's venturi plate."""
    bm = bmesh.new(); fr, bk = [], []
    for i in range(n):
        a = 2 * math.pi * i / n; ca, sa = math.cos(a), math.sin(a)
        s = min((w / 2) / max(abs(ca), 1e-9), (h / 2) / max(abs(sa), 1e-9))
        for lst, y in ((fr, -t / 2), (bk, t / 2)):
            lst.append((bm.verts.new((r * ca, y, r * sa)), bm.verts.new((s * ca, y, s * sa))))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((fr[i][0], fr[i][1], fr[j][1], fr[j][0]))
        bm.faces.new((bk[j][0], bk[j][1], bk[i][1], bk[i][0]))
        bm.faces.new((fr[j][0], bk[j][0], bk[i][0], fr[i][0]))          # the bore
        bm.faces.new((fr[i][1], bk[i][1], bk[j][1], fr[j][1]))          # the outer rim
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj(bm, m, M(center))


def cloth(width, height, bottom, y_back, depth, folds, m, sway=0.0):
    """A hanging curtain: a pleated sheet, its folds deepest at the bottom, just in front of the wall."""
    bm = bmesh.new(); nx, nz = folds * 8, 10; rows = []
    for k in range(nz + 1):
        t = k / nz; z = bottom + height * t; row = []
        for i in range(nx + 1):
            u = i / nx; x = -width / 2 + width * u
            fold = 0.5 + 0.5 * math.sin(2 * math.pi * folds * u + 0.6 * math.sin(7.0 * u))
            d = depth * (0.55 + 0.45 * (1 - t))                  # folds spread a little toward the hem
            y = y_back - 0.006 - d * fold
            x += sway * (1 - t) * math.sin(3 * u)
            row.append(bm.verts.new((x, y, z)))
        rows.append(row)
    for k in range(nz):
        for i in range(nx): bm.faces.new((rows[k][i], rows[k][i + 1], rows[k + 1][i + 1], rows[k + 1][i]))
    sol = obj(bm, m, smooth=True)
    md = sol.modifiers.new("s", "SOLIDIFY"); md.thickness = 0.006
    return sol


def fan_blades(c, n, length, w0, w1, m, pitch=28, twist=-10, start=0.0, hub_r=0.035):
    """Blades radiating in the XZ plane from c (facing -Y)."""
    c = Vector(c)
    for i in range(n):
        a = start + 360.0 * i / n
        bm = blade_bm(length - hub_r, w0, w1, 0.006, twist, pitch=pitch, curve=0.02)
        obj(bm, m, Matrix.Translation(c) @ Euler((0, math.radians(a), 0)).to_matrix().to_4x4() @ M((0, 0, hub_r * 0.8)),
            smooth=True)


def guard(c, r, m, rings=(0.33, 0.62, 0.9), spokes=12, wire=0.0035, depth=0.0, rim=None):
    """A round wire guard facing -Y: concentric rings and radial wires, domed `depth` toward -Y at its centre."""
    c = Vector(c)
    for f in rings:
        dz = depth * (1 - f * f)
        torus(r * f, wire, c + Vector((0, -dz, 0)), m, axis="Y", seg=40, rseg=6)
    torus(r, wire * 1.8, c, rim or m, axis="Y", seg=48, rseg=6)
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        pts = []
        for f in (0.12, 0.5, 1.0):
            pts.append(c + Vector((math.cos(a) * r * f, -depth * (1 - f * f), math.sin(a) * r * f)))
        path(pts, wire, m, segs=6)
    cyl(r * 0.12, 0.01, c + Vector((0, -depth, 0)), m, axis="Y", segs=16)


def dial(c, r, m_face="#e9e4d4", m_knob="#2a2b2d", pointer=30):
    """A round knob facing -Y: skirt, grip and a white pointer line."""
    c = Vector(c)
    cyl(r, 0.012, c + Vector((0, 0.002, 0)), mat(m_face, 0.45, dirt=0.15), axis="Y", segs=24)
    cyl(r * 0.62, 0.03, c + Vector((0, -0.014, 0)), mat(m_knob, 0.45, 0.1, dirt=0.1), axis="Y", segs=20)
    a = math.radians(pointer)
    box((0.004, 0.004, r * 0.5), c + Vector((math.sin(a) * r * 0.3, -0.03, math.cos(a) * r * 0.3)),
        mat("#e6e6e2", 0.4, dirt=0, wear=False), rot=(0, math.degrees(a), 0), bevel=0)


def label(c, size, col="#d9d2bd", axis="Y"):
    box(size, c, mat(col, 0.7, var=0.05, dirt=0.25), bevel=0.0)


# ------------------------------------------------------------------ 0-3 grow room panel
def grow_panel():
    """A grey steel control enclosure: a hinged door with a 24-hour pin timer, a temperature/humidity dial,
    a red LED readout, pilot lamps, three toggle switches and a label plate; conduit runs up to the ceiling."""
    p = P(); z = 1.30; w, h, d = 0.34, 0.44, 0.085
    body = mat("#6e767c", 0.5, 0.35, var=0.08, dirt=0.25)
    door = mat("#7c858b", 0.45, 0.35, var=0.08, dirt=0.2)
    box((w + 0.03, 0.012, h + 0.03), (0, B - 0.006, z), body, bevel=0.0)                   # mounting flange
    box((w, d, h), (0, B - 0.012 - d / 2, z), body, bevel=0.012)                    # clear of the flange: no shared face
    d += 0.012
    fy = B - d - 0.006
    box((w - 0.03, 0.012, h - 0.03), (0, B - d, z), door, bevel=0.006)
    for zz in (z + 0.14, z - 0.14): cyl(0.008, 0.06, (-w / 2 + 0.006, B - d - 0.004, zz), p["steel"], segs=10)
    box((0.016, 0.02, 0.07), (w / 2 - 0.035, fy - 0.006, z - 0.02), mat("#b9bcbf", 0.3, 0.8, dirt=0.1), bevel=0.004)
    # 24-hour pin timer: cream dial, a ring of trippers (green pushed in = lights on), centre knob and arrow.
    tc = Vector((-0.06, fy, z + 0.09))
    cyl(0.072, 0.012, tc + Vector((0, 0.002, 0)), mat("#3a3c3f", 0.5, 0.2), axis="Y", segs=40)
    cyl(0.062, 0.012, tc + Vector((0, -0.006, 0)), mat("#e7e0cc", 0.5, dirt=0.15), axis="Y", segs=40)
    for i in range(24):
        a = 2 * math.pi * i / 24; on = 6 <= i < 24
        box((0.008, 0.012 if on else 0.022, 0.012), tc + Vector((math.cos(a) * 0.066, -0.01 - (0 if on else 0.006), math.sin(a) * 0.066)),
            mat("#3e8a4a" if on else "#2b2c2e", 0.5, dirt=0.05), rot=(0, -math.degrees(a), 0), bevel=0.0)
    cyl(0.018, 0.02, tc + Vector((0, -0.016, 0)), mat("#2b2c2e", 0.45), axis="Y", segs=16)
    box((0.006, 0.004, 0.04), tc + Vector((0, -0.016, 0.06)), mat("#c23a2e", 0.5, dirt=0), bevel=0)
    # temperature / humidity gauge and a red LED readout
    gauge((0.085, fy - 0.002, z + 0.12), (0, 0, 0), 0.04, 0.55, rim="#b5b8bb")
    box((0.1, 0.008, 0.035), (0.085, fy - 0.002, z + 0.035), mat("#141414", 0.4, dirt=0, wear=False), bevel=0.002)
    box((0.07, 0.004, 0.018), (0.085, fy - 0.006, z + 0.035), glow("#ff4a32", 4.0), bevel=0)
    # pilot lamps: power green, lights amber, fault red (dark)
    for x, col, lit in ((-0.1, "#6fe07a", True), (-0.05, "#f2b63c", True), (0.0, "#d84a3a", False)):
        cyl(0.013, 0.006, (x, fy, z - 0.03), mat("#2b2c2e", 0.5), axis="Y", segs=14)
        lamp((x, fy - 0.006, z - 0.03), lit, col, 0.01)
    # toggle switches on chrome bezels
    for i, x in enumerate((-0.1, -0.05, 0.0)):
        cyl(0.012, 0.006, (x, fy, z - 0.1), p["steel"], axis="Y", segs=14)
        tube((x, fy - 0.004, z - 0.1), (x, fy - 0.03, z - 0.1 + (0.012 if i != 2 else -0.012)), 0.004, mat("#c9cccf", 0.3, 0.8, dirt=0))
    label((0.075, fy - 0.001, z - 0.1), (0.09, 0.004, 0.05), "#d9d2bd")
    box((0.06, 0.003, 0.004), (0.075, fy - 0.004, z - 0.09), mat("#3a3a3a", 0.6, dirt=0), bevel=0)
    box((0.05, 0.003, 0.004), (0.075, fy - 0.004, z - 0.11), mat("#3a3a3a", 0.6, dirt=0), bevel=0)
    label((0, fy - 0.001, z - 0.175), (0.2, 0.004, 0.028), "#c9b779")
    # conduit up to the ceiling from the top, and a strap
    cyl(0.02, 0.02, (0.1, B - 0.045, z + h / 2 + 0.01), p["steel_dark"], segs=12)
    if not ICON[0]:
        tube((0.1, B - 0.045, z + h / 2 + 0.01), (0.1, B - 0.045, 2.45), 0.012, mat("#9a9fa3", 0.4, 0.5, dirt=0.2))
        box((0.04, 0.03, 0.012), (0.1, B - 0.035, 1.9), p["steel"], bevel=0.002)


# ------------------------------------------------------------------ 4-7 blackout curtains
def curtain(width, height, bottom):
    """Heavy blackout drape on a steel rod with rings, hung close in front of the opening (flush, 0.03 deep)."""
    p = P()
    fab = mat("#2c2733", 0.95, var=0.1, dirt=0.1)
    cloth(width, height, bottom, B, 0.022, max(5, round(width / 0.11)), fab)
    hem = mat("#24202a", 0.95, var=0.08, dirt=0.15)
    box((width + 0.004, 0.012, 0.02), (0, B - 0.02, bottom + 0.01), hem, bevel=0.003)
    rz = bottom + height + 0.03
    tube((-width / 2 - 0.05, B - 0.018, rz), (width / 2 + 0.05, B - 0.018, rz), 0.009, mat("#8d9196", 0.35, 0.7, dirt=0.15))
    for x in (-width / 2 - 0.05, width / 2 + 0.05):
        ball(0.014, (x, B - 0.018, rz), mat("#6b6e72", 0.35, 0.7, dirt=0.15))
        box((0.012, 0.018, 0.03), (x, B - 0.009, rz), p["steel_dark"], bevel=0.002)
    n = max(5, round(width / 0.11))
    for i in range(n + 1):
        x = -width / 2 + width * i / n
        torus(0.014, 0.0028, (x, B - 0.018, rz), mat("#9a9c9e", 0.35, 0.8, dirt=0.1), axis="X", seg=16, rseg=6)


# ------------------------------------------------------------------ 8-15 wall fans
def wall_fan(kind):
    """A square through-wall shutter fan: galvanized box frame and venturi plate, five pitched blades on a motor
    hung from three struts, and a chrome wire guard. Exhaust: galvanized with orange blades; intake: blue plate."""
    p = P(); z = WALL_Z; s = 0.46; d = 0.15
    galv = mat("#a3a7a6", 0.45, 0.6, var=0.12, dirt=0.3)
    if kind == "intake": galv = mat("#4f7395", 0.5, 0.25, var=0.08, dirt=0.25)          # intake: housing painted blue
    plate_m = galv
    blade_m = mat("#bf7434", 0.5, 0.3, var=0.08, dirt=0.15) if kind == "exhaust" else mat("#b4b8bb", 0.35, 0.7, dirt=0.15)
    for sx in (-1, 1): box((0.03, d, s), (sx * (s / 2 - 0.015), B - d / 2, z), galv, bevel=0.004)
    for sz in (-1, 1): box((s, d, 0.03), (0, B - d / 2, z + sz * (s / 2 - 0.015)), galv, bevel=0.004)
    plate_with_hole(s - 0.05, s - 0.05, 0.19, 0.012, (0, B - 0.075, z), plate_m)
    cyl(0.192, 0.05, (0, B - 0.075, z), mat("#2a2b2d", 0.6, dirt=0.3), axis="Y", segs=48, caps=False)   # orifice ring
    # motor behind the blades on three struts
    cyl(0.07, 0.07, (0, B - 0.035, z), mat("#3c3f43", 0.5, 0.4, dirt=0.25), axis="Y", segs=24)
    for a in (90, 210, 330):
        e = Vector((math.cos(math.radians(a)), 0, math.sin(math.radians(a))))
        tube(Vector((0, B - 0.03, z)) + e * 0.06, Vector((0, B - 0.03, z)) + e * 0.215, 0.007, p["steel_dark"], 8)
    cyl(0.01, 0.06, (0, B - 0.09, z), p["steel"], axis="Y", segs=10)
    fan_blades((0, B - 0.1, z), 5, 0.185, 0.07, 0.11, blade_m, pitch=30, start=12)
    cyl(0.04, 0.03, (0, B - 0.105, z), blade_m if kind == "exhaust" else p["steel_dark"], axis="Y", segs=20)
    guard((0, B - d + 0.004, z), 0.2, mat("#c3c6c8", 0.3, 0.8, dirt=0.15), depth=0.012, rim=galv)
    for sx in (-1, 1):
        for sz in (-1, 1): screw((sx * (s / 2 - 0.015), B - d - 0.001, z + sz * (s / 2 - 0.015)))
    label((-0.15, B - d - 0.001, z - s / 2 + 0.015), (0.08, 0.004, 0.018), "#d0a33a" if kind == "exhaust" else "#d7d5cc")
    wall_drop(s / 2 - 0.04, B - 0.02, z - s / 2)


# ------------------------------------------------------------------ 16-18 floor units (legacy, kept for old saves)
def oil_radiator():
    """An oil-filled column radiator: eight pressed fins, a control box with a thermostat dial and red lamp,
    two caster feet and a cord."""
    p = P(); cream = mat("#d9d3c1", 0.4, 0.15, var=0.06, dirt=0.25)
    n = 8; pitch = 0.055; x0 = -pitch * (n - 1) / 2 - 0.04
    for i in range(n):
        x = x0 + i * pitch
        box((0.04, 0.24, 0.5), (x, 0, 0.38), cream, bevel=0.018)
        box((0.042, 0.06, 0.06), (x, 0, 0.16), cream, bevel=0.01)
    for zz in (0.18, 0.6): tube((x0, 0, zz), (x0 + (n - 1) * pitch, 0, zz), 0.022, cream)
    cx = x0 + (n - 1) * pitch + 0.065
    box((0.07, 0.17, 0.2), (cx, 0, 0.48), cream, bevel=0.012)
    box((0.004, 0.13, 0.15), (cx + 0.036, 0, 0.48), mat("#bdb6a3", 0.45, dirt=0.15), bevel=0)
    cyl(0.03, 0.02, (cx + 0.045, -0.02, 0.51), mat("#2d2e30", 0.45), axis="X", segs=20)
    box((0.004, 0.004, 0.022), (cx + 0.056, -0.02, 0.52), mat("#e6e6e2", 0.4, dirt=0, wear=False), bevel=0)
    cyl(0.009, 0.006, (cx + 0.039, 0.045, 0.44), mat("#2b2c2e", 0.5), axis="X", segs=12)
    lamp((cx + 0.042, 0.045, 0.44), True, "#ff5a3a", 0.008)
    for x in (x0 + 0.02, x0 + (n - 1) * pitch - 0.02):
        box((0.035, 0.34, 0.03), (x, 0, 0.075), mat("#c9c3b1", 0.45, 0.15, dirt=0.3), bevel=0.008)
        for y in (-0.15, 0.15): ball(0.022, (x, y, 0.035), p["rubber"])
    cord([(cx, 0.06, 0.4), (cx + 0.06, 0.12, 0.2), (cx + 0.12, 0.2, 0.015), (cx + 0.2, 0.32, 0.01)])


def dehumidifier():
    """A 1990s almond plastic dehumidifier on casters: top outlet grille, humidistat dial and full-bucket lamp,
    a pull-out bucket with a handle slot, side intake slots and a cord."""
    p = P(); shell = mat("#d8d1bf", 0.45, var=0.06, dirt=0.25)
    w, dd, h = 0.38, 0.3, 0.6; z0 = 0.05
    box((w, dd, h), (0, 0, z0 + h / 2), shell, bevel=0.03)
    box((w - 0.08, dd - 0.1, 0.012), (0, 0.02, z0 + h + 0.001), mat("#4b4d50", 0.6), bevel=0.003)
    for i in range(9): box((w - 0.1, 0.008, 0.004), (0, 0.02 - 0.09 + i * 0.022, z0 + h + 0.008), mat("#2d2e30", 0.6), bevel=0)
    box((0.12, 0.05, 0.01), (0, -dd / 2 + 0.035, z0 + h + 0.003), mat("#b5ae9c", 0.5), bevel=0.003)
    dial((-0.06, -dd / 2 - 0.002, z0 + h - 0.08), 0.03)
    cyl(0.009, 0.006, (0.08, -dd / 2 - 0.002, z0 + h - 0.08), mat("#2b2c2e", 0.5), axis="Y", segs=12)
    lamp((0.08, -dd / 2 - 0.006, z0 + h - 0.08), True, "#6fe07a", 0.007)
    label((0.0, -dd / 2 - 0.001, z0 + h - 0.15), (0.2, 0.004, 0.02), "#7a8a99")
    # bucket: a seam around a slightly darker front with a handle slot
    box((w - 0.04, 0.008, 0.24), (0, -dd / 2 - 0.002, z0 + 0.16), mat("#cfc8b5", 0.45, var=0.05, dirt=0.3), bevel=0.006)
    box((0.12, 0.008, 0.025), (0, -dd / 2 - 0.006, z0 + 0.25), mat("#2d2e30", 0.6), bevel=0.004)
    for i in range(10):
        box((0.008, 0.2, 0.008), (w / 2 + 0.001, 0, z0 + 0.25 + i * 0.025), mat("#4b4d50", 0.6), bevel=0)
    for x in (-w / 2 + 0.05, w / 2 - 0.05):
        for y in (-dd / 2 + 0.05, dd / 2 - 0.05):
            cyl(0.022, 0.018, (x, y, 0.025), p["rubber"], axis="X", segs=16)
    cord([(w / 2 - 0.04, dd / 2, z0 + 0.1), (w / 2 + 0.05, dd / 2 + 0.06, 0.012), (w / 2 + 0.12, dd / 2 + 0.02, 0.008)])


def humidifier():
    """A cool-mist humidifier: round white base with a dial and lamp, a translucent blue water tank and a mist
    nozzle with a soft plume."""
    p = P(); white = mat("#e3e0d6", 0.4, var=0.05, dirt=0.25)
    cyl(0.17, 0.12, (0, 0, 0.07), white, segs=40, r2=0.155)
    cyl(0.18, 0.012, (0, 0, 0.012), mat("#bdb9ad", 0.5), segs=40)
    cyl(0.15, 0.28, (0, 0, 0.27), mat("#86b3d6", 0.12, alpha=0.6, dirt=0, var=0.04), segs=40)
    cyl(0.135, 0.2, (0, 0, 0.23), mat("#3f7fb3", 0.15, alpha=0.75, dirt=0, var=0.04), segs=36)
    cyl(0.152, 0.03, (0, 0, 0.42), white, segs=40)
    ball(0.14, (0, 0, 0.43), white, scale=(1, 1, 0.25), segs=32)
    box((0.12, 0.03, 0.02), (0, 0.06, 0.46), mat("#cfcabd", 0.45), bevel=0.008)          # carry handle
    cyl(0.03, 0.06, (0, -0.06, 0.47), white, segs=20)
    cyl(0.022, 0.012, (0, -0.06, 0.505), mat("#9fa3a6", 0.4), segs=16)
    puffs((0, -0.06, 0.5), 5, 0.03, "#eef2f4", 0.28, rise=(0.02, -0.06, 0.5), seed=4)
    dial((0.0, -0.16, 0.08), 0.026)
    lamp((0.06, -0.15, 0.1), True, "#6fe07a", 0.007)
    cord([(0.12, 0.1, 0.03), (0.2, 0.18, 0.012), (0.3, 0.22, 0.008)])


# ------------------------------------------------------------------ 20-31 high wall units
def bracket_pair(xs, z, depth, m):
    """Two angle-iron wall brackets under a unit."""
    for x in xs:
        box((0.025, depth, 0.02), (x, B - depth / 2, z), m, bevel=0.003)
        box((0.025, 0.012, 0.1), (x, B - 0.006, z + 0.04), m, bevel=0.003)
        tube((x, B - 0.01, z - 0.06), (x, B - depth + 0.02, z), 0.006, m, 6)


def wall_heater():
    """A wall-hung fan-forced heater: brick-red steel case on brackets, tilted down at the room, a louvred
    grille with glowing elements behind it, thermostat dial, rocker switch and pilot lamp."""
    p = P(); z = WALL_Z; w, h, d = 0.48, 0.3, 0.16
    red = mat("#8c3b2e", 0.5, 0.25, var=0.1, dirt=0.25)
    dark = mat("#2b2522", 0.6, 0.2, dirt=0.2)
    bracket_pair((-0.17, 0.17), z - h / 2 - 0.02, d, p["steel_dark"])
    HEAD.append(HEAD[-1] @ M((0, B, z)) @ M((0, 0, 0), (-8, 0, 0)) @ M((0, -B, -z)))
    box((w, d, h), (0, B - d / 2, z), red, bevel=0.014)
    fy = B - d
    box((0.32, 0.01, 0.22), (-0.06, fy, z), dark, bevel=0.004)
    for i in range(5): box((0.29, 0.006, 0.018), (-0.06, fy - 0.004, z - 0.074 + i * 0.037), glow("#ff7a2a", 7.0), bevel=0)
    for i in range(6): box((0.3, 0.012, 0.005), (-0.06, fy - 0.008, z - 0.093 + i * 0.037), mat("#3a302b", 0.5, 0.3, dirt=0.2), bevel=0)
    box((0.1, 0.008, 0.22), (0.17, fy - 0.002, z), mat("#7a3227", 0.5, 0.25), bevel=0.004)
    dial((0.17, fy - 0.006, z + 0.05), 0.028)
    box((0.03, 0.012, 0.022), (0.17, fy - 0.008, z - 0.03), mat("#1f1f21", 0.5), bevel=0.003)
    lamp((0.17, fy - 0.008, z - 0.075), True, "#ff5a3a", 0.007)
    for x in (-0.18, 0.18): screw((x, B - d / 2, z + h / 2 + 0.001), axis="Z", r=0.006)
    HEAD.pop()
    wall_drop(0.2, B - 0.03, z - h / 2 - 0.02)


def wall_dehumidifier():
    """A white steel wall dehumidifier: intake grille, humidistat dial, green run lamp and a level window;
    a clear drain hose and the cord run down the wall."""
    p = P(); z = WALL_Z; w, h, d = 0.5, 0.36, 0.17
    white = mat("#dcdcd6", 0.45, 0.15, var=0.06, dirt=0.25)
    box((w, d, h), (0, B - d / 2, z), white, bevel=0.016)
    fy = B - d
    box((0.4, 0.008, 0.16), (-0.02, fy, z + 0.07), mat("#34373a", 0.6), bevel=0.003)
    for i in range(8): box((0.39, 0.01, 0.011), (-0.02, fy - 0.004, z + 0.0 + i * 0.02), white, rot=(-20, 0, 0), bevel=0.002)
    dial((-0.14, fy - 0.004, z - 0.09), 0.028)
    box((0.1, 0.006, 0.05), (0.02, fy - 0.002, z - 0.09), mat("#2c3a44", 0.2, dirt=0), bevel=0.003)
    box((0.09, 0.004, 0.022), (0.02, fy - 0.005, z - 0.1), mat("#4f8ec2", 0.2, dirt=0), bevel=0)
    cyl(0.009, 0.006, (0.15, fy - 0.002, z - 0.09), mat("#2b2c2e", 0.5), axis="Y", segs=12)
    lamp((0.15, fy - 0.006, z - 0.09), True, "#6fe07a", 0.007)
    label((0.15, fy - 0.001, z - 0.14), (0.08, 0.004, 0.018), "#7a8a99")
    cyl(0.014, 0.03, (0.18, B - 0.07, z - h / 2 - 0.01), p["steel"], segs=12)
    if not ICON[0]:
        cord([(0.18, B - 0.07, z - h / 2 - 0.02), (0.185, B - 0.05, z - h / 2 - 0.15), (0.19, B - 0.02, 0.2),
              (0.2, B - 0.03, 0.03), (0.26, B - 0.1, 0.012)], "#8fa3a6", 0.008)
    wall_drop(-0.2, B - 0.02, z - h / 2)


def wall_humidifier():
    """A slate-blue wall humidifier: water feed in a copper line from below, a mist head on top with a soft
    plume, a level window, humidistat dial and lamp."""
    p = P(); z = WALL_Z; w, h, d = 0.42, 0.3, 0.16
    slate = mat("#4f6c84", 0.45, 0.2, var=0.08, dirt=0.25)
    box((w, d, h), (0, B - d / 2, z), slate, bevel=0.016)
    fy = B - d
    box((w - 0.06, 0.008, 0.06), (0, fy, z + h / 2 - 0.05), mat("#3e5568", 0.5, 0.2), bevel=0.003)
    for i in range(14): box((0.006, 0.006, 0.04), (-0.16 + i * 0.0245, fy - 0.004, z + h / 2 - 0.05), mat("#22303b", 0.6), bevel=0)
    box((0.07, 0.008, 0.14), (-0.13, fy - 0.002, z - 0.04), mat("#22303b", 0.3), bevel=0.003)
    box((0.05, 0.004, 0.09), (-0.13, fy - 0.006, z - 0.065), mat("#79b2de", 0.15, dirt=0), bevel=0)
    dial((0.03, fy - 0.004, z - 0.04), 0.03)
    cyl(0.009, 0.006, (0.13, fy - 0.002, z - 0.0), mat("#2b2c2e", 0.5), axis="Y", segs=12)
    lamp((0.13, fy - 0.006, z - 0.0), True, "#6fe07a", 0.007)
    label((0.11, fy - 0.001, z - 0.09), (0.1, 0.004, 0.02), "#d9d2bd")
    for x in (-0.09, 0.09):                                                              # mist heads
        cyl(0.028, 0.04, (x, B - 0.08, z + h / 2 + 0.02), mat("#d8dadb", 0.4), segs=18)
        cyl(0.02, 0.01, (x, B - 0.08, z + h / 2 + 0.042), mat("#2b2c2e", 0.5), segs=14)
        puffs((x, B - 0.09, z + h / 2 + 0.04), 4, 0.022, "#eef2f4", 0.24, rise=(0.0, -0.05, 0.35), seed=int(x * 100) + 7)
    cyl(0.012, 0.03, (0.15, B - 0.05, z - h / 2 - 0.01), p["brass"], segs=10)
    if not ICON[0]:
        path([(0.15, B - 0.05, z - h / 2 - 0.02), (0.15, B - 0.03, z - h / 2 - 0.1), (0.155, B - 0.012, z - h / 2 - 0.18),
              (0.155, B - 0.012, 0.0)], 0.007, p["copper"])
    wall_drop(-0.17, B - 0.02, z - h / 2)


# ------------------------------------------------------------------ 32-35 wall AC
def wall_ac():
    """A 1990s through-the-wall room air conditioner in an almond plastic front: a wall sleeve trim, a
    discharge louvre along the top, an intake grille, and a control panel with two knobs and a badge."""
    p = P(); z = 1.66; w, h = 0.64, 0.42; d = 0.235
    almond = mat("#d7cfbc", 0.45, var=0.06, dirt=0.25)
    grille = mat("#cbc3af", 0.5, var=0.06, dirt=0.3)
    box((w + 0.06, 0.02, h + 0.06), (0, B - 0.01, z), mat("#a8a395", 0.5, 0.3, dirt=0.3), bevel=0.004)  # sleeve trim
    box((w - 0.02, d - 0.03, h - 0.02), (0, B - (d - 0.03) / 2 - 0.02, z), mat("#b9b3a3", 0.5, 0.3, dirt=0.3), bevel=0.01)
    box((w, 0.05, h), (0, B - d + 0.025, z), almond, bevel=0.012)
    fy = B - d
    # discharge louvres along the top, tilted up into the room
    box((0.44, 0.012, 0.09), (-0.09, fy, z + 0.14), mat("#3a3a38", 0.6), bevel=0.003)
    slats(-0.3, 0.12, z + 0.1, z + 0.185, fy - 0.01, 5, grille, tilt=35, t=0.006)
    # intake grille: vertical bars over a dark filter
    box((0.44, 0.01, 0.2), (-0.09, fy, z - 0.06), mat("#4c4f4e", 0.8, dirt=0.2), bevel=0.003)
    for i in range(22): box((0.008, 0.012, 0.2), (-0.3 + i * 0.02, fy - 0.006, z - 0.06), grille, bevel=0.001)
    box((0.44, 0.014, 0.01), (-0.09, fy - 0.007, z + 0.045), grille, bevel=0.002)
    # control panel
    box((0.15, 0.006, 0.34), (0.225, fy - 0.001, z), mat("#c8c0ac", 0.45, dirt=0.2), bevel=0.003)
    dial((0.225, fy - 0.004, z + 0.09), 0.03, pointer=-40)
    dial((0.225, fy - 0.004, z - 0.01), 0.03, pointer=60)
    label((0.225, fy - 0.004, z - 0.1), (0.08, 0.004, 0.02), "#7d8a96")
    box((0.06, 0.004, 0.012), (0.225, fy - 0.006, z - 0.145), mat("#a07f3e", 0.4, 0.6, dirt=0), bevel=0)
    wall_drop(w / 2 - 0.03, B - 0.03, z - h / 2)


# ------------------------------------------------------------------ 36-39 circulation fan
def circ_fan():
    """A wall-mount oscillating fan: wall plate and arm, a gearbox and motor pod angled down at the room,
    three translucent blue blades in a domed chrome cage, a pull cord and a cord down the wall."""
    p = P(); z = 1.82
    body = mat("#d5d2c8", 0.4, 0.1, var=0.06, dirt=0.25)
    chrome = mat("#c3c6c8", 0.3, 0.8, dirt=0.15)
    box((0.1, 0.02, 0.15), (0, B - 0.01, z + 0.05), body, bevel=0.008)
    for zz in (z + 0.0, z + 0.1): screw((0, B - 0.021, zz), r=0.006)
    tube((0, B - 0.02, z + 0.02), (0, B - 0.07, z + 0.0), 0.016, body)
    ball(0.024, (0, B - 0.07, z), body)
    HEAD.append(HEAD[-1] @ M((0, B - 0.07, z)) @ M((0, 0, 0), (-14, 0, 0)) @ M((0, -B + 0.07, -z)))
    c = Vector((0, B - 0.1, z - 0.02))
    cyl(0.055, 0.09, c + Vector((0, 0.03, 0)), body, axis="Y", segs=24)
    ball(0.055, c + Vector((0, 0.075, 0)), body, scale=(1, 0.5, 1))
    cyl(0.008, 0.04, c + Vector((0, -0.03, 0)), p["steel"], axis="Y", segs=10)
    fh = c + Vector((0, -0.055, 0))
    guard(fh + Vector((0, 0.03, 0)), 0.19, chrome, rings=(0.4, 0.7, 0.9), spokes=16, depth=-0.02)
    fan_blades(fh, 3, 0.17, 0.08, 0.12, mat("#6f97bd", 0.2, alpha=0.8, dirt=0, var=0.05), pitch=25, start=20)
    cyl(0.035, 0.03, fh, body, axis="Y", segs=20)
    guard(fh + Vector((0, -0.03, 0)), 0.19, chrome, rings=(0.3, 0.55, 0.8), spokes=24, depth=0.04)
    cyl(0.045, 0.012, fh + Vector((0, -0.075, 0)), mat("#3c5f86", 0.4, dirt=0), axis="Y", segs=24)       # badge
    HEAD.pop()
    if not ICON[0]:
        path([(0.04, B - 0.08, z - 0.06), (0.05, B - 0.085, z - 0.3)], 0.002, mat("#d9d5c6", 0.6, dirt=0))
        ball(0.008, (0.05, B - 0.085, z - 0.305), body)
    wall_drop(-0.03, B - 0.03, z - 0.02)


# ------------------------------------------------------------------ 40 drip irrigation tank
def drip_tank():
    """A green poly reservoir with a screw lid and sight tube, a pump on a block with a plug-in pin timer,
    and black drip lines running off across the floor."""
    p = P(); green = mat("#3f5c41", 0.55, var=0.12, dirt=0.3)
    tc = Vector((-0.06, 0.06, 0))
    cyl(0.28, 0.66, tc + Vector((0, 0, 0.36)), green, segs=48)
    ball(0.28, tc + Vector((0, 0, 0.69)), green, scale=(1, 1, 0.18), segs=40)
    for zz in (0.18, 0.4, 0.58): torus(0.281, 0.01, tc + Vector((0, 0, zz)), green, seg=48)
    cyl(0.12, 0.05, tc + Vector((0, 0, 0.76)), mat("#2c3a2d", 0.55, dirt=0.2), segs=32)
    for i in range(12):
        a = 2 * math.pi * i / 12
        box((0.012, 0.012, 0.04), tc + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, 0.76)), mat("#2c3a2d", 0.55),
            rot=(0, 0, math.degrees(a)), bevel=0.002)
    box((0.04, 0.02, 0.5), tc + Vector((0.13, -0.25, 0.36)), mat("#cfd6d4", 0.15, alpha=0.65, dirt=0), rot=(0, 0, -30), bevel=0.004)
    box((0.026, 0.022, 0.3), tc + Vector((0.13, -0.25, 0.26)), mat("#4f86b5", 0.2, dirt=0), rot=(0, 0, -30), bevel=0.003)
    cyl(0.035, 0.04, tc + Vector((0, 0, 0.02)), green, segs=16)
    # pump on a block, its timer and the outlet
    box((0.16, 0.16, 0.06), (0.3, -0.16, 0.03), p["cinder"], bevel=0.006)
    cyl(0.06, 0.12, (0.3, -0.16, 0.12), mat("#2f3236", 0.5, 0.4, dirt=0.2), axis="X", segs=24)
    box((0.08, 0.1, 0.1), (0.3, -0.16, 0.24), mat("#e4e2da", 0.45, var=0.04, dirt=0.15), bevel=0.012)
    tcen = Vector((0.3, -0.212, 0.245))
    cyl(0.032, 0.008, tcen, mat("#e9e4d4", 0.45), axis="Y", segs=24)
    for i in range(16):
        a = 2 * math.pi * i / 16
        box((0.005, 0.01, 0.007), tcen + Vector((math.cos(a) * 0.034, -0.004, math.sin(a) * 0.034)),
            mat("#3e8a4a" if i % 4 == 0 else "#2b2c2e", 0.5, dirt=0), rot=(0, -math.degrees(a), 0), bevel=0)
    cyl(0.009, 0.012, tcen + Vector((0, -0.006, 0)), mat("#2b2c2e", 0.45), axis="Y", segs=12)
    path([(-0.06 + 0.2, 0.06 - 0.2, 0.06), (0.24, -0.12, 0.1)], 0.012, p["rubber"])
    hose = mat("#1d1d1f", 0.7, dirt=0.15)
    for k, (ex, ey) in enumerate(((0.47, -0.47), (0.2, -0.49), (0.49, -0.12))):
        path([(0.34, -0.2, 0.08), (0.36 + k * 0.02, -0.24 - k * 0.02, 0.012), (ex, ey, 0.008)], 0.007, hose)
        cyl(0.006, 0.03, (ex, ey, 0.015), mat("#7a2b25", 0.5), segs=8)


# ------------------------------------------------------------------ icons: plug-in mechanical timers
def plug_timer(kind):
    """A plug-in 24-hour mechanical timer: a squat plastic case with a pin dial (trippers pushed in for the on
    hours), a manual slide switch, a grounded outlet on the face and plug prongs at the back.
    light: white case, 48 trippers; flood: blue heavy-duty case, 96 fine trippers for 15-minute pump runs."""
    light = kind == "light"
    case = mat("#e6e3d9", 0.4, var=0.05, dirt=0.15) if light else mat("#3c66a0", 0.4, 0.05, var=0.06, dirt=0.15)
    w, d, h = 0.1, 0.06, 0.14
    box((w, d, h), (0, 0, h / 2), case, bevel=0.012)
    box((w - 0.012, 0.012, h - 0.012), (0, -d / 2 - 0.004, h / 2), case, bevel=0.006)
    fy = -d / 2 - 0.011
    c = Vector((0, fy, 0.087)); r = 0.036
    cyl(r + 0.006, 0.008, c + Vector((0, 0.003, 0)), mat("#2b2c2e", 0.45), axis="Y", segs=40)
    cyl(r - 0.004, 0.01, c + Vector((0, -0.003, 0)), mat("#f0ead8", 0.45, dirt=0.05), axis="Y", segs=40)
    for i in range(12):                                               # half the dial shaded for night hours
        if i >= 6:
            a = 2 * math.pi * (i + 0.5) / 12
            box((0.012, 0.003, 0.016), c + Vector((math.cos(a) * r * 0.62, -0.009, math.sin(a) * r * 0.62)),
                mat("#2f4a78", 0.5, dirt=0, wear=False), rot=(0, -math.degrees(a) + 90, 0), bevel=0)
    n = 48 if light else 96; pin_on = mat("#3e8a4a" if light else "#d24a2e", 0.5, dirt=0, wear=False)
    pin_off = mat("#2b2c2e", 0.5, dirt=0, wear=False)
    for i in range(n):
        a = 2 * math.pi * i / n
        on = (i % (n // 4)) < n // 8 if not light else 12 <= i < 36
        box((0.0045 if light else 0.0024, 0.006 if on else 0.012, 0.007), c + Vector((math.cos(a) * r, -0.004 - (0 if on else 0.004), math.sin(a) * r)),
            pin_on if on else pin_off, rot=(0, -math.degrees(a), 0), bevel=0)
    cyl(0.009, 0.012, c + Vector((0, -0.01, 0)), mat("#2b2c2e", 0.45), axis="Y", segs=16)
    box((0.004, 0.004, 0.02), c + Vector((0, -0.016, r + 0.012)), mat("#c23a2e", 0.5, dirt=0, wear=False), bevel=0)
    # outlet below the dial: two slots and a ground hole
    oc = Vector((0, fy - 0.001, 0.024))
    box((0.05, 0.006, 0.026), oc, mat("#d9d6cc" if light else "#2f4f7c", 0.45), bevel=0.004)
    for x in (-0.01, 0.01): box((0.003, 0.006, 0.011), oc + Vector((x, -0.002, 0.003)), mat("#151515", 0.8, dirt=0, wear=False), bevel=0)
    if not light: cyl(0.0035, 0.006, oc + Vector((0, -0.002, -0.009)), mat("#151515", 0.8, dirt=0, wear=False), axis="Y", segs=10)
    # manual override slide switch on the side
    box((0.004, 0.026, 0.012), (w / 2 + 0.002, -0.005, h - 0.03), mat("#2b2c2e", 0.5), bevel=0.001)
    box((0.006, 0.008, 0.01), (w / 2 + 0.004, -0.01, h - 0.03), mat("#c23a2e" if light else "#e8e4d8", 0.5, dirt=0), bevel=0.001)
    brass = mat("#b9a06a", 0.35, 0.8, dirt=0.1)
    for x in (-0.012, 0.012): box((0.003, 0.03, 0.012), (x, d / 2 + 0.015, h / 2 - 0.01), brass, bevel=0)
    if not light: cyl(0.004, 0.03, (0, d / 2 + 0.015, h / 2 - 0.03), brass, axis="Y", segs=10)


# ------------------------------------------------------------------ jobs
# first sprite index, builder, the facings rendered (consecutive indices), floor unit (gets a contact shadow)
SETS = {
    "panel": (0, grow_panel, ["S", "E", "N", "W"], False),
    "curtain_door": (4, lambda: curtain(0.78, 2.05, 0.0), ["S", "E"], False),
    "curtain_window": (6, lambda: curtain(0.62, 0.78, 0.95), ["S", "E"], False),
    "exhaust": (8, lambda: wall_fan("exhaust"), ["S", "E", "N", "W"], False),
    "intake": (12, lambda: wall_fan("intake"), ["S", "E", "N", "W"], False),
    "heater": (16, oil_radiator, ["S"], True),
    "dehumidifier": (17, dehumidifier, ["S"], True),
    "humidifier": (18, humidifier, ["S"], True),
    "wall_heater": (20, wall_heater, ["S", "E", "N", "W"], False),
    "wall_dehumidifier": (24, wall_dehumidifier, ["S", "E", "N", "W"], False),
    "wall_humidifier": (28, wall_humidifier, ["S", "E", "N", "W"], False),
    "wall_ac": (32, wall_ac, ["S", "E", "N", "W"], False),
    "circ_fan": (36, circ_fan, ["S", "E", "N", "W"], False),
    "drip_tank": (40, drip_tank, ["S"], True),
}
FLOOR_YAW = {"heater": 0, "dehumidifier": 0, "humidifier": 0, "drip_tank": 0}
ICONS = {
    "FloodTimer": lambda: plug_timer("flood"),
    "LightTimer": lambda: plug_timer("light"),
    "GrowRoomPanel": grow_panel,
    "Heater": wall_heater,                 # the Heater item places the wall heater (sprite 20)
    "Humidifier": wall_humidifier,         # the Humidifier item places the wall humidifier (sprite 28)
    "Dehumidifier": wall_dehumidifier,     # the Dehumidifier item places the wall dehumidifier (sprite 24)
    "ExhaustFan": lambda: wall_fan("exhaust"),
    "IntakeFan": lambda: wall_fan("intake"),
    "WallAC": wall_ac,
    "CirculationFan": circ_fan,
    "DripTank": drip_tank,
    "BlackoutCurtain": lambda: curtain(0.62, 0.78, 0.95),
}
CONTACT_SAMPLES = 48


def contact_plane():
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    o = obj(bm, mat("#808080", 1.0, dirt=0, wear=False), name="contact")
    o.is_shadow_catcher = True; o.hide_render = True
    return o


def render_contact(path, plane):
    """Only the soft sky occlusion under a floor unit, on a catcher the size of its square (see room_post.py)."""
    suns = [bpy.data.objects[n] for n in ("Key", "Rim")]
    parts = [o for o in MODEL.objects if o.type == "MESH" and o is not plane]
    keep = scene.cycles.samples
    for o in suns: o.hide_render = True
    for o in parts: o.is_holdout = True
    plane.hide_render = False; scene.cycles.samples = CONTACT_SAMPLES
    try: render(path)
    finally:
        for o in suns: o.hide_render = False
        for o in parts: o.is_holdout = False
        plane.hide_render = True; scene.cycles.samples = keep


def build_root(fn):
    clear(); WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
    start = len(BUILT); fn()
    root = bpy.data.objects.new("root", None); MODEL.objects.link(root)
    for ob in BUILT[start:]: ob.parent = root
    return root, BUILT[start:]


def render_cells(names):
    tile_camera(); out = os.path.join(_OUT_DIR, "cells"); os.makedirs(out, exist_ok=True)
    yaw = dict(DANK_FACINGS)
    for name in names:
        first, fn, facings, floor = SETS[name]
        ICON[0] = False
        root, parts = build_root(fn)
        plane = contact_plane() if floor else None
        for k, f in enumerate(facings):
            root.rotation_euler = (0, 0, math.radians(yaw[f] + FLOOR_YAW.get(name, 0)))
            idx = first + k
            render(os.path.join(out, "%d.png" % idx))
            if plane: render_contact(os.path.join(out, "%d_s.png" % idx), plane)
        log("room", name, first, facings)


def render_icons(names):
    out = os.path.join(_OUT_DIR, "icons"); os.makedirs(out, exist_ok=True)
    for name in names:
        ICON[0] = True
        root, parts = build_root(ICONS[name])
        bpy.context.view_layer.update()
        icon_camera([o for o in parts if o.type == "MESH"], 256)
        render(os.path.join(out, "Item_%s.png" % name)); log("icon", name)
    ICON[0] = False


for job in _JOBS:
    t0 = time.time()
    if job == "all": render_cells(list(SETS)); render_icons(list(ICONS))
    elif job == "cells": render_cells(list(SETS))
    elif job == "icons": render_icons(list(ICONS))
    elif job.startswith("icon:"): render_icons(job[5:].split(","))
    elif job == "align": render_align()
    elif job in SETS: render_cells([job])
    else: raise SystemExit("unknown job %r" % job)
    log("job", job, "took %.0fs" % (time.time() - t0))
log("finished")
