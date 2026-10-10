"""DazedDank plant layers, v2 ("in-between" style): every female shape/stage, male and colour phenotype as a
512x1024 isometric layer for tools/make_overlay_sprites.py (106 renders: seedling, 7 shapes x 4 stages, 7 x 3 males,
4 colours x 7 shapes x flowering/ripe).

Camera and anchor are render_plants.py's (ortho 2:1, 512x1024 for the 128x256 cell, stem base at 1x row 226, PX_V/PX_H
scale), so a layer drops into the same overlay slot. Lighting is DazedPower's dz_render.py rig (sky fill 0.85, key sun
2.7 / 12 deg, rim sun 0.7 without shadow, exposure -0.1, Standard view), turned 90 deg about Z to sit the same way
relative to Dank's camera. Plants are built for real: serrated fan leaves (alpha cards with tools/blender/
plant_textures.py textures), decussate then alternate phyllotaxis, a branch in every leaf axil, colas of calyx
clusters with pistils (white -> orange) and frosty sugar leaves, late-flower fade on the old fan leaves. The 7 body
plans and 4 colours are render_shapes.py's; males hang pale pollen-sac clusters (open flowers when ripe).
Style "bold" (default, the chosen "in-between" look) has bigger, broader, greener leaves than "real".

    python3 tools/blender/plant_textures.py tools/blender/shapes/tex
    blender -b --factory-startup -P tools/blender/render_plants_v2.py -- tools/blender/shapes/tex build/plants all
        (or: python tools/blender/render_plants_v2.py -- ... with the pip bpy module)
    python3 tools/blender/plants_v2_post.py build/plants          # Power grade -> tools/blender/shapes/<name>.png
    python3 tools/make_overlay_sprites.py                          # rebuilds overlay_01 / overlay_02

Jobs: all, or names like shape_kush_Ripe, male_haze_Flowering, colour_purple_auto_Ripe, seedling. Env: DD_SAMPLES
(64), DD_STYLE (bold|real), FORCE=1 re-renders existing outputs. About 45 s a render on a 4-core CPU.
"""
import bpy, math, os, random, sys, time
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TEX, OUT = ARGS[0], ARGS[1]
STYLE = os.environ.get("DD_STYLE", "bold")
SAMPLES = int(os.environ.get("DD_SAMPLES", "64"))
RES = (512, 1024)
PX_V, PX_H = 78.4, 90.51
ORTHO = 128.0 / PX_H
BASE_Y = 226.0
I4 = Matrix.Identity(4)


def lin(rgb):
    return tuple((c / 255.0) ** 2.2 for c in rgb) + (1.0,)


# ------------------------------------------------------------------ scene (Dank camera, Power lights)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 6
sc.cycles.diffuse_bounces = 2
sc.cycles.glossy_bounces = 1
sc.cycles.transmission_bounces = 2
sc.cycles.transparent_max_bounces = 24
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.render.film_transparent = True
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.view_settings.view_transform = 'Standard'
try:
    sc.view_settings.look = 'None'
except Exception:
    pass
sc.view_settings.exposure = -0.1

cd = bpy.data.cameras.new("cam")
cd.type = 'ORTHO'
cd.ortho_scale = ORTHO
cd.sensor_fit = 'HORIZONTAL'
cd.shift_y = ((BASE_Y - 128.0) / PX_H) / ORTHO
cd.clip_end = 200
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
pos = Vector((0.612, 0.612, 0.5)) * 40
cam.location = pos
cam.rotation_euler = (-pos).to_track_quat('-Z', 'Y').to_euler()
sc.camera = cam

world = bpy.data.worlds.new("W")
sc.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.62, 0.66, 0.72, 1)
bg.inputs[1].default_value = 0.85


def sun(name, toward_light, energy, angle, shadows=True):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = energy
    ld.angle = math.radians(angle)
    try:
        ld.use_shadow = shadows
    except Exception:
        pass
    ob = bpy.data.objects.new(name, ld)
    sc.collection.objects.link(ob)
    ob.rotation_euler = Vector((0, 0, 1)).rotation_difference(Vector(toward_light).normalized()).to_euler()


# Power's Key (-0.55,-1,1.55) and Rim (1,0.35,0.8), rotated +90 deg about Z to Dank's camera side
sun("Key", (1.0, -0.55, 1.55), 2.7, 12)
sun("Rim", (-0.35, 1.0, 0.8), 0.7, 30, shadows=False)


# ------------------------------------------------------------------ materials
MATS = {}


def solid_mat(name, col, rough=0.6, frost=0.0, frost_col=(236, 238, 226), sheen=0.0, bump=0.0, var=0.12, scale=60.0,
              trans=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    N, L = m.node_tree.nodes, m.node_tree.links
    N.clear()
    out = N.new('ShaderNodeOutputMaterial')
    bs = N.new('ShaderNodeBsdfPrincipled')
    bs.inputs['Roughness'].default_value = rough
    tc = N.new('ShaderNodeTexCoord')
    nz = N.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = scale; nz.inputs['Detail'].default_value = 3.0
    L.new(tc.outputs['Object'], nz.inputs['Vector'])
    rp = N.new('ShaderNodeValToRGB')
    c = lin(col)
    rp.color_ramp.elements[0].color = tuple(x * (1 - var * 1.6) for x in c[:3]) + (1,)
    rp.color_ramp.elements[1].color = tuple(min(1, x * (1 + var * 1.6)) for x in c[:3]) + (1,)
    L.new(nz.outputs['Fac'], rp.inputs['Fac'])
    colo = rp.outputs['Color']
    if frost > 0:
        n2 = N.new('ShaderNodeTexVoronoi'); n2.inputs['Scale'].default_value = 900.0
        L.new(tc.outputs['Object'], n2.inputs['Vector'])
        r2 = N.new('ShaderNodeValToRGB')
        r2.color_ramp.elements[0].position = 0.0; r2.color_ramp.elements[0].color = (1, 1, 1, 1)
        r2.color_ramp.elements[1].position = 0.22 + 0.25 * min(frost, 1.0); r2.color_ramp.elements[1].color = (0, 0, 0, 1)
        L.new(n2.outputs['Distance'], r2.inputs['Fac'])
        mul = N.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = min(1.0, frost)
        L.new(r2.outputs['Color'], mul.inputs[0])
        mx = N.new('ShaderNodeMix'); mx.data_type = 'RGBA'
        L.new(mul.outputs[0], mx.inputs[0]); L.new(colo, mx.inputs[6]); mx.inputs[7].default_value = lin(frost_col)
        colo = mx.outputs[2]
        bp = N.new('ShaderNodeBump'); bp.inputs['Strength'].default_value = 0.35 * min(frost, 1.0)
        bp.inputs['Distance'].default_value = 0.002
        L.new(r2.outputs['Color'], bp.inputs['Height']); L.new(bp.outputs['Normal'], bs.inputs['Normal'])
        # trichome heads catch light: a little less rough where frosted
        rr = N.new('ShaderNodeMapRange'); rr.inputs['To Min'].default_value = rough; rr.inputs['To Max'].default_value = 0.28
        L.new(mul.outputs[0], rr.inputs['Value']); L.new(rr.outputs['Result'], bs.inputs['Roughness'])
    elif bump > 0:
        bp = N.new('ShaderNodeBump'); bp.inputs['Strength'].default_value = bump; bp.inputs['Distance'].default_value = 0.003
        L.new(nz.outputs['Fac'], bp.inputs['Height']); L.new(bp.outputs['Normal'], bs.inputs['Normal'])
    L.new(colo, bs.inputs['Base Color'])
    if sheen > 0:
        try:
            bs.inputs['Sheen Weight'].default_value = sheen
            bs.inputs['Sheen Tint'].default_value = lin((235, 240, 225))
            bs.inputs['Sheen Roughness'].default_value = 0.4
        except Exception:
            pass
    surf = bs.outputs[0]
    if trans > 0:
        tr = N.new('ShaderNodeBsdfTranslucent'); L.new(colo, tr.inputs['Color'])
        mx = N.new('ShaderNodeMixShader'); mx.inputs[0].default_value = trans
        L.new(surf, mx.inputs[1]); L.new(tr.outputs[0], mx.inputs[2]); surf = mx.outputs[0]
    L.new(surf, out.inputs['Surface'])
    MATS[name] = m
    return m


# ------------------------------------------------------------------ geometry accumulators
class Geo:
    def __init__(self):
        self.v, self.f, self.uv = [], [], []

    def add(self, verts, faces, uvs, m=I4):
        b = len(self.v)
        for p, uv in zip(verts, uvs):
            self.v.append(tuple(m @ Vector(p)))
            self.uv.append(uv)
        for f in faces:
            self.f.append(tuple(i + b for i in f))

    def build(self, name, mat, smooth=True):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        lay = me.uv_layers.new(name="UVMap")
        for li, lp in enumerate(me.loops):
            lay.data[li].uv = self.uv[lp.vertex_index]
        me.materials.append(mat)
        if smooth:
            me.shade_smooth()
        ob = bpy.data.objects.new(name, me)
        sc.collection.objects.link(ob)
        return ob


GEO = {}


def geo(key):
    if key not in GEO:
        GEO[key] = Geo()
    return GEO[key]


def card(R, droop, cup, curl, n=8):
    """A square leaf card, centre at the origin, forward +Y. Leaflets droop with distance from the centre."""
    verts, faces, uvs = [], [], []
    for j in range(n + 1):
        for i in range(n + 1):
            u, v = i / n, j / n
            x, y = (u - 0.5) * 2 * R, (v - 0.5) * 2 * R
            r = math.hypot(x, y) / R
            z = -droop * R * r * r + cup * R * (abs(x) / R) * 0.25 + curl * R * (x / R) * r * 0.2
            verts.append((x, y, z))
            uvs.append((u, v))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + 1, a + n + 2, a + n + 1))
    return verts, faces, uvs


def tube(pts, radii, seg=7):
    """A tube through points with per-point radii."""
    pts = [Vector(p) for p in pts]
    verts, faces, uvs = [], [], []
    prev_x = None
    for k, p in enumerate(pts):
        d = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)])
        d = d.normalized() if d.length > 1e-9 else Vector((0, 0, 1))
        if prev_x is None:
            h = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0))
            x = d.cross(h).normalized()
        else:
            x = (prev_x - d * prev_x.dot(d)).normalized()
        y = d.cross(x)
        prev_x = x
        for s in range(seg):
            a = 2 * math.pi * s / seg
            verts.append(tuple(p + (x * math.cos(a) + y * math.sin(a)) * radii[k]))
            uvs.append((s / seg, k / max(1, len(pts) - 1)))
    for k in range(len(pts) - 1):
        for s in range(seg):
            s2 = (s + 1) % seg
            faces.append((k * seg + s, k * seg + s2, (k + 1) * seg + s2, (k + 1) * seg + s))
    return verts, faces, uvs


def _sphere(seg=8, rings=6):
    verts, faces, uvs = [], [], []
    for r in range(rings + 1):
        th = math.pi * r / rings
        for s in range(seg):
            ph = 2 * math.pi * s / seg
            verts.append((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
            uvs.append((s / seg, r / rings))
    for r in range(rings):
        for s in range(seg):
            s2 = (s + 1) % seg
            faces.append((r * seg + s, r * seg + s2, (r + 1) * seg + s2, (r + 1) * seg + s))
    return verts, faces, uvs


SPH = _sphere()


def frame(direction):
    """Rotation taking +Z to direction."""
    return Vector(direction).normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()


def ellipsoid(key, c, d, rx, rz, rng):
    v, f, u = SPH
    vv = []
    for p in v:
        k = 1 + rng.uniform(-0.08, 0.08)
        # teardrop: pointier toward +Z
        z = p[2]
        w = (1 - 0.35 * max(0.0, z))
        vv.append((p[0] * rx * w * k, p[1] * rx * w * k, z * rz * k))
    geo(key).add(vv, f, u, Matrix.Translation(Vector(c)) @ frame(d))


# ------------------------------------------------------------------ plant parts
VIEW = Vector((0.612, 0.612, 0.5)).normalized()       # towards the camera
def leaf(tex, base, yaw, tilt, R, droop, rng, cup=0.15, roll=0.0):
    """Place a fan-leaf card: centre at base, forward along yaw (0 = +Y), pitched up by tilt."""
    v, f, u = card(R, droop, cup, rng.uniform(-0.3, 0.3))
    # a card seen edge-on reads as a pale strip: nudge tilt/roll until it shows enough of its face to the camera
    best, bf = None, -1.0
    for dt, dr in ((0, 0), (0.25, 0), (-0.25, 0), (0, 0.4), (0, -0.4), (0.45, 0.35), (0.45, -0.35), (-0.45, 0.45), (-0.45, -0.45)):
        M = (Matrix.Translation(Vector(base)) @ Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Rotation(tilt + dt, 4, 'X')
             @ Matrix.Rotation(roll + dr, 4, 'Y'))
        fc = abs((M.to_3x3() @ Vector((0, 0, 1))).normalized().dot(VIEW))
        if fc > bf:
            best, bf = M, fc
        if fc >= 0.4:
            break
    geo("L:" + tex).add(v, f, u, best)


def petiole_leaf(node, out_dir, R, tex, rng, rise=0.35, tilt=None, droop=0.45, stem_key="stem"):
    out = Vector(out_dir).normalized()
    pl = R * 0.75
    mid = Vector(node) + out * pl * 0.55 + Vector((0, 0, pl * rise))
    end = Vector(node) + out * pl + Vector((0, 0, pl * rise * 1.2))
    geo(stem_key).add(*tube([node, mid, end], [0.0065, 0.005, 0.004], 5))
    yaw = math.atan2(-out.x, out.y) + rng.uniform(-0.2, 0.2)
    # leaf centre a little past the petiole tip; card's unused rear half hides behind
    leaf(tex, end, yaw, math.radians(tilt if tilt is not None else rng.uniform(12, 30)), R, droop, rng,
         roll=rng.uniform(-0.25, 0.25))


def cola(p0, p1, width, st, rng, sugar_tex, n_calyx=11, sugar_rate=1.0):
    """A cola from p0 (base) to p1 (tip): dense stacked calyx clusters, pistils, frosty sugar leaves."""
    p0, p1 = Vector(p0), Vector(p1)
    ax = (p1 - p0)
    Lc = ax.length
    ax.normalize()
    hx = Vector((1, 0, 0)) if abs(ax.x) < 0.9 else Vector((0, 1, 0))
    bx = ax.cross(hx).normalized()
    by = ax.cross(bx)
    fat = st["fat"]
    R0 = width * 0.5 * fat
    step = R0 * 0.5
    nn = max(2, int(Lc / step))
    for i in range(nn + 1):
        t = i / nn
        # spear profile: full through the lower two thirds, tapering to a rounded tip; lumpy
        prof = (0.75 + 0.25 * math.sin(math.pi * min(1.0, 0.2 + t))) * (1 - 0.6 * max(0.0, t - 0.55) / 0.45) ** 1.2
        prof *= rng.uniform(0.85, 1.12)
        r = max(R0 * 0.3, R0 * prof)
        ang = i * 2.4 + rng.uniform(-0.4, 0.4)
        off = (bx * math.cos(ang) + by * math.sin(ang)) * r * 0.18
        c = p0 + ax * (Lc * t) + off
        ellipsoid("bud", c, ax, r * 0.62, r * 0.7, rng)                       # nug core
        nc = max(5, int(n_calyx * (0.6 + 0.4 * prof)))
        for k in range(nc):
            a = 2 * math.pi * k / nc + rng.uniform(0, 0.6) + i * 0.9
            e = rng.uniform(-0.2, 0.8)
            dirv = (bx * math.cos(a) + by * math.sin(a)) * math.cos(e) + ax * math.sin(e)
            dirv = (dirv + ax * 0.6).normalized()
            rc = r * rng.uniform(0.3, 0.42)
            pc = c + dirv * r * 0.62
            ellipsoid("bud", pc, dirv, rc * 0.72, rc * 1.3, rng)
            if rng.random() < st["pist_rate"]:
                tip = pc + dirv * rc * 1.15
                pd = (dirv + Vector((rng.uniform(-.6, .6), rng.uniform(-.6, .6), rng.uniform(0, .5)))).normalized()
                ln = r * rng.uniform(0.5, 0.9) * st["pist_len"]
                bend = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), -0.8 if st["ripe"] else 0.3)).normalized()
                pts = [tip, tip + pd * ln * 0.5, tip + pd * ln * 0.8 + bend * ln * 0.4 * st["curl"]]
                key = "pist_o" if rng.random() < st["orange"] else "pist_w"
                geo(key).add(*tube(pts, [0.0034, 0.0028, 0.0018], 4))
        if rng.random() < 0.85 * sugar_rate and t < 0.9:
            for _ in range(1 if rng.random() < 0.6 else 2):
                a = rng.uniform(0, 2 * math.pi)
                outv = (bx * math.cos(a) + by * math.sin(a))
                yaw = math.atan2(-outv.x, outv.y)
                tex = sugar_tex if rng.random() < 0.55 else sugar_tex.replace("3", "1")
                leaf(tex, c + outv * r * 0.45, yaw, math.radians(rng.uniform(30, 55)), r * rng.uniform(1.5, 2.1), 0.3, rng, cup=0.3)
    ellipsoid("bud", p1 + ax * R0 * 0.1, ax, R0 * 0.3, R0 * 0.55, rng)


# ======================================================================= v2: shapes, colours, males, styles
# Body plans ported from DazedDank tools/blender/render_shapes.py (h/w are 1x pixel sizes at full flower).
SHAPES = {
    "landrace": dict(h=162, w=74, fingers=9, thin=0.13, nodes=9, taper=0.8, bud_w=5.5, bud_len=0.30, sparse=0.35, leaf=(96, 156, 54)),
    "haze":     dict(h=150, w=84, fingers=9, thin=0.15, nodes=8, taper=0.75, bud_w=5.0, bud_len=0.42, sparse=0.2, leaf=(88, 150, 50)),
    "hybrid":   dict(h=122, w=96, fingers=7, thin=0.22, nodes=7, taper=0.75, bud_w=7.5, bud_len=0.34, sparse=0.0, leaf=(66, 128, 44)),
    "kush":     dict(h=96, w=110, fingers=7, thin=0.30, nodes=6, taper=0.55, bud_w=10.0, bud_len=0.36, sparse=0.0, leaf=(52, 102, 38)),
    "afghan":   dict(h=84, w=128, fingers=5, thin=0.38, nodes=6, taper=0.45, bud_w=11.5, bud_len=0.30, sparse=0.0, leaf=(44, 92, 34)),
    "auto":     dict(h=66, w=70, fingers=5, thin=0.26, nodes=5, taper=0.6, bud_w=7.0, bud_len=0.38, sparse=0.1, leaf=(80, 140, 50)),
    "tree":     dict(h=132, w=118, fingers=7, thin=0.24, nodes=8, taper=0.95, bud_w=8.5, bud_len=0.40, sparse=0.0, leaf=(60, 120, 42)),
}
COLOURS = {
    "purple": dict(leaf_mix=((84, 52, 96), 0.35), bud=(96, 46, 124), sugar=(76, 40, 96), pist=(232, 140, 70), frost=0.3),
    "frosty": dict(leaf_mix=((190, 205, 180), 0.12), bud=(206, 220, 196), sugar=(186, 204, 176), pist=(240, 236, 220), frost=0.9),
    "gold":   dict(leaf_mix=((168, 200, 60), 0.45), bud=(206, 192, 92), sugar=(186, 196, 80), pist=(236, 150, 40), frost=0.25),
    "dark":   dict(leaf_mix=((40, 70, 40), 0.3), bud=(38, 26, 46), sugar=(72, 100, 62), pist=(196, 112, 58), frost=0.22),
}
CLASSES = [14, 18, 22, 27, 32, 38, 46]
# realistic = the v1 look; bold = "in-between": same structure, bigger/wider/fewer leaves, greener, more saturated
STYLES = {
    "real": dict(leafR=1.0, thin=1.0, tilt=0.0, branch_leaves=2, sat=1.0, val=1.0, hue=0.5, trans=0.18, yellow=1.0,
                 cola=1.0, bud_sat=1.0, bud_val=1.0, sugar_rate=1.0, droop=1.0, frost=1.0, pale=0.28),
    "bold": dict(leafR=1.3, thin=1.35, tilt=10.0, branch_leaves=2, sat=1.6, val=1.35, hue=0.49, trans=0.06, yellow=0.3,
                 cola=1.15, bud_sat=1.35, bud_val=1.12, sugar_rate=0.55, droop=0.8, frost=0.7, pale=0.12),
}
JOB = {}


def lin3(rgb):
    return lin(rgb)[:3]


def leaf_mat(tex, trans=None):
    """Leaf card material: baked texture x shape tint -> style HSV -> colour-phenotype mix; paler undersides."""
    if "leaf:" + tex in MATS:
        return MATS["leaf:" + tex]
    S, sh, col = STYLES[JOB["style"]], JOB["shape"], JOB.get("colour")
    sugar = tex.startswith("sugar")
    m = bpy.data.materials.new(tex)
    m.use_nodes = True
    N, L = m.node_tree.nodes, m.node_tree.links
    N.clear()
    out = N.new('ShaderNodeOutputMaterial')
    img = N.new('ShaderNodeTexImage')
    img.image = bpy.data.images.load(os.path.join(TEX, tex + ".png"), check_existing=True)
    img.interpolation = 'Cubic'
    c = img.outputs['Color']
    if not sugar:
        t = [lin3(SHAPES[sh]["leaf"])[i] / lin3(SHAPES["hybrid"]["leaf"])[i] for i in range(3)]
        t = [min(2.2, max(0.5, x)) ** 0.6 for x in t]          # partial: keep the texture's own palette
        mul = N.new('ShaderNodeMix'); mul.data_type = 'RGBA'; mul.blend_type = 'MULTIPLY'
        mul.inputs[0].default_value = 1.0
        L.new(c, mul.inputs[6]); mul.inputs[7].default_value = tuple(t) + (1,)
        c = mul.outputs[2]
    hsv = N.new('ShaderNodeHueSaturation')
    hsv.inputs['Hue'].default_value = S["hue"]
    hsv.inputs['Saturation'].default_value = S["sat"]
    hsv.inputs['Value'].default_value = S["val"]
    L.new(c, hsv.inputs['Color'])
    c = hsv.outputs['Color']
    if col:
        C = COLOURS[col]
        target, amt = (C["sugar"], 0.7) if sugar else (C["leaf_mix"][0], C["leaf_mix"][1] * (1.0 if JOB["stage"] == "Ripe" else 0.7))
        mx = N.new('ShaderNodeMix'); mx.data_type = 'RGBA'
        mx.inputs[0].default_value = amt
        L.new(c, mx.inputs[6]); mx.inputs[7].default_value = lin(target)
        c = mx.outputs[2]
    geo_n = N.new('ShaderNodeNewGeometry')
    under = N.new('ShaderNodeMix'); under.data_type = 'RGBA'
    L.new(geo_n.outputs['Backfacing'], under.inputs[0])
    L.new(c, under.inputs[6])
    pale = N.new('ShaderNodeMix'); pale.data_type = 'RGBA'; pale.inputs[0].default_value = S["pale"]
    L.new(c, pale.inputs[6]); pale.inputs[7].default_value = lin((150, 166, 130))
    L.new(pale.outputs[2], under.inputs[7])
    c = under.outputs[2]
    bs = N.new('ShaderNodeBsdfPrincipled'); bs.inputs['Roughness'].default_value = 0.52
    L.new(c, bs.inputs['Base Color'])
    tr = N.new('ShaderNodeBsdfTranslucent'); L.new(c, tr.inputs['Color'])
    mx = N.new('ShaderNodeMixShader'); mx.inputs[0].default_value = S["trans"]
    L.new(bs.outputs[0], mx.inputs[1]); L.new(tr.outputs[0], mx.inputs[2])
    tp = N.new('ShaderNodeBsdfTransparent')
    cut = N.new('ShaderNodeMath'); cut.operation = 'GREATER_THAN'; cut.inputs[1].default_value = 0.5
    L.new(img.outputs['Alpha'], cut.inputs[0])
    ma = N.new('ShaderNodeMixShader')
    L.new(cut.outputs[0], ma.inputs[0]); L.new(tp.outputs[0], ma.inputs[1]); L.new(mx.outputs[0], ma.inputs[2])
    L.new(ma.outputs[0], out.inputs['Surface'])
    MATS["leaf:" + tex] = m
    return m


STAGE = {
    "Vegetative": dict(H=0.64, nodes=-3, leafR=0.36, pre=True, veg=True, pist_rate=0.0, orange=0.0, fat=0.8, ripe=False,
                       pist_len=1.0, curl=0.8, frost=0.0, yellow=0.0, droop=0.32, branch=0.6),
    "PreFlower": dict(H=1.12, nodes=-1, leafR=0.41, pre=True, pist_rate=0.7, orange=0.0, fat=0.8, ripe=False,
                      pist_len=1.0, curl=0.8, frost=0.0, yellow=0.0, droop=0.38, branch=0.85),
    "Flowering": dict(H=1.42, nodes=0, leafR=0.42, pre=False, pist_rate=0.55, orange=0.15, fat=0.92, ripe=False,
                      pist_len=0.75, curl=0.9, frost=0.3, yellow=0.08, droop=0.38, branch=1.0),
    "Ripe":      dict(H=1.42, nodes=0, leafR=0.41, pre=False, pist_rate=0.65, orange=0.88, fat=1.15, ripe=True,
                      pist_len=1.0, curl=1.0, frost=0.9, yellow=0.45, droop=0.5, branch=1.0),
}


def spec_for(shape, stage, style):
    """Stage parameters for one shape and style (hybrid = the v1 sample)."""
    sh, S = SHAPES[shape], STYLES[style]
    st = dict(STAGE[stage])
    kH, kW = sh["h"] / 122.0, sh["w"] / 96.0
    st["H"] *= kH
    st["nodes"] = max(3, sh["nodes"] + 1 + st["nodes"])
    st["leafR"] *= (0.55 + 0.45 * kW) * (0.85 + 0.15 * kH) * S["leafR"]
    st["kW"] = kW
    st["taper"] = sh["taper"]
    st["sparse"] = sh["sparse"]
    st["fingers"] = sh["fingers"]
    st["cls"] = min(CLASSES, key=lambda c: abs(c / 100.0 - sh["thin"] * S["thin"]))
    st["width"] = 0.15 * (sh["bud_w"] / 7.5) ** 0.8 * S["cola"]
    st["clen"] = 0.38 * sh["bud_len"] / 0.34
    st["yellow"] *= S["yellow"]
    st["droop"] *= S["droop"]
    st["frost"] *= S["frost"] if not JOB.get("colour") else 1.0
    st["tilt"] = S["tilt"]
    st["branch_leaves"] = S["branch_leaves"]
    st["sugar_rate"] = S["sugar_rate"]
    return st


def leaf_tex(n, st, t, rng, young=False):
    n = max(3, min(9, n))
    c = st["cls"]
    if young:
        return f"leaf{n}_young_t{c}"
    y = st["yellow"] * (1.25 - t)
    r = rng.random()
    if y > 0.4 and r < 0.55:
        return f"leaf{n}_yellow2_t{c}"
    if y > 0.12 and r < 0.45 + y * 0.4:
        return f"leaf{n}_yellow1_t{c}"
    return f"leaf{n}_green_t{c}"


def build_seedling(rng):
    S = 1.7
    H = 0.15 * S
    geo("stem").add(*tube([(0, 0, -0.03), (0.004, 0, H * 0.5), (0.006, 0.003, H)], [0.012, 0.01, 0.008], 7))
    for s in (-1, 1):
        d = Vector((s * 0.7, -0.7 * s, 0)).normalized()
        c = Vector((0.006, 0.003, H * 0.9)) + d * 0.045 * S
        geo("cot").add(*SPH, m=Matrix.Translation(c) @ Matrix.Rotation(math.atan2(-d.x, d.y), 4, 'Z')
                       @ Matrix.Rotation(math.radians(-15), 4, 'X') @ Matrix.Diagonal(Vector((0.024 * S, 0.042 * S, 0.006, 1))))
    top = Vector((0.006, 0.003, H))
    k = STYLES[JOB["style"]]["leafR"]
    for s in (-1, 1):
        d = Vector((s * 0.7, s * 0.7, 0)).normalized()
        petiole_leaf(top + Vector((0, 0, 0.005)), d, 0.085 * S * k, "leaf1_young", rng, rise=0.6, tilt=30, droop=0.2)
    geo("stem").add(*tube([top, top + Vector((0, 0, 0.04 * S))], [0.007, 0.005], 6))
    t2 = top + Vector((0, 0, 0.04 * S))
    for s in (-1, 1):
        d = Vector((s * 0.7, -s * 0.7, 0)).normalized()
        petiole_leaf(t2, d, 0.06 * S * k, "leaf3_young", rng, rise=0.9, tilt=40, droop=0.15)
    leaf("leaf3_young", t2 + Vector((0, 0, 0.012)), 0.8, math.radians(70), 0.03 * S, 0.0, rng)


def branch(node, yaw, blen, R, st, t, rng, colas, male=False):
    bout = Vector((-math.sin(yaw), math.cos(yaw), 0))
    pts = [Vector(node)]
    p = Vector(node)
    d = (bout * 0.8 + Vector((0, 0, 0.6))).normalized()
    seg = 6
    for i in range(seg):
        p = p + d * blen / seg
        pts.append(p.copy())
        d = (d + Vector((0, 0, 0.2))).normalized()
    geo("stem").add(*tube(pts, [0.012 - 0.0075 * i / seg for i in range(seg + 1)], 6))
    for j, bi in enumerate((2, 4)[:st["branch_leaves"]]):
        side = 1 if j % 2 == 0 else -1
        perp = bout.cross(Vector((0, 0, 1)))
        ld = (perp * side + bout * 0.5).normalized()
        n = st["fingers"] if blen > 0.32 and j == 0 else st["fingers"] - 2
        sc_ = (0.78 - 0.14 * j) * (1.1 if st["branch_leaves"] == 1 else 1.0)
        petiole_leaf(pts[bi], ld, R * sc_ * rng.uniform(0.85, 1.05), leaf_tex(n, st, t + 0.08 * j, rng), rng,
                     rise=0.35, droop=st["droop"] * 0.9, tilt=rng.uniform(32, 52) + st["tilt"])
    colas.append((pts[-1], (pts[-1] - pts[-3]).normalized(), blen, t, pts))


def pollen_cluster(origin, direction, length, rng, ripe, dens):
    """Male flowers: a short stalk forking into pedicels that end in hanging pollen sacs (some open when ripe)."""
    origin = Vector(origin)
    tip = origin + Vector(direction).normalized() * length
    geo("stem").add(*tube([origin, tip], [0.005, 0.003], 4))
    for i in range(dens):
        t = (i + 0.5) / dens
        p = origin + (tip - origin) * (0.2 + 0.8 * t)
        a = rng.uniform(0, 2 * math.pi)
        o = Vector((math.cos(a), math.sin(a), rng.uniform(-0.9, -0.1))).normalized()
        end = p + o * length * rng.uniform(0.25, 0.4)
        geo("stem").add(*tube([p, end], [0.0022, 0.0016], 3))
        sz = rng.uniform(0.026, 0.034)
        if ripe and rng.random() < 0.45:
            for k in range(5):
                aa = 2 * math.pi * k / 5
                po = Vector((math.cos(aa), math.sin(aa), -0.4)).normalized()
                ellipsoid("petal", end + po * sz * 0.8, po, sz * 0.55, sz * 0.25, rng)
            for k in range(4):
                aa = 2 * math.pi * k / 4 + 0.4
                a0 = end + Vector((math.cos(aa) * sz * 0.3, math.sin(aa) * sz * 0.3, -sz * 1.2))
                ellipsoid("anther", a0, Vector((0, 0, -1)), sz * 0.22, sz * 0.45, rng)
        else:
            ellipsoid("sac", end, Vector((0, 0, -1)), sz * 0.75, sz * 1.1, rng)


def build_plant(shape, stage, style, male=False, seed=4242):
    rng = random.Random(seed + (7 if male else 0))
    st = spec_for(shape, stage, style)
    H = st["H"] * (1.15 if male else 1.0)
    sway = Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 0))

    def sp(z):
        t = z / H
        return Vector((sway.x * t * t + 0.006 * math.sin(t * 9), sway.y * t * t, z))

    zs = [H * i / 14 for i in range(15)]
    r0 = 0.021 * (0.7 + 0.3 * min(1.3, st["kW"]))
    geo("stem").add(*tube([sp(-0.04)] + [sp(z) for z in zs[1:]], [r0] + [r0 * (0.9 - 0.62 * (z / H)) for z in zs[1:]], 8))
    nodes = st["nodes"]
    gaps = [0.65 + 0.5 * math.sin(math.pi * (k + 0.5) / nodes) for k in range(nodes)]
    if not st["pre"] and not male:
        gaps = [g * (0.7 if k >= nodes - 3 else 1.0) for k, g in enumerate(gaps)]
    ztop = H * 0.8
    scl = (ztop - 0.09) / sum(gaps)
    z = 0.09
    phi = rng.uniform(0, math.pi)
    colas = []
    for k in range(nodes):
        t = z / H
        opposite = k < 4
        sides = [phi, phi + math.pi] if opposite else [phi]
        node = sp(z)
        for yaw in sides:
            skip = rng.random() < st["sparse"] * t + (0.15 if male and t > 0.45 else 0.0)
            out = Vector((-math.sin(yaw), math.cos(yaw), 0))
            mf = st["fingers"]
            fingers = mf if t < 0.5 else mf - 2 if t < 0.72 else 3
            if k == 0:
                fingers = min(5, mf)
            R = st["leafR"] * (1.0 - 0.5 * t) * rng.uniform(0.9, 1.08) * (0.7 if k == 0 else 1.0)
            dr = st["droop"] * rng.uniform(0.85, 1.2) * (1.25 if t < 0.3 else 1.0)
            if not skip:
                petiole_leaf(node, out, R, leaf_tex(fingers, st, t, rng), rng, rise=0.25 + 0.4 * t, droop=dr,
                             tilt=rng.uniform(34, 54) + st["tilt"])
            if k >= 1:
                ft = max(0.05, 1 - t * st["taper"] / 0.75)
                blen = (0.5 * ft ** 0.6 * (1 - t) ** 0.25 + 0.04) * st["kW"] * rng.uniform(0.85, 1.1) * st["branch"]
                if male:
                    blen *= 0.8
                branch(node, yaw + rng.uniform(-0.35, 0.35), blen, st["leafR"] * (1.0 - 0.5 * t), st, t, rng, colas)
            if male and t > (0.6 if st["pre"] else 0.35):
                for c in range(2):
                    a = rng.uniform(0, 2 * math.pi)
                    pollen_cluster(node, Vector((math.cos(a), math.sin(a), rng.uniform(-0.1, 0.4))), rng.uniform(0.05, 0.08),
                                   rng, st["ripe"], 7)
        phi += (math.pi / 2 if opposite else math.radians(137.5)) + rng.uniform(-0.15, 0.15)
        z += gaps[k] * scl
    top = sp(H)
    sugar = "sugar3_heavy" if st["frost"] > 0.8 else "sugar3_light"
    if male:
        geo("stem").add(*tube([sp(H - 0.05), top + Vector((0, 0, 0.05))], [0.007, 0.004], 6))
        for tip, d, blen, t, pts in colas:
            leaf(leaf_tex(5, st, t, rng), tip, rng.uniform(0, 6.3), math.radians(50), 0.05 + 0.12 * blen, 0.2, rng)
            if t > (0.5 if st["pre"] else 0.15):
                for c in range(1 if st["pre"] else 3):
                    dd = d * 0.5 + Vector((rng.uniform(-.5, .5), rng.uniform(-.5, .5), rng.uniform(-0.3, 0.4)))
                    pollen_cluster(tip, dd, rng.uniform(0.06, 0.1), rng, st["ripe"], 9)
        for s in range(4):
            leaf(leaf_tex(5, st, 0.9, rng, young=True), top - Vector((0, 0, 0.02 * s)), s * 1.6, math.radians(55), 0.07, 0.15, rng)
        for c in range(4 if st["pre"] else 9):
            a = c * 2.1 + rng.uniform(0, 0.6)
            pollen_cluster(top - Vector((0, 0, 0.025 * c)), Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.6)),
                           rng.uniform(0.05, 0.09), rng, st["ripe"], 9)
        return
    if st["pre"]:
        for tip, d, blen, t, pts in colas:
            for s in range(3):
                leaf(leaf_tex(5, st, t, rng, young=True), tip + Vector((0, 0, 0.008)), rng.uniform(0, 6.3),
                     math.radians(rng.uniform(45, 65)), 0.05 + 0.14 * blen, 0.15, rng)
            if t > 0.3 and not st.get("veg"):
                cola(tip - d * 0.015, tip + d * 0.035, 0.04, st, rng, "sugar3_light", n_calyx=6, sugar_rate=0.3)
        zz = sp(H - 0.1)
        geo("stem").add(*tube([zz, top + Vector((0, 0, 0.03))], [0.008, 0.005], 6))
        for s in range(6):
            leaf(leaf_tex(5 if s > 1 else 7, st, 0.9, rng, young=True), top + Vector((0, 0, -0.015 * s)), s * 1.25 + rng.uniform(0, 0.4),
                 math.radians(58 - s * 5), 0.06 + 0.02 * s, 0.12, rng)
        if not st.get("veg"):
            cola(top - Vector((0, 0, 0.1)), top + Vector((0, 0, 0.04)), 0.05, st, rng, "sugar3_light", n_calyx=7, sugar_rate=0.3)
        return
    width = st["width"]
    clen = H * st["clen"]
    cola(top - Vector((0, 0, clen * 0.75)), top + Vector((0, 0, clen * 0.25)), width, st, rng, sugar, sugar_rate=st["sugar_rate"])
    for s in range(5):
        zz = H - clen * 0.7 + clen * 0.7 * s / 5
        a = s * 2.4 + rng.uniform(-0.3, 0.3)
        out = Vector((-math.sin(a), math.cos(a), 0))
        petiole_leaf(sp(min(zz, H)), out, (0.11 + 0.05 * (1 - s / 5)) * STYLES[JOB["style"]]["leafR"],
                     leaf_tex(3 if s > 2 else 5, st, 0.7, rng), rng, rise=0.7, droop=0.3, tilt=rng.uniform(25, 45))
    for tip, d, blen, t, pts in colas:
        f = min(1.0, 0.3 + blen * 1.5)
        cl = clen * 0.6 * f
        dd = (d + Vector((0, 0, 0.8))).normalized()
        cola(tip - dd * cl * 0.3, tip + dd * cl * 0.7, width * (0.48 + 0.4 * f), st, rng, sugar, n_calyx=10,
             sugar_rate=st["sugar_rate"])


def sat_col(rgb, k, v=1.0):
    """Scale an sRGB colour's saturation by k and value by v."""
    import colorsys
    h, s, vv = colorsys.rgb_to_hsv(*[c / 255.0 for c in rgb])
    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, s * k), min(1.0, vv * v))
    return (r * 255, g * 255, b * 255)


def materials(stage):
    S = STYLES[JOB["style"]]
    st = STAGE.get(stage, {})
    frost = st.get("frost", 0.0) * S["frost"]
    ripe = st.get("ripe", False)
    bud_col = (116, 148, 66) if not ripe else (130, 144, 74)
    pist_o = (176, 96, 44) if ripe else (206, 128, 58)
    fcol = (232, 234, 214) if not ripe else (234, 226, 196)
    col = JOB.get("colour")
    if col:
        C = COLOURS[col]
        bud_col, pist_o, frost = C["bud"], C["pist"], max(frost, C["frost"] * (1.0 if ripe else 0.75))
    if not col:
        bud_col = sat_col(bud_col, S["bud_sat"], S["bud_val"])
    stem = sat_col((82, 108, 52), S["sat"] ** 0.5, S["val"] ** 0.5)
    return {
        "stem": solid_mat("stem", stem, 0.65, bump=0.2, scale=30),
        "cot": solid_mat("cot", sat_col((96, 130, 62), S["sat"] ** 0.5, S["val"]), 0.5, trans=0.25, scale=12),
        "bud": solid_mat("bud", bud_col, 0.55, frost=frost * 1.1 + (0.1 if stage == "PreFlower" else 0.0),
                         frost_col=fcol, sheen=0.25 + 0.5 * frost, var=0.16),
        "pist_w": solid_mat("pist_w", (222, 214, 186), 0.6, scale=20),
        "pist_o": solid_mat("pist_o", pist_o, 0.6, scale=20, var=0.2),
        "sac": solid_mat("sac", (184, 204, 136), 0.5, trans=0.15, bump=0.2),
        "petal": solid_mat("petal", (226, 222, 176), 0.6, trans=0.35),
        "anther": solid_mat("anther", (214, 186, 80), 0.55),
    }


SHAPE_ORDER = ["landrace", "haze", "hybrid", "kush", "afghan", "auto", "tree"]


def all_jobs():
    """Every layer make_overlay_sprites.py reads, by its file name."""
    out = ["seedling"]
    for sh in SHAPE_ORDER:
        out += [f"shape_{sh}_{st}" for st in ("Vegetative", "PreFlower", "Flowering", "Ripe")]
        out += [f"male_{sh}_{st}" for st in ("PreFlower", "Flowering", "Ripe")]
        out += [f"colour_{c}_{sh}_{st}" for c in COLOURS for st in ("Flowering", "Ripe")]
    return out


def parse(name):
    """Output name -> (shape, stage, colour, male)."""
    p = name.split("_")
    if p[0] == "seedling":
        return "hybrid", "Seedling", None, False
    if p[0] == "shape":
        return p[1], p[2], None, False
    if p[0] == "male":
        return p[1], p[2], None, True
    return p[2], p[3], p[1], False


FIT = 0.64          # widest reach from the stem on screen (world units): the cell edge is at 0.707, and the XL sheet is 10% bigger


def fit_width():
    """Keep the plant inside its 128 px cell: a quick wide, low-sample probe render measures how far the foliage
    reaches left and right of the stem; if it would be cut by the cell edge, squeeze the plant towards the stem
    (horizontally, and a little in height only when the squeeze is strong)."""
    import numpy as np
    keep = (cd.ortho_scale, cd.shift_y, sc.render.resolution_x, sc.render.resolution_y, sc.cycles.samples,
            sc.cycles.use_denoising, sc.render.filepath)
    k = 1.8
    cd.ortho_scale, cd.shift_y = ORTHO * k, 0.25
    sc.render.resolution_x, sc.render.resolution_y = 256, 512
    sc.cycles.samples, sc.cycles.use_denoising = 2, False
    probe = os.path.join(OUT, "_probe.png")
    sc.render.filepath = probe
    bpy.ops.render.render(write_still=True)
    cd.ortho_scale, cd.shift_y, sc.render.resolution_x, sc.render.resolution_y, sc.cycles.samples, \
        sc.cycles.use_denoising, sc.render.filepath = keep
    img = bpy.data.images.load(probe)
    a = np.array(img.pixels[:], dtype=np.float32).reshape(512, 256, 4)[..., 3]
    bpy.data.images.remove(img)
    cols = np.where(a.max(axis=0) > 0.3)[0]
    if not len(cols):
        return
    half = max(128 - cols.min(), cols.max() + 1 - 128) / 128.0 * (ORTHO * k / 2)
    if half <= FIT:
        return
    f = FIT / half
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            ob.scale = (f, f, min(1.0, f / 0.8))
    print(f"fit {f:.2f}", flush=True)


def render(name):
    import zlib
    shape, stage, colour, male = parse(name)
    JOB.clear()
    JOB.update(style=STYLE, shape=shape, stage=stage, colour=colour)
    for ob in list(bpy.data.objects):
        if ob.type == 'MESH':
            bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for ma in list(bpy.data.materials):
        bpy.data.materials.remove(ma)
    MATS.clear()
    GEO.clear()
    if stage == "Seedling":
        build_seedling(random.Random(7))
    else:
        # one seed per strain (shape + colour): stages of a strain grow from the same plant, strains differ
        build_plant(shape, stage, STYLE, male, seed=zlib.crc32(f"{shape}/{colour or 'green'}".encode()) % 100000)
    mats = materials(stage)
    for key, g in GEO.items():
        if g.v:
            g.build(key, leaf_mat(key[2:]) if key.startswith("L:") else mats[key])
    fit_width()
    t1 = time.time()
    sc.render.filepath = os.path.join(OUT, f"raw_{name}.png")
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {name} {time.time() - t1:.1f}s", flush=True)


os.makedirs(OUT, exist_ok=True)
NAMES = [n for j in (ARGS[2:] or ["all"]) for n in (all_jobs() if j == "all" else [j])]
for n in NAMES:
    if os.environ.get("FORCE") or not os.path.exists(os.path.join(OUT, f"raw_{n}.png")):
        render(n)
print("DD DONE", flush=True)
