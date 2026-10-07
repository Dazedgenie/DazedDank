"""Dazed Dank grow room art: the panel, blackout curtains, fans, floor and wall-mounted climate units, rendered with the PZ Sprite Forge rig.
Run: blender.exe -b -P room_art.py [-- sets...] (renders land in ./renders/<set>/); add "icons" to render inventory icons instead."""
from __future__ import annotations

import math
import shutil
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pz_sprite_forge as F  # noqa: E402

OUT = HERE / "renders"
WALL_Y = 0.5 - 0.035          # the face of a north wall, so wall-hung parts sit just in front of it
MATS = {}


def mat(name, cls, paint):
    """A cached forge material: flat paint in one of the measured material classes."""
    if name not in MATS:
        MATS[name] = F.forge_material(name, cls, paint)
    return MATS[name]


def box(parts, name, centre, size, material, rot=(0, 0, 0)):
    """Add a box by centre and full size (metres = tiles)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    obj.data.materials.append(material)
    parts.append(obj)
    return obj


def disc(parts, name, centre, radius, depth, material, axis="Y", verts=32):
    """Add a cylinder lying along Y (facing the room) or standing along Z."""
    rot = (math.pi / 2, 0, 0) if axis == "Y" else (0, 0, 0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=centre, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(material)
    parts.append(obj)
    return obj


def ring(parts, name, centre, radius, thickness, material):
    """Add a thin torus facing the room, for fan guards."""
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thickness, location=centre,
                                     rotation=(math.pi / 2, 0, 0), major_segments=40, minor_segments=8)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(material)
    parts.append(obj)
    return obj


# --------------------------------------------------------------------------- #
# Models. Wall pieces are built facing S (hung on the north wall); the rig turns them for the other facings.
# --------------------------------------------------------------------------- #

def build_panel():
    parts = []
    housing = mat("panel_housing", "metal", (0.16, 0.17, 0.21))
    face = mat("panel_face", "metal", (0.30, 0.32, 0.38))
    screen_bg = mat("panel_screen_bg", "metal", (0.04, 0.10, 0.07))
    screen = mat("panel_screen", "metal", (0.20, 0.75, 0.40))
    purple = mat("panel_led_purple", "metal", (0.57, 0.25, 0.93))
    lilac = mat("panel_led_lilac", "metal", (0.75, 0.52, 0.99))
    red = mat("panel_led_red", "metal", (0.90, 0.22, 0.22))
    knob = mat("panel_knob", "metal", (0.62, 0.63, 0.67))
    w, h, d, z = 0.36, 0.46, 0.07, 1.30
    y = WALL_Y - d / 2
    box(parts, "panel_body", (0, y, z), (w, d, h), housing)
    box(parts, "panel_face", (0, y - d / 2 - 0.004, z), (w - 0.04, 0.008, h - 0.04), face)
    fy = y - d / 2 - 0.010
    box(parts, "screen_bezel", (0, fy, z + 0.10), (0.26, 0.008, 0.16), screen_bg)
    box(parts, "screen", (0, fy - 0.004, z + 0.10), (0.23, 0.006, 0.13), screen)
    for i, m in enumerate((purple, lilac, red)):
        disc(parts, f"led_{i}", (-0.09 + i * 0.07, fy - 0.004, z - 0.03), 0.018, 0.012, m, verts=16)
    disc(parts, "dial", (0.10, fy - 0.010, z - 0.13), 0.035, 0.03, knob)
    box(parts, "label", (-0.05, fy - 0.002, z - 0.13), (0.12, 0.006, 0.025), knob)
    # A short cable gland on top so it reads as wired in.
    disc(parts, "gland", (0.12, y, z + h / 2 + 0.02), 0.02, 0.04, housing, axis="Z", verts=12)
    return parts


def build_fan(accent_rgb):
    parts = []
    housing = mat("fan_housing", "metal", (0.20, 0.21, 0.25))
    accent = mat(f"fan_accent_{accent_rgb}", "metal", accent_rgb)
    guard = mat("fan_guard", "metal", (0.62, 0.63, 0.68))
    blade = mat("fan_blade", "metal", (0.70, 0.71, 0.75))
    dark = mat("fan_dark", "metal", (0.05, 0.05, 0.07))
    s, d, z = 0.46, 0.14, WALL_Z   # up with the wall heater, dehumidifier and humidifier
    y = WALL_Y - d / 2
    box(parts, "fan_box", (0, y, z), (s, d, s), housing)
    box(parts, "fan_trim", (0, y - d / 2 - 0.004, z), (s - 0.02, 0.008, s - 0.02), accent)
    disc(parts, "fan_hole", (0, y - d / 2 - 0.006, z), 0.19, 0.012, dark)
    fy = y - d / 2 - 0.02
    for k in range(4):
        a = math.radians(20 + 90 * k)
        cx, cz = math.cos(a) * 0.09, math.sin(a) * 0.09
        box(parts, f"blade_{k}", (cx, fy + 0.006, z + cz), (0.15, 0.010, 0.065), blade, rot=(0, -a + math.radians(-12), 0))
    disc(parts, "hub", (0, fy - 0.004, z), 0.035, 0.03, accent)
    for k, r in enumerate((0.07, 0.13, 0.19)):
        ring(parts, f"guard_{k}", (0, fy - 0.022, z), r, 0.006, guard)
    box(parts, "guard_bar_v", (0, fy - 0.022, z), (0.012, 0.010, 0.38), guard)
    box(parts, "guard_bar_h", (0, fy - 0.022, z), (0.38, 0.010, 0.012), guard)
    return parts


def build_curtain(width, height, bottom):
    parts = []
    cloth = mat("curtain_cloth", "fabric", (0.15, 0.11, 0.24))
    fold = mat("curtain_fold", "fabric", (0.22, 0.17, 0.33))
    rod = mat("curtain_rod", "metal", (0.48, 0.45, 0.52))
    y = WALL_Y - 0.06
    folds = max(4, int(width / 0.09))
    pitch = width / folds
    for k in range(folds):
        x = -width / 2 + pitch * (k + 0.5)
        depth = 0.018 if k % 2 == 0 else 0.0
        box(parts, f"fold_{k}", (x, y - depth, bottom + height / 2), (pitch * 1.02, 0.02, height), fold if k % 2 == 0 else cloth)
    disc(parts, "rod", (0, y + 0.01, bottom + height + 0.03), 0.015, width + 0.12, rod, axis="Z", verts=10)
    parts[-1].rotation_euler = (0, math.pi / 2, 0)
    return parts


def build_heater():
    parts = []
    body = mat("heater_body", "metal", (0.55, 0.16, 0.12))
    dark = mat("heater_dark", "metal", (0.10, 0.08, 0.08))
    glow = mat("heater_glow", "metal", (1.00, 0.55, 0.12))
    knob = mat("heater_knob", "metal", (0.80, 0.80, 0.82))
    w, d, h = 0.50, 0.28, 0.46
    box(parts, "heater_body", (0, 0, 0.05 + h / 2), (w, d, h), body)
    box(parts, "grille_back", (-0.05, -d / 2 - 0.004, 0.05 + h / 2), (0.32, 0.008, 0.34), dark)
    for k in range(5):
        box(parts, f"coil_{k}", (-0.05, -d / 2 - 0.010, 0.13 + k * 0.065), (0.29, 0.012, 0.025), glow)
    disc(parts, "knob", (0.18, -d / 2 - 0.012, 0.40), 0.035, 0.025, knob)
    disc(parts, "switch", (0.18, -d / 2 - 0.010, 0.27), 0.022, 0.02, dark)
    for sx in (-1, 1):
        box(parts, f"foot_{sx}", (sx * 0.18, 0, 0.025), (0.06, d + 0.06, 0.05), dark)
    box(parts, "handle", (0, 0, 0.05 + h + 0.025), (0.22, 0.05, 0.03), dark)
    return parts


def build_dehumidifier():
    parts = []
    body = mat("dehum_body", "metal", (0.82, 0.83, 0.86))
    vent = mat("dehum_vent", "metal", (0.40, 0.42, 0.47))
    tank = mat("dehum_tank", "metal", (0.28, 0.58, 0.86))
    led = mat("dehum_led", "metal", (0.25, 0.85, 0.45))
    dark = mat("dehum_dark", "metal", (0.12, 0.12, 0.14))
    w, d, h = 0.42, 0.32, 0.66
    box(parts, "dehum_body", (0, 0, 0.03 + h / 2), (w, d, h), body)
    for k in range(6):
        box(parts, f"vent_{k}", (0, -d / 2 - 0.004, 0.42 + k * 0.035), (0.32, 0.008, 0.014), vent)
    box(parts, "tank", (0, -d / 2 - 0.006, 0.20), (0.30, 0.012, 0.22), tank)
    box(parts, "top_grille", (0, 0, 0.03 + h + 0.004), (0.34, 0.24, 0.008), vent)
    disc(parts, "led", (0.15, -d / 2 - 0.006, 0.36), 0.014, 0.012, led, verts=12)
    for sx in (-1, 1):
        for sy in (-1, 1):
            disc(parts, f"wheel_{sx}_{sy}", (sx * 0.16, sy * 0.11, 0.025), 0.025, 0.03, dark, axis="Z", verts=12)
    return parts


def build_humidifier():
    parts = []
    base = mat("hum_base", "metal", (0.24, 0.36, 0.46))
    tank = mat("hum_tank", "metal", (0.55, 0.78, 0.92))
    dark = mat("hum_dark", "metal", (0.14, 0.16, 0.20))
    mist = mat("hum_mist", "fabric", (0.90, 0.95, 1.00))
    box(parts, "hum_base", (0, 0, 0.08), (0.38, 0.38, 0.16), base)
    box(parts, "hum_tank", (0, 0.02, 0.16 + 0.15), (0.32, 0.30, 0.30), tank)
    box(parts, "hum_panel", (0, -0.19 - 0.004, 0.08), (0.26, 0.008, 0.10), dark)
    disc(parts, "nozzle", (0, 0.0, 0.46 + 0.04), 0.05, 0.08, dark, axis="Z", verts=16)
    disc(parts, "nozzle_cap", (0, 0.0, 0.55), 0.035, 0.02, mist, axis="Z", verts=16)
    box(parts, "water_line", (0, -0.13, 0.30), (0.30, 0.008, 0.02), dark)
    return parts


# Wall-mounted climate units hang up high on the north wall like an overhead cupboard; the rig turns them for each facing.
WALL_Z = 1.78                 # centre height of a high wall unit


def build_wall_heater():
    parts = []
    body = mat("wheater_body", "metal", (0.55, 0.16, 0.12))
    dark = mat("wheater_dark", "metal", (0.10, 0.08, 0.08))
    glow = mat("wheater_glow", "metal", (1.00, 0.55, 0.12))
    knob = mat("wheater_knob", "metal", (0.80, 0.80, 0.82))
    w, h, d = 0.52, 0.30, 0.14
    y = WALL_Y - d / 2
    box(parts, "wheater_body", (0, y, WALL_Z), (w, d, h), body)
    box(parts, "wheater_bracket", (0, WALL_Y - 0.01, WALL_Z), (w - 0.10, 0.02, h + 0.06), dark)
    fy = y - d / 2
    box(parts, "wheater_grille", (-0.06, fy - 0.004, WALL_Z - 0.01), (0.34, 0.008, 0.20), dark)
    for k in range(4):
        box(parts, f"wheater_coil_{k}", (-0.06, fy - 0.010, WALL_Z - 0.075 + k * 0.045), (0.31, 0.010, 0.018), glow)
    disc(parts, "wheater_knob", (0.19, fy - 0.012, WALL_Z + 0.05), 0.03, 0.022, knob)
    disc(parts, "wheater_switch", (0.19, fy - 0.010, WALL_Z - 0.06), 0.018, 0.02, dark)
    # A tilt-down louvre along the bottom so it reads as blowing warm air into the room.
    box(parts, "wheater_louvre", (0, fy - 0.02, WALL_Z - h / 2 + 0.01), (w - 0.06, 0.05, 0.02), dark, rot=(math.radians(-25), 0, 0))
    return parts


def build_wall_dehumidifier():
    parts = []
    body = mat("wdehum_body", "metal", (0.82, 0.83, 0.86))
    vent = mat("wdehum_vent", "metal", (0.40, 0.42, 0.47))
    tank = mat("wdehum_tank", "metal", (0.28, 0.58, 0.86))
    led = mat("wdehum_led", "metal", (0.25, 0.85, 0.45))
    dark = mat("wdehum_dark", "metal", (0.12, 0.12, 0.14))
    w, h, d = 0.50, 0.36, 0.18
    y = WALL_Y - d / 2
    box(parts, "wdehum_body", (0, y, WALL_Z), (w, d, h), body)
    fy = y - d / 2
    for k in range(5):
        box(parts, f"wdehum_vent_{k}", (0, fy - 0.004, WALL_Z + 0.04 + k * 0.026), (0.40, 0.008, 0.012), vent)
    box(parts, "wdehum_tank", (-0.08, fy - 0.006, WALL_Z - 0.09), (0.24, 0.012, 0.11), tank)
    disc(parts, "wdehum_led", (0.17, fy - 0.006, WALL_Z - 0.09), 0.014, 0.012, led, verts=12)
    # The drain hose drops from the underside toward the floor.
    disc(parts, "wdehum_hose", (0.20, y, WALL_Z - h / 2 - 0.22), 0.012, 0.44, dark, axis="Z", verts=10)
    return parts


def build_wall_humidifier():
    parts = []
    base = mat("whum_base", "metal", (0.24, 0.36, 0.46))
    tank = mat("whum_tank", "metal", (0.55, 0.78, 0.92))
    dark = mat("whum_dark", "metal", (0.14, 0.16, 0.20))
    mist = mat("whum_mist", "fabric", (0.90, 0.95, 1.00))
    w, h, d = 0.42, 0.30, 0.16
    y = WALL_Y - d / 2
    box(parts, "whum_body", (0, y, WALL_Z), (w, d, h), base)
    fy = y - d / 2
    box(parts, "whum_tank", (0, fy - 0.008, WALL_Z + 0.02), (0.30, 0.016, 0.16), tank)
    box(parts, "whum_panel", (0, fy - 0.004, WALL_Z - 0.10), (0.24, 0.008, 0.05), dark)
    # Two mist nozzles on top, angled out into the room.
    for sx in (-1, 1):
        disc(parts, f"whum_nozzle_{sx}", (sx * 0.10, y - 0.03, WALL_Z + h / 2 + 0.03), 0.03, 0.06, dark, axis="Z", verts=14)
        disc(parts, f"whum_mist_{sx}", (sx * 0.10, y - 0.05, WALL_Z + h / 2 + 0.075), 0.022, 0.02, mist, axis="Z", verts=14)
    return parts


SETS = [
    # name, facings, builder
    ("panel", "4", build_panel),
    ("curtain_door", "2", lambda: build_curtain(0.78, 2.05, 0.0)),
    ("curtain_window", "2", lambda: build_curtain(0.62, 0.78, 0.95)),
    ("exhaust", "4", lambda: build_fan((0.87, 0.50, 0.14))),
    ("intake", "4", lambda: build_fan((0.22, 0.58, 0.87))),
    ("heater", "1", build_heater),
    ("dehumidifier", "1", build_dehumidifier),
    ("humidifier", "1", build_humidifier),
    ("wall_heater", "4", build_wall_heater),
    ("wall_dehumidifier", "4", build_wall_dehumidifier),
    ("wall_humidifier", "4", build_wall_humidifier),
]


ICONS = [
    # icon file, builder: inventory icons, framed tight on the model
    ("GrowRoomPanel", build_panel),
    ("BlackoutCurtain", lambda: build_curtain(0.62, 0.78, 0.95)),
    ("ExhaustFan", lambda: build_fan((0.87, 0.50, 0.14))),
    ("IntakeFan", lambda: build_fan((0.22, 0.58, 0.87))),
    ("Heater", build_heater),
    ("Dehumidifier", build_dehumidifier),
    ("Humidifier", build_humidifier),
    ("WallHeater", build_wall_heater),
    ("WallDehumidifier", build_wall_dehumidifier),
    ("WallHumidifier", build_wall_humidifier),
]


def render_icons(only):
    """Render each model to a 256x256 transparent icon with the rig's camera angle and light, framed to its bounds."""
    from mathutils import Vector
    scene = bpy.context.scene
    subject = bpy.data.objects[F.SUBJECT_NAME]
    cam = bpy.data.objects[F.CAMERA_NAME]
    out = OUT / "icons"
    out.mkdir(parents=True, exist_ok=True)
    for name, builder in ICONS:
        if only and name not in only:
            continue
        clear_parts(subject)
        parts = builder()
        for part in parts:
            part.parent = subject
        F.apply_render_settings(bpy.context)
        scene.render.resolution_x = scene.render.resolution_y = 256
        bpy.context.view_layer.update()
        pts = [p.matrix_world @ v.co for p in parts for v in p.data.vertices]
        lo = Vector((min(q.x for q in pts), min(q.y for q in pts), min(q.z for q in pts)))
        hi = Vector((max(q.x for q in pts), max(q.y for q in pts), max(q.z for q in pts)))
        cam.location = (lo + hi) / 2 + F.camera_direction() * 100.0
        bpy.context.view_layer.update()
        inv = cam.matrix_world.inverted()
        local = [inv @ q for q in pts]
        xs, ys = [q.x for q in local], [q.y for q in local]
        span = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.1
        cam.data.ortho_scale = span
        cam.data.shift_x = (max(xs) + min(xs)) / 2 / span
        cam.data.shift_y = (max(ys) + min(ys)) / 2 / span
        scene.camera = cam
        scene.render.filepath = str(out / ("Item_" + name + ".png"))
        bpy.ops.render.render(write_still=True)
        print(f"[DD] icon {name}")
    cam.data.ortho_scale = F.ortho_scale()
    cam.data.shift_x = cam.data.shift_y = 0.0


def clear_parts(subject):
    for obj in list(subject.children_recursive):
        bpy.data.objects.remove(obj, do_unlink=True)


def main():
    only = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else []
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    F.register()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    props = scene.pz_forge
    props.footprint_x = props.footprint_y = 1
    props.show_guide = False
    props.contrast_boost = 1.0
    props.toon_shading = True
    F.build_rig(bpy.context)
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    subject = bpy.data.objects[F.SUBJECT_NAME]
    if "icons" in only:
        render_icons([a for a in only if a != "icons"])
        (OUT / "DONE.txt").write_text("ok")
        print("[DD] all done")
        return
    for name, facings, builder in SETS:
        if only and name not in only:
            continue
        clear_parts(subject)
        for part in builder():
            part.parent = subject
        out = OUT / name
        if out.exists():
            shutil.rmtree(out)
        props.sheet_name = "dd_" + name
        props.output_dir = str(out)
        props.facings = facings
        manifest = F.render_cells(bpy.context)
        print(f"[DD] rendered {len(manifest['cells'])} cell(s) of {name}")
    (OUT / "DONE.txt").write_text("ok")
    print("[DD] all done")


if __name__ == "__main__":
    main()
