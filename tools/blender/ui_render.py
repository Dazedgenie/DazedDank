"""Blender script: renders the grow room dashboard and plant Inspect art at 2x for media/ui/DazedDank: the grow tent behind
plant photos, the reservoir tank (back and front layers, water drawn between in code) and the section icons.
Run inside Blender (4.2+ / 5.x): DD_UI_OUT = r"C:\\...\\ui"; exec(open(path).read())
Optional globals: DD_UI_OUT, DD_UI_SAMPLES (default 96), DD_UI_ONLY (list of names).
"""
import bpy
import math
import os

OUT = globals().get("DD_UI_OUT") or os.path.join(os.path.dirname(os.path.abspath(globals().get("__file__", "."))), "ui")
SAMPLES = globals().get("DD_UI_SAMPLES", 96)
ONLY = globals().get("DD_UI_ONLY")
U = 0.1          # one base pixel in Blender units; renders come out at 2 px per base pixel


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras, bpy.data.textures):
        for d in list(coll):
            coll.remove(d)


def srgb(r, g, b):
    """sRGB 0-255 to the linear values Blender's colour inputs take."""
    def f(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b))


def mat(name, col, rough=0.5, metal=0.0, emit=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Alpha"].default_value = alpha
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def put(obj, m, smooth=True):
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.use_smooth = smooth
    return obj


def at(x, z, y=0):
    return (x * U, y * U, z * U)


def box(w, d, h, m, x=0, z=0, y=0, bevel=0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at(x, z, y), rotation=rot)
    o = bpy.context.object
    o.scale = (w * U, d * U, h * U)
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel * U
        mod.segments = 4
    return put(o, m, smooth=False)


def cyl(r, h, m, x=0, z=0, y=0, rot=(0, 0, 0), verts=48, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r * U, depth=h * U, location=at(x, z, y), rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r * U, radius2=r2 * U, depth=h * U, location=at(x, z, y), rotation=rot)
    return put(bpy.context.object, m)


def ball(r, m, x=0, z=0, y=0, scale=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r * U, segments=32, ring_count=16, location=at(x, z, y), rotation=rot)
    o = bpy.context.object
    o.scale = scale
    return put(o, m)


def torus(R, r, m, x=0, z=0, y=0, rot=(math.pi / 2, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R * U, minor_radius=r * U, major_segments=64, minor_segments=16,
                                     location=at(x, z, y), rotation=rot)
    return put(bpy.context.object, m)


def setup(w, h, tilt=0.0, world=0.6, key=1.0):
    """Camera looking along +Y at a w x h base-pixel part, raised `tilt` degrees; soft key from the upper left."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = int(w * 2), int(h * 2)
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = max(w, h) * U
    co = bpy.data.objects.new("cam", cam)
    t = math.radians(tilt)
    co.location = (0, -100 * U * math.cos(t), 100 * U * math.sin(t))
    co.rotation_euler = (math.pi / 2 - t, 0, 0)
    sc.collection.objects.link(co)
    sc.camera = co
    for name, loc, power, size in (("key", (-60, -90, 90), 30000 * key, 80), ("fill", (70, -80, 10), 9000 * key, 120)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = power * U * U
        ld.size = size * U
        lo = bpy.data.objects.new(name, ld)
        lo.location = tuple(v * U for v in loc)
        lo.rotation_euler = (-lo.location).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(lo)
    wd = sc.world or bpy.data.worlds.new("w")
    sc.world = wd
    wd.use_nodes = True
    wd.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.5, 0.5, 1)
    wd.node_tree.nodes["Background"].inputs["Strength"].default_value = world


def shoot(name):
    os.makedirs(OUT, exist_ok=True)
    bpy.context.scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------ the grow tent behind plant photos

def photo_tent():
    # Crinkled mylar walls under a magenta-white LED glow, darker at the floor.
    setup(100, 150, world=0.2, key=0.4)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 4 * U, 0), rotation=(math.pi / 2, 0, 0))
    wall = bpy.context.object
    wall.scale = (110 * U, 160 * U, 1)
    bpy.ops.object.transform_apply(scale=True)
    sub = wall.modifiers.new("sub", "SUBSURF")
    sub.subdivision_type = "SIMPLE"
    sub.levels = sub.render_levels = 6
    tex = bpy.data.textures.new("crinkle", "VORONOI")
    tex.noise_scale = 3.5
    dis = wall.modifiers.new("dis", "DISPLACE")
    dis.texture = tex
    dis.strength = 0.12
    dis.direction = "Y"
    put(wall, mat("mylar", srgb(214, 214, 222), 0.45, 0.9))
    box(110, 30, 14, mat("floor", srgb(46, 40, 52), 0.8), z=-72, y=-10)
    for name, loc, col, power in (("led", (0, -40, 140), srgb(255, 150, 235), 120000), ("white", (40, -60, 150), srgb(255, 248, 240), 20000)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = power * U * U
        ld.size = 90 * U
        ld.color = col
        lo = bpy.data.objects.new(name, ld)
        lo.location = tuple(v * U for v in loc)
        lo.rotation_euler = (-lo.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.collection.objects.link(lo)


# ------------------------------------------------------------------ the reservoir tank

def tank_parts(front):
    black = mat("lid", srgb(36, 38, 40), 0.4, 0.3)
    if not front:
        box(34, 2, 38, mat("inside", srgb(214, 226, 232), 0.6), y=6, z=-1)
    box(38, 14, 6, black, z=21, bevel=1.5)
    box(38, 14, 4, black, z=-22, bevel=1.2)
    for x in (-18, 18):
        box(2, 14, 38, mat("edge", srgb(150, 170, 182), 0.3, 0.2), x=x, z=-1)
    if front:
        box(34, 1, 38, mat("glass", srgb(235, 245, 250), 0.05, 0, alpha=0.12), y=-7, z=-1)
        box(3, 1, 28, mat("shine", srgb(255, 255, 255), 0.05, 0, emit=srgb(255, 255, 255), strength=0.6, alpha=0.45),
            x=-11, y=-8, z=1)


def tank_back():
    setup(40, 48)
    tank_parts(False)


def tank_front():
    setup(40, 48)
    tank_parts(True)


# ------------------------------------------------------------------ section icons (16 px, rendered at 32)

def icon_setup():
    setup(16, 16, tilt=12, world=0.7)


def icon_bulb():
    icon_setup()
    glow = srgb(255, 214, 90)
    ball(4.6, mat("glass", glow, 0.2, emit=glow, strength=1.4), z=1.8)
    cyl(2.6, 3.6, mat("base", srgb(180, 180, 176), 0.25, 1.0), z=-4)
    ball(1.2, mat("tip", srgb(40, 40, 40), 0.4), z=-6.2)


def icon_thermo():
    icon_setup()
    red = srgb(220, 52, 40)
    cyl(1.6, 11, mat("tube", srgb(236, 240, 244), 0.15), z=1.5)
    cyl(0.8, 9, mat("mercury", red, 0.3, emit=red, strength=0.4), z=0, y=-0.9)
    ball(2.8, mat("bulb", red, 0.25, emit=red, strength=0.4), z=-5)


def icon_drop():
    icon_setup()
    blue = mat("water", srgb(64, 150, 226), 0.08, emit=srgb(64, 150, 226), strength=0.25)
    ball(4.6, blue, z=-2)
    cyl(4.4, 6.5, blue, z=3.4, r2=0.2)


def icon_lock():
    icon_setup()
    brass = mat("brass", srgb(214, 172, 70), 0.3, 1.0)
    torus(3.2, 1.0, mat("shackle", srgb(196, 196, 192), 0.25, 1.0), z=2.6)
    box(10, 4, 8, brass, z=-2.4, bevel=1.2)
    ball(1.0, mat("hole", srgb(40, 30, 20), 0.6), z=-2, y=-2.1)


def icon_leaf():
    icon_setup()
    green = mat("leaf", srgb(76, 160, 70), 0.5)
    lens = [4.4, 6.5, 8.3, 9.6, 8.3, 6.5, 4.4]
    for i, L in enumerate(lens):
        a = math.radians(-78 + i * 26)
        cx, cz = math.sin(a) * L / 2, -5 + math.cos(a) * L / 2
        ball(1, green, x=cx, z=cz, scale=(1.1, 0.2, L / 2), rot=(0, a, 0))
    cyl(0.5, 3, mat("stem", srgb(70, 120, 50), 0.6), z=-6.5)


def icon_bucket():
    icon_setup()
    cyl(4.6, 9, mat("bucket", srgb(52, 56, 62), 0.45), z=-1, r2=5.6)
    cyl(5.4, 0.4, mat("water", srgb(70, 150, 220), 0.1), z=3.3)
    torus(5.6, 0.5, mat("rim", srgb(70, 74, 80), 0.4), z=3.5, rot=(0, 0, 0))


def icon_fan():
    icon_setup()
    dark = mat("frame", srgb(52, 56, 62), 0.45, 0.3)
    box(13, 2, 13, dark, bevel=2)
    torus(5.4, 0.5, mat("guard", srgb(180, 182, 186), 0.3, 1.0), y=-1.4)
    blade = mat("blade", srgb(70, 170, 210), 0.35)
    for i in range(4):
        a = i * math.pi / 2 + 0.4
        box(2.2, 0.5, 4.6, blade, x=math.sin(a) * 2.6, z=math.cos(a) * 2.6, y=-1.2, rot=(0, a, 0))
    ball(1.2, dark, y=-1.6)


def icon_heart():
    icon_setup()
    red = mat("heart", srgb(214, 60, 72), 0.3)
    ball(3.2, red, x=-2.4, z=1.6)
    ball(3.2, red, x=2.4, z=1.6)
    cyl(5.2, 7, red, z=-2.8, r2=0.2, rot=(math.pi, 0, 0))


def icon_can():
    icon_setup()
    green = mat("can", srgb(70, 150, 90), 0.4, 0.2)
    cyl(3.6, 7, green, x=-1, z=-1.5)
    cyl(0.6, 7, green, x=3.5, z=0.8, rot=(0, math.radians(55), 0))
    torus(2.6, 0.6, green, x=-1, z=3, rot=(math.pi / 2, 0, 0))
    cyl(1.1, 0.8, green, x=6.3, z=2.8, rot=(0, math.radians(55), 0))


def icon_dna():
    icon_setup()
    a_m = mat("strandA", srgb(140, 70, 220), 0.35)
    b_m = mat("strandB", srgb(80, 170, 90), 0.35)
    rung = mat("rung", srgb(200, 200, 205), 0.4)
    for i in range(9):
        t = i * 0.7
        z = -6 + i * 1.5
        x = 3 * math.cos(t)
        y = 3 * math.sin(t)
        ball(1.0, a_m, x=x, y=y, z=z)
        ball(1.0, b_m, x=-x, y=-y, z=z)
        cyl(0.3, 6, rung, z=z, rot=(0, math.pi / 2, t))


PARTS = {
    "photo_tent": photo_tent, "tank_back": tank_back, "tank_front": tank_front,
    "icon_lights": icon_bulb, "icon_temp": icon_thermo, "icon_humid": icon_drop, "icon_seal": icon_lock,
    "icon_plants": icon_leaf, "icon_tank": icon_bucket, "icon_fan": icon_fan, "icon_vitals": icon_heart,
    "icon_care": icon_can, "icon_genetics": icon_dna,
}

for name, build in PARTS.items():
    if ONLY and name not in ONLY:
        continue
    clear()
    build()
    shoot(name)
print("DD UI DONE", OUT)
