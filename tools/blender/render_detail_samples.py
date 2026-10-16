"""Dank grow gear rebuilt on Dazed Power's rig (dz_render.py): sample renders for a style check.
    python3 render_detail_samples.py <out dir> [name ...]
Each model sits on one floor tile, front toward -Y, and renders to <out>/<name>.png at 256x512 (2x a game cell).
"""
import os, sys, math, random
DZ_LIBRARY = True
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "out_samples")
ONLY = sys.argv[2:]
sys.argv = [sys.argv[0], "--", OUT_DIR]
exec(open(os.path.join(HERE, "dz_render.py")).read(), globals())

import bmesh
from mathutils import Vector

scene.cycles.samples = 80
LAMP_Z = 1.85                      # hanging height that matches the old lamp sprites
CEIL_Z = 2.5


# ------------------------------------------------------------------ small shared parts
def ratchet_hanger(x, y, z0, z1, p):
    """Rope ratchet hanger: rope up to the ceiling with the ratchet body near the lamp."""
    rope = mat("#2a2b2d", 0.8, dirt=0.1)
    tube((x, y, z0), (x, y, z1), 0.004, rope, 6)
    box((0.028, 0.012, 0.05), (x, y, z0 + 0.14), mat("#1d1e20", 0.55, dirt=0.1), bevel=0.004)
    torus(0.012, 0.003, (x, y, z0 + 0.012), p["steel"], axis="Y", seg=14, rseg=5)


def cord(pts, p):
    path(pts, 0.006, p["wire_k"], segs=8)


def screws(pts, p, r=0.006, axis="Y"):
    for c in pts: cyl(r, 0.004, c, p["steel"], axis=axis, segs=10)


def label(size, loc, col="#d8d2bd", rot=(0, 0, 0)):
    box(size, loc, mat(col, 0.7, var=0.08, dirt=0.25), rot=rot, bevel=0.0005)


# ------------------------------------------------------------------ hanging lamps
def build_dish_pro():
    """Pro dish lamp: hammered reflector, ballast on top, warm HPS bulb under it."""
    p = P(); z = LAMP_Z
    refl = mat("#b9bcc0", 0.28, 0.85, var=0.18, dirt=0.25)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=32, radius1=0.3, radius2=0.1, depth=0.16)
    for v in bm.verts:                                   # hammered dimples
        n = random.Random(int(v.co.x * 997 + v.co.y * 131)).uniform(-0.006, 0.006)
        v.co.x *= 1 + n; v.co.y *= 1 + n
    obj(bm, refl, M((0, 0, z + 0.08)), smooth=True)
    torus(0.3, 0.008, (0, 0, z), refl, seg=40, rseg=6)                # rolled rim
    cyl(0.1, 0.03, (0, 0, z + 0.175), p["steel_dark"])
    # ballast with fins and a sticker
    box((0.2, 0.13, 0.08), (0, 0, z + 0.23), mat("#2e3034", 0.5, 0.4, dirt=0.25), bevel=0.008)
    for i in range(7): box((0.004, 0.13, 0.025), (-0.075 + i * 0.025, 0, z + 0.282), p["alu"], bevel=0.001)
    label((0.08, 0.002, 0.035), (0.04, -0.066, 0.23 + z), "#d4a23a")
    lamp((-0.07, -0.066, z + 0.24), True, "#ff7a2a", r=0.006)
    # bulb glowing under the reflector
    ball(0.045, (0, 0, z + 0.06), glow("#ffd890", 16), scale=(1, 1, 1.6))
    cyl(0.03, 0.04, (0, 0, z + 0.14), mat("#d9d4c4", 0.6))
    for a in (45, 225):
        ax, ay = math.cos(math.radians(a)) * 0.08, math.sin(math.radians(a)) * 0.08
        ratchet_hanger(ax, ay, z + 0.27, CEIL_Z, p)
    cord([(0.1, 0, z + 0.23), (0.17, 0.05, z + 0.3), (0.2, 0.1, CEIL_Z)], p)


def build_bar_pro():
    """Large Pro LED bar: finned aluminium body, two warm strips, driver box, ratchet hangers."""
    p = P(); z = 1.5
    body = mat("#3a3c41", 0.4, 0.6, dirt=0.2)
    L = 1.05
    box((L, 0.1, 0.04), (0, 0, z), body, bevel=0.008)
    for i in range(10):
        box((L - 0.04, 0.006, 0.03), (0, -0.045 + i * 0.01, z + 0.035), p["alu"], bevel=0.001)
    for y in (-0.025, 0.025):
        box((L - 0.06, 0.03, 0.006), (0, y, z - 0.022), glow("#ffe2a0", 14), bevel=0.001)
    for y in (-0.052, 0.052):
        box((L - 0.04, 0.004, 0.012), (0, y, z - 0.012), glow("#ffd27a", 6), bevel=0.0005)
    for x in (-L / 2, L / 2):
        box((0.02, 0.11, 0.05), (x, 0, z), p["plastic"], bevel=0.004)
        screws([(x - 0.011 * (1 if x < 0 else -1), -0.03, z), (x - 0.011 * (1 if x < 0 else -1), 0.03, z)], p, 0.004, "X")
    box((0.22, 0.09, 0.05), (0.1, 0, z + 0.075), mat("#24262a", 0.5, 0.3, dirt=0.2), bevel=0.006)
    label((0.07, 0.002, 0.025), (0.12, -0.046, z + 0.075), "#c9c3ae")
    lamp((0.03, -0.046, z + 0.085), True, "#57d36a", r=0.005)
    for x in (-0.42, 0.42):
        ratchet_hanger(x, 0, z + 0.04, CEIL_Z, p)
    cord([(0.21, 0, z + 0.08), (0.3, 0.04, z + 0.2), (0.33, 0.06, CEIL_Z)], p)
    return 90                     # the bar runs along the tile like the old sprite


def build_flood_pro():
    """Pro flood stand: tripod, T-bar, two finned flood heads angled down."""
    p = P()
    leg = mat("#2c2e31", 0.45, 0.6, dirt=0.25)
    top = 1.55
    tube((0, 0, 0.35), (0, 0, top), 0.016, leg, 12)
    tube((0, 0, 0.6), (0, 0, 1.1), 0.02, p["steel"], 12)         # telescoping section
    box((0.03, 0.03, 0.05), (0, 0, 1.1), p["plastic"], bevel=0.004)
    for a in (90, 210, 330):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        tube((0, 0, 0.42), d * 0.36 + Vector((0, 0, 0.0)), 0.011, leg, 8)
        tube(d * 0.05 + Vector((0, 0, 0.35)), d * 0.2 + Vector((0, 0, 0.16)), 0.006, leg, 6)
        cyl(0.018, 0.015, d * 0.36 + Vector((0, 0, 0.007)), p["rubber"])
    tube((-0.4, 0, top), (0.4, 0, top), 0.014, leg, 10)
    for x in (-0.21, 0.21):
        head = Vector((x, -0.04, top + 0.12))
        tilt = (0, 0, 0)
        box((0.36, 0.07, 0.24), head, mat("#2b2d31", 0.45, 0.5, dirt=0.3), rot=tilt, bevel=0.01)
        for i in range(7):
            box((0.006, 0.05, 0.2), head + Vector((-0.15 + i * 0.05, 0.055, 0.0)), p["alu"], rot=tilt, bevel=0.001)
        box((0.31, 0.006, 0.19), head + Vector((0, -0.038, 0)), glow("#ffd98a", 5), rot=tilt, bevel=0.001)
        for i in range(3):
            box((0.31, 0.004, 0.006), head + Vector((0, -0.042, -0.06 + i * 0.06)), p["steel_dark"], rot=tilt, bevel=0)
        for s in (-1, 1):
            box((0.01, 0.03, 0.05), (x + s * 0.17, -0.0, top + 0.05), p["steel_dark"], bevel=0.002)
    box((0.08, 0.05, 0.1), (0, 0.03, 0.9), mat("#26282b", 0.5, 0.3), bevel=0.006)
    lamp((0, 0.004, 0.92), True, "#57d36a", r=0.005)
    cord([(0, 0.06, 0.88), (0.05, 0.12, 0.5), (0.15, 0.2, 0.05), (0.4, 0.3, 0.01)], p)
    return 45                    # heads face the viewer


# ------------------------------------------------------------------ floor gear
def build_flood_table():
    """Flood-and-drain table: steel stand, ribbed tray with lip, drain and fill fittings, hose."""
    p = P()
    galv = p["galv"]; H = 0.6; S = 0.92
    for x in (-S / 2 + 0.04, S / 2 - 0.04):
        for y in (-S / 2 + 0.04, S / 2 - 0.04):
            box((0.035, 0.035, H - 0.05), (x, y, (H - 0.05) / 2), galv, bevel=0.004)
            box((0.06, 0.06, 0.012), (x, y, 0.006), p["rubber"], bevel=0.003)
    for z in (0.18, H - 0.07):
        rect(-S / 2 + 0.04, S / 2 - 0.04, -S / 2 + 0.04, S / 2 - 0.04, z, 0.012, galv)
    tray = mat("#e6e4dc", 0.55, var=0.1, dirt=0.35)
    box((S, S, 0.03), (0, 0, H - 0.03), tray, bevel=0.01)
    for x in (-S / 2 + 0.015, S / 2 - 0.015):
        box((0.03, S, 0.07), (x, 0, H + 0.02), tray, bevel=0.008)
    for y in (-S / 2 + 0.015, S / 2 - 0.015):
        box((S, 0.03, 0.07), (0, y, H + 0.02), tray, bevel=0.008)
    for i in range(11):                                   # drainage ribs
        box((0.018, S - 0.1, 0.012), (-0.36 + i * 0.072, 0, H - 0.008), mat("#d9d6cc", 0.55, dirt=0.4), bevel=0.003)
    wet = mat("#9aa6a2", 0.15, var=0.3, alpha=0.18, dirt=0, wear=False)
    box((S - 0.08, S - 0.08, 0.002), (0, 0, H - 0.0), wet, bevel=0)
    cyl(0.035, 0.03, (0.3, -0.3, H + 0.006), p["plastic"]); cyl(0.022, 0.06, (0.3, -0.3, H + 0.02), mat("#3d6fae", 0.45))
    cyl(0.028, 0.025, (-0.32, 0.3, H + 0.004), p["plastic"])
    hose = mat("#202325", 0.6, dirt=0.15)
    path([(0.3, -0.3, H - 0.05), (0.33, -0.36, 0.4), (0.38, -0.44, 0.08), (0.5, -0.47, 0.015)], 0.014, hose)
    path([(-0.32, 0.3, H - 0.05), (-0.36, 0.34, 0.3), (-0.4, 0.44, 0.015)], 0.012, hose)
    label((0.1, 0.002, 0.03), (-0.2, -S / 2 - 0.001, H + 0.02), "#2f6fb0")
    return 0


def fabric_mat(col):
    """Felt grow-bag fabric: coarse colour noise plus a bump so the weave catches the light."""
    m = mat(col, 0.95, var=0.25, dirt=0.35)
    nt = m.node_tree; b = nt.nodes.get("Principled BSDF")
    if not b.inputs["Normal"].is_linked:
        bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.35
        nt.links.new(noise(nt, 160.0, 2), bp.inputs["Height"]); nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m


def build_grow_bag():
    """Large fabric pot with soil: sagging felt walls, stitched rim band, two strap handles, perlite."""
    p = P(); rnd = random.Random(4)
    felt = fabric_mat("#3a3b3e"); band = mat("#2a2b2d", 0.9, var=0.1, dirt=0.3)
    R, H = 0.42, 0.42
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=40, radius1=R * 0.96, radius2=R, depth=H)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.1], cuts=5)
    for v in bm.verts:                                   # soft bulge and creases
        a = math.atan2(v.co.y, v.co.x); t = (v.co.z + H / 2) / H
        bulge = 1 + 0.05 * math.sin(t * math.pi) + 0.012 * math.sin(a * 7 + t * 3)
        v.co.x *= bulge; v.co.y *= bulge
    obj(bm, felt, M((0, 0, H / 2)), smooth=True)
    cyl(R * 1.04 + 0.006, 0.045, (0, 0, H - 0.02), band, segs=40, caps=False)
    cyl(R * 0.96, 0.01, (0, 0, 0.005), band, segs=40)
    stitch = mat("#8a8a86", 0.8, dirt=0.2)
    for i in range(64):
        a = 2 * math.pi * i / 64
        box((0.014, 0.002, 0.003), (math.cos(a) * (R * 1.04 + 0.01), math.sin(a) * (R * 1.04 + 0.01), H - 0.042),
            stitch, rot=(0, 0, math.degrees(a) + 90), bevel=0)
    for a in (0, 180):
        c = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0)) * (R * 1.04 + 0.02)
        torus(0.05, 0.008, c + Vector((0, 0, H - 0.03)), band, axis="Y" if a in (0, 180) else "X", seg=20, rseg=6,
              rot=(90, 0, 90 + a))
    soil = mat("#4a3524", 0.98, var=0.35, dirt=0.0)
    cyl(R * 1.03, 0.02, (0, 0, H - 0.06), soil, segs=40)
    for _ in range(70):
        a = rnd.uniform(0, 6.283); d = (R - 0.03) * rnd.random() ** 0.5
        ball(0.007, (math.cos(a) * d, math.sin(a) * d, H - 0.049), mat("#e8e6dc", 0.8, dirt=0), segs=6)
    label((0.13, 0.002, 0.07), (0.1, -R * 1.02 - 0.012, 0.2), "#c9c1a5", rot=(0, 0, 14))
    return 0


def build_dwc():
    """DWC bucket: ribbed 5-gallon bucket, lid with net pot and clay pebbles, airline to a small pump."""
    p = P(); rnd = random.Random(2)
    blk = mat("#25272a", 0.5, var=0.12, dirt=0.35)
    R, H = 0.25, 0.56
    cyl(R * 0.9, H, (0, 0, H / 2), blk, segs=36, r2=R)
    for z in (0.16, 0.27, 0.4): torus(R * (0.9 + 0.1 * z / H) + 0.004, 0.006, (0, 0, z), blk, seg=36, rseg=6)
    cyl(R + 0.012, 0.035, (0, 0, H + 0.005), mat("#2f3135", 0.5, dirt=0.3), segs=36)
    torus(R * 0.55, 0.006, (0, 0, H + 0.024), mat("#1a1b1d", 0.6), seg=28)
    cyl(R * 0.52, 0.03, (0, 0, H + 0.02), mat("#141516", 0.7), segs=28)
    clay = mat("#a5552f", 0.9, var=0.3, dirt=0.1)
    for _ in range(26):
        a = rnd.uniform(0, 6.283); d = R * 0.45 * rnd.random() ** 0.5
        ball(0.016, (math.cos(a) * d, math.sin(a) * d, H + 0.04), clay, segs=8)
    # handle
    hp = [(R + 0.01, 0, H - 0.04)] + [(math.cos(math.radians(a)) * (R + 0.03), 0.0, H - 0.04 + math.sin(math.radians(a)) * 0.0) for a in ()]
    torus(R + 0.02, 0.005, (0, 0, H - 0.05), p["steel"], axis="X", seg=40, rseg=6, rot=(70, 0, 0))
    # water level window and sticker
    box((0.03, 0.004, 0.3), (-0.07, -R * 0.95, 0.24), mat("#4f6a73", 0.2, alpha=0.6, dirt=0, wear=False), rot=(0, 0, 0), bevel=0.002)
    label((0.11, 0.002, 0.08), (0.07, -R * 0.96, 0.33), "#d9d2bc")
    # air pump and line
    box((0.12, 0.08, 0.06), (0.34, -0.2, 0.03), mat("#d8d6cf", 0.55, dirt=0.35), bevel=0.012)
    lamp((0.3, -0.241, 0.04), True, "#57d36a", r=0.004)
    path([(0.34, -0.16, 0.06), (0.32, 0.0, 0.2), (0.22, 0.1, H + 0.07), (0.09, 0.06, H + 0.04)], 0.004, mat("#b8d4d6", 0.3, alpha=0.8, dirt=0))
    cord([(0.4, -0.2, 0.02), (0.45, -0.3, 0.01), (0.47, -0.42, 0.008)], p)
    return 0


# ------------------------------------------------------------------ wall gear (north wall, facing -Y)
WALL_Y = 0.5


def build_panel():
    """Grow room panel: steel enclosure, door with screen, dials, switches, conduit down the wall."""
    p = P(); z = 1.25
    y = WALL_Y - 0.06
    box((0.36, 0.1, 0.46), (0, y, z), mat("#7d8790", 0.4, 0.5, dirt=0.3), bevel=0.012)
    box((0.33, 0.012, 0.43), (0, y - 0.055, z), mat("#8b959d", 0.42, 0.5, dirt=0.3), bevel=0.006)
    for zz in (z + 0.15, z - 0.15): cyl(0.008, 0.04, (-0.168, y - 0.06, zz), p["steel_dark"], axis="Z", segs=10)
    box((0.03, 0.02, 0.06), (0.15, y - 0.07, z), p["plastic"], bevel=0.004)          # latch
    box((0.17, 0.006, 0.09), (-0.03, y - 0.062, z + 0.12), mat("#1b2a20", 0.2, dirt=0), bevel=0.002)
    box((0.15, 0.002, 0.07), (-0.03, y - 0.066, z + 0.12), glow("#6dff8a", 3.5), bevel=0)
    gauge((-0.08, y - 0.062, z - 0.02), (0, 0, 0), r=0.035, needle=0.6)
    gauge((0.03, y - 0.062, z - 0.02), (0, 0, 0), r=0.035, needle=0.35)
    for i, col in enumerate(("#3fb35a", "#d6a52a", "#c7382f")):
        lamp((-0.09 + i * 0.05, y - 0.065, z - 0.13), i == 0, col, r=0.008)
    for i in range(3):
        box((0.012, 0.025, 0.03), (0.05 + i * 0.035, y - 0.07, z - 0.13), p["steel"], rot=(25, 0, 0), bevel=0.002)
    label((0.08, 0.002, 0.04), (0.07, y - 0.063, z + 0.12), "#e1c43f")
    box((0.05, 0.05, 0.04), (0, y - 0.0, z + 0.25), p["steel_dark"], bevel=0.004)
    tube((0, y + 0.01, z + 0.27), (0, y + 0.01, 2.6), 0.016, p["galv"], 12)
    for zz in (1.75, 2.15): box((0.05, 0.02, 0.012), (0, y + 0.015, zz), p["galv"], bevel=0.002)
    tube((0.14, y, z - 0.23), (0.14, y + 0.02, 0.9), 0.007, p["wire_k"], 8)
    return 0


def build_exhaust():
    """Wall exhaust fan: square steel housing, wire guard, angled blades, shutter frame, cable down."""
    p = P(); z = 1.55; y = WALL_Y - 0.08
    house = mat("#9aa0a4", 0.42, 0.55, dirt=0.35)
    S = 0.4
    for (sx, sz, dx, dz) in ((S, 0.03, 0, S / 2), (S, 0.03, 0, -S / 2), (0.03, S, S / 2, 0), (0.03, S, -S / 2, 0)):
        box((sx, 0.16, sz), (dx, y, z + dz), house, bevel=0.006)
    box((S, 0.01, S), (0, y + 0.075, z), p["steel_dark"], bevel=0.002)
    torus(0.18, 0.012, (0, y - 0.02, z), house, axis="Y", seg=40, rseg=8)
    hub = Vector((0, y + 0.02, z))
    cyl(0.05, 0.06, hub, p["iron"], axis="Y", segs=24)
    blade = mat("#b9a27a", 0.4, 0.7, dirt=0.3)
    for i in range(5):
        a = 72 * i
        bm = blade_bm(0.13, 0.09, 0.12, 0.004, 18, pitch=25)
        obj(bm, blade, M(hub, (90, a, 0)) @ M((0, 0, 0.03)))
    grd = p["steel"]
    for r in (0.06, 0.11, 0.16):
        torus(r, 0.0025, (0, y - 0.085, z), grd, axis="Y", seg=36, rseg=4)
    for i in range(8):
        a = math.radians(22.5 * i)
        tube((math.cos(a) * 0.17, y - 0.085, z + math.sin(a) * 0.17), (-math.cos(a) * 0.17, y - 0.085, z - math.sin(a) * 0.17), 0.0025, grd, 4)
    screws([(sx, y - 0.082, z + sz) for sx in (-0.18, 0.18) for sz in (-0.18, 0.18)], p, 0.008)
    box((0.07, 0.04, 0.06), (0.16, y - 0.09, z - 0.24), p["plastic"], bevel=0.006)
    label((0.06, 0.002, 0.025), (-0.1, y - 0.082, z - 0.215), "#e1c43f")
    tube((0.16, y - 0.09, z - 0.27), (0.16, y - 0.09, 0.9), 0.006, p["wire_k"], 8)
    return 0


BUILDS = {
    "dish_pro": build_dish_pro, "bar_pro": build_bar_pro, "flood_pro": build_flood_pro,
    "flood_table": build_flood_table, "grow_bag": build_grow_bag, "dwc": build_dwc,
    "panel": build_panel, "exhaust": build_exhaust,
}

os.makedirs(OUT_DIR, exist_ok=True)
tile_camera()
for name, fn in BUILDS.items():
    if ONLY and name not in ONLY: continue
    clear(); WEAR.update(rust=0.0, dirt=0.05, scorch=0.0)
    start = len(BUILT)
    yaw = fn() or 0
    root = bpy.data.objects.new("root", None); MODEL.objects.link(root)
    for ob in BUILT[start:]: ob.parent = root
    root.rotation_euler = (0, 0, math.radians(yaw))
    render(os.path.join(OUT_DIR, name + ".png")); log("sample", name)
    print("rendered", name, flush=True)
