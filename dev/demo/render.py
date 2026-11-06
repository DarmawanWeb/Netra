"""Synthetic captures for the substation demo: radiometric-looking thermal images (ironbow), the
matching visual images and acoustic images, with the regions the inspection points measure."""
import io

import numpy as np
from PIL import Image, ImageFilter

W, H = 640, 480
YY, XX = np.mgrid[0:H, 0:W] / np.array([H, W]).reshape(2, 1, 1)
STOPS = np.array([[0.0, 11, 2, 33], [0.18, 59, 15, 112], [0.36, 140, 41, 129], [0.54, 222, 73, 104],
                  [0.72, 254, 159, 109], [0.88, 251, 224, 138], [1.0, 255, 251, 230]])

PHASES = {'r': 0.24, 's': 0.5, 't': 0.76}
CLAMP_ROI = {k: {'x': round(x - 0.07, 3), 'y': 0.33, 'w': 0.14, 'h': 0.16} for k, x in PHASES.items()}
BUSHING_X = {'r': 0.28, 's': 0.5, 't': 0.72}
BUSHING_ROI = {k: {'x': round(x - 0.06, 3), 'y': 0.1, 'w': 0.12, 'h': 0.15} for k, x in BUSHING_X.items()}
TANK_ROI = {'x': 0.2, 'y': 0.64, 'w': 0.6, 'h': 0.28}


def ironbow(v):
    v = np.clip(v, 0, 1)
    out = np.empty(v.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(v, STOPS[:, 0], STOPS[:, c + 1])
    return out.astype(np.uint8)


def blob(cx, cy, rx, ry):
    return np.exp(-(((XX - cx) / rx) ** 2 + ((YY - cy) / ry) ** 2))


def rect(x0, y0, x1, y1):
    return ((XX >= x0) & (XX <= x1) & (YY >= y0) & (YY <= y1)).astype(float)


def jpeg(arr, blur=0.8):
    img = Image.fromarray(arr).filter(ImageFilter.GaussianBlur(blur))
    buf = io.BytesIO()
    img.save(buf, 'JPEG', quality=86)
    return buf.getvalue()


def to_thermal(field, rng, ambient):
    """Ironbow over a span from below ambient to the hottest spot (at least 22 °C), like a camera's auto range."""
    field = field + rng.normal(0, 0.18, field.shape)
    lo, hi = ambient - 6, max(field.max(), ambient + 22)
    return jpeg(ironbow((field - lo) / max(hi - lo, 1e-3)))


def clamps(temps, ambient, seed=0):
    """A disconnector or breaker seen from the side: gantry, three phases with their clamps on insulators."""
    rng = np.random.default_rng(seed)
    f = ambient - 7 + 3 * YY
    f = np.where(rect(0.04, 0.12, 0.96, 0.16) > 0, ambient + 1.5, f)
    vis = np.zeros((H, W, 3))
    vis[:] = np.stack([150 + 50 * YY, 175 + 40 * YY, 205 + 25 * YY], -1)
    beam = rect(0.04, 0.12, 0.96, 0.16)
    vis[beam > 0] = (96, 100, 108)
    for k, x in PHASES.items():
        tc = temps[k]
        wire = rect(x - 0.005, 0.16, x + 0.005, 0.37)
        f = np.where(wire > 0, ambient + (tc - ambient) * 0.55, f)
        vis[wire > 0] = (52, 54, 60)
        ins = rect(x - 0.024, 0.47, x + 0.024, 0.88)
        sheds = rect(x - 0.04, 0.47, x + 0.04, 0.88) * (np.sin((YY - 0.47) * 160) > 0.4)
        body = np.maximum(ins, sheds)
        f = np.where(body > 0, ambient + 1.8 + 0.6 * blob(x, 0.5, 0.03, 0.06), f)
        vis[body > 0] = (126, 76, 52)
        f = np.maximum(f, ambient + (tc - ambient) * blob(x, 0.41, 0.045, 0.04))
        clamp = blob(x, 0.41, 0.04, 0.032) > 0.5
        vis[clamp] = (168, 170, 176)
    base = rect(0.0, 0.88, 1.0, 1.0)
    f = np.where(base > 0, ambient + 4, f)
    vis[base > 0] = (118, 120, 116)
    return to_thermal(f, rng, ambient), jpeg(vis.astype(np.uint8), 0.6)


def bushings(temps, tank, ambient, seed=0):
    """A transformer's top: three bushings with their terminals over the tank."""
    rng = np.random.default_rng(seed)
    f = ambient - 6 + 3 * YY
    vis = np.zeros((H, W, 3))
    vis[:] = np.stack([155 + 50 * YY, 180 + 35 * YY, 210 + 20 * YY], -1)
    tankm = rect(0.08, 0.58, 0.92, 1.0)
    f = np.where(tankm > 0, tank - 4 + 6 * (1 - (YY - 0.58) / 0.42), f)
    vis[tankm > 0] = (92, 104, 96)
    for k, x in BUSHING_X.items():
        cone = (np.abs(XX - x) < 0.018 + 0.03 * (YY - 0.22) / 0.36) & (YY > 0.22) & (YY < 0.58)
        sheds = cone & (np.sin((YY - 0.22) * 150) > 0.5)
        f = np.where(cone, ambient + 3 + (tank - ambient) * 0.25 * (YY - 0.22) / 0.36, f)
        vis[cone] = (120, 74, 54)
        vis[sheds] = (100, 60, 44)
        f = np.maximum(f, ambient + (temps[k] - ambient) * blob(x, 0.18, 0.04, 0.05))
        term = rect(x - 0.025, 0.12, x + 0.025, 0.22)
        vis[term > 0] = (170, 172, 178)
    return to_thermal(f, rng, ambient), jpeg(vis.astype(np.uint8), 0.6)


def acoustic(db, detected, seed=0):
    """The visual image of the bushings in grey with the acoustic camera's map of the discharge."""
    _, vis = bushings({'r': 30, 's': 30, 't': 30}, 40, 30, seed)
    base = np.asarray(Image.open(io.BytesIO(vis)).convert('L').convert('RGB')).astype(float) * 0.8
    if detected:
        a = blob(0.28, 0.17, 0.06, 0.07) * min(1, max(0.25, db / 25))
        heat = np.stack([255 * np.clip(a * 2, 0, 1), 255 * np.clip(a * 2 - 0.6, 0, 1), 40 * a], -1)
        alpha = np.clip(a * 1.4, 0, 0.85)[..., None]
        base = base * (1 - alpha) + heat * alpha
    return jpeg(base.astype(np.uint8), 0.5)
