"""Blender script: renders the 9 male cannabis plants (3 strains x pre-flower, flowering, ripe) as isometric sprites.
Run inside Blender: exec(open(path).read()). Reuses render_plants.py; optional globals DD_SAMPLES, DD_OUT, DD_ONLY.
"""

import os

DD_NO_MAIN = True
ART_DIR = globals().get("DD_ART_DIR", r"C:\Users\Shado\Zomboid\DazedDank_art")
exec(open(os.path.join(ART_DIR, "render_plants.py")).read(), globals())

MALE_STAGES = ["PreFlower", "Flowering", "Ripe"]
# Males stretch: taller and thinner than the females, with longer gaps between nodes.
MALE_HEIGHT = {"PreFlower": 1.05, "Flowering": 1.18, "Ripe": 1.22}


def add_sac(Gs, center, rng, size):
    """One pollen sac: a small, slightly pointed green bud hanging from its stalk."""
    v, f, u = blob_geo(center, (size * 0.8, size * 0.8, size * 1.15), rng, 0.08, rings=4, seg=6)
    Gs.add(v, f, u)


def add_open_flower(Gp, Ga, Gst, center, rng, size):
    """An open male flower: five pale petals folded back, with stamens dangling yellow anthers."""
    for k in range(5):
        a = 2 * math.pi * k / 5 + rng.uniform(-0.2, 0.2)
        out = Vector((math.cos(a), math.sin(a), -0.35)).normalized()
        c = center + out * size * 0.9
        v, f, u = blob_geo(c, (size * 0.75, size * 0.75, size * 0.22), rng, 0.05, rings=3, seg=6)
        Gp.add(v, f, u)
    for k in range(5):
        a = 2 * math.pi * k / 5 + math.pi / 5
        p0 = center + Vector((math.cos(a) * size * 0.2, math.sin(a) * size * 0.2, 0))
        p1 = p0 + Vector((math.cos(a) * size * 0.3, math.sin(a) * size * 0.3, -size * 1.1))
        Gst.add(*tube_geo(p0, p1, size * 0.08, size * 0.06, 3))
        v, f, u = blob_geo(p1 - Vector((0, 0, size * 0.25)), (size * 0.18, size * 0.18, size * 0.38), rng, 0.05, rings=3, seg=5)
        Ga.add(v, f, u)


def add_cluster(G, origin, direction, length, rng, stage, density):
    """A drooping panicle of pollen sacs: a short stalk that forks into small pedicels, each ending in a sac or open flower."""
    tip = origin + direction.normalized() * length
    G["stem"].add(*tube_geo(origin, tip, 0.006, 0.0035, 4))
    count = max(3, int(density))
    for i in range(count):
        t = (i + 0.5) / count
        p = origin + (tip - origin) * (0.25 + 0.75 * t)
        a = rng.uniform(0, 2 * math.pi)
        out = Vector((math.cos(a), math.sin(a), rng.uniform(-0.9, -0.2))).normalized()
        end = p + out * length * rng.uniform(0.22, 0.38)
        G["stem"].add(*tube_geo(p, end, 0.002, 0.0015, 3))
        size = rng.uniform(0.019, 0.025) * (0.8 if stage == "PreFlower" else 1.0)
        if stage == "Ripe" and rng.random() < 0.5:
            add_open_flower(G["petal"], G["anther"], G["stamen"], end, rng, size)
        else:
            add_sac(G["sac"], end, rng, size)


def build_male(typ, stage, seed):
    """A male plant: leggy and sparse, its branch tips and upper nodes hung with pollen-sac clusters."""
    rng = random.Random(seed)
    G = {k: Geo() for k in ("stem", "leaf", "sac", "petal", "anther", "stamen")}
    spec = TYPES[typ]
    scale = STAGE_SCALE[stage]
    H = spec["h"] / PX_V * scale * MALE_HEIGHT[stage]
    W = spec["w"] / PX_H * scale * 0.9
    sway = Vector((rng.uniform(-0.04, 0.04) * H, rng.uniform(-0.04, 0.04) * H, 0))

    def stem_pt(z):
        t = z / H
        return Vector((sway.x * t * t, sway.y * t * t, z))

    segs = 9
    for i in range(segs):
        r0 = (0.030 - 0.023 * i / segs) * (0.55 + 0.45 * scale)
        r1 = (0.030 - 0.023 * (i + 1) / segs) * (0.55 + 0.45 * scale)
        G["stem"].add(*tube_geo(stem_pt(H * i / segs), stem_pt(H * (i + 1) / segs), r0, r1, 6))

    nodes = max(4, spec["nodes"])
    dens = {"PreFlower": 5, "Flowering": 12, "Ripe": 13}[stage]
    for k in range(nodes):
        t = (k + 0.7) / (nodes + 0.5)
        z = H * 0.14 + H * 0.82 * t
        phi = k * math.pi / 2 + rng.uniform(-0.2, 0.2)
        reach = W * 0.5 * (1 - t * 0.6)
        size = max(0.1, reach * 0.95) * rng.uniform(0.9, 1.1)
        fingers = spec["fingers"] if t < 0.5 else max(3, spec["fingers"] - 2)
        for side in (0, 1):
            if t > 0.45 and rng.random() < 0.15:
                continue        # sparse: males drop leaves as they flower
            yaw = phi + side * math.pi
            out = Vector((-math.sin(yaw), math.cos(yaw), 0))
            pet = size * 0.35
            sp = stem_pt(z)
            base = sp + out * pet + Vector((0, 0, pet * 0.3))
            G["stem"].add(*tube_geo(sp, base, 0.005, 0.0035, 4))
            place_leaf(G["leaf"], base, yaw, math.radians(rng.uniform(10, 28)), size, fingers, spec["thin"], 0.9)
        if k >= 1:
            by = phi + math.pi / 2
            bout = Vector((-math.sin(by), math.cos(by), 0))
            bl = reach * (0.9 - 0.3 * t)
            sp = stem_pt(z)
            tip = sp + bout * bl * 0.8 + Vector((0, 0, bl * 0.5))
            G["stem"].add(*tube_geo(sp, tip, 0.007, 0.0035, 4))
            if t > (0.55 if stage == "PreFlower" else 0.2):
                for c in range(2 if stage == "PreFlower" else 4):
                    d = bout * 0.5 + Vector((rng.uniform(-.4, .4), rng.uniform(-.4, .4), rng.uniform(-0.3, 0.4)))
                    add_cluster(G, tip, d, rng.uniform(0.06, 0.10), rng, stage, dens)
            place_leaf(G["leaf"], tip, by + rng.uniform(-.5, .5), math.radians(35), size * 0.45, max(3, fingers - 2), spec["thin"], 0.5)
        if t > 0.4 and stage != "PreFlower":
            for c in range(3):
                a = rng.uniform(0, 2 * math.pi)
                d = Vector((math.cos(a), math.sin(a), rng.uniform(-0.2, 0.3)))
                add_cluster(G, stem_pt(z), d, rng.uniform(0.04, 0.07), rng, stage, dens - 2)
    top = stem_pt(H)
    for s in range(3):
        yaw = s * 2.1 + rng.uniform(0, 0.5)
        place_leaf(G["leaf"], top - Vector((0, 0, H * 0.05)), yaw, math.radians(55), max(0.07, W * 0.18), 5, spec["thin"], 0.2)
    for c in range(4 if stage == "PreFlower" else 9):
        a = c * 2.1 + rng.uniform(0, 0.6)
        d = Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.6))
        add_cluster(G, top - Vector((0, 0, 0.02 * c)), d, rng.uniform(0.05, 0.09), rng, stage, dens)
    return G


def render_male(typ, stage):
    sc = bpy.context.scene
    keep = [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT')]
    for ob in list(bpy.data.objects):
        if ob not in keep:
            bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for ma in list(bpy.data.materials):
        bpy.data.materials.remove(ma)
    G = build_male(typ, stage, zlib.crc32(f"male/{typ}/{stage}".encode()))
    leaf = TYPES[typ]["leaf"]
    if stage == "Ripe":
        leaf = mixc(leaf, (150, 150, 60), 0.35)
    mats = {
        "stem": new_mat("stem", (78, 112, 46), 0.7),
        "leaf": new_mat("leaf", leaf, 0.45, trans=0.3, vein=mixc(leaf, (210, 230, 170), 0.5)),
        "sac": new_mat("sac", (128, 168, 84), 0.5, trans=0.15, bump=0.2),
        "petal": new_mat("petal", (226, 222, 176), 0.6, trans=0.35),
        "anther": new_mat("anther", (226, 196, 80), 0.55),
        "stamen": new_mat("stamen", (210, 200, 150), 0.6),
    }
    for key, geo in G.items():
        if geo.v:
            geo.to_object(key, mats[key])
    os.makedirs(OUT, exist_ok=True)
    sc.render.filepath = os.path.join(OUT, f"male_{typ}_{stage}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered male", typ, stage)


def run_males():
    only = globals().get("DD_ONLY")
    setup_render()
    for typ in TYPE_ORDER:
        for stage in MALE_STAGES:
            if only and f"{typ}_{stage}" not in only:
                continue
            render_male(typ, stage)
    print("DD DONE")


if not globals().get("DD_NO_RUN"):
    run_males()
