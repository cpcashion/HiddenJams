"""
Procedural 🤘 (sign of the horns) hand, modelled as a signed distance field.

Coordinate frame (model space):
    +y up, +x to the viewer's right, +z toward the viewer.
    Right hand, palm facing the viewer, so the thumb sits on the viewer's right.

Why an SDF: it gives per-part control over blending. Each finger is smoothly
blended into the palm (soft webbing, fleshy thenar pad) but fingers are joined
to each other with a hard union, so neighbouring fingers stay distinct instead
of melting into a mitten. Contact between the thumb and the folded fingers is
also a hard union, which reads as the thumb pressing on them.

Writes: out/hand.npz (verts, faces) and out/nails.npz (verts, faces).
"""

import sys
import time
import numpy as np
from skimage.measure import marching_cubes

OUT = sys.argv[1]

# ---------------------------------------------------------------- primitives

def smin(a, b, k):
    """Polynomial smooth minimum (iq). k = blend width."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def round_cone(px, py, pz, a, b, r1, r2):
    """Capsule with different end radii between points a and b (iq)."""
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    ba = b - a
    l2 = float(ba @ ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2

    pax, pay, paz = px - a[0], py - a[1], pz - a[2]
    y = pax * ba[0] + pay * ba[1] + paz * ba[2]
    z = y - l2
    qx = pax * l2 - ba[0] * y
    qy = pay * l2 - ba[1] * y
    qz = paz * l2 - ba[2] * y
    x2 = qx * qx + qy * qy + qz * qz
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2

    d_end = np.sqrt(x2 + z2) * il2 - r2
    d_start = np.sqrt(x2 + y2) * il2 - r1
    d_side = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - r1
    return np.where(np.sign(z) * a2 * z2 > k, d_end,
                    np.where(np.sign(y) * a2 * y2 < k, d_start, d_side))


def chain(px, py, pz, pts, radii, k=0.025):
    """Smoothly joined sequence of round cones through pts."""
    d = None
    for i in range(len(pts) - 1):
        seg = round_cone(px, py, pz, pts[i], pts[i + 1], radii[i], radii[i + 1])
        d = seg if d is None else smin(d, seg, k)
    return d


def round_box(px, py, pz, c, half, r):
    qx = np.abs(px - c[0]) - half[0] + r
    qy = np.abs(py - c[1]) - half[1] + r
    qz = np.abs(pz - c[2]) - half[2] + r
    outside = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2 + np.maximum(qz, 0) ** 2)
    inside = np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0.0)
    return outside + inside - r


def sphere(px, py, pz, c, r):
    return np.sqrt((px - c[0]) ** 2 + (py - c[1]) ** 2 + (pz - c[2]) ** 2) - r


# ---------------------------------------------------------------- anatomy

# Extended fingers: base (inside palm) -> mid joint -> tip centre.
INDEX_PTS = [(0.203, 0.20, 0.000), (0.224, 0.47, 0.004), (0.246, 0.705, 0.030)]
INDEX_R = [0.090, 0.083, 0.077]

PINKY_PTS = [(-0.203, 0.18, 0.000), (-0.232, 0.38, 0.004), (-0.258, 0.555, 0.028)]
PINKY_R = [0.080, 0.074, 0.068]

# Folded fingers: MCP (inside palm) -> PIP (forward, toward viewer)
#                 -> DIP (down) -> tip (tucked back toward the palm).
MIDDLE_PTS = [(0.074, 0.235, 0.000), (0.074, 0.300, 0.205), (0.070, 0.135, 0.232), (0.066, 0.070, 0.135)]
MIDDLE_R = [0.086, 0.082, 0.078, 0.072]

RING_PTS = [(-0.072, 0.225, 0.000), (-0.075, 0.282, 0.198), (-0.073, 0.122, 0.222), (-0.069, 0.060, 0.128)]
RING_R = [0.082, 0.079, 0.075, 0.069]

# Thumb: CMC (lower palm) -> MCP -> IP -> tip, crossing in front of the
# folded middle and ring fingers and pressing them down.
THUMB_PTS = [(0.190, -0.170, 0.000), (0.312, -0.030, 0.150), (0.190, 0.150, 0.318), (-0.040, 0.185, 0.338)]
THUMB_R = [0.106, 0.096, 0.090, 0.082]

PALM_C = (0.0, 0.0, 0.0)
PALM_HALF = (0.292, 0.300, 0.118)
PALM_ROUND = 0.110


def hand_sdf(px, py, pz):
    # Palm: rounded slab, slightly narrower toward the wrist, with a hint of
    # cupping so its edges curve toward the viewer.
    taper = 1.0 + 0.16 * (py - 0.30) / 0.60
    taper = np.clip(taper, 0.80, 1.0)
    cup = 0.18 * (px * px)
    palm = round_box(px / taper, py, pz - cup, PALM_C, PALM_HALF, PALM_ROUND) * np.minimum(taper, 1.0)

    # Wrist: flattened tapered capsule, bottom gently flattened so the hand
    # stands as a figurine rather than ending in a blob.
    wz = 0.74
    wrist = round_cone(px, py, pz / wz, (0.0, -0.20, -0.01), (0.0, -0.40, -0.02), 0.205, 0.192) * wz
    wrist = smax(wrist, -0.50 - py, 0.08)

    core = smin(palm, wrist, 0.11)

    # Back-of-hand knuckles: soft bumps so the reverse side reads as a fist.
    for x, r in ((0.205, 0.072), (0.074, 0.076), (-0.072, 0.072), (-0.205, 0.064)):
        core = smin(core, sphere(px, py, pz, (x, 0.255, -0.070), r), 0.09)

    index = chain(px, py, pz, INDEX_PTS, INDEX_R, k=0.045)
    pinky = chain(px, py, pz, PINKY_PTS, PINKY_R, k=0.045)
    middle = chain(px, py, pz, MIDDLE_PTS, MIDDLE_R, k=0.02)
    ring = chain(px, py, pz, RING_PTS, RING_R, k=0.02)

    thumb_base = chain(px, py, pz, THUMB_PTS[:2], THUMB_R[:2])
    thumb_tip = chain(px, py, pz, THUMB_PTS[1:], THUMB_R[1:], k=0.02)

    # Each part blends into the palm on its own; parts are then hard-unioned
    # so adjacent fingers keep a crisp gap.
    parts = [
        smin(core, index, 0.060),
        smin(core, pinky, 0.060),
        smin(core, middle, 0.050),
        smin(core, ring, 0.050),
        # Big blend on the thumb's base makes the fleshy thenar pad.
        smin(smin(core, thumb_base, 0.10), thumb_tip, 0.035),
    ]
    d = parts[0]
    for p in parts[1:]:
        d = np.minimum(d, p)
    return d


# ---------------------------------------------------------------- nails

def nail_sdf(px, py, pz, finger_pts, finger_r, dorsal_hint, length=0.118, width=0.048, finger_sd=None):
    """A nail plate that hugs the finger surface near its tip.

    Built as a thin shell offset from the finger's own SDF, intersected with a
    rounded box in the finger's local frame — so the nail follows the finger's
    curvature exactly instead of floating as a separate blob.
    """
    a = np.asarray(finger_pts[-2], np.float32)
    b = np.asarray(finger_pts[-1], np.float32)
    d = b - a
    d /= np.linalg.norm(d)
    w = np.asarray(dorsal_hint, np.float32)
    w = w - (w @ d) * d
    w /= np.linalg.norm(w)
    u = np.cross(d, w)

    r_tip = finger_r[-1]
    centre = b - d * (length * 0.5 - 0.006) + w * r_tip

    rx, ry, rz = px - centre[0], py - centre[1], pz - centre[2]
    lu = rx * u[0] + ry * u[1] + rz * u[2]
    lv = rx * d[0] + ry * d[1] + rz * d[2]
    lw = rx * w[0] + ry * w[1] + rz * w[2]
    region = round_box(lu, lv, lw, (0, 0, 0), (width, length * 0.5, 0.06), 0.032)

    shell = np.abs(finger_sd - 0.0045) - 0.0060
    return smax(shell, region, 0.006)


# ---------------------------------------------------------------- meshing

def grid(lo, hi, step):
    xs = np.arange(lo[0], hi[0], step, dtype=np.float32)
    ys = np.arange(lo[1], hi[1], step, dtype=np.float32)
    zs = np.arange(lo[2], hi[2], step, dtype=np.float32)
    px, py, pz = np.meshgrid(xs, ys, zs, indexing="ij")
    return px, py, pz, np.array([xs[0], ys[0], zs[0]], np.float32)


def mesh(sdf_values, origin, step):
    v, f, _, _ = marching_cubes(sdf_values, level=0.0, spacing=(step, step, step))
    return (v + origin).astype(np.float32), f.astype(np.int32)


t0 = time.time()
STEP = 0.0042
px, py, pz, origin = grid((-0.42, -0.70, -0.24), (0.52, 0.86, 0.47), STEP)
print(f"hand grid {px.shape} = {px.size/1e6:.1f}M samples")
hv, hf = mesh(hand_sdf(px, py, pz), origin, STEP)
print(f"hand: {len(hv):,} verts {len(hf):,} faces  ({time.time()-t0:.1f}s)")
del px, py, pz
np.savez_compressed(f"{OUT}/hand.npz", verts=hv, faces=hf)

# Nails: index + pinky (back of hand) and the thumb (faces the viewer).
NAIL_STEP = 0.0016
nail_specs = [
    ("index", INDEX_PTS, INDEX_R, (0, 0, -1), 0.118, 0.048),
    ("pinky", PINKY_PTS, PINKY_R, (0, 0, -1), 0.104, 0.042),
    ("thumb", THUMB_PTS, THUMB_R, (0, 0.35, 1), 0.112, 0.050),
]
all_v, all_f, offset = [], [], 0
for name, pts, radii, dorsal, length, width in nail_specs:
    tip = np.asarray(pts[-1])
    lo = tip - 0.16
    hi = tip + 0.16
    px, py, pz, origin = grid(lo, hi, NAIL_STEP)
    finger_sd = chain(px, py, pz, pts[-2:], radii[-2:])
    nsd = nail_sdf(px, py, pz, pts, radii, dorsal, length, width, finger_sd)
    v, f = mesh(nsd, origin, NAIL_STEP)
    print(f"nail {name}: {len(v):,} verts")
    all_v.append(v)
    all_f.append(f + offset)
    offset += len(v)
np.savez_compressed(f"{OUT}/nails.npz", verts=np.concatenate(all_v), faces=np.concatenate(all_f))
print(f"done in {time.time()-t0:.1f}s")
