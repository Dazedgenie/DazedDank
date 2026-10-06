"""Blender script: renders the 7 plant shapes (4 stages each), their males (3 stages) and the 4 bud colours
(flowering and ripe) as isometric plant layers for tools/make_overlay_sprites.py.
Run inside Blender: exec(open(path).read()). Reuses render_plants.py and render_males.py from DD_ART_DIR.
Optional globals: DD_SAMPLES, DD_OUT (default <art dir>/shapes), DD_ONLY (list of output names without .png).
"""

import os

DD_NO_MAIN = True
DD_NO_RUN = True
ART_DIR = globals().get("DD_ART_DIR", r"C:\Users\Shado\Zomboid\DazedDank_art")
exec(open(os.path.join(ART_DIR, "render_plants.py")).read(), globals())
exec(open(os.path.join(ART_DIR, "render_males.py")).read(), globals())
OUT = globals().get("DD_OUT", os.path.join(ART_DIR, "shapes"))

# Body plans. h/w are pixel sizes at full flower; taper is how much shorter the top branches reach (a cone near 1);
# bud_w and bud_len set the main colas (haze runs long and thin, afghan short and fat).
SHAPES = {
    "landrace": dict(h=162, w=74, fingers=9, thin=0.13, nodes=9, taper=0.8, bud_w=5.5, bud_len=0.30, sparse=0.35,
                     leaf=(96, 156, 54), bud=(182, 202, 106)),
    "haze":     dict(h=150, w=84, fingers=9, thin=0.15, nodes=8, taper=0.75, bud_w=5.0, bud_len=0.42, sparse=0.2,
                     leaf=(88, 150, 50), bud=(178, 198, 100)),
    "hybrid":   dict(h=122, w=96, fingers=7, thin=0.22, nodes=7, taper=0.75, bud_w=7.5, bud_len=0.34, sparse=0.0,
                     leaf=(66, 128, 44), bud=(165, 190, 96)),
    "kush":     dict(h=96, w=110, fingers=7, thin=0.30, nodes=6, taper=0.55, bud_w=10.0, bud_len=0.36, sparse=0.0,
                     leaf=(52, 102, 38), bud=(150, 178, 92)),
    "afghan":   dict(h=84, w=128, fingers=5, thin=0.38, nodes=6, taper=0.45, bud_w=11.5, bud_len=0.30, sparse=0.0,
                     leaf=(44, 92, 34), bud=(146, 172, 88)),
    "auto":     dict(h=66, w=70, fingers=5, thin=0.26, nodes=5, taper=0.6, bud_w=7.0, bud_len=0.38, sparse=0.1,
                     leaf=(80, 140, 50), bud=(170, 194, 100)),
    "tree":     dict(h=132, w=118, fingers=7, thin=0.24, nodes=8, taper=0.95, bud_w=8.5, bud_len=0.40, sparse=0.0,
                     leaf=(60, 120, 42), bud=(160, 186, 94)),
}
TYPES.update(SHAPES)
SHAPE_ORDER = ["landrace", "haze", "hybrid", "kush", "afghan", "auto", "tree"]
FEMALE_STAGES = ["Vegetative", "PreFlower", "Flowering", "Ripe"]

# Colour phenotypes: what changes on the leaves, buds, sugar leaves and pistils late in flower.
COLOURS = {
    "purple": dict(leaf_mix=((84, 52, 96), 0.35), bud=(118, 62, 146), sugar=(92, 48, 112), pist=(232, 140, 70), frost=0.3),
    "frosty": dict(leaf_mix=((190, 205, 180), 0.12), bud=(206, 220, 196), sugar=(186, 204, 176), pist=(240, 236, 220), frost=0.9),
    "gold":   dict(leaf_mix=((168, 200, 60), 0.45), bud=(206, 192, 92), sugar=(186, 196, 80), pist=(236, 150, 40), frost=0.25),
    "dark":   dict(leaf_mix=((26, 52, 28), 0.6), bud=(64, 94, 52), sugar=(42, 70, 38), pist=(190, 110, 60), frost=0.2),
}


def build_shape(shape, stage, seed):
    """A female plant of one body plan: the original builder with the shape's taper and cola sizes."""
    rng = random.Random(seed)
    G = {k: Geo() for k in ("stem", "leaf", "bud", "pist", "cot", "sugar")}
    spec = SHAPES[shape]
    scale = STAGE_SCALE[stage]
    H = spec["h"] / PX_V * scale
    W = spec["w"] / PX_H * scale
    ripe = stage == "Ripe"
    sway = Vector((rng.uniform(-0.04, 0.04) * H, rng.uniform(-0.04, 0.04) * H, 0))

    def stem_pt(z):
        t = z / H
        return Vector((sway.x * t * t, sway.y * t * t, z))

    segs = 8
    for i in range(segs):
        r0 = (0.034 - 0.026 * i / segs) * (0.55 + 0.45 * scale)
        r1 = (0.034 - 0.026 * (i + 1) / segs) * (0.55 + 0.45 * scale)
        G["stem"].add(*tube_geo(stem_pt(H * i / segs), stem_pt(H * (i + 1) / segs), r0, r1, 6))

    nodes = max(3, int(spec["nodes"] * (0.6 + 0.4 * scale)))
    flowering = stage in ("Flowering", "Ripe")
    sites = []
    for k in range(nodes):
        t = (k + 0.7) / (nodes + 0.5)
        z = H * 0.12 + H * 0.83 * t
        phi = k * math.pi / 2 + rng.uniform(-0.2, 0.2)
        reach = W * 0.5 * (1 - t * spec["taper"])
        size = max(0.1, reach * 0.9) * rng.uniform(0.9, 1.1)
        fingers = spec["fingers"] if t < 0.6 else max(3, spec["fingers"] - 2)
        for side in (0, 1):
            if rng.random() < spec["sparse"] * t:
                continue
            yaw = phi + side * math.pi
            out = Vector((-math.sin(yaw), math.cos(yaw), 0))
            pet = size * 0.3
            sp = stem_pt(z)
            base = sp + out * pet + Vector((0, 0, pet * 0.3))
            G["stem"].add(*tube_geo(sp, base, 0.006, 0.004, 4))
            place_leaf(G["leaf"], base, yaw, math.radians(rng.uniform(8, 25)), size, fingers, spec["thin"], 0.9)
        if k >= 1 and (rng.random() < 0.8 or flowering):
            by = phi + math.pi / 2
            bout = Vector((-math.sin(by), math.cos(by), 0))
            bl = reach * (0.85 - 0.3 * t)
            sp = stem_pt(z)
            tip = sp + bout * bl * 0.75 + Vector((0, 0, bl * 0.55))
            G["stem"].add(*tube_geo(sp, tip, 0.008, 0.004, 4))
            place_leaf(G["leaf"], tip, by + rng.uniform(-.5, .5), math.radians(35), size * 0.55, max(3, fingers - 2), spec["thin"], 0.5)
            sites.append((tip, bout, t))
    top = stem_pt(H)
    for s in range(3):
        yaw = s * 2.1 + rng.uniform(0, 0.5)
        place_leaf(G["leaf"], top - Vector((0, 0, H * 0.04)), yaw, math.radians(55), max(0.08, W * 0.2), 5, spec["thin"], 0.2)

    if stage == "PreFlower":
        for tip, out, t in sites:
            if t > 0.45:
                add_bud(G["bud"], G["pist"], G["sugar"], tip, out * 0.3 + Vector((0, 0, 1)), 0.09, 0.05, rng, False)
        add_bud(G["bud"], G["pist"], G["sugar"], top - Vector((0, 0, 0.07)), Vector((0, 0, 1)), 0.14, 0.07, rng, False)
    elif flowering:
        fat = 1.25 if ripe else 1.0
        w_main = spec["bud_w"] * fat / PX_H * 1.2
        l_main = H * spec["bud_len"]
        for tip, out, t in sites:
            if t > 0.3:
                f = 0.45 + 0.4 * t
                add_bud(G["bud"], G["pist"], G["sugar"], tip, out * 0.35 + Vector((0, 0, 1)), l_main * f, w_main * f, rng, ripe)
        add_bud(G["bud"], G["pist"], G["sugar"], top - Vector((0, 0, l_main * 0.8)), Vector((0, 0, 1)), l_main, w_main, rng, ripe)
    return G


def clear_meshes():
    keep = [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT')]
    for ob in list(bpy.data.objects):
        if ob not in keep:
            bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for ma in list(bpy.data.materials):
        bpy.data.materials.remove(ma)


def render_female(shape, stage, colour=None):
    """One female layer; `colour` swaps the late-flower materials for a colour phenotype."""
    clear_meshes()
    spec = SHAPES[shape]
    G = build_shape(shape, stage, zlib.crc32(f"{shape}/{stage}".encode()))
    leaf = spec["leaf"]
    if stage == "Ripe":
        leaf = mixc(leaf, (150, 150, 60), 0.30)
    pist = {"PreFlower": (240, 238, 228), "Flowering": (236, 150, 60), "Ripe": (196, 96, 36)}.get(stage, (240, 238, 228))
    bud = mixc(spec["bud"], (60, 100, 40), 0.45)
    sugar = mixc(spec["bud"], leaf, 0.4)
    frost = 0.22 if stage == "Flowering" else 0.4 if stage == "Ripe" else 0.0
    if colour:
        c = COLOURS[colour]
        leaf = mixc(leaf, c["leaf_mix"][0], c["leaf_mix"][1] * (1.0 if stage == "Ripe" else 0.7))
        bud, sugar, pist = c["bud"], c["sugar"], c["pist"]
        frost = max(frost, c["frost"] * (1.0 if stage == "Ripe" else 0.75))
    mats = {
        "stem": new_mat("stem", (78, 112, 46), 0.7),
        "leaf": new_mat("leaf", leaf, 0.45, trans=0.3, vein=mixc(leaf, (210, 230, 170), 0.5)),
        "cot": new_mat("cot", (110, 160, 70), 0.5, trans=0.2),
        "bud": new_mat("bud", bud, 0.55, frost=frost),
        "pist": new_mat("pist", pist, 0.6),
        "sugar": new_mat("sugar", sugar, 0.5, trans=0.2, frost=frost * 0.6),
    }
    for key, geo in G.items():
        if geo.v:
            geo.to_object(key, mats[key])
    name = f"colour_{colour}_{shape}_{stage}" if colour else f"shape_{shape}_{stage}"
    write(name)


def render_shape_male(shape, stage):
    clear_meshes()
    G = build_male(shape, stage, zlib.crc32(f"male/{shape}/{stage}".encode()))
    leaf = SHAPES[shape]["leaf"]
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
    write(f"male_{shape}_{stage}")


def write(name):
    os.makedirs(OUT, exist_ok=True)
    bpy.context.scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


def jobs():
    out = []
    for shape in SHAPE_ORDER:
        for stage in FEMALE_STAGES:
            out.append((f"shape_{shape}_{stage}", lambda s=shape, st=stage: render_female(s, st)))
        for stage in MALE_STAGES:
            out.append((f"male_{shape}_{stage}", lambda s=shape, st=stage: render_shape_male(s, st)))
        for colour in COLOURS:
            for stage in ("Flowering", "Ripe"):
                out.append((f"colour_{colour}_{shape}_{stage}", lambda s=shape, st=stage, c=colour: render_female(s, st, c)))
    return out


def run_shapes():
    only = globals().get("DD_ONLY")
    skip_done = globals().get("DD_SKIP_DONE", True)
    setup_render()
    for name, job in jobs():
        if only and name not in only:
            continue
        if skip_done and not only and os.path.exists(os.path.join(OUT, name + ".png")):
            continue
        job()
    print("DD DONE")


if not globals().get("DD_SHAPES_NO_RUN"):
    run_shapes()
