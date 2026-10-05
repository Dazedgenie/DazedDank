"""Blender script: renders the flood lights, curing barrel, DWC and RDWC buckets, the RDWC control bucket and their icons.
Run inside Blender with render_plants.py, render_furniture.py and render_icons.py next to it: exec(open(path).read()). Optional globals: DD_ONLY, DD_SAMPLES.
"""

import bpy
import math
import os
import random
from mathutils import Vector, Matrix

DD_NO_MAIN = True
DD_NO_RUN = True
DD_NO_RUN_ICONS = True
HERE = globals().get("DD_DIR", r"C:\Users\Shado\Zomboid\DazedDank_art")
exec(open(os.path.join(HERE, "render_icons.py")).read(), globals())


def flatbox_geo(c, sx, sy, sz):
    """A box with its own vertices per face, so it stays crisp under smooth shading."""
    c = Vector(c)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    quads = [
        [(-1, -1, -1), (-1, 1, -1), (-1, 1, 1), (-1, -1, 1)], [(1, -1, -1), (1, -1, 1), (1, 1, 1), (1, 1, -1)],
        [(-1, -1, -1), (-1, -1, 1), (1, -1, 1), (1, -1, -1)], [(-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1)],
        [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1)], [(-1, -1, 1), (-1, 1, 1), (1, 1, 1), (1, -1, 1)],
    ]
    verts, faces, uvs = [], [], []
    for q in quads:
        base = len(verts)
        for (dx, dy, dz), uv in zip(q, ((0, 0), (1, 0), (1, 1), (0, 1))):
            verts.append(c + Vector((dx * hx, dy * hy, dz * hz)))
            uvs.append(uv)
        faces.append((base, base + 1, base + 2, base + 3))
    return verts, faces, uvs


def bulge_geo(h, r_end, r_mid, seg=32, rings=10):
    """A barrel body: radius r_end at both ends swelling to r_mid at half height."""
    verts, faces, uvs = [], [], []
    for k in range(rings + 1):
        t = k / rings
        r = r_end + (r_mid - r_end) * math.sin(math.pi * t)
        for s in range(seg):
            a = 2 * math.pi * s / seg
            verts.append(Vector((math.cos(a) * r, math.sin(a) * r, h * t)))
            uvs.append((s / seg, t))
    for k in range(rings):
        for s in range(seg):
            s2 = (s + 1) % seg
            faces.append((k * seg + s, k * seg + s2, (k + 1) * seg + s2, (k + 1) * seg + s))
    return verts, faces, uvs


def hoop(G, z, r, thick=0.012, seg=40):
    ring_path(G, [Vector((math.cos(2 * math.pi * s / seg) * r, math.sin(2 * math.pi * s / seg) * r, z)) for s in range(seg)], thick, 5, True)


def facing_matrix(origin, tilt_deg):
    """A frame at `origin` whose +Y points toward the viewer, tilted down by `tilt_deg`, with +Z up out of the top."""
    t = math.radians(tilt_deg)
    y = (TOWARD * math.cos(t) + Vector((0, 0, -math.sin(t)))).normalized()
    x = -RIGHT
    z = x.cross(y).normalized()
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


# Every material these models use: name -> builder.
MATS = {
    "yellow":  lambda: new_mat("yellow", (214, 168, 40), 0.45, metal=0.1),
    "charcoal": lambda: new_mat("charcoal", (48, 48, 58), 0.45, metal=0.3),
    "steel":   lambda: new_mat("steel", (160, 162, 170), 0.35, metal=0.85),
    "black":   lambda: new_mat("black", (28, 28, 32), 0.55),
    "grille":  lambda: new_mat("grille", (230, 230, 236), 0.4, metal=0.6),
    "purpleglow": lambda: emit_mat("purpleglow", (150, 60, 255), 1.6),
    "warmglow": lambda: emit_mat("warmglow", (255, 200, 110), 2.4),
    "oak":     lambda: new_mat("oak", (128, 84, 46), 0.75, bump=0.5, scale=22, patch=0.25),
    "oakdark": lambda: new_mat("oakdark", (78, 50, 28), 0.8),
    "oaklid":  lambda: new_mat("oaklid", (150, 102, 60), 0.75, bump=0.4, scale=22, patch=0.2),
    "iron":    lambda: new_mat("iron", (58, 58, 64), 0.5, metal=0.7),
    "dwcbody": lambda: new_mat("dwcbody", (34, 34, 38), 0.45),
    "dwclid":  lambda: new_mat("dwclid", (52, 52, 58), 0.5),
    "sitebody": lambda: new_mat("sitebody", (56, 74, 98), 0.45),
    "sitelid": lambda: new_mat("sitelid", (80, 98, 124), 0.5),
    "ctrlbody": lambda: new_mat("ctrlbody", (220, 222, 226), 0.4),
    "ctrllid": lambda: new_mat("ctrllid", (236, 236, 240), 0.45),
    "netpot":  lambda: new_mat("netpot", (22, 22, 26), 0.6),
    "hole":    lambda: new_mat("hole", (8, 8, 10), 0.9),
    "pebble":  lambda: new_mat("pebble", (176, 92, 52), 0.8, bump=0.5, scale=90, patch=0.3),
    "rawclay": lambda: new_mat("rawclay", (150, 128, 110), 0.85, bump=0.4, scale=90, patch=0.2),
    "rockwool": lambda: new_mat("rockwool", (214, 204, 156), 0.95, bump=0.9, scale=140, patch=0.2),
    "pumpbody": lambda: new_mat("pumpbody", (214, 216, 222), 0.4),
    "airline": lambda: new_mat("airline", (170, 210, 230), 0.25, trans=0.3),
    "hose":    lambda: new_mat("hose", (34, 34, 38), 0.6),
    "led":     lambda: emit_mat("led", (90, 230, 120), 6.0),
    "timerbody": lambda: new_mat("timerbody", (222, 224, 228), 0.4),
    "dialface": lambda: new_mat("dialface", (250, 250, 248), 0.5),
    "pinon":   lambda: new_mat("pinon", (70, 170, 80), 0.4),
    "pinoff":  lambda: new_mat("pinoff", (60, 60, 70), 0.4),
    "needle":  lambda: new_mat("needle", (200, 60, 60), 0.4),
    "brass":   lambda: new_mat("brass", (186, 160, 90), 0.3, metal=0.9),
    "kraft":   lambda: new_mat("kraft", (176, 140, 96), 0.9, bump=0.3, scale=40, patch=0.15),
    "cover":   lambda: new_mat("cover", (40, 110, 170), 0.35),
    "spine":   lambda: new_mat("spine", (28, 80, 130), 0.35),
    "title":   lambda: new_mat("title", (240, 240, 250), 0.4),
    "photo":   lambda: new_mat("photo", (120, 190, 230), 0.4),
    "leafg":   lambda: new_mat("leafg", (90, 190, 90), 0.4),
    "pagewhite": lambda: new_mat("pagewhite", (236, 232, 220), 0.6),
    "tray":    lambda: new_mat("tray", (228, 228, 222), 0.45),
    "trayrib": lambda: new_mat("trayrib", (196, 196, 190), 0.5),
    "frame":   lambda: new_mat("frame", (150, 154, 160), 0.35, metal=0.8),
    "tote":    lambda: new_mat("tote", (32, 32, 36), 0.5),
    "totelid": lambda: new_mat("totelid", (60, 62, 70), 0.5),
    "timerblue": lambda: new_mat("timerblue", (70, 118, 196), 0.4),
}


def mats_of(G):
    return {k: MATS[k]() for k, g in G.items() if g.v}


# ------------------------------------------------------------------ flood lights

FLOOD_SPEC = {
    "Basic": dict(w=22, heads=1, top=96, body="yellow", glow="purpleglow"),
    "Pro":   dict(w=18, heads=2, top=112, body="charcoal", glow="warmglow"),
}


def model_flood(key):
    """A tripod work light: three splayed legs, a pole, a yoke and one or two lamp heads tilted down at the plants."""
    sp = FLOOD_SPEC[key]
    G = new_geos(sp["body"], "charcoal", "steel", "black", "grille", sp["glow"])
    top = sp["top"] / PX_V
    hub = top * 0.5
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.5
        foot = Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, 0.0))
        G["charcoal"].add(*tube_geo((0, 0, hub), foot, 0.012, 0.01, 6))
        G["black"].add(*blob_geo(foot + Vector((0, 0, 0.008)), (0.02, 0.02, 0.01), random.Random(k), 0.0, 3, 8))
    G["charcoal"].add(*tube_geo((0, 0, hub - 0.03), (0, 0, hub + 0.05), 0.026, 0.026, 10))
    G["steel"].add(*tube_geo((0, 0, hub), (0, 0, top - 0.06), 0.012, 0.012, 8))
    w = sp["w"] / PX_H
    hh = (26 if sp["heads"] == 1 else 24) / PX_V
    centres = [Vector((0, 0, 0))] if sp["heads"] == 1 else [-RIGHT * (w + 0.03), RIGHT * (w + 0.03)]
    # crossbar and yoke
    span = (w + 0.03) * (1 if sp["heads"] == 1 else 2) + 0.02
    G["steel"].add(*tube_geo(RIGHT * -span + Vector((0, 0, top - 0.06)), RIGHT * span + Vector((0, 0, top - 0.06)), 0.01, 0.01, 6))
    for c in centres:
        base = c + Vector((0, 0, top - 0.06))
        for side in (-1, 1):
            arm = base + RIGHT * side * (w + 0.012)
            G["steel"].add(*tube_geo(arm, arm + Vector((0, 0, hh * 0.55)), 0.007, 0.007, 5))
        M = facing_matrix(base + Vector((0, 0, hh * 0.55)), 28)
        depth = 0.09
        G[sp["body"]].add(*flatbox_geo((0, 0, 0), w * 2, depth, hh), m=M)
        G[sp["body"]].add(*flatbox_geo((0, depth / 2 + 0.006, 0), w * 2 + 0.014, 0.012, hh + 0.014), m=M)
        G[sp["glow"]].add(*flatbox_geo((0, depth / 2 + 0.008, 0), w * 2 - 0.02, 0.012, hh - 0.02), m=M)
        bars = 4 if key == "Pro" else 3
        for i in range(1, bars):
            x = -w + 2 * w * i / bars
            G["grille"].add(*flatbox_geo((x, depth / 2 + 0.016, 0), 0.006, 0.006, hh - 0.02), m=M)
        for i in range(5):
            x = -w * 0.8 + w * 1.6 * i / 4
            G["black"].add(*flatbox_geo((x, -depth / 2 - 0.015, 0), 0.008, 0.03, hh * 0.85), m=M)
    return G


# ------------------------------------------------------------------ curing barrel

def model_barrel():
    """An oak curing barrel on end: bulging staves with dark seams, four iron hoops and a planked lid."""
    G = new_geos("oak", "oakdark", "oaklid", "iron")
    r, h = 24 / PX_H, 62 / PX_V
    G["oak"].add(*bulge_geo(h, r, r * 1.1, 40, 12))
    G["oakdark"].add(*disc_geo(0.004, r, 40))
    for s in range(16):
        a = 2 * math.pi * s / 16
        pts = [Vector((math.cos(a) * (r + (r * 0.1) * math.sin(math.pi * t)) * 1.003,
                       math.sin(a) * (r + (r * 0.1) * math.sin(math.pi * t)) * 1.003, h * t)) for t in (0.02, 0.25, 0.5, 0.75, 0.98)]
        ring_path(G["oakdark"], pts, 0.0028, 4)
    for t in (0.1, 0.3, 0.7, 0.9):
        hoop(G["iron"], h * t, (r + r * 0.1 * math.sin(math.pi * t)) * 1.008, 0.011)
    G["oakdark"].add(*cone_geo(h - 0.025, h, r * 0.96, r * 0.99, 40))
    G["oaklid"].add(*disc_geo(h - 0.02, r * 0.96, 40))
    for k in (-2, -1, 0, 1, 2):
        G["oakdark"].add(*flatbox_geo((k * r * 0.32, 0, h - 0.018), 0.004, r * 1.8 * math.sqrt(max(0.05, 1 - (k * 0.32) ** 2)), 0.004))
    return G


# ------------------------------------------------------------------ hydro buckets

BUCKETS = {
    "dwc":  dict(r=22, h=40, body="dwcbody", lid="dwclid"),
    "rdwc": dict(r=22, h=40, body="sitebody", lid="sitelid"),
    "rdwc_control": dict(r=27, h=72, body="ctrlbody", lid="ctrllid"),
}


def bucket_shell(G, spec):
    """A tapered bucket with stacking ribs, a rolled rim and a snap lid; returns (radius, height) in world units."""
    r, h = spec["r"] / PX_H, spec["h"] / PX_V
    body, lid = spec["body"], spec["lid"]
    G[body].add(*cone_geo(0.0, h - 0.02, r * 0.88, r, 36, None, 0, 4))
    G[body].add(*disc_geo(0.002, r * 0.88, 36))
    for t in (0.22, 0.5):
        hoop(G[body], h * t, (r * 0.88 + r * 0.12 * t) * 1.012, 0.006)
    hoop(G[body], h - 0.03, r * 1.01, 0.01)
    G[lid].add(*cone_geo(h - 0.022, h + 0.004, r * 1.03, r * 1.03, 36))
    G[lid].add(*disc_geo(h + 0.004, r * 1.03, 36))
    return r, h


def net_pot(G, h, medium, rng, rp=0.085):
    """The net pot in the lid: an open black ring, empty or filled with clay pebbles around a rockwool cube."""
    hoop(G["netpot"], h + 0.008, rp, 0.008, 30)
    G["hole"].add(*disc_geo(h + 0.006, rp, 30))
    if medium:
        for _ in range(60):
            a = rng.uniform(0, 6.28)
            d = (rp - 0.012) * rng.random() ** 0.5
            s = rng.uniform(0.010, 0.014)
            G["pebble"].add(*blob_geo((math.cos(a) * d, math.sin(a) * d, h + 0.014 + rng.uniform(0, 0.008)), (s, s, s * 0.85), rng, 0.15, 3, 6))
        G["rockwool"].add(*flatbox_geo((0, 0, h + 0.03), 0.05, 0.05, 0.04), m=Matrix.Rotation(0.3, 4, 'Z'))
    else:
        for k in range(-2, 3):
            G["netpot"].add(*flatbox_geo((k * rp * 0.36, 0, h + 0.004), 0.008, rp * 1.8 * math.sqrt(max(0.1, 1 - (k * 0.36) ** 2)), 0.004))


def air_pump(G, at, lid_pt):
    """A little white air pump on the floor with its airline running up into the lid."""
    G["pumpbody"].add(*flatbox_geo(at + Vector((0, 0, 0.035)), 0.13, 0.08, 0.07), m=Matrix.Translation(at) @ Matrix.Rotation(0.6, 4, 'Z') @ Matrix.Translation(-at))
    p0 = at + Vector((0, 0, 0.07))
    pts = [p0, p0 + Vector((0, 0, 0.12)), (p0 + lid_pt) / 2 + Vector((0, 0, 0.32)), lid_pt + Vector((0, 0, 0.06)), lid_pt]
    ring_path(G["airline"], pts, 0.006, 5)


def model_bucket(style, medium):
    """A DWC bucket (black, own air pump) or an RDWC site (blue-grey, with a return hose running off along the floor)."""
    spec = BUCKETS[style]
    G = new_geos(spec["body"], spec["lid"], "netpot", "hole", "pebble", "rockwool", "pumpbody", "airline", "hose", "black")
    rng = random.Random(7 if style == "dwc" else 8)
    r, h = bucket_shell(G, spec)
    net_pot(G, h, medium, rng)
    if style == "dwc":
        air_pump(G, RIGHT * (r + 0.13) + TOWARD * 0.05, -RIGHT * 0.0 + RIGHT * r * 0.6 + Vector((0, 0, h)))
    else:
        fit = -RIGHT * r * 0.95 + Vector((0, 0, 0.06))
        G["black"].add(*tube_geo(fit, fit - RIGHT * 0.04, 0.022, 0.022, 10))
        pts = [fit - RIGHT * 0.04, fit - RIGHT * 0.1 + Vector((0, 0, -0.04)), -RIGHT * (r + 0.25) + TOWARD * 0.05 + Vector((0, 0, 0.018)),
               -RIGHT * (r + 0.5) + TOWARD * 0.12 + Vector((0, 0, 0.018))]
        ring_path(G["hose"], pts, 0.018, 8)
    return G


def model_control():
    """The RDWC control bucket: a tall white reservoir with a pump housing and power light on the lid, an air pump, and three hoses out to the sites."""
    spec = BUCKETS["rdwc_control"]
    G = new_geos(spec["body"], spec["lid"], "charcoal", "led", "pumpbody", "airline", "hose", "black")
    r, h = bucket_shell(G, spec)
    G["charcoal"].add(*flatbox_geo((0, 0, h + 0.04), 0.14, 0.1, 0.07), m=Matrix.Rotation(0.785, 4, 'Z'))
    G["led"].add(*flatbox_geo(TOWARD * 0.072 + Vector((0, 0, h + 0.05)), 0.016, 0.016, 0.016))
    G["black"].add(*tube_geo(Vector((0, 0, h + 0.075)), Vector((0, 0, h + 0.1)), 0.012, 0.012, 8))
    air_pump(G, RIGHT * (r + 0.15) + TOWARD * 0.06, RIGHT * r * 0.6 + Vector((0, 0, h)))
    # Hoses leave the sides and back and lie flat, so they read as plumbing rather than legs.
    for a in (-1.5, 1.5, 2.7):
        out = (TOWARD * math.cos(a) + RIGHT * math.sin(a) * -1).normalized()
        fit = out * r * 0.9 + Vector((0, 0, 0.06))
        G["black"].add(*tube_geo(fit, fit + out * 0.04, 0.022, 0.022, 10))
        pts = [fit + out * 0.04, fit + out * 0.12 + Vector((0, 0, -0.04)), out * (r + 0.32) + Vector((0, 0, 0.018)), out * (r + 0.55) + Vector((0, 0, 0.018))]
        ring_path(G["hose"], pts, 0.018, 8)
    return G


# ------------------------------------------------------------------ Ebb and Flow

TABLE_TOP_PX = 30          # tray floor height in 1x pixels; the sprite pipeline lifts plants by TABLE_LIFT_PX
ROCKWOOL_PX = 11           # a 4-inch rockwool block standing on the tray


def model_flood_table(medium):
    """One tile of a flood table: a white ribbed tray on a galvanised frame; with `medium`, a rockwool block sits in the middle."""
    G = new_geos("tray", "trayrib", "frame", "rockwool", "black", "hole")
    top = TABLE_TOP_PX / PX_V
    half = 0.47
    for sx in (-1, 1):
        for sy in (-1, 1):
            G["frame"].add(*flatbox_geo((sx * (half - 0.03), sy * (half - 0.03), top / 2), 0.03, 0.03, top))
    for sx in (-1, 1):
        G["frame"].add(*flatbox_geo((sx * (half - 0.03), 0, top * 0.35), 0.02, 2 * half - 0.06, 0.02))
        G["frame"].add(*flatbox_geo((0, sx * (half - 0.03), top * 0.35), 2 * half - 0.06, 0.02, 0.02))
    G["tray"].add(*flatbox_geo((0, 0, top - 0.01), 2 * half, 2 * half, 0.02))
    rim = 0.05
    for sx in (-1, 1):
        G["tray"].add(*flatbox_geo((sx * (half - 0.01), 0, top + rim / 2), 0.02, 2 * half, rim))
        G["tray"].add(*flatbox_geo((0, sx * (half - 0.01), top + rim / 2), 2 * half, 0.02, rim))
    for k in range(-3, 4):
        G["trayrib"].add(*flatbox_geo((k * 0.12, 0, top + 0.004), 0.025, 2 * half - 0.06, 0.008))
    G["black"].add(*tube_geo((half - 0.1, half - 0.1, top), (half - 0.1, half - 0.1, top - 0.08), 0.02, 0.02, 10))
    if medium:
        h = ROCKWOOL_PX / PX_V
        G["rockwool"].add(*flatbox_geo((0, 0, top + h / 2), 0.16, 0.16, h), m=Matrix.Rotation(0.2, 4, 'Z'))
        G["hole"].add(*disc_geo(top + h + 0.002, 0.025, 14))
    return G


def model_flood_reservoir():
    """The flood reservoir: a black tote with a grey lid, a fill and a drain hose rising to table height, and the pump's control box."""
    G = new_geos("tote", "totelid", "hose", "black", "pumpbody", "led")
    w, d, h = 0.6, 0.6, 0.46
    M = Matrix.Rotation(0.0, 4, 'Z')   # square to the floor grid, so two sides show like other furniture
    G["tote"].add(*flatbox_geo((0, 0, h / 2), w, d, h), m=M)
    G["totelid"].add(*flatbox_geo((0, 0, h + 0.015), w + 0.03, d + 0.03, 0.03), m=M)
    for k, off in enumerate((-0.12, 0.08)):
        base = -RIGHT * 0.18 + TOWARD * off + Vector((0, 0, h + 0.03))
        pts = [base, base + Vector((0, 0, 0.1)), base - RIGHT * 0.12 + Vector((0, 0, 0.14)), base - RIGHT * 0.32 + Vector((0, 0, 0.12))]
        ring_path(G["hose"], pts, 0.016, 8)
        G["black"].add(*tube_geo(base, base + Vector((0, 0, 0.02)), 0.024, 0.024, 10))
    box = RIGHT * 0.2 + TOWARD * 0.2 + Vector((0, 0, h * 0.62))
    G["pumpbody"].add(*flatbox_geo(box, 0.12, 0.12, 0.12), m=Matrix.Translation(box) @ M @ Matrix.Translation(-box))
    G["led"].add(*flatbox_geo(box + TOWARD * 0.062 + Vector((0, 0, 0.03)), 0.015, 0.015, 0.015))
    return G


def m_flood_timer():
    """The flood timer: the light timer in blue."""
    G = m_timer()
    G["timerblue"] = G.pop("timerbody")
    return G


# ------------------------------------------------------------------ icon-only models

def m_timer():
    """A plug-in mechanical timer: grey body, a white dial ringed with on/off pins, a red pointer and brass prongs."""
    G = new_geos("timerbody", "dialface", "pinon", "pinoff", "needle", "brass")
    M = Matrix.Rotation(-math.pi / 4, 4, 'Z')
    G["timerbody"].add(*flatbox_geo((0, 0, 0.16), 0.26, 0.12, 0.32), m=M)
    face = M @ Matrix.Translation(Vector((0, 0.061, 0.18))) @ Matrix.Rotation(-math.pi / 2, 4, 'X')
    G["dialface"].add(*disc_geo(0, 0.1, 32), m=face)
    for k in range(24):
        a = 2 * math.pi * k / 24
        G["pinon" if k < 12 else "pinoff"].add(*flatbox_geo((math.cos(a) * 0.085, math.sin(a) * 0.085, 0.01), 0.012, 0.012, 0.02), m=face)
    G["needle"].add(*flatbox_geo((0, 0.035, 0.016), 0.01, 0.07, 0.008), m=face)
    for x in (-0.05, 0.05):
        G["brass"].add(*flatbox_geo((x, -0.09, 0.2), 0.012, 0.06, 0.04), m=M)
    return G


def m_rockwool():
    """A rockwool starter cube with a seed hole in its top."""
    G = new_geos("rockwool", "hole")
    G["rockwool"].add(*flatbox_geo((0, 0, 0.13), 0.26, 0.26, 0.26), m=Matrix.Rotation(0.2, 4, 'Z'))
    G["hole"].add(*disc_geo(0.262, 0.03, 16))
    return G


def m_pebbles(fired):
    """An open paper sack heaped with clay pebbles: terracotta once fired, grey raw clay before."""
    G = new_geos("kraft", "pebble", "rawclay")
    rng = random.Random(3)
    w, d, hgt = 0.34, 0.24, 0.26
    for c, sx, sy in (((0, -d / 2, hgt / 2), w, 0.01), ((0, d / 2, hgt / 2), w, 0.01), ((-w / 2, 0, hgt / 2), 0.01, d), ((w / 2, 0, hgt / 2), 0.01, d)):
        G["kraft"].add(*flatbox_geo(c, sx, sy, hgt))
    G["kraft"].add(*flatbox_geo((0, 0, 0.005), w, d, 0.01))
    mat = "pebble" if fired else "rawclay"
    for _ in range(140):
        x, y = rng.uniform(-w / 2 + 0.02, w / 2 - 0.02), rng.uniform(-d / 2 + 0.02, d / 2 - 0.02)
        mound = 0.05 * (1 - (2 * x / w) ** 2) * (1 - (2 * y / d) ** 2)
        s = rng.uniform(0.016, 0.022)
        G[mat].add(*blob_geo((x, y, hgt - 0.01 + mound * rng.uniform(0.3, 1.0)), (s, s, s * 0.85), rng, 0.15, 3, 6))
    return G


def m_magazine():
    """Hydroponics Monthly: a blue magazine with a white masthead and a leaf on a water-blue cover photo."""
    G = new_geos("pagewhite", "cover", "spine", "title", "photo", "leafg")
    M = Matrix.Rotation(-math.pi / 4, 4, 'Z') @ Matrix.Rotation(math.radians(-62), 4, 'X')
    G["pagewhite"].add(*flatbox_geo((0.004, 0, -0.006), 0.36, 0.5, 0.012), m=M)
    G["cover"].add(*flatbox_geo((0, 0, 0.002), 0.36, 0.5, 0.004), m=M)
    G["spine"].add(*flatbox_geo((-0.165, 0, 0.004), 0.03, 0.5, 0.004), m=M)
    G["title"].add(*flatbox_geo((0.015, 0.19, 0.005), 0.26, 0.07, 0.004), m=M)
    G["title"].add(*flatbox_geo((0.015, -0.2, 0.005), 0.26, 0.02, 0.004), m=M)
    G["photo"].add(*disc_geo(0.006, 0.11, 28), m=M @ Matrix.Translation(Vector((0.015, -0.01, 0))))
    leaf = M @ Matrix.Translation(Vector((0.015, -0.01, 0.008))) @ Matrix.Rotation(math.pi / 4, 4, 'Z')
    G["leafg"].add(*flatbox_geo((0, 0, 0), 0.07, 0.07, 0.003), m=leaf)
    return G


# ------------------------------------------------------------------ run

def run_extra():
    setup_render()
    world = [
        ("flood_Basic", lambda: model_flood("Basic")),
        ("flood_Pro", lambda: model_flood("Pro")),
        ("barrel", model_barrel),
        ("dwc_empty", lambda: model_bucket("dwc", False)),
        ("dwc_medium", lambda: model_bucket("dwc", True)),
        ("rdwc_empty", lambda: model_bucket("rdwc", False)),
        ("rdwc_medium", lambda: model_bucket("rdwc", True)),
        ("rdwc_control", model_control),
        ("ebb_table_empty", lambda: model_flood_table(False)),
        ("ebb_table_medium", lambda: model_flood_table(True)),
        ("flood_reservoir", model_flood_reservoir),
    ]
    for name, fn in world:
        if want(name):
            clear_data()
            render_geo_mats(name, fn())
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = 256
    sc.camera.data.shift_y = 0.0
    icons = [
        ("floodBasic", lambda: model_flood("Basic")),
        ("floodPro", lambda: model_flood("Pro")),
        ("barrel", model_barrel),
        ("dwc", lambda: model_bucket("dwc", False)),
        ("rdwcSite", lambda: model_bucket("rdwc", False)),
        ("rdwcControl", model_control),
        ("timer", m_timer),
        ("rockwool", m_rockwool),
        ("pebbles", lambda: m_pebbles(True)),
        ("pebblesRaw", lambda: m_pebbles(False)),
        ("hydroMag", m_magazine),
        ("floodTable", lambda: model_flood_table(True)),
        ("floodReservoir", model_flood_reservoir),
        ("floodTimer", m_flood_timer),
    ]
    for name, fn in icons:
        if want(name):
            clear_data()
            G = fn()
            render_icon(name, G, mats_of(G))
    print("DD EXTRA DONE")


def render_geo_mats(name, G):
    """Like render_geo, with this script's own materials."""
    sc = bpy.context.scene
    keep = [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT')]
    for ob in list(bpy.data.objects):
        if ob not in keep:
            bpy.data.objects.remove(ob, do_unlink=True)
    mats = mats_of(G)
    for k, g in G.items():
        if g.v:
            g.to_object(k, mats[k])
    os.makedirs(FOUT, exist_ok=True)
    sc.render.filepath = os.path.join(FOUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


if not globals().get("DD_NO_RUN_EXTRA"):
    run_extra()
