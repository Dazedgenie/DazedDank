"""Blender script: renders the 13 cannabis plant layers (seedling + 4 stages x 3 strains) as isometric sprites.
Run inside Blender: exec(open(path).read()). Optional globals before running: DD_SLOTS, DD_SAMPLES, DD_OUT.
"""

import bpy
import math
import random
import os
import zlib
from mathutils import Vector, Matrix

OUT = globals().get("DD_OUT", r"C:\Users\Shado\Zomboid\DazedDank_art\plants")
SLOTS = globals().get("DD_SLOTS", list(range(13)))
SAMPLES = globals().get("DD_SAMPLES", 48)
RES = (512, 1024)           # 4x the 128x256 cell, shrunk by the sprite pipeline
PX_V = 78.4                 # screen pixels (1x) per world unit of height
PX_H = 90.51                # screen pixels (1x) per world unit on the ground
ORTHO = 128.0 / PX_H        # world width covered by the cell
BASE_Y = 226.0              # pixel row where the stem meets the soil

TYPES = {
    "Indica": dict(h=92, w=112, fingers=7, thin=0.30, nodes=6, leaf=(52, 102, 38), bud=(150, 178, 92)),
    "Hybrid": dict(h=122, w=96, fingers=7, thin=0.22, nodes=7, leaf=(66, 128, 44), bud=(165, 190, 96)),
    "Sativa": dict(h=150, w=78, fingers=9, thin=0.15, nodes=8, leaf=(92, 152, 52), bud=(180, 200, 104)),
}
STAGE_SCALE = {"Vegetative": 0.45, "PreFlower": 0.78, "Flowering": 1.0, "Ripe": 1.0}
STAGES = ["Seedling", "Vegetative", "PreFlower", "Flowering", "Ripe"]
TYPE_ORDER = ["Indica", "Sativa", "Hybrid"]
I4 = Matrix.Identity(4)


def lin(rgb):
    return tuple((c / 255.0) ** 2.2 for c in rgb)


def mixc(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# --------------------------------------------------------------------------- geometry

class Geo:
    """Accumulates vertices, faces and per-vertex UVs for one material."""

    def __init__(self):
        self.v, self.f, self.uv = [], [], []

    def add(self, verts, faces, uvs, m=I4):
        base = len(self.v)
        for p, uv in zip(verts, uvs):
            self.v.append(tuple(m @ Vector(p)))
            self.uv.append(uv)
        for f in faces:
            self.f.append(tuple(i + base for i in f))

    def to_object(self, name, mat):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        layer = me.uv_layers.new(name="UVMap")
        for li, loop in enumerate(me.loops):
            layer.data[li].uv = self.uv[loop.vertex_index]
        me.materials.append(mat)
        try:
            me.shade_smooth()
        except Exception:
            for p in me.polygons:
                p.use_smooth = True
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def leaf_geo(n, length, thin, droop):
    """A palmate fan leaf lying in the XY plane, pointing +Y, with serrated leaflets."""
    verts, faces, uvs = [], [], []
    m = max((n - 1) // 2, 1)
    steps = 9
    for j in range(-((n - 1) // 2), (n - 1) // 2 + 1):
        a = math.radians(j * 78.0 / m)
        lf = length * math.cos(abs(j) / m * 1.1)
        half = lf * thin * 0.55
        d = Vector((-math.sin(a), math.cos(a), 0))
        nr = Vector((math.cos(a), math.sin(a), 0))
        base = len(verts)
        for k in range(steps + 1):
            t = k / steps
            w = half * (math.sin(math.pi * t ** 0.7) ** 0.8)
            if k % 2 == 1:
                w *= 0.78
            if k == steps:
                w = 0.0
            r = t * lf + 0.02 * length
            z = -droop * r * r / max(length, 1e-4)
            c = d * r
            verts += [c + nr * w + Vector((0, 0, z + 0.14 * w)), c + Vector((0, 0, z)), c - nr * w + Vector((0, 0, z + 0.14 * w))]
            uvs += [(1.0, t), (0.5, t), (0.0, t)]
        for k in range(steps):
            i = base + k * 3
            i2 = i + 3
            faces.append((i, i + 1, i2 + 1, i2))
            faces.append((i + 1, i + 2, i2 + 2, i2 + 1))
    return verts, faces, uvs


def tube_geo(p0, p1, r0, r1, seg=6):
    p0, p1 = Vector(p0), Vector(p1)
    z = (p1 - p0)
    if z.length < 1e-6:
        z = Vector((0, 0, 1e-4))
    z = z.normalized()
    helper = Vector((1, 0, 0)) if abs(z.x) < 0.9 else Vector((0, 1, 0))
    x = z.cross(helper).normalized()
    y = z.cross(x)
    verts, faces, uvs = [], [], []
    for ring, (p, r) in enumerate(((p0, r0), (p1, r1))):
        for s in range(seg):
            a = 2 * math.pi * s / seg
            verts.append(p + (x * math.cos(a) + y * math.sin(a)) * r)
            uvs.append((s / seg, float(ring)))
    for s in range(seg):
        s2 = (s + 1) % seg
        faces.append((s, s2, seg + s2, seg + s))
    return verts, faces, uvs


def blob_geo(center, radii, rng, jitter=0.12, rings=5, seg=8):
    center = Vector(center)
    verts, faces, uvs = [], [], []
    for r in range(rings + 1):
        th = math.pi * r / rings
        for s in range(seg):
            ph = 2 * math.pi * s / seg
            j = 1 + rng.uniform(-jitter, jitter)
            verts.append(center + Vector((math.sin(th) * math.cos(ph) * radii[0] * j,
                                          math.sin(th) * math.sin(ph) * radii[1] * j,
                                          math.cos(th) * radii[2] * j)))
            uvs.append((s / seg, r / rings))
    for r in range(rings):
        for s in range(seg):
            s2 = (s + 1) % seg
            faces.append((r * seg + s, r * seg + s2, (r + 1) * seg + s2, (r + 1) * seg + s))
    return verts, faces, uvs


# --------------------------------------------------------------------------- materials

def new_mat(name, col, rough=0.55, trans=0.0, vein=None, frost=0.0, patch=0.12, metal=0.0, bump=0.0, scale=7.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    N, L = nt.nodes, nt.links
    N.clear()
    out = N.new('ShaderNodeOutputMaterial')
    bsdf = N.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    tc = N.new('ShaderNodeTexCoord')
    noise = N.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = scale
    L.new(tc.outputs['Object'], noise.inputs['Vector'])
    if bump > 0:
        bp = N.new('ShaderNodeBump')
        bp.inputs['Strength'].default_value = bump
        bp.inputs['Distance'].default_value = 0.02
        L.new(noise.outputs['Fac'], bp.inputs['Height'])
        L.new(bp.outputs['Normal'], bsdf.inputs['Normal'])
    ramp = N.new('ShaderNodeValToRGB')
    c = lin(col)
    ramp.color_ramp.elements[0].color = tuple(x * (1 - patch * 1.6) for x in c) + (1,)
    ramp.color_ramp.elements[1].color = tuple(min(1, x * (1 + patch * 1.6)) for x in c) + (1,)
    L.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    color_out = ramp.outputs['Color']
    if vein:
        sep = N.new('ShaderNodeSeparateXYZ')
        L.new(tc.outputs['UV'], sep.inputs['Vector'])
        sub = N.new('ShaderNodeMath')
        sub.operation = 'SUBTRACT'
        L.new(sep.outputs['X'], sub.inputs[0])
        sub.inputs[1].default_value = 0.5
        ab = N.new('ShaderNodeMath')
        ab.operation = 'ABSOLUTE'
        L.new(sub.outputs[0], ab.inputs[0])
        lt = N.new('ShaderNodeMath')
        lt.operation = 'LESS_THAN'
        L.new(ab.outputs[0], lt.inputs[0])
        lt.inputs[1].default_value = 0.05
        mx = N.new('ShaderNodeMix')
        mx.data_type = 'RGBA'
        L.new(lt.outputs[0], mx.inputs[0])
        L.new(color_out, mx.inputs[6])
        mx.inputs[7].default_value = lin(vein) + (1,)
        color_out = mx.outputs[2]
    if frost > 0:
        n2 = N.new('ShaderNodeTexNoise')
        n2.inputs['Scale'].default_value = 260.0
        n2.inputs['Detail'].default_value = 2.0
        L.new(tc.outputs['Object'], n2.inputs['Vector'])
        r2 = N.new('ShaderNodeValToRGB')
        r2.color_ramp.elements[0].position = 0.55
        r2.color_ramp.elements[1].position = 0.62
        L.new(n2.outputs['Fac'], r2.inputs['Fac'])
        m2 = N.new('ShaderNodeMath')
        m2.operation = 'MULTIPLY'
        L.new(r2.outputs['Color'], m2.inputs[0])
        m2.inputs[1].default_value = frost
        mx2 = N.new('ShaderNodeMix')
        mx2.data_type = 'RGBA'
        L.new(m2.outputs[0], mx2.inputs[0])
        L.new(color_out, mx2.inputs[6])
        mx2.inputs[7].default_value = (0.95, 0.97, 0.9, 1)
        color_out = mx2.outputs[2]
    L.new(color_out, bsdf.inputs['Base Color'])
    surf = bsdf.outputs['BSDF']
    if trans > 0:
        tr = N.new('ShaderNodeBsdfTranslucent')
        L.new(color_out, tr.inputs['Color'])
        ms = N.new('ShaderNodeMixShader')
        ms.inputs[0].default_value = trans
        L.new(bsdf.outputs['BSDF'], ms.inputs[1])
        L.new(tr.outputs['BSDF'], ms.inputs[2])
        surf = ms.outputs['Shader']
    L.new(surf, out.inputs['Surface'])
    return mat


# --------------------------------------------------------------------------- plant

def place_leaf(G, base, yaw, tilt, size, fingers, thin, droop):
    v, f, u = leaf_geo(fingers, size, thin, droop)
    G.add(v, f, u, Matrix.Translation(base) @ Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Rotation(tilt, 4, 'X'))


def add_bud(Gb, Gp, Gl, origin, direction, length, width, rng, ripe):
    """One cola: a spindle of lumpy calyx blobs with pistils and a few sugar leaves."""
    M = Matrix.Translation(origin) @ direction.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
    levels = max(3, int(length / (width * 0.5)))
    for i in range(levels):
        t = (i + 0.5) / levels
        r = width * 0.5 * (math.sin(math.pi * (0.16 + 0.8 * t)) ** 0.6) * (1.12 if ripe else 1.0)
        z = length * t
        count = 5 if r > 0.02 else 3
        v, f, u = blob_geo((0, 0, z), (r * 0.75, r * 0.75, r * 0.85), rng, 0.12)
        Gb.add(v, f, u, M)
        for s in range(count):
            a = 2 * math.pi * s / count + rng.uniform(0, 0.6) + i * 0.8
            c = Vector((math.cos(a) * r * 0.6, math.sin(a) * r * 0.6, z + rng.uniform(-0.01, 0.01) * length))
            rad = r * rng.uniform(0.5, 0.7)
            v, f, u = blob_geo(c, (rad, rad, rad * 1.15), rng, 0.15)
            Gb.add(v, f, u, M)
            for _ in range(2):
                o = Vector((math.cos(a) + rng.uniform(-.3, .3), math.sin(a) + rng.uniform(-.3, .3), 0.4)).normalized()
                p0 = c + o * rad * 0.8
                p1 = p0 + o * rad * rng.uniform(0.3, 0.7) + Vector((0, 0, rad * 0.3))
                Gp.add(*tube_geo(p0, p1, 0.0035, 0.0012, 3), m=M)
    for s in range(4):
        a = s * math.pi / 2 + rng.uniform(-0.4, 0.4)
        z = length * rng.uniform(0.1, 0.5)
        local = Matrix.Translation(Vector((0, 0, z))) @ Matrix.Rotation(a, 4, 'Z') @ Matrix.Rotation(math.radians(58), 4, 'X')
        v, f, u = leaf_geo(3, width * 0.9, 0.26, 0.4)
        Gl.add(v, f, u, M @ local)


def build_seedling(G):
    rng = random.Random(7)
    Gs, Gl = G["stem"], G["leaf"]
    Gs.add(*tube_geo((0, 0, 0), (0, 0, 0.17), 0.012, 0.008, 6))
    for side in (-1, 1):
        v, f, u = blob_geo((side * 0.07, 0, 0.16), (0.065, 0.04, 0.012), rng, 0.0)
        G["cot"].add(v, f, u)
    for yaw in (0.0, math.pi):
        place_leaf(Gl, Vector((0, 0, 0.18)), yaw + math.radians(90), math.radians(28), 0.11, 3, 0.34, 0.3)


def build_plant(typ, stage, seed):
    rng = random.Random(seed)
    G = {k: Geo() for k in ("stem", "leaf", "bud", "pist", "cot", "sugar")}
    if stage == "Seedling":
        build_seedling(G)
        return G
    spec = TYPES[typ]
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
    sites = []                      # (position, outward direction, t) for buds
    for k in range(nodes):
        t = (k + 0.7) / (nodes + 0.5)
        z = H * 0.12 + H * 0.83 * t
        phi = k * math.pi / 2 + rng.uniform(-0.2, 0.2)
        reach = W * 0.5 * (1 - t * (0.55 if typ == "Indica" else 0.75))
        size = max(0.1, reach * 0.9) * rng.uniform(0.9, 1.1)
        fingers = spec["fingers"] if t < 0.6 else max(3, spec["fingers"] - 2)
        for side in (0, 1):
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
    # apex leaves
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
        w_main = (10 if typ == "Indica" else 7.5 if typ == "Hybrid" else 6) * fat / PX_H * 1.2
        l_main = H * (0.36 if typ == "Indica" else 0.34 if typ == "Hybrid" else 0.32)
        for tip, out, t in sites:
            if t > 0.3:
                f = 0.45 + 0.4 * t
                add_bud(G["bud"], G["pist"], G["sugar"], tip, out * 0.35 + Vector((0, 0, 1)), l_main * f, w_main * f, rng, ripe)
        add_bud(G["bud"], G["pist"], G["sugar"], top - Vector((0, 0, l_main * 0.8)), Vector((0, 0, 1)), l_main, w_main, rng, ripe)
    return G


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for ma in list(bpy.data.materials):
        bpy.data.materials.remove(ma)


def setup_render():
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    cd = bpy.data.cameras.new("ddcam")
    cd.type = 'ORTHO'
    cd.ortho_scale = ORTHO
    cd.sensor_fit = 'HORIZONTAL'
    cd.shift_y = ((BASE_Y - 128.0) / PX_H) / ORTHO
    cd.clip_end = 200
    cam = bpy.data.objects.new("ddcam", cd)
    sc.collection.objects.link(cam)
    pos = Vector((0.612, 0.612, 0.5)) * 40
    cam.location = pos
    cam.rotation_euler = (-pos).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sd = bpy.data.lights.new("ddsun", 'SUN')
    sd.energy = 4.0
    sd.angle = math.radians(14)
    sun = bpy.data.objects.new("ddsun", sd)
    sc.collection.objects.link(sun)
    sun.rotation_euler = Vector((0.636, -0.141, 1.0)).normalized().to_track_quat('Z', 'Y').to_euler()
    w = bpy.data.worlds.get("ddworld") or bpy.data.worlds.new("ddworld")
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.55, 0.66, 0.85, 1)
    bg.inputs[1].default_value = 0.7
    sc.world = w


def render_slot(slot, typ, stage):
    sc = bpy.context.scene
    keep = [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT')]
    for ob in list(bpy.data.objects):
        if ob not in keep:
            bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for ma in list(bpy.data.materials):
        bpy.data.materials.remove(ma)
    seed = zlib.crc32(f"{typ}/{stage}".encode())
    G = build_plant(typ, stage, seed)
    spec = TYPES[typ if stage != "Seedling" else "Hybrid"]
    leaf = spec["leaf"]
    if stage == "Ripe":
        leaf = mixc(leaf, (150, 150, 60), 0.30)
    pist = {"PreFlower": (240, 238, 228), "Flowering": (236, 150, 60), "Ripe": (196, 96, 36)}.get(stage, (240, 238, 228))
    mats = {
        "stem": new_mat("stem", (78, 112, 46), 0.7),
        "leaf": new_mat("leaf", leaf, 0.45, trans=0.3, vein=mixc(leaf, (210, 230, 170), 0.5)),
        "cot": new_mat("cot", (110, 160, 70), 0.5, trans=0.2),
        "bud": new_mat("bud", mixc(spec["bud"], (60, 100, 40), 0.45), 0.55, frost=0.22 if stage == "Flowering" else 0.4 if stage == "Ripe" else 0.0),
        "pist": new_mat("pist", pist, 0.6),
        "sugar": new_mat("sugar", mixc(spec["bud"], leaf, 0.4), 0.5, trans=0.2),
    }
    for key, geo in G.items():
        if geo.v:
            geo.to_object(key, mats[key])
    os.makedirs(OUT, exist_ok=True)
    sc.render.filepath = os.path.join(OUT, f"slot_{slot:02d}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", slot, typ, stage)


def main():
    setup_render()
    for stage in STAGES:
        for t in (["Hybrid"] if stage == "Seedling" else TYPE_ORDER):
            slot = 0 if stage == "Seedling" else 1 + TYPE_ORDER.index(t) * 4 + (STAGES.index(stage) - 1)
            if slot in SLOTS:
                render_slot(slot, t, stage)
    print("DD DONE")


if not globals().get("DD_NO_MAIN"):
    main()
