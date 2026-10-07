# Build 42 tile depth: the game's own camera (TileGeometryUtils) so a modded tile can ship a DEPTH_<tileset>.png.
# Scene units: a square spans -0.5..0.5 on x (east) and z (south), y is up, and one floor is 2.4495 high.
import math
import numpy as np

R2 = math.sqrt(2)
LEVEL = 2.4495


def _ortho(l, r, b, t, n, f):
    return np.array([[2 / (r - l), 0, 0, -(r + l) / (r - l)], [0, 2 / (t - b), 0, -(t + b) / (t - b)],
                     [0, 0, -2 / (f - n), -(f + n) / (f - n)], [0, 0, 0, 1]])


def _rot(ax, ay):
    cx, sx, cy, sy = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay)
    rx = np.array([[1, 0, 0, 0], [0, cx, -sx, 0], [0, sx, cx, 0], [0, 0, 0, 1]])
    ry = np.array([[cy, 0, sy, 0], [0, 1, 0, 0], [-sy, 0, cy, 0], [0, 0, 0, 1]])
    return rx @ ry


_T = np.eye(4)
_T[1, 3] = -2 * R2 * 0.375
M = _ortho(-R2 / 2, R2 / 2, -R2, R2, -2, 2) @ _T @ _rot(math.radians(30), math.radians(315))
MINV = np.linalg.inv(M)
_REF = abs((M @ np.array([-0.5, 0, -0.5, 1.0]))[2])


def normalized(p):
    """Normalized depth of a scene point, as the game stores it (0.5 at the near corner, 1.0 at the far one)."""
    return (M @ np.array([p[0], p[1], p[2], 1.0]))[2] * (0.25 / _REF) + 0.75


def ray(px, py, w=128, h=256):
    """The camera ray through a pixel of a 128x256 tile frame: origin and direction."""
    x, y = (px + 0.5) / w * 2 - 1, 1 - (py + 0.5) / h * 2
    a = MINV @ np.array([x, y, -1, 1.0])
    b = MINV @ np.array([x, y, 1, 1.0])
    return a[:3], b[:3] - a[:3]


def box_depth(px, py, lo, hi):
    """Depth where a pixel's ray first meets an axis-aligned box, or None if it misses."""
    o, d = ray(px, py)
    t0, t1 = -1e9, 1e9
    for i in range(3):
        if abs(d[i]) < 1e-12:
            if o[i] < lo[i] or o[i] > hi[i]:
                return None
            continue
        a, b = (lo[i] - o[i]) / d[i], (hi[i] - o[i]) / d[i]
        t0, t1 = max(t0, min(a, b)), min(t1, max(a, b))
    return None if t0 > t1 else normalized(o + d * t0)


def plane_depth(px, py, axis, value):
    """Depth where a pixel's ray meets the plane axis = value (0 for x, 2 for z)."""
    o, d = ray(px, py)
    return normalized(o + d * ((value - o[axis]) / d[axis]))
