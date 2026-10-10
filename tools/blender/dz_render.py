"""DazedPower art, modelled from scratch (no shared models). Run headless:
    blender -b -P dz_render.py -- <out dir> <job> [job ...]
Jobs: align, test, all, cells:<kind>[,<kind>], icons, poster. Cells land in <out>/cells/<sprite index>.png at 256x512.
"""
import bpy, bmesh, math, os, sys, random, time
from mathutils import Vector, Matrix, Euler

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
JOBS = ARGS[1:] or ["test"]
os.makedirs(OUT, exist_ok=True)
LOG = open(os.path.join(OUT, "log.txt"), "a")


def log(*a):
    """One line to the log file, flushed so progress can be watched."""
    LOG.write(time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a) + "\n"); LOG.flush()


# ------------------------------------------------------------------ sheet layout (must match OGM_Parts.lua)
KINDS = ["pedal", "windmill", "steam", "windsock", "vane", "propane", "petrol"]
TIERS = {"windsock": ["basic"], "vane": ["basic"]}
STATES = {"pedal": ["off", "on"], "windmill": ["still", "turning", "furled", "broken"],
          "steam": ["cold", "warming", "running", "broken"], "windsock": ["limp", "half", "full"],
          "vane": ["set"], "propane": ["off", "running", "broken"], "petrol": ["off", "running", "broken"]}
ROWS = [(k, t, s) for k in KINDS for t in TIERS.get(k, ["makeshift", "salvaged", "manufactured"]) for s in STATES[k]]
FACINGS = [("E", 90), ("S", 0), ("W", 270), ("N", 180)]      # model front is -Y; degrees about Z

# ------------------------------------------------------------------ scene
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.render.film_transparent = True
scene.render.resolution_x, scene.render.resolution_y = 256, 512
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.cycles.samples = 96
scene.cycles.use_denoising = True
scene.cycles.transparent_max_bounces = 16
for vt in ("Standard",):
    try: scene.view_settings.view_transform = vt
    except Exception: pass
try: scene.view_settings.look = "None"
except Exception: pass
scene.view_settings.exposure = -0.1


def setup_gpu():
    """Use the first GPU backend that has a device; CPU otherwise."""
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for t in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
            try:
                prefs.compute_device_type = t
                prefs.get_devices()
                if any(d.type == t for d in prefs.devices):
                    for d in prefs.devices: d.use = d.type == t
                    scene.cycles.device = "GPU"
                    return t
            except Exception:
                pass
    except Exception:
        pass
    return "CPU"


log("start", JOBS, "device", setup_gpu())

# Soft sky fill plus a high key light from the viewer's front-left, like the base game's furniture.
world = bpy.data.worlds.new("W"); scene.world = world
try: world.use_nodes = True
except Exception: pass
bg = world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.62, 0.66, 0.72, 1); bg.inputs[1].default_value = 0.85


def sun(name, toward_light, energy, angle, shadows=True):
    """A sun lamp shining from the given direction."""
    ld = bpy.data.lights.new(name, "SUN"); ld.energy = energy; ld.angle = math.radians(angle)
    try: ld.use_shadow = shadows
    except Exception: pass
    ob = bpy.data.objects.new(name, ld); scene.collection.objects.link(ob)
    ob.rotation_euler = Vector((0, 0, 1)).rotation_difference(Vector(toward_light).normalized()).to_euler()
    return ob


sun("Key", (-0.55, -1.0, 1.55), 2.7, 12)
sun("Rim", (1.0, 0.35, 0.8), 0.7, 30, shadows=False)

cam_data = bpy.data.cameras.new("Cam"); cam_data.type = "ORTHO"
cam = bpy.data.objects.new("Cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
CAM_ROT = Euler((math.radians(60), 0, math.radians(45)))


def aim_camera(center, ortho, res):
    """Place the 2:1 iso camera so `center` sits mid-frame."""
    cam_data.ortho_scale = ortho; cam_data.clip_end = 200
    scene.render.resolution_x, scene.render.resolution_y = res
    fwd = CAM_ROT.to_matrix() @ Vector((0, 0, -1))
    cam.rotation_euler = CAM_ROT; cam.location = Vector(center) - fwd * 50


def tile_camera():
    """Cell camera: one floor tile's diamond fills the bottom 64 px of a 128x256 cell (rendered at 2x)."""
    up = CAM_ROT.to_matrix() @ Vector((0, 1, 0))
    aim_camera(up * (1.5 / math.sqrt(2)), 2 * math.sqrt(2), (256, 512))


MODEL = bpy.data.collections.new("Model"); scene.collection.children.link(MODEL)

# ------------------------------------------------------------------ materials


def lin(hexcol):
    """sRGB hex to linear RGBA."""
    h = hexcol.lstrip("#"); c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)


def shade(c, f):
    """Scale a linear colour."""
    return (c[0] * f, c[1] * f, c[2] * f, 1.0)


WEAR = {"rust": 0.0, "dirt": 0.0, "scorch": 0.0}
MATS = {}


def _sock(lst, name, typ):
    return [s for s in lst if s.name == name and s.type == typ][0]


def _set(nt, sock, v):
    if isinstance(v, bpy.types.NodeSocket): nt.links.new(v, sock)
    else: sock.default_value = v


def mix(nt, fac, a, b, blend="MIX"):
    """Colour mix node; any argument may be a socket or a value."""
    n = nt.nodes.new("ShaderNodeMix"); n.data_type = "RGBA"; n.blend_type = blend
    _set(nt, _sock(n.inputs, "Factor", "VALUE"), fac)
    _set(nt, _sock(n.inputs, "A", "RGBA"), a); _set(nt, _sock(n.inputs, "B", "RGBA"), b)
    return _sock(n.outputs, "Result", "RGBA")


def math_node(nt, op, a, b=0.0):
    n = nt.nodes.new("ShaderNodeMath"); n.operation = op
    _set(nt, n.inputs[0], a); _set(nt, n.inputs[1], b)
    return n.outputs[0]


def noise(nt, scale, detail=6.0):
    n = nt.nodes.new("ShaderNodeTexNoise"); n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    tc = nt.nodes.new("ShaderNodeTexCoord"); nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
    return n.outputs["Fac"]


def ramp(nt, fac, lo, hi):
    """Hard-ish threshold of a 0-1 value between lo and hi."""
    n = nt.nodes.new("ShaderNodeMapRange"); _set(nt, n.inputs[0], fac)
    n.inputs[1].default_value, n.inputs[2].default_value = lo, hi
    n.inputs[3].default_value, n.inputs[4].default_value = 0.0, 1.0
    return n.outputs[0]


def bsdf_in(b, *names):
    for nm in names:
        if nm in b.inputs: return b.inputs[nm]
    return None


def mat(col, rough=0.6, metal=0.0, var=0.12, rust=0.0, dirt=0.3, alpha=1.0, emit=0.0, emit_col=None, wear=True):
    """Painterly worn material: colour noise, rust patches, crevice and ground grime."""
    if wear:
        rust = min(1.0, rust + WEAR["rust"]); dirt = min(1.0, dirt + WEAR["dirt"])
    sc = WEAR["scorch"] if wear else 0.0
    key = (col, rough, metal, var, round(rust, 2), round(dirt, 2), alpha, emit, emit_col, round(sc, 2))
    if key in MATS: return MATS[key]
    m = bpy.data.materials.new("m%d" % len(MATS))
    try: m.use_nodes = True
    except Exception: pass
    nt = m.node_tree; b = nt.nodes.get("Principled BSDF")
    base = lin(col)
    c = mix(nt, math_node(nt, "MULTIPLY", noise(nt, 3.0), var * 1.6), base, shade(base, 0.62))
    c = mix(nt, math_node(nt, "MULTIPLY", noise(nt, 38.0, 2), 0.18), c, shade(base, 1.25))
    r_out = rough
    if rust > 0:
        rm = ramp(nt, noise(nt, 7.0, 10), 0.72 - rust * 0.32, 0.78 - rust * 0.3)
        c = mix(nt, rm, c, mix(nt, noise(nt, 20.0), lin("#6a3b20"), lin("#8a5530")))
        rr = nt.nodes.new("ShaderNodeMapRange"); _set(nt, rr.inputs[0], rm)
        rr.inputs[3].default_value, rr.inputs[4].default_value = rough, 0.92
        r_out = rr.outputs[0]
    if sc > 0:
        c = mix(nt, math_node(nt, "MULTIPLY", ramp(nt, noise(nt, 2.5), 0.35, 0.6), sc), c, lin("#1d1a17"))
    if dirt > 0:
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.12
        crev = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", 1.0, ao.outputs["AO"]), dirt * 1.2)
        tc = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(tc.outputs["Object"], sep.inputs[0])
        low = nt.nodes.new("ShaderNodeMapRange"); nt.links.new(sep.outputs[2], low.inputs[0])
        low.inputs[1].default_value, low.inputs[2].default_value = 0.0, 0.28
        low.inputs[3].default_value, low.inputs[4].default_value = dirt * 0.55, 0.0
        g = math_node(nt, "MINIMUM", math_node(nt, "ADD", crev, low.outputs[0]), 0.85)
        c = mix(nt, g, c, lin("#3b3227"))
    nt.links.new(c, b.inputs["Base Color"])
    _set(nt, b.inputs["Roughness"], r_out)
    b.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        try: m.blend_method = "BLEND"
        except Exception: pass
    if emit > 0:
        ec = bsdf_in(b, "Emission Color", "Emission"); ec.default_value = lin(emit_col or col)
        es = bsdf_in(b, "Emission Strength")
        if es: es.default_value = emit
    MATS[key] = m
    return m


def glow(col, strength):
    return mat("#202020", 0.5, emit=strength, emit_col=col, dirt=0, wear=False)


def puff(col="#dcdcd8", a=0.4):
    return mat(col, 1.0, alpha=a, dirt=0, var=0.05, wear=False)


# ------------------------------------------------------------------ geometry helpers
AX = {"Z": (0, 0, 0), "X": (0, 90, 0), "Y": (90, 0, 0)}
BUILT = []
FIXED = set()            # objects that keep their place whatever the facing (vane compass letters)
HEAD = [Matrix.Identity(4)]   # extra transform applied to everything built (for yawing a whole head)


def M(loc=(0, 0, 0), rot=(0, 0, 0)):
    return Matrix.Translation(Vector(loc)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()


def obj(bm, m, matrix=None, smooth=False, bevel=0.0, name="p"):
    """Finish a bmesh into an object in the model, applying the head transform."""
    bmesh.ops.transform(bm, matrix=HEAD[-1] @ (matrix or Matrix.Identity(4)), verts=bm.verts)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); MODEL.objects.link(ob); me.materials.append(m)
    if smooth:
        for p in me.polygons: p.use_smooth = True
        try: me.set_sharp_from_angle(angle=math.radians(35))
        except Exception:
            try: me.use_auto_smooth = True; me.auto_smooth_angle = math.radians(35)
            except Exception: pass
    if bevel > 0:
        md = ob.modifiers.new("b", "BEVEL"); md.width = bevel; md.segments = 2; md.limit_method = "ANGLE"
    BUILT.append(ob)
    return ob


def box(size, loc, m, rot=(0, 0, 0), bevel=0.006):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return obj(bm, m, M(loc, rot), bevel=min(bevel, min(size) * 0.3))


def cyl(r, h, loc, m, axis="Z", segs=24, r2=None, rot=None, smooth=True, caps=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    return obj(bm, m, M(loc, rot if rot is not None else AX[axis]), smooth=smooth)


def tube(p0, p1, r, m, segs=12, r2=None):
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=d.length)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return obj(bm, m, Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4(), smooth=True)


def path(pts, r, m, segs=10):
    """A bent pipe or cable through points, with small joints so bends look solid."""
    for a, b in zip(pts, pts[1:]): tube(a, b, r, m, segs)
    for p in pts[1:-1]: ball(r, p, m, segs=segs)


def ball(r, loc, m, scale=(1, 1, 1), segs=16):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(6, segs // 2), radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    return obj(bm, m, M(loc), smooth=True)


def torus(R, r, loc, m, axis="Z", seg=32, rseg=8, rot=None):
    bm = bmesh.new(); rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg; ring = []
        for j in range(rseg):
            b_ = 2 * math.pi * j / rseg; rr = R + r * math.cos(b_)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b_))))
        rings.append(ring)
    for i in range(seg):
        for j in range(rseg):
            bm.faces.new((rings[i][j], rings[(i + 1) % seg][j], rings[(i + 1) % seg][(j + 1) % rseg],
                          rings[i][(j + 1) % rseg]))
    return obj(bm, m, M(loc, rot if rot is not None else AX[axis]), smooth=True)


def blade_bm(length, w0, w1, thick, twist, pitch=0.0, curve=0.0):
    """A tapered, twisted blade from the origin along +Z, chord along X."""
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.5],
                              cuts=4)
    for v in bm.verts:
        t = v.co.z + 0.5; w = w0 + (w1 - w0) * t
        x, y = v.co.x * w, v.co.y * thick + curve * (v.co.x * 2) ** 2 * w
        a = math.radians(pitch + twist * t)
        v.co.x, v.co.y, v.co.z = x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a), t * length
    return bm


def rect(x0, x1, y0, y1, z, r, m):
    """A rectangle of tube, like a frame rail."""
    pts = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z), (x0, y0, z)]
    for a, b in zip(pts, pts[1:]): tube(a, b, r, m, 10)
    for p in pts[:4]: ball(r, p, m, segs=10)


def wheel(c, r, w, m_tire, m_rim, axis="X", spokes=0, m_spoke=None, blur=False, tire=True):
    """Spoked or solid wheel; `blur` swaps the spokes for a motion-blurred disc."""
    c = Vector(c)
    if tire: torus(r - 0.02, 0.022, c, m_tire, axis=axis, seg=40)
    torus(r - 0.045, 0.01, c, m_rim, axis=axis, seg=40)
    cyl(0.025, w, c, m_rim, axis=axis, segs=12)
    if blur:
        cyl(r - 0.05, 0.004, c, mat("#8a8d90", 0.6, alpha=0.35, dirt=0, wear=False), axis=axis, segs=40)
    elif spokes:
        for i in range(spokes):
            a = 2 * math.pi * i / spokes
            d = Vector((0, math.cos(a), math.sin(a))) if axis == "X" else Vector((math.cos(a), 0, math.sin(a)))
            tube(c, c + d * (r - 0.05), 0.0035, m_spoke or m_rim, 5)


def puffs(at, n, size, col="#dcdcd8", a=0.4, rise=(0.0, 0.0, 1.0), seed=1):
    """A short plume of soft translucent balls."""
    rnd = random.Random(seed); at = Vector(at); rise = Vector(rise)
    for i in range(n):
        k = i / max(1, n - 1)
        p = at + rise * (0.08 + 0.32 * k) + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * 0.03 * (1 + k)
        ball(size * (0.5 + 0.8 * k), p, puff(col, a * 0.75 * (1 - 0.5 * k)), segs=14)


def tape(c, r, axis="Z", w=0.03):
    """A wrap of grey duct tape."""
    cyl(r, w, c, mat("#a4a7a6", 0.45, var=0.08, dirt=0.25), axis=axis, segs=14)


def lamp(loc, lit, col="#57d36a", r=0.016):
    ball(r, loc, glow(col, 12) if lit else mat("#2c3a30", 0.25, dirt=0), segs=10)


def gauge(loc, rot, r=0.04, needle=0.0, rim="#8e9196"):
    """Round dial facing -Y before `rot`."""
    R = M(loc, rot)
    b1 = bmesh.new(); bmesh.ops.create_cone(b1, cap_ends=True, cap_tris=False, segments=20, radius1=r, radius2=r, depth=0.02)
    obj(b1, mat(rim, 0.35, 0.7, dirt=0.2), R @ M((0, 0.0, 0), (90, 0, 0)), smooth=True)
    b2 = bmesh.new(); bmesh.ops.create_cone(b2, cap_ends=True, cap_tris=False, segments=20, radius1=r * 0.82, radius2=r * 0.82, depth=0.004)
    obj(b2, mat("#e8e2cf", 0.5, dirt=0.15), R @ M((0, -0.011, 0), (90, 0, 0)), smooth=True)
    b3 = bmesh.new(); bmesh.ops.create_cube(b3, size=1.0); bmesh.ops.scale(b3, vec=(0.004, 0.003, r * 0.7), verts=b3.verts)
    obj(b3, mat("#1a1a1a", 0.5, dirt=0), R @ M((0, -0.014, 0), (0, -50 + 100 * needle, 0)) @ M((0, 0, r * 0.3)))


# ------------------------------------------------------------------ palette (muted, base-game feel)
def P():
    return {
        "wood": mat("#8b7155", 0.85, var=0.2, dirt=0.35), "wood_grey": mat("#86796a", 0.9, var=0.22, dirt=0.35),
        "wood_dark": mat("#5f4a36", 0.85, var=0.2), "ply": mat("#a8916b", 0.85, var=0.18),
        "steel": mat("#8d9196", 0.42, 0.65, var=0.1, dirt=0.25), "steel_dark": mat("#4b4e52", 0.5, 0.5, dirt=0.3),
        "galv": mat("#a3a6a3", 0.5, 0.55, var=0.14, dirt=0.25), "iron": mat("#38383a", 0.65, 0.3, var=0.12, dirt=0.3),
        "alu": mat("#a9a7a0", 0.45, 0.5, dirt=0.35), "rubber": mat("#242426", 0.85, dirt=0.15),
        "plastic": mat("#2c2d30", 0.55, dirt=0.2), "concrete": mat("#8e8a83", 0.95, var=0.18, dirt=0.3),
        "cinder": mat("#7f7d77", 0.95, var=0.2, dirt=0.35), "brass": mat("#b08c4a", 0.35, 0.8, dirt=0.2),
        "copper": mat("#a5663f", 0.4, 0.8, dirt=0.25), "wire_r": mat("#8e2c26", 0.6, dirt=0.1),
        "wire_k": mat("#1f1f21", 0.6, dirt=0.1), "glass": mat("#9fb3b6", 0.08, alpha=0.45, dirt=0, wear=False),
        "dark": mat("#141414", 0.9, dirt=0, wear=False),
    }


# ------------------------------------------------------------------ pedal generators
def build_pedal(tier, state):
    p = P(); on = state == "on"
    if tier == "makeshift":
        for x in (-0.2, 0.2): box((0.08, 0.86, 0.06), (x, 0.0, 0.03), p["wood"])
        for y in (-0.33, -0.05, 0.3): box((0.56, 0.1, 0.025), (0, y, 0.072), p["wood_grey"])
        box((0.16, 0.13, 0.12), (0, -0.3, 0.145), p["wood_dark"])
        paint = mat("#8a3c31", 0.55, 0.2, rust=0.35, dirt=0.3)
        ax = Vector((0, 0.17, 0.33))
        for x in (-0.11, 0.11):                       # rear stand posts
            box((0.045, 0.045, 0.36), (x, 0.17, 0.18), p["wood"]); box((0.045, 0.2, 0.045), (x, 0.17, 0.03), p["wood"])
        tube((-0.11, 0.17, 0.33), (0.11, 0.17, 0.33), 0.008, p["steel"])
        bb, seat, head0, head1 = Vector((0, -0.02, 0.3)), Vector((0, 0.05, 0.74)), Vector((0, -0.28, 0.52)), Vector((0, -0.31, 0.76))
        for a, b in ((bb, seat), (seat + Vector((0, -0.02, -0.02)), head1 + Vector((0, 0.01, -0.03))), (bb, head0),
                     (bb, ax), (seat + Vector((0, -0.01, -0.03)), ax), (head0, head1)):
            tube(a, b, 0.017, paint)
        tube(head0, (0, -0.3, 0.2), 0.013, paint); tape((0, -0.3, 0.22), 0.026, "Y", 0.05)
        tube((0, -0.33, 0.8), (0, -0.33, 0.84), 0.012, p["steel"])
        tube((-0.2, -0.36, 0.84), (0.2, -0.36, 0.84), 0.011, p["steel"])
        for x in (-0.2, 0.2): tube((x, -0.36, 0.84), (x * 0.95, -0.38, 0.84), 0.016, p["rubber"]); tube((x * 1.05, -0.36, 0.84), (x * 1.18, -0.37, 0.84), 0.017, p["rubber"])
        box((0.11, 0.2, 0.045), (0, 0.07, 0.78), p["rubber"], bevel=0.02)
        tube(seat, (0, 0.06, 0.76), 0.012, p["steel"])
        wheel(ax, 0.26, 0.05, p["rubber"], p["steel"], spokes=0 if on else 12, blur=on)
        cyl(0.075, 0.012, (0.04, -0.02, 0.3), p["steel_dark"], axis="X")
        for s in (1, -1):
            tube((0.06 * s, -0.02, 0.3), (0.06 * s, -0.02 + 0.11 * s, 0.3 - 0.06 * s), 0.008, p["steel"])
            box((0.07, 0.035, 0.015), (0.09 * s, -0.02 + 0.11 * s, 0.3 - 0.06 * s), p["plastic"])
        tube((0.045, -0.02, 0.37), (0.045, 0.17, 0.36), 0.004, p["iron"]); tube((0.045, -0.02, 0.23), (0.045, 0.17, 0.3), 0.004, p["iron"])
        # car alternator riding on the tyre, screwed to a board
        box((0.2, 0.12, 0.025), (0, 0.42, 0.075), p["ply"])
        cyl(0.065, 0.11, (0, 0.42, 0.16), p["alu"], axis="X"); cyl(0.03, 0.03, (-0.07, 0.42, 0.16), p["steel_dark"], axis="X")
        cyl(0.022, 0.05, (0.075, 0.42, 0.16), p["steel"], axis="X")
        for x in (-0.05, 0.05): tape((x, 0.42, 0.12), 0.07, "X", 0.025)
        path([(0.06, 0.45, 0.2), (0.15, 0.46, 0.2), (0.3, 0.42, 0.06), (0.42, 0.4, 0.02)], 0.007, p["wire_r"])
        path([(0.06, 0.46, 0.17), (0.17, 0.48, 0.15), (0.3, 0.46, 0.04), (0.42, 0.44, 0.02)], 0.007, p["wire_k"])
        tape((0.24, 0.45, 0.1), 0.016, "Z", 0.03)
        box((0.025, 0.045, 0.03), (0.0, -0.33, 0.885), p["plastic"]); lamp((0.0, -0.355, 0.89), on, "#ffc35a", 0.012)
    elif tier == "salvaged":
        paint = mat("#56708a", 0.5, 0.25, var=0.16, rust=0.2, dirt=0.3)
        for y in (-0.32, 0.3):
            tube((-0.26, y, 0.035), (0.26, y, 0.035), 0.024, paint)
            for x in (-0.27, 0.27): cyl(0.03, 0.04, (x, y, 0.03), p["rubber"], axis="X")
        tube((0, -0.32, 0.06), (0, 0.3, 0.06), 0.028, paint)
        tube((0, 0.15, 0.06), (0, 0.22, 0.72), 0.026, paint); tube((0, 0.22, 0.6), (0, 0.23, 0.78), 0.018, p["steel"])
        box((0.15, 0.24, 0.06), (0, 0.24, 0.81), p["rubber"], bevel=0.025)
        tube((0, -0.2, 0.06), (0, -0.3, 0.86), 0.026, paint)
        tube((-0.17, -0.35, 0.9), (0.17, -0.35, 0.9), 0.014, p["steel"])
        for x in (-0.17, 0.17): tube((x, -0.35, 0.9), (x, -0.45, 0.92), 0.019, p["rubber"])
        tube((0, -0.3, 0.86), (0, -0.35, 0.9), 0.016, p["steel"])
        fw = Vector((0, -0.12, 0.3))
        cyl(0.21, 0.05, fw, mat("#3a3c3f", 0.55, 0.4, rust=0.25) if not on else p["steel_dark"], axis="X", segs=40)
        if on: cyl(0.215, 0.054, fw, mat("#808488", 0.6, alpha=0.3, dirt=0, wear=False), axis="X", segs=40)
        else:
            for i in range(6):
                a = i * math.pi / 3; box((0.056, 0.02, 0.05), fw + Vector((0, math.cos(a), math.sin(a))) * 0.17, p["steel"], rot=(math.degrees(a), 0, 0))
        guard = mat("#4f6982", 0.55, var=0.15, dirt=0.3)
        for x in (-0.045, 0.045):
            bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=40, radius1=0.24, radius2=0.24, depth=0.01)
            for v in [v for v in bm.verts if v.co.x < -0.02]: v.co.x = -0.02
            obj(bm, guard, M(fw + Vector((x, 0, 0)), (0, 90, 0)) , smooth=True)
        cyl(0.025, 0.14, (0, 0.05, 0.3), p["steel"], axis="X")
        for s in (1, -1):
            tube((0.07 * s, 0.05, 0.3), (0.07 * s, 0.05 + 0.1 * s, 0.3 - 0.08 * s), 0.009, p["steel"])
            box((0.08, 0.035, 0.015), (0.1 * s, 0.05 + 0.1 * s, 0.3 - 0.08 * s), p["plastic"])
        # salvaged motor as generator, belted to the flywheel
        mo = Vector((0.0, 0.1, 0.12))
        cyl(0.07, 0.16, mo, mat("#2d3033", 0.5, 0.3, rust=0.2), axis="X"); cyl(0.072, 0.02, mo + Vector((0.08, 0, 0)), p["alu"], axis="X")
        cyl(0.072, 0.02, mo + Vector((-0.08, 0, 0)), p["alu"], axis="X")
        box((0.18, 0.12, 0.03), (0, 0.1, 0.06), p["steel_dark"])
        tube((-0.09, 0.1, 0.18), (-0.09, -0.08, 0.5), 0.006, p["rubber"]); tube((-0.09, 0.15, 0.1), (-0.09, -0.15, 0.1), 0.006, p["rubber"])
        cyl(0.025, 0.02, (-0.09, 0.1, 0.12), p["steel"], axis="X")
        box((0.12, 0.05, 0.09), (0, -0.33, 0.8), p["plastic"], rot=(-25, 0, 0))
        gauge((0.0, -0.36, 0.81), (-25, 0, 0), 0.03, 0.62 if on else 0.0)
        lamp((0.045, -0.36, 0.77), on, "#6fe07a", 0.009)
        path([(0.05, 0.12, 0.08), (0.2, 0.2, 0.03), (0.42, 0.25, 0.02)], 0.007, p["wire_k"])
    else:
        frame = mat("#56626b", 0.45, 0.35, var=0.1, dirt=0.18)
        box((0.6, 0.86, 0.05), (0, 0, 0.025), mat("#3e4144", 0.5, 0.4, dirt=0.25), bevel=0.01)
        for x in (-0.27, 0.27):
            for y in (-0.4, 0.4): cyl(0.025, 0.015, (x, y, 0.0), p["rubber"])
        box((0.05, 0.6, 0.05), (0, 0.05, 0.08), frame)
        box((0.045, 0.045, 0.66), (0, 0.24, 0.42), frame, rot=(-10, 0, 0))
        box((0.15, 0.25, 0.06), (0, 0.29, 0.79), p["rubber"], bevel=0.025)
        box((0.045, 0.045, 0.72), (0, -0.3, 0.44), frame, rot=(8, 0, 0))
        tube((-0.18, -0.36, 0.83), (0.18, -0.36, 0.83), 0.014, p["steel"])
        for x in (-0.18, 0.18): tube((x, -0.36, 0.83), (x, -0.45, 0.85), 0.019, p["rubber"])
        # enclosed flywheel and generator
        hous = mat("#5b6a73", 0.45, 0.3, var=0.1, dirt=0.15)
        cyl(0.24, 0.12, (0, -0.06, 0.32), hous, axis="X", segs=48)
        cyl(0.2, 0.124, (0, -0.06, 0.32), mat("#4b5860", 0.5, 0.3, dirt=0.2), axis="X", segs=48)
        if on: cyl(0.16, 0.13, (0, -0.06, 0.32), mat("#9aa1a5", 0.6, alpha=0.25, dirt=0, wear=False), axis="X", segs=40)
        for i in range(5):
            a = 2 * math.pi * i / 5 + 0.3
            box((0.13, 0.02, 0.08), (0, -0.06 + math.cos(a) * 0.11, 0.32 + math.sin(a) * 0.11), mat("#2a2e31", 0.6, dirt=0),
                rot=(math.degrees(a), 0, 0))
        box((0.13, 0.03, 0.06), (0.0, 0.13, 0.12), p["dark"])
        box((0.22, 0.2, 0.2), (0, 0.15, 0.17), hous, bevel=0.015)
        for i in range(5): box((0.005, 0.12, 0.012), (0.112, 0.15, 0.1 + i * 0.03), p["dark"])
        cyl(0.02, 0.14, (0, -0.01, 0.32), p["steel"], axis="X")
        for s in (1, -1):
            tube((0.08 * s, -0.01, 0.32), (0.08 * s, -0.01 + 0.1 * s, 0.32 - 0.08 * s), 0.01, p["steel"])
            box((0.09, 0.035, 0.016), (0.11 * s, -0.01 + 0.1 * s, 0.32 - 0.08 * s), p["plastic"])
        box((0.16, 0.06, 0.1), (0, -0.32, 0.8), p["plastic"], rot=(-30, 0, 0), bevel=0.01)
        gauge((-0.035, -0.35, 0.805), (-30, 0, 0), 0.03, 0.7 if on else 0.0, rim="#c9ccd0")
        lamp((0.04, -0.35, 0.82), on, "#6fe07a", 0.011); lamp((0.04, -0.36, 0.79), False, "#d84a3a", 0.011)
        path([(0.1, 0.25, 0.12), (0.2, 0.36, 0.06), (0.24, 0.43, 0.05)], 0.012, p["wire_k"])
        box((0.08, 0.05, 0.06), (0.24, 0.43, 0.08), mat("#c9a23a", 0.5, dirt=0.2))


# ------------------------------------------------------------------ windmills
def rotor(hub, n, length, w0, w1, m, state, twist=18, pitch=12, curve=0.0, hubm=None, hub_r=0.05, broken_style="drop"):
    """Blades in the XZ plane round `hub`, facing -Y; states blur, stop or break them."""
    hub = Vector(hub); turning = state == "turning"
    bm_alpha = mat("#b9b8b0", 0.7, alpha=0.45, dirt=0, wear=False) if turning else m
    start = 17.0 if turning else 0.0
    # Spin frames (windspin rows): solid blades stepped a quarter of one blade's share of the turn per frame.
    if state.startswith("spin"):
        start = (360.0 / n / 4) * (int(state[4:]) - 1)
    if state == "wobble":
        start, state = 10.0, "broken"                                 # the broken rotor rocked off its rest
    for i in range(n):
        a = start + 360.0 * i / n
        if state == "broken":
            if i == 1: continue                                           # snapped clean off
            if i == 2 and broken_style == "drop":
                obj(blade_bm(length * 0.8, w0, w1, 0.012, twist, pitch, curve), m, M(hub, (0, 160, 0)) @ M((0, 0, 0), (25, 0, 0)))
                continue
            if i == 2:
                obj(blade_bm(length * 0.45, w0, (w0 + w1) / 2, 0.012, twist * 0.5, pitch, curve), m, M(hub, (0, a, 0)))
                continue
        obj(blade_bm(length, w0, w1, 0.012, twist, pitch, curve), bm_alpha, M(hub, (0, a, 0)))
    if turning:
        cyl(length * 0.97, 0.003, hub, mat("#c7c6be", 0.8, alpha=0.16, dirt=0, wear=False), axis="Y", segs=48)
    cyl(hub_r, 0.06, hub + Vector((0, -0.02, 0)), hubm or m, axis="Y", segs=20)


def build_windmill(tier, state):
    p = P()
    yaw = 78.0 if state == "furled" else 0.0
    brk = state in ("broken", "wobble")
    if tier == "makeshift":
        H = 2.02; post = p["wood_grey"]
        for rot in (0, 90): box((0.82, 0.09, 0.06), (0, 0, 0.03), p["wood"], rot=(0, 0, rot))
        for a in (0, 90, 180, 270):
            d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
            tube(d * 0.36 + Vector((0, 0, 0.06)), d * 0.05 + Vector((0, 0, 0.62)), 0.022, p["wood"], 4)
        box((0.1, 0.1, H - 0.05), (0, 0, (H - 0.05) / 2), post)
        cyl(0.012, 0.03, (0.06, 0, 0.3), p["steel"], axis="X")
        path([(0.055, 0.0, H - 0.15), (0.055, 0.01, 0.9), (0.06, 0.02, 0.4), (0.12, 0.12, 0.02), (0.3, 0.3, 0.02)], 0.008, p["wire_k"])
        for z in (1.6, 1.1, 0.55): tape((0.055, 0.0, z), 0.016, "Z", 0.03)
        HEAD.append(M((0, 0, 0), (0, 0, yaw)) @ (M((0, 0.05, H - 0.1), (-12, 0, 8)) @ M((0, -0.05, -H + 0.1)) if brk else Matrix.Identity(4)))
        box((0.09, 0.42, 0.035), (0, 0.12, H - 0.06), p["wood"])
        cyl(0.07, 0.15, (0, -0.02, H), p["alu"], axis="Y"); cyl(0.04, 0.04, (0, 0.07, H), p["steel_dark"], axis="Y")
        for y in (-0.06, 0.03): tape((0, y, H - 0.04), 0.075, "Y", 0.025)
        tail_rot = (0, 0, 22) if brk else (0, 0, 0)
        box((0.025, 0.32, 0.025), (0, 0.42, H - 0.05), p["wood"], rot=tail_rot)
        box((0.012, 0.26, 0.24), (0.06 if brk else 0, 0.58, H + 0.04), p["ply"], rot=(0, 18, 25) if brk else (0, 0, 0))
        rotor((0, -0.12, H), 3, 0.56, 0.1, 0.05, mat("#b3b0a4", 0.55, var=0.1, dirt=0.25), state, curve=0.25,
              hubm=p["ply"], hub_r=0.07)
        HEAD.pop()
    elif tier == "salvaged":
        H = 2.12
        for a in (30, 150, 270):
            d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
            tube(d * 0.38 + Vector((0, 0, 0.1)), Vector((0, 0, 0.95)), 0.018, p["galv"])
            box((0.19, 0.39, 0.19), d * 0.38 + Vector((0, 0, 0.095)), p["cinder"], rot=(0, 0, a))
        cyl(0.035, H - 0.08, (0, 0, (H - 0.08) / 2), p["galv"], segs=16)
        path([(0.04, 0, 1.8), (0.04, 0.0, 0.2), (0.15, 0.1, 0.02), (0.3, 0.32, 0.02)], 0.008, p["wire_k"])
        HEAD.append(M((0, 0, 0), (0, 0, yaw)) @ (M((0, 0.05, H - 0.1), (-14, 0, -6)) @ M((0, -0.05, -H + 0.1)) if brk else Matrix.Identity(4)))
        cyl(0.05, 0.08, (0, 0, H - 0.1), p["steel_dark"])
        cyl(0.085, 0.24, (0, 0.0, H), mat("#5b6255", 0.55, 0.3, rust=0.3), axis="Y")
        cyl(0.088, 0.03, (0, 0.11, H), p["steel_dark"], axis="Y")
        tube((0, 0.1, H), (0, 0.5, H + 0.02), 0.016, p["galv"])
        sign = mat("#c3a03e", 0.6, 0.2, var=0.2, rust=0.25, dirt=0.3)
        rs = (40, 0, 20) if brk else (45, 0, 0)
        box((0.01, 0.3, 0.3), (0.05 if brk else 0, 0.58, H + 0.03), sign, rot=(rs[0], 0, rs[2]) if brk else (45, 0, 0))
        box((0.006, 0.31, 0.31), (0.05 if brk else 0, 0.58, H + 0.03), mat("#1e1e1e", 0.7, dirt=0.1), rot=(rs[0], 0, rs[2]) if brk else (45, 0, 0))
        rotor((0, -0.15, H), 6, 0.5, 0.11, 0.13, mat("#405f7c", 0.55, 0.3, var=0.18, rust=0.35), state, twist=8, pitch=28,
              curve=0.4, hubm=p["steel_dark"], hub_r=0.07)
        HEAD.pop()
    else:
        H = 2.04; white = mat("#cbcbc3", 0.45, 0.1, var=0.06, dirt=0.15)
        box((0.6, 0.6, 0.1), (0, 0, 0.05), p["concrete"], bevel=0.01)
        for x in (-0.2, 0.2):
            for y in (-0.2, 0.2): cyl(0.016, 0.03, (x, y, 0.11), p["steel"], segs=6)
        cyl(0.11, 0.03, (0, 0, 0.115), p["steel_dark"], segs=20)
        cyl(0.07, H - 0.12, (0, 0, (H - 0.12) / 2 + 0.1), white, r2=0.045, segs=24)
        box((0.12, 0.08, 0.16), (0, -0.09, 0.42), mat("#7d8285", 0.45, 0.4), bevel=0.01)
        path([(0, -0.09, 0.34), (0, -0.12, 0.13), (0, -0.25, 0.1), (0, -0.33, 0.02)], 0.014, p["steel_dark"])
        HEAD.append(M((0, 0, 0), (0, 0, yaw)) @ (M((0, 0.0, H - 0.1), (-10, 0, 0)) @ M((0, 0, -H + 0.1)) if brk else Matrix.Identity(4)))
        cyl(0.085, 0.34, (0, 0.02, H), white, axis="Y", segs=24)
        ball(0.085, (0, 0.19, H), white, scale=(1, 0.8, 1))
        ball(0.06, (0, -0.2, H), white, scale=(1, 1.5, 1))
        tube((0, 0.18, H), (0, 0.5, H + 0.03), 0.018, white)
        fin = bmesh.new(); bmesh.ops.create_cube(fin, size=1.0)
        for v in fin.verts:
            v.co.x *= 0.012; v.co.y = v.co.y * 0.3; v.co.z = v.co.z * (0.12 + 0.22 * (v.co.y / 0.3 + 0.5))
        obj(fin, white, M((0.03 if brk else 0, 0.6, H + 0.05), (0, 0, 30) if brk else (0, 0, 0)))
        rotor((0, -0.22, H), 3, 0.55, 0.075, 0.03, white, state, twist=24, pitch=10, curve=0.15, hubm=white,
              hub_r=0.04, broken_style="snap")
        HEAD.pop()


# ------------------------------------------------------------------ steam engines
def fire(opening, w, h, state, depth=0.04):
    """Firebox mouth at `opening` (front face centre, facing -Y)."""
    o = Vector(opening)
    if state == "running":
        box((w, depth, h), o + Vector((0, depth / 2 + 0.002, 0)), glow("#ff9a3c", 8))
        ld = bpy.data.lights.new("f", "POINT"); ld.energy = 9; ld.color = (1.0, 0.55, 0.2); ld.shadow_soft_size = 0.05
        lo = bpy.data.objects.new("f", ld); MODEL.objects.link(lo); lo.location = HEAD[-1] @ (o + Vector((0, -0.08, 0))); BUILT.append(lo)
    elif state == "warming":
        box((w, depth, h), o + Vector((0, depth / 2 + 0.002, 0)), glow("#c4521f", 4))
    else:
        box((w, depth, h), o + Vector((0, depth / 2 + 0.002, 0)), mat("#1b1816", 0.95, dirt=0, wear=False))


def flywheel(c, r, w, m, state, spokes=6):
    c = Vector(c)
    torus(r - 0.02, 0.022, c, m, axis="X", seg=40)
    cyl(0.03, w + 0.04, c, m, axis="X", segs=12)
    if state == "running":
        cyl(r - 0.03, 0.006, c, mat("#5a5552", 0.7, alpha=0.4, dirt=0, wear=False), axis="X", segs=40)
    else:
        for i in range(spokes):
            a = 2 * math.pi * i / spokes + 0.2
            tube(c, c + Vector((0, math.cos(a), math.sin(a))) * (r - 0.03), 0.011, m, 6)


def build_steam(tier, state):
    p = P(); run = state == "running"; warm = state in ("running", "warming"); brk = state == "broken"
    smoke_n = 7 if run else (3 if state == "warming" else 0)
    if tier == "makeshift":
        box((0.86, 0.8, 0.02), (0, 0.02, 0.01), mat("#6f6a62", 0.95, var=0.25, dirt=0.4))
        for x, y, sx, sy in ((-0.32, 0.1, 0.18, 0.5), (0.22, 0.1, 0.18, 0.5), (-0.05, 0.31, 0.38, 0.12)):
            for z in (0.08, 0.24): box((sx, sy, 0.15), (x, y, z), p["cinder"], bevel=0.004)
        box((0.22, 0.12, 0.08), (-0.05, -0.1, 0.28), p["cinder"])
        fire((-0.05, -0.16, 0.12), 0.24, 0.17, state)
        drum = mat("#5a6c74", 0.55, 0.3, var=0.2, rust=0.45, dirt=0.35)
        cyl(0.21, 0.66, (-0.05, 0.1, 0.52), drum, axis="X", segs=32)
        for x in (-0.22, 0.12): cyl(0.215, 0.02, (x, 0.1, 0.52), drum, axis="X", segs=32)
        cyl(0.03, 0.03, (0.05, 0.1, 0.735), p["steel_dark"])
        gauge((-0.15, -0.115, 0.55), (0, 0, 0), 0.035, 0.55 if run else (0.25 if warm else 0.0))
        ch_top = (-0.3, 0.33, 1.62) if not brk else (-0.4, 0.38, 1.52)
        tube((-0.3, 0.3, 0.6), ch_top, 0.05, p["iron"], 16)
        cyl(0.075, 0.06, Vector(ch_top) + Vector((0, 0, 0.07)), p["iron"], r2=0.02, segs=16)
        path([(0.18, 0.1, 0.72), (0.18, -0.02, 0.8), (0.3, -0.2, 0.8), (0.3, -0.24, 0.42)], 0.016, p["copper"])
        box((0.4, 0.2, 0.04), (0.24, -0.27, 0.06), p["wood"])
        box((0.16, 0.14, 0.18), (0.22, -0.26, 0.17), mat("#4a4a48", 0.6, 0.3, rust=0.3))
        for i in range(4): box((0.17, 0.15, 0.008), (0.22, -0.26, 0.27 + i * 0.018), p["steel_dark"])
        cyl(0.04, 0.12, (0.22, -0.26, 0.38), p["steel_dark"])
        flywheel((0.36, -0.26, 0.25), 0.17, 0.04, p["iron"], state)
        cyl(0.06, 0.1, (0.22, -0.43, 0.09), p["alu"], axis="X")
        tube((0.38, -0.26, 0.09), (0.38, -0.43, 0.06), 0.005, p["rubber"]); tube((0.38, -0.26, 0.42), (0.28, -0.43, 0.13), 0.005, p["rubber"])
        path([(0.16, -0.43, 0.09), (0.05, -0.42, 0.02), (-0.3, -0.42, 0.02)], 0.007, p["wire_k"])
        chimney = Vector(ch_top) + Vector((0, 0, 0.1))
        exh = Vector((0.22, -0.26, 0.45))
    elif tier == "salvaged":
        box((0.84, 0.78, 0.03), (0, 0.02, 0.015), p["steel_dark"])
        stove = mat("#333436", 0.6, 0.4, rust=0.3)
        box((0.38, 0.38, 0.3), (-0.14, 0.12, 0.18), stove, bevel=0.01)
        box((0.2, 0.02, 0.15), (-0.14, -0.08, 0.16), stove)
        fire((-0.14, -0.072, 0.16), 0.14 if state != "cold" else 0.14, 0.09, state if state != "broken" else "cold", 0.01)
        tank = mat("#c3bdb1", 0.5, 0.1, var=0.12, rust=0.3, dirt=0.35)
        cyl(0.17, 0.62, (-0.14, 0.12, 0.64), tank, segs=32); ball(0.17, (-0.14, 0.12, 0.95), tank, scale=(1, 1, 0.3))
        cyl(0.02, 0.06, (-0.04, 0.05, 1.0), p["brass"]); box((0.06, 0.008, 0.008), (-0.01, 0.05, 1.03), p["brass"])
        gauge((-0.14, -0.05, 0.75), (0, 0, 0), 0.035, 0.6 if run else (0.3 if warm else 0.0))
        ch_rot = (12, -14, 0) if brk else (0, 0, 0)
        obj_c = cyl(0.045, 0.9, (-0.14, 0.12, 1.42), p["iron"], segs=16, rot=ch_rot)
        cyl(0.07, 0.04, (-0.14 + (0.1 if brk else 0), 0.12 + (-0.08 if brk else 0), 1.88), p["iron"], r2=0.03, segs=16)
        path([(-0.0, 0.12, 0.85), (0.12, 0.05, 0.85), (0.2, -0.1, 0.5), (0.2, -0.16, 0.32)], 0.015, p["copper"])
        box((0.3, 0.42, 0.05), (0.22, -0.12, 0.1), p["iron"])
        cyl(0.07, 0.2, (0.2, -0.2, 0.22), mat("#3e4a3d", 0.5, 0.3, rust=0.25), axis="Y")
        for y in (-0.31, -0.09): cyl(0.08, 0.02, (0.2, y, 0.22), p["steel"], axis="Y")
        tube((0.2, -0.1, 0.22), (0.2, 0.08, 0.24), 0.012, p["steel"])
        flywheel((0.34, 0.06, 0.25), 0.18, 0.04, p["iron"], state)
        cyl(0.07, 0.14, (0.24, 0.33, 0.12), p["alu"], axis="X")
        tube((0.36, 0.06, 0.07), (0.32, 0.33, 0.06), 0.005, p["rubber"]); tube((0.36, 0.06, 0.43), (0.32, 0.33, 0.19), 0.005, p["rubber"])
        path([(0.17, 0.33, 0.12), (0.1, 0.42, 0.03), (-0.2, 0.44, 0.02)], 0.007, p["wire_k"])
        chimney = Vector((-0.14 + (0.1 if brk else 0), 0.12 + (-0.08 if brk else 0), 1.92)); exh = Vector((0.2, -0.33, 0.26))
    else:
        green = mat("#3e5a46", 0.45, 0.25, var=0.1, dirt=0.15)
        box((0.88, 0.84, 0.06), (0, 0.02, 0.03), mat("#2f3a33", 0.5, 0.3, dirt=0.25), bevel=0.008)
        cyl(0.21, 0.8, (-0.17, 0.14, 0.47), green, segs=40); ball(0.21, (-0.17, 0.14, 0.87), green, scale=(1, 1, 0.35))
        for z in (0.18, 0.5, 0.82): torus(0.212, 0.008, (-0.17, 0.14, z), p["brass"], seg=40)
        box((0.14, 0.04, 0.11), (-0.17, -0.07, 0.2), p["iron"], bevel=0.008)
        fire((-0.17, -0.09, 0.2), 0.09, 0.06, state if not brk else "cold", 0.01)
        box((0.012, 0.012, 0.08), (-0.1, -0.1, 0.22), p["brass"])
        tube((0.05, 0.08, 0.35), (0.05, 0.08, 0.7), 0.012, p["glass"]); cyl(0.015, 0.03, (0.05, 0.08, 0.34), p["brass"]); cyl(0.015, 0.03, (0.05, 0.08, 0.71), p["brass"])
        gauge((-0.17, -0.08, 0.66), (0, 0, 0), 0.05, 0.62 if run else (0.3 if warm else 0.0), rim="#b08c4a")
        cyl(0.02, 0.08, (-0.08, 0.2, 0.96), p["brass"]); ball(0.025, (-0.08, 0.2, 1.01), p["brass"])
        ch = (-0.17, 0.14, 0.94); top = (-0.17, 0.14, 2.05) if not brk else (-0.34, 0.28, 1.95)
        tube(ch, top, 0.055, p["iron"], 16); cyl(0.075, 0.08, Vector(top) + Vector((0, 0, 0.04)), p["iron"], r2=0.058, segs=16)
        path([(-0.05, 0.14, 0.86), (0.15, 0.0, 0.86), (0.2, -0.18, 0.6), (0.2, -0.22, 0.3)], 0.016, p["copper"])
        box((0.22, 0.44, 0.08), (0.24, -0.14, 0.1), green, bevel=0.01)
        cyl(0.075, 0.18, (0.22, -0.26, 0.24), green, axis="Y"); cyl(0.082, 0.02, (0.22, -0.36, 0.24), p["brass"], axis="Y"); cyl(0.082, 0.02, (0.22, -0.16, 0.24), p["brass"], axis="Y")
        tube((0.22, -0.15, 0.24), (0.22, 0.0, 0.24), 0.012, p["steel"])
        flywheel((0.34, 0.02, 0.27), 0.22, 0.05, mat("#7a2c25", 0.5, 0.2, dirt=0.2), state)
        cyl(0.09, 0.2, (0.24, 0.32, 0.15), green, axis="X"); cyl(0.093, 0.02, (0.14, 0.32, 0.15), p["brass"], axis="X")
        box((0.06, 0.004, 0.03), (0.24, 0.226, 0.2), p["brass"])
        tube((0.37, 0.02, 0.06), (0.36, 0.32, 0.06), 0.006, p["rubber"]); tube((0.37, 0.02, 0.48), (0.36, 0.32, 0.24), 0.006, p["rubber"])
        path([(0.34, 0.4, 0.12), (0.38, 0.45, 0.04)], 0.01, p["wire_k"])
        chimney = Vector(top) + Vector((0, 0, 0.1)); exh = Vector((0.22, -0.37, 0.26))
    if smoke_n:
        puffs(chimney, smoke_n, 0.06 if run else 0.04, "#d7d6d2" if run else "#bfbebb", 0.42 if run else 0.25, (0.05, -0.08, 1.0), seed=3)
    if run:
        puffs(exh, 3, 0.035, "#eeeeea", 0.4, (-0.05, -0.1, 0.4), seed=5)
    if brk:
        box((0.004, 0.08, 0.16), (-0.05 if tier == "makeshift" else -0.2, -0.09, 0.6), p["dark"], rot=(0, 0, 20))
        rnd = random.Random(7)
        for i in range(4):
            box((rnd.uniform(0.04, 0.08), rnd.uniform(0.03, 0.06), 0.008), (rnd.uniform(-0.3, 0.3), rnd.uniform(-0.4, -0.3), 0.01),
                mat("#3c3631", 0.7, 0.3, rust=0.6), rot=(0, 0, rnd.uniform(0, 90)))
        cyl(0.15, 0.004, (0.0, -0.3, 0.002), mat("#121110", 0.95, alpha=0.6, dirt=0, wear=False), segs=24)


# ------------------------------------------------------------------ wind instruments
def build_windsock(tier, state):
    p = P(); FIXED_POLE = []
    cyl(0.09, 0.06, (0, 0, 0.03), p["concrete"], segs=16)
    cyl(0.022, 2.1, (0, 0, 1.08), p["galv"], segs=12)
    cyl(0.03, 0.05, (0, 0, 2.08), p["steel_dark"], segs=12)
    droop = {"limp": 78.0, "half": 38.0, "full": 6.0}[state]
    cloth = [mat("#d8d3c4", 0.95, var=0.25, dirt=0.35), mat("#b0412f", 0.8, var=0.2, dirt=0.3)]
    n = 6; L = 0.62 if state != "limp" else 0.55
    r0, r1 = (0.1, 0.05) if state == "full" else ((0.085, 0.04) if state == "half" else (0.06, 0.03))
    pos = Vector((0, -0.03, 2.05)); rnd = random.Random({"limp": 1, "half": 2, "full": 3}[state])
    torus(r0, 0.007, pos + Vector((0, 0, 0)), p["steel"], rot=(90 - 0, 0, 0))
    tube((0, 0, 2.05 + r0), pos + Vector((0, 0, r0)), 0.006, p["steel"]); tube((0, 0, 2.05 - r0), pos + Vector((0, 0, -r0)), 0.006, p["steel"])
    for i in range(n):
        t0, t1 = i / n, (i + 1) / n
        ang = math.radians(droop * (0.25 + 0.75 * t1) ** (0.6 if state == "limp" else 1.0))
        d = Vector((0, -math.cos(ang), -math.sin(ang)))
        seg = L / n
        a, b = pos, pos + d * seg
        ra, rb = r0 + (r1 - r0) * t0, r0 + (r1 - r0) * t1
        if state == "limp": ra *= 0.85 + rnd.uniform(-0.1, 0.1); rb *= 0.85 + rnd.uniform(-0.1, 0.1)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=18, radius1=ra, radius2=rb, depth=seg)
        if state != "full":
            for v in bm.verts: v.co.x *= 0.8 + rnd.uniform(-0.08, 0.08)
        q = Vector((0, 0, 1)).rotation_difference(d)
        obj(bm, cloth[i % 2], Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4(), smooth=True)
        pos = b


def build_vane(tier, state):
    p = P(); iron = mat("#2f2f30", 0.6, 0.4, var=0.15, rust=0.25, dirt=0.2)
    box((0.11, 0.11, 1.0), (0, 0, 0.5), p["wood_grey"])
    for rot in (0, 90): box((0.5, 0.08, 0.05), (0, 0, 0.025), p["wood"], rot=(0, 0, rot))
    cyl(0.018, 0.95, (0, 0, 1.45), p["galv"], segs=12)
    z = 1.55
    for d, letter in (((0, 1), "N"), ((0, -1), "S"), ((1, 0), "E"), ((-1, 0), "W")):
        e = Vector((d[0], d[1], 0))
        o = tube(Vector((0, 0, z)), e * 0.25 + Vector((0, 0, z)), 0.006, iron, 6); FIXED.add(o)
        cu = bpy.data.curves.new("t", "FONT"); cu.body = letter; cu.size = 0.11; cu.extrude = 0.006
        cu.align_x = "CENTER"; cu.materials.append(iron)
        t = bpy.data.objects.new("t", cu); MODEL.objects.link(t)
        t.location = e * 0.3 + Vector((0, 0, z - 0.035))
        t.rotation_euler = (math.radians(90), 0, math.radians(90) if d[0] == 0 else 0)
        FIXED.add(t); BUILT.append(t)
    zt = 1.82
    tube((0, -0.32, zt), (0, 0.3, zt), 0.007, iron, 6)
    head = bmesh.new()
    vs = [head.verts.new(v) for v in ((-0.005, -0.42, zt), (-0.005, -0.3, zt + 0.06), (-0.005, -0.3, zt - 0.06))]
    vs2 = [head.verts.new((0.005, v.co.y, v.co.z)) for v in vs]
    head.faces.new(vs); head.faces.new(list(reversed(vs2)))
    for i in range(3): head.faces.new((vs[i], vs[(i + 1) % 3], vs2[(i + 1) % 3], vs2[i]))
    obj(head, iron)
    tail = bmesh.new()
    pts = ((0.18, zt), (0.36, zt + 0.12), (0.42, zt + 0.12), (0.36, zt), (0.42, zt - 0.1), (0.36, zt - 0.1))
    vs = [tail.verts.new((-0.004, y, zz)) for y, zz in pts]; vs2 = [tail.verts.new((0.004, y, zz)) for y, zz in pts]
    tail.faces.new(vs); tail.faces.new(list(reversed(vs2)))
    for i in range(len(vs)): tail.faces.new((vs[i], vs[(i + 1) % len(vs)], vs2[(i + 1) % len(vs)], vs2[i]))
    obj(tail, iron)
    ball(0.025, (0, 0, zt), iron); cyl(0.012, 0.25, (0, 0, zt + 0.15), iron); ball(0.018, (0, 0, zt + 0.28), iron)


# ------------------------------------------------------------------ propane / petrol engines
def propane_tank(c, r=0.15, h=0.3, broken=False):
    p = P(); white = mat("#d6d2c7", 0.45, 0.15, var=0.08, rust=0.2 if broken else 0.05, dirt=0.3)
    c = Vector(c)
    cyl(r, h, c + Vector((0, 0, h / 2 + 0.03)), white, segs=28)
    ball(r, c + Vector((0, 0, h + 0.03)), white, scale=(1, 1, 0.45)); ball(r, c + Vector((0, 0, 0.03)), white, scale=(1, 1, 0.3))
    cyl(r * 0.8, 0.04, c + Vector((0, 0, 0.02)), white, segs=20)
    cyl(r * 0.62, 0.09, c + Vector((0, 0, h + 0.1)), white, segs=20, caps=False)
    cyl(0.018, 0.05, c + Vector((0, 0, h + 0.1)), p["brass"], segs=10)
    box((0.05, 0.012, 0.012), c + Vector((0.02, 0, h + 0.13)), mat("#2b2c30", 0.6, dirt=0))
    return c + Vector((0, 0, h + 0.1))


def jerry_can(c, rot=0):
    red = mat("#a8352b", 0.55, var=0.1, dirt=0.3)
    c = Vector(c); R = M(c, (0, 0, rot))
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(0.24, 0.13, 0.26), verts=b.verts)
    o = obj(b, red, R @ M((0, 0, 0.13)), bevel=0.025)
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(0.12, 0.03, 0.04), verts=b.verts)
    obj(b, red, R @ M((-0.03, 0, 0.29)), bevel=0.01)
    b = bmesh.new(); bmesh.ops.create_cone(b, cap_ends=True, cap_tris=False, segments=12, radius1=0.022, radius2=0.018, depth=0.05)
    obj(b, mat("#d4ac3c", 0.5, dirt=0.2), R @ M((0.08, 0, 0.29)), smooth=True)
    return c + Vector((0.0, 0, 0.27))


def build_gas(fuel, tier, state):
    p = P(); run = state == "running"; brk = state == "broken"
    body_col = "#c4bca6" if fuel == "propane" else "#a6352c"
    if tier == "makeshift":
        for x in (-0.33, 0, 0.33): box((0.06, 0.62, 0.08), (x, 0, 0.04), p["wood"])
        for i in range(5): box((0.78, 0.1, 0.022), (0, -0.26 + i * 0.13, 0.091), p["wood_grey"])
        eng = mat("#3a5a3c" if fuel == "propane" else "#8c2f28", 0.55, 0.2, rust=0.3, dirt=0.35)
        box((0.2, 0.2, 0.16), (-0.12, -0.08, 0.19), mat("#7c7d7b", 0.55, 0.4, rust=0.25))
        for i in range(4): box((0.21, 0.04, 0.008), (-0.12, -0.2, 0.15 + i * 0.03), p["alu"])
        b = box((0.24, 0.24, 0.12), (-0.12, -0.06, 0.32), eng, bevel=0.04)
        cyl(0.08, 0.02, (-0.12, -0.06, 0.39), mat("#2b2b2b", 0.5)); box((0.05, 0.015, 0.02), (-0.12, -0.2, 0.37), p["rubber"])
        box((0.08, 0.06, 0.08), (-0.27, -0.12, 0.2), p["iron"]); cyl(0.012, 0.05, (-0.32, -0.12, 0.22), p["iron"], axis="X")
        cyl(0.03, 0.1, (0.03, -0.08, 0.2), p["steel"], axis="X")
        cyl(0.075, 0.13, (0.15, -0.08, 0.2), p["alu"], axis="X"); cyl(0.04, 0.03, (0.23, -0.08, 0.2), p["steel_dark"], axis="X")
        for x in (0.09, 0.2): tape((x, -0.08, 0.2), 0.08, "X", 0.02)
        box((0.18, 0.06, 0.08), (0.15, -0.08, 0.14), p["wood_dark"])
        path([(0.2, -0.04, 0.25), (0.3, 0.05, 0.28), (0.4, 0.2, 0.1)], 0.007, p["wire_r"]); path([(0.2, -0.05, 0.22), (0.32, 0.0, 0.2), (0.42, 0.15, 0.1)], 0.007, p["wire_k"])
        if fuel == "propane":
            top = propane_tank((0.12, 0.2, 0.1), 0.12, 0.24, brk)
            box((0.28, 0.02, 0.025), (0.12, 0.2, 0.25), mat("#c86f24", 0.6, dirt=0.2))
            path([top, top + Vector((-0.06, -0.06, 0.05)), (-0.08, 0.1, 0.42), (-0.12, -0.02, 0.36)], 0.009, p["rubber"])
            cyl(0.025, 0.04, top + Vector((-0.06, -0.06, 0.05)), p["brass"])
        else:
            top = jerry_can((0.15, 0.2, 0.1), 0)
            path([top + Vector((0.08, 0, 0.02)), (0.0, 0.18, 0.45), (-0.12, -0.02, 0.36)], 0.006, mat("#c9c3a6", 0.3, alpha=0.7, dirt=0, wear=False))
        lamp((0.0, -0.27, 0.13), run, "#6fe07a", 0.012)
        exh = Vector((-0.37, -0.12, 0.22))
    elif tier == "salvaged":
        frame = mat("#262729", 0.5, 0.4, var=0.1, rust=0.25)
        rect(-0.32, 0.32, -0.21, 0.21, 0.05, 0.016, frame); rect(-0.32, 0.32, -0.21, 0.21, 0.52, 0.016, frame)
        for x in (-0.32, 0.32):
            for y in (-0.21, 0.21): tube((x, y, 0.05), (x, y, 0.52), 0.016, frame)
        for y in (-0.21, 0.21): cyl(0.022, 0.03, (-0.32, y, 0.02), p["rubber"])
        cyl(0.07, 0.04, (0.32, 0.25, 0.07), p["rubber"], axis="Y"); cyl(0.07, 0.04, (0.32, -0.25, 0.07), p["rubber"], axis="Y")
        box((0.24, 0.3, 0.06), (0.0, 0, 0.08), frame)
        box((0.22, 0.24, 0.2), (-0.13, 0.0, 0.22), mat("#5d5e5c", 0.55, 0.4, rust=0.2))
        for i in range(5): box((0.23, 0.2, 0.008), (-0.13, 0.0, 0.33 + i * 0.016), p["alu"])
        cyl(0.09, 0.03, (-0.13, -0.135, 0.24), p["plastic"], axis="Y"); box((0.05, 0.02, 0.02), (-0.13, -0.16, 0.3), p["rubber"])
        body = mat(body_col, 0.5, 0.15, var=0.12, rust=0.2, dirt=0.3)
        cyl(0.12, 0.24, (0.14, 0.0, 0.22), body, axis="X", segs=28)
        for i in range(5): box((0.008, 0.18, 0.012), (0.265, 0.0, 0.16 + i * 0.025), p["dark"])
        if fuel == "petrol":
            box((0.5, 0.3, 0.1), (0, 0, 0.47), body, bevel=0.04); cyl(0.03, 0.02, (0.1, 0.05, 0.53), p["plastic"])
        else:
            box((0.12, 0.1, 0.04), (-0.1, 0.0, 0.42), p["steel_dark"]); cyl(0.022, 0.05, (-0.1, 0.0, 0.46), p["brass"])
            path([(-0.1, 0.0, 0.47), (-0.1, 0.18, 0.48), (-0.05, 0.3, 0.42), (0.0, 0.34, 0.3)], 0.009, p["rubber"])
            propane_tank((-0.02, 0.36, 0.0), 0.1, 0.22, brk)
            box((0.1, 0.06, 0.12), (0.2, 0.17, 0.42), mat("#7a7c78", 0.5, 0.3, dirt=0.25))
            lamp((0.2, 0.135, 0.45), run, "#6fe07a", 0.01)
        box((0.24, 0.02, 0.15), (0.14, -0.215, 0.3), mat("#38393b", 0.5, 0.3))
        for x in (0.08, 0.18): box((0.04, 0.008, 0.05), (x, -0.226, 0.32), mat("#d0c9b5", 0.6, dirt=0.2))
        gauge((0.14, -0.23, 0.25), (0, 0, 0), 0.022, 0.6 if run else 0.0)
        lamp((0.24, -0.228, 0.36), run, "#6fe07a", 0.009)
        cyl(0.04, 0.14, (-0.3, 0.07, 0.3), p["iron"], axis="Y")
        exh = Vector((-0.3, -0.02, 0.3))
    else:
        body = mat(body_col, 0.5, 0.2, var=0.08, rust=0.0, dirt=0.15)
        box((0.82, 0.58, 0.05), (0, -0.03, 0.025), mat("#3a3c3e", 0.5, 0.3, dirt=0.25), bevel=0.01)
        box((0.76, 0.48, 0.5), (0, -0.05, 0.3), body, bevel=0.025)
        box((0.78, 0.5, 0.012), (0, -0.05, 0.47), mat("#3a3c3e", 0.5, 0.3))
        for s in (1, -1):
            for i in range(6): box((0.01, 0.26, 0.016), (0.38 * s, -0.05, 0.13 + i * 0.045), p["dark"], rot=(0, 25 * s, 0))
        for i in range(4): box((0.26, 0.01, 0.014), (0.18, -0.29, 0.14 + i * 0.04), p["dark"])
        box((0.22, 0.02, 0.15), (-0.18, -0.29, 0.33), mat("#2a2b2d", 0.45, 0.3))
        box((0.1, 0.008, 0.045), (-0.2, -0.302, 0.36), glow("#58b06a", 3) if run else mat("#1d2a20", 0.2, dirt=0))
        for x in (-0.26, -0.14): box((0.025, 0.012, 0.02), (x, -0.302, 0.29), mat("#b8b6ae", 0.5, dirt=0.1))
        lamp((-0.1, -0.302, 0.29), run, "#6fe07a", 0.01)
        cyl(0.03, 0.08, (0.42, 0.1, 0.42), p["iron"], axis="X")
        if fuel == "propane":
            white = mat("#d6d2c7", 0.45, 0.15, var=0.08, dirt=0.25)
            cyl(0.1, 0.5, (0, 0.33, 0.16), white, axis="X", segs=24)
            for x in (-0.25, 0.25): ball(0.1, (x, 0.33, 0.16), white, scale=(0.4, 1, 1))
            for x in (-0.18, 0.18): box((0.04, 0.2, 0.06), (x, 0.33, 0.04), p["steel_dark"])
            cyl(0.02, 0.06, (0.0, 0.33, 0.28), p["brass"]); path([(0, 0.33, 0.3), (0, 0.24, 0.36), (0, 0.19, 0.36)], 0.009, p["rubber"])
            cyl(0.025, 0.05, (0.26, 0.19, 0.2), p["brass"], axis="Y")
        else:
            cyl(0.04, 0.025, (0.25, 0.05, 0.56), p["plastic"]); box((0.06, 0.03, 0.02), (0.25, -0.29, 0.43), mat("#d6d2c4", 0.5))
            cyl(0.025, 0.05, (-0.3, 0.19, 0.2), p["brass"], axis="Y")
        exh = Vector((0.46, 0.1, 0.42))
    if run:
        puffs(exh, 4, 0.035, "#8a8884", 0.38, (0.35, 0.0, 0.6) if tier != "salvaged" else (-0.4, 0, 0.5), seed=9)
    if brk:
        cyl(0.2, 0.003, (0.05, -0.05, 0.002), mat("#0f0e0d", 0.15, alpha=0.75, dirt=0, wear=False), segs=24)
        if tier == "manufactured":
            box((0.26, 0.012, 0.2), (0.22, -0.5, 0.11), body, rot=(-70, 0, 15))
            box((0.24, 0.01, 0.18), (0.18, -0.3, 0.22), p["dark"])
        rnd = random.Random(11)
        for i in range(3):
            box((0.05, 0.03, 0.01), (rnd.uniform(-0.35, 0.35), rnd.uniform(-0.45, -0.32), 0.006), p["steel_dark"], rot=(0, 0, rnd.uniform(0, 90)))


# ------------------------------------------------------------------ build & render
BUILDERS = {"pedal": build_pedal, "windmill": build_windmill, "steam": build_steam, "windsock": build_windsock,
            "vane": build_vane, "propane": lambda t, s: build_gas("propane", t, s), "petrol": lambda t, s: build_gas("petrol", t, s)}


def clear():
    for ob in list(MODEL.objects): bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.lights):
        for d in list(coll):
            if d.users == 0: coll.remove(d)
    BUILT.clear(); FIXED.clear()


def build(kind, tier, state, at=(0, 0, 0), yaw=0.0):
    """Build one machine; returns an empty holding the facing-rotated parts."""
    WEAR["rust"] = 0.35 if state == "broken" else 0.0
    WEAR["dirt"] = 0.15 if state == "broken" else 0.0
    WEAR["scorch"] = 0.7 if state == "broken" and kind in ("steam", "propane", "petrol") else 0.0
    start = len(BUILT)
    BUILDERS[kind](tier, state)
    root = bpy.data.objects.new("root", None); MODEL.objects.link(root)
    fixed = bpy.data.objects.new("fixed", None); MODEL.objects.link(fixed)
    for ob in BUILT[start:]:
        ob.parent = fixed if ob in FIXED else root
    root.location = fixed.location = Vector(at); root.rotation_euler = (0, 0, math.radians(yaw))
    return root


def render(path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_rows(kinds=None, only=None):
    tile_camera(); os.makedirs(os.path.join(OUT, "cells"), exist_ok=True)
    for r, (k, t, s) in enumerate(ROWS):
        if kinds and k not in kinds: continue
        if only and (k, t, s) not in only: continue
        clear(); root = build(k, t, s)
        for col, (fname, deg) in enumerate(FACINGS):
            root.rotation_euler = (0, 0, math.radians(deg))
            render(os.path.join(OUT, "cells", "%d.png" % (r * 4 + col)))
        log("row", r, k, t, s)


def render_align():
    tile_camera(); clear()
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    obj(bm, mat("#ff00ff", 1.0, dirt=0, wear=False))
    render(os.path.join(OUT, "align.png")); log("align done")


# ------------------------------------------------------------------ inventory icon models
def icon_camera(objs, res=256):
    pts = []
    for ob in objs:
        if ob.type == "MESH":
            pts += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    rot = CAM_ROT.to_matrix(); rx, ry = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    xs = [p.dot(rx) for p in pts]; ys = [p.dot(ry) for p in pts]
    c = sum(pts, Vector()) / len(pts)
    aim_camera(c, max(max(xs) - min(xs), max(ys) - min(ys)) * 1.12, (res, res))


def sprocket(c, r, teeth, m, w=0.012):
    c = Vector(c)
    cyl(r, w, c, m, axis="X", segs=max(24, teeth * 2))
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        box((w, 0.012, 0.016), c + Vector((0, math.cos(a), math.sin(a))) * (r + 0.006), m, rot=(math.degrees(a) - 90, 0, 0), bevel=0.002)
    cyl(r * 0.35, w + 0.004, c, mat("#3a3b3d", 0.4, 0.6, dirt=0), axis="X", segs=20)


def chain_loop(c, r, m):
    c = Vector(c)
    for i in range(28):
        a = 2 * math.pi * i / 28
        box((0.012, 0.014, 0.008), c + Vector((0, math.cos(a) * r, math.sin(a) * r * 0.5)), m, rot=(math.degrees(a) + 90, 0, 0), bevel=0.002)


def build_icon(name):
    p = P(); WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
    if name.startswith("OffGridGearKit"):
        steel = mat("#a4a8ac", 0.3, 0.8, dirt=0.15)
        sizes = {"Low": (0.16, 0.12, 0.09), "Stock": (0.12, 0.095, 0.075), "Racing": (0.09, 0.075, 0.06)}[name[len("OffGridGearKit"):]]
        for i, r in enumerate(sizes):
            sprocket((i * 0.03, 0, 0.2), r, int(r * 220), steel if name != "OffGridGearKitRacing" or i else mat("#9a2d28", 0.35, 0.6, dirt=0))
        chain_loop((0.0, 0.0, 0.03), 0.17, mat("#5a5d60", 0.4, 0.7, dirt=0.15))
        box((0.1, 0.06, 0.02), (0.02, 0.15, 0.03), mat("#c9b38a", 0.8, dirt=0.1))
    else:
        box((0.24, 0.16, 0.08), (0, 0, 0.04), mat("#232426", 0.5, 0.2, dirt=0.15), bevel=0.01)
        for i in range(9): box((0.008, 0.15, 0.05), (-0.1 + i * 0.025, 0, 0.1), p["alu"], bevel=0.002)
        box((0.09, 0.002, 0.04), (0.04, -0.081, 0.04), mat("#d7b43c", 0.6, dirt=0))
        for x, col in ((-0.08, "#9b2b26"), (-0.04, "#1c1c1c")):
            cyl(0.014, 0.03, (x, -0.06, 0.09), mat(col, 0.5)); cyl(0.006, 0.02, (x, -0.06, 0.11), p["brass"])
        torus(0.03, 0.012, (0.13, 0.05, 0.03), p["copper"], axis="X")
        path([(0.12, -0.08, 0.04), (0.2, -0.14, 0.03), (0.25, -0.12, 0.01)], 0.006, p["wire_r"])
        path([(0.1, -0.08, 0.03), (0.17, -0.17, 0.02), (0.23, -0.18, 0.01)], 0.006, p["wire_k"])


def render_icons():
    os.makedirs(os.path.join(OUT, "icons"), exist_ok=True)
    for name in ("OffGridGearKitLow", "OffGridGearKitStock", "OffGridGearKitRacing", "OffGridAmplifier"):
        clear(); start = len(BUILT); build_icon(name)
        icon_camera(BUILT[start:]); render(os.path.join(OUT, "icons", name + ".png")); log("icon", name)


# ------------------------------------------------------------------ Workshop diorama
def render_poster():
    clear(); WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
    grass = mat("#5d6a3a", 0.95, var=0.35, dirt=0.0, wear=False)
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=2.0); obj(bm, grass, M((0.5, 0.5, 0)))
    dirt = mat("#6e5c43", 0.95, var=0.3, dirt=0, wear=False)
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5); obj(bm, dirt, M((0.0, -0.5, 0.002)))
    for k, t, s, at, yaw in (("windmill", "manufactured", "turning", (1.0, 1.4, 0), 0), ("steam", "salvaged", "running", (-0.6, 0.9, 0), 0),
                             ("propane", "manufactured", "running", (1.2, 0.0, 0), 90), ("pedal", "salvaged", "off", (0.15, -0.45, 0), 0),
                             ("windsock", "basic", "full", (2.1, 1.6, 0), 0), ("petrol", "makeshift", "off", (2.05, 0.55, 0), 0)):
        build(k, t, s, at, yaw)
    aim_camera((0.5, 0.6, 0.8), 4.6, (1024, 1024))
    scene.cycles.samples = 160
    render(os.path.join(OUT, "poster_scene.png")); log("poster done")


for job in ([] if globals().get("DZ_LIBRARY") else JOBS):
    t0 = time.time()
    if job == "align": render_align()
    elif job == "all": render_rows()
    elif job == "test":
        render_rows(only={("propane", "manufactured", "running"), ("windmill", "makeshift", "still"), ("steam", "salvaged", "running"),
                          ("pedal", "makeshift", "off")})
    elif job.startswith("cells:"): render_rows(kinds=job[6:].split(","))
    elif job.startswith("rows:"): render_rows(only={tuple(x.split("/")) for x in job[5:].split(",")})
    elif job == "icons": render_icons()
    elif job == "poster": render_poster()
    log("job", job, "took %.0fs" % (time.time() - t0))
if not globals().get("DZ_LIBRARY"): log("finished")
